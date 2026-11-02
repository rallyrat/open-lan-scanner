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

    public func load() throws -> [FavoriteDevice] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([FavoriteDevice].self, from: data)
    }

    public func save(_ favorites: [FavoriteDevice]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(favorites)
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
