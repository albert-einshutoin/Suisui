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
TIMEOUT_SECONDS="${SOLOPM_RUNTIME_SETTINGS_SAVE_TIMEOUT_SECONDS:-30}"
KEEP_HOME="${SOLOPM_RUNTIME_SETTINGS_SAVE_KEEP_HOME:-0}"
WINDOW_WIDTH="${SOLOPM_RUNTIME_SETTINGS_SAVE_WINDOW_WIDTH:-760}"
WINDOW_HEIGHT="${SOLOPM_RUNTIME_SETTINGS_SAVE_WINDOW_HEIGHT:-900}"

if [[ ! "$TIMEOUT_SECONDS" =~ ^[0-9]+$ || "$TIMEOUT_SECONDS" -lt 1 ]]; then
  echo "SOLOPM_RUNTIME_SETTINGS_SAVE_TIMEOUT_SECONDS must be a positive integer" >&2
  exit 2
fi

cd "$ROOT_DIR"
mkdir -p "$ROOT_DIR/.tmp"
tmp_dir="$(mktemp -d "$ROOT_DIR/.tmp/solopm-runtime-settings-save.XXXXXX")"
settings_home="$tmp_dir/home"
database_path="$tmp_dir/SoloPM-runtime-settings-save.sqlite"
settings_suite_name="$BUNDLE_IDENTIFIER.runtime-settings-save.$(/usr/bin/uuidgen | tr '[:upper:]' '[:lower:]')"
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
  if [[ "$KEEP_HOME" != "1" ]]; then
    /usr/bin/defaults delete "$settings_suite_name" >/dev/null 2>&1 || true
    rm -rf "$tmp_dir"
  else
    /usr/bin/defaults export "$settings_suite_name" "$settings_home/app-settings.plist" >/dev/null 2>&1 || true
    /usr/bin/defaults delete "$settings_suite_name" >/dev/null 2>&1 || true
    printf "INFO: kept runtime settings save home at %s\n" "$settings_home"
    printf "INFO: exported runtime settings store to %s\n" "$settings_home/app-settings.plist"
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

set_settings_window_size() {
  local width="$1"
  local height="$2"
  # The settings evidence window starts compact. Resize it through AX so the
  # Task Automation controls and Save button are visible without scrolling.
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
          perform action "AXRaise" of currentWindow
        end try
        try
          set size of currentWindow to {targetWidth, targetHeight}
        end try
      end repeat
    end tell
  end tell
end run
APPLESCRIPT
  sleep 1
}

launch_app_for_settings() {
  terminate_app
  mkdir -p "$settings_home/Library/Preferences"
  HOME="$settings_home" \
    SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1 \
    SOLOPM_DATABASE_PATH="$database_path" \
    SOLOPM_APP_SETTINGS_SUITE_NAME="$settings_suite_name" \
    SOLOPM_OPEN_SETTINGS_ON_LAUNCH=1 \
    SOLOPM_SETTINGS_EVIDENCE_TAB=AI \
    "$APP_BINARY" &
  app_pid=$!
  wait_for_app_process
  activate_app
  wait_for_visible_windows
  set_settings_window_size "$WINDOW_WIDTH" "$WINDOW_HEIGHT"
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

enableCheckboxContaining() {
  local fragment="$1"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local output=""

  while true; do
    set +e
    output="$(/usr/bin/osascript - "$APP_NAME" "$fragment" <<'APPLESCRIPT' 2>/dev/null
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
          if itemRole is "AXCheckBox" or itemRole is "AXSwitch" then
            set itemName to ""
            set itemTitle to ""
            set itemDescription to ""
            set itemHelp to ""
            set itemIdentifier to ""
            set itemValue to ""
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
            try
              set itemValue to value of axItem as text
            end try
            set signalText to itemIdentifier & " " & itemName & " " & itemTitle & " " & itemDescription & " " & itemHelp
            if signalText contains fragment then
              if itemValue is "1" or itemValue is "true" then
                return "enabled " & fragment
              end if
              set isEnabled to true
              try
                set isEnabled to enabled of axItem as boolean
              end try
              if isEnabled then
                perform action "AXPress" of axItem
                return "pressed " & fragment
              end if
            end if
          end if
        end repeat
      end repeat
    end tell
  end tell
  error "checkbox signal not found: " & fragment
end run
APPLESCRIPT
)"
    local osascript_status=$?
    set -e

    if [[ "$osascript_status" -eq 0 && "$output" == enabled* ]]; then
      printf '%s\n' "$output"
      return 0
    fi
    if [[ "$osascript_status" -eq 0 && "$output" == pressed* ]]; then
      sleep 1
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: failed to enable AX checkbox: $fragment" >&2
      return 1
    fi
    sleep 0.2
  done
}

verify_settings_saved() {
  HOME="$settings_home" \
    SOLOPM_SETTINGS_SMOKE_BUNDLE_IDENTIFIER="$settings_suite_name" \
    SOLOPM_SETTINGS_SMOKE_TIMEOUT_SECONDS="$TIMEOUT_SECONDS" \
    /usr/bin/swift "$ROOT_DIR/script/settings_save_smoke_check.swift"
}

printf "== Runtime settings save smoke ==\n"
./script/build_and_run.sh --build-only

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "BLOCKER: app bundle not found after build: $APP_BUNDLE" >&2
  exit 2
fi

if [[ ! -x "$APP_BINARY" ]]; then
  echo "BLOCKER: app binary not found or not executable after build: $APP_BINARY" >&2
  exit 2
fi

launch_app_for_settings
enableCheckboxContaining "settings-task-auto-execution-toggle"
pressControlContaining "settings-save-button"
verify_settings_saved

printf "OK: runtime settings save smoke enabled task automation and verified isolated UserDefaults\n"
