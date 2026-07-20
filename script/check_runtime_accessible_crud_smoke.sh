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
APP_BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-}"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
TIMEOUT_SECONDS="${SOLOPM_RUNTIME_ACCESSIBLE_CRUD_TIMEOUT_SECONDS:-60}"
KEEP_DATABASE="${SOLOPM_RUNTIME_ACCESSIBLE_CRUD_KEEP_DATABASE:-0}"
ARTIFACT_DIR="${SOLOPM_RUNTIME_ACCESSIBLE_CRUD_ARTIFACT_DIR:-}"
SQLITE3="${SQLITE3:-sqlite3}"
SQLITE_BUSY_TIMEOUT_MS="${SOLOPM_RUNTIME_ACCESSIBLE_CRUD_SQLITE_BUSY_TIMEOUT_MS:-5000}"
DESTRUCTIVE_POSTCONDITION_TIMEOUT_SECONDS="${SOLOPM_RUNTIME_ACCESSIBLE_CRUD_DESTRUCTIVE_POSTCONDITION_TIMEOUT_SECONDS:-10}"
FORM_POSTCONDITION_TIMEOUT_SECONDS="${SOLOPM_RUNTIME_ACCESSIBLE_CRUD_FORM_POSTCONDITION_TIMEOUT_SECONDS:-10}"
RECOVERABLE_ONLY="${SOLOPM_RUNTIME_ACCESSIBLE_CRUD_RECOVERABLE_ONLY:-0}"
AX_HELPERS="${AX_HELPERS:-$ROOT_DIR/script/ui_accessibility_smoke_helpers.sh}"
AX_TEXT_INPUT_HELPER="${AX_TEXT_INPUT_HELPER:-$ROOT_DIR/script/ui_evidence_ax_text_input.swift}"
AX_SCROLL_HELPER="${AX_SCROLL_HELPER:-$ROOT_DIR/script/ui_evidence_ax_scroll_container.swift}"
AX_BUTTON_HELPER="${AX_BUTTON_HELPER:-$ROOT_DIR/script/ui_evidence_ax_press_button.swift}"

if [[ ! "$TIMEOUT_SECONDS" =~ ^[0-9]+$ || "$TIMEOUT_SECONDS" -lt 1 ]]; then
  echo "SOLOPM_RUNTIME_ACCESSIBLE_CRUD_TIMEOUT_SECONDS must be a positive integer" >&2
  exit 2
fi

if [[ ! "$SQLITE_BUSY_TIMEOUT_MS" =~ ^[0-9]+$ || "$SQLITE_BUSY_TIMEOUT_MS" -lt 1 ]]; then
  echo "SOLOPM_RUNTIME_ACCESSIBLE_CRUD_SQLITE_BUSY_TIMEOUT_MS must be a positive integer" >&2
  exit 2
fi

if [[ ! "$DESTRUCTIVE_POSTCONDITION_TIMEOUT_SECONDS" =~ ^[0-9]+$ || "$DESTRUCTIVE_POSTCONDITION_TIMEOUT_SECONDS" -lt 1 ]]; then
  echo "SOLOPM_RUNTIME_ACCESSIBLE_CRUD_DESTRUCTIVE_POSTCONDITION_TIMEOUT_SECONDS must be a positive integer" >&2
  exit 2
fi

if [[ ! "$FORM_POSTCONDITION_TIMEOUT_SECONDS" =~ ^[0-9]+$ || "$FORM_POSTCONDITION_TIMEOUT_SECONDS" -lt 1 ]]; then
  echo "SOLOPM_RUNTIME_ACCESSIBLE_CRUD_FORM_POSTCONDITION_TIMEOUT_SECONDS must be a positive integer" >&2
  exit 2
fi

if ! command -v "$SQLITE3" >/dev/null 2>&1; then
  echo "BLOCKER: sqlite3 is required for runtime accessible CRUD smoke" >&2
  exit 2
fi

# shellcheck source=/dev/null
source "$AX_HELPERS"

