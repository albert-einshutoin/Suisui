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
TIMEOUT_SECONDS="${SUISUI_HEADER_LAYOUT_SMOKE_TIMEOUT_SECONDS:-20}"
OUTPUT_DIR="${SUISUI_HEADER_LAYOUT_SMOKE_OUTPUT_DIR:-$ROOT_DIR/.tmp/project-board-header-layout-smoke}"
WINDOW_NAME="${SUISUI_PROJECT_BOARD_WINDOW_NAME:-Suisui}"
HEADER_LAYOUT_DATABASE_PATH="${SUISUI_HEADER_LAYOUT_DATABASE_PATH:-$OUTPUT_DIR/Suisui-header-layout.sqlite}"
SQLITE3="${SQLITE3:-/usr/bin/sqlite3}"
SETTINGS_SUITE="dev.suisui.header-layout-smoke"

if [[ ! "$TIMEOUT_SECONDS" =~ ^[0-9]+$ || "$TIMEOUT_SECONDS" -lt 1 ]]; then
  echo "SUISUI_HEADER_LAYOUT_SMOKE_TIMEOUT_SECONDS must be a positive integer" >&2
  exit 2
fi

if ! command -v "$SQLITE3" >/dev/null 2>&1; then
  echo "BLOCKER: sqlite3 is required for Project Board header layout smoke" >&2
  exit 2
fi

cd "$ROOT_DIR"
mkdir -p "$OUTPUT_DIR"

window_id=""
window_x=""
window_y=""
window_width=""
window_height=""
header_layout_project_id=""
header_layout_project_task_id=""
header_layout_alternate_project_id=""
header_layout_alternate_task_id=""
app_pid=""

terminate_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  if [[ -n "${app_pid:-}" ]]; then
    wait "$app_pid" >/dev/null 2>&1 || true
    app_pid=""
  fi
}

activate_app() {
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

restore_project_board_window() {
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while true; do
    if /usr/bin/osascript - "$APP_NAME" "$app_pid" <<'APPLESCRIPT' >/dev/null 2>&1
on containsIdentifier(uiElement, targetIdentifier, depth)
  tell application "System Events"
    try
      if value of attribute "AXIdentifier" of uiElement is targetIdentifier then return true
    end try
    if depth < 12 then
      try
        repeat with childElement in UI elements of uiElement
          if my containsIdentifier(childElement, targetIdentifier, depth + 1) then return true
        end repeat
      end try
    end if
  end tell
  return false
end containsIdentifier

on run argv
  set appName to item 1 of argv
  set targetPID to (item 2 of argv) as integer
  tell application "System Events"
    set matchingProcesses to every process whose unix id is targetPID
    if (count of matchingProcesses) is not 1 then error "owned process missing"
    tell item 1 of matchingProcesses
      set frontmost to true
      repeat with candidateWindow in windows
        if my containsIdentifier(candidateWindow, "project-board-sidebar-toggle", 0) and my containsIdentifier(candidateWindow, "project-board-detail", 0) then
          try
            perform action "AXRaise" of candidateWindow
          end try
          try
            set value of attribute "AXMain" of candidateWindow to true
          end try
          return true
        end if
      end repeat
    end tell
  end tell
  error "Project Board window not restored yet"
end run
APPLESCRIPT
    then
      wait_for_window_metadata
      return 0
    fi

    activate_app
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: PID-owned Project Board window did not become visible and key within ${TIMEOUT_SECONDS}s" >&2
      return 1
    fi
    sleep 0.2
  done
}

prepare_header_layout_candidate() {
  ./script/build_and_run.sh --build-only
  # This smoke owns its isolated database. Reusing an interrupted zero-byte
  # fixture makes a shared seeder wait for migrations that can never be
  # observed, so initialize and seed the narrow toolbar fixture directly.
  rm -f "$HEADER_LAYOUT_DATABASE_PATH" "$HEADER_LAYOUT_DATABASE_PATH-wal" "$HEADER_LAYOUT_DATABASE_PATH-shm"

  SUISUI_DISABLE_KEYCHAIN_SECRET_STORE=1 \
    SUISUI_LAUNCH_RECOVERY_MODE=1 \
    SUISUI_DATABASE_PATH="$HEADER_LAYOUT_DATABASE_PATH" \
    "$APP_BINARY" &
  app_pid=$!
  wait_for_app_process

  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while ! "$SQLITE3" -batch -noheader "$HEADER_LAYOUT_DATABASE_PATH" \
    "SELECT name FROM sqlite_master WHERE type='table' AND name='projects';" 2>/dev/null |
    grep -Fx "projects" >/dev/null; do
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: Project Board schema was not initialized for native toolbar smoke" >&2
      return 1
    fi
    sleep 0.2
  done
  terminate_app

  "$SQLITE3" "$HEADER_LAYOUT_DATABASE_PATH" <<SQL
PRAGMA foreign_keys = ON;
INSERT INTO projects (title, status, priority, deadline, workspace_path, tags_json, source_command, created_at, updated_at)
VALUES (
  'Native Toolbar Review Project',
  'active',
  'high',
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '+7 days'),
  '$ROOT_DIR',
  '["layout","toolbar"]',
  'header-layout-native-toolbar-seed',
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
);
SQL

  header_layout_project_id="$("$SQLITE3" -batch -noheader "$HEADER_LAYOUT_DATABASE_PATH" "SELECT id FROM projects WHERE title='Native Toolbar Review Project' AND source_command='header-layout-native-toolbar-seed' ORDER BY id DESC LIMIT 1;" | tail -n 1)"
  if [[ -z "${header_layout_project_id//[[:space:]]/}" ]]; then
    echo "BLOCKER: header layout candidate project was not seeded" >&2
    return 1
  fi

  "$SQLITE3" "$HEADER_LAYOUT_DATABASE_PATH" <<SQL
PRAGMA foreign_keys = ON;
INSERT INTO tasks (project_id, title, status, detail, due_at, priority, source_command, created_at, updated_at)
VALUES (
  $header_layout_project_id,
  'Verify native toolbar actions',
  'planned',
  'Verify primary actions and semantic overflow remain reachable at the minimum content size.',
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '+2 days'),
  'high',
  'header-layout-native-toolbar-seed',
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
);
SQL

  header_layout_project_task_id="$("$SQLITE3" -batch -noheader "$HEADER_LAYOUT_DATABASE_PATH" "SELECT id FROM tasks WHERE project_id=$header_layout_project_id AND title='Verify native toolbar actions' AND source_command='header-layout-native-toolbar-seed' ORDER BY id DESC LIMIT 1;" | tail -n 1)"
  if [[ -z "${header_layout_project_task_id//[[:space:]]/}" ]]; then
    echo "BLOCKER: header layout candidate project task was not seeded" >&2
    return 1
  fi

  local settings_json settings_hex
  settings_json='{"aiProvider":"openaiResponses","sttProvider":"openAITranscribe","notificationsEnabled":false,"isDeveloperModeEnabled":true,"timeZoneIdentifier":"UTC","taskAutoExecution":{"isEnabled":true,"mode":"reviewOnly","cadence":"manual","maxTasksPerRun":3,"dailyLLMCallLimit":6,"lookaheadHours":720,"urgentReviewCooldownMinutes":60}}'
  settings_hex="$(printf '%s' "$settings_json" | /usr/bin/xxd -p | tr -d '\n')"
  /usr/bin/defaults delete "$SETTINGS_SUITE" >/dev/null 2>&1 || true
  /usr/bin/defaults write "$SETTINGS_SUITE" app.settings -data "$settings_hex"
}

