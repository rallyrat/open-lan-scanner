import Foundation
import SystemConfiguration

public protocol InterfaceEnumerating: Sendable {
    func usableIPv4Interfaces() -> [NetworkInterfaceInfo]
}

public struct SystemInterfaceEnumerator: InterfaceEnumerating {
    public init() {}

    public func usableIPv4Interfaces() -> [NetworkInterfaceInfo] {
        var interfaces: [NetworkInterfaceInfo] = []
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return [] }
        defer { freeifaddrs(first) }

        let vpnPrefixes = ["utun", "ipsec", "ppp", "wg", "tun", "tap"]

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ptr = cursor {
            defer { cursor = ptr.pointee.ifa_next }
            let iface = ptr.pointee
            guard let addr = iface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            let name = String(cString: iface.ifa_name)
            let flags = Int32(iface.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            let sin = UnsafeRawPointer(addr).assumingMemoryBound(to: sockaddr_in.self).pointee
            let ipValue = UInt32(bigEndian: sin.sin_addr.s_addr)
            let ip = IPv4Address(rawValue: ipValue)

            var prefix = 32
            if let netmask = iface.ifa_netmask {
                let maskSin = UnsafeRawPointer(netmask).assumingMemoryBound(to: sockaddr_in.self).pointee
                let mask = UInt32(bigEndian: maskSin.sin_addr.s_addr)
                prefix = Self.prefixLength(from: mask)
            }

            let isLikelyVPN = vpnPrefixes.contains { name.hasPrefix($0) }
            let display = Self.friendlyName(for: name) ?? name

            interfaces.append(
                NetworkInterfaceInfo(
                    name: name,
                    displayName: display,
                    ipv4: ip,
                    prefixLength: prefix,
                    isUp: isUp,
                    isLoopback: isLoopback,
                    isLikelyVPN: isLikelyVPN
                )
            )
        }

        return interfaces
            .filter { !$0.isLoopback }
            .sorted { lhs, rhs in
                if lhs.isUp != rhs.isUp { return lhs.isUp && !rhs.isUp }
                if lhs.isLikelyVPN != rhs.isLikelyVPN { return !lhs.isLikelyVPN && rhs.isLikelyVPN }
                return lhs.name < rhs.name
            }
    }

    public func preferredInterface() -> NetworkInterfaceInfo? {
        let all = usableIPv4Interfaces()
        return all.first(where: { $0.isUp && !$0.isLikelyVPN }) ?? all.first(where: \.isUp) ?? all.first
    }

    private static func prefixLength(from mask: UInt32) -> Int {
        var bits = 0
        var value = mask
        while value & 0x8000_0000 != 0 {
            bits += 1
            value <<= 1
        }
        return bits
    }

    private static func friendlyName(for bsdName: String) -> String? {
        // Best-effort: use SCNetworkInterfaceCopyAll when available.
        guard let list = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return nil }
        for iface in list {
            if let bsd = SCNetworkInterfaceGetBSDName(iface) as String?, bsd == bsdName {
                return SCNetworkInterfaceGetLocalizedDisplayName(iface) as String? ?? bsdName
            }
        }
        return nil
    }
}
