import Foundation

public protocol VendorLooking: Sendable {
    func vendor(forMAC mac: String) -> String?
}

public struct OUIVendorLookup: VendorLooking {
    private let prefixes: [String: String]

    public init(prefixes: [String: String]) {
        self.prefixes = prefixes
    }

    public static func loadBundledSample() -> OUIVendorLookup {
        if let url = Bundle.module.url(forResource: "oui-sample", withExtension: "csv", subdirectory: nil)
            ?? Bundle.module.url(forResource: "oui-sample", withExtension: "csv", subdirectory: "OUI"),
           let lookup = try? OUIVendorLookup(contentsOf: url) {
            return lookup
        }
        // Fallback embedded commons if resource missing during tests.
        return OUIVendorLookup(prefixes: [
            "001A2B": "Apple, Inc.",
            "B827EB": "Raspberry Pi Foundation",
            "000C29": "VMware, Inc.",
            "525400": "QEMU virtual NIC"
        ])
    }

    public init(contentsOf url: URL) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        self.prefixes = Self.parseCSV(text)
    }

    public func vendor(forMAC mac: String) -> String? {
        let hex = mac.uppercased().filter { $0.isHexDigit }
        guard hex.count >= 6 else { return nil }
        let oui24 = String(hex.prefix(6))
        if let name = prefixes[oui24] { return name }
        // MA-M / longer prefixes if present
        if hex.count >= 7 {
            let key7 = String(hex.prefix(7))
            if let name = prefixes[key7] { return name }
        }
        if hex.count >= 9 {
            let key9 = String(hex.prefix(9))
            if let name = prefixes[key9] { return name }
        }
        return nil
    }

    public static func parseCSV(_ text: String) -> [String: String] {
        var map: [String: String] = [:]
        for (index, line) in text.split(whereSeparator: \.isNewline).enumerated() {
            let raw = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.isEmpty { continue }
            if index == 0 && raw.lowercased().contains("assignment") { continue }

            // Support "XXXXXX,Vendor" and IEEE-style quoted CSV.
            let columns = splitCSVLine(raw)
            guard columns.count >= 2 else { continue }
            let assignment = columns[0].uppercased().filter { $0.isHexDigit }
            let org = columns[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard assignment.count >= 6, !org.isEmpty else { continue }
            map[String(assignment.prefix(6))] = org
        }
        return map
    }

    private static func splitCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        for ch in line {
            if ch == "\"" {
                inQuotes.toggle()
                continue
            }
            if ch == "," && !inQuotes {
                fields.append(current)
                current = ""
                continue
            }
            current.append(ch)
        }
        fields.append(current)
        return fields
    }
}
