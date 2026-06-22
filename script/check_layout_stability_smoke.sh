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
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
WINDOW_NAME="${SOLOPM_PROJECT_BOARD_WINDOW_NAME:-SoloPM}"
TIMEOUT_SECONDS="${SOLOPM_LAYOUT_STABILITY_TIMEOUT_SECONDS:-20}"
LAYOUT_STABILITY_OUTPUT_DIR="${SOLOPM_LAYOUT_STABILITY_OUTPUT_DIR:-$ROOT_DIR/.tmp/layout-stability}"
# Default to 0px because layout-sensitive mutations should settle
# synchronously. Set SOLOPM_LAYOUT_STABILITY_FRAME_DELTA_THRESHOLD_PX=1 only
# for a documented macOS rendering/runtime tolerance.
LAYOUT_STABILITY_FRAME_DELTA_THRESHOLD_PX="${SOLOPM_LAYOUT_STABILITY_FRAME_DELTA_THRESHOLD_PX:-0}"
LAYOUT_STABILITY_DATABASE_PATH="${SOLOPM_LAYOUT_STABILITY_DATABASE_PATH:-$LAYOUT_STABILITY_OUTPUT_DIR/SoloPM-layout-stability.sqlite}"
SQLITE3="${SQLITE3:-sqlite3}"

if [[ ! "$TIMEOUT_SECONDS" =~ ^[0-9]+$ || "$TIMEOUT_SECONDS" -lt 1 ]]; then
  echo "SOLOPM_LAYOUT_STABILITY_TIMEOUT_SECONDS must be a positive integer" >&2
  exit 2
fi

if [[ ! "$LAYOUT_STABILITY_FRAME_DELTA_THRESHOLD_PX" =~ ^[0-9]+$ ]]; then
  echo "LAYOUT_STABILITY_FRAME_DELTA_THRESHOLD_PX must be a non-negative integer" >&2
  exit 2
fi

if ! command -v "$SQLITE3" >/dev/null 2>&1; then
  echo "BLOCKER: sqlite3 is required for layout stability smoke" >&2
  exit 2
fi

cd "$ROOT_DIR"
mkdir -p "$LAYOUT_STABILITY_OUTPUT_DIR"

SUMMARY_FILE="$LAYOUT_STABILITY_OUTPUT_DIR/layout-stability-summary.md"
SAMPLES_FILE="$LAYOUT_STABILITY_OUTPUT_DIR/samples.tsv"
DIFF_FILE="$LAYOUT_STABILITY_OUTPUT_DIR/diff.tsv"
SAMPLES_JSON_FILE="$LAYOUT_STABILITY_OUTPUT_DIR/samples.json"
DIFF_JSON_FILE="$LAYOUT_STABILITY_OUTPUT_DIR/diff.json"
WINDOW_METADATA_FILE="$LAYOUT_STABILITY_OUTPUT_DIR/window.tsv"
REQUIRED_AX_IDENTIFIERS=(
  "project-board-header-bar"
  "project-board-detail"
  "project-board-sidebar"
  "project-inspector"
)
# Sampling schedule: t=0ms, t=50ms, t=150ms, t=300ms.
SAMPLE_OFFSETS_MS=(0 50 150 300)
layout_project_id=""
app_pid=""

: >"$SAMPLES_FILE"
: >"$DIFF_FILE"

