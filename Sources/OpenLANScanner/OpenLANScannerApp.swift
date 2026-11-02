import AppKit
import OpenLANScannerCore
import SwiftUI
import UniformTypeIdentifiers

@main
struct OpenLANScannerApp: App {
    @State private var model = ScanSessionViewModel()

    var body: some Scene {
        WindowGroup("Open LAN Scanner") {
            ContentView(model: model)
                .frame(minWidth: 900, minHeight: 560)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
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
                Button("Export CSV…") { exportCSV() }
                Button("Export JSON…") { exportJSON() }
                Divider()
                Button("Export Favorites…") { exportFavorites() }
                Button("Import Favorites…") { importFavorites() }
                Divider()
                Button("Copy Selected IP") {
                    if let host = model.selectedHost {
                        DeviceActions.copyToPasteboard([host.ip.dotted])
                    }
                }
                .keyboardShortcut("c", modifiers: [.command])
            }
            CommandMenu("Host") {
                Button("Open SMB") {
                    if let host = model.selectedHost { DeviceActions.openSMB(ip: host.ip) }
                }
                Button("Open HTTP") {
                    if let host = model.selectedHost { DeviceActions.openHTTP(ip: host.ip, secure: false) }
                }
                Button("Open HTTPS") {
                    if let host = model.selectedHost { DeviceActions.openHTTP(ip: host.ip, secure: true) }
                }
                Button("SSH") {
                    if let host = model.selectedHost { DeviceActions.openSSH(ip: host.ip) }
                }
                Button("Screen Sharing") {
                    if let host = model.selectedHost { DeviceActions.openVNC(ip: host.ip) }
                }
                Button("Wake-on-LAN") {
                    if let host = model.selectedHost {
                        Task { try? await DeviceActions.wakeOnLAN(mac: host.macAddress) }
                    }
                }
                Button("Ping") {
                    if let host = model.selectedHost { DeviceActions.ping(ip: host.ip) }
                }
                Button("Traceroute") {
                    if let host = model.selectedHost { DeviceActions.traceroute(ip: host.ip) }
                }
            }
        }
        Settings {
            PreferencesView(model: model)
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "open-lan-scanner-results.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let csv = ResultExporter.csv(from: model.hosts)
        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "open-lan-scanner-results.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? ResultExporter.json(from: model.hosts) else { return }
        try? data.write(to: url)
    }

    private func exportFavorites() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "open-lan-scanner-favorites.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? model.exportFavoritesJSON() else { return }
        try? data.write(to: url)
    }

    private func importFavorites() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        try? model.importFavoritesJSON(data)
    }
}
