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
SCHEDULE_COCKPIT_EVIDENCE_FILE="${SOLOPM_SCHEDULE_COCKPIT_EVIDENCE_FILE:-$ROOT_DIR/docs/release/evidence/schedule-cockpit-screenshots.md}"
EVIDENCE_TMPDIR="${SOLOPM_UI_EVIDENCE_TMPDIR:-$ROOT_DIR/.tmp}"
VISUAL_BASELINE_MANIFEST="$ROOT_DIR/docs/quality/visual-baseline-manifest.json"
VISUAL_BASELINE_VIEWPORT="${SOLOPM_VISUAL_BASELINE_VIEWPORT:-1560x860}"
SETTINGS_VISUAL_BASELINE_VIEWPORT="${SOLOPM_SETTINGS_VISUAL_BASELINE_VIEWPORT:-1200x720}"
TARGET_TIMEOUT_SECONDS="${SOLOPM_UI_EVIDENCE_TARGET_TIMEOUT_SECONDS:-30}"
AX_MARKER_MAX_NODES="${SOLOPM_UI_EVIDENCE_AX_MAX_NODES:-6000}"
mkdir -p "$EVIDENCE_TMPDIR"
export TMPDIR="$EVIDENCE_TMPDIR/"
EVIDENCE_HOME="${SOLOPM_UI_EVIDENCE_HOME:-$(mktemp -d "$EVIDENCE_TMPDIR/solopm-ui-evidence.XXXXXX")}"
KEEP_HOME="${SOLOPM_UI_EVIDENCE_KEEP_HOME:-0}"
DRY_RUN=0
DOCTOR=0
P0_WORKFLOWS=0
SCHEDULE_COCKPIT=0
SCHEDULE_WORKLOAD=0
PROJECT_BOARD_SELECTION_OVERRIDE=""
PROJECT_BOARD_SELECTED_TASK_OVERRIDE=""
PROJECT_BOARD_TARGET_MARKERS=""
INBOX_VOICE_TARGET_MARKERS=""
APPEARANCE_OVERRIDE=""
SETTINGS_WINDOW_OVERRIDE=""
SETTINGS_TAB_OVERRIDE=""
VOICE_COMMAND_WINDOW_OVERRIDE=""
EVIDENCE_APP_PID=""
DATABASE_PATH=""

for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=1
      ;;
    --doctor)
      DOCTOR=1
      ;;
    --p0-workflows)
      P0_WORKFLOWS=1
      ;;
    --schedule-cockpit)
      SCHEDULE_COCKPIT=1
      ;;
    --schedule-workload)
      SCHEDULE_WORKLOAD=1
      ;;
    *)
      echo "usage: $0 [--dry-run|--doctor|--p0-workflows|--schedule-cockpit|--schedule-workload]" >&2
      exit 2
      ;;
  esac
done

if [[ $((DRY_RUN + DOCTOR + P0_WORKFLOWS + SCHEDULE_COCKPIT + SCHEDULE_WORKLOAD)) -gt 1 ]]; then
  echo "usage: $0 [--dry-run|--doctor|--p0-workflows|--schedule-cockpit|--schedule-workload]" >&2
  exit 2
fi

if [[ ! "$TARGET_TIMEOUT_SECONDS" =~ ^[0-9]+$ || "$TARGET_TIMEOUT_SECONDS" -lt 1 ]]; then
  echo "SOLOPM_UI_EVIDENCE_TARGET_TIMEOUT_SECONDS must be a positive integer" >&2
  exit 2
fi
if [[ ! "$AX_MARKER_MAX_NODES" =~ ^[0-9]+$ || "$AX_MARKER_MAX_NODES" -lt 1 ]]; then
  echo "SOLOPM_UI_EVIDENCE_AX_MAX_NODES must be a positive integer" >&2
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

ui_evidence_source_commit() {
  local commit
  commit="$(
    git -C "$ROOT_DIR" log -1 --format=%h -- \
      Sources/SoloPMApp \
      Sources/SoloPMCore \
      Package.swift 2>/dev/null || true
  )"
  if [[ -n "$commit" ]]; then
    printf "%s" "$commit"
  else
    git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || printf "unknown"
  fi
}

app_env_args() {
  local args=("SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1")
  if [[ "$SCHEDULE_COCKPIT" != "1" ]]; then
    args+=("HOME=$EVIDENCE_HOME")
    args+=("CFFIXED_USER_HOME=$EVIDENCE_HOME")
  fi
  args+=("SOLOPM_FORCE_PROJECT_BOARD_FALLBACK=1")
  if [[ -n "$DATABASE_PATH" ]]; then
    # Screenshot evidence must open the exact SQLite file seeded below; relying
    # on HOME-derived defaults can silently fall back to another database.
    args+=("SOLOPM_DATABASE_PATH=$DATABASE_PATH")
  fi
  if [[ "$P0_WORKFLOWS" == "1" || "$SCHEDULE_COCKPIT" == "1" ]]; then
    args+=("SOLOPM_LAUNCH_RECOVERY_MODE=1")
  fi
  if [[ -n "$PROJECT_BOARD_SELECTION_OVERRIDE" ]]; then
    args+=("SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION=$PROJECT_BOARD_SELECTION_OVERRIDE")
  fi
  if [[ -n "$PROJECT_BOARD_SELECTED_TASK_OVERRIDE" ]]; then
    args+=("SOLOPM_PROJECT_BOARD_SELECTED_TASK_ID=$PROJECT_BOARD_SELECTED_TASK_OVERRIDE")
  fi
  if [[ -n "$APPEARANCE_OVERRIDE" ]]; then
    args+=("SOLOPM_APPEARANCE_PREFERENCE=$APPEARANCE_OVERRIDE")
  fi
  if [[ "$SETTINGS_WINDOW_OVERRIDE" == "1" ]]; then
    args+=("SOLOPM_OPEN_SETTINGS_ON_LAUNCH=1")
  fi
  if [[ -n "$SETTINGS_TAB_OVERRIDE" ]]; then
    args+=("SOLOPM_SETTINGS_EVIDENCE_TAB=$SETTINGS_TAB_OVERRIDE")
  fi
  if [[ "$VOICE_COMMAND_WINDOW_OVERRIDE" == "1" ]]; then
    args+=("SOLOPM_OPEN_VOICE_COMMAND_ON_LAUNCH=1")
  fi
  printf '%s\0' "${args[@]}"
}

open_evidence_app() {
  local env_args=()
  while IFS= read -r -d '' env_arg; do
    env_args+=("$env_arg")
  done < <(app_env_args)
  if [[ "$SCHEDULE_COCKPIT" == "1" ]]; then
    wait_for_app_process_exit
    # Schedule recovery needs the explicit SQLite DB but LaunchServices can keep
    # the window off-screen with that env; direct launch matches runtime smokes.
    /usr/bin/env "${env_args[@]}" "$APP_BINARY" >/dev/null 2>&1 &
    EVIDENCE_APP_PID=$!
    return
  fi
  local open_args=(-n -F "$APP_BUNDLE")
  local env_arg
  for env_arg in "${env_args[@]}"; do
    open_args+=(--env "$env_arg")
  done
  wait_for_app_process_exit
  # Launch through LaunchServices so SwiftUI windows become on-screen, while
  # still passing the isolated database, appearance, and target-selection env.
  /usr/bin/open "${open_args[@]}" >/dev/null
  EVIDENCE_APP_PID=""
  for _ in {1..40}; do
    EVIDENCE_APP_PID="$(pgrep -x "$APP_NAME" | head -n 1 || true)"
    if [[ -n "$EVIDENCE_APP_PID" ]]; then
      return
    fi
    sleep 0.25
  done
  echo "$APP_NAME did not launch after open." >&2
  exit 1
}

wait_for_app_process_exit() {
  for _ in {1..40}; do
    if ! pgrep -x "$APP_NAME" >/dev/null; then
      return
    fi
    sleep 0.25
  done
  echo "$APP_NAME did not terminate before next evidence capture." >&2
  exit 1
}

stop_evidence_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  if [[ -n "$EVIDENCE_APP_PID" ]]; then
    wait "$EVIDENCE_APP_PID" >/dev/null 2>&1 || true
    EVIDENCE_APP_PID=""
  fi
  wait_for_app_process_exit
}

