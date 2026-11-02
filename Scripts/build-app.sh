#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

cd "$ROOT"

if [[ -f "$ROOT/VERSION" ]]; then
  VERSION="${VERSION:-$(tr -d '[:space:]' < "$ROOT/VERSION")}"
else
  VERSION="${VERSION:-0.1.0}"
fi
BUILD_NUMBER="${BUILD_NUMBER:-1}"
CONFIG="${CONFIG:-release}"
# Prefer a local scratch path — external volumes with spaces can break SwiftPM indexes.
BUILD_PATH="${BUILD_PATH:-/tmp/open-lan-scanner-build}"
DIST="$ROOT/dist"
APP="$DIST/OpenLANScanner.app"

echo "==> Building OpenLANScanner $VERSION ($CONFIG) → $BUILD_PATH"
swift build -c "$CONFIG" --product OpenLANScanner --build-path "$BUILD_PATH"

EXECUTABLE="$(swift build -c "$CONFIG" --show-bin-path --build-path "$BUILD_PATH")/OpenLANScanner"

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "error: built executable not found" >&2
  exit 1
fi

echo "==> Assembling app bundle at $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$EXECUTABLE" "$APP/Contents/MacOS/OpenLANScanner"
cp "$ROOT/App/Info.plist" "$APP/Contents/Info.plist"

if [[ -f "$ROOT/Resources/Icon/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/Icon/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
else
  echo "warning: AppIcon.icns missing" >&2
fi

# SPM resource bundle expected at Bundle.main.resourceURL/OpenLANScanner_OpenLANScannerCore.bundle
PRODUCTS_CONFIG="Release"
if [[ "$CONFIG" != "release" ]]; then
  PRODUCTS_CONFIG="Debug"
fi
RESOURCE_BUNDLE="$(dirname "$EXECUTABLE")/OpenLANScanner_OpenLANScannerCore.bundle"
if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
  RESOURCE_BUNDLE="$BUILD_PATH/out/Products/${PRODUCTS_CONFIG}/OpenLANScanner_OpenLANScannerCore.bundle"
fi
if [[ -d "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"
else
  echo "warning: SPM resource bundle not found; OUI sample may be unavailable" >&2
fi

/usr/bin/plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleIconFile -string "AppIcon" "$APP/Contents/Info.plist" 2>/dev/null \
  || /usr/bin/plutil -insert CFBundleIconFile -string "AppIcon" "$APP/Contents/Info.plist"

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
if command -v codesign >/dev/null 2>&1; then
  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "==> Ad-hoc code signature (not notarized)"
    codesign --force --deep --sign - "$APP"
  else
    echo "==> Signing with identity: $SIGN_IDENTITY"
    ENTITLEMENTS="${ENTITLEMENTS:-}"
    if [[ -n "$ENTITLEMENTS" && -f "$ENTITLEMENTS" ]]; then
      codesign --force --deep --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$APP"
    else
      codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
    fi
  fi
fi

echo "==> Built $APP"
echo "Launch with: open \"$APP\""
