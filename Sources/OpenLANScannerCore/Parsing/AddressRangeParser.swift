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
            let display = count == Int.max ? "more than \(limit)" : "\(count)"
            return "Range expands to \(display) addresses (limit \(limit)). Narrow the range."
        }
    }
}

public struct AddressRangeBounds: Sendable, Equatable {
    public var start: IPv4Address
    public var end: IPv4Address

    public init(start: IPv4Address, end: IPv4Address) {
        self.start = start
        self.end = end
    }

    /// Inclusive host count using overflow-safe arithmetic. Returns nil if the span cannot fit in Int.
    public var inclusiveCount: Int? {
        Self.inclusiveCount(from: start.rawValue, through: end.rawValue)
    }

    public static func inclusiveCount(from start: UInt32, through end: UInt32) -> Int? {
        guard start <= end else { return 0 }
        let diff = UInt64(end) &- UInt64(start)
        let total = diff &+ 1
        guard total <= UInt64(Int.max) else { return nil }
        return Int(total)
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
        let limit = max(1, absoluteLimit)

        let parts = trimmed
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Preflight: reject any single token whose bounds exceed the limit before allocating.
        var preflightTotal: UInt64 = 0
        var tokenBounds: [(AddressRangeBounds, Bool)] = [] // bounds, isCIDRUsableHosts
        for part in parts {
            let bounds = try boundsForToken(part)
            guard let count = bounds.inclusiveCount else {
                throw AddressParseError.tooManyAddresses(count: Int.max, limit: limit)
            }
            if count > limit {
                throw AddressParseError.tooManyAddresses(count: count, limit: limit)
            }
            preflightTotal += UInt64(count)
            if preflightTotal > UInt64(limit) {
                // Upper bound only — overlapping tokens may still fit after dedupe, but
                // we still refuse pathological inputs that clearly exceed the cap.
                // For overlapping ranges we refine during materialization with early exit.
                if parts.count == 1 {
                    throw AddressParseError.tooManyAddresses(count: count, limit: limit)
                }
            }
            tokenBounds.append((bounds, part.contains("/")))
        }

        var seen = Set<UInt32>()
        var ordered: [IPv4Address] = []
        ordered.reserveCapacity(min(limit, Int(min(preflightTotal, UInt64(limit)))))

        for (index, part) in parts.enumerated() {
            let bounds = tokenBounds[index].0
            // For CIDR, skip network/broadcast except /31 and /32.
            let expandBounds: AddressRangeBounds
            if part.contains("/") {
                expandBounds = try usableBounds(forCIDRToken: part)
                if let count = expandBounds.inclusiveCount, count > limit {
                    throw AddressParseError.tooManyAddresses(count: count, limit: limit)
                }
            } else {
                expandBounds = bounds
            }

            try appendStride(
                from: expandBounds.start.rawValue,
                through: expandBounds.end.rawValue,
                into: &ordered,
                seen: &seen,
                limit: limit
            )
        }

        return AddressRangeExpansion(addresses: ordered, expression: trimmed)
    }

    /// Inclusive bounds for a token without materializing addresses.
    public static func boundsForToken(_ token: String) throws -> AddressRangeBounds {
        if token.contains("/") {
            return try cidrBounds(token)
        }
        if token.contains("-") {
            return try dashBounds(token)
        }
        guard let address = IPv4Address(string: token) else {
            throw AddressParseError.invalidAddress(token)
        }
        return AddressRangeBounds(start: address, end: address)
    }

    public static func subnet(
        address: IPv4Address,
        prefixLength: Int
    ) throws -> (start: IPv4Address, end: IPv4Address) {
        let bounds = try subnetBounds(address: address, prefixLength: prefixLength)
        return (bounds.start, bounds.end)
    }

