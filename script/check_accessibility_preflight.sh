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
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
SOURCE_ONLY=1
RUN_RUNTIME=0
LAUNCH_APP=1
SKIP_SOURCE_ANCHORS=0
LAUNCH_ENV_FILE=""
DEFAULT_VOICEOVER_LAUNCH_ENV_FILE="$ROOT_DIR/.tmp/voiceover-review/launch.env"
TIMEOUT_SECONDS=12
APP_LAUNCH_PID=""
MIN_AX_BUTTONS=5
MIN_AX_TEXT_FIELDS=1
MIN_AX_STATIC_TEXTS=5
REQUIRED_RUNTIME_CRUD_MARKERS=(
  "project-header-add-task"
  "task-card-open-details"
  "task-status-move-"
  "task-inspector-apply-suggestion"
  "task-inspector-save"
  "task-auto-execution-review"
  "task-auto-execution-run-plan"
  "task-inspector-delete"
)
REQUIRED_RUNTIME_FOCUS_MARKERS=(
  "Project navigation=>project-board-sidebar"
  "Project board detail=>project-board-detail"
  "Open task=>task-card-open-details"
  "Inline Task Composer=>project-header-add-task"
  "Status controls=>task-status-move-controls"
  "Task inspector=>task-inspector"
)
REQUIRED_RUNTIME_BUTTON_A11Y_MARKERS=(
  "project-header-add-task=>Add task"
  "task-card-open-details=>Open task"
  "task-status-move-=>Move"
  "task-inspector-apply-suggestion=>Applies the local next-step suggestion"
  "task-inspector-save=>Saves edits"
  "task-auto-execution-review=>Prepares review-only local automation"
  "task-auto-execution-run-plan=>Runs the reviewed local task step"
  "task-inspector-delete=>Deletes the selected task"
)
REQUIRED_RUNTIME_SCREEN_MARKERS=(
  "Inbox sidebar=>sidebar-destination-inbox"
  "Today sidebar=>sidebar-destination-today"
  "Settings toolbar=>project-board-settings-link"
  "Voice Command toolbar=>project-board-voice-command"
)
REQUIRED_RUNTIME_DESTRUCTIVE_CANCEL_MARKERS=(
  "Delete task cancel=>task-inspector-delete-confirmation-cancel"
)

