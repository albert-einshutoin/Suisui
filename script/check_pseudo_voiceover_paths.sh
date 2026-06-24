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
  "SoloPMHarnessTaskLifecycleOperation"
  "requiredTaskLifecycleOperations"
  "completeTaskLifecycleOperations"
  "project-board-sidebar"
  "project-board-detail"
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

if [[ "$RUN_SWIFT_TESTS" -eq 1 ]]; then
  cd "$ROOT_DIR"
  # The string marker scan is intentionally cheap for release summaries. The
  # optional Swift pass proves the real harness behavior before a manual
  # VoiceOver worksheet can reuse the pseudo VoiceOver gate.
  swift test --filter AccessibilityFocusPathAuditTests
  swift test --filter SoloPMHarnessTests
fi

echo "OK: pseudo VoiceOver focus path contract covers task create/edit/status/automation/approved execution/delete markers"
