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
ARTIFACT_DIR="${SUISUI_RUNTIME_DEVELOPMENT_PR_ARTIFACT_DIR:-$ROOT_DIR/.tmp/runtime-development-pr-smoke}"
KEEP_WORKSPACE="${SUISUI_RUNTIME_DEVELOPMENT_PR_KEEP_WORKSPACE:-0}"
KEEP_DATABASE="${SUISUI_RUNTIME_DEVELOPMENT_PR_KEEP_DATABASE:-0}"
TIMEOUT_SECONDS="${SUISUI_RUNTIME_DEVELOPMENT_PR_TIMEOUT_SECONDS:-30}"
SQLITE3="${SQLITE3:-sqlite3}"
AX_MAX_NODES="${SUISUI_RUNTIME_DEVELOPMENT_PR_AX_MAX_NODES:-9000}"
WINDOW_WIDTH="${SUISUI_RUNTIME_DEVELOPMENT_PR_WINDOW_WIDTH:-1440}"
WINDOW_HEIGHT="${SUISUI_RUNTIME_DEVELOPMENT_PR_WINDOW_HEIGHT:-920}"
OUTPUT_FILE="$ARTIFACT_DIR/swift-test-output.txt"
APP_LOG_FILE="$ARTIFACT_DIR/visible-app-output.txt"
ARTIFACT_FILE="$ARTIFACT_DIR/evidence.md"
WORKSPACE_ROOT="$ARTIFACT_DIR/workspaces"
UI_ROOT="$ARTIFACT_DIR/visible-ui"
UI_HOME="$UI_ROOT/home"
UI_WORKSPACE="$UI_ROOT/approved-workspace"
database_path="$UI_ROOT/Suisui-runtime-development-pr-ui.sqlite"
receipt_directory="$UI_HOME/Library/Application Support/Suisui/ExecutionReceipts"
runtime_fake_git_bin="$UI_ROOT/fake-publish-bin"
runtime_fake_git_push_log="$UI_ROOT/fake-push.log"
runtime_fake_github_pr_log="$UI_ROOT/fake-pull-request-create.log"
runtime_fake_github_review_log="$UI_ROOT/fake-pull-request-review.log"
runtime_fake_github_merge_log="$UI_ROOT/fake-pull-request-merge.log"
runtime_blocked_external_write_log="$UI_ROOT/blocked-external-write.log"
runtime_expected_branch_file="$UI_ROOT/fake-expected-branch.txt"
runtime_expected_head_file="$UI_ROOT/fake-expected-head.txt"
runtime_pull_request_base_branch="main"
runtime_fake_pull_request_url="https://github.com/albert-einshutoin/suisui/pull/16001"
runtime_pull_request_title="Suisui: Implement runtime branch flow"
runtime_pull_request_body=$'## Summary\n- Prepare Implement runtime branch flow for AX Runtime Development Project.\n'
REAL_GIT="$(command -v git || true)"
app_pid=""
seed_project_id=""
seed_task_id=""
queued_item_id=""
repository_edit_item_id=""
verification_item_id=""
commit_item_id=""
push_item_id=""
pull_request_item_id=""
pull_request_review_item_id=""
pull_request_merge_item_id=""
prepared_branch_name=""
visible_commit_head_before=""
visible_commit_head_after=""
visible_edit_relative_path="runtime-development-pr-visible-edit.md"
visible_edit_contents="Visible repository edit smoke proof"
visible_commit_message="Update runtime development visible edit"
failure_reason="development PR smoke failed"

mkdir -p "$ARTIFACT_DIR" "$WORKSPACE_ROOT" "$UI_ROOT" "$UI_HOME" "$runtime_fake_git_bin"
cd "$ROOT_DIR"

if [[ ! "$TIMEOUT_SECONDS" =~ ^[0-9]+$ || "$TIMEOUT_SECONDS" -lt 1 ]]; then
  echo "SUISUI_RUNTIME_DEVELOPMENT_PR_TIMEOUT_SECONDS must be a positive integer" >&2
  exit 2
fi
if [[ ! "$AX_MAX_NODES" =~ ^[0-9]+$ || "$AX_MAX_NODES" -lt 1 ]]; then
  echo "SUISUI_RUNTIME_DEVELOPMENT_PR_AX_MAX_NODES must be a positive integer" >&2
  exit 2
fi
if ! command -v "$SQLITE3" >/dev/null 2>&1; then
  echo "BLOCKER: sqlite3 is required for runtime development PR smoke" >&2
  exit 2
fi
if [[ -z "$REAL_GIT" ]]; then
  echo "BLOCKER: git is required for runtime development PR smoke" >&2
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
    printf -- '- Flow: visible Project inspector -> NSOpenPanel folder picker -> stored project workspace bookmark -> `development.pr_workflow.prepare` -> `development.repository.list_files` -> `development.repository.create_file` -> `development.repository.update_file` -> `development.verification.run` -> `development.pr_workflow.commit` -> `development.pr_workflow.push` -> `development.pr_workflow.create_pull_request` -> `development.pr_workflow.review_gate` -> `development.pr_workflow.merge` with fake Git and GitHub runners.\n'
    printf -- '- Visible UI: Project automation panel -> `project-development-automation-queue` -> `project-development-automation-queue-handoff` -> Assistant Queue approve/run -> receipt\n'
    printf -- '- Project directory picker workspace: `%s`\n' "$(relative_path "$UI_WORKSPACE")"
    printf -- '- Queued project: `%s`\n' "${seed_project_id:-not-seeded}"
    printf -- '- Queued task: `%s`\n' "${seed_task_id:-not-seeded}"
    printf -- '- Assistant Queue item: `%s`\n' "${queued_item_id:-not-queued}"
    printf -- '- Repository edit Assistant Queue item: `%s`\n' "${repository_edit_item_id:-not-queued}"
    printf -- '- Repository edit path: `%s`\n' "$visible_edit_relative_path"
    printf -- '- Verification Assistant Queue item: `%s`\n' "${verification_item_id:-not-queued}"
    printf -- '- Commit Assistant Queue item: `%s`\n' "${commit_item_id:-not-queued}"
    printf -- '- Push Assistant Queue item: `%s`\n' "${push_item_id:-not-queued}"
    printf -- '- Pull Request Assistant Queue item: `%s`\n' "${pull_request_item_id:-not-queued}"
    printf -- '- Pull Request Review Gate Assistant Queue item: `%s`\n' "${pull_request_review_item_id:-not-queued}"
    printf -- '- Pull Request Merge Assistant Queue item: `%s`\n' "${pull_request_merge_item_id:-not-queued}"
    printf -- '- Pull Request URL: `%s`\n' "${runtime_fake_pull_request_url:-not-created}"
    printf -- '- Commit head before: `%s`\n' "${visible_commit_head_before:-not-run}"
    printf -- '- Commit head after: `%s`\n' "${visible_commit_head_after:-not-run}"
    printf -- '- Approval boundary: `requiresPushApproval=true`, `requiresPullRequestApproval=true`\n'
    printf -- '- External writes: No live GitHub PR creation or merge is created by this smoke; branch push uses a local fake branch push wrapper, and PR creation/review/merge use smoke-only fake GitHub runners.\n'
    printf -- '- Fake push log: `%s`\n' "$(relative_path "$runtime_fake_git_push_log")"
    printf -- '- Fake pull request create log: `%s`\n' "$(relative_path "$runtime_fake_github_pr_log")"
    printf -- '- Fake pull request review log: `%s`\n' "$(relative_path "$runtime_fake_github_review_log")"
    printf -- '- Fake pull request merge log: `%s`\n' "$(relative_path "$runtime_fake_github_merge_log")"
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
  PATH="$runtime_fake_git_bin:$PATH" \
    HOME="$UI_HOME" \
    CFFIXED_USER_HOME="$UI_HOME" \
    SUISUI_DISABLE_KEYCHAIN_SECRET_STORE=1 \
    SUISUI_RUNTIME_DEVELOPMENT_PR_SMOKE_BOOKMARK=1 \
    SUISUI_RUNTIME_DEVELOPMENT_PR_EXPECTED_BRANCH="$prepared_branch_name" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_EXPECTED_HEAD="$visible_commit_head_after" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_EXPECTED_BASE="$runtime_pull_request_base_branch" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_CREATE_URL="$runtime_fake_pull_request_url" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_CREATE_LOG="$runtime_fake_github_pr_log" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_REVIEW_LOG="$runtime_fake_github_review_log" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_MERGE_LOG="$runtime_fake_github_merge_log" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_GIT_EXECUTABLE="$runtime_fake_git_bin/git" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_PUSH_LOG="$runtime_fake_git_push_log" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_FAKE_PUSH_LOG="$runtime_fake_git_push_log" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_BLOCKED_EXTERNAL_WRITE_LOG="$runtime_blocked_external_write_log" \
    REAL_GIT="$REAL_GIT" \
    SUISUI_FORCE_PROJECT_BOARD_FALLBACK=1 \
    SUISUI_DATABASE_PATH="$database_path" \
    "$APP_BINARY" >>"$APP_LOG_FILE" 2>&1 &
  app_pid=$!
  wait_for_app_process
}

