import Darwin
import Foundation
import os

public protocol NeighborLooking: Sendable {
    func macAddress(for ip: IPv4Address) -> String?
    func refresh() async
}

/// Reads the IPv4 neighbor (ARP) table via routing sysctl.
/// MAC addresses are only expected for directly connected L2 neighbors.
public final class SystemNeighborTable: NeighborLooking, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [UInt32: String]())

    public init() {}

    public func refresh() async {
        let snapshot = Self.readARPTable()
        lock.withLock { $0 = snapshot }
    }

    public func macAddress(for ip: IPv4Address) -> String? {
        lock.withLock { $0[ip.rawValue] }
    }

    private static func readARPTable() -> [UInt32: String] {
        var result: [UInt32: String] = [:]

        var neededLength = 0
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO]
        guard sysctl(&mib, u_int(mib.count), nil, &neededLength, nil, 0) == 0, neededLength > 0 else {
            return result
        }

        var buffer = [UInt8](repeating: 0, count: neededLength)
        let ok = buffer.withUnsafeMutableBufferPointer { ptr -> Bool in
            var len = neededLength
            return sysctl(&mib, u_int(mib.count), ptr.baseAddress, &len, nil, 0) == 0
        }
        guard ok else { return result }

        var offset = 0
        while offset + MemoryLayout<rt_msghdr>.size <= buffer.count {
            let msgLen: Int = buffer.withUnsafeBytes { raw in
                Int(raw.load(fromByteOffset: offset, as: rt_msghdr.self).rtm_msglen)
            }
            guard msgLen > 0 else { break }

            let addrs: Int32 = buffer.withUnsafeBytes { raw in
                raw.load(fromByteOffset: offset, as: rt_msghdr.self).rtm_addrs
            }

            var saOffset = offset + MemoryLayout<rt_msghdr>.stride
            var destinationIP: UInt32?
            var mac: String?

            for bit in 0..<RTAX_MAX {
                guard (addrs & (1 << bit)) != 0 else { continue }
                guard saOffset + 2 <= offset + msgLen else { break }

                let saLen = Int(buffer[saOffset])
                let saFamily = buffer[saOffset + 1]
                let stride = max(saLen, 4)

                if bit == Int(RTAX_DST), saFamily == UInt8(AF_INET), saOffset + MemoryLayout<sockaddr_in>.size <= buffer.count {
                    destinationIP = buffer.withUnsafeBytes { raw in
                        let sin = raw.load(fromByteOffset: saOffset, as: sockaddr_in.self)
                        return UInt32(bigEndian: sin.sin_addr.s_addr)
                    }
                } else if bit == Int(RTAX_GATEWAY), saFamily == UInt8(AF_LINK) {
                    if saOffset + 8 <= buffer.count {
                        let nlen = Int(buffer[saOffset + 5])
                        let alen = Int(buffer[saOffset + 6])
                        let dataStart = saOffset + 8 + nlen
                        if alen == 6, dataStart + 6 <= buffer.count {
                            let bytes = buffer[dataStart..<(dataStart + 6)]
                            let formatted = bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
                            if formatted != "00:00:00:00:00:00" {
                                mac = formatted
                            }
                        }
                    }
                }

                saOffset += stride
            }

            if let destinationIP, let mac {
                result[destinationIP] = mac
            }

            offset += msgLen
        }

        return result
    }
}

public struct StaticNeighborTable: NeighborLooking {
    public var mapping: [IPv4Address: String]

    public init(mapping: [IPv4Address: String] = [:]) {
        self.mapping = mapping
    }

    public func macAddress(for ip: IPv4Address) -> String? {
        mapping[ip]
    }

    public func refresh() async {}
}
