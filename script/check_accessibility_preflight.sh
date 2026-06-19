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
SKIP_SOURCE_ANCHORS=0
TIMEOUT_SECONDS=12
MIN_AX_BUTTONS=5
MIN_AX_TEXT_FIELDS=1
MIN_AX_STATIC_TEXTS=5

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
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::task-inspector-detail"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::task-inspector-status"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::task-inspector-priority"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::task-inspector-due"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::task-inspector-apply-suggestion"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::task-inspector-save"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::task-inspector-delete"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-inspector"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-inspector-title"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-inspector-apply-suggestion"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-inspector-save"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-inspector-complete"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-inspector-restore"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-inspector-archive"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-inspector-delete"
  "Sources/SoloPMApp/Views/ProjectWorkflowViews.swift::sidebar-destination-"
  "Sources/SoloPMApp/Views/ProjectWorkflowViews.swift::inbox-quick-add-button"
  "Sources/SoloPMApp/Views/ProjectWorkflowViews.swift::workflow-task-row-"
  "Sources/SoloPMApp/Views/ProjectWorkflowViews.swift::workflow-task-completion-"
  "Sources/SoloPMApp/Views/ProjectWorkflowViews.swift::inbox-action-panel"
  "Sources/SoloPMApp/Views/ProjectWorkflowViews.swift::today-plan-summary"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::.keyboardShortcut(\"n\", modifiers: [.command])"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::.keyboardShortcut(\"n\", modifiers: [.command, .shift])"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::.keyboardShortcut(\",\", modifiers: [.command])"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::.keyboardShortcut(\"s\", modifiers: [.command])"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::.keyboardShortcut(.delete, modifiers: [.command])"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::.keyboardShortcut(.return, modifiers: [.command])"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::.keyboardShortcut(.escape, modifiers: [])"
  "Sources/SoloPMApp/Views/ProjectWorkflowViews.swift::.keyboardShortcut(\"1\", modifiers: [.command])"
  "Sources/SoloPMApp/Views/ProjectWorkflowViews.swift::.keyboardShortcut(\"2\", modifiers: [.command])"
  "Sources/SoloPMApp/Views/ProjectWorkflowViews.swift::.keyboardShortcut(\"3\", modifiers: [.command])"
  "Sources/SoloPMApp/Views/ProjectWorkflowViews.swift::.keyboardShortcut(\"4\", modifiers: [.command])"
  "Sources/SoloPMApp/SoloPMApp.swift::.keyboardShortcut(.return, modifiers: [.command])"
)

usage() {
  printf '%s\n' "usage: $0 [--source-only|--runtime] [--skip-source-anchors] [--app-bundle PATH] [--skip-launch] [--timeout SECONDS]"
  printf '%s\n' ""
  printf '%s\n' "Checks accessibility anchors before the manual VoiceOver release pass."
  printf '%s\n' "This is not a substitute for the manual VoiceOver pass."
  printf '%s\n' "Runtime smoke fails when the visible window has fewer than $MIN_AX_BUTTONS buttons, $MIN_AX_TEXT_FIELDS text field, or $MIN_AX_STATIC_TEXTS static texts."
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
    --skip-source-anchors)
      SKIP_SOURCE_ANCHORS=1
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

if [[ "$SKIP_SOURCE_ANCHORS" -eq 1 && "$RUN_RUNTIME" -ne 1 ]]; then
  echo "--skip-source-anchors requires --runtime" >&2
  exit 2
fi

if [[ "$SKIP_SOURCE_ANCHORS" -ne 1 ]]; then
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
fi

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

ax_deadline=$((SECONDS + TIMEOUT_SECONDS))
ax_output=""
ax_status=1
while true; do
  set +e
  ax_output="$(/usr/bin/osascript - "$APP_NAME" "$MIN_AX_BUTTONS" "$MIN_AX_TEXT_FIELDS" "$MIN_AX_STATIC_TEXTS" <<'APPLESCRIPT' 2>&1
on run argv
  set appName to item 1 of argv
  set minButtons to (item 2 of argv) as integer
  set minTextFields to (item 3 of argv) as integer
  set minStaticTexts to (item 4 of argv) as integer
  set bestSummary to ""
  set bestScore to -1
  set bestButtonCount to 0
  set bestTextFieldCount to 0
  set bestStaticTextCount to 0
  set bestUnlabeledButtonCount to 0
  tell application "System Events"
    if not (exists process appName) then error appName & " process is not visible to System Events"
    tell process appName
      set windowCount to count of windows
      if windowCount < 1 then error appName & " has no visible windows"
      repeat with windowIndex from 1 to windowCount
        set currentWindow to window windowIndex
        set windowName to ""
        try
          set windowName to name of currentWindow as text
        end try
        set buttonCount to 0
        set textFieldCount to 0
        set staticTextCount to 0
        set unlabeledButtonCount to 0
        set axItems to entire contents of currentWindow
        repeat with axItem in axItems
          set itemRole to ""
          try
            set itemRole to role of axItem as text
          end try
          if itemRole is "AXButton" then
            set buttonCount to buttonCount + 1
            set buttonName to ""
            try
              set buttonName to name of axItem as text
            end try
            if buttonName is "" or buttonName is "missing value" then
              try
                set buttonName to description of axItem as text
              end try
            end if
            if buttonName is "" or buttonName is "missing value" then set unlabeledButtonCount to unlabeledButtonCount + 1
          end if
          if itemRole is "AXTextField" or itemRole is "AXTextArea" then set textFieldCount to textFieldCount + 1
          if itemRole is "AXStaticText" then set staticTextCount to staticTextCount + 1
        end repeat
        set currentSummary to "window=" & windowIndex & " name=" & windowName & ", buttons=" & buttonCount & ", textFields=" & textFieldCount & ", staticTexts=" & staticTextCount & ", unlabeledButtons=" & unlabeledButtonCount
        set currentScore to buttonCount + textFieldCount + staticTextCount
        if bestSummary is "" then
          set bestSummary to currentSummary
          set bestScore to currentScore
          set bestButtonCount to buttonCount
          set bestTextFieldCount to textFieldCount
          set bestStaticTextCount to staticTextCount
          set bestUnlabeledButtonCount to unlabeledButtonCount
        else if currentScore > bestScore then
          set bestSummary to currentSummary
          set bestScore to currentScore
          set bestButtonCount to buttonCount
          set bestTextFieldCount to textFieldCount
          set bestStaticTextCount to staticTextCount
          set bestUnlabeledButtonCount to unlabeledButtonCount
        end if
        if buttonCount >= minButtons and textFieldCount >= minTextFields and staticTextCount >= minStaticTexts and unlabeledButtonCount is 0 then
          return "OK: runtime AX smoke visible, windows=" & windowCount & ", " & currentSummary
        end if
      end repeat
      if bestSummary is "" then set bestSummary to "windows=" & windowCount & ", no AX elements inspected"
      if bestSummary does not contain "buttons=" then error "runtime AX smoke could not inspect visible window AX elements: " & bestSummary
      if bestButtonCount < minButtons then error "runtime AX smoke has too few buttons: " & bestButtonCount & " < " & minButtons & " (" & bestSummary & ")"
      if bestTextFieldCount < minTextFields then error "runtime AX smoke has too few text fields: " & bestTextFieldCount & " < " & minTextFields & " (" & bestSummary & ")"
      if bestStaticTextCount < minStaticTexts then error "runtime AX smoke has too few static texts: " & bestStaticTextCount & " < " & minStaticTexts & " (" & bestSummary & ")"
      if bestUnlabeledButtonCount > 0 then error "runtime AX smoke has unlabeled buttons: " & bestUnlabeledButtonCount & " (" & bestSummary & ")"
      error "runtime AX smoke did not find a qualifying visible window: " & bestSummary
    end tell
  end tell
end run
APPLESCRIPT
)"
  ax_status=$?
  set -e

  if [[ "$ax_status" -eq 0 ]]; then
    break
  fi

  if [[ "$SECONDS" -ge "$ax_deadline" ]]; then
    break
  fi

  sleep 1
done

if [[ "$ax_status" -ne 0 ]]; then
  printf '%s\n' "$ax_output" >&2
  echo "BLOCKER: runtime AX smoke did not pass within ${TIMEOUT_SECONDS}s" >&2
  echo "BLOCKER: runtime AX smoke failed; grant Accessibility permission to Terminal/Codex and keep the Project Board window visible." >&2
  exit 1
fi

printf '%s\n' "$ax_output"
printf '%s\n' 'This is not a substitute for the manual VoiceOver pass.'
