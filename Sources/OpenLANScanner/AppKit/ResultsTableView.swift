import AppKit
import OpenLANScannerCore
import SwiftUI

struct ResultsTableView: NSViewRepresentable {
    var hosts: [HostRecord]
    @Binding var selection: String?
    @Binding var selectedIDs: Set<String>
    var sortColumn: String
    var sortAscending: Bool
    var compactDensity: Bool
    var showMACColumn: Bool
    var showVendorColumn: Bool
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
        table.rowHeight = compactDensity ? OLSTheme.tableRowHeightCompact : OLSTheme.tableRowHeight
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.doubleClicked(_:))
        table.menu = context.coordinator.makeMenu()
        table.style = .inset
        table.headerView = NSTableHeaderView()

        for column in Coordinator.makeColumns() {
            table.addTableColumn(column)
        }
        context.coordinator.applyColumnVisibility(on: table)
        context.coordinator.applySortIndicators(on: table)
        context.coordinator.applyDensity(on: table)

        scroll.documentView = table
        context.coordinator.tableView = table
        // Defer fit until the scroll view has a real width (SwiftUI first layout).
        DispatchQueue.main.async {
            table.sizeLastColumnToFit()
        }
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        let previousScroll = (nsView.documentView as? NSTableView).map {
            $0.enclosingScrollView?.contentView.bounds.origin.y ?? 0
        } ?? 0

        let sortUnchanged = coordinator.lastSortColumn == sortColumn
            && coordinator.lastSortAscending == sortAscending
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
            let densityChanged = coordinator.lastCompactDensity != compactDensity
            let visibilityChanged = coordinator.lastShowMAC != showMACColumn
                || coordinator.lastShowVendor != showVendorColumn
            coordinator.applyDensity(on: table)
            coordinator.applyColumnVisibility(on: table)
            coordinator.lastCompactDensity = compactDensity
            coordinator.lastShowMAC = showMACColumn
            coordinator.lastShowVendor = showVendorColumn
            if densityChanged || visibilityChanged {
                table.sizeLastColumnToFit()
            }

            // Keep table highlight aligned with inspector primary selection.
            // When the model reports a single primary selection, highlight only that row
            // so multi-select leftovers cannot disagree with the inspector.
            let rows = coordinator.hosts
            var indexes = IndexSet()
            if let selection, selectedIDs.count <= 1 || selectedIDs == [selection] {
                if let row = rows.firstIndex(where: { $0.id == selection }) {
                    indexes.insert(row)
                }
            } else {
                for id in selectedIDs {
                    if let row = rows.firstIndex(where: { $0.id == id }) {
                        indexes.insert(row)
                    }
                }
                if indexes.isEmpty, let selection,
                   let row = rows.firstIndex(where: { $0.id == selection }) {
                    indexes.insert(row)
                }
            }
            if table.selectedRowIndexes != indexes {
                coordinator.isApplyingProgrammaticSelection = true
                table.selectRowIndexes(indexes, byExtendingSelection: false)
                coordinator.isApplyingProgrammaticSelection = false
            }
            if let clip = table.enclosingScrollView?.contentView {
                clip.scroll(to: NSPoint(x: 0, y: previousScroll))
                table.enclosingScrollView?.reflectScrolledClipView(clip)
            }
            if let selection, let row = rows.firstIndex(where: { $0.id == selection }) {
                table.scrollRowToVisible(row)
            }
        }
    }

    static func sorted(_ hosts: [HostRecord], column: String, ascending: Bool) -> [HostRecord] {
        hosts.sorted { lhs, rhs in
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
    }

    final class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        var parent: ResultsTableView
        var hosts: [HostRecord] = []
        var lastSortColumn: String = ""
        var lastSortAscending: Bool = true
        var isApplyingProgrammaticSelection = false
        var lastCompactDensity: Bool?
        var lastShowMAC: Bool?
        var lastShowVendor: Bool?
        weak var tableView: NSTableView?

        init(parent: ResultsTableView) {
            self.parent = parent
            self.hosts = parent.hosts
            self.lastSortColumn = parent.sortColumn
            self.lastSortAscending = parent.sortAscending
        }

        /// Default visible order prioritizes Name, IP, Status, Services, Response.
        static func makeColumns() -> [NSTableColumn] {
            let defaults = UserDefaults.standard
            // Sum of primary defaults (~626) fits the default window beside a ~320pt inspector.
            let specs: [(String, String, CGFloat)] = [
                ("hostname", "Name", 140),
                ("ip", "IP Address", 118),
                ("status", "Status", 108),
                ("services", "Services", 110),
                ("latency", "Response", 150),
                ("mac", "MAC Address", 120),
                ("vendor", "Vendor", 140)
            ]
            return specs.map { id, title, width in
                let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
                column.title = title
                let key = "ols.column.width.\(id)"
                column.width = CGFloat(
                    TableColumnWidthPolicy.resolved(
                        saved: defaults.double(forKey: key),
                        defaultWidth: Double(width)
                    )
                )
                column.minWidth = CGFloat(TableColumnWidthPolicy.minimum)
                column.maxWidth = 420
                column.resizingMask = [.userResizingMask, .autoresizingMask]
                return column
            }
        }

        func applyDensity(on table: NSTableView) {
            let compact = parent.compactDensity
            table.rowHeight = compact ? OLSTheme.tableRowHeightCompact : OLSTheme.tableRowHeight
        }

        func applyColumnVisibility(on table: NSTableView) {
            for column in table.tableColumns {
                switch column.identifier.rawValue {
                case "mac":
                    column.isHidden = !parent.showMACColumn
                case "vendor":
                    column.isHidden = !parent.showVendorColumn
                default:
                    column.isHidden = false
                }
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
            let fontSize = parent.compactDensity ? OLSTheme.tableFontSizeCompact : OLSTheme.tableFontSize

            if id == "status" {
                return statusCell(tableView: tableView, cellID: cellID, host: host, fontSize: fontSize)
            }

            let label: NSTextField
            if let reused = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTextField {
                label = reused
            } else {
                label = NSTextField(labelWithString: "")
                label.identifier = cellID
                label.lineBreakMode = .byTruncatingTail
            }
            let mono = id == "ip" || id == "mac" || id == "latency"
            label.font = mono
                ? NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
                : NSFont.systemFont(ofSize: fontSize)
            label.stringValue = text
            let tip = (id == "latency") ? host.responseSummary : text
            label.toolTip = (tip == "—" || tip == "Unavailable") ? nil : tip
            label.textColor = .labelColor
            label.alignment = (id == "latency") ? .right : .left
            label.setAccessibilityLabel("\(tableColumn.title): \(tip)")
            return label
        }

        private func statusCell(tableView: NSTableView, cellID: NSUserInterfaceItemIdentifier, host: HostRecord, fontSize: CGFloat) -> NSView {
            let stack: NSStackView
            if let reused = tableView.makeView(withIdentifier: cellID, owner: self) as? NSStackView {
                stack = reused
            } else {
                let image = NSImageView()
                image.identifier = NSUserInterfaceItemIdentifier("status-icon")
                image.imageScaling = .scaleProportionallyDown
                let label = NSTextField(labelWithString: "")
                label.identifier = NSUserInterfaceItemIdentifier("status-label")
                label.lineBreakMode = .byTruncatingTail
                stack = NSStackView(views: [image, label])
                stack.orientation = .horizontal
                stack.alignment = .centerY
                stack.spacing = 4
                stack.identifier = cellID
            }
            let image = stack.views.compactMap { $0 as? NSImageView }.first
            let label = stack.views.compactMap { $0 as? NSTextField }.first
            let symbol = host.status == .online ? "checkmark.circle.fill" : "questionmark.circle"
            let config = NSImage.SymbolConfiguration(pointSize: fontSize, weight: .regular)
            image?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: host.status.displayLabel)?
                .withSymbolConfiguration(config)
            image?.contentTintColor = host.status == .online
                ? OLSTheme.statusRespondedNSColor
                : OLSTheme.statusNoResponseNSColor
            label?.font = NSFont.systemFont(ofSize: fontSize)
            label?.stringValue = host.status.displayLabel + (host.isFavorite ? " ★" : "")
            label?.textColor = host.status == .online
                ? OLSTheme.statusRespondedNSColor
                : OLSTheme.statusNoResponseNSColor
            stack.toolTip = host.status.displayLabel
            stack.setAccessibilityLabel("Status: \(host.status.displayLabel)")
            return stack
        }

        func tableViewColumnDidResize(_ notification: Notification) {
            guard let column = notification.userInfo?["NSTableColumn"] as? NSTableColumn else { return }
            // Skip autoresize fill widths so the next launch keeps practical defaults.
            guard TableColumnWidthPolicy.shouldPersist(Double(column.width)) else { return }
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
            guard let tableView, !isApplyingProgrammaticSelection else { return }
            var ids = Set<String>()
            for row in tableView.selectedRowIndexes {
                if row >= 0, row < hosts.count {
                    ids.insert(hosts[row].id)
                }
            }
            parent.selectedIDs = ids
            // Inspector follows the anchor selection (selectedRow), not an arbitrary set element.
            if let row = Optional(tableView.selectedRow), row >= 0, row < hosts.count {
                parent.selection = hosts[row].id
            } else {
                parent.selection = ids.sorted().first
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
                // Compact cell text; full “ms · method” stays on the tooltip / inspector.
                if let ms = host.responseTimeMs {
                    return String(format: "%.0f ms", ms)
                }
                return "—"
            case "services":
                return host.services.isEmpty ? "—" : host.services.map(\.name).joined(separator: ", ")
            default: return "—"
            }
        }
    }
}

private extension CGFloat {
    var nonZero: CGFloat? { self > 0 ? self : nil }
}
