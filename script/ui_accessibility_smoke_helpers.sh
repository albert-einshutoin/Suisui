#!/usr/bin/env bash
set -euo pipefail

# Shared accessibility helpers for smoke scripts.
# Keep the shared automation contract in one place so runtime smoke flows stay fast and
# consistent while avoiding duplicated AppleScript/Swift marker glue logic in each script.

ax_wait_for_visible_window() {
  local app_name="$1"
  local timeout_seconds="$2"
  local bundle_identifier="${3:-}"
  local deadline=$((SECONDS + timeout_seconds))
  local window_count=""
  local osascript_status=1

  while true; do
    set +e
    window_count="$(
      /usr/bin/osascript - "$app_name" "$bundle_identifier" <<'APPLESCRIPT' 2>/dev/null
on run argv
  set appName to item 1 of argv
  set bundleID to item 2 of argv
  tell application "System Events"
    set targetProcess to missing value
    if exists process appName then
      tell process appName
        if (count of windows) > 0 then
          set targetProcess to it
        end if
      end tell
    end if
    if targetProcess is missing value and bundleID is not "" then
      set appMatches to application processes whose bundle identifier is bundleID
      repeat with appProcess in appMatches
        if (count of windows of appProcess) > 0 then
          set targetProcess to appProcess
          exit repeat
        end if
      end repeat
    end if
    if targetProcess is missing value then
      return "0"
    end if
    tell targetProcess
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
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      return 1
    fi
    sleep 1
  done
}

ax_wait_for_visible_windows() {
  ax_wait_for_visible_window "$@"
}

ax_click_sidebar_destination() {
  local app_name="$1"
  local destination_identifier="$2"
  local destination_label="$3"
  /usr/bin/osascript - "$app_name" "$destination_identifier" "$destination_label" <<'APPLESCRIPT' >/dev/null
on pressDestination(uiElement, destinationIdentifier, destinationLabel)
  tell application "System Events"
    set identifierValue to ""
    try
      set identifierValue to value of attribute "AXIdentifier" of uiElement
    end try
    set nameValue to ""
    try
      set nameValue to name of uiElement
    end try
    if identifierValue is destinationIdentifier or nameValue starts with destinationLabel then
      try
        perform action "AXPress" of uiElement
        return true
      end try
      try
        click uiElement
        return true
      end try
    end if
    try
      repeat with childElement in UI elements of uiElement
        if my pressDestination(childElement, destinationIdentifier, destinationLabel) then return true
      end repeat
    end try
  end tell
  return false
end pressDestination

on run argv
  set appName to item 1 of argv
  set destinationIdentifier to item 2 of argv
  set destinationLabel to item 3 of argv
  tell application "System Events"
    if not (exists process appName) then error "process missing"
    tell process appName
      if not (exists window 1) then error "window missing"
      set frontmost to true
      try
        perform action "AXRaise" of window 1
      end try
      if not my pressDestination(window 1, destinationIdentifier, destinationLabel) then error "destination missing: " & destinationIdentifier
    end tell
  end tell
end run
APPLESCRIPT
}

ax_wait_for_ax_identifier() {
  local app_name="$1"
  local identifier="$2"
  local timeout_seconds="$3"
  local root_dir="$4"
  local probe_file="$5"
  # Optional arguments retain the established five-argument API for existing
  # smoke scripts while allowing new launch-owned checks to prove their AX
  # result belongs to the process they started.
  local text_marker="${6:-}"
  local app_pid="${7:-}"
  local ax_arguments=("$app_name" "$identifier" "$text_marker")
  if [[ -n "$app_pid" ]]; then
    ax_arguments+=("$app_pid")
  fi
  local deadline=$((SECONDS + timeout_seconds))

  while true; do
    if /usr/bin/swift "$root_dir/script/ui_evidence_ax_marker_check.swift" "${ax_arguments[@]}" \
      >"$probe_file" 2>"$probe_file.err"; then
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      return 1
    fi
    sleep 1
  done
}