write_json_artifacts() {
  # JSON phase values: "phase":"before", "phase":"immediate", "phase":"after".
  awk -F $'\t' '
    function json_escape(value) {
      gsub(/\\/,"\\\\",value)
      gsub(/"/,"\\\"",value)
      return value
    }
    function phase_for(label) {
      if (label == "initial") return "before"
      if (label == "sidebar-hidden") return "immediate"
      if (label == "sidebar-restored") return "after"
      return label
    }
    BEGIN { print "[" }
    {
      if (count > 0) printf ",\n"
      printf "  {\"phase\":\"%s\",\"label\":\"%s\",\"sample\":%d,\"offset\":\"%s\",\"identifier\":\"%s\",\"x\":%d,\"y\":%d,\"width\":%d,\"height\":%d}",
        phase_for($1), json_escape($1), $2, json_escape($3), json_escape($4), $5, $6, $7, $8
      count += 1
    }
    END {
      if (count > 0) print ""
      print "]"
    }
  ' "$SAMPLES_FILE" >"$SAMPLES_JSON_FILE"

  awk -F $'\t' '
    function json_escape(value) {
      gsub(/\\/,"\\\\",value)
      gsub(/"/,"\\\"",value)
      return value
    }
    function phase_for(label) {
      if (label == "initial") return "before"
      if (label == "sidebar-hidden") return "immediate"
      if (label == "sidebar-restored") return "after"
      return label
    }
    BEGIN { print "[" }
    {
      if (count > 0) printf ",\n"
      printf "  {\"phase\":\"%s\",\"label\":\"%s\",\"offset\":\"%s\",\"identifier\":\"%s\",\"dx\":%d,\"dy\":%d,\"dw\":%d,\"dh\":%d,\"delta\":%d}",
        phase_for($1), json_escape($1), json_escape($2), json_escape($3), $4, $5, $6, $7, $8
      count += 1
    }
    END {
      if (count > 0) print ""
      print "]"
    }
  ' "$DIFF_FILE" >"$DIFF_JSON_FILE"
}

terminate_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  if [[ -n "${app_pid:-}" ]]; then
    wait "$app_pid" >/dev/null 2>&1 || true
    app_pid=""
  fi
}

activate_app() {
  # Use System Events instead of LaunchServices activation so the selected
  # project/database environment stays attached to the already-running app.
  /usr/bin/osascript - "$APP_NAME" <<'APPLESCRIPT' >/dev/null 2>&1 || true
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
end run
APPLESCRIPT
}

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

prepare_layout_candidate() {
  ./script/build_and_run.sh --build-only
  SOLOPM_VOICEOVER_REVIEW_TIMEOUT_SECONDS="$TIMEOUT_SECONDS" \
    ./script/prepare_voiceover_review_candidate.sh --database "$LAYOUT_STABILITY_DATABASE_PATH" --no-launch --skip-build >/dev/null
  layout_project_id="$("$SQLITE3" -batch -noheader "$LAYOUT_STABILITY_DATABASE_PATH" "SELECT id FROM projects WHERE title='VoiceOver Review Project' AND source_command='voiceover-review-seed' ORDER BY id DESC LIMIT 1;" | tail -n 1)"
  if [[ -z "${layout_project_id//[[:space:]]/}" ]]; then
    echo "BLOCKER: layout stability candidate project was not seeded" >&2
    return 1
  fi
}

launch_layout_candidate() {
  terminate_app
  SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1 \
    SOLOPM_DATABASE_PATH="$LAYOUT_STABILITY_DATABASE_PATH" \
    SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION="project:$layout_project_id" \
    "$APP_BINARY" &
  app_pid=$!
  wait_for_app_process
  activate_app
  wait_for_visible_windows
}

read_window_metadata() {
  local output
  output="$(
    SOLOPM_WINDOW_OWNER="$APP_NAME" \
    SOLOPM_WINDOW_NAME="$WINDOW_NAME" \
    /usr/bin/swift "$ROOT_DIR/script/ui_evidence_window_metadata.swift"
  )"
  printf '%s\n' "$output" >"$WINDOW_METADATA_FILE"
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

capture_layout_screenshot() {
  local label="$1"
  local offset_label="$2"
  local window_id window_x window_y window_width window_height
  wait_for_window_metadata
  read -r window_id window_x window_y window_width window_height <"$WINDOW_METADATA_FILE"
  local screenshot_path="$LAYOUT_STABILITY_OUTPUT_DIR/${label}-${offset_label}.png"
  /usr/sbin/screencapture -x -l "$window_id" "$screenshot_path"
  if [[ ! -s "$screenshot_path" ]]; then
    echo "BLOCKER: layout stability screenshot was not written: $screenshot_path" >&2
    return 1
  fi
}

collect_ax_frames() {
  /usr/bin/osascript - "$APP_NAME" <<'APPLESCRIPT'
on collectIdentifiedElements(outputLines, uiElement)
  tell application "System Events"
    set identifierValue to ""
    try
      set identifierValue to value of attribute "AXIdentifier" of uiElement
    end try
    if identifierValue is not equal to "" then
      set itemPosition to position of uiElement
      set itemSize to size of uiElement
      set end of outputLines to identifierValue & tab & (item 1 of itemPosition as text) & tab & (item 2 of itemPosition as text) & tab & (item 1 of itemSize as text) & tab & (item 2 of itemSize as text)
    end if
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
      set frontmost to true
      set outputLines to {}
      set outputLines to my collectIdentifiedElements(outputLines, window 1)
      set AppleScript's text item delimiters to linefeed
      return outputLines as text
    end tell
  end tell
end run
APPLESCRIPT
}

