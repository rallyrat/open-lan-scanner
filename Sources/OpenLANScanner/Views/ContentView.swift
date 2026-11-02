import AppKit
import OpenLANScannerCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ContentView: View {
    @Bindable var model: ScanSessionViewModel
    @State private var showHistory = false
    @State private var sortColumn = UserDefaults.standard.string(forKey: "ols.sort.column") ?? "hostname"
    @State private var sortAscending = UserDefaults.standard.object(forKey: "ols.sort.ascending") as? Bool ?? true

    var body: some View {
        VStack(spacing: 0) {
            ToolbarView(model: model)
            if let warning = model.permissionWarning {
                HStack(spacing: OLSTheme.controlGap) {
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
                .padding(.horizontal, OLSTheme.contentInset)
                .padding(.vertical, 6)
                .background(OLSTheme.warning.opacity(0.15))
            }
            if let banner = model.actionBanner {
                HStack {
                    Text(banner).font(.caption)
                    Spacer()
                    Button("OK") { model.actionBanner = nil }.buttonStyle(.borderless)
                }
                .padding(.horizontal, OLSTheme.contentInset)
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
        .frame(minWidth: OLSTheme.windowMinWidth, minHeight: OLSTheme.windowMinHeight)
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
                    compactDensity: model.compactTableDensity,
                    showMACColumn: model.showMACColumn,
                    showVendorColumn: model.showVendorColumn,
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
                .frame(minWidth: 480, minHeight: 280)
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
        VStack(spacing: OLSTheme.relatedGap) {
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
            HStack(spacing: OLSTheme.controlGap) {
                ForEach(emptyActions, id: \.0) { title, action in
                    Button(title, action: action)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(OLSTheme.contentInset)
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
            return "Clear search or filters to see discovered hosts."
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
        HStack(spacing: OLSTheme.relatedGap) {
            Text(model.statusMessage)
                .font(.caption)
                .foregroundStyle(OLSTheme.mutedText)
                .lineLimit(1)
                .help(model.statusMessage)
            Spacer(minLength: OLSTheme.controlGap)
            if model.isScanning {
                ProgressView(value: model.progress.fraction)
                    .frame(width: 100)
                    .help("Scan progress")
            }
            Text("\(model.filteredHosts.count) shown · \(model.filteredHosts.filter { $0.status == .online }.count) responded")
                .font(.caption.monospacedDigit())
                .foregroundStyle(OLSTheme.mutedText)
                .lineLimit(1)
            Text(elapsedLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(OLSTheme.mutedText)
                .lineLimit(1)
            Button("History") { showHistory = true }
                .buttonStyle(.plain)
                .font(.caption)
                .help("Saved scans")
        }
        .padding(.horizontal, OLSTheme.contentInset)
        .padding(.vertical, 6)
        .background(OLSTheme.surface)
    }

    private var elapsedLabel: String {
        let t = model.elapsed
        return String(format: "%02d:%04.1f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60))
    }

    private func handleContext(_ host: HostRecord, _ action: ResultsTableView.ResultsTableContextAction) {
        // Ensure inspector targets the context host.
        model.selectedHostID = host.id
        model.selectedHostIDs = [host.id]
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
