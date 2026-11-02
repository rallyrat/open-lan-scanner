import Foundation

public protocol VendorLooking: Sendable {
    func vendor(forMAC mac: String) -> String?
}

public struct MACAddressInfo: Sendable, Equatable {
    public var normalized: String // AA:BB:CC:DD:EE:FF
    public var hex: String // AABBCCDDEEFF
    public var isLocallyAdministered: Bool
    public var isMulticast: Bool

    public var randomizedOrLocalDescription: String? {
        guard isLocallyAdministered else { return nil }
        return "Locally administered / randomized MAC"
    }
}

public enum MACAddressParsing {
    public static func parse(_ mac: String) -> MACAddressInfo? {
        let hex = mac.uppercased().filter(\.isHexDigit)
        guard hex.count == 12 else { return nil }
        var bytes: [UInt8] = []
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2)
            guard let b = UInt8(hex[idx..<next], radix: 16) else { return nil }
            bytes.append(b)
            idx = next
        }
        let first = bytes[0]
        let normalized = bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
        return MACAddressInfo(
            normalized: normalized,
            hex: hex,
            isLocallyAdministered: (first & 0x02) != 0,
            isMulticast: (first & 0x01) != 0
        )
    }
}

public struct OUIDatasetMetadata: Sendable, Equatable, Codable {
    public var source: String
    public var importedAt: Date?
    public var entryCount: Int
    public var format: String

    public init(source: String, importedAt: Date? = nil, entryCount: Int, format: String) {
        self.source = source
        self.importedAt = importedAt
        self.entryCount = entryCount
        self.format = format
    }
}

public struct OUIVendorLookup: VendorLooking {
    /// Maps OUI hex prefix (no separators, uppercase) → organization. Longer keys win.
    private let prefixes: [String: String]
    public let metadata: OUIDatasetMetadata

    public init(prefixes: [String: String], metadata: OUIDatasetMetadata? = nil) {
        self.prefixes = prefixes
        self.metadata = metadata ?? OUIDatasetMetadata(
            source: "inline",
            entryCount: prefixes.count,
            format: "map"
        )
    }

    public static func loadBundledSample() -> OUIVendorLookup { loadDefault() }

    public static func loadDefault() -> OUIVendorLookup {
        if let imported = try? loadImportedApplicationSupport() {
            return imported
        }
        if let url = Bundle.module.url(forResource: "oui-sample", withExtension: "csv", subdirectory: nil)
            ?? Bundle.module.url(forResource: "oui-sample", withExtension: "csv", subdirectory: "OUI"),
           let lookup = try? OUIVendorLookup(contentsOf: url, sourceLabel: "bundled oui-sample.csv") {
            return lookup
        }
        return OUIVendorLookup(prefixes: [
            "001A2B": "Ayecom Technology Co., Ltd.",
            "001C42": "Parallels, Inc.",
            "000C29": "VMware, Inc.",
            "B827EB": "Raspberry Pi Foundation",
            "DCA632": "Raspberry Pi Trading Ltd",
            "525400": "QEMU virtual NIC",
            "F0D1A9": "Apple, Inc.",
            "3C22FB": "Apple, Inc.",
            "ACDE48": "Private"
        ], metadata: OUIDatasetMetadata(source: "embedded-fallback", entryCount: 9, format: "map"))
    }

    public static func applicationSupportOUIURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("OpenLANScanner", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("oui.csv")
    }

    public static func metadataURL() throws -> URL {
        try applicationSupportOUIURL().deletingLastPathComponent().appendingPathComponent("oui-metadata.json")
    }

    public static func loadImportedApplicationSupport() throws -> OUIVendorLookup? {
        let url = try applicationSupportOUIURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        var meta = OUIDatasetMetadata(source: url.lastPathComponent, entryCount: 0, format: "csv")
        if let data = try? Data(contentsOf: try metadataURL()),
           let decoded = try? JSONDecoder().decode(OUIDatasetMetadata.self, from: data) {
            meta = decoded
        }
        return try OUIVendorLookup(contentsOf: url, sourceLabel: meta.source, importedAt: meta.importedAt)
    }

    /// Soft upper bound for imported OUI CSV size (bytes). Larger files are rejected before load.
    public static let maxImportByteCount = 32 * 1024 * 1024

