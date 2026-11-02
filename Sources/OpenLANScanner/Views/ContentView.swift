import OpenLANScannerCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var model: ScanSessionViewModel
    @State private var exportError: String?
    @State private var showPreferences = false

    var body: some View {
        VStack(spacing: 0) {
            ToolbarView(model: model)
            Divider()
            HSplitView {
                resultsPane
                if model.showInspector {
                    InspectorView(model: model)
                }
            }
            Divider()
            statusBar
        }
        .background(OLSTheme.background)
        .alert("Large range", isPresented: $model.showLargeRangeConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Scan \(model.pendingAddressCount) addresses") {
                model.confirmLargeRangeScan()
            }
        } message: {
            Text("This target expands to \(model.pendingAddressCount) addresses. Continue?")
        }
        .alert("Error", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .sheet(isPresented: $showPreferences) {
            PreferencesView(model: model)
        }
        .onAppear {
            model.refreshInterfaces(selectPreferred: model.selectedInterfaceID == nil)
        }
    }

    private var resultsPane: some View {
        Group {
            if model.filteredHosts.isEmpty && !model.isScanning {
                emptyState
            } else {
                ResultsTableView(
                    hosts: model.filteredHosts,
                    selection: $model.selectedHostID,
                    onDoubleClick: { host in
                        if host.services.contains(where: { $0.port == 445 }) {
                            DeviceActions.openSMB(ip: host.ip)
                        } else if host.services.contains(where: { $0.port == 443 }) {
                            DeviceActions.openHTTP(ip: host.ip, secure: true)
                        } else if host.services.contains(where: { $0.port == 80 }) {
                            DeviceActions.openHTTP(ip: host.ip, secure: false)
                        } else {
                            DeviceActions.copyToPasteboard([host.ip.dotted])
                        }
                    },
                    onContextAction: handleContext
                )
                .frame(minWidth: 520, minHeight: 280)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(OLSTheme.accent)
            Text("No results yet")
                .font(.title3.weight(.semibold))
            Text("Choose an interface, confirm the address range, then press Scan. Devices that ignore ICMP can still appear when a probed TCP service answers.")
                .font(.callout)
                .foregroundStyle(OLSTheme.mutedText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            if let iface = model.selectedInterface {
                Text("Suggested: \(iface.suggestedScanExpression)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(OLSTheme.mutedText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            if model.isScanning {
                ProgressView(value: model.progress.fraction)
                    .frame(width: 120)
            }
            Text(model.statusMessage)
                .font(.caption)
                .foregroundStyle(OLSTheme.mutedText)
            Spacer()
            Text("\(model.filteredHosts.count) shown · \(model.progress.onlineCount) online")
                .font(.caption.monospacedDigit())
                .foregroundStyle(OLSTheme.mutedText)
            Text(elapsedLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(OLSTheme.mutedText)
            Button("Preferences…") { showPreferences = true }
                .buttonStyle(.plain)
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(OLSTheme.surface)
    }

    private var elapsedLabel: String {
        let t = model.elapsed
        return String(format: "%02d:%04.1f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60))
    }

    private func handleContext(_ host: HostRecord, _ action: ResultsTableView.ResultsTableContextAction) {
        switch action {
        case .favorite:
            model.toggleFavorite(host)
        case .copyIP:
            DeviceActions.copyToPasteboard([host.ip.dotted])
        case .smb:
            DeviceActions.openSMB(ip: host.ip)
        case .http:
            DeviceActions.openHTTP(ip: host.ip, secure: false)
        case .https:
            DeviceActions.openHTTP(ip: host.ip, secure: true)
        case .ssh:
            DeviceActions.openSSH(ip: host.ip)
        case .vnc:
            DeviceActions.openVNC(ip: host.ip)
        case .rdp:
            do { try DeviceActions.openRDP(ip: host.ip) }
            catch { model.errorMessage = error.localizedDescription }
        case .wol:
            Task {
                do { try await DeviceActions.wakeOnLAN(mac: host.macAddress) }
                catch { model.errorMessage = error.localizedDescription }
            }
        case .ping:
            DeviceActions.ping(ip: host.ip)
        }
    }
}

struct PreferencesView: View {
    @Bindable var model: ScanSessionViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Scan Preferences")
                .font(.title2.weight(.semibold))
            Form {
                Stepper(value: $model.preferences.concurrency, in: 1...512) {
                    Text("Concurrency: \(model.preferences.concurrency)")
                }
                Stepper(value: $model.preferences.connectTimeoutMs, in: 50...5000, step: 50) {
                    Text("Connect timeout: \(model.preferences.connectTimeoutMs) ms")
                }
                Stepper(value: $model.preferences.probeRetries, in: 1...5) {
                    Text("Retries: \(model.preferences.probeRetries)")
                }
                Stepper(value: $model.preferences.largeRangeWarningThreshold, in: 64...8192, step: 64) {
                    Text("Large-range warning at: \(model.preferences.largeRangeWarningThreshold)")
                }
                Toggle("Resolve hostnames", isOn: $model.preferences.resolveHostnames)
                Toggle("Look up neighbor MAC addresses", isOn: $model.preferences.lookupNeighbors)
                Toggle("Look up vendors (OUI)", isOn: $model.preferences.lookupVendors)
                Section("Service probes") {
                    ForEach($model.preferences.services) { $service in
                        Toggle("\(service.name) (\(service.port))", isOn: $service.enabled)
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Close") {
                    model.savePreferences()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480, height: 520)
    }
}
