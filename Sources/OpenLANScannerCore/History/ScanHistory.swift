import Foundation
import os

public struct ScanHostSnapshot: Hashable, Sendable, Codable, Identifiable {
    public var id: String { ip.dotted }
    public var ip: IPv4Address
    public var status: HostReachability
    public var hostname: String?
    public var customName: String?
    public var macAddress: String?
    public var services: [DiscoveredService]
    public var evidenceKinds: [String]

    public init(from host: HostRecord) {
        self.ip = host.ip
        self.status = host.status
        self.hostname = host.hostname
        self.customName = host.customName
        self.macAddress = host.macAddress
        self.services = host.services
        self.evidenceKinds = host.evidence.map(\.kind.rawValue)
    }

    public init(
        ip: IPv4Address,
        status: HostReachability,
        hostname: String? = nil,
        customName: String? = nil,
        macAddress: String? = nil,
        services: [DiscoveredService] = [],
        evidenceKinds: [String] = []
    ) {
        self.ip = ip
        self.status = status
        self.hostname = hostname
        self.customName = customName
        self.macAddress = macAddress
        self.services = services
        self.evidenceKinds = evidenceKinds
    }
}

public struct ScanSnapshot: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var createdAt: Date
    public var targetExpression: String
    public var interfaceNote: String?
    public var onlineCount: Int
    public var probedCount: Int
    public var preferencesSummary: String
    public var hosts: [ScanHostSnapshot]

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        targetExpression: String,
        interfaceNote: String?,
        onlineCount: Int,
        probedCount: Int,
        preferencesSummary: String,
        hosts: [ScanHostSnapshot]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.targetExpression = targetExpression
        self.interfaceNote = interfaceNote
        self.onlineCount = onlineCount
        self.probedCount = probedCount
        self.preferencesSummary = preferencesSummary
        self.hosts = hosts
    }
}

public struct ServiceChange: Hashable, Sendable, Codable {
    public var ip: IPv4Address
    public var before: [DiscoveredService]
    public var after: [DiscoveredService]
}

public struct ScanComparison: Sendable, Equatable {
    public var newlyObserved: [ScanHostSnapshot]
    /// Seen online before; no live evidence in the newer snapshot. Not proof they left the network.
    public var previouslyObservedNoResponse: [ScanHostSnapshot]
    public var changedServices: [ServiceChange]
    public var uncertainMatches: [String]

    public init(
        newlyObserved: [ScanHostSnapshot] = [],
        previouslyObservedNoResponse: [ScanHostSnapshot] = [],
        changedServices: [ServiceChange] = [],
        uncertainMatches: [String] = []
    ) {
        self.newlyObserved = newlyObserved
        self.previouslyObservedNoResponse = previouslyObservedNoResponse
        self.changedServices = changedServices
        self.uncertainMatches = uncertainMatches
    }
}

public enum ScanHistory {
    public static func compare(older: ScanSnapshot, newer: ScanSnapshot) -> ScanComparison {
        var uncertain: [String] = []
        if older.targetExpression != newer.targetExpression {
            uncertain.append("Target expressions differ; IP overlap may identify different devices on different networks.")
        }
        if older.interfaceNote != newer.interfaceNote {
            uncertain.append("Interface/network context differs between snapshots.")
        }

        let olderOnline = Dictionary(uniqueKeysWithValues: older.hosts.filter { $0.status == .online }.map { ($0.ip.rawValue, $0) })
        let newerOnline = Dictionary(uniqueKeysWithValues: newer.hosts.filter { $0.status == .online }.map { ($0.ip.rawValue, $0) })

        var newly: [ScanHostSnapshot] = []
        for (key, host) in newerOnline where olderOnline[key] == nil {
            newly.append(host)
        }

        var missing: [ScanHostSnapshot] = []
        for (key, host) in olderOnline where newerOnline[key] == nil {
            missing.append(host)
        }

        var changed: [ServiceChange] = []
        for (key, before) in olderOnline {
            guard let after = newerOnline[key] else { continue }
            let beforePorts = Set(before.services.map(\.port))
            let afterPorts = Set(after.services.map(\.port))
            if beforePorts != afterPorts {
                changed.append(ServiceChange(ip: before.ip, before: before.services, after: after.services))
            }
        }

        newly.sort { $0.ip < $1.ip }
        missing.sort { $0.ip < $1.ip }
        return ScanComparison(
            newlyObserved: newly,
            previouslyObservedNoResponse: missing,
            changedServices: changed,
            uncertainMatches: uncertain
        )
    }
}

public protocol ScanHistoryStoring: Sendable {
    func load() throws -> [ScanSnapshot]
    func save(_ items: [ScanSnapshot]) throws
}

public struct FileScanHistoryStore: ScanHistoryStoring {
    public var fileURL: URL
    public var retentionLimit: Int

    public init(fileURL: URL, retentionLimit: Int = 50) {
        self.fileURL = fileURL
        self.retentionLimit = max(1, retentionLimit)
    }

    public static func applicationSupportStore(retentionLimit: Int = 50) throws -> FileScanHistoryStore {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("OpenLANScanner", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return FileScanHistoryStore(
            fileURL: dir.appendingPathComponent("scan-history.json"),
            retentionLimit: retentionLimit
        )
    }

    public static let maxFileByteCount = 8 * 1024 * 1024

    public func load() throws -> [ScanSnapshot] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        if let size = attrs[.size] as? NSNumber, size.intValue > Self.maxFileByteCount {
            throw NSError(
                domain: "ScanHistory",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Scan history file exceeds \(Self.maxFileByteCount) bytes."
                ]
            )
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ScanSnapshot].self, from: data)
    }

    public func save(_ items: [ScanSnapshot]) throws {
        let trimmed = Array(items.sorted { $0.createdAt > $1.createdAt }.prefix(retentionLimit))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(trimmed).write(to: fileURL, options: .atomic)
    }
}

public final class InMemoryScanHistoryStore: ScanHistoryStoring, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [ScanSnapshot]())
    public var retentionLimit: Int
    public init(retentionLimit: Int = 50) { self.retentionLimit = retentionLimit }
    public func load() throws -> [ScanSnapshot] { lock.withLock { $0 } }
    public func save(_ items: [ScanSnapshot]) throws {
        let limit = retentionLimit
        lock.withLock { $0 = Array(items.prefix(limit)) }
    }
}
