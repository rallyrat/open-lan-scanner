# Changelog

All notable changes to Open LAN Scanner are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
