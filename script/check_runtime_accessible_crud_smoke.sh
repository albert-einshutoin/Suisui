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
TIMEOUT_SECONDS="${SOLOPM_RUNTIME_ACCESSIBLE_CRUD_TIMEOUT_SECONDS:-30}"
KEEP_DATABASE="${SOLOPM_RUNTIME_ACCESSIBLE_CRUD_KEEP_DATABASE:-0}"
SQLITE3="${SQLITE3:-sqlite3}"

if [[ ! "$TIMEOUT_SECONDS" =~ ^[0-9]+$ || "$TIMEOUT_SECONDS" -lt 1 ]]; then
  echo "SOLOPM_RUNTIME_ACCESSIBLE_CRUD_TIMEOUT_SECONDS must be a positive integer" >&2
  exit 2
fi

if ! command -v "$SQLITE3" >/dev/null 2>&1; then
  echo "BLOCKER: sqlite3 is required for runtime accessible CRUD smoke" >&2
  exit 2
fi

cd "$ROOT_DIR"
mkdir -p "$ROOT_DIR/.tmp"
tmp_dir="$(mktemp -d "$ROOT_DIR/.tmp/solopm-runtime-accessible-crud.XXXXXX")"
database_path="$tmp_dir/SoloPM-runtime-accessible-crud.sqlite"
created_project_id=""
created_task_id=""
cascade_task_id=""
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
    printf "INFO: kept runtime accessible CRUD database at %s\n" "$database_path"
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

launch_app_for_database_migration() {
  terminate_app
  SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1 SOLOPM_DATABASE_PATH="$database_path" "$APP_BINARY" &
  app_pid=$!
  wait_for_app_process
  activate_app
  wait_for_visible_windows
}

launch_app_for_seed_project() {
  local seed_project_id="$1"
  terminate_app
  SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1 \
    SOLOPM_DATABASE_PATH="$database_path" \
    SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION="project:$seed_project_id" \
    "$APP_BINARY" &
  app_pid=$!
  wait_for_app_process
  activate_app
  wait_for_visible_windows
}

