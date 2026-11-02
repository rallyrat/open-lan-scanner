import AppKit
import OpenLANScannerCore
import SwiftUI
import UniformTypeIdentifiers

@main
@MainActor
struct OpenLANScannerApp: App {
    @State private var model = ScanSessionViewModel()
    @State private var didApplyDemoLaunch = false

    var body: some Scene {
        WindowGroup("Open LAN Scanner") {
            ContentView(model: model)
                .frame(minWidth: 1100, minHeight: 680)
                .onAppear {
                    applyDemoLaunchIfNeeded()
                }
        }
        .defaultSize(width: 1180, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .pasteboard) {
                Button("Copy") {
                    if Self.isEditingText {
                        NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                    } else {
                        model.copySelectedRows()
                    }
                }
                .keyboardShortcut("c", modifiers: [.command])
                Button("Copy Selected IPs") {
                    guard !Self.isEditingText else {
                        NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                        return
                    }
                    model.copySelectedIPs()
                }
            }
            CommandMenu("Scan") {
                Button("Scan") { model.requestScan() }
                    .keyboardShortcut("r", modifiers: [.command])
                Button("Stop") { model.stopScan() }
                    .keyboardShortcut(".", modifiers: [.command])
                Divider()
                Button("Use Interface Subnet") { model.applySelectedInterfaceSubnet() }
                Button("Snap to /24") { model.applyClassC() }
                Divider()
                Button("Refresh Interfaces") { model.refreshInterfaces(selectPreferred: false) }
            }
            CommandMenu("Results") {
                Menu("Export CSV") {
                    Button("All Results…") { exportCSV(.allResults) }
                    Button("Filtered Results…") { exportCSV(.filteredResults) }
                    Button("Selected Rows…") { exportCSV(.selectedRows) }
                }
                Menu("Export JSON") {
                    Button("All Results…") { exportJSON(.allResults) }
                    Button("Filtered Results…") { exportJSON(.filteredResults) }
                    Button("Selected Rows…") { exportJSON(.selectedRows) }
                }
                Divider()
                Button("Export Favorites…") { exportFavorites() }
                Button("Import Favorites…") { importFavorites() }
            }
            CommandMenu("Host") {
                Button("Open SMB") {
                    if let host = model.selectedHost { DeviceActions.openSMB(ip: host.ip) }
                }
                .disabled(model.selectedHost == nil)
                Button("Open HTTP") {
                    if let host = model.selectedHost { DeviceActions.openHTTP(ip: host.ip, secure: false) }
                }
                .disabled(model.selectedHost == nil)
                Button("Open HTTPS") {
                    if let host = model.selectedHost { DeviceActions.openHTTP(ip: host.ip, secure: true) }
                }
                .disabled(model.selectedHost == nil)
                Button("SSH") {
                    if let host = model.selectedHost { DeviceActions.openSSH(ip: host.ip) }
                }
                .disabled(model.selectedHost == nil)
                Button("Screen Sharing") {
                    if let host = model.selectedHost { DeviceActions.openVNC(ip: host.ip) }
                }
                .disabled(model.selectedHost == nil)
                Button("Wake-on-LAN") {
                    guard let host = model.selectedHost else { return }
                    Task {
                        do {
                            try await DeviceActions.wakeOnLAN(mac: host.macAddress)
                            model.showAction("Sent Wake-on-LAN to \(host.macAddress ?? "")")
                        } catch {
                            model.errorMessage = error.localizedDescription
                        }
                    }
                }
                .disabled(model.selectedHost?.macAddress == nil)
                Button("Ping") {
                    if let host = model.selectedHost { DeviceActions.ping(ip: host.ip) }
                }
                .disabled(model.selectedHost == nil)
                Button("Traceroute") {
                    if let host = model.selectedHost { DeviceActions.traceroute(ip: host.ip) }
                }
                .disabled(model.selectedHost == nil)
            }
        }
        Settings {
            PreferencesView(model: model)
        }
    }

    private static var isEditingText: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        return responder is NSTextView || responder is NSTextField || responder is NSText
    }

    private func applyDemoLaunchIfNeeded() {
        guard !didApplyDemoLaunch else { return }
        didApplyDemoLaunch = true
        guard DemoScreenshotLaunchOptions.isDemoUI else { return }

        model.loadDemoScreenshotData()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        guard let exportDir = DemoScreenshotLaunchOptions.exportDirectory else { return }
        Task { @MainActor in
            await exportDemoScreenshots(to: exportDir)
        }
    }

    private func exportDemoScreenshots(to directory: URL) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Allow SwiftUI + AppKit table to settle before capturing.
        try? await Task.sleep(nanoseconds: 900_000_000)

        let appearance = NSApp.effectiveAppearance
        defer { NSApp.appearance = appearance }

        // 1) Main results + inspector (light) — NAS selected for SMB/SSH services
        NSApp.appearance = NSAppearance(named: .aqua)
        model.showFavoritesOnly = false
        model.selectDemoHost(ip: "203.0.113.20")
        model.showInspector = true
        try? await Task.sleep(nanoseconds: 700_000_000)
        try? DemoWindowCapture.captureKeyWindowPNG(
            to: directory.appendingPathComponent("01-main-results.png")
        )

        // 2) Laptop selected — inspector actions + hostname-focused detail
        model.selectDemoHost(ip: "203.0.113.42")
        try? await Task.sleep(nanoseconds: 700_000_000)
        try? DemoWindowCapture.captureKeyWindowPNG(
            to: directory.appendingPathComponent("02-inspector-actions.png")
        )

        // 3) Favorites filter in dark appearance
        NSApp.appearance = NSAppearance(named: .darkAqua)
        model.showFavoritesOnly = true
        model.selectDemoHost(ip: "203.0.113.1")
        try? await Task.sleep(nanoseconds: 700_000_000)
        try? DemoWindowCapture.captureKeyWindowPNG(
            to: directory.appendingPathComponent("03-favorites-dark.png")
        )

        // Signal completion for automation wrappers.
        let marker = directory.appendingPathComponent("EXPORT_DONE")
        try? "ok\n".write(to: marker, atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }

    private func exportCSV(_ scope: ScanSessionViewModel.ExportScope) {
        let rows = model.hosts(for: scope)
        guard !rows.isEmpty else {
            model.errorMessage = "Nothing to export for that scope."
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "open-lan-scanner-\(scopeFileLabel(scope)).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ResultExporter.csv(from: rows).write(to: url, atomically: true, encoding: .utf8)
            model.showAction("Exported \(rows.count) row(s) to \(url.lastPathComponent)")
        } catch {
            model.errorMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func exportJSON(_ scope: ScanSessionViewModel.ExportScope) {
        let rows = model.hosts(for: scope)
        guard !rows.isEmpty else {
            model.errorMessage = "Nothing to export for that scope."
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "open-lan-scanner-\(scopeFileLabel(scope)).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try ResultExporter.json(from: rows)
            try data.write(to: url, options: .atomic)
            model.showAction("Exported \(rows.count) row(s) to \(url.lastPathComponent)")
        } catch {
            model.errorMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func scopeFileLabel(_ scope: ScanSessionViewModel.ExportScope) -> String {
        switch scope {
        case .allResults: return "all"
        case .filteredResults: return "filtered"
        case .selectedRows: return "selected"
        }
    }

    private func exportFavorites() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "open-lan-scanner-favorites.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try model.exportFavoritesJSON()
            try data.write(to: url, options: .atomic)
            model.showAction("Exported favorites to \(url.lastPathComponent)")
        } catch {
            model.errorMessage = "Favorites export failed: \(error.localizedDescription)"
        }
    }

    private func importFavorites() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            try model.importFavoritesJSON(data)
        } catch {
            model.errorMessage = "Favorites import failed: \(error.localizedDescription)"
        }
    }
}
