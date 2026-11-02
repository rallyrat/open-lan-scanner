import XCTest
@testable import OpenLANScannerCore

final class ScanEngineTests: XCTestCase {
    func testBoundedDiscoveryAndDedup() async throws {
        let onlineA = IPv4Address(string: "192.168.1.10")!
        let onlineB = IPv4Address(string: "192.168.1.20")!
        let offline = IPv4Address(string: "192.168.1.30")!

        let tcp = SimulatedTCPProbe(openPorts: [
            onlineA: [80, 22],
            onlineB: [445]
        ], latencyMs: 12)

        let neighbors = StaticNeighborTable(mapping: [
            onlineA: "00:1A:2B:00:00:01"
        ])
        let hostnames = StaticHostnameResolver(mapping: [
            onlineA: "alpha.local"
        ])
        let vendors = OUIVendorLookup(prefixes: ["001A2B": "Apple, Inc."])

        let engine = ScanEngine(
            dependencies: ScanEngineDependencies(
                tcp: tcp,
                icmp: NoOpICMPProbe(),
                bonjour: NoOpBonjourBrowser(),
                neighbors: neighbors,
                hostnames: hostnames,
                vendors: vendors
            )
        )

        var prefs = ScanPreferences(
            concurrency: 4,
            connectTimeoutMs: 100,
            attemptICMP: false,
            browseBonjour: false
        )
        prefs.services = [
            ServiceProbeDefinition(name: "SSH", port: 22),
            ServiceProbeDefinition(name: "HTTP", port: 80),
            ServiceProbeDefinition(name: "SMB", port: 445)
        ]

        let uniqueAddresses = [onlineA, onlineB, offline].sorted()

        var found: [IPv4Address: HostRecord] = [:]
        var finalProgress: ScanProgress?

        let stream = await engine.scan(addresses: uniqueAddresses, preferences: prefs)
        for await event in stream {
            if let host = event.host {
                if var existing = found[host.ip] {
                    existing.merge(host)
                    found[host.ip] = existing
                } else {
                    found[host.ip] = host
                }
            }
            if !event.isEnrichmentOnly {
                finalProgress = event.progress
            }
        }

        XCTAssertEqual(found.count, 2)
        XCTAssertEqual(found[onlineA]?.hostname, "alpha.local")
        XCTAssertEqual(found[onlineA]?.macAddress, "00:1A:2B:00:00:01")
        XCTAssertEqual(found[onlineA]?.vendor, "Apple, Inc.")
        XCTAssertEqual(found[onlineA]?.latencyKind, .tcpProbe)
        XCTAssertTrue(found[onlineA]?.services.contains(where: { $0.port == 22 }) == true)
        XCTAssertNil(found[offline])
        XCTAssertEqual(finalProgress?.onlineCount, 2)
        XCTAssertEqual(finalProgress?.phase, .completed)
        XCTAssertEqual(finalProgress?.completed, 3)
    }

    func testTCPRefusalCountsAsLiveWithoutOpenService() async throws {
        let ip = IPv4Address(string: "10.9.9.9")!
        let tcp = SimulatedTCPProbe(openPorts: [:], refusedPorts: [ip: [80]])
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
        var prefs = ScanPreferences(concurrency: 1, attemptICMP: false, browseBonjour: false)
        prefs.services = [ServiceProbeDefinition(name: "HTTP", port: 80, enabled: true)]
        prefs.discoveryProbes = [DiscoveryProbeDefinition(port: 80, enabled: true)]

        var host: HostRecord?
        let stream = await engine.scan(addresses: [ip], preferences: prefs)
        for await event in stream {
            host = event.host ?? host
        }
        XCTAssertEqual(host?.status, .online)
        XCTAssertTrue(host?.services.isEmpty == true)
        XCTAssertTrue(host?.evidence.contains(where: { $0.kind == .tcpRefused }) == true)
    }

    func testDisabledServicePortNotListedEvenIfDiscoveryHits() async throws {
        let ip = IPv4Address(string: "10.8.8.8")!
        let tcp = SimulatedTCPProbe(openPorts: [ip: [548]])
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
        var prefs = ScanPreferences(concurrency: 1, attemptICMP: false, browseBonjour: false)
        prefs.services = [ServiceProbeDefinition(name: "AFP", port: 548, enabled: false)]
        prefs.discoveryProbes = [DiscoveryProbeDefinition(port: 548, enabled: true)]

        var host: HostRecord?
        for await event in await engine.scan(addresses: [ip], preferences: prefs) {
            host = event.host ?? host
        }
        XCTAssertEqual(host?.status, .online)
        XCTAssertTrue(host?.services.isEmpty == true)
    }

    func testInterfacePropagatedToTransport() async throws {
        let ip = IPv4Address(string: "10.1.2.3")!
        let tcp = SimulatedTCPProbe(openPorts: [ip: [80]])
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
        var prefs = ScanPreferences(concurrency: 1, attemptICMP: false, browseBonjour: false)
        prefs.discoveryProbes = [DiscoveryProbeDefinition(port: 80)]
        let constraint = ScanInterfaceConstraint(bsdName: "en0", ipv4: IPv4Address(string: "10.1.2.1"))
        let stream = await engine.scan(
            configuration: ScanConfiguration(
                addresses: [ip],
                preferences: prefs,
                interface: constraint,
                interfaceNote: "Wi-Fi (en0)"
            )
        )
        for await _ in stream {}
        XCTAssertEqual(tcp.lastInterface?.bsdName, "en0")
    }