seed_header_layout_selection_project() {
  "$SQLITE3" "$HEADER_LAYOUT_DATABASE_PATH" <<SQL
PRAGMA foreign_keys = ON;
DELETE FROM tasks WHERE source_command='header-layout-selection-seed';
DELETE FROM projects WHERE source_command='header-layout-selection-seed';

INSERT INTO projects (title, status, priority, deadline, workspace_path, tags_json, source_command, created_at, updated_at)
VALUES (
  'Header Layout Selection Project',
  'active',
  'medium',
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '+9 days'),
  NULL,
  '["layout","selection"]',
  'header-layout-selection-seed',
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
);
SQL

  header_layout_alternate_project_id="$("$SQLITE3" -batch -noheader "$HEADER_LAYOUT_DATABASE_PATH" "SELECT id FROM projects WHERE title='Header Layout Selection Project' AND source_command='header-layout-selection-seed' ORDER BY id DESC LIMIT 1;" | tail -n 1)"
  if [[ -z "${header_layout_alternate_project_id//[[:space:]]/}" ]]; then
    echo "BLOCKER: header layout alternate project was not seeded" >&2
    return 1
  fi

  "$SQLITE3" "$HEADER_LAYOUT_DATABASE_PATH" <<SQL
PRAGMA foreign_keys = ON;
INSERT INTO tasks (project_id, title, status, detail, due_at, priority, source_command, created_at, updated_at)
VALUES (
  $header_layout_alternate_project_id,
  'Validate project selection layout',
  'planned',
  'Switch between projects and verify the header action group stays anchored to the detail column.',
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '+6 days'),
  'medium',
  'header-layout-selection-seed',
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
);
SQL

  header_layout_alternate_task_id="$("$SQLITE3" -batch -noheader "$HEADER_LAYOUT_DATABASE_PATH" "SELECT id FROM tasks WHERE project_id=$header_layout_alternate_project_id AND title='Validate project selection layout' AND source_command='header-layout-selection-seed' ORDER BY id DESC LIMIT 1;" | tail -n 1)"
  if [[ -z "${header_layout_alternate_task_id//[[:space:]]/}" ]]; then
    echo "BLOCKER: header layout alternate project task was not seeded" >&2
    return 1
  fi
}

launch_header_layout_candidate() {
  local language="${1:-english}"
  terminate_app
  SUISUI_DISABLE_KEYCHAIN_SECRET_STORE=1 \
    SUISUI_APP_SETTINGS_SUITE_NAME="$SETTINGS_SUITE" \
    SUISUI_LANGUAGE_PREFERENCE="$language" \
    SUISUI_DISABLE_PROJECT_BOARD_FALLBACK=1 \
    SUISUI_DATABASE_PATH="$HEADER_LAYOUT_DATABASE_PATH" \
    SUISUI_PROJECT_BOARD_SELECTED_DESTINATION="project:$header_layout_project_id" \
    "$APP_BINARY" &
  app_pid=$!
  wait_for_app_process
  activate_app
  wait_for_visible_windows
}

launch_runtime_crud_recovery_candidate() {
  terminate_app
  SUISUI_DISABLE_KEYCHAIN_SECRET_STORE=1 \
    SUISUI_APP_SETTINGS_SUITE_NAME="$SETTINGS_SUITE" \
    SUISUI_LAUNCH_RECOVERY_MODE=1 \
    SUISUI_RUNTIME_CRUD_RECOVERY_MODE=1 \
    SUISUI_DISABLE_PROJECT_BOARD_FALLBACK=1 \
    SUISUI_DATABASE_PATH="$HEADER_LAYOUT_DATABASE_PATH" \
    SUISUI_PROJECT_BOARD_SELECTED_DESTINATION="project:$header_layout_project_id" \
    "$APP_BINARY" &
  app_pid=$!
  wait_for_app_process
  activate_app
  wait_for_visible_windows
}

assert_single_native_toolbar() {
  local count
  count="$(/usr/bin/osascript - "$APP_NAME" "$app_pid" <<'APPLESCRIPT'
on containsIdentifier(uiElement, targetIdentifier, depth)
  tell application "System Events"
    try
      if value of attribute "AXIdentifier" of uiElement is targetIdentifier then return true
    end try
    if depth < 8 then
      try
        repeat with childElement in UI elements of uiElement
          if my containsIdentifier(childElement, targetIdentifier, depth + 1) then return true
        end repeat
      end try
    end if
  end tell
  return false
end containsIdentifier

on run argv
  set appName to item 1 of argv
  set targetPID to (item 2 of argv) as integer
  tell application "System Events"
    set matchingProcesses to every process whose unix id is targetPID
    if (count of matchingProcesses) is not 1 then return "0"
    tell item 1 of matchingProcesses
      repeat with candidateWindow in windows
        if my containsIdentifier(candidateWindow, "project-board-detail", 0) then
          return (count of toolbars of candidateWindow) as text
        end if
      end repeat
      return "0"
    end tell
  end tell
end run
APPLESCRIPT
)"
  if [[ "$count" != "1" ]]; then
    echo "BLOCKER: expected one native Project Board toolbar, observed $count" >&2
    return 1
  fi
  printf "OK: Project Board exposes one native toolbar\n"
}

