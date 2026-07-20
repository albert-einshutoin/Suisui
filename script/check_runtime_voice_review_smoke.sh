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
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:?BUNDLE_IDENTIFIER is required}"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
AX_HELPERS="${AX_HELPERS:-$ROOT_DIR/script/ui_accessibility_smoke_helpers.sh}"
TIMEOUT_SECONDS="${SUISUI_RUNTIME_VOICE_REVIEW_TIMEOUT_SECONDS:-35}"
AX_ATTEMPT_SECONDS="${SUISUI_RUNTIME_VOICE_REVIEW_AX_ATTEMPT_SECONDS:-5}"
KEEP_DATABASE="${SUISUI_RUNTIME_VOICE_REVIEW_KEEP_DATABASE:-0}"
SQLITE3="${SQLITE3:-sqlite3}"
WINDOW_HEIGHT="${SUISUI_RUNTIME_VOICE_REVIEW_WINDOW_HEIGHT:-640}"
daily_planning_seed_task_id=""

# shellcheck source=/dev/null
source "$AX_HELPERS"

if [[ ! "$TIMEOUT_SECONDS" =~ ^[0-9]+$ || "$TIMEOUT_SECONDS" -lt 1 ]]; then
  echo "SUISUI_RUNTIME_VOICE_REVIEW_TIMEOUT_SECONDS must be a positive integer" >&2
  exit 2
fi
if [[ ! "$AX_ATTEMPT_SECONDS" =~ ^[0-9]+$ || "$AX_ATTEMPT_SECONDS" -lt 1 ]]; then
  echo "SUISUI_RUNTIME_VOICE_REVIEW_AX_ATTEMPT_SECONDS must be a positive integer" >&2
  exit 2
fi

if ! command -v "$SQLITE3" >/dev/null 2>&1; then
  echo "BLOCKER: sqlite3 is required for runtime voice review smoke" >&2
  exit 2
fi

cd "$ROOT_DIR"
mkdir -p "$ROOT_DIR/.tmp"
tmp_dir="$(mktemp -d "$ROOT_DIR/.tmp/suisui-runtime-voice-review.XXXXXX")"
database_path="$tmp_dir/Suisui-runtime-voice-review.sqlite"
settings_suite_name="$BUNDLE_IDENTIFIER.runtime-voice-review.$(/usr/bin/uuidgen | tr '[:upper:]' '[:lower:]')"
settings_suite_names=()
app_launch_pid=""
app_launch_identity=""
app_pid=""
app_identity=""

terminate_app() {
  local owned_pid="${app_pid:-}"
  local launch_pid="${app_launch_pid:-}"
  if [[ -n "$owned_pid" ]]; then
    ax_terminate_owned_process "$owned_pid" "$APP_BINARY" "${app_identity:-}"
  fi
  if [[ -n "$launch_pid" && "$launch_pid" != "$owned_pid" ]]; then
    ax_terminate_owned_process "$launch_pid" "$APP_BINARY" "${app_launch_identity:-}"
  fi
  app_launch_pid=""
  app_launch_identity=""
  app_pid=""
  app_identity=""
}

cleanup() {
  terminate_app
  local suite
  for suite in "${settings_suite_names[@]}"; do
    /usr/bin/defaults delete "$suite" >/dev/null 2>&1 || true
  done
  if [[ "$KEEP_DATABASE" != "1" ]]; then
    rm -rf "$tmp_dir"
  else
    printf "INFO: kept runtime voice review database at %s\n" "$database_path"
  fi
}
trap cleanup EXIT

wait_for_osascript_attempt() {
  local osascript_pid="$1"
  local ax_attempt_seconds="${SUISUI_RUNTIME_VOICE_REVIEW_AX_ATTEMPT_SECONDS:-5}"
  local attempt_deadline=$((SECONDS + ax_attempt_seconds))
  while kill -0 "$osascript_pid" >/dev/null 2>&1; do
    if [[ "$SECONDS" -ge "$attempt_deadline" ]]; then
      kill "$osascript_pid" >/dev/null 2>&1 || true
      wait "$osascript_pid" >/dev/null 2>&1 || true
      return 124
    fi
    sleep 0.1
  done
  wait "$osascript_pid"
}

