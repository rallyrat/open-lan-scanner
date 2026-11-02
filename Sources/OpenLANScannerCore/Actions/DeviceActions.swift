import AppKit
import Foundation

public enum DeviceActionError: Error, LocalizedError, Sendable {
    case missingMAC
    case missingApplication(String)
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .missingMAC:
            return "A MAC address is required for Wake-on-LAN."
        case .missingApplication(let name):
            return "\(name) is not installed."
        case .unsupported(let detail):
            return detail
        }
    }
}

@MainActor
public enum DeviceActions {
    public static func openSMB(ip: IPv4Address) {
        openURL(URL(string: "smb://\(ip.dotted)")!)
    }

    public static func openHTTP(ip: IPv4Address, secure: Bool) {
        let scheme = secure ? "https" : "http"
        openURL(URL(string: "\(scheme)://\(ip.dotted)")!)
    }

    public static func openFTP(ip: IPv4Address) {
        openURL(URL(string: "ftp://\(ip.dotted)")!)
    }

    public static func openVNC(ip: IPv4Address) {
        openURL(URL(string: "vnc://\(ip.dotted)")!)
    }

    public static func openRDP(ip: IPv4Address) throws {
        // Microsoft Remote Desktop registers rdp:// on macOS when installed.
        if let url = URL(string: "rdp://full%20address=s:\(ip.dotted)"), openURL(url) {
            return
        }
        let candidates = [
            "com.microsoft.rdc.macos",
            "com.microsoft.rdc.mac"
        ]
        for bundleID in candidates {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let config = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.openApplication(at: url, configuration: config)
                // Still tell the user they may need to enter the host manually.
                throw DeviceActionError.unsupported(
                    "Opened Microsoft Remote Desktop. Connect to \(ip.dotted) manually if a session did not start."
                )
            }
        }
        throw DeviceActionError.missingApplication(
            "Microsoft Remote Desktop (install from the Mac App Store, then use rdp://\(ip.dotted))"
        )
    }

    public static func openSSH(ip: IPv4Address, username: String = NSUserName()) {
        let command = "ssh \(username)@\(ip.dotted)"
        runInTerminal(command)
    }

    public static func openTelnet(ip: IPv4Address) {
        runInTerminal("telnet \(ip.dotted)")
    }

    public static func ping(ip: IPv4Address) {
        runInTerminal("/sbin/ping -c 4 \(ip.dotted)")
    }

    public static func traceroute(ip: IPv4Address) {
        runInTerminal("traceroute \(ip.dotted)")
    }

    public static func copyToPasteboard(_ strings: [String]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(strings.joined(separator: "\n"), forType: .string)
    }

    public static func wakeOnLAN(mac: String?) async throws {
        guard let mac, !mac.isEmpty else { throw DeviceActionError.missingMAC }
        try await WakeOnLAN.send(mac: mac)
    }

    @discardableResult
    private static func openURL(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }

    private static func runInTerminal(_ command: String) {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
          activate
          do script "\(escaped)"
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if error != nil {
                // Fallback: open Terminal only.
                if let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
                    NSWorkspace.shared.openApplication(at: terminal, configuration: NSWorkspace.OpenConfiguration())
                }
            }
        }
    }
}
