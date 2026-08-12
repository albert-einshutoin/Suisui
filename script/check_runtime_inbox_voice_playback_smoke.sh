#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METADATA_FILE="$ROOT_DIR/packaging/app_metadata.env"

if [[ ! -f "$METADATA_FILE" ]]; then
  echo "BLOCKER: app metadata is unavailable" >&2
  exit 2
fi

# shellcheck source=/dev/null
source "$METADATA_FILE"

APP_NAME="${APP_NAME:?APP_NAME is required}"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
TIMEOUT_SECONDS="${SUISUI_RUNTIME_INBOX_VOICE_PLAYBACK_TIMEOUT_SECONDS:-30}"
SQLITE3="${SQLITE3:-sqlite3}"
AX_HELPERS="${AX_HELPERS:-$ROOT_DIR/script/ui_accessibility_smoke_helpers.sh}"
AX_PRESS_HELPER_SOURCE="$ROOT_DIR/script/ui_evidence_ax_press_element.swift"

if [[ ! "$TIMEOUT_SECONDS" =~ ^[0-9]+$ || "$TIMEOUT_SECONDS" -lt 1 ]]; then
  echo "SUISUI_RUNTIME_INBOX_VOICE_PLAYBACK_TIMEOUT_SECONDS must be a positive integer" >&2
  exit 2
fi

for command in "$SQLITE3" swift /usr/bin/osascript /usr/bin/uuidgen; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "BLOCKER: a required local command is unavailable" >&2
    exit 2
  fi
done

cd "$ROOT_DIR"
mkdir -p "$ROOT_DIR/.tmp"
tmp_dir="$(mktemp -d "$ROOT_DIR/.tmp/suisui-runtime-inbox-voice-playback.XXXXXX")"
runtime_home="$tmp_dir/home"
database_path="$runtime_home/Suisui-runtime-inbox-voice-playback.sqlite"
app_log="$tmp_dir/app.log"
app_pid=""
app_launch_pid=""
ax_press_helper="$tmp_dir/ui-evidence-ax-press-element"
ax_value_helper="$tmp_dir/inbox-voice-ax-value"

# shellcheck source=/dev/null
source "$AX_HELPERS"

terminate_app() {
  if [[ -n "${app_pid:-}" ]]; then
    kill "$app_pid" >/dev/null 2>&1 || true
    wait "$app_pid" >/dev/null 2>&1 || true
    app_pid=""
  fi
  app_launch_pid=""
}