activate_app() {
  ax_process_matches_identity "$app_pid" "$APP_BINARY" "$app_identity" || return 1
  /usr/bin/osascript - "$app_pid" <<'APPLESCRIPT' >/dev/null 2>&1 &
on run argv
  set appPID to (item 1 of argv) as integer
  tell application "System Events"
    set matchingProcesses to application processes whose unix id is appPID
    if (count of matchingProcesses) is 0 then error "pid-owned process missing"
    set targetProcess to item 1 of matchingProcesses
    tell targetProcess
      set frontmost to true
      repeat with windowIndex from 1 to count of windows
        set currentWindow to window windowIndex
        try
          if (name of currentWindow as text) is "Voice Command" then
            perform action "AXRaise" of currentWindow
            exit repeat
          end if
        end try
      end repeat
    end tell
  end tell
  return "activated"
end run
APPLESCRIPT
  local osascript_pid=$!
  wait_for_osascript_attempt "$osascript_pid"
}

wait_for_voice_window() {
  ax_wait_for_pid_owned_window "$APP_NAME" "$app_pid" "Voice Command" \
    "$TIMEOUT_SECONDS" "" "$APP_BINARY"
}

set_voice_window_size() {
  local width="$1"
  local height="$2"
  ax_process_matches_identity "$app_pid" "$APP_BINARY" "$app_identity" || return 1
  /usr/bin/osascript - "$app_pid" "$width" "$height" <<'APPLESCRIPT' >/dev/null 2>&1 &
on run argv
  set appPID to (item 1 of argv) as integer
  set targetWidth to (item 2 of argv) as integer
  set targetHeight to (item 3 of argv) as integer
  tell application "System Events"
    set matchingProcesses to application processes whose unix id is appPID
    if (count of matchingProcesses) is 0 then error "pid-owned process missing"
    set targetProcess to item 1 of matchingProcesses
    tell targetProcess
      set frontmost to true
      repeat with windowIndex from 1 to count of windows
        set currentWindow to window windowIndex
        try
          if (name of currentWindow as text) is "Voice Command" then
            perform action "AXRaise" of currentWindow
            set size of currentWindow to {targetWidth, targetHeight}
          end if
        end try
      end repeat
    end tell
  end tell
end run
APPLESCRIPT
  local osascript_pid=$!
  wait_for_osascript_attempt "$osascript_pid"
  sleep 1
}

launch_app_for_voice_review() {
  local locale="$1"
  local width="$2"
  terminate_app
  database_path="$tmp_dir/Suisui-runtime-voice-review-$locale.sqlite"
  settings_suite_name="$BUNDLE_IDENTIFIER.runtime-voice-review.$locale.$(/usr/bin/uuidgen | tr '[:upper:]' '[:lower:]')"
  settings_suite_names+=("$settings_suite_name")
  SUISUI_DISABLE_KEYCHAIN_SECRET_STORE=1 \
    SUISUI_DATABASE_PATH="$database_path" \
    SUISUI_APP_SETTINGS_SUITE_NAME="$settings_suite_name" \
    SUISUI_OPEN_VOICE_COMMAND_ON_LAUNCH=1 \
    SUISUI_LANGUAGE_PREFERENCE="$locale" \
    "$APP_BINARY" -ApplePersistenceIgnoreState YES &
  app_launch_pid=$!
  app_launch_identity="$(ax_wait_for_owned_process_identity "$app_launch_pid" "$APP_BINARY" 3)" || {
    echo "BLOCKER: Voice launch identity could not be established" >&2
    return 1
  }
  app_pid="$(ax_wait_for_owned_app_pid "$app_launch_pid" "$APP_BINARY" "$TIMEOUT_SECONDS")" || {
    echo "BLOCKER: PID-owned Voice process did not appear" >&2
    return 1
  }
  app_identity="$(ax_wait_for_owned_process_identity "$app_pid" "$APP_BINARY" 3)" || {
    echo "BLOCKER: Voice process identity could not be established" >&2
    return 1
  }
  ax_wait_for_pid_owned_process "$APP_NAME" "$app_pid" "$TIMEOUT_SECONDS" "$APP_BINARY"
  wait_for_voice_window
  activate_app
  set_voice_window_size "$width" "$WINDOW_HEIGHT"
}

