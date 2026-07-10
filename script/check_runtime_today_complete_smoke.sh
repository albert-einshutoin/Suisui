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
TIMEOUT_SECONDS="${SOLOPM_RUNTIME_TODAY_COMPLETE_TIMEOUT_SECONDS:-30}"
KEEP_DATABASE="${SOLOPM_RUNTIME_TODAY_COMPLETE_KEEP_DATABASE:-0}"
SQLITE3="${SQLITE3:-sqlite3}"
AX_HELPERS="${AX_HELPERS:-$ROOT_DIR/script/ui_accessibility_smoke_helpers.sh}"
WINDOW_WIDTH="${SOLOPM_RUNTIME_TODAY_COMPLETE_WINDOW_WIDTH:-1300}"
WINDOW_HEIGHT="${SOLOPM_RUNTIME_TODAY_COMPLETE_WINDOW_HEIGHT:-860}"
AX_MAX_NODES="${SOLOPM_RUNTIME_TODAY_COMPLETE_AX_MAX_NODES:-9000}"

if [[ ! "$TIMEOUT_SECONDS" =~ ^[0-9]+$ || "$TIMEOUT_SECONDS" -lt 1 ]]; then
  echo "SOLOPM_RUNTIME_TODAY_COMPLETE_TIMEOUT_SECONDS must be a positive integer" >&2
  exit 2
fi

if ! command -v "$SQLITE3" >/dev/null 2>&1; then
  echo "BLOCKER: sqlite3 is required for runtime today complete smoke" >&2
  exit 2
fi

cd "$ROOT_DIR"
mkdir -p "$ROOT_DIR/.tmp"
tmp_dir="$(mktemp -d "$ROOT_DIR/.tmp/solopm-runtime-today-complete.XXXXXX")"
database_path="$tmp_dir/SoloPM-runtime-today-complete.sqlite"
runtime_home="$tmp_dir/home"
mkdir -p "$runtime_home"
app_pid=""
app_launch_pid=""

# shellcheck source=/dev/null
source "$AX_HELPERS"

terminate_app() {
  if [[ -n "${app_pid:-}" ]]; then
    kill "$app_pid" >/dev/null 2>&1 || true
    wait "$app_pid" >/dev/null 2>&1 || true
    app_pid=""
  fi
  app_launch_pid=""
}

cleanup() {
  terminate_app
  if [[ "$KEEP_DATABASE" != "1" ]]; then
    rm -rf "$tmp_dir"
  else
    printf "INFO: kept runtime today complete database at %s\n" "$database_path"
  fi
}
trap cleanup EXIT

wait_for_app_process() {
  app_pid="$(ax_wait_for_owned_app_pid "$app_launch_pid" "$APP_BINARY" "$TIMEOUT_SECONDS")" || {
    echo "BLOCKER: $APP_NAME did not launch from pid $app_launch_pid" >&2
    return 1
  }
  ax_wait_for_pid_owned_process "$APP_NAME" "$app_pid" "$TIMEOUT_SECONDS" "$APP_BINARY"
}

wait_for_no_app_process() {
  # The smoke owns only app_pid. Do not inspect or terminate another user's
  # SoloPM process while resetting the isolated test database.
  [[ -z "${app_pid:-}" ]]
}

