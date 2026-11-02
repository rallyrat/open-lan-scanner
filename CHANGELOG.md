# Changelog

All notable changes to Open LAN Scanner are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.1] - 2026-11-02

### Changed

- Native UI polish: layout tokens, interface → range → Scan toolbar, restructured inspector, Preferences tabs, History compare wording, and footer status layout
- Results table: practical default columns (Name, IP, Status, Services, Response), compact density preference, adaptive status colors, selection sync with the inspector, and clamped column-width persistence
- User-facing labels for discovery evidence (for example “TCP connection”, “Open TCP port”) instead of implementation identifiers
- Regenerated fictional demo screenshots (RFC 5737 TEST-NET-3)

### Security

- Harden Terminal/AppleScript device actions (argv quoting, username allow-list)
- Neutralize CSV spreadsheet formula injection on export (including leading whitespace/BOM); JSON export unchanged
- Bound OUI / favorites / history file sizes before load; timeout stalled reverse DNS; cap concurrent DNS lookups
- Cancel in-flight `NWConnection` probes on task cancellation
- Extract bounds-checked routing/ICMP parsers with deterministic fuzz tests; validate ICMP echo replies
- Hard-limit enrichment concurrency with metrics; pin GitHub Actions to commit SHAs
- Dedicated AddressSanitizer parser harness (`OLSParserSanitizerHarness`) with positive-control verification
- Strip AppleDouble/`._*` from release archives; archive content validation gate

### Fixed

- Packaging EXIT cleanup no longer fails CI after a successful ZIP/DMG build
- Swift 5.10 MainActor / Task capture CI failures

### Added

- Local cleanup tooling (`Scripts/clean-local.sh`) and maintainer follow-ups documentation
- Demo-mode README screenshots captured without live network probes

## [0.1.0] - 2026-11-02

Initial public early release.

### Added

- Native macOS app (Swift / SwiftUI + AppKit results table) for local IPv4 LAN scanning
- Interface selection with suggested subnet, CIDR / range / single-IP targets
- Bounded concurrent TCP discovery with live results, cancel, and progress
- Hostname (reverse DNS), neighbor MAC when available, bundled OUI vendor sample
- Configurable service probes (SSH, HTTP, HTTPS, SMB, RDP, VNC, and optional ports)
- Favorites with custom names and notes; CSV / JSON export; favorites import/export
- Device actions: SMB, HTTP(S), SSH, VNC, RDP (when a client is installed), Wake-on-LAN, Ping, Traceroute
- Preferences for concurrency, timeouts, retries, and probe set
- App icon, packaging scripts (ZIP + DMG), unit tests for parsing / scan engine / export
- CI workflow and tag-based release workflow (unsigned artifacts unless secrets are configured)

### Known limitations

- Early release (`0.x`); treat results as best-effort discovery, not an inventory authority
- MAC addresses generally only for directly connected L2 neighbors
- Latency shown is TCP probe time by default
- Windows remote shutdown and Radmin are not supported
- Ad-hoc signed builds are not notarized unless you configure Developer ID secrets

[Unreleased]: https://github.com/rallyrat/open-lan-scanner/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/rallyrat/open-lan-scanner/releases/tag/v0.1.1
[0.1.0]: https://github.com/rallyrat/open-lan-scanner/releases/tag/v0.1.0
