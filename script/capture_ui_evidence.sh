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
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:?BUNDLE_IDENTIFIER is required}"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
SCREENSHOT_DIR="${SUISUI_UI_EVIDENCE_DIR:-$ROOT_DIR/docs/release/evidence/ui-screenshots}"
EVIDENCE_FILE="${SUISUI_UI_EVIDENCE_FILE:-$ROOT_DIR/docs/release/evidence/ui-screenshots.md}"
SCHEDULE_COCKPIT_EVIDENCE_FILE="${SUISUI_SCHEDULE_COCKPIT_EVIDENCE_FILE:-$ROOT_DIR/docs/release/evidence/schedule-cockpit-screenshots.md}"
DONE_ANALYTICS_EVIDENCE_FILE="${SUISUI_DONE_ANALYTICS_EVIDENCE_FILE:-$ROOT_DIR/docs/release/evidence/done-analytics-screenshots.md}"
EVIDENCE_TMPDIR="${SUISUI_UI_EVIDENCE_TMPDIR:-$ROOT_DIR/.tmp}"
VISUAL_BASELINE_MANIFEST="${SUISUI_VISUAL_BASELINE_MANIFEST:-$ROOT_DIR/docs/quality/visual-baseline-manifest.json}"
SUISUI_VISUAL_AX_AUDIT_RESULT="${SUISUI_VISUAL_AX_AUDIT_RESULT:-$EVIDENCE_TMPDIR/visual-ax-audit-receipt.json}"
VISUAL_BASELINE_VIEWPORT="${SUISUI_VISUAL_BASELINE_VIEWPORT:-1024x676}"
SETTINGS_VISUAL_BASELINE_VIEWPORT="${SUISUI_SETTINGS_VISUAL_BASELINE_VIEWPORT:-1024x676}"
VOICE_COMMAND_VISUAL_BASELINE_VIEWPORT="${SUISUI_VOICE_COMMAND_VISUAL_BASELINE_VIEWPORT:-1024x676}"
TARGET_TIMEOUT_SECONDS="${SUISUI_UI_EVIDENCE_TARGET_TIMEOUT_SECONDS:-30}"
EVIDENCE_WINDOW_ATTEMPTS=2
EVIDENCE_ROUTE_ATTEMPTS=2
AX_MARKER_MAX_NODES="${SUISUI_UI_EVIDENCE_AX_MAX_NODES:-6000}"
EVIDENCE_LOCALE="${SUISUI_UI_EVIDENCE_LOCALE:-english}"
EVIDENCE_LOCALES=("english" "japanese")
# A fixed instant keeps relative seed dates and UI read models on one day even
# when a long 39-screen capture crosses midnight. These capture-only variables
# are ignored by normal launches, which continue to use the system clock.
EVIDENCE_REFERENCE_INSTANT="${SUISUI_VISUAL_EVIDENCE_REFERENCE_INSTANT:-2026-07-10T12:00:00Z}"
EVIDENCE_TIME_ZONE="${SUISUI_VISUAL_EVIDENCE_TIME_ZONE:-UTC}"
AX_HELPERS="${AX_HELPERS:-$ROOT_DIR/script/ui_accessibility_smoke_helpers.sh}"
mkdir -p "$EVIDENCE_TMPDIR"
export TMPDIR="$EVIDENCE_TMPDIR/"
AX_MARKER_CHECKER="$EVIDENCE_TMPDIR/ui-evidence-ax-marker-checker.$$"
AX_SCROLL_HELPER="$EVIDENCE_TMPDIR/ui-evidence-ax-scroll-to.$$"
AX_SCROLL_CONTAINER_HELPER="$EVIDENCE_TMPDIR/ui-evidence-ax-scroll-container.$$"
AX_TARGET_FRAME_AUDITOR="$EVIDENCE_TMPDIR/ui-evidence-ax-target-frame-auditor.$$"
AX_RESIZE_WINDOW_HELPER_SOURCE="$ROOT_DIR/script/ui_evidence_ax_resize_window.swift"
AX_RESIZE_WINDOW_HELPER_BINARY="$EVIDENCE_TMPDIR/ui-evidence-ax-resize-window.$$"
AX_PRESS_ELEMENT_HELPER="$EVIDENCE_TMPDIR/ui-evidence-ax-press-element.$$"
POINTER_PARKER="$EVIDENCE_TMPDIR/ui-evidence-pointer-park.$$"
AX_CAPTURE_RECEIPT_TSV="$EVIDENCE_TMPDIR/visual-ax-captures.$$.tsv"
AX_RECEIPT_WRITER="$EVIDENCE_TMPDIR/write-visual-ax-audit-receipt.$$"
VISUAL_RASTER_STABILITY_CHECKER="$EVIDENCE_TMPDIR/visual-raster-stability-checker.$$"
VISUAL_APPEARANCE_CHECKER="$EVIDENCE_TMPDIR/visual-appearance-checker.$$"
VISUAL_FIRST_RASTER="$EVIDENCE_TMPDIR/visual-first-raster.$$.png"
EVIDENCE_HOME="${SUISUI_UI_EVIDENCE_HOME:-}"
EVIDENCE_HOME_MARKER_TOKEN=""
EVIDENCE_HOME_DEVICE=""
EVIDENCE_HOME_INODE=""
EVIDENCE_HOME_CONTAINER=""
EVIDENCE_HOME_READY=0
EVIDENCE_HOME_IS_AUTOMATIC=0
KEEP_HOME="${SUISUI_UI_EVIDENCE_KEEP_HOME:-0}"
DRY_RUN=0
DOCTOR=0
SEED_ONLY=0
P0_WORKFLOWS=0
SCHEDULE_COCKPIT=0
SCHEDULE_WORKLOAD=0
DONE_ANALYTICS=0
PROJECT_BOARD_SELECTION_OVERRIDE=""
PROJECT_BOARD_SELECTED_TASK_OVERRIDE=""
SCHEDULE_MODE_OVERRIDE=""
PROJECT_BOARD_TARGET_MARKERS=""
INBOX_VOICE_TARGET_MARKERS=""
APPEARANCE_OVERRIDE=""
SETTINGS_WINDOW_OVERRIDE=""
SETTINGS_TAB_OVERRIDE=""
VOICE_COMMAND_WINDOW_OVERRIDE=""
VOICE_SURFACE_OVERRIDE=""
INBOX_EVIDENCE_CLEAR_SELECTION=""
POSITIONED_WINDOW_WIDTH=""
POSITIONED_WINDOW_HEIGHT=""
EVIDENCE_APP_PID=""
EVIDENCE_APP_LAUNCH_PID=""
EVIDENCE_APP_IDENTITY=""
EVIDENCE_APP_LAUNCH_IDENTITY=""
EVIDENCE_APP_LOG="$EVIDENCE_TMPDIR/visual-evidence-app.$$.log"
EVIDENCE_WAIT_FAILURE_CATEGORY="launch"
EVIDENCE_WAIT_FAILURE_REASON="visual-launch-unavailable"
DATABASE_PATH=""
VISUAL_FIXTURE_SEEDER_BIN="${SUISUI_VISUAL_FIXTURE_SEEDER_BIN:-}"
CAPTURE_PROJECT_ID=""
CAPTURE_INBOX_VOICE_TASK_ID=""
CAPTURE_TASK_ID=""
CAPTURE_REVIEW_TASK_ID=""
CAPTURE_UNSCHEDULED_TASK_ID=""
CAPTURE_DUE_DATE=""
CAPTURE_REVIEW_DUE_DATE=""

for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=1
      ;;
    --doctor)
      DOCTOR=1
      ;;
    --seed-only)
      SEED_ONLY=1
      ;;
    --p0-workflows)
      P0_WORKFLOWS=1
      ;;
    --schedule-cockpit)
      SCHEDULE_COCKPIT=1
      ;;
    --schedule-workload)
      SCHEDULE_WORKLOAD=1
      ;;
    --done-analytics)
      DONE_ANALYTICS=1
      ;;
    *)
      echo "usage: $0 [--dry-run|--doctor|--seed-only|--p0-workflows|--schedule-cockpit|--schedule-workload|--done-analytics]" >&2
      exit 2
      ;;
  esac
done

if [[ $((DRY_RUN + DOCTOR + SEED_ONLY + P0_WORKFLOWS + SCHEDULE_COCKPIT + SCHEDULE_WORKLOAD + DONE_ANALYTICS)) -gt 1 ]]; then
  echo "usage: $0 [--dry-run|--doctor|--seed-only|--p0-workflows|--schedule-cockpit|--schedule-workload|--done-analytics]" >&2
  exit 2
fi

if [[ ! "$TARGET_TIMEOUT_SECONDS" =~ ^[0-9]+$ || "$TARGET_TIMEOUT_SECONDS" -lt 1 ]]; then
  echo "SUISUI_UI_EVIDENCE_TARGET_TIMEOUT_SECONDS must be a positive integer" >&2
  exit 2
fi
if [[ ! "$AX_MARKER_MAX_NODES" =~ ^[0-9]+$ || "$AX_MARKER_MAX_NODES" -lt 1 ]]; then
  echo "SUISUI_UI_EVIDENCE_AX_MAX_NODES must be a positive integer" >&2
  exit 2
fi
if [[ " ${EVIDENCE_LOCALES[*]} " != *" $EVIDENCE_LOCALE "* ]]; then
  echo "SUISUI_UI_EVIDENCE_LOCALE must be english or japanese" >&2
  exit 2
fi
if [[ ! "$EVIDENCE_REFERENCE_INSTANT" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
  echo "SUISUI_VISUAL_EVIDENCE_REFERENCE_INSTANT must be a whole-second UTC ISO-8601 instant" >&2
  exit 2
fi
if ! /bin/date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$EVIDENCE_REFERENCE_INSTANT" "+%Y-%m-%dT%H:%M:%SZ" >/dev/null 2>&1; then
  echo "SUISUI_VISUAL_EVIDENCE_REFERENCE_INSTANT is not a valid UTC instant" >&2
  exit 2
fi
if [[ "$EVIDENCE_TIME_ZONE" != "UTC" ]]; then
  echo "SUISUI_VISUAL_EVIDENCE_TIME_ZONE must be UTC for canonical visual baselines" >&2
  exit 2
fi

# The product language override controls Suisui's localized strings, while
# AppleLanguages/AppleLocale control Foundation/AppKit formatters. Keep all
# three values in one mapping so the runtime pixels and hashed audit receipt cannot
# claim different locales on capture hosts with different system settings.
case "$EVIDENCE_LOCALE" in
  english)
    APPLE_LANGUAGES="(en)"
    APPLE_LOCALE="en_US"
    EVIDENCE_RECEIPT_LOCALE="en-US"
    ;;
  japanese)
    APPLE_LANGUAGES="(ja)"
    APPLE_LOCALE="ja_JP"
    EVIDENCE_RECEIPT_LOCALE="ja-JP"
    ;;
esac

if [[ "$EVIDENCE_LOCALE" == "japanese" && -z "${SUISUI_UI_EVIDENCE_FILE+x}" ]]; then
  # Keep Japanese run metadata with its screenshots so the second locale cannot
  # overwrite the tracked English evidence document during a complete capture.
  EVIDENCE_FILE="$SCREENSHOT_DIR/ui-screenshots.md"
fi

# A manifest override exists only to keep one locale's screenshots and
# baselines in its own roots. Requiring an in-repository regular file whose
# locale and artifact root match this capture prevents an arbitrary manifest
# from authenticating mixed or externally redirected evidence.
if [[ ! -f "$VISUAL_BASELINE_MANIFEST" ]]; then
  echo "BLOCKER: visual baseline manifest is not a regular file: $VISUAL_BASELINE_MANIFEST" >&2
  exit 2
fi
if [[ -L "$VISUAL_BASELINE_MANIFEST" ]]; then
  echo "BLOCKER: visual baseline manifest must not be a symbolic link: $VISUAL_BASELINE_MANIFEST" >&2
  exit 2
