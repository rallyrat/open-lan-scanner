#!/usr/bin/env bash
# Fail if release archives contain AppleDouble / resource-fork debris or missing required paths.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="${1:-$ROOT/dist}"

fail() { echo "error: $*" >&2; exit 1; }

shopt -s nullglob
zips=("$DIST"/OpenLANScanner-*.zip)
dmgs=("$DIST"/OpenLANScanner-*.dmg)
[[ ${#zips[@]} -gt 0 ]] || fail "no OpenLANScanner-*.zip in $DIST"

for zip in "${zips[@]}"; do
  echo "==> Checking $(basename "$zip")"
  listing="$(unzip -l "$zip")"
  if echo "$listing" | grep -E '(^|/)(\._|__MACOSX/)' >/dev/null; then
    echo "$listing" | grep -E '(^|/)(\._|__MACOSX/)' | head -40 >&2
    fail "AppleDouble / __MACOSX entries found in $(basename "$zip")"
  fi
  echo "$listing" | grep -q 'Contents/MacOS/OpenLANScanner' || fail "missing MacOS binary in zip"
  echo "$listing" | grep -q 'Contents/Info.plist' || fail "missing Info.plist in zip"
  echo "$listing" | grep -q 'Contents/Resources/AppIcon.icns' || fail "missing AppIcon.icns in zip"
  echo "    zip content OK"
done

for dmg in "${dmgs[@]}"; do
  echo "==> Checking $(basename "$dmg")"
  mnt="$(mktemp -d /tmp/ols-dmg-check-XXXX)"
  cleanup() { hdiutil detach "$mnt" >/dev/null 2>&1 || true; rmdir "$mnt" 2>/dev/null || true; }
  trap cleanup EXIT
  hdiutil attach "$dmg" -readonly -nobrowse -mountpoint "$mnt" >/dev/null
  test -d "$mnt/OpenLANScanner.app" || fail "DMG missing OpenLANScanner.app"
  test -x "$mnt/OpenLANScanner.app/Contents/MacOS/OpenLANScanner" || fail "DMG app not executable"
  if find "$mnt/OpenLANScanner.app" \( -name '._*' -o -name '.DS_Store' \) | grep -q .; then
    find "$mnt/OpenLANScanner.app" \( -name '._*' -o -name '.DS_Store' \) | head -40 >&2
    fail "AppleDouble / .DS_Store found inside mounted DMG app"
  fi
  echo "    dmg content OK"
  cleanup
  trap - EXIT
done

echo "==> Archive content validation passed"