launch_app_for_development_detail() {
  terminate_app
  PATH="$runtime_fake_git_bin:$PATH" \
    HOME="$UI_HOME" \
    CFFIXED_USER_HOME="$UI_HOME" \
    SUISUI_DISABLE_KEYCHAIN_SECRET_STORE=1 \
    SUISUI_RUNTIME_DEVELOPMENT_PR_SMOKE_BOOKMARK=1 \
    SUISUI_RUNTIME_DEVELOPMENT_PR_EXPECTED_BRANCH="$prepared_branch_name" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_EXPECTED_HEAD="$visible_commit_head_after" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_EXPECTED_BASE="$runtime_pull_request_base_branch" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_CREATE_URL="$runtime_fake_pull_request_url" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_CREATE_LOG="$runtime_fake_github_pr_log" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_REVIEW_LOG="$runtime_fake_github_review_log" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_MERGE_LOG="$runtime_fake_github_merge_log" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_GIT_EXECUTABLE="$runtime_fake_git_bin/git" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_PUSH_LOG="$runtime_fake_git_push_log" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_FAKE_PUSH_LOG="$runtime_fake_git_push_log" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_BLOCKED_EXTERNAL_WRITE_LOG="$runtime_blocked_external_write_log" \
    REAL_GIT="$REAL_GIT" \
    SUISUI_FORCE_PROJECT_BOARD_FALLBACK=1 \
    SUISUI_DATABASE_PATH="$database_path" \
    SUISUI_PROJECT_BOARD_SELECTED_DESTINATION="project:$seed_project_id" \
    SUISUI_PROJECT_BOARD_SELECTED_TASK_ID="$seed_task_id" \
    "$APP_BINARY" >>"$APP_LOG_FILE" 2>&1 &
  app_pid=$!
  wait_for_app_process
  activate_app
  wait_for_visible_windows
  set_development_window_size "$WINDOW_WIDTH" "$WINDOW_HEIGHT"
}

launch_app_for_project_directory_picker() {
  terminate_app
  PATH="$runtime_fake_git_bin:$PATH" \
    HOME="$UI_HOME" \
    CFFIXED_USER_HOME="$UI_HOME" \
    SUISUI_DISABLE_KEYCHAIN_SECRET_STORE=1 \
    SUISUI_RUNTIME_DEVELOPMENT_PR_SMOKE_BOOKMARK=1 \
    SUISUI_RUNTIME_DEVELOPMENT_PR_EXPECTED_BRANCH="$prepared_branch_name" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_EXPECTED_HEAD="$visible_commit_head_after" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_EXPECTED_BASE="$runtime_pull_request_base_branch" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_CREATE_URL="$runtime_fake_pull_request_url" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_CREATE_LOG="$runtime_fake_github_pr_log" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_REVIEW_LOG="$runtime_fake_github_review_log" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_MERGE_LOG="$runtime_fake_github_merge_log" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_GIT_EXECUTABLE="$runtime_fake_git_bin/git" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_PUSH_LOG="$runtime_fake_git_push_log" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_FAKE_PUSH_LOG="$runtime_fake_git_push_log" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_BLOCKED_EXTERNAL_WRITE_LOG="$runtime_blocked_external_write_log" \
    REAL_GIT="$REAL_GIT" \
    SUISUI_FORCE_PROJECT_BOARD_FALLBACK=1 \
    SUISUI_DATABASE_PATH="$database_path" \
    SUISUI_PROJECT_BOARD_SELECTED_DESTINATION="project:$seed_project_id" \
    "$APP_BINARY" >>"$APP_LOG_FILE" 2>&1 &
  app_pid=$!
  wait_for_app_process
  activate_app
  wait_for_visible_windows
  set_development_window_size "$WINDOW_WIDTH" "$WINDOW_HEIGHT"
}

launch_app_for_assistant_queue() {
  terminate_app
  PATH="$runtime_fake_git_bin:$PATH" \
    HOME="$UI_HOME" \
    CFFIXED_USER_HOME="$UI_HOME" \
    SUISUI_DISABLE_KEYCHAIN_SECRET_STORE=1 \
    SUISUI_RUNTIME_DEVELOPMENT_PR_SMOKE_BOOKMARK=1 \
    SUISUI_RUNTIME_DEVELOPMENT_PR_EXPECTED_BRANCH="$prepared_branch_name" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_EXPECTED_HEAD="$visible_commit_head_after" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_EXPECTED_BASE="$runtime_pull_request_base_branch" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_CREATE_URL="$runtime_fake_pull_request_url" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_CREATE_LOG="$runtime_fake_github_pr_log" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_REVIEW_LOG="$runtime_fake_github_review_log" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_MERGE_LOG="$runtime_fake_github_merge_log" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_GIT_EXECUTABLE="$runtime_fake_git_bin/git" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_PUSH_LOG="$runtime_fake_git_push_log" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_FAKE_PUSH_LOG="$runtime_fake_git_push_log" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_BLOCKED_EXTERNAL_WRITE_LOG="$runtime_blocked_external_write_log" \
    REAL_GIT="$REAL_GIT" \
    SUISUI_FORCE_PROJECT_BOARD_FALLBACK=1 \
    SUISUI_DATABASE_PATH="$database_path" \
    SUISUI_PROJECT_BOARD_SELECTED_DESTINATION="assistant-queue" \
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
    error_file="$(mktemp "${TMPDIR:-/tmp}/suisui-development-pr-ax-marker-error.XXXXXX")"
    SUISUI_UI_EVIDENCE_AX_MAX_NODES="$AX_MAX_NODES" \
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
    error_file="$(mktemp "${TMPDIR:-/tmp}/suisui-development-pr-ax-button-error.XXXXXX")"
    SUISUI_UI_EVIDENCE_AX_MAX_NODES="$AX_MAX_NODES" \
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

setTextFieldContaining() {
  local fragment="$1"
  local replacement="$2"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))

  while true; do
    if /usr/bin/osascript - "$APP_NAME" "$fragment" "$replacement" <<'APPLESCRIPT'
on run argv
  set appName to item 1 of argv
  set fragment to item 2 of argv
  set replacement to item 3 of argv
  tell application "System Events"
    if not (exists process appName) then error appName & " process is not visible to System Events"
    tell process appName
      set windowCount to count of windows
      if windowCount < 1 then error appName & " has no visible windows"
      try
        set frontmost to true
      end try
      repeat with windowIndex from 1 to windowCount
        set currentWindow to window windowIndex
        try
          perform action "AXRaise" of currentWindow
        end try
        set axItems to entire contents of currentWindow
        repeat with axItem in axItems
          set itemRole to ""
          try
            set itemRole to role of axItem as text
          end try
          if itemRole is "AXTextField" or itemRole is "AXTextArea" then
            set fieldIdentifier to ""
            set fieldName to ""
            set fieldTitle to ""
            set fieldDescription to ""
            set fieldHelp to ""
            set fieldValue to ""
            try
              set fieldIdentifier to value of attribute "AXIdentifier" of axItem as text
            end try
            try
              set fieldName to name of axItem as text
            end try
            try
              set fieldTitle to value of attribute "AXTitle" of axItem as text
            end try
            try
              set fieldDescription to description of axItem as text
            end try
            try
              set fieldHelp to value of attribute "AXHelp" of axItem as text
            end try
            try
              set fieldValue to value of axItem as text
            end try
            set signalText to fieldIdentifier & " " & fieldName & " " & fieldTitle & " " & fieldDescription & " " & fieldHelp & " " & fieldValue
            if signalText contains fragment then
              set previousClipboard to ""
              try
                set previousClipboard to the clipboard as text
              end try
              perform action "AXPress" of axItem
              set focused of axItem to true
              delay 0.2
              set the clipboard to replacement
              keystroke "a" using command down
              delay 0.1
              key code 51
              delay 0.1
              keystroke "v" using command down
              delay 0.3
              -- AXTextArea treats Tab as file content, so only text fields use
              -- Tab to leave focus after pasting reviewed repository contents.
              if itemRole is not "AXTextArea" then
                key code 48
                delay 0.2
              end if
              try
                set the clipboard to previousClipboard
              end try
              delay 0.2
              return "set text field " & fragment
            end if
          end if
        end repeat
      end repeat
    end tell
  end tell
  error "text field signal not found: " & fragment
end run
APPLESCRIPT
    then
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: failed to set text field in AX tree: $fragment" >&2
      return 1
    fi
    activate_app
    wait_for_visible_windows >/dev/null 2>&1 || true
    sleep 1
  done
}

