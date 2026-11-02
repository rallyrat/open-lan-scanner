import XCTest
@testable import OpenLANScannerCore

final class DisplayLabelTests: XCTestCase {
    func testLatencyAndEvidenceUseReadableLabels() {
        XCTAssertEqual(HostRecord.LatencyKind.tcpProbe.displayLabel, "TCP connection")
        XCTAssertEqual(HostRecord.LatencyKind.icmp.displayLabel, "ICMP echo")
        XCTAssertEqual(DiscoveryEvidence.Kind.tcpOpen.displayLabel, "Open TCP port")
        XCTAssertEqual(DiscoveryEvidence.Kind.tcpRefused.displayLabel, "TCP connection refused")

        let host = HostRecord(
            ip: IPv4Address(string: "203.0.113.9")!,
            status: .online,
            responseTimeMs: 12,
            latencyKind: .tcpProbe
        )
        XCTAssertTrue(host.responseSummary.contains("TCP connection"))
        XCTAssertFalse(host.responseSummary.contains("tcpProbe"))
    }

    func testReachabilityLabelsStayUserFacing() {
        XCTAssertEqual(HostReachability.online.displayLabel, "Responded")
        XCTAssertEqual(HostReachability.unknown.displayLabel, "No response")
    }

    func testPersistedColumnWidthsRejectAutoresizeInflation() {
        XCTAssertEqual(TableColumnWidthPolicy.resolved(saved: 708, defaultWidth: 150), 150)
        XCTAssertEqual(TableColumnWidthPolicy.resolved(saved: 180, defaultWidth: 150), 180)
        XCTAssertEqual(TableColumnWidthPolicy.resolved(saved: 0, defaultWidth: 150), 150)
        XCTAssertFalse(TableColumnWidthPolicy.shouldPersist(708))
        XCTAssertTrue(TableColumnWidthPolicy.shouldPersist(180))
    }
}
