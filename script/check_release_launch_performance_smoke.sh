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
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
TIMEOUT_SECONDS="${SOLOPM_PERFORMANCE_TIMEOUT_SECONDS:-30}"
OUTPUT_DIR="${SOLOPM_PERFORMANCE_OUTPUT_DIR:-$ROOT_DIR/.tmp/release-launch-performance}"
PERFORMANCE_HOME="${SOLOPM_PERFORMANCE_HOME:-$OUTPUT_DIR/home}"
PERFORMANCE_DATABASE_PATH="${SOLOPM_PERFORMANCE_DATABASE_PATH:-$PERFORMANCE_HOME/Library/Application Support/SoloPM/SoloPM.sqlite}"
SUMMARY_FILE="$OUTPUT_DIR/summary.md"
SAMPLES_FILE="$OUTPUT_DIR/samples.tsv"
AX_HELPERS="${AX_HELPERS:-$ROOT_DIR/script/ui_accessibility_smoke_helpers.sh}"
AX_PRESS_ELEMENT_HELPER="${AX_PRESS_ELEMENT_HELPER:-$ROOT_DIR/script/ui_evidence_ax_press_element.swift}"
AX_MARKER_HELPER="${AX_MARKER_HELPER:-$ROOT_DIR/script/ui_evidence_ax_marker_check.swift}"
AX_PRESS_ELEMENT_HELPER_EXECUTABLE="$OUTPUT_DIR/ui-evidence-ax-press-element.$$"
AX_MARKER_HELPER_EXECUTABLE="$OUTPUT_DIR/ui-evidence-ax-marker-checker.$$"
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

PERFORMANCE_BUILD_CONFIGURATION_OVERRIDE="${SOLOPM_PERFORMANCE_BUILD_CONFIGURATION:-}"
if [[ "$SOLOPM_PERFORMANCE_PROFILE" == "release" && -n "$PERFORMANCE_BUILD_CONFIGURATION_OVERRIDE" && "$PERFORMANCE_BUILD_CONFIGURATION_OVERRIDE" != "release" ]]; then
  # Release safety stays strict here so release evidence cannot be weakened by
  # a debug build override hiding launch behavior differences.
  echo "BLOCKER: release performance profile requires release build configuration" >&2
  exit 2
fi

BUILD_CONFIGURATION="${PERFORMANCE_BUILD_CONFIGURATION_OVERRIDE:-$DEFAULT_BUILD_CONFIGURATION}"
MAX_COLD_LAUNCH_MS="${SOLOPM_PERFORMANCE_MAX_COLD_LAUNCH_MS:-$DEFAULT_COLD_LAUNCH_BUDGET_MS}"
MAX_DESTINATION_SWITCH_MS="${SOLOPM_PERFORMANCE_MAX_DESTINATION_SWITCH_MS:-$DEFAULT_DESTINATION_SWITCH_BUDGET_MS}"

require_positive_integer_budget() {
  local name="$1"
  local value="$2"
  if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then
    echo "BLOCKER: $name must be a positive integer millisecond budget" >&2
    exit 2
  fi
}

reject_relaxed_release_budget() {
  local name="$1"
  local value="$2"
  local default_value="$3"
  if [[ "$SOLOPM_PERFORMANCE_PROFILE" == "release" && "$value" -gt "$default_value" ]]; then
    # Release evidence must not be made easier by env overrides; lower values are
    # allowed because they are stricter and preserve the release baseline.
    echo "BLOCKER: release performance budget override cannot exceed default $name budget (${default_value}ms)" >&2
    exit 2
  fi
}

require_positive_integer_budget "SOLOPM_PERFORMANCE_MAX_COLD_LAUNCH_MS" "$MAX_COLD_LAUNCH_MS"
require_positive_integer_budget "SOLOPM_PERFORMANCE_MAX_DESTINATION_SWITCH_MS" "$MAX_DESTINATION_SWITCH_MS"
reject_relaxed_release_budget "cold launch" "$MAX_COLD_LAUNCH_MS" "$DEFAULT_COLD_LAUNCH_BUDGET_MS"
reject_relaxed_release_budget "destination switch" "$MAX_DESTINATION_SWITCH_MS" "$DEFAULT_DESTINATION_SWITCH_BUDGET_MS"

cd "$ROOT_DIR"
mkdir -p "$OUTPUT_DIR"
mkdir -p "$(dirname "$PERFORMANCE_DATABASE_PATH")"

# shellcheck source=/dev/null
source "$AX_HELPERS"

APP_PID=""
APP_LAUNCH_PID=""
APP_IDENTITY=""
APP_LAUNCH_IDENTITY=""