    public static func usableHosts(
        address: IPv4Address,
        prefixLength: Int,
        absoluteLimit: Int = absoluteMaxAddresses
    ) throws -> [IPv4Address] {
        let bounds = try usableSubnetBounds(address: address, prefixLength: prefixLength)
        guard let count = bounds.inclusiveCount else {
            throw AddressParseError.tooManyAddresses(count: Int.max, limit: absoluteLimit)
        }
        if count > absoluteLimit {
            throw AddressParseError.tooManyAddresses(count: count, limit: absoluteLimit)
        }
        var seen = Set<UInt32>()
        var ordered: [IPv4Address] = []
        ordered.reserveCapacity(count)
        try appendStride(
            from: bounds.start.rawValue,
            through: bounds.end.rawValue,
            into: &ordered,
            seen: &seen,
            limit: absoluteLimit
        )
        return ordered
    }

    public static func classCRange(containing address: IPv4Address) -> (start: IPv4Address, end: IPv4Address) {
        let base = address.rawValue & 0xFFFFFF00
        return (IPv4Address(rawValue: base), IPv4Address(rawValue: base | 0xFF))
    }

    public static func expression(from start: IPv4Address, to end: IPv4Address) -> String {
        if start == end { return start.dotted }
        return "\(start.dotted)-\(end.dotted)"
    }

    // MARK: - Bounds helpers

    private static func subnetBounds(address: IPv4Address, prefixLength: Int) throws -> AddressRangeBounds {
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
        return AddressRangeBounds(
            start: IPv4Address(rawValue: network),
            end: IPv4Address(rawValue: broadcast)
        )
    }

    private static func usableSubnetBounds(address: IPv4Address, prefixLength: Int) throws -> AddressRangeBounds {
        let bounds = try subnetBounds(address: address, prefixLength: prefixLength)
        if prefixLength >= 31 {
            return bounds
        }
        let start = IPv4Address(rawValue: bounds.start.rawValue &+ 1)
        let end = IPv4Address(rawValue: bounds.end.rawValue &- 1)
        guard start.rawValue <= end.rawValue else {
            // Empty usable set (should be rare); encode as inverted span so inclusiveCount == 0.
            return AddressRangeBounds(start: IPv4Address(rawValue: 1), end: IPv4Address(rawValue: 0))
        }
        return AddressRangeBounds(start: start, end: end)
    }

    private static func cidrBounds(_ token: String) throws -> AddressRangeBounds {
        let pieces = token.split(separator: "/", omittingEmptySubsequences: false)
        guard pieces.count == 2,
              let address = IPv4Address(string: String(pieces[0])),
              let prefix = Int(pieces[1]),
              (0...32).contains(prefix)
        else {
            throw AddressParseError.invalidCIDR(token)
        }
        // Preflight uses full subnet size (including network/broadcast) so /0 is rejected early.
        return try subnetBounds(address: address, prefixLength: prefix)
    }

    private static func usableBounds(forCIDRToken token: String) throws -> AddressRangeBounds {
        let pieces = token.split(separator: "/", omittingEmptySubsequences: false)
        guard pieces.count == 2,
              let address = IPv4Address(string: String(pieces[0])),
              let prefix = Int(pieces[1]),
              (0...32).contains(prefix)
        else {
            throw AddressParseError.invalidCIDR(token)
        }
        return try usableSubnetBounds(address: address, prefixLength: prefix)
    }

    private static func dashBounds(_ token: String) throws -> AddressRangeBounds {
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
        return AddressRangeBounds(start: start, end: end)
    }

    private static func appendStride(
        from start: UInt32,
        through end: UInt32,
        into ordered: inout [IPv4Address],
        seen: inout Set<UInt32>,
        limit: Int
    ) throws {
        guard start <= end else { return }
        var current = start
        while true {
            if seen.insert(current).inserted {
                if ordered.count >= limit {
                    throw AddressParseError.tooManyAddresses(count: ordered.count + 1, limit: limit)
                }
                ordered.append(IPv4Address(rawValue: current))
            }
            if current == end || current == UInt32.max { break }
            current &+= 1
        }
    }
}
