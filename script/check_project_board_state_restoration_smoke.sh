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
WINDOW_NAME="${SUISUI_PROJECT_BOARD_WINDOW_NAME:-Suisui}"
TIMEOUT_SECONDS="${SUISUI_STATE_RESTORATION_TIMEOUT_SECONDS:-30}"
STATE_RESTORATION_OUTPUT_DIR="${SUISUI_STATE_RESTORATION_OUTPUT_DIR:-$ROOT_DIR/.tmp/project-board-state-restoration}"
STATE_RESTORATION_MANY_PROJECT_COUNT="${SUISUI_STATE_RESTORATION_MANY_PROJECT_COUNT:-24}"
STATE_RESTORATION_MANY_TASKS_PER_PROJECT="${SUISUI_STATE_RESTORATION_MANY_TASKS_PER_PROJECT:-12}"
KEEP_OUTPUT="${SUISUI_STATE_RESTORATION_KEEP_OUTPUT:-0}"
SQLITE3="${SQLITE3:-/usr/bin/sqlite3}"

if [[ ! "$TIMEOUT_SECONDS" =~ ^[0-9]+$ || "$TIMEOUT_SECONDS" -lt 1 ]]; then
  echo "SUISUI_STATE_RESTORATION_TIMEOUT_SECONDS must be a positive integer" >&2
  exit 2
fi

for numeric_name in STATE_RESTORATION_MANY_PROJECT_COUNT STATE_RESTORATION_MANY_TASKS_PER_PROJECT; do
  numeric_value="${!numeric_name}"
  if [[ ! "$numeric_value" =~ ^[0-9]+$ || "$numeric_value" -lt 1 ]]; then
    echo "$numeric_name must be a positive integer" >&2
    exit 2
  fi
done

if ! command -v "$SQLITE3" >/dev/null 2>&1; then
  echo "BLOCKER: sqlite3 is required for Project Board state restoration smoke" >&2
  exit 2
fi

cd "$ROOT_DIR"
mkdir -p "$ROOT_DIR/.tmp" "$STATE_RESTORATION_OUTPUT_DIR"
tmp_dir="$(mktemp -d "$ROOT_DIR/.tmp/project-board-state-restoration.XXXXXX")"
empty_database_path="$tmp_dir/empty.sqlite"
normal_database_path="$tmp_dir/normal.sqlite"
many_database_path="$tmp_dir/many.sqlite"
summary_file="$STATE_RESTORATION_OUTPUT_DIR/state-restoration-summary.md"
app_pid=""

terminate_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  if [[ -n "${app_pid:-}" ]]; then
    wait "$app_pid" >/dev/null 2>&1 || true
    app_pid=""
  fi
}

cleanup() {
  terminate_app
  if [[ "$KEEP_OUTPUT" != "1" ]]; then
    rm -rf "$tmp_dir"
  else
    printf "INFO: kept Project Board state restoration databases in %s\n" "$tmp_dir"
  fi
}
trap cleanup EXIT

query_single_value() {
  local database_path="$1"
  local sql="$2"
  "$SQLITE3" -batch -noheader "$database_path" "$sql" | tail -n 1
}

sql_escape() {
  printf "%s" "$1" | sed "s/'/''/g"
}

wait_for_app_process() {
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while ! pgrep -x "$APP_NAME" >/dev/null 2>&1; do
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: Project Board state restoration app process did not appear within ${TIMEOUT_SECONDS}s" >&2
      return 1
    fi
    sleep 1
  done
}

wait_for_no_app_process() {
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while pgrep -x "$APP_NAME" >/dev/null 2>&1; do
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      pkill -x "$APP_NAME" >/dev/null 2>&1 || true
      return 0
    fi
    sleep 1
  done
}

activate_app() {
  # Activation stays in System Events so LaunchServices never starts a second
  # instance without the isolated database and selected-destination environment.
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
      return 0
    fi
    sleep 0.1
  done
  kill "$osascript_pid" >/dev/null 2>&1 || true
  wait "$osascript_pid" >/dev/null 2>&1 || true
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
      echo "BLOCKER: Project Board state restoration app did not expose a visible AX window within ${TIMEOUT_SECONDS}s" >&2
      return 1
    fi
    sleep 1
  done
}

