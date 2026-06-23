#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

REQUIRED_MARKERS=(
  "AccessibilityFocusPathAudit"
  "SoloPMHarnessTaskLifecycleOperation"
  "requiredTaskLifecycleOperations"
  "completeTaskLifecycleOperations"
  "project-board-sidebar"
  "project-board-detail"
  "project-header-add-task"
  "inline-task-create"
  "project-board-task-auto-execution-review"
  "task-card-open-details"
  "task-inspector-save"
  "task-status-move-controls"
  "task-auto-execution-review"
  "task-auto-execution-run-plan"
  "approved-execution-receipt"
  "task-inspector-delete"
  "task-inspector-delete-confirmation-confirm"
)

SOURCES=(
  "$ROOT_DIR/Sources/SoloPMCore/App/AccessibilityFocusPathAudit.swift"
  "$ROOT_DIR/Sources/SoloPMCore/App/SoloPMHarness.swift"
  "$ROOT_DIR/Sources/SoloPMApp/Views/ProjectBoardView.swift"
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

if [[ "$missing" -gt 0 ]]; then
  exit 1
fi

echo "OK: pseudo VoiceOver focus path contract covers task create/edit/status/automation/approved execution/delete markers"
