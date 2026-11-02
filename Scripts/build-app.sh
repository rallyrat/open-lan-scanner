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
# Override BUILD_PATH for concurrent builds (CI / ASan / packaging) to avoid clobbering.
BUILD_PATH="${BUILD_PATH:-/tmp/open-lan-scanner-build}"
DIST="$ROOT/dist"
APP="$DIST/OpenLANScanner.app"
mkdir -p "$DIST"

echo "==> Building OpenLANScanner $VERSION ($CONFIG) → $BUILD_PATH"
swift build -c "$CONFIG" --product OpenLANScanner --build-path "$BUILD_PATH"

EXECUTABLE="$(swift build -c "$CONFIG" --show-bin-path --build-path "$BUILD_PATH")/OpenLANScanner"

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "error: built executable not found" >&2
  exit 1
fi

echo "==> Assembling app bundle at $APP"
# Prevent AppleDouble (._*) / resource-fork copies on filesystems that support them.
export COPYFILE_DISABLE=1
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$EXECUTABLE" "$APP/Contents/MacOS/OpenLANScanner"
cp "$ROOT/App/Info.plist" "$APP/Contents/Info.plist"

if [[ -f "$ROOT/Resources/Icon/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/Icon/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
else
  echo "warning: AppIcon.icns missing" >&2
fi

# SPM resource bundle — place where both Xcode-style and classic SwiftPM accessors look.
PRODUCTS_CONFIG="Release"
if [[ "$CONFIG" != "release" ]]; then
  PRODUCTS_CONFIG="Debug"
fi
RESOURCE_BUNDLE="$(dirname "$EXECUTABLE")/OpenLANScanner_OpenLANScannerCore.bundle"
if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
  RESOURCE_BUNDLE="$BUILD_PATH/out/Products/${PRODUCTS_CONFIG}/OpenLANScanner_OpenLANScannerCore.bundle"
fi
if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
  # Classic SwiftPM triple layout (seen on some CI runners).
  RESOURCE_BUNDLE="$(echo "$BUILD_PATH"/*/release/OpenLANScanner_OpenLANScannerCore.bundle | awk '{print $1}')"
fi
if [[ -d "$RESOURCE_BUNDLE" ]]; then
  BUNDLE_NAME="$(basename "$RESOURCE_BUNDLE")"
  # Keep resources under Contents/ only — files at the .app root are unsealed and break codesign.
  # --norsrc/--noextattr avoid reintroducing AppleDouble sidecars into the bundle.
  ditto --norsrc --noextattr "$RESOURCE_BUNDLE" "$APP/Contents/Resources/$BUNDLE_NAME"
  # Also beside the executable for classic SwiftPM layouts that resolve relative to the binary.
  ditto --norsrc --noextattr "$RESOURCE_BUNDLE" "$APP/Contents/MacOS/$BUNDLE_NAME"
  # Ensure a loadable Info.plist exists for flat SPM bundles (OUI/ at bundle root).
  for DEST in \
    "$APP/Contents/Resources/$BUNDLE_NAME" \
    "$APP/Contents/MacOS/$BUNDLE_NAME"
  do
    if [[ -d "$DEST/OUI" && ! -f "$DEST/Contents/Info.plist" && ! -f "$DEST/Info.plist" ]]; then
      /usr/bin/plutil -create xml1 "$DEST/Info.plist"
      /usr/bin/plutil -insert CFBundleIdentifier -string "org.openlanscanner.OpenLANScannerCore" "$DEST/Info.plist"
      /usr/bin/plutil -insert CFBundleName -string "OpenLANScanner_OpenLANScannerCore" "$DEST/Info.plist"
      /usr/bin/plutil -insert CFBundlePackageType -string "BNDL" "$DEST/Info.plist"
    fi
  done
  # Direct CSV copy so launch never depends solely on SPM bundle discovery.
  mkdir -p "$APP/Contents/Resources/OUI"
  OUI_SAMPLE=""
  for candidate in \
    "$RESOURCE_BUNDLE/OUI/oui-sample.csv" \
    "$RESOURCE_BUNDLE/Contents/Resources/OUI/oui-sample.csv" \
    "$APP/Contents/Resources/$BUNDLE_NAME/OUI/oui-sample.csv" \
    "$APP/Contents/Resources/$BUNDLE_NAME/Contents/Resources/OUI/oui-sample.csv"
  do
    if [[ -f "$candidate" ]]; then
      OUI_SAMPLE="$candidate"
      break
    fi
  done
  if [[ -n "$OUI_SAMPLE" ]]; then
    cp -f "$OUI_SAMPLE" "$APP/Contents/Resources/OUI/oui-sample.csv"
  fi
else
  echo "warning: SPM resource bundle not found; OUI sample may be unavailable" >&2
fi

# Strip any stray AppleDouble / Finder metadata before signing.
find "$APP" \( -name '._*' -o -name '.DS_Store' \) -delete 2>/dev/null || true

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
