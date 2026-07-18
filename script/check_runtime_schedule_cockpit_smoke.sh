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
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
TIMEOUT_SECONDS="${SOLOPM_RUNTIME_SCHEDULE_COCKPIT_TIMEOUT_SECONDS:-30}"
KEEP_DATABASE="${SOLOPM_RUNTIME_SCHEDULE_COCKPIT_KEEP_DATABASE:-0}"
SQLITE3="${SQLITE3:-sqlite3}"
WINDOW_WIDTH="${SOLOPM_RUNTIME_SCHEDULE_COCKPIT_WINDOW_WIDTH:-1500}"
WINDOW_HEIGHT="${SOLOPM_RUNTIME_SCHEDULE_COCKPIT_WINDOW_HEIGHT:-940}"
AX_MAX_NODES="${SOLOPM_RUNTIME_SCHEDULE_COCKPIT_AX_MAX_NODES:-9000}"

if [[ ! "$TIMEOUT_SECONDS" =~ ^[0-9]+$ || "$TIMEOUT_SECONDS" -lt 1 ]]; then
  echo "SOLOPM_RUNTIME_SCHEDULE_COCKPIT_TIMEOUT_SECONDS must be a positive integer" >&2
  exit 2
fi

if ! command -v "$SQLITE3" >/dev/null 2>&1; then
  echo "BLOCKER: sqlite3 is required for runtime schedule cockpit smoke" >&2
  exit 2
fi

cd "$ROOT_DIR"
mkdir -p "$ROOT_DIR/.tmp"
tmp_dir="$(mktemp -d "$ROOT_DIR/.tmp/solopm-runtime-schedule-cockpit.XXXXXX")"
database_path="$tmp_dir/SoloPM-runtime-schedule-cockpit.sqlite"
runtime_day_key=""
app_pid=""

terminate_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  if [[ -n "${app_pid:-}" ]]; then
    wait "$app_pid" >/dev/null 2>&1 || true
    app_pid=""
  fi
}

cleanup() {
  terminate_app
  if [[ "$KEEP_DATABASE" != "1" ]]; then
    rm -rf "$tmp_dir"
  else
    printf "INFO: kept runtime schedule cockpit database at %s\n" "$database_path"
  fi
}
trap cleanup EXIT

wait_for_app_process() {
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while ! pgrep -x "$APP_NAME" >/dev/null 2>&1; do
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: $APP_NAME process did not appear within ${TIMEOUT_SECONDS}s" >&2
      return 1
    fi
    sleep 1
  done
}

wait_for_no_app_process() {
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while pgrep -x "$APP_NAME" >/dev/null 2>&1; do
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      pkill -x "$APP_NAME" >/dev/null 2>&1 || true
      return 0
    fi
    sleep 1
  done
}

activate_app() {
  # Keep activation inside System Events so LaunchServices does not start a
  # second app instance without the isolated SQLite/keychain test environment.
  /usr/bin/osascript - "$APP_NAME" <<'APPLESCRIPT' >/dev/null 2>&1 &
on run argv
  set appName to item 1 of argv
  tell application "System Events"
    if not (exists process appName) then return "missing"
    tell process appName
      set frontmost to true
      if (count of windows) > 0 then
        try
          perform action "AXRaise" of window 1
        end try
      end if
    end tell
  end tell
  return "activated"
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

wait_for_visible_windows() {
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local window_count=""
  local osascript_status=1

  while true; do
    set +e
    window_count="$(/usr/bin/osascript - "$APP_NAME" <<'APPLESCRIPT' 2>/dev/null
on run argv
  set appName to item 1 of argv
  tell application "System Events"
    if not (exists process appName) then return "0"
    tell process appName
      return (count of windows) as text
    end tell
  end tell
end run
APPLESCRIPT
)"
    osascript_status=$?
    set -e

    if [[ "$osascript_status" -eq 0 && "${window_count:-0}" =~ ^[0-9]+$ && "$window_count" -ge 1 ]]; then
      return 0
    fi

    activate_app
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: $APP_NAME did not expose a visible AX window within ${TIMEOUT_SECONDS}s" >&2
      return 1
    fi
    sleep 1
  done
}

