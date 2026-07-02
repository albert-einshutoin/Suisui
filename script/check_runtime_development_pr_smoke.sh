#!/usr/bin/env bash
set -euo pipefail
set +m

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
ARTIFACT_DIR="${SOLOPM_RUNTIME_DEVELOPMENT_PR_ARTIFACT_DIR:-$ROOT_DIR/.tmp/runtime-development-pr-smoke}"
KEEP_WORKSPACE="${SOLOPM_RUNTIME_DEVELOPMENT_PR_KEEP_WORKSPACE:-0}"
KEEP_DATABASE="${SOLOPM_RUNTIME_DEVELOPMENT_PR_KEEP_DATABASE:-0}"
TIMEOUT_SECONDS="${SOLOPM_RUNTIME_DEVELOPMENT_PR_TIMEOUT_SECONDS:-30}"
SQLITE3="${SQLITE3:-sqlite3}"
AX_MAX_NODES="${SOLOPM_RUNTIME_DEVELOPMENT_PR_AX_MAX_NODES:-9000}"
WINDOW_WIDTH="${SOLOPM_RUNTIME_DEVELOPMENT_PR_WINDOW_WIDTH:-1440}"
WINDOW_HEIGHT="${SOLOPM_RUNTIME_DEVELOPMENT_PR_WINDOW_HEIGHT:-920}"
OUTPUT_FILE="$ARTIFACT_DIR/swift-test-output.txt"
APP_LOG_FILE="$ARTIFACT_DIR/visible-app-output.txt"
ARTIFACT_FILE="$ARTIFACT_DIR/evidence.md"
WORKSPACE_ROOT="$ARTIFACT_DIR/workspaces"
UI_ROOT="$ARTIFACT_DIR/visible-ui"
UI_HOME="$UI_ROOT/home"
UI_WORKSPACE="$UI_ROOT/approved-workspace"
database_path="$UI_ROOT/SoloPM-runtime-development-pr-ui.sqlite"
receipt_directory="$UI_HOME/Library/Application Support/SoloPM/ExecutionReceipts"
app_pid=""
seed_project_id=""
seed_task_id=""
queued_item_id=""
failure_reason="development PR smoke failed"

mkdir -p "$ARTIFACT_DIR" "$WORKSPACE_ROOT" "$UI_ROOT" "$UI_HOME"
cd "$ROOT_DIR"

if [[ ! "$TIMEOUT_SECONDS" =~ ^[0-9]+$ || "$TIMEOUT_SECONDS" -lt 1 ]]; then
  echo "SOLOPM_RUNTIME_DEVELOPMENT_PR_TIMEOUT_SECONDS must be a positive integer" >&2
  exit 2
fi
if [[ ! "$AX_MAX_NODES" =~ ^[0-9]+$ || "$AX_MAX_NODES" -lt 1 ]]; then
  echo "SOLOPM_RUNTIME_DEVELOPMENT_PR_AX_MAX_NODES must be a positive integer" >&2
  exit 2
fi
if ! command -v "$SQLITE3" >/dev/null 2>&1; then
  echo "BLOCKER: sqlite3 is required for runtime development PR smoke" >&2
  exit 2
fi