fi
MANIFEST_PARENT_REAL="$(cd "$(dirname "$VISUAL_BASELINE_MANIFEST")" && pwd -P)"
ROOT_DIR_REAL="$(cd "$ROOT_DIR" && pwd -P)"
case "$MANIFEST_PARENT_REAL" in
  "$ROOT_DIR_REAL"|"$ROOT_DIR_REAL"/*) ;;
  *)
    echo "BLOCKER: visual baseline manifest parent must resolve inside the repository" >&2
    exit 2
    ;;
esac
if ! MANIFEST_LOCALE="$(/usr/bin/plutil -extract baselineContext.locale raw -o - "$VISUAL_BASELINE_MANIFEST" 2>/dev/null)"; then
  echo "BLOCKER: visual baseline manifest is missing baselineContext.locale" >&2
  exit 2
fi
if [[ "$MANIFEST_LOCALE" != "$EVIDENCE_RECEIPT_LOCALE" ]]; then
  echo "BLOCKER: visual baseline manifest locale $MANIFEST_LOCALE does not match capture locale $EVIDENCE_RECEIPT_LOCALE" >&2
  exit 2
fi
if ! MANIFEST_ARTIFACT_ROOT="$(/usr/bin/plutil -extract artifactRoot raw -o - "$VISUAL_BASELINE_MANIFEST" 2>/dev/null)"; then
  echo "BLOCKER: visual baseline manifest is missing artifactRoot" >&2
  exit 2
fi
case "$SCREENSHOT_DIR" in
  "$ROOT_DIR"/*) EXPECTED_ARTIFACT_ROOT="${SCREENSHOT_DIR#"$ROOT_DIR/"}" ;;
  *) EXPECTED_ARTIFACT_ROOT="$SCREENSHOT_DIR" ;;
esac
if [[ "$MANIFEST_ARTIFACT_ROOT" != "$EXPECTED_ARTIFACT_ROOT" ]]; then
  echo "BLOCKER: visual baseline manifest artifactRoot does not match screenshot directory" >&2
  exit 2
fi

validate_visual_ax_audit_result_path() {
  local receipt_path="$SUISUI_VISUAL_AX_AUDIT_RESULT"
  local receipt_parent
  local receipt_parent_real

  if [[ -L "$receipt_path" ]]; then
    echo "BLOCKER: visual AX audit receipt must not be a symbolic link: $receipt_path" >&2
    return 2
  fi
  if [[ -e "$receipt_path" && ! -f "$receipt_path" ]]; then
    echo "BLOCKER: visual AX audit receipt must be a regular file when it exists: $receipt_path" >&2
    return 2
  fi

  receipt_parent="$(dirname "$receipt_path")"
  if [[ ! -d "$receipt_parent" ]]; then
    echo "BLOCKER: visual AX audit receipt parent must be an existing directory: $receipt_parent" >&2
    return 2
  fi
  if ! receipt_parent_real="$(cd "$receipt_parent" && pwd -P)"; then
    echo "BLOCKER: visual AX audit receipt parent could not be resolved: $receipt_parent" >&2
    return 2
  fi
  case "$receipt_parent_real/" in
    "$ROOT_DIR_REAL/.tmp/"*|"$ROOT_DIR_REAL/.build/"*)
      ;;
    *)
      echo "BLOCKER: visual AX audit receipt parent must resolve under the repository .tmp or .build directory" >&2
      return 2
      ;;
  esac
}

select_isolated_evidence_home() {
  local requested_home="$EVIDENCE_HOME"
  local requested_parent
  local requested_parent_real
  local requested_name

  if [[ -z "$requested_home" ]]; then
    EVIDENCE_HOME_CONTAINER="$(mktemp -d "$EVIDENCE_TMPDIR/suisui-ui-evidence.XXXXXX")"
    EVIDENCE_HOME="$EVIDENCE_HOME_CONTAINER/home"
    EVIDENCE_HOME_IS_AUTOMATIC=1
  else
    # An override identifies a new leaf, not an existing HOME. Requiring the
    # capture process to create it exclusively prevents a typo such as
    # SUISUI_UI_EVIDENCE_HOME=$HOME from exposing a real Suisui database to the
    # destructive deterministic fixture reset.
    if [[ -e "$requested_home" || -L "$requested_home" ]]; then
      echo "BLOCKER: SUISUI_UI_EVIDENCE_HOME must name a new isolated home, not an existing path: $requested_home" >&2
      return 2
    fi
    requested_parent="$(dirname "$requested_home")"
    requested_name="$(basename "$requested_home")"
    if [[ "$requested_name" == "." || "$requested_name" == ".." || "$requested_name" == "/" ]]; then
      echo "BLOCKER: SUISUI_UI_EVIDENCE_HOME has an invalid isolated home name: $requested_home" >&2
      return 2
    fi
    if [[ ! -d "$requested_parent" || -L "$requested_parent" ]]; then
      echo "BLOCKER: SUISUI_UI_EVIDENCE_HOME parent must be an existing non-symlink directory: $requested_parent" >&2
      return 2
    fi
    requested_parent_real="$(cd "$requested_parent" && pwd -L)"
    EVIDENCE_HOME="$requested_parent_real/$requested_name"
  fi

  EVIDENCE_HOME_MARKER_TOKEN="$(/usr/bin/uuidgen)"
}

# Validate the release-evidence destination before loading optional helpers or
# creating any isolated runtime state. Invalid or redirected receipt paths must
# fail closed without modifying the previous receipt.
if [[ "$DRY_RUN" != "1" && "$DOCTOR" != "1" && "$SEED_ONLY" != "1" ]]; then
  validate_visual_ax_audit_result_path || exit $?
fi

# shellcheck source=/dev/null
source "$AX_HELPERS"

cleanup() {
  if [[ "$DRY_RUN" != "1" && "$DOCTOR" != "1" && "$SEED_ONLY" != "1" ]] \
      && declare -F stop_evidence_app >/dev/null; then
    stop_evidence_app
  fi
  rm -f "$AX_MARKER_CHECKER"
  rm -f "$AX_SCROLL_HELPER"
  rm -f "$AX_SCROLL_CONTAINER_HELPER"
  rm -f "$AX_TARGET_FRAME_AUDITOR"
  rm -f "$AX_RESIZE_WINDOW_HELPER_BINARY"
  rm -f "$AX_PRESS_ELEMENT_HELPER"
  rm -f "$POINTER_PARKER"
  rm -f "$AX_CAPTURE_RECEIPT_TSV" "$AX_RECEIPT_WRITER" "$VISUAL_RASTER_STABILITY_CHECKER" "$VISUAL_APPEARANCE_CHECKER"
  rm -f "$VISUAL_FIRST_RASTER"
  rm -f "$EVIDENCE_APP_LOG"
  if [[ "$KEEP_HOME" != "1" && "$EVIDENCE_HOME_IS_AUTOMATIC" == "1" ]]; then
    if [[ "$EVIDENCE_HOME_READY" == "1" && -n "$VISUAL_FIXTURE_SEEDER_BIN" ]]; then
      # Cleanup is delegated to the same dirfd-based helper that created the
      # HOME. It verifies the capture token plus device/inode and recursively
      # unlinks through pinned descriptors, so a replacement path is never
      # passed to rm -rf.
      if "$VISUAL_FIXTURE_SEEDER_BIN" \
          --cleanup-evidence-home \
          --path "$EVIDENCE_HOME" \
          --evidence-home-marker-token "$EVIDENCE_HOME_MARKER_TOKEN" \
          --expected-evidence-home-device "$EVIDENCE_HOME_DEVICE" \
          --expected-evidence-home-inode "$EVIDENCE_HOME_INODE"; then
        EVIDENCE_HOME_READY=0
      else
        echo "BLOCKER: secure isolated HOME cleanup failed; refusing path-based fallback: $EVIDENCE_HOME" >&2
      fi
    fi
    if [[ "$EVIDENCE_HOME_READY" == "0" && -n "$EVIDENCE_HOME_CONTAINER" && -d "$EVIDENCE_HOME_CONTAINER" ]]; then
      /bin/rmdir "$EVIDENCE_HOME_CONTAINER" 2>/dev/null || true
    fi
  fi
}
trap cleanup EXIT

select_isolated_evidence_home

# Any mode that can overwrite screenshot artifacts invalidates the previous
# complete-run receipt up front. Otherwise a failed or partial recapture could
# leave a still-fresh receipt that incorrectly authenticates a mixed image set.
if [[ "$DRY_RUN" != "1" && "$DOCTOR" != "1" && "$SEED_ONLY" != "1" ]]; then
  rm -f "$SUISUI_VISUAL_AX_AUDIT_RESULT"
fi

ui_evidence_product_source_commit() {
  local commit
  local source_ref="${SUISUI_VISUAL_SOURCE_REF:-HEAD}"
  commit="$(
    git -C "$ROOT_DIR" log -1 --format=%H "$source_ref" -- Sources Package.swift script/capture_ui_evidence.sh 2>/dev/null || true
  )"
  if [[ -n "$commit" ]]; then
    printf '%s\n' "$commit"
  else
    git -C "$ROOT_DIR" rev-parse HEAD
  fi
}

visual_product_source_is_clean() {
  local index_flags tracked_changes

  # The capture script defines which visible states count as evidence, so a dirty
  # harness is as provenance-breaking as a dirty app binary.
  index_flags="$(git -C "$ROOT_DIR" ls-files -v -- \
    Sources Package.swift script/capture_ui_evidence.sh)" \
    && ! grep -Eq '^[a-zS] ' <<<"$index_flags" \
    && tracked_changes="$(git -C "$ROOT_DIR" status --porcelain=v1 --untracked-files=no -- \
    Sources Package.swift script/capture_ui_evidence.sh)" \
    && [[ -z "$tracked_changes" ]] \
    && [[ -z "$(git -C "$ROOT_DIR" ls-files --others --exclude-standard -- Sources Package.swift script/capture_ui_evidence.sh)" ]]
}

assert_visual_product_source_is_committed() {
  if visual_product_source_is_clean; then
    return
  fi
  echo "BLOCKER: visual evidence source is dirty under Sources, Package.swift, or script/capture_ui_evidence.sh" >&2
  echo "NEXT: commit every evidence-source change before capture so receipt sourceCommit identifies the binary and harness that produced the screenshots." >&2
  return 1
}
require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 2
  fi
}

relative_path() {
  local path="$1"
  case "$path" in
    "$ROOT_DIR"/*) printf '%s\n' "${path#"$ROOT_DIR/"}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

ui_evidence_source_commit() {
  local commit
  commit="$(
    git -C "$ROOT_DIR" -c core.abbrev=8 log -1 --format=%h -- Sources Package.swift script/capture_ui_evidence.sh 2>/dev/null || true
  )"
  if [[ -n "$commit" ]]; then
    printf "%s" "$commit"
  else
    git -C "$ROOT_DIR" rev-parse --short=8 HEAD 2>/dev/null || printf "unknown"
  fi
}

app_env_args() {
  local args=("SUISUI_DISABLE_KEYCHAIN_SECRET_STORE=1")
  # A capture must have one canonical AX window and must not inherit or mutate
  # a developer's saved board geometry. Duplicate fallback windows make a
  # focused-window audit nondeterministic even when both belong to this PID.
  args+=("SUISUI_DISABLE_PROJECT_BOARD_FALLBACK=1")
  args+=("SUISUI_DISABLE_PROJECT_BOARD_PRESENTATION_PERSISTENCE=1")
  args+=("HOME=$EVIDENCE_HOME")
  args+=("CFFIXED_USER_HOME=$EVIDENCE_HOME")
  args+=("TZ=$EVIDENCE_TIME_ZONE")
  args+=("SUISUI_VISUAL_EVIDENCE_REFERENCE_INSTANT=$EVIDENCE_REFERENCE_INSTANT")
  args+=("SUISUI_VISUAL_EVIDENCE_TIME_ZONE=$EVIDENCE_TIME_ZONE")
  args+=("SUISUI_VISUAL_EVIDENCE_LOCALE_IDENTIFIER=$EVIDENCE_RECEIPT_LOCALE")
  # Pin Suisui's product language. Foundation/AppKit locale defaults are pinned
  # separately through launch arguments in open_evidence_app.
  args+=("SUISUI_LANGUAGE_PREFERENCE=$EVIDENCE_LOCALE")
  if [[ "$APPEARANCE_OVERRIDE" != "light" ]]; then
    # Dark and system semantic materials inherit the capture host's wallpaper
    # tint. Light evidence is already host-stable and keeps native rendering.
    args+=("SUISUI_VISUAL_EVIDENCE_STABLE_BACKDROP=1")
  fi
  if [[ -n "$DATABASE_PATH" ]]; then
    # Screenshot evidence must open the exact SQLite file seeded below; relying
    # on HOME-derived defaults can silently fall back to another database.
    args+=("SUISUI_DATABASE_PATH=$DATABASE_PATH")
  fi
  if [[ -n "$PROJECT_BOARD_SELECTION_OVERRIDE" ]]; then
    args+=("SUISUI_PROJECT_BOARD_SELECTED_DESTINATION=$PROJECT_BOARD_SELECTION_OVERRIDE")
  fi
  if [[ -n "$PROJECT_BOARD_SELECTED_TASK_OVERRIDE" ]]; then
    args+=("SUISUI_PROJECT_BOARD_SELECTED_TASK_ID=$PROJECT_BOARD_SELECTED_TASK_OVERRIDE")
  fi
  if [[ "$INBOX_EVIDENCE_CLEAR_SELECTION" == "1" ]]; then
    args+=("SUISUI_INBOX_EVIDENCE_CLEAR_SELECTION=1")
  fi
  if [[ -n "$SCHEDULE_MODE_OVERRIDE" ]]; then
    args+=("SUISUI_VISUAL_EVIDENCE_SCHEDULE_MODE=$SCHEDULE_MODE_OVERRIDE")
  fi
  if [[ -n "$APPEARANCE_OVERRIDE" ]]; then
    args+=("SUISUI_APPEARANCE_PREFERENCE=$APPEARANCE_OVERRIDE")
  fi
  if [[ "$APPEARANCE_OVERRIDE" == "system" ]]; then
    # Keep the product preference truthful while giving hosted GUI sessions a
    # deterministic system appearance that does not depend on the login user.
    args+=("SUISUI_VISUAL_EVIDENCE_SYSTEM_APPEARANCE=dark")
  fi
  if [[ "$SETTINGS_WINDOW_OVERRIDE" == "1" ]]; then
    args+=("SUISUI_OPEN_SETTINGS_ON_LAUNCH=1")
  fi
  if [[ -n "$SETTINGS_TAB_OVERRIDE" ]]; then
    args+=("SUISUI_SETTINGS_EVIDENCE_TAB=$SETTINGS_TAB_OVERRIDE")
  fi
  if [[ "$VOICE_COMMAND_WINDOW_OVERRIDE" == "1" ]]; then
    args+=("SUISUI_OPEN_VOICE_COMMAND_ON_LAUNCH=1")
  fi
  if [[ -n "$VOICE_SURFACE_OVERRIDE" ]]; then
    args+=("SUISUI_VISUAL_EVIDENCE_VOICE_SURFACE=$VOICE_SURFACE_OVERRIDE")
  fi
  printf '%s\0' "${args[@]}"
}

emit_evidence_app_diagnostic() {
  [[ -s "$EVIDENCE_APP_LOG" ]] || return 0
  echo "Sanitized Suisui launch diagnostic:" >&2
  /usr/bin/sed -E \
    -e 's#/(Users|Volumes)/[^[:space:]]+#<path>#g' \
    -e 's#/private/var/folders/[^[:space:]]+#<temp-path>#g' \
    -e 's#(/var)?/tmp/[^[:space:]]+#<temp-path>#g' \
    -e 's#(token|secret|password|api[_-]?key)[=:][^[:space:]]+#\1=<redacted>#g' \
    "$EVIDENCE_APP_LOG" | /usr/bin/tail -n 80 >&2
}

open_evidence_app() {
  local env_args=()
  local launch_args=(
    "-ApplePersistenceIgnoreState" "YES"
    "-AppleShowScrollBars" "Always"
    "-AppleLanguages" "$APPLE_LANGUAGES"
    "-AppleLocale" "$APPLE_LOCALE"
  )
  while IFS= read -r -d '' env_arg; do
    env_args+=("$env_arg")
  done < <(app_env_args)
  if [[ "$APPEARANCE_OVERRIDE" != "light" ]]; then
    # Registration-domain launch arguments are process-local. Disable desktop
    # tinting for Dark/System evidence without mutating the user's global
    # accessibility or appearance preferences.
    launch_args+=("-AppleReduceDesktopTinting" "YES")
  fi
  stop_evidence_app
  : >"$EVIDENCE_APP_LOG"
  # Direct launch preserves the isolated database, appearance, selected route,
  # Settings, and Voice Command env exactly. LaunchServices can drop or delay
  # those env values on some release hosts, which makes screenshot evidence
  # fail before the app exposes a real window.
  # Use the most constrained persistent-scrollbar setting so layout does not
  # inherit a local or hosted runner preference.
  /usr/bin/env -i PATH="$PATH" TMPDIR="$EVIDENCE_TMPDIR" "${env_args[@]}" \
    "$APP_BINARY" "${launch_args[@]}" \
    >>"$EVIDENCE_APP_LOG" 2>&1 &
  EVIDENCE_APP_LAUNCH_PID=$!
  EVIDENCE_APP_PID="$EVIDENCE_APP_LAUNCH_PID"
  EVIDENCE_APP_LAUNCH_IDENTITY="$(ax_wait_for_owned_process_identity "$EVIDENCE_APP_LAUNCH_PID" "$APP_BINARY" "$TARGET_TIMEOUT_SECONDS")" || {
    echo "failure_category=launch" >&2
    echo "failure_message=visual-launch-identity-unavailable" >&2
    emit_evidence_app_diagnostic
    return 1
  }
  EVIDENCE_APP_IDENTITY="$EVIDENCE_APP_LAUNCH_IDENTITY"
}

wait_for_app_process_exit() {
  [[ -z "${EVIDENCE_APP_PID:-}" && -z "${EVIDENCE_APP_LAUNCH_PID:-}" ]]
}

stop_evidence_app() {
  local owned_pid="${EVIDENCE_APP_PID:-}"
  local launch_pid="${EVIDENCE_APP_LAUNCH_PID:-}"
  if [[ -n "$owned_pid" ]]; then
    ax_terminate_owned_process "$owned_pid" "$APP_BINARY" "${EVIDENCE_APP_IDENTITY:-}"
  fi
  if [[ -n "$launch_pid" && "$launch_pid" != "$owned_pid" ]]; then
    ax_terminate_owned_process "$launch_pid" "$APP_BINARY" "${EVIDENCE_APP_LAUNCH_IDENTITY:-}"
  fi
  EVIDENCE_APP_PID=""
  EVIDENCE_APP_LAUNCH_PID=""
  EVIDENCE_APP_IDENTITY=""
  EVIDENCE_APP_LAUNCH_IDENTITY=""
  wait_for_app_process_exit
}

activate_evidence_app() {
  # Avoid LaunchServices activation; it can start a second app instance without
  # the isolated screenshot database, target selection, or appearance env.
  /usr/bin/osascript - "$EVIDENCE_APP_PID" "$APP_NAME" <<'APPLESCRIPT' >/dev/null 2>&1 &
on run argv
  set appPID to item 1 of argv as integer
  set appName to item 2 of argv
  tell application "System Events"
    set matchingProcesses to application processes whose unix id is appPID
    if (count of matchingProcesses) is 0 then return "missing"
    set targetProcess to item 1 of matchingProcesses
    tell targetProcess
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
      return
    fi
    sleep 0.1
  done
  kill "$osascript_pid" >/dev/null 2>&1 || true
  wait "$osascript_pid" >/dev/null 2>&1 || true
}

resolve_evidence_process_and_window() {
  local resolved_pid
  if ! resolved_pid="$(ax_wait_for_owned_app_pid "$EVIDENCE_APP_PID" "$APP_BINARY" "$TARGET_TIMEOUT_SECONDS")"; then
    EVIDENCE_WAIT_FAILURE_CATEGORY="launch"
    EVIDENCE_WAIT_FAILURE_REASON="visual-owned-pid-unavailable"
    return 1
  fi
  EVIDENCE_APP_PID="$resolved_pid"
  if ! EVIDENCE_APP_IDENTITY="$(ax_wait_for_owned_process_identity "$EVIDENCE_APP_PID" "$APP_BINARY" "$TARGET_TIMEOUT_SECONDS")"; then
    EVIDENCE_WAIT_FAILURE_CATEGORY="launch"
    EVIDENCE_WAIT_FAILURE_REASON="visual-owned-identity-unavailable"
    return 1
  fi
  if ! ax_wait_for_pid_owned_process "$APP_NAME" "$EVIDENCE_APP_PID" "$TARGET_TIMEOUT_SECONDS" "$APP_BINARY"; then
    EVIDENCE_WAIT_FAILURE_CATEGORY="launch"
    EVIDENCE_WAIT_FAILURE_REASON="visual-owned-process-unavailable"
    return 1
  fi
  if ! ax_wait_for_pid_owned_window "$APP_NAME" "$EVIDENCE_APP_PID" "" "$TARGET_TIMEOUT_SECONDS" "" "$APP_BINARY"; then
    EVIDENCE_WAIT_FAILURE_CATEGORY="window"
    EVIDENCE_WAIT_FAILURE_REASON="visual-window-unavailable"
    return 1
  fi
}

wait_for_process() {
  local attempt
  if [[ -z "$EVIDENCE_APP_PID" ]]; then
    echo "$APP_NAME launch pid is missing." >&2
    return 1
  fi

  for ((attempt = 1; attempt <= EVIDENCE_WINDOW_ATTEMPTS; attempt++)); do
    if resolve_evidence_process_and_window; then
      return 0
    fi
    if [[ "$attempt" -lt "$EVIDENCE_WINDOW_ATTEMPTS" && "$EVIDENCE_WAIT_FAILURE_CATEGORY" == "window" ]]; then
      echo "INFO: retrying normal UI capture after owned window publication timeout" >&2
      emit_evidence_app_diagnostic
      stop_evidence_app
      sleep 1
      open_evidence_app || return 1
    else
      break
    fi
  done

  echo "failure_category=$EVIDENCE_WAIT_FAILURE_CATEGORY" >&2
  echo "failure_message=$EVIDENCE_WAIT_FAILURE_REASON" >&2
  emit_evidence_app_diagnostic
  return 1
}

wait_for_database() {
  local database_path="$1"
  for _ in {1..40}; do
    if [[ -f "$database_path" ]]; then
      return 0
    fi
    sleep 0.25
  done
  echo "database was not created: $database_path" >&2
  exit 1
}

find_window_capture_metadata() {
  local window_name="${1:-}"
  SUISUI_WINDOW_OWNER="$APP_NAME" \
    SUISUI_WINDOW_OWNER_PID="$EVIDENCE_APP_PID" \
    SUISUI_WINDOW_NAME="$window_name" \
    /usr/bin/swift "$ROOT_DIR/script/ui_evidence_window_metadata.swift"
}

wait_for_window_capture_metadata() {
  local window_name="${1:-}"
  local metadata
  local deadline=$((SECONDS + TARGET_TIMEOUT_SECONDS))
  while true; do
    if metadata="$(find_window_capture_metadata "$window_name" 2>/dev/null)"; then
      printf '%s\n' "$metadata"
      return 0
    fi
    # Window restoration can be slower than process launch, so share the same
    # operator-controlled timeout as target marker validation.
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      break
    fi
    sleep 0.25
  done
  find_window_capture_metadata "$window_name"
}

wait_for_owned_evidence_window() {
  local window_name="${1:-}"
  local diagnostic_file="${2:-}"

  ax_wait_for_pid_owned_window "$APP_NAME" "$EVIDENCE_APP_PID" "$window_name" \
    "$TARGET_TIMEOUT_SECONDS" "$diagnostic_file" "$APP_BINARY"
}

target_marker_present() {
  local identifier="$1"
  local text="$2"
  local marker_mode="${3:-legacy}"
  local error_file
  local checker_pid
  local deadline
  local status
  local timed_out=0
  error_file="$(mktemp "${TMPDIR:-/tmp}/suisui-ui-target-marker-error.XXXXXX")"
  prepare_ax_marker_checker

  # AX marker scans use a bounded Swift AX traversal because SwiftUI's generated
  # accessibility tree can make AppleScript recursion stall on detail-heavy screens.
  # Compile the helper once; running it through `swift` for every marker leaves
  # swift-frontend children that a shell watchdog cannot reliably terminate.
  case "$marker_mode" in
    strict-task-card)
      SUISUI_UI_EVIDENCE_AX_MAX_NODES="$AX_MARKER_MAX_NODES" \
        SUISUI_UI_EVIDENCE_AX_REQUIRE_IDENTIFIER_SUBTREE=1 \
        SUISUI_UI_EVIDENCE_AX_REQUIRE_EXACT_IDENTIFIER=1 \
        "$AX_MARKER_CHECKER" "$APP_NAME" "$identifier" "$text" "$EVIDENCE_APP_PID" \
        >/dev/null 2>"$error_file" &
      ;;
    legacy)
      # Existing workflow markers intentionally allow identifier and text to
      # live in different runtime AX elements (for example Inbox Voice).
      SUISUI_UI_EVIDENCE_AX_MAX_NODES="$AX_MARKER_MAX_NODES" \
        "$AX_MARKER_CHECKER" "$APP_NAME" "$identifier" "$text" "$EVIDENCE_APP_PID" \
        >/dev/null 2>"$error_file" &
      ;;
    *)
      echo "invalid AX target marker mode: $marker_mode" >&2
      rm -f "$error_file"
      return 2
      ;;
  esac
  checker_pid=$!
  deadline=$((SECONDS + TARGET_TIMEOUT_SECONDS))
  while kill -0 "$checker_pid" >/dev/null 2>&1; do
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      timed_out=1
      kill "$checker_pid" >/dev/null 2>&1 || true
      sleep 1
      kill -9 "$checker_pid" >/dev/null 2>&1 || true
      break
    fi
    sleep 0.2
  done
  set +e
  wait "$checker_pid"
  status=$?
  set -e
  if [[ "$timed_out" == "1" ]]; then
    status=124
  fi
  if [[ "$status" -ne 0 ]]; then
    cat "$error_file" >&2
    if [[ "$status" -eq 124 || "$status" -eq 143 || "$status" -eq 137 ]]; then
      echo "AX target marker scan timed out after ${TARGET_TIMEOUT_SECONDS}s: $identifier => $text" >&2
    fi
  fi
  rm -f "$error_file"
  return "$status"
}

prepare_ax_marker_checker() {
  if [[ -x "$AX_MARKER_CHECKER" ]]; then
    return
  fi
  /usr/bin/swiftc "$ROOT_DIR/script/ui_evidence_ax_marker_check.swift" -o "$AX_MARKER_CHECKER"
}

prepare_ax_scroll_helper() {
  if [[ -x "$AX_SCROLL_HELPER" ]]; then
    return
  fi
  /usr/bin/swiftc "$ROOT_DIR/script/ui_evidence_ax_scroll_to.swift" -o "$AX_SCROLL_HELPER"
}

prepare_ax_scroll_container_helper() {
  if [[ -x "$AX_SCROLL_CONTAINER_HELPER" ]]; then
    return
  fi
  /usr/bin/swiftc "$ROOT_DIR/script/ui_evidence_ax_scroll_container.swift" -o "$AX_SCROLL_CONTAINER_HELPER"
}

prepare_ax_press_element_helper() {
  if [[ -x "$AX_PRESS_ELEMENT_HELPER" ]]; then
    return
  fi
  /usr/bin/swiftc "$ROOT_DIR/script/ui_evidence_ax_press_element.swift" -o "$AX_PRESS_ELEMENT_HELPER"
}

press_named_window_control() {
  local identifier="$1"
  local error_file
  local helper_pid
  local deadline
  local status
  local timed_out=0

  prepare_ax_press_element_helper
  error_file="$(mktemp "${TMPDIR:-/tmp}/suisui-ui-press-element-error.XXXXXX")"
  SUISUI_UI_EVIDENCE_AX_MAX_NODES="$AX_MARKER_MAX_NODES" \
    "$AX_PRESS_ELEMENT_HELPER" "$EVIDENCE_APP_PID" "$identifier" \
    >/dev/null 2>"$error_file" &
  helper_pid=$!
  deadline=$((SECONDS + TARGET_TIMEOUT_SECONDS))
  while kill -0 "$helper_pid" >/dev/null 2>&1; do
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      timed_out=1
      kill "$helper_pid" >/dev/null 2>&1 || true
      sleep 1
      kill -9 "$helper_pid" >/dev/null 2>&1 || true
      break
    fi
    sleep 0.2
  done
  set +e
  wait "$helper_pid"
  status=$?
  set -e
  if [[ "$timed_out" == "1" ]]; then
    status=124
  fi
  if [[ "$status" -ne 0 ]]; then
    cat "$error_file" >&2
    echo "Could not activate named window control: $identifier" >&2
  fi
  rm -f "$error_file"
  return "$status"
}

scroll_ax_container_down() {
  local identifier="$1"
  prepare_ax_scroll_container_helper
  SUISUI_UI_EVIDENCE_AX_MAX_NODES="$AX_MARKER_MAX_NODES" \
    SUISUI_UI_EVIDENCE_AX_SCROLL_EVENTS=10 \
    "$AX_SCROLL_CONTAINER_HELPER" "$EVIDENCE_APP_PID" "$identifier" >/dev/null
}

prepare_ax_target_frame_auditor() {
  if [[ -x "$AX_TARGET_FRAME_AUDITOR" ]]; then
    return
  fi
  /usr/bin/swiftc "$ROOT_DIR/script/ui_evidence_ax_target_frame_audit.swift" -o "$AX_TARGET_FRAME_AUDITOR"
}

prepare_ax_window_resizer() {
  if [[ -x "$AX_RESIZE_WINDOW_HELPER_BINARY" ]]; then
    return
  fi
  /usr/bin/swiftc "$AX_RESIZE_WINDOW_HELPER_SOURCE" -o "$AX_RESIZE_WINDOW_HELPER_BINARY"
}

prepare_pointer_parker() {
  if [[ -x "$POINTER_PARKER" ]]; then
    return
  fi
  /usr/bin/swiftc "$ROOT_DIR/script/ui_evidence_pointer_park.swift" -o "$POINTER_PARKER"
}

park_pointer_outside_evidence_window() {
  prepare_pointer_parker
  # Canonical evidence windows start at x >= 80 and y >= 70, so the screen's
  # top-left corner is outside product content for every capture viewport.
  "$POINTER_PARKER" 8 8
}

audit_ax_target_frame() {
  local identifier="$1"
  local window_name="$2"
  local audit_mode="${3:-${AX_TARGET_FRAME_AUDIT_MODE:-receipt}}"
  local window_x="${4:-}"
  local window_y="${5:-}"
  local window_width="${6:-}"
  local window_height="${7:-}"
  local window_frame_args=()
  local output_file
  local error_file
  local auditor_pid
  local deadline
  local status
  local timed_out=0

  output_file="$(mktemp "${TMPDIR:-/tmp}/suisui-ui-target-frame-output.XXXXXX")"
  error_file="$(mktemp "${TMPDIR:-/tmp}/suisui-ui-target-frame-error.XXXXXX")"
  prepare_ax_target_frame_auditor
  if [[ -n "$window_x" || -n "$window_y" || -n "$window_width" || -n "$window_height" ]]; then
    [[ -n "$window_x" && -n "$window_y" && -n "$window_width" && -n "$window_height" ]] || {
      echo "AX target frame audit requires a complete captured window frame" >&2
      return 2
    }
    window_frame_args=("$window_x" "$window_y" "$window_width" "$window_height")
  fi
  if [[ "$audit_mode" == "fingerprint" ]]; then
    SUISUI_UI_EVIDENCE_AX_MAX_NODES="$AX_MARKER_MAX_NODES" \
      SUISUI_UI_EVIDENCE_AX_IDENTITY_FINGERPRINT=1 \
      "$AX_TARGET_FRAME_AUDITOR" "$APP_NAME" "$identifier" "$EVIDENCE_APP_PID" "$window_name" "${window_frame_args[@]}" \
      >"$output_file" 2>"$error_file" &
  else
    SUISUI_UI_EVIDENCE_AX_MAX_NODES="$AX_MARKER_MAX_NODES" \
      "$AX_TARGET_FRAME_AUDITOR" "$APP_NAME" "$identifier" "$EVIDENCE_APP_PID" "$window_name" "${window_frame_args[@]}" \
      >"$output_file" 2>"$error_file" &
  fi
  auditor_pid=$!
  deadline=$((SECONDS + TARGET_TIMEOUT_SECONDS))
  while kill -0 "$auditor_pid" >/dev/null 2>&1; do
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      timed_out=1
      kill "$auditor_pid" >/dev/null 2>&1 || true
      sleep 1
      kill -9 "$auditor_pid" >/dev/null 2>&1 || true
      break
    fi
    sleep 0.2
  done
  set +e
  wait "$auditor_pid"
  status=$?
  set -e
  if [[ "$timed_out" == "1" ]]; then
    status=124
  fi
  if [[ "$status" -ne 0 ]]; then
    cat "$error_file" >&2
    if [[ "$status" -eq 124 || "$status" -eq 143 || "$status" -eq 137 ]]; then
      echo "AX target frame audit timed out after ${TARGET_TIMEOUT_SECONDS}s: $identifier" >&2
    fi
    rm -f "$output_file" "$error_file"
    return "$status"
  fi
  cat "$output_file"
  rm -f "$output_file" "$error_file"
}

wait_for_stable_ax_target_frame() {
  local identifier="$1"
  local window_name="$2"
  local audit_mode="${3:-${AX_TARGET_FRAME_AUDIT_MODE:-receipt}}"
  local window_x="${4:-}"
  local window_y="${5:-}"
  local window_width="${6:-}"
  local window_height="${7:-}"
  local stable_samples_required=3
  local stable_samples=0
  local previous_sample=""
  local current_sample
  local deadline=$((SECONDS + TARGET_TIMEOUT_SECONDS))

  while [[ "$SECONDS" -lt "$deadline" ]]; do
    if ! current_sample="$(audit_ax_target_frame "$identifier" "$window_name" "$audit_mode" "$window_x" "$window_y" "$window_width" "$window_height")"; then
      # CGWindow can publish the owned window one scheduling turn before the
      # Accessibility server publishes kAXWindows on hosted macOS runners.
      # Retry only inside the existing deadline and require a fresh sequence
      # of stable samples, so a real missing/incorrect target still fails closed.
      previous_sample=""
      stable_samples=0
      sleep 0.25
      continue
    fi
    if [[ "$current_sample" == "$previous_sample" ]]; then
      stable_samples=$((stable_samples + 1))
    else
      previous_sample="$current_sample"
      stable_samples=1
    fi
    if [[ "$stable_samples" -ge "$stable_samples_required" ]]; then
      printf '%s\n' "$current_sample"
      return 0
    fi
    sleep 0.25
  done

  echo "AX target frame did not converge for screenshot evidence: $identifier" >&2
  return 1
}

receipt_ax_target_frame_fields() {
  local fingerprint="$1"
  local identifier target_width target_height visible_width visible_height
  IFS=$'\t' read -r identifier target_width target_height visible_width visible_height _ <<<"$fingerprint"
  if [[ -z "$identifier" || -z "$target_width" || -z "$target_height" || -z "$visible_width" || -z "$visible_height" ]]; then
    echo "invalid AX identity fingerprint; receipt fields are incomplete" >&2
    return 1
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$identifier" "$target_width" "$target_height" "$visible_width" "$visible_height"
}

scroll_ax_target_into_view() {
  local identifier="$1"
  local label="$2"
  local error_file
  local helper_pid
  local deadline
  local status
  local timed_out=0

  if [[ -z "$identifier" ]]; then
    return 0
  fi

  error_file="$(mktemp "${TMPDIR:-/tmp}/suisui-ui-scroll-target-error.XXXXXX")"
  prepare_ax_scroll_helper
  SUISUI_UI_EVIDENCE_AX_MAX_NODES="$AX_MARKER_MAX_NODES" \
    "$AX_SCROLL_HELPER" "$APP_NAME" "$identifier" "$EVIDENCE_APP_PID" \
    >/dev/null 2>"$error_file" &
  helper_pid=$!
  deadline=$((SECONDS + TARGET_TIMEOUT_SECONDS))
  while kill -0 "$helper_pid" >/dev/null 2>&1; do
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      timed_out=1
      kill "$helper_pid" >/dev/null 2>&1 || true
      sleep 1
      kill -9 "$helper_pid" >/dev/null 2>&1 || true
      break
    fi
    sleep 0.2
  done
  set +e
  wait "$helper_pid"
  status=$?
  set -e
  if [[ "$timed_out" == "1" ]]; then
    status=124
  fi
  if [[ "$status" -ne 0 ]]; then
    cat "$error_file" >&2
    echo "Could not scroll $label to live AX target: $identifier" >&2
  fi
  rm -f "$error_file"
  return "$status"
}

assert_project_board_destination_ready() {
  local label="$1"
  local marker_spec="$2"
  local markers=()
  local marker
  local identifier
  local text
  local marker_mode
  local missing=()

  if [[ -z "$marker_spec" ]]; then
    return 0
  fi

  IFS='|' read -r -a markers <<<"$marker_spec"
  for marker in "${markers[@]}"; do
    [[ -z "$marker" ]] && continue
    if [[ "$marker" != *"=>"* ]]; then
      echo "invalid UI evidence target marker for $label: $marker" >&2
      return 2
    fi
    identifier="${marker%%=>*}"
    text="${marker#*=>}"
    if [[ "$identifier" == task-card-open-details-* ]]; then
      if [[ "$identifier" =~ ^task-card-open-details-[0-9]+$ ]]; then
        marker_mode="strict-task-card"
      else
        echo "invalid task-card UI evidence identifier for $label: $identifier" >&2
        return 2
      fi
    else
      marker_mode="legacy"
    fi
    if ! target_marker_present "$identifier" "$text" "$marker_mode"; then
      missing+=("$marker")
    fi
  done

  if [[ "${#missing[@]}" -gt 0 ]]; then
    printf 'UI evidence target not ready for %s; missing marker(s): %s\n' "$label" "${missing[*]}" >&2
    return 1
  fi
}

wait_for_project_board_destination() {
  local label="$1"
  local marker_spec="$2"
  local deadline=$((SECONDS + TARGET_TIMEOUT_SECONDS))

  while true; do
    if assert_project_board_destination_ready "$label" "$marker_spec" >/dev/null 2>&1; then
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      assert_project_board_destination_ready "$label" "$marker_spec"
      echo "BLOCKER: UI evidence target did not become ready for $label within ${TARGET_TIMEOUT_SECONDS}s" >&2
      echo "NEXT: keep the intended Suisui window visible, verify Accessibility permission for Terminal/Codex, and rerun script/capture_ui_evidence.sh." >&2
      return 1
    fi
    sleep 0.25
  done
}

position_window_for_capture() {
  local window_name="${1:-}"
  local diagnostic_file="${2:-}"
  local viewport="$VISUAL_BASELINE_VIEWPORT"
  # Hosted macOS runners can expose only a 1024x768 desktop. Positioning away
  # from the origin makes WindowServer shrink a compact evidence window even
  # though the requested viewport itself fits the display.
  local origin_x=0
  local origin_y=0

  if [[ "$SETTINGS_WINDOW_OVERRIDE" == "1" ]]; then
    viewport="$SETTINGS_VISUAL_BASELINE_VIEWPORT"
  elif [[ "$VOICE_COMMAND_WINDOW_OVERRIDE" == "1" ]]; then
    viewport="$VOICE_COMMAND_VISUAL_BASELINE_VIEWPORT"
  elif [[ -n "$window_name" && "$window_name" != "Voice Command" ]]; then
    viewport="$SETTINGS_VISUAL_BASELINE_VIEWPORT"
  fi

  local width="${viewport%x*}"
  local height="${viewport#*x}"
  local deadline=$((SECONDS + TARGET_TIMEOUT_SECONDS))
  local window_metadata
  local window_id window_x window_y window_width window_height
  local ax_window_size
  local observed_width=""
  local observed_height=""
  if [[ ! "$width" =~ ^[0-9]+$ || ! "$height" =~ ^[0-9]+$ ]]; then
    echo "invalid viewport: $viewport" >&2
    return 2
  fi

  while true; do
    if window_metadata="$(wait_for_window_capture_metadata "$window_name" 2>/dev/null)"; then
      set -- $window_metadata
      window_id="$1"
      window_x="$2"
      window_y="$3"
      window_width="$4"
      window_height="$5"
      prepare_ax_window_resizer
      if ax_window_size="$(
        "$AX_RESIZE_WINDOW_HELPER_BINARY" \
          "$EVIDENCE_APP_PID" \
          "$window_x" "$window_y" "$window_width" "$window_height" \
          "$width" "$height" "$origin_x" "$origin_y" \
          2>>"${diagnostic_file:-/dev/null}"
      )"; then
        read -r _ _ observed_width observed_height <<<"$ax_window_size"
      fi
      if window_metadata="$(wait_for_window_capture_metadata "$window_name" 2>/dev/null)"; then
        # CG window bounds include compositor decoration on newer macOS
        # versions even when `screencapture -o` excludes the shadow. The AX
        # size is the product's logical viewport and is therefore the value
        # bound to the manifest and receipt.
        # AppKit clamps y=0 below the menu bar on a normal desktop. The logical
        # viewport is the release contract; the following CG lookup and AX
        # target audit bind capture to the actual clamped frame.
        if [[ "$observed_width" == "$width" && "$observed_height" == "$height" ]]; then
          POSITIONED_WINDOW_WIDTH="$observed_width"
          POSITIONED_WINDOW_HEIGHT="$observed_height"
          park_pointer_outside_evidence_window
          return 0
        fi
      fi
    fi

    if [[ "$SECONDS" -ge "$deadline" ]]; then
      break
    fi

    # SwiftUI can replace the route window after the initial AX wait. Reacquire
    # the window from the same owned PID before retrying, instead of falling
    # through to another process or accepting stale CG metadata.
    echo "INFO: waiting for recreated owned evidence window before positioning" >&2
    activate_evidence_app
    sleep 0.25
  done

  echo "failure_category=window" >&2
  if [[ -n "$observed_width" && -n "$observed_height" ]]; then
    echo "failure_message=visual-window-viewport-mismatch requested=${width}x${height} observed=${observed_width}x${observed_height}" >&2
  else
    echo "failure_message=visual-window-position-unavailable" >&2
  fi
  return 1
}

assert_screenshot_has_visible_content() {
  local image_path="$1"

  /usr/bin/swift "$ROOT_DIR/script/ui_evidence_content_check.swift" "$image_path"
}

print_capture_failure_guidance() {
  local appearance="$1"
  local output_path="$2"
  local window_context="$3"

  {
    echo "UI screenshot capture could not produce valid visible pixels for appearance: $appearance"
    echo "output: $output_path"
    echo "selected Suisui window: $window_context"
    echo "Open System Settings > Privacy & Security > Screen Recording / Screen & System Audio Recording and allow the terminal or Codex app that runs this script."
    echo "Quit and reopen the terminal or Codex app after granting permission, then rerun: script/capture_ui_evidence.sh"
    echo "For debugging, rerun with SUISUI_UI_EVIDENCE_KEEP_HOME=1 to keep the isolated HOME: $EVIDENCE_HOME"
  } >&2
}

write_appearance_preference() {
  local appearance="$1"
  write_app_preference suisui.appearancePreference "$appearance"
}

write_app_preference() {
  local key="$1"
  local value="$2"

  mkdir -p "$EVIDENCE_HOME/Library/Preferences"
  /usr/bin/env \
    HOME="$EVIDENCE_HOME" \
    CFFIXED_USER_HOME="$EVIDENCE_HOME" \
    /usr/bin/defaults write "$BUNDLE_IDENTIFIER" "$key" -string "$value"
}

localized_evidence_day_label() {
  local stored_day="$1"
  case "$EVIDENCE_LOCALE" in
    english)
      LC_ALL=en_US.UTF-8 /bin/date -j -u -f "%Y-%m-%d" "$stored_day" "+%b %e" \
        | tr -s ' '
      ;;
    japanese)
      local month="${stored_day:5:2}"
      local day="${stored_day:8:2}"
      printf '%d月%d日\n' "$((10#$month))" "$((10#$day))"
      ;;
  esac
}

prepare_visual_fixture_seeder() {
  if [[ -n "$VISUAL_FIXTURE_SEEDER_BIN" ]]; then
    if [[ ! -f "$VISUAL_FIXTURE_SEEDER_BIN" || ! -x "$VISUAL_FIXTURE_SEEDER_BIN" || -L "$VISUAL_FIXTURE_SEEDER_BIN" ]]; then
      echo "BLOCKER: SUISUI_VISUAL_FIXTURE_SEEDER_BIN must be a non-symlink executable file" >&2
      return 2
    fi
    local seeder_parent_real
    seeder_parent_real="$(cd "$(dirname "$VISUAL_FIXTURE_SEEDER_BIN")" && pwd -P)"
    case "$seeder_parent_real/" in
      "$ROOT_DIR_REAL/.build/"*) ;;
      *)
        echo "BLOCKER: SUISUI_VISUAL_FIXTURE_SEEDER_BIN must resolve below the repository .build directory" >&2
        return 2
        ;;
    esac
    VISUAL_FIXTURE_SEEDER_BIN="$seeder_parent_real/$(basename "$VISUAL_FIXTURE_SEEDER_BIN")"
    return 0
  fi

  require_command swift
  swift build --package-path "$ROOT_DIR" --product SuisuiVisualFixtureSeeder
  VISUAL_FIXTURE_SEEDER_BIN="$(
    swift build --package-path "$ROOT_DIR" --show-bin-path
  )/SuisuiVisualFixtureSeeder"
}

create_isolated_evidence_home() {
  local create_output
  local key
  local value
  local extra

  if [[ "$EVIDENCE_HOME_READY" == "1" ]]; then
    return 0
  fi
  create_output="$(
    SUISUI_LANGUAGE_PREFERENCE="$EVIDENCE_LOCALE" "$VISUAL_FIXTURE_SEEDER_BIN" \
      --create-evidence-home \
      --path "$EVIDENCE_HOME" \
      --evidence-home-marker-token "$EVIDENCE_HOME_MARKER_TOKEN"
  )" || return $?

  EVIDENCE_HOME_DEVICE=""
  EVIDENCE_HOME_INODE=""
  while IFS='=' read -r key value extra; do
    if [[ -n "$extra" || -z "$key" || -z "$value" ]]; then
      echo "BLOCKER: secure isolated HOME creator returned malformed metadata" >&2
      return 2
    fi
    case "$key" in
      evidence_home_device)
        [[ -z "$EVIDENCE_HOME_DEVICE" && "$value" =~ ^-?[0-9]+$ ]] || {
          echo "BLOCKER: secure isolated HOME creator returned invalid device metadata" >&2
          return 2
        }
        EVIDENCE_HOME_DEVICE="$value"
        ;;
      evidence_home_inode)
        [[ -z "$EVIDENCE_HOME_INODE" && "$value" =~ ^[0-9]+$ ]] || {
          echo "BLOCKER: secure isolated HOME creator returned invalid inode metadata" >&2
          return 2
        }
        EVIDENCE_HOME_INODE="$value"
        ;;
      *)
        echo "BLOCKER: secure isolated HOME creator returned unknown metadata: $key" >&2
        return 2
        ;;
    esac
  done <<<"$create_output"

  if [[ -z "$EVIDENCE_HOME_DEVICE" || -z "$EVIDENCE_HOME_INODE" ]]; then
    echo "BLOCKER: secure isolated HOME creator did not attest the requested identity" >&2
    return 2
  fi
  EVIDENCE_HOME_READY=1
}

seed_capture_database() {
  local database_path="$1"
  local seed_output
  seed_output="$(
    HOME="$EVIDENCE_HOME" CFFIXED_USER_HOME="$EVIDENCE_HOME" \
      SUISUI_LANGUAGE_PREFERENCE="$EVIDENCE_LOCALE" "$VISUAL_FIXTURE_SEEDER_BIN" \
      --database "$database_path" \
      --evidence-home "$EVIDENCE_HOME" \
      --evidence-home-marker-token "$EVIDENCE_HOME_MARKER_TOKEN" \
      --expected-evidence-home-device "$EVIDENCE_HOME_DEVICE" \
      --expected-evidence-home-inode "$EVIDENCE_HOME_INODE" \
      --capture-reference-instant "$EVIDENCE_REFERENCE_INSTANT"
  )" || return $?

  CAPTURE_PROJECT_ID=""
  CAPTURE_INBOX_VOICE_TASK_ID=""
  CAPTURE_TASK_ID=""
  CAPTURE_REVIEW_TASK_ID=""
  CAPTURE_UNSCHEDULED_TASK_ID=""
  CAPTURE_DUE_DATE=""
  CAPTURE_REVIEW_DUE_DATE=""

  local key value extra
  while IFS='=' read -r key value extra; do
    if [[ -z "$key" && -z "$value" && -z "$extra" ]]; then
      continue
    fi
    if [[ -n "$extra" || -z "$value" ]]; then
      echo "BLOCKER: malformed visual fixture seeder receipt" >&2
      return 2
    fi
    # Parse only a fixed data contract. Never source or eval seeder output:
    # even a compromised build artifact must not turn receipt text into shell.
    case "$key" in
      project_id)
        [[ -z "$CAPTURE_PROJECT_ID" ]] || { echo "BLOCKER: duplicate project_id receipt" >&2; return 2; }
        CAPTURE_PROJECT_ID="$value"
        ;;
      inbox_voice_task_id)
        [[ -z "$CAPTURE_INBOX_VOICE_TASK_ID" ]] || { echo "BLOCKER: duplicate inbox_voice_task_id receipt" >&2; return 2; }
        CAPTURE_INBOX_VOICE_TASK_ID="$value"
        ;;
      capture_task_id)
        [[ -z "$CAPTURE_TASK_ID" ]] || { echo "BLOCKER: duplicate capture_task_id receipt" >&2; return 2; }
        CAPTURE_TASK_ID="$value"
        ;;
      review_task_id)
        [[ -z "$CAPTURE_REVIEW_TASK_ID" ]] || { echo "BLOCKER: duplicate review_task_id receipt" >&2; return 2; }
        CAPTURE_REVIEW_TASK_ID="$value"
        ;;
      unscheduled_task_id)
        [[ -z "$CAPTURE_UNSCHEDULED_TASK_ID" ]] || { echo "BLOCKER: duplicate unscheduled_task_id receipt" >&2; return 2; }
        CAPTURE_UNSCHEDULED_TASK_ID="$value"
        ;;
      capture_due_date)
        [[ -z "$CAPTURE_DUE_DATE" ]] || { echo "BLOCKER: duplicate capture_due_date receipt" >&2; return 2; }
        CAPTURE_DUE_DATE="$value"
        ;;
      review_due_date)
        [[ -z "$CAPTURE_REVIEW_DUE_DATE" ]] || { echo "BLOCKER: duplicate review_due_date receipt" >&2; return 2; }
        CAPTURE_REVIEW_DUE_DATE="$value"
        ;;
      *)
        echo "BLOCKER: unknown visual fixture seeder receipt key: $key" >&2
        return 2
        ;;
    esac
  done <<<"$seed_output"

  local identifier
  for identifier in \
    "$CAPTURE_PROJECT_ID" \
    "$CAPTURE_INBOX_VOICE_TASK_ID" \
    "$CAPTURE_TASK_ID" \
    "$CAPTURE_REVIEW_TASK_ID" \
    "$CAPTURE_UNSCHEDULED_TASK_ID"; do
    if [[ ! "$identifier" =~ ^[0-9]+$ ]]; then
      echo "BLOCKER: visual fixture seeder receipt has a non-numeric identifier" >&2
      return 2
    fi
  done
  if [[ ! "$CAPTURE_DUE_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ \
        || ! "$CAPTURE_REVIEW_DUE_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "BLOCKER: visual fixture seeder receipt has a non-canonical due date" >&2
    return 2
  fi
}

persist_project_board_selection() {
  local project_id="$CAPTURE_PROJECT_ID"
  local inbox_voice_task_id="$CAPTURE_INBOX_VOICE_TASK_ID"
  local capture_task_id="$CAPTURE_TASK_ID"
  local review_task_id="$CAPTURE_REVIEW_TASK_ID"
  local unscheduled_task_id="$CAPTURE_UNSCHEDULED_TASK_ID"
  local capture_due_date="$CAPTURE_DUE_DATE"
  local review_due_date="$CAPTURE_REVIEW_DUE_DATE"
  local planned_label
  local medium_label
  local high_label
  local no_due_date_label
  local inbox_label
  local inbox_classification_actions_label
  # AX readiness must match the human date shown by the app, not the stored
  # yyyy-MM-dd value. Otherwise improving date readability makes the capture
  # harness wait forever for text the product correctly stopped exposing.
  capture_due_label="$(localized_evidence_day_label "$capture_due_date")"
  review_due_label="$(localized_evidence_day_label "$review_due_date")"

  # These values mirror the canonical Localizable.strings entries used by the
  # task metadata accessibility value in each capture locale.
  case "$EVIDENCE_LOCALE" in
    english)
      inbox_label="Inbox"
      planned_label="Planned"
      in_progress_label="In Progress"
      medium_label="Medium"
      high_label="High"
      no_due_date_label="No due date"
      inbox_classification_actions_label="Inbox classification actions"
      ;;
    japanese)
      inbox_label="インボックス"
      planned_label="予定"
      in_progress_label="進行中"
      medium_label="中"
      high_label="高"
      no_due_date_label="期限なし"
      inbox_classification_actions_label="インボックス分類操作"
      ;;
  esac

  PROJECT_BOARD_SELECTION_OVERRIDE="project:$project_id"
  # SwiftUI combines each card into its parent button in the runtime AX tree.
  # Bind title and metadata proof to that exact task button so a hidden child
  # identifier or another card's text cannot authenticate the screenshot.
  PROJECT_BOARD_SELECTED_TASK_OVERRIDE="$review_task_id"
  PROJECT_BOARD_TARGET_MARKERS="project-board-detail=>Launch Readiness|task-card-open-details-$capture_task_id=>Capture launch screenshots|task-card-open-details-$capture_task_id=>$planned_label, $high_label, $capture_due_label|task-card-open-details-$review_task_id=>Review VoiceOver focus path|task-card-open-details-$review_task_id=>$in_progress_label, $high_label, $review_due_label|task-card-open-details-$unscheduled_task_id=>$planned_label, $medium_label, $no_due_date_label"
  INBOX_VOICE_TASK_OVERRIDE="$inbox_voice_task_id"
  local inbox_voice_title
  case "$EVIDENCE_LOCALE" in
    english) inbox_voice_title="Create tomorrow's presentation materials" ;;
    japanese) inbox_voice_title="明日のプレゼン資料を作成する" ;;
  esac
  INBOX_VOICE_TARGET_MARKERS="inbox-workflow=>$inbox_label|inbox-voice-intake-detail=>Voice intake detail for $inbox_voice_title|inbox-action-panel=>$inbox_classification_actions_label"
  write_app_preference suisui.projectBoard.selectedDestination "$PROJECT_BOARD_SELECTION_OVERRIDE"
}

capture_visible_window() {
  local label="$1"
  local output_path="$2"
  local window_name="${3:-}"
  local target_identifier="${4:-}"
  local expected_appearance="${label%% *}"
  if [[ "$expected_appearance" == "system" ]]; then
    expected_appearance="dark"
  fi

  if [[ -z "$target_identifier" ]]; then
    echo "missing AX target frame audit identifier for $label" >&2
    exit 2
  fi

  local capture_attempt
  local capture_attempts=3
  local capture_ready=0
  local window_metadata
  local window_id window_x window_y window_width window_height
  local window_context=""
  local target_frame_audit
  local target_frame_fingerprint
  local AX_TARGET_FRAME_AUDIT_MODE="fingerprint"
  local successful_window_width=""
  local successful_window_height=""
  local successful_target_frame_audit=""
  local first_raster="$VISUAL_FIRST_RASTER"
  local second_raster="$output_path"
  local second_window_metadata
  local second_target_frame_fingerprint
  for ((capture_attempt = 1; capture_attempt <= capture_attempts; capture_attempt++)); do
    # A route transition can recreate the window between attempts. Reposition
    # first, then bind this exact attempt to fresh PID-owned CG bounds and a
    # converged AX target frame. Only a successful attempt is written to the
    # receipt, so stale window IDs or frames cannot authenticate the raster.
    position_window_for_capture "$window_name"
    sleep 0.25
    window_metadata="$(wait_for_window_capture_metadata "$window_name")"
    set -- $window_metadata
    window_id="$1"
    window_x="$2"
    window_y="$3"
    window_width="$4"
    window_height="$5"
    window_context="id=$window_id bounds=${window_width}x${window_height}+${window_x}+${window_y}"
    target_frame_audit="$(wait_for_stable_ax_target_frame "$target_identifier" "$window_name" "$AX_TARGET_FRAME_AUDIT_MODE" "$window_x" "$window_y" "$window_width" "$window_height")"
    target_frame_fingerprint="$target_frame_audit"
    target_frame_audit="$(receipt_ax_target_frame_fields "$target_frame_fingerprint")"

    rm -f "$output_path" "$first_raster"
    # Window shadows change raster bounds depending on transient activation
    # state. Excluding them binds repeated captures to the logical viewport
    # instead of nondeterministic compositor padding.
    if screencapture -x -o -l "$window_id" "$first_raster"; then
      if [[ -s "$first_raster" ]] && assert_screenshot_has_visible_content "$first_raster"; then
        # AX geometry can settle before SwiftUI child text reaches the
        # compositor. Reconfirm the same PID-owned window and target frame,
        # then accept only two consecutive rasters that satisfy the canonical
        # manifest thresholds. This prevents a partially rendered chip from
        # becoming evidence while tolerating bounded antialiasing noise.
        sleep 0.2
        second_window_metadata="$(wait_for_window_capture_metadata "$window_name")"
        # A fresh three-sample acquisition rejects a target that briefly
        # returns to the same frame while its SwiftUI subtree is still moving.
        set -- $second_window_metadata
        second_target_frame_fingerprint="$(wait_for_stable_ax_target_frame "$target_identifier" "$window_name" "$AX_TARGET_FRAME_AUDIT_MODE" "$2" "$3" "$4" "$5")"
        if [[ "$second_window_metadata" == "$window_metadata" && "$second_target_frame_fingerprint" == "$target_frame_fingerprint" ]] \
          && screencapture -x -o -l "$window_id" "$second_raster" \
          && [[ -s "$second_raster" ]] \
          && assert_screenshot_has_visible_content "$second_raster" \
          && "$VISUAL_APPEARANCE_CHECKER" "$second_raster" "$expected_appearance" \
          && "$VISUAL_RASTER_STABILITY_CHECKER" \
            --manifest "$VISUAL_BASELINE_MANIFEST" \
            --first "$first_raster" \
            --second "$second_raster"; then
          successful_window_width="$POSITIONED_WINDOW_WIDTH"
          successful_window_height="$POSITIONED_WINDOW_HEIGHT"
          successful_target_frame_audit="$target_frame_audit"
          capture_ready=1
          rm -f "$first_raster"
          break
        fi
        echo "INFO: screenshot raster did not converge on attempt $capture_attempt; retrying the owned window." >&2
      fi
    fi
    # AX readiness can precede the final compositor frame on hosted runners.
    # Re-raise the same PID-owned window and retry instead of accepting a
    # partially black raster as baseline evidence.
    activate_evidence_app
    sleep 1
  done
  rm -f "$first_raster"

  if [[ "$capture_ready" != "1" ]]; then
    print_capture_failure_guidance "$label" "$output_path" "$window_context"
    echo "screen capture did not produce complete visible content after ${capture_attempts} attempts." >&2
    rm -f "$output_path"
    exit 1
  fi

  /usr/bin/sips -g pixelWidth -g pixelHeight "$output_path" >/dev/null

  local bytes
  bytes="$(wc -c <"$output_path" | tr -d '[:space:]')"
  if [[ "$bytes" -lt 30000 ]]; then
    echo "screenshot is unexpectedly small ($bytes bytes): $output_path" >&2
    print_capture_failure_guidance "$label" "$output_path" "$window_context"
    echo "This usually means Screen Recording permission is missing or the captured image is blank." >&2
    rm -f "$output_path"
    exit 1
  fi

  local sha256
  sha256="$(/usr/bin/shasum -a 256 "$output_path" | /usr/bin/awk '{print $1}')"
  if [[ ! "$sha256" =~ ^[0-9a-f]{64}$ ]]; then
    echo "could not compute canonical screenshot SHA-256: $output_path" >&2
    rm -f "$output_path"
    exit 1
  fi

  # Record only after the live AX window was selected and the raster passed all
  # health checks. The receipt is intentionally end-of-run so partial captures
  # can never be mistaken for complete runtime AX evidence.
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(basename "$output_path")" "$label" "$successful_window_width" "$successful_window_height" "$successful_target_frame_audit" "$sha256" \
    >>"$AX_CAPTURE_RECEIPT_TSV"
}

open_mcp_settings_tab() {
  wait_for_window_capture_metadata >/dev/null
}

open_settings_appearance_tab() {
  wait_for_window_capture_metadata >/dev/null
}

open_settings_overview_tab() {
  wait_for_window_capture_metadata >/dev/null
}

open_settings_sync_tab() {
  wait_for_window_capture_metadata >/dev/null
}

prepare_named_evidence_window() {
  local window_name="$1"
  local label="$2"
  local marker_spec="$3"
  local preparation_control_identifier="${4:-}"
  local window_attempt
  local readiness_diagnostic

  # The process-level readiness probe can succeed on the Project Board before
  # the requested Settings or Voice Command workspace is ready. Reacquire the
  # board window after AX marker traversal; hosted WindowServer has twice
  # withdrawn an auxiliary window between the first probe and the capture, so
  # retry the complete owned-process launch instead of accepting a stale window
  # or weakening the visual gate.
  for ((window_attempt = 1; window_attempt <= EVIDENCE_ROUTE_ATTEMPTS; window_attempt++)); do
    readiness_diagnostic="$EVIDENCE_TMPDIR/named-evidence-window.$$.attempt-$window_attempt.err"
    : >"$readiness_diagnostic"
    stop_evidence_app
    write_appearance_preference "$APPEARANCE_OVERRIDE"

    if open_evidence_app 2>>"$readiness_diagnostic" \
      && wait_for_process 2>>"$readiness_diagnostic"; then
      activate_evidence_app
      sleep 1.0
      if wait_for_window_capture_metadata "$window_name" > /dev/null 2>>"$readiness_diagnostic" \
        && position_window_for_capture "$window_name" "$readiness_diagnostic" 2>>"$readiness_diagnostic" \
        && { [[ -z "$preparation_control_identifier" ]] \
          || press_named_window_control "$preparation_control_identifier" 2>>"$readiness_diagnostic"; } \
        && wait_for_project_board_destination "$label" "$marker_spec" 2>>"$readiness_diagnostic" \
        && position_window_for_capture "$window_name" "$readiness_diagnostic" 2>>"$readiness_diagnostic"; then
        rm -f "$readiness_diagnostic"
        return 0
      fi
    fi

    if [[ "$window_attempt" -lt "$EVIDENCE_ROUTE_ATTEMPTS" ]]; then
      echo "INFO: retrying named evidence window after readiness failure" >&2
      emit_evidence_app_diagnostic
      rm -f "$readiness_diagnostic"
      continue
    fi

    /bin/cat "$readiness_diagnostic" >&2
    emit_evidence_app_diagnostic
    rm -f "$readiness_diagnostic"
    return 1
  done
}

capture_settings_overview() {
  local appearance="$1"
  local output_path="$2"

  APPEARANCE_OVERRIDE="$appearance"
  PROJECT_BOARD_SELECTION_OVERRIDE=""
  SETTINGS_WINDOW_OVERRIDE=1
  SETTINGS_TAB_OVERRIDE="Overview"
  VOICE_COMMAND_WINDOW_OVERRIDE=""
  prepare_named_evidence_window "" "Settings overview" "settings-status-overview=>|settings-overview-detail-rail=>"

  capture_visible_window "$appearance Settings overview" "$output_path" "" "settings-status-overview"
}

capture_settings_sync() {
  local appearance="$1"
  local output_path="$2"

  APPEARANCE_OVERRIDE="$appearance"
  PROJECT_BOARD_SELECTION_OVERRIDE=""
  SETTINGS_WINDOW_OVERRIDE=1
  SETTINGS_TAB_OVERRIDE="Sync"
  VOICE_COMMAND_WINDOW_OVERRIDE=""
  prepare_named_evidence_window "" "Settings integrations" "sync-paid-value-row=>"

  capture_visible_window "$appearance Settings integrations" "$output_path" "" "sync-paid-value-row"
}

capture_settings_appearance() {
  local appearance="$1"
  local output_path="$2"

  APPEARANCE_OVERRIDE="$appearance"
  PROJECT_BOARD_SELECTION_OVERRIDE=""
  SETTINGS_WINDOW_OVERRIDE=1
  SETTINGS_TAB_OVERRIDE="Appearance"
  VOICE_COMMAND_WINDOW_OVERRIDE=""
  prepare_named_evidence_window "" "Settings appearance" "settings-theme-picker=>"

  capture_visible_window "$appearance Settings appearance" "$output_path" "" "settings-theme-picker"
}

capture_settings_ai() {
  local appearance="$1"
  local output_path="$2"

  APPEARANCE_OVERRIDE="$appearance"
  PROJECT_BOARD_SELECTION_OVERRIDE=""
  SETTINGS_WINDOW_OVERRIDE=1
  SETTINGS_TAB_OVERRIDE="AI"
  VOICE_COMMAND_WINDOW_OVERRIDE=""
  prepare_named_evidence_window "" "Settings AI" "settings-ai-readiness-rail=>"

  capture_visible_window "$appearance Settings AI" "$output_path" "" "settings-ai-readiness-rail"
}

capture_settings_privacy() {
  local appearance="$1"
  local output_path="$2"

  APPEARANCE_OVERRIDE="$appearance"
  PROJECT_BOARD_SELECTION_OVERRIDE=""
  SETTINGS_WINDOW_OVERRIDE=1
  SETTINGS_TAB_OVERRIDE="Privacy"
  VOICE_COMMAND_WINDOW_OVERRIDE=""
  prepare_named_evidence_window "" "Settings Privacy" "settings-privacy-root=>"

  capture_visible_window "$appearance Settings Privacy" "$output_path" "" "settings-privacy-root"
}

capture_mcp_settings_appearance() {
  local appearance="$1"
  local output_path="$2"

  APPEARANCE_OVERRIDE="$appearance"
  PROJECT_BOARD_SELECTION_OVERRIDE=""
  SETTINGS_WINDOW_OVERRIDE=1
  SETTINGS_TAB_OVERRIDE="MCP"
  VOICE_COMMAND_WINDOW_OVERRIDE=""
  prepare_named_evidence_window "" "MCP settings" "mcp-paid-execution-boundary-row=>"
  scroll_ax_target_into_view "mcp-paid-execution-boundary-row" "MCP settings"
  sleep 1.0

  capture_visible_window "$appearance MCP settings" "$output_path" "" "mcp-paid-execution-boundary-row"
}

capture_appearance() {
  local appearance="$1"
  local output_path="$2"

  APPEARANCE_OVERRIDE="$appearance"
  SETTINGS_WINDOW_OVERRIDE=""
  SETTINGS_TAB_OVERRIDE=""
  VOICE_COMMAND_WINDOW_OVERRIDE=""
  stop_evidence_app
  write_appearance_preference "$appearance"
  open_evidence_app
  wait_for_process
  activate_evidence_app
  sleep 1.5

  capture_visible_window "$appearance" "$output_path" "" "project-board-detail"
}

capture_project_board_destination() {
  local appearance="$1"
  local selected_destination="$2"
  local output_path="$3"
  local label="$4"
  local target_markers="${5:-}"
  local selected_task_id="${6:-}"
  local scroll_target_identifier="${7:-}"
  local target_audit_identifier="${8:-}"
  local post_scroll_target_markers="${9:-}"
  local schedule_mode_override="${10:-}"
  local scroll_container_identifier="${11:-}"
  local route_attempt
  local marker_diagnostic
  local launch_destination="$selected_destination"
  local destination_status

  APPEARANCE_OVERRIDE="$appearance"
  PROJECT_BOARD_SELECTION_OVERRIDE="$launch_destination"
  PROJECT_BOARD_SELECTED_TASK_OVERRIDE="$selected_task_id"
  if [[ "$launch_destination" == "inbox" && -z "$selected_task_id" ]]; then
    INBOX_EVIDENCE_CLEAR_SELECTION=1
  else
    INBOX_EVIDENCE_CLEAR_SELECTION=""
  fi
  SCHEDULE_MODE_OVERRIDE="$schedule_mode_override"
  SETTINGS_WINDOW_OVERRIDE=""
  SETTINGS_TAB_OVERRIDE=""
  VOICE_COMMAND_WINDOW_OVERRIDE=""
  VOICE_SURFACE_OVERRIDE=""
  for ((route_attempt = 1; route_attempt <= EVIDENCE_ROUTE_ATTEMPTS; route_attempt++)); do
    marker_diagnostic="$EVIDENCE_TMPDIR/project-board-destination.$$.attempt-$route_attempt.err"
    : >"$marker_diagnostic"
    stop_evidence_app
    write_appearance_preference "$appearance"
    write_app_preference suisui.projectBoard.selectedDestination "$launch_destination"
    open_evidence_app
    wait_for_process
    activate_evidence_app
    sleep 1.5
    # Dense workflow footers may not enter the AX visible subtree until the
    # evidence window is widened, so target validation uses the same bounds as
    # the screenshot instead of a smaller launch-default window.
    # Treat CG metadata publication and AX positioning as one readiness unit.
    # SwiftUI can remove the first window between process readiness and either
    # probe, so both failures must consume the same bounded fresh-process retry.
    if ! wait_for_window_capture_metadata > /dev/null 2>>"$marker_diagnostic" ||
      ! position_window_for_capture "" "$marker_diagnostic" 2>>"$marker_diagnostic"; then
      if [[ "$route_attempt" -lt "$EVIDENCE_ROUTE_ATTEMPTS" ]]; then
        echo "INFO: retrying exact production destination after owned window readiness failure" >&2
        emit_evidence_app_diagnostic
        rm -f "$marker_diagnostic"
        continue
      fi
      cat "$marker_diagnostic" >&2
      emit_evidence_app_diagnostic
      rm -f "$marker_diagnostic"
      PROJECT_BOARD_SELECTION_OVERRIDE="$selected_destination"
      return 1
    fi
    sleep 0.25
    destination_status=0

    # Typed route overrides are the production deep-link contract. Launching
    # the exact route avoids depending on whether a SwiftUI List has published
    # an off-screen project row into the hosted runner's AX tree.
    if [[ "$destination_status" -eq 0 ]]; then
      wait_for_project_board_destination "$label" "$target_markers" 2>>"$marker_diagnostic" || destination_status=$?
    fi
    if [[ "$destination_status" -eq 0 ]]; then
      rm -f "$marker_diagnostic"
      PROJECT_BOARD_SELECTION_OVERRIDE="$selected_destination"
      break
    fi
    if [[ "$route_attempt" -lt "$EVIDENCE_ROUTE_ATTEMPTS" ]]; then
      echo "INFO: retrying exact production destination after required marker timeout" >&2
      emit_evidence_app_diagnostic
      rm -f "$marker_diagnostic"
      continue
    fi
    cat "$marker_diagnostic" >&2
    rm -f "$marker_diagnostic"
    PROJECT_BOARD_SELECTION_OVERRIDE="$selected_destination"
    return 1
  done

  # Route markers can exist outside the current ScrollView viewport. Scroll the
  # evidence-specific landmark into view so captures of the same route prove a
  # distinct visual state instead of producing duplicate raster baselines.
  if [[ -n "$scroll_container_identifier" ]]; then
    # Some SwiftUI descendants do not enter the visible AX subtree until their
    # containing ScrollView moves. Materialize that region first, then use the
    # exact target helper to settle on the evidence landmark.
    scroll_ax_container_down "$scroll_container_identifier"
    sleep 0.5
  fi
  if [[ -n "$scroll_target_identifier" ]]; then
    scroll_ax_target_into_view "$scroll_target_identifier" "$label"
  fi
  sleep 0.5
  if [[ -n "$post_scroll_target_markers" ]]; then
    wait_for_project_board_destination "$label after scroll" "$post_scroll_target_markers"
  fi
  if [[ "$scroll_target_identifier" == "inbox-voice-intake-detail" ]]; then
    # Voice intake detail can publish its AX subtree before the split rail
    # finishes compositing on dark/system evidence runs.
    activate_evidence_app
    sleep 1.5
  fi

  capture_visible_window "$appearance $label" "$output_path" "" "$target_audit_identifier"
}

capture_voice_command_appearance() {
  local appearance="$1"
  local output_path="$2"

  APPEARANCE_OVERRIDE="$appearance"
  PROJECT_BOARD_SELECTION_OVERRIDE=""
  INBOX_EVIDENCE_CLEAR_SELECTION=""
  SETTINGS_WINDOW_OVERRIDE=""
  SETTINGS_TAB_OVERRIDE=""
  VOICE_COMMAND_WINDOW_OVERRIDE=1
  VOICE_SURFACE_OVERRIDE=""
  prepare_named_evidence_window "" "Voice Command" "$VOICE_COMMAND_TARGET_MARKERS" "voice-command-quick-command-tab"

  capture_visible_window "$appearance Voice Command" "$output_path" "" "voice-command-root"
}

capture_voice_command_listening_appearance() {
  local appearance="$1"
  local output_path="$2"

  APPEARANCE_OVERRIDE="$appearance"
  PROJECT_BOARD_SELECTION_OVERRIDE=""
  INBOX_EVIDENCE_CLEAR_SELECTION=""
  SETTINGS_WINDOW_OVERRIDE=""
  SETTINGS_TAB_OVERRIDE=""
  VOICE_COMMAND_WINDOW_OVERRIDE=1
  VOICE_SURFACE_OVERRIDE="listening"
  prepare_named_evidence_window "" "Voice Command" "$VOICE_COMMAND_LISTENING_TARGET_MARKERS" "voice-command-quick-command-tab"

  capture_visible_window "$appearance Voice Command Listening" "$output_path" "" "voice-command-listening-hero"
}

capture_voice_conversation_appearance() {
  local appearance="$1"
  local output_path="$2"

  APPEARANCE_OVERRIDE="$appearance"
  PROJECT_BOARD_SELECTION_OVERRIDE=""
  INBOX_EVIDENCE_CLEAR_SELECTION=""
  SETTINGS_WINDOW_OVERRIDE=""
  SETTINGS_TAB_OVERRIDE=""
  VOICE_COMMAND_WINDOW_OVERRIDE=1
  VOICE_SURFACE_OVERRIDE="conversation"
  prepare_named_evidence_window "" "Voice Conversation" "$VOICE_CONVERSATION_TARGET_MARKERS"

  capture_visible_window "$appearance Voice Conversation" "$output_path" "" "voice-conversation-workspace"
}

write_evidence_file() {
  local generated_at="$1"
  local light_path="$2"
  local dark_path="$3"
  local system_path="$4"
  local overview_light_path="$5"
  local overview_dark_path="$6"
  local appearance_light_path="$7"
  local appearance_dark_path="$8"
  local mcp_light_path="$9"
  local mcp_dark_path="${10}"
  local inbox_light_path="${11}"
  local inbox_dark_path="${12}"
  local projects_light_path="${13}"
  local projects_dark_path="${14}"
  local schedule_light_path="${15}"
  local schedule_dark_path="${16}"
  local done_light_path="${17}"
  local done_dark_path="${18}"
  local settings_integrations_light_path="${19}"
  local settings_integrations_dark_path="${20}"

  {
    printf '%s\n' '# UI Screenshot Evidence'
    printf '\n'
    printf '%s\n' 'Generated with `script/capture_ui_evidence.sh`.'
    printf '\n'
    printf -- '- Generated at: `%s`\n' "$generated_at"
    printf -- '- Source commit: `%s`\n' "$(ui_evidence_source_commit)"
    printf -- '- App bundle: `dist/%s.app`\n' "$APP_NAME"
    printf -- '- Visual baseline manifest: `%s`\n' "$(relative_path "$VISUAL_BASELINE_MANIFEST")"
    printf -- '- Viewport contract: `SUISUI_VISUAL_BASELINE_VIEWPORT=%s`, `SUISUI_SETTINGS_VISUAL_BASELINE_VIEWPORT=%s`, `SUISUI_VOICE_COMMAND_VISUAL_BASELINE_VIEWPORT=%s`\n' "$VISUAL_BASELINE_VIEWPORT" "$SETTINGS_VISUAL_BASELINE_VIEWPORT" "$VOICE_COMMAND_VISUAL_BASELINE_VIEWPORT"
    printf -- '- Runtime context: locale `%s`, timezone `%s`, reference instant `%s`\n' "$EVIDENCE_RECEIPT_LOCALE" "$EVIDENCE_TIME_ZONE" "$EVIDENCE_REFERENCE_INSTANT"
    printf '%s\n' '- Launch mode: normal `ProjectBoardView` route with explicit selected destination; recovery flags are excluded from release evidence.'
    printf '%s\n' '- Data isolation: isolated temporary HOME via `HOME` and `CFFIXED_USER_HOME`'
    printf '%s\n' '- Seed data: local `Launch Readiness` project with planned, in-progress, blocked, Inbox voice, Schedule, Done analytics, milestone, completed project, deterministic MCP registration rows, and production-model Assistant Queue review fixtures'
    printf '%s\n' '- Scope: Project board sidebar, task cards, Inbox voice detail, Today cockpit, Projects overview, Schedule cockpit, Schedule workload dashboard, Done analytics, Assistant Queue approval states, Settings integrations, Settings Appearance Theme picker, and Settings MCP server list across Light/Dark/System'
    printf '%s\n' '- Capture contract: Light/Dark/System visual baseline manifest fixes product screen targets, viewport, semantic tolerances, and AX frame audit requirements.'
    printf '%s\n' '- Manual review: passed for Project Board sidebar/cards/inspector, Inbox voice detail, Today cockpit, Projects overview, Schedule cockpit, Schedule workload dashboard, Done analytics, Settings integrations, Settings Appearance Theme picker, Settings MCP server rows, and Light/Dark/System contrast'
    printf '\n'
    printf '%s\n' '## Screenshots'
    printf '\n'
    printf -- '- Light: `%s`\n' "$(relative_path "$light_path")"
    printf -- '- Dark: `%s`\n' "$(relative_path "$dark_path")"
    printf -- '- System: `%s`\n' "$(relative_path "$system_path")"
    printf -- '- Settings Overview Light: `%s`\n' "$(relative_path "$overview_light_path")"
    printf -- '- Settings Overview Dark: `%s`\n' "$(relative_path "$overview_dark_path")"
    printf -- '- Settings Appearance Light: `%s`\n' "$(relative_path "$appearance_light_path")"
    printf -- '- Settings Appearance Dark: `%s`\n' "$(relative_path "$appearance_dark_path")"
    printf -- '- MCP Settings Light: `%s`\n' "$(relative_path "$mcp_light_path")"
    printf -- '- MCP Settings Dark: `%s`\n' "$(relative_path "$mcp_dark_path")"
    printf -- '- Inbox Voice Light: `%s`\n' "$(relative_path "$inbox_light_path")"
    printf -- '- Inbox Voice Dark: `%s`\n' "$(relative_path "$inbox_dark_path")"
    printf -- '- Projects Overview Light: `%s`\n' "$(relative_path "$projects_light_path")"
    printf -- '- Projects Overview Dark: `%s`\n' "$(relative_path "$projects_dark_path")"
    printf -- '- Schedule Light: `%s`\n' "$(relative_path "$schedule_light_path")"
    printf -- '- Schedule Dark: `%s`\n' "$(relative_path "$schedule_dark_path")"
    printf -- '- Schedule Workload Light: `%s`\n' "$(relative_path "$SCHEDULE_WORKLOAD_LIGHT_SCREENSHOT")"
    printf -- '- Schedule Workload Dark: `%s`\n' "$(relative_path "$SCHEDULE_WORKLOAD_DARK_SCREENSHOT")"
    printf -- '- Done Light: `%s`\n' "$(relative_path "$done_light_path")"
    printf -- '- Done Dark: `%s`\n' "$(relative_path "$done_dark_path")"
    printf -- '- Settings Integrations Light: `%s`\n' "$(relative_path "$settings_integrations_light_path")"
    printf -- '- Settings Integrations Dark: `%s`\n' "$(relative_path "$settings_integrations_dark_path")"
    printf -- '- Assistant Queue Waiting Review Light: `%s`\n' "$(relative_path "$ASSISTANT_QUEUE_WAITING_LIGHT_SCREENSHOT")"
    printf -- '- Assistant Queue Waiting Review Dark: `%s`\n' "$(relative_path "$ASSISTANT_QUEUE_WAITING_DARK_SCREENSHOT")"
    printf -- '- Assistant Queue Approved Light: `%s`\n' "$(relative_path "$ASSISTANT_QUEUE_APPROVED_LIGHT_SCREENSHOT")"
    printf -- '- Assistant Queue Approved Dark: `%s`\n' "$(relative_path "$ASSISTANT_QUEUE_APPROVED_DARK_SCREENSHOT")"
    printf -- '- Assistant Queue Failed Light: `%s`\n' "$(relative_path "$ASSISTANT_QUEUE_FAILED_LIGHT_SCREENSHOT")"
    printf -- '- Assistant Queue Failed Dark: `%s`\n' "$(relative_path "$ASSISTANT_QUEUE_FAILED_DARK_SCREENSHOT")"
    printf '\n'
    printf '%s\n' '## Visual Baseline Manifest Screenshots'
    printf '\n'
    printf -- '- Project Board Light: `%s`\n' "$(relative_path "$LIGHT_SCREENSHOT")"
    printf -- '- Project Board Dark: `%s`\n' "$(relative_path "$DARK_SCREENSHOT")"
    printf -- '- Project Board System: `%s`\n' "$(relative_path "$SYSTEM_SCREENSHOT")"
    printf -- '- Inbox Light: `%s`\n' "$(relative_path "$INBOX_LIGHT_SCREENSHOT")"
    printf -- '- Inbox Dark: `%s`\n' "$(relative_path "$INBOX_DARK_SCREENSHOT")"
    printf -- '- Inbox System: `%s`\n' "$(relative_path "$INBOX_SYSTEM_SCREENSHOT")"
    printf -- '- Today Light: `%s`\n' "$(relative_path "$TODAY_LIGHT_SCREENSHOT")"
    printf -- '- Today Dark: `%s`\n' "$(relative_path "$TODAY_DARK_SCREENSHOT")"
    printf -- '- Today System: `%s`\n' "$(relative_path "$TODAY_SYSTEM_SCREENSHOT")"
    printf -- '- Settings Overview Light: `%s`\n' "$(relative_path "$SETTINGS_OVERVIEW_LIGHT_SCREENSHOT")"
    printf -- '- Settings Overview Dark: `%s`\n' "$(relative_path "$SETTINGS_OVERVIEW_DARK_SCREENSHOT")"
    printf -- '- Settings Overview System: `%s`\n' "$(relative_path "$SETTINGS_OVERVIEW_SYSTEM_SCREENSHOT")"
    printf -- '- Settings Appearance Light: `%s`\n' "$(relative_path "$SETTINGS_APPEARANCE_LIGHT_SCREENSHOT")"
    printf -- '- Settings Appearance Dark: `%s`\n' "$(relative_path "$SETTINGS_APPEARANCE_DARK_SCREENSHOT")"
    printf -- '- Settings Appearance System: `%s`\n' "$(relative_path "$SETTINGS_APPEARANCE_SYSTEM_SCREENSHOT")"
    printf -- '- Settings AI Light: `%s`\n' "$(relative_path "$SETTINGS_AI_LIGHT_SCREENSHOT")"
    printf -- '- Settings AI Dark: `%s`\n' "$(relative_path "$SETTINGS_AI_DARK_SCREENSHOT")"
    printf -- '- MCP Settings Light: `%s`\n' "$(relative_path "$MCP_SETTINGS_LIGHT_SCREENSHOT")"
    printf -- '- MCP Settings Dark: `%s`\n' "$(relative_path "$MCP_SETTINGS_DARK_SCREENSHOT")"
    printf -- '- MCP Settings System: `%s`\n' "$(relative_path "$MCP_SETTINGS_SYSTEM_SCREENSHOT")"
    printf -- '- Voice Command Light: `%s`\n' "$(relative_path "$VOICE_COMMAND_LIGHT_SCREENSHOT")"
    printf -- '- Voice Command Dark: `%s`\n' "$(relative_path "$VOICE_COMMAND_DARK_SCREENSHOT")"
    printf -- '- Voice Command System: `%s`\n' "$(relative_path "$VOICE_COMMAND_SYSTEM_SCREENSHOT")"
    printf -- '- Schedule Workload Light: `%s`\n' "$(relative_path "$SCHEDULE_WORKLOAD_LIGHT_SCREENSHOT")"
    printf -- '- Schedule Workload Dark: `%s`\n' "$(relative_path "$SCHEDULE_WORKLOAD_DARK_SCREENSHOT")"
    printf -- '- Assistant Queue Waiting Review Light: `%s`\n' "$(relative_path "$ASSISTANT_QUEUE_WAITING_LIGHT_SCREENSHOT")"
    printf -- '- Assistant Queue Waiting Review Dark: `%s`\n' "$(relative_path "$ASSISTANT_QUEUE_WAITING_DARK_SCREENSHOT")"
    printf -- '- Assistant Queue Approved Light: `%s`\n' "$(relative_path "$ASSISTANT_QUEUE_APPROVED_LIGHT_SCREENSHOT")"
    printf -- '- Assistant Queue Approved Dark: `%s`\n' "$(relative_path "$ASSISTANT_QUEUE_APPROVED_DARK_SCREENSHOT")"
    printf -- '- Assistant Queue Failed Light: `%s`\n' "$(relative_path "$ASSISTANT_QUEUE_FAILED_LIGHT_SCREENSHOT")"
    printf -- '- Assistant Queue Failed Dark: `%s`\n' "$(relative_path "$ASSISTANT_QUEUE_FAILED_DARK_SCREENSHOT")"
    printf '\n'
    printf '%s\n' '## Notes'
    printf '\n'
    printf '%s\n' '- The script seeds only deterministic local Project/Task/MCP registration data into the isolated SQLite database.'
    printf '%s\n' '- Secret input screens are excluded from the default visual baseline manifest.'
    printf '%s\n' '- Only masked SecureField state may be captured if a future release needs a secret-entry screenshot.'
    printf '%s\n' '- API keys and provider tokens are not read, written, logged, rendered, or captured unmasked.'
    printf '%s\n' '- Run `script/capture_ui_evidence.sh --doctor` first to verify required commands and Screen Recording visible-pixel capture without writing release evidence.'
    printf '%s\n' '- The capture host must grant Screen Recording permission through System Settings > Privacy & Security > Screen Recording / Screen & System Audio Recording to the terminal/Codex app; otherwise the script fails before treating screenshots as evidence.'
    printf '%s\n' '- If capture still fails, rerun with `SUISUI_UI_EVIDENCE_KEEP_HOME=1` to keep the isolated HOME for database and preference inspection.'
    printf '%s\n' '- VoiceOver focus order still requires a manual assistive-technology pass.'
  } >"$EVIDENCE_FILE"
}

write_p0_workflow_evidence_file() {
  local generated_at="$1"
  local inbox_light_path="$2"
  local inbox_dark_path="$3"
  local inbox_system_path="$4"
  local today_light_path="$5"
  local today_dark_path="$6"
  local today_system_path="$7"
  local inbox_voice_light_path="$8"
  local inbox_voice_dark_path="$9"
  local source_commit
  source_commit="$(ui_evidence_source_commit)"

  {
    printf '%s\n' '# P0 Workflow Screenshot Evidence'
    printf '\n'
    printf '%s\n' 'Generated with `script/capture_ui_evidence.sh --p0-workflows`.'
    printf '%s\n' 'This targeted evidence covers the Personal MVP Inbox and Today closeout paths without rewriting the full release screenshot set.'
    printf '\n'
    printf -- '- Generated at: `%s`\n' "$generated_at"
    printf -- '- Source commit: `%s`\n' "$source_commit"
    printf -- '- Screen Recording preflight: `script/capture_ui_evidence.sh --doctor`\n'
    printf '\n'
    printf '%s\n' '## Inbox'
    printf '\n'
    printf -- '- Light: `%s`\n' "$(relative_path "$inbox_light_path")"
    printf -- '- Dark: `%s`\n' "$(relative_path "$inbox_dark_path")"
    printf -- '- System: `%s`\n' "$(relative_path "$inbox_system_path")"
    printf '\n'
    printf '%s\n' '## Today'
    printf '\n'
    printf -- '- Light: `%s`\n' "$(relative_path "$today_light_path")"
    printf -- '- Dark: `%s`\n' "$(relative_path "$today_dark_path")"
    printf -- '- System: `%s`\n' "$(relative_path "$today_system_path")"
    printf '\n'
    printf '%s\n' '## Inbox Voice Detail'
    printf '\n'
    printf -- '- Light: `%s`\n' "$(relative_path "$inbox_voice_light_path")"
    printf -- '- Dark: `%s`\n' "$(relative_path "$inbox_voice_dark_path")"
    printf '\n'
    printf '%s\n' '## Guardrails'
    printf '\n'
    printf '%s\n' '- API keys, provider tokens, OAuth tokens, calendar contents, and customer file contents are not captured.'
    printf '%s\n' '- The app runs with `SUISUI_DISABLE_KEYCHAIN_SECRET_STORE=1`, an isolated HOME, and a seeded SQLite database.'
    printf '%s\n' '- The P0 workflow capture uses the normal `ProjectBoardView` route with explicit Today and Inbox selected destinations.'
  } >"$ROOT_DIR/docs/release/evidence/p0-workflow-screenshots.md"
}

write_schedule_cockpit_evidence_file() {
  local generated_at="$1"
  local schedule_light_path="$2"
  local schedule_dark_path="$3"
  local source_commit
  source_commit="$(ui_evidence_source_commit)"

  {
    printf '%s\n' '# Schedule Cockpit Screenshot Evidence'
    printf '\n'
    printf '%s\n' 'Generated with `script/capture_ui_evidence.sh --schedule-cockpit`.'
    printf '%s\n' 'This targeted evidence covers issue #9 Schedule cockpit light/dark closeout without rewriting the full release screenshot set.'
    printf '\n'
    printf -- '- Generated at: `%s`\n' "$generated_at"
    printf -- '- Source commit: `%s`\n' "$source_commit"
    printf -- '- Screen Recording preflight: `script/capture_ui_evidence.sh --doctor`\n'
    printf -- '- Target markers: `schedule-workflow`, `schedule-mode-overview`, `schedule-mini-calendar`\n'
    printf '\n'
    printf '%s\n' '## Schedule Cockpit'
    printf '\n'
    printf -- '- Light: `%s`\n' "$(relative_path "$schedule_light_path")"
    printf -- '- Dark: `%s`\n' "$(relative_path "$schedule_dark_path")"
    printf '\n'
    printf '%s\n' '## Guardrails'
    printf '\n'
    printf '%s\n' '- The cockpit is seeded from local ProjectBoard tasks in an isolated SQLite database.'
    printf '%s\n' '- Opening the cockpit does not enqueue or execute external Calendar or Reminder writes.'
    printf '%s\n' '- API keys, provider tokens, OAuth tokens, calendar contents, and customer file contents are not captured.'
    printf '%s\n' '- The app runs with `SUISUI_DISABLE_KEYCHAIN_SECRET_STORE=1`, an explicit isolated SQLite database, and env-driven Schedule selection.'
  } >"$SCHEDULE_COCKPIT_EVIDENCE_FILE"
}

write_schedule_workload_evidence_file() {
  local generated_at="$1"
  local schedule_workload_light_path="$2"
  local schedule_workload_dark_path="$3"
  local source_commit
  source_commit="$(ui_evidence_source_commit)"

  {
    printf '%s\n' '# Schedule Workload Screenshot Evidence'
    printf '\n'
    printf '%s\n' 'Generated with `script/capture_ui_evidence.sh --schedule-workload`.'
    printf '%s\n' 'This targeted evidence covers the issue #1 calendar workload dashboard without rewriting the full release screenshot set.'
    printf '\n'
    printf -- '- Generated at: `%s`\n' "$generated_at"
    printf -- '- Source commit: `%s`\n' "$source_commit"
    printf -- '- Screen Recording preflight: `script/capture_ui_evidence.sh --doctor`\n'
    printf -- '- Target markers: `schedule-workflow`, `schedule-workload-dashboard`, `schedule-workload-attention-banner`, `schedule-workload-day-detail`\n'
    printf '\n'
    printf '%s\n' '## Schedule Workload'
    printf '\n'
    printf -- '- Light: `%s`\n' "$(relative_path "$schedule_workload_light_path")"
    printf -- '- Dark: `%s`\n' "$(relative_path "$schedule_workload_dark_path")"
    printf '\n'
    printf '%s\n' '## Guardrails'
    printf '\n'
    printf '%s\n' '- The dashboard is seeded from local ProjectBoard tasks in an isolated SQLite database.'
    printf '%s\n' '- Opening the workload dashboard does not enqueue or execute external Calendar writes.'
    printf '%s\n' '- API keys, provider tokens, OAuth tokens, calendar contents, and customer file contents are not captured.'
    printf '%s\n' '- The app runs with `SUISUI_DISABLE_KEYCHAIN_SECRET_STORE=1`, an isolated HOME, and a seeded SQLite database.'
  } >"$ROOT_DIR/docs/release/evidence/schedule-workload-screenshots.md"
}

write_done_analytics_evidence_file() {
  local generated_at="$1"
  local done_light_path="$2"
  local done_dark_path="$3"
  local source_commit
  source_commit="$(ui_evidence_source_commit)"

  {
    printf '%s\n' '# Done Analytics Screenshot Evidence'
    printf '\n'
    printf '%s\n' 'Generated with `script/capture_ui_evidence.sh --done-analytics`.'
    printf '%s\n' 'This targeted evidence covers issue #10 Done analytics light/dark closeout without rewriting the full release screenshot set.'
    printf '\n'
    printf -- '- Generated at: `%s`\n' "$generated_at"
    printf -- '- Source commit: `%s`\n' "$source_commit"
    printf -- '- Screen Recording preflight: `script/capture_ui_evidence.sh --doctor`\n'
    printf -- '- Target markers: `done-workflow`, `done-completion-heatmap`, `done-productivity-insight`, `done-local-rule-insight`\n'
    printf '\n'
    printf '%s\n' '## Done Analytics'
    printf '\n'
    printf -- '- Light: `%s`\n' "$(relative_path "$done_light_path")"
    printf -- '- Dark: `%s`\n' "$(relative_path "$done_dark_path")"
    printf '\n'
    printf '%s\n' '## Guardrails'
    printf '\n'
    printf '%s\n' '- The Done dashboard is seeded from local ProjectBoard completion history in an isolated SQLite database.'
    printf '%s\n' '- Opening Done analytics does not enqueue or execute external writes.'
    printf '%s\n' '- API keys, provider tokens, OAuth tokens, calendar contents, and customer file contents are not captured.'
    printf '%s\n' '- The app runs with `SUISUI_DISABLE_KEYCHAIN_SECRET_STORE=1`, an isolated HOME, and a seeded SQLite database.'
  } >"$DONE_ANALYTICS_EVIDENCE_FILE"
}

write_visual_baseline_capture_manifest() {
  local generated_at="$1"
  local output_file="$SCREENSHOT_DIR/visual-baseline-capture-manifest.json"

  {
    printf '%s\n' '{'
    printf '  "generatedAt": "%s",\n' "$generated_at"
    printf '  "sourceCommit": "%s",\n' "$(ui_evidence_product_source_commit)"
    printf '  "locale": "%s",\n' "$EVIDENCE_RECEIPT_LOCALE"
    printf '  "timeZoneIdentifier": "%s",\n' "$EVIDENCE_TIME_ZONE"
    printf '  "referenceInstant": "%s",\n' "$EVIDENCE_REFERENCE_INSTANT"
    printf '  "sourceManifest": "%s",\n' "$(relative_path "$VISUAL_BASELINE_MANIFEST")"
    printf '  "screenshotDirectory": "%s",\n' "$(relative_path "$SCREENSHOT_DIR")"
    printf '  "mainViewport": "%s",\n' "$VISUAL_BASELINE_VIEWPORT"
    printf '  "settingsViewport": "%s",\n' "$SETTINGS_VISUAL_BASELINE_VIEWPORT"
    printf '  "voiceCommandViewport": "%s",\n' "$VOICE_COMMAND_VISUAL_BASELINE_VIEWPORT"
    printf '  "comparison": "semantic"\n'
    printf '%s\n' '}'
  } >"$output_file"
}

run_doctor() {
  echo "UI evidence doctor"
  echo "bundle: $APP_BUNDLE"
  echo "home: $EVIDENCE_HOME"
  echo "screenshots: $SCREENSHOT_DIR"
  echo "evidence: $EVIDENCE_FILE"
  echo "visual baseline manifest: $VISUAL_BASELINE_MANIFEST"
  echo "visual viewport: $VISUAL_BASELINE_VIEWPORT"
  echo "settings visual viewport: $SETTINGS_VISUAL_BASELINE_VIEWPORT"
  echo "voice command visual viewport: $VOICE_COMMAND_VISUAL_BASELINE_VIEWPORT"
  echo "runtime locale: $EVIDENCE_RECEIPT_LOCALE"
  echo "runtime timezone: $EVIDENCE_TIME_ZONE"
  echo "reference instant: $EVIDENCE_REFERENCE_INSTANT"
  echo "mode: screen capture preflight; does not write release evidence"

  local blocker_count=0
  local command_name
  for command_name in screencapture swift swiftc sips osascript; do
    if command -v "$command_name" >/dev/null 2>&1; then
      echo "OK: found $command_name"
    else
      echo "BLOCKER: missing required command: $command_name"
      blocker_count=$((blocker_count + 1))
    fi
  done

  if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "INFO: app bundle is not present yet; normal capture mode will run script/build_and_run.sh --build-only."
  fi

  if visual_product_source_is_clean; then
    echo "OK: visual evidence product source is fully committed"
  else
    echo "BLOCKER: visual evidence source is dirty under Sources, Package.swift, or script/capture_ui_evidence.sh"
    echo "NEXT: commit evidence-source changes before running a mutating capture."
    blocker_count=$((blocker_count + 1))
  fi

  if command -v screencapture >/dev/null 2>&1 && command -v swift >/dev/null 2>&1; then
    local probe_base
    local probe
    probe_base="$(mktemp "${TMPDIR:-/tmp}/suisui-ui-evidence-doctor.XXXXXX")"
    probe="$probe_base.png"
    rm -f "$probe_base"
    if screencapture -x "$probe" >/dev/null 2>&1 && [[ -s "$probe" ]] && assert_screenshot_has_visible_content "$probe"; then
      echo "OK: screen capture preflight produced visible pixels"
    else
      echo "BLOCKER: screen capture preflight did not produce visible pixels"
      echo "NEXT: grant Screen Recording permission to the terminal/Codex app, quit and reopen it, then rerun script/capture_ui_evidence.sh --doctor."
      blocker_count=$((blocker_count + 1))
    fi
    rm -f "$probe"
  fi

  if [[ "$blocker_count" -gt 0 ]]; then
    exit 1
  fi
}

if [[ "$DOCTOR" == "1" ]]; then
  run_doctor
  exit 0
fi

if [[ "$SEED_ONLY" == "1" ]]; then
  prepare_visual_fixture_seeder
  create_isolated_evidence_home
  DATABASE_PATH="$EVIDENCE_HOME/Library/Application Support/Suisui/Suisui.sqlite"
  seed_capture_database "$DATABASE_PATH"
  echo "capture_seed_ready=1"
  exit 0
fi

write_visual_ax_audit_receipt() {
  local source_commit="$1"
  # Revalidate immediately before the second removal so a path swapped during
  # the long capture cannot redirect the end-of-run receipt write.
  validate_visual_ax_audit_result_path || return $?
  rm -f "$SUISUI_VISUAL_AX_AUDIT_RESULT"
  /usr/bin/swiftc "$ROOT_DIR/script/write_visual_ax_audit_receipt.swift" -o "$AX_RECEIPT_WRITER"
  "$AX_RECEIPT_WRITER" \
    "$VISUAL_BASELINE_MANIFEST" \
    "$AX_CAPTURE_RECEIPT_TSV" \
    "$SUISUI_VISUAL_AX_AUDIT_RESULT" \
    "$source_commit" \
    "normal" \
    "$EVIDENCE_RECEIPT_LOCALE" \
    "$EVIDENCE_TIME_ZONE" \
    "$EVIDENCE_REFERENCE_INSTANT"
  echo "AX audit receipt: $SUISUI_VISUAL_AX_AUDIT_RESULT"
}

require_command screencapture
require_command swift
require_command swiftc
require_command sips
require_command osascript

mkdir -p "$SCREENSHOT_DIR"

if [[ "$DRY_RUN" == "1" ]]; then
  echo "UI evidence dry run"
  echo "bundle: $APP_BUNDLE"
  echo "home: $EVIDENCE_HOME"
  echo "screenshots: $SCREENSHOT_DIR"
  echo "evidence: $EVIDENCE_FILE"
  echo "visual baseline manifest: $VISUAL_BASELINE_MANIFEST"
  echo "visual viewport: $VISUAL_BASELINE_VIEWPORT"
  echo "settings visual viewport: $SETTINGS_VISUAL_BASELINE_VIEWPORT"
  echo "voice command visual viewport: $VOICE_COMMAND_VISUAL_BASELINE_VIEWPORT"
  echo "runtime locale: $EVIDENCE_RECEIPT_LOCALE"
  echo "runtime timezone: $EVIDENCE_TIME_ZONE"
  echo "reference instant: $EVIDENCE_REFERENCE_INSTANT"
  if visual_product_source_is_clean; then
    echo "product source: committed"
  else
    echo "product source: dirty (a mutating capture would be blocked)"
  fi
  exit 0
fi

assert_visual_product_source_is_committed

prepare_visual_fixture_seeder
create_isolated_evidence_home
"$ROOT_DIR/script/build_and_run.sh" --build-only
/usr/bin/swiftc "$ROOT_DIR/script/visual_raster_stability_check.swift" -o "$VISUAL_RASTER_STABILITY_CHECKER"
/usr/bin/swiftc "$ROOT_DIR/script/ui_evidence_appearance_check.swift" -o "$VISUAL_APPEARANCE_CHECKER"

SOURCE_COMMIT="$(ui_evidence_product_source_commit)"

DATABASE_PATH="$EVIDENCE_HOME/Library/Application Support/Suisui/Suisui.sqlite"
seed_capture_database "$DATABASE_PATH"
persist_project_board_selection

LIGHT_SCREENSHOT="$SCREENSHOT_DIR/project-board-light.png"
DARK_SCREENSHOT="$SCREENSHOT_DIR/project-board-dark.png"
SYSTEM_SCREENSHOT="$SCREENSHOT_DIR/project-board-system.png"
SETTINGS_OVERVIEW_LIGHT_SCREENSHOT="$SCREENSHOT_DIR/settings-overview-light.png"
SETTINGS_OVERVIEW_DARK_SCREENSHOT="$SCREENSHOT_DIR/settings-overview-dark.png"
SETTINGS_APPEARANCE_LIGHT_SCREENSHOT="$SCREENSHOT_DIR/settings-appearance-light.png"
SETTINGS_APPEARANCE_DARK_SCREENSHOT="$SCREENSHOT_DIR/settings-appearance-dark.png"
SETTINGS_AI_LIGHT_SCREENSHOT="$SCREENSHOT_DIR/settings-ai-light.png"
SETTINGS_AI_DARK_SCREENSHOT="$SCREENSHOT_DIR/settings-ai-dark.png"
SETTINGS_PRIVACY_LIGHT_SCREENSHOT="$SCREENSHOT_DIR/settings-privacy-light.png"
SETTINGS_PRIVACY_DARK_SCREENSHOT="$SCREENSHOT_DIR/settings-privacy-dark.png"
MCP_SETTINGS_LIGHT_SCREENSHOT="$SCREENSHOT_DIR/settings-mcp-light.png"
MCP_SETTINGS_DARK_SCREENSHOT="$SCREENSHOT_DIR/settings-mcp-dark.png"
INBOX_LIGHT_SCREENSHOT="$SCREENSHOT_DIR/inbox-light.png"
INBOX_DARK_SCREENSHOT="$SCREENSHOT_DIR/inbox-dark.png"
INBOX_SYSTEM_SCREENSHOT="$SCREENSHOT_DIR/inbox-system.png"
TODAY_LIGHT_SCREENSHOT="$SCREENSHOT_DIR/today-light.png"
TODAY_DARK_SCREENSHOT="$SCREENSHOT_DIR/today-dark.png"
TODAY_SYSTEM_SCREENSHOT="$SCREENSHOT_DIR/today-system.png"
SETTINGS_OVERVIEW_SYSTEM_SCREENSHOT="$SCREENSHOT_DIR/settings-overview-system.png"
SETTINGS_APPEARANCE_SYSTEM_SCREENSHOT="$SCREENSHOT_DIR/settings-appearance-system.png"
MCP_SETTINGS_SYSTEM_SCREENSHOT="$SCREENSHOT_DIR/settings-mcp-system.png"
VOICE_COMMAND_LIGHT_SCREENSHOT="$SCREENSHOT_DIR/voice-command-light.png"
VOICE_COMMAND_DARK_SCREENSHOT="$SCREENSHOT_DIR/voice-command-dark.png"
VOICE_COMMAND_SYSTEM_SCREENSHOT="$SCREENSHOT_DIR/voice-command-system.png"
VOICE_COMMAND_LISTENING_LIGHT_SCREENSHOT="$SCREENSHOT_DIR/voice-command-listening-light.png"
VOICE_COMMAND_LISTENING_DARK_SCREENSHOT="$SCREENSHOT_DIR/voice-command-listening-dark.png"
VOICE_CONVERSATION_LIGHT_SCREENSHOT="$SCREENSHOT_DIR/voice-conversation-light.png"
VOICE_CONVERSATION_DARK_SCREENSHOT="$SCREENSHOT_DIR/voice-conversation-dark.png"
INBOX_VOICE_LIGHT_SCREENSHOT="$SCREENSHOT_DIR/inbox-voice-light.png"
INBOX_VOICE_DARK_SCREENSHOT="$SCREENSHOT_DIR/inbox-voice-dark.png"
PROJECTS_OVERVIEW_LIGHT_SCREENSHOT="$SCREENSHOT_DIR/projects-overview-light.png"
PROJECTS_OVERVIEW_DARK_SCREENSHOT="$SCREENSHOT_DIR/projects-overview-dark.png"
SCHEDULE_LIGHT_SCREENSHOT="$SCREENSHOT_DIR/schedule-light.png"
SCHEDULE_DARK_SCREENSHOT="$SCREENSHOT_DIR/schedule-dark.png"
SCHEDULE_WORKLOAD_LIGHT_SCREENSHOT="$SCREENSHOT_DIR/schedule-workload-light.png"
SCHEDULE_WORKLOAD_DARK_SCREENSHOT="$SCREENSHOT_DIR/schedule-workload-dark.png"
DONE_LIGHT_SCREENSHOT="$SCREENSHOT_DIR/done-light.png"
DONE_DARK_SCREENSHOT="$SCREENSHOT_DIR/done-dark.png"
SETTINGS_INTEGRATIONS_LIGHT_SCREENSHOT="$SCREENSHOT_DIR/settings-integrations-light.png"
SETTINGS_INTEGRATIONS_DARK_SCREENSHOT="$SCREENSHOT_DIR/settings-integrations-dark.png"
ASSISTANT_QUEUE_WAITING_LIGHT_SCREENSHOT="$SCREENSHOT_DIR/assistant-queue-waiting-review-light.png"
ASSISTANT_QUEUE_WAITING_DARK_SCREENSHOT="$SCREENSHOT_DIR/assistant-queue-waiting-review-dark.png"
ASSISTANT_QUEUE_APPROVED_LIGHT_SCREENSHOT="$SCREENSHOT_DIR/assistant-queue-approved-light.png"
ASSISTANT_QUEUE_APPROVED_DARK_SCREENSHOT="$SCREENSHOT_DIR/assistant-queue-approved-dark.png"
ASSISTANT_QUEUE_FAILED_LIGHT_SCREENSHOT="$SCREENSHOT_DIR/assistant-queue-failed-light.png"
ASSISTANT_QUEUE_FAILED_DARK_SCREENSHOT="$SCREENSHOT_DIR/assistant-queue-failed-dark.png"

case "$EVIDENCE_LOCALE" in
  english)
    INBOX_ROUTE_LABEL="Inbox"
    TODAY_ROUTE_LABEL="Today"
    PROJECTS_ROUTE_LABEL="Projects"
    SCHEDULE_ROUTE_LABEL="Schedule"
    DONE_ROUTE_LABEL="Done"
    VOICE_COMMAND_LABEL="Voice Command"
    VOICE_COMMAND_LISTENING_LABEL="Listening"
    INBOX_CLASSIFICATION_ACTIONS_LABEL="Inbox classification actions"
    INBOX_VOICE_TITLE="Create tomorrow's presentation materials"
    ;;
  japanese)
    INBOX_ROUTE_LABEL="インボックス"
    TODAY_ROUTE_LABEL="今日"
    PROJECTS_ROUTE_LABEL="プロジェクト"
    SCHEDULE_ROUTE_LABEL="予定"
    DONE_ROUTE_LABEL="完了"
    VOICE_COMMAND_LABEL="音声コマンド"
    VOICE_COMMAND_LISTENING_LABEL="聞き取り中"
    INBOX_CLASSIFICATION_ACTIONS_LABEL="インボックス分類操作"
    INBOX_VOICE_TITLE="明日のプレゼン資料を作成する"
    ;;
esac

# Every release capture proves both the normal-route identifier and localized
# user-visible content. Seeded workflow captures additionally require stable
# fixture text so a blank or wrong database cannot be accepted as evidence.
INBOX_TARGET_MARKERS="inbox-workflow=>$INBOX_ROUTE_LABEL|inbox-action-panel=>$INBOX_ROUTE_LABEL"
TODAY_TARGET_MARKERS="today-workflow=>$TODAY_ROUTE_LABEL|today-briefing-panel=>$TODAY_ROUTE_LABEL|today-assistant-rail=>$TODAY_ROUTE_LABEL"
P0_INBOX_TARGET_MARKERS="inbox-workflow=>$INBOX_ROUTE_LABEL|inbox-action-panel=>$INBOX_ROUTE_LABEL"
P0_TODAY_TARGET_MARKERS="today-workflow=>$TODAY_ROUTE_LABEL|today-briefing-panel=>$TODAY_ROUTE_LABEL|today-assistant-rail=>$TODAY_ROUTE_LABEL"
INBOX_VOICE_ROUTE_MARKERS="inbox-workflow=>$INBOX_ROUTE_LABEL"
# The detail panel now exposes stable accessibility anchors for the voice
# surface. Keep the visual harness independent of localized action copy so a
# Japanese run validates the same selected detail as the English run.
P0_INBOX_VOICE_TARGET_MARKERS="inbox-workflow=>$INBOX_ROUTE_LABEL|inbox-voice-intake-detail=>Voice intake detail for $INBOX_VOICE_TITLE|inbox-action-panel=>$INBOX_CLASSIFICATION_ACTIONS_LABEL"
PROJECTS_TARGET_MARKERS="sidebar-destination-projects=>$PROJECTS_ROUTE_LABEL|projects-portfolio-overview=>$PROJECTS_ROUTE_LABEL"
SCHEDULE_TARGET_MARKERS="schedule-workflow=>$SCHEDULE_ROUTE_LABEL|schedule-mode-overview=>|schedule-mini-calendar=>"
SCHEDULE_COCKPIT_TARGET_MARKERS="schedule-workflow=>$SCHEDULE_ROUTE_LABEL|schedule-mode-overview=>|schedule-mini-calendar=>"
SCHEDULE_WORKLOAD_TARGET_MARKERS="schedule-workflow=>$SCHEDULE_ROUTE_LABEL|schedule-mode-workload=>|schedule-mini-calendar=>"
SCHEDULE_WORKLOAD_DETAIL_MARKERS="schedule-workload-attention-banner=>|schedule-workload-day-detail=>"
DONE_TARGET_MARKERS="done-workflow=>$DONE_ROUTE_LABEL"
DONE_ANALYTICS_TARGET_MARKERS="done-workflow=>$DONE_ROUTE_LABEL|done-completion-heatmap=>|done-productivity-insight=>|done-local-rule-insight=>"
VOICE_COMMAND_TARGET_MARKERS="voice-command-root=>$VOICE_COMMAND_LABEL"
VOICE_COMMAND_LISTENING_TARGET_MARKERS="voice-command-listening-hero=>$VOICE_COMMAND_LISTENING_LABEL"
VOICE_CONVERSATION_TARGET_MARKERS="voice-conversation-workspace=>"
# The compact destination lives inside a closed Menu and is not guaranteed to
# appear in the AX tree. The selected workflow itself is the stable route proof.
ASSISTANT_QUEUE_ROUTE_MARKERS="assistant-queue-workflow=>"
ASSISTANT_QUEUE_WAITING_TARGET_MARKERS="assistant-queue-row-visual-waiting=>|assistant-queue-approve-visual-waiting=>|assistant-queue-more-visual-waiting=>"
ASSISTANT_QUEUE_APPROVED_TARGET_MARKERS="assistant-queue-row-visual-approved=>|assistant-queue-run-visual-approved=>|assistant-queue-more-visual-approved=>"
ASSISTANT_QUEUE_FAILED_TARGET_MARKERS="assistant-queue-row-visual-failed=>|assistant-queue-retry-visual-failed=>"

if [[ "$P0_WORKFLOWS" == "1" ]]; then
  capture_project_board_destination light inbox "$INBOX_LIGHT_SCREENSHOT" "Inbox" "$P0_INBOX_TARGET_MARKERS" "" "" "inbox-workflow"
  capture_project_board_destination dark inbox "$INBOX_DARK_SCREENSHOT" "Inbox" "$P0_INBOX_TARGET_MARKERS" "" "" "inbox-workflow"
  capture_project_board_destination system inbox "$INBOX_SYSTEM_SCREENSHOT" "Inbox" "$P0_INBOX_TARGET_MARKERS" "" "" "inbox-workflow"
  capture_project_board_destination light today "$TODAY_LIGHT_SCREENSHOT" "Today" "$P0_TODAY_TARGET_MARKERS" "" "" "today-workflow"
  capture_project_board_destination dark today "$TODAY_DARK_SCREENSHOT" "Today" "$P0_TODAY_TARGET_MARKERS" "" "" "today-workflow"
  capture_project_board_destination system today "$TODAY_SYSTEM_SCREENSHOT" "Today" "$P0_TODAY_TARGET_MARKERS" "" "" "today-workflow"
  capture_project_board_destination light inbox "$INBOX_VOICE_LIGHT_SCREENSHOT" "Inbox voice detail" "$INBOX_VOICE_ROUTE_MARKERS" "$INBOX_VOICE_TASK_OVERRIDE" "inbox-voice-intake-detail" "inbox-voice-intake-detail" "$P0_INBOX_VOICE_TARGET_MARKERS"
  capture_project_board_destination dark inbox "$INBOX_VOICE_DARK_SCREENSHOT" "Inbox voice detail" "$INBOX_VOICE_ROUTE_MARKERS" "$INBOX_VOICE_TASK_OVERRIDE" "inbox-voice-intake-detail" "inbox-voice-intake-detail" "$P0_INBOX_VOICE_TARGET_MARKERS"

  GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  write_p0_workflow_evidence_file "$GENERATED_AT" "$INBOX_LIGHT_SCREENSHOT" "$INBOX_DARK_SCREENSHOT" "$INBOX_SYSTEM_SCREENSHOT" "$TODAY_LIGHT_SCREENSHOT" "$TODAY_DARK_SCREENSHOT" "$TODAY_SYSTEM_SCREENSHOT" "$INBOX_VOICE_LIGHT_SCREENSHOT" "$INBOX_VOICE_DARK_SCREENSHOT"

  echo "P0 workflow screenshot evidence generated:"
  echo "evidence: $ROOT_DIR/docs/release/evidence/p0-workflow-screenshots.md"
  echo "screenshots: $SCREENSHOT_DIR"
  exit 0
fi

if [[ "$SCHEDULE_COCKPIT" == "1" ]]; then
  capture_project_board_destination light schedule "$SCHEDULE_LIGHT_SCREENSHOT" "Schedule cockpit" "$SCHEDULE_COCKPIT_TARGET_MARKERS" "" "schedule-mini-calendar" "schedule-mini-calendar"
  capture_project_board_destination dark schedule "$SCHEDULE_DARK_SCREENSHOT" "Schedule cockpit" "$SCHEDULE_COCKPIT_TARGET_MARKERS" "" "schedule-mini-calendar" "schedule-mini-calendar"

  GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  write_schedule_cockpit_evidence_file "$GENERATED_AT" "$SCHEDULE_LIGHT_SCREENSHOT" "$SCHEDULE_DARK_SCREENSHOT"

  echo "Schedule cockpit screenshot evidence generated:"
  echo "evidence: $SCHEDULE_COCKPIT_EVIDENCE_FILE"
  echo "screenshots: $SCREENSHOT_DIR"
  exit 0
fi

if [[ "$SCHEDULE_WORKLOAD" == "1" ]]; then
  capture_project_board_destination light schedule "$SCHEDULE_WORKLOAD_LIGHT_SCREENSHOT" "Schedule workload dashboard" "$SCHEDULE_WORKLOAD_TARGET_MARKERS" "" "" "schedule-workload-attention-banner" "$SCHEDULE_WORKLOAD_DETAIL_MARKERS" workload
  capture_project_board_destination dark schedule "$SCHEDULE_WORKLOAD_DARK_SCREENSHOT" "Schedule workload dashboard" "$SCHEDULE_WORKLOAD_TARGET_MARKERS" "" "" "schedule-workload-attention-banner" "$SCHEDULE_WORKLOAD_DETAIL_MARKERS" workload

  GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  write_schedule_workload_evidence_file "$GENERATED_AT" "$SCHEDULE_WORKLOAD_LIGHT_SCREENSHOT" "$SCHEDULE_WORKLOAD_DARK_SCREENSHOT"

  echo "Schedule workload screenshot evidence generated:"
  echo "evidence: $ROOT_DIR/docs/release/evidence/schedule-workload-screenshots.md"
  echo "screenshots: $SCREENSHOT_DIR"
  exit 0
fi

if [[ "$DONE_ANALYTICS" == "1" ]]; then
  capture_project_board_destination light done "$DONE_LIGHT_SCREENSHOT" "Done analytics" "$DONE_ANALYTICS_TARGET_MARKERS" "" "" "done-workflow"
  capture_project_board_destination dark done "$DONE_DARK_SCREENSHOT" "Done analytics" "$DONE_ANALYTICS_TARGET_MARKERS" "" "" "done-workflow"

  GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  write_done_analytics_evidence_file "$GENERATED_AT" "$DONE_LIGHT_SCREENSHOT" "$DONE_DARK_SCREENSHOT"

  echo "Done analytics screenshot evidence generated:"
  echo "evidence: $DONE_ANALYTICS_EVIDENCE_FILE"
  echo "screenshots: $SCREENSHOT_DIR"
  exit 0
fi

capture_project_board_destination light "$PROJECT_BOARD_SELECTION_OVERRIDE" "$LIGHT_SCREENSHOT" "Project Board" "$PROJECT_BOARD_TARGET_MARKERS" "$PROJECT_BOARD_SELECTED_TASK_OVERRIDE" "" "project-board-detail"
capture_project_board_destination dark "$PROJECT_BOARD_SELECTION_OVERRIDE" "$DARK_SCREENSHOT" "Project Board" "$PROJECT_BOARD_TARGET_MARKERS" "$PROJECT_BOARD_SELECTED_TASK_OVERRIDE" "" "project-board-detail"
capture_project_board_destination system "$PROJECT_BOARD_SELECTION_OVERRIDE" "$SYSTEM_SCREENSHOT" "Project Board" "$PROJECT_BOARD_TARGET_MARKERS" "$PROJECT_BOARD_SELECTED_TASK_OVERRIDE" "" "project-board-detail"
capture_project_board_destination light inbox "$INBOX_LIGHT_SCREENSHOT" "Inbox" "$INBOX_TARGET_MARKERS" "" "" "inbox-workflow"
capture_project_board_destination dark inbox "$INBOX_DARK_SCREENSHOT" "Inbox" "$INBOX_TARGET_MARKERS" "" "" "inbox-workflow"
capture_project_board_destination system inbox "$INBOX_SYSTEM_SCREENSHOT" "Inbox" "$INBOX_TARGET_MARKERS" "" "" "inbox-workflow"
capture_project_board_destination light today "$TODAY_LIGHT_SCREENSHOT" "Today" "$TODAY_TARGET_MARKERS" "" "" "today-workflow"
capture_project_board_destination dark today "$TODAY_DARK_SCREENSHOT" "Today" "$TODAY_TARGET_MARKERS" "" "" "today-workflow"
capture_project_board_destination system today "$TODAY_SYSTEM_SCREENSHOT" "Today" "$TODAY_TARGET_MARKERS" "" "" "today-workflow"
capture_project_board_destination light inbox "$INBOX_VOICE_LIGHT_SCREENSHOT" "Inbox voice detail" "$INBOX_VOICE_ROUTE_MARKERS" "$INBOX_VOICE_TASK_OVERRIDE" "inbox-voice-intake-detail" "inbox-voice-intake-detail" "$INBOX_VOICE_TARGET_MARKERS"
capture_project_board_destination dark inbox "$INBOX_VOICE_DARK_SCREENSHOT" "Inbox voice detail" "$INBOX_VOICE_ROUTE_MARKERS" "$INBOX_VOICE_TASK_OVERRIDE" "inbox-voice-intake-detail" "inbox-voice-intake-detail" "$INBOX_VOICE_TARGET_MARKERS"
capture_project_board_destination light projects "$PROJECTS_OVERVIEW_LIGHT_SCREENSHOT" "Projects overview" "$PROJECTS_TARGET_MARKERS" "" "" "projects-portfolio-overview"
capture_project_board_destination dark projects "$PROJECTS_OVERVIEW_DARK_SCREENSHOT" "Projects overview" "$PROJECTS_TARGET_MARKERS" "" "" "projects-portfolio-overview"
capture_project_board_destination light schedule "$SCHEDULE_LIGHT_SCREENSHOT" "Schedule cockpit" "$SCHEDULE_TARGET_MARKERS" "" "schedule-mini-calendar" "schedule-mini-calendar"
capture_project_board_destination dark schedule "$SCHEDULE_DARK_SCREENSHOT" "Schedule cockpit" "$SCHEDULE_TARGET_MARKERS" "" "schedule-mini-calendar" "schedule-mini-calendar"
capture_project_board_destination light schedule "$SCHEDULE_WORKLOAD_LIGHT_SCREENSHOT" "Schedule workload dashboard" "$SCHEDULE_WORKLOAD_TARGET_MARKERS" "" "" "schedule-workload-attention-banner" "$SCHEDULE_WORKLOAD_DETAIL_MARKERS" workload
capture_project_board_destination dark schedule "$SCHEDULE_WORKLOAD_DARK_SCREENSHOT" "Schedule workload dashboard" "$SCHEDULE_WORKLOAD_TARGET_MARKERS" "" "" "schedule-workload-attention-banner" "$SCHEDULE_WORKLOAD_DETAIL_MARKERS" workload
capture_project_board_destination light done "$DONE_LIGHT_SCREENSHOT" "Done analytics" "$DONE_TARGET_MARKERS" "" "" "done-workflow"
capture_project_board_destination dark done "$DONE_DARK_SCREENSHOT" "Done analytics" "$DONE_TARGET_MARKERS" "" "" "done-workflow"
capture_project_board_destination light assistant-queue "$ASSISTANT_QUEUE_WAITING_LIGHT_SCREENSHOT" "Assistant Queue waiting review" "$ASSISTANT_QUEUE_ROUTE_MARKERS" "" "assistant-queue-row-visual-waiting" "assistant-queue-row-visual-waiting" "$ASSISTANT_QUEUE_WAITING_TARGET_MARKERS"
capture_project_board_destination dark assistant-queue "$ASSISTANT_QUEUE_WAITING_DARK_SCREENSHOT" "Assistant Queue waiting review" "$ASSISTANT_QUEUE_ROUTE_MARKERS" "" "assistant-queue-row-visual-waiting" "assistant-queue-row-visual-waiting" "$ASSISTANT_QUEUE_WAITING_TARGET_MARKERS"
capture_project_board_destination light assistant-queue "$ASSISTANT_QUEUE_APPROVED_LIGHT_SCREENSHOT" "Assistant Queue approved" "$ASSISTANT_QUEUE_ROUTE_MARKERS" "" "assistant-queue-row-visual-approved" "assistant-queue-row-visual-approved" "$ASSISTANT_QUEUE_APPROVED_TARGET_MARKERS"
capture_project_board_destination dark assistant-queue "$ASSISTANT_QUEUE_APPROVED_DARK_SCREENSHOT" "Assistant Queue approved" "$ASSISTANT_QUEUE_ROUTE_MARKERS" "" "assistant-queue-row-visual-approved" "assistant-queue-row-visual-approved" "$ASSISTANT_QUEUE_APPROVED_TARGET_MARKERS"
capture_project_board_destination light assistant-queue "$ASSISTANT_QUEUE_FAILED_LIGHT_SCREENSHOT" "Assistant Queue failed" "$ASSISTANT_QUEUE_ROUTE_MARKERS" "" "assistant-queue-row-visual-failed" "assistant-queue-row-visual-failed" "$ASSISTANT_QUEUE_FAILED_TARGET_MARKERS"
capture_project_board_destination dark assistant-queue "$ASSISTANT_QUEUE_FAILED_DARK_SCREENSHOT" "Assistant Queue failed" "$ASSISTANT_QUEUE_ROUTE_MARKERS" "" "assistant-queue-row-visual-failed" "assistant-queue-row-visual-failed" "$ASSISTANT_QUEUE_FAILED_TARGET_MARKERS"
capture_settings_overview light "$SETTINGS_OVERVIEW_LIGHT_SCREENSHOT"
capture_settings_overview dark "$SETTINGS_OVERVIEW_DARK_SCREENSHOT"
capture_settings_sync light "$SETTINGS_INTEGRATIONS_LIGHT_SCREENSHOT"
capture_settings_sync dark "$SETTINGS_INTEGRATIONS_DARK_SCREENSHOT"
capture_settings_overview system "$SETTINGS_OVERVIEW_SYSTEM_SCREENSHOT"
capture_settings_appearance light "$SETTINGS_APPEARANCE_LIGHT_SCREENSHOT"
capture_settings_appearance dark "$SETTINGS_APPEARANCE_DARK_SCREENSHOT"
capture_settings_appearance system "$SETTINGS_APPEARANCE_SYSTEM_SCREENSHOT"
capture_settings_ai light "$SETTINGS_AI_LIGHT_SCREENSHOT"
capture_settings_ai dark "$SETTINGS_AI_DARK_SCREENSHOT"
capture_settings_privacy light "$SETTINGS_PRIVACY_LIGHT_SCREENSHOT"
capture_settings_privacy dark "$SETTINGS_PRIVACY_DARK_SCREENSHOT"
capture_mcp_settings_appearance light "$MCP_SETTINGS_LIGHT_SCREENSHOT"
capture_mcp_settings_appearance dark "$MCP_SETTINGS_DARK_SCREENSHOT"
capture_mcp_settings_appearance system "$MCP_SETTINGS_SYSTEM_SCREENSHOT"
# Voice Command is an in-board workspace. Capture it after Settings so the
# evidence launch flag can replace the previous destination without restoring
# a second scene.
capture_voice_command_appearance light "$VOICE_COMMAND_LIGHT_SCREENSHOT"
capture_voice_command_appearance dark "$VOICE_COMMAND_DARK_SCREENSHOT"
capture_voice_command_appearance system "$VOICE_COMMAND_SYSTEM_SCREENSHOT"
capture_voice_command_listening_appearance light "$VOICE_COMMAND_LISTENING_LIGHT_SCREENSHOT"
capture_voice_command_listening_appearance dark "$VOICE_COMMAND_LISTENING_DARK_SCREENSHOT"
capture_voice_conversation_appearance light "$VOICE_CONVERSATION_LIGHT_SCREENSHOT"
capture_voice_conversation_appearance dark "$VOICE_CONVERSATION_DARK_SCREENSHOT"

GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
write_visual_ax_audit_receipt "$SOURCE_COMMIT"
write_evidence_file "$GENERATED_AT" "$LIGHT_SCREENSHOT" "$DARK_SCREENSHOT" "$SYSTEM_SCREENSHOT" "$SETTINGS_OVERVIEW_LIGHT_SCREENSHOT" "$SETTINGS_OVERVIEW_DARK_SCREENSHOT" "$SETTINGS_APPEARANCE_LIGHT_SCREENSHOT" "$SETTINGS_APPEARANCE_DARK_SCREENSHOT" "$MCP_SETTINGS_LIGHT_SCREENSHOT" "$MCP_SETTINGS_DARK_SCREENSHOT" "$INBOX_VOICE_LIGHT_SCREENSHOT" "$INBOX_VOICE_DARK_SCREENSHOT" "$PROJECTS_OVERVIEW_LIGHT_SCREENSHOT" "$PROJECTS_OVERVIEW_DARK_SCREENSHOT" "$SCHEDULE_LIGHT_SCREENSHOT" "$SCHEDULE_DARK_SCREENSHOT" "$DONE_LIGHT_SCREENSHOT" "$DONE_DARK_SCREENSHOT" "$SETTINGS_INTEGRATIONS_LIGHT_SCREENSHOT" "$SETTINGS_INTEGRATIONS_DARK_SCREENSHOT"
write_visual_baseline_capture_manifest "$GENERATED_AT"

echo "UI screenshot evidence generated:"
echo "- $(relative_path "$LIGHT_SCREENSHOT")"
echo "- $(relative_path "$DARK_SCREENSHOT")"
echo "- $(relative_path "$SYSTEM_SCREENSHOT")"
echo "- $(relative_path "$INBOX_LIGHT_SCREENSHOT")"
echo "- $(relative_path "$INBOX_DARK_SCREENSHOT")"
echo "- $(relative_path "$INBOX_SYSTEM_SCREENSHOT")"
echo "- $(relative_path "$TODAY_LIGHT_SCREENSHOT")"
echo "- $(relative_path "$TODAY_DARK_SCREENSHOT")"
echo "- $(relative_path "$TODAY_SYSTEM_SCREENSHOT")"
echo "- $(relative_path "$VOICE_COMMAND_LIGHT_SCREENSHOT")"
echo "- $(relative_path "$VOICE_COMMAND_DARK_SCREENSHOT")"
echo "- $(relative_path "$VOICE_COMMAND_SYSTEM_SCREENSHOT")"
echo "- $(relative_path "$VOICE_COMMAND_LISTENING_LIGHT_SCREENSHOT")"
echo "- $(relative_path "$VOICE_COMMAND_LISTENING_DARK_SCREENSHOT")"
echo "- $(relative_path "$SETTINGS_OVERVIEW_LIGHT_SCREENSHOT")"
echo "- $(relative_path "$SETTINGS_OVERVIEW_DARK_SCREENSHOT")"
echo "- $(relative_path "$SETTINGS_OVERVIEW_SYSTEM_SCREENSHOT")"
echo "- $(relative_path "$INBOX_VOICE_LIGHT_SCREENSHOT")"
echo "- $(relative_path "$INBOX_VOICE_DARK_SCREENSHOT")"
echo "- $(relative_path "$PROJECTS_OVERVIEW_LIGHT_SCREENSHOT")"
echo "- $(relative_path "$PROJECTS_OVERVIEW_DARK_SCREENSHOT")"
echo "- $(relative_path "$SCHEDULE_LIGHT_SCREENSHOT")"
echo "- $(relative_path "$SCHEDULE_DARK_SCREENSHOT")"
echo "- $(relative_path "$DONE_LIGHT_SCREENSHOT")"
echo "- $(relative_path "$DONE_DARK_SCREENSHOT")"
echo "- $(relative_path "$SETTINGS_INTEGRATIONS_LIGHT_SCREENSHOT")"
echo "- $(relative_path "$SETTINGS_INTEGRATIONS_DARK_SCREENSHOT")"
echo "- $(relative_path "$ASSISTANT_QUEUE_WAITING_LIGHT_SCREENSHOT")"
echo "- $(relative_path "$ASSISTANT_QUEUE_WAITING_DARK_SCREENSHOT")"
echo "- $(relative_path "$ASSISTANT_QUEUE_APPROVED_LIGHT_SCREENSHOT")"
echo "- $(relative_path "$ASSISTANT_QUEUE_APPROVED_DARK_SCREENSHOT")"
echo "- $(relative_path "$ASSISTANT_QUEUE_FAILED_LIGHT_SCREENSHOT")"
echo "- $(relative_path "$ASSISTANT_QUEUE_FAILED_DARK_SCREENSHOT")"
echo "- $(relative_path "$SETTINGS_APPEARANCE_LIGHT_SCREENSHOT")"
echo "- $(relative_path "$SETTINGS_APPEARANCE_DARK_SCREENSHOT")"
echo "- $(relative_path "$SETTINGS_APPEARANCE_SYSTEM_SCREENSHOT")"
echo "- $(relative_path "$SETTINGS_AI_LIGHT_SCREENSHOT")"
echo "- $(relative_path "$SETTINGS_AI_DARK_SCREENSHOT")"
echo "- $(relative_path "$MCP_SETTINGS_LIGHT_SCREENSHOT")"
echo "- $(relative_path "$MCP_SETTINGS_DARK_SCREENSHOT")"
echo "- $(relative_path "$MCP_SETTINGS_SYSTEM_SCREENSHOT")"
echo "- $(relative_path "$EVIDENCE_FILE")"
