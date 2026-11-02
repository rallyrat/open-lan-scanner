#!/usr/bin/env bash
# Project-local cleanup for Open LAN Scanner development artifacts.
#
# Default: dry-run (lists paths + estimated reclaim). Deletion requires --apply.
#
# Usage:
#   ./Scripts/clean-local.sh              # dry-run ordinary cleanup
#   ./Scripts/clean-local.sh --apply      # delete ordinary targets
#   ./Scripts/clean-local.sh --deep       # dry-run including default build caches
#   ./Scripts/clean-local.sh --deep --apply
#
# Never deletes: source, tests, Docs/assets screenshots, BMAD config, Application Support
# user data, credentials, keychains, or remote release assets.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APPLY=0
DEEP=0

usage() {
  sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
}

for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    --deep) DEEP=1 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "error: unknown argument: $arg" >&2
      usage >&2
      exit 2
      ;;
  esac
done

# Paths that must never be deleted by this script.
is_forbidden() {
  local p="$1"
  case "$p" in
    "$ROOT"|"$ROOT/"*) ;;
    /tmp/open-lan-scanner*|/tmp/ols-*) ;;
    *) return 0 ;;
  esac
  case "$p" in
    "$ROOT/Sources"|"$ROOT/Sources"/*) return 0 ;;
    "$ROOT/Tests"|"$ROOT/Tests"/*) return 0 ;;
    "$ROOT/Scripts"|"$ROOT/Scripts"/*) return 0 ;;
    "$ROOT/Docs"|"$ROOT/Docs"/*) return 0 ;;
    "$ROOT/Resources"|"$ROOT/Resources"/*) return 0 ;;
    "$ROOT/App"|"$ROOT/App"/*) return 0 ;;
    "$ROOT/Tools"|"$ROOT/Tools"/*) return 0 ;;
    "$ROOT/_bmad"|"$ROOT/_bmad"/*) return 0 ;;
    "$ROOT/.git"|"$ROOT/.git"/*) return 0 ;;
    "$ROOT/.github"|"$ROOT/.github"/*) return 0 ;;
    "$HOME/Library/Application Support"/*) return 0 ;;
    "$HOME/Library/Keychains"/*) return 0 ;;
    *.p12|*.pem|*.key|*.mobileprovision) return 0 ;;
  esac
  return 1
}

# Only allow deletion of validated project-owned locations.
is_allowed_target() {
  local p="$1"
  # Refuse symlinks that escape allowed roots (do not follow).
  if [[ -L "$p" ]]; then
    local target
    target="$(readlink "$p" 2>/dev/null || true)"
    case "$target" in
      /tmp/open-lan-scanner*|/tmp/ols-*|"$ROOT/dist"/*) ;;
      *)
        echo "  skip symlink (unsafe/unknown target): $p -> $target"
        return 1
        ;;
    esac
  fi
  case "$p" in
    "$ROOT/dist/stage"|"$ROOT/dist/stage"/*) return 0 ;;
    "$ROOT/dist/dmg-root"|"$ROOT/dist/dmg-root"/*) return 0 ;;
    "$ROOT/dist/tmp-ols.dmg") return 0 ;;
    "$ROOT/dist/.DS_Store"|"$ROOT/.DS_Store") return 0 ;;
    "$ROOT"/.build|"$ROOT"/.build/*) return 0 ;;
    "$ROOT"/.swiftpm|"$ROOT"/.swiftpm/*) return 0 ;;
    /tmp/open-lan-scanner-ci-*|/tmp/open-lan-scanner-ci-repro|/tmp/open-lan-scanner-readme-check) return 0 ;;
    /tmp/open-lan-scanner-build-asan|/tmp/open-lan-scanner-asan) return 0 ;;
    /tmp/ols-*.txt|/tmp/ols-*.log|/tmp/ols-*.err|/tmp/ols-*.out|/tmp/ols-*.zip|/tmp/ols-check.zip) return 0 ;;
    /tmp/ols-demo-screenshots*) return 0 ;;
  esac
  if [[ "$DEEP" -eq 1 ]]; then
    case "$p" in
      /tmp/open-lan-scanner-build|/tmp/open-lan-scanner-build/*) return 0 ;;
      /tmp/open-lan-scanner-asan|/tmp/open-lan-scanner-asan/*) return 0 ;;
    esac
  fi
  return 1
}

bytes_of() {
  local p="$1"
  if [[ -e "$p" || -L "$p" ]]; then
    /usr/bin/du -sk "$p" 2>/dev/null | awk '{print $1 * 1024}'
  else
    echo 0
  fi
}

human() {
  local b="$1"
  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec --suffix=B "$b"
  else
    awk -v b="$b" 'BEGIN{
      split("B KB MB GB TB", u, " ");
      s=1; while (b>=1024 && s<5) {b/=1024; s++}
      printf "%.1f%s", b, u[s]
    }'
  fi
}

candidates=()

add_if_exists() {
  local p="$1"
  if [[ -e "$p" || -L "$p" ]]; then
    candidates+=("$p")
  fi
}

# --- Ordinary cleanup candidates ---
add_if_exists "$ROOT/dist/stage"
add_if_exists "$ROOT/dist/dmg-root"
add_if_exists "$ROOT/dist/tmp-ols.dmg"
add_if_exists "$ROOT/dist/.DS_Store"
add_if_exists "$ROOT/.DS_Store"
add_if_exists "$ROOT/.build"
add_if_exists "$ROOT/.swiftpm"

# Abandoned SwiftPM build trees (not the default BUILD_PATH unless --deep)
for d in /tmp/open-lan-scanner-ci-fix /tmp/open-lan-scanner-ci-fix2 \
         /tmp/open-lan-scanner-ci-repro /tmp/open-lan-scanner-readme-check \
         /tmp/open-lan-scanner-build-asan /tmp/open-lan-scanner-asan; do
  add_if_exists "$d"
done

# Disposable log / zip leftovers with ols- prefix in /tmp
shopt -s nullglob
for f in /tmp/ols-*.txt /tmp/ols-*.log /tmp/ols-*.err /tmp/ols-*.out /tmp/ols-*.zip /tmp/ols-check.zip /tmp/ols-demo-screenshots*; do
  add_if_exists "$f"
done
shopt -u nullglob

if [[ "$DEEP" -eq 1 ]]; then
  add_if_exists /tmp/open-lan-scanner-build
  add_if_exists /tmp/open-lan-scanner-asan
fi

echo "==> Open LAN Scanner local cleanup"
echo "    root=$ROOT"
echo "    mode=$([ "$APPLY" -eq 1 ] && echo APPLY || echo DRY-RUN)$([ "$DEEP" -eq 1 ] && echo '+DEEP' || true)"
echo "    preserved by policy: dist/*.zip dist/*.dmg SHA256SUMS.txt build-metadata.txt"
echo "                         OpenLANScanner.app Docs/assets _bmad Application Support"
echo

# Deduplicate while preserving order (globs can overlap, e.g. ols-*.zip vs ols-check.zip).
# Portable across macOS /bin/bash 3.2 (no associative arrays).
unique=()
for p in "${candidates[@]+"${candidates[@]}"}"; do
  already=0
  for u in "${unique[@]+"${unique[@]}"}"; do
    if [[ "$u" == "$p" ]]; then
      already=1
      break
    fi
  done
  [[ "$already" -eq 1 ]] && continue
  unique+=("$p")
done

total=0
planned=()
for p in "${unique[@]+"${unique[@]}"}"; do
  if is_forbidden "$p"; then
    echo "  skip forbidden: $p"
    continue
  fi
  if ! is_allowed_target "$p"; then
    echo "  skip unvalidated: $p"
    continue
  fi
  b="$(bytes_of "$p")"
  total=$((total + b))
  planned+=("$p")
  echo "  $(human "$b")	$p"
done

echo
echo "==> Estimated reclaim: $(human "$total") across ${#planned[@]} path(s)"

if [[ ${#planned[@]} -eq 0 ]]; then
  echo "Nothing to clean."
  exit 0
fi

if [[ "$APPLY" -ne 1 ]]; then
  echo
  echo "Dry-run only. Re-run with --apply to delete the listed paths."
  exit 0
fi

echo
echo "==> Deleting…"
for p in "${planned[@]}"; do
  if is_forbidden "$p" || ! is_allowed_target "$p"; then
    echo "  refuse: $p"
    continue
  fi
  # Unmount project DMGs if a path is somehow still attached (best-effort).
  if [[ "$p" == *.dmg && -f "$p" ]]; then
    hdiutil detach "$p" -force >/dev/null 2>&1 || true
  fi
  rm -rf -- "$p"
  echo "  removed $p"
done

echo "==> Done"
