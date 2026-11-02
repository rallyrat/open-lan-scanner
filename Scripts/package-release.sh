#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if [[ -f "$ROOT/VERSION" ]]; then
  VERSION="${VERSION:-$(tr -d '[:space:]' < "$ROOT/VERSION")}"
else
  VERSION="${VERSION:-0.1.0}"
fi
BUILD_NUMBER="${BUILD_NUMBER:-1}"
DIST="$ROOT/dist"
APP="$DIST/OpenLANScanner.app"
CREATE_DMG="${CREATE_DMG:-1}"
ARCH_LABEL="${ARCH_LABEL:-}"

"$ROOT/Scripts/build-app.sh"

if [[ ! -d "$APP" ]]; then
  echo "error: app bundle missing after build" >&2
  exit 1
fi

# Validate packaged app
echo "==> Validating app bundle"
test -x "$APP/Contents/MacOS/OpenLANScanner"
test -f "$APP/Contents/Info.plist"
test -f "$APP/Contents/Resources/AppIcon.icns"
plutil -lint "$APP/Contents/Info.plist" >/dev/null
SHORT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
ICON="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$APP/Contents/Info.plist" 2>/dev/null || true)"
echo "    version=$SHORT build=$BUILD icon=$ICON"
if [[ "$SHORT" != "$VERSION" ]]; then
  echo "error: Info.plist version $SHORT != VERSION $VERSION" >&2
  exit 1
fi

# Detect architecture of the binary for artifact naming
BIN_ARCH="$(lipo -archs "$APP/Contents/MacOS/OpenLANScanner" 2>/dev/null || true)"
if [[ -z "$ARCH_LABEL" ]]; then
  case "$BIN_ARCH" in
    *x86_64*arm64*|*arm64*x86_64*) ARCH_LABEL="universal" ;;
    *arm64*) ARCH_LABEL="arm64" ;;
    *x86_64*) ARCH_LABEL="x86_64" ;;
    *) ARCH_LABEL="macos" ;;
  esac
fi

STAGE="$DIST/stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
export COPYFILE_DISABLE=1
ditto --norsrc --noextattr "$APP" "$STAGE/OpenLANScanner.app"
find "$STAGE" \( -name '._*' -o -name '.DS_Store' \) -delete 2>/dev/null || true

ZIP="$DIST/OpenLANScanner-${VERSION}-${ARCH_LABEL}.zip"
rm -f "$ZIP"
# --norsrc/--noextattr keep AppleDouble out of the zip payload.
ditto -c -k --norsrc --noextattr --keepParent "$STAGE/OpenLANScanner.app" "$ZIP"
echo "==> Created $ZIP"

DMG=""
if [[ "$CREATE_DMG" == "1" ]]; then
  DMG="$DIST/OpenLANScanner-${VERSION}-${ARCH_LABEL}.dmg"
  rm -f "$DMG"
  DMG_ROOT="$DIST/dmg-root"
  rm -rf "$DMG_ROOT"
  mkdir -p "$DMG_ROOT"
  ditto --norsrc --noextattr "$APP" "$DMG_ROOT/OpenLANScanner.app"
  find "$DMG_ROOT" \( -name '._*' -o -name '.DS_Store' \) -delete 2>/dev/null || true
  ln -s /Applications "$DMG_ROOT/Applications"
  # RW temp then convert for a simple installer disk image
  TMP_DMG="$DIST/tmp-ols.dmg"
  rm -f "$TMP_DMG"
  hdiutil create -volname "Open LAN Scanner" -srcfolder "$DMG_ROOT" -ov -format UDRW "$TMP_DMG" >/dev/null
  hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
  rm -f "$TMP_DMG"
  rm -rf "$DMG_ROOT"
  echo "==> Created $DMG"
fi

# Reject AppleDouble / missing required paths before checksums settle.
"$ROOT/Scripts/validate-archive-contents.sh" "$DIST"

# Checksums only after final downloadable bytes are settled
(
  cd "$DIST"
  rm -f SHA256SUMS.txt
  shasum -a 256 "OpenLANScanner-${VERSION}-${ARCH_LABEL}.zip" >> SHA256SUMS.txt
  if [[ -n "$DMG" && -f "$DMG" ]]; then
    shasum -a 256 "$(basename "$DMG")" >> SHA256SUMS.txt
  fi
  echo "==> Checksums"
  cat SHA256SUMS.txt
)

# Signing status note for humans
if codesign -dv "$APP" 2>&1 | grep -q "Signature=adhoc\|flags=0x0\|Signature=adhoc\|Authority=(absent)"; then
  SIGN_STATE="adhoc-or-unsigned"
elif codesign -dv --verbose=2 "$APP" 2>&1 | grep -q "Developer ID Application"; then
  SIGN_STATE="developer-id"
else
  SIGN_STATE="signed-other"
fi
echo "SIGN_STATE=$SIGN_STATE" > "$DIST/build-metadata.txt"
echo "VERSION=$VERSION" >> "$DIST/build-metadata.txt"
echo "BUILD_NUMBER=$BUILD_NUMBER" >> "$DIST/build-metadata.txt"
echo "ARCH=$BIN_ARCH" >> "$DIST/build-metadata.txt"
echo "ARCH_LABEL=$ARCH_LABEL" >> "$DIST/build-metadata.txt"

cat <<EOF

Packaging complete for Open LAN Scanner $VERSION (build $BUILD_NUMBER).

Signing / notarization (optional, paid Apple Developer account + GitHub secrets):
  export SIGN_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)"
  ./Scripts/build-app.sh
  # Notarize the zip or dmg with notarytool, then staple the app/dmg.
  See Docs/MAINTAINERS.md

Ad-hoc or unsigned builds are NOT notarized. First launch may require
right-click → Open under Gatekeeper. Do not disable Gatekeeper globally.

EOF