resize_window_below_minimum() {
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while true; do
    if read_window_metadata >/dev/null 2>&1 &&
      /usr/bin/swift "$ROOT_DIR/script/ui_evidence_ax_resize_window.swift" \
        "$app_pid" "$window_x" "$window_y" "$window_width" "$window_height" \
        700 500 120 160 >/dev/null 2>&1; then
      return 0
    fi
    # SwiftUI can briefly replace the scene-owned NSWindow while its restored
    # state hydrates. Match the visible CoreGraphics frame back to the PID-owned
    # AX window instead of depending on transient hierarchy depth or ordering.
    activate_app
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: PID-owned Project Board window frame was not stable enough to resize within ${TIMEOUT_SECONDS}s" >&2
      return 1
    fi
    sleep 0.2
  done
}

assert_window_respects_minimum() {
  wait_for_window_metadata
  if (( window_width < 960 || window_height < 620 )); then
    echo "BLOCKER: native toolbar window violated 960x620 minimum: ${window_width}x${window_height}" >&2
    return 1
  fi
  printf "OK: native toolbar remains usable at minimum window size (%sx%s)\n" "$window_width" "$window_height"
}

assert_utility_menu_items_reachable() {
  local automation_title="$1"
  local localized_automation_title="$2"
  click_first_ax_identifier "project-board-integrations-menu"
  /usr/bin/osascript - "$APP_NAME" "$app_pid" "$automation_title" "$localized_automation_title" <<'APPLESCRIPT' >/dev/null
on containsEitherNamedMenuItem(uiElement, primaryName, localizedName, depth)
  tell application "System Events"
    try
      if role of uiElement is "AXMenuItem" then
        set elementName to name of uiElement
        if elementName is primaryName or elementName is localizedName then return true
      end if
    end try
    if depth < 4 then
      try
        repeat with childElement in UI elements of uiElement
          if my containsEitherNamedMenuItem(childElement, primaryName, localizedName, depth + 1) then return true
        end repeat
      end try
    end if
  end tell
  return false
end containsEitherNamedMenuItem

on run argv
  set appName to item 1 of argv
  set targetPID to (item 2 of argv) as integer
  set automationTitle to item 3 of argv
  set localizedAutomationTitle to item 4 of argv
  tell application "System Events"
    set matchingProcesses to every process whose unix id is targetPID
    if (count of matchingProcesses) is not 1 then error "owned process missing"
    tell item 1 of matchingProcesses
      repeat with candidateWindow in windows
        if my containsEitherNamedMenuItem(candidateWindow, automationTitle, localizedAutomationTitle, 0) then
          key code 53
          return true
        end if
      end repeat
      error "owned Project Board utility menu missing"
    end tell
  end tell
end run
APPLESCRIPT
  printf "OK: automation is reachable from native toolbar overflow\n"
}

open_utilities_menu() {
  click_first_ax_identifier "project-board-integrations-menu"
}

wait_for_file_panel_and_cancel() {
  local label="$1"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while true; do
    if /usr/bin/osascript - "$APP_NAME" "$app_pid" <<'APPLESCRIPT' >/dev/null 2>&1
on pressCancel(uiElement, depth)
  tell application "System Events"
    set identifierValue to ""
    try
      set identifierValue to value of attribute "AXIdentifier" of uiElement
    end try
    if identifierValue is "CancelButton" then
      perform action "AXPress" of uiElement
      return true
    end if
    if depth < 8 then
      try
        repeat with childElement in UI elements of uiElement
          if my pressCancel(childElement, depth + 1) then return true
        end repeat
      end try
    end if
  end tell
  return false
end pressCancel

on run argv
  set appName to item 1 of argv
  set targetPID to (item 2 of argv) as integer
  tell application "System Events"
    set matchingProcesses to every process whose unix id is targetPID
    if (count of matchingProcesses) is not 1 then error "owned process missing"
    tell item 1 of matchingProcesses
      repeat with candidateWindow in windows
        if my pressCancel(candidateWindow, 0) then return true
      end repeat
    end tell
  end tell
  error "file panel not visible yet"
end run
APPLESCRIPT
    then
      printf "OK: %s opened a cancellable file panel\n" "$label"
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: $label did not open a cancellable file panel" >&2
      return 1
    fi
    sleep 0.2
  done
}

exercise_file_utility() {
  local identifier="$1"
  local label="$2"
  open_utilities_menu
  click_first_ax_identifier "$identifier"
  wait_for_file_panel_and_cancel "$label"
  # AX closes the native panel asynchronously; do not let the next toolbar
  # action target controls behind a still-active modal surface.
  wait_for_ax_identifier_absent "open-panel"
  restore_project_board_window
}

assert_google_calendar_utility_is_safely_disabled() {
  open_utilities_menu
  /usr/bin/osascript - "$APP_NAME" "$app_pid" <<'APPLESCRIPT' >/dev/null
on findGoogleCalendarItem(uiElement, depth)
  tell application "System Events"
    try
      if role of uiElement is "AXMenuItem" then
        set itemName to name of uiElement
        if itemName is "Google Calendar Sync" or itemName is "Googleカレンダー同期" then
          if enabled of uiElement then error "Google Calendar utility unexpectedly enabled"
          return true
        end if
      end if
    end try
    if depth < 4 then
      try
        repeat with childElement in UI elements of uiElement
          if my findGoogleCalendarItem(childElement, depth + 1) then return true
        end repeat
      end try
    end if
  end tell
  return false
end findGoogleCalendarItem

on run argv
  set appName to item 1 of argv
  set targetPID to (item 2 of argv) as integer
  tell application "System Events"
    set matchingProcesses to every process whose unix id is targetPID
    if (count of matchingProcesses) is not 1 then error "owned process missing"
    tell item 1 of matchingProcesses
      repeat with candidateWindow in windows
        if my findGoogleCalendarItem(candidateWindow, 0) then
          key code 53
          return true
        end if
      end repeat
      error "Google Calendar utility missing"
    end tell
  end tell
end run
APPLESCRIPT
  printf "OK: Google Calendar utility exposes the safe disabled readiness state\n"
}

exercise_automation_utility() {
  open_utilities_menu
  click_first_ax_identifier "project-board-task-auto-execution-review"
  wait_for_ax_identifier_present "task-inspector"
  click_first_ax_identifier "task-inspector-close"
  wait_for_ax_identifier_absent "task-inspector"
  restore_project_board_window
  printf "OK: task automation utility opened and closed its review inspector\n"
}

