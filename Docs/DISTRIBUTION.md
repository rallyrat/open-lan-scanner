# Distribution, permissions, and signing

## App Sandbox decision

**App Sandbox is off** for Open LAN Scanner.

Local discovery needs unrestricted outbound TCP to arbitrary LAN addresses, neighbor/ARP visibility, UDP broadcast for Wake-on-LAN, and Bonjour browsing. A sandboxed app with only `com.apple.security.network.client` can open TCP connections but typically cannot read the full neighbor table and may be constrained for broadcast WoL. Shipping a privileged helper solely for ARP was judged unnecessary for v1.

Hardened Runtime can still be enabled for Developer ID builds. Do not disable SIP or add setuid helpers.

## Local Network privacy (macOS 15+)

Per Apple TN3179:

- Add `NSLocalNetworkUsageDescription` to Info.plist.
- Add `NSBonjourServices` for browsed service types (`_ssh._tcp`, `_http._tcp`, `_smb._tcp`, `_rfb._tcp`, etc.).
- First LAN operation may prompt; user can change later in **System Settings → Privacy & Security → Local Network**.
- Multicast entitlement is **not** required on macOS.
- Prefer `NWConnection` so a denied path can surface `localNetworkDenied` and wait/retry after the user allows access.

On macOS 14, the Local Network privilege UI does not apply the same way; scanning still works with standard networking APIs.

## Minimum OS

**macOS 14.0**. Apple Silicon and Intel (x86_64) when building universal.

## Packaging

1. `Scripts/build-app.sh` compiles the executable and assembles `dist/OpenLANScanner.app`.
2. `Scripts/package-release.sh` produces `OpenLANScanner-<version>-macos.zip`.
3. Optional DMG: use `hdiutil create` (documented in the release script).

## Signing and notarization

| Build | What you get |
|---|---|
| Local unsigned | Runs after right-click → Open (Gatekeeper) |
| Apple Development | Dev machines / TestFlight-like local |
| Developer ID Application + notarize | Broad distribution outside the Mac App Store |

Unsigned builds are **not** notarized. Notarization requires a paid Apple Developer account, `codesign` with Developer ID, and `notarytool`/`stapler`.

Mac App Store distribution would require revisiting Sandbox and may lose neighbor-table features; not targeted for v1.

## Privacy

No telemetry. Scan results and favorites stay on-device. OUI dataset updates only when the user runs the documented download script or in-app update action.
