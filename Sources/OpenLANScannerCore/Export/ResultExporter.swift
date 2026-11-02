import Foundation

public enum ResultExporter {
    public static func csv(from hosts: [HostRecord]) -> String {
        var lines: [String] = []
        lines.append(
            [
                "status",
                "ip",
                "hostname",
                "mac",
                "vendor",
                "response_ms",
                "latency_kind",
                "services",
                "favorite",
                "custom_name",
                "notes"
            ].joined(separator: ",")
        )

        for host in hosts.sorted(by: { $0.ip < $1.ip }) {
            let services = host.services.map { "\($0.name):\($0.port)" }.joined(separator: " ")
            let row: [String] = [
                host.status.rawValue,
                host.ip.dotted,
                host.hostname ?? "",
                host.macAddress ?? "",
                host.vendor ?? "",
                host.responseTimeMs.map { String(format: "%.1f", $0) } ?? "",
                host.latencyKind.rawValue,
                services,
                host.isFavorite ? "true" : "false",
                host.customName ?? "",
                host.notes ?? ""
            ]
            lines.append(row.map(escapeCSV).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func json(from hosts: [HostRecord]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(hosts.sorted(by: { $0.ip < $1.ip }))
    }

    public static func escapeCSV(_ field: String) -> String {
        // Neutralize spreadsheet formula injection (=, +, -, @, tab, CR), including after
        // leading whitespace/BOM that Excel still treats as a formula starter.
        var value = field
        let trimmedLeading = value.drop(while: { $0 == " " || $0 == "\t" || $0 == "\u{feff}" })
        if let first = trimmedLeading.unicodeScalars.first {
            let risky = CharacterSet(charactersIn: "=+-@\t\r")
            if risky.contains(first) {
                value = "'" + value
            }
        }
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }
}
