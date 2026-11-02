import Foundation

public struct FavoriteDevice: Identifiable, Hashable, Sendable, Codable {
    public var id: String { ip.dotted }
    public var ip: IPv4Address
    public var macAddress: String?
    public var customName: String
    public var notes: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        ip: IPv4Address,
        macAddress: String? = nil,
        customName: String = "",
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.ip = ip
        self.macAddress = macAddress
        self.customName = customName
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Validates MACs when present and deduplicates by IP (last write wins). Rejects empty imports that would crash unique-key dictionaries.
    public static func validateAndDeduplicate(_ items: [FavoriteDevice]) throws -> [FavoriteDevice] {
        var map: [UInt32: FavoriteDevice] = [:]
        for item in items {
            if let mac = item.macAddress, !mac.isEmpty {
                guard MACAddressParsing.parse(mac) != nil else {
                    throw FavoritesError.invalidMAC(mac)
                }
            }
            map[item.ip.rawValue] = item
        }
        return Array(map.values).sorted { $0.ip < $1.ip }
    }
}

public enum FavoritesError: LocalizedError {
    case invalidMAC(String)
    case malformedImport(String)

    public var errorDescription: String? {
        switch self {
        case .invalidMAC(let mac):
            return "Invalid MAC address in favorites import: \(mac)"
        case .malformedImport(let detail):
            return "Malformed favorites import: \(detail)"
        }
    }
}

public protocol FavoritesStoring: Sendable {
    func load() throws -> [FavoriteDevice]
    func save(_ favorites: [FavoriteDevice]) throws
}

public struct FileFavoritesStore: FavoritesStoring {
    public var fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func applicationSupportStore(
        fileManager: FileManager = .default
    ) throws -> FileFavoritesStore {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("OpenLANScanner", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return FileFavoritesStore(fileURL: dir.appendingPathComponent("favorites.json"))
    }

    public static let maxFileByteCount = 2 * 1024 * 1024

    public func load() throws -> [FavoriteDevice] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        if let size = attrs[.size] as? NSNumber, size.intValue > Self.maxFileByteCount {
            throw FavoritesError.malformedImport(
                "Favorites file exceeds \(Self.maxFileByteCount) bytes."
            )
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([FavoriteDevice].self, from: data)
        return try FavoriteDevice.validateAndDeduplicate(decoded)
    }

    public func save(_ favorites: [FavoriteDevice]) throws {
        let cleaned = try FavoriteDevice.validateAndDeduplicate(favorites)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(cleaned)
        try data.write(to: fileURL, options: [.atomic])
    }
}

public final class InMemoryFavoritesStore: FavoritesStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [FavoriteDevice]

    public init(items: [FavoriteDevice] = []) {
        self.items = items
    }

    public func load() throws -> [FavoriteDevice] {
        lock.lock(); defer { lock.unlock() }
        return items
    }

    public func save(_ favorites: [FavoriteDevice]) throws {
        lock.lock(); defer { lock.unlock() }
        items = favorites
    }
}
