#!/usr/bin/env bash
set -euo pipefail
[[ $# -eq 1 ]] || { echo 'Usage: script REPO_CLONE_PATH'; exit 2; }
TARGET="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ -d "$TARGET/.git" ]] || { echo 'ERROR: target must be a Git clone'; exit 2; }
[[ ! -e "$TARGET/.github/workflows/02-release.yml" ]] || { echo 'STOP: workflows already present. Review manually to avoid overwriting'; exit 2; }
mkdir -p "$TARGET/.github/workflows" "$TARGET/scripts" "$TARGET/docs"
cp "$ROOT/Dockerfile" "$ROOT/.dockerignore" "$ROOT/.gitignore" "$TARGET/"
cp "$ROOT/.github/workflows/01-ci.yml" "$ROOT/.github/workflows/02-release.yml" "$TARGET/.github/workflows/"
cp "$ROOT/scripts/validate_repo.py" "$TARGET/scripts/"
cp "$ROOT/docs/release-runbook.md" "$TARGET/docs/"
echo 'PASS: copied CI/CD files into clone without replacing existing workflows.'
