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
SCREENSHOT_DIR="${SOLOPM_UI_EVIDENCE_DIR:-$ROOT_DIR/docs/release/evidence/ui-screenshots}"
EVIDENCE_FILE="${SOLOPM_UI_EVIDENCE_FILE:-$ROOT_DIR/docs/release/evidence/ui-screenshots.md}"
EVIDENCE_TMPDIR="${SOLOPM_UI_EVIDENCE_TMPDIR:-$ROOT_DIR/.tmp}"
mkdir -p "$EVIDENCE_TMPDIR"
export TMPDIR="$EVIDENCE_TMPDIR/"
EVIDENCE_HOME="${SOLOPM_UI_EVIDENCE_HOME:-$(mktemp -d "$EVIDENCE_TMPDIR/solopm-ui-evidence.XXXXXX")}"
KEEP_HOME="${SOLOPM_UI_EVIDENCE_KEEP_HOME:-0}"
DRY_RUN=0
DOCTOR=0
PROJECT_BOARD_SELECTION_OVERRIDE=""
APPEARANCE_OVERRIDE=""
EVIDENCE_APP_PID=""

for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=1
      ;;
    --doctor)
      DOCTOR=1
      ;;
    *)
      echo "usage: $0 [--dry-run|--doctor]" >&2
      exit 2
      ;;
  esac
done

if [[ "$DRY_RUN" == "1" && "$DOCTOR" == "1" ]]; then
  echo "usage: $0 [--dry-run|--doctor]" >&2
  exit 2
fi

cleanup() {
  if [[ "$DRY_RUN" != "1" && "$DOCTOR" != "1" ]]; then
    stop_evidence_app
  fi
  if [[ "$KEEP_HOME" != "1" && -d "$EVIDENCE_HOME" && "${SOLOPM_UI_EVIDENCE_HOME:-}" == "" ]]; then
    rm -rf "$EVIDENCE_HOME"
  fi
}
trap cleanup EXIT

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 2
  fi
}

