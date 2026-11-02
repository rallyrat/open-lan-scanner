import XCTest
@testable import OpenLANScannerCore

final class SecurityAndStressTests: XCTestCase {
    func testCSVFormulaInjectionNeutralized() {
        let host = HostRecord(
            ip: IPv4Address(string: "10.0.0.9")!,
            status: .online,
            hostname: "=cmd|' /C calc'!A0",
            customName: "@SUM(A1)",
            notes: "+2+5"
        )
        let csv = ResultExporter.csv(from: [host])
        XCTAssertTrue(csv.contains("'=cmd|' /C calc'!A0") || csv.contains("\"'=cmd"))
        XCTAssertTrue(csv.contains("'+2+5") || csv.contains("\"'+2+5\""))
        XCTAssertTrue(csv.contains("'@SUM(A1)") || csv.contains("\"'@SUM(A1)\""))
    }

    func testAppleScriptAndShellQuotingHardening() {
        XCTAssertEqual(DeviceActions.shellQuote("abc"), "'abc'")
        XCTAssertEqual(DeviceActions.shellQuote("a'b"), "'a'\\''b'")
        let lit = DeviceActions.appleScriptStringLiteral("say \"hi\"\\there")
        XCTAssertTrue(lit.hasPrefix("\""))
        XCTAssertTrue(lit.hasSuffix("\""))
        XCTAssertTrue(lit.contains("\\\""))
        XCTAssertTrue(lit.contains("\\\\"))
        XCTAssertTrue(DeviceActions.isSafeRemoteUsername("jaiden"))
        XCTAssertTrue(DeviceActions.isSafeRemoteUsername("user.name-1"))
        XCTAssertFalse(DeviceActions.isSafeRemoteUsername("user; rm -rf /"))
        XCTAssertFalse(DeviceActions.isSafeRemoteUsername("a\"b"))
        XCTAssertFalse(DeviceActions.isSafeRemoteUsername(""))
    }

    func testOversizedOUIImportRejectedWithoutClobbering() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ols-oui-stress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Plant a small valid file via parse path only (unit-level size gate).
        let huge = dir.appendingPathComponent("huge.csv")
        // Avoid exhausting RAM: create a sparse-like large file with FileHandle.
        FileManager.default.createFile(atPath: huge.path, contents: nil)
        let handle = try FileHandle(forWritingTo: huge)
        try handle.seek(toOffset: UInt64(OUIVendorLookup.maxImportByteCount) + 1)
        try handle.write(contentsOf: Data([0x0A]))
        try handle.close()

