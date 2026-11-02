# Maintainer guide — Open LAN Scanner

App display name: **Open LAN Scanner**  
Bundle ID: `org.openlanscanner.app`  
Executable / product: `OpenLANScanner`  
Minimum macOS: **14.0**  
Version source of truth: `VERSION` (SemVer). Build number: CI `github.run_number` or local `BUILD_NUMBER`.

## 1. Run and develop locally

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export BUILD_PATH=/tmp/open-lan-scanner-build
swift test --build-path "$BUILD_PATH"
./Scripts/build-app.sh
open dist/OpenLANScanner.app
```

Core logic lives in `Sources/OpenLANScannerCore/`. UI in `Sources/OpenLANScanner/`.

## 2. Make a change and run checks

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export BUILD_PATH=/tmp/open-lan-scanner-build
swift test --build-path "$BUILD_PATH"
./Scripts/build-app.sh   # when UI, Info.plist, icon, or packaging changes
```

Update `CHANGELOG.md` under `[Unreleased]` for user-visible work. Open a PR into `main`.

## 3. Update version and changelog

1. Set `VERSION` (example `0.1.1`).
2. Set `App/Info.plist` `CFBundleShortVersionString` to the same value (packaging overwrites from `VERSION` / env anyway).
3. Move `[Unreleased]` notes into a new `CHANGELOG.md` section `## [X.Y.Z] - YYYY-MM-DD`.
4. Commit on `main` (or merge the PR) **before** tagging.

## 4. Create a release tag and publish a download

```bash
# on main, clean tree, VERSION already bumped
git tag -a "v$(tr -d '[:space:]' < VERSION)" -m "Open LAN Scanner $(tr -d '[:space:]' < VERSION)"
git push origin main
git push origin "v$(tr -d '[:space:]' < VERSION)"
```

The `Release` workflow builds ZIP + DMG, writes `SHA256SUMS.txt`, and publishes a **prerelease** GitHub Release for `0.x` tags. Watch the Actions run; download artifacts from the Release page once green.

Local dry-run without publishing:

```bash
CREATE_DMG=1 ./Scripts/package-release.sh
```

## 5. Signing and notarization

Optional GitHub Actions secrets:

| Secret | Purpose |
|---|---|
| `MACOS_CERTIFICATE_P12_BASE64` | Base64-encoded Developer ID Application `.p12` |
| `MACOS_CERTIFICATE_PASSWORD` | Password for that `.p12` |
| `KEYCHAIN_PASSWORD` | Temporary CI keychain password |
| `APPLE_ID` | Apple ID for `notarytool` |
| `APPLE_TEAM_ID` | Team ID |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password |

Without certificate secrets, CI produces **ad-hoc** builds and release notes warn about Gatekeeper. Never commit certificates or passwords.

Local signed build:

```bash
export SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
./Scripts/build-app.sh
# then notarytool submit + stapler as documented in Docs/DISTRIBUTION.md
```

## 6. Troubleshoot a failed release

| Symptom | Check |
|---|---|
| Tag rejected by workflow | `VERSION` file must equal tag without `v` |
| SwiftPM / index errors | Use `BUILD_PATH=/tmp/open-lan-scanner-build` |
| Missing icon in app | `Resources/Icon/AppIcon.icns` + `CFBundleIconFile=AppIcon` |
| Empty release assets | Ensure `package-release.sh` created `dist/OpenLANScanner-*.{zip,dmg}` |
| Notarization failure | Confirm Developer ID + notary secrets; inspect `notarytool` log |
| Gatekeeper blocks download | Expected for ad-hoc builds — right-click → Open |

Re-run the failed workflow from the Actions UI after fixing secrets or pushing a fix tag only when appropriate (prefer a new patch version over reusing a bad tag).

## 7. Deprecate a bad release and ship a fix

1. On the GitHub Release, edit the notes: mark **Do not use** and explain the issue.
2. Optionally delete the broken assets (keep the tag history honest) or leave them with a warning.
3. Bump a patch version (`0.1.0` → `0.1.1`), document in `CHANGELOG.md`, tag `v0.1.1`, push.
4. Do **not** force-push tags that others may have mirrored unless you accept the breakage and announce it.

## Automatic updates (follow-up)

Sparkle is the usual macOS approach. Not integrated yet. When adding it:

- Host an `appcast.xml` over HTTPS.
- Sign updates with an EdDSA (or legacy DSA) Sparkle key kept offline / in secrets.
- Only ship Sparkle once release signing + notarization are reliable.
- Until then, users update by downloading the latest GitHub Release.

## Identity checklist

- Display name: Open LAN Scanner  
- Bundle ID: `org.openlanscanner.app`  
- Artifact prefix: `OpenLANScanner-<version>-<arch>.{zip,dmg}`  
- Repo: `https://github.com/rallyrat/open-lan-scanner`
