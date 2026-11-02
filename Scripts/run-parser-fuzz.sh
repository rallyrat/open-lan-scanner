#!/usr/bin/env bash
# Explicit, bounded parser fuzz/stress beyond the default CI suite.
# Usage:
#   ./Scripts/run-parser-fuzz.sh           # XCTest fuzz/resource suites
#   OLS_ASAN=1 ./Scripts/run-parser-fuzz.sh  # also run dedicated ASan harness
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export BUILD_PATH="${BUILD_PATH:-/tmp/open-lan-scanner-build}"

echo "==> Parser fuzz / resource-bound XCTest filters"
echo "    Budgets: NetworkParserFuzzTests ~few hundred KB; ResourceBoundsTests <5s"
cd "$ROOT"
swift test --build-path "$BUILD_PATH" \
  --filter NetworkParserFuzzTests \
  --filter ResourceBoundsTests \
  --filter HardeningVerificationTests \
  --filter SecurityAndStressTests

if [[ "${OLS_ASAN:-0}" == "1" ]]; then
  echo "==> Dedicated AddressSanitizer harness (not XCTest)"
  "$ROOT/Scripts/run-asan-harness.sh"
fi

echo "Done."