ensure_no_existing_app_process() {
  if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    echo "BLOCKER: close running $APP_NAME before runtime development PR smoke; the smoke only terminates its own launched PID." >&2
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

write_artifact() {
  local status="$1"
  local reason="$2"
  {
    printf '# Runtime Development PR Smoke\n\n'
    printf -- '- Status: `%s`\n' "$status"
    printf -- '- Reason: `%s`\n' "$reason"
    printf -- '- XCTest: `DevelopmentAutomationRuntimeSmokeTests/testApprovedProjectDirectoryCanEditVerifyCommitAndPreparePullRequestBranch`\n'
    printf -- '- Flow: approved project directory -> `development.pr_workflow.prepare` -> `development.repository.list_files` -> `development.repository.create_file` -> `development.repository.update_file` -> `development.verification.run` -> `development.pr_workflow.commit` -> `development.pr_workflow.push` -> `development.pr_workflow.create_pull_request` -> `development.pr_workflow.review_gate` -> `development.pr_workflow.merge` with fake Git and GitHub runners\n'
    printf -- '- Visible UI: Project automation panel -> `project-development-automation-queue` -> `project-development-automation-queue-handoff` -> Assistant Queue approve/run -> receipt\n'
    printf -- '- Queued project: `%s`\n' "${seed_project_id:-not-seeded}"
    printf -- '- Queued task: `%s`\n' "${seed_task_id:-not-seeded}"
    printf -- '- Assistant Queue item: `%s`\n' "${queued_item_id:-not-queued}"
    printf -- '- Approval boundary: `requiresPushApproval=true`, `requiresPullRequestApproval=true`\n'
    printf -- '- External writes: No live push, GitHub PR, review gate, or merge is created by this smoke.\n'
    printf -- '- Workspace retention requested: `%s`\n' "$KEEP_WORKSPACE"
    printf -- '- Runtime database retained: `%s`\n' "$KEEP_DATABASE"
    printf -- '- Workspace root: `%s`\n' "$(relative_path "$WORKSPACE_ROOT")"
    printf -- '- Runtime database: `%s`\n' "$(relative_path "$database_path")"
    printf -- '- XCTest output: `%s`\n' "$(relative_path "$OUTPUT_FILE")"
    printf -- '- App output: `%s`\n' "$(relative_path "$APP_LOG_FILE")"
  } >"$ARTIFACT_FILE"
}

terminate_app() {
  if [[ -z "${app_pid:-}" ]]; then
    return 0
  fi

  /usr/bin/swift - "$app_pid" <<'SWIFT' >/dev/null 2>&1 || true
import AppKit

guard CommandLine.arguments.count == 2,
      let pid = pid_t(CommandLine.arguments[1]),
      let app = NSRunningApplication(processIdentifier: pid) else {
    exit(1)
}
_ = app.terminate()
SWIFT
  for _ in {1..20}; do
    if ! kill -0 "$app_pid" >/dev/null 2>&1; then
      wait "$app_pid" >/dev/null 2>&1 || true
      app_pid=""
      return 0
    fi
    sleep 0.25
  done
  kill -9 "$app_pid" >/dev/null 2>&1 || true
  wait "$app_pid" >/dev/null 2>&1 || true
  app_pid=""
}

cleanup() {
  terminate_app
  if [[ "$KEEP_DATABASE" != "1" ]]; then
    rm -rf "$UI_ROOT"
  else
    printf "INFO: kept runtime development PR UI database at %s\n" "$database_path"
  fi
}
trap cleanup EXIT

on_error() {
  local status=$?
  write_artifact "failed" "$failure_reason"
  echo "BLOCKER: runtime development PR smoke failed. Evidence: $(relative_path "$ARTIFACT_FILE")" >&2
  exit "$status"
}
trap on_error ERR

wait_for_app_process() {
  if [[ -z "${app_pid:-}" ]]; then
    echo "BLOCKER: app PID is missing before waiting for $APP_NAME" >&2
    return 1
  fi
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while ! kill -0 "$app_pid" >/dev/null 2>&1; do
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: $APP_NAME process $app_pid did not appear within ${TIMEOUT_SECONDS}s" >&2
      return 1
    fi
    sleep 1
  done
}

wait_for_no_app_process() {
  if [[ -z "${app_pid:-}" ]]; then
    return 0
  fi
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while kill -0 "$app_pid" >/dev/null 2>&1; do
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      kill -9 "$app_pid" >/dev/null 2>&1 || true
      wait "$app_pid" >/dev/null 2>&1 || true
      app_pid=""
      return 0
    fi
    sleep 1
  done
  wait "$app_pid" >/dev/null 2>&1 || true
  app_pid=""
}

activate_app() {
  # Keep the directly launched process and its isolated database env active;
  # LaunchServices activation can start a second app without the fixture DB.
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
      echo "BLOCKER: $APP_NAME did not expose a visible AX window within ${TIMEOUT_SECONDS}s" >&2
      return 1
    fi
    sleep 1
  done
}

set_development_window_size() {
  local width="$1"
  local height="$2"
  /usr/bin/osascript - "$APP_NAME" "$width" "$height" <<'APPLESCRIPT' >/dev/null
on run argv
  set appName to item 1 of argv
  set targetWidth to (item 2 of argv) as integer
  set targetHeight to (item 3 of argv) as integer
  tell application "System Events"
    if not (exists process appName) then error "process missing"
    tell process appName
      if not (exists window 1) then error "window missing"
      set frontmost to true
      try
        perform action "AXRaise" of window 1
      end try
      set size of window 1 to {targetWidth, targetHeight}
    end tell
  end tell
end run
APPLESCRIPT
  sleep 1
}

launch_app_for_database_migration() {
  terminate_app
  HOME="$UI_HOME" \
    CFFIXED_USER_HOME="$UI_HOME" \
    SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1 \
    SOLOPM_RUNTIME_DEVELOPMENT_PR_FIXTURE_BOOKMARK=1 \
    SOLOPM_FORCE_PROJECT_BOARD_FALLBACK=1 \
    SOLOPM_DATABASE_PATH="$database_path" \
    "$APP_BINARY" >>"$APP_LOG_FILE" 2>&1 &
  app_pid=$!
  wait_for_app_process
}

launch_app_for_development_detail() {
  terminate_app
  HOME="$UI_HOME" \
    CFFIXED_USER_HOME="$UI_HOME" \
    SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1 \
    SOLOPM_RUNTIME_DEVELOPMENT_PR_FIXTURE_BOOKMARK=1 \
    SOLOPM_FORCE_PROJECT_BOARD_FALLBACK=1 \
    SOLOPM_LAUNCH_RECOVERY_MODE=1 \
    SOLOPM_DATABASE_PATH="$database_path" \
    SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION="project:$seed_project_id" \
    SOLOPM_PROJECT_BOARD_SELECTED_TASK_ID="$seed_task_id" \
    "$APP_BINARY" >>"$APP_LOG_FILE" 2>&1 &
  app_pid=$!
  wait_for_app_process
  activate_app
  wait_for_visible_windows
  set_development_window_size "$WINDOW_WIDTH" "$WINDOW_HEIGHT"
}

launch_app_for_assistant_queue() {
  terminate_app
  HOME="$UI_HOME" \
    CFFIXED_USER_HOME="$UI_HOME" \
    SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1 \
    SOLOPM_RUNTIME_DEVELOPMENT_PR_FIXTURE_BOOKMARK=1 \
    SOLOPM_FORCE_PROJECT_BOARD_FALLBACK=1 \
    SOLOPM_LAUNCH_RECOVERY_MODE=1 \
    SOLOPM_DATABASE_PATH="$database_path" \
    SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION="assistant-queue" \
    "$APP_BINARY" >>"$APP_LOG_FILE" 2>&1 &
  app_pid=$!
  wait_for_app_process
  activate_app
  wait_for_visible_windows
  set_development_window_size "$WINDOW_WIDTH" "$WINDOW_HEIGHT"
}

wait_for_database_table() {
  local table="$1"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while true; do
    if [[ -f "$database_path" ]] && "$SQLITE3" "$database_path" "SELECT name FROM sqlite_master WHERE type='table' AND name='$table';" | grep -Fx "$table" >/dev/null; then
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: SQLite table '$table' was not created in runtime database: $database_path" >&2
      return 1
    fi
    sleep 1
  done
}

waitForAXMarkerContaining() {
  local identifier_fragment="$1"
  local required_text="${2:-}"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local error_file
  local checker_pid
  local watchdog_pid
  local status

  if [[ -z "$required_text" ]]; then
    required_text="$identifier_fragment"
  fi

  while true; do
    error_file="$(mktemp "${TMPDIR:-/tmp}/solopm-development-pr-ax-marker-error.XXXXXX")"
    SOLOPM_UI_EVIDENCE_AX_MAX_NODES="$AX_MAX_NODES" \
      /usr/bin/swift "$ROOT_DIR/script/ui_evidence_ax_marker_check.swift" "$APP_NAME" "$identifier_fragment" "$required_text" \
      >/dev/null 2>"$error_file" &
    checker_pid=$!
    (
      sleep "$TIMEOUT_SECONDS"
      kill "$checker_pid" >/dev/null 2>&1 || true
    ) &
    watchdog_pid=$!
    set +e
    wait "$checker_pid"
    status=$?
    set -e
    kill "$watchdog_pid" >/dev/null 2>&1 || true
    wait "$watchdog_pid" >/dev/null 2>&1 || true
    if [[ "$status" -eq 0 ]]; then
      rm -f "$error_file"
      return 0
    fi
    cat "$error_file" >&2
    rm -f "$error_file"
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: AX element did not expose required signal: $identifier_fragment" >&2
      return 1
    fi
    activate_app
    wait_for_visible_windows >/dev/null 2>&1 || true
    sleep 1
  done
}

query_single_value() {
  local sql="$1"
  "$SQLITE3" -batch -noheader "$database_path" "$sql" | tail -n 1
}

wait_for_nonempty_value() {
  local label="$1"
  local sql="$2"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local actual=""
  while true; do
    actual="$(query_single_value "$sql" || true)"
    if [[ -n "$actual" ]]; then
      printf "%s" "$actual"
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: $label did not produce a SQLite value" >&2
      return 1
    fi
    sleep 1
  done
}

pressButtonContainingBounded() {
  local fragment="$1"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local error_file
  local checker_pid
  local watchdog_pid
  local status

  while true; do
    error_file="$(mktemp "${TMPDIR:-/tmp}/solopm-development-pr-ax-button-error.XXXXXX")"
    SOLOPM_UI_EVIDENCE_AX_MAX_NODES="$AX_MAX_NODES" \
      /usr/bin/swift "$ROOT_DIR/script/ui_evidence_ax_press_button.swift" "$APP_NAME" "$fragment" \
      >/dev/null 2>"$error_file" &
    checker_pid=$!
    (
      sleep "$TIMEOUT_SECONDS"
      kill "$checker_pid" >/dev/null 2>&1 || true
    ) &
    watchdog_pid=$!
    set +e
    wait "$checker_pid"
    status=$?
    set -e
    kill "$watchdog_pid" >/dev/null 2>&1 || true
    wait "$watchdog_pid" >/dev/null 2>&1 || true
    if [[ "$status" -eq 0 ]]; then
      rm -f "$error_file"
      return 0
    fi
    cat "$error_file" >&2
    rm -f "$error_file"
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: failed to press bounded AX button: $fragment" >&2
      return 1
    fi
    activate_app
    wait_for_visible_windows >/dev/null 2>&1 || true
    sleep 1
  done
}

waitForAXSubtreeMarkerContaining() {
  local identifier_fragment="$1"
  local required_text="$2"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local error_file
  local checker_pid
  local watchdog_pid
  local status

  while true; do
    error_file="$(mktemp "${TMPDIR:-/tmp}/solopm-development-pr-ax-marker-error.XXXXXX")"
    SOLOPM_UI_EVIDENCE_AX_REQUIRE_IDENTIFIER_SUBTREE=1 \
      SOLOPM_UI_EVIDENCE_AX_MAX_NODES="$AX_MAX_NODES" \
      /usr/bin/swift "$ROOT_DIR/script/ui_evidence_ax_marker_check.swift" "$APP_NAME" "$identifier_fragment" "$required_text" \
      >/dev/null 2>"$error_file" &
    checker_pid=$!
    (
      sleep "$TIMEOUT_SECONDS"
      kill "$checker_pid" >/dev/null 2>&1 || true
    ) &
    watchdog_pid=$!
    set +e
    wait "$checker_pid"
    status=$?
    set -e
    kill "$watchdog_pid" >/dev/null 2>&1 || true
    wait "$watchdog_pid" >/dev/null 2>&1 || true
    if [[ "$status" -eq 0 ]]; then
      rm -f "$error_file"
      return 0
    fi
    cat "$error_file" >&2
    rm -f "$error_file"
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: AX subtree marker did not expose required signal: $identifier_fragment => $required_text" >&2
      return 1
    fi
    activate_app
    wait_for_visible_windows >/dev/null 2>&1 || true
    sleep 1
  done
}

pressButtonUntilSQLiteValue() {
  local label="$1"
  local fragment="$2"
  local sql="$3"
  local expected="$4"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local actual=""

  while true; do
    pressButtonContainingBounded "$fragment"

    local postcondition_deadline=$((SECONDS + 3))
    while true; do
      actual="$(query_single_value "$sql" || true)"
      if [[ "$actual" == "$expected" ]]; then
        printf "OK: %s verified in SQLite (%s)\n" "$label" "$actual"
        return 0
      fi
      if [[ "$SECONDS" -ge "$deadline" ]]; then
        echo "BLOCKER: $label SQLite verification failed after AX press retry: expected '$expected', got '${actual:-<empty>}'" >&2
        echo "SQL: $sql" >&2
        return 1
      fi
      if [[ "$SECONDS" -ge "$postcondition_deadline" ]]; then
        break
      fi
      sleep 1
    done

    printf "INFO: SQLite postcondition for %s was not met after pressing '%s'; retrying AX press.\n" "$label" "$fragment" >&2
    sleep 1
  done
}

sql_escape() {
  printf "%s" "$1" | sed "s/'/''/g"
}

make_runtime_smoke_bookmark_base64() {
  local workspace="$1"
  printf 'solopm-runtime-development-pr-smoke:%s' "$workspace" | base64 | tr -d '\n'
}

fixture_git() {
  git \
    -c commit.gpgsign=false \
    -c tag.gpgsign=false \
    -c core.hooksPath=/dev/null \
    "$@"
}

seed_git_repository() {
  if ! fixture_git -C "$UI_WORKSPACE" init -b main >/dev/null 2>&1; then
    fixture_git -C "$UI_WORKSPACE" init >/dev/null
    fixture_git -C "$UI_WORKSPACE" checkout -B main >/dev/null
  fi
  fixture_git -C "$UI_WORKSPACE" config user.name "SoloPM Runtime Smoke" >/dev/null
  fixture_git -C "$UI_WORKSPACE" config user.email "runtime-smoke@solopm.local" >/dev/null
  fixture_git -C "$UI_WORKSPACE" add README.md
  fixture_git -C "$UI_WORKSPACE" commit -m "Seed runtime development UI repo" >/dev/null
}

seed_development_project() {
  rm -rf "$UI_WORKSPACE"
  mkdir -p "$UI_WORKSPACE"
  printf '# Runtime Development UI Repo\n' >"$UI_WORKSPACE/README.md"
  seed_git_repository

  local escaped_workspace
  local bookmark_data
  escaped_workspace="$(sql_escape "$UI_WORKSPACE")"
  bookmark_data="$(make_runtime_smoke_bookmark_base64 "$UI_WORKSPACE")"

  "$SQLITE3" "$database_path" <<SQL
DELETE FROM tasks WHERE source_command = 'runtime-development-pr-ui-smoke';
DELETE FROM projects WHERE source_command = 'runtime-development-pr-ui-smoke';

INSERT INTO projects (
  title,
  status,
  priority,
  deadline,
  workspace_path,
  workspace_bookmark,
  tags_json,
  source_command,
  created_at,
  updated_at
)
VALUES (
  'AX Runtime Development Project',
  'active',
  'high',
  NULL,
  '$escaped_workspace',
  '$bookmark_data',
  '["runtime","development"]',
  'runtime-development-pr-ui-smoke',
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
);

INSERT INTO tasks (
  project_id,
  title,
  status,
  detail,
  due_at,
  completed_at,
  priority,
  source_command,
  created_at,
  updated_at
)
VALUES (
  last_insert_rowid(),
  'Implement runtime branch flow',
  'planned',
  'Queue branch automation from the visible Project detail panel.',
  NULL,
  NULL,
  'high',
  'runtime-development-pr-ui-smoke',
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
);
SQL

  seed_project_id="$(wait_for_nonempty_value \
    "development UI project id" \
    "SELECT id FROM projects WHERE title='AX Runtime Development Project' AND source_command='runtime-development-pr-ui-smoke' ORDER BY id DESC LIMIT 1;")"
  seed_task_id="$(wait_for_nonempty_value \
    "development UI task id" \
    "SELECT id FROM tasks WHERE title='Implement runtime branch flow' AND source_command='runtime-development-pr-ui-smoke' ORDER BY id DESC LIMIT 1;")"
}

verify_visible_queue_handoff() {
  local branch_fragment="feature/solopm-$seed_project_id-$seed_task_id"
  local queue_sql
  queue_sql="
SELECT CASE WHEN count(*) = 1 THEN 1 ELSE 0 END
FROM assistant_queue_items
WHERE id LIKE 'action-plan:development-pr-prepare:$seed_project_id:$seed_task_id:%'
  AND payload_kind='action_plan'
  AND state='waitingReview'
  AND risk_level='write'
  AND approval_json IS NULL
  AND payload_json LIKE '%development.pr_workflow.prepare%'
  AND payload_json LIKE '%\"requiresApproval\":true%'
  AND required_capabilities_json LIKE '%providerExecutionApproval%'
  AND (
    required_capabilities_json LIKE '%development.pr_workflow.prepare%'
    OR required_capabilities_json LIKE '%developmentPreparePullRequestWorkflow%'
  );
"

  waitForAXMarkerContaining "project-development-automation-status"
  waitForAXMarkerContaining "project-development-automation-branch-preview" "$branch_fragment"
  pressButtonUntilSQLiteValue \
    "visible Project automation panel queued branch automation into Assistant Queue" \
    "project-development-automation-queue" \
    "$queue_sql" \
    "1"
  queued_item_id="$(wait_for_nonempty_value \
    "queued development branch prepare Assistant Queue item id" \
    "SELECT id FROM assistant_queue_items WHERE id LIKE 'action-plan:development-pr-prepare:$seed_project_id:$seed_task_id:%' ORDER BY updated_at DESC LIMIT 1;")"
  waitForAXMarkerContaining "project-development-automation-queue-handoff"
}

wait_for_receipt_json() {
  local label="$1"
  local item_id="$2"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local receipt_file=""

  while true; do
    if [[ -d "$receipt_directory" ]]; then
      receipt_file="$(/usr/bin/swift - "$receipt_directory" "$item_id" <<'SWIFT' 2>/dev/null || true
import Foundation

struct Receipt: Decodable {
    let assistantQueueItemID: String?
    let primaryToolName: String?
    let status: String
}

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let itemID = CommandLine.arguments[2]
let decoder = JSONDecoder()
let files = (try? FileManager.default.contentsOfDirectory(
    at: directory,
    includingPropertiesForKeys: [.contentModificationDateKey],
    options: [.skipsHiddenFiles]
)) ?? []

for file in files where file.pathExtension == "json" {
    guard let data = try? Data(contentsOf: file),
          let receipt = try? decoder.decode(Receipt.self, from: data),
          receipt.assistantQueueItemID == itemID,
          receipt.primaryToolName == "development.pr_workflow.prepare",
          receipt.status == "succeeded" else {
        continue
    }
    print(file.path)
    exit(0)
}
SWIFT
)"
      if [[ -n "$receipt_file" ]]; then
        printf "OK: %s receipt verified at %s\n" "$label" "$(relative_path "$receipt_file")"
        return 0
      fi
    fi

    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: $label receipt was not saved in $receipt_directory" >&2
      return 1
    fi
    sleep 1
  done
}