activate_evidence_app() {
  # Avoid LaunchServices activation; it can start a second app instance without
  # the isolated screenshot database, target selection, or appearance env.
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
      return
    fi
    sleep 0.1
  done
  kill "$osascript_pid" >/dev/null 2>&1 || true
  wait "$osascript_pid" >/dev/null 2>&1 || true
}

wait_for_process() {
  if [[ -n "$EVIDENCE_APP_PID" ]]; then
    for _ in {1..40}; do
      if kill -0 "$EVIDENCE_APP_PID" >/dev/null 2>&1; then
        return 0
      fi
      sleep 0.25
    done
    echo "$APP_NAME did not launch as expected pid $EVIDENCE_APP_PID." >&2
    exit 1
  fi

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
  local deadline=$((SECONDS + TARGET_TIMEOUT_SECONDS))
  while true; do
    if metadata="$(find_window_capture_metadata "$window_name" 2>/dev/null)"; then
      printf '%s\n' "$metadata"
      return 0
    fi
    # Window restoration can be slower than process launch, so share the same
    # operator-controlled timeout as target marker validation.
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      break
    fi
    sleep 0.25
  done
  find_window_capture_metadata "$window_name"
}

target_marker_present() {
  local identifier="$1"
  local text="$2"
  local error_file
  local checker_pid
  local watchdog_pid
  local status
  error_file="$(mktemp "${TMPDIR:-/tmp}/solopm-ui-target-marker-error.XXXXXX")"

  # AX marker scans use a bounded Swift AX traversal because SwiftUI's generated
  # accessibility tree can make AppleScript recursion stall on detail-heavy screens.
  SOLOPM_UI_EVIDENCE_AX_MAX_NODES="$AX_MARKER_MAX_NODES" \
    /usr/bin/swift "$ROOT_DIR/script/ui_evidence_ax_marker_check.swift" "$APP_NAME" "$identifier" "$text" \
    >/dev/null 2>"$error_file" &
  checker_pid=$!
  (
    sleep "$TARGET_TIMEOUT_SECONDS"
    kill "$checker_pid" >/dev/null 2>&1 || true
  ) &
  watchdog_pid=$!
  wait "$checker_pid"
  status=$?
  kill "$watchdog_pid" >/dev/null 2>&1 || true
  wait "$watchdog_pid" >/dev/null 2>&1 || true
  if [[ "$status" -ne 0 ]]; then
    cat "$error_file" >&2
    if [[ "$status" -eq 143 || "$status" -eq 137 ]]; then
      echo "AX target marker scan timed out after ${TARGET_TIMEOUT_SECONDS}s: $identifier => $text" >&2
    fi
  fi
  rm -f "$error_file"
  return "$status"
}

assert_project_board_destination_ready() {
  local label="$1"
  local marker_spec="$2"
  local markers=()
  local marker
  local identifier
  local text
  local missing=()

  if [[ -z "$marker_spec" ]]; then
    return 0
  fi

  IFS='|' read -r -a markers <<<"$marker_spec"
  for marker in "${markers[@]}"; do
    [[ -z "$marker" ]] && continue
    if [[ "$marker" != *"=>"* ]]; then
      echo "invalid UI evidence target marker for $label: $marker" >&2
      return 2
    fi
    identifier="${marker%%=>*}"
    text="${marker#*=>}"
    if ! target_marker_present "$identifier" "$text"; then
      missing+=("$marker")
    fi
  done

  if [[ "${#missing[@]}" -gt 0 ]]; then
    printf 'UI evidence target not ready for %s; missing marker(s): %s\n' "$label" "${missing[*]}" >&2
    return 1
  fi
}

wait_for_project_board_destination() {
  local label="$1"
  local marker_spec="$2"
  local deadline=$((SECONDS + TARGET_TIMEOUT_SECONDS))

  while true; do
    if assert_project_board_destination_ready "$label" "$marker_spec" >/dev/null 2>&1; then
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      assert_project_board_destination_ready "$label" "$marker_spec"
      echo "BLOCKER: UI evidence target did not become ready for $label within ${TARGET_TIMEOUT_SECONDS}s" >&2
      echo "NEXT: keep the intended SoloPM window visible, verify Accessibility permission for Terminal/Codex, and rerun script/capture_ui_evidence.sh." >&2
      return 1
    fi
    sleep 0.25
  done
}

visual_baseline_bounds() {
  local viewport="$1"
  local origin_x="$2"
  local origin_y="$3"
  local width="${viewport%x*}"
  local height="${viewport#*x}"

  if [[ ! "$width" =~ ^[0-9]+$ || ! "$height" =~ ^[0-9]+$ ]]; then
    echo "invalid viewport: $viewport" >&2
    exit 2
  fi

  printf '{%s, %s, %s, %s}' "$origin_x" "$origin_y" "$((origin_x + width))" "$((origin_y + height))"
}