close_window_containing_identifier() {
  local identifier="$1"
  /usr/bin/osascript - "$app_pid" "$identifier" <<'APPLESCRIPT' >/dev/null
on containsIdentifier(uiElement, targetIdentifier, depth)
  tell application "System Events"
    try
      if value of attribute "AXIdentifier" of uiElement is targetIdentifier then return true
    end try
    if depth < 10 then
      try
        repeat with childElement in UI elements of uiElement
          if my containsIdentifier(childElement, targetIdentifier, depth + 1) then return true
        end repeat
      end try
    end if
  end tell
  return false
end containsIdentifier

on run argv
  set targetPID to item 1 of argv as integer
  set targetIdentifier to item 2 of argv
  tell application "System Events"
    set matchingProcesses to application processes whose unix id is targetPID
    if (count of matchingProcesses) is not 1 then error "owned process missing"
    tell item 1 of matchingProcesses
      repeat with candidateWindow in windows
        if my containsIdentifier(candidateWindow, targetIdentifier, 0) then
          perform action "AXPress" of (first button of candidateWindow whose subrole is "AXCloseButton")
          return true
        end if
      end repeat
    end tell
  end tell
  error "window containing identifier not found: " & targetIdentifier
end run
APPLESCRIPT
}

press_ax_button() {
  local identifier="$1"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while true; do
    if /usr/bin/swift "$ROOT_DIR/script/ui_evidence_ax_press_button.swift" \
      "$app_pid" "$identifier" >/dev/null 2>&1; then
      return 0
    fi
    activate_app
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: PID-owned AX button was not pressable within ${TIMEOUT_SECONDS}s: $identifier" >&2
      return 1
    fi
    sleep 0.2
  done
}

exercise_sidebar_entrypoints() {
  press_ax_button "sidebar-open-search"
  wait_for_ax_identifier_present "command-palette-input"
  launch_header_layout_candidate
  wait_for_project_detail_visible
  press_ax_button "sidebar-action-voice-command"
  wait_for_process_ax_identifier "voice-command-quick-command-tab" "present"
  close_window_containing_identifier "voice-command-quick-command-tab"
  restore_project_board_window
  printf "OK: sidebar Search and Voice Command opened their destination surfaces\n"
}

exercise_settings_utility() {
  ensure_sidebar_visible
  press_ax_button "sidebar-action-settings"
  wait_for_process_ax_identifier "settings-status-overview" "present"
  close_window_containing_identifier "settings-status-overview"
  restore_project_board_window
  printf "OK: sidebar Settings opened and closed the verified Settings window\n"
}

ensure_sidebar_visible() {
  local probe_file="$OUTPUT_DIR/sidebar-visibility.tsv"
  if toolbar_items_deduplicated >"$probe_file" 2>/dev/null &&
    awk -F $'\t' '$1 == "project-board-sidebar" { found = 1 } END { exit(found ? 0 : 1) }' "$probe_file"; then
    return 0
  fi
  click_sidebar_toggle
  wait_for_ax_identifier_present "project-board-sidebar"
}

press_keyboard_shortcut() {
  local key_code="$1"
  local modifier="$2"
  /usr/bin/osascript - "$app_pid" "$key_code" "$modifier" <<'APPLESCRIPT' >/dev/null
on run argv
  set targetPID to item 1 of argv as integer
  set targetKeyCode to item 2 of argv as integer
  set modifierName to item 3 of argv
  tell application "System Events"
    set matchingProcesses to application processes whose unix id is targetPID
    if (count of matchingProcesses) is not 1 then error "owned process missing"
    tell item 1 of matchingProcesses
      set frontmost to true
      if modifierName is "command" then
        key code targetKeyCode using command down
      else if modifierName is "command-shift" then
        key code targetKeyCode using {command down, shift down}
      else
        error "unsupported shortcut modifier"
      end if
    end tell
  end tell
end run
APPLESCRIPT
}

exercise_keyboard_entrypoints() {
  click_sidebar_toggle
  wait_for_ax_identifier_absent "project-board-sidebar"

  press_keyboard_shortcut 40 "command"
  wait_for_ax_identifier_present "command-palette-input"
  launch_header_layout_candidate
  wait_for_project_detail_visible
  click_sidebar_toggle
  wait_for_ax_identifier_absent "project-board-sidebar"
  press_keyboard_shortcut 9 "command-shift"
  wait_for_process_ax_identifier "voice-command-quick-command-tab" "present"

  launch_header_layout_candidate
  wait_for_project_detail_visible
  click_sidebar_toggle
  wait_for_ax_identifier_absent "project-board-sidebar"
  press_keyboard_shortcut 43 "command"
  wait_for_process_ax_identifier "settings-status-overview" "present"

  launch_header_layout_candidate
  wait_for_project_detail_visible
  printf "OK: hidden-sidebar keyboard shortcuts opened Search, Voice Command, and Settings\n"
}

exercise_runtime_crud_recovery_entrypoints() {
  launch_runtime_crud_recovery_candidate
  wait_for_process_ax_identifier "project-board-settings-link" "present"

  press_ax_button "project-board-settings-link"
  wait_for_process_ax_identifier "settings-status-overview" "present"
  close_window_containing_identifier "settings-status-overview"

  activate_app
  press_ax_button "project-board-voice-command"
  wait_for_process_ax_identifier "voice-command-quick-command-tab" "present"
  close_window_containing_identifier "voice-command-quick-command-tab"
  printf "OK: runtime CRUD recovery Settings and Voice Command reached their destination windows\n"
}

exercise_terminal_utility() {
  open_utilities_menu
  click_first_ax_identifier "project-board-terminal-toggle"
  wait_for_ax_identifier_present "embedded-terminal-close"
  click_first_ax_identifier "embedded-terminal-close"
  wait_for_ax_identifier_absent "embedded-terminal-close"
  restore_project_board_window
  printf "OK: developer Terminal utility opened and closed the embedded panel\n"
}

exercise_toolbar_utilities() {
  exercise_file_utility "project-board-export-tasks" "Export Tasks"
  exercise_file_utility "project-board-import-tasks" "Import Tasks"
  assert_google_calendar_utility_is_safely_disabled
  exercise_automation_utility
  exercise_settings_utility
  exercise_terminal_utility
}

