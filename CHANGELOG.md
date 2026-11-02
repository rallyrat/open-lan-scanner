# Changelog

All notable changes to Open LAN Scanner are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Security

- Harden Terminal/AppleScript device actions (argv quoting, username allow-list)
- Neutralize CSV spreadsheet formula injection on export (including leading whitespace/BOM); JSON export unchanged
- Bound OUI / favorites / history file sizes before load; timeout stalled reverse DNS; cap concurrent DNS lookups
- Cancel in-flight `NWConnection` probes on task cancellation
- Extract bounds-checked routing/ICMP parsers with deterministic fuzz tests; validate ICMP echo replies
- Hard-limit enrichment concurrency with metrics; pin GitHub Actions to commit SHAs
- Dedicated AddressSanitizer parser harness (`OLSParserSanitizerHarness`) with positive-control verification
- Strip AppleDouble/`._*` from release archives; archive content validation gate
- BMAD Method 6.12.4 + TEA 1.27.2 installed for stable local QA (not v7)

### Changed

- Address parsing rejects oversized CIDRs/ranges with overflow-safe counts before allocation
- Host discovery separated from service enumeration; TCP refusals count as live evidence without claiming an open service
- Selected network interface is carried into probes; UI explains binding limits and adapter state
- Progressive enrichment (hostname / MAC / vendor) with generation-guarded cancellation and unbounded event delivery
- Results table: multi-select, header sort (IP/latency numeric), persisted column layout, custom names, copy/export scopes
- Empty states and a persistent Local Network permission banner replace repeated alerts
- OUI lookup: IEEE + compact CSV, longest-prefix match, LAA explanation, in-app import to Application Support
- Favorites/preferences/history save paths surface errors; imports validate and deduplicate
- Local scan history with conservative compare (no “left the network” claims from timeouts alone)
- CI/release workflows restored under `.github/workflows`; checksums regenerated after notarization; keychain cleaned on failure

### Added

- Discovery-probe toggles distinct from service probes; optional ICMP and Bonjour best-effort discovery
- Export all / filtered / selected rows; Wake-on-LAN and export success/failure feedback
- Scan history retention controls and Clear History

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

[Unreleased]: https://github.com/rallyrat/open-lan-scanner/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/rallyrat/open-lan-scanner/releases/tag/v0.1.0