    /// Import a CSV into Application Support. Keeps previous files if parsing fails.
    public static func importCSV(from sourceURL: URL) throws -> OUIVendorLookup {
        let attrs = try FileManager.default.attributesOfItem(atPath: sourceURL.path)
        if let size = attrs[.size] as? NSNumber, size.intValue > maxImportByteCount {
            throw NSError(domain: "OUIVendorLookup", code: 2, userInfo: [
                NSLocalizedDescriptionKey:
                    "OUI file is too large (\(size.intValue) bytes; limit \(maxImportByteCount))."
            ])
        }
        let text = try String(contentsOf: sourceURL, encoding: .utf8)
        let parsed = parseCSV(text)
        guard !parsed.prefixes.isEmpty else {
            throw NSError(domain: "OUIVendorLookup", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No OUI assignments found in the selected file."
            ])
        }
        let dest = try applicationSupportOUIURL()
        let backup = dest.appendingPathExtension("bak")
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) {
            try? fm.removeItem(at: backup)
            try? fm.copyItem(at: dest, to: backup)
        }
        do {
            try text.write(to: dest, atomically: true, encoding: .utf8)
            let meta = OUIDatasetMetadata(
                source: sourceURL.lastPathComponent,
                importedAt: Date(),
                entryCount: parsed.prefixes.count,
                format: parsed.format
            )
            let metaData = try JSONEncoder().encode(meta)
            try metaData.write(to: try metadataURL(), options: .atomic)
            return OUIVendorLookup(prefixes: parsed.prefixes, metadata: meta)
        } catch {
            if fm.fileExists(atPath: backup.path) {
                try? fm.removeItem(at: dest)
                try? fm.moveItem(at: backup, to: dest)
            }
            throw error
        }
    }

    public init(contentsOf url: URL, sourceLabel: String? = nil, importedAt: Date? = nil) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        let parsed = Self.parseCSV(text)
        self.prefixes = parsed.prefixes
        self.metadata = OUIDatasetMetadata(
            source: sourceLabel ?? url.lastPathComponent,
            importedAt: importedAt,
            entryCount: parsed.prefixes.count,
            format: parsed.format
        )
    }

    public func vendor(forMAC mac: String) -> String? {
        guard let info = MACAddressParsing.parse(mac) else { return nil }
        if info.isLocallyAdministered {
            return info.randomizedOrLocalDescription
        }
        return vendor(forHexPrefix: info.hex)
    }

    public func vendor(forHexPrefix hex: String) -> String? {
        let key = hex.uppercased().filter(\.isHexDigit)
        // Longest-prefix match: try 9 (MA-S/OUI-36), 7 (MA-M), then 6 (MA-L/OUI).
        for length in [9, 7, 6] where key.count >= length {
            let prefix = String(key.prefix(length))
            if let name = prefixes[prefix] { return name }
        }
        return nil
    }

    public struct ParseResult: Sendable {
        public var prefixes: [String: String]
        public var format: String
    }

    public static func parseCSV(_ text: String) -> ParseResult {
        var map: [String: String] = [:]
        var format = "compact"
        let lines = text.split(whereSeparator: \.isNewline)
        for (index, lineSub) in lines.enumerated() {
            let raw = String(lineSub).trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.isEmpty { continue }
            let lower = raw.lowercased()
            if index == 0 && (lower.contains("assignment") || lower.contains("registry")) {
                if lower.contains("registry") { format = "ieee" }
                continue
            }

            let columns = splitCSVLine(raw)
            guard columns.count >= 2 else { continue }

            let assignmentColumn: String
            let orgColumn: String
            if format == "ieee" || (columns.count >= 3 && columns[0].uppercased().hasPrefix("MA-")) {
                format = "ieee"
                // IEEE: Registry, Assignment, Organization Name, ...
                assignmentColumn = columns[1]
                orgColumn = columns[2]
            } else {
                assignmentColumn = columns[0]
                orgColumn = columns[1]
            }

            let assignment = assignmentColumn.uppercased().filter(\.isHexDigit)
            let org = orgColumn.trimmingCharacters(in: .whitespacesAndNewlines)
            guard assignment.count >= 6, !org.isEmpty else { continue }
            // Preserve full assignment length (6, 7, or 9+).
            let key: String
            if assignment.count >= 9 {
                key = String(assignment.prefix(9))
            } else if assignment.count >= 7 {
                key = String(assignment.prefix(7))
            } else {
                key = String(assignment.prefix(6))
            }
            map[key] = org
        }
        return ParseResult(prefixes: map, format: format)
    }

    private static func splitCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "\"" {
                if inQuotes, i + 1 < chars.count, chars[i + 1] == "\"" {
                    // Escaped quote ""
                    current.append("\"")
                    i += 2
                    continue
                }
                inQuotes.toggle()
                i += 1
                continue
            }
            if ch == "," && !inQuotes {
                fields.append(current)
                current = ""
                i += 1
                continue
            }
            current.append(ch)
            i += 1
        }
        fields.append(current)
        return fields
    }
}
