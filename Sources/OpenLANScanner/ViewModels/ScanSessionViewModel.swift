import Foundation
import Observation
import OpenLANScannerCore
import SwiftUI

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
    var showLargeRangeConfirm = false
    var pendingAddressCount = 0
    var preferences: ScanPreferences
    var showInspector = true
    var elapsed: TimeInterval = 0

    private let engine: ScanEngine
    private let interfaceEnumerator: InterfaceEnumerating
    private let favoritesStore: FavoritesStoring
    private let preferencesStore: PreferencesStoring
    private var favorites: [FavoriteDevice] = []
    private var scanStartedAt: Date?
    private var elapsedTimer: Timer?
    private var activeGeneration: UUID?
    private var scanConsumerTask: Task<Void, Never>?

    init(
        engine: ScanEngine = ScanEngine(),
        interfaceEnumerator: InterfaceEnumerating = SystemInterfaceEnumerator(),
        favoritesStore: FavoritesStoring? = nil,
        preferencesStore: PreferencesStoring = UserDefaultsPreferencesStore()
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
        refreshInterfaces(selectPreferred: true)
        reloadFavorites()
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
                    || host.services.contains { $0.name.lowercased().contains(query) }
            }
        }
        return rows.sorted { $0.ip < $1.ip }
    }

    func refreshInterfaces(selectPreferred: Bool) {
        interfaces = interfaceEnumerator.usableIPv4Interfaces()
        if selectPreferred || selectedInterfaceID == nil {
            if let preferred = (interfaceEnumerator as? SystemInterfaceEnumerator)?.preferredInterface()
                ?? interfaces.first(where: { $0.isUp && !$0.isLikelyVPN })
                ?? interfaces.first {
                selectedInterfaceID = preferred.id
                if rangeText.isEmpty {
                    rangeText = preferred.suggestedScanExpression
                }
            }
        }
    }

    func applySelectedInterfaceSubnet() {
        guard let iface = selectedInterface else { return }
        rangeText = iface.suggestedScanExpression
        statusMessage = "Using subnet for \(iface.displayName)"
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
    }

    func savePreferences() {
        preferencesStore.save(preferences)
    }

    func reloadFavorites() {
        favorites = (try? favoritesStore.load()) ?? []
        applyFavoritesOverlay()
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
        try? favoritesStore.save(favorites)
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
        try? favoritesStore.save(favorites)
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
        var map = Dictionary(uniqueKeysWithValues: favorites.map { ($0.ip.rawValue, $0) })
        for item in imported {
            map[item.ip.rawValue] = item
        }
        favorites = Array(map.values).sorted { $0.ip < $1.ip }
        try favoritesStore.save(favorites)
        applyFavoritesOverlay()
    }

    func requestScan() {
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
        guard let expansion = try? AddressRangeParser.parse(rangeText) else { return }
        startScan(addresses: expansion.addresses)
    }

    func stopScan() {
        scanConsumerTask?.cancel()
        scanConsumerTask = nil
        activeGeneration = nil
        Task {
            await engine.cancel()
        }
        isScanning = false
        stopElapsed()
        statusMessage = "Scan stopped"
    }

    private func startScan(addresses: [IPv4Address]) {
        scanConsumerTask?.cancel()
        activeGeneration = nil
        hosts.removeAll()
        applyFavoritesAsSeeds()
        isScanning = true
        progress = ScanProgress(total: addresses.count)
        statusMessage = "Scanning \(addresses.count) addresses…"
        scanStartedAt = Date()
        startElapsed()

        scanConsumerTask = Task {
            let stream = await engine.scan(addresses: addresses, preferences: preferences)
            for await event in stream {
                if Task.isCancelled { break }
                if activeGeneration == nil {
                    activeGeneration = event.generation
                } else if event.generation != activeGeneration {
                    continue
                }
                progress = event.progress
                if let host = event.host {
                    upsert(host)
                }
                if event.progress.localNetworkDenied {
                    errorMessage = "Local Network access is denied. Enable Open LAN Scanner in System Settings → Privacy & Security → Local Network."
                }
                if event.progress.isFinished {
                    isScanning = false
                    stopElapsed()
                    statusMessage = "Found \(event.progress.onlineCount) online of \(event.progress.total)"
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
                record.vendor = OUIVendorLookup.loadBundledSample().vendor(forMAC: vendorMac)
            }
            hosts.append(record)
        }
    }

    private func startElapsed() {
        elapsed = 0
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
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