ensure_project_detail_visible() {
  /usr/bin/osascript - "$APP_NAME" <<'APPLESCRIPT' >/dev/null 2>&1 || true
on clickFirstMatching(uiElement)
  tell application "System Events"
    set identifierValue to ""
    try
      set identifierValue to value of attribute "AXIdentifier" of uiElement
    end try
    if identifierValue starts with "project-sidebar-row-" or identifierValue starts with "projects-portfolio-open-" then
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
        if my clickFirstMatching(childElement) then return true
      end repeat
    end try
  end tell
  return false
end clickFirstMatching

on run argv
  set appName to item 1 of argv
  tell application "System Events"
    if not (exists process appName) then return "missing"
    tell process appName
      if not (exists window 1) then return "window missing"
      set frontmost to true
      try
        perform action "AXRaise" of window 1
      end try
      my clickFirstMatching(window 1)
    end tell
  end tell
end run
APPLESCRIPT
}

write_summary_header() {
  {
    printf '%s\n' '# Layout Stability Smoke'
    printf '\n'
    printf 'Generated at: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf 'Output directory: `%s`\n' "$LAYOUT_STABILITY_OUTPUT_DIR"
    printf 'Frame delta threshold: `%spx`\n' "$LAYOUT_STABILITY_FRAME_DELTA_THRESHOLD_PX"
    printf '\n'
    printf '%s\n' '## Samples'
  } >"$SUMMARY_FILE"
}

require_ax_identifiers() {
  local frame_file="$1"
  shift || true
  local required_identifiers=("$@")
  local missing=0
  local identifier
  if [[ "${#required_identifiers[@]}" -eq 0 ]]; then
    required_identifiers=("${REQUIRED_AX_IDENTIFIERS[@]}")
  fi
  for identifier in "${required_identifiers[@]}"; do
    if ! awk -F $'\t' -v wanted="$identifier" '$1 == wanted { found = 1 } END { exit(found ? 0 : 1) }' "$frame_file"; then
      printf 'BLOCKER: required AX identifier missing: %s\n' "$identifier" >&2
      missing=$((missing + 1))
    fi
  done
  if (( missing > 0 )); then
    printf 'Observed AX identifiers were written to %s\n' "$frame_file" >&2
    return 1
  fi
}

has_required_ax_identifiers() {
  local frame_file="$1"
  shift || true
  local required_identifiers=("$@")
  local identifier
  if [[ "${#required_identifiers[@]}" -eq 0 ]]; then
    required_identifiers=("${REQUIRED_AX_IDENTIFIERS[@]}")
  fi
  for identifier in "${required_identifiers[@]}"; do
    if ! awk -F $'\t' -v wanted="$identifier" '$1 == wanted { found = 1 } END { exit(found ? 0 : 1) }' "$frame_file"; then
      return 1
    fi
  done
}

wait_for_required_layout_subjects() {
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local probe_file="$LAYOUT_STABILITY_OUTPUT_DIR/required-identifiers-probe.tsv"

  while true; do
    ensure_project_detail_visible
    if collect_ax_frames >"$probe_file" 2>"$LAYOUT_STABILITY_OUTPUT_DIR/required-identifiers-probe.err" &&
      has_required_ax_identifiers "$probe_file"; then
      return 0
    fi

    if [[ "$SECONDS" -ge "$deadline" ]]; then
      require_ax_identifiers "$probe_file"
      return 1
    fi
    sleep 1
  done
}