set_schedule_window_size() {
  local width="$1"
  local height="$2"
  /usr/bin/osascript - "$APP_NAME" "$width" "$height" <<'APPLESCRIPT' >/dev/null
on run argv
  set appName to item 1 of argv
  set targetWidth to (item 2 of argv) as integer
  set targetHeight to (item 3 of argv) as integer
  tell application "System Events"
    if not (exists process appName) then error "process missing"
    tell process appName
      if not (exists window 1) then error "window missing"
      set frontmost to true
      try
        perform action "AXRaise" of window 1
      end try
      set size of window 1 to {targetWidth, targetHeight}
    end tell
  end tell
end run
APPLESCRIPT
  sleep 1
}

launch_app_for_database_migration() {
  terminate_app
  SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1 \
    SOLOPM_DATABASE_PATH="$database_path" \
    "$APP_BINARY" &
  app_pid=$!
  wait_for_app_process
  activate_app
  wait_for_visible_windows
}

launch_app_for_schedule() {
  terminate_app
  SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1 \
    SOLOPM_DATABASE_PATH="$database_path" \
    SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION="schedule" \
    "$APP_BINARY" &
  app_pid=$!
  wait_for_app_process
  activate_app
  wait_for_visible_windows
  set_schedule_window_size "$WINDOW_WIDTH" "$WINDOW_HEIGHT"
}

wait_for_database_table() {
  local table="$1"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while true; do
    if [[ -f "$database_path" ]] && "$SQLITE3" "$database_path" "SELECT name FROM sqlite_master WHERE type='table' AND name='$table';" | grep -Fx "$table" >/dev/null; then
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: SQLite table '$table' was not created in runtime database: $database_path" >&2
      return 1
    fi
    sleep 1
  done
}

query_single_value() {
  local sql="$1"
  "$SQLITE3" -batch -noheader "$database_path" "$sql" | tail -n 1
}

wait_for_nonempty_value() {
  local label="$1"
  local sql="$2"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local actual=""
  while true; do
    actual="$(query_single_value "$sql" || true)"
    if [[ -n "$actual" ]]; then
      printf "%s" "$actual"
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: $label did not produce a SQLite value" >&2
      return 1
    fi
    sleep 1
  done
}

verify_single_value() {
  local label="$1"
  local sql="$2"
  local expected="$3"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local actual=""
  while true; do
    actual="$(query_single_value "$sql" || true)"
    if [[ "$actual" == "$expected" ]]; then
      printf "OK: %s verified in SQLite (%s)\n" "$label" "$actual"
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: $label SQLite verification failed: expected '$expected', got '${actual:-<empty>}'" >&2
      echo "SQL: $sql" >&2
      return 1
    fi
    sleep 1
  done
}

pressButtonUntilSQLiteValue() {
  local label="$1"
  local fragment="$2"
  local sql="$3"
  local expected="$4"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local actual=""

  while true; do
    pressButtonContaining "$fragment"

    local postcondition_deadline=$((SECONDS + 3))
    while true; do
      actual="$(query_single_value "$sql" || true)"
      if [[ "$actual" == "$expected" ]]; then
        printf "OK: %s verified in SQLite (%s)\n" "$label" "$actual"
        return 0
      fi
      if [[ "$SECONDS" -ge "$deadline" ]]; then
        echo "BLOCKER: $label SQLite verification failed after AX press retry: expected '$expected', got '${actual:-<empty>}'" >&2
        echo "SQL: $sql" >&2
        return 1
      fi
      if [[ "$SECONDS" -ge "$postcondition_deadline" ]]; then
        break
      fi
      sleep 1
    done

    printf "INFO: SQLite postcondition for $label was not met after pressing '$fragment'; retrying AX press.\n" >&2
    activate_app
    wait_for_visible_windows >/dev/null 2>&1 || true
    sleep 1
  done
}

waitForAXElementContaining() {
  local identifier_fragment="$1"
  local required_text_one="${2:-}"
  local required_text_two="${3:-}"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local text_marker="${required_text_one:-$identifier_fragment}"
  while true; do
    if axMarkerPresent "$identifier_fragment" "$text_marker"; then
      if [[ -z "$required_text_two" ]] || axMarkerPresent "$identifier_fragment" "$required_text_two"; then
        return 0
      fi
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: AX element did not expose required signal: $identifier_fragment" >&2
      return 1
    fi
    activate_app
    wait_for_visible_windows >/dev/null 2>&1 || true
    sleep 1
  done
}