wait_for_database_table() {
  local database_path="$1"
  local table="$2"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while true; do
    if [[ -f "$database_path" ]] && "$SQLITE3" "$database_path" "SELECT name FROM sqlite_master WHERE type='table' AND name='$table';" | grep -Fx "$table" >/dev/null; then
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: Project Board state restoration database did not create table '$table': $database_path" >&2
      return 1
    fi
    sleep 1
  done
}

wait_for_project_board_window_metadata() {
  local label="$1"
  local output_file="$STATE_RESTORATION_OUTPUT_DIR/$label-window.tsv"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local metadata_output=""
  local metadata_status=1

  while true; do
    set +e
    metadata_output="$(
      SUISUI_WINDOW_OWNER="$APP_NAME" \
      SUISUI_WINDOW_NAME="$WINDOW_NAME" \
      /usr/bin/swift "$ROOT_DIR/script/ui_evidence_window_metadata.swift" 2>&1
    )"
    metadata_status=$?
    set -e

    if [[ "$metadata_status" -eq 0 ]]; then
      printf "%s\n" "$metadata_output" >"$output_file"
      return 0
    fi

    activate_app
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      printf "%s\n" "$metadata_output" >&2
      echo "BLOCKER: Project Board state restoration window metadata was unavailable for $label within ${TIMEOUT_SECONDS}s" >&2
      return 1
    fi
    sleep 1
  done
}

launch_state_case() {
  local label="$1"
  local database_path="$2"
  local selected_destination="$3"

  terminate_app
  SUISUI_DISABLE_KEYCHAIN_SECRET_STORE=1 \
    SUISUI_DATABASE_PATH="$database_path" \
    SUISUI_PROJECT_BOARD_SELECTED_DESTINATION="$selected_destination" \
    "$APP_BINARY" &
  app_pid=$!
  wait_for_app_process
  activate_app
  wait_for_visible_windows
  wait_for_project_board_window_metadata "$label"
  wait_for_database_table "$database_path" "projects"

  {
    printf '| `%s` | `%s` | `%s` | visible |\n' "$label" "$database_path" "$selected_destination"
    printf -- '- `%s` launch env: `SUISUI_PROJECT_BOARD_SELECTED_DESTINATION="%s"`\n' "$label" "$selected_destination"
  } >>"$summary_file"
  printf "OK: Project Board state restoration launched %s with %s\n" "$label" "$selected_destination"

  terminate_app
  wait_for_no_app_process
}

prepare_seed_database() {
  local database_path="$1"
  local seed_project_id=""

  ./script/prepare_voiceover_review_candidate.sh --database "$database_path" --no-launch --skip-build >/dev/null
  terminate_app
  wait_for_no_app_process

  seed_project_id="$(query_single_value "$database_path" "SELECT id FROM projects WHERE title='VoiceOver Review Project' AND source_command='voiceover-review-seed' ORDER BY id DESC LIMIT 1;")"
  if [[ -z "${seed_project_id//[[:space:]]/}" ]]; then
    echo "BLOCKER: Project Board state restoration seed project was not created in $database_path" >&2
    exit 1
  fi
  printf "%s" "$seed_project_id"
}

