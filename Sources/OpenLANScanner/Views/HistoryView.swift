import OpenLANScannerCore
import SwiftUI

@MainActor
struct HistoryView: View {
    @Bindable var model: ScanSessionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedEarlier: UUID?
    @State private var selectedLater: UUID?
    @State private var comparison: ScanComparison?
    @State private var compareError: String?

    private var canCompare: Bool {
        guard let earlier = selectedEarlier, let later = selectedLater, earlier != later else { return false }
        return model.history.contains(where: { $0.id == earlier })
            && model.history.contains(where: { $0.id == later })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OLSTheme.relatedGap) {
            Text("Saved Scans")
                .font(.title2.weight(.semibold))
            Text("Snapshots stay on this Mac. A missing response in a later scan does not prove a device left the network.")
                .font(.caption)
                .foregroundStyle(OLSTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)

            if model.history.isEmpty {
                ContentUnavailableView(
                    "No saved scans yet",
                    systemImage: "clock",
                    description: Text("Completed scans appear here for comparison.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.history) { snap in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snap.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.body.weight(.medium))
                        Text("\(snap.targetExpression) · \(snap.onlineCount) responded / \(snap.probedCount) probed")
                            .font(.caption)
                            .foregroundStyle(OLSTheme.mutedText)
                            .lineLimit(2)
                    }
                    .tag(snap.id)
                }
                .frame(minHeight: 160)

                HStack(alignment: .top, spacing: OLSTheme.relatedGap) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Earlier scan")
                            .font(.caption)
                            .foregroundStyle(OLSTheme.mutedText)
                        Picker("Earlier scan", selection: $selectedEarlier) {
                            Text("Choose…").tag(Optional<UUID>.none)
                            ForEach(model.history) { snap in
                                Text(snap.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .tag(Optional(snap.id))
                            }
                        }
                        .labelsHidden()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Later scan")
                            .font(.caption)
                            .foregroundStyle(OLSTheme.mutedText)
                        Picker("Later scan", selection: $selectedLater) {
                            Text("Choose…").tag(Optional<UUID>.none)
                            ForEach(model.history) { snap in
                                Text(snap.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .tag(Optional(snap.id))
                            }
                        }
                        .labelsHidden()
                    }
                    VStack {
                        Spacer(minLength: 14)
                        Button("Compare") { runCompare() }
                            .disabled(!canCompare)
                    }
                }

                if let compareError {
                    Text(compareError)
                        .font(.caption)
                        .foregroundStyle(OLSTheme.error)
                }

                if let comparison {
                    GroupBox("Comparison") {
                        ScrollView {
                            VStack(alignment: .leading, spacing: OLSTheme.controlGap) {
                                ForEach(comparison.uncertainMatches, id: \.self) { note in
                                    Label(note, systemImage: "exclamationmark.triangle")
                                        .font(.caption)
                                        .foregroundStyle(OLSTheme.warning)
                                }
                                deviceGroup("Newly observed", comparison.newlyObserved)
                                deviceGroup("Previously observed, no response this scan", comparison.previouslyObservedNoResponse)
                                Text("Changed services: \(comparison.changedServices.count)")
                                    .font(.caption)
                                Text("A “no response” row is uncertain — the host may be offline, filtered, or simply quiet.")
                                    .font(.caption2)
                                    .foregroundStyle(OLSTheme.mutedText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 180)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(OLSTheme.contentInset)
        .frame(minWidth: 560, idealWidth: 600, minHeight: 480, idealHeight: 560)
        .onAppear {
            if selectedLater == nil {
                selectedLater = model.history.first?.id
            }
            if selectedEarlier == nil {
                selectedEarlier = model.history.dropFirst().first?.id
            }
        }
    }

    private func runCompare() {
        compareError = nil
        comparison = nil
        guard let earlierID = selectedEarlier, let laterID = selectedLater, earlierID != laterID else {
            compareError = "Choose two different saved scans."
            return
        }
        guard let earlier = model.history.first(where: { $0.id == earlierID }),
              let later = model.history.first(where: { $0.id == laterID }) else {
            compareError = "One of the selected scans is no longer available."
            return
        }
        let orderedOlder = earlier.createdAt <= later.createdAt ? earlier : later
        let orderedNewer = earlier.createdAt <= later.createdAt ? later : earlier
        if orderedOlder.targetExpression != orderedNewer.targetExpression {
            compareError = "Targets differ (\(orderedOlder.targetExpression) vs \(orderedNewer.targetExpression)). Comparison may mix unrelated ranges."
        }
        comparison = ScanHistory.compare(older: orderedOlder, newer: orderedNewer)
    }

    @ViewBuilder
    private func deviceGroup(_ title: String, _ hosts: [ScanHostSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
            if hosts.isEmpty {
                Text("None")
                    .font(.caption)
                    .foregroundStyle(OLSTheme.mutedText)
            } else {
                ForEach(hosts) { host in
                    HStack {
                        Text(host.ip.dotted)
                            .font(.caption.monospacedDigit())
                        if let name = host.hostname, !name.isEmpty {
                            Text(name)
                                .font(.caption)
                                .foregroundStyle(OLSTheme.mutedText)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }
}
