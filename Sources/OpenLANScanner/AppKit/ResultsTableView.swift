import AppKit
import OpenLANScannerCore
import SwiftUI

struct ResultsTableView: NSViewRepresentable {
    var hosts: [HostRecord]
    @Binding var selection: String?
    @Binding var selectedIDs: Set<String>
    var sortColumn: String
    var sortAscending: Bool
    var onSortChange: ((String, Bool) -> Void)?
    var onDoubleClick: ((HostRecord) -> Void)?
    var onContextAction: ((HostRecord, ResultsTableContextAction) -> Void)?

    enum ResultsTableContextAction {
        case favorite, copyIP, copyRows, smb, http, https, ssh, vnc, rdp, wol, ping
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let table = NSTableView()
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.allowsMultipleSelection = true
        table.allowsColumnResizing = true
        table.allowsColumnReordering = true
        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 22
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.doubleClicked(_:))
        table.menu = context.coordinator.makeMenu()
        table.style = .plain

        for column in Coordinator.makeColumns() {
            table.addTableColumn(column)
        }
        context.coordinator.applySortIndicators(on: table)

        scroll.documentView = table
        context.coordinator.tableView = table
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        let previousSelection = selectedIDs
        let previousScroll = (nsView.documentView as? NSTableView).map {
            $0.enclosingScrollView?.contentView.bounds.origin.y ?? 0
        } ?? 0

        let sortUnchanged = coordinator.lastSortColumn == sortColumn
            && coordinator.lastSortAscending == sortAscending
        // Skip re-sort + full reload when the presented rows are unchanged (common during
        // selection-only / timer-driven SwiftUI updates).
        let dataUnchanged = sortUnchanged && coordinator.hosts == hosts
        if !dataUnchanged {
            let sorted = Self.sorted(hosts, column: sortColumn, ascending: sortAscending)
            let oldIDs = coordinator.hosts.map(\.id)
            let newIDs = sorted.map(\.id)
            coordinator.hosts = sorted
            coordinator.lastSortColumn = sortColumn
            coordinator.lastSortAscending = sortAscending
            coordinator.applySortIndicators(on: coordinator.tableView)

            if let table = coordinator.tableView {
                if oldIDs != newIDs {
                    table.reloadData()
                } else {
                    // Same row identities: refresh visible cells only (enrichment / latency updates).
                    let visibleRange = table.rows(in: table.visibleRect)
                    let cols = IndexSet(integersIn: 0..<table.numberOfColumns)
                    if visibleRange.length > 0 {
                        let rows = IndexSet(integersIn: visibleRange.location..<(visibleRange.location + visibleRange.length))
                        table.reloadData(forRowIndexes: rows, columnIndexes: cols)
                    } else {
                        table.reloadData()
                    }
                }
            }
        } else {
            coordinator.applySortIndicators(on: coordinator.tableView)
        }

