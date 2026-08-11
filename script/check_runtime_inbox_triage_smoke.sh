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
TIMEOUT_SECONDS="${SUISUI_RUNTIME_INBOX_TRIAGE_TIMEOUT_SECONDS:-30}"
KEEP_DATABASE="${SUISUI_RUNTIME_INBOX_TRIAGE_KEEP_DATABASE:-0}"
SQLITE3="${SQLITE3:-sqlite3}"
AX_HELPERS="${AX_HELPERS:-$ROOT_DIR/script/ui_accessibility_smoke_helpers.sh}"
AX_TEXT_INPUT_HELPER="${AX_TEXT_INPUT_HELPER:-$ROOT_DIR/script/ui_evidence_ax_text_input.swift}"
WINDOW_WIDTH="${SUISUI_RUNTIME_INBOX_TRIAGE_WINDOW_WIDTH:-1400}"
WINDOW_HEIGHT="${SUISUI_RUNTIME_INBOX_TRIAGE_WINDOW_HEIGHT:-920}"

if [[ ! "$TIMEOUT_SECONDS" =~ ^[0-9]+$ || "$TIMEOUT_SECONDS" -lt 1 ]]; then
  echo "SUISUI_RUNTIME_INBOX_TRIAGE_TIMEOUT_SECONDS must be a positive integer" >&2
  exit 2
fi

if ! command -v "$SQLITE3" >/dev/null 2>&1; then
  echo "BLOCKER: sqlite3 is required for runtime inbox triage smoke" >&2
  exit 2
fi

cd "$ROOT_DIR"
mkdir -p "$ROOT_DIR/.tmp"
tmp_dir="$(mktemp -d "$ROOT_DIR/.tmp/suisui-runtime-inbox-triage.XXXXXX")"
database_path="$tmp_dir/Suisui-runtime-inbox-triage.sqlite"
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
    printf "INFO: kept runtime inbox triage database at %s\n" "$database_path"
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
  # Suisui process while resetting the isolated test database.
  [[ -z "${app_pid:-}" ]]
}

