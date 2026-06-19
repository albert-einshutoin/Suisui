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
REQUIRED_RUNTIME_CRUD_MARKERS=(
  "Shows archived projects"
  "Creates a new local project"
  "Opens the inline composer for a new local task"
  "Add task to Backlog"
  "Saves edits to the selected project"
  "Completes the selected project"
  "Archives the selected project"
  "Deletes the selected project"
)
REQUIRED_RUNTIME_FOCUS_MARKERS=(
  "Project navigation=>Project navigation"
  "Project board detail=>Review project tasks, open a task card, then use the inspector for edits."
  "Open task=>Opens task details in the inspector"
  "Inline Task Composer=>Opens the inline composer for a new local task"
  "Status controls=>Moves the task between board columns"
  "Task inspector=>Task inspector"
)

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
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::.help(\"Creates the task in the local SoloPM database\")"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::.help(\"Cancels task creation and returns focus to the board column\")"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::task-inspector"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::task-inspector-title"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::task-inspector-detail"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::task-inspector-status"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::task-inspector-priority"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::task-inspector-due"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::task-inspector-apply-suggestion"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::task-inspector-save"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::task-inspector-delete"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::.help(\"Applies the local next-step suggestion to the selected task\")"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::.help(\"Saves edits to the selected task in the local SoloPM database\")"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::.help(\"Deletes the selected task after confirmation\")"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-inspector"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-inspector-title"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-inspector-apply-suggestion"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-inspector-save"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-inspector-complete"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-inspector-restore"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-inspector-archive"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-inspector-delete"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::.help(\"Applies the local next-step suggestion to the selected project\")"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::.help(\"Saves edits to the selected project in the local SoloPM database\")"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::.help(\"Restores the selected project to active views in the local SoloPM database\")"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::.help(\"Completes the selected project in the local SoloPM database\")"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::.help(\"Archives the selected project after confirmation\")"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::.help(\"Deletes the selected project after confirmation\")"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-overview-task-open-"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-overview-add-task"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-local-suggestion-open-task"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-local-suggestion-unblock-task"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-artifact-path"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-artifact-track"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-artifact-remove-"
  "Sources/SoloPMApp/Views/ProjectWorkflowViews.swift::sidebar-destination-"
  "Sources/SoloPMApp/Views/ProjectWorkflowViews.swift::inbox-quick-add-button"
  "Sources/SoloPMApp/Views/ProjectWorkflowViews.swift::workflow-task-row-"
  "Sources/SoloPMApp/Views/ProjectWorkflowViews.swift::workflow-task-completion-"
  "Sources/SoloPMApp/Views/ProjectWorkflowViews.swift::inbox-action-panel"
  "Sources/SoloPMApp/Views/ProjectWorkflowViews.swift::today-plan-summary"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::.keyboardShortcut(\"n\", modifiers: [.command])"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::.keyboardShortcut(\"n\", modifiers: [.command, .shift])"
  "Sources/SoloPMApp/SoloPMApp.swift::.keyboardShortcut(\",\", modifiers: [.command])"
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
  printf '%s\n' "Runtime smoke fails when the visible window has fewer than $MIN_AX_BUTTONS buttons, $MIN_AX_TEXT_FIELDS text field, $MIN_AX_STATIC_TEXTS static texts, unlabeled buttons, generic button labels without help or child text, missing primary CRUD button help signals, or missing VoiceOver focus path signals."
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
required_runtime_crud_markers_joined=""
for required_runtime_crud_marker in "${REQUIRED_RUNTIME_CRUD_MARKERS[@]}"; do
  if [[ -z "$required_runtime_crud_markers_joined" ]]; then
    required_runtime_crud_markers_joined="$required_runtime_crud_marker"
  else
    required_runtime_crud_markers_joined="${required_runtime_crud_markers_joined}|||${required_runtime_crud_marker}"
  fi
done
required_runtime_crud_marker_count="${#REQUIRED_RUNTIME_CRUD_MARKERS[@]}"
required_runtime_focus_markers_joined=""
for required_runtime_focus_marker in "${REQUIRED_RUNTIME_FOCUS_MARKERS[@]}"; do
  if [[ -z "$required_runtime_focus_markers_joined" ]]; then
    required_runtime_focus_markers_joined="$required_runtime_focus_marker"
  else
    required_runtime_focus_markers_joined="${required_runtime_focus_markers_joined}|||${required_runtime_focus_marker}"
  fi
done
required_runtime_focus_marker_count="${#REQUIRED_RUNTIME_FOCUS_MARKERS[@]}"
while true; do
  set +e
  ax_output="$(/usr/bin/osascript - "$APP_NAME" "$MIN_AX_BUTTONS" "$MIN_AX_TEXT_FIELDS" "$MIN_AX_STATIC_TEXTS" "$required_runtime_crud_markers_joined" "$required_runtime_crud_marker_count" "$required_runtime_focus_markers_joined" "$required_runtime_focus_marker_count" <<APPLESCRIPT 2>&1
on run argv
  set appName to item 1 of argv
  set minButtons to (item 2 of argv) as integer
  set minTextFields to (item 3 of argv) as integer
  set minStaticTexts to (item 4 of argv) as integer
  set requiredCRUDMarkersRaw to item 5 of argv
  set requiredCRUDMarkerCount to (item 6 of argv) as integer
  set requiredFocusMarkersRaw to item 7 of argv
  set requiredFocusMarkerCount to (item 8 of argv) as integer
  set previousTextItemDelimiters to text item delimiters of AppleScript
  set text item delimiters of AppleScript to "|||"
  set requiredCRUDMarkers to text items of requiredCRUDMarkersRaw
  set requiredFocusMarkers to text items of requiredFocusMarkersRaw
  set text item delimiters of AppleScript to previousTextItemDelimiters
  set bestSummary to ""
  set bestScore to -1
  set bestButtonCount to 0
  set bestTextFieldCount to 0
  set bestStaticTextCount to 0
  set bestUnlabeledButtonCount to 0
  set bestGenericButtonCount to 0
  set bestCRUDSignalCount to 0
  set bestMissingCRUDSignals to ""
  set bestFocusPathSignalCount to 0
  set bestMissingFocusPathSignals to ""
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
        set genericButtonCount to 0
        set genericButtonDetails to ""
        set buttonSignalText to ""
        set focusPathSignalText to ""
        set axItems to entire contents of currentWindow
        repeat with axItem in axItems
          set itemRole to ""
          set itemName to ""
          set itemTitle to ""
          set itemValue to ""
          set itemDescription to ""
          set itemHelp to ""
          try
            set itemRole to role of axItem as text
          end try
          try
            set itemName to name of axItem as text
          end try
          try
            set itemTitle to value of attribute "AXTitle" of axItem as text
          end try
          try
            set itemValue to value of axItem as text
          end try
          try
            set itemDescription to description of axItem as text
          end try
          try
            set itemHelp to value of attribute "AXHelp" of axItem as text
          end try
          set focusPathSignalText to focusPathSignalText & " " & itemName & " " & itemTitle & " " & itemValue & " " & itemDescription & " " & itemHelp
          if itemRole is "AXButton" then
            set buttonCount to buttonCount + 1
            set buttonName to ""
            set buttonTitle to ""
            set buttonDescription to ""
            set buttonHelp to ""
            set buttonPosition to ""
            set buttonSize to ""
            set childTextCount to 0
            try
              set buttonName to name of axItem as text
            end try
            try
              set buttonTitle to value of attribute "AXTitle" of axItem as text
            end try
            try
              set buttonDescription to description of axItem as text
            end try
            try
              set buttonHelp to value of attribute "AXHelp" of axItem as text
            end try
            try
              set buttonPosition to position of axItem as text
            end try
            try
              set buttonSize to size of axItem as text
            end try
            try
              repeat with childItem in entire contents of axItem
                set childRole to ""
                set childText to ""
                try
                  set childRole to role of childItem as text
                end try
                if childRole is "AXStaticText" then
                  try
                    set childText to name of childItem as text
                  end try
                  if childText is "" or childText is "missing value" then
                    try
                      set childText to value of childItem as text
                    end try
                  end if
                  if childText is not "" and childText is not "missing value" then set childTextCount to childTextCount + 1
                end if
              end repeat
            end try
            if buttonName is "" or buttonName is "missing value" then set buttonName to buttonTitle
            if buttonName is "" or buttonName is "missing value" then set buttonName to buttonDescription
            if buttonName is "" or buttonName is "missing value" then
              set unlabeledButtonCount to unlabeledButtonCount + 1
            else if buttonName is "button" and (buttonHelp is "" or buttonHelp is "missing value") and childTextCount is 0 then
              set genericButtonCount to genericButtonCount + 1
              set genericButtonDetail to "generic button #" & buttonCount & " title=" & buttonTitle & " description=" & buttonDescription & " childTexts=" & childTextCount & " position=" & buttonPosition & " size=" & buttonSize
              if genericButtonDetails is "" then
                set genericButtonDetails to genericButtonDetail
              else if genericButtonCount <= 3 then
                set genericButtonDetails to genericButtonDetails & "; " & genericButtonDetail
              end if
            end if
            set buttonSignalText to buttonSignalText & " " & buttonName & " " & buttonTitle & " " & buttonDescription & " " & buttonHelp
          end if
          if itemRole is "AXTextField" or itemRole is "AXTextArea" then set textFieldCount to textFieldCount + 1
          if itemRole is "AXStaticText" then set staticTextCount to staticTextCount + 1
        end repeat
        set crudSignalCount to 0
        set missingCRUDSignals to ""
        repeat with requiredCRUDMarker in requiredCRUDMarkers
          set requiredCRUDMarkerText to requiredCRUDMarker as text
          if requiredCRUDMarkerText is not "" then
            if buttonSignalText contains requiredCRUDMarkerText then
              set crudSignalCount to crudSignalCount + 1
            else
              if missingCRUDSignals is "" then
                set missingCRUDSignals to requiredCRUDMarkerText
              else
                set missingCRUDSignals to missingCRUDSignals & "; " & requiredCRUDMarkerText
              end if
            end if
          end if
        end repeat
        set focusPathSignalCount to 0
        set missingFocusPathSignals to ""
        repeat with requiredFocusMarker in requiredFocusMarkers
          set requiredFocusMarkerText to requiredFocusMarker as text
          if requiredFocusMarkerText is not "" then
            set requiredFocusMarkerLabel to requiredFocusMarkerText
            set requiredFocusMarkerNeedle to requiredFocusMarkerText
            set focusMarkerSeparatorOffset to offset of "=>" in requiredFocusMarkerText
            if focusMarkerSeparatorOffset > 0 then
              set requiredFocusMarkerLabel to text 1 thru (focusMarkerSeparatorOffset - 1) of requiredFocusMarkerText
              set requiredFocusMarkerNeedle to text (focusMarkerSeparatorOffset + 2) thru -1 of requiredFocusMarkerText
            end if
            if focusPathSignalText contains requiredFocusMarkerNeedle then
              set focusPathSignalCount to focusPathSignalCount + 1
            else
              if missingFocusPathSignals is "" then
                set missingFocusPathSignals to requiredFocusMarkerLabel
              else
                set missingFocusPathSignals to missingFocusPathSignals & "; " & requiredFocusMarkerLabel
              end if
            end if
          end if
        end repeat
        set currentSummary to "window=" & windowIndex & " name=" & windowName & ", buttons=" & buttonCount & ", textFields=" & textFieldCount & ", staticTexts=" & staticTextCount & ", unlabeledButtons=" & unlabeledButtonCount & ", genericButtons=" & genericButtonCount & ", crudSignals=" & crudSignalCount & "/" & requiredCRUDMarkerCount & ", focusPathSignals=" & focusPathSignalCount & "/" & requiredFocusMarkerCount
        if genericButtonDetails is not "" then set currentSummary to currentSummary & ", genericButtonDetails=" & genericButtonDetails
        set currentScore to buttonCount + textFieldCount + staticTextCount
        if bestSummary is "" then
          set bestSummary to currentSummary
          set bestScore to currentScore
          set bestButtonCount to buttonCount
          set bestTextFieldCount to textFieldCount
          set bestStaticTextCount to staticTextCount
          set bestUnlabeledButtonCount to unlabeledButtonCount
          set bestGenericButtonCount to genericButtonCount
          set bestCRUDSignalCount to crudSignalCount
          set bestMissingCRUDSignals to missingCRUDSignals
          set bestFocusPathSignalCount to focusPathSignalCount
          set bestMissingFocusPathSignals to missingFocusPathSignals
        else if currentScore > bestScore then
          set bestSummary to currentSummary
          set bestScore to currentScore
          set bestButtonCount to buttonCount
          set bestTextFieldCount to textFieldCount
          set bestStaticTextCount to staticTextCount
          set bestUnlabeledButtonCount to unlabeledButtonCount
          set bestGenericButtonCount to genericButtonCount
          set bestCRUDSignalCount to crudSignalCount
          set bestMissingCRUDSignals to missingCRUDSignals
          set bestFocusPathSignalCount to focusPathSignalCount
          set bestMissingFocusPathSignals to missingFocusPathSignals
        end if
        if buttonCount >= minButtons and textFieldCount >= minTextFields and staticTextCount >= minStaticTexts and unlabeledButtonCount is 0 and genericButtonCount is 0 and crudSignalCount is requiredCRUDMarkerCount and focusPathSignalCount is requiredFocusMarkerCount then
          return "OK: runtime AX smoke visible, windows=" & windowCount & ", " & currentSummary
        end if
      end repeat
      if bestSummary is "" then set bestSummary to "windows=" & windowCount & ", no AX elements inspected"
      if bestSummary does not contain "buttons=" then error "runtime AX smoke could not inspect visible window AX elements: " & bestSummary
      if bestButtonCount < minButtons then error "runtime AX smoke has too few buttons: " & bestButtonCount & " < " & minButtons & " (" & bestSummary & ")"
      if bestTextFieldCount < minTextFields then error "runtime AX smoke has too few text fields: " & bestTextFieldCount & " < " & minTextFields & " (" & bestSummary & ")"
      if bestStaticTextCount < minStaticTexts then error "runtime AX smoke has too few static texts: " & bestStaticTextCount & " < " & minStaticTexts & " (" & bestSummary & ")"
      if bestUnlabeledButtonCount > 0 then error "runtime AX smoke has unlabeled buttons: " & bestUnlabeledButtonCount & " (" & bestSummary & ")"
      if bestGenericButtonCount > 0 then error "runtime AX smoke has generic button labels without help or child text: " & bestGenericButtonCount & " (" & bestSummary & ")"
      if bestCRUDSignalCount < requiredCRUDMarkerCount then error "runtime AX smoke is missing primary CRUD button labels or help: " & bestMissingCRUDSignals & " (" & bestSummary & ")"
      if bestFocusPathSignalCount < requiredFocusMarkerCount then error "runtime AX smoke is missing VoiceOver focus path labels or help: " & bestMissingFocusPathSignals & " (" & bestSummary & ")"
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
