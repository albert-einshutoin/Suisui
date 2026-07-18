#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE_MODE="${1:-}"
ARTIFACT_DIR="${SOLOPM_UI_RUNNER_CAPABILITY_ARTIFACT_DIR:-$ROOT_DIR/.tmp/ui-runner-capabilities}"
SUMMARY_FILE="$ARTIFACT_DIR/ui-runner-capability-summary.env"
PROBE_SOURCE="$ROOT_DIR/script/macos_ui_runner_capability_probe.swift"
CONTENT_CHECK_SOURCE="$ROOT_DIR/script/ui_evidence_content_check.swift"

STATUS="blocked"
FAILURE_CATEGORY="runner-capability"
FAILURE_REASON="probe-not-completed"
DARWIN=0
GUI_SESSION=0
WINDOW_SERVER=0
ACTIVE_DISPLAY=0
ACCESSIBILITY=0
SYSTEM_EVENTS=0
SCREEN_RECORDING="not-required"
VISIBLE_PIXELS="not-required"
DISPLAY_FRAME_X=0
DISPLAY_FRAME_Y=0
DISPLAY_FRAME_WIDTH=0
DISPLAY_FRAME_HEIGHT=0
DISPLAY_VISIBLE_FRAME_X=0
DISPLAY_VISIBLE_FRAME_Y=0
DISPLAY_VISIBLE_FRAME_WIDTH=0
DISPLAY_VISIBLE_FRAME_HEIGHT=0
PRIVATE_DIR=""

mkdir -p "$ARTIFACT_DIR"

write_summary() {
  # Values in this artifact are a closed vocabulary. Do not add hostnames,
  # usernames, absolute paths, environment dumps, or raw TCC diagnostics.
  {
    printf 'schema_version=1\n'
    printf 'gate=%s\n' "$GATE_MODE"
    printf 'status=%s\n' "$STATUS"
    printf 'failure_category=%s\n' "$FAILURE_CATEGORY"
    printf 'failure_reason=%s\n' "$FAILURE_REASON"
    printf 'darwin=%s\n' "$DARWIN"
    printf 'gui_session=%s\n' "$GUI_SESSION"
    printf 'window_server=%s\n' "$WINDOW_SERVER"
    printf 'active_display=%s\n' "$ACTIVE_DISPLAY"
    printf 'accessibility=%s\n' "$ACCESSIBILITY"
    printf 'system_events=%s\n' "$SYSTEM_EVENTS"
    printf 'screen_recording=%s\n' "$SCREEN_RECORDING"
    printf 'visible_pixels=%s\n' "$VISIBLE_PIXELS"
    printf 'display_frame_x=%s\n' "$DISPLAY_FRAME_X"
    printf 'display_frame_y=%s\n' "$DISPLAY_FRAME_Y"
    printf 'display_frame_width=%s\n' "$DISPLAY_FRAME_WIDTH"
    printf 'display_frame_height=%s\n' "$DISPLAY_FRAME_HEIGHT"
    printf 'display_visible_frame_x=%s\n' "$DISPLAY_VISIBLE_FRAME_X"
    printf 'display_visible_frame_y=%s\n' "$DISPLAY_VISIBLE_FRAME_Y"
    printf 'display_visible_frame_width=%s\n' "$DISPLAY_VISIBLE_FRAME_WIDTH"
    printf 'display_visible_frame_height=%s\n' "$DISPLAY_VISIBLE_FRAME_HEIGHT"
  } >"$SUMMARY_FILE"
}

cleanup() {
  if [[ -n "${PRIVATE_DIR:-}" && -d "$PRIVATE_DIR" ]]; then
    rm -rf "$PRIVATE_DIR"
  fi
}

finalize() {
  local exit_code=$?
  write_summary
  cleanup
  return "$exit_code"
}
trap finalize EXIT
trap 'FAILURE_REASON="interrupted"; exit 130' INT
trap 'FAILURE_REASON="terminated"; exit 143' TERM

block() {
  local category="$1"
  local reason="$2"
  local exit_code="${3:-1}"
  STATUS="blocked"
  FAILURE_CATEGORY="$category"
  FAILURE_REASON="$reason"
  write_summary
  printf 'failure_category=%s\n' "$FAILURE_CATEGORY" >&2
  printf 'failure_reason=%s\n' "$FAILURE_REASON" >&2
  printf 'summary_artifact=ui-runner-capability-summary.env\n' >&2
  exit "$exit_code"
}

case "$GATE_MODE" in
  runtime|performance|visual)
    ;;
  *)
    block "configuration" "unsupported-mode" 2
    ;;
esac

if [[ "$(uname -s 2>/dev/null || true)" != "Darwin" ]]; then
  block "runner-capability" "macos-required"
fi
DARWIN=1

required_commands=(id launchctl pgrep swift swiftc osascript)
case "$GATE_MODE" in
  runtime)
    required_commands+=(sqlite3 screencapture)
    ;;
  performance)
    required_commands+=(sqlite3)
    ;;
  visual)
    required_commands+=(sqlite3 sips screencapture)
    ;;
esac
for required_command in "${required_commands[@]}"; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    block "runner-capability" "missing-required-command"
  fi
done

UID_VALUE="$(id -u)"
if launchctl print "gui/$UID_VALUE" >/dev/null 2>&1; then
  GUI_SESSION=1
else
  block "runner-capability" "gui-login-session-unavailable"
