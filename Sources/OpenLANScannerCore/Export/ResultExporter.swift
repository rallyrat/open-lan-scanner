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
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }
}