setTextAreaContaining() {
  local fragment="$1"
  local text_value="$2"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))

  while true; do
    ax_process_matches_identity "$app_pid" "$APP_BINARY" "$app_identity" || return 1
    local attempt_output="$tmp_dir/set-text.$$.out"
    /usr/bin/osascript - "$app_pid" "$fragment" "$text_value" <<'APPLESCRIPT' >"$attempt_output" 2>&1 &
on run argv
  set appPID to (item 1 of argv) as integer
  set fragment to item 2 of argv
  set textValue to item 3 of argv
  tell application "System Events"
    set matchingProcesses to application processes whose unix id is appPID
    if (count of matchingProcesses) is 0 then error "pid-owned process missing"
    set targetProcess to item 1 of matchingProcesses
    tell targetProcess
      set windowCount to count of windows
      repeat with windowIndex from 1 to windowCount
        set currentWindow to window windowIndex
        set windowName to ""
        try
          set windowName to name of currentWindow as text
        end try
        if windowName is "Voice Command" then
          try
            set frontmost to true
            perform action "AXRaise" of currentWindow
          end try
          set fallbackTextArea to missing value
          set axItems to entire contents of currentWindow
          repeat with axItem in axItems
            set itemRole to ""
            try
              set itemRole to role of axItem as text
            end try
            if itemRole is "AXTextArea" or itemRole is "AXTextField" then
              if fallbackTextArea is missing value then set fallbackTextArea to axItem
              set itemIdentifier to ""
              set itemName to ""
              set itemHelp to ""
              try
                set itemIdentifier to value of attribute "AXIdentifier" of axItem as text
              end try
              try
                set itemName to name of axItem as text
              end try
              try
                set itemHelp to value of attribute "AXHelp" of axItem as text
              end try
              set signalText to itemIdentifier & " " & itemName & " " & itemHelp
              if signalText contains fragment then
                set value of axItem to textValue
                return "set " & fragment
              end if
            end if
          end repeat
          if fallbackTextArea is not missing value then
            set value of fallbackTextArea to textValue
            return "set " & fragment
          end if
        end if
      end repeat
    end tell
  end tell
  error "text area signal not found: " & fragment
end run
APPLESCRIPT
    local osascript_pid=$!
    if wait_for_osascript_attempt "$osascript_pid"; then
      cat "$attempt_output"
      rm -f "$attempt_output"
      sleep 1
      return 0
    fi
    rm -f "$attempt_output"
    ax_process_matches_identity "$app_pid" "$APP_BINARY" "$app_identity" || return 1
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: failed to set AX text area: $fragment" >&2
      return 1
    fi
    sleep 1
  done
}

pressControlContaining() {
  local fragment="$1"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while true; do
    ax_process_matches_identity "$app_pid" "$APP_BINARY" "$app_identity" || return 1
    local attempt_output="$tmp_dir/press-control.$$.out"
    /usr/bin/osascript - "$app_pid" "$fragment" <<'APPLESCRIPT' >"$attempt_output" 2>&1 &
on run argv
  set appPID to (item 1 of argv) as integer
  set fragment to item 2 of argv
  tell application "System Events"
    set matchingProcesses to application processes whose unix id is appPID
    if (count of matchingProcesses) is 0 then error "pid-owned process missing"
    set targetProcess to item 1 of matchingProcesses
    tell targetProcess
      repeat with windowIndex from 1 to count of windows
        set currentWindow to window windowIndex
        set windowName to ""
        try
          set windowName to name of currentWindow as text
        end try
        if windowName is "Voice Command" then
          try
            set frontmost to true
            perform action "AXRaise" of currentWindow
          end try
          set axItems to entire contents of currentWindow
          repeat with axItem in axItems
            set itemRole to ""
            try
              set itemRole to role of axItem as text
            end try
            if itemRole is "AXButton" or itemRole is "AXCheckBox" then
              set itemName to ""
              set itemTitle to ""
              set itemDescription to ""
              set itemHelp to ""
              set itemIdentifier to ""
              try
                set itemName to name of axItem as text
              end try
              try
                set itemTitle to value of attribute "AXTitle" of axItem as text
              end try
              try
                set itemDescription to description of axItem as text
              end try
              try
                set itemHelp to value of attribute "AXHelp" of axItem as text
              end try
              try
                set itemIdentifier to value of attribute "AXIdentifier" of axItem as text
              end try
              set signalText to itemIdentifier & " " & itemName & " " & itemTitle & " " & itemDescription & " " & itemHelp
              set isEnabled to true
              try
                set isEnabled to enabled of axItem as boolean
              end try
              if isEnabled and signalText contains fragment then
                perform action "AXPress" of axItem
                return "pressed " & fragment
              end if
            end if
          end repeat
        end if
      end repeat
    end tell
  end tell
  error "control signal not found: " & fragment
end run
APPLESCRIPT
    local osascript_pid=$!
    if wait_for_osascript_attempt "$osascript_pid"; then
      cat "$attempt_output"
      rm -f "$attempt_output"
      return 0
    fi
    rm -f "$attempt_output"
    ax_process_matches_identity "$app_pid" "$APP_BINARY" "$app_identity" || return 1
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: failed to press control in AX tree: $fragment" >&2
      return 1
    fi
    sleep 1
  done
}