cleanup() {
  terminate_app
  # tmp_dir is created by mktemp below the repository-owned .tmp directory.
  # Removing only that exact leaf keeps the managed WAV and database isolated
  # without risking another user's Suisui data.
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

prepare_fixture() {
  local seeder_bin
  local marker_token
  local create_output
  local seed_output
  local home_device=""
  local home_inode=""
  local key value extra

  if ! swift build --package-path "$ROOT_DIR" --product SuisuiVisualFixtureSeeder \
    >>"$app_log" 2>&1; then
    echo "BLOCKER: the visual fixture seeder could not be built" >&2
    return 2
  fi
  if ! seeder_bin="$(
    swift build --package-path "$ROOT_DIR" --show-bin-path 2>>"$app_log"
  )/SuisuiVisualFixtureSeeder"; then
    echo "BLOCKER: the visual fixture seeder location is unavailable" >&2
    return 2
  fi
  if [[ ! -x "$seeder_bin" || -L "$seeder_bin" ]]; then
    echo "BLOCKER: the visual fixture seeder is unavailable" >&2
    return 2
  fi

  marker_token="$(/usr/bin/uuidgen)"
  if ! create_output="$(
    "$seeder_bin" \
      --create-evidence-home \
      --path "$runtime_home" \
      --evidence-home-marker-token "$marker_token" \
      2>>"$app_log"
  )"; then
    echo "BLOCKER: isolated runtime HOME creation failed" >&2
    return 2
  fi

  while IFS='=' read -r key value extra; do
    if [[ -n "$extra" || -z "$key" || -z "$value" ]]; then
      echo "BLOCKER: isolated runtime HOME receipt is malformed" >&2
      return 2
    fi
    case "$key" in
      evidence_home_device) home_device="$value" ;;
      evidence_home_inode) home_inode="$value" ;;
      *)
        echo "BLOCKER: isolated runtime HOME receipt has an unknown field" >&2
        return 2
        ;;
    esac
  done <<<"$create_output"
  if [[ ! "$home_device" =~ ^-?[0-9]+$ || ! "$home_inode" =~ ^[0-9]+$ ]]; then
    echo "BLOCKER: isolated runtime HOME identity is invalid" >&2
    return 2
  fi

  if ! seed_output="$(
    HOME="$runtime_home" CFFIXED_USER_HOME="$runtime_home" \
      SUISUI_LANGUAGE_PREFERENCE=english "$seeder_bin" \
      --database "$database_path" \
      --evidence-home "$runtime_home" \
      --evidence-home-marker-token "$marker_token" \
      --expected-evidence-home-device "$home_device" \
      --expected-evidence-home-inode "$home_inode" \
      --capture-reference-instant "2026-07-10T12:00:00Z" \
      2>>"$app_log"
  )"; then
    echo "BLOCKER: Inbox voice fixture creation failed" >&2
    return 2
  fi

  inbox_voice_task_id=""
  while IFS='=' read -r key value extra; do
    if [[ -z "$key" && -z "$value" && -z "$extra" ]]; then
      continue
    fi
    if [[ -n "$extra" || -z "$value" ]]; then
      echo "BLOCKER: Inbox voice fixture receipt is malformed" >&2
      return 2
    fi
    case "$key" in
      inbox_voice_task_id) inbox_voice_task_id="$value" ;;
      project_id|capture_task_id|review_task_id|unscheduled_task_id|capture_due_date|review_due_date) ;;
      *)
        echo "BLOCKER: Inbox voice fixture receipt has an unknown field" >&2
        return 2
        ;;
    esac
  done <<<"$seed_output"
  if [[ ! "$inbox_voice_task_id" =~ ^[0-9]+$ ]]; then
    echo "BLOCKER: Inbox voice fixture task identifier is invalid" >&2
    return 2
  fi
}

verify_managed_fixture() {
  local managed_root="$runtime_home/Library/Application Support/Suisui/InboxAudio"
  local managed_root_real
  local audio_path
  local audio_parent_real

  if [[ ! -f "$database_path" || -L "$database_path" ]]; then
    echo "BLOCKER: isolated Inbox database is not a regular file" >&2
    return 2
  fi
  audio_path="$($SQLITE3 -batch -noheader "$database_path" \
    "SELECT audio_file_path FROM inbox_capture_records WHERE task_id=$inbox_voice_task_id ORDER BY id LIMIT 1;")"
  if [[ -z "$audio_path" || "$audio_path" == *$'\n'* || ! -f "$audio_path" || -L "$audio_path" ]]; then
    echo "BLOCKER: managed Inbox WAV is not a regular file" >&2
    return 2
  fi
  if [[ ! -d "$managed_root" || -L "$managed_root" ]]; then
    echo "BLOCKER: managed Inbox audio directory is invalid" >&2
    return 2
  fi
  managed_root_real="$(cd "$managed_root" && pwd -P)"
  audio_parent_real="$(cd "$(dirname "$audio_path")" && pwd -P)"
  if [[ "$audio_parent_real" != "$managed_root_real" || "${audio_path##*.}" != "wav" ]]; then
    echo "BLOCKER: Inbox audio escaped the isolated managed WAV directory" >&2
    return 2
  fi
  if [[ "$(LC_ALL=C /usr/bin/od -An -N4 -c "$audio_path" | tr -d '[:space:]')" != "RIFF" ]]; then
    echo "BLOCKER: managed Inbox audio does not have a WAV header" >&2
    return 2
  fi
}

prepare_ax_press_helper() {
  if [[ -x "$ax_press_helper" ]]; then
    return 0
  fi
  if ! /usr/bin/swiftc "$AX_PRESS_HELPER_SOURCE" -o "$ax_press_helper" \
    >>"$app_log" 2>&1; then
    echo "BLOCKER: PID-scoped AX press helper could not be built" >&2
    return 2
  fi
}