scrollProjectDetailDown() {
  /usr/bin/osascript - "$APP_NAME" <<'APPLESCRIPT' >/dev/null 2>&1 || true
on run argv
  set appName to item 1 of argv
  tell application "System Events"
    if not (exists process appName) then return
    tell process appName
      if not (exists window 1) then return
      try
        set frontmost to true
      end try
      set axItems to entire contents of window 1
      repeat with axItem in axItems
        set itemRole to ""
        try
          set itemRole to role of axItem as text
        end try
        if itemRole is "AXScrollArea" then
          repeat 6 times
            try
              perform action "AXScrollDown" of axItem
            end try
          end repeat
          return
        end if
      end repeat
      repeat 8 times
        key code 121
        delay 0.05
      end repeat
    end tell
  end tell
end run
APPLESCRIPT
  sleep 1
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
    error_file="$(mktemp "${TMPDIR:-/tmp}/suisui-development-pr-ax-marker-error.XXXXXX")"
    SUISUI_UI_EVIDENCE_AX_REQUIRE_IDENTIFIER_SUBTREE=1 \
      SUISUI_UI_EVIDENCE_AX_MAX_NODES="$AX_MAX_NODES" \
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

waitForSQLiteValue() {
  local label="$1"
  local sql="$2"
  local expected="$3"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local actual=""

  while true; do
    actual="$(query_single_value "$sql" || true)"
    if [[ "$actual" == "$expected" ]]; then
      printf "OK: %s verified in SQLite (%s)\n" "$label" "$actual"
      return 0
    fi

    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: $label SQLite verification failed: expected '$expected', got '${actual:-<empty>}'" >&2
      echo "SQL: $sql" >&2
      return 1
    fi
    sleep 1
  done
}

sql_escape() {
  printf "%s" "$1" | sed "s/'/''/g"
}

make_runtime_smoke_bookmark_base64() {
  local workspace="$1"
  printf 'suisui-runtime-development-pr-smoke:%s' "$workspace" | base64 | tr -d '\n'
}

fixture_git() {
  git \
    -c commit.gpgsign=false \
    -c tag.gpgsign=false \
    -c core.hooksPath=/dev/null \
    "$@"
}

install_runtime_fake_publish_tools() {
  rm -f "$runtime_fake_git_push_log" "$runtime_fake_github_pr_log" "$runtime_fake_github_review_log" "$runtime_fake_github_merge_log" "$runtime_blocked_external_write_log"
  : >"$runtime_expected_branch_file"
  : >"$runtime_expected_head_file"
  local real_git_literal
  local fake_push_log_literal
  local blocked_log_literal
  local expected_branch_file_literal
  local expected_head_file_literal
  real_git_literal="$(printf '%q' "$REAL_GIT")"
  fake_push_log_literal="$(printf '%q' "$runtime_fake_git_push_log")"
  blocked_log_literal="$(printf '%q' "$runtime_blocked_external_write_log")"
  expected_branch_file_literal="$(printf '%q' "$runtime_expected_branch_file")"
  expected_head_file_literal="$(printf '%q' "$runtime_expected_head_file")"
  cat >"$runtime_fake_git_bin/git" <<BASH
#!/usr/bin/env bash
set -euo pipefail

default_real_git=$real_git_literal
default_fake_push_log=$fake_push_log_literal
default_blocked_external_write_log=$blocked_log_literal
expected_branch_file=$expected_branch_file_literal
expected_head_file=$expected_head_file_literal
BASH

  cat >>"$runtime_fake_git_bin/git" <<'BASH'
REAL_GIT="${REAL_GIT:-$default_real_git}"
SUISUI_RUNTIME_DEVELOPMENT_PR_FAKE_PUSH_LOG="${SUISUI_RUNTIME_DEVELOPMENT_PR_FAKE_PUSH_LOG:-$default_fake_push_log}"
SUISUI_RUNTIME_DEVELOPMENT_PR_BLOCKED_EXTERNAL_WRITE_LOG="${SUISUI_RUNTIME_DEVELOPMENT_PR_BLOCKED_EXTERNAL_WRITE_LOG:-$default_blocked_external_write_log}"

args=("$@")
git_global_args=()
index=0
while [[ "$index" -lt "${#args[@]}" ]]; do
  token="${args[$index]}"
  case "$token" in
    -C|-c|--git-dir|--work-tree|--namespace|--config-env)
      next_index=$((index + 1))
      git_global_args+=("$token" "${args[$next_index]:-}")
      index=$((index + 2))
      ;;
    --git-dir=*|--work-tree=*|--namespace=*|--config-env=*|-c=*)
      git_global_args+=("$token")
      index=$((index + 1))
      ;;
    --)
      index=$((index + 1))
      break
      ;;
    -*)
      git_global_args+=("$token")
      index=$((index + 1))
      ;;
    *)
      break
      ;;
  esac
done

command_name="${args[$index]:-}"
command_args=("${args[@]:$((index + 1))}")

if [[ "$command_name" == "push" ]]; then
  expected_branch="${SUISUI_RUNTIME_DEVELOPMENT_PR_EXPECTED_BRANCH:-}"
  expected_head="${SUISUI_RUNTIME_DEVELOPMENT_PR_EXPECTED_HEAD:-}"
  if [[ -z "$expected_branch" && -r "$expected_branch_file" ]]; then
    expected_branch="$(<"$expected_branch_file")"
  fi
  if [[ -z "$expected_head" && -r "$expected_head_file" ]]; then
    expected_head="$(<"$expected_head_file")"
  fi
  expected_refspec="${expected_head}:refs/heads/${expected_branch}"
  if [[ "${#command_args[@]}" -eq 3 && "${command_args[0]}" == "-u" && "${command_args[1]}" == "origin" && -n "$expected_branch" && -n "$expected_head" && "${command_args[2]}" == "$expected_refspec" ]]; then
    head_oid="$("$REAL_GIT" "${git_global_args[@]}" rev-parse HEAD)"
    {
      printf 'cwd=%s\n' "$PWD"
      printf 'args=%s\n' "$*"
      printf 'branch=%s\n' "$expected_branch"
      printf 'head=%s\n' "$head_oid"
    } >>"$SUISUI_RUNTIME_DEVELOPMENT_PR_FAKE_PUSH_LOG"
    printf 'fake branch push %s\n' "$expected_refspec"
    exit 0
  fi
  printf 'blocked publish command: %s\n' "$*" >>"$SUISUI_RUNTIME_DEVELOPMENT_PR_BLOCKED_EXTERNAL_WRITE_LOG"
  exit 42
fi

if [[ "$command_name" == "ls-remote" ]]; then
  expected_branch="${SUISUI_RUNTIME_DEVELOPMENT_PR_EXPECTED_BRANCH:-}"
  expected_head="${SUISUI_RUNTIME_DEVELOPMENT_PR_EXPECTED_HEAD:-}"
  if [[ -z "$expected_branch" && -r "$expected_branch_file" ]]; then
    expected_branch="$(<"$expected_branch_file")"
  fi
  if [[ -z "$expected_head" && -r "$expected_head_file" ]]; then
    expected_head="$(<"$expected_head_file")"
  fi
  expected_ref="refs/heads/${expected_branch}"
  if [[ "${#command_args[@]}" -eq 2 && -n "$expected_branch" && -n "$expected_head" && "${command_args[1]}" == "$expected_ref" ]]; then
    printf '%s\trefs/heads/%s\n' "$expected_head" "$expected_branch"
    exit 0
  fi
  printf 'blocked ls-remote command: %s\n' "$*" >>"$SUISUI_RUNTIME_DEVELOPMENT_PR_BLOCKED_EXTERNAL_WRITE_LOG"
  exit 42
fi

exec "$REAL_GIT" "$@"
BASH
  chmod +x "$runtime_fake_git_bin/git"

  for blocked_tool in gh curl ssh; do
    cat >"$runtime_fake_git_bin/$blocked_tool" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

: "${SUISUI_RUNTIME_DEVELOPMENT_PR_BLOCKED_EXTERNAL_WRITE_LOG:?blocked external write log is required}"
printf 'blocked external tool: %s %s\n' "$(basename "$0")" "$*" >>"$SUISUI_RUNTIME_DEVELOPMENT_PR_BLOCKED_EXTERNAL_WRITE_LOG"
exit 43
BASH
    chmod +x "$runtime_fake_git_bin/$blocked_tool"
  done
}

seed_git_repository() {
  if ! fixture_git -C "$UI_WORKSPACE" init -b main >/dev/null 2>&1; then
    fixture_git -C "$UI_WORKSPACE" init >/dev/null
    fixture_git -C "$UI_WORKSPACE" checkout -B main >/dev/null
  fi
  fixture_git -C "$UI_WORKSPACE" config user.name "Suisui Runtime Smoke" >/dev/null
  fixture_git -C "$UI_WORKSPACE" config user.email "runtime-smoke@suisui.local" >/dev/null
  fixture_git -C "$UI_WORKSPACE" add README.md
  fixture_git -C "$UI_WORKSPACE" commit -m "Seed runtime development UI repo" >/dev/null
  fixture_git -C "$UI_WORKSPACE" remote add origin "https://github.com/albert-einshutoin/suisui.git" >/dev/null
}

seed_development_project() {
  rm -rf "$UI_WORKSPACE"
  mkdir -p "$UI_WORKSPACE"
  printf '# Runtime Development UI Repo\n' >"$UI_WORKSPACE/README.md"
  seed_git_repository

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
  NULL,
  NULL,
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
  waitForSQLiteValue \
    "development UI project starts without a selected workspace" \
    "SELECT CASE WHEN workspace_path IS NULL AND workspace_bookmark IS NULL THEN 1 ELSE 0 END FROM projects WHERE id=$seed_project_id;" \
    "1"
}

chooseRuntimeProjectWorkspaceViaOpenPanel() {
  local workspace="$1"

  pressButtonContainingBounded "project-workspace-choose"

  /usr/bin/osascript - "$APP_NAME" "$workspace" <<'APPLESCRIPT'
on run argv
  set appName to item 1 of argv
  set folderPath to item 2 of argv
  set deadlineDate to (current date) + 20
  tell application "System Events"
    repeat
      if exists process appName then exit repeat
      if (current date) > deadlineDate then error appName & " process is not visible to System Events"
      delay 0.2
    end repeat
    tell process appName
      set frontmost to true
      repeat
        if (count of windows) > 0 then exit repeat
        if (current date) > deadlineDate then error appName & " has no window for the folder picker"
        delay 0.2
      end repeat

      set previousClipboard to ""
      try
        set previousClipboard to the clipboard as text
      end try
      keystroke "g" using {command down, shift down}
      delay 0.4
      set the clipboard to folderPath
      keystroke "v" using command down
      delay 0.2
      key code 36
      delay 0.8

      repeat
        set didChoose to false
        repeat with currentWindow in windows
          try
            set axItems to entire contents of currentWindow
            repeat with axItem in axItems
              set itemRole to ""
              set itemName to ""
              set itemTitle to ""
              set itemDescription to ""
              try
                set itemRole to role of axItem as text
              end try
              try
                set itemName to name of axItem as text
              end try
              try
                set itemTitle to value of attribute "AXTitle" of axItem as text
              end try
              try
                set itemDescription to description of axItem as text
              end try
              set signalText to itemName & " " & itemTitle & " " & itemDescription
              if itemRole is "AXButton" and (signalText contains "Choose" or signalText contains "選択") then
                perform action "AXPress" of axItem
                set didChoose to true
                exit repeat
              end if
            end repeat
          end try
          if didChoose then exit repeat
        end repeat
        if didChoose then exit repeat
        if (current date) > deadlineDate then error "Choose button not found in folder picker"
        delay 0.2
      end repeat
      try
        set the clipboard to previousClipboard
      end try
    end tell
  end tell
end run
APPLESCRIPT
}

