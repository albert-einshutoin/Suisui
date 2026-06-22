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
TIMEOUT_SECONDS="${SOLOPM_HEADER_LAYOUT_SMOKE_TIMEOUT_SECONDS:-20}"
OUTPUT_DIR="${SOLOPM_HEADER_LAYOUT_SMOKE_OUTPUT_DIR:-$ROOT_DIR/.tmp/project-board-header-layout-smoke}"
WINDOW_NAME="${SOLOPM_PROJECT_BOARD_WINDOW_NAME:-SoloPM}"

if [[ ! "$TIMEOUT_SECONDS" =~ ^[0-9]+$ || "$TIMEOUT_SECONDS" -lt 1 ]]; then
  echo "SOLOPM_HEADER_LAYOUT_SMOKE_TIMEOUT_SECONDS must be a positive integer" >&2
  exit 2
fi

cd "$ROOT_DIR"
mkdir -p "$OUTPUT_DIR"

window_id=""
window_x=""
window_y=""
window_width=""
window_height=""

terminate_app() {
  /usr/bin/osascript - "$APP_NAME" <<'APPLESCRIPT' >/dev/null 2>&1 || true
on run argv
  tell application (item 1 of argv) to quit
end run
APPLESCRIPT
}

read_window_metadata() {
  local output
  output="$(
    SOLOPM_WINDOW_OWNER="$APP_NAME" \
    SOLOPM_WINDOW_NAME="$WINDOW_NAME" \
    /usr/bin/swift "$ROOT_DIR/script/ui_evidence_window_metadata.swift"
  )"
  read -r window_id window_x window_y window_width window_height <<<"$output"
}

wait_for_window_metadata() {
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while true; do
    if read_window_metadata >/dev/null 2>&1; then
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: Project Board window metadata was not available within ${TIMEOUT_SECONDS}s" >&2
      return 1
    fi
    sleep 1
  done
}

capture_window() {
  local label="$1"
  wait_for_window_metadata
  local screenshot_path="$OUTPUT_DIR/project-board-${label}.png"
  /usr/sbin/screencapture -x -l "$window_id" "$screenshot_path"
  if [[ ! -s "$screenshot_path" ]]; then
    echo "BLOCKER: screenshot was not written for $label at $screenshot_path" >&2
    return 1
  fi
  printf "OK: captured %s header layout screenshot (%s)\n" "$label" "$screenshot_path"
}

toolbar_items() {
  /usr/bin/osascript - "$APP_NAME" <<'APPLESCRIPT'
on run argv
  set appName to item 1 of argv
  tell application "System Events"
    if not (exists process appName) then error "process missing"
    tell process appName
      if not (exists window 1) then error "window missing"
      if not (exists toolbar 1 of window 1) then error "toolbar missing"
      set outputLines to {}
      repeat with toolbarItem in UI elements of toolbar 1 of window 1
        set identifierValue to ""
        try
          set identifierValue to value of attribute "AXIdentifier" of toolbarItem
        end try
        set roleValue to ""
        try
          set roleValue to role of toolbarItem
        end try
        -- SwiftUI toolbar Menu is exposed as an anonymous AXGroup on macOS;
        -- treat that single group as the Integrations action so the smoke
        -- verifies its real screen position instead of relying on source text.
        if (identifierValue is missing value or identifierValue is "") and roleValue is "AXGroup" then
          set identifierValue to "project-board-integrations-menu"
        end if
        if identifierValue is not missing value and identifierValue is not "" then
          set itemPosition to position of toolbarItem
          set itemSize to size of toolbarItem
          set end of outputLines to identifierValue & tab & (item 1 of itemPosition as text) & tab & (item 2 of itemPosition as text) & tab & (item 1 of itemSize as text) & tab & (item 2 of itemSize as text)
        end if
      end repeat
      set AppleScript's text item delimiters to linefeed
      return outputLines as text
    end tell
  end tell
end run
APPLESCRIPT
}

button_x() {
  local identifier="$1"
  awk -F $'\t' -v wanted="$identifier" '$1 == wanted { print $2; found = 1 } END { if (!found) exit 1 }' "$button_state_file"
}

assert_button_present() {
  local identifier="$1"
  if ! awk -F $'\t' -v wanted="$identifier" '$1 == wanted { found = 1 } END { exit(found ? 0 : 1) }' "$button_state_file"; then
    echo "BLOCKER: toolbar button '$identifier' was not exposed through AX" >&2
    echo "Observed toolbar buttons:" >&2
    cat "$button_state_file" >&2
    return 1
  fi
}

wait_for_toolbar_buttons() {
  local label="$1"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  button_state_file="$OUTPUT_DIR/toolbar-${label}.tsv"
  while true; do
    if toolbar_items >"$button_state_file" 2>"$OUTPUT_DIR/toolbar-${label}.err"; then
      if [[ -s "$button_state_file" ]]; then
        return 0
      fi
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: toolbar AX buttons were not available for $label within ${TIMEOUT_SECONDS}s" >&2
      cat "$OUTPUT_DIR/toolbar-${label}.err" >&2 || true
      return 1
    fi
    sleep 1
  done
}

assert_action_buttons_are_trailing() {
  local label="$1"
  wait_for_window_metadata
  wait_for_toolbar_buttons "$label"

  assert_button_present "project-board-sidebar-toggle"
  assert_button_present "project-board-integrations-menu"
  assert_button_present "project-board-voice-command"
  assert_button_present "project-board-settings-link"
  assert_button_present "project-board-terminal-toggle"

  local sidebar_x integrations_x voice_x settings_x terminal_x trailing_threshold
  sidebar_x="$(button_x "project-board-sidebar-toggle")"
  integrations_x="$(button_x "project-board-integrations-menu")"
  voice_x="$(button_x "project-board-voice-command")"
  settings_x="$(button_x "project-board-settings-link")"
  terminal_x="$(button_x "project-board-terminal-toggle")"
  trailing_threshold=$((window_x + window_width - 240))

  if (( sidebar_x >= integrations_x )); then
    echo "BLOCKER: sidebar toggle is not left of toolbar actions for $label" >&2
    cat "$button_state_file" >&2
    return 1
  fi

  if (( integrations_x < trailing_threshold || voice_x < trailing_threshold || settings_x < trailing_threshold || terminal_x < trailing_threshold )); then
    echo "BLOCKER: toolbar action buttons are not trailing for $label" >&2
    echo "window=($window_x,$window_y ${window_width}x${window_height}) threshold=$trailing_threshold" >&2
    cat "$button_state_file" >&2
    return 1
  fi

  printf "OK: toolbar actions are trailing for %s\n" "$label"
}

click_sidebar_toggle() {
  /usr/bin/osascript - "$APP_NAME" <<'APPLESCRIPT' >/dev/null
on run argv
  set appName to item 1 of argv
  tell application "System Events"
    tell process appName
      tell toolbar 1 of window 1
        click (first button whose value of attribute "AXIdentifier" is "project-board-sidebar-toggle")
      end tell
    end tell
  end tell
end run
APPLESCRIPT
}

trap terminate_app EXIT

SOLOPM_VERIFY_TIMEOUT_SECONDS="$TIMEOUT_SECONDS" ./script/build_and_run.sh --verify

capture_window "sidebar-visible"
assert_action_buttons_are_trailing "sidebar-visible"

click_sidebar_toggle
sleep 1
capture_window "sidebar-hidden"
assert_action_buttons_are_trailing "sidebar-hidden"

click_sidebar_toggle
sleep 1
capture_window "sidebar-restored"
assert_action_buttons_are_trailing "sidebar-restored"

printf "OK: Project Board header layout smoke passed\n"
