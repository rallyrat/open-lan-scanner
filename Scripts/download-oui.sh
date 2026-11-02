#!/usr/bin/env bash
# Explicit, user-initiated download of IEEE MA-L (OUI) public listing.
# See THIRD_PARTY_NOTICES.md. IEEE encourages fetching updates from IEEE directly.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${1:-$ROOT/Resources/OUI}"
mkdir -p "$OUT_DIR"

URL="https://standards-oui.ieee.org/oui/oui.csv"
DEST="$OUT_DIR/oui.csv"

echo "Downloading IEEE MA-L public listing…"
echo "Source: $URL"
curl -fsSL "$URL" -o "$DEST"
echo "Wrote $DEST ($(wc -l < "$DEST") lines)"
echo "Copy into Sources/OpenLANScannerCore/Resources/OUI/ and rebuild to bundle a fuller dataset."
