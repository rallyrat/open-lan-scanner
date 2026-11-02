import Foundation

public enum AddressParseError: Error, Equatable, LocalizedError, Sendable {
    case empty
    case invalidAddress(String)
    case invalidCIDR(String)
    case invalidRange(String)
    case invertedRange(start: String, end: String)
    case tooManyAddresses(count: Int, limit: Int)

    public var errorDescription: String? {
        switch self {
        case .empty:
            return "Enter an IPv4 address, range, or CIDR."
        case .invalidAddress(let value):
            return "Invalid IPv4 address: \(value)"
        case .invalidCIDR(let value):
            return "Invalid CIDR notation: \(value)"
        case .invalidRange(let value):
            return "Invalid address range: \(value)"
        case .invertedRange(let start, let end):
            return "Range start \(start) is after end \(end)."
        case .tooManyAddresses(let count, let limit):
            return "Range expands to \(count) addresses (limit \(limit)). Narrow the range."
        }
    }
}

public struct AddressRangeExpansion: Sendable, Equatable {
    public var addresses: [IPv4Address]
    public var expression: String

    public var count: Int { addresses.count }

    public init(addresses: [IPv4Address], expression: String) {
        self.addresses = addresses
        self.expression = expression
    }
}

public enum AddressRangeParser {
    /// Hard safety cap to avoid accidental multi-million host expansions in memory.
    public static let absoluteMaxAddresses = 65_536

    public static func parse(
        _ expression: String,
        absoluteLimit: Int = absoluteMaxAddresses
    ) throws -> AddressRangeExpansion {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AddressParseError.empty }

        let parts = trimmed
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var seen = Set<UInt32>()
        var ordered: [IPv4Address] = []

        for part in parts {
            let chunk = try expandToken(part)
            for address in chunk {
                if seen.insert(address.rawValue).inserted {
                    ordered.append(address)
                    if ordered.count > absoluteLimit {
                        throw AddressParseError.tooManyAddresses(count: ordered.count, limit: absoluteLimit)
                    }
                }
            }
        }

        return AddressRangeExpansion(addresses: ordered, expression: trimmed)
    }

    public static func subnet(
        address: IPv4Address,
        prefixLength: Int
    ) throws -> (start: IPv4Address, end: IPv4Address) {
        guard (0...32).contains(prefixLength) else {
            throw AddressParseError.invalidCIDR("prefix \(prefixLength)")
        }
        let mask: UInt32
        if prefixLength == 0 {
            mask = 0
        } else {
            mask = UInt32.max << (32 - prefixLength)
        }
        let network = address.rawValue & mask
        let broadcast: UInt32
        if prefixLength == 32 {
            broadcast = network
        } else {
            broadcast = network | ~mask
        }
        return (IPv4Address(rawValue: network), IPv4Address(rawValue: broadcast))
    }

    public static func usableHosts(
        address: IPv4Address,
        prefixLength: Int
    ) throws -> [IPv4Address] {
        let bounds = try subnet(address: address, prefixLength: prefixLength)
        if prefixLength >= 31 {
            return strideAddresses(from: bounds.start, through: bounds.end)
        }
        // Skip network and broadcast for typical LAN scans.
        let start = IPv4Address(rawValue: bounds.start.rawValue &+ 1)
        let end = IPv4Address(rawValue: bounds.end.rawValue &- 1)
        guard start.rawValue <= end.rawValue else { return [] }
        return strideAddresses(from: start, through: end)
    }

    public static func classCRange(containing address: IPv4Address) -> (start: IPv4Address, end: IPv4Address) {
        let base = address.rawValue & 0xFFFFFF00
        return (IPv4Address(rawValue: base), IPv4Address(rawValue: base | 0xFF))
    }

    public static func expression(from start: IPv4Address, to end: IPv4Address) -> String {
        if start == end { return start.dotted }
        return "\(start.dotted)-\(end.dotted)"
    }

    // MARK: - Private

    private static func expandToken(_ token: String) throws -> [IPv4Address] {
        if token.contains("/") {
            return try expandCIDR(token)
        }
        if token.contains("-") {
            return try expandDashRange(token)
        }
        guard let address = IPv4Address(string: token) else {
            throw AddressParseError.invalidAddress(token)
        }
        return [address]
    }

    private static func expandCIDR(_ token: String) throws -> [IPv4Address] {
        let pieces = token.split(separator: "/", omittingEmptySubsequences: false)
        guard pieces.count == 2,
              let address = IPv4Address(string: String(pieces[0])),
              let prefix = Int(pieces[1]),
              (0...32).contains(prefix)
        else {
            throw AddressParseError.invalidCIDR(token)
        }
        return try usableHosts(address: address, prefixLength: prefix)
    }

    private static func expandDashRange(_ token: String) throws -> [IPv4Address] {
        // Support "192.168.1.1-192.168.1.50" and "192.168.1.1-50"
        let parts = token.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 else { throw AddressParseError.invalidRange(token) }

        guard let start = IPv4Address(string: parts[0]) else {
            throw AddressParseError.invalidAddress(parts[0])
        }

        let end: IPv4Address
        if let full = IPv4Address(string: parts[1]) {
            end = full
        } else if let lastOctet = UInt32(parts[1]), lastOctet <= 255 {
            let base = start.rawValue & 0xFFFFFF00
            end = IPv4Address(rawValue: base | lastOctet)
        } else {
            throw AddressParseError.invalidRange(token)
        }

        guard start.rawValue <= end.rawValue else {
            throw AddressParseError.invertedRange(start: start.dotted, end: end.dotted)
        }
        return strideAddresses(from: start, through: end)
    }

    private static func strideAddresses(from start: IPv4Address, through end: IPv4Address) -> [IPv4Address] {
        let count = Int(end.rawValue - start.rawValue) + 1
        var result: [IPv4Address] = []
        result.reserveCapacity(count)
        var current = start.rawValue
        while current <= end.rawValue {
            result.append(IPv4Address(rawValue: current))
            if current == UInt32.max { break }
            current &+= 1
        }
        return result
    }
}