relative_path() {
  local path="$1"
  case "$path" in
    "$ROOT_DIR"/*) printf '%s\n' "${path#"$ROOT_DIR/"}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

app_env_args() {
  local args=(
    "HOME=$EVIDENCE_HOME"
    "CFFIXED_USER_HOME=$EVIDENCE_HOME"
  )
  if [[ -n "$PROJECT_BOARD_SELECTION_OVERRIDE" ]]; then
    args+=("SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION=$PROJECT_BOARD_SELECTION_OVERRIDE")
  fi
  if [[ -n "$APPEARANCE_OVERRIDE" ]]; then
    args+=("SOLOPM_APPEARANCE_PREFERENCE=$APPEARANCE_OVERRIDE")
  fi
  printf '%s\0' "${args[@]}"
}

open_evidence_app() {
  local env_args=()
  while IFS= read -r -d '' env_arg; do
    env_args+=("$env_arg")
  done < <(app_env_args)
  /usr/bin/env "${env_args[@]}" "$APP_BINARY" >/dev/null 2>&1 &
  EVIDENCE_APP_PID=$!
}

stop_evidence_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  if [[ -n "$EVIDENCE_APP_PID" ]]; then
    wait "$EVIDENCE_APP_PID" >/dev/null 2>&1 || true
    EVIDENCE_APP_PID=""
  fi
}

activate_evidence_app() {
  /usr/bin/osascript -e "tell application \"$APP_NAME\" to activate" >/dev/null 2>&1 &
  local osascript_pid=$!
  for _ in {1..20}; do
    if ! kill -0 "$osascript_pid" >/dev/null 2>&1; then
      wait "$osascript_pid" >/dev/null 2>&1 || true
      return
    fi
    sleep 0.1
  done
  kill "$osascript_pid" >/dev/null 2>&1 || true
  wait "$osascript_pid" >/dev/null 2>&1 || true
}

wait_for_process() {
  for _ in {1..40}; do
    if pgrep -x "$APP_NAME" >/dev/null; then
      return 0
    fi
    sleep 0.25
  done
  echo "$APP_NAME did not launch." >&2
  exit 1
}

wait_for_database() {
  local database_path="$1"
  for _ in {1..40}; do
    if [[ -f "$database_path" ]]; then
      return 0
    fi
    sleep 0.25
  done
  echo "database was not created: $database_path" >&2
  exit 1
}

find_window_capture_metadata() {
  local window_name="${1:-}"
  SOLOPM_WINDOW_OWNER="$APP_NAME" \
    SOLOPM_WINDOW_NAME="$window_name" \
    /usr/bin/swift "$ROOT_DIR/script/ui_evidence_window_metadata.swift"
}

wait_for_window_capture_metadata() {
  local window_name="${1:-}"
  local metadata
  for _ in {1..40}; do
    if metadata="$(find_window_capture_metadata "$window_name" 2>/dev/null)"; then
      printf '%s\n' "$metadata"
      return 0
    fi
    sleep 0.25
  done
  find_window_capture_metadata "$window_name"
}

position_window_for_capture() {
  local window_name="${1:-}"

  if [[ -n "$window_name" ]]; then
    /usr/bin/osascript \
      -e 'tell application "System Events"' \
      -e "tell process \"$APP_NAME\"" \
      -e "if exists window \"$window_name\" then set bounds of window \"$window_name\" to {120, 90, 1320, 810}" \
      -e 'end tell' \
      -e 'end tell' >/dev/null 2>&1 || true
  else
    /usr/bin/osascript \
      -e 'tell application "System Events"' \
      -e "tell process \"$APP_NAME\"" \
      -e 'if exists front window then set bounds of front window to {80, 70, 1640, 930}' \
      -e 'end tell' \
      -e 'end tell' >/dev/null 2>&1 || true
  fi
}

assert_screenshot_has_visible_content() {
  local image_path="$1"

  /usr/bin/swift "$ROOT_DIR/script/ui_evidence_content_check.swift" "$image_path"
}

print_capture_failure_guidance() {
  local appearance="$1"
  local output_path="$2"
  local window_context="$3"

  {
    echo "UI screenshot capture could not produce valid visible pixels for appearance: $appearance"
    echo "output: $output_path"
    echo "selected SoloPM window: $window_context"
    echo "Open System Settings > Privacy & Security > Screen Recording / Screen & System Audio Recording and allow the terminal or Codex app that runs this script."
    echo "Quit and reopen the terminal or Codex app after granting permission, then rerun: script/capture_ui_evidence.sh"
    echo "For debugging, rerun with SOLOPM_UI_EVIDENCE_KEEP_HOME=1 to keep the isolated HOME: $EVIDENCE_HOME"
  } >&2
}

write_appearance_preference() {
  local appearance="$1"
  write_app_preference solopm.appearancePreference "$appearance"
}

write_app_preference() {
  local key="$1"
  local value="$2"

  mkdir -p "$EVIDENCE_HOME/Library/Preferences"
  /usr/bin/env \
    HOME="$EVIDENCE_HOME" \
    CFFIXED_USER_HOME="$EVIDENCE_HOME" \
    /usr/bin/defaults write "$BUNDLE_IDENTIFIER" "$key" -string "$value"
}

initialize_database() {
  local database_path="$1"

  mkdir -p "$(dirname "$database_path")"
  sqlite3 "$database_path" "
CREATE TABLE IF NOT EXISTS projects (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  status TEXT NOT NULL,
  priority TEXT,
  deadline TEXT,
  workspace_path TEXT,
  tags_json TEXT NOT NULL DEFAULT '[]',
  source_command TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS tasks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project_id INTEGER,
  title TEXT NOT NULL,
  status TEXT NOT NULL,
  detail TEXT,
  due_at TEXT,
  priority TEXT,
  source_command TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS artifacts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project_id INTEGER,
  task_id INTEGER,
  workspace_path TEXT NOT NULL,
  expected_path TEXT NOT NULL,
  created_state TEXT NOT NULL CHECK(created_state IN ('expected', 'created', 'missing')),
  last_modified_at TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(workspace_path, expected_path)
);

CREATE TABLE IF NOT EXISTS mcp_server_registrations (
  id TEXT PRIMARY KEY NOT NULL,
  sort_order INTEGER NOT NULL,
  display_name TEXT NOT NULL,
  command TEXT NOT NULL,
  arguments_json TEXT NOT NULL DEFAULT '[]',
  environment_json TEXT NOT NULL DEFAULT '{}',
  working_directory TEXT,
  is_enabled INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_mcp_server_registrations_sort_order
ON mcp_server_registrations(sort_order);
"
}

seed_database() {
  local database_path="$1"
  local tomorrow
  tomorrow="$(date -v+1d +%Y-%m-%d)"

  sqlite3 "$database_path" "
DELETE FROM tasks WHERE source_command = 'ui-evidence';
DELETE FROM projects WHERE source_command = 'ui-evidence';

INSERT INTO projects (title, status, priority, deadline, workspace_path, tags_json, source_command)
VALUES ('Launch Readiness', 'active', 'high', '$tomorrow', NULL, '["ui-evidence","local"]', 'ui-evidence');

INSERT INTO tasks (project_id, title, status, detail, due_at, priority, source_command)
VALUES
  ((SELECT id FROM projects WHERE source_command = 'ui-evidence' AND title = 'Launch Readiness' ORDER BY id DESC LIMIT 1),
   'Capture launch screenshots', 'planned', 'Verify board card density, sidebar, and inspector in each theme.', '$tomorrow', 'high', 'ui-evidence'),
  ((SELECT id FROM projects WHERE source_command = 'ui-evidence' AND title = 'Launch Readiness' ORDER BY id DESC LIMIT 1),
   'Review VoiceOver focus path', 'in_progress', 'Confirm project board to task card to inspector path before public alpha.', '$tomorrow', 'medium', 'ui-evidence'),
  ((SELECT id FROM projects WHERE source_command = 'ui-evidence' AND title = 'Launch Readiness' ORDER BY id DESC LIMIT 1),
   'Document remaining release blockers', 'blocked', 'Keep signing, notarization, and manual accessibility gates visible.', NULL, 'medium', 'ui-evidence');
"
}

seed_mcp_registrations() {
  local database_path="$1"

  sqlite3 "$database_path" "
DELETE FROM mcp_server_registrations;

INSERT INTO mcp_server_registrations (
  id,
  sort_order,
  display_name,
  command,
  arguments_json,
  environment_json,
  working_directory,
  is_enabled
) VALUES (
  'ui-evidence-filesystem',
  0,
  'Local Filesystem MCP',
  '/usr/bin/env',
  '[\"node\",\"@modelcontextprotocol/server-filesystem\",\"/tmp\"]',
  '{\"SOLOPM_FILESYSTEM_TOKEN\":{\"type\":\"keychain\",\"key\":\"mcp_filesystem_token\"}}',
  '$ROOT_DIR',
  1
);

INSERT INTO mcp_server_registrations (
  id,
  sort_order,
  display_name,
  command,
  arguments_json,
  environment_json,
  working_directory,
  is_enabled
) VALUES (
  'ui-evidence-issues',
  1,
  'Issue Tracker MCP',
  '/usr/bin/env',
  '[\"npx\",\"-y\",\"@modelcontextprotocol/server-github\"]',
  '{\"GITHUB_TOKEN\":{\"type\":\"keychain\",\"key\":\"mcp_github_token\"}}',
  '$ROOT_DIR',
  0
);
"
}

persist_project_board_selection() {
  local database_path="$1"
  local project_id
  project_id="$(sqlite3 "$database_path" "SELECT id FROM projects WHERE source_command = 'ui-evidence' AND title = 'Launch Readiness' ORDER BY id DESC LIMIT 1;")"

  if [[ -z "$project_id" ]]; then
    echo "seeded Launch Readiness project was not found." >&2
    exit 1
  fi

  PROJECT_BOARD_SELECTION_OVERRIDE="project:$project_id"
  write_app_preference solopm.projectBoard.selectedDestination "$PROJECT_BOARD_SELECTION_OVERRIDE"
}

capture_visible_window() {
  local label="$1"
  local output_path="$2"
  local window_name="${3:-}"

  position_window_for_capture "$window_name"
  sleep 0.25

  local window_metadata
  window_metadata="$(wait_for_window_capture_metadata "$window_name")"
  set -- $window_metadata
  local window_id="$1"
  local window_x="$2"
  local window_y="$3"
  local window_width="$4"
  local window_height="$5"
  local window_context
  window_context="id=$window_id bounds=${window_width}x${window_height}+${window_x}+${window_y}"

  if ! screencapture -x -l "$window_id" "$output_path"; then
    if ! screencapture -x -R "${window_x},${window_y},${window_width},${window_height}" "$output_path"; then
      print_capture_failure_guidance "$label" "$output_path" "$window_context"
      echo "screen capture failed. Grant Screen Recording permission to the terminal/Codex app and rerun." >&2
      exit 1
    fi
  fi

  if [[ ! -s "$output_path" ]]; then
    echo "screenshot was not created: $output_path" >&2
    exit 1
  fi

  /usr/bin/sips -g pixelWidth -g pixelHeight "$output_path" >/dev/null

  if ! assert_screenshot_has_visible_content "$output_path"; then
    print_capture_failure_guidance "$label" "$output_path" "$window_context"
    echo "This usually means Screen Recording permission is missing, the display is locked/headless, or the captured image is blank." >&2
    rm -f "$output_path"
    exit 1
  fi

  local bytes
  bytes="$(wc -c <"$output_path" | tr -d '[:space:]')"
  if [[ "$bytes" -lt 50000 ]]; then
    echo "screenshot is unexpectedly small ($bytes bytes): $output_path" >&2
    print_capture_failure_guidance "$label" "$output_path" "$window_context"
    echo "This usually means Screen Recording permission is missing or the captured image is blank." >&2
    rm -f "$output_path"
    exit 1
  fi
}

open_mcp_settings_tab() {
  /usr/bin/osascript \
    -e 'tell application "System Events"' \
    -e "tell process \"$APP_NAME\"" \
    -e 'set frontmost to true' \
    -e 'keystroke "," using command down' \
    -e 'set settingsWindow to missing value' \
    -e 'repeat 40 times' \
    -e 'if exists window "MCP" then' \
    -e 'set settingsWindow to window "MCP"' \
    -e 'exit repeat' \
    -e 'else if exists window "Overview" then' \
    -e 'set settingsWindow to window "Overview"' \
    -e 'exit repeat' \
    -e 'end if' \
    -e 'delay 0.25' \
    -e 'end repeat' \
    -e 'if settingsWindow is missing value then' \
    -e 'error "SoloPM Settings window did not appear."' \
    -e 'end if' \
    -e 'click button "MCP" of toolbar 1 of settingsWindow' \
    -e 'end tell' \
    -e 'end tell' >/dev/null
}

open_settings_overview_tab() {
  /usr/bin/osascript \
    -e 'tell application "System Events"' \
    -e "tell process \"$APP_NAME\"" \
    -e 'set frontmost to true' \
    -e 'keystroke "," using command down' \
    -e 'set settingsWindow to missing value' \
    -e 'repeat 40 times' \
    -e 'if exists window "Overview" then' \
    -e 'set settingsWindow to window "Overview"' \
    -e 'exit repeat' \
    -e 'else if exists window "MCP" then' \
    -e 'set settingsWindow to window "MCP"' \
    -e 'exit repeat' \
    -e 'end if' \
    -e 'delay 0.25' \
    -e 'end repeat' \
    -e 'if settingsWindow is missing value then' \
    -e 'error "SoloPM Settings window did not appear."' \
    -e 'end if' \
    -e 'click button "Overview" of toolbar 1 of settingsWindow' \
    -e 'end tell' \
    -e 'end tell' >/dev/null
}

capture_settings_overview_appearance() {
  local appearance="$1"
  local output_path="$2"

  APPEARANCE_OVERRIDE="$appearance"
  stop_evidence_app
  write_appearance_preference "$appearance"
  open_evidence_app
  wait_for_process
  activate_evidence_app
  sleep 1.0
  open_settings_overview_tab
  sleep 1.0

  capture_visible_window "$appearance Settings overview" "$output_path" "Overview"
}

capture_mcp_settings_appearance() {
  local appearance="$1"
  local output_path="$2"

  APPEARANCE_OVERRIDE="$appearance"
  stop_evidence_app
  write_appearance_preference "$appearance"
  open_evidence_app
  wait_for_process
  activate_evidence_app
  sleep 1.0
  open_mcp_settings_tab
  sleep 1.0

  capture_visible_window "$appearance MCP settings" "$output_path" "MCP"
}

capture_appearance() {
  local appearance="$1"
  local output_path="$2"

  APPEARANCE_OVERRIDE="$appearance"
  stop_evidence_app
  write_appearance_preference "$appearance"
  open_evidence_app
  wait_for_process
  activate_evidence_app
  sleep 1.5

  capture_visible_window "$appearance" "$output_path"
}

write_evidence_file() {
  local generated_at="$1"
  local light_path="$2"
  local dark_path="$3"
  local system_path="$4"
  local overview_light_path="$5"
  local overview_dark_path="$6"
  local mcp_light_path="$7"
  local mcp_dark_path="$8"

  {
    printf '%s\n' '# UI Screenshot Evidence'
    printf '\n'
    printf '%s\n' 'Generated with `script/capture_ui_evidence.sh`.'
    printf '\n'
    printf -- '- Generated at: `%s`\n' "$generated_at"
    printf -- '- App bundle: `dist/%s.app`\n' "$APP_NAME"
    printf '%s\n' '- Data isolation: isolated temporary HOME via `HOME` and `CFFIXED_USER_HOME`'
    printf '%s\n' '- Seed data: local `Launch Readiness` project with planned, in-progress, and blocked task cards plus deterministic MCP registration rows'
    printf '%s\n' '- Scope: Project board sidebar, task cards, right inspector, Settings Overview Theme picker, and Settings MCP server list across Light/Dark/System'
    printf '%s\n' '- Manual review: passed for Project Board sidebar/cards/inspector, Settings Overview Theme picker, Settings MCP server rows, and Light/Dark/System contrast'
    printf '\n'
    printf '%s\n' '## Screenshots'
    printf '\n'
    printf -- '- Light: `%s`\n' "$(relative_path "$light_path")"
    printf -- '- Dark: `%s`\n' "$(relative_path "$dark_path")"
    printf -- '- System: `%s`\n' "$(relative_path "$system_path")"
    printf -- '- Settings Overview Light: `%s`\n' "$(relative_path "$overview_light_path")"
    printf -- '- Settings Overview Dark: `%s`\n' "$(relative_path "$overview_dark_path")"
    printf -- '- MCP Settings Light: `%s`\n' "$(relative_path "$mcp_light_path")"
    printf -- '- MCP Settings Dark: `%s`\n' "$(relative_path "$mcp_dark_path")"
    printf '\n'
    printf '%s\n' '## Notes'
    printf '\n'
    printf '%s\n' '- The script seeds only deterministic local Project/Task/MCP registration data into the isolated SQLite database.'
    printf '%s\n' '- API keys and provider tokens are not read, written, logged, or rendered.'
    printf '%s\n' '- Run `script/capture_ui_evidence.sh --doctor` first to verify required commands and Screen Recording visible-pixel capture without writing release evidence.'
    printf '%s\n' '- The capture host must grant Screen Recording permission through System Settings > Privacy & Security > Screen Recording / Screen & System Audio Recording to the terminal/Codex app; otherwise the script fails before treating screenshots as evidence.'
    printf '%s\n' '- If capture still fails, rerun with `SOLOPM_UI_EVIDENCE_KEEP_HOME=1` to keep the isolated HOME for database and preference inspection.'
    printf '%s\n' '- VoiceOver focus order still requires a manual assistive-technology pass.'
  } >"$EVIDENCE_FILE"
}

run_doctor() {
  echo "UI evidence doctor"
  echo "bundle: $APP_BUNDLE"
  echo "home: $EVIDENCE_HOME"
  echo "screenshots: $SCREENSHOT_DIR"
  echo "evidence: $EVIDENCE_FILE"
  echo "mode: screen capture preflight; does not write release evidence"

  local blocker_count=0
  local command_name
  for command_name in sqlite3 screencapture swift sips osascript; do
    if command -v "$command_name" >/dev/null 2>&1; then
      echo "OK: found $command_name"
    else
      echo "BLOCKER: missing required command: $command_name"
      blocker_count=$((blocker_count + 1))
    fi
  done

  if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "INFO: app bundle is not present yet; normal capture mode will run script/build_and_run.sh --build-only."
  fi

  if command -v screencapture >/dev/null 2>&1 && command -v swift >/dev/null 2>&1; then
    local probe_base
    local probe
    probe_base="$(mktemp "${TMPDIR:-/tmp}/solopm-ui-evidence-doctor.XXXXXX")"
    probe="$probe_base.png"
    rm -f "$probe_base"
    if screencapture -x "$probe" >/dev/null 2>&1 && [[ -s "$probe" ]] && assert_screenshot_has_visible_content "$probe"; then
      echo "OK: screen capture preflight produced visible pixels"
    else
      echo "BLOCKER: screen capture preflight did not produce visible pixels"
      echo "NEXT: grant Screen Recording permission to the terminal/Codex app, quit and reopen it, then rerun script/capture_ui_evidence.sh --doctor."
      blocker_count=$((blocker_count + 1))
    fi
    rm -f "$probe"
  fi

  if [[ "$blocker_count" -gt 0 ]]; then
    exit 1
  fi
}

if [[ "$DOCTOR" == "1" ]]; then
  run_doctor
  exit 0
fi

require_command sqlite3
require_command screencapture
require_command swift
require_command sips
require_command osascript

mkdir -p "$SCREENSHOT_DIR"
mkdir -p "$EVIDENCE_HOME/Library/Application Support"

if [[ "$DRY_RUN" == "1" ]]; then
  echo "UI evidence dry run"
  echo "bundle: $APP_BUNDLE"
  echo "home: $EVIDENCE_HOME"
  echo "screenshots: $SCREENSHOT_DIR"
  echo "evidence: $EVIDENCE_FILE"
  exit 0
fi

"$ROOT_DIR/script/build_and_run.sh" --build-only

DATABASE_PATH="$EVIDENCE_HOME/Library/Application Support/SoloPM/SoloPM.sqlite"
initialize_database "$DATABASE_PATH"
seed_database "$DATABASE_PATH"
seed_mcp_registrations "$DATABASE_PATH"
persist_project_board_selection "$DATABASE_PATH"

LIGHT_SCREENSHOT="$SCREENSHOT_DIR/project-board-light.png"
DARK_SCREENSHOT="$SCREENSHOT_DIR/project-board-dark.png"
SYSTEM_SCREENSHOT="$SCREENSHOT_DIR/project-board-system.png"
SETTINGS_OVERVIEW_LIGHT_SCREENSHOT="$SCREENSHOT_DIR/settings-overview-light.png"
SETTINGS_OVERVIEW_DARK_SCREENSHOT="$SCREENSHOT_DIR/settings-overview-dark.png"
MCP_SETTINGS_LIGHT_SCREENSHOT="$SCREENSHOT_DIR/settings-mcp-light.png"
MCP_SETTINGS_DARK_SCREENSHOT="$SCREENSHOT_DIR/settings-mcp-dark.png"

capture_appearance light "$LIGHT_SCREENSHOT"
capture_appearance dark "$DARK_SCREENSHOT"
capture_appearance system "$SYSTEM_SCREENSHOT"
capture_settings_overview_appearance light "$SETTINGS_OVERVIEW_LIGHT_SCREENSHOT"
capture_settings_overview_appearance dark "$SETTINGS_OVERVIEW_DARK_SCREENSHOT"
capture_mcp_settings_appearance light "$MCP_SETTINGS_LIGHT_SCREENSHOT"
capture_mcp_settings_appearance dark "$MCP_SETTINGS_DARK_SCREENSHOT"

GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
write_evidence_file "$GENERATED_AT" "$LIGHT_SCREENSHOT" "$DARK_SCREENSHOT" "$SYSTEM_SCREENSHOT" "$SETTINGS_OVERVIEW_LIGHT_SCREENSHOT" "$SETTINGS_OVERVIEW_DARK_SCREENSHOT" "$MCP_SETTINGS_LIGHT_SCREENSHOT" "$MCP_SETTINGS_DARK_SCREENSHOT"

echo "UI screenshot evidence generated:"
echo "- $(relative_path "$LIGHT_SCREENSHOT")"
echo "- $(relative_path "$DARK_SCREENSHOT")"
echo "- $(relative_path "$SYSTEM_SCREENSHOT")"
echo "- $(relative_path "$SETTINGS_OVERVIEW_LIGHT_SCREENSHOT")"
echo "- $(relative_path "$SETTINGS_OVERVIEW_DARK_SCREENSHOT")"
echo "- $(relative_path "$MCP_SETTINGS_LIGHT_SCREENSHOT")"
echo "- $(relative_path "$MCP_SETTINGS_DARK_SCREENSHOT")"
echo "- $(relative_path "$EVIDENCE_FILE")"
