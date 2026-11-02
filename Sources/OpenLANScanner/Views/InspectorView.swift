import OpenLANScannerCore
import SwiftUI

@MainActor
struct InspectorView: View {
    @Bindable var model: ScanSessionViewModel
    @State private var nameDraft = ""
    @State private var notesDraft = ""
    @State private var actionError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Device")
                .font(.headline)
            if let host = model.selectedHost {
                grid(host)
                Divider()
                Text("Favorites")
                    .font(.subheadline.weight(.semibold))
                TextField("Custom name", text: $nameDraft)
                    .textFieldStyle(.roundedBorder)
                TextField("Notes", text: $notesDraft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
                HStack {
                    Button(host.isFavorite ? "Update Favorite" : "Add Favorite") {
                        model.updateFavoriteMetadata(for: host.ip, name: nameDraft, notes: notesDraft)
                    }
                    Button(host.isFavorite ? "Remove" : "Add Star") {
                        model.toggleFavorite(host)
                    }
                }
                Divider()
                Text("Actions")
                    .font(.subheadline.weight(.semibold))
                actionButtons(host)
                if let actionError {
                    Text(actionError)
                        .font(.caption)
                        .foregroundStyle(OLSTheme.error)
                }
            } else {
                Text("Select a host to inspect.")
                    .foregroundStyle(OLSTheme.mutedText)
                    .font(.callout)
                Spacer()
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(minWidth: 260, idealWidth: 280, maxWidth: 320)
        .background(OLSTheme.surface)
        .onChange(of: model.selectedHostID) { _, _ in
            syncDrafts()
        }
        .onAppear(perform: syncDrafts)
    }

    private func syncDrafts() {
        nameDraft = model.selectedHost?.customName ?? ""
        notesDraft = model.selectedHost?.notes ?? ""
        actionError = nil
    }

    @ViewBuilder
    private func grid(_ host: HostRecord) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
            row("Status", host.status.displayLabel)
            row("Name", host.displayName)
            row("IP", host.ip.dotted)
            row("Hostname", host.hostname ?? "—")
            row("MAC", host.macAddress ?? "—")
            row("Vendor", host.vendor ?? "—")
            row(
                "Response",
                host.responseTimeMs.map { String(format: "%.0f ms (%@)", $0, host.latencyKind.rawValue) } ?? "—"
            )
            row(
                "Services",
                host.services.isEmpty ? "—" : host.services.map { "\($0.name):\($0.port)" }.joined(separator: ", ")
            )
            row(
                "Evidence",
                host.evidence.isEmpty
                    ? "Not observed"
                    : host.evidence.map { "\($0.kind.rawValue)" }.joined(separator: ", ")
            )
        }
        .font(.system(size: 12))
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(OLSTheme.mutedText)
            Text(value)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func actionButtons(_ host: HostRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("Open SMB") { DeviceActions.openSMB(ip: host.ip) }
            Button("Open HTTP") { DeviceActions.openHTTP(ip: host.ip, secure: false) }
            Button("Open HTTPS") { DeviceActions.openHTTP(ip: host.ip, secure: true) }
            Button("SSH in Terminal") { DeviceActions.openSSH(ip: host.ip) }
            Button("Screen Sharing") { DeviceActions.openVNC(ip: host.ip) }
            Button("RDP…") {
                do { try DeviceActions.openRDP(ip: host.ip) }
                catch { actionError = error.localizedDescription }
            }
            Button("Wake-on-LAN") {
                Task {
                    do { try await DeviceActions.wakeOnLAN(mac: host.macAddress) }
                    catch { actionError = error.localizedDescription }
                }
            }
            .disabled(host.macAddress == nil)
            Button("Copy IP") { DeviceActions.copyToPasteboard([host.ip.dotted]) }
            Button("Ping") { DeviceActions.ping(ip: host.ip) }
        }
        .buttonStyle(.borderless)
    }
}
