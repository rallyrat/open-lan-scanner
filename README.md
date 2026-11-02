# Open LAN Scanner

Native, open-source **macOS LAN scanner**. Scan local IPv4 ranges, review live hosts, and open common remote actions — without accounts, cloud backends, or Electron.

**Not affiliated with Advanced IP Scanner or Famatech.**

<p align="center">
  <img src="Resources/Icon/AppIcon-1024.png" alt="Open LAN Scanner icon" width="128" height="128">
</p>

| | |
|---|---|
| **Platform** | macOS 14.0+ (Apple Silicon and Intel when you build for that architecture) |
| **Stack** | Swift, SwiftUI, AppKit table, Network.framework |
| **License** | MIT |
| **Status** | Early public release (`0.x`) |

## Features

- Interface picker with suggested subnet; CIDR, ranges, and single IPv4 targets
- Bounded concurrent TCP discovery with cancel, progress, and live results
- Columns: status, IP (numeric sort), hostname, MAC (when available), vendor, probe latency, services
- Filters: search, online-only, favorites
- Actions: SMB, HTTP/HTTPS, SSH, VNC, RDP (if a client is installed), Wake-on-LAN, Ping, Traceroute
- Favorites with notes; CSV and JSON export
- Local preferences only — no telemetry

## Install (releases)

1. Download the `.dmg` (preferred) or `.zip` from the [latest GitHub Release](https://github.com/rallyrat/open-lan-scanner/releases).
2. Open the disk image and drag **Open LAN Scanner** into **Applications**.
3. If macOS blocks launch on an **unsigned / ad-hoc** build: right-click the app → **Open** → **Open**. Do not disable Gatekeeper globally.
4. Verify checksums when provided:

```bash
shasum -a 256 -c SHA256SUMS.txt
```

## First scan

1. Select a network interface (non-VPN preferred when listed).
2. Confirm the suggested range or enter CIDR / `a.b.c.d-e`.
3. Click **Scan**. Stop anytime with **Stop** or ⌘.
4. Use the inspector or context menu for host actions.

### Permissions

| Permission | When |
|---|---|
| **Local Network** (macOS 15+) | First LAN probe / Bonjour use — allow in System Settings → Privacy & Security → Local Network if scans find nothing |
| Apple Events / Automation (optional) | Opening Terminal for Ping / SSH |

## Limitations

- A failed probe does **not** prove a host is offline.
- MAC addresses are typically available only for **directly connected** neighbors.
- Response times are **TCP connect probe** latency unless noted otherwise.
- Windows remote shutdown and Radmin are **not** supported ([notes](Docs/REMOTE_SHUTDOWN.md)).
- Early `0.x` software — expect rough edges.

## Build from source

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export BUILD_PATH=/tmp/open-lan-scanner-build
git clone https://github.com/rallyrat/open-lan-scanner.git
cd open-lan-scanner
chmod +x Scripts/*.sh
swift test --build-path "$BUILD_PATH"
./Scripts/build-app.sh
open dist/OpenLANScanner.app
```

Package ZIP + DMG locally:

```bash
CREATE_DMG=1 ./Scripts/package-release.sh
```

## Documentation

- [Architecture](Docs/ARCHITECTURE.md)
- [Feature parity](Docs/FEATURE_PARITY.md)
- [Distribution, sandbox, signing](Docs/DISTRIBUTION.md)
- [Maintainer guide](Docs/MAINTAINERS.md)
- [Contributing](CONTRIBUTING.md)
- [Security](SECURITY.md)
- [Changelog](CHANGELOG.md)
- [Design](DESIGN.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)

## OUI vendor data

A small sample OUI table is bundled. Optional full IEEE MA-L download:

```bash
./Scripts/download-oui.sh
```

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Updates are explicit; nothing uploads your network data.

## Screenshots

No committed UI screenshots yet (Screen Recording permission was unavailable in the release environment). Run the app locally after `./Scripts/build-app.sh` to inspect the UI. A GitHub social preview image lives at [`docs/assets/github-social-preview.png`](docs/assets/github-social-preview.png) — set it under the repo **Settings → General → Social preview**.

## CI status

Workflow YAML currently lives in [`Docs/github-workflows/`](Docs/github-workflows/) because the publishing token lacked the GitHub `workflow` scope. Restore with:

```bash
./Scripts/install-github-workflows.sh
gh auth refresh -h github.com -s workflow,repo
git add .github/workflows && git commit -m "Enable GitHub Actions workflows" && git push
```

## License

MIT — see [LICENSE](LICENSE).
