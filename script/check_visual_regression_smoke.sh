#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${SOLOPM_VISUAL_BASELINE_MANIFEST:-$ROOT_DIR/docs/quality/visual-baseline-manifest.json}"
SCREENSHOT_DIR="${SOLOPM_VISUAL_SCREENSHOT_DIR:-$ROOT_DIR/docs/release/evidence/ui-screenshots}"
BASELINE_DIR="${SOLOPM_VISUAL_BASELINE_DIR:-$ROOT_DIR/docs/quality/visual-baselines}"
UPDATE_BASELINES=0
ALLOW_UPDATE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest)
      MANIFEST="${2:?--manifest requires a path}"
      shift 2
      ;;
    --screenshot-dir)
      SCREENSHOT_DIR="${2:?--screenshot-dir requires a path}"
      shift 2
      ;;
    --baseline-dir)
      BASELINE_DIR="${2:?--baseline-dir requires a path}"
      shift 2
      ;;
    --update-baselines)
      UPDATE_BASELINES=1
      shift
      ;;
    --allow-update)
      ALLOW_UPDATE=1
      shift
      ;;
    *)
      echo "usage: $0 [--manifest path] [--screenshot-dir path] [--baseline-dir path] [--update-baselines --allow-update]" >&2
      exit 2
      ;;
  esac
done

if [[ "$UPDATE_BASELINES" == "1" && "$ALLOW_UPDATE" != "1" ]]; then
  echo "BLOCKER: baseline update requires --allow-update" >&2
  exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
  echo "BLOCKER: swift is required for visual regression smoke" >&2
  exit 2
fi

args=(
  "--manifest" "$MANIFEST"
  "--screenshot-dir" "$SCREENSHOT_DIR"
  "--baseline-dir" "$BASELINE_DIR"
)

if [[ "$UPDATE_BASELINES" == "1" ]]; then
  args+=("--update-baselines")
fi

/usr/bin/swift "$ROOT_DIR/script/visual_regression_smoke_check.swift" "${args[@]}"