verify_visible_project_directory_picker_assignment() {
  local escaped_workspace
  local picker_sql
  escaped_workspace="$(sql_escape "$UI_WORKSPACE")"
  picker_sql="
SELECT CASE WHEN workspace_path='$escaped_workspace' AND workspace_bookmark IS NOT NULL AND length(workspace_bookmark) > 0 THEN 1 ELSE 0 END
FROM projects
WHERE id=$seed_project_id;
"

  # Project selection intentionally keeps editing closed until the user asks
  # for it. Open the inspector through the same visible control a user uses
  # before exercising the directory picker.
  pressButtonContainingBounded "project-header-open-inspector"
  waitForAXMarkerContaining "project-inspector"
  waitForAXSubtreeMarkerContaining "project-workspace-current" "Not set"
  chooseRuntimeProjectWorkspaceViaOpenPanel "$UI_WORKSPACE"
  waitForSQLiteValue \
    "visible Project inspector selected project workspace through NSOpenPanel" \
    "$picker_sql" \
    "1"
  waitForAXSubtreeMarkerContaining "project-workspace-current" "approved-workspace"
}

verify_runtime_fake_publish_tools_block_bypass() {
  local git_command="git"
  local push_command="push"

  : >"$runtime_blocked_external_write_log"
  if PATH="$runtime_fake_git_bin:$PATH" \
    REAL_GIT="$REAL_GIT" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_FAKE_PUSH_LOG="$runtime_fake_git_push_log" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_BLOCKED_EXTERNAL_WRITE_LOG="$runtime_blocked_external_write_log" \
    "$git_command" -C "$UI_WORKSPACE" "$push_command" -u blocked-remote "feature/blocked" >/dev/null 2>&1; then
    echo "BLOCKER: fake publish wrapper allowed global -C publish bypass" >&2
    return 1
  fi
  if ! grep -F "blocked publish command:" "$runtime_blocked_external_write_log" >/dev/null; then
    echo "BLOCKER: fake publish wrapper did not log global -C publish bypass" >&2
    return 1
  fi

  : >"$runtime_blocked_external_write_log"
  if PATH="$runtime_fake_git_bin:$PATH" \
    REAL_GIT="$REAL_GIT" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_FAKE_PUSH_LOG="$runtime_fake_git_push_log" \
    SUISUI_RUNTIME_DEVELOPMENT_PR_BLOCKED_EXTERNAL_WRITE_LOG="$runtime_blocked_external_write_log" \
    "$git_command" -c core.hooksPath=/dev/null "$push_command" -u blocked-remote "feature/blocked" >/dev/null 2>&1; then
    echo "BLOCKER: fake publish wrapper allowed global -c publish bypass" >&2
    return 1
  fi
  if ! grep -F "blocked publish command:" "$runtime_blocked_external_write_log" >/dev/null; then
    echo "BLOCKER: fake publish wrapper did not log global -c publish bypass" >&2
    return 1
  fi

  : >"$runtime_blocked_external_write_log"
}

verify_visible_queue_handoff() {
  local branch_fragment="feature/suisui-$seed_project_id-$seed_task_id"
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
}

