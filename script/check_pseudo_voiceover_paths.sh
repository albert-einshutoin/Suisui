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
  "sidebar-destination-today"
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

TODAY_WORKFLOW_SOURCE="$ROOT_DIR/Sources/SuisuiApp/Views/ProjectWorkflowTodayView.swift"
SIDEBAR_WORKFLOW_SOURCE="$ROOT_DIR/Sources/SuisuiApp/Views/ProjectWorkflowViews.swift"
SIDEBAR_DESTINATION_SOURCE="$ROOT_DIR/Sources/SuisuiCore/App/ProjectBoardSelectionPersistence.swift"

SOURCES=(
  "$ROOT_DIR/Sources/SuisuiCore/App/AccessibilityFocusPathAudit.swift"
  "$ROOT_DIR/Sources/SuisuiCore/App/SuisuiHarness.swift"
  "$SIDEBAR_DESTINATION_SOURCE"
  "$ROOT_DIR/Sources/SuisuiApp/Views/ProjectBoardView.swift"
  "$TODAY_WORKFLOW_SOURCE"
  "$SIDEBAR_WORKFLOW_SOURCE"
  "$ROOT_DIR/docs/quality/accessibility-focus-paths.md"
)

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

if [[ ! -f "$SIDEBAR_DESTINATION_SOURCE" ]]; then
  echo "BLOCKER: sidebar destination source is missing: $SIDEBAR_DESTINATION_SOURCE" >&2
  missing=$((missing + 1))
else
  if ! grep -F '.accessibilityIdentifier("sidebar-destination-\(destination.accessibilityIdentifierSuffix)")' "$SIDEBAR_WORKFLOW_SOURCE" >/dev/null; then
    echo "BLOCKER: generated sidebar accessibilityIdentifier template is missing from ProjectWorkflowViews.swift" >&2
    missing=$((missing + 1))
  fi
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

echo "OK: pseudo VoiceOver focus path contract covers task lifecycle execution and Today cockpit markers"