now_ms() {
  /usr/bin/perl -MTime::HiRes=time -e 'printf "%d\n", time() * 1000'
}

terminate_app() {
  local owned_pid="${APP_PID:-}"
  local launch_pid="${APP_LAUNCH_PID:-}"
  if [[ -n "$owned_pid" ]]; then
    ax_terminate_owned_process "$owned_pid" "$APP_BINARY" "${APP_IDENTITY:-}"
  fi
  if [[ -n "$launch_pid" && "$launch_pid" != "$owned_pid" ]]; then
    ax_terminate_owned_process "$launch_pid" "$APP_BINARY" "${APP_LAUNCH_IDENTITY:-}"
  fi
  APP_PID=""
  APP_LAUNCH_PID=""
  APP_IDENTITY=""
  APP_LAUNCH_IDENTITY=""
}

cleanup() {
  terminate_app
  rm -f "$AX_PRESS_ELEMENT_HELPER_EXECUTABLE" "$AX_MARKER_HELPER_EXECUTABLE"
}

prepare_ax_helpers() {
  # Compilation is harness setup, not product latency. Reuse these executables
  # so destination samples start with a ready AX selector and marker checker.
  /usr/bin/swiftc "$AX_PRESS_ELEMENT_HELPER" -o "$AX_PRESS_ELEMENT_HELPER_EXECUTABLE"
  /usr/bin/swiftc "$AX_MARKER_HELPER" -o "$AX_MARKER_HELPER_EXECUTABLE"
}

activate_app() {
  # Target the process we launched. Addressing the application by name can make
  # LaunchServices start or activate a different SoloPM instance and invalidate
  # both the isolated database and the performance sample.
  /usr/bin/osascript - "$APP_PID" "$APP_NAME" <<'APPLESCRIPT' >/dev/null 2>&1 &
on run argv
  set appPID to item 1 of argv as integer
  set appName to item 2 of argv
  tell application "System Events"
    set matchingProcesses to application processes whose unix id is appPID
    if (count of matchingProcesses) is 0 then return "missing"
    set targetProcess to item 1 of matchingProcesses
    tell targetProcess
      set frontmost to true
      if (count of windows) > 0 then
        try
          perform action "AXRaise" of window 1
        end try
      end if
    end tell
  end tell
  return "activated " & appName
end run
APPLESCRIPT
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
  # Direct launch retains the deterministic HOME/SQLite/selection contract;
  # unlike LaunchServices it cannot silently drop normal-route environment.
  /usr/bin/env -i PATH="$PATH" TMPDIR="$OUTPUT_DIR" HOME="$PERFORMANCE_HOME" CFFIXED_USER_HOME="$PERFORMANCE_HOME" \
    SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1 SOLOPM_DATABASE_PATH="$PERFORMANCE_DATABASE_PATH" \
    SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION="today" \
    "$APP_BINARY" -ApplePersistenceIgnoreState YES >/dev/null 2>&1 &
  APP_LAUNCH_PID=$!
  APP_LAUNCH_IDENTITY="$(ax_wait_for_owned_process_identity "$APP_LAUNCH_PID" "$APP_BINARY" 3)" || {
    ax_emit_failure_category "launch" "performance-launch-identity-unavailable"
    return 1
  }
  APP_PID="$(ax_wait_for_owned_app_pid "$APP_LAUNCH_PID" "$APP_BINARY" "$TIMEOUT_SECONDS")" || {
    ax_emit_failure_category "launch" "performance-owned-pid-unavailable"
    echo "BLOCKER: performance app did not launch from pid $APP_LAUNCH_PID" >&2
    return 1
  }
  APP_IDENTITY="$(ax_wait_for_owned_process_identity "$APP_PID" "$APP_BINARY" 3)" || {
    ax_emit_failure_category "launch" "performance-owned-identity-unavailable"
    return 1
  }
  ax_wait_for_pid_owned_process "$APP_NAME" "$APP_PID" "$TIMEOUT_SECONDS" "$APP_BINARY"
  activate_app
}

wait_for_visible_window() {
  if ! ax_wait_for_pid_owned_window "$APP_NAME" "$APP_PID" "" "$TIMEOUT_SECONDS" "" "$APP_BINARY"; then
    ax_emit_failure_category "window" "performance-window-unavailable"
    echo "BLOCKER: $APP_NAME did not publish a visible window for launched pid $APP_PID within ${TIMEOUT_SECONDS}s" >&2
    return 1
  fi
  return 0
}