position_window_for_capture() {
  local window_name="${1:-}"
  local bounds

  if [[ -n "$window_name" ]]; then
    bounds="$(visual_baseline_bounds "$SETTINGS_VISUAL_BASELINE_VIEWPORT" 120 90)"
    /usr/bin/osascript \
      -e 'tell application "System Events"' \
      -e "tell process \"$APP_NAME\"" \
      -e "if exists window \"$window_name\" then set bounds of window \"$window_name\" to $bounds" \
      -e 'end tell' \
      -e 'end tell' >/dev/null 2>&1 || true
  else
    bounds="$(visual_baseline_bounds "$VISUAL_BASELINE_VIEWPORT" 80 70)"
    /usr/bin/osascript \
      -e 'tell application "System Events"' \
      -e "tell process \"$APP_NAME\"" \
      -e "if exists front window then set bounds of front window to $bounds" \
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
  completed_at TEXT,
  priority TEXT,
  source_command TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS project_milestones (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project_id INTEGER NOT NULL,
  title TEXT NOT NULL,
  due_at TEXT,
  is_completed INTEGER NOT NULL DEFAULT 0 CHECK(is_completed IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS inbox_capture_records (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  task_id INTEGER NOT NULL,
  source_kind TEXT NOT NULL CHECK(source_kind IN ('voice_memo')),
  audio_file_path TEXT NOT NULL,
  duration_seconds REAL NOT NULL CHECK(duration_seconds >= 0),
  transcript TEXT,
  interpretation_summary TEXT,
  memo TEXT,
  classification_status TEXT NOT NULL CHECK(classification_status IN ('unclassified', 'classified', 'dismissed')),
  transcription_status TEXT NOT NULL CHECK(transcription_status IN ('pending', 'succeeded', 'failed')),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE CASCADE
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

CREATE INDEX IF NOT EXISTS idx_project_milestones_project
ON project_milestones(project_id);

CREATE INDEX IF NOT EXISTS idx_inbox_capture_records_task
ON inbox_capture_records(task_id);
"
}

seed_database() {
  local database_path="$1"
  local today
  local tomorrow
  local yesterday
  today="$(date +%Y-%m-%d)"
  tomorrow="$(date -v+1d +%Y-%m-%d)"
  yesterday="$(date -v-1d -u +%Y-%m-%dT%H:%M:%SZ)"

  sqlite3 "$database_path" "
DELETE FROM inbox_capture_records WHERE task_id IN (SELECT id FROM tasks WHERE source_command = 'ui-evidence');
DELETE FROM project_milestones WHERE project_id IN (SELECT id FROM projects WHERE source_command = 'ui-evidence');
DELETE FROM tasks WHERE source_command = 'ui-evidence';
DELETE FROM projects WHERE source_command = 'ui-evidence';

INSERT INTO projects (title, status, priority, deadline, workspace_path, tags_json, source_command)
VALUES ('Launch Readiness', 'active', 'high', '$tomorrow', NULL, '["ui-evidence","local"]', 'ui-evidence');

INSERT INTO projects (title, status, priority, deadline, workspace_path, tags_json, source_command)
VALUES ('Inbox', 'active', NULL, NULL, NULL, '["ui-evidence","inbox"]', 'ui-evidence');

INSERT INTO projects (title, status, priority, deadline, workspace_path, tags_json, source_command)
VALUES ('Completed Evidence Project', 'completed', 'medium', '$tomorrow', NULL, '["ui-evidence","done"]', 'ui-evidence');

INSERT INTO tasks (project_id, title, status, detail, due_at, completed_at, priority, source_command)
VALUES
  ((SELECT id FROM projects WHERE source_command = 'ui-evidence' AND title = 'Launch Readiness' ORDER BY id DESC LIMIT 1),
   'Capture launch screenshots', 'planned', 'Verify board card density, sidebar, and inspector in each theme.', '$tomorrow', NULL, 'high', 'ui-evidence'),
  ((SELECT id FROM projects WHERE source_command = 'ui-evidence' AND title = 'Launch Readiness' ORDER BY id DESC LIMIT 1),
   'Review VoiceOver focus path', 'in_progress', 'Confirm project board to task card to inspector path before public alpha.', '$today', NULL, 'high', 'ui-evidence'),
  ((SELECT id FROM projects WHERE source_command = 'ui-evidence' AND title = 'Launch Readiness' ORDER BY id DESC LIMIT 1),
   'Document remaining release blockers', 'blocked', 'Keep signing, notarization, and manual accessibility gates visible.', NULL, NULL, 'medium', 'ui-evidence'),
  ((SELECT id FROM projects WHERE source_command = 'ui-evidence' AND title = 'Inbox' ORDER BY id DESC LIMIT 1),
   'Scheduled manual capture', 'planned', 'Voice memo capture with transcript and local interpretation metadata.', NULL, NULL, 'high', 'ui-evidence'),
  ((SELECT id FROM projects WHERE source_command = 'ui-evidence' AND title = 'Launch Readiness' ORDER BY id DESC LIMIT 1),
   'Unscheduled schedule draft input', 'planned', 'Appears in Schedule cockpit as an unscheduled task.', NULL, NULL, 'medium', 'ui-evidence'),
  ((SELECT id FROM projects WHERE source_command = 'ui-evidence' AND title = 'Completed Evidence Project' ORDER BY id DESC LIMIT 1),
   'Done analytics sample', 'completed', 'Completed history appears in Done analytics evidence.', '$tomorrow', '$yesterday', 'medium', 'ui-evidence');

INSERT INTO inbox_capture_records (
  task_id,
  source_kind,
  audio_file_path,
  duration_seconds,
  transcript,
  interpretation_summary,
  memo,
  classification_status,
  transcription_status,
  created_at
) VALUES (
  (SELECT id FROM tasks WHERE source_command = 'ui-evidence' AND title = 'Scheduled manual capture' ORDER BY id DESC LIMIT 1),
  'voice_memo',
  '/tmp/solopm-ui-evidence-redacted.m4a',
  18.5,
  'Schedule launch review and capture visual evidence.',
  'Create a task for launch review evidence.',
  'Seeded local transcript for UI screenshot evidence.',
  'unclassified',
  'succeeded',
  '$yesterday'
);

INSERT INTO project_milestones (project_id, title, due_at, is_completed)
VALUES (
  (SELECT id FROM projects WHERE source_command = 'ui-evidence' AND title = 'Launch Readiness' ORDER BY id DESC LIMIT 1),
  'Launch milestone',
  '$tomorrow',
  0
);
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

assert_phase12_seed_data() {
  local database_path="$1"
  local scheduled_manual_capture_count
  local done_analytics_sample_count
  local completed_project_count
  local inbox_project_count

  scheduled_manual_capture_count="$(sqlite3 "$database_path" "SELECT COUNT(*) FROM tasks WHERE source_command = 'ui-evidence' AND title = 'Scheduled manual capture';")"
  done_analytics_sample_count="$(sqlite3 "$database_path" "SELECT COUNT(*) FROM tasks WHERE source_command = 'ui-evidence' AND title = 'Done analytics sample';")"
  completed_project_count="$(sqlite3 "$database_path" "SELECT COUNT(*) FROM projects WHERE source_command = 'ui-evidence' AND title = 'Completed Evidence Project';")"
  inbox_project_count="$(sqlite3 "$database_path" "SELECT COUNT(*) FROM projects WHERE source_command = 'ui-evidence' AND title = 'Inbox';")"

  if [[ "$scheduled_manual_capture_count" -lt 1 ]]; then
    echo "missing Phase 12 UI evidence seed: Scheduled manual capture" >&2
    exit 1
  fi
  if [[ "$done_analytics_sample_count" -lt 1 ]]; then
    echo "missing Phase 12 UI evidence seed: Done analytics sample" >&2
    exit 1
  fi
  if [[ "$completed_project_count" -lt 1 ]]; then
    echo "missing Phase 12 UI evidence seed: Completed Evidence Project" >&2
    exit 1
  fi
  if [[ "$inbox_project_count" -lt 1 ]]; then
    echo "missing Phase 12 UI evidence seed: Inbox" >&2
    exit 1
  fi
}

assert_valid_seed_task_statuses() {
  local database_path="$1"
  local invalid_statuses

  # The app maps persisted "completed" tasks to the UI's Done column; writing
  # the UI label into SQLite makes the screenshot evidence capture an error page.
  invalid_statuses="$(sqlite3 "$database_path" "
SELECT DISTINCT status
FROM tasks
WHERE source_command = 'ui-evidence'
  AND status NOT IN ('open', 'backlog', 'planned', 'in_progress', 'blocked', 'completed')
ORDER BY status;
")"

  if [[ -n "$invalid_statuses" ]]; then
    echo "unsupported Phase 12 UI evidence task status: $invalid_statuses" >&2
    exit 1
  fi
}

persist_project_board_selection() {
  local database_path="$1"
  local project_id
  local inbox_voice_task_id
  project_id="$(sqlite3 "$database_path" "SELECT id FROM projects WHERE source_command = 'ui-evidence' AND title = 'Launch Readiness' ORDER BY id DESC LIMIT 1;")"

  if [[ -z "$project_id" ]]; then
    echo "seeded Launch Readiness project was not found." >&2
    exit 1
  fi
  inbox_voice_task_id="$(sqlite3 "$database_path" "SELECT id FROM tasks WHERE source_command = 'ui-evidence' AND title = 'Scheduled manual capture' ORDER BY id DESC LIMIT 1;")"
  if [[ -z "$inbox_voice_task_id" ]]; then
    echo "seeded Scheduled manual capture task was not found." >&2
    exit 1
  fi

  PROJECT_BOARD_SELECTION_OVERRIDE="project:$project_id"
  PROJECT_BOARD_TARGET_MARKERS="project-board-detail=>Launch Readiness|task-card-open-details=>Capture launch screenshots"
  INBOX_VOICE_TASK_OVERRIDE="$inbox_voice_task_id"
  INBOX_VOICE_TARGET_MARKERS="sidebar-destination-inbox=>Inbox|inbox-action-panel=>Voice capture metadata available for Scheduled manual capture|inbox-voice-intake-detail=>Voice intake detail for Scheduled manual capture|inbox-voice-transcript=>Schedule launch review and capture visual evidence.|inbox-voice-interpretation=>Create a task for launch review evidence.|inbox-action-grid=>Make Task"
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
  wait_for_window_capture_metadata "MCP" >/dev/null
}

open_settings_appearance_tab() {
  wait_for_window_capture_metadata "Appearance" >/dev/null
}

open_settings_overview_tab() {
  wait_for_window_capture_metadata "Overview" >/dev/null
}

capture_settings_overview() {
  local appearance="$1"
  local output_path="$2"

  APPEARANCE_OVERRIDE="$appearance"
  SETTINGS_WINDOW_OVERRIDE=1
  SETTINGS_TAB_OVERRIDE="Overview"
  VOICE_COMMAND_WINDOW_OVERRIDE=""
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

capture_settings_appearance() {
  local appearance="$1"
  local output_path="$2"

  APPEARANCE_OVERRIDE="$appearance"
  SETTINGS_WINDOW_OVERRIDE=1
  SETTINGS_TAB_OVERRIDE="Appearance"
  VOICE_COMMAND_WINDOW_OVERRIDE=""
  stop_evidence_app
  write_appearance_preference "$appearance"
  open_evidence_app
  wait_for_process
  activate_evidence_app
  sleep 1.0
  open_settings_appearance_tab
  sleep 1.0

  capture_visible_window "$appearance Settings appearance" "$output_path" "Appearance"
}

capture_mcp_settings_appearance() {
  local appearance="$1"
  local output_path="$2"

  APPEARANCE_OVERRIDE="$appearance"
  SETTINGS_WINDOW_OVERRIDE=1
  SETTINGS_TAB_OVERRIDE="MCP"
  VOICE_COMMAND_WINDOW_OVERRIDE=""
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
  SETTINGS_WINDOW_OVERRIDE=""
  SETTINGS_TAB_OVERRIDE=""
  VOICE_COMMAND_WINDOW_OVERRIDE=""
  stop_evidence_app
  write_appearance_preference "$appearance"
  open_evidence_app
  wait_for_process
  activate_evidence_app
  sleep 1.5

  capture_visible_window "$appearance" "$output_path"
}

capture_project_board_destination() {
  local appearance="$1"
  local selected_destination="$2"
  local output_path="$3"
  local label="$4"
  local target_markers="${5:-}"
  local selected_task_id="${6:-}"

  APPEARANCE_OVERRIDE="$appearance"
  PROJECT_BOARD_SELECTION_OVERRIDE="$selected_destination"
  PROJECT_BOARD_SELECTED_TASK_OVERRIDE="$selected_task_id"
  SETTINGS_WINDOW_OVERRIDE=""
  SETTINGS_TAB_OVERRIDE=""
  VOICE_COMMAND_WINDOW_OVERRIDE=""
  stop_evidence_app
  write_appearance_preference "$appearance"
  write_app_preference solopm.projectBoard.selectedDestination "$selected_destination"
  open_evidence_app
  wait_for_process
  activate_evidence_app
  sleep 1.5
  wait_for_window_capture_metadata >/dev/null
  # Dense workflow footers may not enter the AX visible subtree until the
  # evidence window is widened, so target validation uses the same bounds as
  # the screenshot instead of checking a smaller launch-default window.
  position_window_for_capture
  sleep 0.25
  wait_for_project_board_destination "$label" "$target_markers"

  capture_visible_window "$appearance $label" "$output_path"
}

capture_voice_command_appearance() {
  local appearance="$1"
  local output_path="$2"

  APPEARANCE_OVERRIDE="$appearance"
  PROJECT_BOARD_SELECTION_OVERRIDE=""
  SETTINGS_WINDOW_OVERRIDE=""
  SETTINGS_TAB_OVERRIDE=""
  VOICE_COMMAND_WINDOW_OVERRIDE=1
  stop_evidence_app
  write_appearance_preference "$appearance"
  open_evidence_app
  wait_for_process
  activate_evidence_app
  sleep 1.0
  wait_for_window_capture_metadata "Voice Command" >/dev/null
  wait_for_project_board_destination "Voice Command" "$VOICE_COMMAND_TARGET_MARKERS"

  capture_visible_window "$appearance Voice Command" "$output_path" "Voice Command"
}

write_evidence_file() {
  local generated_at="$1"
  local light_path="$2"
  local dark_path="$3"
  local system_path="$4"
  local overview_light_path="$5"
  local overview_dark_path="$6"
  local appearance_light_path="$7"
  local appearance_dark_path="$8"
  local mcp_light_path="$9"
  local mcp_dark_path="${10}"
  local inbox_light_path="${11}"
  local inbox_dark_path="${12}"
  local projects_light_path="${13}"
  local projects_dark_path="${14}"
  local schedule_light_path="${15}"
  local schedule_dark_path="${16}"
  local done_light_path="${17}"
  local done_dark_path="${18}"
  local settings_integrations_light_path="${19}"
  local settings_integrations_dark_path="${20}"

  {
    printf '%s\n' '# UI Screenshot Evidence'
    printf '\n'
    printf '%s\n' 'Generated with `script/capture_ui_evidence.sh`.'
    printf '\n'
    printf -- '- Generated at: `%s`\n' "$generated_at"
    printf -- '- Source commit: `%s`\n' "$(ui_evidence_source_commit)"
    printf -- '- App bundle: `dist/%s.app`\n' "$APP_NAME"
    printf -- '- Visual baseline manifest: `%s`\n' "$(relative_path "$VISUAL_BASELINE_MANIFEST")"
    printf -- '- Viewport contract: `SOLOPM_VISUAL_BASELINE_VIEWPORT=%s`, `SOLOPM_SETTINGS_VISUAL_BASELINE_VIEWPORT=%s`\n' "$VISUAL_BASELINE_VIEWPORT" "$SETTINGS_VISUAL_BASELINE_VIEWPORT"
    printf '%s\n' '- Data isolation: isolated temporary HOME via `HOME` and `CFFIXED_USER_HOME`'
    printf '%s\n' '- Seed data: local `Launch Readiness` project with planned, in-progress, blocked, Inbox voice, Schedule, Done analytics, milestone, completed project, and deterministic MCP registration rows'
    printf '%s\n' '- Scope: Project board sidebar, task cards, Inbox voice detail, Today cockpit, Projects overview, Schedule cockpit, Schedule workload dashboard, Done analytics, Settings integrations, Settings Appearance Theme picker, and Settings MCP server list across Light/Dark/System'
    printf '%s\n' '- Capture contract: Light/Dark/System visual baseline manifest fixes product screen targets, viewport, semantic tolerances, and AX frame audit requirements.'
    printf '%s\n' '- Manual review: passed for Project Board sidebar/cards/inspector, Inbox voice detail, Today cockpit, Projects overview, Schedule cockpit, Schedule workload dashboard, Done analytics, Settings integrations, Settings Appearance Theme picker, Settings MCP server rows, and Light/Dark/System contrast'
    printf '\n'
    printf '%s\n' '## Screenshots'
    printf '\n'
    printf -- '- Light: `%s`\n' "$(relative_path "$light_path")"
    printf -- '- Dark: `%s`\n' "$(relative_path "$dark_path")"
    printf -- '- System: `%s`\n' "$(relative_path "$system_path")"
    printf -- '- Settings Overview Light: `%s`\n' "$(relative_path "$overview_light_path")"
    printf -- '- Settings Overview Dark: `%s`\n' "$(relative_path "$overview_dark_path")"
    printf -- '- Settings Appearance Light: `%s`\n' "$(relative_path "$appearance_light_path")"
    printf -- '- Settings Appearance Dark: `%s`\n' "$(relative_path "$appearance_dark_path")"
    printf -- '- MCP Settings Light: `%s`\n' "$(relative_path "$mcp_light_path")"
    printf -- '- MCP Settings Dark: `%s`\n' "$(relative_path "$mcp_dark_path")"
    printf -- '- Inbox Voice Light: `%s`\n' "$(relative_path "$inbox_light_path")"
    printf -- '- Inbox Voice Dark: `%s`\n' "$(relative_path "$inbox_dark_path")"
    printf -- '- Projects Overview Light: `%s`\n' "$(relative_path "$projects_light_path")"
    printf -- '- Projects Overview Dark: `%s`\n' "$(relative_path "$projects_dark_path")"
    printf -- '- Schedule Light: `%s`\n' "$(relative_path "$schedule_light_path")"
    printf -- '- Schedule Dark: `%s`\n' "$(relative_path "$schedule_dark_path")"
    printf -- '- Schedule Workload Light: `%s`\n' "$(relative_path "$SCHEDULE_WORKLOAD_LIGHT_SCREENSHOT")"
    printf -- '- Schedule Workload Dark: `%s`\n' "$(relative_path "$SCHEDULE_WORKLOAD_DARK_SCREENSHOT")"
    printf -- '- Done Light: `%s`\n' "$(relative_path "$done_light_path")"
    printf -- '- Done Dark: `%s`\n' "$(relative_path "$done_dark_path")"
    printf -- '- Settings Integrations Light: `%s`\n' "$(relative_path "$settings_integrations_light_path")"
    printf -- '- Settings Integrations Dark: `%s`\n' "$(relative_path "$settings_integrations_dark_path")"
    printf '\n'
    printf '%s\n' '## Visual Baseline Manifest Screenshots'
    printf '\n'
    printf -- '- Project Board Light: `%s`\n' "$(relative_path "$LIGHT_SCREENSHOT")"
    printf -- '- Project Board Dark: `%s`\n' "$(relative_path "$DARK_SCREENSHOT")"
    printf -- '- Project Board System: `%s`\n' "$(relative_path "$SYSTEM_SCREENSHOT")"
    printf -- '- Inbox Light: `%s`\n' "$(relative_path "$INBOX_LIGHT_SCREENSHOT")"
    printf -- '- Inbox Dark: `%s`\n' "$(relative_path "$INBOX_DARK_SCREENSHOT")"
    printf -- '- Inbox System: `%s`\n' "$(relative_path "$INBOX_SYSTEM_SCREENSHOT")"
    printf -- '- Today Light: `%s`\n' "$(relative_path "$TODAY_LIGHT_SCREENSHOT")"
    printf -- '- Today Dark: `%s`\n' "$(relative_path "$TODAY_DARK_SCREENSHOT")"
    printf -- '- Today System: `%s`\n' "$(relative_path "$TODAY_SYSTEM_SCREENSHOT")"
    printf -- '- Settings Overview Light: `%s`\n' "$(relative_path "$SETTINGS_OVERVIEW_LIGHT_SCREENSHOT")"
    printf -- '- Settings Overview Dark: `%s`\n' "$(relative_path "$SETTINGS_OVERVIEW_DARK_SCREENSHOT")"
    printf -- '- Settings Overview System: `%s`\n' "$(relative_path "$SETTINGS_OVERVIEW_SYSTEM_SCREENSHOT")"
    printf -- '- Settings Appearance Light: `%s`\n' "$(relative_path "$SETTINGS_APPEARANCE_LIGHT_SCREENSHOT")"
    printf -- '- Settings Appearance Dark: `%s`\n' "$(relative_path "$SETTINGS_APPEARANCE_DARK_SCREENSHOT")"
    printf -- '- Settings Appearance System: `%s`\n' "$(relative_path "$SETTINGS_APPEARANCE_SYSTEM_SCREENSHOT")"
    printf -- '- MCP Settings Light: `%s`\n' "$(relative_path "$MCP_SETTINGS_LIGHT_SCREENSHOT")"
    printf -- '- MCP Settings Dark: `%s`\n' "$(relative_path "$MCP_SETTINGS_DARK_SCREENSHOT")"
    printf -- '- MCP Settings System: `%s`\n' "$(relative_path "$MCP_SETTINGS_SYSTEM_SCREENSHOT")"
    printf -- '- Voice Command Light: `%s`\n' "$(relative_path "$VOICE_COMMAND_LIGHT_SCREENSHOT")"
    printf -- '- Voice Command Dark: `%s`\n' "$(relative_path "$VOICE_COMMAND_DARK_SCREENSHOT")"
    printf -- '- Voice Command System: `%s`\n' "$(relative_path "$VOICE_COMMAND_SYSTEM_SCREENSHOT")"
    printf -- '- Schedule Workload Light: `%s`\n' "$(relative_path "$SCHEDULE_WORKLOAD_LIGHT_SCREENSHOT")"
    printf -- '- Schedule Workload Dark: `%s`\n' "$(relative_path "$SCHEDULE_WORKLOAD_DARK_SCREENSHOT")"
    printf '\n'
    printf '%s\n' '## Notes'
    printf '\n'
    printf '%s\n' '- The script seeds only deterministic local Project/Task/MCP registration data into the isolated SQLite database.'
    printf '%s\n' '- Secret input screens are excluded from the default visual baseline manifest.'
    printf '%s\n' '- Only masked SecureField state may be captured if a future release needs a secret-entry screenshot.'
    printf '%s\n' '- API keys and provider tokens are not read, written, logged, rendered, or captured unmasked.'
    printf '%s\n' '- Run `script/capture_ui_evidence.sh --doctor` first to verify required commands and Screen Recording visible-pixel capture without writing release evidence.'
    printf '%s\n' '- The capture host must grant Screen Recording permission through System Settings > Privacy & Security > Screen Recording / Screen & System Audio Recording to the terminal/Codex app; otherwise the script fails before treating screenshots as evidence.'
    printf '%s\n' '- If capture still fails, rerun with `SOLOPM_UI_EVIDENCE_KEEP_HOME=1` to keep the isolated HOME for database and preference inspection.'
    printf '%s\n' '- VoiceOver focus order still requires a manual assistive-technology pass.'
  } >"$EVIDENCE_FILE"
}

write_p0_workflow_evidence_file() {
  local generated_at="$1"
  local inbox_light_path="$2"
  local inbox_dark_path="$3"
  local inbox_system_path="$4"
  local today_light_path="$5"
  local today_dark_path="$6"
  local today_system_path="$7"
  local inbox_voice_light_path="$8"
  local inbox_voice_dark_path="$9"
  local source_commit
  source_commit="$(ui_evidence_source_commit)"

  {
    printf '%s\n' '# P0 Workflow Screenshot Evidence'
    printf '\n'
    printf '%s\n' 'Generated with `script/capture_ui_evidence.sh --p0-workflows`.'
    printf '%s\n' 'This targeted evidence covers the Personal MVP Inbox and Today closeout paths without rewriting the full release screenshot set.'
    printf '\n'
    printf -- '- Generated at: `%s`\n' "$generated_at"
    printf -- '- Source commit: `%s`\n' "$source_commit"
    printf -- '- Screen Recording preflight: `script/capture_ui_evidence.sh --doctor`\n'
    printf '\n'
    printf '%s\n' '## Inbox'
    printf '\n'
    printf -- '- Light: `%s`\n' "$(relative_path "$inbox_light_path")"
    printf -- '- Dark: `%s`\n' "$(relative_path "$inbox_dark_path")"
    printf -- '- System: `%s`\n' "$(relative_path "$inbox_system_path")"
    printf '\n'
    printf '%s\n' '## Today'
    printf '\n'
    printf -- '- Light: `%s`\n' "$(relative_path "$today_light_path")"
    printf -- '- Dark: `%s`\n' "$(relative_path "$today_dark_path")"
    printf -- '- System: `%s`\n' "$(relative_path "$today_system_path")"
    printf '\n'
    printf '%s\n' '## Inbox Voice Detail'
    printf '\n'
    printf -- '- Light: `%s`\n' "$(relative_path "$inbox_voice_light_path")"
    printf -- '- Dark: `%s`\n' "$(relative_path "$inbox_voice_dark_path")"
    printf '\n'
    printf '%s\n' '## Guardrails'
    printf '\n'
    printf '%s\n' '- API keys, provider tokens, OAuth tokens, calendar contents, and customer file contents are not captured.'
    printf '%s\n' '- The app runs with `SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1`, an isolated HOME, and a seeded SQLite database.'
    printf '%s\n' '- The P0 workflow capture uses `SOLOPM_LAUNCH_RECOVERY_MODE=1` so evidence targets Today and Inbox workflow rails directly.'
  } >"$ROOT_DIR/docs/release/evidence/p0-workflow-screenshots.md"
}

write_schedule_cockpit_evidence_file() {
  local generated_at="$1"
  local schedule_light_path="$2"
  local schedule_dark_path="$3"
  local source_commit
  source_commit="$(ui_evidence_source_commit)"

  {
    printf '%s\n' '# Schedule Cockpit Screenshot Evidence'
    printf '\n'
    printf '%s\n' 'Generated with `script/capture_ui_evidence.sh --schedule-cockpit`.'
    printf '%s\n' 'This targeted evidence covers issue #9 Schedule cockpit light/dark closeout without rewriting the full release screenshot set.'
    printf '\n'
    printf -- '- Generated at: `%s`\n' "$generated_at"
    printf -- '- Source commit: `%s`\n' "$source_commit"
    printf -- '- Screen Recording preflight: `script/capture_ui_evidence.sh --doctor`\n'
    printf -- '- Target markers: `schedule-workflow`, `schedule-week-grid`, `schedule-week-time-axis-grid`\n'
    printf '\n'
    printf '%s\n' '## Schedule Cockpit'
    printf '\n'
    printf -- '- Light: `%s`\n' "$(relative_path "$schedule_light_path")"
    printf -- '- Dark: `%s`\n' "$(relative_path "$schedule_dark_path")"
    printf '\n'
    printf '%s\n' '## Guardrails'
    printf '\n'
    printf '%s\n' '- The cockpit is seeded from local ProjectBoard tasks in an isolated SQLite database.'
    printf '%s\n' '- Opening the cockpit does not enqueue or execute external Calendar or Reminder writes.'
    printf '%s\n' '- API keys, provider tokens, OAuth tokens, calendar contents, and customer file contents are not captured.'
    printf '%s\n' '- The app runs with `SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1`, an explicit isolated SQLite database, and env-driven Schedule selection.'
  } >"$SCHEDULE_COCKPIT_EVIDENCE_FILE"
}

write_schedule_workload_evidence_file() {
  local generated_at="$1"
  local schedule_workload_light_path="$2"
  local schedule_workload_dark_path="$3"
  local source_commit
  source_commit="$(ui_evidence_source_commit)"

  {
    printf '%s\n' '# Schedule Workload Screenshot Evidence'
    printf '\n'
    printf '%s\n' 'Generated with `script/capture_ui_evidence.sh --schedule-workload`.'
    printf '%s\n' 'This targeted evidence covers the issue #1 calendar workload dashboard without rewriting the full release screenshot set.'
    printf '\n'
    printf -- '- Generated at: `%s`\n' "$generated_at"
    printf -- '- Source commit: `%s`\n' "$source_commit"
    printf -- '- Screen Recording preflight: `script/capture_ui_evidence.sh --doctor`\n'
    printf -- '- Target markers: `schedule-workflow`, `schedule-workload-dashboard`, `schedule-workload-attention-banner`, `schedule-workload-day-detail`\n'
    printf '\n'
    printf '%s\n' '## Schedule Workload'
    printf '\n'
    printf -- '- Light: `%s`\n' "$(relative_path "$schedule_workload_light_path")"
    printf -- '- Dark: `%s`\n' "$(relative_path "$schedule_workload_dark_path")"
    printf '\n'
    printf '%s\n' '## Guardrails'
    printf '\n'
    printf '%s\n' '- The dashboard is seeded from local ProjectBoard tasks in an isolated SQLite database.'
    printf '%s\n' '- Opening the workload dashboard does not enqueue or execute external Calendar writes.'
    printf '%s\n' '- API keys, provider tokens, OAuth tokens, calendar contents, and customer file contents are not captured.'
    printf '%s\n' '- The app runs with `SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1`, an isolated HOME, and a seeded SQLite database.'
  } >"$ROOT_DIR/docs/release/evidence/schedule-workload-screenshots.md"
}

write_visual_baseline_capture_manifest() {
  local generated_at="$1"
  local output_file="$SCREENSHOT_DIR/visual-baseline-capture-manifest.json"

  {
    printf '%s\n' '{'
    printf '  "generatedAt": "%s",\n' "$generated_at"
    printf '  "sourceManifest": "%s",\n' "$(relative_path "$VISUAL_BASELINE_MANIFEST")"
    printf '  "screenshotDirectory": "%s",\n' "$(relative_path "$SCREENSHOT_DIR")"
    printf '  "mainViewport": "%s",\n' "$VISUAL_BASELINE_VIEWPORT"
    printf '  "settingsViewport": "%s",\n' "$SETTINGS_VISUAL_BASELINE_VIEWPORT"
    printf '  "comparison": "semantic"\n'
    printf '%s\n' '}'
  } >"$output_file"
}

run_doctor() {
  echo "UI evidence doctor"
  echo "bundle: $APP_BUNDLE"
  echo "home: $EVIDENCE_HOME"
  echo "screenshots: $SCREENSHOT_DIR"
  echo "evidence: $EVIDENCE_FILE"
  echo "visual baseline manifest: $VISUAL_BASELINE_MANIFEST"
  echo "visual viewport: $VISUAL_BASELINE_VIEWPORT"
  echo "settings visual viewport: $SETTINGS_VISUAL_BASELINE_VIEWPORT"
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
  echo "visual baseline manifest: $VISUAL_BASELINE_MANIFEST"
  echo "visual viewport: $VISUAL_BASELINE_VIEWPORT"
  echo "settings visual viewport: $SETTINGS_VISUAL_BASELINE_VIEWPORT"
  exit 0
fi

"$ROOT_DIR/script/build_and_run.sh" --build-only

DATABASE_PATH="$EVIDENCE_HOME/Library/Application Support/SoloPM/SoloPM.sqlite"
initialize_database "$DATABASE_PATH"
seed_database "$DATABASE_PATH"
seed_mcp_registrations "$DATABASE_PATH"
assert_phase12_seed_data "$DATABASE_PATH"
assert_valid_seed_task_statuses "$DATABASE_PATH"
persist_project_board_selection "$DATABASE_PATH"

LIGHT_SCREENSHOT="$SCREENSHOT_DIR/project-board-light.png"
DARK_SCREENSHOT="$SCREENSHOT_DIR/project-board-dark.png"
SYSTEM_SCREENSHOT="$SCREENSHOT_DIR/project-board-system.png"
SETTINGS_OVERVIEW_LIGHT_SCREENSHOT="$SCREENSHOT_DIR/settings-overview-light.png"
SETTINGS_OVERVIEW_DARK_SCREENSHOT="$SCREENSHOT_DIR/settings-overview-dark.png"
SETTINGS_APPEARANCE_LIGHT_SCREENSHOT="$SCREENSHOT_DIR/settings-appearance-light.png"
SETTINGS_APPEARANCE_DARK_SCREENSHOT="$SCREENSHOT_DIR/settings-appearance-dark.png"
MCP_SETTINGS_LIGHT_SCREENSHOT="$SCREENSHOT_DIR/settings-mcp-light.png"
MCP_SETTINGS_DARK_SCREENSHOT="$SCREENSHOT_DIR/settings-mcp-dark.png"
INBOX_LIGHT_SCREENSHOT="$SCREENSHOT_DIR/inbox-light.png"
INBOX_DARK_SCREENSHOT="$SCREENSHOT_DIR/inbox-dark.png"
INBOX_SYSTEM_SCREENSHOT="$SCREENSHOT_DIR/inbox-system.png"
TODAY_LIGHT_SCREENSHOT="$SCREENSHOT_DIR/today-light.png"
TODAY_DARK_SCREENSHOT="$SCREENSHOT_DIR/today-dark.png"
TODAY_SYSTEM_SCREENSHOT="$SCREENSHOT_DIR/today-system.png"
SETTINGS_OVERVIEW_SYSTEM_SCREENSHOT="$SCREENSHOT_DIR/settings-overview-system.png"
SETTINGS_APPEARANCE_SYSTEM_SCREENSHOT="$SCREENSHOT_DIR/settings-appearance-system.png"
MCP_SETTINGS_SYSTEM_SCREENSHOT="$SCREENSHOT_DIR/settings-mcp-system.png"
VOICE_COMMAND_LIGHT_SCREENSHOT="$SCREENSHOT_DIR/voice-command-light.png"
VOICE_COMMAND_DARK_SCREENSHOT="$SCREENSHOT_DIR/voice-command-dark.png"
VOICE_COMMAND_SYSTEM_SCREENSHOT="$SCREENSHOT_DIR/voice-command-system.png"
INBOX_VOICE_LIGHT_SCREENSHOT="$SCREENSHOT_DIR/inbox-voice-light.png"
INBOX_VOICE_DARK_SCREENSHOT="$SCREENSHOT_DIR/inbox-voice-dark.png"
PROJECTS_OVERVIEW_LIGHT_SCREENSHOT="$SCREENSHOT_DIR/projects-overview-light.png"
PROJECTS_OVERVIEW_DARK_SCREENSHOT="$SCREENSHOT_DIR/projects-overview-dark.png"
SCHEDULE_LIGHT_SCREENSHOT="$SCREENSHOT_DIR/schedule-light.png"
SCHEDULE_DARK_SCREENSHOT="$SCREENSHOT_DIR/schedule-dark.png"
SCHEDULE_WORKLOAD_LIGHT_SCREENSHOT="$SCREENSHOT_DIR/schedule-workload-light.png"
SCHEDULE_WORKLOAD_DARK_SCREENSHOT="$SCREENSHOT_DIR/schedule-workload-dark.png"
DONE_LIGHT_SCREENSHOT="$SCREENSHOT_DIR/done-light.png"
DONE_DARK_SCREENSHOT="$SCREENSHOT_DIR/done-dark.png"
SETTINGS_INTEGRATIONS_LIGHT_SCREENSHOT="$SCREENSHOT_DIR/settings-integrations-light.png"
SETTINGS_INTEGRATIONS_DARK_SCREENSHOT="$SCREENSHOT_DIR/settings-integrations-dark.png"

INBOX_TARGET_MARKERS="sidebar-destination-inbox=>Inbox|inbox-action-panel=>Inbox"
TODAY_TARGET_MARKERS="sidebar-destination-today=>Today|today-briefing-panel=>Today|today-assistant-rail=>Today"
P0_INBOX_TARGET_MARKERS="inbox-workflow=>Inbox|inbox-action-panel=>Inbox"
P0_TODAY_TARGET_MARKERS="today-workflow=>Today|today-briefing-panel=>Today|today-assistant-rail=>Today"
P0_INBOX_VOICE_TARGET_MARKERS="inbox-workflow=>Inbox|inbox-action-panel=>Voice capture metadata available for Scheduled manual capture|inbox-action-panel=>Schedule launch review and capture visual evidence.|inbox-action-panel=>Create a task for launch review evidence.|inbox-action-make-task=>Inbox classification actions"
PROJECTS_TARGET_MARKERS="sidebar-destination-projects=>Projects|projects-portfolio-overview=>Projects"
SCHEDULE_TARGET_MARKERS="sidebar-destination-schedule=>Schedule|schedule-workflow=>Schedule|schedule-week-grid=>Weekly schedule grid|schedule-week-time-axis-grid=>Schedule time axis grid"
SCHEDULE_COCKPIT_TARGET_MARKERS="schedule-workflow=>Schedule|schedule-week-grid=>schedule-week-grid|schedule-week-time-axis-grid=>schedule-week-time-axis-grid"
SCHEDULE_WORKLOAD_TARGET_MARKERS="sidebar-destination-schedule=>Schedule|schedule-workflow=>Schedule|schedule-workload-dashboard=>schedule-workload-dashboard|schedule-workload-attention-banner=>schedule-workload-attention-banner|schedule-workload-day-detail=>schedule-workload-day-detail"
DONE_TARGET_MARKERS="sidebar-destination-done=>Done|done-workflow=>Done"
VOICE_COMMAND_TARGET_MARKERS="voice-command-root=>Voice Command|voice-command-input=>Voice Command"

if [[ "$P0_WORKFLOWS" == "1" ]]; then
  capture_project_board_destination light inbox "$INBOX_LIGHT_SCREENSHOT" "Inbox" "$P0_INBOX_TARGET_MARKERS"
  capture_project_board_destination dark inbox "$INBOX_DARK_SCREENSHOT" "Inbox" "$P0_INBOX_TARGET_MARKERS"
  capture_project_board_destination system inbox "$INBOX_SYSTEM_SCREENSHOT" "Inbox" "$P0_INBOX_TARGET_MARKERS"
  capture_project_board_destination light today "$TODAY_LIGHT_SCREENSHOT" "Today" "$P0_TODAY_TARGET_MARKERS"
  capture_project_board_destination dark today "$TODAY_DARK_SCREENSHOT" "Today" "$P0_TODAY_TARGET_MARKERS"
  capture_project_board_destination system today "$TODAY_SYSTEM_SCREENSHOT" "Today" "$P0_TODAY_TARGET_MARKERS"
  capture_project_board_destination light inbox "$INBOX_VOICE_LIGHT_SCREENSHOT" "Inbox voice detail" "$P0_INBOX_VOICE_TARGET_MARKERS" "$INBOX_VOICE_TASK_OVERRIDE"
  capture_project_board_destination dark inbox "$INBOX_VOICE_DARK_SCREENSHOT" "Inbox voice detail" "$P0_INBOX_VOICE_TARGET_MARKERS" "$INBOX_VOICE_TASK_OVERRIDE"

  GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  write_p0_workflow_evidence_file "$GENERATED_AT" "$INBOX_LIGHT_SCREENSHOT" "$INBOX_DARK_SCREENSHOT" "$INBOX_SYSTEM_SCREENSHOT" "$TODAY_LIGHT_SCREENSHOT" "$TODAY_DARK_SCREENSHOT" "$TODAY_SYSTEM_SCREENSHOT" "$INBOX_VOICE_LIGHT_SCREENSHOT" "$INBOX_VOICE_DARK_SCREENSHOT"

  echo "P0 workflow screenshot evidence generated:"
  echo "evidence: $ROOT_DIR/docs/release/evidence/p0-workflow-screenshots.md"
  echo "screenshots: $SCREENSHOT_DIR"
  exit 0
fi

if [[ "$SCHEDULE_COCKPIT" == "1" ]]; then
  capture_project_board_destination light schedule "$SCHEDULE_LIGHT_SCREENSHOT" "Schedule cockpit" "$SCHEDULE_COCKPIT_TARGET_MARKERS"
  capture_project_board_destination dark schedule "$SCHEDULE_DARK_SCREENSHOT" "Schedule cockpit" "$SCHEDULE_COCKPIT_TARGET_MARKERS"

  GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  write_schedule_cockpit_evidence_file "$GENERATED_AT" "$SCHEDULE_LIGHT_SCREENSHOT" "$SCHEDULE_DARK_SCREENSHOT"

  echo "Schedule cockpit screenshot evidence generated:"
  echo "evidence: $SCHEDULE_COCKPIT_EVIDENCE_FILE"
  echo "screenshots: $SCREENSHOT_DIR"
  exit 0
fi

if [[ "$SCHEDULE_WORKLOAD" == "1" ]]; then
  capture_project_board_destination light schedule "$SCHEDULE_WORKLOAD_LIGHT_SCREENSHOT" "Schedule workload dashboard" "$SCHEDULE_WORKLOAD_TARGET_MARKERS"
  capture_project_board_destination dark schedule "$SCHEDULE_WORKLOAD_DARK_SCREENSHOT" "Schedule workload dashboard" "$SCHEDULE_WORKLOAD_TARGET_MARKERS"

  GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  write_schedule_workload_evidence_file "$GENERATED_AT" "$SCHEDULE_WORKLOAD_LIGHT_SCREENSHOT" "$SCHEDULE_WORKLOAD_DARK_SCREENSHOT"

  echo "Schedule workload screenshot evidence generated:"
  echo "evidence: $ROOT_DIR/docs/release/evidence/schedule-workload-screenshots.md"
  echo "screenshots: $SCREENSHOT_DIR"
  exit 0
fi

capture_project_board_destination light "$PROJECT_BOARD_SELECTION_OVERRIDE" "$LIGHT_SCREENSHOT" "Project Board" "$PROJECT_BOARD_TARGET_MARKERS"
capture_project_board_destination dark "$PROJECT_BOARD_SELECTION_OVERRIDE" "$DARK_SCREENSHOT" "Project Board" "$PROJECT_BOARD_TARGET_MARKERS"
capture_project_board_destination system "$PROJECT_BOARD_SELECTION_OVERRIDE" "$SYSTEM_SCREENSHOT" "Project Board" "$PROJECT_BOARD_TARGET_MARKERS"
capture_project_board_destination light inbox "$INBOX_LIGHT_SCREENSHOT" "Inbox" "$INBOX_TARGET_MARKERS"
capture_project_board_destination dark inbox "$INBOX_DARK_SCREENSHOT" "Inbox" "$INBOX_TARGET_MARKERS"
capture_project_board_destination system inbox "$INBOX_SYSTEM_SCREENSHOT" "Inbox" "$INBOX_TARGET_MARKERS"
capture_project_board_destination light today "$TODAY_LIGHT_SCREENSHOT" "Today" "$TODAY_TARGET_MARKERS"
capture_project_board_destination dark today "$TODAY_DARK_SCREENSHOT" "Today" "$TODAY_TARGET_MARKERS"
capture_project_board_destination system today "$TODAY_SYSTEM_SCREENSHOT" "Today" "$TODAY_TARGET_MARKERS"
capture_voice_command_appearance light "$VOICE_COMMAND_LIGHT_SCREENSHOT"
capture_voice_command_appearance dark "$VOICE_COMMAND_DARK_SCREENSHOT"
capture_voice_command_appearance system "$VOICE_COMMAND_SYSTEM_SCREENSHOT"
capture_project_board_destination light inbox "$INBOX_VOICE_LIGHT_SCREENSHOT" "Inbox voice detail" "$INBOX_VOICE_TARGET_MARKERS" "$INBOX_VOICE_TASK_OVERRIDE"
capture_project_board_destination dark inbox "$INBOX_VOICE_DARK_SCREENSHOT" "Inbox voice detail" "$INBOX_VOICE_TARGET_MARKERS" "$INBOX_VOICE_TASK_OVERRIDE"
capture_project_board_destination light projects "$PROJECTS_OVERVIEW_LIGHT_SCREENSHOT" "Projects overview" "$PROJECTS_TARGET_MARKERS"
capture_project_board_destination dark projects "$PROJECTS_OVERVIEW_DARK_SCREENSHOT" "Projects overview" "$PROJECTS_TARGET_MARKERS"
capture_project_board_destination light schedule "$SCHEDULE_LIGHT_SCREENSHOT" "Schedule cockpit" "$SCHEDULE_TARGET_MARKERS"
capture_project_board_destination dark schedule "$SCHEDULE_DARK_SCREENSHOT" "Schedule cockpit" "$SCHEDULE_TARGET_MARKERS"
capture_project_board_destination light schedule "$SCHEDULE_WORKLOAD_LIGHT_SCREENSHOT" "Schedule workload dashboard" "$SCHEDULE_WORKLOAD_TARGET_MARKERS"
capture_project_board_destination dark schedule "$SCHEDULE_WORKLOAD_DARK_SCREENSHOT" "Schedule workload dashboard" "$SCHEDULE_WORKLOAD_TARGET_MARKERS"
capture_project_board_destination light done "$DONE_LIGHT_SCREENSHOT" "Done analytics" "$DONE_TARGET_MARKERS"
capture_project_board_destination dark done "$DONE_DARK_SCREENSHOT" "Done analytics" "$DONE_TARGET_MARKERS"
capture_settings_overview light "$SETTINGS_OVERVIEW_LIGHT_SCREENSHOT"
capture_settings_overview dark "$SETTINGS_OVERVIEW_DARK_SCREENSHOT"
capture_settings_overview light "$SETTINGS_INTEGRATIONS_LIGHT_SCREENSHOT"
capture_settings_overview dark "$SETTINGS_INTEGRATIONS_DARK_SCREENSHOT"
capture_settings_overview system "$SETTINGS_OVERVIEW_SYSTEM_SCREENSHOT"
capture_settings_appearance light "$SETTINGS_APPEARANCE_LIGHT_SCREENSHOT"
capture_settings_appearance dark "$SETTINGS_APPEARANCE_DARK_SCREENSHOT"
capture_settings_appearance system "$SETTINGS_APPEARANCE_SYSTEM_SCREENSHOT"
capture_mcp_settings_appearance light "$MCP_SETTINGS_LIGHT_SCREENSHOT"
capture_mcp_settings_appearance dark "$MCP_SETTINGS_DARK_SCREENSHOT"
capture_mcp_settings_appearance system "$MCP_SETTINGS_SYSTEM_SCREENSHOT"

GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
write_evidence_file "$GENERATED_AT" "$LIGHT_SCREENSHOT" "$DARK_SCREENSHOT" "$SYSTEM_SCREENSHOT" "$SETTINGS_OVERVIEW_LIGHT_SCREENSHOT" "$SETTINGS_OVERVIEW_DARK_SCREENSHOT" "$SETTINGS_APPEARANCE_LIGHT_SCREENSHOT" "$SETTINGS_APPEARANCE_DARK_SCREENSHOT" "$MCP_SETTINGS_LIGHT_SCREENSHOT" "$MCP_SETTINGS_DARK_SCREENSHOT" "$INBOX_VOICE_LIGHT_SCREENSHOT" "$INBOX_VOICE_DARK_SCREENSHOT" "$PROJECTS_OVERVIEW_LIGHT_SCREENSHOT" "$PROJECTS_OVERVIEW_DARK_SCREENSHOT" "$SCHEDULE_LIGHT_SCREENSHOT" "$SCHEDULE_DARK_SCREENSHOT" "$DONE_LIGHT_SCREENSHOT" "$DONE_DARK_SCREENSHOT" "$SETTINGS_INTEGRATIONS_LIGHT_SCREENSHOT" "$SETTINGS_INTEGRATIONS_DARK_SCREENSHOT"
write_visual_baseline_capture_manifest "$GENERATED_AT"

echo "UI screenshot evidence generated:"
echo "- $(relative_path "$LIGHT_SCREENSHOT")"
echo "- $(relative_path "$DARK_SCREENSHOT")"
echo "- $(relative_path "$SYSTEM_SCREENSHOT")"
echo "- $(relative_path "$INBOX_LIGHT_SCREENSHOT")"
echo "- $(relative_path "$INBOX_DARK_SCREENSHOT")"
echo "- $(relative_path "$INBOX_SYSTEM_SCREENSHOT")"
echo "- $(relative_path "$TODAY_LIGHT_SCREENSHOT")"
echo "- $(relative_path "$TODAY_DARK_SCREENSHOT")"
echo "- $(relative_path "$TODAY_SYSTEM_SCREENSHOT")"
echo "- $(relative_path "$VOICE_COMMAND_LIGHT_SCREENSHOT")"
echo "- $(relative_path "$VOICE_COMMAND_DARK_SCREENSHOT")"
echo "- $(relative_path "$VOICE_COMMAND_SYSTEM_SCREENSHOT")"
echo "- $(relative_path "$SETTINGS_OVERVIEW_LIGHT_SCREENSHOT")"
echo "- $(relative_path "$SETTINGS_OVERVIEW_DARK_SCREENSHOT")"
echo "- $(relative_path "$SETTINGS_OVERVIEW_SYSTEM_SCREENSHOT")"
echo "- $(relative_path "$INBOX_VOICE_LIGHT_SCREENSHOT")"
echo "- $(relative_path "$INBOX_VOICE_DARK_SCREENSHOT")"
echo "- $(relative_path "$PROJECTS_OVERVIEW_LIGHT_SCREENSHOT")"
echo "- $(relative_path "$PROJECTS_OVERVIEW_DARK_SCREENSHOT")"
echo "- $(relative_path "$SCHEDULE_LIGHT_SCREENSHOT")"
echo "- $(relative_path "$SCHEDULE_DARK_SCREENSHOT")"
echo "- $(relative_path "$DONE_LIGHT_SCREENSHOT")"
echo "- $(relative_path "$DONE_DARK_SCREENSHOT")"
echo "- $(relative_path "$SETTINGS_INTEGRATIONS_LIGHT_SCREENSHOT")"
echo "- $(relative_path "$SETTINGS_INTEGRATIONS_DARK_SCREENSHOT")"
echo "- $(relative_path "$SETTINGS_APPEARANCE_LIGHT_SCREENSHOT")"
echo "- $(relative_path "$SETTINGS_APPEARANCE_DARK_SCREENSHOT")"
echo "- $(relative_path "$SETTINGS_APPEARANCE_SYSTEM_SCREENSHOT")"
echo "- $(relative_path "$MCP_SETTINGS_LIGHT_SCREENSHOT")"
echo "- $(relative_path "$MCP_SETTINGS_DARK_SCREENSHOT")"
echo "- $(relative_path "$MCP_SETTINGS_SYSTEM_SCREENSHOT")"
echo "- $(relative_path "$EVIDENCE_FILE")"