launch_app_for_crud_mutation() {
  terminate_app
  SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1 \
    SOLOPM_DATABASE_PATH="$database_path" \
    SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION="projects" \
    "$APP_BINARY" &
  app_pid=$!
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

pressDestructiveButtonUntilSQLiteValue() {
  local label="$1"
  local destructive_fragment="$2"
  local confirmation_fragment="$3"
  local excluded_help="$4"
  local sql="$5"
  local expected="$6"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local actual=""

  while true; do
    pressButtonContaining "$destructive_fragment"
    sleep 1
    pressConfirmationButtonContaining "$confirmation_fragment" "$excluded_help"

    local postcondition_deadline=$((SECONDS + 3))
    while true; do
      actual="$(query_single_value "$sql" || true)"
      if [[ "$actual" == "$expected" ]]; then
        printf "OK: %s verified in SQLite (%s)\n" "$label" "$actual"
        return 0
      fi
      if [[ "$SECONDS" -ge "$deadline" ]]; then
        echo "BLOCKER: $label SQLite verification failed after destructive AX flow retry: expected '$expected', got '${actual:-<empty>}'" >&2
        echo "SQL: $sql" >&2
        return 1
      fi
      if [[ "$SECONDS" -ge "$postcondition_deadline" ]]; then
        break
      fi
      sleep 1
    done

    printf "INFO: SQLite postcondition for $label was not met after pressing confirmation '$confirmation_fragment'; retrying destructive AX flow.\n" >&2
    sleep 1
  done
}

seed_board_data() {
  "$SQLITE3" "$database_path" <<'SQL'
INSERT INTO projects (title, status, priority, deadline, workspace_path, tags_json, source_command, created_at, updated_at)
VALUES ('AX CRUD Seed', 'active', 'high', NULL, NULL, '[]', 'runtime-accessible-crud-smoke', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
INSERT INTO tasks (project_id, title, status, detail, due_at, priority, source_command, created_at, updated_at)
VALUES (last_insert_rowid(), 'AX seed task', 'backlog', 'Seed task for runtime accessible CRUD smoke', NULL, 'medium', 'runtime-accessible-crud-smoke', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
SQL
  query_single_value "SELECT id FROM projects WHERE title='AX CRUD Seed' ORDER BY id DESC LIMIT 1;"
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

pressConfirmationButtonContaining() {
  local fragment="$1"
  local excluded_help="$2"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while true; do
    if /usr/bin/osascript - "$APP_NAME" "$fragment" "$excluded_help" <<'APPLESCRIPT'
on run argv
  set appName to item 1 of argv
  set fragment to item 2 of argv
  set excludedHelp to item 3 of argv
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
            if isEnabled and (signalText contains fragment) and (excludedHelp is "" or not (signalText contains excludedHelp)) then
              try
                perform action "AXPress" of axItem
                return "pressed confirmation " & fragment
              end try
            end if
          end if
        end repeat
      end repeat
    end tell
  end tell
  error "confirmation button signal not found: " & fragment
end run
APPLESCRIPT
    then
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: failed to press confirmation button in AX tree: $fragment" >&2
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
    if /usr/bin/osascript - "$APP_NAME" "$fragment" "$replacement" <<'APPLESCRIPT'
on run argv
  set appName to item 1 of argv
  set fragment to item 2 of argv
  set replacement to item 3 of argv
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
            if signalText contains fragment then
              set previousClipboard to ""
              try
                set previousClipboard to the clipboard as text
              end try
              perform action "AXPress" of axItem
              set focused of axItem to true
              delay 0.2
              set the clipboard to replacement
              keystroke "a" using command down
              delay 0.1
              key code 51
              delay 0.1
              keystroke "v" using command down
              delay 0.3
              key code 48
              delay 0.2
              try
                set the clipboard to previousClipboard
              end try
              delay 0.2
              return "set text field " & fragment
            end if
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

printf "== Runtime accessible CRUD smoke ==\n"
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
terminate_app
wait_for_no_app_process

seed_project_id="$(seed_board_data)"
if [[ -z "$seed_project_id" ]]; then
  echo "BLOCKER: seed project was not inserted into runtime SQLite database" >&2
  exit 1
fi

launch_app_for_seed_project "$seed_project_id"
terminate_app
wait_for_no_app_process
launch_app_for_crud_mutation

pressButtonUntilSQLiteValue "created project" "project-board-add-project" "SELECT CASE WHEN count(*) >= 1 THEN 1 ELSE 0 END FROM projects WHERE title='Untitled Project' AND source_command='app.project-board';" "1"
created_project_id="$(wait_for_nonempty_value "created project id" "SELECT id FROM projects WHERE title='Untitled Project' AND source_command='app.project-board' ORDER BY id DESC LIMIT 1;")"
terminate_app
wait_for_no_app_process
launch_app_for_seed_project "$created_project_id"

waitForTextFieldContaining "project-inspector-title"
setTextFieldContaining "project-inspector-title" "AX Runtime CRUD Project"
waitForTextFieldContaining "AX Runtime CRUD Project"
pressButtonContaining "project-inspector-save"
verify_single_value "renamed project" "SELECT title FROM projects WHERE id=$created_project_id;" "AX Runtime CRUD Project"

pressButtonContaining "project-header-add-task"
waitForTextFieldContaining "inline-task-title"
setTextFieldContaining "inline-task-title" "AX Runtime CRUD Task"
waitForTextFieldContaining "AX Runtime CRUD Task"
pressButtonUntilSQLiteValue "created task" "inline-task-create" "SELECT CASE WHEN count(*) >= 1 THEN 1 ELSE 0 END FROM tasks WHERE project_id=$created_project_id AND title='AX Runtime CRUD Task' AND status='backlog' AND source_command='app.project-board';" "1"
created_task_id="$(wait_for_nonempty_value "created task id" "SELECT id FROM tasks WHERE project_id=$created_project_id AND title='AX Runtime CRUD Task' ORDER BY id DESC LIMIT 1;")"

pressButtonContaining "task-card-open-details"
waitForTextFieldContaining "task-inspector-title"
setTextFieldContaining "task-inspector-title" "AX Runtime CRUD Task Updated"
waitForTextFieldContaining "AX Runtime CRUD Task Updated"
pressButtonContaining "task-inspector-save"
verify_single_value "renamed task" "SELECT title FROM tasks WHERE id=$created_task_id;" "AX Runtime CRUD Task Updated"
pressButtonContaining "task-status-move-planned-$created_task_id"
verify_single_value "advanced task status" "SELECT status FROM tasks WHERE id=$created_task_id;" "planned"
terminate_app
wait_for_no_app_process
launch_app_for_seed_project "$created_project_id"
pressButtonContaining "task-card-open-details"
pressDestructiveButtonUntilSQLiteValue "deleted task" "task-inspector-delete" "task-inspector-delete-confirmation-confirm" "" "SELECT count(*) FROM tasks WHERE id=$created_task_id;" "0"

pressButtonContaining "project-header-add-task"
waitForTextFieldContaining "inline-task-title"
setTextFieldContaining "inline-task-title" "AX Runtime Cascade Task"
waitForTextFieldContaining "AX Runtime Cascade Task"
pressButtonUntilSQLiteValue "created cascade task" "inline-task-create" "SELECT CASE WHEN count(*) >= 1 THEN 1 ELSE 0 END FROM tasks WHERE project_id=$created_project_id AND title='AX Runtime Cascade Task' AND status='backlog' AND source_command='app.project-board';" "1"
cascade_task_id="$(wait_for_nonempty_value "cascade task id" "SELECT id FROM tasks WHERE project_id=$created_project_id AND title='AX Runtime Cascade Task' ORDER BY id DESC LIMIT 1;")"
terminate_app
wait_for_no_app_process
launch_app_for_seed_project "$created_project_id"
waitForTextFieldContaining "project-inspector-title"

pressButtonUntilSQLiteValue "completed project" "project-inspector-complete" "SELECT status FROM projects WHERE id=$created_project_id;" "completed"

pressDestructiveButtonUntilSQLiteValue "deleted project" "project-inspector-delete" "project-inspector-delete-confirmation-confirm" "" "SELECT count(*) FROM projects WHERE id=$created_project_id;" "0"
verify_single_value "deleted task cascade" "SELECT count(*) FROM tasks WHERE id=$cascade_task_id OR project_id=$created_project_id;" "0"

printf "OK: runtime accessible CRUD smoke created, renamed, completed, and deleted a project, then created, updated, moved, directly deleted, and cascade-deleted tasks through the visible app\n"
