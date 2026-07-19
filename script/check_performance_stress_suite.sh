#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STRESS_TMP_ROOT="${SUISUI_STRESS_TMP_ROOT:-$ROOT_DIR/.tmp}"
OUTPUT_DIR="${SUISUI_STRESS_OUTPUT_DIR:-$STRESS_TMP_ROOT/performance-stress}"
SUMMARY_FILE="$OUTPUT_DIR/summary.md"
SCRATCH_PATH="${SUISUI_STRESS_SCRATCH_PATH:-$ROOT_DIR/.build/performance-stress}"
RUN_RUNTIME_PERFORMANCE="${SUISUI_STRESS_RUNTIME_PERFORMANCE:-0}"

validate_flag() {
  local name="$1"
  local value="$2"
  if [[ "$value" != "0" && "$value" != "1" ]]; then
    echo "BLOCKER: $name must be 0 or 1" >&2
    exit 2
  fi
}

join_by_pipe() {
  local IFS="|"
  printf "%s" "$*"
}

# Keep the default suite deterministic and non-GUI: it should catch scale and
# bounded-operation regressions without requiring a local Accessibility session.
STRESS_TEST_FILTERS=(
  "DevelopmentRepositoryFileAccessTests/testListFilesCapsLargeWorkspaceResults"
  "KnowledgeAdvancedTests/testSQLiteVectorIndexSearchWithTopKBoundedRankingAndTiebreak"
  "KnowledgeAdvancedTests/testSQLiteVectorIndexLargeCorpusKeepsTopKAndTiebreakStable"
  "ExternalTaskInteropTests/testGoogleCalendarTaskSyncBoundsWritesAndCountsDeferredDueTasksAcrossLargeFixtures"
  "ExternalTaskInteropTests/testGoogleCalendarTaskSyncReportsRetryableRateLimitFailuresWithoutLoopingUnboundedly"
  "GoogleCalendarAppRuntimeTests/testHTTPEventClientReports429RetryAfterAsRateLimit"
  "GoogleCalendarAppRuntimeTests/testHTTPEventClientReports503WithoutRetryAfterAsRateLimit"
  "ExecutionReceiptTests/testFileExecutionReceiptStoreScopedListDoesNotLoseOlderMatchingReceiptsBehindGlobalLimit"
  "ExecutionReceiptTests/testExecutionReceiptStoreSearchFiltersBeforeLimitForAuditRows"
  "AssistantQueueStoreTests/testSQLiteReadModelSnapshotDoesNotDecodeActionPayloadJSONForListRows"
  "AssistantQueueStoreTests/testSQLiteStoreFiltersAttentionStatesBeforeLimit"
  "AssistantQueueStoreTests/testReadModelSnapshotScalesToLargeQueueWhilePreservingAttentionCounts"
  "AssistantQueueStoreTests/testReadModelSnapshotDoesNotDecodeLargeActionPlanPayloadForWindowedListRows"
  "AssistantQueueStoreTests/testProjectBoardViewModelCountsAttentionStatesBeyondTerminalRowLimit"
  "ProjectBoardStoreTests/testProjectBoardViewModelLoadsIndexedLargeBoardReadModelsWithoutFullScanPlans"
  "STTProviderTests/testProcessWhisperCppCommandRunnerDrainsAndCapsLargeStderr"
  "AppExperienceSourceTests/testProjectBoardPerformanceReadModelsStayOutOfRenderPath"
  "ReleasePipelineTests/testReleaseLaunchPerformanceSmokeMeasuresColdLaunchAndWorkflowSwitches"
  "ReleasePipelineTests/testReleaseLaunchPerformanceSmokeRejectsRelaxedReleaseBudgetsBeforeBuild"
)

run_swift_stress_tests() {
  local filter
  filter="$(join_by_pipe "${STRESS_TEST_FILTERS[@]}")"
  swift test --scratch-path "$SCRATCH_PATH" --filter "$filter"
}

run_runtime_performance_smoke() {
  SUISUI_PERFORMANCE_PROFILE="${SUISUI_PERFORMANCE_PROFILE:-debug}" \
  SUISUI_PERFORMANCE_BUILD_CONFIGURATION="${SUISUI_PERFORMANCE_BUILD_CONFIGURATION:-debug}" \
  SUISUI_PERFORMANCE_OUTPUT_DIR="${SUISUI_PERFORMANCE_OUTPUT_DIR:-$OUTPUT_DIR/release-launch-performance}" \
    "$ROOT_DIR/script/check_release_launch_performance_smoke.sh"
}

validate_flag "SUISUI_STRESS_RUNTIME_PERFORMANCE" "$RUN_RUNTIME_PERFORMANCE"

cd "$ROOT_DIR"
mkdir -p "$OUTPUT_DIR"
{
  printf '# Suisui Performance Stress Suite\n\n'
  printf -- '- Started: `%s`\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  printf -- '- Swift stress filters: `%d`\n' "${#STRESS_TEST_FILTERS[@]}"
  printf -- '- Runtime performance smoke: `%s`\n' "$RUN_RUNTIME_PERFORMANCE"
  printf -- '- Scratch path: `%s`\n\n' "$SCRATCH_PATH"
} >"$SUMMARY_FILE"

run_swift_stress_tests
printf -- '- Swift stress tests: `passed`\n' >>"$SUMMARY_FILE"

if [[ "$RUN_RUNTIME_PERFORMANCE" == "1" ]]; then
  run_runtime_performance_smoke
  printf -- '- Runtime performance smoke: `passed`\n' >>"$SUMMARY_FILE"
fi

printf "OK: performance stress suite passed; summary: %s\n" "$SUMMARY_FILE"