sample_layout_frames() {
  local label="$1"
  shift || true
  local required_identifiers=("$@")
  local sample_index=0
  local previous_offset_ms=0
  local offset_ms sleep_ms frame_file
  if [[ "${#required_identifiers[@]}" -eq 0 ]]; then
    required_identifiers=("${REQUIRED_AX_IDENTIFIERS[@]}")
  fi

  for offset_ms in "${SAMPLE_OFFSETS_MS[@]}"; do
    if (( offset_ms > 0 )); then
      sleep_ms=$((offset_ms - previous_offset_ms))
      sleep "$(awk -v ms="$sleep_ms" 'BEGIN { printf "%.3f", ms / 1000 }')"
    fi

    frame_file="$LAYOUT_STABILITY_OUTPUT_DIR/${label}-t=${offset_ms}ms.tsv"
    collect_ax_frames >"$frame_file"
    require_ax_identifiers "$frame_file" "${required_identifiers[@]}"
    capture_layout_screenshot "$label" "t=${offset_ms}ms"

    # The first sample is intentionally taken at t=0ms so transient layout
    # correction cannot be hidden behind a delayed runloop retry.
    awk -F $'\t' -v label="$label" -v sample="$sample_index" -v offset="t=${offset_ms}ms" '
      $1 == "project-board-header-bar" ||
      $1 == "project-board-detail" ||
      $1 == "project-board-sidebar" ||
      $1 == "project-inspector" {
        print label "\t" sample "\t" offset "\t" $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5
      }
    ' "$frame_file" >>"$SAMPLES_FILE"

    printf -- '- `%s` sample %s (`t=%sms`) -> `%s`\n' "$label" "$sample_index" "$offset_ms" "$frame_file" >>"$SUMMARY_FILE"
    sample_index=$((sample_index + 1))
    previous_offset_ms="$offset_ms"
  done
}

assert_layout_stable() {
  local label="$1"
  shift || true
  local required_identifiers=("$@")
  local max_delta
  if [[ "${#required_identifiers[@]}" -eq 0 ]]; then
    required_identifiers=("${REQUIRED_AX_IDENTIFIERS[@]}")
  fi
  sample_layout_frames "$label" "${required_identifiers[@]}"

  max_delta="$(
    awk -F $'\t' -v label="$label" -v threshold="$LAYOUT_STABILITY_FRAME_DELTA_THRESHOLD_PX" '
      function abs(value) { return value < 0 ? -value : value }
      $1 == label {
        key = $4
        if ($2 == 0) {
          baseX[key] = $5
          baseY[key] = $6
          baseW[key] = $7
          baseH[key] = $8
          next
        }
        dx = abs($5 - baseX[key])
        dy = abs($6 - baseY[key])
        dw = abs($7 - baseW[key])
        dh = abs($8 - baseH[key])
        delta = dx
        if (dy > delta) delta = dy
        if (dw > delta) delta = dw
        if (dh > delta) delta = dh
        if (delta > maxDelta) maxDelta = delta
        print label "\t" $3 "\t" key "\t" dx "\t" dy "\t" dw "\t" dh "\t" delta >> diffFile
        if (delta > threshold) failed = 1
      }
      END {
        printf "%d\n", maxDelta
        if (failed) exit 9
      }
    ' diffFile="$DIFF_FILE" "$SAMPLES_FILE"
  )" || {
    write_json_artifacts
    echo "BLOCKER: layout frame delta exceeded ${LAYOUT_STABILITY_FRAME_DELTA_THRESHOLD_PX}px after $label" >&2
    echo "See $SAMPLES_FILE, $SAMPLES_JSON_FILE, $DIFF_FILE, and $DIFF_JSON_FILE" >&2
    return 1
  }

  printf "OK: layout frame delta stayed within %spx after %s (max=%spx)\n" "$LAYOUT_STABILITY_FRAME_DELTA_THRESHOLD_PX" "$label" "$max_delta"
  printf -- '- `%s` max delta: `%spx`\n' "$label" "$max_delta" >>"$SUMMARY_FILE"
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

write_summary_header
prepare_layout_candidate
launch_layout_candidate
wait_for_required_layout_subjects

assert_layout_stable "initial"

click_sidebar_toggle
assert_layout_stable "sidebar-hidden" "project-board-header-bar" "project-board-detail" "project-inspector"

click_sidebar_toggle
assert_layout_stable "sidebar-restored"

write_json_artifacts

{
  printf '\n'
  printf '%s\n' '## Artifacts'
  printf -- '- `samples.tsv`\n'
  printf -- '- `samples.json`\n'
  printf -- '- `diff.tsv`\n'
  printf -- '- `diff.json`\n'
  printf '\n'
  printf '%s\n' 'Status: passed'
} >>"$SUMMARY_FILE"

printf "OK: layout stability smoke passed; artifacts written to %s\n" "$LAYOUT_STABILITY_OUTPUT_DIR"