read_window_metadata() {
  local output
  output="$(
    SUISUI_WINDOW_OWNER="$APP_NAME" \
    SUISUI_WINDOW_OWNER_PID="$app_pid" \
    SUISUI_WINDOW_NAME="$WINDOW_NAME" \
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
      end try
      try
        click uiElement
      end try
      try
        set itemPosition to position of uiElement
        set itemSize to size of uiElement
        click at {((item 1 of itemPosition) + ((item 1 of itemSize) / 2)), ((item 2 of itemPosition) + ((item 2 of itemSize) / 2))}
        return true
      end try
      return true
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

close_hydrated_loading_window() {
  /usr/bin/osascript - "$app_pid" <<'APPLESCRIPT' >/dev/null
on containsIdentifier(uiElement, targetIdentifier, depth)
  tell application "System Events"
    try
      if value of attribute "AXIdentifier" of uiElement is targetIdentifier then return true
    end try
    if depth < 8 then
      try
        repeat with childElement in UI elements of uiElement
          if my containsIdentifier(childElement, targetIdentifier, depth + 1) then return true
        end repeat
      end try
    end if
  end tell
  return false
end containsIdentifier

on run argv
  set targetPID to (item 1 of argv) as integer
  tell application "System Events"
    set matchingProcesses to every process whose unix id is targetPID
    if (count of matchingProcesses) is not 1 then error "owned process missing"
    tell item 1 of matchingProcesses
      repeat with candidateWindow in windows
        if my containsIdentifier(candidateWindow, "project-board-fallback-loading", 0) then
          perform action "AXPress" of (first button of candidateWindow whose subrole is "AXCloseButton")
        end if
      end repeat
    end tell
  end tell
end run
APPLESCRIPT
}

wait_for_project_detail_visible() {
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local probe_file="$OUTPUT_DIR/project-detail-probe.tsv"
  while true; do
    ensure_project_detail_visible
    if toolbar_items_deduplicated >"$probe_file" 2>"$OUTPUT_DIR/project-detail-probe.err" &&
      awk -F $'\t' '$1 == "project-board-detail" { found = 1 } END { exit(found ? 0 : 1) }' "$probe_file"; then
      # Direct evidence launches can leave the first-paint loading window next
      # to the hydrated board. Close only that identified temporary surface so
      # CGWindow screenshot selection cannot capture stale launch chrome.
      close_hydrated_loading_window
      wait_for_window_metadata
      return 0
    fi

    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: Project Board detail was not visible within ${TIMEOUT_SECONDS}s" >&2
      cat "$probe_file" >&2 || true
      return 1
    fi
    sleep 0.2
  done
}

capture_window() {
  local label="$1"
  restore_project_board_window
  assert_primary_ax_frames_are_nonzero
  sleep 0.5
  local screenshot_path="$OUTPUT_DIR/project-board-${label}.png"
  /usr/sbin/screencapture -x -o -l "$window_id" "$screenshot_path"
  if [[ ! -s "$screenshot_path" ]]; then
    echo "BLOCKER: screenshot was not written for $label at $screenshot_path" >&2
    return 1
  fi
  assert_capture_dimensions "$screenshot_path"
  assert_screenshot_has_visible_pixels "$screenshot_path"
  assert_semantic_regions_have_visible_variance "$screenshot_path"
  printf "OK: captured %s header layout screenshot (%s)\n" "$label" "$screenshot_path"
}

assert_primary_ax_frames_are_nonzero() {
  local frame_file="$OUTPUT_DIR/screenshot-primary-frames.tsv"
  toolbar_items_deduplicated >"$frame_file"
  for identifier in project-board-sidebar-toggle project-board-sidebar project-board-detail; do
    if ! awk -F $'\t' -v wanted="$identifier" '
      $1 == wanted && $4 + 0 > 0 && $5 + 0 > 0 { found = 1 }
      END { exit(found ? 0 : 1) }
    ' "$frame_file"; then
      echo "BLOCKER: screenshot prerequisite has a missing or zero-sized AX frame: $identifier" >&2
      cat "$frame_file" >&2
      return 1
    fi
  done
}

assert_capture_dimensions() {
  local screenshot_path="$1"
  local pixel_width pixel_height
  pixel_width="$(/usr/bin/sips -g pixelWidth "$screenshot_path" | awk '/pixelWidth:/ { print $2 }')"
  pixel_height="$(/usr/bin/sips -g pixelHeight "$screenshot_path" | awk '/pixelHeight:/ { print $2 }')"
  if [[ ! "$pixel_width" =~ ^[0-9]+$ || ! "$pixel_height" =~ ^[0-9]+$ ||
        "$pixel_width" -lt "$window_width" || "$pixel_height" -lt "$window_height" ]]; then
    echo "BLOCKER: screenshot dimensions do not cover the Project Board window: capture=${pixel_width:-missing}x${pixel_height:-missing} window=${window_width}x${window_height}" >&2
    return 1
  fi
}

assert_screenshot_has_visible_pixels() {
  local screenshot_path="$1"
  if ! /usr/bin/swift "$ROOT_DIR/script/ui_evidence_content_check.swift" "$screenshot_path" >/dev/null; then
    echo "BLOCKER: native toolbar screenshot is blank, black, or incomplete: $screenshot_path" >&2
    return 1
  fi
}

assert_ax_region_has_visible_variance() {
  local screenshot_path="$1"
  local identifier="$2"
  local frame_file="$OUTPUT_DIR/screenshot-primary-frames.tsv"
  local frame_x frame_y frame_width frame_height relative_x relative_y
  local pixel_width pixel_height scale_x scale_y pixel_x pixel_y pixel_region_width pixel_region_height
  IFS=$'\t' read -r _ frame_x frame_y frame_width frame_height < <(
    awk -F $'\t' -v wanted="$identifier" '$1 == wanted || index($1, wanted "-") == 1 { print; exit }' "$frame_file"
  )
  if [[ -z "${frame_x:-}" || -z "${frame_y:-}" || -z "${frame_width:-}" || -z "${frame_height:-}" ]]; then
    echo "BLOCKER: semantic screenshot region is missing from AX evidence: $identifier" >&2
    return 1
  fi
  relative_x=$((frame_x - window_x))
  relative_y=$((frame_y - window_y))
  pixel_width="$(/usr/bin/sips -g pixelWidth "$screenshot_path" | awk '/pixelWidth:/ { print $2 }')"
  pixel_height="$(/usr/bin/sips -g pixelHeight "$screenshot_path" | awk '/pixelHeight:/ { print $2 }')"
  scale_x="$(awk -v pixels="$pixel_width" -v points="$window_width" 'BEGIN { printf "%.8f", pixels / points }')"
  scale_y="$(awk -v pixels="$pixel_height" -v points="$window_height" 'BEGIN { printf "%.8f", pixels / points }')"
  pixel_x="$(scaled_region_component "$relative_x" "$scale_x" "$pixel_width" 0)"
  pixel_y="$(scaled_region_component "$relative_y" "$scale_y" "$pixel_height" 0)"
  pixel_region_width="$(scaled_region_component "$frame_width" "$scale_x" "$((pixel_width - pixel_x))" 1)"
  pixel_region_height="$(scaled_region_component "$frame_height" "$scale_y" "$((pixel_height - pixel_y))" 1)"
  if ! /usr/bin/swift "$ROOT_DIR/script/ui_evidence_content_check.swift" \
    "$screenshot_path" "$pixel_x" "$pixel_y" "$pixel_region_width" "$pixel_region_height" >/dev/null; then
    echo "BLOCKER: semantic screenshot region lacks visible composed content: $identifier" >&2
    return 1
  fi
}

scaled_region_component() {
  local point_value="$1"
  local scale="$2"
  local maximum="$3"
  local minimum="${4:-0}"
  awk -v points="$point_value" -v scale="$scale" -v maximum="$maximum" -v minimum="$minimum" '
    BEGIN {
      value = int(points * scale + 0.5)
      if (value < minimum) value = minimum
      if (value > maximum) value = maximum
      print value
    }
  '
}

assert_scaled_region_component_contract() {
  [[ "$(scaled_region_component 24 1 100 0)" == "24" ]] ||
    { echo "BLOCKER: 1x AX point-to-image pixel conversion regressed" >&2; return 1; }
  [[ "$(scaled_region_component 24 2 100 0)" == "48" ]] ||
    { echo "BLOCKER: 2x AX point-to-image pixel conversion regressed" >&2; return 1; }
  [[ "$(scaled_region_component 80 2 100 0)" == "100" ]] ||
    { echo "BLOCKER: AX point-to-image pixel conversion no longer clamps" >&2; return 1; }
}

assert_semantic_regions_have_visible_variance() {
  local screenshot_path="$1"
  # These regions are expected to contain visible controls or seeded task
  # content even when the remainder of the dark board canvas is intentionally empty.
  assert_ax_region_has_visible_variance "$screenshot_path" "project-header-add-task"
  assert_ax_region_has_visible_variance "$screenshot_path" "task-card-open-details"
}

toolbar_items() {
  /usr/bin/osascript - "$APP_NAME" "$app_pid" <<'APPLESCRIPT'
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
      if titleValue is "Utilities" or titleValue is "ユーティリティ" or titleValue is "Integrations" or titleValue is "連携" then
        set identifierValue to "project-board-integrations-menu"
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

on containsIdentifier(uiElement, targetIdentifier, depth)
  tell application "System Events"
    try
      if value of attribute "AXIdentifier" of uiElement is targetIdentifier then return true
    end try
    if depth < 8 then
      try
        repeat with childElement in UI elements of uiElement
          if my containsIdentifier(childElement, targetIdentifier, depth + 1) then return true
        end repeat
      end try
    end if
  end tell
  return false
end containsIdentifier

on run argv
  set appName to item 1 of argv
  set targetPID to (item 2 of argv) as integer
  tell application "System Events"
    set matchingProcesses to every process whose unix id is targetPID
    if (count of matchingProcesses) is not 1 then error "owned process missing"
    tell item 1 of matchingProcesses
      set outputLines to {}
      repeat with candidateWindow in windows
        if my containsIdentifier(candidateWindow, "project-board-detail", 0) then
          if (exists toolbar 1 of candidateWindow) then
            repeat with toolbarItem in UI elements of toolbar 1 of candidateWindow
              set identifierValue to ""
              try
                set identifierValue to value of attribute "AXIdentifier" of toolbarItem
              end try
              set roleValue to ""
              try
                set roleValue to role of toolbarItem
              end try
              -- SwiftUI toolbar Menu is exposed as an anonymous AXGroup on macOS.
              if identifierValue is equal to "" and roleValue is "AXGroup" then
                set identifierValue to "project-board-integrations-menu"
              end if
              set outputLines to my appendIdentifiedElement(outputLines, toolbarItem, identifierValue)
            end repeat
          end if
          set outputLines to my collectIdentifiedElements(outputLines, candidateWindow)
          exit repeat
        end if
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
  local sidebar_x inspector_x utilities_x utilities_width window_right

  while true; do
    wait_for_window_metadata
    wait_for_toolbar_buttons "$label"

    assert_button_present "project-board-sidebar-toggle"
    assert_button_present "project-board-inspector-toggle"
    assert_button_present "project-board-integrations-menu"

    sidebar_x="$(button_x "project-board-sidebar-toggle")"
    inspector_x="$(button_x "project-board-inspector-toggle")"
    utilities_x="$(button_x "project-board-integrations-menu")"
    utilities_width="$(button_width "project-board-integrations-menu")"
    window_right=$((window_x + window_width))

    if (( sidebar_x < inspector_x &&
          inspector_x < utilities_x &&
          utilities_x + utilities_width <= window_right )); then
      printf "OK: native toolbar actions fit without overlap for %s\n" "$label"
      return 0
    fi

    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: native toolbar controls overlap or clip for $label" >&2
      echo "window=($window_x,$window_y ${window_width}x${window_height})" >&2
      cat "$button_state_file" >&2
      return 1
    fi

    sleep 0.1
  done
}

toolbar_position_signature() {
  awk -F $'\t' '
    $1 == "project-board-sidebar-toggle" ||
    $1 == "project-board-inspector-toggle" ||
    $1 == "project-board-integrations-menu" {
      print $1 ":" $2 ":" $3 ":" $4 ":" $5
    }
  ' "$1"
}

assert_toolbar_layout_is_stable() {
  local label="$1"
  local samples="${2:-5}"
  local baseline_file="$OUTPUT_DIR/toolbar-${label}-sample-0.tsv"
  local baseline_signature sample_file sample_signature

  # SwiftUI can briefly detach and reattach the NSWindow while native split
  # chrome changes. Reconnect to the PID-owned AX window before sampling.
  wait_for_visible_windows
  if ! toolbar_items_deduplicated >"$baseline_file" 2>"$OUTPUT_DIR/toolbar-${label}-sample-0.err"; then
    echo "BLOCKER: header layout stability baseline failed after $label" >&2
    cat "$OUTPUT_DIR/toolbar-${label}-sample-0.err" >&2 || true
    return 1
  fi
  baseline_signature="$(toolbar_position_signature "$baseline_file")"

  for ((sample = 1; sample <= samples; sample += 1)); do
    sample_file="$OUTPUT_DIR/toolbar-${label}-sample-${sample}.tsv"
    if ! toolbar_items_deduplicated >"$sample_file" 2>"$OUTPUT_DIR/toolbar-${label}-sample-${sample}.err"; then
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

click_first_ax_identifier() {
  local target_identifier="$1"
  /usr/bin/osascript - "$APP_NAME" "$app_pid" "$target_identifier" <<'APPLESCRIPT' >/dev/null
on clickMatchingIdentifier(uiElement, targetIdentifier)
  tell application "System Events"
    set identifierValue to ""
    try
      set identifierValue to value of attribute "AXIdentifier" of uiElement
    end try
    if identifierValue is targetIdentifier then
      try
        perform action "AXPress" of uiElement
        return true
      end try
      try
        click uiElement
      end try
      try
        set itemPosition to position of uiElement
        set itemSize to size of uiElement
        click at {((item 1 of itemPosition) + ((item 1 of itemSize) / 2)), ((item 2 of itemPosition) + ((item 2 of itemSize) / 2))}
        return true
      end try
      return true
    end if

    try
      repeat with childElement in UI elements of uiElement
        if my clickMatchingIdentifier(childElement, targetIdentifier) then return true
      end repeat
    end try
  end tell
  return false
end clickMatchingIdentifier

on run argv
  set appName to item 1 of argv
  set targetPID to (item 2 of argv) as integer
  set targetIdentifier to item 3 of argv
  tell application "System Events"
    set matchingProcesses to every process whose unix id is targetPID
    if (count of matchingProcesses) is not 1 then error "owned process missing"
    tell item 1 of matchingProcesses
      set frontmost to true
      repeat with candidateWindow in windows
        if my clickMatchingIdentifier(candidateWindow, targetIdentifier) then return true
      end repeat
      error "BLOCKER: AX identifier was not clickable in owned process: " & targetIdentifier
    end tell
  end tell
end run
APPLESCRIPT
}

click_ax_identifier_center() {
  local target_identifier="$1"
  /usr/bin/osascript - "$APP_NAME" "$target_identifier" <<'APPLESCRIPT' >/dev/null
on clickIdentifierCenter(uiElement, targetIdentifier)
  tell application "System Events"
    set identifierValue to ""
    try
      set identifierValue to value of attribute "AXIdentifier" of uiElement
    end try
    if identifierValue is targetIdentifier then
      set itemPosition to position of uiElement
      set itemSize to size of uiElement
      click at {((item 1 of itemPosition) + ((item 1 of itemSize) / 2)), ((item 2 of itemPosition) + ((item 2 of itemSize) / 2))}
      return true
    end if

    try
      repeat with childElement in UI elements of uiElement
        if my clickIdentifierCenter(childElement, targetIdentifier) then return true
      end repeat
    end try
  end tell
  return false
end clickIdentifierCenter

on run argv
  set appName to item 1 of argv
  set targetIdentifier to item 2 of argv
  tell application "System Events"
    tell process appName
      set frontmost to true
      if not my clickIdentifierCenter(window 1, targetIdentifier) then
        error "BLOCKER: AX identifier center was not clickable: " & targetIdentifier
      end if
    end tell
  end tell
end run
APPLESCRIPT
}

wait_for_ax_identifier_present() {
  local target_identifier="$1"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local probe_file="$OUTPUT_DIR/identifier-present-${target_identifier}.tsv"
  while true; do
    if toolbar_items_deduplicated >"$probe_file" 2>"$OUTPUT_DIR/identifier-present-${target_identifier}.err" &&
      awk -F $'\t' -v wanted="$target_identifier" '$1 == wanted { found = 1 } END { exit(found ? 0 : 1) }' "$probe_file"; then
      return 0
    fi

    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: AX identifier was not visible: $target_identifier" >&2
      cat "$probe_file" >&2 || true
      return 1
    fi
    sleep 0.2
  done
}

wait_for_ax_identifier_absent() {
  local target_identifier="$1"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local probe_file="$OUTPUT_DIR/identifier-absent-${target_identifier}.tsv"
  while true; do
    if toolbar_items_deduplicated >"$probe_file" 2>"$OUTPUT_DIR/identifier-absent-${target_identifier}.err" &&
      ! awk -F $'\t' -v wanted="$target_identifier" '$1 == wanted { found = 1 } END { exit(found ? 0 : 1) }' "$probe_file"; then
      return 0
    fi

    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: AX identifier stayed visible: $target_identifier" >&2
      cat "$probe_file" >&2 || true
      return 1
    fi
    sleep 0.2
  done
}

wait_for_process_ax_identifier() {
  local target_identifier="$1"
  local expected_presence="$2"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while true; do
    if SUISUI_UI_EVIDENCE_AX_REQUIRE_EXACT_IDENTIFIER=1 \
      /usr/bin/swift "$ROOT_DIR/script/ui_evidence_ax_marker_check.swift" \
      "$APP_NAME" "$target_identifier" "" "$app_pid" >/dev/null 2>&1; then
      [[ "$expected_presence" == "present" ]] && return 0
    else
      [[ "$expected_presence" == "absent" ]] && return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: process AX identifier did not become $expected_presence: $target_identifier" >&2
      return 1
    fi
    sleep 0.2
  done
}

click_inspector_close() {
  click_first_ax_identifier "project-inspector-close"
}

click_task_card_open_details() {
  click_first_ax_identifier "task-card-open-details"
}

click_terminal_toggle() {
  click_first_ax_identifier "project-board-terminal-toggle"
}

click_terminal_close() {
  click_first_ax_identifier "embedded-terminal-close"
}

click_project_sidebar_row() {
  local project_id="$1"
  click_ax_identifier_center "project-sidebar-row-$project_id"
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

click_project_display_mode() {
  local mode="$1"
  local target_identifier fallback_identifier
  case "$mode" in
    overview)
      target_identifier="project-display-mode-overview"
      fallback_identifier="rectangle.grid.2x2"
      ;;
    board)
      target_identifier="project-display-mode-board"
      fallback_identifier="rectangle.3.group"
      ;;
    list)
      target_identifier="project-display-mode-list"
      fallback_identifier="list.bullet"
      ;;
    *)
      echo "unknown Project display mode: $mode" >&2
      return 2
      ;;
  esac

  /usr/bin/osascript - "$APP_NAME" "$target_identifier" "$fallback_identifier" <<'APPLESCRIPT' >/dev/null
