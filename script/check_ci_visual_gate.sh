#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE_LOCALE="${SUISUI_CI_VISUAL_GATE_LOCALE:-en-US}"
VISUAL_BASELINE_PROFILE="${SUISUI_CI_VISUAL_BASELINE_PROFILE:-local-display}"
case "$GATE_LOCALE" in
  en-US|ja-JP)
    ;;
  *)
    printf 'failure_category=configuration\n' >&2
    printf 'failure_reason=unsupported-visual-gate-locale\n' >&2
    exit 2
    ;;
esac
case "$VISUAL_BASELINE_PROFILE" in
  local-display|apple-virtual-display)
    ;;
  *)
    printf 'failure_category=configuration\n' >&2
    printf 'failure_reason=unsupported-visual-baseline-profile\n' >&2
    exit 2
    ;;
esac
case "$GATE_LOCALE:$VISUAL_BASELINE_PROFILE" in
  en-US:local-display)
    LOCALE_SLUG="en-US"
    CAPTURE_LOCALE="english"
    MANIFEST_RELATIVE="docs/quality/visual-baseline-manifest.json"
    BASELINE_RELATIVE="docs/quality/visual-baselines"
    ;;
  ja-JP:local-display)
    LOCALE_SLUG="ja-JP"
    CAPTURE_LOCALE="japanese"
    MANIFEST_RELATIVE="docs/quality/visual-baseline-manifest-ja.json"
    BASELINE_RELATIVE="docs/quality/visual-baselines-ja"
    ;;
  en-US:apple-virtual-display)
    LOCALE_SLUG="en-US"
    CAPTURE_LOCALE="english"
    MANIFEST_RELATIVE="docs/quality/visual-baseline-manifest-apple-virtual.json"
    BASELINE_RELATIVE="docs/quality/visual-baselines-apple-virtual"
    ;;
  ja-JP:apple-virtual-display)
    LOCALE_SLUG="ja-JP"
    CAPTURE_LOCALE="japanese"
    MANIFEST_RELATIVE="docs/quality/visual-baseline-manifest-ja-apple-virtual.json"
    BASELINE_RELATIVE="docs/quality/visual-baselines-ja-apple-virtual"
    ;;
esac
OUTPUT_DIR="${SUISUI_CI_VISUAL_GATE_OUTPUT_DIR:-$ROOT_DIR/.tmp/ci-visual-gate/$LOCALE_SLUG}"
ROOT_CANONICAL="$(cd "$ROOT_DIR" && pwd -P)"
OUTPUT_CANONICAL=""
SUMMARY_FILE=""
EXPECTED_SCREENSHOT_COUNT=39
STATUS="blocked"
FAILURE_CATEGORY="internal"
FAILURE_REASON="gate-not-completed"
SCREENSHOT_COUNT=0
PRIVATE_DIR=""
SUMMARY_CONTRACT_READY=0

fail_without_summary() {
  local reason="$1"
  printf 'failure_category=configuration\n' >&2
  printf 'failure_reason=%s\n' "$reason" >&2
  exit 2
}