axMarkerPresent() {
  local identifier="$1"
  local text="$2"
  local error_file
  local checker_pid
  local watchdog_pid
  local status
  error_file="$(mktemp "${TMPDIR:-/tmp}/solopm-schedule-ax-marker-error.XXXXXX")"

  # Schedule is rendered inside the full Project Board. Bound the Swift AX
  # traversal so a large SwiftUI tree cannot stall the smoke indefinitely.
  SOLOPM_UI_EVIDENCE_AX_REQUIRE_IDENTIFIER_SUBTREE=1 \
  SOLOPM_UI_EVIDENCE_AX_MAX_NODES="$AX_MAX_NODES" \
    /usr/bin/swift "$ROOT_DIR/script/ui_evidence_ax_marker_check.swift" "$APP_NAME" "$identifier" "$text" \
    >/dev/null 2>"$error_file" &
  checker_pid=$!
  (
    sleep "$TIMEOUT_SECONDS"
    kill "$checker_pid" >/dev/null 2>&1 || true
  ) &
  watchdog_pid=$!
  set +e
  wait "$checker_pid"
  status=$?
  set -e
  kill "$watchdog_pid" >/dev/null 2>&1 || true
  wait "$watchdog_pid" >/dev/null 2>&1 || true
  if [[ "$status" -ne 0 ]]; then
    cat "$error_file" >&2
  fi
  rm -f "$error_file"
  return "$status"
}

pressButtonContaining() {
  local fragment="$1"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local error_file
  local checker_pid
  local watchdog_pid
  local status
  while true; do
    error_file="$(mktemp "${TMPDIR:-/tmp}/solopm-schedule-ax-button-error.XXXXXX")"
    SOLOPM_UI_EVIDENCE_AX_MAX_NODES="$AX_MAX_NODES" \
      /usr/bin/swift "$ROOT_DIR/script/ui_evidence_ax_press_button.swift" "$APP_NAME" "$fragment" \
      >/dev/null 2>"$error_file" &
    checker_pid=$!
    (
      sleep "$TIMEOUT_SECONDS"
      kill "$checker_pid" >/dev/null 2>&1 || true
    ) &
    watchdog_pid=$!
    set +e
    wait "$checker_pid"
    status=$?
    set -e
    kill "$watchdog_pid" >/dev/null 2>&1 || true
    wait "$watchdog_pid" >/dev/null 2>&1 || true
    if [[ "$status" -eq 0 ]]; then
      rm -f "$error_file"
      return 0
    fi
    cat "$error_file" >&2
    rm -f "$error_file"
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: failed to press button in AX tree: $fragment" >&2
      return 1
    fi
    activate_app
    wait_for_visible_windows >/dev/null 2>&1 || true
    sleep 1
  done
}