wait_for_receipt_json() {
  local label="$1"
  local item_id="$2"
  local expected_tool="$3"
  local expected_reference_kind="${4:-}"
  local expected_reference_id="${5:-}"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local receipt_file=""

  while true; do
    if [[ -d "$receipt_directory" ]]; then
      receipt_file="$(/usr/bin/swift - "$receipt_directory" "$item_id" "$expected_tool" "$expected_reference_kind" "$expected_reference_id" <<'SWIFT' 2>/dev/null || true
import Foundation

struct Reference: Decodable {
    let kind: String
    let id: String
}

struct Receipt: Decodable {
    let assistantQueueItemID: String?
    let primaryToolName: String?
    let status: String
    let references: [Reference]?
}

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let itemID = CommandLine.arguments[2]
let expectedTool = CommandLine.arguments[3]
let expectedReferenceKind = CommandLine.arguments.count > 4 ? CommandLine.arguments[4] : ""
let expectedReferenceID = CommandLine.arguments.count > 5 ? CommandLine.arguments[5] : ""
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
          receipt.primaryToolName == expectedTool,
          receipt.status == "succeeded" else {
        continue
    }
    let hasExpectedReference = expectedReferenceKind.isEmpty
        || (receipt.references ?? []).contains { reference in
            reference.kind == expectedReferenceKind && reference.id == expectedReferenceID
        }
    guard hasExpectedReference else {
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
  branch_fragment="feature/suisui-$seed_project_id-$seed_task_id"
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
  wait_for_receipt_json "visible Assistant Queue branch preparation" "$queued_item_id" "development.pr_workflow.prepare"

  current_branch="$(fixture_git -C "$UI_WORKSPACE" branch --show-current)"
  prepared_branch_name="$current_branch"
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

verify_visible_repository_edit_handoff() {
  local escaped_relative_path
  local queue_sql
  escaped_relative_path="$(sql_escape "$visible_edit_relative_path")"
  queue_sql="
SELECT CASE WHEN count(*) = 1 THEN 1 ELSE 0 END
FROM assistant_queue_items
WHERE id LIKE 'action-plan:development-repository-edit:$seed_project_id:$seed_task_id:%'
  AND payload_kind='action_plan'
  AND state='waitingReview'
  AND risk_level='write'
  AND approval_json IS NULL
  AND payload_json LIKE '%development.repository.create_file%'
  AND payload_json LIKE '%$escaped_relative_path%'
  AND required_capabilities_json LIKE '%providerExecutionApproval%'
  AND (
    required_capabilities_json LIKE '%development.repository.create_file%'
    OR required_capabilities_json LIKE '%developmentRepositoryCreateFile%'
  );
"

  waitForAXMarkerContaining "project-development-automation-status"
  setTextFieldContaining "project-development-automation-edit-path" "$visible_edit_relative_path"
  setTextFieldContaining "project-development-automation-edit-contents" "$visible_edit_contents"
  waitForAXSubtreeMarkerContaining "project-development-automation-edit-preview" "$visible_edit_relative_path"
  pressButtonUntilSQLiteValue \
    "visible Project automation panel queued repository edit review into Assistant Queue" \
    "project-development-automation-edit-queue" \
    "$queue_sql" \
    "1"
  repository_edit_item_id="$(wait_for_nonempty_value \
    "queued development repository edit Assistant Queue item id" \
    "SELECT id FROM assistant_queue_items WHERE id LIKE 'action-plan:development-repository-edit:$seed_project_id:$seed_task_id:%' ORDER BY updated_at DESC LIMIT 1;")"
}

verify_visible_assistant_queue_repository_edit_execution() {
  if [[ -z "$repository_edit_item_id" ]]; then
    echo "BLOCKER: repository edit Assistant Queue item id is missing before approve/run" >&2
    return 1
  fi

  local escaped_item_id
  local approval_sql
  local done_sql
  local edited_path
  local actual_contents
  escaped_item_id="$(sql_escape "$repository_edit_item_id")"
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
  waitForAXMarkerContaining "assistant-queue-row-$repository_edit_item_id"
  pressButtonUntilSQLiteValue \
    "visible Assistant Queue approved repository edit" \
    "assistant-queue-approve-$repository_edit_item_id" \
    "$approval_sql" \
    "1"
  pressButtonUntilSQLiteValue \
    "visible Assistant Queue approved and executed repository edit" \
    "assistant-queue-run-$repository_edit_item_id" \
    "$done_sql" \
    "1"
  wait_for_receipt_json "visible Assistant Queue repository edit" "$repository_edit_item_id" "development.repository.create_file"

  edited_path="$UI_WORKSPACE/$visible_edit_relative_path"
  if [[ ! -f "$edited_path" ]]; then
    echo "BLOCKER: repository edit did not create expected file: $edited_path" >&2
    return 1
  fi
  actual_contents="$(cat "$edited_path")"
  if [[ "$actual_contents" != "$visible_edit_contents" ]]; then
    echo "BLOCKER: repository edit file contents mismatch for $edited_path" >&2
    return 1
  fi
  printf "OK: visible repository edit wrote %s\n" "$(relative_path "$edited_path")"
}

verify_visible_verification_handoff() {
  local queue_sql
  queue_sql="
SELECT CASE WHEN count(*) = 1 THEN 1 ELSE 0 END
FROM assistant_queue_items
WHERE id LIKE 'action-plan:development-verification:$seed_project_id:$seed_task_id:%'
  AND payload_kind='action_plan'
  AND state='waitingReview'
  AND risk_level='write'
  AND approval_json IS NULL
  AND payload_json LIKE '%development.verification.run%'
  AND payload_json LIKE '%git.diff_check%'
  AND required_capabilities_json LIKE '%providerExecutionApproval%'
  AND (
    required_capabilities_json LIKE '%development.verification.run%'
    OR required_capabilities_json LIKE '%developmentRunVerification%'
  );
"

  waitForAXMarkerContaining "project-development-automation-status"
  pressButtonUntilSQLiteValue \
    "visible Project automation panel queued verification review into Assistant Queue" \
    "project-development-automation-verification-queue" \
    "$queue_sql" \
    "1"
  verification_item_id="$(wait_for_nonempty_value \
    "queued development verification Assistant Queue item id" \
    "SELECT id FROM assistant_queue_items WHERE id LIKE 'action-plan:development-verification:$seed_project_id:$seed_task_id:%' ORDER BY updated_at DESC LIMIT 1;")"
}

verify_visible_assistant_queue_verification_execution() {
  if [[ -z "$verification_item_id" ]]; then
    echo "BLOCKER: verification Assistant Queue item id is missing before approve/run" >&2
    return 1
  fi

  local escaped_item_id
  local approval_sql
  local done_sql
  escaped_item_id="$(sql_escape "$verification_item_id")"
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
  waitForAXMarkerContaining "assistant-queue-row-$verification_item_id"
  pressButtonUntilSQLiteValue \
    "visible Assistant Queue approved verification" \
    "assistant-queue-approve-$verification_item_id" \
    "$approval_sql" \
    "1"
  pressButtonUntilSQLiteValue \
    "visible Assistant Queue approved and executed verification" \
    "assistant-queue-run-$verification_item_id" \
    "$done_sql" \
    "1"
  wait_for_receipt_json \
    "visible Assistant Queue verification" \
    "$verification_item_id" \
    "development.verification.run" \
    "development_branch" \
    "$prepared_branch_name"
}

verify_visible_commit_handoff() {
  local escaped_relative_path
  local escaped_commit_message
  local escaped_branch_name
  local escaped_json_branch_name
  local queue_sql
  escaped_relative_path="$(sql_escape "$visible_edit_relative_path")"
  escaped_commit_message="$(sql_escape "$visible_commit_message")"
  escaped_branch_name="$(sql_escape "$prepared_branch_name")"
  escaped_json_branch_name="$(sql_escape "${prepared_branch_name//\//\\/}")"
  queue_sql="
SELECT CASE WHEN count(*) = 1 THEN 1 ELSE 0 END
FROM assistant_queue_items
WHERE id LIKE 'action-plan:development-commit:$seed_project_id:$seed_task_id:%'
  AND payload_kind='action_plan'
  AND state='waitingReview'
  AND risk_level='write'
  AND approval_json IS NULL
  AND payload_json LIKE '%development.pr_workflow.commit%'
  AND payload_json LIKE '%$escaped_relative_path%'
  AND payload_json LIKE '%$escaped_commit_message%'
  AND (
    payload_json LIKE '%$escaped_branch_name%'
    OR payload_json LIKE '%$escaped_json_branch_name%'
  )
  AND payload_json NOT LIKE '%development.pr_workflow.push%'
  AND payload_json NOT LIKE '%development.pr_workflow.create_pull_request%'
  AND required_capabilities_json LIKE '%providerExecutionApproval%'
  AND (
    required_capabilities_json LIKE '%development.pr_workflow.commit%'
    OR required_capabilities_json LIKE '%developmentCommitChanges%'
  );
"

  waitForAXMarkerContaining "project-development-automation-status"
  setTextFieldContaining "project-development-automation-commit-paths" "$visible_edit_relative_path"
  setTextFieldContaining "project-development-automation-commit-message" "$visible_commit_message"
  pressButtonUntilSQLiteValue \
    "visible Project automation panel queued commit review into Assistant Queue" \
    "project-development-automation-commit-queue" \
    "$queue_sql" \
    "1"
  commit_item_id="$(wait_for_nonempty_value \
    "queued development commit Assistant Queue item id" \
    "SELECT id FROM assistant_queue_items WHERE id LIKE 'action-plan:development-commit:$seed_project_id:$seed_task_id:%' ORDER BY updated_at DESC LIMIT 1;")"
}

verify_visible_assistant_queue_commit_execution() {
  if [[ -z "$commit_item_id" ]]; then
    echo "BLOCKER: commit Assistant Queue item id is missing before approve/run" >&2
    return 1
  fi

  local escaped_item_id
  local approval_sql
  local done_sql
  local current_branch
  local committed_paths
  escaped_item_id="$(sql_escape "$commit_item_id")"
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

  visible_commit_head_before="$(fixture_git -C "$UI_WORKSPACE" rev-parse HEAD)"

  launch_app_for_assistant_queue
  wait_for_database_table "assistant_queue_items"
  waitForAXMarkerContaining "assistant-queue-workflow"
  waitForAXMarkerContaining "assistant-queue-row-$commit_item_id"
  pressButtonUntilSQLiteValue \
    "visible Assistant Queue approved local commit" \
    "assistant-queue-approve-$commit_item_id" \
    "$approval_sql" \
    "1"
  pressButtonUntilSQLiteValue \
    "visible Assistant Queue approved and executed local commit" \
    "assistant-queue-run-$commit_item_id" \
    "$done_sql" \
    "1"

  visible_commit_head_after="$(fixture_git -C "$UI_WORKSPACE" rev-parse HEAD)"
  if [[ "$visible_commit_head_after" == "$visible_commit_head_before" ]]; then
    echo "BLOCKER: local commit did not advance fixture HEAD" >&2
    return 1
  fi

  current_branch="$(fixture_git -C "$UI_WORKSPACE" branch --show-current)"
  if [[ "$current_branch" != "$prepared_branch_name" ]]; then
    echo "BLOCKER: local commit ran on branch '$current_branch', expected '$prepared_branch_name'" >&2
    return 1
  fi

  committed_paths="$(fixture_git -C "$UI_WORKSPACE" diff-tree --no-commit-id --name-only -r "$visible_commit_head_after")"
  if ! printf '%s\n' "$committed_paths" | grep -Fx "$visible_edit_relative_path" >/dev/null; then
    echo "BLOCKER: local commit did not include reviewed path $visible_edit_relative_path" >&2
    return 1
  fi

  wait_for_receipt_json \
    "visible Assistant Queue commit branch reference" \
    "$commit_item_id" \
    "development.pr_workflow.commit" \
    "development_branch" \
    "$prepared_branch_name"
  wait_for_receipt_json \
    "visible Assistant Queue commit" \
    "$commit_item_id" \
    "development.pr_workflow.commit" \
    "development_commit" \
    "$visible_commit_head_after"
  printf "OK: visible Assistant Queue local commit advanced fixture HEAD to %s\n" "$visible_commit_head_after"
}

verify_visible_push_handoff() {
  if [[ -z "$prepared_branch_name" || -z "$visible_commit_head_after" ]]; then
    echo "BLOCKER: branch name or reviewed commit OID is missing before push handoff" >&2
    return 1
  fi
  printf '%s' "$prepared_branch_name" >"$runtime_expected_branch_file"
  printf '%s' "$visible_commit_head_after" >"$runtime_expected_head_file"

  local escaped_branch_name
  local escaped_json_branch_name
  local escaped_head_oid
  local queue_sql
  escaped_branch_name="$(sql_escape "$prepared_branch_name")"
  escaped_json_branch_name="$(sql_escape "${prepared_branch_name//\//\\/}")"
  escaped_head_oid="$(sql_escape "$visible_commit_head_after")"
  queue_sql="
SELECT CASE WHEN count(*) = 1 THEN 1 ELSE 0 END
FROM assistant_queue_items
WHERE id LIKE 'action-plan:development-pr-push:$seed_project_id:$seed_task_id:%'
  AND payload_kind='action_plan'
  AND state='waitingReview'
  AND risk_level='write'
  AND approval_json IS NULL
  AND payload_json LIKE '%development.pr_workflow.push%'
  AND payload_json LIKE '%expectedHeadOID%'
  AND payload_json LIKE '%$escaped_head_oid%'
  AND (
    payload_json LIKE '%$escaped_branch_name%'
    OR payload_json LIKE '%$escaped_json_branch_name%'
  )
  AND payload_json NOT LIKE '%development.pr_workflow.create_pull_request%'
  AND required_capabilities_json LIKE '%providerExecutionApproval%'
  AND (
    required_capabilities_json LIKE '%development.pr_workflow.push%'
    OR required_capabilities_json LIKE '%developmentPushBranch%'
  );
"

  waitForAXMarkerContaining "project-development-automation-status"
  pressButtonUntilSQLiteValue \
    "visible Project automation panel queued branch push review into Assistant Queue" \
    "project-development-automation-push-queue" \
    "$queue_sql" \
    "1"
  push_item_id="$(wait_for_nonempty_value \
    "queued development branch push Assistant Queue item id" \
    "SELECT id FROM assistant_queue_items WHERE id LIKE 'action-plan:development-pr-push:$seed_project_id:$seed_task_id:%' ORDER BY updated_at DESC LIMIT 1;")"
}

verify_runtime_fake_push_log() {
  if [[ ! -f "$runtime_fake_git_push_log" ]]; then
    echo "BLOCKER: fake branch push did not record a log at $runtime_fake_git_push_log" >&2
    return 1
  fi
  local branch_count
  branch_count="$(grep -c '^branch=' "$runtime_fake_git_push_log" || true)"
  if [[ "$branch_count" != "1" ]]; then
    echo "BLOCKER: fake branch push log should contain exactly one branch entry, found $branch_count" >&2
    cat "$runtime_fake_git_push_log" >&2 || true
    return 1
  fi
  if ! grep -Fx "branch=$prepared_branch_name" "$runtime_fake_git_push_log" >/dev/null; then
    echo "BLOCKER: fake branch push log did not record expected branch $prepared_branch_name" >&2
    cat "$runtime_fake_git_push_log" >&2 || true
    return 1
  fi
  if ! grep -Fx "head=$visible_commit_head_after" "$runtime_fake_git_push_log" >/dev/null; then
    echo "BLOCKER: fake branch push log did not record reviewed commit $visible_commit_head_after" >&2
    cat "$runtime_fake_git_push_log" >&2 || true
    return 1
  fi
  if [[ -s "$runtime_blocked_external_write_log" ]]; then
    echo "BLOCKER: unexpected external publish tool call was blocked" >&2
    cat "$runtime_blocked_external_write_log" >&2 || true
    return 1
  fi
}

verify_no_merge_followup() {
  local merge_queue_count
  merge_queue_count="$("$SQLITE3" "$database_path" "SELECT count(*) FROM assistant_queue_items WHERE payload_json LIKE '%development.pr_workflow.merge%';")"
  if [[ "$merge_queue_count" != "0" ]]; then
    echo "BLOCKER: runtime PR smoke queued merge unexpectedly" >&2
    return 1
  fi

  local receipt_payload_json
  receipt_payload_json="$(/usr/bin/swift - "$receipt_directory" <<'SWIFT' 2>/dev/null || true
import Foundation

struct Receipt: Decodable {
    let primaryToolName: String?
}

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let files = (try? FileManager.default.contentsOfDirectory(
    at: directory,
    includingPropertiesForKeys: nil,
    options: [.skipsHiddenFiles]
)) ?? []
let decoder = JSONDecoder()
for file in files where file.pathExtension == "json" {
    guard let data = try? Data(contentsOf: file),
          let receipt = try? decoder.decode(Receipt.self, from: data),
          let tool = receipt.primaryToolName else {
        continue
    }
    print(tool)
}
SWIFT
)"
  if printf '%s\n' "$receipt_payload_json" | grep -Fx "development.pr_workflow.merge" >/dev/null; then
    echo "BLOCKER: runtime PR smoke created unexpected merge receipt" >&2
    return 1
  fi
}

verify_visible_assistant_queue_push_execution() {
  if [[ -z "$push_item_id" ]]; then
    echo "BLOCKER: push Assistant Queue item id is missing before approve/run" >&2
    return 1
  fi

  local escaped_item_id
  local approval_sql
  local done_sql
  escaped_item_id="$(sql_escape "$push_item_id")"
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
  waitForAXMarkerContaining "assistant-queue-row-$push_item_id"
  pressButtonUntilSQLiteValue \
    "visible Assistant Queue approved branch push" \
    "assistant-queue-approve-$push_item_id" \
    "$approval_sql" \
    "1"
  pressButtonUntilSQLiteValue \
    "visible Assistant Queue approved and executed fake branch push" \
    "assistant-queue-run-$push_item_id" \
    "$done_sql" \
    "1"

  wait_for_receipt_json \
    "visible Assistant Queue branch push reference" \
    "$push_item_id" \
    "development.pr_workflow.push" \
    "development_branch" \
    "$prepared_branch_name"
  wait_for_receipt_json \
    "visible Assistant Queue branch push" \
    "$push_item_id" \
    "development.pr_workflow.push" \
    "development_commit" \
    "$visible_commit_head_after"
  verify_runtime_fake_push_log
  printf "OK: visible Assistant Queue fake branch push recorded reviewed HEAD %s\n" "$visible_commit_head_after"
}

verify_visible_pull_request_creation_handoff() {
  if [[ -z "$prepared_branch_name" || -z "$visible_commit_head_after" ]]; then
    echo "BLOCKER: branch name or reviewed commit OID is missing before PR creation handoff" >&2
    return 1
  fi

  local escaped_branch_name
  local escaped_json_branch_name
  local escaped_base_branch
  local escaped_json_base_branch
  local escaped_head_oid
  local escaped_title
  local queue_sql
  escaped_branch_name="$(sql_escape "$prepared_branch_name")"
  escaped_json_branch_name="$(sql_escape "${prepared_branch_name//\//\\/}")"
  escaped_base_branch="$(sql_escape "$runtime_pull_request_base_branch")"
  escaped_json_base_branch="$(sql_escape "${runtime_pull_request_base_branch//\//\\/}")"
  escaped_head_oid="$(sql_escape "$visible_commit_head_after")"
  escaped_title="$(sql_escape "$runtime_pull_request_title")"
  queue_sql="
SELECT CASE WHEN count(*) = 1 THEN 1 ELSE 0 END
FROM assistant_queue_items
WHERE id LIKE 'action-plan:development-pr-create:$seed_project_id:$seed_task_id:%'
  AND payload_kind='action_plan'
  AND state='waitingReview'
  AND risk_level='write'
  AND approval_json IS NULL
  AND payload_json LIKE '%development.pr_workflow.create_pull_request%'
  AND payload_json LIKE '%expectedHeadOID%'
  AND payload_json LIKE '%$escaped_head_oid%'
  AND payload_json LIKE '%$escaped_title%'
  AND (
    payload_json LIKE '%$escaped_branch_name%'
    OR payload_json LIKE '%$escaped_json_branch_name%'
  )
  AND (
    payload_json LIKE '%$escaped_base_branch%'
    OR payload_json LIKE '%$escaped_json_base_branch%'
  )
  AND payload_json NOT LIKE '%development.pr_workflow.review_gate%'
  AND payload_json NOT LIKE '%development.pr_workflow.merge%'
  AND required_capabilities_json LIKE '%providerExecutionApproval%'
  AND (
    required_capabilities_json LIKE '%development.pr_workflow.create_pull_request%'
    OR required_capabilities_json LIKE '%developmentCreatePullRequest%'
  );
"

  waitForAXMarkerContaining "project-development-automation-status"
  scrollProjectDetailDown
  waitForAXMarkerContaining "project-development-automation-pr-create-queue"
  pressButtonUntilSQLiteValue \
    "visible Project automation panel queued pull request creation review into Assistant Queue" \
    "project-development-automation-pr-create-queue" \
    "$queue_sql" \
    "1"
  pull_request_item_id="$(wait_for_nonempty_value \
    "queued development pull request creation Assistant Queue item id" \
    "SELECT id FROM assistant_queue_items WHERE id LIKE 'action-plan:development-pr-create:$seed_project_id:$seed_task_id:%' ORDER BY updated_at DESC LIMIT 1;")"
}

verify_runtime_fake_pull_request_log() {
  if [[ ! -f "$runtime_fake_github_pr_log" ]]; then
    echo "BLOCKER: fake pull request create did not record a log at $runtime_fake_github_pr_log" >&2
    return 1
  fi
  local url_count
  url_count="$(grep -c '^url=' "$runtime_fake_github_pr_log" || true)"
  if [[ "$url_count" != "1" ]]; then
    echo "BLOCKER: fake pull request create log should contain exactly one URL entry, found $url_count" >&2
    cat "$runtime_fake_github_pr_log" >&2 || true
    return 1
  fi
  for expected_line in \
    "branch=$prepared_branch_name" \
    "base=$runtime_pull_request_base_branch" \
    "url=$runtime_fake_pull_request_url"; do
    if ! grep -Fx "$expected_line" "$runtime_fake_github_pr_log" >/dev/null; then
      echo "BLOCKER: fake pull request create log missing $expected_line" >&2
      cat "$runtime_fake_github_pr_log" >&2 || true
      return 1
    fi
  done
  if grep -Fx "bodyBytes=-1" "$runtime_fake_github_pr_log" >/dev/null; then
    echo "BLOCKER: fake pull request create did not read the reviewed body file" >&2
    cat "$runtime_fake_github_pr_log" >&2 || true
    return 1
  fi
  if [[ -s "$runtime_blocked_external_write_log" ]]; then
    echo "BLOCKER: unexpected external publish tool call was blocked" >&2
    cat "$runtime_blocked_external_write_log" >&2 || true
    return 1
  fi
}

verify_visible_assistant_queue_pull_request_creation_execution() {
  if [[ -z "$pull_request_item_id" ]]; then
    echo "BLOCKER: pull request creation Assistant Queue item id is missing before approve/run" >&2
    return 1
  fi

  local escaped_item_id
  local approval_sql
  local done_sql
  escaped_item_id="$(sql_escape "$pull_request_item_id")"
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
  waitForAXMarkerContaining "assistant-queue-row-$pull_request_item_id"
  pressButtonUntilSQLiteValue \
    "visible Assistant Queue approved pull request creation" \
    "assistant-queue-approve-$pull_request_item_id" \
    "$approval_sql" \
    "1"
  launch_app_for_assistant_queue
  wait_for_database_table "assistant_queue_items"
  waitForAXMarkerContaining "assistant-queue-workflow"
  waitForAXMarkerContaining "assistant-queue-row-$pull_request_item_id"
  pressButtonUntilSQLiteValue \
    "visible Assistant Queue approved and executed fake pull request creation" \
    "assistant-queue-run-$pull_request_item_id" \
    "$done_sql" \
    "1"

  wait_for_receipt_json \
    "visible Assistant Queue pull request creation URL" \
    "$pull_request_item_id" \
    "development.pr_workflow.create_pull_request" \
    "pull_request" \
    "$runtime_fake_pull_request_url"
  wait_for_receipt_json \
    "visible Assistant Queue pull request creation branch" \
    "$pull_request_item_id" \
    "development.pr_workflow.create_pull_request" \
    "development_branch" \
    "$prepared_branch_name"
  wait_for_receipt_json \
    "visible Assistant Queue pull request creation base" \
    "$pull_request_item_id" \
    "development.pr_workflow.create_pull_request" \
    "development_base_branch" \
    "$runtime_pull_request_base_branch"
  wait_for_receipt_json \
    "visible Assistant Queue pull request creation" \
    "$pull_request_item_id" \
    "development.pr_workflow.create_pull_request" \
    "development_commit" \
    "$visible_commit_head_after"
  verify_runtime_fake_pull_request_log
  verify_no_merge_followup
  printf "OK: visible Assistant Queue fake pull request create recorded %s\n" "$runtime_fake_pull_request_url"
}

verify_visible_pull_request_review_gate_handoff() {
  if [[ -z "$prepared_branch_name" || -z "$visible_commit_head_after" ]]; then
    echo "BLOCKER: branch name or reviewed commit OID is missing before PR review gate handoff" >&2
    return 1
  fi

  local escaped_pull_request_url
  local escaped_json_pull_request_url
  local escaped_branch_name
  local escaped_json_branch_name
  local escaped_base_branch
  local escaped_json_base_branch
  local queue_sql
  escaped_pull_request_url="$(sql_escape "$runtime_fake_pull_request_url")"
  escaped_json_pull_request_url="$(sql_escape "${runtime_fake_pull_request_url//\//\\/}")"
  escaped_branch_name="$(sql_escape "$prepared_branch_name")"
  escaped_json_branch_name="$(sql_escape "${prepared_branch_name//\//\\/}")"
  escaped_base_branch="$(sql_escape "$runtime_pull_request_base_branch")"
  escaped_json_base_branch="$(sql_escape "${runtime_pull_request_base_branch//\//\\/}")"
  queue_sql="
SELECT CASE WHEN count(*) = 1 THEN 1 ELSE 0 END
FROM assistant_queue_items
WHERE id LIKE 'automation-request:project-development-pr-review:$seed_project_id:$seed_task_id:%'
  AND payload_kind='automation_request'
  AND state='waitingReview'
  AND risk_level='write'
  AND approval_json IS NULL
  AND payload_json LIKE '%development.pr_workflow.review_gate%'
  AND payload_json LIKE '%reviewGate%'
  AND (
    payload_json LIKE '%$escaped_pull_request_url%'
    OR payload_json LIKE '%$escaped_json_pull_request_url%'
  )
  AND (
    payload_json LIKE '%$escaped_branch_name%'
    OR payload_json LIKE '%$escaped_json_branch_name%'
  )
  AND (
    payload_json LIKE '%$escaped_base_branch%'
    OR payload_json LIKE '%$escaped_json_base_branch%'
  )
  AND required_capabilities_json LIKE '%providerExecutionApproval%'
  AND (
    required_capabilities_json LIKE '%development.pr_workflow.review_gate%'
    OR required_capabilities_json LIKE '%developmentReviewPullRequestGate%'
  );
"

  waitForAXMarkerContaining "project-development-automation-status"
  scrollProjectDetailDown
  waitForAXMarkerContaining "project-development-automation-pr-review-queue"
  pressButtonUntilSQLiteValue \
    "visible Project automation panel queued pull request review gate into Assistant Queue" \
    "project-development-automation-pr-review-queue" \
    "$queue_sql" \
    "1"
  pull_request_review_item_id="$(wait_for_nonempty_value \
    "queued development pull request review gate Assistant Queue item id" \
    "SELECT id FROM assistant_queue_items WHERE id LIKE 'automation-request:project-development-pr-review:$seed_project_id:$seed_task_id:%' ORDER BY updated_at DESC LIMIT 1;")"
  verify_no_merge_followup
}

verify_runtime_fake_pull_request_review_log() {
  if [[ ! -f "$runtime_fake_github_review_log" ]]; then
    echo "BLOCKER: fake pull request review gate did not record a log at $runtime_fake_github_review_log" >&2
    return 1
  fi
  local status_count
  local threads_count
  status_count="$(grep -c '^action=status$' "$runtime_fake_github_review_log" || true)"
  threads_count="$(grep -c '^action=threads$' "$runtime_fake_github_review_log" || true)"
  if [[ "$status_count" != "1" || "$threads_count" != "1" ]]; then
    echo "BLOCKER: fake pull request review log should contain one status and one threads entry, found status=$status_count threads=$threads_count" >&2
    cat "$runtime_fake_github_review_log" >&2 || true
    return 1
  fi
  local review_url_path
  local expected_repository
  local expected_number
  review_url_path="${runtime_fake_pull_request_url#https://github.com/}"
  expected_repository="${review_url_path%%/pull/*}"
  expected_number="${review_url_path##*/}"
  for expected_line in \
    "url=$runtime_fake_pull_request_url" \
    "branch=$prepared_branch_name" \
    "base=$runtime_pull_request_base_branch" \
    "head=$visible_commit_head_after" \
    "repository=$expected_repository" \
    "number=$expected_number"; do
    if ! grep -Fx "$expected_line" "$runtime_fake_github_review_log" >/dev/null; then
      echo "BLOCKER: fake pull request review log missing $expected_line" >&2
      cat "$runtime_fake_github_review_log" >&2 || true
      return 1
    fi
  done
  if [[ -s "$runtime_blocked_external_write_log" ]]; then
    echo "BLOCKER: unexpected external publish tool call was blocked" >&2
    cat "$runtime_blocked_external_write_log" >&2 || true
    return 1
  fi
}

verify_visible_assistant_queue_pull_request_review_gate_execution() {
  if [[ -z "$pull_request_review_item_id" ]]; then
    echo "BLOCKER: pull request review gate Assistant Queue item id is missing before approve/run" >&2
    return 1
  fi

  local escaped_item_id
  local approval_sql
  local done_sql
  escaped_item_id="$(sql_escape "$pull_request_review_item_id")"
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
  waitForAXMarkerContaining "assistant-queue-row-$pull_request_review_item_id"
  pressButtonUntilSQLiteValue \
    "visible Assistant Queue approved pull request review gate" \
    "assistant-queue-approve-$pull_request_review_item_id" \
    "$approval_sql" \
    "1"
  launch_app_for_assistant_queue
  wait_for_database_table "assistant_queue_items"
  waitForAXMarkerContaining "assistant-queue-workflow"
  waitForAXMarkerContaining "assistant-queue-row-$pull_request_review_item_id"
  pressButtonUntilSQLiteValue \
    "visible Assistant Queue approved and executed fake pull request review gate" \
    "assistant-queue-run-$pull_request_review_item_id" \
    "$done_sql" \
    "1"

  wait_for_receipt_json \
    "visible Assistant Queue pull request review gate URL" \
    "$pull_request_review_item_id" \
    "development.pr_workflow.review_gate" \
    "pull_request" \
    "$runtime_fake_pull_request_url"
  wait_for_receipt_json \
    "visible Assistant Queue pull request review gate branch" \
    "$pull_request_review_item_id" \
    "development.pr_workflow.review_gate" \
    "development_branch" \
    "$prepared_branch_name"
  wait_for_receipt_json \
    "visible Assistant Queue pull request review gate base" \
    "$pull_request_review_item_id" \
    "development.pr_workflow.review_gate" \
    "development_base_branch" \
    "$runtime_pull_request_base_branch"
  wait_for_receipt_json \
    "visible Assistant Queue pull request review gate" \
    "$pull_request_review_item_id" \
    "development.pr_workflow.review_gate" \
    "development_commit" \
    "$visible_commit_head_after"
  verify_runtime_fake_pull_request_review_log
  verify_no_merge_followup
  printf "OK: visible Assistant Queue fake pull request review gate passed for %s\n" "$runtime_fake_pull_request_url"
}

verify_visible_pull_request_merge_handoff() {
  if [[ -z "$prepared_branch_name" || -z "$visible_commit_head_after" ]]; then
    echo "BLOCKER: branch name or reviewed commit OID is missing before PR merge handoff" >&2
    return 1
  fi

  local escaped_pull_request_url
  local escaped_json_pull_request_url
  local escaped_branch_name
  local escaped_json_branch_name
  local escaped_base_branch
  local escaped_json_base_branch
  local queue_sql
  escaped_pull_request_url="$(sql_escape "$runtime_fake_pull_request_url")"
  escaped_json_pull_request_url="$(sql_escape "${runtime_fake_pull_request_url//\//\\/}")"
  escaped_branch_name="$(sql_escape "$prepared_branch_name")"
  escaped_json_branch_name="$(sql_escape "${prepared_branch_name//\//\\/}")"
  escaped_base_branch="$(sql_escape "$runtime_pull_request_base_branch")"
  escaped_json_base_branch="$(sql_escape "${runtime_pull_request_base_branch//\//\\/}")"
  queue_sql="
SELECT CASE WHEN count(*) = 1 THEN 1 ELSE 0 END
FROM assistant_queue_items
WHERE id LIKE 'automation-request:project-development-pr-merge:$seed_project_id:$seed_task_id:%'
  AND payload_kind='automation_request'
  AND state='waitingReview'
  AND risk_level='write'
  AND approval_json IS NULL
  AND payload_json LIKE '%development.pr_workflow.merge%'
  AND payload_json LIKE '%merge%'
  AND (
    payload_json LIKE '%$escaped_pull_request_url%'
    OR payload_json LIKE '%$escaped_json_pull_request_url%'
  )
  AND (
    payload_json LIKE '%$escaped_branch_name%'
    OR payload_json LIKE '%$escaped_json_branch_name%'
  )
  AND (
    payload_json LIKE '%$escaped_base_branch%'
    OR payload_json LIKE '%$escaped_json_base_branch%'
  )
  AND required_capabilities_json LIKE '%providerExecutionApproval%'
  AND (
    required_capabilities_json LIKE '%development.pr_workflow.merge%'
    OR required_capabilities_json LIKE '%developmentMergePullRequest%'
  );
"

  waitForAXMarkerContaining "project-development-automation-status"
  scrollProjectDetailDown
  waitForAXMarkerContaining "project-development-automation-pr-merge-queue"
  pressButtonUntilSQLiteValue \
    "visible Project automation panel queued pull request merge into Assistant Queue" \
    "project-development-automation-pr-merge-queue" \
    "$queue_sql" \
    "1"
  pull_request_merge_item_id="$(wait_for_nonempty_value \
    "queued development pull request merge Assistant Queue item id" \
    "SELECT id FROM assistant_queue_items WHERE id LIKE 'automation-request:project-development-pr-merge:$seed_project_id:$seed_task_id:%' ORDER BY updated_at DESC LIMIT 1;")"
}

verify_runtime_fake_pull_request_merge_log() {
  if [[ ! -f "$runtime_fake_github_merge_log" ]]; then
    echo "BLOCKER: fake pull request merge did not record a log at $runtime_fake_github_merge_log" >&2
    return 1
  fi
  local merge_count
  merge_count="$(grep -c '^action=merge$' "$runtime_fake_github_merge_log" || true)"
  if [[ "$merge_count" != "1" ]]; then
    echo "BLOCKER: fake pull request merge log should contain one merge entry, found $merge_count" >&2
    cat "$runtime_fake_github_merge_log" >&2 || true
    return 1
  fi

  local status_count
  local threads_count
  status_count="$(grep -c '^action=status$' "$runtime_fake_github_review_log" || true)"
  threads_count="$(grep -c '^action=threads$' "$runtime_fake_github_review_log" || true)"
  if [[ "$status_count" != "2" || "$threads_count" != "2" ]]; then
    echo "BLOCKER: fake pull request merge should re-check review gates before merge, found status=$status_count threads=$threads_count" >&2
    cat "$runtime_fake_github_review_log" >&2 || true
    return 1
  fi

  for expected_line in \
    "url=$runtime_fake_pull_request_url" \
    "branch=$prepared_branch_name" \
    "base=$runtime_pull_request_base_branch" \
    "head=$visible_commit_head_after" \
    "strategy=merge" \
    "deleteBranch=true"; do
    if ! grep -Fx "$expected_line" "$runtime_fake_github_merge_log" >/dev/null; then
      echo "BLOCKER: fake pull request merge log missing $expected_line" >&2
      cat "$runtime_fake_github_merge_log" >&2 || true
      return 1
    fi
  done
  if ! grep -Fx "args=gh pr merge $runtime_fake_pull_request_url --merge --delete-branch --match-head-commit $visible_commit_head_after" "$runtime_fake_github_merge_log" >/dev/null; then
    echo "BLOCKER: fake pull request merge log did not record the reviewed head-locked merge command" >&2
    cat "$runtime_fake_github_merge_log" >&2 || true
    return 1
  fi
  if [[ -s "$runtime_blocked_external_write_log" ]]; then
    echo "BLOCKER: unexpected external publish tool call was blocked" >&2
    cat "$runtime_blocked_external_write_log" >&2 || true
    return 1
  fi
}

verify_visible_assistant_queue_pull_request_merge_execution() {
  if [[ -z "$pull_request_merge_item_id" ]]; then
    echo "BLOCKER: pull request merge Assistant Queue item id is missing before approve/run" >&2
    return 1
  fi

  local escaped_item_id
  local approval_sql
  local done_sql
  escaped_item_id="$(sql_escape "$pull_request_merge_item_id")"
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
  waitForAXMarkerContaining "assistant-queue-row-$pull_request_merge_item_id"
  pressButtonUntilSQLiteValue \
    "visible Assistant Queue approved pull request merge" \
    "assistant-queue-approve-$pull_request_merge_item_id" \
    "$approval_sql" \
    "1"
  launch_app_for_assistant_queue
  wait_for_database_table "assistant_queue_items"
  waitForAXMarkerContaining "assistant-queue-workflow"
  waitForAXMarkerContaining "assistant-queue-row-$pull_request_merge_item_id"
  pressButtonUntilSQLiteValue \
    "visible Assistant Queue approved and executed fake pull request merge" \
    "assistant-queue-run-$pull_request_merge_item_id" \
    "$done_sql" \
    "1"

  wait_for_receipt_json \
    "visible Assistant Queue pull request merge URL" \
    "$pull_request_merge_item_id" \
    "development.pr_workflow.merge" \
    "pull_request" \
    "$runtime_fake_pull_request_url"
  wait_for_receipt_json \
    "visible Assistant Queue pull request merge branch" \
    "$pull_request_merge_item_id" \
    "development.pr_workflow.merge" \
    "development_branch" \
    "$prepared_branch_name"
  wait_for_receipt_json \
    "visible Assistant Queue pull request merge base" \
    "$pull_request_merge_item_id" \
    "development.pr_workflow.merge" \
    "development_base_branch" \
    "$runtime_pull_request_base_branch"
  wait_for_receipt_json \
    "visible Assistant Queue pull request merge" \
    "$pull_request_merge_item_id" \
    "development.pr_workflow.merge" \
    "development_commit" \
    "$visible_commit_head_after"
  verify_runtime_fake_pull_request_merge_log
  printf "OK: visible Assistant Queue fake pull request merge recorded %s at %s\n" "$runtime_fake_pull_request_url" "$visible_commit_head_after"
}

printf "== Runtime development PR smoke ==\n"
ensure_no_existing_app_process
install_runtime_fake_publish_tools

failure_reason="approved project directory fixture XCTest failed"
if ! SUISUI_RUNTIME_DEVELOPMENT_PR_WORKSPACE_ROOT="$WORKSPACE_ROOT" \
  SUISUI_RUNTIME_DEVELOPMENT_PR_KEEP_WORKSPACE="$KEEP_WORKSPACE" \
  swift test --filter DevelopmentAutomationRuntimeSmokeTests/testApprovedProjectDirectoryCanEditVerifyCommitAndPreparePullRequestBranch --quiet >"$OUTPUT_FILE" 2>&1; then
  cat "$OUTPUT_FILE" >&2
  write_artifact "failed" "development PR fixture flow failed"
  echo "BLOCKER: runtime development PR smoke failed. Evidence: $(relative_path "$ARTIFACT_FILE")" >&2
  exit 1
fi
cat "$OUTPUT_FILE"

failure_reason="Suisui app bundle build failed"
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
rm -rf "$receipt_directory"
failure_reason="runtime database migration failed"
launch_app_for_database_migration
wait_for_database_table "projects"
wait_for_database_table "tasks"
wait_for_database_table "assistant_queue_items"
terminate_app
wait_for_no_app_process

failure_reason="runtime development UI fixture seed failed"
seed_development_project
verify_runtime_fake_publish_tools_block_bypass

failure_reason="visible Project inspector directory picker assignment failed"
launch_app_for_project_directory_picker
verify_visible_project_directory_picker_assignment

failure_reason="visible Project detail Assistant Queue handoff failed"
launch_app_for_development_detail
wait_for_database_table "assistant_queue_items"
verify_visible_queue_handoff

failure_reason="visible Assistant Queue branch preparation execution failed"
verify_visible_assistant_queue_prepare_execution

failure_reason="visible Project detail repository edit handoff failed"
launch_app_for_development_detail
verify_visible_repository_edit_handoff

failure_reason="visible Assistant Queue repository edit execution failed"
verify_visible_assistant_queue_repository_edit_execution

failure_reason="visible Project detail verification handoff failed"
launch_app_for_development_detail
verify_visible_verification_handoff

failure_reason="visible Assistant Queue verification execution failed"
verify_visible_assistant_queue_verification_execution

failure_reason="visible Project detail commit handoff failed"
launch_app_for_development_detail
verify_visible_commit_handoff

failure_reason="visible Assistant Queue commit execution failed"
verify_visible_assistant_queue_commit_execution

failure_reason="visible Project detail branch push handoff failed"
launch_app_for_development_detail
verify_visible_push_handoff

failure_reason="visible Assistant Queue branch push execution failed"
verify_visible_assistant_queue_push_execution

failure_reason="visible Project detail pull request creation handoff failed"
launch_app_for_development_detail
verify_visible_pull_request_creation_handoff

failure_reason="visible Assistant Queue pull request creation execution failed"
verify_visible_assistant_queue_pull_request_creation_execution

failure_reason="visible Project detail pull request review gate handoff failed"
launch_app_for_development_detail
verify_visible_pull_request_review_gate_handoff

failure_reason="visible Assistant Queue pull request review gate execution failed"
verify_visible_assistant_queue_pull_request_review_gate_execution

failure_reason="visible Project detail pull request merge handoff failed"
launch_app_for_development_detail
verify_visible_pull_request_merge_handoff

failure_reason="visible Assistant Queue pull request merge execution failed"
verify_visible_assistant_queue_pull_request_merge_execution

write_artifact "passed" "visible Project inspector selected project workspace through NSOpenPanel, approved project directory fixture flow reached local commit, fake push, fake PR creation, fake PR review gate, fake PR merge, visible Project automation panel queued branch automation into Assistant Queue, visible Assistant Queue approved and executed local branch preparation, visible Project automation panel queued repository edit review into Assistant Queue, visible Assistant Queue approved and executed repository edit, visible Project automation panel queued verification review into Assistant Queue, visible Assistant Queue approved and executed verification, visible Project automation panel queued commit review into Assistant Queue, visible Assistant Queue approved and executed local commit, visible Project automation panel queued branch push review into Assistant Queue, visible Assistant Queue approved and executed fake branch push, visible Project automation panel queued pull request creation review into Assistant Queue, visible Assistant Queue approved and executed fake pull request creation, visible Project automation panel queued pull request review gate into Assistant Queue, visible Assistant Queue approved and executed fake pull request review gate, visible Project automation panel queued pull request merge into Assistant Queue, and visible Assistant Queue approved and executed fake pull request merge"
printf 'OK: runtime development PR smoke passed. Evidence: %s\n' "$(relative_path "$ARTIFACT_FILE")"