cd "$ROOT_DIR"
mkdir -p "$ROOT_DIR/.tmp"
tmp_dir="$(mktemp -d "$ROOT_DIR/.tmp/solopm-runtime-accessible-crud.XXXXXX")"
database_path="$tmp_dir/SoloPM-runtime-accessible-crud.sqlite"
runtime_home="$tmp_dir/home"
mkdir -p "$runtime_home"
created_project_id=""
created_task_id=""
execution_task_id=""
cascade_task_id=""
app_pid=""
app_launch_pid=""
app_identity=""
app_launch_identity=""
CRUD_STATUS="failed"

write_artifact_summary() {
  [[ -n "$ARTIFACT_DIR" ]] || return 0
  mkdir -p "$ARTIFACT_DIR"
  printf 'gate=runtime-accessible-crud\nstatus=%s\n' "$CRUD_STATUS" >"$ARTIFACT_DIR/summary.env"
}

terminate_app() {
  local owned_pid="${app_pid:-}"
  local launch_pid="${app_launch_pid:-}"
  if [[ -n "$owned_pid" ]]; then
    ax_terminate_owned_process "$owned_pid" "$APP_BINARY" "${app_identity:-}"
  fi
  if [[ -n "$launch_pid" && "$launch_pid" != "$owned_pid" ]]; then
    ax_terminate_owned_process "$launch_pid" "$APP_BINARY" "${app_launch_identity:-}"
  fi
  app_pid=""
  app_launch_pid=""
  app_identity=""
  app_launch_identity=""
}

cleanup() {
  local exit_code=$?
  terminate_app
  write_artifact_summary
  if [[ "$KEEP_DATABASE" != "1" ]]; then
    rm -rf "$tmp_dir"
  else
    printf "INFO: kept runtime accessible CRUD database at %s\n" "$database_path"
  fi
  return "$exit_code"
}
trap cleanup EXIT