    func testCancellationStopsWork() async throws {
        let tcp = SimulatedTCPProbe(openPorts: [:], latencyMs: 1)
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

        let addresses = (1...200).compactMap { IPv4Address(string: "10.0.0.\($0)") }
        var prefs = ScanPreferences(concurrency: 8, connectTimeoutMs: 50, attemptICMP: false, browseBonjour: false)
        prefs.discoveryProbes = [DiscoveryProbeDefinition(port: 80)]
        let stream = await engine.scan(addresses: addresses, preferences: prefs)

        var sawProgress = false
        var stoppedPhase: ScanPhase?
        let consumer = Task {
            for await event in stream {
                sawProgress = true
                if event.progress.completed >= 2 {
                    await engine.cancel()
                }
                if event.progress.isFinished {
                    stoppedPhase = event.progress.phase
                }
            }
        }
        await consumer.value
        XCTAssertTrue(sawProgress)
        XCTAssertLessThan(tcp.probeCount, 200 * 10)
        XCTAssertEqual(stoppedPhase, .stopped)
    }

    func testSlowConsumerDoesNotDropHosts() async throws {
        // Many hosts, tiny consumer delay — unbounded buffer must retain discoveries.
        var open: [IPv4Address: Set<UInt16>] = [:]
        let addresses: [IPv4Address] = (1...40).compactMap {
            let ip = IPv4Address(string: "10.2.0.\($0)")!
            open[ip] = [80]
            return ip
        }
        let tcp = SimulatedTCPProbe(openPorts: open)
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
        var prefs = ScanPreferences(concurrency: 8, connectTimeoutMs: 20, attemptICMP: false, browseBonjour: false)
        prefs.discoveryProbes = [DiscoveryProbeDefinition(port: 80)]
        prefs.services = []

        var found = Set<UInt32>()
        let stream = await engine.scan(addresses: addresses, preferences: prefs)
        for await event in stream {
            try? await Task.sleep(nanoseconds: 2_000_000)
            if let host = event.host, !event.isEnrichmentOnly {
                found.insert(host.ip.rawValue)
            }
        }
        XCTAssertEqual(found.count, 40)
    }

    func testPartialResultsWithoutMAC() async throws {
        let ip = IPv4Address(string: "10.1.1.5")!
        let tcp = SimulatedTCPProbe(openPorts: [ip: [443]])
        let engine = ScanEngine(
            dependencies: ScanEngineDependencies(
                tcp: tcp,
                icmp: NoOpICMPProbe(),
                bonjour: NoOpBonjourBrowser(),
                neighbors: StaticNeighborTable(mapping: [:]),
                hostnames: StaticHostnameResolver(),
                vendors: OUIVendorLookup(prefixes: [:])
            )
        )
        var prefs = ScanPreferences(
            concurrency: 1,
            resolveHostnames: false,
            attemptICMP: false,
            browseBonjour: false
        )
        let stream = await engine.scan(addresses: [ip], preferences: prefs)
        var host: HostRecord?
        for await event in stream {
            host = event.host ?? host
        }
        XCTAssertEqual(host?.status, .online)
        XCTAssertNil(host?.macAddress)
        XCTAssertNil(host?.vendor)
        XCTAssertNil(host?.hostname)
    }

    func testLocalNetworkDeniedFlag() async throws {
        let ip = IPv4Address(string: "192.168.0.2")!
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
        let stream = await engine.scan(
            addresses: [ip],
            preferences: ScanPreferences(concurrency: 1, attemptICMP: false, browseBonjour: false)
        )
        var denied = false
        for await event in stream {
            denied = denied || event.progress.localNetworkDenied
        }
        XCTAssertTrue(denied)
    }

    func testICMPDiscoveryWithoutOpenTCP() async throws {
        let ip = IPv4Address(string: "10.7.7.7")!
        let tcp = SimulatedTCPProbe(openPorts: [:])
        let icmp = SimulatedICMPProbe(responsive: [ip])
        let engine = ScanEngine(
            dependencies: ScanEngineDependencies(
                tcp: tcp,
                icmp: icmp,
                bonjour: NoOpBonjourBrowser(),
                neighbors: StaticNeighborTable(),
                hostnames: StaticHostnameResolver(),
                vendors: OUIVendorLookup(prefixes: [:])
            )
        )
        var prefs = ScanPreferences(concurrency: 1, attemptICMP: true, browseBonjour: false)
        prefs.discoveryProbes = [DiscoveryProbeDefinition(port: 80, enabled: true)]
        var host: HostRecord?
        for await event in await engine.scan(addresses: [ip], preferences: prefs) {
            host = event.host ?? host
        }
        XCTAssertEqual(host?.status, .online)
        XCTAssertEqual(host?.latencyKind, .icmp)
        XCTAssertTrue(host?.evidence.contains(where: { $0.kind == .icmpEcho }) == true)
    }
}
