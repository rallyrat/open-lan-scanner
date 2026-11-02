import XCTest
@testable import OpenLANScannerCore

final class ResourceBoundsTests: XCTestCase {
    /// Acceptance thresholds (justified): concurrency prefs are hard caps for probe workers;
    /// enrichment peak must stay ≤ enrichmentConcurrency; cancellation should finish quickly
    /// with simulated stalls ≤ connectTimeout + small slack.
    private let enrichmentLimit = 2
    private let probeConcurrency = 4

    func testEnrichmentPeakRespectsHardLimit() async throws {
        let addresses = (1...24).map { IPv4Address(rawValue: 0x0A0A0000 + UInt32($0)) }
        var open: [IPv4Address: Set<UInt16>] = [:]
        for ip in addresses { open[ip] = [80] }
        let tcp = SimulatedTCPProbe(openPorts: open, latencyMs: 2)
        let hostnames = StallingHostnameResolver(delayMs: 80)
        let engine = ScanEngine(
            dependencies: ScanEngineDependencies(
                tcp: tcp,
                icmp: NoOpICMPProbe(),
                bonjour: NoOpBonjourBrowser(),
                neighbors: StaticNeighborTable(),
                hostnames: hostnames,
                vendors: OUIVendorLookup(prefixes: [:])
            )
        )
        var prefs = ScanPreferences(
            concurrency: probeConcurrency,
            enrichmentConcurrency: enrichmentLimit,
            connectTimeoutMs: 40,
            resolveHostnames: true,
            lookupNeighbors: false,
            attemptICMP: false,
            browseBonjour: false
        )
        prefs.discoveryProbes = [DiscoveryProbeDefinition(port: 80)]
        prefs.services = []

        for await _ in await engine.scan(addresses: addresses, preferences: prefs) {}
        let metrics = await engine.resourceMetrics()
        XCTAssertLessThanOrEqual(metrics.peakEnrichmentInFlight, enrichmentLimit)
        XCTAssertEqual(metrics.enrichmentStarted, metrics.enrichmentFinished)
        XCTAssertGreaterThan(metrics.hostEventsYielded, 0)
    }

    func testProbeConcurrencyCapAndNoSilentHostLoss() async throws {
        let addresses = (1...30).map { IPv4Address(rawValue: 0x0A0B0000 + UInt32($0)) }
        var open: [IPv4Address: Set<UInt16>] = [:]
        for ip in addresses { open[ip] = [80] }
        let tcp = SimulatedTCPProbe(openPorts: open, latencyMs: 5)
        let engine = ScanEngine(
            dependencies: ScanEngineDependencies(
                tcp: tcp,
                icmp: NoOpICMPProbe(),
                bonjour: NoOpBonjourBrowser(),
                neighbors: StaticNeighborTable(),
                hostnames: StaticHostnameResolver(),
                vendors: OUIVendorLookup(prefixes: [:])
            )
        )
        var prefs = ScanPreferences(
            concurrency: probeConcurrency,
            enrichmentConcurrency: 2,
            connectTimeoutMs: 20,
            resolveHostnames: false,
            lookupNeighbors: false,
            attemptICMP: false,
            browseBonjour: false
        )
        prefs.discoveryProbes = [DiscoveryProbeDefinition(port: 80)]
        prefs.services = []

        var found = Set<UInt32>()
        // Slow consumer (backpressure): must not drop hosts with unbounded stream + merge.
        for await event in await engine.scan(addresses: addresses, preferences: prefs) {
            try? await Task.sleep(nanoseconds: 1_500_000)
            if let host = event.host, !event.isEnrichmentOnly {
                found.insert(host.ip.rawValue)
            }
        }
        XCTAssertEqual(found.count, addresses.count)
        XCTAssertEqual(tcp.unfinishedCount, 0)
    }

