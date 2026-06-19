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
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
SOURCE_ONLY=1
RUN_RUNTIME=0
LAUNCH_APP=1
TIMEOUT_SECONDS=12

REQUIRED_SOURCE_ANCHORS=(
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-board-sidebar"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::Project navigation"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-board-detail"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-kanban-board"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::task-card-open-details"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::task-status-move-controls"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::inline-task-title"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::inline-task-detail"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::inline-task-priority"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::inline-task-due"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::inline-task-create"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::inline-task-cancel"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::task-inspector"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::task-inspector-title"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::task-inspector-save"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::task-inspector-delete"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-inspector"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-inspector-save"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-inspector-delete"
  "Sources/SoloPMApp/Views/ProjectWorkflowViews.swift::sidebar-destination-"
  "Sources/SoloPMApp/Views/ProjectWorkflowViews.swift::inbox-quick-add-button"
  "Sources/SoloPMApp/Views/ProjectWorkflowViews.swift::workflow-task-row-"
  "Sources/SoloPMApp/Views/ProjectWorkflowViews.swift::workflow-task-completion-"
  "Sources/SoloPMApp/Views/ProjectWorkflowViews.swift::inbox-action-panel"
  "Sources/SoloPMApp/Views/ProjectWorkflowViews.swift::today-plan-summary"
)

usage() {
  printf '%s\n' "usage: $0 [--source-only|--runtime] [--app-bundle PATH] [--skip-launch] [--timeout SECONDS]"
  printf '%s\n' ""
  printf '%s\n' "Checks accessibility anchors before the manual VoiceOver release pass."
  printf '%s\n' "This is not a substitute for the manual VoiceOver pass."
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --source-only)
      SOURCE_ONLY=1
      RUN_RUNTIME=0
      shift
      ;;
    --runtime)
      SOURCE_ONLY=0
      RUN_RUNTIME=1
      shift
      ;;
    --app-bundle)
      APP_BUNDLE="${2:-}"
      shift 2
      ;;
    --skip-launch)
      LAUNCH_APP=0
      shift
      ;;
    --timeout)
      TIMEOUT_SECONDS="${2:-}"
      shift 2
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

if [[ ! "$TIMEOUT_SECONDS" =~ ^[0-9]+$ || "$TIMEOUT_SECONDS" -lt 1 ]]; then
  echo "--timeout must be a positive integer" >&2
  exit 2
fi

missing_count=0
for anchor in "${REQUIRED_SOURCE_ANCHORS[@]}"; do
  source_file="${anchor%%::*}"
  needle="${anchor#*::}"
  source_path="$ROOT_DIR/$source_file"

  if [[ ! -f "$source_path" ]]; then
    echo "BLOCKER: missing source file for accessibility preflight: $source_file" >&2
    missing_count=$((missing_count + 1))
    continue
  fi

  if ! grep -F "$needle" "$source_path" >/dev/null; then
    echo "BLOCKER: missing accessibility anchor '$needle' in $source_file" >&2
    missing_count=$((missing_count + 1))
  fi
done

if [[ "$missing_count" -gt 0 ]]; then
  echo "accessibility source anchor preflight failed" >&2
  exit 1
fi

printf 'OK: accessibility source anchors are present (%d anchors)\n' "${#REQUIRED_SOURCE_ANCHORS[@]}"

if [[ "$SOURCE_ONLY" -eq 1 && "$RUN_RUNTIME" -eq 0 ]]; then
  printf '%s\n' 'This is not a substitute for the manual VoiceOver pass.'
  exit 0
fi

if [[ "$RUN_RUNTIME" -ne 1 ]]; then
  exit 0
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "BLOCKER: app bundle not found: $APP_BUNDLE" >&2
  echo "NEXT: run ./script/build_and_run.sh --verify before --runtime accessibility preflight." >&2
  exit 2
fi

if [[ "$LAUNCH_APP" -eq 1 ]]; then
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  /usr/bin/open -n -F "$APP_BUNDLE"
  /usr/bin/osascript -e "tell application \"$APP_NAME\" to activate" >/dev/null 2>&1 || true
fi

deadline=$((SECONDS + TIMEOUT_SECONDS))
while ! pgrep -x "$APP_NAME" >/dev/null 2>&1; do
  if [[ "$SECONDS" -ge "$deadline" ]]; then
    echo "BLOCKER: $APP_NAME process did not appear within ${TIMEOUT_SECONDS}s" >&2
    exit 1
  fi
  sleep 1
done

set +e
ax_output="$(/usr/bin/osascript - "$APP_NAME" <<'APPLESCRIPT' 2>&1
on run argv
  set appName to item 1 of argv
  tell application "System Events"
    if not (exists process appName) then error appName & " process is not visible to System Events"
    tell process appName
      set windowCount to count of windows
      if windowCount < 1 then error appName & " has no visible windows"
      set firstWindow to window 1
      set buttonCount to count of buttons of entire contents of firstWindow
      set textFieldCount to count of text fields of entire contents of firstWindow
      set staticTextCount to count of static texts of entire contents of firstWindow
      return "OK: runtime AX smoke visible, windows=" & windowCount & ", buttons=" & buttonCount & ", textFields=" & textFieldCount & ", staticTexts=" & staticTextCount
    end tell
  end tell
end run
APPLESCRIPT
)"
ax_status=$?
set -e

if [[ "$ax_status" -ne 0 ]]; then
  printf '%s\n' "$ax_output" >&2
  echo "BLOCKER: runtime AX smoke failed; grant Accessibility permission to Terminal/Codex and keep the Project Board window visible." >&2
  exit 1
fi

printf '%s\n' "$ax_output"
printf '%s\n' 'This is not a substitute for the manual VoiceOver pass.'
