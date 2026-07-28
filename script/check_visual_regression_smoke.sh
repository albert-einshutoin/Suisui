#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${SUISUI_VISUAL_BASELINE_MANIFEST:-$ROOT_DIR/docs/quality/visual-baseline-manifest.json}"
SCREENSHOT_DIR="${SUISUI_VISUAL_SCREENSHOT_DIR:-$ROOT_DIR/docs/release/evidence/ui-screenshots}"
BASELINE_DIR="${SUISUI_VISUAL_BASELINE_DIR:-$ROOT_DIR/docs/quality/visual-baselines}"
ARTIFACT_DIR="${SUISUI_VISUAL_ARTIFACT_DIR:-$ROOT_DIR/.tmp/visual-regression-artifacts}"
AX_AUDIT_RESULT="${SUISUI_AX_AUDIT_RESULT:-${SUISUI_VISUAL_AX_AUDIT_RESULT:-$ROOT_DIR/.tmp/visual-ax-audit-receipt.json}}"
CURRENT_SOURCE_COMMIT="${SUISUI_VISUAL_CURRENT_SOURCE_COMMIT:-}"
UPDATE_BASELINES=0
ALLOW_UPDATE=0
RASTER_ONLY=0
FORWARD_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest|--screenshot-dir|--baseline-dir|--artifact-dir|--ax-audit-result|--current-source-commit)
      [[ $# -ge 2 ]] || { echo "BLOCKER: $1 requires a path" >&2; exit 2; }
      case "$1" in
        --manifest) MANIFEST="$2";; --screenshot-dir) SCREENSHOT_DIR="$2";; --baseline-dir) BASELINE_DIR="$2";; --artifact-dir) ARTIFACT_DIR="$2";; --ax-audit-result) AX_AUDIT_RESULT="$2";; --current-source-commit) CURRENT_SOURCE_COMMIT="$2";;
      esac
      shift 2;;
    --update-baselines) UPDATE_BASELINES=1; shift;;
    --allow-update) ALLOW_UPDATE=1; shift;;
    --raster-only) RASTER_ONLY=1; shift;;
    *) echo "BLOCKER: usage: $0 [--manifest path] [--screenshot-dir path] [--baseline-dir path] [--artifact-dir path] [--ax-audit-result path] [--current-source-commit commit] [--raster-only] [--update-baselines --allow-update]" >&2; exit 2;;
  esac
done
if [[ "$UPDATE_BASELINES" == 1 && "$ALLOW_UPDATE" != 1 ]]; then echo "BLOCKER: baseline update requires --allow-update" >&2; exit 1; fi
if [[ "$RASTER_ONLY" == 1 && "$UPDATE_BASELINES" == 1 ]]; then
  echo "BLOCKER: raster-only comparison is read-only and cannot update baselines" >&2
  exit 1
fi
if [[ -z "$CURRENT_SOURCE_COMMIT" ]]; then
  SOURCE_REF="${SUISUI_VISUAL_SOURCE_REF:-HEAD}"
  CURRENT_SOURCE_COMMIT="$(git -C "$ROOT_DIR" log -1 --format=%H "$SOURCE_REF" -- Sources Package.swift script/capture_ui_evidence.sh 2>/dev/null || true)"
fi
[[ -n "$CURRENT_SOURCE_COMMIT" ]] || { echo "BLOCKER: current product source commit is unavailable; pass --current-source-commit" >&2; exit 1; }
command -v swiftc >/dev/null 2>&1 || { echo "BLOCKER: swiftc is required for visual regression smoke" >&2; exit 2; }
mkdir -p "$ROOT_DIR/.tmp"
MODULE_CACHE_DIR="$ROOT_DIR/.tmp/visual-regression-module-cache"
mkdir -p "$MODULE_CACHE_DIR"
CHECKER_SOURCE="$ROOT_DIR/script/visual_regression_smoke_check.swift"
CHECKER_BINARY="$ROOT_DIR/.tmp/visual_regression_smoke_check"
if [[ ! -x "$CHECKER_BINARY" || "$CHECKER_SOURCE" -nt "$CHECKER_BINARY" ]]; then
  CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR" swiftc "$CHECKER_SOURCE" -o "$CHECKER_BINARY" || { echo "BLOCKER: could not compile visual regression checker" >&2; exit 1; }
fi
FORWARD_ARGS=(--manifest "$MANIFEST" --screenshot-dir "$SCREENSHOT_DIR" --baseline-dir "$BASELINE_DIR" --artifact-dir "$ARTIFACT_DIR" --current-source-commit "$CURRENT_SOURCE_COMMIT")
[[ "$RASTER_ONLY" == 0 && -n "$AX_AUDIT_RESULT" ]] && FORWARD_ARGS+=(--ax-audit-result "$AX_AUDIT_RESULT")
[[ "$RASTER_ONLY" == 1 ]] && FORWARD_ARGS+=(--raster-only)
[[ "$UPDATE_BASELINES" == 1 ]] && FORWARD_ARGS+=(--update-baselines)
[[ "$ALLOW_UPDATE" == 1 ]] && FORWARD_ARGS+=(--allow-update)
"$CHECKER_BINARY" "${FORWARD_ARGS[@]}"
