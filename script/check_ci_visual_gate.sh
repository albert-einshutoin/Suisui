#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${SUISUI_CI_VISUAL_GATE_OUTPUT_DIR:-$ROOT_DIR/.tmp/ci-visual-gate}"
SUMMARY_FILE="$OUTPUT_DIR/ui-visual-gate-summary.env"
EXPECTED_SCREENSHOT_COUNT=39
STATUS="blocked"
FAILURE_CATEGORY="internal"
FAILURE_REASON="gate-not-completed"
SCREENSHOT_COUNT=0
PRIVATE_DIR=""

mkdir -p "$OUTPUT_DIR"

write_summary() {
  # This is intentionally a closed, path-free vocabulary so the artifact can
  # be uploaded from a public CI run without exposing runner-local state.
  {
    printf 'schema_version=1\n'
    printf 'gate=visual\n'
    printf 'status=%s\n' "$STATUS"
    printf 'failure_category=%s\n' "$FAILURE_CATEGORY"
    printf 'failure_reason=%s\n' "$FAILURE_REASON"
    printf 'expected_screenshot_count=%s\n' "$EXPECTED_SCREENSHOT_COUNT"
    printf 'screenshot_count=%s\n' "$SCREENSHOT_COUNT"
    printf 'capture_route=normal\n'
    printf 'baseline_update=disabled\n'
  } >"$SUMMARY_FILE"
}

cleanup() {
  if [[ -n "${PRIVATE_DIR:-}" && -d "$PRIVATE_DIR" ]]; then
    rm -rf "$PRIVATE_DIR"
  fi
}

finalize() {
  local exit_code=$?
  write_summary
  cleanup
  return "$exit_code"
}
trap finalize EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

block() {
  local category="$1"
  local reason="$2"
  local exit_code="${3:-1}"
  STATUS="blocked"
  FAILURE_CATEGORY="$category"
  FAILURE_REASON="$reason"
  write_summary
  printf 'failure_category=%s\n' "$FAILURE_CATEGORY" >&2
  printf 'failure_reason=%s\n' "$FAILURE_REASON" >&2
  printf 'summary_artifact=ui-visual-gate-summary.env\n' >&2
  exit "$exit_code"
}

if [[ $# -ne 0 ]]; then
  block "configuration" "arguments-not-supported" 2
fi

ROOT_CANONICAL="$(cd "$ROOT_DIR" && pwd -P)"
OUTPUT_CANONICAL="$(cd "$OUTPUT_DIR" && pwd -P)"
case "$OUTPUT_CANONICAL/" in
  "$ROOT_CANONICAL/.tmp/"*|"$ROOT_CANONICAL/.build/"*)
    ;;
  *)
    block "configuration" "unsafe-output-directory" 2
    ;;
esac
if [[ "$OUTPUT_CANONICAL" == "/" || "$OUTPUT_CANONICAL" == "/tmp" || "$OUTPUT_CANONICAL" == "/var/tmp" || "$OUTPUT_CANONICAL" == "${HOME:-}" ]]; then
  block "configuration" "unsafe-output-directory" 2
fi

CURRENT_DIR="$OUTPUT_DIR/current"
SCREENSHOT_DIR="$CURRENT_DIR/screenshots"
DIFF_DIR="$OUTPUT_DIR/diff"
LOG_DIR="$OUTPUT_DIR/logs"
CAPABILITY_DIR="$OUTPUT_DIR/capability"
PRIVATE_DIR="$(mktemp -d "/tmp/suisui-ci-visual-gate.XXXXXX")"
PRIVATE_HOME="$PRIVATE_DIR/home"
PRIVATE_TMP="$PRIVATE_DIR/tmp"
CAPTURE_EVIDENCE_FILE="$CURRENT_DIR/ui-screenshots.md"
AX_RECEIPT="$CURRENT_DIR/visual-ax-audit-receipt.json"
MANIFEST="$ROOT_DIR/docs/quality/visual-baseline-manifest.json"
CI_MANIFEST="$CURRENT_DIR/visual-baseline-manifest.json"
BASELINE_DIR="$ROOT_DIR/docs/quality/visual-baselines"
TRACKED_EVIDENCE_BEFORE="$PRIVATE_DIR/tracked-evidence-before"
TRACKED_EVIDENCE_AFTER="$PRIVATE_DIR/tracked-evidence-after"