        if let table = coordinator.tableView {
            let rows = coordinator.hosts
            var indexes = IndexSet()
            for id in previousSelection {
                if let row = rows.firstIndex(where: { $0.id == id }) {
                    indexes.insert(row)
                }
            }
            table.selectRowIndexes(indexes, byExtendingSelection: false)
            if let clip = table.enclosingScrollView?.contentView {
                clip.scroll(to: NSPoint(x: 0, y: previousScroll))
                table.enclosingScrollView?.reflectScrolledClipView(clip)
            }
            if let selected = selection, let row = rows.firstIndex(where: { $0.id == selected }) {
                table.scrollRowToVisible(row)
            }
        }
    }

    static func sorted(_ hosts: [HostRecord], column: String, ascending: Bool) -> [HostRecord] {
        let sorted = hosts.sorted { lhs, rhs in
            let result: ComparisonResult
            switch column {
            case "status":
                result = lhs.status.rawValue.compare(rhs.status.rawValue)
            case "ip":
                result = lhs.ip.rawValue < rhs.ip.rawValue ? .orderedAscending
                    : lhs.ip.rawValue > rhs.ip.rawValue ? .orderedDescending : .orderedSame
            case "hostname":
                result = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
            case "mac":
                result = (lhs.macAddress ?? "").compare(rhs.macAddress ?? "")
            case "vendor":
                result = (lhs.vendor ?? "").localizedCaseInsensitiveCompare(rhs.vendor ?? "")
            case "latency":
                let l = lhs.responseTimeMs ?? Double.greatestFiniteMagnitude
                let r = rhs.responseTimeMs ?? Double.greatestFiniteMagnitude
                result = l < r ? .orderedAscending : l > r ? .orderedDescending : .orderedSame
            case "services":
                result = lhs.services.map(\.name).joined().compare(rhs.services.map(\.name).joined())
            default:
                result = .orderedSame
            }
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }
        return sorted
    }

    final class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        var parent: ResultsTableView
        var hosts: [HostRecord] = []
        var lastSortColumn: String = ""
        var lastSortAscending: Bool = true
        weak var tableView: NSTableView?

        init(parent: ResultsTableView) {
            self.parent = parent
            self.hosts = parent.hosts
            self.lastSortColumn = parent.sortColumn
            self.lastSortAscending = parent.sortAscending
        }

        static func makeColumns() -> [NSTableColumn] {
            let defaults = UserDefaults.standard
            let specs: [(String, String, CGFloat)] = [
                ("status", "Status", 90),
                ("ip", "IP Address", 120),
                ("hostname", "Name", 160),
                ("mac", "MAC Address", 130),
                ("vendor", "Vendor", 160),
                ("latency", "Response", 90),
                ("services", "Services", 180)
            ]
            return specs.map { id, title, width in
                let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
                column.title = title
                let key = "ols.column.width.\(id)"
                column.width = CGFloat(defaults.double(forKey: key)).nonZero ?? width
                column.minWidth = 50
                column.resizingMask = [.userResizingMask, .autoresizingMask]
                return column
            }
        }

        func applySortIndicators(on table: NSTableView?) {
            guard let table else { return }
            for column in table.tableColumns {
                if column.identifier.rawValue == parent.sortColumn {
                    table.highlightedTableColumn = column
                    column.sortDescriptorPrototype = NSSortDescriptor(
                        key: column.identifier.rawValue,
                        ascending: parent.sortAscending
                    )
                }
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int { hosts.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < hosts.count, let tableColumn else { return nil }
            let host = hosts[row]
            let id = tableColumn.identifier.rawValue
            let text = value(for: host, column: id)
            let cellID = NSUserInterfaceItemIdentifier("cell-\(id)")
            let label: NSTextField
            if let reused = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTextField {
                label = reused
            } else {
                label = NSTextField(labelWithString: "")
                label.identifier = cellID
                label.lineBreakMode = .byTruncatingTail
                label.font = id == "ip" || id == "mac" || id == "latency"
                    ? NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
                    : NSFont.systemFont(ofSize: 12)
            }
            label.stringValue = text
            label.toolTip = text == "—" ? nil : text
            label.textColor = color(for: host, column: id)
            label.setAccessibilityLabel("\(tableColumn.title): \(text)")
            return label
        }

        func tableViewColumnDidResize(_ notification: Notification) {
            guard let column = notification.userInfo?["NSTableColumn"] as? NSTableColumn else { return }
            UserDefaults.standard.set(Double(column.width), forKey: "ols.column.width.\(column.identifier.rawValue)")
        }

        func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
            let id = tableColumn.identifier.rawValue
            if parent.sortColumn == id {
                parent.onSortChange?(id, !parent.sortAscending)
            } else {
                parent.onSortChange?(id, true)
            }
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView else { return }
            var ids = Set<String>()
            for row in tableView.selectedRowIndexes {
                if row >= 0, row < hosts.count {
                    ids.insert(hosts[row].id)
                }
            }
            parent.selectedIDs = ids
            parent.selection = ids.count == 1 ? ids.first : tableView.selectedRowIndexes.first.flatMap { row in
                row < hosts.count ? hosts[row].id : nil
            }
        }

        @objc func doubleClicked(_ sender: Any?) {
            guard let tableView, tableView.clickedRow >= 0, tableView.clickedRow < hosts.count else { return }
            parent.onDoubleClick?(hosts[tableView.clickedRow])
        }

        func makeMenu() -> NSMenu {
            let menu = NSMenu(title: "Host")
            let items: [(String, Selector)] = [
                ("Toggle Favorite", #selector(ctxFavorite)),
                ("Copy IP Address", #selector(ctxCopyIP)),
                ("Copy Selected Rows", #selector(ctxCopyRows)),
                ("Open SMB in Finder", #selector(ctxSMB)),
                ("Open HTTP", #selector(ctxHTTP)),
                ("Open HTTPS", #selector(ctxHTTPS)),
                ("Open SSH…", #selector(ctxSSH)),
                ("Screen Sharing (VNC)", #selector(ctxVNC)),
                ("Remote Desktop (RDP)…", #selector(ctxRDP)),
                ("Wake-on-LAN", #selector(ctxWOL)),
                ("Ping in Terminal", #selector(ctxPing))
            ]
            for (title, sel) in items {
                let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
                item.target = self
                menu.addItem(item)
            }
            return menu
        }

        private func currentHost() -> HostRecord? {
            guard let tableView else { return nil }
            let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
            guard row >= 0, row < hosts.count else { return nil }
            return hosts[row]
        }

        @objc func ctxFavorite() { if let h = currentHost() { parent.onContextAction?(h, .favorite) } }
        @objc func ctxCopyIP() { if let h = currentHost() { parent.onContextAction?(h, .copyIP) } }
        @objc func ctxCopyRows() { if let h = currentHost() { parent.onContextAction?(h, .copyRows) } }
        @objc func ctxSMB() { if let h = currentHost() { parent.onContextAction?(h, .smb) } }
        @objc func ctxHTTP() { if let h = currentHost() { parent.onContextAction?(h, .http) } }
        @objc func ctxHTTPS() { if let h = currentHost() { parent.onContextAction?(h, .https) } }
        @objc func ctxSSH() { if let h = currentHost() { parent.onContextAction?(h, .ssh) } }
        @objc func ctxVNC() { if let h = currentHost() { parent.onContextAction?(h, .vnc) } }
        @objc func ctxRDP() { if let h = currentHost() { parent.onContextAction?(h, .rdp) } }
        @objc func ctxWOL() { if let h = currentHost() { parent.onContextAction?(h, .wol) } }
        @objc func ctxPing() { if let h = currentHost() { parent.onContextAction?(h, .ping) } }

        private func value(for host: HostRecord, column: String) -> String {
            switch column {
            case "status":
                return host.status.displayLabel + (host.isFavorite ? " ★" : "")
            case "ip": return host.ip.dotted
            case "hostname": return host.displayName
            case "mac": return host.macAddress ?? "—"
            case "vendor": return host.vendor ?? "—"
            case "latency":
                if let ms = host.responseTimeMs {
                    let kind = host.latencyKind == .icmp ? "icmp" : "tcp"
                    return String(format: "%.0f ms (%@)", ms, kind)
                }
                return "—"
            case "services":
                return host.services.isEmpty ? "—" : host.services.map(\.name).joined(separator: ", ")
            default: return "—"
            }
        }

        private func color(for host: HostRecord, column: String) -> NSColor {
            if column == "status" {
                switch host.status {
                case .online: return NSColor(srgbRed: 0.11, green: 0.50, blue: 0.29, alpha: 1)
                case .offline, .unknown: return .secondaryLabelColor
                }
            }
            return .labelColor
        }
    }
}

private extension CGFloat {
    var nonZero: CGFloat? { self > 0 ? self : nil }
}
