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
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-}"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
TIMEOUT_SECONDS="${SOLOPM_PERFORMANCE_TIMEOUT_SECONDS:-30}"
OUTPUT_DIR="${SOLOPM_PERFORMANCE_OUTPUT_DIR:-$ROOT_DIR/.tmp/release-launch-performance}"
SUMMARY_FILE="$OUTPUT_DIR/summary.md"
SAMPLES_FILE="$OUTPUT_DIR/samples.tsv"
BUILD_CONFIGURATION="${SOLOPM_PERFORMANCE_BUILD_CONFIGURATION:-release}"

cd "$ROOT_DIR"
mkdir -p "$OUTPUT_DIR"

now_ms() {
  /usr/bin/perl -MTime::HiRes=time -e 'printf "%d\n", time() * 1000'
}

terminate_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

activate_app() {
  /usr/bin/osascript -e "tell application \"$APP_NAME\" to activate" >/dev/null 2>&1 &
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

open_app() {
  /usr/bin/open -n -F "$APP_BUNDLE" --args -ApplePersistenceIgnoreState YES
  activate_app
}

wait_for_visible_window() {
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while true; do
    if /usr/bin/osascript - "$APP_NAME" "$BUNDLE_IDENTIFIER" <<'APPLESCRIPT' >/dev/null 2>&1; then
on run argv
  set appName to item 1 of argv
  set bundleID to item 2 of argv
  tell application "System Events"
    if exists process appName then
      tell process appName
        if (count of windows) > 0 then return "visible"
      end tell
    end if
    if bundleID is not "" then
      set appMatches to application processes whose bundle identifier is bundleID
      repeat with appProcess in appMatches
        if (count of windows of appProcess) > 0 then return "visible"
      end repeat
    end if
  end tell
  error "window not visible"
end run
APPLESCRIPT
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: $APP_NAME did not publish a visible window within ${TIMEOUT_SECONDS}s" >&2
      return 1
    fi
    sleep 1
  done
}

click_sidebar_destination() {
  local destination_identifier="$1"
  local destination_label="$2"
  /usr/bin/osascript - "$APP_NAME" "$destination_identifier" "$destination_label" <<'APPLESCRIPT' >/dev/null
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

wait_for_marker() {
  local identifier="$1"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local safe_identifier="${identifier//[^[:alnum:]_-]/_}"
  local probe_file="$OUTPUT_DIR/wait-$safe_identifier.txt"
  while true; do
    if /usr/bin/swift "$ROOT_DIR/script/ui_evidence_ax_marker_check.swift" "$APP_NAME" "$identifier" "" >"$probe_file" 2>"$probe_file.err"; then
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: AX marker did not appear during performance smoke: $identifier" >&2
      sed -n '1,20p' "$probe_file.err" >&2 || true
      sed -n '1,20p' "$probe_file" >&2 || true
      return 1
    fi
    sleep 1
  done
}

record_sample() {
  local label="$1"
  local start_ms="$2"
  local end_ms="$3"
  local elapsed_ms=$((end_ms - start_ms))
  printf '%s\t%s\n' "$label" "$elapsed_ms" >>"$SAMPLES_FILE"
  printf -- '- `%s`: `%sms`\n' "$label" "$elapsed_ms" >>"$SUMMARY_FILE"
  printf "OK: %s completed in %sms\n" "$label" "$elapsed_ms"
}

measure_destination() {
  local label="$1"
  local destination_identifier="$2"
  local destination_label="$3"
  local marker="$4"
  local start_ms end_ms
  start_ms="$(now_ms)"
  click_sidebar_destination "$destination_identifier" "$destination_label"
  wait_for_marker "$marker"
  end_ms="$(now_ms)"
  record_sample "$label" "$start_ms" "$end_ms"
}

trap terminate_app EXIT

{
  printf '%s\n' '# Release Launch Performance Smoke'
  printf '\n'
  printf 'Generated at: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf 'Build configuration: `%s`\n' "$BUILD_CONFIGURATION"
  printf '\n'
  printf '%s\n' '## Samples'
} >"$SUMMARY_FILE"
printf '%s\t%s\n' "label" "elapsed_ms" >"$SAMPLES_FILE"

terminate_app
SOLOPM_BUILD_CONFIGURATION="$BUILD_CONFIGURATION" ./script/build_and_run.sh --build-only

launch_start_ms="$(now_ms)"
open_app
wait_for_visible_window
wait_for_marker "project-board-header-bar"
launch_end_ms="$(now_ms)"
record_sample "cold-launch-visible-window" "$launch_start_ms" "$launch_end_ms"

measure_destination "destination-inbox" "sidebar-destination-inbox" "Inbox" "inbox-workflow"
measure_destination "destination-assistant-queue" "sidebar-destination-assistant-queue" "Assistant Queue" "assistant-queue-workflow"
measure_destination "destination-today" "sidebar-destination-today" "Today" "today-workflow"

printf '\nStatus: passed\n' >>"$SUMMARY_FILE"
printf "OK: release launch performance smoke passed; artifacts written to %s\n" "$OUTPUT_DIR"
