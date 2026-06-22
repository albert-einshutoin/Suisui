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
on appendIdentifiedElement(outputLines, uiElement, syntheticIdentifier)
  set identifierValue to syntheticIdentifier
  tell application "System Events"
    if identifierValue is equal to "" then
      try
        set identifierValue to value of attribute "AXIdentifier" of uiElement
      end try
    end if
    if identifierValue is equal to "" then
      set titleValue to ""
      try
        set titleValue to name of uiElement
      end try
      if titleValue is "Integrations" or titleValue is "連携" then
        set identifierValue to "project-board-integrations-menu"
      else if titleValue is "Voice Command" or titleValue is "音声コマンド" then
        set identifierValue to "project-board-voice-command"
      else if titleValue is "Settings" or titleValue is "設定" then
        set identifierValue to "project-board-settings-link"
      else if titleValue is "Terminal" or titleValue is "ターミナル" then
        set identifierValue to "project-board-terminal-toggle"
      end if
    end if
    if identifierValue is not equal to "" then
      set itemPosition to position of uiElement
      set itemSize to size of uiElement
      set end of outputLines to identifierValue & tab & (item 1 of itemPosition as text) & tab & (item 2 of itemPosition as text) & tab & (item 1 of itemSize as text) & tab & (item 2 of itemSize as text)
    end if
  end tell
  return outputLines
end appendIdentifiedElement

on collectIdentifiedElements(outputLines, uiElement)
  set outputLines to my appendIdentifiedElement(outputLines, uiElement, "")
  tell application "System Events"
    try
      repeat with childElement in UI elements of uiElement
        set outputLines to my collectIdentifiedElements(outputLines, childElement)
      end repeat
    end try
  end tell
  return outputLines
end collectIdentifiedElements

on run argv
  set appName to item 1 of argv
  tell application "System Events"
    if not (exists process appName) then error "process missing"
    tell process appName
      if not (exists window 1) then error "window missing"
      set outputLines to {}
      if (exists toolbar 1 of window 1) then
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
          if identifierValue is equal to "" and roleValue is "AXGroup" then
            set identifierValue to "project-board-integrations-menu"
          end if
          set outputLines to my appendIdentifiedElement(outputLines, toolbarItem, identifierValue)
        end repeat
      end if
      repeat with windowElement in UI elements of window 1
        set outputLines to my collectIdentifiedElements(outputLines, windowElement)
      end repeat
      set AppleScript's text item delimiters to linefeed
      return outputLines as text
    end tell
  end tell
end run
APPLESCRIPT
}

deduplicate_toolbar_items() {
  awk -F $'\t' '!seen[$1]++ { print }'
}

toolbar_items_deduplicated() {
  toolbar_items | deduplicate_toolbar_items
}

button_x() {
  local identifier="$1"
  awk -F $'\t' -v wanted="$identifier" '$1 == wanted { print $2; found = 1 } END { if (!found) exit 1 }' "$button_state_file"
}

button_width() {
  local identifier="$1"
  awk -F $'\t' -v wanted="$identifier" '$1 == wanted { print $4; found = 1 } END { if (!found) exit 1 }' "$button_state_file"
}

assert_button_present() {
  local identifier="$1"
  if ! awk -F $'\t' -v wanted="$identifier" '$1 == wanted { found = 1 } END { exit(found ? 0 : 1) }' "$button_state_file"; then
    echo "BLOCKER: header control '$identifier' was not exposed through AX" >&2
    echo "Observed header controls:" >&2
    cat "$button_state_file" >&2
    return 1
  fi
}

wait_for_toolbar_buttons() {
  local label="$1"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  button_state_file="$OUTPUT_DIR/toolbar-${label}.tsv"
  while true; do
    if toolbar_items_deduplicated >"$button_state_file" 2>"$OUTPUT_DIR/toolbar-${label}.err"; then
      if [[ -s "$button_state_file" ]]; then
        return 0
      fi
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: header AX controls were not available for $label within ${TIMEOUT_SECONDS}s" >&2
      cat "$OUTPUT_DIR/toolbar-${label}.err" >&2 || true
      return 1
    fi
    sleep 1
  done
}

