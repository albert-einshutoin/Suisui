#!/usr/bin/env bash
# Drives the real, distributed Suisui app for the #617 core value loop evidence lane.
# It owns only the process it launches and emits redacted, machine-readable
# witnesses. A missing product capability is a failure, never a simulated pass.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/packaging/app_metadata.env"
source "$ROOT_DIR/script/ui_accessibility_smoke_helpers.sh"

APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
SQLITE3="${SQLITE3:-/usr/bin/sqlite3}"
DATABASE_PATH="${SUISUI_DATABASE_PATH:?SUISUI_DATABASE_PATH is required}"
RUNTIME_HOME="${HOME:?isolated HOME is required}"
WITNESS_DIR="${SUISUI_VOICE_TASK_CONTINUITY_WITNESS_DIR:?witness directory is required}"
SNAPSHOT_FILE="${SUISUI_VOICE_TASK_CONTINUITY_PRE_APPROVAL_SNAPSHOT:?snapshot path is required}"
SOURCE_COMMIT="${SUISUI_VOICE_TASK_CONTINUITY_SOURCE_COMMIT:?source commit is required}"
EXPECTED_APP_BINARY_SHA256="${SUISUI_VOICE_TASK_CONTINUITY_APP_BINARY_SHA256:?app binary SHA-256 is required}"
FIXTURE_MANIFEST="${SUISUI_VOICE_TASK_CONTINUITY_FIXTURE_MANIFEST:?fixture manifest is required}"
TIMEOUT_SECONDS="${SUISUI_VOICE_TASK_CONTINUITY_TIMEOUT_SECONDS:-35}"
LOCALE="${SUISUI_VOICE_TASK_CONTINUITY_LOCALE:-english}"
WINDOW_WIDTH="${SUISUI_VOICE_TASK_CONTINUITY_WINDOW_WIDTH:-960}"
WINDOW_HEIGHT="${SUISUI_VOICE_TASK_CONTINUITY_WINDOW_HEIGHT:-572}"

PROJECT_ID=1833801
TASK_ONE_ID=1833811
TASK_TWO_ID=1833812
PROJECT_TITLE="P17 617 Core Value Loop"
TASK_ONE_TITLE="P17 617 prepare review"
TASK_TWO_TITLE="P17 617 submit summary"
DUE_DATE="2031-03-08"
COMMAND_LIST="List tasks"
COMMAND_UPDATE="Update the second task due date and priority high"

app_launch_pid=""
app_pid=""
app_identity=""
baseline_task_digest=""
session_id=""
queue_item_id=""
action_link_id=""
execution_receipt_id=""
source_turn_id=""
action_plan_id=""
relation_count=""
route_transition_count=0
window_size=""

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
    printf 'app_binary_sha256=%s\n' "$EXPECTED_APP_BINARY_SHA256"
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
  [[ "$WINDOW_WIDTH" =~ ^[0-9]+$ && "$WINDOW_WIDTH" -ge 960 ]] || fail "normal_product_route" "window" "invalid_window_width"
  [[ "$WINDOW_HEIGHT" =~ ^[0-9]+$ && "$WINDOW_HEIGHT" -ge 572 ]] || fail "normal_product_route" "window" "invalid_window_height"
  [[ "$LOCALE" == "english" || "$LOCALE" == "japanese" ]] || fail "normal_product_route" "localization" "unsupported_locale"
  command -v jq >/dev/null 2>&1 || fail "redacted_source_bound_artifact" "evidence" "jq_unavailable"
  [[ "$EXPECTED_APP_BINARY_SHA256" =~ ^[a-f0-9]{64}$ ]] || fail "normal_product_route" "provenance" "expected_app_binary_hash_invalid"
  assert_app_binary_provenance || fail "normal_product_route" "provenance" "app_binary_hash_mismatch"
}

assert_app_binary_provenance() {
  local actual_app_binary_sha256
  actual_app_binary_sha256="$(/usr/bin/shasum -a 256 "$APP_BINARY" | awk '{print $1}')" || return 1
  [[ "$actual_app_binary_sha256" == "$EXPECTED_APP_BINARY_SHA256" ]]
}

