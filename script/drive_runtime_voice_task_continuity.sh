#!/usr/bin/env bash
# Drives the real, distributed Suisui app for the #338 continuity evidence lane.
# It owns only the process it launches and emits redacted, machine-readable
# witnesses. A missing product capability is a failure, never a simulated pass.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/packaging/app_metadata.env"
source "$ROOT_DIR/script/ui_accessibility_smoke_helpers.sh"

APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
SQLITE3="${SQLITE3:-sqlite3}"
DATABASE_PATH="${SUISUI_DATABASE_PATH:?SUISUI_DATABASE_PATH is required}"
RUNTIME_HOME="${HOME:?isolated HOME is required}"
WITNESS_DIR="${SUISUI_VOICE_TASK_CONTINUITY_WITNESS_DIR:?witness directory is required}"
SNAPSHOT_FILE="${SUISUI_VOICE_TASK_CONTINUITY_PRE_APPROVAL_SNAPSHOT:?snapshot path is required}"
SOURCE_COMMIT="${SUISUI_VOICE_TASK_CONTINUITY_SOURCE_COMMIT:?source commit is required}"
FIXTURE_MANIFEST="${SUISUI_VOICE_TASK_CONTINUITY_FIXTURE_MANIFEST:?fixture manifest is required}"
TIMEOUT_SECONDS="${SUISUI_VOICE_TASK_CONTINUITY_TIMEOUT_SECONDS:-35}"

PROJECT_ID=1833801
TASK_ONE_ID=1833811
TASK_TWO_ID=1833812
PROJECT_TITLE="P18 338 Voice Continuity"
TASK_ONE_TITLE="P18 338 prepare review"
TASK_TWO_TITLE="P18 338 submit summary"
DUE_DATE="2031-03-08"
COMMAND_LIST="List tasks"
COMMAND_UPDATE="Update the second task due date and priority high"

app_launch_pid=""
app_pid=""
app_identity=""
baseline_task_digest=""
session_id=""
queue_item_id=""

usage() {
  printf '%s\n' "usage: $0 --run-all" >&2
}

write_failure() {
  local stage="$1" layer="$2" reason="$3"
  mkdir -p "$WITNESS_DIR"
  # Keep reasons closed vocabulary: no AX output, transcript, path, or secret
  # can escape an isolated fixture through the parent artifact.
  printf 'stage=%s\nlayer=%s\nreason=%s\n' "$stage" "$layer" "$reason" >"$WITNESS_DIR/driver-failure.env"
}

fail() {
  write_failure "$1" "$2" "$3"
  exit 1
}

write_witness() {
  local stage="$1"
  shift
  mkdir -p "$WITNESS_DIR"
  {
    printf 'stage=%s\n' "$stage"
    printf 'result=passed\n'
    printf 'source_commit=%s\n' "$SOURCE_COMMIT"
    printf '%s\n' "$@"
  } >"$WITNESS_DIR/$stage.witness"
}