prepare_ax_value_helper() {
  if [[ -x "$ax_value_helper" ]]; then
    return 0
  fi
  if ! /usr/bin/swiftc -o "$ax_value_helper" - >>"$app_log" 2>&1 <<'SWIFT'
import ApplicationServices
import Foundation

guard CommandLine.arguments.count == 4,
      let rawPID = Int32(CommandLine.arguments[1]), rawPID > 0 else {
    exit(2)
}
let app = AXUIElementCreateApplication(pid_t(rawPID))
let identifier = CommandLine.arguments[2]
let operation = CommandLine.arguments[3]

func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
    AXUIElementSetMessagingTimeout(element, 1)
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name, &value) == .success ? value : nil
}

func elements(_ value: CFTypeRef?) -> [AXUIElement] {
    guard let value else { return [] }
    if CFGetTypeID(value) == AXUIElementGetTypeID() {
        return [unsafeBitCast(value, to: AXUIElement.self)]
    }
    guard let array = value as? [AnyObject] else { return [] }
    return array.compactMap { item in
        let value = item as CFTypeRef
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }
}

func string(_ value: CFTypeRef?) -> String? {
    if let value = value as? String { return value }
    if let value = value as? NSNumber { return value.stringValue }
    return nil
}

func visibleSize(_ element: AXUIElement) -> CGSize? {
    guard let value = attribute(element, kAXSizeAttribute as CFString),
          CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var size = CGSize.zero
    guard AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cgSize, &size),
          size.width > 1, size.height > 1 else { return nil }
    return size
}

let childAttributes = [
    kAXChildrenAttribute as String,
    "AXVisibleChildren",
    "AXContents",
    "AXRows",
    "AXColumns",
    "AXDisclosedRows"
]
guard let windowsValue = attribute(app, kAXWindowsAttribute as CFString) else { exit(1) }
var queue = elements(windowsValue)
var cursor = 0
var visited = 0
var matches: [(element: AXUIElement, value: String)] = []
while cursor < queue.count && visited < 6_000 {
    let element = queue[cursor]
    cursor += 1
    visited += 1
    if string(attribute(element, "AXIdentifier" as CFString)) == identifier,
       visibleSize(element) != nil,
       let value = string(attribute(element, kAXValueAttribute as CFString)) {
        matches.append((element, value))
    }
    for childAttribute in childAttributes {
        queue.append(contentsOf: elements(attribute(element, childAttribute as CFString)))
    }
}
guard !matches.isEmpty else { exit(1) }

switch operation {
case "values":
    print(matches.map(\.value).sorted().joined(separator: ";"))
case "increment-max":
    let numericMatches = matches.compactMap { match -> (element: AXUIElement, value: Double)? in
        guard let value = Double(match.value) else { return nil }
        return (match.element, value)
    }
    guard let target = numericMatches.max(by: { $0.value < $1.value }),
          AXUIElementPerformAction(target.element, kAXIncrementAction as CFString) == .success else {
        exit(1)
    }
default:
    exit(2)
}
SWIFT
  then
    echo "BLOCKER: PID-scoped AX value helper could not be built" >&2
    return 2
  fi
}

wait_for_app_process() {
  app_pid="$(ax_wait_for_owned_app_pid "$app_launch_pid" "$APP_BINARY" "$TIMEOUT_SECONDS")" || {
    echo "BLOCKER: the isolated Suisui process did not launch" >&2
    return 1
  }
  ax_wait_for_pid_owned_process "$APP_NAME" "$app_pid" "$TIMEOUT_SECONDS" "$APP_BINARY" >/dev/null
}

