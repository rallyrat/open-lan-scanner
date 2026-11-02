import Foundation

public enum ScanPhase: String, Sendable, Codable, Equatable {
    case idle
    case running
    case stopping
    case completed
    case stopped
    case failed
}

public struct ScanProgress: Sendable, Equatable {
    public var completed: Int
    public var total: Int
    public var onlineCount: Int
    public var phase: ScanPhase
    public var localNetworkDenied: Bool
    public var generation: UUID
    public var interfaceNote: String?

    public var isFinished: Bool {
        switch phase {
        case .completed, .stopped, .failed: return true
        case .idle, .running, .stopping: return false
        }
    }

    public var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    public init(
        completed: Int = 0,
        total: Int = 0,
        onlineCount: Int = 0,
        phase: ScanPhase = .idle,
        localNetworkDenied: Bool = false,
        generation: UUID = UUID(),
        interfaceNote: String? = nil
    ) {
        self.completed = completed
        self.total = total
        self.onlineCount = onlineCount
        self.phase = phase
        self.localNetworkDenied = localNetworkDenied
        self.generation = generation
        self.interfaceNote = interfaceNote
    }
}

public struct ScanEvent: Sendable {
    public var generation: UUID
    public var host: HostRecord?
    public var progress: ScanProgress
    /// When true, UI should merge `host` but ignore progress counters.
    public var isEnrichmentOnly: Bool

    public init(
        generation: UUID,
        host: HostRecord?,
        progress: ScanProgress,
        isEnrichmentOnly: Bool = false
    ) {
        self.generation = generation
        self.host = host
        self.progress = progress
        self.isEnrichmentOnly = isEnrichmentOnly
    }
}

public struct ScanConfiguration: Sendable {
    public var addresses: [IPv4Address]
    public var preferences: ScanPreferences
    public var interface: ScanInterfaceConstraint
    public var interfaceNote: String?

    public init(
        addresses: [IPv4Address],
        preferences: ScanPreferences,
        interface: ScanInterfaceConstraint = .none,
        interfaceNote: String? = nil
    ) {
        self.addresses = addresses
        self.preferences = preferences
        self.interface = interface
        self.interfaceNote = interfaceNote
    }
}

public struct HostProbeOutcome: Sendable {
    public var host: HostRecord?
    public var localNetworkDenied: Bool
}

public struct ScanEngineDependencies: Sendable {
    public var tcp: any TCPConnecting
    public var icmp: any ICMPProbing
    public var bonjour: any BonjourBrowsing
    public var neighbors: any NeighborLooking
    public var hostnames: any HostnameResolving
    public var vendors: any VendorLooking

    public init(
        tcp: any TCPConnecting,
        icmp: any ICMPProbing = NoOpICMPProbe(),
        bonjour: any BonjourBrowsing = NoOpBonjourBrowser(),
        neighbors: any NeighborLooking,
        hostnames: any HostnameResolving,
        vendors: any VendorLooking
    ) {
        self.tcp = tcp
        self.icmp = icmp
        self.bonjour = bonjour
        self.neighbors = neighbors
        self.hostnames = hostnames
        self.vendors = vendors
    }

    public static func production() -> ScanEngineDependencies {
        ScanEngineDependencies(
            tcp: NWConnectionTCPProbe(),
            icmp: SystemICMPProbe(),
            bonjour: SystemBonjourBrowser(),
            neighbors: SystemNeighborTable(),
            hostnames: SystemHostnameResolver(),
            vendors: OUIVendorLookup.loadDefault()
        )
    }
}

public struct ScanResourceMetrics: Sendable, Equatable {
    public var peakEnrichmentInFlight: Int
    public var enrichmentStarted: Int
    public var enrichmentFinished: Int
    public var hostEventsYielded: Int
    public var activeEnrichmentWaiters: Int

    public init(
        peakEnrichmentInFlight: Int = 0,
        enrichmentStarted: Int = 0,
        enrichmentFinished: Int = 0,
        hostEventsYielded: Int = 0,
        activeEnrichmentWaiters: Int = 0
    ) {
        self.peakEnrichmentInFlight = peakEnrichmentInFlight
        self.enrichmentStarted = enrichmentStarted
        self.enrichmentFinished = enrichmentFinished
        self.hostEventsYielded = hostEventsYielded
        self.activeEnrichmentWaiters = activeEnrichmentWaiters
    }
}

