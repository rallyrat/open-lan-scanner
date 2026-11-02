import OpenLANScannerCore
import SwiftUI

@MainActor
struct InspectorView: View {
    @Bindable var model: ScanSessionViewModel
    @State private var nameDraft = ""
    @State private var notesDraft = ""
    @State private var actionError: String?
    @State private var favoriteSaved = false
    @State private var showEvidence = false

    var body: some View {
        Group {
            if let host = model.selectedHost {
                ScrollView {
                    VStack(alignment: .leading, spacing: OLSTheme.inspectorSectionGap) {
                        header(host)
                        detailsSection(host)
                        favoriteSection(host)
                        actionsSection(host)
                        if let actionError {
                            Text(actionError)
                                .font(.caption)
                                .foregroundStyle(OLSTheme.error)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(OLSTheme.contentInset)
                }
            } else {
                VStack(alignment: .leading, spacing: OLSTheme.relatedGap) {
                    Text("Inspector")
                        .font(.headline)
                    Text("Select a device to view details")
                        .font(.callout)
                        .foregroundStyle(OLSTheme.mutedText)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(OLSTheme.contentInset)
            }
        }
        .frame(
            minWidth: OLSTheme.inspectorMinWidth,
            idealWidth: OLSTheme.inspectorIdealWidth,
            maxWidth: OLSTheme.inspectorMaxWidth
        )
        .background(OLSTheme.surface)
        .onChange(of: model.selectedHostID) { _, _ in
            syncDrafts()
            favoriteSaved = false
            actionError = nil
            showEvidence = false
        }
        .onAppear(perform: syncDrafts)
    }

    private func syncDrafts() {
        nameDraft = model.selectedHost?.customName ?? ""
        notesDraft = model.selectedHost?.notes ?? ""
    }

    private func header(_ host: HostRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(host.displayName)
                .font(.title3.weight(.semibold))
                .textSelection(.enabled)
                .lineLimit(3)
            Text(host.ip.dotted)
                .font(.body.monospacedDigit())
                .foregroundStyle(OLSTheme.mutedText)
                .textSelection(.enabled)
            Label(host.status.displayLabel, systemImage: statusSymbol(host.status))
                .font(.caption.weight(.medium))
                .foregroundStyle(statusColor(host.status))
        }
    }

    private func detailsSection(_ host: HostRecord) -> some View {
        VStack(alignment: .leading, spacing: OLSTheme.controlGap) {
            sectionTitle("Details")
            detailRow("Hostname", host.hostname ?? "Unavailable")
            detailRow("MAC Address", host.macAddress ?? "Unavailable")
            detailRow("Vendor", host.vendor ?? "Unavailable")
            detailRow("Response", host.responseSummary)
            detailRow(
                "Services",
                host.services.isEmpty
                    ? "None observed"
                    : host.services.map { "\($0.name) (\(String($0.port)))" }.joined(separator: ", ")
            )
            DisclosureGroup("Discovery evidence", isExpanded: $showEvidence) {
                if host.evidence.isEmpty {
                    Text("Not observed in this scan")
                        .font(.caption)
                        .foregroundStyle(OLSTheme.mutedText)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(host.evidence.enumerated()), id: \.offset) { _, item in
                            Text(item.displaySummary)
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .font(.caption)
        }
    }

    private func favoriteSection(_ host: HostRecord) -> some View {
        VStack(alignment: .leading, spacing: OLSTheme.controlGap) {
            sectionTitle("Favorite")
            LabeledContent("Custom name") {
                TextField("Optional name", text: $nameDraft)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
            }
            LabeledContent("Notes") {
                TextField("Optional notes", text: $notesDraft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...5)
                    .labelsHidden()
            }
            HStack(spacing: OLSTheme.controlGap) {
                Button(host.isFavorite ? "Save Favorite" : "Add Favorite") {
                    model.updateFavoriteMetadata(for: host.ip, name: nameDraft, notes: notesDraft)
                    favoriteSaved = true
                    model.showAction("Favorite saved")
                }
                .buttonStyle(.bordered)
                if host.isFavorite {
                    Button("Remove", role: .destructive) {
                        model.toggleFavorite(host)
                        favoriteSaved = false
                    }
                    .buttonStyle(.borderless)
                }
                if favoriteSaved {
                    Text("Saved")
                        .font(.caption)
                        .foregroundStyle(OLSTheme.success)
                }
            }
        }
    }

    private func actionsSection(_ host: HostRecord) -> some View {
        VStack(alignment: .leading, spacing: OLSTheme.controlGap) {
            sectionTitle("Actions")
            let primary = primaryActions(for: host)
            ForEach(primary, id: \.title) { item in
                Button(item.title) { item.run() }
                    .buttonStyle(.bordered)
            }
            Menu("More Actions") {
                Button("Open SMB") { DeviceActions.openSMB(ip: host.ip) }
                Button("Open HTTP") { DeviceActions.openHTTP(ip: host.ip, secure: false) }
                Button("Open HTTPS") { DeviceActions.openHTTP(ip: host.ip, secure: true) }
                Button("SSH in Terminal") { DeviceActions.openSSH(ip: host.ip) }
                Button("Screen Sharing") { DeviceActions.openVNC(ip: host.ip) }
                Button("RDP…") {
                    do { try DeviceActions.openRDP(ip: host.ip) }
                    catch { actionError = error.localizedDescription }
                }
                Divider()
                Button("Wake-on-LAN") {
                    Task {
                        do {
                            try await DeviceActions.wakeOnLAN(mac: host.macAddress)
                            model.showAction("Sent Wake-on-LAN")
                        } catch {
                            actionError = error.localizedDescription
                        }
                    }
                }
                .disabled(host.macAddress == nil)
                Button("Copy IP") {
                    DeviceActions.copyToPasteboard([host.ip.dotted])
                    model.showAction("Copied IP \(host.ip.dotted)")
                }
                Button("Ping") { DeviceActions.ping(ip: host.ip) }
                Button("Traceroute") { DeviceActions.traceroute(ip: host.ip) }
            }
            Text("Suggested actions are based on observed services. Other actions may still work if a service was not detected.")
                .font(.caption2)
                .foregroundStyle(OLSTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private struct ActionItem {
        let title: String
        let run: () -> Void
    }

    private func primaryActions(for host: HostRecord) -> [ActionItem] {
        var items: [ActionItem] = []
        let ports = Set(host.services.map(\.port))
        if ports.contains(445) {
            items.append(ActionItem(title: "Open SMB") { DeviceActions.openSMB(ip: host.ip) })
        }
        if ports.contains(443) {
            items.append(ActionItem(title: "Open HTTPS") { DeviceActions.openHTTP(ip: host.ip, secure: true) })
        } else if ports.contains(80) {
            items.append(ActionItem(title: "Open HTTP") { DeviceActions.openHTTP(ip: host.ip, secure: false) })
        }
        if ports.contains(22) {
            items.append(ActionItem(title: "SSH in Terminal") { DeviceActions.openSSH(ip: host.ip) })
        }
        if ports.contains(5900) {
            items.append(ActionItem(title: "Screen Sharing") { DeviceActions.openVNC(ip: host.ip) })
        }
        if ports.contains(3389) {
            items.append(ActionItem(title: "RDP…") {
                do { try DeviceActions.openRDP(ip: host.ip) }
                catch { actionError = error.localizedDescription }
            })
        }
        if items.isEmpty {
            items.append(ActionItem(title: "Copy IP") {
                DeviceActions.copyToPasteboard([host.ip.dotted])
                model.showAction("Copied IP \(host.ip.dotted)")
            })
            items.append(ActionItem(title: "Ping") { DeviceActions.ping(ip: host.ip) })
        }
        return Array(items.prefix(3))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(OLSTheme.text)
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(OLSTheme.mutedText)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statusSymbol(_ status: HostReachability) -> String {
        switch status {
        case .online: return "checkmark.circle.fill"
        case .offline: return "xmark.circle"
        case .unknown: return "questionmark.circle"
        }
    }

    private func statusColor(_ status: HostReachability) -> Color {
        switch status {
        case .online: return OLSTheme.success
        case .offline, .unknown: return OLSTheme.offline
        }
    }
}
