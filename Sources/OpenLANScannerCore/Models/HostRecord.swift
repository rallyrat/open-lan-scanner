import Foundation

public enum HostReachability: String, Sendable, Codable, CaseIterable {
    /// No conclusive observation in the current scan.
    case unknown
    /// At least one live-host signal (open port, TCP refuse, ICMP, Bonjour).
    case online
    /// Reserved for explicit offline markers (not inferred from timeouts alone).
    case offline

    public var displayLabel: String {
        switch self {
        case .online: return "Responded"
        case .offline: return "Offline"
        case .unknown: return "No response"
        }
    }
}

public struct DiscoveredService: Hashable, Sendable, Codable, Identifiable {
    public var id: String { "\(name):\(port)" }
    public var name: String
    public var port: UInt16
    public var transport: String

    public init(name: String, port: UInt16, transport: String = "tcp") {
        self.name = name
        self.port = port
        self.transport = transport
    }
}

public struct HostRecord: Identifiable, Hashable, Sendable, Codable {
    public var id: String { ip.dotted }
    public var ip: IPv4Address
    public var status: HostReachability
    public var hostname: String?
    public var macAddress: String?
    public var vendor: String?
    public var responseTimeMs: Double?
    public var latencyKind: LatencyKind
    public var services: [DiscoveredService]
    public var evidence: [DiscoveryEvidence]
    public var isFavorite: Bool
    public var customName: String?
    public var notes: String?
    public var lastSeen: Date?
    public var firstSeenInScan: Date?

    public enum LatencyKind: String, Sendable, Codable {
        case none
        case tcpProbe
        case icmp

        /// User-facing label (never expose raw enum cases in UI).
        public var displayLabel: String {
            switch self {
            case .none: return "—"
            case .tcpProbe: return "TCP connection"
            case .icmp: return "ICMP echo"
            }
        }
    }

    public var responseSummary: String {
        guard let ms = responseTimeMs else { return "—" }
        switch latencyKind {
        case .none:
            return String(format: "%.0f ms", ms)
        case .tcpProbe, .icmp:
            return String(format: "%.0f ms · %@", ms, latencyKind.displayLabel)
        }
    }

    public init(
        ip: IPv4Address,
        status: HostReachability = .unknown,
        hostname: String? = nil,
        macAddress: String? = nil,
        vendor: String? = nil,
        responseTimeMs: Double? = nil,
        latencyKind: LatencyKind = .none,
        services: [DiscoveredService] = [],
        evidence: [DiscoveryEvidence] = [],
        isFavorite: Bool = false,
        customName: String? = nil,
        notes: String? = nil,
        lastSeen: Date? = nil,
        firstSeenInScan: Date? = nil
    ) {
        self.ip = ip
        self.status = status
        self.hostname = hostname
        self.macAddress = macAddress
        self.vendor = vendor
        self.responseTimeMs = responseTimeMs
        self.latencyKind = latencyKind
        self.services = services
        self.evidence = evidence
        self.isFavorite = isFavorite
        self.customName = customName
        self.notes = notes
        self.lastSeen = lastSeen
        self.firstSeenInScan = firstSeenInScan
    }

    public var displayName: String {
        if let customName, !customName.isEmpty { return customName }
        if let hostname, !hostname.isEmpty { return hostname }
        return ip.dotted
    }

    public mutating func merge(_ other: HostRecord) {
        precondition(ip == other.ip)
        if other.status == .online {
            status = .online
        } else if status == .unknown, other.status != .unknown {
            status = other.status
        }
        if let hostname = other.hostname, !hostname.isEmpty { self.hostname = hostname }
        if let mac = other.macAddress, !mac.isEmpty { macAddress = mac }
        if let vendor = other.vendor, !vendor.isEmpty { self.vendor = vendor }
        if let ms = other.responseTimeMs {
            if responseTimeMs == nil || ms < (responseTimeMs ?? .greatestFiniteMagnitude) {
                responseTimeMs = ms
                latencyKind = other.latencyKind
            }
        }
        var byPort = Dictionary(uniqueKeysWithValues: services.map { ($0.port, $0) })
        for service in other.services {
            byPort[service.port] = service
        }
        services = byPort.values.sorted { $0.port < $1.port }

        var evidenceKeys = Set(evidence.map { "\($0.kind.rawValue)|\($0.detail)" })
        for item in other.evidence where evidenceKeys.insert("\(item.kind.rawValue)|\(item.detail)").inserted {
            evidence.append(item)
        }

        if other.isFavorite { isFavorite = true }
        if let customName = other.customName { self.customName = customName }
        if let notes = other.notes { self.notes = notes }
        if let lastSeen = other.lastSeen {
            if self.lastSeen == nil || lastSeen > self.lastSeen! {
                self.lastSeen = lastSeen
            }
        }
        if firstSeenInScan == nil {
            firstSeenInScan = other.firstSeenInScan ?? other.lastSeen
        }
    }
}
