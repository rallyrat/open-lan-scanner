import Foundation

/// IPv4 address with numeric ordering suitable for table sorting.
public struct IPv4Address: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public init?(string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard let octet = UInt32(part), octet <= 255 else { return nil }
            value = (value << 8) | octet
        }
        self.rawValue = value
    }

    public var description: String {
        let a = (rawValue >> 24) & 0xFF
        let b = (rawValue >> 16) & 0xFF
        let c = (rawValue >> 8) & 0xFF
        let d = rawValue & 0xFF
        return "\(a).\(b).\(c).\(d)"
    }

    public var dotted: String { description }

    public static func < (lhs: IPv4Address, rhs: IPv4Address) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public func advanced(by distance: Int) -> IPv4Address? {
        let next = Int64(rawValue) + Int64(distance)
        guard next >= 0, next <= Int64(UInt32.max) else { return nil }
        return IPv4Address(rawValue: UInt32(next))
    }
}