on clickMatchingDisplayMode(uiElement, targetIdentifier, fallbackIdentifier)
  tell application "System Events"
    set identifierValue to ""
    try
      set identifierValue to value of attribute "AXIdentifier" of uiElement
    end try
    if identifierValue is targetIdentifier or identifierValue is fallbackIdentifier then
      try
        perform action "AXPress" of uiElement
      end try
      try
        click uiElement
      end try
      try
        set itemPosition to position of uiElement
        set itemSize to size of uiElement
        click at {((item 1 of itemPosition) + ((item 1 of itemSize) / 2)), ((item 2 of itemPosition) + ((item 2 of itemSize) / 2))}
      end try
      return true
    end if

    try
      repeat with childElement in UI elements of uiElement
        if my clickMatchingDisplayMode(childElement, targetIdentifier, fallbackIdentifier) then return true
      end repeat
    end try
  end tell
  return false
end clickMatchingDisplayMode

on run argv
  set appName to item 1 of argv
  set targetIdentifier to item 2 of argv
  set fallbackIdentifier to item 3 of argv
  tell application "System Events"
    tell process appName
      set frontmost to true
      if not my clickMatchingDisplayMode(window 1, targetIdentifier, fallbackIdentifier) then
        error "BLOCKER: Project display mode control was not available: " & targetIdentifier
      end if
    end tell
  end tell
