#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METADATA_FILE="$ROOT_DIR/packaging/app_metadata.env"

if [[ ! -f "$METADATA_FILE" ]]; then
  echo "missing metadata file: $METADATA_FILE" >&2
  exit 2
fi

# shellcheck source=/dev/null
source "$METADATA_FILE"

APP_NAME="${APP_NAME:?APP_NAME is required}"
ARTIFACT_DIR="${SOLOPM_RUNTIME_WORKFLOW_ARTIFACT_DIR:-$ROOT_DIR/.tmp/runtime-workflow-smoke}"
SCENARIOS=("project_task_crud" "inbox_triage" "today_complete" "settings_save" "voice_review")
REQUESTED_SCENARIOS=()

usage() {
  printf '%s\n' "usage: $0 [--scenario project_task_crud|inbox_triage|today_complete|settings_save|voice_review]..." >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario)
      REQUESTED_SCENARIOS+=("${2:?--scenario requires a name}")
      shift 2
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [[ "${#REQUESTED_SCENARIOS[@]}" -eq 0 ]]; then
  REQUESTED_SCENARIOS=("${SCENARIOS[@]}")
fi

mkdir -p "$ARTIFACT_DIR"

scenario_is_known() {
  local scenario="$1"
  local known
  for known in "${SCENARIOS[@]}"; do
    [[ "$known" == "$scenario" ]] && return 0
  done
  return 1
}

last_visible_window_context() {
  /usr/bin/osascript - "$APP_NAME" <<'APPLESCRIPT' 2>/dev/null || printf '%s\n' 'process=missing windows=0'
on run argv
  set appName to item 1 of argv
  tell application "System Events"
    if not (exists process appName) then return "process=missing windows=0"
    tell process appName
      set windowCount to count of windows
      if windowCount < 1 then return "process=visible windows=0"
      set windowSummaries to {}
      repeat with windowIndex from 1 to windowCount
        set currentWindow to window windowIndex
        set windowName to ""
        set windowPosition to ""
        set windowSize to ""
        try
          set windowName to name of currentWindow as text
        end try
        try
          set windowPosition to position of currentWindow as text
        end try
        try
          set windowSize to size of currentWindow as text
        end try
        set end of windowSummaries to ("window=" & windowIndex & " name=" & windowName & " position=" & windowPosition & " size=" & windowSize)
      end repeat
      return "process=visible windows=" & windowCount & " " & windowSummaries as text
    end tell
  end tell
end run
APPLESCRIPT
}

write_scenario_artifact() {
  local scenario="$1"
  local scenario_status="$2"
  local scenario_reason="$3"
  local artifact_file="$ARTIFACT_DIR/$scenario.md"
  local window_context
  window_context="$(last_visible_window_context)"

  {
    printf '# Runtime Workflow Scenario\n\n'
    printf -- '- Scenario: `%s`\n' "$scenario"
    printf -- '- Status: `%s`\n' "$scenario_status"
    printf -- '- Reason: `%s`\n' "$scenario_reason"
    printf -- '- Last visible window: `%s`\n' "$window_context"
    printf -- '- Artifact directory: `%s`\n' "${ARTIFACT_DIR#"$ROOT_DIR/"}"
  } >"$artifact_file"
}

run_project_task_crud() {
  local scenario_output
  local scenario_status="failed"
  local scenario_reason="project/task CRUD scenario did not finish"

  if scenario_output="$(SOLOPM_RUNTIME_ACCESSIBLE_CRUD_KEEP_DATABASE=1 ./script/check_runtime_accessible_crud_smoke.sh 2>&1)"; then
    printf '%s\n' "$scenario_output"
    scenario_status="passed"
    scenario_reason="project/task CRUD SQLite postconditions passed"
    write_scenario_artifact "project_task_crud" "$scenario_status" "$scenario_reason"
    return 0
  fi

  printf '%s\n' "$scenario_output" >&2
  scenario_reason="project_task_crud command failed"
  write_scenario_artifact "project_task_crud" "$scenario_status" "$scenario_reason"
  echo "BLOCKER: runtime workflow scenario failed: project_task_crud - $scenario_reason" >&2
  return 1
}

run_inbox_triage() {
  local scenario_output
  local scenario_status="failed"
  local scenario_reason="inbox_triage scenario did not finish"

  if scenario_output="$(SOLOPM_RUNTIME_INBOX_TRIAGE_KEEP_DATABASE=1 ./script/check_runtime_inbox_triage_smoke.sh 2>&1)"; then
    printf '%s\n' "$scenario_output"
    scenario_status="passed"
    scenario_reason="Inbox quick add, classification actions, and undo SQLite postconditions passed"
    write_scenario_artifact "inbox_triage" "$scenario_status" "$scenario_reason"
    return 0
  fi

  printf '%s\n' "$scenario_output" >&2
  scenario_reason="inbox_triage command failed"
  write_scenario_artifact "inbox_triage" "$scenario_status" "$scenario_reason"
  echo "BLOCKER: runtime workflow scenario failed: inbox_triage - $scenario_reason" >&2
  return 1
}

run_today_complete() {
  local scenario_status="failed"
  local scenario_reason="today_complete runtime DB assertion is not implemented yet"
  write_scenario_artifact "today_complete" "$scenario_status" "$scenario_reason"
  echo "BLOCKER: runtime workflow scenario failed: today_complete - $scenario_reason" >&2
  return 1
}

run_settings_save() {
  local scenario_status="failed"
  local scenario_reason="settings_save runtime store assertion is not implemented yet"
  write_scenario_artifact "settings_save" "$scenario_status" "$scenario_reason"
  echo "BLOCKER: runtime workflow scenario failed: settings_save - $scenario_reason" >&2
  return 1
}

run_voice_review() {
  local scenario_status="failed"
  local scenario_reason="voice_review approval-boundary runtime assertion is not implemented yet"
  write_scenario_artifact "voice_review" "$scenario_status" "$scenario_reason"
  echo "BLOCKER: runtime workflow scenario failed: voice_review - $scenario_reason" >&2
  return 1
}

failure_count=0
for scenario in "${REQUESTED_SCENARIOS[@]}"; do
  if ! scenario_is_known "$scenario"; then
    echo "BLOCKER: unknown runtime workflow scenario: $scenario" >&2
    failure_count=$((failure_count + 1))
    continue
  fi

  if "run_$scenario"; then
    printf 'OK: runtime workflow scenario passed: %s\n' "$scenario"
  else
    failure_count=$((failure_count + 1))
  fi
done

if [[ "$failure_count" -gt 0 ]]; then
  echo "BLOCKER: runtime workflow smoke failed with $failure_count scenario failure(s). Artifacts: ${ARTIFACT_DIR#"$ROOT_DIR/"}" >&2
  exit 1
fi

printf 'OK: runtime workflow smoke passed (%s scenario(s))\n' "${#REQUESTED_SCENARIOS[@]}"