REQUIRED_SOURCE_ANCHORS=(
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-board-sidebar"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::Project navigation"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-board-detail"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-kanban-board"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-board-show-archived"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-board-add-project"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-header-add-task"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::task-card-open-details"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::task-status-move-controls"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::task-status-move-"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::inline-task-title"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::inline-task-detail"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::inline-task-priority"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::inline-task-due"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::inline-task-create"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::inline-task-cancel"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::.help(\"Creates the task in the local SoloPM database\")"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::.help(\"Cancels task creation and returns focus to the board column\")"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-board-task-auto-execution-review"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::.help(\"Prepares review-only task automation from the configured priority, due-date, cadence, and daily budget settings\")"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::task-inspector"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::task-inspector-title"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::task-inspector-detail"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::task-inspector-status"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::task-inspector-priority"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::task-inspector-due"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::task-inspector-apply-suggestion"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::task-inspector-save"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::task-auto-execution-review"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::task-auto-execution-run-plan"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::task-inspector-delete"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::task-inspector-delete-confirmation-cancel"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::.help(\"Applies the local next-step suggestion to the selected task\")"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::.help(\"Saves edits to the selected task in the local SoloPM database\")"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::.help(\"Prepares review-only local automation for the selected task\")"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::.help(\"Runs the reviewed local task step after explicit user approval\")"
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
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-local-suggestion-review-action"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-artifact-path"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-artifact-track"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::project-artifact-remove-"
  "Sources/SoloPMApp/Views/ProjectWorkflowViews.swift::sidebar-destination-"
  "Sources/SoloPMApp/Views/ProjectWorkflowInboxView.swift::inbox-quick-add-button"
  "Sources/SoloPMApp/Views/ProjectWorkflowSharedViews.swift::workflow-task-row-"
  "Sources/SoloPMApp/Views/ProjectWorkflowSharedViews.swift::workflow-task-completion-"
  "Sources/SoloPMApp/Views/ProjectWorkflowInboxView.swift::inbox-action-panel"
  "Sources/SoloPMApp/Views/ProjectWorkflowSharedViews.swift::inbox-row-triage-summary-"
  "Sources/SoloPMApp/Views/ProjectWorkflowInboxView.swift::inbox-action-grid"
  "Sources/SoloPMApp/Views/ProjectWorkflowInboxView.swift::inbox-voice-intake-detail"
  "Sources/SoloPMApp/Views/ProjectWorkflowInboxView.swift::inbox-voice-transcript-preview"
  "Sources/SoloPMApp/Views/ProjectWorkflowInboxView.swift::inbox-voice-waveform"
  "Sources/SoloPMApp/Views/ProjectWorkflowInboxView.swift::inbox-voice-transcript"
  "Sources/SoloPMApp/Views/ProjectWorkflowInboxView.swift::inbox-voice-interpretation"
  "Sources/SoloPMApp/Views/ProjectWorkflowInboxView.swift::inbox-voice-memo-editor"
  "Sources/SoloPMApp/Views/ProjectWorkflowInboxView.swift::inbox-voice-memo-save"
  "Sources/SoloPMApp/Views/ProjectWorkflowTodayView.swift::today-plan-summary"
  "Sources/SoloPMApp/Views/ProjectWorkflowCatchUpView.swift::catch-up-workflow"
  "Sources/SoloPMApp/Views/ProjectWorkflowCatchUpView.swift::catch-up-missed-review-panel"
  "Sources/SoloPMApp/Views/ProjectWorkflowCatchUpView.swift::catch-up-missed-review-row-"
  "Sources/SoloPMApp/Views/ProjectWorkflowCatchUpView.swift::catch-up-missed-complete-"
  "Sources/SoloPMApp/Views/ProjectWorkflowCatchUpView.swift::catch-up-missed-reschedule-"
  "Sources/SoloPMApp/Views/ProjectWorkflowCatchUpView.swift::catch-up-missed-defer-"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::.keyboardShortcut(\"n\", modifiers: [.command])"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::.keyboardShortcut(\"n\", modifiers: [.command, .shift])"
  "Sources/SoloPMApp/SoloPMApp.swift::.keyboardShortcut(\",\", modifiers: [.command])"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::.keyboardShortcut(\"s\", modifiers: [.command])"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::.keyboardShortcut(.delete, modifiers: [.command])"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::.keyboardShortcut(.return, modifiers: [.command])"
  "Sources/SoloPMApp/Views/ProjectBoardView.swift::.keyboardShortcut(.escape, modifiers: [])"
  "Sources/SoloPMApp/Views/ProjectWorkflowInboxView.swift::.keyboardShortcut(\"1\", modifiers: [.command])"
  "Sources/SoloPMApp/Views/ProjectWorkflowInboxView.swift::.keyboardShortcut(\"2\", modifiers: [.command])"
  "Sources/SoloPMApp/Views/ProjectWorkflowInboxView.swift::.keyboardShortcut(\"3\", modifiers: [.command])"
  "Sources/SoloPMApp/Views/ProjectWorkflowInboxView.swift::.keyboardShortcut(\"4\", modifiers: [.command])"
  "Sources/SoloPMApp/Views/MenuBarPanel.swift::.keyboardShortcut(.return, modifiers: [.command])"
)

usage() {
  printf '%s\n' "usage: $0 [--source-only|--runtime] [--skip-source-anchors] [--app-bundle PATH] [--launch-env PATH] [--skip-launch] [--timeout SECONDS]"
  printf '%s\n' ""
  printf '%s\n' "Checks accessibility anchors before the manual VoiceOver release pass."
  printf '%s\n' "This is not a substitute for the manual VoiceOver pass."
  printf '%s\n' "Runtime smoke fails when the visible window has fewer than $MIN_AX_BUTTONS buttons, $MIN_AX_TEXT_FIELDS text field, $MIN_AX_STATIC_TEXTS static texts, unlabeled buttons, generic button labels without help or child text, missing primary CRUD button help signals, missing primary button label/help signals, missing workflow screen entry signals, missing destructive cancellation signals, or missing VoiceOver focus path signals."
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
    --launch-env)
      LAUNCH_ENV_FILE="${2:-}"
      shift 2
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

launched_app_matches_binary() {
  local process_command
  [[ "$APP_LAUNCH_PID" =~ ^[1-9][0-9]*$ ]] || return 1
  process_command="$(ps -p "$APP_LAUNCH_PID" -o command= 2>/dev/null)" || return 1
  process_command="${process_command#"${process_command%%[![:space:]]*}"}"
  case "$process_command" in
    "$APP_BINARY"|"$APP_BINARY "*) return 0 ;;
  esac
  return 1
}

cleanup_launched_app() {
  if launched_app_matches_binary; then
    kill -TERM "$APP_LAUNCH_PID" >/dev/null 2>&1 || true
    local deadline=$((SECONDS + 3))
    while launched_app_matches_binary && [[ "$SECONDS" -lt "$deadline" ]]; do
      sleep 0.1
    done
    if launched_app_matches_binary; then
      kill -KILL "$APP_LAUNCH_PID" >/dev/null 2>&1 || true
    fi
    wait "$APP_LAUNCH_PID" >/dev/null 2>&1 || true
  fi
  APP_LAUNCH_PID=""
}
trap cleanup_launched_app EXIT INT TERM

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

if [[ "$LAUNCH_APP" -eq 1 && -z "$LAUNCH_ENV_FILE" ]]; then
  if [[ ! -x "$ROOT_DIR/script/prepare_voiceover_review_candidate.sh" ]]; then
    echo "BLOCKER: missing VoiceOver candidate preparation script: script/prepare_voiceover_review_candidate.sh" >&2
    exit 2
  fi

  # Runtime AX needs a deterministic Project Board with task cards and inspector fields;
  # LaunchServices can start the debug app without a useful window, so default to the same
  # seeded candidate used by automated release preflight when no explicit env is provided.
  (
    cd "$ROOT_DIR"
    ./script/prepare_voiceover_review_candidate.sh --skip-build --no-launch >/dev/null
  )
  LAUNCH_ENV_FILE="$DEFAULT_VOICEOVER_LAUNCH_ENV_FILE"
fi

if [[ -n "$LAUNCH_ENV_FILE" ]]; then
  case "$LAUNCH_ENV_FILE" in
    /*) ;;
    *) LAUNCH_ENV_FILE="$ROOT_DIR/$LAUNCH_ENV_FILE" ;;
  esac
  if [[ ! -f "$LAUNCH_ENV_FILE" ]]; then
    echo "BLOCKER: launch env not found for runtime accessibility preflight: $LAUNCH_ENV_FILE" >&2
    exit 2
  fi
  if [[ ! -x "$APP_BINARY" ]]; then
    echo "BLOCKER: app binary not found or not executable: $APP_BINARY" >&2
    exit 2
  fi
fi

activate_app() {
  # Keep activation inside System Events so LaunchServices does not start or
  # block on a second app instance outside the isolated launch environment.
  /usr/bin/osascript - "$APP_NAME" <<'APPLESCRIPT' >/dev/null 2>&1 &
on run argv
  set appName to item 1 of argv
  tell application "System Events"
    if not (exists process appName) then return "missing"
    tell process appName
      set frontmost to true
      if (count of windows) > 0 then
        try
          perform action "AXRaise" of window 1
        end try
      end if
    end tell
  end tell
  return "activated"
end run
APPLESCRIPT
  local osascript_pid=$!
  for _ in {1..20}; do
    if ! kill -0 "$osascript_pid" >/dev/null 2>&1; then
      wait "$osascript_pid" >/dev/null 2>&1 || true
      return 0
    fi
    sleep 0.1
  done
  kill "$osascript_pid" >/dev/null 2>&1 || true
  wait "$osascript_pid" >/dev/null 2>&1 || true
}

# The seeded review candidate opens the project inspector first. Press the
# task detail control before scanning so focusPathSignals proves task edit and
# delete controls, not only the project-level inspector.
open_task_inspector_for_runtime_focus_path() {
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local output=""
  while true; do
    set +e
    output="$(/usr/bin/osascript - "$APP_NAME" <<'APPLESCRIPT' 2>&1
on run argv
  set appName to item 1 of argv
  tell application "System Events"
    if not (exists process appName) then error appName & " process is not visible to System Events"
    tell process appName
      set frontmost to true
      set windowCount to count of windows
      if windowCount < 1 then error appName & " has no visible windows"
      repeat with windowIndex from 1 to windowCount
        set currentWindow to window windowIndex
        try
          perform action "AXRaise" of currentWindow
        end try
        set axItems to entire contents of currentWindow
        repeat with axItem in axItems
          set itemIdentifier to ""
          set itemName to ""
          set itemTitle to ""
          set itemDescription to ""
          set itemHelp to ""
          try
            set itemIdentifier to value of attribute "AXIdentifier" of axItem as text
          end try
          try
            set itemName to name of axItem as text
          end try
          try
            set itemTitle to value of attribute "AXTitle" of axItem as text
          end try
          try
            set itemDescription to description of axItem as text
          end try
          try
            set itemHelp to value of attribute "AXHelp" of axItem as text
          end try
          set itemSignal to itemIdentifier & " " & itemName & " " & itemTitle & " " & itemDescription & " " & itemHelp
          if itemSignal contains "task-inspector" then return "task inspector already visible"
        end repeat
        repeat with axItem in axItems
          set itemRole to ""
          set itemIdentifier to ""
          set itemName to ""
          set itemTitle to ""
          set itemDescription to ""
          set itemHelp to ""
          try
            set itemRole to role of axItem as text
          end try
          try
            set itemIdentifier to value of attribute "AXIdentifier" of axItem as text
          end try
          try
            set itemName to name of axItem as text
          end try
          try
            set itemTitle to value of attribute "AXTitle" of axItem as text
          end try
          try
            set itemDescription to description of axItem as text
          end try
          try
            set itemHelp to value of attribute "AXHelp" of axItem as text
          end try
          set itemSignal to itemIdentifier & " " & itemName & " " & itemTitle & " " & itemDescription & " " & itemHelp
          if itemRole is "AXButton" and itemSignal contains "task-card-open-details" then
            perform action "AXPress" of axItem
            delay 0.4
            return "opened task inspector"
          end if
        end repeat
      end repeat
    end tell
  end tell
  error "task-card-open-details button not found"
end run
APPLESCRIPT
)"
    local status=$?
    set -e
    if [[ "$status" -eq 0 ]]; then
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: runtime AX smoke could not open task inspector from task-card-open-details: $output" >&2
      return 1
    fi
    activate_app
    sleep 1
  done
}

open_task_delete_confirmation_for_runtime_focus_path() {
  local required_runtime_destructive_cancel_markers_joined=""
  for required_runtime_destructive_cancel_marker in "${REQUIRED_RUNTIME_DESTRUCTIVE_CANCEL_MARKERS[@]}"; do
    if [[ -z "$required_runtime_destructive_cancel_markers_joined" ]]; then
      required_runtime_destructive_cancel_markers_joined="$required_runtime_destructive_cancel_marker"
    else
      required_runtime_destructive_cancel_markers_joined="${required_runtime_destructive_cancel_markers_joined}|||${required_runtime_destructive_cancel_marker}"
    fi
  done

  local required_runtime_destructive_cancel_marker_count="${#REQUIRED_RUNTIME_DESTRUCTIVE_CANCEL_MARKERS[@]}"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local output=""
  local status=1
  while true; do
    set +e
    output="$(/usr/bin/osascript - "$APP_NAME" "$required_runtime_destructive_cancel_markers_joined" "$required_runtime_destructive_cancel_marker_count" <<'APPLESCRIPT' 2>&1
on run argv
  set appName to item 1 of argv
  set requiredDestructiveCancelMarkersRaw to item 2 of argv
  set requiredDestructiveCancelMarkerCount to (item 3 of argv) as integer
  set previousTextItemDelimiters to text item delimiters of AppleScript
  set text item delimiters of AppleScript to "|||"
  set requiredDestructiveCancelMarkers to text items of requiredDestructiveCancelMarkersRaw
  set text item delimiters of AppleScript to previousTextItemDelimiters
  set bestSummary to ""
  set bestDestructiveCancelSignalCount to 0
  set bestMissingDestructiveCancelSignals to ""
  tell application "System Events"
    if not (exists process appName) then error appName & " process is not visible to System Events"
    tell process appName
      set frontmost to true
      set windowCount to count of windows
      if windowCount < 1 then error appName & " has no visible windows"
      repeat with windowIndex from 1 to windowCount
        set currentWindow to window windowIndex
        try
          perform action "AXRaise" of currentWindow
        end try
        set axItems to entire contents of currentWindow
        set deleteButton to missing value
        set deleteConfirmationAlreadyVisible to false
        repeat with axItem in axItems
          set itemRole to ""
          set itemIdentifier to ""
          set itemName to ""
          set itemTitle to ""
          set itemDescription to ""
          set itemHelp to ""
          try
            set itemRole to role of axItem as text
          end try
          try
            set itemIdentifier to value of attribute "AXIdentifier" of axItem as text
          end try
          try
            set itemName to name of axItem as text
          end try
          try
            set itemTitle to value of attribute "AXTitle" of axItem as text
          end try
          try
            set itemDescription to description of axItem as text
          end try
          try
            set itemHelp to value of attribute "AXHelp" of axItem as text
          end try
          set itemSignal to itemIdentifier & " " & itemName & " " & itemTitle & " " & itemDescription & " " & itemHelp
          if itemSignal contains "task-inspector-delete-confirmation-cancel" then set deleteConfirmationAlreadyVisible to true
          if itemRole is "AXButton" and itemIdentifier is "task-inspector-delete" then set deleteButton to axItem
        end repeat
        if deleteConfirmationAlreadyVisible is false and deleteButton is not missing value then
          perform action "AXPress" of deleteButton
          delay 0.4
          set axItems to entire contents of currentWindow
        end if
        set destructiveCancelSignalText to ""
        repeat with axItem in axItems
          set itemIdentifier to ""
          set itemName to ""
          set itemTitle to ""
          set itemValue to ""
          set itemDescription to ""
          set itemHelp to ""
          try
            set itemIdentifier to value of attribute "AXIdentifier" of axItem as text
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
          set destructiveCancelSignalText to destructiveCancelSignalText & " " & itemIdentifier & " " & itemName & " " & itemTitle & " " & itemValue & " " & itemDescription & " " & itemHelp
        end repeat
        set destructiveCancelSignalCount to 0
        set missingDestructiveCancelSignals to ""
        repeat with requiredDestructiveCancelMarker in requiredDestructiveCancelMarkers
          set requiredDestructiveCancelMarkerText to requiredDestructiveCancelMarker as text
          if requiredDestructiveCancelMarkerText is not "" then
            set requiredDestructiveCancelMarkerLabel to requiredDestructiveCancelMarkerText
            set requiredDestructiveCancelMarkerNeedle to requiredDestructiveCancelMarkerText
            set destructiveCancelMarkerSeparatorOffset to offset of "=>" in requiredDestructiveCancelMarkerText
            if destructiveCancelMarkerSeparatorOffset > 0 then
              set requiredDestructiveCancelMarkerLabel to text 1 thru (destructiveCancelMarkerSeparatorOffset - 1) of requiredDestructiveCancelMarkerText
              set requiredDestructiveCancelMarkerNeedle to text (destructiveCancelMarkerSeparatorOffset + 2) thru -1 of requiredDestructiveCancelMarkerText
            end if
            if destructiveCancelSignalText contains requiredDestructiveCancelMarkerNeedle then
              set destructiveCancelSignalCount to destructiveCancelSignalCount + 1
            else
              if missingDestructiveCancelSignals is "" then
                set missingDestructiveCancelSignals to requiredDestructiveCancelMarkerLabel
              else
                set missingDestructiveCancelSignals to missingDestructiveCancelSignals & "; " & requiredDestructiveCancelMarkerLabel
              end if
            end if
          end if
        end repeat
        set currentSummary to "destructiveCancelSignals=" & destructiveCancelSignalCount & "/" & requiredDestructiveCancelMarkerCount
        if bestSummary is "" or destructiveCancelSignalCount > bestDestructiveCancelSignalCount then
          set bestSummary to currentSummary
          set bestDestructiveCancelSignalCount to destructiveCancelSignalCount
          set bestMissingDestructiveCancelSignals to missingDestructiveCancelSignals
        end if
        if destructiveCancelSignalCount is requiredDestructiveCancelMarkerCount then
          return "OK: runtime AX destructive cancellation visible, " & currentSummary
        end if
      end repeat
      if bestSummary is "" then set bestSummary to "destructiveCancelSignals=0/" & requiredDestructiveCancelMarkerCount
      if bestDestructiveCancelSignalCount < requiredDestructiveCancelMarkerCount then error "runtime AX smoke is missing destructive cancellation labels or help: " & bestMissingDestructiveCancelSignals & " (" & bestSummary & ")"
      error "runtime AX smoke did not find destructive cancellation controls: " & bestSummary
    end tell
  end tell
end run
APPLESCRIPT
)"
    status=$?
    set -e
    if [[ "$status" -eq 0 ]]; then
      printf '%s\n' "$output"
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      printf '%s\n' "$output" >&2
      return 1
    fi
    activate_app
    sleep 1
  done
}

if [[ "$LAUNCH_APP" -eq 1 ]]; then
  if [[ -n "$LAUNCH_ENV_FILE" ]]; then
    # Launching the binary directly preserves the generated review database and selected project env.
    set -a
    # shellcheck source=/dev/null
    source "$LAUNCH_ENV_FILE"
    set +a
    # Runtime AX preflight verifies task CRUD focus and destructive-cancel
    # signals, so it must opt into the deterministic CRUD recovery surface
    # instead of the development-automation project recovery view.
    export SOLOPM_RUNTIME_CRUD_RECOVERY_MODE=1
    "$APP_BINARY" >/dev/null 2>&1 &
    APP_LAUNCH_PID=$!
  else
    /usr/bin/open -n -F "$APP_BUNDLE"
  fi
  activate_app
fi

deadline=$((SECONDS + TIMEOUT_SECONDS))
while true; do
  if [[ -n "$APP_LAUNCH_PID" ]]; then
    launched_app_matches_binary && break
  elif pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    break
  fi
  if [[ "$SECONDS" -ge "$deadline" ]]; then
    echo "BLOCKER: $APP_NAME process did not appear within ${TIMEOUT_SECONDS}s" >&2
    exit 1
  fi
  sleep 1
done

open_task_inspector_for_runtime_focus_path

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
required_runtime_button_a11y_markers_joined=""
for required_runtime_button_a11y_marker in "${REQUIRED_RUNTIME_BUTTON_A11Y_MARKERS[@]}"; do
  if [[ -z "$required_runtime_button_a11y_markers_joined" ]]; then
    required_runtime_button_a11y_markers_joined="$required_runtime_button_a11y_marker"
  else
    required_runtime_button_a11y_markers_joined="${required_runtime_button_a11y_markers_joined}|||${required_runtime_button_a11y_marker}"
  fi
done
required_runtime_button_a11y_marker_count="${#REQUIRED_RUNTIME_BUTTON_A11Y_MARKERS[@]}"
required_runtime_screen_markers_joined=""
for required_runtime_screen_marker in "${REQUIRED_RUNTIME_SCREEN_MARKERS[@]}"; do
  if [[ -z "$required_runtime_screen_markers_joined" ]]; then
    required_runtime_screen_markers_joined="$required_runtime_screen_marker"
  else
    required_runtime_screen_markers_joined="${required_runtime_screen_markers_joined}|||${required_runtime_screen_marker}"
  fi
done
required_runtime_screen_marker_count="${#REQUIRED_RUNTIME_SCREEN_MARKERS[@]}"
while true; do
  set +e
  ax_output="$(/usr/bin/osascript - "$APP_NAME" "$MIN_AX_BUTTONS" "$MIN_AX_TEXT_FIELDS" "$MIN_AX_STATIC_TEXTS" "$required_runtime_crud_markers_joined" "$required_runtime_crud_marker_count" "$required_runtime_focus_markers_joined" "$required_runtime_focus_marker_count" "$required_runtime_button_a11y_markers_joined" "$required_runtime_button_a11y_marker_count" "$required_runtime_screen_markers_joined" "$required_runtime_screen_marker_count" <<APPLESCRIPT 2>&1
on run argv
  set appName to item 1 of argv
  set minButtons to (item 2 of argv) as integer
  set minTextFields to (item 3 of argv) as integer
  set minStaticTexts to (item 4 of argv) as integer
  set requiredCRUDMarkersRaw to item 5 of argv
  set requiredCRUDMarkerCount to (item 6 of argv) as integer
  set requiredFocusMarkersRaw to item 7 of argv
  set requiredFocusMarkerCount to (item 8 of argv) as integer
  set requiredButtonA11yMarkersRaw to item 9 of argv
  set requiredButtonA11yMarkerCount to (item 10 of argv) as integer
  set requiredScreenMarkersRaw to item 11 of argv
  set requiredScreenMarkerCount to (item 12 of argv) as integer
  set previousTextItemDelimiters to text item delimiters of AppleScript
  set text item delimiters of AppleScript to "|||"
  set requiredCRUDMarkers to text items of requiredCRUDMarkersRaw
  set requiredFocusMarkers to text items of requiredFocusMarkersRaw
  set requiredButtonA11yMarkers to text items of requiredButtonA11yMarkersRaw
  set requiredScreenMarkers to text items of requiredScreenMarkersRaw
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
  set bestButtonA11ySignalCount to 0
  set bestMissingButtonA11ySignals to ""
  set bestScreenSignalCount to 0
  set bestMissingScreenSignals to ""
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
        set buttonA11ySignalText to ""
        set focusPathSignalText to ""
        set axItems to entire contents of currentWindow
        repeat with axItem in axItems
          set itemRole to ""
          set itemName to ""
          set itemTitle to ""
          set itemValue to ""
          set itemDescription to ""
          set itemHelp to ""
          set itemIdentifier to ""
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
          try
            set itemIdentifier to value of attribute "AXIdentifier" of axItem as text
          end try
          set focusPathSignalText to focusPathSignalText & " " & itemIdentifier & " " & itemName & " " & itemTitle & " " & itemValue & " " & itemDescription & " " & itemHelp
          if itemRole is "AXButton" then
            set buttonCount to buttonCount + 1
            set buttonName to ""
            set buttonTitle to ""
            set buttonDescription to ""
            set buttonHelp to ""
            set buttonIdentifier to ""
            set buttonPosition to ""
            set buttonSize to ""
            set childTextCount to 0
            set childTextSignal to ""
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
              set buttonIdentifier to value of attribute "AXIdentifier" of axItem as text
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
                  if childText is not "" and childText is not "missing value" then
                    set childTextCount to childTextCount + 1
                    set childTextSignal to childTextSignal & " " & childText
                  end if
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
            set buttonSignalText to buttonSignalText & " " & buttonIdentifier & " " & buttonName & " " & buttonTitle & " " & buttonDescription & " " & buttonHelp
            set buttonHasReadableA11yText to false
            if buttonName is not "" and buttonName is not "missing value" and buttonName is not "button" then set buttonHasReadableA11yText to true
            if buttonTitle is not "" and buttonTitle is not "missing value" and buttonTitle is not "button" then set buttonHasReadableA11yText to true
            if buttonDescription is not "" and buttonDescription is not "missing value" and buttonDescription is not "button" then set buttonHasReadableA11yText to true
            if buttonHelp is not "" and buttonHelp is not "missing value" then set buttonHasReadableA11yText to true
            if childTextCount > 0 then set buttonHasReadableA11yText to true
            repeat with requiredButtonA11yMarker in requiredButtonA11yMarkers
              set requiredButtonA11yMarkerText to requiredButtonA11yMarker as text
              if requiredButtonA11yMarkerText is not "" then
                set requiredButtonIdentifier to requiredButtonA11yMarkerText
                set requiredButtonTextNeedle to ""
                set buttonA11ySeparatorOffset to offset of "=>" in requiredButtonA11yMarkerText
                if buttonA11ySeparatorOffset > 0 then
                  set requiredButtonIdentifier to text 1 thru (buttonA11ySeparatorOffset - 1) of requiredButtonA11yMarkerText
                  set requiredButtonTextNeedle to text (buttonA11ySeparatorOffset + 2) thru -1 of requiredButtonA11yMarkerText
                end if
                if buttonIdentifier contains requiredButtonIdentifier and requiredButtonTextNeedle is not "" and buttonHasReadableA11yText then
                  set buttonA11ySignalText to buttonA11ySignalText & " " & requiredButtonA11yMarkerText
                end if
              end if
            end repeat
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
        set buttonA11ySignalCount to 0
        set missingButtonA11ySignals to ""
        repeat with requiredButtonA11yMarker in requiredButtonA11yMarkers
          set requiredButtonA11yMarkerText to requiredButtonA11yMarker as text
          if requiredButtonA11yMarkerText is not "" then
            if buttonA11ySignalText contains requiredButtonA11yMarkerText then
              set buttonA11ySignalCount to buttonA11ySignalCount + 1
            else
              if missingButtonA11ySignals is "" then
                set missingButtonA11ySignals to requiredButtonA11yMarkerText
              else
                set missingButtonA11ySignals to missingButtonA11ySignals & "; " & requiredButtonA11yMarkerText
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
        set screenSignalCount to 0
        set missingScreenSignals to ""
        repeat with requiredScreenMarker in requiredScreenMarkers
          set requiredScreenMarkerText to requiredScreenMarker as text
          if requiredScreenMarkerText is not "" then
            set requiredScreenMarkerLabel to requiredScreenMarkerText
            set requiredScreenMarkerNeedle to requiredScreenMarkerText
            set screenMarkerSeparatorOffset to offset of "=>" in requiredScreenMarkerText
            if screenMarkerSeparatorOffset > 0 then
              set requiredScreenMarkerLabel to text 1 thru (screenMarkerSeparatorOffset - 1) of requiredScreenMarkerText
              set requiredScreenMarkerNeedle to text (screenMarkerSeparatorOffset + 2) thru -1 of requiredScreenMarkerText
            end if
            if focusPathSignalText contains requiredScreenMarkerNeedle then
              set screenSignalCount to screenSignalCount + 1
            else
              if missingScreenSignals is "" then
                set missingScreenSignals to requiredScreenMarkerLabel
              else
                set missingScreenSignals to missingScreenSignals & "; " & requiredScreenMarkerLabel
              end if
            end if
          end if
        end repeat
        set currentSummary to "window=" & windowIndex & " name=" & windowName & ", buttons=" & buttonCount & ", textFields=" & textFieldCount & ", staticTexts=" & staticTextCount & ", unlabeledButtons=" & unlabeledButtonCount & ", genericButtons=" & genericButtonCount & ", crudSignals=" & crudSignalCount & "/" & requiredCRUDMarkerCount & ", buttonA11ySignals=" & buttonA11ySignalCount & "/" & requiredButtonA11yMarkerCount & ", screenSignals=" & screenSignalCount & "/" & requiredScreenMarkerCount & ", focusPathSignals=" & focusPathSignalCount & "/" & requiredFocusMarkerCount
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
          set bestButtonA11ySignalCount to buttonA11ySignalCount
          set bestMissingButtonA11ySignals to missingButtonA11ySignals
          set bestScreenSignalCount to screenSignalCount
          set bestMissingScreenSignals to missingScreenSignals
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
          set bestButtonA11ySignalCount to buttonA11ySignalCount
          set bestMissingButtonA11ySignals to missingButtonA11ySignals
          set bestScreenSignalCount to screenSignalCount
          set bestMissingScreenSignals to missingScreenSignals
        end if
        if buttonCount >= minButtons and textFieldCount >= minTextFields and staticTextCount >= minStaticTexts and unlabeledButtonCount is 0 and genericButtonCount is 0 and crudSignalCount is requiredCRUDMarkerCount and buttonA11ySignalCount is requiredButtonA11yMarkerCount and screenSignalCount is requiredScreenMarkerCount and focusPathSignalCount is requiredFocusMarkerCount then
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
      if bestButtonA11ySignalCount < requiredButtonA11yMarkerCount then error "runtime AX smoke is missing primary button label or help: " & bestMissingButtonA11ySignals & " (" & bestSummary & ")"
      if bestScreenSignalCount < requiredScreenMarkerCount then error "runtime AX smoke is missing workflow screen entry labels or help: " & bestMissingScreenSignals & " (" & bestSummary & ")"
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

if ! destructive_cancel_output="$(open_task_delete_confirmation_for_runtime_focus_path)"; then
  echo "BLOCKER: runtime AX smoke did not pass destructive cancellation verification within ${TIMEOUT_SECONDS}s" >&2
  echo "BLOCKER: runtime AX smoke failed; grant Accessibility permission to Terminal/Codex and keep the Task inspector visible." >&2
  exit 1
fi

destructive_cancel_summary="${destructive_cancel_output#OK: runtime AX destructive cancellation visible, }"
printf '%s, %s\n' "$ax_output" "$destructive_cancel_summary"
printf '%s\n' 'This is not a substitute for the manual VoiceOver pass.'