end run
APPLESCRIPT
}

wait_for_display_mode_content() {
  local mode="$1"
  local content_identifier
  case "$mode" in
    overview)
      content_identifier="project-overview-add-task"
      ;;
    board)
      content_identifier="project-kanban-board"
      ;;
    list)
      content_identifier="project-task-list"
      ;;
    *)
      echo "unknown Project display mode content: $mode" >&2
      return 2
      ;;
  esac

  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local probe_file="$OUTPUT_DIR/display-mode-${mode}-probe.tsv"
  while true; do
    if toolbar_items_deduplicated >"$probe_file" 2>"$OUTPUT_DIR/display-mode-${mode}-probe.err" &&
      awk -F $'\t' -v wanted="$content_identifier" '$1 == wanted { found = 1 } END { exit(found ? 0 : 1) }' "$probe_file"; then
      return 0
    fi

    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: Project display mode content was not visible for $mode: $content_identifier" >&2
      cat "$probe_file" >&2 || true
      return 1
    fi
    sleep 0.2
  done
}

set_toolbar_display_mode() {
  local mode="$1"
  local primary_title localized_title
  case "$mode" in
    icon-only)
      primary_title="Icon Only"
      localized_title="アイコンのみ"
      ;;
    icon-and-label)
      primary_title="Icon and Text"
      localized_title="アイコンとテキスト"
      ;;
    *)
      echo "unknown toolbar display mode: $mode" >&2
      return 2
      ;;
  esac

  /usr/bin/osascript - "$APP_NAME" "$primary_title" "$localized_title" <<'APPLESCRIPT' >/dev/null