verify_visible_assistant_queue_prepare_execution() {
  if [[ -z "$queued_item_id" ]]; then
    echo "BLOCKER: queued Assistant Queue item id is missing before approve/run" >&2
    return 1
  fi

  local escaped_item_id
  local approval_sql
  local done_sql
  local branch_fragment
  local current_branch
  escaped_item_id="$(sql_escape "$queued_item_id")"
  branch_fragment="feature/solopm-$seed_project_id-$seed_task_id"
  approval_sql="
SELECT CASE WHEN state='approved' AND approval_json IS NOT NULL THEN 1 ELSE 0 END
FROM assistant_queue_items
WHERE id='$escaped_item_id';
"
  done_sql="
SELECT CASE WHEN state='done' AND approval_json IS NOT NULL THEN 1 ELSE 0 END
FROM assistant_queue_items
WHERE id='$escaped_item_id';
"

  launch_app_for_assistant_queue
  wait_for_database_table "assistant_queue_items"
  waitForAXMarkerContaining "assistant-queue-workflow"
  waitForAXMarkerContaining "assistant-queue-row-$queued_item_id"
  pressButtonUntilSQLiteValue \
    "visible Assistant Queue approved local branch preparation" \
    "assistant-queue-approve-$queued_item_id" \
    "$approval_sql" \
    "1"
  pressButtonUntilSQLiteValue \
    "visible Assistant Queue approved and executed local branch preparation" \
    "assistant-queue-run-$queued_item_id" \
    "$done_sql" \
    "1"
  wait_for_receipt_json "visible Assistant Queue branch preparation" "$queued_item_id"

  current_branch="$(fixture_git -C "$UI_WORKSPACE" branch --show-current)"
  case "$current_branch" in
    *"$branch_fragment"*)
      printf "OK: local development branch prepared in fixture repo (%s)\n" "$current_branch"
      ;;
    *)
      echo "BLOCKER: expected local branch containing '$branch_fragment', got '${current_branch:-<empty>}'" >&2
      return 1
      ;;
  esac
}

