import OpenLANScannerCore
import SwiftUI

@MainActor
struct ToolbarView: View {
    @Bindable var model: ScanSessionViewModel

    var body: some View {
        HStack(spacing: 10) {
            Picker("Interface", selection: $model.selectedInterfaceID) {
                ForEach(model.interfaces) { iface in
                    Text(iface.menuLabel).tag(Optional(iface.id))
                }
            }
            .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)
            .accessibilityLabel("Network interface")
            .onChange(of: model.selectedInterfaceID) { _, _ in
                model.suggestRangeForSelectedInterfaceIfAppropriate()
            }

            Button {
                model.applySelectedInterfaceSubnet()
            } label: {
                Image(systemName: "network")
            }
            .help("Use selected interface subnet")
            .accessibilityLabel("Use selected interface subnet")

            Button {
                model.applyClassC()
            } label: {
                Text("/24")
                    .font(.caption.monospaced())
            }
            .help("Snap to class C range")
            .accessibilityLabel("Snap to class C range")

            TextField(
                "IP, range, or CIDR",
                text: Binding(
                    get: { model.rangeText },
                    set: { model.rangeText = $0; model.markRangeEdited() }
                )
            )
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 200)
                .help("Examples: 192.168.1.0/24 or 192.168.1.1-254")
                .onSubmit { model.requestScan() }

            if model.isScanning {
                Button {
                    model.stopScan()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .keyboardShortcut(".", modifiers: [.command])
                .accessibilityLabel("Stop scan")
            } else {
                Button {
                    model.requestScan()
                } label: {
                    Label("Scan", systemImage: "play.fill")
                }
                .keyboardShortcut("r", modifiers: [.command])
                .accessibilityLabel("Start scan")
            }

            Toggle(isOn: $model.showOnlineOnly) {
                Image(systemName: "circle.fill")
            }
            .toggleStyle(.button)
            .help("Online only")
            .accessibilityLabel("Show online only")

            Toggle(isOn: $model.showFavoritesOnly) {
                Image(systemName: "star.fill")
            }
            .toggleStyle(.button)
            .help("Favorites only")
            .accessibilityLabel("Show favorites only")

            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(OLSTheme.mutedText)
                TextField("Search", text: $model.searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 140)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(OLSTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(OLSTheme.border, lineWidth: 1)
            )

            Toggle(isOn: $model.showInspector) {
                Image(systemName: "sidebar.trailing")
            }
            .toggleStyle(.button)
            .help("Toggle inspector")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(OLSTheme.background)
    }
}