cleanup() {
  if [[ -n "$app_pid" && -n "$app_identity" ]]; then
    ax_terminate_owned_process "$app_pid" "$APP_BINARY" "$app_identity"
  elif [[ -n "$app_launch_pid" ]]; then
    # Only the launch PID was created by this script; never name-kill Suisui.
    kill -TERM "$app_launch_pid" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

require_prerequisites() {
  [[ -x "$APP_BINARY" ]] || fail "normal_product_route" "launch" "distributed_app_missing"
  [[ -f "$FIXTURE_MANIFEST" ]] || fail "fixed_fixture_seed" "fixture" "fixture_manifest_missing"
  command -v "$SQLITE3" >/dev/null 2>&1 || fail "isolated_home_sqlite" "sqlite" "sqlite3_unavailable"
  [[ "$DATABASE_PATH" != ":memory:" ]] || fail "isolated_home_sqlite" "sqlite" "non_isolated_database"
  [[ "$RUNTIME_HOME" != "/Users/"* && "$RUNTIME_HOME" != "/home/"* ]] || fail "isolated_home_sqlite" "isolation" "non_isolated_home"
  [[ "$TIMEOUT_SECONDS" =~ ^[0-9]+$ && "$TIMEOUT_SECONDS" -gt 0 ]] || fail "isolated_home_sqlite" "harness" "invalid_timeout"
}

terminate_owned_app() {
  if [[ -n "$app_pid" && -n "$app_identity" ]]; then
    ax_terminate_owned_process "$app_pid" "$APP_BINARY" "$app_identity"
  fi
  app_launch_pid=""; app_pid=""; app_identity=""
}

launch_owned_app() {
  local destination="$1" selected_task_id="${2:-}" open_voice="$3"
  terminate_owned_app
  /usr/bin/env -i \
    PATH="$PATH" \
    HOME="$RUNTIME_HOME" \
    CFFIXED_USER_HOME="$RUNTIME_HOME" \
    SUISUI_DISABLE_KEYCHAIN_SECRET_STORE=1 \
    SUISUI_DATABASE_PATH="$DATABASE_PATH" \
    SUISUI_APP_SETTINGS_SUITE_NAME="$BUNDLE_IDENTIFIER.p18-338" \
    SUISUI_PROJECT_BOARD_SELECTED_DESTINATION="$destination" \
    SUISUI_PROJECT_BOARD_SELECTED_TASK_ID="$selected_task_id" \
    SUISUI_OPEN_VOICE_COMMAND_ON_LAUNCH="$open_voice" \
    "$APP_BINARY" -ApplePersistenceIgnoreState YES &
  app_launch_pid=$!
  app_pid="$(ax_wait_for_owned_app_pid "$app_launch_pid" "$APP_BINARY" "$TIMEOUT_SECONDS")" || return 1
  app_identity="$(ax_wait_for_owned_process_identity "$app_pid" "$APP_BINARY" 3)" || return 1
  ax_wait_for_pid_owned_process "$APP_NAME" "$app_pid" "$TIMEOUT_SECONDS" "$APP_BINARY"
}

wait_for_table() {
  local table="$1" deadline=$((SECONDS + TIMEOUT_SECONDS))
  while true; do
    if [[ -f "$DATABASE_PATH" ]] && "$SQLITE3" "$DATABASE_PATH" "SELECT name FROM sqlite_master WHERE type='table' AND name='$table';" | grep -Fxq "$table"; then
      return 0
    fi
    [[ "$SECONDS" -lt "$deadline" ]] || return 1
    sleep 1
  done
}

wait_for_marker() {
  local identifier text_marker probe
  identifier="$1"
  text_marker="${2:-}"
  probe="$WITNESS_DIR/.ax-$identifier"
  if ! ax_wait_for_ax_identifier "$APP_NAME" "$identifier" "$TIMEOUT_SECONDS" "$ROOT_DIR" "$probe" "$text_marker" "$app_pid"; then
    return 1
  fi
}

ax_set_text() {
  local identifier="$1" value="$2"
  ax_process_matches_identity "$app_pid" "$APP_BINARY" "$app_identity" || return 1
  /usr/bin/osascript - "$app_pid" "$identifier" "$value" <<'APPLESCRIPT' >/dev/null
on setMatchingIdentifier(uiElement, targetIdentifier, replacement)
  tell application "System Events"
    set identifierValue to ""
    try
      set identifierValue to value of attribute "AXIdentifier" of uiElement as text
    end try
    if identifierValue is targetIdentifier then
      set value of uiElement to replacement
      return true
    end if
    try
      repeat with childElement in UI elements of uiElement
        if my setMatchingIdentifier(childElement, targetIdentifier, replacement) then return true
      end repeat
    end try
  end tell
  return false
end setMatchingIdentifier

on run argv
  set appPID to (item 1 of argv) as integer
  set requestedIdentifier to item 2 of argv
  set replacement to item 3 of argv
  tell application "System Events"
    set matchingProcesses to application processes whose unix id is appPID
    if (count of matchingProcesses) is 0 then error "owned process missing"
    set targetProcess to item 1 of matchingProcesses
    tell targetProcess
      set frontmost to true
      repeat with currentWindow in windows
        try
          perform action "AXRaise" of currentWindow
        end try
        if my setMatchingIdentifier(currentWindow, requestedIdentifier, replacement) then return
      end repeat
    end tell
  end tell
  error "AX text input missing"
end run
APPLESCRIPT
}

ax_press() {
  local identifier="$1"
  ax_process_matches_identity "$app_pid" "$APP_BINARY" "$app_identity" || return 1
  /usr/bin/osascript - "$app_pid" "$identifier" <<'APPLESCRIPT' >/dev/null
on pressMatchingIdentifier(uiElement, targetIdentifier)
  tell application "System Events"
    set identifierValue to ""
    try
      set identifierValue to value of attribute "AXIdentifier" of uiElement as text
    end try
    if identifierValue is targetIdentifier then
      try
        perform action "AXPress" of uiElement
        return true
      end try
      try
        click uiElement
        return true
      end try
      return false
    end if
    try
      repeat with childElement in UI elements of uiElement
        if my pressMatchingIdentifier(childElement, targetIdentifier) then return true
      end repeat
    end try
  end tell
  return false
end pressMatchingIdentifier

on run argv
  set appPID to (item 1 of argv) as integer
  set requestedIdentifier to item 2 of argv
  tell application "System Events"
    set matchingProcesses to application processes whose unix id is appPID
    if (count of matchingProcesses) is 0 then error "owned process missing"
    set targetProcess to item 1 of matchingProcesses
    tell targetProcess
      set frontmost to true
      repeat with currentWindow in windows
        try
          perform action "AXRaise" of currentWindow
        end try
        if my pressMatchingIdentifier(currentWindow, requestedIdentifier) then return
      end repeat
    end tell
  end tell
  error "AX button missing"
end run
APPLESCRIPT
}

task_digest() {
  "$SQLITE3" -readonly -noheader "$DATABASE_PATH" "SELECT id || '|' || project_id || '|' || title || '|' || status || '|' || COALESCE(due_at,'') || '|' || COALESCE(priority,'') FROM tasks WHERE id IN ($TASK_ONE_ID,$TASK_TWO_ID) ORDER BY id;" | /usr/bin/shasum -a 256 | awk '{print $1}'
}

seed_fixture() {
  "$SQLITE3" "$DATABASE_PATH" <<SQL
PRAGMA foreign_keys=ON;
BEGIN IMMEDIATE;
INSERT OR REPLACE INTO projects (id,title,status,priority,tags_json,source_command) VALUES ($PROJECT_ID,'$PROJECT_TITLE','active','high','[]','p18-338');
INSERT OR REPLACE INTO tasks (id,project_id,title,status,due_at,priority,source_command) VALUES ($TASK_ONE_ID,$PROJECT_ID,'$TASK_ONE_TITLE','backlog',NULL,'medium','p18-338');
INSERT OR REPLACE INTO tasks (id,project_id,title,status,due_at,priority,source_command) VALUES ($TASK_TWO_ID,$PROJECT_ID,'$TASK_TWO_TITLE','backlog',NULL,'medium','p18-338');
COMMIT;
SQL
  baseline_task_digest="$(task_digest)"
  [[ -n "$baseline_task_digest" ]] || return 1
}

wait_for_queue_state() {
  local expected="$1" deadline=$((SECONDS + TIMEOUT_SECONDS))
  while true; do
    local state
    state="$("$SQLITE3" -readonly -noheader "$DATABASE_PATH" "SELECT state FROM assistant_queue_items WHERE id='$queue_item_id';" 2>/dev/null | tail -n 1)"
    [[ "$state" == "$expected" ]] && return 0
    [[ "$SECONDS" -lt "$deadline" ]] || return 1
    sleep 1
  done
}

assert_session_scope() {
  local stage="$1" scoped_session_count
  scoped_session_count="$("$SQLITE3" -readonly -noheader "$DATABASE_PATH" "SELECT count(*) FROM voice_task_conversation_sessions WHERE id='$session_id' AND active_project_id=$PROJECT_ID AND active_task_id=$TASK_TWO_ID;" | tr -d '\r')"
  [[ "$scoped_session_count" == "1" ]] || fail "$stage" "scope" "conversation_scope_not_persisted"
}

assert_linked_execution_receipt() {
  local execution_receipt_id receipt_directory receipt_filename receipt_file receipt_file_id
  execution_receipt_id="$("$SQLITE3" -readonly -noheader "$DATABASE_PATH" "SELECT execution_receipt_id FROM conversation_action_links WHERE session_id='$session_id' AND assistant_queue_item_id='$queue_item_id' AND execution_receipt_id IS NOT NULL AND length(trim(execution_receipt_id)) > 0 ORDER BY created_at DESC LIMIT 1;" | tr -d '\r')"
  [[ -n "$execution_receipt_id" ]] || return 1

  # Match the store's safe filename contract, then verify the receipt JSON's
  # own id. This binds the Action Link to the executed receipt rather than an
  # unrelated JSON file in the isolated Application Support directory.
  receipt_directory="$RUNTIME_HOME/Library/Application Support/$APP_NAME/ExecutionReceipts"
  receipt_filename="$(printf '%s' "$execution_receipt_id" | /usr/bin/sed -E 's/[^[:alnum:]_-]/-/g').json"
  receipt_file="$receipt_directory/$receipt_filename"
  [[ -f "$receipt_file" ]] || return 1
  receipt_file_id="$(/usr/bin/plutil -extract id raw -o - "$receipt_file" 2>/dev/null || true)"
  [[ "$receipt_file_id" == "$execution_receipt_id" ]]
}

run_all() {
  require_prerequisites
  mkdir -p "$WITNESS_DIR"

  # First owned launch creates exactly the migrations used by normal product code.
  launch_owned_app "projects" "" "0" || fail "isolated_home_sqlite" "launch" "migration_launch_failed"
  wait_for_table "tasks" || fail "isolated_home_sqlite" "sqlite" "migrations_missing"
  wait_for_table "assistant_queue_items" || fail "isolated_home_sqlite" "sqlite" "queue_schema_missing"
  write_witness "isolated_home_sqlite" "database_isolated=true" "home_isolated=true"
  terminate_owned_app
  seed_fixture || fail "fixed_fixture_seed" "sqlite" "fixed_numeric_seed_failed"
  write_witness "fixed_fixture_seed" "fixture_project_id=$PROJECT_ID" "fixture_project_title=$PROJECT_TITLE" "fixture_task_one_id=$TASK_ONE_ID" "fixture_task_one_title=$TASK_ONE_TITLE" "fixture_task_two_id=$TASK_TWO_ID" "fixture_task_two_title=$TASK_TWO_TITLE"

  # Do not use the evidence-only direct Voice window: it bypasses ScopeBridge.
  # The toolbar action is the normal Project Board route and carries the
  # selected project/task into the persisted conversation session.
  launch_owned_app "project:$PROJECT_ID" "$TASK_TWO_ID" "0" || fail "normal_product_route" "launch" "normal_route_launch_failed"
  wait_for_marker "project-board-detail" || fail "normal_product_route" "ax" "project_board_marker_missing"
  ax_press "project-board-voice-command" || fail "normal_product_route" "ax" "voice_command_control_missing"
  wait_for_marker "voice-conversation-workspace" || fail "normal_product_route" "ax" "voice_workspace_marker_missing"
  write_witness "normal_product_route" "project_board_ax=visible" "voice_command_ax=visible"
  session_id="$("$SQLITE3" -readonly -noheader "$DATABASE_PATH" "SELECT id FROM voice_task_conversation_sessions ORDER BY updated_at DESC LIMIT 1;" | tr -d '\r')"
  [[ -n "$session_id" ]] || fail "session_start" "conversation" "session_not_persisted"
  assert_session_scope "session_start"
  write_witness "session_start" "session_started=true" "session_scope=project_and_task"

  ax_set_text "voice-conversation-input" "$COMMAND_LIST" || fail "task_list" "ax" "conversation_input_missing"
  ax_press "voice-conversation-send-review" || fail "task_list" "ax" "conversation_send_missing"
  wait_for_marker "voice-conversation-turn-list" "$TASK_TWO_TITLE" || fail "task_list" "plan" "deterministic_task_list_missing"
  write_witness "task_list" "listed_task_ids=$TASK_ONE_ID,$TASK_TWO_ID"

  ax_set_text "voice-conversation-input" "$COMMAND_UPDATE" || fail "reference_selection" "ax" "conversation_input_missing"
  ax_press "voice-conversation-send-review" || fail "reference_selection" "ax" "conversation_send_missing"
  wait_for_marker "voice-conversation-clarification" || fail "clarification" "plan" "date_clarification_missing"
  write_witness "reference_selection" "selected_task_id=$TASK_TWO_ID"
  ax_set_text "voice-conversation-input" "$DUE_DATE" || fail "clarification" "ax" "clarification_input_missing"
  ax_press "voice-conversation-submit-clarification" || fail "clarification" "ax" "clarification_submit_missing"
  write_witness "clarification" "clarification_count=1"
  wait_for_marker "voice-conversation-proposal" || fail "proposal" "plan" "proposal_missing"
  wait_for_marker "voice-conversation-queue-handoff" || fail "proposal" "plan" "review_queue_handoff_missing"
  write_witness "proposal" "proposal_due_date=$DUE_DATE" "proposal_priority=high"

  [[ "$(task_digest)" == "$baseline_task_digest" ]] || fail "pre_approval_snapshot" "pre-approval" "task_mutated_before_approval"
  printf '%s database\n' "$baseline_task_digest" >"$SNAPSHOT_FILE"
  write_witness "pre_approval_snapshot" "database_mutated=false"

  queue_item_id="$("$SQLITE3" -readonly -noheader "$DATABASE_PATH" "SELECT id FROM assistant_queue_items WHERE state='waitingReview' ORDER BY updated_at DESC LIMIT 1;" | tr -d '\r')"
  [[ -n "$queue_item_id" ]] || fail "queue_approval_execution" "queue" "review_queue_item_missing"
  ax_press "voice-conversation-open-assistant-queue" || fail "queue_approval_execution" "ax" "queue_handoff_control_missing"
  wait_for_marker "assistant-queue-workflow" || fail "queue_approval_execution" "ax" "queue_board_marker_missing"
  ax_press "assistant-queue-approve-$queue_item_id" || fail "queue_approval_execution" "ax" "queue_approve_missing"
  wait_for_queue_state "approved" || fail "queue_approval_execution" "queue" "queue_approval_not_persisted"
  ax_press "assistant-queue-run-$queue_item_id" || fail "queue_approval_execution" "ax" "queue_run_missing"
  wait_for_queue_state "done" || fail "queue_approval_execution" "execution" "queue_execution_not_done"
  write_witness "queue_approval_execution" "queue_reviewed=true" "queue_approved=true" "queue_executed=true"

  task_post="$("$SQLITE3" -readonly -noheader "$DATABASE_PATH" "SELECT CASE WHEN due_at='$DUE_DATE' AND priority='high' THEN 'passed' ELSE 'failed' END FROM tasks WHERE id=$TASK_TWO_ID;" | tr -d '\r')"
  [[ "$task_post" == "passed" ]] || fail "postcondition_receipt_action_link" "postcondition" "task_update_missing"
  assert_linked_execution_receipt || fail "postcondition_receipt_action_link" "receipt" "linked_execution_receipt_missing"
  write_witness "postcondition_receipt_action_link" "task_postcondition=passed" "receipt_link=present" "action_link=present"

  terminate_owned_app
  launch_owned_app "project:$PROJECT_ID" "$TASK_TWO_ID" "0" || fail "restart" "launch" "owned_restart_failed"
  wait_for_marker "project-board-detail" || fail "restart" "ax" "project_board_marker_missing"
  ax_press "project-board-voice-command" || fail "restart" "ax" "voice_command_control_missing"
  wait_for_marker "voice-conversation-workspace" || fail "restart" "window" "voice_workspace_not_restored"
  write_witness "restart" "app_restarted=true"
  resumed="$("$SQLITE3" -readonly -noheader "$DATABASE_PATH" "SELECT count(*) FROM voice_task_conversation_sessions WHERE id='$session_id';" | tr -d '\r')"
  [[ "$resumed" == "1" ]] || fail "resume" "conversation" "session_changed_after_restart"
  assert_session_scope "resume"
  wait_for_marker "voice-conversation-workspace" || fail "resume" "ax" "conversation_workspace_missing"
  write_witness \
    "resume" \
    "session_resumed=true" \
    "resume_project_scope=$PROJECT_ID" \
    "resume_task_scope=$TASK_TWO_ID" \
    "resume_action_link=present"
}

[[ $# -eq 1 && "$1" == "--run-all" ]] || { usage; exit 2; }
run_all