wait_for_app_process() {
  app_pid="$(ax_wait_for_owned_app_pid "$app_launch_pid" "$APP_BINARY" "$TIMEOUT_SECONDS")" || {
    ax_emit_failure_category "launch" "runtime-crud-owned-pid-unavailable"
    echo "BLOCKER: $APP_NAME did not launch from pid $app_launch_pid" >&2
    return 1
  }
  app_identity="$(ax_wait_for_owned_process_identity "$app_pid" "$APP_BINARY" 3)" || {
    ax_emit_failure_category "launch" "runtime-crud-owned-identity-unavailable"
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
  # Keep activation inside System Events so LaunchServices does not start a
  # second app instance without the isolated SQLite/keychain test environment.
  /usr/bin/osascript - "$app_pid" "$APP_NAME" <<'APPLESCRIPT' >/dev/null 2>&1 &
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
  if ! ax_wait_for_pid_owned_window "$APP_NAME" "$app_pid" "" "$TIMEOUT_SECONDS" "" "$APP_BINARY"; then
    echo "BLOCKER: $APP_NAME did not expose a window for launched pid $app_pid" >&2
    return 1
  fi
  return 0
}

launch_app_for_database_migration() {
  terminate_app
  /usr/bin/env -i PATH="$PATH" TMPDIR="$tmp_dir" HOME="$runtime_home" CFFIXED_USER_HOME="$runtime_home" SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1 SOLOPM_DATABASE_PATH="$database_path" SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION="projects" "$APP_BINARY" -ApplePersistenceIgnoreState YES &
  app_launch_pid=$!
  app_launch_identity="$(ax_wait_for_owned_process_identity "$app_launch_pid" "$APP_BINARY" 3)" || return 1
  wait_for_app_process
  activate_app
  wait_for_visible_windows
}

launch_app_for_seed_project() {
  local seed_project_id="$1"
  local selected_task_id="${2:-}"
  local inspector_field="project-inspector-title"
  terminate_app
  if [[ -n "$selected_task_id" ]]; then
    /usr/bin/env -i PATH="$PATH" TMPDIR="$tmp_dir" HOME="$runtime_home" CFFIXED_USER_HOME="$runtime_home" \
      SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1 SOLOPM_DATABASE_PATH="$database_path" \
      SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION="project:$seed_project_id" \
      SOLOPM_PROJECT_BOARD_SELECTED_TASK_ID="$selected_task_id" \
      "$APP_BINARY" -ApplePersistenceIgnoreState YES &
  else
    /usr/bin/env -i PATH="$PATH" TMPDIR="$tmp_dir" HOME="$runtime_home" CFFIXED_USER_HOME="$runtime_home" \
      SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1 SOLOPM_DATABASE_PATH="$database_path" \
      SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION="project:$seed_project_id" \
      "$APP_BINARY" -ApplePersistenceIgnoreState YES &
  fi
  app_launch_pid=$!
  app_launch_identity="$(ax_wait_for_owned_process_identity "$app_launch_pid" "$APP_BINARY" 3)" || return 1
  wait_for_app_process
  activate_app
  wait_for_visible_windows
  if [[ -n "$selected_task_id" ]]; then
    inspector_field="task-inspector-title"
  fi
  # Scene/AppStorage presentation intent survives the repeated launches in this
  # isolated HOME. Inspect the postcondition first so a blind toggle cannot
  # close an inspector that SwiftUI has already restored from the prior phase.
  if ! textFieldContainingExists "$inspector_field"; then
    pressButtonUntilTextFieldContaining "project-board-inspector-toggle" "$inspector_field"
  fi
}

launch_app_for_crud_mutation() {
  terminate_app
  /usr/bin/env -i PATH="$PATH" TMPDIR="$tmp_dir" HOME="$runtime_home" CFFIXED_USER_HOME="$runtime_home" \
    SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1 SOLOPM_DATABASE_PATH="$database_path" \
    SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION="projects" \
    "$APP_BINARY" -ApplePersistenceIgnoreState YES &
  app_launch_pid=$!
  app_launch_identity="$(ax_wait_for_owned_process_identity "$app_launch_pid" "$APP_BINARY" 3)" || return 1
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
  "$SQLITE3" -batch -noheader -cmd ".timeout $SQLITE_BUSY_TIMEOUT_MS" "$database_path" "$sql" | tail -n 1
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
  local fallback_fragment="${3:-}"
  local sql="$4"
  local expected="$5"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local actual=""

  while true; do
    pressButtonContaining "$fragment" "$fallback_fragment"

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
  local confirmation_fallback="$4"
  local excluded_help="$5"
  local sql="$6"
  local expected="$7"
  local before_confirmation_expected="${8:-}"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local actual=""
  local did_verify_confirmation_gate=0

  while true; do
    pressButtonContaining "$destructive_fragment"
    if [[ -n "$before_confirmation_expected" && "$did_verify_confirmation_gate" -eq 0 ]]; then
      verify_single_value "$label waits for confirmation" "$sql" "$before_confirmation_expected" || {
        echo "BLOCKER: $label mutated before confirmation" >&2
        return 1
      }
      did_verify_confirmation_gate=1
    fi
    sleep 1
    pressConfirmationButtonContaining "$confirmation_fragment" "$confirmation_fallback" "$excluded_help"

    local postcondition_deadline=$((SECONDS + DESTRUCTIVE_POSTCONDITION_TIMEOUT_SECONDS))
    while true; do
      actual="$(query_single_value "$sql" || true)"
      if [[ "$actual" == "$expected" ]]; then
        printf "OK: %s verified in SQLite (%s)\n" "$label" "$actual"
        return 0
      fi
      if [[ "$SECONDS" -ge "$postcondition_deadline" ]]; then
        break
      fi
      sleep 1
    done

    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: $label SQLite verification failed after destructive AX flow retry: expected '$expected', got '${actual:-<empty>}'" >&2
      echo "SQL: $sql" >&2
      return 1
    fi

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
  local fallback_fragment="${2:-}"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while true; do
    if /usr/bin/osascript - "$app_pid" "$APP_NAME" "$fragment" "$fallback_fragment" <<'APPLESCRIPT'
on run argv
  set appPID to item 1 of argv as integer
  set appName to item 2 of argv
  set fragment to item 3 of argv
  set fallbackFragment to item 4 of argv
  tell application "System Events"
    set matchingProcesses to application processes whose unix id is appPID
    if (count of matchingProcesses) is 0 then error appName & " pid " & appPID & " is not visible to System Events"
    set targetProcess to item 1 of matchingProcesses
    tell targetProcess
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
            set matchesPrimary to signalText contains fragment
            set matchesFallback to false
            if fallbackFragment is not "" and signalText contains fallbackFragment then set matchesFallback to true
            if isEnabled and (matchesPrimary or matchesFallback) then
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
    activate_app
    wait_for_visible_windows >/dev/null 2>&1 || true
    sleep 1
  done
}

pressConfirmationButtonContaining() {
  local fragment="$1"
  # SwiftUI may expose a confirmation button's VoiceOver label even when
  # AXIdentifier is missing from the runtime tree, so keep the stable identifier
  # as the primary signal and the distinct "Confirm ..." label as the fallback.
  local fallback_fragment="$2"
  local excluded_help="$3"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while true; do
    if /usr/bin/swift "$AX_BUTTON_HELPER" "$app_pid" "$fragment"; then
      printf "pressed confirmation %s\n" "$fragment"
      return 0
    fi
    if /usr/bin/osascript - "$app_pid" "$APP_NAME" "$fragment" "$fallback_fragment" "$excluded_help" <<'APPLESCRIPT'
on run argv
  set appPID to item 1 of argv as integer
  set appName to item 2 of argv
  set fragment to item 3 of argv
  set fallbackFragment to item 4 of argv
  set excludedHelp to item 5 of argv
  tell application "System Events"
    set matchingProcesses to application processes whose unix id is appPID
    if (count of matchingProcesses) is 0 then error appName & " pid " & appPID & " is not visible to System Events"
    set targetProcess to item 1 of matchingProcesses
    tell targetProcess
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
            set matchesPrimary to signalText contains fragment
            set matchesFallback to false
            if fallbackFragment is not "" and signalText contains fallbackFragment then set matchesFallback to true
            if isEnabled and (matchesPrimary or matchesFallback) and (excludedHelp is "" or not (signalText contains excludedHelp)) then
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
    activate_app
    wait_for_visible_windows >/dev/null 2>&1 || true
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

scrollAXContainerDown() {
  local fragment="$1"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while true; do
    if /usr/bin/swift "$AX_SCROLL_HELPER" "$app_pid" "$fragment"; then
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: failed to scroll AX container: $fragment" >&2
      return 1
    fi
    activate_app
    sleep 1
  done
}

waitForTextFieldContaining() {
  local fragment="$1"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while true; do
    if textFieldContainingExists "$fragment"; then
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: text field did not appear in AX tree: $fragment" >&2
      return 1
    fi
    activate_app
    wait_for_visible_windows >/dev/null 2>&1 || true
    sleep 1
  done
}

textFieldContainingExists() {
  local fragment="$1"
  /usr/bin/osascript - "$app_pid" "$APP_NAME" "$fragment" <<'APPLESCRIPT' >/dev/null 2>&1
on run argv
  set appPID to item 1 of argv as integer
  set appName to item 2 of argv
  set fragment to item 3 of argv
  tell application "System Events"
    set matchingProcesses to application processes whose unix id is appPID
    if (count of matchingProcesses) is 0 then error appName & " pid " & appPID & " is not visible to System Events"
    set targetProcess to item 1 of matchingProcesses
    tell targetProcess
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
}

waitForAXElementContaining() {
  local identifier_fragment="$1"
  local required_text_one="$2"
  local required_text_two="$3"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while true; do
    if /usr/bin/osascript - "$app_pid" "$APP_NAME" "$identifier_fragment" "$required_text_one" "$required_text_two" <<'APPLESCRIPT' >/dev/null 2>&1
on run argv
  set appPID to item 1 of argv as integer
  set appName to item 2 of argv
  set identifierFragment to item 3 of argv
  set requiredTextOne to item 4 of argv
  set requiredTextTwo to item 5 of argv
  tell application "System Events"
    set matchingProcesses to application processes whose unix id is appPID
    if (count of matchingProcesses) is 0 then error appName & " pid " & appPID & " is not visible to System Events"
    set targetProcess to item 1 of matchingProcesses
    tell targetProcess
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
          if signalText contains identifierFragment and signalText contains requiredTextOne and signalText contains requiredTextTwo then
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
      echo "BLOCKER: AX element did not expose required text: $identifier_fragment" >&2
      return 1
    fi
    activate_app
    wait_for_visible_windows >/dev/null 2>&1 || true
    sleep 1
  done
}

pressButtonUntilTextFieldContaining() {
  local button_fragment="$1"
  local field_fragment="$2"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))

  while true; do
    pressButtonContaining "$button_fragment"

    # A successful AXPress can consume the phase timeout while SwiftUI is
    # rebuilding its window. Give the resulting form its own bounded window so
    # a real press is not misclassified as a failure before the field appears.
    local postcondition_deadline=$((SECONDS + FORM_POSTCONDITION_TIMEOUT_SECONDS))
    while true; do
      if textFieldContainingExists "$field_fragment"; then
        return 0
      fi
      if [[ "$SECONDS" -ge "$postcondition_deadline" ]]; then
        break
      fi
      activate_app
      wait_for_visible_windows >/dev/null 2>&1 || true
      sleep 1
    done

    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: text field did not appear after pressing '$button_fragment': $field_fragment" >&2
      return 1
    fi

    printf "INFO: text field '%s' did not appear after pressing '%s'; retrying AX press.\n" "$field_fragment" "$button_fragment" >&2
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

if [[ "$RECOVERABLE_ONLY" == "1" ]]; then
  created_project_id="$seed_project_id"
  created_task_id="$(wait_for_nonempty_value "seed task id" "SELECT id FROM tasks WHERE project_id=$created_project_id ORDER BY id DESC LIMIT 1;")"
  launch_app_for_seed_project "$created_project_id" "$created_task_id"
  waitForTextFieldContaining "task-inspector-title"
  "$SQLITE3" "$database_path" "CREATE TRIGGER runtime_crud_fail_task_update BEFORE UPDATE ON tasks WHEN OLD.id=$created_task_id BEGIN SELECT RAISE(FAIL, 'injected recoverable task save failure'); END;"
  setTextFieldContaining "task-inspector-title" "AX Runtime CRUD Task Retried"
  pressButtonContaining "task-inspector-save"
  verify_single_value "failed save did not mutate task" "SELECT title FROM tasks WHERE id=$created_task_id;" "AX seed task"
  "$SQLITE3" "$database_path" "DROP TRIGGER runtime_crud_fail_task_update;"
  pressButtonContaining "task-inspector-save-retry" "Retry"
  verify_single_value "recoverable task save retry" "SELECT title FROM tasks WHERE id=$created_task_id;" "AX Runtime CRUD Task Retried"
  CRUD_STATUS="passed"
  printf "OK: runtime recoverable save smoke passed\n"
  exit 0
fi

launch_app_for_seed_project "$seed_project_id"
terminate_app
wait_for_no_app_process
launch_app_for_crud_mutation

pressButtonUntilSQLiteValue "created project" "project-board-add-project" "projects-hub-compact-add-project" "SELECT CASE WHEN count(*) >= 1 THEN 1 ELSE 0 END FROM projects WHERE title='Untitled Project' AND source_command='app.project-board';" "1"
created_project_id="$(wait_for_nonempty_value "created project id" "SELECT id FROM projects WHERE title='Untitled Project' AND source_command='app.project-board' ORDER BY id DESC LIMIT 1;")"
terminate_app
wait_for_no_app_process
launch_app_for_seed_project "$created_project_id"

waitForTextFieldContaining "project-inspector-title"
setTextFieldContaining "project-inspector-title" "AX Runtime CRUD Project"
waitForTextFieldContaining "AX Runtime CRUD Project"
pressButtonContaining "project-inspector-save"
verify_single_value "renamed project" "SELECT title FROM projects WHERE id=$created_project_id;" "AX Runtime CRUD Project"

pressButtonUntilTextFieldContaining "project-header-add-task" "inline-task-title"
waitForTextFieldContaining "inline-task-title"
setTextFieldContaining "inline-task-title" "AX Runtime CRUD Task"
waitForTextFieldContaining "AX Runtime CRUD Task"
pressButtonUntilSQLiteValue "created task" "inline-task-create" "" "SELECT CASE WHEN count(*) >= 1 THEN 1 ELSE 0 END FROM tasks WHERE project_id=$created_project_id AND title='AX Runtime CRUD Task' AND status='backlog' AND source_command='app.project-board';" "1"
created_task_id="$(wait_for_nonempty_value "created task id" "SELECT id FROM tasks WHERE project_id=$created_project_id AND title='AX Runtime CRUD Task' ORDER BY id DESC LIMIT 1;")"

pressButtonContaining "task-card-open-details"
waitForTextFieldContaining "task-inspector-title"
setTextFieldContaining "task-inspector-title" "AX Runtime CRUD Task Updated"
waitForTextFieldContaining "AX Runtime CRUD Task Updated"

# Structured inspector dates must only write a real date or NULL. Merely
# opening/closing the date controls without Save must not mutate SQLite.
pressButtonContaining "task-inspector-due"
pressButtonContaining "task-inspector-due-clear"
verify_single_value "cancelled due date edit" "SELECT CASE WHEN due_at IS NULL THEN 1 ELSE 0 END FROM tasks WHERE id=$created_task_id;" "1"
pressButtonContaining "task-inspector-due"
pressButtonContaining "task-inspector-save"
verify_single_value "renamed task" "SELECT title FROM tasks WHERE id=$created_task_id;" "AX Runtime CRUD Task Updated"
verify_single_value "set native task due date" "SELECT CASE WHEN due_at IS NOT NULL AND datetime(due_at) IS NOT NULL THEN 1 ELSE 0 END FROM tasks WHERE id=$created_task_id;" "1"
terminate_app
wait_for_no_app_process
launch_app_for_seed_project "$created_project_id" "$created_task_id"
waitForTextFieldContaining "task-inspector-title"
pressButtonContaining "task-inspector-due-clear"
pressButtonContaining "task-inspector-save"
verify_single_value "cleared native task due date" "SELECT CASE WHEN due_at IS NULL THEN 1 ELSE 0 END FROM tasks WHERE id=$created_task_id;" "1"
terminate_app
wait_for_no_app_process
launch_app_for_seed_project "$created_project_id" "$created_task_id"
waitForTextFieldContaining "task-inspector-title"

# A real SQLite write failure proves the recoverable path without adding a
# product-only fault flag. The inspector and draft stay visible for Retry.
"$SQLITE3" "$database_path" "CREATE TRIGGER runtime_crud_fail_task_update BEFORE UPDATE ON tasks WHEN OLD.id=$created_task_id BEGIN SELECT RAISE(FAIL, 'injected recoverable task save failure'); END;"
setTextFieldContaining "task-inspector-title" "AX Runtime CRUD Task Retried"
pressButtonContaining "task-inspector-save"
verify_single_value "failed save did not mutate task" "SELECT title FROM tasks WHERE id=$created_task_id;" "AX Runtime CRUD Task Updated"
"$SQLITE3" "$database_path" "DROP TRIGGER runtime_crud_fail_task_update;"
pressButtonContaining "task-inspector-save-retry" "Retry"
verify_single_value "recoverable task save retry" "SELECT title FROM tasks WHERE id=$created_task_id;" "AX Runtime CRUD Task Retried"
pressButtonContaining "task-status-move-planned-$created_task_id"
verify_single_value "advanced task status" "SELECT status FROM tasks WHERE id=$created_task_id;" "planned"
terminate_app
wait_for_no_app_process
launch_app_for_seed_project "$created_project_id" "$created_task_id"
waitForTextFieldContaining "task-inspector-title"
pressDestructiveButtonUntilSQLiteValue "deleted task" "task-inspector-delete" "task-inspector-delete-confirmation-confirm" "Confirm Delete Task" "" "SELECT count(*) FROM tasks WHERE id=$created_task_id;" "0" "1"

pressButtonUntilTextFieldContaining "project-header-add-task" "inline-task-title"
waitForTextFieldContaining "inline-task-title"
setTextFieldContaining "inline-task-title" "AX Runtime Execution Task"
waitForTextFieldContaining "AX Runtime Execution Task"
waitForTextFieldContaining "inline-task-detail"
setTextFieldContaining "inline-task-detail" "Execute this runtime task through the approved plan."
waitForTextFieldContaining "Execute this runtime task through the approved plan."
pressButtonUntilSQLiteValue "created execution task" "inline-task-create" "" "SELECT CASE WHEN count(*) >= 1 THEN 1 ELSE 0 END FROM tasks WHERE project_id=$created_project_id AND title='AX Runtime Execution Task' AND detail='Execute this runtime task through the approved plan.' AND status='backlog' AND source_command='app.project-board';" "1"
execution_task_id="$(wait_for_nonempty_value "execution task id" "SELECT id FROM tasks WHERE project_id=$created_project_id AND title='AX Runtime Execution Task' ORDER BY id DESC LIMIT 1;")"
pressButtonContaining "task-card-open-details"
waitForTextFieldContaining "task-inspector-title"
pressButtonContaining "task-auto-execution-review"
pressButtonContaining "task-auto-execution-run-plan"
verify_single_value "executed task status" "SELECT status FROM tasks WHERE id=$execution_task_id;" "in_progress"
verify_single_value "executed task detail marker" "SELECT CASE WHEN detail LIKE '%SoloPM approved automation execution%' THEN 1 ELSE 0 END FROM tasks WHERE id=$execution_task_id;" "1"
pressButtonContaining "task-card-open-details"
scrollAXContainerDown "task-inspector"
waitForAXElementContaining "approved-execution-receipt" "AX Runtime Execution Task" "Execute this runtime task through the approved plan."

pressButtonUntilTextFieldContaining "project-header-add-task" "inline-task-title"
waitForTextFieldContaining "inline-task-title"
setTextFieldContaining "inline-task-title" "AX Runtime Cascade Task"
waitForTextFieldContaining "AX Runtime Cascade Task"
pressButtonUntilSQLiteValue "created cascade task" "inline-task-create" "" "SELECT CASE WHEN count(*) >= 1 THEN 1 ELSE 0 END FROM tasks WHERE project_id=$created_project_id AND title='AX Runtime Cascade Task' AND status='backlog' AND source_command='app.project-board';" "1"
cascade_task_id="$(wait_for_nonempty_value "cascade task id" "SELECT id FROM tasks WHERE project_id=$created_project_id AND title='AX Runtime Cascade Task' ORDER BY id DESC LIMIT 1;")"
terminate_app
wait_for_no_app_process
launch_app_for_seed_project "$created_project_id"
waitForTextFieldContaining "project-inspector-title"

pressButtonUntilSQLiteValue "completed project" "project-inspector-complete" "" "SELECT status FROM projects WHERE id=$created_project_id;" "completed"

pressDestructiveButtonUntilSQLiteValue "deleted project" "project-inspector-delete" "project-inspector-delete-confirmation-confirm" "Confirm Delete Project" "" "SELECT count(*) FROM projects WHERE id=$created_project_id;" "0" "1"
verify_single_value "deleted task cascade" "SELECT count(*) FROM tasks WHERE id=$cascade_task_id OR project_id=$created_project_id;" "0"

CRUD_STATUS="passed"
printf "OK: runtime accessible CRUD smoke created, renamed, completed, and deleted a project, then created, updated, moved, executed approved task content with a readable AX receipt, directly deleted, and cascade-deleted tasks through the visible app\n"
