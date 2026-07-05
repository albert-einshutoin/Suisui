#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METADATA_FILE="$ROOT_DIR/packaging/app_metadata.env"

if [[ ! -f "$METADATA_FILE" ]]; then
  echo "missing metadata file: $METADATA_FILE" >&2
  exit 2
fi

# shellcheck source=/dev/null
source "$METADATA_FILE"

APP_NAME="${APP_NAME:?APP_NAME is required}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-}"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
TIMEOUT_SECONDS="${SOLOPM_PERFORMANCE_TIMEOUT_SECONDS:-30}"
OUTPUT_DIR="${SOLOPM_PERFORMANCE_OUTPUT_DIR:-$ROOT_DIR/.tmp/release-launch-performance}"
SUMMARY_FILE="$OUTPUT_DIR/summary.md"
SAMPLES_FILE="$OUTPUT_DIR/samples.tsv"
AX_HELPERS="${AX_HELPERS:-$ROOT_DIR/script/ui_accessibility_smoke_helpers.sh}"
SOLOPM_PERFORMANCE_PROFILE="${SOLOPM_PERFORMANCE_PROFILE:-release}"

case "$SOLOPM_PERFORMANCE_PROFILE" in
  release)
    # Release profile keeps the build aligned with release-machine evidence and
    # the stricter Sparkle requirements already enforced by the release path.
    DEFAULT_BUILD_CONFIGURATION=release
    DEFAULT_COLD_LAUNCH_BUDGET_MS=15000
    DEFAULT_DESTINATION_SWITCH_BUDGET_MS=3000
    ;;
  debug)
    # Debug profile keeps local and CI diagnostics usable when release secrets
    # are intentionally absent, while still enforcing measured launch budgets.
    DEFAULT_BUILD_CONFIGURATION=debug
    DEFAULT_COLD_LAUNCH_BUDGET_MS=25000
    DEFAULT_DESTINATION_SWITCH_BUDGET_MS=5000
    ;;
  *)
    echo "BLOCKER: SOLOPM_PERFORMANCE_PROFILE must be release or debug" >&2
    exit 2
    ;;
esac

BUILD_CONFIGURATION="${SOLOPM_PERFORMANCE_BUILD_CONFIGURATION:-$DEFAULT_BUILD_CONFIGURATION}"
MAX_COLD_LAUNCH_MS="${SOLOPM_PERFORMANCE_MAX_COLD_LAUNCH_MS:-$DEFAULT_COLD_LAUNCH_BUDGET_MS}"
MAX_DESTINATION_SWITCH_MS="${SOLOPM_PERFORMANCE_MAX_DESTINATION_SWITCH_MS:-$DEFAULT_DESTINATION_SWITCH_BUDGET_MS}"

cd "$ROOT_DIR"
mkdir -p "$OUTPUT_DIR"

# shellcheck source=/dev/null
source "$AX_HELPERS"

now_ms() {
  /usr/bin/perl -MTime::HiRes=time -e 'printf "%d\n", time() * 1000'
}

terminate_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

activate_app() {
  /usr/bin/osascript -e "tell application \"$APP_NAME\" to activate" >/dev/null 2>&1 &
  local osascript_pid=$!
  for _ in {1..20}; do
    if ! kill -0 "$osascript_pid" >/dev/null 2>&1; then
      wait "$osascript_pid" >/dev/null 2>&1 || true
      return 0
    fi
    sleep 0.1
  done
  kill "$osascript_pid" >/dev/null 2>&1 || true
  wait "$osascript_pid" >/dev/null 2>&1 || true
}

open_app() {
  /usr/bin/open -n -F "$APP_BUNDLE" --args -ApplePersistenceIgnoreState YES
  activate_app
}

wait_for_visible_window() {
  if ax_wait_for_visible_window "$APP_NAME" "$TIMEOUT_SECONDS" "$BUNDLE_IDENTIFIER"; then
    return 0
  fi
  echo "BLOCKER: $APP_NAME did not publish a visible window within ${TIMEOUT_SECONDS}s" >&2
  return 1
}

click_sidebar_destination() {
  local destination_identifier="$1"
  local destination_label="$2"
  ax_click_sidebar_destination "$APP_NAME" "$destination_identifier" "$destination_label"
}

