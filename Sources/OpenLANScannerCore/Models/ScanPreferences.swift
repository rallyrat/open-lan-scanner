import Foundation

public struct ServiceProbeDefinition: Hashable, Sendable, Codable, Identifiable {
    public var id: String { "\(name)-\(port)" }
    public var name: String
    public var port: UInt16
    public var enabled: Bool

    public init(name: String, port: UInt16, enabled: Bool = true) {
        self.name = name
        self.port = port
        self.enabled = enabled
    }

    public static let defaults: [ServiceProbeDefinition] = [
        .init(name: "SSH", port: 22),
        .init(name: "HTTP", port: 80),
        .init(name: "HTTPS", port: 443),
        .init(name: "SMB", port: 445),
        .init(name: "RDP", port: 3389),
        .init(name: "VNC", port: 5900),
        .init(name: "AFP", port: 548, enabled: false),
        .init(name: "FTP", port: 21, enabled: false)
    ]
}

/// Ports used only to detect a responding host (not listed as services unless also enabled above).
public struct DiscoveryProbeDefinition: Hashable, Sendable, Codable, Identifiable {
    public var id: String { "discovery-\(port)" }
    public var port: UInt16
    public var enabled: Bool

    public init(port: UInt16, enabled: Bool = true) {
        self.port = port
        self.enabled = enabled
    }

    public static let defaults: [DiscoveryProbeDefinition] = [
        .init(port: 80),
        .init(port: 443),
        .init(port: 22),
        .init(port: 445),
        .init(port: 548),
        .init(port: 3389),
        .init(port: 5900)
    ]
}

public struct ScanPreferences: Sendable, Codable, Equatable {
    public var schemaVersion: Int
    public var concurrency: Int
    public var enrichmentConcurrency: Int
    public var connectTimeoutMs: Int
    public var resolveHostnames: Bool
    public var lookupNeighbors: Bool
    public var lookupVendors: Bool
    public var probeRetries: Int
    public var largeRangeWarningThreshold: Int
    public var services: [ServiceProbeDefinition]
    public var discoveryProbes: [DiscoveryProbeDefinition]
    public var attemptICMP: Bool
    public var browseBonjour: Bool

    public static let currentSchemaVersion = 2

    public init(
        schemaVersion: Int = ScanPreferences.currentSchemaVersion,
        concurrency: Int = 64,
        enrichmentConcurrency: Int = 8,
        connectTimeoutMs: Int = 400,
        resolveHostnames: Bool = true,
        lookupNeighbors: Bool = true,
        lookupVendors: Bool = true,
        probeRetries: Int = 1,
        largeRangeWarningThreshold: Int = 1024,
        services: [ServiceProbeDefinition] = ServiceProbeDefinition.defaults,
        discoveryProbes: [DiscoveryProbeDefinition] = DiscoveryProbeDefinition.defaults,
        attemptICMP: Bool = true,
        browseBonjour: Bool = true
    ) {
        self.schemaVersion = schemaVersion
        self.concurrency = Self.clamp(concurrency, 1...512)
        self.enrichmentConcurrency = Self.clamp(enrichmentConcurrency, 1...64)
        self.connectTimeoutMs = Self.clamp(connectTimeoutMs, 50...10_000)
        self.resolveHostnames = resolveHostnames
        self.lookupNeighbors = lookupNeighbors
        self.lookupVendors = lookupVendors
        self.probeRetries = Self.clamp(probeRetries, 1...5)
        self.largeRangeWarningThreshold = max(1, largeRangeWarningThreshold)
        self.services = services
        self.discoveryProbes = discoveryProbes
        self.attemptICMP = attemptICMP
        self.browseBonjour = browseBonjour
    }

    public var enabledServicePorts: [ServiceProbeDefinition] {
        services.filter(\.enabled)
    }

    public var enabledDiscoveryPorts: [UInt16] {
        discoveryProbes.filter(\.enabled).map(\.port)
    }

    /// Clamp + fill defaults after Codable decode (synthesized decode bypasses init clamps).
    public mutating func normalize() {
        schemaVersion = Self.currentSchemaVersion
        concurrency = Self.clamp(concurrency, 1...512)
        enrichmentConcurrency = Self.clamp(enrichmentConcurrency, 1...64)
        connectTimeoutMs = Self.clamp(connectTimeoutMs, 50...10_000)
        probeRetries = Self.clamp(probeRetries, 1...5)
        largeRangeWarningThreshold = max(1, largeRangeWarningThreshold)
        if services.isEmpty {
            services = ServiceProbeDefinition.defaults
        }
        if discoveryProbes.isEmpty {
            discoveryProbes = DiscoveryProbeDefinition.defaults
        }
    }

    public static func validated(_ prefs: ScanPreferences) -> ScanPreferences {
        var copy = prefs
        copy.normalize()
        return copy
    }

    private static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, concurrency, enrichmentConcurrency, connectTimeoutMs
        case resolveHostnames, lookupNeighbors, lookupVendors, probeRetries
        case largeRangeWarningThreshold, services, discoveryProbes, attemptICMP, browseBonjour
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        concurrency = try container.decodeIfPresent(Int.self, forKey: .concurrency) ?? 64
        enrichmentConcurrency = try container.decodeIfPresent(Int.self, forKey: .enrichmentConcurrency) ?? 8
        connectTimeoutMs = try container.decodeIfPresent(Int.self, forKey: .connectTimeoutMs) ?? 400
        resolveHostnames = try container.decodeIfPresent(Bool.self, forKey: .resolveHostnames) ?? true
        lookupNeighbors = try container.decodeIfPresent(Bool.self, forKey: .lookupNeighbors) ?? true
        lookupVendors = try container.decodeIfPresent(Bool.self, forKey: .lookupVendors) ?? true
        probeRetries = try container.decodeIfPresent(Int.self, forKey: .probeRetries) ?? 1
        largeRangeWarningThreshold = try container.decodeIfPresent(Int.self, forKey: .largeRangeWarningThreshold) ?? 1024
        services = try container.decodeIfPresent([ServiceProbeDefinition].self, forKey: .services) ?? ServiceProbeDefinition.defaults
        discoveryProbes = try container.decodeIfPresent([DiscoveryProbeDefinition].self, forKey: .discoveryProbes)
            ?? DiscoveryProbeDefinition.defaults
        attemptICMP = try container.decodeIfPresent(Bool.self, forKey: .attemptICMP) ?? true
        browseBonjour = try container.decodeIfPresent(Bool.self, forKey: .browseBonjour) ?? true
        normalize()
    }
}