terminate_owned_app() {
  if [[ -n "$app_pid" && -n "$app_identity" ]]; then
    ax_terminate_owned_process "$app_pid" "$APP_BINARY" "$app_identity"
  fi
  app_launch_pid=""; app_pid=""; app_identity=""
}

launch_owned_app() {
  local destination="$1" selected_task_id="${2:-}" open_voice="$3"
  local apple_languages apple_locale
  case "$LOCALE" in
    english) apple_languages='(en)'; apple_locale=en_US ;;
    japanese) apple_languages='(ja)'; apple_locale=ja_JP ;;
  esac
  terminate_owned_app
  assert_app_binary_provenance || return 1
  /usr/bin/env -i \
    PATH="$PATH" \
    HOME="$RUNTIME_HOME" \
    CFFIXED_USER_HOME="$RUNTIME_HOME" \
    SUISUI_DISABLE_KEYCHAIN_SECRET_STORE=1 \
    SUISUI_DATABASE_PATH="$DATABASE_PATH" \
    SUISUI_APP_SETTINGS_SUITE_NAME="$BUNDLE_IDENTIFIER.issue-617.$LOCALE" \
    SUISUI_LANGUAGE_PREFERENCE="$LOCALE" \
    SUISUI_PROJECT_BOARD_SELECTED_DESTINATION="$destination" \
    SUISUI_PROJECT_BOARD_SELECTED_TASK_ID="$selected_task_id" \
    SUISUI_OPEN_VOICE_COMMAND_ON_LAUNCH="$open_voice" \
    "$APP_BINARY" -ApplePersistenceIgnoreState YES -AppleLanguages "$apple_languages" -AppleLocale "$apple_locale" &
  app_launch_pid=$!
  app_pid="$(ax_wait_for_owned_app_pid "$app_launch_pid" "$APP_BINARY" "$TIMEOUT_SECONDS")" || return 1
  app_identity="$(ax_wait_for_owned_process_identity "$app_pid" "$APP_BINARY" 3)" || return 1
  assert_app_binary_provenance || return 1
  ax_wait_for_pid_owned_process "$APP_NAME" "$app_pid" "$TIMEOUT_SECONDS" "$APP_BINARY" || return 1
  resize_owned_window || return 1
}

resize_owned_window() {
  local observed
  ax_process_matches_identity "$app_pid" "$APP_BINARY" "$app_identity" || return 1
  ax_wait_for_pid_owned_window "$APP_NAME" "$app_pid" "" "$TIMEOUT_SECONDS" "" "$APP_BINARY" >/dev/null || return 1
  observed="$({
    /usr/bin/osascript - "$app_pid" "$WINDOW_WIDTH" "$WINDOW_HEIGHT" <<'APPLESCRIPT'
on run argv
  set appPID to (item 1 of argv) as integer
  set targetWidth to (item 2 of argv) as integer
  set targetHeight to (item 3 of argv) as integer
  tell application "System Events"
    set matchingProcesses to application processes whose unix id is appPID
    if (count of matchingProcesses) is 0 then error "pid-owned process missing"
    set targetProcess to item 1 of matchingProcesses
    tell targetProcess
      if (count of windows) is 0 then error "window missing"
      set frontmost to true
      set size of window 1 to {targetWidth, targetHeight}
      set currentSize to size of window 1
      return ((item 1 of currentSize) as text) & "x" & ((item 2 of currentSize) as text)
    end tell
  end tell
end run
APPLESCRIPT
  } 2>/dev/null)" || return 1
  [[ "$observed" =~ ^[0-9]+x[0-9]+$ ]] || return 1
  [[ "${observed%%x*}" -ge "$WINDOW_WIDTH" && "${observed##*x}" -ge "$WINDOW_HEIGHT" ]] || return 1
  window_size="$observed"
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
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while true; do
    ax_process_matches_identity "$app_pid" "$APP_BINARY" "$app_identity" || return 1
    if /usr/bin/swift \
      "$ROOT_DIR/script/ui_evidence_ax_text_input.swift" \
      "$app_pid" \
      "$identifier" \
      "$value" \
      >/dev/null 2>&1; then
      return 0
    fi
    [[ "$SECONDS" -lt "$deadline" ]] || return 1
    sleep 0.5
  done
}

