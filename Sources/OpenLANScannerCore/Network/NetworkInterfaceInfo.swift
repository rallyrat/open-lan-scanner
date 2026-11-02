import Foundation

public struct NetworkInterfaceInfo: Identifiable, Hashable, Sendable {
    public var id: String { "\(name)-\(ipv4.dotted)" }
    public var name: String
    public var displayName: String
    public var ipv4: IPv4Address
    public var prefixLength: Int
    public var isUp: Bool
    public var isLoopback: Bool
    public var isLikelyVPN: Bool

    public init(
        name: String,
        displayName: String,
        ipv4: IPv4Address,
        prefixLength: Int,
        isUp: Bool,
        isLoopback: Bool,
        isLikelyVPN: Bool
    ) {
        self.name = name
        self.displayName = displayName
        self.ipv4 = ipv4
        self.prefixLength = prefixLength
        self.isUp = isUp
        self.isLoopback = isLoopback
        self.isLikelyVPN = isLikelyVPN
    }

    public var subnetExpression: String {
        "\(ipv4.dotted)/\(prefixLength)"
    }

    public var suggestedScanExpression: String {
        guard let hosts = try? AddressRangeParser.usableHosts(address: ipv4, prefixLength: prefixLength),
              let first = hosts.first,
              let last = hosts.last
        else {
            return "\(ipv4.dotted)/\(prefixLength)"
        }
        return AddressRangeParser.expression(from: first, to: last)
    }

    public var menuLabel: String {
        var label = "\(displayName) — \(ipv4.dotted)/\(prefixLength)"
        if isLikelyVPN { label += " (VPN)" }
        if !isUp { label += " (down)" }
        return label
    }
}