waitForControlEnabledState() {
  local fragment="$1"
  local expected_enabled="$2"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while true; do
    ax_process_matches_identity "$app_pid" "$APP_BINARY" "$app_identity" || return 1
    local attempt_output="$tmp_dir/control-state.$$.out"
    /usr/bin/osascript - "$app_pid" "$fragment" "$expected_enabled" <<'APPLESCRIPT' >"$attempt_output" 2>&1 &
on run argv
  set appPID to (item 1 of argv) as integer
  set fragment to item 2 of argv
  set expectedEnabled to item 3 of argv
  tell application "System Events"
    set matchingProcesses to application processes whose unix id is appPID
    if (count of matchingProcesses) is 0 then error "pid-owned process missing"
    set targetProcess to item 1 of matchingProcesses
    tell targetProcess
      repeat with windowIndex from 1 to count of windows
        set currentWindow to window windowIndex
        set windowName to ""
        try
          set windowName to name of currentWindow as text
        end try
        if windowName is "Voice Command" then
          set axItems to entire contents of currentWindow
          repeat with axItem in axItems
            set itemRole to ""
            try
              set itemRole to role of axItem as text
            end try
            if itemRole is "AXButton" then
              set itemIdentifier to ""
              try
                set itemIdentifier to value of attribute "AXIdentifier" of axItem as text
              end try
              if itemIdentifier contains fragment then
                set isEnabled to enabled of axItem as boolean
                if (expectedEnabled is "true" and isEnabled) or (expectedEnabled is "false" and not isEnabled) then
                  return "matched"
                end if
                error "control enabled state did not match"
              end if
            end if
          end repeat
        end if
      end repeat
    end tell
  end tell
  error "control signal not found: " & fragment
end run
APPLESCRIPT
    local osascript_pid=$!
    if wait_for_osascript_attempt "$osascript_pid"; then
      rm -f "$attempt_output"
      return 0
    fi
    rm -f "$attempt_output"
    ax_process_matches_identity "$app_pid" "$APP_BINARY" "$app_identity" || return 1
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: control '$fragment' did not reach enabled=$expected_enabled" >&2
      return 1
    fi
    sleep 1
  done
}

waitForTextContaining() {
  local fragment="$1"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while true; do
    ax_process_matches_identity "$app_pid" "$APP_BINARY" "$app_identity" || return 1
    local attempt_output="$tmp_dir/wait-text.$$.out"
    /usr/bin/osascript - "$app_pid" "$fragment" <<'APPLESCRIPT' >"$attempt_output" 2>&1 &
on run argv
  set appPID to (item 1 of argv) as integer
  set fragment to item 2 of argv
  tell application "System Events"
    set matchingProcesses to application processes whose unix id is appPID
    if (count of matchingProcesses) is 0 then error "pid-owned process missing"
    set targetProcess to item 1 of matchingProcesses
    tell targetProcess
      repeat with windowIndex from 1 to count of windows
        set currentWindow to window windowIndex
        set windowName to ""
        try
          set windowName to name of currentWindow as text
        end try
        if windowName is "Voice Command" then
          set axItems to entire contents of currentWindow
          repeat with axItem in axItems
            set itemName to ""
            set itemValue to ""
            set itemDescription to ""
            set itemHelp to ""
            try
              set itemName to name of axItem as text
            end try
            try
              set itemValue to value of axItem as text
            end try
            try
              set itemDescription to description of axItem as text
            end try
            try
              set itemHelp to value of attribute "AXHelp" of axItem as text
            end try
            set signalText to itemName & " " & itemValue & " " & itemDescription & " " & itemHelp
            if signalText contains fragment then return "found"
          end repeat
        end if
      end repeat
    end tell
  end tell
  error "text not found: " & fragment
end run
APPLESCRIPT
    local osascript_pid=$!
    if wait_for_osascript_attempt "$osascript_pid"; then
      rm -f "$attempt_output"
      return 0
    fi
    rm -f "$attempt_output"
    ax_process_matches_identity "$app_pid" "$APP_BINARY" "$app_identity" || return 1
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: Voice Command window did not expose text: $fragment" >&2
      return 1
    fi
    sleep 1
  done
}

