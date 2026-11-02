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
                neighbors: neighbors,
                hostnames: hostnames,
                vendors: vendors
            )
        )

        var prefs = ScanPreferences(concurrency: 4, connectTimeoutMs: 100)
        prefs.services = [
            ServiceProbeDefinition(name: "SSH", port: 22),
            ServiceProbeDefinition(name: "HTTP", port: 80),
            ServiceProbeDefinition(name: "SMB", port: 445)
        ]

        let addresses = [onlineA, onlineB, offline, onlineA] // intentional duplicate input ignored by caller
        var uniqueAddresses = Array(Set(addresses)).sorted()

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
            finalProgress = event.progress
        }

        XCTAssertEqual(found.count, 2)
        XCTAssertEqual(found[onlineA]?.hostname, "alpha.local")
        XCTAssertEqual(found[onlineA]?.macAddress, "00:1A:2B:00:00:01")
        XCTAssertEqual(found[onlineA]?.vendor, "Apple, Inc.")
        XCTAssertEqual(found[onlineA]?.latencyKind, .tcpProbe)
        XCTAssertTrue(found[onlineA]?.services.contains(where: { $0.port == 22 }) == true)
        XCTAssertNil(found[offline])
        XCTAssertEqual(finalProgress?.onlineCount, 2)
        XCTAssertEqual(finalProgress?.isFinished, true)
        XCTAssertEqual(finalProgress?.completed, 3)
    }

    func testCancellationStopsWork() async throws {
        let tcp = SimulatedTCPProbe(openPorts: [:], latencyMs: 1)
        let engine = ScanEngine(
            dependencies: ScanEngineDependencies(
                tcp: tcp,
                neighbors: StaticNeighborTable(),
                hostnames: StaticHostnameResolver(),
                vendors: OUIVendorLookup(prefixes: [:])
            )
        )

        let addresses = (1...200).compactMap { IPv4Address(string: "10.0.0.\($0)") }
        let stream = await engine.scan(addresses: addresses, preferences: ScanPreferences(concurrency: 8, connectTimeoutMs: 50))

        var sawProgress = false
        let consumer = Task {
            for await event in stream {
                sawProgress = true
                if event.progress.completed >= 2 {
                    await engine.cancel()
                }
            }
        }
        await consumer.value
        XCTAssertTrue(sawProgress)
        // Probe count should be well below 200 * ports if cancellation worked.
        XCTAssertLessThan(tcp.probeCount, 200 * 10)
    }

    func testPartialResultsWithoutMAC() async throws {
        let ip = IPv4Address(string: "10.1.1.5")!
        let tcp = SimulatedTCPProbe(openPorts: [ip: [443]])
        let engine = ScanEngine(
            dependencies: ScanEngineDependencies(
                tcp: tcp,
                neighbors: StaticNeighborTable(mapping: [:]),
                hostnames: StaticHostnameResolver(),
                vendors: OUIVendorLookup(prefixes: [:])
            )
        )
        let stream = await engine.scan(
            addresses: [ip],
            preferences: ScanPreferences(concurrency: 1, resolveHostnames: false)
        )
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
                neighbors: StaticNeighborTable(),
                hostnames: StaticHostnameResolver(),
                vendors: OUIVendorLookup(prefixes: [:])
            )
        )
        let stream = await engine.scan(addresses: [ip], preferences: ScanPreferences(concurrency: 1))
        var denied = false
        for await event in stream {
            denied = denied || event.progress.localNetworkDenied
        }
        XCTAssertTrue(denied)
    }
}
