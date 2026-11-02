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

public struct ScanPreferences: Sendable, Codable, Equatable {
    public var concurrency: Int
    public var connectTimeoutMs: Int
    public var resolveHostnames: Bool
    public var lookupNeighbors: Bool
    public var lookupVendors: Bool
    public var probeRetries: Int
    public var largeRangeWarningThreshold: Int
    public var services: [ServiceProbeDefinition]
    public var attemptICMP: Bool

    public init(
        concurrency: Int = 64,
        connectTimeoutMs: Int = 400,
        resolveHostnames: Bool = true,
        lookupNeighbors: Bool = true,
        lookupVendors: Bool = true,
        probeRetries: Int = 1,
        largeRangeWarningThreshold: Int = 1024,
        services: [ServiceProbeDefinition] = ServiceProbeDefinition.defaults,
        attemptICMP: Bool = false
    ) {
        self.concurrency = max(1, min(concurrency, 512))
        self.connectTimeoutMs = max(50, min(connectTimeoutMs, 10_000))
        self.resolveHostnames = resolveHostnames
        self.lookupNeighbors = lookupNeighbors
        self.lookupVendors = lookupVendors
        self.probeRetries = max(1, min(probeRetries, 5))
        self.largeRangeWarningThreshold = max(1, largeRangeWarningThreshold)
        self.services = services
        self.attemptICMP = attemptICMP
    }

    public var enabledPorts: [ServiceProbeDefinition] {
        services.filter(\.enabled)
    }
}
