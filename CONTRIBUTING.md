# Contributing to Open LAN Scanner

Thanks for helping improve this project. By participating you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Development setup

Requirements:

- macOS 14+
- Xcode 15+ (full Xcode, not only Command Line Tools)
- Swift 5.9+

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

Scratch builds default to `/tmp/open-lan-scanner-build` because some external volumes and paths with spaces break SwiftPM indexes.

## Project layout

| Path | Role |
|---|---|
| `Sources/OpenLANScannerCore/` | Discovery engine, models, export, persistence |
| `Sources/OpenLANScanner/` | SwiftUI / AppKit UI |
| `Tests/OpenLANScannerCoreTests/` | Deterministic unit tests |
| `Scripts/` | Build, package, OUI download |
| `Resources/Icon/` | App icon source and `.icns` |
| `Docs/` | Architecture, distribution, maintainers |

## Checks before opening a PR

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export BUILD_PATH=/tmp/open-lan-scanner-build
swift test --build-path "$BUILD_PATH"
./Scripts/build-app.sh
```

- Keep scans cancellable; never invent MAC, vendor, latency, or services.
- Prefer Apple frameworks; avoid fragile shell parsing of network tables.
- Do not commit secrets, certificates, personal captures, or `dist/` artifacts.
- Update `CHANGELOG.md` under `[Unreleased]` for user-visible changes.
- Match existing naming and the restrained utility UI in `DESIGN.md`.

## Pull requests

1. Fork (or branch from `main`).
2. Make a focused change.
3. Run the checks above.
4. Open a PR using the template; link related issues.

## Coding conventions

- Swift concurrency with bounded parallelism; UI updates on the main actor.
- Dependency injection for probe transports so tests stay offline/deterministic.
- No telemetry. No plaintext password storage.
- Document honesty limitations when changing discovery behavior.

## Security issues

Do not file public issues for vulnerabilities. See [SECURITY.md](SECURITY.md).
