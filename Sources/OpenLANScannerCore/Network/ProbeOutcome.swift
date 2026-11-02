import Foundation

/// Distinct TCP (or similar) probe outcomes. A refusal proves a stack answered; a timeout does not.
public enum ProbeOutcomeKind: String, Sendable, Codable, Equatable {
    case open
    case refused
    case timeout
    case localNetworkDenied
    case cancelled
    case error
}

public struct ProbeOutcome: Sendable, Equatable {
    public var kind: ProbeOutcomeKind
    public var latencyMs: Double?
    public var detail: String?

    public init(kind: ProbeOutcomeKind, latencyMs: Double? = nil, detail: String? = nil) {
        self.kind = kind
        self.latencyMs = latencyMs
        self.detail = detail
    }

    public var indicatesLiveHost: Bool {
        switch kind {
        case .open, .refused:
            return true
        case .timeout, .localNetworkDenied, .cancelled, .error:
            return false
        }
    }

    public var isOpenService: Bool { kind == .open }
    public var localNetworkDenied: Bool { kind == .localNetworkDenied }
}

/// Back-compat shim used by older call sites/tests during migration.
public struct ProbeResult: Sendable, Equatable {
    public var isOpen: Bool
    public var latencyMs: Double?
    public var localNetworkDenied: Bool
    public var outcome: ProbeOutcome

    public init(isOpen: Bool, latencyMs: Double? = nil, localNetworkDenied: Bool = false) {
        self.isOpen = isOpen
        self.latencyMs = latencyMs
        self.localNetworkDenied = localNetworkDenied
        if localNetworkDenied {
            self.outcome = ProbeOutcome(kind: .localNetworkDenied)
        } else if isOpen {
            self.outcome = ProbeOutcome(kind: .open, latencyMs: latencyMs)
        } else {
            self.outcome = ProbeOutcome(kind: .timeout, latencyMs: latencyMs)
        }
    }

    public init(outcome: ProbeOutcome) {
        self.outcome = outcome
        self.isOpen = outcome.isOpenService
        self.latencyMs = outcome.latencyMs
        self.localNetworkDenied = outcome.localNetworkDenied
    }
}

public struct DiscoveryEvidence: Hashable, Sendable, Codable, Equatable {
    public enum Kind: String, Sendable, Codable {
        case tcpOpen
        case tcpRefused
        case icmpEcho
        case bonjour

        public var displayLabel: String {
            switch self {
            case .tcpOpen: return "Open TCP port"
            case .tcpRefused: return "TCP connection refused"
            case .icmpEcho: return "ICMP echo reply"
            case .bonjour: return "Bonjour"
            }
        }
    }

    public var kind: Kind
    public var detail: String
    public var observedAt: Date
    public var latencyMs: Double?

    public init(kind: Kind, detail: String, observedAt: Date = Date(), latencyMs: Double? = nil) {
        self.kind = kind
        self.detail = detail
        self.observedAt = observedAt
        self.latencyMs = latencyMs
    }

    public var displaySummary: String {
        if detail.isEmpty { return kind.displayLabel }
        return "\(kind.displayLabel) · \(detail)"
    }
}