ax_press() {
  local identifier="$1"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while true; do
    ax_process_matches_identity "$app_pid" "$APP_BINARY" "$app_identity" || return 1
    if /usr/bin/swift \
      "$ROOT_DIR/script/ui_evidence_ax_press_element.swift" \
      "$app_pid" \
      "$identifier" \
      >/dev/null 2>&1; then
      return 0
    fi
    [[ "$SECONDS" -lt "$deadline" ]] || return 1
    sleep 0.5
  done
}

task_digest() {
  "$SQLITE3" -readonly -noheader "$DATABASE_PATH" "SELECT id || '|' || project_id || '|' || title || '|' || status || '|' || COALESCE(due_at,'') || '|' || COALESCE(priority,'') FROM tasks WHERE id IN ($TASK_ONE_ID,$TASK_TWO_ID) ORDER BY id;" | /usr/bin/shasum -a 256 | awk '{print $1}'
}

seed_fixture() {
  "$SQLITE3" "$DATABASE_PATH" <<SQL
PRAGMA foreign_keys=ON;
BEGIN IMMEDIATE;
INSERT OR REPLACE INTO projects (id,title,status,priority,tags_json,source_command) VALUES ($PROJECT_ID,'$PROJECT_TITLE','active','high','[]','issue-617');
INSERT OR REPLACE INTO tasks (id,project_id,title,status,due_at,priority,source_command) VALUES ($TASK_ONE_ID,$PROJECT_ID,'$TASK_ONE_TITLE','backlog',NULL,'medium','issue-617');
INSERT OR REPLACE INTO tasks (id,project_id,title,status,due_at,priority,source_command) VALUES ($TASK_TWO_ID,$PROJECT_ID,'$TASK_TWO_TITLE','backlog',NULL,'medium','issue-617');
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

assert_receipt_file_id() {
  local expected_receipt_id="$1"
  local receipt_directory receipt_filename receipt_file receipt_file_id

  receipt_directory="$RUNTIME_HOME/Library/Application Support/$APP_NAME/ExecutionReceipts"
  receipt_filename="$(printf '%s' "$expected_receipt_id" | /usr/bin/sed -E 's/[^[:alnum:]_-]/-/g').json"
  receipt_file="$receipt_directory/$receipt_filename"
  [[ -f "$receipt_file" ]] || return 1
  receipt_file_id="$(/usr/bin/plutil -extract id raw -o - "$receipt_file" 2>/dev/null || true)"
  [[ "$receipt_file_id" == "$expected_receipt_id" ]]
}

assert_linked_execution_receipt() {
  action_link_id="$("$SQLITE3" -readonly -noheader "$DATABASE_PATH" "SELECT id FROM conversation_action_links WHERE session_id='$session_id' AND assistant_queue_item_id='$queue_item_id' AND execution_receipt_id IS NOT NULL AND length(trim(execution_receipt_id)) > 0 ORDER BY created_at DESC LIMIT 1;" | tr -d '\r')"
  source_turn_id="$("$SQLITE3" -readonly -noheader "$DATABASE_PATH" "SELECT source_turn_id FROM conversation_action_links WHERE id='$action_link_id' AND session_id='$session_id' AND assistant_queue_item_id='$queue_item_id';" | tr -d '\r')"
  action_plan_id="$("$SQLITE3" -readonly -noheader "$DATABASE_PATH" "SELECT action_plan_id FROM conversation_action_links WHERE id='$action_link_id' AND session_id='$session_id' AND assistant_queue_item_id='$queue_item_id';" | tr -d '\r')"
  relation_count="$("$SQLITE3" -readonly -noheader "$DATABASE_PATH" "SELECT count(*) FROM conversation_action_links WHERE id='$action_link_id' AND session_id='$session_id' AND source_turn_id='$source_turn_id' AND action_plan_id='$action_plan_id' AND assistant_queue_item_id='$queue_item_id' AND execution_receipt_id IS NOT NULL AND length(trim(execution_receipt_id)) > 0;" | tr -d '\r')"
  execution_receipt_id="$("$SQLITE3" -readonly -noheader "$DATABASE_PATH" "SELECT execution_receipt_id FROM conversation_action_links WHERE session_id='$session_id' AND assistant_queue_item_id='$queue_item_id' AND execution_receipt_id IS NOT NULL AND length(trim(execution_receipt_id)) > 0 ORDER BY created_at DESC LIMIT 1;" | tr -d '\r')"
  [[ -n "$action_link_id" && -n "$source_turn_id" && -n "$action_plan_id" && "$relation_count" == "1" && -n "$execution_receipt_id" ]] || return 1
  assert_receipt_file_id "$execution_receipt_id"
}

prepare_measurement_defaults() {
  HOME="$RUNTIME_HOME" CFFIXED_USER_HOME="$RUNTIME_HOME" \
    /usr/bin/defaults write "$BUNDLE_IDENTIFIER" suisui.publicAlphaMeasurementEnabled -bool true
  HOME="$RUNTIME_HOME" CFFIXED_USER_HOME="$RUNTIME_HOME" \
    /usr/bin/defaults write "$BUNDLE_IDENTIFIER" suisui.publicAlphaParticipantSeed -string "issue-617-runtime"
}

assert_measurement_ledger() {
  local ledger_file="$RUNTIME_HOME/Library/Application Support/$APP_NAME/PublicAlphaValidation/ledger.json"
  local required_stages actual_external_writes actual_transcript_rows
  [[ -f "$ledger_file" ]] || return 1
  jq -e --arg source "$SOURCE_COMMIT" '
    [.stageEvents[] | select(.mark == "completed" and .build.sourceCommit == $source)]
    | group_by(.workReference)
    | any(.[]; .[0].workReference != null and
        ([.[].stage] | unique | contains([
          "first_capture", "reviewable_action_plan", "approved_local_action",
          "local_execution", "result_displayed"
        ])))
  ' "$ledger_file" >/dev/null || return 1
  required_stages="$(jq -r '[.stageEvents[] | select(.mark == "completed") | .stage] | unique | sort | join(",")' "$ledger_file")"
  actual_external_writes="$("$SQLITE3" -readonly -noheader "$DATABASE_PATH" "SELECT count(*) FROM external_side_effect_journal WHERE state IN ('started','succeeded','unknown');" | tr -d '\r')"
  actual_transcript_rows="$("$SQLITE3" -readonly -noheader "$DATABASE_PATH" "SELECT count(*) FROM voice_task_conversation_turns WHERE session_id='$session_id' AND raw_transcript IS NOT NULL AND length(trim(raw_transcript)) > 0;" | tr -d '\r')"
  [[ "$actual_external_writes" =~ ^[0-9]+$ && "$actual_transcript_rows" =~ ^[0-9]+$ ]] || return 1
  write_witness \
    "measurement" \
    "same_work_id=true" \
    "candidate_build_matches_source=true" \
    "candidate_result_matches_source=true" \
    "candidate_stage_count=$required_stages" \
    "external_write_count=$actual_external_writes" \
    "transcript_row_count=$actual_transcript_rows" \
    "screen_transition_count=$route_transition_count" \
    "input_proposal_queue_result_receipt=present"
}

assert_restored_action_link() {
  local restored_action_link_id restored_execution_receipt_id
  restored_action_link_id="$("$SQLITE3" -readonly -noheader "$DATABASE_PATH" "SELECT id FROM conversation_action_links WHERE session_id='$session_id' AND assistant_queue_item_id='$queue_item_id' ORDER BY created_at DESC LIMIT 1;" | tr -d '\r')"
  restored_execution_receipt_id="$("$SQLITE3" -readonly -noheader "$DATABASE_PATH" "SELECT execution_receipt_id FROM conversation_action_links WHERE id='$restored_action_link_id' AND session_id='$session_id' AND assistant_queue_item_id='$queue_item_id';" | tr -d '\r')"
  [[ "$restored_action_link_id" == "$action_link_id" ]] || return 1
  [[ "$restored_execution_receipt_id" == "$execution_receipt_id" ]] || return 1
  assert_receipt_file_id "$restored_execution_receipt_id"
}

run_all() {
  require_prerequisites
  mkdir -p "$WITNESS_DIR"
  prepare_measurement_defaults

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
  ax_press "sidebar-destination-secretary" || fail "normal_product_route" "ax" "secretary_control_missing"
  wait_for_marker "voice-conversation-workspace" || fail "normal_product_route" "ax" "voice_workspace_marker_missing"
  write_witness "normal_product_route" "project_board_ax=visible" "voice_command_ax=visible" "locale=$LOCALE" "window_size=$window_size"
  session_id="$("$SQLITE3" -readonly -noheader "$DATABASE_PATH" "SELECT id FROM voice_task_conversation_sessions ORDER BY updated_at DESC LIMIT 1;" | tr -d '\r')"
  [[ -n "$session_id" ]] || fail "session_start" "conversation" "session_not_persisted"
  assert_session_scope "session_start"
  write_witness "session_start" "session_started=true" "session_scope=project_and_task"

  ax_set_text "voice-conversation-input" "$COMMAND_LIST" || fail "task_list" "ax" "conversation_input_missing"
  ax_press "voice-conversation-send-review" || fail "task_list" "ax" "conversation_send_missing"
  wait_for_marker "voice-conversation-task-list-answer" "$TASK_TWO_TITLE" || fail "task_list" "plan" "deterministic_task_list_missing"
  write_witness "task_list" "listed_task_ids=$TASK_ONE_ID,$TASK_TWO_ID"

  ax_set_text "voice-conversation-input" "$COMMAND_UPDATE" || fail "reference_selection" "ax" "conversation_input_missing"
  ax_press "voice-conversation-send-review" || fail "reference_selection" "ax" "conversation_send_missing"
  wait_for_marker "voice-conversation-clarification" || fail "clarification" "plan" "date_clarification_missing"
  write_witness "reference_selection" "selected_task_id=$TASK_TWO_ID"
  ax_set_text "voice-conversation-input" "$DUE_DATE" || fail "clarification" "ax" "clarification_input_missing"
  ax_press "voice-conversation-submit-clarification" || fail "clarification" "ax" "clarification_submit_missing"
  write_witness "clarification" "clarification_count=1"
  ax_press "voice-conversation-understanding-disclosure" || fail "proposal" "ax" "understanding_disclosure_missing"
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
  # The Queue remains the canonical approval/execution surface after review.
  ax_press "assistant-queue-run-$queue_item_id" || fail "queue_approval_execution" "ax" "queue_run_missing"
  wait_for_queue_state "done" || fail "queue_approval_execution" "execution" "queue_execution_not_done"
  write_witness "queue_approval_execution" "queue_reviewed=true" "queue_approved=true" "queue_executed=true"

  task_post="$("$SQLITE3" -readonly -noheader "$DATABASE_PATH" "SELECT CASE WHEN due_at='$DUE_DATE' AND priority='high' THEN 'passed' ELSE 'failed' END FROM tasks WHERE id=$TASK_TWO_ID;" | tr -d '\r')"
  [[ "$task_post" == "passed" ]] || fail "postcondition_receipt_action_link" "postcondition" "task_update_missing"
  assert_linked_execution_receipt || fail "postcondition_receipt_action_link" "receipt" "linked_execution_receipt_missing"
  write_witness "postcondition_receipt_action_link" "task_postcondition=passed" "receipt_link=present" "action_link=present" "source_turn_id=$source_turn_id" "action_plan_id=$action_plan_id" "relation_count=$relation_count"

  route_transition_count=0
  ax_press "sidebar-destination-work" || fail "route_round_trip" "ax" "work_destination_missing"
  wait_for_marker "work-hub" || fail "route_round_trip" "ax" "work_destination_not_rendered"
  ((route_transition_count += 1))
  ax_press "sidebar-destination-schedule" || fail "route_round_trip" "ax" "schedule_destination_missing"
  wait_for_marker "schedule-workflow" || fail "route_round_trip" "ax" "schedule_destination_not_rendered"
  ((route_transition_count += 1))
  ax_press "sidebar-destination-secretary" || fail "route_round_trip" "ax" "secretary_destination_missing"
  wait_for_marker "voice-conversation-workspace" || fail "route_round_trip" "ax" "secretary_return_missing"
  ax_press "voice-conversation-understanding-disclosure" || fail "route_round_trip" "ax" "understanding_disclosure_missing"
  wait_for_marker "voice-conversation-proposal" || fail "route_round_trip" "conversation" "conversation_proposal_not_restored"
  wait_for_marker "voice-conversation-queue-handoff" || fail "route_round_trip" "conversation" "conversation_queue_not_restored"
  ((route_transition_count += 1))
  assert_session_scope "route_round_trip"
  assert_restored_action_link || fail "route_round_trip" "receipt" "action_link_changed"
  write_witness \
    "route_round_trip" \
    "route_transitions=$route_transition_count" \
    "same_session=true" \
    "proposal_preserved=true" \
    "queue_item_preserved=true"
  wait_for_marker "voice-conversation-receipt" "$execution_receipt_id" || fail "result_displayed" "ax" "receipt_marker_missing"
  write_witness \
    "result_displayed" \
    "result_receipt_ax=visible" \
    "result_status=done" \
    "receipt_id=$execution_receipt_id"
  assert_measurement_ledger || fail "measurement" "evidence" "measurement_ledger_mismatch"

  terminate_owned_app
  launch_owned_app "project:$PROJECT_ID" "$TASK_TWO_ID" "0" || fail "restart" "launch" "owned_restart_failed"
  wait_for_marker "project-board-detail" || fail "restart" "ax" "project_board_marker_missing"
  ax_press "sidebar-destination-secretary" || fail "restart" "ax" "secretary_control_missing"
  wait_for_marker "voice-conversation-workspace" || fail "restart" "window" "voice_workspace_not_restored"
  ax_press "voice-conversation-understanding-disclosure" || fail "restart" "ax" "understanding_disclosure_missing"
  wait_for_marker "voice-conversation-proposal" || fail "restart" "conversation" "proposal_not_restored"
  wait_for_marker "voice-conversation-receipt" "$execution_receipt_id" || fail "restart" "receipt" "receipt_not_restored"
  write_witness "restart" "app_restarted=true"
  local resumed resume_summary resume_summary_sha256
  resumed="$("$SQLITE3" -readonly -noheader "$DATABASE_PATH" "SELECT count(*) FROM voice_task_conversation_sessions WHERE id='$session_id';" | tr -d '\r')"
  [[ "$resumed" == "1" ]] || fail "resume" "conversation" "session_changed_after_restart"
  assert_session_scope "resume"
  assert_restored_action_link || fail "resume" "receipt" "restored_action_link_receipt_mismatch"
  resume_summary="$("$SQLITE3" -readonly -noheader "$DATABASE_PATH" "SELECT resume_summary FROM voice_task_conversation_sessions WHERE id='$session_id';" | tr -d '\r')"
  [[ -n "$resume_summary" && "$resume_summary" == *"$PROJECT_TITLE"* && "$resume_summary" == *"$TASK_TWO_TITLE"* ]] \
    || fail "resume" "conversation" "resume_summary_missing_scope"
  wait_for_marker "voice-conversation-workspace" || fail "resume" "ax" "conversation_workspace_missing"
  wait_for_marker "voice-conversation-scope" "$resume_summary" || fail "resume" "ax" "resume_summary_not_rendered"
  wait_for_marker "voice-conversation-receipt" "$execution_receipt_id" || fail "resume" "receipt" "receipt_not_rendered"
  resume_summary_sha256="$(printf '%s' "$resume_summary" | /usr/bin/shasum -a 256 | awk '{print $1}')"
  write_witness \
    "resume" \
    "session_resumed=true" \
    "resume_project_scope=$PROJECT_ID" \
    "resume_task_scope=$TASK_TWO_ID" \
    "resume_action_link_id=$action_link_id" \
    "resume_execution_receipt_id=$execution_receipt_id" \
    "resume_summary_sha256=$resume_summary_sha256"
}

[[ $# -eq 1 && "$1" == "--run-all" ]] || { usage; exit 2; }
run_all