activate_app() {
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while true; do
    if /usr/bin/osascript - "$app_pid" <<'APPLESCRIPT' >/dev/null 2>&1
on run argv
  set targetPID to (item 1 of argv) as integer
  tell application "System Events"
    set targetProcess to first process whose unix id is targetPID
    tell targetProcess
      set frontmost to true
      if (count of windows) > 0 then
        try
          perform action "AXRaise" of window 1
        end try
      end if
    end tell
  end tell
end run
APPLESCRIPT
    then
      return 0
    fi
    if ! ax_pid_is_owned_process "$APP_NAME" "$app_pid" "$APP_BINARY"; then
      echo "BLOCKER: the isolated Suisui process exited before activation" >&2
      return 1
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: the isolated Suisui process could not be activated" >&2
      return 1
    fi
    sleep 0.2
  done
}

wait_for_visible_window() {
  ax_wait_for_pid_owned_window "$APP_NAME" "$app_pid" "" "$TIMEOUT_SECONDS" "" "$APP_BINARY" >/dev/null || {
    echo "BLOCKER: the isolated Suisui process did not expose a visible window" >&2
    return 1
  }
  /usr/bin/osascript - "$app_pid" <<'APPLESCRIPT' >/dev/null 2>&1
on run argv
  set targetPID to (item 1 of argv) as integer
  tell application "System Events"
    set targetProcess to first process whose unix id is targetPID
    tell targetProcess
      if not (exists window 1) then error "window missing"
      set frontmost to true
      try
        perform action "AXRaise" of window 1
      end try
      set size of window 1 to {1400, 920}
    end tell
  end tell
end run
APPLESCRIPT
  sleep 1
}

launch_app_for_inbox() {
  terminate_app
  /usr/bin/env -i PATH="$PATH" TMPDIR="$tmp_dir" \
    HOME="$runtime_home" CFFIXED_USER_HOME="$runtime_home" \
    SUISUI_DISABLE_KEYCHAIN_SECRET_STORE=1 \
    SUISUI_LANGUAGE_PREFERENCE=english \
    SUISUI_DATABASE_PATH="$database_path" \
    SUISUI_PROJECT_BOARD_SELECTED_DESTINATION="inbox" \
    SUISUI_PROJECT_BOARD_SELECTED_TASK_ID="$inbox_voice_task_id" \
    "$APP_BINARY" -ApplePersistenceIgnoreState YES \
      -AppleLanguages '(en)' -AppleLocale en_US >"$app_log" 2>&1 &
  app_launch_pid=$!
  wait_for_app_process
  activate_app
  wait_for_visible_window
}

ax_signal_for_identifier() {
  local identifier="$1"
  "$ax_value_helper" "$app_pid" "$identifier" values 2>/dev/null
}

print_inbox_voice_ax_diagnostics() {
  /usr/bin/osascript - "$app_pid" <<'APPLESCRIPT' 2>/dev/null >&2 || true
on run argv
  set targetPID to (item 1 of argv) as integer
  set foundSignals to {}
  tell application "System Events"
    set targetProcess to first process whose unix id is targetPID
    tell targetProcess
      if (count of windows) is 0 then return "AX diagnostics: no visible window"
      repeat with currentWindow in windows
        repeat with axItem in entire contents of currentWindow
          set itemIdentifier to ""
          try
            set itemIdentifier to value of attribute "AXIdentifier" of axItem as text
          end try
          if itemIdentifier contains "inbox-voice" then
            set itemName to ""
            try
              set itemName to name of axItem as text
            end try
            set end of foundSignals to itemIdentifier & ":" & itemName
          end if
        end repeat
      end repeat
    end tell
  end tell
  if (count of foundSignals) is 0 then return "AX diagnostics: no inbox-voice identifiers"
  set AppleScript's text item delimiters to ", "
  return "AX diagnostics: " & (foundSignals as text)
end run
APPLESCRIPT
}

wait_for_signal_containing() {
  local identifier="$1"
  local expected="$2"
  local probe_file="$tmp_dir/ax-marker"
  if SUISUI_UI_EVIDENCE_AX_REQUIRE_EXACT_IDENTIFIER=1 \
    SUISUI_UI_EVIDENCE_AX_REQUIRE_IDENTIFIER_SUBTREE=1 \
    ax_wait_for_ax_identifier \
    "$APP_NAME" "$identifier" "$TIMEOUT_SECONDS" "$ROOT_DIR" "$probe_file" "$expected" "$app_pid"; then
    return 0
  fi
  echo "BLOCKER: visible Inbox voice control did not reach the expected state" >&2
  if [[ -f "$probe_file.err" ]]; then
    tail -n 5 "$probe_file.err" \
      | sed -e "s|$tmp_dir|<isolated>|g" -e "s|$ROOT_DIR|<repository>|g" >&2
  fi
  print_inbox_voice_ax_diagnostics
  return 1
}

