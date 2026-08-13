#!/usr/bin/env bash
# Runtime evidence for the normal, approval-gated voice-task conversation.
# No fallback may convert a missing Voice/AX route into a successful result.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METADATA_FILE="$ROOT_DIR/packaging/app_metadata.env"
ARTIFACT_ROOT="${SUISUI_VOICE_TASK_CONTINUITY_ARTIFACT_DIR:-$ROOT_DIR/.tmp/runtime-voice-task-continuity}"
DRIVER="${SUISUI_VOICE_TASK_CONTINUITY_DRIVER:-$ROOT_DIR/script/drive_runtime_voice_task_continuity.sh}"
KEEP_FIXTURE="${SUISUI_VOICE_TASK_CONTINUITY_KEEP_FIXTURE:-0}"
SQLITE3="${SQLITE3:-sqlite3}"

# Stable, non-user fixtures keep AX/SQLite evidence attributable to this run.
FIXTURE_PROJECT_ID="1833801"
FIXTURE_PROJECT_TITLE="P18 338 Voice Continuity"
FIXTURE_TASK_ONE_ID="1833811"
FIXTURE_TASK_TWO_ID="1833812"
FIXTURE_TASK_ONE_TITLE="P18 338 prepare review"
FIXTURE_TASK_TWO_TITLE="P18 338 submit summary"
FIXTURE_DUE_DATE="2031-03-08"

runtime_dir=""
runtime_home=""
database_path=""
fixture_manifest=""
witness_dir=""
pre_approval_snapshot=""
source_commit=""
app_binary=""
app_binary_sha256=""
build_configuration_fingerprint=""
completed_stages=()
driver_has_run=0

usage() {
  printf '%s\n' "usage: $0" >&2
  printf '%s\n' "uses the bundled normal-product driver unless SUISUI_VOICE_TASK_CONTINUITY_DRIVER overrides it" >&2
}

