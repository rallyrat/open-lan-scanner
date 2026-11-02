import OpenLANScannerCore
import SwiftUI

@MainActor
struct PreferencesView: View {
    @Bindable var model: ScanSessionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClearHistory = false

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            discoveryTab.tabItem { Label("Discovery", systemImage: "antenna.radiowaves.left.and.right") }
            servicesTab.tabItem { Label("Services", systemImage: "switch.2") }
            dataTab.tabItem { Label("Data", systemImage: "externaldrive") }
            advancedTab.tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        .padding(OLSTheme.contentInset)
        .frame(width: 560, height: 480)
        .alert("Clear scan history?", isPresented: $confirmClearHistory) {
            Button("Cancel", role: .cancel) {}
            Button("Clear History", role: .destructive) { model.clearHistory() }
        } message: {
            Text("Removes saved scan snapshots from this Mac only. Favorites and preferences are kept.")
        }
    }

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Compact results table", isOn: $model.compactTableDensity)
                Toggle("Show MAC Address column", isOn: $model.showMACColumn)
                Toggle("Show Vendor column", isOn: $model.showVendorColumn)
            } footer: {
                Text("Name, IP, Status, Services, and Response stay visible. MAC and Vendor remain in the inspector.")
            }
            Section {
                Toggle("Resolve hostnames", isOn: $model.preferences.resolveHostnames)
                Toggle("Look up neighbor MAC addresses", isOn: $model.preferences.lookupNeighbors)
                Toggle("Look up vendors (OUI)", isOn: $model.preferences.lookupVendors)
            }
            Section {
                Button("Done") {
                    model.savePreferences()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
    }

    private var discoveryTab: some View {
        Form {
            Section {
                Text("Discovery probes check whether a host shows live evidence (open TCP, refused TCP, ICMP, or Bonjour). They are not listed as services.")
                    .font(.caption)
                    .foregroundStyle(OLSTheme.mutedText)
                Toggle("Attempt ICMP echo (best-effort)", isOn: $model.preferences.attemptICMP)
                Toggle("Browse Bonjour services (best-effort)", isOn: $model.preferences.browseBonjour)
            }
            Section("Discovery ports") {
                ForEach($model.preferences.discoveryProbes) { $probe in
                    Toggle("TCP \(portLabel(probe.port))", isOn: $probe.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .onDisappear { model.savePreferences() }
    }

    private var servicesTab: some View {
        Form {
            Section {
                Text("Service probes are listed on a host only when the TCP port is open. A closed or filtered port does not prove the service is absent.")
                    .font(.caption)
                    .foregroundStyle(OLSTheme.mutedText)
            }
            Section("Service enumeration") {
                ForEach($model.preferences.services) { $service in
                    Toggle("\(service.name) (\(portLabel(service.port)))", isOn: $service.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .onDisappear { model.savePreferences() }
    }

    private var dataTab: some View {
        Form {
            Section("Vendor database") {
                Text(model.vendorDatasetDescription)
                    .font(.caption)
                    .foregroundStyle(OLSTheme.mutedText)
                Button("Import IEEE / OUI CSV…") { model.importOUIDataset() }
            }
            Section("Saved scans") {
                HStack {
                    Text("Keep recent scans")
                    Spacer()
                    TextField(
                        "",
                        value: Binding(
                            get: { model.historyRetention },
                            set: { model.historyRetention = min(200, max(5, $0)) }
                        ),
                        format: .number.grouping(.never)
                    )
                    .frame(width: 56)
                    .textFieldStyle(.roundedBorder)
                    Stepper("", value: $model.historyRetention, in: 5...200)
                        .labelsHidden()
                }
                Button("Clear History…", role: .destructive) {
                    confirmClearHistory = true
                }
            }
        }
        .formStyle(.grouped)
        .onDisappear { model.savePreferences() }
    }

    private var advancedTab: some View {
        Form {
            Section {
                labeledIntField(
                    title: "Discovery concurrency",
                    value: Binding(
                        get: { model.preferences.concurrency },
                        set: { model.preferences.concurrency = min(512, max(1, $0)) }
                    ),
                    rangeHint: "1–512"
                )
                labeledIntField(
                    title: "Enrichment concurrency",
                    value: Binding(
                        get: { model.preferences.enrichmentConcurrency },
                        set: { model.preferences.enrichmentConcurrency = min(64, max(1, $0)) }
                    ),
                    rangeHint: "1–64"
                )
                labeledIntField(
                    title: "Connect timeout (ms)",
                    value: Binding(
                        get: { model.preferences.connectTimeoutMs },
                        set: { model.preferences.connectTimeoutMs = min(5000, max(50, $0)) }
                    ),
                    rangeHint: "50–5000"
                )
                labeledIntField(
                    title: "Probe retries",
                    value: Binding(
                        get: { model.preferences.probeRetries },
                        set: { model.preferences.probeRetries = min(5, max(1, $0)) }
                    ),
                    rangeHint: "1–5"
                )
            } footer: {
                Text("Higher concurrency scans faster but may stress routers or trip rate limits.")
            }
        }
        .formStyle(.grouped)
        .onDisappear { model.savePreferences() }
    }

    private func labeledIntField(title: String, value: Binding<Int>, rangeHint: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("", value: value, format: .number.grouping(.never))
                .frame(width: 64)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
            Text(rangeHint)
                .font(.caption2)
                .foregroundStyle(OLSTheme.mutedText)
        }
    }

    private func portLabel(_ port: UInt16) -> String {
        // Avoid locale thousands separators (3389, not 3,389).
        String(port)
    }
}
