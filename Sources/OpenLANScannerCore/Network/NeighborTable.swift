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
        var neededLength = 0
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO]
        guard sysctl(&mib, u_int(mib.count), nil, &neededLength, nil, 0) == 0, neededLength > 0 else {
            return [:]
        }
        // Bound allocation from a hostile/unexpected kernel length.
        let capped = min(neededLength, RoutingTableParser.maxAcceptedBufferBytes)
        guard capped > 0 else { return [:] }

        var buffer = [UInt8](repeating: 0, count: capped)
        let ok = buffer.withUnsafeMutableBufferPointer { ptr -> Bool in
            var len = capped
            return sysctl(&mib, u_int(mib.count), ptr.baseAddress, &len, nil, 0) == 0
        }
        guard ok else { return [:] }
        return RoutingTableParser.parseARPEntries(from: buffer)
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