        XCTAssertThrowsError(try OUIVendorLookup.importCSV(from: huge))
    }

    func testCorruptedPreferencesFallBackToDefaults() {
        let defaults = UserDefaults(suiteName: "ols-test-\(UUID().uuidString)")!
        defaults.set(Data("{not-json".utf8), forKey: "scanPreferences")
        let store = UserDefaultsPreferencesStore(defaults: defaults)
        let prefs = store.load()
        XCTAssertEqual(prefs.concurrency, ScanPreferences().concurrency)
        XCTAssertFalse(prefs.services.isEmpty)
    }

    func testDuplicateFavoritesImportSafe() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ols-fav-stress-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let payload = """
        [
          {"ip":{"rawValue":3232235521},"customName":"one","notes":"","createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"},
          {"ip":{"rawValue":3232235521},"customName":"two","notes":"","createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"}
        ]
        """
        try payload.write(to: url, atomically: true, encoding: .utf8)
        let store = FileFavoritesStore(fileURL: url)
        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 1)
    }

    func testRapidCancelAcrossGenerationsDoesNotCrossPollute() async throws {
        let online = (1...20).map { IPv4Address(rawValue: 0x0A000000 + UInt32($0)) }
        var open: [IPv4Address: Set<UInt16>] = [:]
        for ip in online { open[ip] = [80] }
        let tcp = SimulatedTCPProbe(openPorts: open, latencyMs: 30)
        let engine = ScanEngine(
            dependencies: ScanEngineDependencies(
                tcp: tcp,
                icmp: NoOpICMPProbe(),
                bonjour: NoOpBonjourBrowser(),
                neighbors: StaticNeighborTable(),
                hostnames: StallingHostnameResolver(delayMs: 5_000),
                vendors: OUIVendorLookup(prefixes: [:])
            )
        )
        var prefs = ScanPreferences(
            concurrency: 8,
            enrichmentConcurrency: 2,
            connectTimeoutMs: 50,
            resolveHostnames: true,
            attemptICMP: false,
            browseBonjour: false
        )
        prefs.discoveryProbes = [DiscoveryProbeDefinition(port: 80)]
        prefs.services = []

        let first = await engine.scan(addresses: online, preferences: prefs)
        let generationBox = ConcurrentUUIDBox()
        let consumer1 = Task {
            for await event in first {
                if generationBox.value == nil { generationBox.value = event.generation }
                if event.progress.completed >= 3 { break }
            }
            await engine.cancel()
        }
        try await Task.sleep(nanoseconds: 40_000_000)
        await consumer1.value
        let firstGeneration = generationBox.value

        let secondOnline = IPv4Address(string: "10.9.9.9")!
        let tcp2 = SimulatedTCPProbe(openPorts: [secondOnline: [80]], latencyMs: 5)
        let engine2 = ScanEngine(
            dependencies: ScanEngineDependencies(
                tcp: tcp2,
                icmp: NoOpICMPProbe(),
                bonjour: NoOpBonjourBrowser(),
                neighbors: StaticNeighborTable(),
                hostnames: StaticHostnameResolver(mapping: [secondOnline: "fresh.local"]),
                vendors: OUIVendorLookup(prefixes: [:])
            )
        )
        var seenSecond = false
        var foreignEnrichment = false
        for await event in await engine2.scan(addresses: [secondOnline], preferences: prefs) {
            if let host = event.host, host.ip == secondOnline {
                seenSecond = true
            }
            if let firstGeneration, event.generation == firstGeneration {
                foreignEnrichment = true
            }
        }
        XCTAssertTrue(seenSecond)
        XCTAssertFalse(foreignEnrichment)
    }

    func testStalledDNSDoesNotBlockScanCompletion() async throws {
        let ip = IPv4Address(string: "10.8.8.8")!
        let tcp = SimulatedTCPProbe(openPorts: [ip: [80]], latencyMs: 5)
        let engine = ScanEngine(
            dependencies: ScanEngineDependencies(
                tcp: tcp,
                icmp: NoOpICMPProbe(),
                bonjour: NoOpBonjourBrowser(),
                neighbors: StaticNeighborTable(),
                hostnames: StallingHostnameResolver(delayMs: 60_000),
                vendors: OUIVendorLookup(prefixes: [:])
            )
        )
        var prefs = ScanPreferences(
            concurrency: 1,
            enrichmentConcurrency: 1,
            connectTimeoutMs: 100,
            resolveHostnames: true,
            attemptICMP: false,
            browseBonjour: false
        )
        prefs.discoveryProbes = [DiscoveryProbeDefinition(port: 80)]
        prefs.services = []

        let started = Date()
        var completed = false
        for await event in await engine.scan(addresses: [ip], preferences: prefs) {
            if event.progress.phase == .completed {
                completed = true
            }
        }
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertTrue(completed)
        XCTAssertLessThan(elapsed, 5.0, "Stalled DNS must not hang scan completion")
    }

    func testLargeRangeRejectedWithoutMaterializing() {
        XCTAssertThrowsError(try AddressRangeParser.parse("10.0.0.0/8")) { error in
            guard let parseError = error as? AddressParseError,
                  case .tooManyAddresses = parseError
            else {
                return XCTFail("Expected tooManyAddresses, got \(error)")
            }
        }
        // Bounded workload: /24 is allowed and stays within absoluteMaxAddresses.
        XCTAssertNoThrow(try AddressRangeParser.parse("10.0.0.0/24"))
    }
}

/// Never returns in time — used to simulate stalled reverse DNS.
struct StallingHostnameResolver: HostnameResolving {
    var delayMs: Int
    func reverseDNS(for ip: IPv4Address) async -> String? {
        try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
        return "stalled-\(ip.dotted)"
    }
}

/// Mutable box for Swift 5.10 concurrency checking inside `Task` closures.
private final class ConcurrentUUIDBox: @unchecked Sendable {
    var value: UUID?
}
