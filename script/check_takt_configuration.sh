#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAKT_DIR="$ROOT_DIR/.takt"

required_files=(
  "$TAKT_DIR/config.yaml"
  "$TAKT_DIR/devloopd.yaml"
  "$TAKT_DIR/workflows/subscription-devloop.yaml"
  "$TAKT_DIR/automation/create-product-issues.sh"
  "$TAKT_DIR/automation/full-auto-devloop.sh"
  "$TAKT_DIR/automation/staged-devloop.sh"
  "$TAKT_DIR/quality-gates/project-check.sh"
)

for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    printf 'BLOCKER: required TAKT file is missing: %s\n' "${file#"$ROOT_DIR/"}" >&2
    exit 1
  fi
done

for script in "$TAKT_DIR"/automation/*.sh "$TAKT_DIR"/quality-gates/*.sh; do
  bash -n "$script"
done

grep -Eq '^subscription_only:[[:space:]]*true$' "$TAKT_DIR/config.yaml"
grep -Eq '^[[:space:]]*-[[:space:]]+cursor-cli$' "$TAKT_DIR/config.yaml"
grep -Eq '^[[:space:]]*provider:[[:space:]]+cursor-cli$' "$TAKT_DIR/workflows/subscription-devloop.yaml"
grep -Fq 'cursor-agent --print' "$TAKT_DIR/automation/create-product-issues.sh"
grep -Fq './scripts/ci.sh swiftpm' "$TAKT_DIR/quality-gates/project-check.sh"
grep -Fq './script/check_security_regressions.sh' "$TAKT_DIR/quality-gates/project-check.sh"
grep -Fq 'HARD_MAX_AUTO_MERGE_FILES=20' "$TAKT_DIR/automation/full-auto-devloop.sh"
grep -Fq 'HARD_MAX_AUTO_MERGE_LINES=800' "$TAKT_DIR/automation/full-auto-devloop.sh"
grep -Fq '.takt/*|packaging/*|Package.swift|Package.resolved|' "$TAKT_DIR/automation/full-auto-devloop.sh"

if rg -n -i 'opencode' \
  "$TAKT_DIR/config.yaml" \
  "$TAKT_DIR/workflows" \
  "$TAKT_DIR/automation" \
  "$TAKT_DIR/quality-gates"; then
  echo 'BLOCKER: OpenCode remains in an executable suisui TAKT route' >&2
  exit 1
fi

printf 'OK: suisui TAKT configuration uses cursor-agent without OpenCode routes\n'