rm -rf "$CURRENT_DIR" "$DIFF_DIR" "$LOG_DIR" "$CAPABILITY_DIR"
mkdir -p "$SCREENSHOT_DIR" "$DIFF_DIR" "$LOG_DIR" "$CAPABILITY_DIR" "$PRIVATE_HOME" "$PRIVATE_TMP"

sanitize_log() {
  local input_file="$1"
  local output_file="$2"
  /usr/bin/sed -E \
    -e 's#/(Users|Volumes)/[^[:space:]]+#<path>#g' \
    -e 's#/private/var/folders/[^[:space:]]+#<temp-path>#g' \
    -e 's#(/var)?/tmp/[^[:space:]]+#<temp-path>#g' \
    "$input_file" >"$output_file"
}

run_logged() {
  local stage="$1"
  shift
  local raw_log="$PRIVATE_DIR/${stage}.raw.log"
  local safe_log="$LOG_DIR/${stage}.log"
  local command_status
  set +e
  "$@" >"$raw_log" 2>&1
  command_status=$?
  set -e
  sanitize_log "$raw_log" "$safe_log"
  /bin/cat "$safe_log"
  return "$command_status"
}

snapshot_tracked_evidence() {
  local output_file="$1"
  {
    git -C "$ROOT_DIR" status --porcelain=v1 --untracked-files=all -- docs/release/evidence docs/quality/visual-baseline-manifest.json docs/quality/visual-baselines
    git -C "$ROOT_DIR" diff --binary -- docs/release/evidence docs/quality/visual-baseline-manifest.json docs/quality/visual-baselines
    git -C "$ROOT_DIR" diff --cached --binary -- docs/release/evidence docs/quality/visual-baseline-manifest.json docs/quality/visual-baselines
  } >"$output_file"
}

if ! command -v git >/dev/null 2>&1; then
  block "configuration" "git-unavailable" 2
fi
if [[ ! -r "$MANIFEST" || ! -d "$BASELINE_DIR" ]]; then
  block "configuration" "visual-baseline-unavailable" 2
fi

MANIFEST_SCREENSHOT_COUNT="$(grep -Eo '"[^"]+\.png"' "$MANIFEST" | sort -u | wc -l | tr -d '[:space:]')"
if [[ "$MANIFEST_SCREENSHOT_COUNT" != "$EXPECTED_SCREENSHOT_COUNT" ]]; then
  block "configuration" "unexpected-baseline-count" 2
fi

# The checked-in manifest authenticates the baseline set, but its artifactRoot
# points at release evidence. Stage a private copy whose root matches this
# gate's isolated screenshot directory so capture and comparison share one
# truthful runtime contract without mutating tracked provenance.
if ! /bin/cp "$MANIFEST" "$CI_MANIFEST"; then
  block "configuration" "private-manifest-copy-failed" 2
fi
SCREENSHOT_ARTIFACT_ROOT="${SCREENSHOT_DIR#"$ROOT_DIR/"}"
if ! /usr/bin/plutil -replace artifactRoot -string "$SCREENSHOT_ARTIFACT_ROOT" "$CI_MANIFEST"; then
  block "configuration" "private-manifest-update-failed" 2
fi
if [[ ! -f "$CI_MANIFEST" || -L "$CI_MANIFEST" ]]; then
  block "configuration" "unsafe-private-manifest" 2
fi
CI_MANIFEST_PARENT="$(cd "$(dirname "$CI_MANIFEST")" && pwd -P)"
case "$CI_MANIFEST_PARENT/" in
  "$ROOT_CANONICAL/.tmp/"*|"$ROOT_CANONICAL/.build/"*)
    ;;
  *)
    block "configuration" "unsafe-private-manifest" 2
    ;;
