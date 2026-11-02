import AppKit
import OpenLANScannerCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var model: ScanSessionViewModel
    @State private var showPreferences = false
    @State private var showHistory = false
    @State private var sortColumn = UserDefaults.standard.string(forKey: "ols.sort.column") ?? "ip"
    @State private var sortAscending = UserDefaults.standard.object(forKey: "ols.sort.ascending") as? Bool ?? true

    var body: some View {
        VStack(spacing: 0) {
            ToolbarView(model: model)
            if let warning = model.permissionWarning {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(warning)
                        .font(.caption)
                    Spacer()
                    Button("System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)
                    Button("Dismiss") { model.permissionWarning = nil }
                        .buttonStyle(.borderless)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(OLSTheme.warning.opacity(0.15))
            }
            if let banner = model.actionBanner {
                HStack {
                    Text(banner).font(.caption)
                    Spacer()
                    Button("OK") { model.actionBanner = nil }.buttonStyle(.borderless)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(OLSTheme.surface)
            }
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
        .frame(minWidth: 880, minHeight: 520)
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
        .sheet(isPresented: $showHistory) {
            HistoryView(model: model)
        }
        .onAppear {
            model.refreshInterfaces(selectPreferred: model.selectedInterfaceID == nil)
            model.recomputeEmptyState()
        }
    }

    private var resultsPane: some View {
        Group {
            if shouldShowEmptyOverlay {
                emptyState
            } else {
                ResultsTableView(
                    hosts: model.filteredHosts,
                    selection: $model.selectedHostID,
                    selectedIDs: $model.selectedHostIDs,
                    sortColumn: sortColumn,
                    sortAscending: sortAscending,
                    onSortChange: { column, ascending in
                        sortColumn = column
                        sortAscending = ascending
                        UserDefaults.standard.set(column, forKey: "ols.sort.column")
                        UserDefaults.standard.set(ascending, forKey: "ols.sort.ascending")
                    },
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

    private var shouldShowEmptyOverlay: Bool {
        switch model.emptyState {
        case .idleWithResults, .scanning:
            return model.filteredHosts.isEmpty && model.emptyState != .scanning
        case .noFilterMatches:
            return true
        default:
            return model.filteredHosts.isEmpty
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: emptyIcon)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(OLSTheme.accent)
            Text(emptyTitle)
                .font(.title3.weight(.semibold))
            Text(emptyBody)
                .font(.callout)
                .foregroundStyle(OLSTheme.mutedText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            HStack {
                ForEach(emptyActions, id: \.0) { title, action in
                    Button(title, action: action)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var emptyIcon: String {
        switch model.emptyState {
        case .noInterface: return "cable.connector.slash"
        case .permissionDenied: return "lock.shield"
        case .scanning: return "antenna.radiowaves.left.and.right"
        case .noFilterMatches: return "line.3.horizontal.decrease.circle"
        case .noDevices: return "wifi.exclamationmark"
        default: return "wifi"
        }
    }

    private var emptyTitle: String {
        switch model.emptyState {
        case .noInterface: return "No usable network interface"
        case .permissionDenied: return "Local Network access blocked"
        case .scanning: return "Scanning…"
        case .noFilterMatches: return "No rows match filters"
        case .noDevices: return "No devices responded"
        default: return "Ready to scan"
        }
    }

    private var emptyBody: String {
        switch model.emptyState {
        case .noInterface:
            return "Connect Ethernet or Wi‑Fi, then refresh interfaces. VPN-only adapters may not show LAN neighbors."
        case .permissionDenied:
            return model.permissionWarning ?? "Allow Local Network access for Open LAN Scanner, then scan again."
        case .scanning:
            return "Live results appear as hosts respond. Stop cancels in-flight probes."
        case .noFilterMatches:
            return "Clear search or filter toggles to see discovered hosts."
        case .noDevices:
            return "No live evidence in this range. That does not prove hosts are offline — try ICMP, wider discovery ports, or a different interface."
        default:
            return "Choose an interface, confirm the address range, then press Scan. Open TCP ports or TCP refusals count as responses; timeouts do not."
        }
    }

    private var emptyActions: [(String, () -> Void)] {
        switch model.emptyState {
        case .noInterface:
            return [("Refresh Interfaces", { model.refreshInterfaces(selectPreferred: true) })]
        case .permissionDenied:
            return [("Scan Again", { model.requestScan() })]
        case .noFilterMatches:
            return [("Clear Filters", {
                model.searchText = ""
                model.showOnlineOnly = false
                model.showFavoritesOnly = false
                model.recomputeEmptyState()
            })]
        case .noDevices, .firstLaunch:
            return [
                ("Use Interface Subnet", { model.applySelectedInterfaceSubnet() }),
                ("Scan", { model.requestScan() })
            ]
        default:
            return []
        }
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
                .lineLimit(1)
            if let note = model.progress.interfaceNote {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(OLSTheme.mutedText)
                    .lineLimit(1)
            }
            Spacer()
            Text("\(model.filteredHosts.count) shown · \(model.progress.onlineCount) responded")
                .font(.caption.monospacedDigit())
                .foregroundStyle(OLSTheme.mutedText)
            Text(elapsedLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(OLSTheme.mutedText)
            Button("History") { showHistory = true }
                .buttonStyle(.plain)
                .font(.caption)
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
            model.showAction("Copied IP \(host.ip.dotted)")
        case .copyRows:
            model.copySelectedRows()
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
            do {
                try DeviceActions.openRDP(ip: host.ip)
                model.showAction("Opened RDP for \(host.ip.dotted)")
            } catch {
                model.errorMessage = error.localizedDescription
            }
        case .wol:
            Task {
                do {
                    try await DeviceActions.wakeOnLAN(mac: host.macAddress)
                    model.showAction("Sent Wake-on-LAN to \(host.macAddress ?? "")")
                } catch {
                    model.errorMessage = error.localizedDescription
                }
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
                    Text("Discovery concurrency: \(model.preferences.concurrency)")
                }
                Stepper(value: $model.preferences.enrichmentConcurrency, in: 1...64) {
                    Text("Enrichment concurrency: \(model.preferences.enrichmentConcurrency)")
                }
                Stepper(value: $model.preferences.connectTimeoutMs, in: 50...5000, step: 50) {
                    Text("Connect timeout: \(model.preferences.connectTimeoutMs) ms")
                }
                Stepper(value: $model.preferences.probeRetries, in: 1...5) {
                    Text("Retries: \(model.preferences.probeRetries)")
                }
                Toggle("Resolve hostnames", isOn: $model.preferences.resolveHostnames)
                Toggle("Look up neighbor MAC addresses", isOn: $model.preferences.lookupNeighbors)
                Toggle("Look up vendors (OUI)", isOn: $model.preferences.lookupVendors)
                Toggle("Attempt ICMP echo (best-effort)", isOn: $model.preferences.attemptICMP)
                Toggle("Browse Bonjour services (best-effort)", isOn: $model.preferences.browseBonjour)
                Section("Discovery ports (live-host evidence; not listed as services)") {
                    ForEach($model.preferences.discoveryProbes) { $probe in
                        Toggle("TCP \(probe.port)", isOn: $probe.enabled)
                    }
                }
                Section("Service probes (listed when open)") {
                    ForEach($model.preferences.services) { $service in
                        Toggle("\(service.name) (\(service.port))", isOn: $service.enabled)
                    }
                }
                Section("Vendor database") {
                    Text(model.vendorDatasetDescription)
                        .font(.caption)
                        .foregroundStyle(OLSTheme.mutedText)
                    Button("Import IEEE / OUI CSV…") { model.importOUIDataset() }
                }
                Section("History") {
                    Stepper(value: $model.historyRetention, in: 5...200) {
                        Text("Keep \(model.historyRetention) scans")
                    }
                    Button("Clear History", role: .destructive) { model.clearHistory() }
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
        .frame(width: 520, height: 640)
    }
}

struct HistoryView: View {
    @Bindable var model: ScanSessionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedOlder: UUID?
    @State private var selectedNewer: UUID?
    @State private var comparison: ScanComparison?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scan History")
                .font(.title2.weight(.semibold))
            Text("Snapshots are stored only on this Mac. “No response” compared to a prior scan does not prove a device left the network.")
                .font(.caption)
                .foregroundStyle(OLSTheme.mutedText)
            List(model.history, selection: $selectedNewer) { snap in
                VStack(alignment: .leading) {
                    Text(snap.createdAt.formatted())
                    Text("\(snap.targetExpression) · \(snap.onlineCount) responded / \(snap.probedCount) probed")
                        .font(.caption)
                        .foregroundStyle(OLSTheme.mutedText)
                }
                .tag(snap.id)
            }
            HStack {
                Picker("Compare older", selection: $selectedOlder) {
                    Text("—").tag(Optional<UUID>.none)
                    ForEach(model.history) { snap in
                        Text(snap.createdAt.formatted()).tag(Optional(snap.id))
                    }
                }
                Button("Compare") {
                    comparison = model.compareHistory(older: selectedOlder, newer: selectedNewer)
                }
                Spacer()
                Button("Close") { dismiss() }
            }
            if let comparison {
                GroupBox("Comparison") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(comparison.uncertainMatches, id: \.self) {
                            Text("Note: \($0)").font(.caption).foregroundStyle(OLSTheme.warning)
                        }
                        Text("Newly observed: \(comparison.newlyObserved.map(\.ip.dotted).joined(separator: ", ") )")
                            .font(.caption)
                        Text("Previously observed, no response this scan: \(comparison.previouslyObservedNoResponse.map(\.ip.dotted).joined(separator: ", ") )")
                            .font(.caption)
                        Text("Changed services: \(comparison.changedServices.count)")
                            .font(.caption)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 560, height: 480)
    }
}
