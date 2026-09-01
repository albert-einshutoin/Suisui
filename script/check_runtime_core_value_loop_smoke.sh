#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="${SUISUI_CORE_VALUE_LOOP_ARTIFACT_DIR:-$ROOT_DIR/.tmp/suisui-core-value-loop}"
MANIFEST_PATH="$ARTIFACT_DIR/manifest.json"
INBOX_TIMEOUT_SECONDS="${SUISUI_CORE_VALUE_LOOP_INBOX_TIMEOUT_SECONDS:-${SUISUI_RUNTIME_INBOX_TRIAGE_TIMEOUT_SECONDS:-60}}"
VOICE_TIMEOUT_SECONDS="${SUISUI_CORE_VALUE_LOOP_VOICE_TIMEOUT_SECONDS:-${SUISUI_RUNTIME_VOICE_REVIEW_TIMEOUT_SECONDS:-60}}"
SCHEDULE_TIMEOUT_SECONDS="${SUISUI_CORE_VALUE_LOOP_SCHEDULE_TIMEOUT_SECONDS:-${SUISUI_RUNTIME_SCHEDULE_COCKPIT_TIMEOUT_SECONDS:-60}}"

capture_status="not_run"
interpret_status="not_run"
review_status="not_run"
move_status="not_run"
evidence_status="not_run"
overall_status="not_run"

mkdir -p "$ARTIFACT_DIR"
source_commit="$(git -C "$ROOT_DIR" rev-parse --verify HEAD)"

write_manifest() {
  cat >"$MANIFEST_PATH" <<EOF
{
  "schema": "suisui.core_value_loop.v1",
  "sourceCommit": "$source_commit",
  "route": "normal-product",
  "externalWrites": 0,
  "rawTranscriptStored": false,
  "stages": {
    "Capture": "$capture_status",
    "Interpret": "$interpret_status",
    "Review": "$review_status",
    "Move": "$move_status",
    "Evidence": "$evidence_status"
  },
  "status": "$overall_status"
}
EOF
}
trap write_manifest EXIT

set_stage_status() {
  local stage="$1"
  local status="$2"
  case "$stage" in
    capture) capture_status="$status" ;;
    interpret) interpret_status="$status" ;;
    review) review_status="$status" ;;
    move) move_status="$status" ;;
    evidence) evidence_status="$status" ;;
    *)
      echo "BLOCKER: unknown core value loop stage: $stage" >&2
      return 2
      ;;
  esac
}

run_stage() {
  local stage="$1"
  shift
  printf '[core-loop] %s\n' "$stage"
  if "$@"; then
    set_stage_status "$stage" "passed"
    return 0
  fi
  set_stage_status "$stage" "failed"
  overall_status="failed"
  echo "BLOCKER: core value loop stage failed: $stage" >&2
  return 1
}

cd "$ROOT_DIR"
if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
  overall_status="blocked"
  echo "BLOCKER: core value loop evidence requires a clean source worktree" >&2
  exit 1
fi

run_stage capture env SUISUI_RUNTIME_INBOX_TRIAGE_TIMEOUT_SECONDS="$INBOX_TIMEOUT_SECONDS" ./script/check_runtime_inbox_triage_smoke.sh
run_stage interpret env SUISUI_RUNTIME_VOICE_REVIEW_TIMEOUT_SECONDS="$VOICE_TIMEOUT_SECONDS" ./script/check_runtime_voice_review_smoke.sh
run_stage review env SUISUI_RUNTIME_SCHEDULE_COCKPIT_TIMEOUT_SECONDS="$SCHEDULE_TIMEOUT_SECONDS" ./script/check_runtime_schedule_cockpit_smoke.sh
run_stage move swift test --filter 'ProjectBoardStoreTests/(testProjectBoardViewModelQuickCapturesInboxTaskAndNotifies|testScheduleDraftQueuesCalendarWorkBlocksForReviewWithoutCalendarWrite|testScheduleApplyPersistsExecutionReceiptForCreatedCalendarEvents|testScheduleApplyPersistsFailedExecutionReceiptWhenCalendarWriteFails)|AssistantQueueTests/(testApprovedItemEditReturnsToWaitingReviewAndClearsApproval|testReviewDispositionTransitionsRejectRunningAndTerminalItems|testFailedActionPlanCanReopenForRetryReview)'
run_stage evidence ./script/check_accessibility_preflight.sh --source-only

overall_status="passed"
printf 'OK: Capture -> Interpret -> Review -> Move -> Evidence verified on normal product routes\n'
printf 'OK: redacted source-bound manifest: %s\n' "$MANIFEST_PATH"