activate_app() {
  # Keep activation in System Events so the isolated DB/keychain environment
  # remains attached to the process started by this script.
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

set_inbox_window_size() {
  local width="$1"
  local height="$2"
  # The classification panel is below the task list; fixing the window size
  # keeps this runtime path testing product behavior instead of prior user
  # window state or a clipped footer.
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

launch_app_for_inbox() {
  terminate_app
  /usr/bin/env -i PATH="$PATH" TMPDIR="$tmp_dir" HOME="$runtime_home" CFFIXED_USER_HOME="$runtime_home" \
    SUISUI_DISABLE_KEYCHAIN_SECRET_STORE=1 SUISUI_DATABASE_PATH="$database_path" \
    SUISUI_PROJECT_BOARD_SELECTED_DESTINATION="inbox" \
    "$APP_BINARY" -ApplePersistenceIgnoreState YES &
  app_launch_pid=$!
  wait_for_app_process
  activate_app
  wait_for_visible_windows
  set_inbox_window_size "$WINDOW_WIDTH" "$WINDOW_HEIGHT"
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

setTextFieldContaining() {
  local fragment="$1"
  local replacement="$2"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while true; do
    if /usr/bin/swift "$AX_TEXT_INPUT_HELPER" "$app_pid" "$fragment" "$replacement"
    then
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: failed to set text field in AX tree: $fragment" >&2
      return 1
    fi
    sleep 1
  done
}

waitForTextFieldContaining() {
  local fragment="$1"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while true; do
    if /usr/bin/osascript - "$APP_NAME" "$fragment" <<'APPLESCRIPT' >/dev/null 2>&1
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
          if itemRole is "AXTextField" or itemRole is "AXTextArea" then
            set fieldIdentifier to ""
            set fieldName to ""
            set fieldTitle to ""
            set fieldDescription to ""
            set fieldHelp to ""
            set fieldValue to ""
            try
              set fieldIdentifier to value of attribute "AXIdentifier" of axItem as text
            end try
            try
              set fieldName to name of axItem as text
            end try
            try
              set fieldTitle to value of attribute "AXTitle" of axItem as text
            end try
            try
              set fieldDescription to description of axItem as text
            end try
            try
              set fieldHelp to value of attribute "AXHelp" of axItem as text
            end try
            try
              set fieldValue to value of axItem as text
            end try
            set signalText to fieldIdentifier & " " & fieldName & " " & fieldTitle & " " & fieldDescription & " " & fieldHelp & " " & fieldValue
            if signalText contains fragment then return "found text field " & fragment
          end if
        end repeat
      end repeat
    end tell
  end tell
  error "text field signal not found: " & fragment
end run
APPLESCRIPT
    then
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: text field did not appear in AX tree: $fragment" >&2
      return 1
    fi
    sleep 1
  done
}

create_inbox_item() {
  local title="$1"
  local task_id=""

  pressButtonContaining "inbox-quick-add-button" >&2
  waitForTextFieldContaining "inbox-quick-add-title"
  setTextFieldContaining "inbox-quick-add-title" "$title" >&2
  waitForTextFieldContaining "$title"
  pressButtonUntilSQLiteValue \
    "create inbox item: $title" \
    "inbox-quick-add-button" \
    "SELECT CASE WHEN count(*) = 1 THEN 1 ELSE 0 END FROM tasks t JOIN projects p ON p.id = t.project_id WHERE p.title='Inbox' AND t.title='$title' AND t.status='backlog' AND t.due_at IS NULL;" \
    "1" >&2
  task_id="$(wait_for_nonempty_value \
    "task id: $title" \
    "SELECT t.id FROM tasks t JOIN projects p ON p.id = t.project_id WHERE p.title='Inbox' AND t.title='$title' ORDER BY t.id DESC LIMIT 1;")"
  pressButtonContaining "workflow-task-row-$task_id" >&2
  printf "%s" "$task_id"
}

printf "== Runtime inbox triage smoke ==\n"
./script/build_and_run.sh --build-only

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "BLOCKER: app bundle not found after build: $APP_BUNDLE" >&2
  exit 2
fi

if [[ ! -x "$APP_BINARY" ]]; then
  echo "BLOCKER: app binary not found or not executable after build: $APP_BINARY" >&2
  exit 2
fi

launch_app_for_inbox
wait_for_database_table "projects"
wait_for_database_table "tasks"
inbox_project_id="$(wait_for_nonempty_value "Inbox project id" "SELECT id FROM projects WHERE title='Inbox' ORDER BY id DESC LIMIT 1;")"
verify_single_value "Inbox project exists" "SELECT CASE WHEN count(*) >= 1 THEN 1 ELSE 0 END FROM projects WHERE title='Inbox';" "1"

make_task_id="$(create_inbox_item "AX Runtime Inbox Make Task")"
pressButtonContaining "inbox-action-make-task"
verify_single_value "make-task persists Inbox disposition" "SELECT CASE WHEN t.status='backlog' AND t.due_at IS NULL AND t.project_id=$inbox_project_id AND r.disposition='task' AND r.review_at IS NULL THEN 1 ELSE 0 END FROM tasks t JOIN inbox_triage_records r ON r.task_id=t.id WHERE t.id=$make_task_id;" "1"

schedule_task_id="$(create_inbox_item "AX Runtime Inbox Schedule")"
pressButtonUntilSQLiteValue "schedule inbox item" "inbox-action-schedule-today" "SELECT CASE WHEN t.status='planned' AND t.due_at IS NOT NULL AND t.project_id=$inbox_project_id AND r.disposition='scheduled' AND r.review_at IS NULL THEN 1 ELSE 0 END FROM tasks t JOIN inbox_triage_records r ON r.task_id=t.id WHERE t.id=$schedule_task_id;" "1"
pressButtonUntilSQLiteValue "undo inbox schedule" "inbox-classification-undo" "SELECT CASE WHEN t.status='backlog' AND t.due_at IS NULL AND t.project_id=$inbox_project_id AND r.disposition='unprocessed' AND r.review_at IS NULL THEN 1 ELSE 0 END FROM tasks t JOIN inbox_triage_records r ON r.task_id=t.id WHERE t.id=$schedule_task_id;" "1"

review_task_id="$(create_inbox_item "AX Runtime Inbox Review Later")"
# Review Later must preserve any existing due date while writing its own
# deferred review timestamp. Seed scheduling state directly so the AX path
# covers the Review Later button rather than a preceding feedback banner.
terminate_app
wait_for_no_app_process
"$SQLITE3" "$database_path" "UPDATE tasks SET status='planned', due_at='2026-06-23T09:00:00Z', updated_at=CURRENT_TIMESTAMP WHERE id=$review_task_id;"
launch_app_for_inbox
pressButtonContaining "workflow-task-row-$review_task_id"
verify_single_value "prepared review-later inbox item" "SELECT CASE WHEN status='planned' AND due_at IS NOT NULL AND project_id=$inbox_project_id THEN 1 ELSE 0 END FROM tasks WHERE id=$review_task_id;" "1"
pressButtonUntilSQLiteValue "review later inbox item" "inbox-action-review-later" "SELECT CASE WHEN t.status='planned' AND t.due_at='2026-06-23T09:00:00Z' AND r.disposition='review_later' AND r.review_at IS NOT NULL THEN 1 ELSE 0 END FROM tasks t JOIN inbox_triage_records r ON r.task_id=t.id WHERE t.id=$review_task_id;" "1"
pressButtonUntilSQLiteValue "undo inbox review later" "inbox-classification-undo" "SELECT CASE WHEN t.status='planned' AND t.due_at='2026-06-23T09:00:00Z' AND r.disposition='unprocessed' AND r.review_at IS NULL THEN 1 ELSE 0 END FROM tasks t JOIN inbox_triage_records r ON r.task_id=t.id WHERE t.id=$review_task_id;" "1"

project_task_id="$(create_inbox_item "AX Runtime Inbox Project Conversion")"
pressButtonUntilSQLiteValue "convert inbox item to project" "inbox-action-make-project" "SELECT CASE WHEN count(*) = 1 THEN 1 ELSE 0 END FROM projects WHERE title='AX Runtime Inbox Project Conversion';" "1"
verify_single_value "converted inbox item moved into project" "SELECT CASE WHEN t.status='planned' AND p.title='AX Runtime Inbox Project Conversion' AND r.disposition='project' THEN 1 ELSE 0 END FROM tasks t JOIN projects p ON p.id = t.project_id JOIN inbox_triage_records r ON r.task_id=t.id WHERE t.id=$project_task_id;" "1"
pressButtonUntilSQLiteValue "undo inbox project conversion" "inbox-classification-undo" "SELECT count(*) FROM projects WHERE title='AX Runtime Inbox Project Conversion';" "0"
verify_single_value "restored inbox project conversion item" "SELECT CASE WHEN count(*) = 1 THEN 1 ELSE 0 END FROM tasks t JOIN projects p ON p.id = t.project_id JOIN inbox_triage_records r ON r.task_id=t.id WHERE p.title='Inbox' AND t.title='AX Runtime Inbox Project Conversion' AND t.status='backlog' AND t.due_at IS NULL AND r.disposition='unprocessed' AND r.review_at IS NULL;" "1"

printf "OK: runtime inbox triage smoke covered quick add, make-task, schedule, review-later, project conversion, and undo through the visible app\n"