seed_many_projects_and_tasks() {
  local database_path="$1"
  local existing_project_count
  local project_index
  local task_index
  local projects_to_add
  local expected_smoke_task_count

  existing_project_count="$(query_single_value "$database_path" "SELECT count(*) FROM projects;")"
  projects_to_add=$((STATE_RESTORATION_MANY_PROJECT_COUNT - existing_project_count))
  if [[ "$projects_to_add" -lt 0 ]]; then
    projects_to_add=0
  fi
  expected_smoke_task_count=$((projects_to_add * STATE_RESTORATION_MANY_TASKS_PER_PROJECT))

  for project_index in $(seq 1 "$projects_to_add"); do
    local project_title="State Restoration Project $project_index"
    local escaped_project_title
    local project_id
    escaped_project_title="$(sql_escape "$project_title")"
    "$SQLITE3" "$database_path" <<SQL
PRAGMA foreign_keys = ON;
INSERT INTO projects (title, status, priority, deadline, workspace_path, tags_json, source_command, created_at, updated_at)
VALUES (
  '$escaped_project_title',
  'active',
  'medium',
  NULL,
  NULL,
  '["state-restoration"]',
  'project-board-state-restoration-smoke',
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
);
SQL
    project_id="$(query_single_value "$database_path" "SELECT id FROM projects WHERE title='$escaped_project_title' AND source_command='project-board-state-restoration-smoke' ORDER BY id DESC LIMIT 1;")"
    if [[ -z "${project_id//[[:space:]]/}" ]]; then
      echo "BLOCKER: Project Board state restoration many-project seed failed for $project_title" >&2
      exit 1
    fi

    for task_index in $(seq 1 "$STATE_RESTORATION_MANY_TASKS_PER_PROJECT"); do
      local status
      case $((task_index % 5)) in
        0) status="completed" ;;
        1) status="backlog" ;;
        2) status="planned" ;;
        3) status="in_progress" ;;
        *) status="blocked" ;;
      esac
      "$SQLITE3" "$database_path" <<SQL
PRAGMA foreign_keys = ON;
INSERT INTO tasks (project_id, title, status, detail, due_at, priority, source_command, created_at, updated_at)
VALUES (
  $project_id,
  'State Restoration Task $project_index.$task_index',
  '$status',
  'Many-database launch fixture task for Project Board state restoration smoke.',
  NULL,
  'medium',
  'project-board-state-restoration-smoke',
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
);
SQL
    done
  done

  local seeded_project_count
  local seeded_smoke_task_count
  seeded_project_count="$(query_single_value "$database_path" "SELECT count(*) FROM projects;")"
  seeded_smoke_task_count="$(query_single_value "$database_path" "SELECT count(*) FROM tasks WHERE source_command='project-board-state-restoration-smoke';")"
  if [[ "$seeded_project_count" -lt "$STATE_RESTORATION_MANY_PROJECT_COUNT" || "$seeded_smoke_task_count" -lt "$expected_smoke_task_count" ]]; then
    echo "BLOCKER: Project Board state restoration many database seed was too small: projects=$seeded_project_count smoke_tasks=$seeded_smoke_task_count" >&2
    exit 1
  fi
}

./script/build_and_run.sh --build-only

if [[ ! -x "$APP_BINARY" ]]; then
  echo "BLOCKER: Project Board state restoration app binary not found or not executable: $APP_BINARY" >&2
  exit 2
fi

{
  printf '# Project Board State Restoration Smoke\n\n'
  printf 'Generated at: %s\n\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf '| Scenario | Database | Selected destination | Window |\n'
  printf '| --- | --- | --- | --- |\n'
} >"$summary_file"

empty_selected_destination="project:42"
# The empty scenario intentionally launches with a stale saved project id:
# SUISUI_PROJECT_BOARD_SELECTED_DESTINATION="project:42"
launch_state_case "empty-database" "$empty_database_path" "$empty_selected_destination"

seed_project_id="$(prepare_seed_database "$normal_database_path")"
# The normal scenario opens the deterministic seeded candidate:
# SUISUI_PROJECT_BOARD_SELECTED_DESTINATION="project:$seed_project_id"
launch_state_case "normal-database" "$normal_database_path" "project:$seed_project_id"

prepare_seed_database "$many_database_path" >/dev/null
seed_many_projects_and_tasks "$many_database_path"
# The many scenario opens the portfolio destination so sidebar/detail restore
# must stay stable under a large project/task list:
# SUISUI_PROJECT_BOARD_SELECTED_DESTINATION="projects"
launch_state_case "many-database" "$many_database_path" "projects"

printf "OK: Project Board state restoration smoke launched empty, normal, and many databases\n"
