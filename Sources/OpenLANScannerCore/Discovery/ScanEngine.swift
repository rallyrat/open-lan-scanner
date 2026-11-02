import Foundation

public struct ScanProgress: Sendable, Equatable {
    public var completed: Int
    public var total: Int
    public var onlineCount: Int
    public var isFinished: Bool
    public var localNetworkDenied: Bool
    public var generation: UUID

    public var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    public init(
        completed: Int = 0,
        total: Int = 0,
        onlineCount: Int = 0,
        isFinished: Bool = false,
        localNetworkDenied: Bool = false,
        generation: UUID = UUID()
    ) {
        self.completed = completed
        self.total = total
        self.onlineCount = onlineCount
        self.isFinished = isFinished
        self.localNetworkDenied = localNetworkDenied
        self.generation = generation
    }
}

public struct ScanEvent: Sendable {
    public var generation: UUID
    public var host: HostRecord?
    public var progress: ScanProgress
}

public struct HostProbeOutcome: Sendable {
    public var host: HostRecord?
    public var localNetworkDenied: Bool
}

public struct ScanEngineDependencies: Sendable {
    public var tcp: any TCPConnecting
    public var neighbors: any NeighborLooking
    public var hostnames: any HostnameResolving
    public var vendors: any VendorLooking

    public init(
        tcp: any TCPConnecting,
        neighbors: any NeighborLooking,
        hostnames: any HostnameResolving,
        vendors: any VendorLooking
    ) {
        self.tcp = tcp
        self.neighbors = neighbors
        self.hostnames = hostnames
        self.vendors = vendors
    }

    public static func production() -> ScanEngineDependencies {
        ScanEngineDependencies(
            tcp: NWConnectionTCPProbe(),
            neighbors: SystemNeighborTable(),
            hostnames: SystemHostnameResolver(),
            vendors: OUIVendorLookup.loadBundledSample()
        )
    }
}

public actor ScanEngine {
    private let deps: ScanEngineDependencies
    private var currentTask: Task<Void, Never>?
    private var currentGeneration: UUID?

    public init(dependencies: ScanEngineDependencies = .production()) {
        self.deps = dependencies
    }

    public func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    public func scan(
        addresses: [IPv4Address],
        preferences: ScanPreferences
    ) -> AsyncStream<ScanEvent> {
        let generation = UUID()
        currentGeneration = generation
        currentTask?.cancel()

        let (stream, continuation) = AsyncStream.makeStream(
            of: ScanEvent.self,
            bufferingPolicy: .bufferingNewest(256)
        )

        let task = Task {
            await self.runScan(
                addresses: addresses,
                preferences: preferences,
                generation: generation,
                continuation: continuation
            )
        }
        currentTask = task
        continuation.onTermination = { @Sendable _ in
            task.cancel()
        }
        return stream
    }

    private func runScan(
        addresses: [IPv4Address],
        preferences: ScanPreferences,
        generation: UUID,
        continuation: AsyncStream<ScanEvent>.Continuation
    ) async {
        let deps = self.deps
        if preferences.lookupNeighbors {
            await deps.neighbors.refresh()
        }

        let total = addresses.count
        var completed = 0
        var onlineCount = 0
        var denied = false

        func emit(host: HostRecord? = nil, finished: Bool = false) {
            let progress = ScanProgress(
                completed: completed,
                total: total,
                onlineCount: onlineCount,
                isFinished: finished,
                localNetworkDenied: denied,
                generation: generation
            )
            continuation.yield(ScanEvent(generation: generation, host: host, progress: progress))
        }

        emit()

        await withTaskGroup(of: HostProbeOutcome.self) { group in
            var iterator = addresses.makeIterator()
            let limit = min(preferences.concurrency, max(total, 1))

            func enqueueNext() {
                guard let ip = iterator.next() else { return }
                group.addTask {
                    await Self.probeHost(ip: ip, preferences: preferences, deps: deps)
                }
            }

            for _ in 0..<min(limit, total) {
                enqueueNext()
            }

            for await outcome in group {
                if Task.isCancelled || self.currentGeneration != generation {
                    group.cancelAll()
                    break
                }

                completed += 1
                if outcome.localNetworkDenied {
                    denied = true
                }
                if let host = outcome.host {
                    if host.status == .online {
                        onlineCount += 1
                    }
                    emit(host: host)
                } else {
                    emit()
                }
                enqueueNext()
            }
        }

        emit(finished: true)
        continuation.finish()
    }

    private static func probeHost(
        ip: IPv4Address,
        preferences: ScanPreferences,
        deps: ScanEngineDependencies
    ) async -> HostProbeOutcome {
        if Task.isCancelled {
            return HostProbeOutcome(host: nil, localNetworkDenied: false)
        }

        var bestLatency: Double?
        var services: [DiscoveredService] = []
        var denied = false

        var probeList = preferences.enabledPorts
        let presenceExtras: [(String, UInt16)] = [
            ("HTTP", 80), ("HTTPS", 443), ("SSH", 22),
            ("SMB", 445), ("AFP", 548), ("RDP", 3389), ("VNC", 5900)
        ]
        for (name, port) in presenceExtras where !probeList.contains(where: { $0.port == port }) {
            probeList.append(ServiceProbeDefinition(name: name, port: port, enabled: false))
        }

        for _ in 0..<preferences.probeRetries {
            if Task.isCancelled { break }
            for service in probeList {
                if Task.isCancelled { break }
                let result = await deps.tcp.probe(
                    host: ip,
                    port: service.port,
                    timeoutMs: preferences.connectTimeoutMs
                )
                if result.localNetworkDenied {
                    denied = true
                }
                guard result.isOpen else { continue }
                if let ms = result.latencyMs {
                    bestLatency = min(bestLatency ?? ms, ms)
                }
                if let configured = preferences.enabledPorts.first(where: { $0.port == service.port && $0.enabled }) {
                    services.append(DiscoveredService(name: configured.name, port: configured.port))
                }
            }
            if bestLatency != nil { break }
        }

        guard bestLatency != nil else {
            return HostProbeOutcome(host: nil, localNetworkDenied: denied)
        }

        var byPort: [UInt16: DiscoveredService] = [:]
        for service in services {
            byPort[service.port] = service
        }

        var record = HostRecord(
            ip: ip,
            status: .online,
            responseTimeMs: bestLatency,
            latencyKind: .tcpProbe,
            services: byPort.values.sorted { $0.port < $1.port },
            lastSeen: Date()
        )

        if preferences.lookupNeighbors, let mac = deps.neighbors.macAddress(for: ip) {
            record.macAddress = mac
            if preferences.lookupVendors {
                record.vendor = deps.vendors.vendor(forMAC: mac)
            }
        }

        if preferences.resolveHostnames {
            record.hostname = await deps.hostnames.reverseDNS(for: ip)
        }

        return HostProbeOutcome(host: record, localNetworkDenied: denied)
    }
}