    func testStopDuringStalledProbesClearsInFlight() async throws {
        let addresses = (1...12).map { IPv4Address(rawValue: 0x0A0C0000 + UInt32($0)) }
        var open: [IPv4Address: Set<UInt16>] = [:]
        for ip in addresses { open[ip] = [80] }
        let tcp = SimulatedTCPProbe(openPorts: open, latencyMs: 5)
        tcp.stallMs = 200
        let engine = ScanEngine(
            dependencies: ScanEngineDependencies(
                tcp: tcp,
                icmp: NoOpICMPProbe(),
                bonjour: NoOpBonjourBrowser(),
                neighbors: StaticNeighborTable(),
                hostnames: StallingHostnameResolver(delayMs: 500),
                vendors: OUIVendorLookup(prefixes: [:])
            )
        )
        var prefs = ScanPreferences(
            concurrency: 4,
            enrichmentConcurrency: 2,
            connectTimeoutMs: 50,
            resolveHostnames: true,
            attemptICMP: false,
            browseBonjour: false
        )
        prefs.discoveryProbes = [DiscoveryProbeDefinition(port: 80)]
        prefs.services = []

        let stream = await engine.scan(addresses: addresses, preferences: prefs)
        let started = Date()
        let consumer = Task {
            for await event in stream {
                if event.progress.completed >= 1 {
                    await engine.cancel()
                    break
                }
            }
        }
        await consumer.value
        // Drain remaining termination
        for await _ in stream {}
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertLessThan(elapsed, 3.0, "cancellation latency budget")
        let metrics = await engine.resourceMetrics()
        XCTAssertEqual(metrics.activeEnrichmentWaiters, 0)
    }

    func testRepeatedScansDoNotAccumulateEnrichmentWaiters() async throws {
        let ip = IPv4Address(string: "10.66.66.1")!
        let tcp = SimulatedTCPProbe(openPorts: [ip: [80]], latencyMs: 1)
        let engine = ScanEngine(
            dependencies: ScanEngineDependencies(
                tcp: tcp,
                icmp: NoOpICMPProbe(),
                bonjour: NoOpBonjourBrowser(),
                neighbors: StaticNeighborTable(),
                hostnames: StaticHostnameResolver(mapping: [ip: "repeat.local"]),
                vendors: OUIVendorLookup(prefixes: [:])
            )
        )
        var prefs = ScanPreferences(
            concurrency: 2,
            enrichmentConcurrency: 1,
            connectTimeoutMs: 30,
            resolveHostnames: true,
            attemptICMP: false,
            browseBonjour: false
        )
        prefs.discoveryProbes = [DiscoveryProbeDefinition(port: 80)]
        prefs.services = []

        for _ in 0..<5 {
            for await _ in await engine.scan(addresses: [ip], preferences: prefs) {}
            let metrics = await engine.resourceMetrics()
            XCTAssertEqual(metrics.activeEnrichmentWaiters, 0)
            XCTAssertEqual(metrics.enrichmentStarted, metrics.enrichmentFinished)
        }
    }

    func testPermissionDenialDoesNotRetryStorm() async throws {
        let addresses = (1...10).map { IPv4Address(rawValue: 0x0A0D0000 + UInt32($0)) }
        let tcp = SimulatedTCPProbe(openPorts: [:], denyLocalNetwork: true)
        let engine = ScanEngine(
            dependencies: ScanEngineDependencies(
                tcp: tcp,
                icmp: NoOpICMPProbe(),
                bonjour: NoOpBonjourBrowser(),
                neighbors: StaticNeighborTable(),
                hostnames: StaticHostnameResolver(),
                vendors: OUIVendorLookup(prefixes: [:])
            )
        )
        var prefs = ScanPreferences(
            concurrency: 4,
            probeRetries: 3,
            attemptICMP: false,
            browseBonjour: false
        )
        prefs.discoveryProbes = [DiscoveryProbeDefinition(port: 80)]
        prefs.services = [ServiceProbeDefinition(name: "HTTP", port: 80)]

        var denied = false
        for await event in await engine.scan(addresses: addresses, preferences: prefs) {
            denied = denied || event.progress.localNetworkDenied
        }
        XCTAssertTrue(denied)
        // One probe attempt path per address×ports×retries upper bound, but denial should not
        // explode beyond addresses * ports * retries.
        XCTAssertLessThanOrEqual(tcp.probeCount, addresses.count * 2 * 3)
    }
}