activate_app() {
  # Use System Events activation to preserve the exact isolated environment
  # passed to the binary instead of asking LaunchServices to open a second app.
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
  ax_wait_for_pid_owned_window "$APP_NAME" "$app_pid" "" "$TIMEOUT_SECONDS" "" "$APP_BINARY" || {
    echo "BLOCKER: $APP_NAME did not expose a window for launched pid $app_pid" >&2
    return 1
  }
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

set_today_window_size() {
  local width="$1"
  local height="$2"
  # Fix the window so the completion control remains visible regardless of
  # previously saved user window state.
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

launch_app_for_today() {
  terminate_app
  /usr/bin/env -i PATH="$PATH" TMPDIR="$tmp_dir" HOME="$runtime_home" CFFIXED_USER_HOME="$runtime_home" \
    SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1 SOLOPM_DATABASE_PATH="$database_path" \
    SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION="today" \
    SOLOPM_PROJECT_BOARD_SELECTED_TASK_ID="$today_task_id" \
    "$APP_BINARY" -ApplePersistenceIgnoreState YES &
  app_launch_pid=$!
  wait_for_app_process
  activate_app
  wait_for_visible_windows
  set_today_window_size "$WINDOW_WIDTH" "$WINDOW_HEIGHT"
}

launch_app_for_database_migration() {
  terminate_app
  /usr/bin/env -i PATH="$PATH" TMPDIR="$tmp_dir" HOME="$runtime_home" CFFIXED_USER_HOME="$runtime_home" \
    SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1 SOLOPM_DATABASE_PATH="$database_path" \
    SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION="today" \
    "$APP_BINARY" -ApplePersistenceIgnoreState YES &
  app_launch_pid=$!
  wait_for_app_process
  activate_app
  wait_for_visible_windows
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
    sleep 1
  done
}

waitForAXElementContaining() {
  local identifier_fragment="$1"
  local required_text_one="${2:-}"
  local required_text_two="${3:-}"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while true; do
    if /usr/bin/osascript - "$APP_NAME" "$identifier_fragment" "$required_text_one" "$required_text_two" <<'APPLESCRIPT' >/dev/null 2>&1
on run argv
  set appName to item 1 of argv
  set identifierFragment to item 2 of argv
  set requiredTextOne to item 3 of argv
  set requiredTextTwo to item 4 of argv
  tell application "System Events"
    if not (exists process appName) then error appName & " process is not visible to System Events"
    tell process appName
      set windowCount to count of windows
      if windowCount < 1 then error appName & " has no visible windows"
      try
        set frontmost to true
      end try
      repeat with windowIndex from 1 to windowCount
        set currentWindow to window windowIndex
        try
          perform action "AXRaise" of currentWindow
        end try
        set axItems to entire contents of currentWindow
        repeat with axItem in axItems
          set itemIdentifier to ""
          set itemName to ""
          set itemTitle to ""
          set itemValue to ""
          set itemDescription to ""
          set itemHelp to ""
          try
            set itemIdentifier to value of attribute "AXIdentifier" of axItem as text
          end try
          try
            set itemName to name of axItem as text
          end try
          try
            set itemTitle to value of attribute "AXTitle" of axItem as text
          end try
          try
            set itemValue to value of axItem as text
          end try
          try
            set itemValue to itemValue & " " & (value of attribute "AXValue" of axItem as text)
          end try
          try
            set itemDescription to description of axItem as text
          end try
          try
            set itemHelp to value of attribute "AXHelp" of axItem as text
          end try
          set signalText to itemIdentifier & " " & itemName & " " & itemTitle & " " & itemValue & " " & itemDescription & " " & itemHelp
          set requiredOneMatches to requiredTextOne is "" or signalText contains requiredTextOne
          set requiredTwoMatches to requiredTextTwo is "" or signalText contains requiredTextTwo
          if signalText contains identifierFragment and requiredOneMatches and requiredTwoMatches then
            return "found AX element " & identifierFragment
          end if
        end repeat
      end repeat
    end tell
  end tell
  error "AX element signal not found: " & identifierFragment
end run
APPLESCRIPT
    then
      return 0
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

waitForAXSubtreeMarkerContaining() {
  local identifier_fragment="$1"
  local required_text="$2"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local error_file
  local checker_pid
  local watchdog_pid
  local status

  while true; do
    error_file="$(mktemp "${TMPDIR:-/tmp}/solopm-today-ax-marker-error.XXXXXX")"
    SOLOPM_UI_EVIDENCE_AX_REQUIRE_IDENTIFIER_SUBTREE=1 \
      SOLOPM_UI_EVIDENCE_AX_MAX_NODES="$AX_MAX_NODES" \
      /usr/bin/swift "$ROOT_DIR/script/ui_evidence_ax_marker_check.swift" "$APP_NAME" "$identifier_fragment" "$required_text" \
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
      echo "BLOCKER: AX subtree marker did not expose required signal: $identifier_fragment => $required_text" >&2
      return 1
    fi
    activate_app
    wait_for_visible_windows >/dev/null 2>&1 || true
    sleep 1
  done
}

pressButtonContainingBounded() {
  local fragment="$1"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local error_file
  local checker_pid
  local watchdog_pid
  local status

  while true; do
    error_file="$(mktemp "${TMPDIR:-/tmp}/solopm-today-ax-button-error.XXXXXX")"
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
      echo "BLOCKER: failed to press bounded AX button: $fragment" >&2
      return 1
    fi
    activate_app
    wait_for_visible_windows >/dev/null 2>&1 || true
    sleep 1
  done
}

pressButtonContaining() {
  local fragment="$1"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while true; do
    if /usr/bin/osascript - "$APP_NAME" "$fragment" <<'APPLESCRIPT'
on run argv
  set appName to item 1 of argv
  set fragment to item 2 of argv
  tell application "System Events"
    if not (exists process appName) then error appName & " process is not visible to System Events"
    tell process appName
      set windowCount to count of windows
      if windowCount < 1 then error appName & " has no visible windows"
      try
        set frontmost to true
      end try
      repeat with windowIndex from 1 to windowCount
        set currentWindow to window windowIndex
        try
          perform action "AXRaise" of currentWindow
        end try
        set axItems to entire contents of currentWindow
        repeat with axItem in axItems
          set itemRole to ""
          try
            set itemRole to role of axItem as text
          end try
          if itemRole is "AXButton" then
            set buttonName to ""
            set buttonTitle to ""
            set buttonDescription to ""
            set buttonHelp to ""
            set buttonIdentifier to ""
            try
              set buttonName to name of axItem as text
            end try
            try
              set buttonTitle to value of attribute "AXTitle" of axItem as text
            end try
            try
              set buttonDescription to description of axItem as text
            end try
            try
              set buttonHelp to value of attribute "AXHelp" of axItem as text
            end try
            try
              set buttonIdentifier to value of attribute "AXIdentifier" of axItem as text
            end try
            set signalText to buttonIdentifier & " " & buttonName & " " & buttonTitle & " " & buttonDescription & " " & buttonHelp
            set isEnabled to true
            try
              set isEnabled to enabled of axItem as boolean
            end try
            if isEnabled and signalText contains fragment then
              try
                perform action "AXPress" of axItem
                return "pressed " & fragment
              end try
            end if
          end if
        end repeat
      end repeat
    end tell
  end tell
  error "button signal not found: " & fragment
end run
APPLESCRIPT
    then
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: failed to press button in AX tree: $fragment" >&2
      return 1
    fi
    sleep 1
  done
}

seed_today_task() {
  "$SQLITE3" "$database_path" <<'SQL'
INSERT INTO projects (title, status, priority, deadline, workspace_path, tags_json, source_command, created_at, updated_at)
VALUES ('AX Runtime Today Project', 'active', 'high', NULL, NULL, '[]', 'runtime-today-complete-smoke', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
INSERT INTO tasks (project_id, title, status, detail, due_at, completed_at, priority, source_command, created_at, updated_at)
VALUES (last_insert_rowid(), 'AX Runtime Today Complete', 'planned', 'Complete this visible Today row through runtime AX smoke', '2026-01-01T09:00:00Z', NULL, 'high', 'runtime-today-complete-smoke', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
SQL
  wait_for_nonempty_value \
    "today task id" \
    "SELECT id FROM tasks WHERE title='AX Runtime Today Complete' AND source_command='runtime-today-complete-smoke' ORDER BY id DESC LIMIT 1;"
}

printf "== Runtime today complete smoke ==\n"
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
terminate_app
wait_for_no_app_process

today_task_id="$(seed_today_task)"
launch_app_for_today
wait_for_database_table "assistant_queue_items"
waitForAXElementContaining "today-command-capture-field"
pressButtonContainingBounded "today-rail-edit-task"
waitForAXSubtreeMarkerContaining "task-inspector-title" "AX Runtime Today Complete"
verify_single_value "edit inspector kept Today task open" "SELECT CASE WHEN status='planned' AND completed_at IS NULL THEN 1 ELSE 0 END FROM tasks WHERE id=$today_task_id;" "1"
terminate_app
wait_for_no_app_process
launch_app_for_today
wait_for_database_table "assistant_queue_items"
waitForAXElementContaining "today-command-capture-field"
# Keep the edit and subtask checks in separate launches. The subtask action
# intentionally moves focus into the command field, and isolating the checks
# keeps this runtime smoke about product behavior rather than AX focus residue.
pressButtonContainingBounded "today-rail-add-subtask"
waitForAXElementContaining "today-command-capture-field" "AX Runtime Today Complete"
verify_single_value "subtask prefill kept Today task open" "SELECT CASE WHEN status='planned' AND completed_at IS NULL THEN 1 ELSE 0 END FROM tasks WHERE id=$today_task_id;" "1"
terminate_app
wait_for_no_app_process
launch_app_for_today
wait_for_database_table "assistant_queue_items"
verify_single_value "seeded today task is open" "SELECT CASE WHEN status='planned' AND completed_at IS NULL AND due_at='2026-01-01T09:00:00Z' THEN 1 ELSE 0 END FROM tasks WHERE id=$today_task_id;" "1"
pressButtonContaining "workflow-task-row-$today_task_id"
pressButtonContaining "today-rail-focus"
verify_single_value "focus kept Today task open" "SELECT CASE WHEN status='planned' AND completed_at IS NULL THEN 1 ELSE 0 END FROM tasks WHERE id=$today_task_id;" "1"
pressButtonContaining "today-rail-schedule-block"
waitForAXElementContaining "today-rail-schedule-draft-status"
verify_single_value "schedule draft kept Today task open" "SELECT CASE WHEN status='planned' AND completed_at IS NULL THEN 1 ELSE 0 END FROM tasks WHERE id=$today_task_id;" "1"
pressButtonUntilSQLiteValue "queue Today rail reminder draft" "today-rail-reminder-draft" "SELECT CASE WHEN count(*) = 1 THEN 1 ELSE 0 END FROM assistant_queue_items WHERE id LIKE 'action-plan:today-reminder:%:task:$today_task_id' AND state='waitingReview' AND approval_json IS NULL;" "1"
verify_single_value "rail actions kept Today task open" "SELECT CASE WHEN status='planned' AND completed_at IS NULL THEN 1 ELSE 0 END FROM tasks WHERE id=$today_task_id;" "1"
pressButtonUntilSQLiteValue "complete today task" "workflow-task-completion-$today_task_id" "SELECT CASE WHEN status='completed' AND completed_at IS NOT NULL THEN 1 ELSE 0 END FROM tasks WHERE id=$today_task_id;" "1"

printf "OK: runtime today complete smoke covered Today rail focus, schedule draft, edit inspector, subtask prefill, reminder draft, and visible row completion\n"
