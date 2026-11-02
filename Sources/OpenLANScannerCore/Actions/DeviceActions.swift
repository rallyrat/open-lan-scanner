import AppKit
import Foundation

public enum DeviceActionError: Error, LocalizedError, Sendable {
    case missingMAC
    case missingApplication(String)
    case unsupported(String)
    case invalidUsername(String)

    public var errorDescription: String? {
        switch self {
        case .missingMAC:
            return "A MAC address is required for Wake-on-LAN."
        case .missingApplication(let name):
            return "\(name) is not installed."
        case .unsupported(let detail):
            return detail
        case .invalidUsername(let value):
            return "Username contains unsupported characters: \(value)"
        }
    }
}

@MainActor
public enum DeviceActions {
    /// Allowed remote login name characters for Terminal `ssh` invocations.
    nonisolated public static func isSafeRemoteUsername(_ username: String) -> Bool {
        guard !username.isEmpty, username.count <= 64 else { return false }
        return username.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                || scalar == "." || scalar == "_" || scalar == "-"
        }
    }

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
        let user: String
        if isSafeRemoteUsername(username) {
            user = username
        } else if isSafeRemoteUsername(NSUserName()) {
            user = NSUserName()
        } else {
            user = "user"
        }
        // argv-style tokens only; IPv4Address.dotted is numeric dotted-quad.
        runInTerminal(argv: ["ssh", "\(user)@\(ip.dotted)"])
    }

    public static func openTelnet(ip: IPv4Address) {
        runInTerminal(argv: ["telnet", ip.dotted])
    }

    public static func ping(ip: IPv4Address) {
        runInTerminal(argv: ["/sbin/ping", "-c", "4", ip.dotted])
    }

    public static func traceroute(ip: IPv4Address) {
        runInTerminal(argv: ["traceroute", ip.dotted])
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

    /// Shell-quote a single argument for embedding in a Terminal `do script` string.
    nonisolated public static func shellQuote(_ argument: String) -> String {
        "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Escape a string for inclusion inside an AppleScript double-quoted literal.
    nonisolated public static func appleScriptStringLiteral(_ value: String) -> String {
        var out = "\""
        for ch in value {
            switch ch {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default: out.append(ch)
            }
        }
        out += "\""
        return out
    }

    @discardableResult
    private static func openURL(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }

    /// Runs a fixed argv in Terminal. Arguments are shell-quoted; never interpolate free-form text.
    private static func runInTerminal(argv: [String]) {
        precondition(!argv.isEmpty)
        let command = argv.map(shellQuote).joined(separator: " ")
        let script = """
        tell application "Terminal"
          activate
          do script \(appleScriptStringLiteral(command))
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if error != nil {
                if let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
                    NSWorkspace.shared.openApplication(at: terminal, configuration: NSWorkspace.OpenConfiguration())
                }
            }
        }
    }
}