waitForVoiceWindowSize() {
  local expected_width="$1"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while true; do
    ax_process_matches_identity "$app_pid" "$APP_BINARY" "$app_identity" || return 1
    local attempt_output="$tmp_dir/window-size.$$.out"
    /usr/bin/osascript - "$app_pid" "$expected_width" "$WINDOW_HEIGHT" <<'APPLESCRIPT' >"$attempt_output" 2>&1 &
on run argv
  set appPID to (item 1 of argv) as integer
  set expectedWidth to (item 2 of argv) as integer
  set requestedHeight to (item 3 of argv) as integer
  tell application "System Events"
    set matchingProcesses to application processes whose unix id is appPID
    if (count of matchingProcesses) is 0 then error "pid-owned process missing"
    set targetProcess to item 1 of matchingProcesses
    tell targetProcess
      repeat with currentWindow in windows
        try
          if (name of currentWindow as text) is "Voice Command" then
            set currentSize to size of currentWindow
            if item 1 of currentSize is expectedWidth and item 2 of currentSize is greater than or equal to requestedHeight then return "matched"
          end if
        end try
      end repeat
    end tell
  end tell
  error "Voice window size did not match"
end run
APPLESCRIPT
    local osascript_pid=$!
    if wait_for_osascript_attempt "$osascript_pid"; then
      rm -f "$attempt_output"
      return 0
    fi
    rm -f "$attempt_output"
    ax_process_matches_identity "$app_pid" "$APP_BINARY" "$app_identity" || return 1
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: Voice window did not settle at width ${expected_width}" >&2
      return 1
    fi
    sleep 1
  done
}

run_voice_readiness_matrix() {
  local locale="$1"
  local width="$2"
  local record_label
  local hands_free_label
  local provider_label
  local privacy_label

  case "$locale" in
    english)
      record_label="Record once"
      hands_free_label="Hands-free mode"
      provider_label="Speech provider: OpenAI Transcribe"
      privacy_label="Audio is processed by the selected speech-to-text provider only while Hands-free mode is listening."
      ;;
    japanese)
      record_label="1回録音"
      hands_free_label="ハンズフリーモード"
      provider_label="音声認識プロバイダー: OpenAI Transcribe"
      privacy_label="音声はハンズフリーモードで待ち受けている間だけ、選択中の音声認識プロバイダーで処理されます。"
      ;;
    *)
      echo "BLOCKER: unsupported Voice runtime locale: $locale" >&2
      return 2
      ;;
  esac

  launch_app_for_voice_review "$locale" "$width"
  waitForVoiceWindowSize "$width"
  waitForTextContaining "$record_label"
  waitForTextContaining "$hands_free_label"
  waitForTextContaining "$provider_label"
  waitForTextContaining "$privacy_label"
  setTextAreaContaining "voice-command-input" "   "
  waitForControlEnabledState "voice-command-generate-plan" "false"
  setTextAreaContaining "voice-command-input" "Create a task called Runtime Voice Review Smoke."
  waitForControlEnabledState "voice-command-generate-plan" "true"
  printf "OK: %s Voice readiness verified at width %s\n" "$locale" "$width"
}

sqlite_scalar() {
  local query="$1"
  "$SQLITE3" "$database_path" "$query"
}

wait_for_sql_value() {
  local expected="$1"
  local label="$2"
  local query="$3"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local value=""

  while true; do
    value="$(sqlite_scalar "$query" 2>/dev/null || true)"
    if [[ "$value" == "$expected" ]]; then
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: $label expected '$expected' but got '${value:-<empty>}'" >&2
      echo "query: $query" >&2
      return 1
    fi
    sleep 1
  done
}