initialize_safe_output() {
  local existing_ancestor="$OUTPUT_DIR"
  local ancestor_parent
  local ancestor_canonical

  if [[ "$OUTPUT_DIR" != /* ]]; then
    OUTPUT_DIR="$PWD/$OUTPUT_DIR"
    existing_ancestor="$OUTPUT_DIR"
  fi

  # Resolve the deepest path component that already exists before mkdir. This
  # prevents mkdir -p from following an output ancestor symlink into an
  # arbitrary filesystem location.
  while [[ ! -e "$existing_ancestor" && ! -L "$existing_ancestor" ]]; do
    ancestor_parent="$(dirname "$existing_ancestor")"
    if [[ "$ancestor_parent" == "$existing_ancestor" ]]; then
      fail_without_summary "unsafe-output-directory"
    fi
    existing_ancestor="$ancestor_parent"
  done
  if [[ ! -d "$existing_ancestor" ]]; then
    fail_without_summary "unsafe-output-directory"
  fi
  if ! ancestor_canonical="$(cd "$existing_ancestor" && pwd -P)"; then
    fail_without_summary "unsafe-output-directory"
  fi
  case "$ancestor_canonical/" in
    "$ROOT_CANONICAL/.tmp/"*|"$ROOT_CANONICAL/.build/"*)
      ;;
    *)
      fail_without_summary "unsafe-output-directory"
      ;;
  esac

  if ! mkdir -p "$OUTPUT_DIR"; then
    fail_without_summary "unsafe-output-directory"
  fi
  if [[ ! -d "$OUTPUT_DIR" || -L "$OUTPUT_DIR" ]]; then
    fail_without_summary "unsafe-output-directory"
  fi
  if ! OUTPUT_CANONICAL="$(cd "$OUTPUT_DIR" && pwd -P)"; then
    fail_without_summary "unsafe-output-directory"
  fi
  case "$OUTPUT_CANONICAL/" in
    "$ROOT_CANONICAL/.tmp/"*|"$ROOT_CANONICAL/.build/"*)
      ;;
    *)
      fail_without_summary "unsafe-output-directory"
      ;;
  esac

  # Use the canonical directory for every later mutation so an accepted
  # lexical alias cannot redirect child artifacts.
  OUTPUT_DIR="$OUTPUT_CANONICAL"
  SUMMARY_FILE="$OUTPUT_DIR/ui-visual-gate-summary.env"
  if [[ -L "$SUMMARY_FILE" || ( -e "$SUMMARY_FILE" && ! -f "$SUMMARY_FILE" ) ]]; then
    fail_without_summary "unsafe-summary-file"
  fi
  SUMMARY_CONTRACT_READY=1
}

validate_summary_destination() {
  local summary_parent_canonical

  if [[ "$SUMMARY_CONTRACT_READY" != "1" || ! -d "$OUTPUT_DIR" || -L "$OUTPUT_DIR" ]]; then
    return 1
  fi
  if ! summary_parent_canonical="$(cd "$(dirname "$SUMMARY_FILE")" && pwd -P)"; then
    return 1
  fi
  if [[ "$summary_parent_canonical" != "$OUTPUT_CANONICAL" ]]; then
    return 1
  fi
  if [[ -L "$SUMMARY_FILE" || ( -e "$SUMMARY_FILE" && ! -f "$SUMMARY_FILE" ) ]]; then
    return 1
  fi
}

write_summary() {
  local summary_private_dir=""
  local summary_temp_file=""
  local summary_private_parent=""

  if ! validate_summary_destination; then
    printf 'BLOCKER: visual gate summary destination is unsafe\n' >&2
    return 1
  fi
  umask 077
  if ! summary_private_dir="$(mktemp -d "$OUTPUT_DIR/.ui-visual-gate-summary.XXXXXX")"; then
    printf 'BLOCKER: visual gate summary private directory could not be created\n' >&2
    return 1
  fi
  if [[ ! -d "$summary_private_dir" || -L "$summary_private_dir" ]]; then
    rmdir "$summary_private_dir" >/dev/null 2>&1 || true
    printf 'BLOCKER: visual gate summary private directory is unsafe\n' >&2
    return 1
  fi
  if ! summary_private_parent="$(cd "$(dirname "$summary_private_dir")" && pwd -P)" \
    || [[ "$summary_private_parent" != "$OUTPUT_CANONICAL" ]]; then
    rmdir "$summary_private_dir" >/dev/null 2>&1 || true
    printf 'BLOCKER: visual gate summary private directory escaped the output directory\n' >&2
    return 1
  fi
  summary_temp_file="$summary_private_dir/summary.env"

  # This is intentionally a closed, path-free vocabulary so the artifact can
  # be uploaded from a public CI run without exposing runner-local state.
  if ! (
    set -o noclobber
    {
      printf 'schema_version=1\n'
      printf 'gate=visual\n'
      printf 'status=%s\n' "$STATUS"
      printf 'failure_category=%s\n' "$FAILURE_CATEGORY"
      printf 'failure_reason=%s\n' "$FAILURE_REASON"
      printf 'locale=%s\n' "$GATE_LOCALE"
      printf 'locale_slug=%s\n' "$LOCALE_SLUG"
      printf 'expected_screenshot_count=%s\n' "$EXPECTED_SCREENSHOT_COUNT"
      printf 'screenshot_count=%s\n' "$SCREENSHOT_COUNT"
      printf 'capture_route=normal\n'
      printf 'baseline_update=disabled\n'
    } >"$summary_temp_file"
  ); then
    rm -f "$summary_temp_file"
    rmdir "$summary_private_dir" >/dev/null 2>&1 || true
    printf 'BLOCKER: visual gate summary private file could not be written\n' >&2
    return 1
  fi
  if [[ ! -f "$summary_temp_file" || -L "$summary_temp_file" ]] \
    || ! validate_summary_destination; then
    rm -f "$summary_temp_file"
    rmdir "$summary_private_dir" >/dev/null 2>&1 || true
    printf 'BLOCKER: visual gate summary contract changed before publication\n' >&2
    return 1
  fi
  # BSD mv -h never follows a destination symlink to a directory. The rename
  # remains on the output filesystem and atomically replaces a regular summary.
  if ! /bin/mv -fh "$summary_temp_file" "$SUMMARY_FILE"; then
    rm -f "$summary_temp_file"
    rmdir "$summary_private_dir" >/dev/null 2>&1 || true
    printf 'BLOCKER: visual gate summary could not be published atomically\n' >&2
    return 1
  fi
  rmdir "$summary_private_dir" >/dev/null 2>&1 || true
  if [[ ! -f "$SUMMARY_FILE" || -L "$SUMMARY_FILE" ]]; then
    printf 'BLOCKER: published visual gate summary is unsafe\n' >&2
    return 1
  fi
}

cleanup() {
  if [[ -n "${PRIVATE_DIR:-}" && -d "$PRIVATE_DIR" ]]; then
    rm -rf "$PRIVATE_DIR"
  fi
}

finalize() {
  local exit_code=$?
  if ! write_summary; then
    printf 'summary_artifact=unavailable\n' >&2
  fi
  cleanup
  return "$exit_code"
}

block() {
  local category="$1"
  local reason="$2"
  local exit_code="${3:-1}"
  STATUS="blocked"
  FAILURE_CATEGORY="$category"
  FAILURE_REASON="$reason"
  if ! write_summary; then
    printf 'summary_artifact=unavailable\n' >&2
  fi
  printf 'failure_category=%s\n' "$FAILURE_CATEGORY" >&2
  printf 'failure_reason=%s\n' "$FAILURE_REASON" >&2
  printf 'summary_artifact=ui-visual-gate-summary.env\n' >&2
  exit "$exit_code"
}

initialize_safe_output
trap finalize EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ $# -ne 0 ]]; then
  block "configuration" "arguments-not-supported" 2
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
MANIFEST="$ROOT_DIR/$MANIFEST_RELATIVE"
CI_MANIFEST="$CURRENT_DIR/visual-baseline-manifest.json"
BASELINE_DIR="$ROOT_DIR/$BASELINE_RELATIVE"
TRACKED_EVIDENCE_BEFORE="$PRIVATE_DIR/tracked-evidence-before"
TRACKED_EVIDENCE_AFTER="$PRIVATE_DIR/tracked-evidence-after"

rm -rf "$CURRENT_DIR" "$DIFF_DIR" "$LOG_DIR" "$CAPABILITY_DIR"
mkdir -p "$SCREENSHOT_DIR" "$DIFF_DIR" "$LOG_DIR" "$CAPABILITY_DIR" "$PRIVATE_TMP"

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
    git -C "$ROOT_DIR" status --porcelain=v1 --untracked-files=all -- \
      docs/release/evidence \
      docs/quality/visual-baseline-manifest.json \
      docs/quality/visual-baseline-manifest-ja.json \
      docs/quality/visual-baseline-manifest-apple-virtual.json \
      docs/quality/visual-baseline-manifest-ja-apple-virtual.json \
      docs/quality/visual-baselines \
      docs/quality/visual-baselines-ja \
      docs/quality/visual-baselines-apple-virtual \
      docs/quality/visual-baselines-ja-apple-virtual
    git -C "$ROOT_DIR" diff --no-ext-diff --no-textconv --binary -- \
      docs/release/evidence \
      docs/quality/visual-baseline-manifest.json \
      docs/quality/visual-baseline-manifest-ja.json \
      docs/quality/visual-baseline-manifest-apple-virtual.json \
      docs/quality/visual-baseline-manifest-ja-apple-virtual.json \
      docs/quality/visual-baselines \
      docs/quality/visual-baselines-ja \
      docs/quality/visual-baselines-apple-virtual \
      docs/quality/visual-baselines-ja-apple-virtual
    git -C "$ROOT_DIR" diff --no-ext-diff --no-textconv --cached --binary -- \
      docs/release/evidence \
      docs/quality/visual-baseline-manifest.json \
      docs/quality/visual-baseline-manifest-ja.json \
      docs/quality/visual-baseline-manifest-apple-virtual.json \
      docs/quality/visual-baseline-manifest-ja-apple-virtual.json \
      docs/quality/visual-baselines \
      docs/quality/visual-baselines-ja \
      docs/quality/visual-baselines-apple-virtual \
      docs/quality/visual-baselines-ja-apple-virtual
  } >"$output_file"
}

if ! command -v git >/dev/null 2>&1; then
  block "configuration" "git-unavailable" 2
fi
if [[ ! -f "$MANIFEST" || -L "$MANIFEST" || ! -d "$BASELINE_DIR" || -L "$BASELINE_DIR" ]]; then
  block "configuration" "visual-baseline-unavailable" 2
fi
MANIFEST_LOCALE="$(/usr/bin/plutil -extract baselineContext.locale raw -o - "$MANIFEST" 2>/dev/null || true)"
if [[ "$MANIFEST_LOCALE" != "$GATE_LOCALE" ]]; then
  block "configuration" "visual-baseline-locale-mismatch" 2
fi
MANIFEST_BASELINE_ROOT="$(/usr/bin/plutil -extract baselineRoot raw -o - "$MANIFEST" 2>/dev/null || true)"
if [[ "$MANIFEST_BASELINE_ROOT" != "$BASELINE_RELATIVE" ]]; then
  block "configuration" "visual-baseline-profile-root-mismatch" 2
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
  SUISUI_UI_EVIDENCE_LOCALE="$CAPTURE_LOCALE" \
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
printf 'locale=%s\n' "$GATE_LOCALE"
printf 'locale_slug=%s\n' "$LOCALE_SLUG"
printf 'summary_artifact=ui-visual-gate-summary.env\n'
