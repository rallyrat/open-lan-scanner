import XCTest
@testable import OpenLANScannerCore

final class ExportAndFavoritesTests: XCTestCase {
    func testCSVEscaping() {
        let host = HostRecord(
            ip: IPv4Address(string: "10.0.0.1")!,
            status: .online,
            hostname: "host, \"name\"",
            notes: "line1\nline2"
        )
        let csv = ResultExporter.csv(from: [host])
        XCTAssertTrue(csv.contains("\"host, \"\"name\"\"\""))
        XCTAssertTrue(csv.contains("\"line1\nline2\""))
        XCTAssertTrue(csv.hasPrefix("status,ip,hostname"))
    }

    func testJSONExportRoundTripShape() throws {
        let host = HostRecord(
            ip: IPv4Address(string: "10.0.0.2")!,
            status: .online,
            macAddress: "AA:BB:CC:DD:EE:FF",
            responseTimeMs: 4.5,
            latencyKind: .tcpProbe,
            services: [DiscoveredService(name: "SSH", port: 22)]
        )
        let data = try ResultExporter.json(from: [host])
        let decoded = try JSONDecoder().decode([HostRecord].self, from: data)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].ip.dotted, "10.0.0.2")
        XCTAssertEqual(decoded[0].services.first?.port, 22)
    }

    func testFavoritesPersistence() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ols-fav-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = FileFavoritesStore(fileURL: url)
        let favorite = FavoriteDevice(
            ip: IPv4Address(string: "192.168.1.50")!,
            macAddress: "11:22:33:44:55:66",
            customName: "NAS",
            notes: "Basement"
        )
        try store.save([favorite])
        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].customName, "NAS")
        XCTAssertEqual(loaded[0].macAddress, "11:22:33:44:55:66")
    }

    func testWakeOnLANMagicPacket() throws {
        let packet = try WakeOnLAN.magicPacket(mac: "01:23:45:67:89:ab")
        XCTAssertEqual(packet.count, 102)
        XCTAssertEqual(Array(packet.prefix(6)), Array(repeating: 0xFF, count: 6))
        XCTAssertEqual(Array(packet[6..<12]), [0x01, 0x23, 0x45, 0x67, 0x89, 0xAB])
    }

    func testOUIVendorLookup() {
        let lookup = OUIVendorLookup(prefixes: ["001A2B": "Ayecom Technology Co., Ltd."])
        XCTAssertEqual(lookup.vendor(forMAC: "00:1a:2b:11:22:33"), "Ayecom Technology Co., Ltd.")
        // ff:... is locally administered (U/L bit), so vendor returns the LAA explanation.
        XCTAssertEqual(
            lookup.vendor(forMAC: "ff:ff:ff:00:00:00"),
            "Locally administered / randomized MAC"
        )
        XCTAssertNil(lookup.vendor(forMAC: "00:11:22:33:44:55"))
    }

    func testHostRecordMergeDoesNotFabricate() {
        var base = HostRecord(ip: IPv4Address(string: "10.0.0.9")!, status: .online)
        let other = HostRecord(
            ip: IPv4Address(string: "10.0.0.9")!,
            status: .online,
            hostname: "box",
            services: [DiscoveredService(name: "HTTP", port: 80)]
        )
        base.merge(other)
        XCTAssertEqual(base.hostname, "box")
        XCTAssertNil(base.macAddress)
        XCTAssertEqual(base.services.count, 1)
    }
}