verify_sql_value() {
  local expected="$1"
  local label="$2"
  local query="$3"
  local value
  value="$(sqlite_scalar "$query")"
  if [[ "$value" != "$expected" ]]; then
    echo "BLOCKER: $label expected '$expected' but got '${value:-<empty>}'" >&2
    echo "query: $query" >&2
    return 1
  fi
}

seed_daily_planning_task() {
  "$SQLITE3" "$database_path" <<'SQL'
INSERT INTO projects (title, status, priority, deadline, workspace_path, tags_json, source_command, created_at, updated_at)
VALUES ('Runtime Daily Planning Project', 'active', 'high', NULL, NULL, '[]', 'runtime-voice-review-smoke', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
INSERT INTO tasks (project_id, title, status, detail, due_at, completed_at, priority, source_command, created_at, updated_at)
VALUES (last_insert_rowid(), 'Runtime Daily Planning Recommended', 'planned', 'Seeded for local Daily Planning voice queue smoke', '2026-01-01T09:00:00Z', NULL, 'high', 'runtime-voice-review-smoke', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
SQL
  daily_planning_seed_task_id="$(sqlite_scalar "SELECT id FROM tasks WHERE title='Runtime Daily Planning Recommended' AND source_command='runtime-voice-review-smoke' ORDER BY id DESC LIMIT 1;")"
  if [[ -z "$daily_planning_seed_task_id" ]]; then
    echo "BLOCKER: daily planning seed task id was not written" >&2
    return 1
  fi
  wait_for_sql_value \
    "1" \
    "daily planning seed task" \
    "SELECT count(*) FROM tasks WHERE title='Runtime Daily Planning Recommended' AND source_command='runtime-voice-review-smoke';"
  daily_planning_seed_project_count="$(sqlite_scalar "SELECT count(*) FROM projects;")"
  if [[ -z "$daily_planning_seed_project_count" ]]; then
    echo "BLOCKER: daily planning seed project baseline was not readable" >&2
    return 1
  fi
}

printf "== Runtime voice review smoke ==\n"
./script/build_and_run.sh --build-only

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "BLOCKER: app bundle not found after build: $APP_BUNDLE" >&2
  exit 2
fi

if [[ ! -x "$APP_BINARY" ]]; then
  echo "BLOCKER: app binary not found or not executable after build: $APP_BINARY" >&2
  exit 2
fi

run_voice_readiness_matrix japanese 1024
run_voice_readiness_matrix english 1024
planning_initial_project_count="$(sqlite_scalar "SELECT count(*) FROM projects;")"
if [[ -z "$planning_initial_project_count" ]]; then
  echo "BLOCKER: initial project count before planning was not readable" >&2
  exit 2
fi
printf "OK: Generate Plan stayed disabled for whitespace and enabled for a valid draft\n"
pressControlContaining "voice-command-generate-plan"
waitForTextContaining "The AI provider rejected the configured API key."

wait_for_sql_value "1" "planning audit started" "SELECT count(*) FROM audit_logs WHERE category='planning' AND action='generate_plan' AND status='started';"
wait_for_sql_value "1" "planning audit failed" "SELECT count(*) FROM audit_logs WHERE category='planning' AND action='generate_plan' AND status='failed' AND metadata_json LIKE '%The AI provider rejected the configured API key.%';"
verify_sql_value "0" "planning audit succeeded" "SELECT count(*) FROM audit_logs WHERE category='planning' AND action='generate_plan' AND status='succeeded';"
verify_sql_value "0" "task writes before approval" "SELECT count(*) FROM tasks;"
verify_sql_value "$planning_initial_project_count" "project count unchanged after rejected planning" "SELECT count(*) FROM projects;"
verify_sql_value "0" "review execution before approval" "SELECT count(*) FROM audit_logs WHERE category='review' OR action LIKE 'execution.%';"

printf "OK: runtime voice review smoke verified fail-closed planning audit and no pre-approval writes\n"

seed_daily_planning_task
setTextAreaContaining "voice-command-input" "Open Today Review and start the recommended task"
pressControlContaining "voice-command-generate-plan"
wait_for_sql_value \
  "1" \
  "daily planning Assistant Queue draft" \
  "SELECT count(*) FROM assistant_queue_items WHERE id LIKE 'action-plan:daily-planning:%:startRecommended:task:${daily_planning_seed_task_id}' AND payload_kind='action_plan' AND state='waitingReview' AND risk_level='write' AND source_transcript='Open Today Review and start the recommended task' AND approval_json IS NULL;"
verify_sql_value \
  "1" \
  "daily planning task remains planned before approval" \
  "SELECT count(*) FROM tasks WHERE title='Runtime Daily Planning Recommended' AND source_command='runtime-voice-review-smoke' AND status='planned';"
verify_sql_value \
  "1" \
  "no extra daily planning tasks before approval" \
  "SELECT count(*) FROM tasks;"
verify_sql_value \
  "1" \
  "no extra daily planning projects before approval" \
  "SELECT count(*) FROM projects WHERE source_command='runtime-voice-review-smoke';"
verify_sql_value \
  "$daily_planning_seed_project_count" \
  "total project count unchanged after daily planning handoff" \
  "SELECT count(*) FROM projects;"
verify_sql_value \
  "1" \
  "only one daily planning queue draft before approval" \
  "SELECT count(*) FROM assistant_queue_items WHERE id LIKE 'action-plan:daily-planning:%';"
verify_sql_value \
  "0" \
  "daily planning review execution before approval" \
  "SELECT count(*) FROM audit_logs WHERE category='review' OR action LIKE 'execution.%';"
verify_sql_value \
  "1" \
  "planning audit did not start again for local Daily Planning handoff" \
  "SELECT count(*) FROM audit_logs WHERE category='planning' AND action='generate_plan' AND status='started';"
verify_sql_value \
  "1" \
  "planning audit failure count unchanged after local Daily Planning handoff" \
  "SELECT count(*) FROM audit_logs WHERE category='planning' AND action='generate_plan' AND status='failed';"
verify_sql_value \
  "0" \
  "planning audit success count unchanged after local Daily Planning handoff" \
  "SELECT count(*) FROM audit_logs WHERE category='planning' AND action='generate_plan' AND status='succeeded';"

setTextAreaContaining "voice-command-input" "Open Today Review and move the recommended task to today"
pressControlContaining "voice-command-generate-plan"
wait_for_sql_value \
  "1" \
  "daily planning move-to-today Assistant Queue draft" \
  "SELECT count(*) FROM assistant_queue_items WHERE id LIKE 'action-plan:daily-planning:%:moveRecommendedDueDateToToday:task:${daily_planning_seed_task_id}' AND payload_kind='action_plan' AND state='waitingReview' AND risk_level='write' AND source_transcript='Open Today Review and move the recommended task to today' AND approval_json IS NULL;"
verify_sql_value \
  "1" \
  "daily planning task due date remains unchanged before move-to-today approval" \
  "SELECT count(*) FROM tasks WHERE id=${daily_planning_seed_task_id} AND due_at='2026-01-01T09:00:00Z';"
verify_sql_value \
  "1" \
  "no extra daily planning tasks before move-to-today approval" \
  "SELECT count(*) FROM tasks;"
verify_sql_value \
  "1" \
  "no extra daily planning projects before move-to-today approval" \
  "SELECT count(*) FROM projects WHERE source_command='runtime-voice-review-smoke';"
verify_sql_value \
  "$daily_planning_seed_project_count" \
  "total project count unchanged after move-to-today daily planning handoff" \
  "SELECT count(*) FROM projects;"
verify_sql_value \
  "2" \
  "two daily planning queue drafts before approval" \
  "SELECT count(*) FROM assistant_queue_items WHERE id LIKE 'action-plan:daily-planning:%';"
verify_sql_value \
  "0" \
  "move-to-today review execution before approval" \
  "SELECT count(*) FROM audit_logs WHERE category='review' OR action LIKE 'execution.%';"
verify_sql_value \
  "1" \
  "planning audit did not start again for move-to-today local Daily Planning handoff" \
  "SELECT count(*) FROM audit_logs WHERE category='planning' AND action='generate_plan' AND status='started';"

# Defer and split are write-capable recommendations, so this smoke verifies
# they only create Assistant Queue drafts and leave task/project rows unchanged
# until the user approves the queued ActionPlan.
setTextAreaContaining "voice-command-input" "Open Today Review and defer the recommended task to tomorrow"
pressControlContaining "voice-command-generate-plan"
wait_for_sql_value \
  "1" \
  "daily planning defer Assistant Queue draft" \
  "SELECT count(*) FROM assistant_queue_items WHERE id LIKE 'action-plan:daily-planning:%:deferRecommendedToTomorrow:task:${daily_planning_seed_task_id}' AND payload_kind='action_plan' AND state='waitingReview' AND risk_level='write' AND source_transcript='Open Today Review and defer the recommended task to tomorrow' AND approval_json IS NULL;"
verify_sql_value \
  "1" \
  "daily planning task due date remains unchanged before defer approval" \
  "SELECT count(*) FROM tasks WHERE id=${daily_planning_seed_task_id} AND due_at='2026-01-01T09:00:00Z';"
verify_sql_value \
  "1" \
  "no extra daily planning tasks before defer approval" \
  "SELECT count(*) FROM tasks;"
verify_sql_value \
  "1" \
  "no extra daily planning projects before defer approval" \
  "SELECT count(*) FROM projects WHERE source_command='runtime-voice-review-smoke';"
verify_sql_value \
  "$daily_planning_seed_project_count" \
  "total project count unchanged after defer daily planning handoff" \
  "SELECT count(*) FROM projects;"
verify_sql_value \
  "3" \
  "three daily planning queue drafts before approval" \
  "SELECT count(*) FROM assistant_queue_items WHERE id LIKE 'action-plan:daily-planning:%';"
verify_sql_value \
  "0" \
  "defer review execution before approval" \
  "SELECT count(*) FROM audit_logs WHERE category='review' OR action LIKE 'execution.%';"
verify_sql_value \
  "1" \
  "planning audit did not start again for defer local Daily Planning handoff" \
  "SELECT count(*) FROM audit_logs WHERE category='planning' AND action='generate_plan' AND status='started';"

setTextAreaContaining "voice-command-input" "Open Today Review and split the recommended task"
pressControlContaining "voice-command-generate-plan"
wait_for_sql_value \
  "1" \
  "daily planning split Assistant Queue draft" \
  "SELECT count(*) FROM assistant_queue_items WHERE id LIKE 'action-plan:daily-planning:%:splitRecommendedTask:task:${daily_planning_seed_task_id}' AND payload_kind='action_plan' AND state='waitingReview' AND risk_level='write' AND source_transcript='Open Today Review and split the recommended task' AND approval_json IS NULL;"
verify_sql_value \
  "0" \
  "no split follow-up tasks before split approval" \
  "SELECT count(*) FROM tasks WHERE source_command LIKE 'Daily Planning Review split from task %' OR title LIKE 'Runtime Daily Planning Recommended - %';"
verify_sql_value \
  "1" \
  "daily planning seed task unchanged before split approval" \
  "SELECT count(*) FROM tasks WHERE id=${daily_planning_seed_task_id} AND title='Runtime Daily Planning Recommended' AND status='planned' AND due_at='2026-01-01T09:00:00Z' AND source_command='runtime-voice-review-smoke';"
verify_sql_value \
  "1" \
  "no extra daily planning tasks before split approval" \
  "SELECT count(*) FROM tasks;"
verify_sql_value \
  "1" \
  "no extra daily planning projects before split approval" \
  "SELECT count(*) FROM projects WHERE source_command='runtime-voice-review-smoke';"
verify_sql_value \
  "$daily_planning_seed_project_count" \
  "total project count unchanged after split daily planning handoff" \
  "SELECT count(*) FROM projects;"
verify_sql_value \
  "4" \
  "four daily planning queue drafts before approval" \
  "SELECT count(*) FROM assistant_queue_items WHERE id LIKE 'action-plan:daily-planning:%';"
verify_sql_value \
  "0" \
  "split review execution before approval" \
  "SELECT count(*) FROM audit_logs WHERE category='review' OR action LIKE 'execution.%';"
verify_sql_value \
  "1" \
  "planning audit did not start again for split local Daily Planning handoff" \
  "SELECT count(*) FROM audit_logs WHERE category='planning' AND action='generate_plan' AND status='started';"

printf "OK: runtime voice review smoke verified local Daily Planning queue handoffs\n"