press_button_by_identifier() {
  local identifier="$1"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while true; do
    if "$ax_press_helper" "$app_pid" "$identifier" >>"$app_log" 2>&1; then
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: visible Inbox voice button could not be pressed" >&2
      return 1
    fi
    sleep 0.2
  done
}

seek_forward_by_identifier() {
  local identifier="$1"
  if "$ax_value_helper" "$app_pid" "$identifier" increment-max >>"$app_log" 2>&1; then
    return 0
  fi
  echo "BLOCKER: visible Inbox voice position control could not be changed" >&2
  return 1
}

wait_for_control_value_ready() {
  local identifier="$1"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local current=""
  while true; do
    current="$(ax_signal_for_identifier "$identifier" || true)"
    if [[ -n "$current" ]]; then
      printf '%s' "$current"
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: visible Inbox voice position was not readable" >&2
      return 1
    fi
    sleep 0.2
  done
}

wait_for_control_value_change() {
  local identifier="$1"
  local previous="$2"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local current=""
  while true; do
    current="$(ax_signal_for_identifier "$identifier" || true)"
    if [[ -n "$current" && "$current" != "$previous" ]]; then
      printf '%s' "$current"
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      printf "BLOCKER: visible Inbox voice position did not advance (initial=%q current=%q)\n" \
        "$previous" "$current" >&2
      return 1
    fi
    sleep 0.2
  done
}

printf "== Runtime Inbox voice playback smoke ==\n"
if ! ./script/build_and_run.sh --build-only >>"$app_log" 2>&1; then
  echo "BLOCKER: Suisui app build failed" >&2
  exit 2
fi
if [[ ! -x "$APP_BINARY" ]]; then
  echo "BLOCKER: built Suisui app binary is unavailable" >&2
  exit 2
fi

prepare_fixture
verify_managed_fixture
prepare_ax_press_helper
prepare_ax_value_helper

# The first launch proves the persisted capture is discoverable. A second
# launch exercises the actual restart path before any playback action occurs.
launch_app_for_inbox
wait_for_signal_containing "inbox-voice-playback-toggle" "Play voice memo"
terminate_app
sleep 1
launch_app_for_inbox
wait_for_signal_containing "inbox-voice-playback-toggle" "Play voice memo"

initial_playback_value="$(wait_for_control_value_ready "inbox-voice-playback-toggle")"
press_button_by_identifier "inbox-voice-playback-toggle"
wait_for_signal_containing "inbox-voice-playback-toggle" "Pause voice memo"
playing_playback_value="$(wait_for_control_value_change "inbox-voice-playback-toggle" "$initial_playback_value")"

press_button_by_identifier "inbox-voice-playback-toggle"
wait_for_signal_containing "inbox-voice-playback-toggle" "Play voice memo"
paused_playback_value="$(wait_for_control_value_ready "inbox-voice-playback-toggle")"
sleep 1
if [[ "$(wait_for_control_value_ready "inbox-voice-playback-toggle")" != "$paused_playback_value" ]]; then
  echo "BLOCKER: paused Inbox voice position continued changing" >&2
  exit 1
fi

seek_forward_by_identifier "inbox-voice-seek"
seeked_playback_value="$(wait_for_control_value_change "inbox-voice-playback-toggle" "$paused_playback_value")"
if [[ "$initial_playback_value" == "$playing_playback_value" || "$playing_playback_value" == "$seeked_playback_value" ]]; then
  echo "BLOCKER: Inbox voice play or seek state did not change" >&2
  exit 1
fi

printf "OK: runtime inbox voice playback smoke verified restart, play, pause, progress, and seek through the visible Inbox UI\n"
