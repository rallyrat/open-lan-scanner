#!/usr/bin/env bash
# Regenerate SHA256SUMS.txt for final downloadable artifacts in dist/.
# Call after notarization/stapling so checksums match settled bytes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"

if [[ ! -d "$DIST" ]]; then
  echo "error: dist/ missing" >&2
  exit 1
fi

cd "$DIST"
rm -f SHA256SUMS.txt
shopt -s nullglob
files=(OpenLANScanner-*.zip OpenLANScanner-*.dmg)
if [[ ${#files[@]} -eq 0 ]]; then
  echo "error: no OpenLANScanner-*.zip/dmg artifacts in dist/" >&2
  exit 1
fi
for f in "${files[@]}"; do
  shasum -a 256 "$f" >> SHA256SUMS.txt
done
echo "==> Regenerated checksums"
cat SHA256SUMS.txt
