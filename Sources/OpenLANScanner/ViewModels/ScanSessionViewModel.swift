import AppKit
import Foundation
import Observation
import OpenLANScannerCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class ScanSessionViewModel {
    var interfaces: [NetworkInterfaceInfo] = []
    var selectedInterfaceID: String?
    var rangeText: String = ""
    var searchText: String = ""
    var showOnlineOnly = false
    var showFavoritesOnly = false
    var hosts: [HostRecord] = []
    var selectedHostID: String?
    var progress = ScanProgress()
    var isScanning = false
    var statusMessage: String = "Ready"
    var errorMessage: String?
    var permissionWarning: String?
    var actionBanner: String?
    var showLargeRangeConfirm = false
    var pendingAddressCount = 0
    var preferences: ScanPreferences
    var showInspector = true
    var elapsed: TimeInterval = 0
    var rangeEditedManually = false
    var selectedHostIDs: Set<String> = []
    var emptyState: EmptyStateKind = .firstLaunch
    var history: [ScanSnapshot] = []
    var historyRetention: Int = 50 {
        didSet {
            UserDefaults.standard.set(historyRetention, forKey: "ols.history.retention")
        }
    }
    var vendorLookup: OUIVendorLookup
    /// Compact results-table density (persisted).
    var compactTableDensity: Bool = UserDefaults.standard.bool(forKey: "ols.table.compact") {
        didSet { UserDefaults.standard.set(compactTableDensity, forKey: "ols.table.compact") }
    }
    /// Optional columns hidden by default; persisted independently.
    var showMACColumn: Bool = UserDefaults.standard.object(forKey: "ols.column.visible.mac") as? Bool ?? false {
        didSet { UserDefaults.standard.set(showMACColumn, forKey: "ols.column.visible.mac") }
    }
    var showVendorColumn: Bool = UserDefaults.standard.object(forKey: "ols.column.visible.vendor") as? Bool ?? false {
        didSet { UserDefaults.standard.set(showVendorColumn, forKey: "ols.column.visible.vendor") }
    }

    enum EmptyStateKind: Equatable {
        case firstLaunch
        case noInterface
        case scanning
        case noDevices
        case permissionDenied
        case noFilterMatches
        case idleWithResults
    }

    enum ExportScope {
        case allResults
        case filteredResults
        case selectedRows
    }

    private let engine: ScanEngine
    private let interfaceEnumerator: InterfaceEnumerating
    private let favoritesStore: FavoritesStoring
    private let preferencesStore: PreferencesStoring
    private var historyStore: ScanHistoryStoring
    private var favorites: [FavoriteDevice] = []
    private var scanStartedAt: Date?
    private var elapsedTimer: Timer?
    private var activeGeneration: UUID?
    private var scanConsumerTask: Task<Void, Never>?
    private var hasCompletedScan = false
    /// True only when launched with explicit `--demo-ui` / `OLS_DEMO_UI=1`.
    private(set) var isDemoScreenshotMode = false

    init(
        engine: ScanEngine = ScanEngine(),
        interfaceEnumerator: InterfaceEnumerating = SystemInterfaceEnumerator(),
        favoritesStore: FavoritesStoring? = nil,
        preferencesStore: PreferencesStoring = UserDefaultsPreferencesStore(),
        historyStore: ScanHistoryStoring? = nil
    ) {
        self.engine = engine
        self.interfaceEnumerator = interfaceEnumerator
        self.preferencesStore = preferencesStore
        self.preferences = preferencesStore.load()
        if let favoritesStore {
            self.favoritesStore = favoritesStore
        } else {
            self.favoritesStore = (try? FileFavoritesStore.applicationSupportStore())
                ?? InMemoryFavoritesStore()
        }
        if let historyStore {
            self.historyStore = historyStore
        } else {
            self.historyStore = (try? FileScanHistoryStore.applicationSupportStore())
                ?? InMemoryScanHistoryStore()
        }
        if UserDefaults.standard.object(forKey: "ols.history.retention") != nil {
            historyRetention = max(5, UserDefaults.standard.integer(forKey: "ols.history.retention"))
        }
        // Load OUI once (property no longer defaults to a second parse).
        vendorLookup = .loadDefault()
        refreshInterfaces(selectPreferred: true)
        reloadFavorites()
        reloadHistory()
    }

    var vendorDatasetDescription: String {
        let meta = vendorLookup.metadata
        let date = meta.importedAt?.formatted(date: .abbreviated, time: .omitted) ?? "bundled"
        return "\(meta.source) · \(meta.entryCount) assignments · \(meta.format) · \(date)"
    }

    var selectedInterface: NetworkInterfaceInfo? {
        interfaces.first(where: { $0.id == selectedInterfaceID })
    }

    var selectedHost: HostRecord? {
        hosts.first(where: { $0.id == selectedHostID })
    }

    var filteredHosts: [HostRecord] {
        var rows = hosts
        if showOnlineOnly {
            rows = rows.filter { $0.status == .online }
        }
        if showFavoritesOnly {
            rows = rows.filter(\.isFavorite)
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            rows = rows.filter { host in
                host.ip.dotted.lowercased().contains(query)
                    || (host.hostname?.lowercased().contains(query) ?? false)
                    || (host.macAddress?.lowercased().contains(query) ?? false)
                    || (host.vendor?.lowercased().contains(query) ?? false)
                    || (host.customName?.lowercased().contains(query) ?? false)
                    || host.displayName.lowercased().contains(query)
                    || host.services.contains { $0.name.lowercased().contains(query) }
            }
        }
        return rows.sorted { $0.ip < $1.ip }
    }

    func recomputeEmptyState() {
        if interfaces.filter(\.isUp).isEmpty {
            emptyState = .noInterface
        } else if permissionWarning != nil && hosts.filter({ $0.status == .online }).isEmpty && hasCompletedScan {
            emptyState = .permissionDenied
        } else if isScanning {
            emptyState = .scanning
        } else if !hosts.isEmpty && filteredHosts.isEmpty {
            emptyState = .noFilterMatches
        } else if hasCompletedScan && hosts.filter({ $0.status == .online }).isEmpty {
            emptyState = .noDevices
        } else if hosts.isEmpty {
            emptyState = .firstLaunch
        } else {
            emptyState = .idleWithResults
        }
    }

    /// Loads fictional RFC 5737 documentation hosts. Does not probe the network.
    func loadDemoScreenshotData() {
        isDemoScreenshotMode = true
        isScanning = false
        hasCompletedScan = true
        permissionWarning = nil
        errorMessage = nil
        rangeEditedManually = true
        rangeText = DemoScreenshotCatalog.rangeText
        // Replace live adapters so screenshots never leak private interface addresses.
        let demoInterface = NetworkInterfaceInfo(
            name: "en0",
            displayName: "Demo Wi‑Fi",
            ipv4: IPv4Address(string: "203.0.113.10")!,
            prefixLength: 24,
            isUp: true,
            isLoopback: false,
            isLikelyVPN: false
        )
        interfaces = [demoInterface]
        selectedInterfaceID = demoInterface.id
        hosts = DemoScreenshotCatalog.hosts()
        selectDemoHost(ip: "203.0.113.20")
        showInspector = true
        showOnlineOnly = false
        showFavoritesOnly = false
        searchText = ""
        progress = ScanProgress(
            completed: hosts.count,
            total: hosts.count,
            onlineCount: hosts.filter { $0.status == .online }.count,
            phase: .completed,
            interfaceNote: DemoScreenshotCatalog.interfaceNote
        )
        statusMessage = "Demo data — not a live network scan"
        actionBanner = "Screenshot mode: fictional TEST-NET-3 hosts (RFC 5737). No network probes were sent."
        elapsed = 4.2
        recomputeEmptyState()
    }

    func selectDemoHost(ip: String) {
        guard let host = hosts.first(where: { $0.ip.dotted == ip }) else { return }
        selectedHostID = host.id
        selectedHostIDs = [host.id]
    }

    func refreshInterfaces(selectPreferred: Bool) {
        if isDemoScreenshotMode {
            // Keep fictional adapter only — never reintroduce live addresses mid-capture.
            return
        }
        interfaces = interfaceEnumerator.usableIPv4Interfaces()
        if selectPreferred || selectedInterfaceID == nil {
            if let preferred = (interfaceEnumerator as? SystemInterfaceEnumerator)?.preferredInterface()
                ?? interfaces.first(where: { $0.isUp && !$0.isLikelyVPN })
                ?? interfaces.first {
                selectedInterfaceID = preferred.id
                if rangeText.isEmpty || !rangeEditedManually {
                    rangeText = preferred.suggestedScanExpression
                }
            }
        }
        recomputeEmptyState()
    }

    func applySelectedInterfaceSubnet() {
        guard let iface = selectedInterface else { return }
        rangeText = iface.suggestedScanExpression
        rangeEditedManually = false
        statusMessage = "Using subnet for \(iface.displayName)"
    }

    func suggestRangeForSelectedInterfaceIfAppropriate() {
        guard !rangeEditedManually, let iface = selectedInterface else { return }
        rangeText = iface.suggestedScanExpression
    }

    func applyClassC() {
        let seed: IPv4Address
        if let parsed = try? AddressRangeParser.parse(rangeText), let first = parsed.addresses.first {
            seed = first
        } else if let iface = selectedInterface {
            seed = iface.ipv4
        } else {
            return
        }
        let bounds = AddressRangeParser.classCRange(containing: seed)
        rangeText = AddressRangeParser.expression(from: bounds.start, to: bounds.end)
        rangeEditedManually = true
    }

    func savePreferences() {
        do {
            try preferencesStore.saveThrowing(preferences)
        } catch {
            errorMessage = "Could not save preferences: \(error.localizedDescription)"
        }
    }

    func reloadFavorites() {
        do {
            favorites = try favoritesStore.load()
            applyFavoritesOverlay()
        } catch {
            errorMessage = "Could not load favorites: \(error.localizedDescription)"
            favorites = []
        }
    }

    func reloadHistory() {
        do {
            history = try historyStore.load()
        } catch {
            errorMessage = "Could not load scan history: \(error.localizedDescription)"
            history = []
        }
    }

    func clearHistory() {
        history = []
        do {
            try historyStore.save([])
            showAction("Scan history cleared")
        } catch {
            errorMessage = "Could not clear history: \(error.localizedDescription)"
        }
    }

    func compareHistory(older: UUID?, newer: UUID?) -> ScanComparison? {
        guard let older, let newer,
              let a = history.first(where: { $0.id == older }),
              let b = history.first(where: { $0.id == newer })
        else { return nil }
        return ScanHistory.compare(older: a, newer: b)
    }

    func copySelectedRows() {
        let ids = selectedHostIDs.isEmpty
            ? Set(selectedHostID.map { [$0] } ?? [])
            : selectedHostIDs
        let rows = hosts.filter { ids.contains($0.id) }
        guard !rows.isEmpty else {
            showAction("Nothing selected to copy")
            return
        }
        let lines = rows.map { host in
            [
                host.status.displayLabel,
                host.ip.dotted,
                host.displayName,
                host.macAddress ?? "",
                host.vendor ?? "",
                host.services.map { "\($0.name):\($0.port)" }.joined(separator: " ")
            ].joined(separator: "\t")
        }
        DeviceActions.copyToPasteboard(lines)
        showAction("Copied \(rows.count) row(s)")
    }

    func copySelectedIPs() {
        let ids = selectedHostIDs.isEmpty
            ? Set(selectedHostID.map { [$0] } ?? [])
            : selectedHostIDs
        let ips = hosts.filter { ids.contains($0.id) }.map(\.ip.dotted)
        guard !ips.isEmpty else {
            showAction("Nothing selected to copy")
            return
        }
        DeviceActions.copyToPasteboard(ips)
        showAction("Copied \(ips.count) IP(s)")
    }

    func hosts(for scope: ExportScope) -> [HostRecord] {
        switch scope {
        case .allResults:
            return hosts
        case .filteredResults:
            return filteredHosts
        case .selectedRows:
            let ids = selectedHostIDs.isEmpty
                ? Set(selectedHostID.map { [$0] } ?? [])
                : selectedHostIDs
            return hosts.filter { ids.contains($0.id) }
        }
    }

    func importOUIDataset() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        panel.message = "Import an IEEE MA-L CSV or compact Assignment,Organization CSV. Previous valid data is kept if import fails."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            vendorLookup = try OUIVendorLookup.importCSV(from: url)
            showAction("Imported \(vendorLookup.metadata.entryCount) OUI assignments from \(url.lastPathComponent)")
        } catch {
            errorMessage = "OUI import failed (previous data kept): \(error.localizedDescription)"
        }
    }

    func toggleFavorite(_ host: HostRecord) {
        if let index = favorites.firstIndex(where: { $0.ip == host.ip }) {
            favorites.remove(at: index)
        } else {
            favorites.append(
                FavoriteDevice(
                    ip: host.ip,
                    macAddress: host.macAddress,
                    customName: host.customName ?? host.hostname ?? "",
                    notes: host.notes ?? ""
                )
            )
        }
        persistFavorites()
        applyFavoritesOverlay()
    }

    func updateFavoriteMetadata(for ip: IPv4Address, name: String, notes: String) {
        if let index = favorites.firstIndex(where: { $0.ip == ip }) {
            favorites[index].customName = name
            favorites[index].notes = notes
            favorites[index].updatedAt = Date()
        } else {
            favorites.append(FavoriteDevice(ip: ip, customName: name, notes: notes))
        }
        persistFavorites()
        applyFavoritesOverlay()
    }

    func exportFavoritesJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(favorites)
    }

    func importFavoritesJSON(_ data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let imported = try decoder.decode([FavoriteDevice].self, from: data)
        let validated = try FavoriteDevice.validateAndDeduplicate(imported)
        var map: [UInt32: FavoriteDevice] = [:]
        for item in favorites {
            map[item.ip.rawValue] = item
        }
        for item in validated {
            map[item.ip.rawValue] = item
        }
        favorites = Array(map.values).sorted { $0.ip < $1.ip }
        try favoritesStore.save(favorites)
        applyFavoritesOverlay()
        showAction("Imported \(validated.count) favorite(s)")
    }

    private func persistFavorites() {
        do {
            try favoritesStore.save(favorites)
        } catch {
            errorMessage = "Could not save favorites: \(error.localizedDescription)"
        }
    }

    private func persistHistorySnapshot(progress: ScanProgress) {
        let snapshot = ScanSnapshot(
            targetExpression: rangeText,
            interfaceNote: progress.interfaceNote ?? selectedInterface?.menuLabel,
            onlineCount: progress.onlineCount,
            probedCount: progress.total,
            preferencesSummary: preferencesSummaryLine(),
            hosts: hosts.map(ScanHostSnapshot.init(from:))
        )
        history.insert(snapshot, at: 0)
        if history.count > historyRetention {
            history = Array(history.prefix(historyRetention))
        }
        do {
            try historyStore.save(history)
        } catch {
            errorMessage = "Could not save scan history: \(error.localizedDescription)"
        }
    }

    private func preferencesSummaryLine() -> String {
        let discovery = preferences.enabledDiscoveryPorts.map(String.init).joined(separator: ",")
        let services = preferences.enabledServicePorts.map { "\($0.name):\($0.port)" }.joined(separator: ",")
        return "discovery=[\(discovery)] services=[\(services)] icmp=\(preferences.attemptICMP) bonjour=\(preferences.browseBonjour)"
    }

    func requestScan() {
        if isDemoScreenshotMode {
            statusMessage = "Demo mode — live scanning disabled"
            showAction("Demo screenshot mode does not send network probes. Relaunch without --demo-ui to scan.")
            return
        }
        errorMessage = nil
        do {
            let expansion = try AddressRangeParser.parse(rangeText)
            pendingAddressCount = expansion.count
            if expansion.count >= preferences.largeRangeWarningThreshold {
                showLargeRangeConfirm = true
            } else {
                startScan(addresses: expansion.addresses)
            }
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Invalid range"
        }
    }

    func confirmLargeRangeScan() {
        showLargeRangeConfirm = false
        if isDemoScreenshotMode { return }
        guard let expansion = try? AddressRangeParser.parse(rangeText) else { return }
        startScan(addresses: expansion.addresses)
    }

    func stopScan() {
        scanConsumerTask?.cancel()
        scanConsumerTask = nil
        let generation = activeGeneration
        activeGeneration = nil
        Task {
            await engine.cancel()
        }
        isScanning = false
        progress.phase = .stopped
        stopElapsed()
        statusMessage = "Scan stopped"
        recomputeEmptyState()
        _ = generation
    }

    func markRangeEdited() {
        rangeEditedManually = true
    }

    func showAction(_ message: String) {
        actionBanner = message
    }

    private func startScan(addresses: [IPv4Address]) {
        scanConsumerTask?.cancel()
        activeGeneration = nil
        permissionWarning = nil
        hosts.removeAll()
        selectedHostIDs.removeAll()
        applyFavoritesAsSeeds()
        isScanning = true
        progress = ScanProgress(total: addresses.count, phase: .running)
        statusMessage = "Scanning \(addresses.count) addresses…"
        scanStartedAt = Date()
        startElapsed()
        recomputeEmptyState()

        let iface = selectedInterface
        let constraint = ScanInterfaceConstraint(bsdName: iface?.name, ipv4: iface?.ipv4)
        var note: String?
        if let iface {
            note = iface.menuLabel
            if !iface.isUp {
                note = (note ?? "") + " — adapter appears down; results may be incomplete."
            }
            if iface.isLikelyVPN {
                note = (note ?? "") + " — VPN interfaces may not reflect LAN neighbors."
            }
        } else {
            note = "No interface selected; scanning without interface binding."
        }

        let configuration = ScanConfiguration(
            addresses: addresses,
            preferences: preferences,
            interface: constraint,
            interfaceNote: note
        )

        scanConsumerTask = Task {
            let stream = await engine.scan(configuration: configuration)
            for await event in stream {
                if Task.isCancelled { break }
                if activeGeneration == nil {
                    activeGeneration = event.generation
                } else if event.generation != activeGeneration {
                    continue
                }
                if !event.isEnrichmentOnly {
                    progress = event.progress
                }
                if let host = event.host {
                    upsert(host)
                }
                if event.progress.localNetworkDenied {
                    permissionWarning = "Local Network access is denied. Enable Open LAN Scanner in System Settings → Privacy & Security → Local Network."
                }
                if event.progress.isFinished {
                    isScanning = false
                    hasCompletedScan = true
                    stopElapsed()
                    switch event.progress.phase {
                    case .stopped:
                        statusMessage = "Scan stopped — \(event.progress.onlineCount) responded"
                    case .failed:
                        statusMessage = "Scan failed"
                    default:
                        statusMessage = "\(event.progress.onlineCount) responded of \(event.progress.total) probed"
                        persistHistorySnapshot(progress: event.progress)
                    }
                    recomputeEmptyState()
                }
            }
        }
    }

    private func upsert(_ host: HostRecord) {
        var merged = host
        if let favorite = favorites.first(where: { $0.ip == host.ip }) {
            merged.isFavorite = true
            merged.customName = favorite.customName.isEmpty ? merged.customName : favorite.customName
            merged.notes = favorite.notes.isEmpty ? merged.notes : favorite.notes
            if merged.macAddress == nil {
                merged.macAddress = favorite.macAddress
            }
        }
        if let index = hosts.firstIndex(where: { $0.ip == merged.ip }) {
            hosts[index].merge(merged)
        } else {
            hosts.append(merged)
        }
    }

    private func applyFavoritesOverlay() {
        let favoriteIPs = Set(favorites.map(\.ip))
        for index in hosts.indices {
            let ip = hosts[index].ip
            hosts[index].isFavorite = favoriteIPs.contains(ip)
            if let favorite = favorites.first(where: { $0.ip == ip }) {
                hosts[index].customName = favorite.customName.isEmpty ? hosts[index].customName : favorite.customName
                hosts[index].notes = favorite.notes
                if hosts[index].macAddress == nil {
                    hosts[index].macAddress = favorite.macAddress
                }
            }
        }
    }

    private func applyFavoritesAsSeeds() {
        for favorite in favorites {
            var record = HostRecord(
                ip: favorite.ip,
                status: .unknown,
                macAddress: favorite.macAddress,
                isFavorite: true,
                customName: favorite.customName,
                notes: favorite.notes
            )
            if let vendorMac = favorite.macAddress {
                record.vendor = vendorLookup.vendor(forMAC: vendorMac)
            }
            hosts.append(record)
        }
    }

    private func startElapsed() {
        elapsed = 0
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let started = self.scanStartedAt else { return }
                self.elapsed = Date().timeIntervalSince(started)
            }
        }
    }

    private func stopElapsed() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }
}
