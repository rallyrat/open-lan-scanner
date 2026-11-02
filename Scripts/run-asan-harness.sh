#!/usr/bin/env bash
# AddressSanitizer validation for extracted routing/ICMP parsers.
# Uses a dedicated executable (not XCTest/swiftpm-xctest-helper) so the ASan
# runtime is linked into the process that exercises the parsers.
#
# Official SwiftPM flag: `swift build --sanitize=address`
# See: https://www.swift.org/documentation/server/guides/llvm-sanitizers.html
#
# Usage:
#   ./Scripts/run-asan-harness.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
BUILD_PATH="${BUILD_PATH:-/tmp/open-lan-scanner-asan}"
SEED_ROUTING="${SEED_ROUTING:-0xC0FFEEF00D2026}"
SEED_ICMP="${SEED_ICMP:-0x1CEB00B52026}"
ITERATIONS="${ITERATIONS:-200}"
MAX_SIZE="${MAX_SIZE:-4096}"

cd "$ROOT"

echo "==> Toolchain"
xcodebuild -version | head -2
swift --version | head -1

echo "==> Building OLSParserSanitizerHarness with AddressSanitizer"
swift build -c debug \
  --product OLSParserSanitizerHarness \
  --build-path "$BUILD_PATH" \
  --sanitize=address

BIN="$(swift build -c debug --show-bin-path --build-path "$BUILD_PATH")/OLSParserSanitizerHarness"
test -x "$BIN"

echo "==> Positive control (expect ASan abort / non-zero exit)"
set +e
ASAN_OPTIONS="${ASAN_OPTIONS:-halt_on_error=1:abort_on_error=1:detect_leaks=0}" \
  "$BIN" --positive-control
POS_STATUS=$?
set -e
if [[ "$POS_STATUS" -eq 0 ]]; then
  echo "error: positive-control exited 0 — ASan instrumentation appears inactive" >&2
  exit 1
fi
echo "    positive-control aborted as expected (exit=$POS_STATUS) — ASan active"

echo "==> Deterministic parser fuzz under ASan"
ASAN_OPTIONS="${ASAN_OPTIONS:-halt_on_error=1:abort_on_error=1:detect_leaks=0}" \
  "$BIN" --all-fuzz \
  --seed-routing "$SEED_ROUTING" \
  --seed-icmp "$SEED_ICMP" \
  --iterations "$ITERATIONS" \
  --max-size "$MAX_SIZE"

echo "==> ASan harness OK"
echo "    binary=$BIN"
echo "    seeds routing=$SEED_ROUTING icmp=$SEED_ICMP iterations=$ITERATIONS maxSize=$MAX_SIZE"
