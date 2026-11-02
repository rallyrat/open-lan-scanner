#!/usr/bin/env bash
# Restore Actions workflows into .github/workflows after `gh auth refresh -s workflow`.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/.github/workflows"
cp "$ROOT/Docs/github-workflows/ci.yml" "$ROOT/.github/workflows/ci.yml"
cp "$ROOT/Docs/github-workflows/release.yml" "$ROOT/.github/workflows/release.yml"
echo "Copied workflows to .github/workflows/"
echo "Next:"
echo "  gh auth refresh -h github.com -s workflow,repo"
echo "  git add .github/workflows && git commit -m 'Enable GitHub Actions workflows' && git push"