fi

if pgrep -x WindowServer >/dev/null 2>&1; then
  WINDOW_SERVER=1
else
  block "runner-capability" "window-server-unavailable"
fi

if [[ ! -r "$PROBE_SOURCE" ]]; then
  block "runner-capability" "system-probe-source-unavailable"
fi

PRIVATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/solopm-ui-runner-capability.XXXXXX")"
PROBE_EXECUTABLE="$PRIVATE_DIR/macos-ui-runner-capability-probe"
if ! /usr/bin/swiftc "$PROBE_SOURCE" -o "$PROBE_EXECUTABLE" >/dev/null 2>&1; then
  block "runner-capability" "system-probe-compile-failed"
fi
if ! PROBE_OUTPUT="$("$PROBE_EXECUTABLE" 2>/dev/null)"; then
  block "runner-capability" "system-probe-execution-failed"
fi

probe_exact_value() {
  local key="$1"
  local value_pattern="$2"
  printf '%s\n' "$PROBE_OUTPUT" | awk -F= -v key="$key" -v valuePattern="$value_pattern" '
    $1 == key {
      count += 1
      if (NF != 2 || $2 !~ valuePattern) invalid = 1
      value = $2
    }
    END {
      if (count != 1 || invalid) exit 1
      print value
    }
  '
}

probe_value() {
  probe_exact_value "$1" '^(0|1)$'
}

probe_integer_value() {
  probe_exact_value "$1" '^-?[0-9]+$'
}

probe_positive_integer_value() {
  probe_exact_value "$1" '^[1-9][0-9]*$'
}

if ! ACTIVE_DISPLAY="$(probe_value active_display)"; then
  block "runner-capability" "invalid-active-display-result"
fi
if [[ "$ACTIVE_DISPLAY" != "1" ]]; then
  block "runner-capability" "active-display-unavailable"
fi

if ! DISPLAY_FRAME_X="$(probe_integer_value display_frame_x)" ||
  ! DISPLAY_FRAME_Y="$(probe_integer_value display_frame_y)" ||
  ! DISPLAY_FRAME_WIDTH="$(probe_positive_integer_value display_frame_width)" ||
  ! DISPLAY_FRAME_HEIGHT="$(probe_positive_integer_value display_frame_height)" ||
  ! DISPLAY_VISIBLE_FRAME_X="$(probe_integer_value display_visible_frame_x)" ||
  ! DISPLAY_VISIBLE_FRAME_Y="$(probe_integer_value display_visible_frame_y)" ||
  ! DISPLAY_VISIBLE_FRAME_WIDTH="$(probe_positive_integer_value display_visible_frame_width)" ||
  ! DISPLAY_VISIBLE_FRAME_HEIGHT="$(probe_positive_integer_value display_visible_frame_height)"; then
  block "runner-capability" "invalid-display-geometry"
fi

if ! ACCESSIBILITY="$(probe_value accessibility)"; then
  block "runner-capability" "invalid-accessibility-result"
fi
if [[ "$ACCESSIBILITY" != "1" ]]; then
  block "runner-capability" "accessibility-permission-unavailable"
fi

if /usr/bin/osascript -e 'tell application "System Events" to get unix id of first application process' >/dev/null 2>&1; then
  SYSTEM_EVENTS=1
else
  block "runner-capability" "system-events-automation-unavailable"
fi

if [[ "$GATE_MODE" == "runtime" || "$GATE_MODE" == "visual" ]]; then
  if ! SCREEN_RECORDING="$(probe_value screen_recording)"; then
    block "runner-capability" "invalid-screen-recording-result"
  fi
  if [[ "$SCREEN_RECORDING" != "1" ]]; then
    block "runner-capability" "screen-recording-permission-unavailable"
  fi
fi

if [[ "$GATE_MODE" == "visual" ]]; then
  if [[ ! -r "$CONTENT_CHECK_SOURCE" ]]; then
    block "runner-capability" "visible-pixel-check-unavailable"
  fi

  SCREENSHOT="$PRIVATE_DIR/visible-pixel-probe.png"
  VISIBLE_PIXEL_PROBE_ATTEMPTS=3
  visible_pixel_probe_attempt=1
  while (( visible_pixel_probe_attempt <= VISIBLE_PIXEL_PROBE_ATTEMPTS )); do
    rm -f "$SCREENSHOT"
    if screencapture -x "$SCREENSHOT" >/dev/null 2>&1 &&
      [[ -s "$SCREENSHOT" ]] &&
      SOLOPM_UI_EVIDENCE_ALLOW_DESKTOP_BACKGROUND=1 \
        /usr/bin/swift "$CONTENT_CHECK_SOURCE" "$SCREENSHOT" >/dev/null 2>&1; then
      VISIBLE_PIXELS=1
      break
    fi
    sleep 0.25
    visible_pixel_probe_attempt=$((visible_pixel_probe_attempt + 1))
  done
  if [[ "$VISIBLE_PIXELS" != "1" ]]; then
    VISIBLE_PIXELS=0
    block "runner-capability" "visible-pixels-unavailable"
  fi
fi

STATUS="passed"
FAILURE_CATEGORY="none"
FAILURE_REASON="none"
write_summary
printf 'status=passed\n'
printf 'gate=%s\n' "$GATE_MODE"
printf 'summary_artifact=ui-runner-capability-summary.env\n'
