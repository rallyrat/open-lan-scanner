import Darwin
import Foundation

/// Pure parser for IPv4 ARP/neighbor entries from a `NET_RT_FLAGS`/`RTF_LLINFO` sysctl dump.
/// Accepts arbitrary bytes for deterministic fuzzing — never requires raw sockets.
public enum RoutingTableParser {
    public static let maxAcceptedBufferBytes = 4 * 1024 * 1024
    public static let headerSize = MemoryLayout<rt_msghdr>.size

    public struct NeighborEntry: Equatable, Sendable {
        public var ipRaw: UInt32
        public var mac: String
    }

    /// Parses neighbor IP→MAC pairs. Malformed input yields a partial or empty result; never traps.
    public static func parseARPEntries(from buffer: [UInt8]) -> [UInt32: String] {
        guard !buffer.isEmpty, buffer.count <= maxAcceptedBufferBytes else { return [:] }
        var result: [UInt32: String] = [:]
        var offset = 0
        var safety = 0
        let maxMessages = buffer.count + 1

        while offset < buffer.count, safety < maxMessages {
            safety += 1
            guard let header = loadUnaligned(rt_msghdr.self, from: buffer, at: offset) else { break }
            let msgLen = Int(header.rtm_msglen)
            guard msgLen >= headerSize else { break }
            guard msgLen <= buffer.count - offset else { break }

            let messageEnd = offset + msgLen
            let addrs = header.rtm_addrs
            var saOffset = offset + MemoryLayout<rt_msghdr>.stride
            // Align sockaddr region start within the message when stride > size.
            if saOffset > messageEnd { break }

            var destinationIP: UInt32?
            var mac: String?

            for bit in 0..<Int(RTAX_MAX) {
                guard (addrs & (1 << bit)) != 0 else { continue }
                guard saOffset + 2 <= messageEnd else { break }

                let saLen = Int(buffer[saOffset])
                let saFamily = buffer[saOffset + 1]
                // BSD sockaddr: zero length still advances by a short word to avoid stalls.
                let stride = max(saLen == 0 ? 4 : saLen, 4)
                guard saOffset + stride <= messageEnd else { break }

                if bit == Int(RTAX_DST), saFamily == UInt8(AF_INET) {
                    if saOffset + MemoryLayout<sockaddr_in>.size <= messageEnd,
                       let sin = loadUnaligned(sockaddr_in.self, from: buffer, at: saOffset) {
                        destinationIP = UInt32(bigEndian: sin.sin_addr.s_addr)
                    }
                } else if bit == Int(RTAX_GATEWAY), saFamily == UInt8(AF_LINK) {
                    if let parsed = parseLinkLayerMAC(buffer: buffer, saOffset: saOffset, messageEnd: messageEnd) {
                        mac = parsed
                    }
                }

                saOffset += stride
            }

            if let destinationIP, let mac {
                result[destinationIP] = mac
            }

            let next = offset + msgLen
            if next <= offset { break } // overflow / zero progress
            offset = next
        }

        return result
    }

    public static func parseARPEntries(from data: Data) -> [UInt32: String] {
        parseARPEntries(from: [UInt8](data))
    }

    // MARK: - Helpers

    public static func loadUnaligned<T>(_ type: T.Type, from buffer: [UInt8], at offset: Int) -> T? {
        let size = MemoryLayout<T>.size
        guard offset >= 0, size > 0, offset <= buffer.count, buffer.count - offset >= size else {
            return nil
        }
        return buffer.withUnsafeBytes { raw -> T? in
            guard let base = raw.baseAddress else { return nil }
            let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
            defer { value.deallocate() }
            memcpy(value, base.advanced(by: offset), size)
            return value.pointee
        }
    }

    private static func parseLinkLayerMAC(buffer: [UInt8], saOffset: Int, messageEnd: Int) -> String? {
        // sockaddr_dl layout (Darwin): len, family, index(2), type, nlen, alen, slen, data…
        guard saOffset + 8 <= messageEnd else { return nil }
        let nlen = Int(buffer[saOffset + 5])
        let alen = Int(buffer[saOffset + 6])
        guard nlen >= 0, alen >= 0 else { return nil }
        guard alen == 6 else { return nil }
        let dataStart = saOffset + 8 + nlen
        guard dataStart >= saOffset, dataStart + 6 <= messageEnd, dataStart + 6 <= buffer.count else {
            return nil
        }
        let bytes = buffer[dataStart..<(dataStart + 6)]
        let formatted = bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
        if formatted == "00:00:00:00:00:00" { return nil }
        return formatted
    }
}
