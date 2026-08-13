#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_SWIFT_TESTS=0

usage() {
  printf '%s\n' "usage: $0 [--swift-test]"
  printf '%s\n' ""
  printf '%s\n' "Checks the MCP pseudo VoiceOver focus-path contract."
  printf '%s\n' "--swift-test also runs the Swift harness tests that prove the focus-path and approved execution receipt logic."
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --swift-test)
      RUN_SWIFT_TESTS=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

REQUIRED_MARKERS=(
  "AccessibilityFocusPathAudit"
  "dynamicRequiredNodeIDPrefixes"
  "todayCockpit"
  "todayEmptyCockpit"
  "SuisuiHarnessTaskLifecycleOperation"
  "SuisuiHarnessTodayCockpitOperation"
  "requiredTaskLifecycleOperations"
  "requiredTodayCockpitOperations"
  "requiredFocusNodeIDs"
  "requiredTodayCockpitFocusNodeIDs"
  "completeTaskLifecycleOperations"
  "completeTodayCockpitOperations"
  "missingTodayCockpitOperations"
  "project-board-sidebar"
  "project-board-detail"
  "project-task-list"
  "project-header-add-task"
  "inline-task-title"
  "inline-task-detail"
  "inline-task-create"
  "project-board-task-auto-execution-review"
  "task-card-open-details"
  "task-inspector-title"
  "task-inspector-detail"
  "task-inspector-save"
  "task-status-move-controls"
  "task-status-move-in_progress"
  "task-auto-execution-review"
  "task-auto-execution-run-plan"
  "approved-execution-receipt"
  "task-inspector-delete"
  "task-inspector-delete-confirmation-cancel"
  "task-inspector-delete-confirmation-confirm"
  "project-inspector-complete"
  "project-inspector-delete"
  "project-inspector-delete-confirmation-cancel"
  "project-inspector-delete-confirmation-confirm"
  "today-workflow"
  "today-briefing-panel"
  "today-focus-recommendation"
  "today-primary-action"
  "today-command-capture-field"
  "today-secondary-actions-menu"
  "today-flow-strip"
  "today-assistant-rail"
  "today-rail-next-action"
  "today-rail-task-detail"
  "today-rail-actions-menu"
  "inbox-selected-context"
  "inbox-action-grid"
  "review-hub-compact-navigation"
  "projects-hub-compact-navigation"
  "assistant-queue-workflow"
  "assistant-queue-approve"
  "assistant-queue-run"
  "assistant-queue-retry"
  "assistant-queue-more"
  "assistant-queue-edit"
  "assistant-queue-edit-reason"
  "assistant-queue-edit-save"
  "assistant-queue-edit-cancel"
)

TODAY_UI_ACCESSIBILITY_IDENTIFIERS=(
  "today-workflow"
  "today-briefing-panel"
  "today-focus-recommendation"
  "today-primary-action"
  "today-command-capture-field"
  "today-secondary-actions-menu"
  "today-flow-strip"
  "today-assistant-rail"
  "today-rail-next-action"
  "today-rail-task-detail"
  "today-rail-actions-menu"
)

SIDEBAR_UI_ACCESSIBILITY_IDENTIFIERS=(
  "sidebar-destination-inbox"
  "sidebar-destination-today"
  "sidebar-destination-projects"
  "sidebar-destination-schedule"
  "sidebar-destination-completed"
)

TODAY_WORKFLOW_SOURCE="$ROOT_DIR/Sources/SuisuiApp/Views/ProjectWorkflowTodayView.swift"
SIDEBAR_SOURCE="$ROOT_DIR/Sources/SuisuiApp/Views/ProjectBoardSidebarView.swift"
SIDEBAR_DESTINATION_SOURCE="$ROOT_DIR/Sources/SuisuiCore/App/ProjectBoardSelectionPersistence.swift"
INBOX_WORKFLOW_SOURCE="$ROOT_DIR/Sources/SuisuiApp/Views/ProjectWorkflowInboxView.swift"
ASSISTANT_QUEUE_WORKFLOW_SOURCE="$ROOT_DIR/Sources/SuisuiApp/Views/ProjectWorkflowAssistantQueueView.swift"
REVIEW_HUB_SOURCE="$ROOT_DIR/Sources/SuisuiApp/Views/ProjectBoardReviewHubView.swift"
PROJECTS_HUB_SOURCE="$ROOT_DIR/Sources/SuisuiApp/Views/ProjectBoardProjectsHubView.swift"

