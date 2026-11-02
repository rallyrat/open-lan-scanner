import XCTest
@testable import OpenLANScannerCore

final class HardeningVerificationTests: XCTestCase {
    func testShellQuoteAndAppleScriptEscapingAreIndependent() {
        let nasty = "a'b\"c\\d\ne"
        let shell = DeviceActions.shellQuote(nasty)
        XCTAssertEqual(shell.first, "'")
        XCTAssertEqual(shell.last, "'")
        XCTAssertFalse(shell.contains("\\\""), "shell quoting must not AppleScript-escape quotes")

        let asLit = DeviceActions.appleScriptStringLiteral(nasty)
        XCTAssertTrue(asLit.hasPrefix("\""))
        XCTAssertTrue(asLit.contains("\\\""))
        XCTAssertTrue(asLit.contains("\\\\"))
        XCTAssertTrue(asLit.contains("\\n"))
        XCTAssertFalse(asLit.hasPrefix("'"), "AppleScript literal is double-quoted, not shell-quoted")
    }

    func testMaliciousUsernamesRejected() {
        let bad = [
            "root;id",
            "user`id`",
            "user$(id)",
            "user|id",
            "user&id",
            "user\nid",
            "user\"id",
            "user'id",
            String(repeating: "a", count: 65)
        ]
        for name in bad {
            XCTAssertFalse(DeviceActions.isSafeRemoteUsername(name), name)
        }
    }

    func testCSVWhitespaceAndControlFormulaPrefixes() throws {
        let cases = ["=1+1", " =1+1", "\t=1+1", "\u{feff}=1+1", "+1", "-1", "@SUM(A1)"]
        for value in cases {
            let escaped = ResultExporter.escapeCSV(value)
            XCTAssertTrue(escaped.hasPrefix("'") || escaped.hasPrefix("\"'"), value)
        }

        let host = HostRecord(
            ip: IPv4Address(string: "10.0.0.3")!,
            status: .online,
            hostname: " =cmd",
            customName: "ok-name",
            notes: "plain"
        )
        let csv = ResultExporter.csv(from: [host])
        XCTAssertTrue(csv.contains("' =cmd") || csv.contains("\"' =cmd\""))

        // JSON export must preserve original values (no silent CSV mutation).
        let data = try ResultExporter.json(from: [host])
        let decoded = try JSONDecoder().decode([HostRecord].self, from: data)
        XCTAssertEqual(decoded[0].hostname, " =cmd")
        XCTAssertEqual(decoded[0].customName, "ok-name")
    }

    func testOUIImportSizeCheckedBeforeContentParse() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ols-oui-verify-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let valid = dir.appendingPathComponent("good.csv")
        try "Assignment,Organization\n001122,Test Org\n".write(to: valid, atomically: true, encoding: .utf8)

        // Oversized empty-ish file: attributes.size exceeds cap before String(contentsOf:).
        let huge = dir.appendingPathComponent("huge.csv")
        FileManager.default.createFile(atPath: huge.path, contents: nil)
        let handle = try FileHandle(forWritingTo: huge)
        try handle.seek(toOffset: UInt64(OUIVendorLookup.maxImportByteCount) + 8)
        try handle.write(contentsOf: Data([0x41, 0x0A]))
        try handle.close()

        XCTAssertThrowsError(try OUIVendorLookup.importCSV(from: huge))
    }

    func testGitHubActionsAreCommitPinned() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let files = [
            root.appendingPathComponent(".github/workflows/ci.yml"),
            root.appendingPathComponent(".github/workflows/release.yml")
        ]
        let usesRegex = try NSRegularExpression(pattern: #"uses:\s*([^\s]+)"#)
        let shaRegex = try NSRegularExpression(pattern: #"^[0-9a-f]{40}$"#)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let ns = text as NSString
            let matches = usesRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            XCTAssertFalse(matches.isEmpty, file.lastPathComponent)
            for match in matches {
                let value = ns.substring(with: match.range(at: 1))
                // Ignore local reusable workflows if any.
                if value.hasPrefix("./") { continue }
                let parts = value.split(separator: "@", maxSplits: 1)
                XCTAssertEqual(parts.count, 2, "Action ref must include @: \(value)")
                let ref = String(parts[1])
                let shaRange = NSRange(location: 0, length: (ref as NSString).length)
                XCTAssertEqual(
                    shaRegex.numberOfMatches(in: ref, range: shaRange),
                    1,
                    "Action must be pinned to 40-char SHA: \(value) in \(file.lastPathComponent)"
                )
            }
        }
    }
}
