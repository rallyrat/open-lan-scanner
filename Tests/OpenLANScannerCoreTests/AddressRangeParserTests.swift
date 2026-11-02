import XCTest
@testable import OpenLANScannerCore

final class AddressRangeParserTests: XCTestCase {
    func testParseSingleAddress() throws {
        let result = try AddressRangeParser.parse("192.168.1.10")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.addresses[0].dotted, "192.168.1.10")
    }

    func testParseCIDR24UsableHosts() throws {
        let result = try AddressRangeParser.parse("192.168.1.0/24")
        XCTAssertEqual(result.count, 254)
        XCTAssertEqual(result.addresses.first?.dotted, "192.168.1.1")
        XCTAssertEqual(result.addresses.last?.dotted, "192.168.1.254")
    }

    func testParseCIDR32() throws {
        let result = try AddressRangeParser.parse("10.0.0.5/32")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.addresses[0].dotted, "10.0.0.5")
    }

    func testParseDashRangeShortForm() throws {
        let result = try AddressRangeParser.parse("192.168.1.10-12")
        XCTAssertEqual(result.addresses.map(\.dotted), [
            "192.168.1.10", "192.168.1.11", "192.168.1.12"
        ])
    }

    func testParseFullDashRange() throws {
        let result = try AddressRangeParser.parse("10.0.0.1-10.0.0.3")
        XCTAssertEqual(result.count, 3)
    }

    func testParseCommaSeparatedDedupes() throws {
        let result = try AddressRangeParser.parse("192.168.0.1, 192.168.0.1, 192.168.0.2")
        XCTAssertEqual(result.count, 2)
    }

    func testInvalidAddress() {
        XCTAssertThrowsError(try AddressRangeParser.parse("192.168.1.999"))
    }

    func testInvertedRange() {
        XCTAssertThrowsError(try AddressRangeParser.parse("192.168.1.20-10")) { error in
            guard let parsed = error as? AddressParseError,
                  case .invertedRange = parsed
            else {
                return XCTFail("expected invertedRange")
            }
        }
    }

    func testEmpty() {
        XCTAssertThrowsError(try AddressRangeParser.parse("  "))
    }

    func testAbsoluteLimit() {
        XCTAssertThrowsError(
            try AddressRangeParser.parse("10.0.0.0/16", absoluteLimit: 100)
        ) { error in
            guard let parsed = error as? AddressParseError,
                  case .tooManyAddresses = parsed
            else {
                return XCTFail("expected tooManyAddresses")
            }
        }
    }

    func testNumericIPSorting() {
        let addresses = [
            IPv4Address(string: "10.0.0.10")!,
            IPv4Address(string: "10.0.0.2")!,
            IPv4Address(string: "10.0.0.1")!
        ].sorted()
        XCTAssertEqual(addresses.map(\.dotted), ["10.0.0.1", "10.0.0.2", "10.0.0.10"])
    }

    func testClassCHelper() {
        let ip = IPv4Address(string: "172.16.5.40")!
        let bounds = AddressRangeParser.classCRange(containing: ip)
        XCTAssertEqual(bounds.start.dotted, "172.16.5.0")
        XCTAssertEqual(bounds.end.dotted, "172.16.5.255")
    }

    func testSubnetPrefix() throws {
        let ip = IPv4Address(string: "192.168.10.50")!
        let bounds = try AddressRangeParser.subnet(address: ip, prefixLength: 24)
        XCTAssertEqual(bounds.start.dotted, "192.168.10.0")
        XCTAssertEqual(bounds.end.dotted, "192.168.10.255")
    }
}