INBOX_APPROVAL_FLOW_MARKERS=(
  '.accessibilityIdentifier("inbox-selected-context")'
  '.accessibilityIdentifier("inbox-action-grid")'
)

REVIEW_HUB_APPROVAL_FLOW_MARKERS=(
  '.accessibilityIdentifier("review-hub-compact-navigation")'
)

PROJECTS_HUB_APPROVAL_FLOW_MARKERS=(
  '.accessibilityIdentifier("projects-hub-compact-navigation")'
)

ASSISTANT_QUEUE_APPROVAL_FLOW_MARKERS=(
  '.accessibilityIdentifier("assistant-queue-workflow")'
  '.accessibilityIdentifier("assistant-queue-approve-\(row.id)")'
  '.accessibilityIdentifier("assistant-queue-run-\(row.id)")'
  '.accessibilityIdentifier("assistant-queue-retry-\(row.id)")'
  '.accessibilityIdentifier("assistant-queue-more-\(row.id)")'
  '.accessibilityIdentifier("assistant-queue-edit-\(row.id)")'
  '.accessibilityIdentifier("assistant-queue-edit-reason-\(row.id)")'
  '.accessibilityIdentifier("assistant-queue-edit-save-\(row.id)")'
  '.accessibilityIdentifier("assistant-queue-edit-cancel-\(row.id)")'
)

SOURCES=(
  "$ROOT_DIR/Sources/SuisuiCore/App/AccessibilityFocusPathAudit.swift"
  "$ROOT_DIR/Sources/SuisuiCore/App/SuisuiHarness.swift"
  "$SIDEBAR_DESTINATION_SOURCE"
  "$ROOT_DIR/Sources/SuisuiApp/Views/ProjectBoardView.swift"
  "$TODAY_WORKFLOW_SOURCE"
  "$SIDEBAR_SOURCE"
  "$INBOX_WORKFLOW_SOURCE"
  "$ASSISTANT_QUEUE_WORKFLOW_SOURCE"
  "$REVIEW_HUB_SOURCE"
  "$PROJECTS_HUB_SOURCE"
  "$ROOT_DIR/docs/quality/accessibility-focus-paths.md"
)

check_source_markers() {
  local source_path="$1"
  local source_label="$2"
  shift 2

  if [[ ! -f "$source_path" ]]; then
    echo "BLOCKER: approval flow source is missing: $source_path" >&2
    return 1
  fi

  local marker
  local marker_missing=0
  for marker in "$@"; do
    if ! grep -F -- "$marker" "$source_path" >/dev/null; then
      echo "BLOCKER: approval flow accessibilityIdentifier missing from $source_label: $marker" >&2
      marker_missing=1
    fi
  done
  return "$marker_missing"
}

missing=0
for marker in "${REQUIRED_MARKERS[@]}"; do
  found=0
  for source in "${SOURCES[@]}"; do
    if [[ -f "$source" ]] && grep -F "$marker" "$source" >/dev/null; then
      found=1
      break
    fi
  done
  if [[ "$found" -ne 1 ]]; then
    echo "BLOCKER: pseudo VoiceOver focus path marker missing: $marker" >&2
    missing=$((missing + 1))
  fi
done

if ! check_source_markers \
  "$INBOX_WORKFLOW_SOURCE" \
  "ProjectWorkflowInboxView.swift" \
  "${INBOX_APPROVAL_FLOW_MARKERS[@]}"; then
  missing=$((missing + 1))
fi
if ! check_source_markers \
  "$REVIEW_HUB_SOURCE" \
  "ProjectBoardReviewHubView.swift" \
  "${REVIEW_HUB_APPROVAL_FLOW_MARKERS[@]}"; then
  missing=$((missing + 1))
fi
if ! check_source_markers \
  "$PROJECTS_HUB_SOURCE" \
  "ProjectBoardProjectsHubView.swift" \
  "${PROJECTS_HUB_APPROVAL_FLOW_MARKERS[@]}"; then
  missing=$((missing + 1))
