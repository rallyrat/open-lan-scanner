#!/usr/bin/env bash
# Export README screenshots from the real app UI using explicit demo data.
# Activation is opt-in only (--demo-ui). No live network probes are sent.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
BUILD_PATH="${BUILD_PATH:-/tmp/open-lan-scanner-build}"
OUT="${1:-$ROOT/Docs/assets}"
STAGING="${TMPDIR:-/tmp}/ols-demo-screenshots-$$"

cd "$ROOT"
mkdir -p "$STAGING" "$OUT"

echo "==> Building app"
./Scripts/build-app.sh

APP="$ROOT/dist/OpenLANScanner.app"
test -x "$APP/Contents/MacOS/OpenLANScanner"

echo "==> Launching demo UI export → $STAGING"
"$APP/Contents/MacOS/OpenLANScanner" --demo-ui --export-screenshots "$STAGING"

test -f "$STAGING/EXPORT_DONE"
for name in 01-main-results.png 02-inspector-actions.png 03-favorites-dark.png; do
  test -s "$STAGING/$name"
  # Re-encode lightly for stable, readable PNGs without tooling dependencies.
  sips -s format png "$STAGING/$name" --out "$OUT/$name" >/dev/null
  echo "    wrote $OUT/$name ($(wc -c < "$OUT/$name") bytes)"
done

echo "==> Demo screenshots ready in $OUT"
ls -la "$OUT"/0{1,2,3}-*.png