assert_action_buttons_are_trailing() {
  local label="$1"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local sidebar_x integrations_x voice_x settings_x terminal_x terminal_width detail_x detail_width detail_right action_group_threshold terminal_right_threshold

  while true; do
    wait_for_window_metadata
    wait_for_toolbar_buttons "$label"

    assert_button_present "project-board-sidebar-toggle"
    assert_button_present "project-board-integrations-menu"
    assert_button_present "project-board-voice-command"
    assert_button_present "project-board-settings-link"
    assert_button_present "project-board-terminal-toggle"

    sidebar_x="$(button_x "project-board-sidebar-toggle")"
    integrations_x="$(button_x "project-board-integrations-menu")"
    voice_x="$(button_x "project-board-voice-command")"
    settings_x="$(button_x "project-board-settings-link")"
    terminal_x="$(button_x "project-board-terminal-toggle")"
    terminal_width="$(button_width "project-board-terminal-toggle")"
    detail_x="$(button_x "project-board-detail")"
    detail_width="$(button_width "project-board-detail")"
    detail_right=$((detail_x + detail_width))
    action_group_threshold=$((detail_right - 420))
    terminal_right_threshold=$((detail_right - 16))

    if (( sidebar_x < integrations_x &&
          integrations_x < voice_x &&
          voice_x < settings_x &&
          settings_x < terminal_x &&
          integrations_x >= action_group_threshold &&
          terminal_x + terminal_width >= terminal_right_threshold )); then
      printf "OK: header actions are trailing for %s\n" "$label"
      return 0
    fi

    if [[ "$SECONDS" -ge "$deadline" ]]; then
      if (( sidebar_x >= integrations_x )); then
        echo "BLOCKER: sidebar toggle is not left of header actions for $label" >&2
      else
        echo "BLOCKER: header action controls are not trailing for $label" >&2
      fi
      echo "window=($window_x,$window_y ${window_width}x${window_height}) detailRight=$detail_right groupThreshold=$action_group_threshold terminalRightThreshold=$terminal_right_threshold" >&2
      cat "$button_state_file" >&2
      return 1
    fi

    sleep 0.1
  done
}

toolbar_position_signature() {
  awk -F $'\t' '
    $1 == "project-board-sidebar-toggle" ||
    $1 == "project-board-integrations-menu" ||
    $1 == "project-board-voice-command" ||
    $1 == "project-board-settings-link" ||
    $1 == "project-board-terminal-toggle" {
      print $1 ":" $2 ":" $3 ":" $4 ":" $5
    }
  ' "$1"
}

assert_toolbar_layout_is_stable() {
  local label="$1"
  local samples="${2:-5}"
  local baseline_file="$OUTPUT_DIR/toolbar-${label}-sample-0.tsv"
  local baseline_signature sample_file sample_signature

  if ! toolbar_items >"$baseline_file" 2>"$OUTPUT_DIR/toolbar-${label}-sample-0.err"; then
    echo "BLOCKER: header layout stability baseline failed after $label" >&2
    cat "$OUTPUT_DIR/toolbar-${label}-sample-0.err" >&2 || true
    return 1
  fi
  baseline_signature="$(toolbar_position_signature "$baseline_file")"

  for ((sample = 1; sample <= samples; sample += 1)); do
    sample_file="$OUTPUT_DIR/toolbar-${label}-sample-${sample}.tsv"
    if ! toolbar_items >"$sample_file" 2>"$OUTPUT_DIR/toolbar-${label}-sample-${sample}.err"; then
      echo "BLOCKER: header layout stability sample $sample failed after $label" >&2
      cat "$OUTPUT_DIR/toolbar-${label}-sample-${sample}.err" >&2 || true
      return 1
    fi

    sample_signature="$(toolbar_position_signature "$sample_file")"
    if [[ "$sample_signature" != "$baseline_signature" ]]; then
      echo "BLOCKER: header layout shifted after $label between immediate samples" >&2
      echo "baseline:" >&2
      cat "$baseline_file" >&2
      echo "sample $sample:" >&2
      cat "$sample_file" >&2
      return 1
    fi
    sleep 0.08
  done

  printf "OK: header layout stayed stable after %s\n" "$label"
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
assert_toolbar_layout_is_stable "sidebar-hidden-immediate" 5
capture_window "sidebar-hidden"
assert_action_buttons_are_trailing "sidebar-hidden"

click_sidebar_toggle
assert_toolbar_layout_is_stable "sidebar-restored-immediate" 5
capture_window "sidebar-restored"
assert_action_buttons_are_trailing "sidebar-restored"

printf "OK: Project Board header layout smoke passed\n"