printf "== Runtime development PR smoke ==\n"
ensure_no_existing_app_process

failure_reason="approved project directory fixture XCTest failed"
if ! SOLOPM_RUNTIME_DEVELOPMENT_PR_WORKSPACE_ROOT="$WORKSPACE_ROOT" \
  SOLOPM_RUNTIME_DEVELOPMENT_PR_KEEP_WORKSPACE="$KEEP_WORKSPACE" \
  swift test --filter DevelopmentAutomationRuntimeSmokeTests/testApprovedProjectDirectoryCanEditVerifyCommitAndPreparePullRequestBranch --quiet >"$OUTPUT_FILE" 2>&1; then
  cat "$OUTPUT_FILE" >&2
  write_artifact "failed" "development PR fixture flow failed"
  echo "BLOCKER: runtime development PR smoke failed. Evidence: $(relative_path "$ARTIFACT_FILE")" >&2
  exit 1
fi
cat "$OUTPUT_FILE"

failure_reason="SoloPM app bundle build failed"
./script/build_and_run.sh --build-only

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "BLOCKER: app bundle not found after build: $APP_BUNDLE" >&2
  exit 2
fi

if [[ ! -x "$APP_BINARY" ]]; then
  echo "BLOCKER: app binary not found or not executable after build: $APP_BINARY" >&2
  exit 2
fi

: >"$APP_LOG_FILE"
rm -f "$database_path"
failure_reason="runtime database migration failed"
launch_app_for_database_migration
wait_for_database_table "projects"
wait_for_database_table "tasks"
wait_for_database_table "assistant_queue_items"
terminate_app
wait_for_no_app_process

failure_reason="runtime development UI fixture seed failed"
seed_development_project

failure_reason="visible Project detail Assistant Queue handoff failed"
launch_app_for_development_detail
wait_for_database_table "assistant_queue_items"
verify_visible_queue_handoff

failure_reason="visible Assistant Queue branch preparation execution failed"
verify_visible_assistant_queue_prepare_execution

write_artifact "passed" "approved project directory fixture flow reached local commit, fake push, fake PR creation, fake review gate, fake merge, visible Project automation panel queued branch automation into Assistant Queue, and visible Assistant Queue approved and executed local branch preparation"
printf 'OK: runtime development PR smoke passed. Evidence: %s\n' "$(relative_path "$ARTIFACT_FILE")"