wait_for_database_schema() {
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while true; do
    if [[ -f "$PERFORMANCE_DATABASE_PATH" ]] &&
      [[ "$(sqlite3 -batch -noheader "$PERFORMANCE_DATABASE_PATH" \
        "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name IN ('projects', 'tasks');" 2>/dev/null || true)" == "2" ]]; then
      return 0
    fi
    if ! ax_process_matches_identity "$APP_PID" "$APP_BINARY" "$APP_IDENTITY"; then
      ax_emit_failure_category "launch" "performance-bootstrap-exited"
      echo "BLOCKER: performance bootstrap app exited before its database schema was ready" >&2
      return 1
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      ax_emit_failure_category "launch" "performance-database-schema-unavailable"
      echo "BLOCKER: performance database schema was not ready within ${TIMEOUT_SECONDS}s" >&2
      return 1
    fi
    sleep 0.2
  done
}

seed_production_fixture() {
  # A fresh CI workspace otherwise opens the recovery route because it has no
  # projects. Seed one deterministic local project before starting the measured
  # launch so the sample can only pass through the production Project Board.
  if ! sqlite3 "$PERFORMANCE_DATABASE_PATH" <<'SQL'
.bail on
.timeout 5000
BEGIN IMMEDIATE;
DELETE FROM tasks WHERE source_command = 'ui-performance';
DELETE FROM projects WHERE source_command = 'ui-performance';
INSERT INTO projects (
  title, status, priority, deadline, workspace_path, tags_json, source_command,
  created_at, updated_at
) VALUES (
  'UI performance fixture', 'active', 'high', NULL, NULL, '[]', 'ui-performance',
  CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
);
INSERT INTO tasks (
  project_id, title, status, detail, due_at, completed_at, priority,
  source_command, created_at, updated_at
) VALUES (
  (SELECT id FROM projects WHERE source_command = 'ui-performance' ORDER BY id DESC LIMIT 1),
  'Measure production destinations', 'planned',
  'Deterministic local task for production-route launch performance.',
  NULL, NULL, 'high', 'ui-performance', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
);
COMMIT;
SQL
  then
    ax_emit_failure_category "harness" "performance-fixture-seed-failed"
    echo "BLOCKER: performance production fixture could not be seeded" >&2
    return 1
  fi
}

prepare_production_fixture() {
  rm -f "$PERFORMANCE_DATABASE_PATH" "$PERFORMANCE_DATABASE_PATH-wal" "$PERFORMANCE_DATABASE_PATH-shm"
  open_app
  wait_for_database_schema
  terminate_app
  seed_production_fixture
}

click_sidebar_destination() {
  local destination_identifier="$1"
  local destination_label="$2"
  if ! "$AX_PRESS_ELEMENT_HELPER_EXECUTABLE" "$APP_PID" "$destination_identifier"; then
    ax_emit_failure_category "product-marker" "performance-destination-unavailable"
    echo "BLOCKER: performance smoke could not select $destination_label in owned app pid $APP_PID" >&2
    return 1
  fi
}

wait_for_marker() {
  local identifier="$1"
  local safe_identifier="${identifier//[^[:alnum:]_-]/_}"
  local probe_file="$OUTPUT_DIR/wait-$safe_identifier.txt"
  if ax_wait_for_ax_identifier "$APP_NAME" "$identifier" "$TIMEOUT_SECONDS" "$ROOT_DIR" "$probe_file" "" "$APP_PID"; then
    return 0
  fi
  echo "BLOCKER: performance smoke could not inspect the AX marker: $identifier" >&2
  ax_emit_failure_category "product-marker" "performance-marker-unavailable"
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
    printf 'failure_category=performance-budget\n' >&2
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

trap cleanup EXIT

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
prepare_ax_helpers
SOLOPM_BUILD_CONFIGURATION="$BUILD_CONFIGURATION" ./script/build_and_run.sh --build-only
prepare_production_fixture

launch_start_ms="$(now_ms)"
open_app
wait_for_visible_window
wait_for_marker "project-board-header-bar"
wait_for_marker "today-workflow"
launch_end_ms="$(now_ms)"
record_sample "cold-launch-visible-window" "$launch_start_ms" "$launch_end_ms" "$MAX_COLD_LAUNCH_MS"

measure_destination "destination-inbox" "sidebar-destination-inbox" "Inbox" "inbox-workflow"
measure_destination "destination-assistant-queue" "sidebar-destination-assistant-queue" "Assistant Queue" "assistant-queue-workflow"
measure_destination "destination-today" "sidebar-destination-today" "Today" "today-workflow"

printf '\nStatus: passed\n' >>"$SUMMARY_FILE"
printf "OK: release launch performance smoke passed; artifacts written to %s\n" "$OUTPUT_DIR"
