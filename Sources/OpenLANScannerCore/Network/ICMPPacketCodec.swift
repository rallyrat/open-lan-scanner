import Foundation

/// Pure ICMP echo encode/decode helpers for tests and the system probe.
public enum ICMPPacketCodec {
    public static let echoRequestType: UInt8 = 8
    public static let echoReplyType: UInt8 = 0

    public struct EchoHeader: Equatable, Sendable {
        public var type: UInt8
        public var code: UInt8
        public var checksum: UInt16
        public var identifier: UInt16
        public var sequence: UInt16
    }

    public static func checksum(_ data: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var i = 0
        while i + 1 < data.count {
            sum += UInt32(data[i]) << 8 | UInt32(data[i + 1])
            i += 2
        }
        if i < data.count {
            sum += UInt32(data[i]) << 8
        }
        while sum >> 16 != 0 {
            sum = (sum & 0xFFFF) + (sum >> 16)
        }
        return ~UInt16(sum & 0xFFFF)
    }

    public static func buildEchoRequest(identifier: UInt16, sequence: UInt16, payload: [UInt8] = Array(repeating: 0, count: 8)) -> [UInt8] {
        var packet = [UInt8](repeating: 0, count: 8 + payload.count)
        packet[0] = echoRequestType
        packet[1] = 0
        packet[4] = UInt8((identifier >> 8) & 0xFF)
        packet[5] = UInt8(identifier & 0xFF)
        packet[6] = UInt8((sequence >> 8) & 0xFF)
        packet[7] = UInt8(sequence & 0xFF)
        for (idx, byte) in payload.enumerated() {
            packet[8 + idx] = byte
        }
        let sum = checksum(packet)
        packet[2] = UInt8((sum >> 8) & 0xFF)
        packet[3] = UInt8(sum & 0xFF)
        return packet
    }

    public static func parseHeader(from buffer: [UInt8], offset: Int = 0) -> EchoHeader? {
        guard offset >= 0, buffer.count - offset >= 8 else { return nil }
        let type = buffer[offset]
        let code = buffer[offset + 1]
        let csum = UInt16(buffer[offset + 2]) << 8 | UInt16(buffer[offset + 3])
        let ident = UInt16(buffer[offset + 4]) << 8 | UInt16(buffer[offset + 5])
        let seq = UInt16(buffer[offset + 6]) << 8 | UInt16(buffer[offset + 7])
        return EchoHeader(type: type, code: code, checksum: csum, identifier: ident, sequence: seq)
    }

    /// Validates an ICMP echo reply for our outstanding request.
    /// `buffer` may be a raw ICMP datagram (SOCK_DGRAM) or include an IPv4 header.
    public static func isMatchingEchoReply(
        _ buffer: [UInt8],
        expectedIdentifier: UInt16,
        expectedSequence: UInt16
    ) -> Bool {
        guard !buffer.isEmpty else { return false }
        for start in icmpPayloadOffsets(in: buffer) {
            guard let header = parseHeader(from: buffer, offset: start) else { continue }
            guard header.type == echoReplyType, header.code == 0 else { continue }
            guard header.identifier == expectedIdentifier, header.sequence == expectedSequence else {
                continue
            }
            let slice = Array(buffer[start...])
            guard slice.count >= 8 else { continue }
            // Classic ICMP: checksum of message with checksum field zeroed equals stored value,
            // or checksum of the on-wire message is 0.
            if checksum(zeroedChecksum(slice)) == header.checksum { return true }
            if checksum(slice) == 0 { return true }
        }
        return false
    }

    private static func zeroedChecksum(_ packet: [UInt8]) -> [UInt8] {
        var copy = packet
        if copy.count >= 4 {
            copy[2] = 0
            copy[3] = 0
        }
        return copy
    }

    private static func icmpPayloadOffsets(in buffer: [UInt8]) -> [Int] {
        var offsets = [0]
        // If this looks like an IPv4 header, also try after IHL.
        if buffer.count >= 20, (buffer[0] >> 4) == 4 {
            let ihl = Int(buffer[0] & 0x0F) * 4
            if ihl >= 20, ihl < buffer.count {
                offsets.append(ihl)
            }
        }
        return offsets
    }
}
