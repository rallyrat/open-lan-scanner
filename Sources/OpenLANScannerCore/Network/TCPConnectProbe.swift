import Foundation
import Network
import os

public struct ProbeResult: Sendable, Equatable {
    public var isOpen: Bool
    public var latencyMs: Double?
    public var localNetworkDenied: Bool

    public init(isOpen: Bool, latencyMs: Double? = nil, localNetworkDenied: Bool = false) {
        self.isOpen = isOpen
        self.latencyMs = latencyMs
        self.localNetworkDenied = localNetworkDenied
    }
}

public protocol TCPConnecting: Sendable {
    func probe(host: IPv4Address, port: UInt16, timeoutMs: Int) async -> ProbeResult
}

public struct NWConnectionTCPProbe: TCPConnecting {
    public init() {}

    public func probe(host: IPv4Address, port: UInt16, timeoutMs: Int) async -> ProbeResult {
        await withCheckedContinuation { continuation in
            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(host.dotted),
                port: NWEndpoint.Port(rawValue: port)!
            )
            let connection = NWConnection(to: endpoint, using: .tcp)
            let state = OSAllocatedUnfairLock(initialState: false)
            let started = Date()

            let finish: @Sendable (ProbeResult) -> Void = { result in
                let shouldResume = state.withLock { resumed -> Bool in
                    if resumed { return false }
                    resumed = true
                    return true
                }
                guard shouldResume else { return }
                connection.cancel()
                continuation.resume(returning: result)
            }

            connection.stateUpdateHandler = { stateUpdate in
                switch stateUpdate {
                case .ready:
                    let ms = Date().timeIntervalSince(started) * 1000
                    finish(ProbeResult(isOpen: true, latencyMs: ms))
                case .failed, .cancelled:
                    finish(ProbeResult(isOpen: false))
                case .waiting:
                    if connection.currentPath?.unsatisfiedReason == .localNetworkDenied {
                        finish(ProbeResult(isOpen: false, localNetworkDenied: true))
                    }
                default:
                    break
                }
            }

            connection.start(queue: DispatchQueue.global(qos: .utility))

            let timeout = DispatchTime.now() + .milliseconds(timeoutMs)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: timeout) {
                finish(ProbeResult(isOpen: false))
            }
        }
    }
}

/// Deterministic transport for unit tests.
public final class SimulatedTCPProbe: TCPConnecting, @unchecked Sendable {
    public var openPorts: [IPv4Address: Set<UInt16>]
    public var latencyMs: Double
    public var denyLocalNetwork: Bool
    private let state: OSAllocatedUnfairLock<(count: Int, open: [IPv4Address: Set<UInt16>], latency: Double, deny: Bool)>

    public var probeCount: Int {
        state.withLock(\.count)
    }

    public init(
        openPorts: [IPv4Address: Set<UInt16>] = [:],
        latencyMs: Double = 5,
        denyLocalNetwork: Bool = false
    ) {
        self.openPorts = openPorts
        self.latencyMs = latencyMs
        self.denyLocalNetwork = denyLocalNetwork
        self.state = OSAllocatedUnfairLock(initialState: (0, openPorts, latencyMs, denyLocalNetwork))
    }

    public func probe(host: IPv4Address, port: UInt16, timeoutMs: Int) async -> ProbeResult {
        _ = timeoutMs
        return state.withLock { s in
            s.count += 1
            // Keep mutable mirrors in sync for callers that mutate properties after init.
            s.open = openPorts
            s.latency = latencyMs
            s.deny = denyLocalNetwork
            if s.deny {
                return ProbeResult(isOpen: false, localNetworkDenied: true)
            }
            let isOpen = s.open[host]?.contains(port) == true
            return ProbeResult(isOpen: isOpen, latencyMs: isOpen ? s.latency : nil)
        }
    }
}