fi
if ! check_source_markers \
  "$ASSISTANT_QUEUE_WORKFLOW_SOURCE" \
  "ProjectWorkflowAssistantQueueView.swift" \
  "${ASSISTANT_QUEUE_APPROVAL_FLOW_MARKERS[@]}"; then
  missing=$((missing + 1))
fi

MARKER_SELF_TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/suisui-pseudo-voiceover.XXXXXX")"
MARKER_SELF_TEST_FIXTURE="$MARKER_SELF_TEST_DIR/ProjectWorkflowAssistantQueueView.swift"
cleanup_marker_self_test() {
  rm -f -- "$MARKER_SELF_TEST_FIXTURE"
  rmdir -- "$MARKER_SELF_TEST_DIR" 2>/dev/null || true
}
trap cleanup_marker_self_test EXIT

if [[ -f "$ASSISTANT_QUEUE_WORKFLOW_SOURCE" ]]; then
  # Exercise the same per-file gate against a realistic broken source copy so
  # refactors cannot accidentally turn the marker scan into an always-pass check.
  grep -F -v -- \
    '.accessibilityIdentifier("assistant-queue-run-\(row.id)")' \
    "$ASSISTANT_QUEUE_WORKFLOW_SOURCE" > "$MARKER_SELF_TEST_FIXTURE"
  if check_source_markers \
    "$MARKER_SELF_TEST_FIXTURE" \
    "negative marker self-test fixture" \
    "${ASSISTANT_QUEUE_APPROVAL_FLOW_MARKERS[@]}" 2>/dev/null; then
    echo "BLOCKER: approval flow marker gate accepted a fixture with a missing queue identifier" >&2
    missing=$((missing + 1))
  fi
fi

if [[ ! -f "$TODAY_WORKFLOW_SOURCE" ]]; then
  echo "BLOCKER: Today workflow source is missing: $TODAY_WORKFLOW_SOURCE" >&2
  missing=$((missing + 1))
else
  for identifier in "${TODAY_UI_ACCESSIBILITY_IDENTIFIERS[@]}"; do
    if ! grep -F ".accessibilityIdentifier(\"$identifier\")" "$TODAY_WORKFLOW_SOURCE" >/dev/null; then
      echo "BLOCKER: Today UI accessibilityIdentifier missing from ProjectWorkflowTodayView.swift: $identifier" >&2
      missing=$((missing + 1))
    fi
  done
fi

if [[ ! -f "$SIDEBAR_SOURCE" ]]; then
  echo "BLOCKER: sidebar source is missing: $SIDEBAR_SOURCE" >&2
  missing=$((missing + 1))
else
  for identifier in "${SIDEBAR_UI_ACCESSIBILITY_IDENTIFIERS[@]}"; do
    if ! grep -F "\"$identifier\"" "$SIDEBAR_SOURCE" >/dev/null; then
      echo "BLOCKER: sidebar accessibilityIdentifier missing from ProjectBoardSidebarView.swift: $identifier" >&2
      missing=$((missing + 1))
    fi
  done
fi

if [[ ! -f "$SIDEBAR_DESTINATION_SOURCE" ]]; then
  echo "BLOCKER: sidebar destination source is missing: $SIDEBAR_DESTINATION_SOURCE" >&2
  missing=$((missing + 1))
else
  if ! awk '/case \.today:/ { foundCase = 1; next } foundCase && /"today"/ { foundValue = 1; exit } END { exit !(foundCase && foundValue) }' "$SIDEBAR_DESTINATION_SOURCE"; then
    echo "BLOCKER: Today sidebar accessibilityIdentifier suffix mapping is missing from ProjectBoardSelectionPersistence.swift" >&2
    missing=$((missing + 1))
  fi
fi

if [[ "$missing" -gt 0 ]]; then
  exit 1
fi

if [[ "$RUN_SWIFT_TESTS" -eq 1 ]]; then
  cd "$ROOT_DIR"
  # The string marker scan is intentionally cheap for release summaries. The
  # optional Swift pass proves the real harness behavior before a manual
  # VoiceOver worksheet can reuse the pseudo VoiceOver gate.
  swift test --filter AccessibilityFocusPathAuditTests
  swift test --filter SuisuiHarnessTests
fi

echo "OK: pseudo VoiceOver focus path contract covers task lifecycle, Today cockpit, and approval flow markers"