public actor ScanEngine {
    private let deps: ScanEngineDependencies
    private var currentTask: Task<Void, Never>?
    private var currentGeneration: UUID?
    private var enrichTasks: [Task<Void, Never>] = []
    private var enrichmentRunning = 0
    private var enrichmentWaiters: [CheckedContinuation<Void, Never>] = []
    private var metrics = ScanResourceMetrics()

    public init(dependencies: ScanEngineDependencies = .production()) {
        self.deps = dependencies
    }

    public func resourceMetrics() -> ScanResourceMetrics {
        var snapshot = metrics
        snapshot.activeEnrichmentWaiters = enrichmentWaiters.count
        return snapshot
    }

    public func cancel() {
        currentTask?.cancel()
        for task in enrichTasks { task.cancel() }
        enrichTasks.removeAll()
        currentTask = nil
        // Unblock any waiters so cancelled enrichment tasks can exit.
        let waiters = enrichmentWaiters
        enrichmentWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        enrichmentRunning = 0
    }

    public func scan(configuration: ScanConfiguration) -> AsyncStream<ScanEvent> {
        let generation = UUID()
        currentGeneration = generation
        currentTask?.cancel()
        for task in enrichTasks { task.cancel() }
        enrichTasks.removeAll()
        let strandedWaiters = enrichmentWaiters
        enrichmentWaiters.removeAll()
        for waiter in strandedWaiters { waiter.resume() }
        enrichmentRunning = 0
        metrics = ScanResourceMetrics()

        // Unbounded buffer so a slow UI cannot drop discovered hosts. Consumers should still
        // coalesce by IP; progress events are frequent but host payloads are authoritative merges.
        let (stream, continuation) = AsyncStream.makeStream(
            of: ScanEvent.self,
            bufferingPolicy: .unbounded
        )

        let task = Task {
            await self.runScan(
                configuration: configuration,
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

    /// Convenience for older call sites.
    public func scan(addresses: [IPv4Address], preferences: ScanPreferences) -> AsyncStream<ScanEvent> {
        scan(configuration: ScanConfiguration(addresses: addresses, preferences: preferences))
    }

    private func runScan(
        configuration: ScanConfiguration,
        generation: UUID,
        continuation: AsyncStream<ScanEvent>.Continuation
    ) async {
        let deps = self.deps
        let preferences = ScanPreferences.validated(configuration.preferences)
        let addresses = configuration.addresses
        let iface = configuration.interface

        let total = addresses.count
        var completed = 0
        var onlineIPs = Set<UInt32>()
        var denied = false
        var phase: ScanPhase = .running

        func emit(host: HostRecord? = nil, phaseOverride: ScanPhase? = nil, enrichmentOnly: Bool = false) {
            if let phaseOverride { phase = phaseOverride }
            if let host, host.status == .online {
                onlineIPs.insert(host.ip.rawValue)
            }
            if host != nil {
                self.metrics.hostEventsYielded += 1
            }
            let progress = ScanProgress(
                completed: completed,
                total: total,
                onlineCount: onlineIPs.count,
                phase: phase,
                localNetworkDenied: denied,
                generation: generation,
                interfaceNote: configuration.interfaceNote
            )
            continuation.yield(
                ScanEvent(
                    generation: generation,
                    host: host,
                    progress: progress,
                    isEnrichmentOnly: enrichmentOnly
                )
            )
        }

        emit()

        // Optional Bonjour pre-pass (requires resolved IPv4; hostname-only hits are skipped).
        if preferences.browseBonjour {
            let hits = await deps.bonjour.browse(timeoutMs: min(1500, preferences.connectTimeoutMs * 3))
            for hit in hits {
                if Task.isCancelled || self.currentGeneration != generation { break }
                let record = HostRecord(
                    ip: hit.ip,
                    status: .online,
                    hostname: hit.hostname,
                    evidence: [
                        DiscoveryEvidence(kind: .bonjour, detail: hit.serviceType)
                    ],
                    lastSeen: Date(),
                    firstSeenInScan: Date()
                )
                emit(host: record)
                scheduleEnrichment(
                    ip: hit.ip,
                    preferences: preferences,
                    generation: generation,
                    continuation: continuation,
                    base: record
                )
            }
        }

        // Neighbor cache is enrichment only — refreshed after probes begin, not as sole online proof.
        var neighborRefreshTask: Task<Void, Never>?
        if preferences.lookupNeighbors {
            neighborRefreshTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled, self.currentGeneration == generation else { return }
                await deps.neighbors.refresh()
            }
        }

        await withTaskGroup(of: HostProbeOutcome.self) { group in
            var iterator = addresses.makeIterator()
            let limit = min(preferences.concurrency, max(total, 1))

            func enqueueNext() {
                guard let ip = iterator.next() else { return }
                group.addTask {
                    await Self.discoverHost(
                        ip: ip,
                        preferences: preferences,
                        deps: deps,
                        interface: iface
                    )
                }
            }

            for _ in 0..<min(limit, total) {
                enqueueNext()
            }

            for await outcome in group {
                if Task.isCancelled || self.currentGeneration != generation {
                    phase = .stopping
                    group.cancelAll()
                    break
                }

                completed += 1
                if outcome.localNetworkDenied { denied = true }

                if let host = outcome.host {
                    emit(host: host)
                    scheduleEnrichment(
                        ip: host.ip,
                        preferences: preferences,
                        generation: generation,
                        continuation: continuation,
                        base: host
                    )
                } else {
                    emit()
                }
                enqueueNext()
            }
        }

        neighborRefreshTask?.cancel()

        // Wait briefly for in-flight enrichment unless cancelled.
        if !Task.isCancelled, self.currentGeneration == generation {
            let pending = enrichTasks
            for task in pending {
                _ = await task.result
            }
        } else {
            for task in enrichTasks { task.cancel() }
        }
        enrichTasks.removeAll()

        if Task.isCancelled || self.currentGeneration != generation {
            emit(phaseOverride: .stopped)
        } else {
            emit(phaseOverride: .completed)
        }
        continuation.finish()
    }

    /// Returns false when cancelled while waiting for a slot (caller must not release).
    private func acquireEnrichmentSlot(limit: Int) async -> Bool {
        let capped = max(1, limit)
        if enrichmentRunning < capped {
            enrichmentRunning += 1
            metrics.peakEnrichmentInFlight = max(metrics.peakEnrichmentInFlight, enrichmentRunning)
            return true
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            enrichmentWaiters.append(cont)
        }
        if Task.isCancelled {
            return false
        }
        enrichmentRunning += 1
        metrics.peakEnrichmentInFlight = max(metrics.peakEnrichmentInFlight, enrichmentRunning)
        return true
    }

    private func releaseEnrichmentSlot() {
        enrichmentRunning = max(0, enrichmentRunning - 1)
        if !enrichmentWaiters.isEmpty {
            enrichmentWaiters.removeFirst().resume()
        }
    }

    private func markEnrichmentFinished() {
        metrics.enrichmentFinished += 1
    }

    private func scheduleEnrichment(
        ip: IPv4Address,
        preferences: ScanPreferences,
        generation: UUID,
        continuation: AsyncStream<ScanEvent>.Continuation,
        base: HostRecord
    ) {
        let deps = self.deps
        enrichTasks.removeAll { $0.isCancelled }
        let dnsTimeout = max(preferences.connectTimeoutMs * 3, 500)
        let limit = preferences.enrichmentConcurrency
        metrics.enrichmentStarted += 1
        let task = Task {
            let acquired = await self.acquireEnrichmentSlot(limit: limit)
            defer { Task { await self.markEnrichmentFinished() } }
            guard acquired else { return }
            defer { Task { await self.releaseEnrichmentSlot() } }
            if Task.isCancelled || self.currentGeneration != generation { return }

            var record = base
            if preferences.resolveHostnames, record.hostname == nil {
                // Bound stalled reverse-DNS so enrichment cannot hang a generation forever.
                if let resolved = await withTimeout(milliseconds: dnsTimeout, operation: {
                    await deps.hostnames.reverseDNS(for: ip)
                }) {
                    record.hostname = resolved
                }
            }
            if Task.isCancelled || self.currentGeneration != generation { return }
            if preferences.lookupNeighbors {
                if deps.neighbors.macAddress(for: ip) == nil {
                    await deps.neighbors.refresh()
                }
                if let mac = deps.neighbors.macAddress(for: ip) {
                    record.macAddress = mac
                    if preferences.lookupVendors {
                        record.vendor = deps.vendors.vendor(forMAC: mac)
                    }
                }
            }
            guard !Task.isCancelled, self.currentGeneration == generation else { return }
            let progress = ScanProgress(phase: .running, generation: generation)
            continuation.yield(
                ScanEvent(
                    generation: generation,
                    host: record,
                    progress: progress,
                    isEnrichmentOnly: true
                )
            )
        }
        enrichTasks.append(task)
    }

    private static func discoverHost(
        ip: IPv4Address,
        preferences: ScanPreferences,
        deps: ScanEngineDependencies,
        interface: ScanInterfaceConstraint
    ) async -> HostProbeOutcome {
        if Task.isCancelled {
            return HostProbeOutcome(host: nil, localNetworkDenied: false)
        }

        var evidence: [DiscoveryEvidence] = []
        var services: [DiscoveredService] = []
        var bestLatency: Double?
        var latencyKind: HostRecord.LatencyKind = .none
        var denied = false
        var live = false

        let discoveryPorts = preferences.enabledDiscoveryPorts
        let serviceDefs = preferences.enabledServicePorts
        // Probe union of discovery + enabled service ports, but only list enabled services.
        var portsToProbe = Set(discoveryPorts)
        for service in serviceDefs { portsToProbe.insert(service.port) }

        if preferences.attemptICMP {
            let icmp = await deps.icmp.echo(host: ip, timeoutMs: preferences.connectTimeoutMs)
            if icmp.kind == .open {
                live = true
                bestLatency = icmp.latencyMs
                latencyKind = .icmp
                evidence.append(
                    DiscoveryEvidence(kind: .icmpEcho, detail: "echo", latencyMs: icmp.latencyMs)
                )
            }
        }

        for _ in 0..<preferences.probeRetries {
            if Task.isCancelled { break }
            if live && !serviceDefs.isEmpty {
                // Still enumerate services even if already live via ICMP.
            }
            for port in portsToProbe.sorted() {
                if Task.isCancelled { break }
                let outcome = await deps.tcp.probe(
                    host: ip,
                    port: port,
                    timeoutMs: preferences.connectTimeoutMs,
                    interface: interface
                )
                switch outcome.kind {
                case .localNetworkDenied:
                    denied = true
                case .cancelled:
                    return HostProbeOutcome(host: nil, localNetworkDenied: denied)
                case .open:
                    live = true
                    if let ms = outcome.latencyMs {
                        if bestLatency == nil || ms < bestLatency! {
                            bestLatency = ms
                            latencyKind = .tcpProbe
                        }
                    }
                    evidence.append(
                        DiscoveryEvidence(
                            kind: .tcpOpen,
                            detail: "port \(port)",
                            latencyMs: outcome.latencyMs
                        )
                    )
                    if let configured = serviceDefs.first(where: { $0.port == port }) {
                        services.append(DiscoveredService(name: configured.name, port: port))
                    }
                case .refused:
                    live = true
                    if let ms = outcome.latencyMs {
                        if bestLatency == nil || ms < bestLatency! {
                            bestLatency = ms
                            latencyKind = .tcpProbe
                        }
                    }
                    evidence.append(
                        DiscoveryEvidence(
                            kind: .tcpRefused,
                            detail: "port \(port)",
                            latencyMs: outcome.latencyMs
                        )
                    )
                case .timeout, .error:
                    break
                }
            }
            if live { break }
        }

        guard live else {
            return HostProbeOutcome(host: nil, localNetworkDenied: denied)
        }

        var byPort: [UInt16: DiscoveredService] = [:]
        for service in services { byPort[service.port] = service }

        let now = Date()
        let record = HostRecord(
            ip: ip,
            status: .online,
            responseTimeMs: bestLatency,
            latencyKind: latencyKind,
            services: byPort.values.sorted { $0.port < $1.port },
            evidence: evidence,
            lastSeen: now,
            firstSeenInScan: now
        )
        return HostProbeOutcome(host: record, localNetworkDenied: denied)
    }
}