esac

snapshot_tracked_evidence "$TRACKED_EVIDENCE_BEFORE"

if ! run_logged capability \
  /usr/bin/env \
  SUISUI_UI_RUNNER_CAPABILITY_ARTIFACT_DIR="$CAPABILITY_DIR" \
  "$ROOT_DIR/script/check_macos_ui_runner_capabilities.sh" visual; then
  block "runner-capability" "visual-runner-capability-unavailable"
fi

# Removing the receipt before capture makes a stale successful receipt
# impossible to reuse if the 39-artifact capture exits partway through.
rm -f "$AX_RECEIPT"
if ! run_logged capture \
  /usr/bin/env \
  SUISUI_UI_EVIDENCE_DIR="$SCREENSHOT_DIR" \
  SUISUI_UI_EVIDENCE_FILE="$CAPTURE_EVIDENCE_FILE" \
  SUISUI_SCHEDULE_COCKPIT_EVIDENCE_FILE="$CURRENT_DIR/schedule-cockpit-screenshots.md" \
  SUISUI_DONE_ANALYTICS_EVIDENCE_FILE="$CURRENT_DIR/done-analytics-screenshots.md" \
  SUISUI_UI_EVIDENCE_TMPDIR="$PRIVATE_TMP" \
  SUISUI_UI_EVIDENCE_HOME="$PRIVATE_HOME" \
  SUISUI_UI_EVIDENCE_KEEP_HOME=0 \
  SUISUI_VISUAL_AX_AUDIT_RESULT="$AX_RECEIPT" \
  SUISUI_VISUAL_BASELINE_MANIFEST="$CI_MANIFEST" \
  "$ROOT_DIR/script/capture_ui_evidence.sh"; then
  block "capture" "full-capture-failed"
fi

SCREENSHOT_COUNT="$(find "$SCREENSHOT_DIR" -maxdepth 1 -type f -name '*.png' | wc -l | tr -d '[:space:]')"
if [[ "$SCREENSHOT_COUNT" != "$EXPECTED_SCREENSHOT_COUNT" ]]; then
  block "capture" "incomplete-screenshot-coverage"
fi
if ! [[ -s "$AX_RECEIPT" ]]; then
  block "capture" "fresh-ax-receipt-missing"
fi

snapshot_tracked_evidence "$TRACKED_EVIDENCE_AFTER"
if ! cmp -s "$TRACKED_EVIDENCE_BEFORE" "$TRACKED_EVIDENCE_AFTER"; then
  block "safety" "tracked-evidence-mutated"
fi

# Baselines are inputs only. This wrapper accepts no arguments and never
# forwards either baseline-update switch supported by the lower-level checker.
if ! run_logged compare \
  /usr/bin/env \
  SUISUI_VISUAL_BASELINE_MANIFEST="$CI_MANIFEST" \
  SUISUI_VISUAL_SCREENSHOT_DIR="$SCREENSHOT_DIR" \
  SUISUI_VISUAL_BASELINE_DIR="$BASELINE_DIR" \
  SUISUI_VISUAL_ARTIFACT_DIR="$DIFF_DIR" \
  SUISUI_VISUAL_AX_AUDIT_RESULT="$AX_RECEIPT" \
  "$ROOT_DIR/script/check_visual_regression_smoke.sh"; then
  block "visual-diff" "baseline-comparison-failed"
fi

snapshot_tracked_evidence "$TRACKED_EVIDENCE_AFTER"
if ! cmp -s "$TRACKED_EVIDENCE_BEFORE" "$TRACKED_EVIDENCE_AFTER"; then
  block "safety" "tracked-evidence-mutated"
fi

STATUS="passed"
FAILURE_CATEGORY="none"
FAILURE_REASON="none"
write_summary
printf 'status=passed\n'
printf 'gate=visual\n'
printf 'summary_artifact=ui-visual-gate-summary.env\n'
