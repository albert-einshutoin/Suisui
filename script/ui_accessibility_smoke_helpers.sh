#!/usr/bin/env bash
set -euo pipefail

# Shared accessibility helpers for smoke scripts.
# Keep the shared automation contract in one place so runtime smoke flows stay fast and
# consistent while avoiding duplicated AppleScript/Swift marker glue logic in each script.

ax_process_matches_binary() {
  local app_pid="$1"
  local app_binary="$2"
  local process_command

  [[ "$app_pid" =~ ^[0-9]+$ && "$app_pid" -gt 0 ]] || return 1
  process_command="$(ps -p "$app_pid" -o command= 2>/dev/null)" || return 1
  process_command="${process_command#"${process_command%%[![:space:]]*}"}"
  case "$process_command" in
    "$app_binary"|"$app_binary "*) return 0 ;;
  esac
  return 1
}

ax_pid_is_owned_process() {
  local app_name="$1"
  local app_pid="$2"
  local app_binary="${3:-}"

  [[ "$app_pid" =~ ^[0-9]+$ && "$app_pid" -gt 0 ]] || return 1
  kill -0 "$app_pid" >/dev/null 2>&1 || return 1
  if [[ -n "$app_binary" ]]; then
    ax_process_matches_binary "$app_pid" "$app_binary"
    return
  fi

  # Keep the legacy two-argument API for smoke scripts that do not have the
  # bundle binary path, but derive the executable from the exact PID's command
  # line instead of trusting a name-only `ps comm` match.
  local process_command
  local executable
  process_command="$(ps -p "$app_pid" -o command= 2>/dev/null)" || return 1
  process_command="${process_command#"${process_command%%[![:space:]]*}"}"
  executable="${process_command%% *}"
  [[ -n "$executable" && "$(basename "$executable")" == "$app_name" ]]
}

ax_find_owned_app_pid() {
  local launch_pid="$1"
  local app_binary="$2"
  local child_pid

  if ax_process_matches_binary "$launch_pid" "$app_binary"; then
    printf '%s\n' "$launch_pid"
    return 0
  fi

  while IFS= read -r child_pid; do
    [[ -n "$child_pid" ]] || continue
    if child_pid="$(ax_find_owned_app_pid "$child_pid" "$app_binary")"; then
      printf '%s\n' "$child_pid"
      return 0
    fi
  done < <(pgrep -P "$launch_pid" 2>/dev/null || true)
  return 1
}

ax_wait_for_owned_app_pid() {
  local launch_pid="$1"
  local app_binary="$2"
  local timeout_seconds="$3"
  local deadline=$((SECONDS + timeout_seconds))
  local app_pid

  while true; do
    if app_pid="$(ax_find_owned_app_pid "$launch_pid" "$app_binary")"; then
      printf '%s\n' "$app_pid"
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      return 1
    fi
    sleep 0.2
  done
}

ax_wait_for_pid_owned_process() {
  local app_name="$1"
  local app_pid="$2"
  local timeout_seconds="$3"
  local app_binary="${4:-}"
  local deadline=$((SECONDS + timeout_seconds))

  while true; do
    if ax_pid_is_owned_process "$app_name" "$app_pid" "$app_binary"; then
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      return 1
    fi
    sleep 1
  done
}

ax_wait_for_pid_owned_window() {
  local app_name="$1"
  local app_pid="$2"
  local window_name="$3"
  local timeout_seconds="$4"
  local diagnostic_file="${5:-}"
  local app_binary="${6:-}"
  local deadline=$((SECONDS + timeout_seconds))
  local window_output=""
  local error_target="/dev/null"
  if [[ -n "$diagnostic_file" ]]; then
    error_target="$diagnostic_file"
    : >"$diagnostic_file"
  fi

  while true; do
    if ax_pid_is_owned_process "$app_name" "$app_pid" "$app_binary"; then
      set +e
      window_output="$(
        /usr/bin/osascript - "$app_pid" "$window_name" <<'APPLESCRIPT' 2>"$error_target"
on run argv
  set appPID to (item 1 of argv) as integer
  set requestedName to item 2 of argv
  tell application "System Events"
    set matchingProcesses to application processes whose unix id is appPID
    if (count of matchingProcesses) is 0 then error "pid-owned process missing"
    set targetProcess to item 1 of matchingProcesses
    tell targetProcess
      repeat with currentWindow in windows
        set currentName to ""
        try
          set currentName to name of currentWindow as text
        end try
        if requestedName is "" or currentName is requestedName then
          return "pid=" & appPID & " window=" & currentName
        end if
      end repeat
    end tell
  end tell
  error "pid-owned window missing"
end run
APPLESCRIPT
      )"
      local window_status=$?
      set -e
      if [[ "$window_status" -eq 0 && -n "$window_output" ]]; then
        printf '%s\n' "$window_output"
        return 0
      fi
    fi

    if [[ "$SECONDS" -ge "$deadline" ]]; then
      return 1
    fi
    sleep 1
  done
}

ax_classify_marker_failure() {
  local probe_file="$1"
  local app_pid="${2:-}"
  local diagnostic_file="${probe_file}.err"

  if [[ -n "$app_pid" ]] && ! kill -0 "$app_pid" >/dev/null 2>&1; then
    printf '%s\n' "launch"
    return 0
  fi
  if [[ -s "$probe_file" || -s "$diagnostic_file" ]] &&
    grep -Eqi 'Accessibility permission|AXIsProcessTrusted|not visible to Accessibility|AXUIElement|permission is required' \
      "$probe_file" "$diagnostic_file" 2>/dev/null; then
    printf '%s\n' "accessibility"
    return 0
  fi
  printf '%s\n' "product-marker"
}

ax_classify_ax_marker_failure() {
  ax_classify_marker_failure "$@"
}

ax_classify_window_failure() {
  local diagnostic_file="$1"
  if [[ -s "$diagnostic_file" ]] &&
    grep -Eqi 'Accessibility|not authorized|permission|assistive devices' "$diagnostic_file" 2>/dev/null; then
    printf '%s\n' "accessibility"
    return 0
  fi
  printf '%s\n' "window"
}

ax_emit_failure_category() {
  local category="$1"
  local message="${2:-}"

  case "$category" in
    launch|window|accessibility|product-marker)
      printf 'failure_category=%s\n' "$category" >&2
      if [[ -n "$message" ]]; then
        printf 'failure_message=%s\n' "$message" >&2
      fi
      ;;
    *)
      printf 'failure_category=launch\n' >&2
      printf 'failure_message=invalid failure category: %s\n' "$category" >&2
      return 2
      ;;
  esac
}

ax_report_failure() {
  ax_emit_failure_category "$@"
}

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
