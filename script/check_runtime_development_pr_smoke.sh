#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="${SOLOPM_RUNTIME_DEVELOPMENT_PR_ARTIFACT_DIR:-$ROOT_DIR/.tmp/runtime-development-pr-smoke}"
KEEP_WORKSPACE="${SOLOPM_RUNTIME_DEVELOPMENT_PR_KEEP_WORKSPACE:-0}"
OUTPUT_FILE="$ARTIFACT_DIR/swift-test-output.txt"
ARTIFACT_FILE="$ARTIFACT_DIR/evidence.md"
WORKSPACE_ROOT="$ARTIFACT_DIR/workspaces"

mkdir -p "$ARTIFACT_DIR" "$WORKSPACE_ROOT"
cd "$ROOT_DIR"

write_artifact() {
  local status="$1"
  local reason="$2"
  {
    printf '# Runtime Development PR Smoke\n\n'
    printf -- '- Status: `%s`\n' "$status"
    printf -- '- Reason: `%s`\n' "$reason"
    printf -- '- XCTest: `DevelopmentAutomationRuntimeSmokeTests/testApprovedProjectDirectoryCanEditVerifyCommitAndPreparePullRequestBranch`\n'
    printf -- '- Flow: approved project directory -> `development.pr_workflow.prepare` -> `development.repository.list_files` -> `development.repository.create_file` -> `development.repository.update_file` -> `development.verification.run` -> `development.pr_workflow.commit` -> `development.pr_workflow.push` -> `development.pr_workflow.create_pull_request` -> `development.pr_workflow.review_gate` -> `development.pr_workflow.merge` with fake Git and GitHub runners\n'
    printf -- '- Approval boundary: `requiresPushApproval=true`, `requiresPullRequestApproval=true`\n'
    printf -- '- External writes: No live push, GitHub PR, review gate, or merge is created by this smoke.\n'
    printf -- '- Workspace retention requested: `%s`\n' "$KEEP_WORKSPACE"
    printf -- '- Workspace root: `%s`\n' "${WORKSPACE_ROOT#"$ROOT_DIR/"}"
    printf -- '- Output: `%s`\n' "${OUTPUT_FILE#"$ROOT_DIR/"}"
  } >"$ARTIFACT_FILE"
}

if SOLOPM_RUNTIME_DEVELOPMENT_PR_WORKSPACE_ROOT="$WORKSPACE_ROOT" \
  SOLOPM_RUNTIME_DEVELOPMENT_PR_KEEP_WORKSPACE="$KEEP_WORKSPACE" \
  swift test --filter DevelopmentAutomationRuntimeSmokeTests/testApprovedProjectDirectoryCanEditVerifyCommitAndPreparePullRequestBranch --quiet >"$OUTPUT_FILE" 2>&1; then
  cat "$OUTPUT_FILE"
  write_artifact "passed" "approved project directory fixture flow reached local commit, fake push, fake PR creation, fake review gate, and fake merge approval boundaries"
  printf 'OK: runtime development PR smoke passed. Evidence: %s\n' "${ARTIFACT_FILE#"$ROOT_DIR/"}"
  exit 0
fi

cat "$OUTPUT_FILE" >&2
write_artifact "failed" "development PR fixture flow failed"
echo "BLOCKER: runtime development PR smoke failed. Evidence: ${ARTIFACT_FILE#"$ROOT_DIR/"}" >&2
exit 1
