import OpenLANScannerCore
import SwiftUI

@MainActor
struct ToolbarView: View {
    @Bindable var model: ScanSessionViewModel

    private var filterActive: Bool {
        model.showOnlineOnly || model.showFavoritesOnly || !model.searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            fullToolbar
            compactToolbar
        }
        .padding(.horizontal, OLSTheme.contentInset)
        .padding(.vertical, OLSTheme.controlGap)
        .background(OLSTheme.background)
    }

    private var fullToolbar: some View {
        HStack(alignment: .center, spacing: OLSTheme.toolbarGroupGap) {
            scanGroup
            filterMenu
            Spacer(minLength: OLSTheme.controlGap)
            searchField
                .frame(width: 160)
            inspectorToggle
        }
    }

    private var compactToolbar: some View {
        HStack(alignment: .center, spacing: OLSTheme.controlGap) {
            scanGroupCompact
            Menu {
                rangeOptions
                Divider()
                filterMenuContent
                Divider()
                Button {
                    model.showInspector.toggle()
                } label: {
                    Label(model.showInspector ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.trailing")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .help("More controls")
            .accessibilityLabel("More toolbar actions")
            Spacer(minLength: 4)
            searchField
                .frame(minWidth: 100, maxWidth: 140)
        }
    }

    private var scanGroup: some View {
        HStack(spacing: OLSTheme.controlGap) {
            Picker("Interface", selection: $model.selectedInterfaceID) {
                ForEach(model.interfaces) { iface in
                    Text(iface.menuLabel).tag(Optional(iface.id))
                }
            }
            .labelsHidden()
            .frame(minWidth: 160, idealWidth: 200, maxWidth: 260)
            .accessibilityLabel("Network interface")
            .onChange(of: model.selectedInterfaceID) { _, _ in
                model.suggestRangeForSelectedInterfaceIfAppropriate()
            }

            Menu {
                rangeOptions
            } label: {
                Label("Range", systemImage: "slider.horizontal.3")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .help("Range options")
            .accessibilityLabel("Range options")

            TextField(
                "IP, range, or CIDR",
                text: Binding(
                    get: { model.rangeText },
                    set: { model.rangeText = $0; model.markRangeEdited() }
                )
            )
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)
            .help("Examples: 192.168.1.0/24 or 192.168.1.1-254")
            .accessibilityLabel("Scan target range")
            .onSubmit { model.requestScan() }

            scanStopButton
        }
    }

    private var scanGroupCompact: some View {
        HStack(spacing: OLSTheme.controlGap) {
            Picker("Interface", selection: $model.selectedInterfaceID) {
                ForEach(model.interfaces) { iface in
                    Text(iface.displayName).tag(Optional(iface.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 140)
            .accessibilityLabel("Network interface")
            .onChange(of: model.selectedInterfaceID) { _, _ in
                model.suggestRangeForSelectedInterfaceIfAppropriate()
            }

            TextField(
                "Target",
                text: Binding(
                    get: { model.rangeText },
                    set: { model.rangeText = $0; model.markRangeEdited() }
                )
            )
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 120, maxWidth: 200)
            .accessibilityLabel("Scan target range")
            .onSubmit { model.requestScan() }

            scanStopButton
        }
    }

    @ViewBuilder
    private var scanStopButton: some View {
        if model.isScanning {
            Button {
                model.stopScan()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .keyboardShortcut(".", modifiers: [.command])
            .accessibilityLabel("Stop scan")
            .help("Stop scan (⌘.)")
        } else {
            Button {
                model.requestScan()
            } label: {
                Label("Scan", systemImage: "play.fill")
            }
            .keyboardShortcut("r", modifiers: [.command])
            .buttonStyle(.borderedProminent)
            .tint(OLSTheme.accent)
            .accessibilityLabel("Start scan")
            .help("Start scan (⌘R)")
        }
    }

    @ViewBuilder
    private var rangeOptions: some View {
        Button("Use Interface Subnet") { model.applySelectedInterfaceSubnet() }
        Button("Snap to /24") { model.applyClassC() }
        Divider()
        Button("Refresh Interfaces") { model.refreshInterfaces(selectPreferred: false) }
    }

    private var filterMenu: some View {
        Menu {
            filterMenuContent
        } label: {
            Label {
                Text(filterActive ? "Filters●" : "Filters")
            } icon: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
        }
        .menuStyle(.borderlessButton)
        .help(filterActive ? "Filters active" : "Filters")
        .accessibilityLabel(filterActive ? "Filters, active" : "Filters")
        .foregroundStyle(filterActive ? OLSTheme.accent : OLSTheme.text)
    }

    @ViewBuilder
    private var filterMenuContent: some View {
        Toggle("Responding only", isOn: $model.showOnlineOnly)
        Toggle("Favorites only", isOn: $model.showFavoritesOnly)
        Divider()
        Button("Clear Filters") {
            model.searchText = ""
            model.showOnlineOnly = false
            model.showFavoritesOnly = false
            model.recomputeEmptyState()
        }
        .disabled(!filterActive)
    }

    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(OLSTheme.mutedText)
            TextField("Search", text: $model.searchText)
                .textFieldStyle(.plain)
                .accessibilityLabel("Search results")
        }
        .padding(.horizontal, OLSTheme.controlGap)
        .padding(.vertical, 5)
        .background(OLSTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(OLSTheme.border, lineWidth: 1)
        )
    }

    private var inspectorToggle: some View {
        Toggle(isOn: $model.showInspector) {
            Image(systemName: "sidebar.trailing")
        }
        .toggleStyle(.button)
        .help("Toggle inspector")
        .accessibilityLabel("Toggle inspector")
    }
}
