import AppKit
import OpenLANScannerCore
import SwiftUI

struct ResultsTableView: NSViewRepresentable {
    var hosts: [HostRecord]
    var selection: Binding<String?>
    var onDoubleClick: ((HostRecord) -> Void)?
    var onContextAction: ((HostRecord, ResultsTableContextAction) -> Void)?

    enum ResultsTableContextAction {
        case favorite
        case copyIP
        case smb
        case http
        case https
        case ssh
        case vnc
        case rdp
        case wol
        case ping
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
        table.allowsMultipleSelection = false
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

        scroll.documentView = table
        context.coordinator.tableView = table
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.hosts = hosts
        context.coordinator.tableView?.reloadData()
        if let selected = selection.wrappedValue,
           let row = hosts.firstIndex(where: { $0.id == selected }) {
            context.coordinator.tableView?.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else {
            context.coordinator.tableView?.deselectAll(nil)
        }
    }

    final class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        var parent: ResultsTableView
        var hosts: [HostRecord] = []
        weak var tableView: NSTableView?

        init(parent: ResultsTableView) {
            self.parent = parent
            self.hosts = parent.hosts
        }

        static func makeColumns() -> [NSTableColumn] {
            let specs: [(String, String, CGFloat)] = [
                ("status", "Status", 70),
                ("ip", "IP Address", 120),
                ("hostname", "Hostname", 160),
                ("mac", "MAC Address", 130),
                ("vendor", "Vendor", 160),
                ("latency", "Response", 80),
                ("services", "Services", 180)
            ]
            return specs.map { id, title, width in
                let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
                column.title = title
                column.width = width
                column.minWidth = 50
                column.resizingMask = [.userResizingMask, .autoresizingMask]
                return column
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            hosts.count
        }

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
                label.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
                if id == "hostname" || id == "vendor" || id == "services" || id == "status" {
                    label.font = NSFont.systemFont(ofSize: 12)
                }
            }
            label.stringValue = text
            label.toolTip = text == "—" ? nil : text
            label.textColor = color(for: host, column: id)
            label.setAccessibilityLabel("\(tableColumn.title): \(text)")
            return label
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView else { return }
            let row = tableView.selectedRow
            if row >= 0, row < hosts.count {
                parent.selection.wrappedValue = hosts[row].id
            } else {
                parent.selection.wrappedValue = nil
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
                switch host.status {
                case .online: return host.isFavorite ? "● ★" : "● Online"
                case .offline: return "○ Offline"
                case .unknown: return host.isFavorite ? "☆ Fav" : "—"
                }
            case "ip": return host.ip.dotted
            case "hostname": return host.hostname ?? "—"
            case "mac": return host.macAddress ?? "—"
            case "vendor": return host.vendor ?? "—"
            case "latency":
                if let ms = host.responseTimeMs {
                    let kind = host.latencyKind == .icmp ? "icmp" : "tcp"
                    return String(format: "%.0f ms (%@)", ms, kind)
                }
                return "—"
            case "services":
                if host.services.isEmpty { return "—" }
                return host.services.map(\.name).joined(separator: ", ")
            default: return "—"
            }
        }

        private func color(for host: HostRecord, column: String) -> NSColor {
            if column == "status" {
                switch host.status {
                case .online: return NSColor(name: nil, dynamicProvider: { _ in
                    NSColor(srgbRed: 0.11, green: 0.50, blue: 0.29, alpha: 1)
                })
                case .offline: return .secondaryLabelColor
                case .unknown: return .tertiaryLabelColor
                }
            }
            return .labelColor
        }
    }
}
