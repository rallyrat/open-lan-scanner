import AppKit
import Foundation
import OpenLANScannerCore

/// Deterministic fictional LAN used only when screenshot/demo mode is explicitly activated.
/// Never used by normal launches. Addresses and MACs are documentation placeholders.
enum DemoScreenshotCatalog {
    static let interfaceNote = "Demo Wi‑Fi (en0) — 203.0.113.10/24"
    static let rangeText = "203.0.113.0/24"

    static func hosts(now: Date = Date()) -> [HostRecord] {
        [
            HostRecord(
                ip: IPv4Address(string: "203.0.113.1")!,
                status: .online,
                hostname: "demo-gateway.example",
                macAddress: "02:00:00:11:22:01",
                vendor: "Locally administered (demo)",
                responseTimeMs: 2,
                latencyKind: .icmp,
                services: [
                    DiscoveredService(name: "http", port: 80),
                    DiscoveredService(name: "https", port: 443)
                ],
                evidence: [
                    DiscoveryEvidence(kind: .icmpEcho, detail: "echo reply", observedAt: now, latencyMs: 2),
                    DiscoveryEvidence(kind: .tcpOpen, detail: "tcp/80", observedAt: now, latencyMs: 4)
                ],
                isFavorite: true,
                customName: "Demo Gateway",
                notes: "Documentation placeholder — not a real device.",
                lastSeen: now,
                firstSeenInScan: now
            ),
            HostRecord(
                ip: IPv4Address(string: "203.0.113.20")!,
                status: .online,
                hostname: "demo-nas.example",
                macAddress: "02:00:00:11:22:20",
                vendor: "Locally administered (demo)",
                responseTimeMs: 8,
                latencyKind: .tcpProbe,
                services: [
                    DiscoveredService(name: "smb", port: 445),
                    DiscoveredService(name: "ssh", port: 22)
                ],
                evidence: [
                    DiscoveryEvidence(kind: .tcpOpen, detail: "tcp/445", observedAt: now, latencyMs: 8),
                    DiscoveryEvidence(kind: .tcpOpen, detail: "tcp/22", observedAt: now, latencyMs: 9)
                ],
                isFavorite: true,
                customName: "Demo NAS",
                notes: "Fictional storage host for README screenshots.",
                lastSeen: now,
                firstSeenInScan: now
            ),
            HostRecord(
                ip: IPv4Address(string: "203.0.113.42")!,
                status: .online,
                hostname: "demo-laptop.example",
                macAddress: "02:00:00:11:22:42",
                vendor: "Locally administered (demo)",
                responseTimeMs: 14,
                latencyKind: .tcpProbe,
                services: [
                    DiscoveredService(name: "ssh", port: 22),
                    DiscoveredService(name: "vnc", port: 5900)
                ],
                evidence: [
                    DiscoveryEvidence(kind: .tcpOpen, detail: "tcp/22", observedAt: now, latencyMs: 14)
                ],
                isFavorite: false,
                customName: nil,
                notes: nil,
                lastSeen: now,
                firstSeenInScan: now
            ),
            HostRecord(
                ip: IPv4Address(string: "203.0.113.55")!,
                status: .online,
                hostname: "demo-printer.example",
                macAddress: "02:00:00:11:22:55",
                vendor: "Locally administered (demo)",
                responseTimeMs: 21,
                latencyKind: .tcpProbe,
                services: [
                    DiscoveredService(name: "http", port: 80)
                ],
                evidence: [
                    DiscoveryEvidence(kind: .tcpRefused, detail: "tcp/445 refused", observedAt: now),
                    DiscoveryEvidence(kind: .tcpOpen, detail: "tcp/80", observedAt: now, latencyMs: 21)
                ],
                isFavorite: false,
                lastSeen: now,
                firstSeenInScan: now
            ),
            HostRecord(
                ip: IPv4Address(string: "203.0.113.200")!,
                status: .unknown,
                hostname: nil,
                macAddress: nil,
                vendor: nil,
                responseTimeMs: nil,
                latencyKind: .none,
                services: [],
                evidence: [],
                isFavorite: false,
                lastSeen: nil,
                firstSeenInScan: now
            )
        ]
    }
}

enum DemoScreenshotLaunchOptions {
    static var isDemoUI: Bool {
        CommandLine.arguments.contains("--demo-ui")
            || ProcessInfo.processInfo.environment["OLS_DEMO_UI"] == "1"
    }

    /// Directory for in-process window captures. Empty means run interactive demo UI only.
    static var exportDirectory: URL? {
        guard let index = CommandLine.arguments.firstIndex(of: "--export-screenshots") else {
            if let env = ProcessInfo.processInfo.environment["OLS_EXPORT_SCREENSHOTS"], !env.isEmpty {
                return URL(fileURLWithPath: env, isDirectory: true)
            }
            return nil
        }
        let next = CommandLine.arguments.index(after: index)
        guard next < CommandLine.arguments.count else { return nil }
        return URL(fileURLWithPath: CommandLine.arguments[next], isDirectory: true)
    }
}

@MainActor
enum DemoWindowCapture {
    static func captureKeyWindowPNG(to url: URL) throws {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil })
                ?? NSApp.keyWindow
                ?? NSApp.mainWindow else {
            throw CaptureError.noWindow
        }
        window.layoutIfNeeded()
        guard let content = window.contentView else { throw CaptureError.noWindow }
        let bounds = content.bounds
        guard bounds.width > 1, bounds.height > 1 else { throw CaptureError.invalidBounds }
        guard let rep = content.bitmapImageRepForCachingDisplay(in: bounds) else {
            throw CaptureError.bitmapFailed
        }
        content.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CaptureError.encodeFailed
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    enum CaptureError: Error, LocalizedError {
        case noWindow
        case invalidBounds
        case bitmapFailed
        case encodeFailed

        var errorDescription: String? {
            switch self {
            case .noWindow: return "No visible app window to capture."
            case .invalidBounds: return "Window content bounds are empty."
            case .bitmapFailed: return "Could not allocate a bitmap for the window."
            case .encodeFailed: return "PNG encoding failed."
            }
        }
    }
}