seed_schedule_tasks() {
  "$SQLITE3" "$database_path" <<SQL
INSERT INTO projects (title, status, priority, deadline, workspace_path, tags_json, source_command, created_at, updated_at)
VALUES ('AX Runtime Schedule Project', 'active', 'high', NULL, NULL, '[]', 'runtime-schedule-cockpit-smoke', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
INSERT INTO tasks (project_id, title, status, detail, due_at, completed_at, priority, source_command, created_at, updated_at)
VALUES (last_insert_rowid(), 'AX Runtime Schedule Due', 'planned', 'Show this due task in the weekly Schedule cockpit.', '$runtime_day_key', NULL, 'high', 'runtime-schedule-cockpit-smoke', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
INSERT INTO tasks (project_id, title, status, detail, due_at, completed_at, priority, source_command, created_at, updated_at)
VALUES (
  (SELECT id FROM projects WHERE title='AX Runtime Schedule Project' AND source_command='runtime-schedule-cockpit-smoke' ORDER BY id DESC LIMIT 1),
  'AX Runtime Schedule Unscheduled',
  'planned',
  'Add this unscheduled task to the local schedule draft without mutating due_at.',
  NULL,
  NULL,
  'medium',
  'runtime-schedule-cockpit-smoke',
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
);
SQL
}

printf "== Runtime schedule cockpit smoke ==\n"
./script/build_and_run.sh --build-only

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "BLOCKER: app bundle not found after build: $APP_BUNDLE" >&2
  exit 2
fi

if [[ ! -x "$APP_BINARY" ]]; then
  echo "BLOCKER: app binary not found or not executable after build: $APP_BINARY" >&2
  exit 2
fi

launch_app_for_database_migration
wait_for_database_table "projects"
wait_for_database_table "tasks"
wait_for_database_table "assistant_queue_items"
terminate_app
wait_for_no_app_process

runtime_day_key="$(/bin/date +%Y-%m-%d)"
seed_schedule_tasks
due_task_id="$(wait_for_nonempty_value "schedule due task id" "SELECT id FROM tasks WHERE title='AX Runtime Schedule Due' AND source_command='runtime-schedule-cockpit-smoke' ORDER BY id DESC LIMIT 1;")"
unscheduled_task_id="$(wait_for_nonempty_value "schedule unscheduled task id" "SELECT id FROM tasks WHERE title='AX Runtime Schedule Unscheduled' AND source_command='runtime-schedule-cockpit-smoke' ORDER BY id DESC LIMIT 1;")"

launch_app_for_schedule
wait_for_database_table "assistant_queue_items"
verify_single_value "seeded due schedule task is open" "SELECT CASE WHEN status='planned' AND due_at='$runtime_day_key' THEN 1 ELSE 0 END FROM tasks WHERE id=$due_task_id;" "1"
verify_single_value "seeded unscheduled task stays unscheduled" "SELECT CASE WHEN status='planned' AND due_at IS NULL THEN 1 ELSE 0 END FROM tasks WHERE id=$unscheduled_task_id;" "1"
waitForAXElementContaining "schedule-workflow"
waitForAXElementContaining "schedule-mode-overview"
waitForAXElementContaining "schedule-mini-calendar"
waitForAXElementContaining "schedule-status-banner"
waitForAXElementContaining "schedule-unscheduled-task-$unscheduled_task_id" "AX Runtime Schedule Unscheduled"
pressButtonContaining "schedule-unscheduled-add-draft-$unscheduled_task_id"
waitForAXElementContaining "schedule-feedback" "AX Runtime Schedule Unscheduled"
pressButtonContaining "schedule-mode-option-timeline"
waitForAXElementContaining "schedule-week-grid"
waitForAXElementContaining "schedule-week-block-$runtime_day_key-due-$due_task_id-all-day" "AX Runtime Schedule Due"
waitForAXElementContaining "schedule-week-block-$runtime_day_key-draft-$unscheduled_task_id" "AX Runtime Schedule Unscheduled" "Schedule draft"
verify_single_value "add-to-draft kept unscheduled task due date empty" "SELECT CASE WHEN status='planned' AND due_at IS NULL THEN 1 ELSE 0 END FROM tasks WHERE id=$unscheduled_task_id;" "1"

pressButtonUntilSQLiteValue \
  "queue Schedule draft Calendar apply" \
  "schedule-apply-calendar" \
  "SELECT CASE WHEN count(*) = 1 THEN 1 ELSE 0 END FROM assistant_queue_items WHERE id LIKE 'action-plan:schedule-draft-calendar-apply:%:task:%$unscheduled_task_id%' AND payload_kind='action_plan' AND state='waitingReview' AND risk_level='write' AND approval_json IS NULL AND (required_capabilities_json LIKE '%calendarCreateWorkBlock%' OR required_capabilities_json LIKE '%calendar.create_work_block%') AND required_capabilities_json LIKE '%providerExecutionApproval%' AND required_capabilities_json LIKE '%appPermission%' AND required_capabilities_json LIKE '%calendar%' AND payload_json LIKE '%\"requiresApproval\":true%';" \
  "1"
verify_single_value "Calendar queue kept due task local" "SELECT CASE WHEN status='planned' AND due_at='$runtime_day_key' THEN 1 ELSE 0 END FROM tasks WHERE id=$due_task_id;" "1"
verify_single_value "Calendar queue kept unscheduled task local" "SELECT CASE WHEN status='planned' AND due_at IS NULL THEN 1 ELSE 0 END FROM tasks WHERE id=$unscheduled_task_id;" "1"

printf "OK: runtime schedule cockpit smoke covered overview-to-timeline navigation, unscheduled add-to-draft, and approval-gated Calendar apply\n"
