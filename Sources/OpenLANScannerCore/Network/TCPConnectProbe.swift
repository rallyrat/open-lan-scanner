import Foundation
import Network
import os

public struct ScanInterfaceConstraint: Sendable, Equatable {
    public var bsdName: String?
    public var ipv4: IPv4Address?

    public init(bsdName: String? = nil, ipv4: IPv4Address? = nil) {
        self.bsdName = bsdName
        self.ipv4 = ipv4
    }

    public static let none = ScanInterfaceConstraint()
}

public protocol TCPConnecting: Sendable {
    func probe(
        host: IPv4Address,
        port: UInt16,
        timeoutMs: Int,
        interface: ScanInterfaceConstraint
    ) async -> ProbeOutcome
}

public extension TCPConnecting {
    func probe(host: IPv4Address, port: UInt16, timeoutMs: Int) async -> ProbeOutcome {
        await probe(host: host, port: port, timeoutMs: timeoutMs, interface: .none)
    }
}

public struct NWConnectionTCPProbe: TCPConnecting {
    public init() {}

    public func probe(
        host: IPv4Address,
        port: UInt16,
        timeoutMs: Int,
        interface: ScanInterfaceConstraint
    ) async -> ProbeOutcome {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host.dotted),
            port: NWEndpoint.Port(rawValue: port)!
        )

        let parameters = NWParameters.tcp
        parameters.prohibitExpensivePaths = false
        parameters.prohibitConstrainedPaths = false
        if let bsd = interface.bsdName, !bsd.isEmpty,
           let nwInterface = Self.interface(named: bsd) {
            parameters.requiredInterface = nwInterface
        }

        let connection = NWConnection(to: endpoint, using: parameters)
        let gate = OSAllocatedUnfairLock(initialState: false)
        let started = Date()
        // Box so task cancellation can cancel the NWConnection promptly.
        let connectionBox = ConnectionBox(connection)

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let resumeOnce: @Sendable (ProbeOutcome) -> Void = { result in
                    let shouldResume = gate.withLock { resumed -> Bool in
                        if resumed { return false }
                        resumed = true
                        return true
                    }
                    guard shouldResume else { return }
                    connectionBox.cancel()
                    continuation.resume(returning: result)
                }

                connection.stateUpdateHandler = { stateUpdate in
                    switch stateUpdate {
                    case .ready:
                        let ms = Date().timeIntervalSince(started) * 1000
                        resumeOnce(ProbeOutcome(kind: .open, latencyMs: ms))
                    case .failed(let error):
                        resumeOnce(Self.mapFailure(error, started: started))
                    case .cancelled:
                        resumeOnce(ProbeOutcome(kind: .cancelled))
                    case .waiting(let error):
                        if connection.currentPath?.unsatisfiedReason == .localNetworkDenied {
                            resumeOnce(ProbeOutcome(kind: .localNetworkDenied))
                        } else if Self.isConnectionRefused(error) {
                            let ms = Date().timeIntervalSince(started) * 1000
                            resumeOnce(ProbeOutcome(kind: .refused, latencyMs: ms, detail: error.localizedDescription))
                        }
                    default:
                        break
                    }
                }

                connection.start(queue: DispatchQueue.global(qos: .utility))

                let timeout = DispatchTime.now() + .milliseconds(max(1, timeoutMs))
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: timeout) {
                    resumeOnce(ProbeOutcome(kind: .timeout))
                }
            }
        } onCancel: {
            connectionBox.cancel()
        }
    }

    private static func interface(named bsdName: String) -> NWInterface? {
        let monitor = NWPathMonitor()
        let semaphore = DispatchSemaphore(value: 0)
        var match: NWInterface?
        monitor.pathUpdateHandler = { path in
            match = path.availableInterfaces.first { $0.name == bsdName }
            semaphore.signal()
        }
        let queue = DispatchQueue(label: "ols.iface")
        monitor.start(queue: queue)
        _ = semaphore.wait(timeout: .now() + 0.2)
        monitor.cancel()
        return match
    }

    private static func mapFailure(_ error: NWError, started: Date) -> ProbeOutcome {
        if isConnectionRefused(error) {
            let ms = Date().timeIntervalSince(started) * 1000
            return ProbeOutcome(kind: .refused, latencyMs: ms, detail: error.localizedDescription)
        }
        return ProbeOutcome(kind: .error, detail: error.localizedDescription)
    }

    private static func isConnectionRefused(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain && ns.code == Int(ECONNREFUSED) {
            return true
        }
        if let nw = error as? NWError {
            if case .posix(let code) = nw, code == .ECONNREFUSED {
                return true
            }
        }
        let text = error.localizedDescription.lowercased()
        return text.contains("connection refused") || text.contains("econnrefused")
    }
}

private final class ConnectionBox: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<NWConnection?>(initialState: nil)

    init(_ connection: NWConnection) {
        lock.withLock { $0 = connection }
    }

    func cancel() {
        let conn = lock.withLock { value -> NWConnection? in
            let current = value
            value = nil
            return current
        }
        conn?.cancel()
    }
}

public final class SimulatedTCPProbe: TCPConnecting, @unchecked Sendable {
    public var openPorts: [IPv4Address: Set<UInt16>]
    public var refusedPorts: [IPv4Address: Set<UInt16>]
    public var latencyMs: Double
    public var denyLocalNetwork: Bool
    public private(set) var lastInterface: ScanInterfaceConstraint?
    public var cancelAfterProbes: Int?
    public var stallMs: Int = 0
    private let state = OSAllocatedUnfairLock(initialState: ProbeCounters())

    public struct ProbeCounters: Sendable {
        public var started = 0
        public var finished = 0
        public var peakInFlight = 0
    }

    public var probeCount: Int { state.withLock { $0.started } }
    public var peakInFlight: Int { state.withLock { $0.peakInFlight } }
    public var unfinishedCount: Int {
        state.withLock { max(0, $0.started - $0.finished) }
    }

    public init(
        openPorts: [IPv4Address: Set<UInt16>] = [:],
        refusedPorts: [IPv4Address: Set<UInt16>] = [:],
        latencyMs: Double = 5,
        denyLocalNetwork: Bool = false
    ) {
        self.openPorts = openPorts
        self.refusedPorts = refusedPorts
        self.latencyMs = latencyMs
        self.denyLocalNetwork = denyLocalNetwork
    }

    public func probe(
        host: IPv4Address,
        port: UInt16,
        timeoutMs: Int,
        interface: ScanInterfaceConstraint
    ) async -> ProbeOutcome {
        _ = timeoutMs
        lastInterface = interface
        state.withLock { counters in
            counters.started += 1
            let inFlight = counters.started - counters.finished
            counters.peakInFlight = max(counters.peakInFlight, inFlight)
        }
        defer {
            state.withLock { $0.finished += 1 }
        }

        if stallMs > 0 {
            try? await Task.sleep(nanoseconds: UInt64(stallMs) * 1_000_000)
        }
        if Task.isCancelled {
            return ProbeOutcome(kind: .cancelled)
        }
        let count = state.withLock { $0.started }
        if let cancelAfterProbes, count > cancelAfterProbes {
            return ProbeOutcome(kind: .cancelled)
        }
        if denyLocalNetwork {
            return ProbeOutcome(kind: .localNetworkDenied)
        }
        if openPorts[host]?.contains(port) == true {
            return ProbeOutcome(kind: .open, latencyMs: latencyMs)
        }
        if refusedPorts[host]?.contains(port) == true {
            return ProbeOutcome(kind: .refused, latencyMs: latencyMs)
        }
        return ProbeOutcome(kind: .timeout)
    }
}