on pressDisplayModeMenuItem(toolbarElement, primaryTitle, localizedTitle)
  tell application "System Events"
    repeat with attempt from 1 to 20
      if (exists menu 1 of toolbarElement) then
        tell menu 1 of toolbarElement
          if exists menu item primaryTitle then
            perform action "AXPress" of menu item primaryTitle
            return true
          end if
          if exists menu item localizedTitle then
            perform action "AXPress" of menu item localizedTitle
            return true
          end if
        end tell
      end if
      delay 0.05
    end repeat
  end tell
  return false
end pressDisplayModeMenuItem

on run argv
  set appName to item 1 of argv
  set primaryTitle to item 2 of argv
  set localizedTitle to item 3 of argv
  tell application "System Events"
    tell process appName
      set frontmost to true
      tell toolbar 1 of window 1
        perform action "AXShowMenu"
        if my pressDisplayModeMenuItem(it, primaryTitle, localizedTitle) is false then
          error "BLOCKER: toolbar display mode menu item was not available: " & primaryTitle & " / " & localizedTitle
        end if
      end tell
    end tell
  end tell
end run
APPLESCRIPT
}

trap terminate_app EXIT

prepare_header_layout_candidate
assert_scaled_region_component_contract
seed_header_layout_selection_project
launch_header_layout_candidate
wait_for_project_detail_visible

if [[ "${SUISUI_HEADER_LAYOUT_ENTRYPOINTS_ONLY:-0}" == "1" ]]; then
  exercise_sidebar_entrypoints
  exercise_keyboard_entrypoints
  exercise_settings_utility
  exercise_runtime_crud_recovery_entrypoints
  printf "OK: Project Board relocated entrypoint smoke passed\n"
  exit 0
fi

assert_single_native_toolbar
capture_window "sidebar-visible"
assert_action_buttons_are_trailing "sidebar-visible"

resize_window_below_minimum
wait_for_visible_windows
assert_window_respects_minimum
assert_action_buttons_are_trailing "minimum-window"
capture_window "minimum-window"
assert_utility_menu_items_reachable "Review Task Automation" "タスク自動化を確認"
exercise_sidebar_entrypoints
exercise_keyboard_entrypoints
exercise_toolbar_utilities

launch_header_layout_candidate "japanese"
wait_for_project_detail_visible
assert_single_native_toolbar
resize_window_below_minimum
wait_for_visible_windows
assert_window_respects_minimum
assert_action_buttons_are_trailing "minimum-window-japanese"
capture_window "minimum-window-japanese"
assert_utility_menu_items_reachable "Review Task Automation" "タスク自動化を確認"
exercise_sidebar_entrypoints
exercise_toolbar_utilities

exercise_runtime_crud_recovery_entrypoints

printf "OK: Project Board header layout smoke passed\n"
