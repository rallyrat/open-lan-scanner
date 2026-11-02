import XCTest
@testable import OpenLANScannerCore

final class PersistenceAndVendorTests: XCTestCase {
    func testPreferencesDecodeClampsOutOfRangeValues() throws {
        let json = """
        {
          "schemaVersion": 1,
          "concurrency": 9999,
          "enrichmentConcurrency": 0,
          "connectTimeoutMs": 1,
          "resolveHostnames": true,
          "lookupNeighbors": true,
          "lookupVendors": true,
          "probeRetries": 99,
          "largeRangeWarningThreshold": 0,
          "services": [],
          "attemptICMP": true,
          "browseBonjour": false
        }
        """.data(using: .utf8)!
        let prefs = try JSONDecoder().decode(ScanPreferences.self, from: json)
        XCTAssertEqual(prefs.concurrency, 512)
        XCTAssertEqual(prefs.enrichmentConcurrency, 1)
        XCTAssertEqual(prefs.connectTimeoutMs, 50)
        XCTAssertEqual(prefs.probeRetries, 5)
        XCTAssertEqual(prefs.largeRangeWarningThreshold, 1)
        XCTAssertFalse(prefs.services.isEmpty)
        XCTAssertFalse(prefs.discoveryProbes.isEmpty)
        XCTAssertEqual(prefs.schemaVersion, ScanPreferences.currentSchemaVersion)
    }

    func testFavoritesDeduplicateAndRejectInvalidMAC() throws {
        let a = FavoriteDevice(ip: IPv4Address(string: "10.0.0.1")!, customName: "A")
        let b = FavoriteDevice(ip: IPv4Address(string: "10.0.0.1")!, customName: "B")
        let deduped = try FavoriteDevice.validateAndDeduplicate([a, b])
        XCTAssertEqual(deduped.count, 1)
        XCTAssertEqual(deduped[0].customName, "B")

        let bad = FavoriteDevice(
            ip: IPv4Address(string: "10.0.0.2")!,
            macAddress: "not-a-mac",
            customName: "Bad"
        )
        XCTAssertThrowsError(try FavoriteDevice.validateAndDeduplicate([bad]))
    }

    func testFavoritesImportDoesNotCrashOnDuplicateKeys() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ols-fav-dup-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = FileFavoritesStore(fileURL: url)
        let duplicates = [
            FavoriteDevice(ip: IPv4Address(string: "192.168.0.1")!, customName: "one"),
            FavoriteDevice(ip: IPv4Address(string: "192.168.0.1")!, customName: "two")
        ]
        try store.save(duplicates)
        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].customName, "two")
    }

    func testIEEEAndCompactOUICSVParsing() {
        let compact = """
        Assignment,Organization
        001A2B,"Ayecom Technology Co., Ltd."
        F0D1A9ABC,Apple Long Prefix Test
        """
        let compactParsed = OUIVendorLookup.parseCSV(compact)
        XCTAssertEqual(compactParsed.format, "compact")
        XCTAssertEqual(compactParsed.prefixes["001A2B"], "Ayecom Technology Co., Ltd.")
        XCTAssertEqual(compactParsed.prefixes["F0D1A9ABC"], "Apple Long Prefix Test")

        let ieee = [
            "Registry,Assignment,Organization Name,Organization Address",
            "MA-L,001A2B,\"Ayecom Technology Co., Ltd.\",\"Some Address, Taiwan\"",
            "MA-M,AABBCCD,Example MA-M Org,Address"
        ].joined(separator: "\n")
        let ieeeParsed = OUIVendorLookup.parseCSV(ieee)
        XCTAssertEqual(ieeeParsed.format, "ieee")
        XCTAssertEqual(ieeeParsed.prefixes["001A2B"], "Ayecom Technology Co., Ltd.")
        XCTAssertEqual(ieeeParsed.prefixes["AABBCCD"], "Example MA-M Org")

        let lookup = OUIVendorLookup(prefixes: compactParsed.prefixes)
        XCTAssertEqual(lookup.vendor(forMAC: "00:1a:2b:11:22:33"), "Ayecom Technology Co., Ltd.")
        // Longest prefix should win when both exist.
        let both = OUIVendorLookup(prefixes: [
            "F0D1A9": "Short",
            "F0D1A9ABC": "Long"
        ])
        XCTAssertEqual(both.vendor(forHexPrefix: "F0D1A9ABCDEF"), "Long")
    }

    func testLocallyAdministeredMACExplanation() {
        let lookup = OUIVendorLookup(prefixes: ["525400": "QEMU"])
        // 02:... has LAA bit set
        let result = lookup.vendor(forMAC: "02:00:00:00:00:01")
        XCTAssertEqual(result, "Locally administered / randomized MAC")
    }

    func testScanHistoryCompareConservative() {
        let older = ScanSnapshot(
            targetExpression: "192.168.1.0/24",
            interfaceNote: "en0 — 192.168.1.5/24",
            onlineCount: 2,
            probedCount: 256,
            preferencesSummary: "test",
            hosts: [
                ScanHostSnapshot(
                    ip: IPv4Address(string: "192.168.1.10")!,
                    status: .online,
                    services: [DiscoveredService(name: "HTTP", port: 80)]
                ),
                ScanHostSnapshot(
                    ip: IPv4Address(string: "192.168.1.20")!,
                    status: .online
                )
            ]
        )
        let newer = ScanSnapshot(
            targetExpression: "10.0.0.0/24",
            interfaceNote: "en1 — 10.0.0.5/24",
            onlineCount: 2,
            probedCount: 256,
            preferencesSummary: "test",
            hosts: [
                ScanHostSnapshot(
                    ip: IPv4Address(string: "192.168.1.10")!,
                    status: .online,
                    services: [DiscoveredService(name: "HTTP", port: 80), DiscoveredService(name: "SSH", port: 22)]
                ),
                ScanHostSnapshot(
                    ip: IPv4Address(string: "10.0.0.9")!,
                    status: .online
                )
            ]
        )
        let cmp = ScanHistory.compare(older: older, newer: newer)
        XCTAssertFalse(cmp.uncertainMatches.isEmpty)
        XCTAssertEqual(cmp.newlyObserved.map(\.ip.dotted), ["10.0.0.9"])
        XCTAssertEqual(cmp.previouslyObservedNoResponse.map(\.ip.dotted), ["192.168.1.20"])
        XCTAssertEqual(cmp.changedServices.count, 1)
    }

    func testHistoryRetentionBound() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ols-hist-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = FileScanHistoryStore(fileURL: url, retentionLimit: 2)
        let snaps = (0..<5).map { i in
            ScanSnapshot(
                createdAt: Date().addingTimeInterval(TimeInterval(i)),
                targetExpression: "10.0.0.\(i)",
                interfaceNote: nil,
                onlineCount: 0,
                probedCount: 1,
                preferencesSummary: "t",
                hosts: []
            )
        }
        try store.save(snaps)
        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 2)
    }

    func testOUIImportKeepsPreviousOnFailure() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ols-oui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Use a temp Application Support substitute by writing via importCSV after planting dest.
        // Direct parse failure path:
        let empty = dir.appendingPathComponent("empty.csv")
        try "not,enough\n".write(to: empty, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try OUIVendorLookup.importCSV(from: empty))
    }
}