wait_for_marker() {
  local identifier="$1"
  local safe_identifier="${identifier//[^[:alnum:]_-]/_}"
  local probe_file="$OUTPUT_DIR/wait-$safe_identifier.txt"
  if ax_wait_for_ax_identifier "$APP_NAME" "$identifier" "$TIMEOUT_SECONDS" "$ROOT_DIR" "$probe_file"; then
    return 0
  fi
  echo "BLOCKER: performance smoke could not inspect the AX marker: $identifier" >&2
  sed -n '1,20p' "$probe_file.err" >&2 || true
  sed -n '1,20p' "$probe_file" >&2 || true
  return 1
}

assert_sample_within_budget() {
  local label="$1"
  local elapsed_ms="$2"
  local budget_ms="$3"
  if [[ -z "$budget_ms" ]]; then
    return 0
  fi
  if [[ ! "$budget_ms" =~ ^[0-9]+$ ]]; then
    echo "BLOCKER: invalid performance budget for $label: $budget_ms" >&2
    return 1
  fi
  if (( elapsed_ms > budget_ms )); then
    echo "BLOCKER: performance budget exceeded for $label: ${elapsed_ms}ms > ${budget_ms}ms" >&2
    return 1
  fi
}

record_sample() {
  local label="$1"
  local start_ms="$2"
  local end_ms="$3"
  local budget_ms="${4:-}"
  local elapsed_ms=$((end_ms - start_ms))
  printf '%s\t%s\n' "$label" "$elapsed_ms" >>"$SAMPLES_FILE"
  if [[ -n "$budget_ms" ]]; then
    printf -- '- `%s`: `%sms` (budget `%sms`)\n' "$label" "$elapsed_ms" "$budget_ms" >>"$SUMMARY_FILE"
  else
    printf -- '- `%s`: `%sms`\n' "$label" "$elapsed_ms" >>"$SUMMARY_FILE"
  fi
  assert_sample_within_budget "$label" "$elapsed_ms" "$budget_ms"
  printf "OK: %s completed in %sms\n" "$label" "$elapsed_ms"
}

measure_destination() {
  local label="$1"
  local destination_identifier="$2"
  local destination_label="$3"
  local marker="$4"
  local start_ms end_ms
  start_ms="$(now_ms)"
  click_sidebar_destination "$destination_identifier" "$destination_label"
  wait_for_marker "$marker"
  end_ms="$(now_ms)"
  record_sample "$label" "$start_ms" "$end_ms" "$MAX_DESTINATION_SWITCH_MS"
}

trap terminate_app EXIT

{
  printf '%s\n' '# Release Launch Performance Smoke'
  printf '\n'
  printf 'Generated at: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf 'Performance profile: `%s`\n' "$SOLOPM_PERFORMANCE_PROFILE"
  printf 'Build configuration: `%s`\n' "$BUILD_CONFIGURATION"
  printf 'Default cold launch budget: `%sms`\n' "$MAX_COLD_LAUNCH_MS"
  printf 'Default destination switch budget: `%sms`\n' "$MAX_DESTINATION_SWITCH_MS"
  printf '\n'
  printf '%s\n' '## Samples'
} >"$SUMMARY_FILE"
printf '%s\t%s\n' "label" "elapsed_ms" >"$SAMPLES_FILE"

terminate_app
SOLOPM_BUILD_CONFIGURATION="$BUILD_CONFIGURATION" ./script/build_and_run.sh --build-only

launch_start_ms="$(now_ms)"
open_app
wait_for_visible_window
wait_for_marker "project-board-header-bar"
launch_end_ms="$(now_ms)"
record_sample "cold-launch-visible-window" "$launch_start_ms" "$launch_end_ms" "$MAX_COLD_LAUNCH_MS"

measure_destination "destination-inbox" "sidebar-destination-inbox" "Inbox" "inbox-workflow"
measure_destination "destination-assistant-queue" "sidebar-destination-assistant-queue" "Assistant Queue" "assistant-queue-workflow"
measure_destination "destination-today" "sidebar-destination-today" "Today" "today-workflow"

printf '\nStatus: passed\n' >>"$SUMMARY_FILE"
printf "OK: release launch performance smoke passed; artifacts written to %s\n" "$OUTPUT_DIR"