repo_relative_path() {
  local value="$1"
  case "$value" in
    "$ROOT_DIR"/*) printf '%s' "${value#"$ROOT_DIR/"}" ;;
    *) printf '%s' "isolated-runtime-fixture" ;;
  esac
}

contains_rejected_evidence() {
  local file="$1"
  # A tracked artifact must never contain a raw transcript, credential-shaped
  # value, or a user's absolute home path.
  grep -Eq '(/Users/|/home/|sk-[[:alnum:]_-]{8,}|AIza[[:alnum:]_-]{12,}|raw[ _-]?transcript|audio[ _-]?transcript)' "$file"
}

write_artifact_atomically() {
  local status="$1" stage="$2" layer="$3" reason="$4"
  local artifact_dir="$ARTIFACT_ROOT"
  local temporary_file artifact_file index
  mkdir -p "$artifact_dir"
  temporary_file="$(mktemp "$artifact_dir/.voice-task-continuity.XXXXXX")"
  artifact_file="$artifact_dir/voice-task-continuity.json"

  # Never serialize driver output: it may include AX labels or a spoken request.
  {
    printf '{\n'
    printf '  "scenario": "voice_task_continuity",\n'
    printf '  "status": "%s",\n' "$status"
    printf '  "sourceCommit": "%s",\n' "$source_commit"
    printf '  "appBinarySHA256": "%s",\n' "$app_binary_sha256"
    printf '  "buildConfigurationFingerprint": "%s",\n' "$build_configuration_fingerprint"
    printf '  "fixture": {"projectID": "%s", "taskIDs": ["%s", "%s"]},\n' "$FIXTURE_PROJECT_ID" "$FIXTURE_TASK_ONE_ID" "$FIXTURE_TASK_TWO_ID"
    printf '  "completedStages": ['
    for index in "${!completed_stages[@]}"; do
      [[ "$index" -gt 0 ]] && printf ', '
      printf '"%s"' "${completed_stages[$index]}"
    done
    printf '],\n'
    printf '  "failure": {"stage": "%s", "layer": "%s", "reason": "%s"},\n' "$stage" "$layer" "$reason"
    printf '  "manualVoiceOver": "not-run"\n'
    printf '}\n'
  } >"$temporary_file"

  if contains_rejected_evidence "$temporary_file"; then
    rm -f "$temporary_file"
    echo "BLOCKER: evidence-security: artifact contained rejected data" >&2
    return 1
  fi
  mv -f "$temporary_file" "$artifact_file"
}

fail_stage() {
  local stage="$1" layer="$2" reason="$3"
  write_artifact_atomically "failed" "$stage" "$layer" "$reason" || true
  printf 'BLOCKER: voice_task_continuity stage=%s layer=%s reason=%s\n' "$stage" "$layer" "$reason" >&2
  exit 1
}

cleanup() {
  if [[ -n "$runtime_dir" && "$KEEP_FIXTURE" != "1" ]]; then
    rm -rf "$runtime_dir"
  fi
}
trap cleanup EXIT

require_runtime_prerequisites() {
  [[ -f "$METADATA_FILE" ]] || fail_stage "isolated_home_sqlite" "launch" "metadata_missing"
  [[ -x "$DRIVER" ]] || fail_stage "normal_product_route" "runtime-integration" "normal_product_driver_unavailable"
  command -v "$SQLITE3" >/dev/null 2>&1 || fail_stage "isolated_home_sqlite" "sqlite" "sqlite3_unavailable"
  command -v git >/dev/null 2>&1 || fail_stage "redacted_source_bound_artifact" "evidence" "git_unavailable"
  command -v /usr/bin/shasum >/dev/null 2>&1 || fail_stage "redacted_source_bound_artifact" "evidence" "sha256_unavailable"
  source_commit="$(git -C "$ROOT_DIR" rev-parse HEAD)" || fail_stage "redacted_source_bound_artifact" "evidence" "source_commit_unavailable"
}

build_current_head_bundle() {
  local tracked_status source_commit_after_build expected_configuration_fingerprint
  tracked_status="$(git -C "$ROOT_DIR" status --porcelain --untracked-files=all)" \
    || fail_stage "normal_product_route" "provenance" "source_status_unavailable"
  [[ -z "$tracked_status" ]] \
    || fail_stage "normal_product_route" "provenance" "source_tree_not_clean"

  # Build the exact clean HEAD in this invocation. A timestamp on an existing
  # dist bundle is not provenance and must never make stale product code pass.
  # Only the explicit variables below cross into the build. In particular,
  # ignored release config, OAuth credentials, and arbitrary parent SUISUI_*
  # values cannot affect or leak into this runtime artifact.
  env -i \
    PATH="$PATH" \
    HOME="$HOME" \
    SUISUI_LOAD_LOCAL_RELEASE_CONFIG=0 \
    SUISUI_BUILD_CONFIGURATION=release \
    SUISUI_RELEASE_BUILD_PURPOSE=performance \
    SUISUI_RUNTIME_POLICY=public-alpha \
    SUISUI_ENABLE_EXPERIMENTAL_GOOGLE_CALENDAR_RUNTIME=0 \
    "$ROOT_DIR/script/build_and_run.sh" --build-only \
    || fail_stage "normal_product_route" "provenance" "current_head_bundle_build_failed"

  source_commit_after_build="$(git -C "$ROOT_DIR" rev-parse HEAD)" \
    || fail_stage "normal_product_route" "provenance" "post_build_source_commit_unavailable"
  [[ "$source_commit_after_build" == "$source_commit" ]] \
    || fail_stage "normal_product_route" "provenance" "source_commit_changed_during_build"
  [[ -z "$(git -C "$ROOT_DIR" status --porcelain --untracked-files=all)" ]] \
    || fail_stage "normal_product_route" "provenance" "source_tree_changed_during_build"

  # shellcheck source=/dev/null
  source "$METADATA_FILE"
  app_binary="$ROOT_DIR/dist/${APP_NAME:?APP_NAME is required}.app/Contents/MacOS/$APP_NAME"
  [[ -x "$app_binary" ]] \
    || fail_stage "normal_product_route" "provenance" "built_app_binary_missing"
  app_binary_sha256="$(/usr/bin/shasum -a 256 "$app_binary" | awk '{print $1}')"
  [[ "$app_binary_sha256" =~ ^[a-f0-9]{64}$ ]] \
    || fail_stage "normal_product_route" "provenance" "built_app_binary_hash_invalid"
  build_configuration_fingerprint="$(
    /usr/libexec/PlistBuddy -c "Print :SuisuiBuildConfigurationFingerprint" \
      "$ROOT_DIR/dist/${APP_NAME}.app/Contents/Info.plist"
  )" || fail_stage "normal_product_route" "provenance" "embedded_configuration_fingerprint_missing"
  expected_configuration_fingerprint="$(
    printf 'schema=1\nruntime-policy=public-alpha\nbuild-configuration=release\nrelease-purpose=performance\nsparkle-feed=\nsparkle-key=\nlicense-key=\n' \
      | /usr/bin/shasum -a 256 \
      | awk '{print $1}'
  )"
  [[ "$build_configuration_fingerprint" == "$expected_configuration_fingerprint" ]] \
    || fail_stage "normal_product_route" "provenance" "embedded_configuration_fingerprint_mismatch"
  [[ "$(/usr/libexec/PlistBuddy -c "Print :SuisuiRuntimePolicy" "$ROOT_DIR/dist/${APP_NAME}.app/Contents/Info.plist")" == "public-alpha" ]] \
    || fail_stage "normal_product_route" "provenance" "embedded_runtime_policy_mismatch"
}

prepare_isolated_home_and_sqlite() {
  mkdir -p "$ROOT_DIR/.tmp"
  runtime_dir="$(mktemp -d "$ROOT_DIR/.tmp/suisui-voice-task-continuity.XXXXXX")"
  runtime_home="$runtime_dir/home"
  database_path="$runtime_dir/Suisui.sqlite"
  fixture_manifest="$runtime_dir/fixed-fixture.tsv"
  witness_dir="$runtime_dir/witnesses"
  pre_approval_snapshot="$runtime_dir/pre-approval.sqlite.sha256"
  mkdir -p "$runtime_home" "$witness_dir"
  : >"$database_path"
  chmod 700 "$runtime_dir" "$runtime_home"
  chmod 600 "$database_path"
  printf 'project\t%s\t%s\n' "$FIXTURE_PROJECT_ID" "$FIXTURE_PROJECT_TITLE" >"$fixture_manifest"
  printf 'task\t%s\t%s\t%s\n' "$FIXTURE_TASK_ONE_ID" "$FIXTURE_PROJECT_ID" "$FIXTURE_TASK_ONE_TITLE" >>"$fixture_manifest"
  printf 'task\t%s\t%s\t%s\n' "$FIXTURE_TASK_TWO_ID" "$FIXTURE_PROJECT_ID" "$FIXTURE_TASK_TWO_TITLE" >>"$fixture_manifest"
  printf 'due_date\t%s\n' "$FIXTURE_DUE_DATE" >>"$fixture_manifest"
  [[ -s "$fixture_manifest" && -f "$database_path" ]] || fail_stage "isolated_home_sqlite" "sqlite" "fixture_initialization_failed"
}

validate_witness() {
  local stage="$1" layer="$2" witness="$witness_dir/$stage.witness"
  [[ -f "$witness" ]] || fail_stage "$stage" "$layer" "stage_witness_missing"
  contains_rejected_evidence "$witness" && fail_stage "$stage" "evidence-security" "witness_contains_rejected_data"
  grep -Fxq "stage=$stage" "$witness" || fail_stage "$stage" "$layer" "witness_stage_mismatch"
  grep -Fxq "result=passed" "$witness" || fail_stage "$stage" "$layer" "witness_not_passed"
  grep -Fxq "source_commit=$source_commit" "$witness" || fail_stage "$stage" "evidence" "source_commit_mismatch"
  grep -Fxq "app_binary_sha256=$app_binary_sha256" "$witness" || fail_stage "$stage" "evidence" "app_binary_hash_mismatch"
}

require_witness_fact() {
  local stage="$1" layer="$2" key="$3" expected="$4"
  local witness="$witness_dir/$stage.witness"
  grep -Eq "^${key}=${expected}$" "$witness" || fail_stage "$stage" "$layer" "required_witness_fact_missing:${key}"
}

validate_stage_contract() {
  local stage="$1" layer="$2"
  # Stage witnesses are intentionally structured facts, not screenshots or raw
  # log text. This checks the data hand-offs that a visible UI alone cannot prove.
  case "$stage" in
    fixed_fixture_seed)
      require_witness_fact "$stage" "$layer" "fixture_project_id" "$FIXTURE_PROJECT_ID"
      require_witness_fact "$stage" "$layer" "fixture_project_title" "$FIXTURE_PROJECT_TITLE"
      require_witness_fact "$stage" "$layer" "fixture_task_one_id" "$FIXTURE_TASK_ONE_ID"
      require_witness_fact "$stage" "$layer" "fixture_task_one_title" "$FIXTURE_TASK_ONE_TITLE"
      require_witness_fact "$stage" "$layer" "fixture_task_two_id" "$FIXTURE_TASK_TWO_ID"
      require_witness_fact "$stage" "$layer" "fixture_task_two_title" "$FIXTURE_TASK_TWO_TITLE"
      ;;
    normal_product_route)
      require_witness_fact "$stage" "$layer" "project_board_ax" "visible"
      require_witness_fact "$stage" "$layer" "voice_command_ax" "visible"
      ;;
    session_start)
      require_witness_fact "$stage" "$layer" "session_started" "true"
      ;;
    task_list)
      require_witness_fact "$stage" "$layer" "listed_task_ids" ".*${FIXTURE_TASK_ONE_ID}.*${FIXTURE_TASK_TWO_ID}.*"
      ;;
    reference_selection)
      require_witness_fact "$stage" "$layer" "selected_task_id" "$FIXTURE_TASK_TWO_ID"
      ;;
    clarification)
      require_witness_fact "$stage" "$layer" "clarification_count" "1"
      ;;
    proposal)
      require_witness_fact "$stage" "$layer" "proposal_due_date" "$FIXTURE_DUE_DATE"
      require_witness_fact "$stage" "$layer" "proposal_priority" "high"
      ;;
    pre_approval_snapshot)
      require_witness_fact "$stage" "$layer" "database_mutated" "false"
      ;;
    queue_approval_execution)
      require_witness_fact "$stage" "$layer" "queue_reviewed" "true"
      require_witness_fact "$stage" "$layer" "queue_approved" "true"
      require_witness_fact "$stage" "$layer" "queue_executed" "true"
      ;;
    postcondition_receipt_action_link)
      require_witness_fact "$stage" "$layer" "task_postcondition" "passed"
      require_witness_fact "$stage" "$layer" "receipt_link" "present"
      require_witness_fact "$stage" "$layer" "action_link" "present"
      ;;
    restart)
      require_witness_fact "$stage" "$layer" "app_restarted" "true"
      ;;
    resume)
      require_witness_fact "$stage" "$layer" "session_resumed" "true"
      require_witness_fact "$stage" "$layer" "resume_project_scope" "$FIXTURE_PROJECT_ID"
      require_witness_fact "$stage" "$layer" "resume_task_scope" "$FIXTURE_TASK_TWO_ID"
      require_witness_fact "$stage" "$layer" "resume_action_link_id" "[[:alnum:]_-]+"
      # Receipt IDs are canonical colon-delimited identifiers (for example,
      # receipt:<run>:<queue>:<session>), unlike UUID-only ActionLink IDs.
      require_witness_fact "$stage" "$layer" "resume_execution_receipt_id" "[[:alnum:]_:-]+"
      require_witness_fact "$stage" "$layer" "resume_summary_sha256" "[a-f0-9]{64}"
      ;;
  esac
}

run_product_stage() {
  local stage="$1" layer="$2"
  if [[ "$driver_has_run" == "0" ]]; then
    # One owned process lifecycle must span the conversational stages. Running
    # a fresh app per witness would conceal broken in-memory hand-offs.
    if ! env -i \
      PATH="$PATH" \
      HOME="$runtime_home" \
      CFFIXED_USER_HOME="$runtime_home" \
      SUISUI_DISABLE_KEYCHAIN_SECRET_STORE=1 \
      SUISUI_DATABASE_PATH="$database_path" \
      SUISUI_VOICE_TASK_CONTINUITY_FIXTURE_MANIFEST="$fixture_manifest" \
      SUISUI_VOICE_TASK_CONTINUITY_WITNESS_DIR="$witness_dir" \
      SUISUI_VOICE_TASK_CONTINUITY_PRE_APPROVAL_SNAPSHOT="$pre_approval_snapshot" \
      SUISUI_VOICE_TASK_CONTINUITY_SOURCE_COMMIT="$source_commit" \
      SUISUI_VOICE_TASK_CONTINUITY_APP_BINARY_SHA256="$app_binary_sha256" \
      "$DRIVER" --run-all; then
      local failure_file="$witness_dir/driver-failure.env"
      if [[ -f "$failure_file" ]]; then
        local failed_stage failed_layer failed_reason
        failed_stage="$(grep -E '^stage=' "$failure_file" | head -1 | cut -d= -f2-)"
        failed_layer="$(grep -E '^layer=' "$failure_file" | head -1 | cut -d= -f2-)"
        failed_reason="$(grep -E '^reason=' "$failure_file" | head -1 | cut -d= -f2-)"
        fail_stage \
          "${failed_stage:-$stage}" \
          "${failed_layer:-$layer}" \
          "${failed_reason:-normal_product_driver_failed}"
      fi
      fail_stage "$stage" "$layer" "normal_product_driver_failed"
    fi
    driver_has_run=1
  fi
  validate_witness "$stage" "$layer"
  validate_stage_contract "$stage" "$layer"
  completed_stages+=("$stage")
}

verify_pre_approval_snapshot() {
  [[ -s "$pre_approval_snapshot" ]] || fail_stage "pre_approval_snapshot" "pre-approval" "pre_approval_snapshot_missing"
  grep -Eq '^[a-f0-9]{64}[[:space:]]+database$' "$pre_approval_snapshot" || fail_stage "pre_approval_snapshot" "pre-approval" "pre_approval_snapshot_invalid"
}

verify_final_evidence() {
  local artifact_file="$ARTIFACT_ROOT/voice-task-continuity.json"
  write_artifact_atomically "passed" "" "" ""
  [[ -f "$artifact_file" ]] || fail_stage "redacted_source_bound_artifact" "evidence" "artifact_missing"
  contains_rejected_evidence "$artifact_file" && fail_stage "redacted_source_bound_artifact" "evidence-security" "artifact_contains_rejected_data"
  grep -Fq "\"sourceCommit\": \"$source_commit\"" "$artifact_file" || fail_stage "redacted_source_bound_artifact" "evidence" "artifact_source_commit_mismatch"
  grep -Fq "\"appBinarySHA256\": \"$app_binary_sha256\"" "$artifact_file" || fail_stage "redacted_source_bound_artifact" "evidence" "artifact_app_binary_hash_mismatch"
  grep -Fq "\"buildConfigurationFingerprint\": \"$build_configuration_fingerprint\"" "$artifact_file" || fail_stage "redacted_source_bound_artifact" "evidence" "artifact_configuration_fingerprint_mismatch"
  grep -Fq '"manualVoiceOver": "not-run"' "$artifact_file" || fail_stage "redacted_source_bound_artifact" "evidence" "manual_voiceover_claimed"
  completed_stages+=("redacted_source_bound_artifact")
  write_artifact_atomically "passed" "" "" ""
}

main() {
  [[ $# -eq 0 ]] || { usage; exit 2; }
  require_runtime_prerequisites
  build_current_head_bundle
  prepare_isolated_home_and_sqlite
  run_product_stage "isolated_home_sqlite" "sqlite"
  run_product_stage "fixed_fixture_seed" "fixture"
  run_product_stage "normal_product_route" "launch"
  run_product_stage "session_start" "ax"
  run_product_stage "task_list" "ax"
  run_product_stage "reference_selection" "plan"
  run_product_stage "clarification" "plan"
  run_product_stage "proposal" "plan"
  run_product_stage "pre_approval_snapshot" "pre-approval"
  verify_pre_approval_snapshot
  run_product_stage "queue_approval_execution" "queue-execution"
  run_product_stage "postcondition_receipt_action_link" "postcondition-receipt-action-link"
  run_product_stage "restart" "restart"
  run_product_stage "resume" "resume"
  verify_final_evidence
  printf 'OK: voice task continuity passed (14 stages, source %s, artifact %s)\n' "$source_commit" "$(repo_relative_path "$ARTIFACT_ROOT/voice-task-continuity.json")"
}

main "$@"
