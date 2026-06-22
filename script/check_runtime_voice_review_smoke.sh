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
TIMEOUT_SECONDS="${SOLOPM_RUNTIME_VOICE_REVIEW_TIMEOUT_SECONDS:-35}"
KEEP_DATABASE="${SOLOPM_RUNTIME_VOICE_REVIEW_KEEP_DATABASE:-0}"
SQLITE3="${SQLITE3:-sqlite3}"
WINDOW_WIDTH="${SOLOPM_RUNTIME_VOICE_REVIEW_WINDOW_WIDTH:-760}"
WINDOW_HEIGHT="${SOLOPM_RUNTIME_VOICE_REVIEW_WINDOW_HEIGHT:-640}"

if [[ ! "$TIMEOUT_SECONDS" =~ ^[0-9]+$ || "$TIMEOUT_SECONDS" -lt 1 ]]; then
  echo "SOLOPM_RUNTIME_VOICE_REVIEW_TIMEOUT_SECONDS must be a positive integer" >&2
  exit 2
fi

if ! command -v "$SQLITE3" >/dev/null 2>&1; then
  echo "BLOCKER: sqlite3 is required for runtime voice review smoke" >&2
  exit 2
fi

cd "$ROOT_DIR"
mkdir -p "$ROOT_DIR/.tmp"
tmp_dir="$(mktemp -d "$ROOT_DIR/.tmp/solopm-runtime-voice-review.XXXXXX")"
database_path="$tmp_dir/SoloPM-runtime-voice-review.sqlite"
settings_suite_name="$BUNDLE_IDENTIFIER.runtime-voice-review.$(/usr/bin/uuidgen | tr '[:upper:]' '[:lower:]')"
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
  /usr/bin/defaults delete "$settings_suite_name" >/dev/null 2>&1 || true
  if [[ "$KEEP_DATABASE" != "1" ]]; then
    rm -rf "$tmp_dir"
  else
    printf "INFO: kept runtime voice review database at %s\n" "$database_path"
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

activate_app() {
  /usr/bin/osascript - "$APP_NAME" <<'APPLESCRIPT' >/dev/null 2>&1 &
on run argv
  set appName to item 1 of argv
  tell application "System Events"
    if not (exists process appName) then return "missing"
    tell process appName
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

wait_for_voice_window() {
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local window_found=""
  local osascript_status=1

  while true; do
    set +e
    window_found="$(/usr/bin/osascript - "$APP_NAME" <<'APPLESCRIPT' 2>/dev/null
on run argv
  set appName to item 1 of argv
  tell application "System Events"
    if not (exists process appName) then return "0"
    tell process appName
      repeat with windowIndex from 1 to count of windows
        try
          if (name of window windowIndex as text) is "Voice Command" then return "1"
        end try
      end repeat
    end tell
  end tell
  return "0"
end run
APPLESCRIPT
)"
    osascript_status=$?
    set -e

    if [[ "$osascript_status" -eq 0 && "$window_found" == "1" ]]; then
      return 0
    fi

    activate_app
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: $APP_NAME did not expose the Voice Command AX window within ${TIMEOUT_SECONDS}s" >&2
      return 1
    fi
    sleep 1
  done
}

set_voice_window_size() {
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
  sleep 1
}

launch_app_for_voice_review() {
  terminate_app
  SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1 \
    SOLOPM_DATABASE_PATH="$database_path" \
    SOLOPM_APP_SETTINGS_SUITE_NAME="$settings_suite_name" \
    SOLOPM_OPEN_VOICE_COMMAND_ON_LAUNCH=1 \
    "$APP_BINARY" &
  app_pid=$!
  wait_for_app_process
  activate_app
  wait_for_voice_window
  set_voice_window_size "$WINDOW_WIDTH" "$WINDOW_HEIGHT"
}

setTextAreaContaining() {
  local fragment="$1"
  local text_value="$2"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))

  while true; do
    if /usr/bin/osascript - "$APP_NAME" "$fragment" "$text_value" <<'APPLESCRIPT'
on run argv
  set appName to item 1 of argv
  set fragment to item 2 of argv
  set textValue to item 3 of argv
  tell application "System Events"
    if not (exists process appName) then error appName & " process is not visible to System Events"
    tell process appName
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
    then
      sleep 1
      return 0
    fi
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
    if /usr/bin/osascript - "$APP_NAME" "$fragment" <<'APPLESCRIPT'
on run argv
  set appName to item 1 of argv
  set fragment to item 2 of argv
  tell application "System Events"
    if not (exists process appName) then error appName & " process is not visible to System Events"
    tell process appName
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
    then
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: failed to press control in AX tree: $fragment" >&2
      return 1
    fi
    sleep 1
  done
}

waitForTextContaining() {
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
    then
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: Voice Command window did not expose text: $fragment" >&2
      return 1
    fi
    sleep 1
  done
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

launch_app_for_voice_review
setTextAreaContaining "voice-command-input" "Create a task called Runtime Voice Review Smoke."
pressControlContaining "voice-command-generate-plan"
waitForTextContaining "The AI provider rejected the configured API key."

wait_for_sql_value "1" "planning audit started" "SELECT count(*) FROM audit_logs WHERE category='planning' AND action='generate_plan' AND status='started';"
wait_for_sql_value "1" "planning audit failed" "SELECT count(*) FROM audit_logs WHERE category='planning' AND action='generate_plan' AND status='failed' AND metadata_json LIKE '%The AI provider rejected the configured API key.%';"
verify_sql_value "0" "planning audit succeeded" "SELECT count(*) FROM audit_logs WHERE category='planning' AND action='generate_plan' AND status='succeeded';"
verify_sql_value "0" "task writes before approval" "SELECT count(*) FROM tasks;"
verify_sql_value "0" "review execution before approval" "SELECT count(*) FROM audit_logs WHERE category='review' OR action LIKE 'execution.%';"

printf "OK: runtime voice review smoke verified fail-closed planning audit and no pre-approval writes\n"
