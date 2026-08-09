#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METADATA_FILE="$ROOT_DIR/packaging/app_metadata.env"
LAYOUT_STABILITY_MODE="${1:-run}"

if [[ $# -gt 1 || "$LAYOUT_STABILITY_MODE" != "run" && "$LAYOUT_STABILITY_MODE" != "--check-display-capacity" ]]; then
  echo "usage: $0 [--check-display-capacity]" >&2
  exit 2
fi

if [[ ! -f "$METADATA_FILE" ]]; then
  echo "missing metadata file: $METADATA_FILE" >&2
  exit 2
fi

# shellcheck source=/dev/null
source "$METADATA_FILE"

APP_NAME="${APP_NAME:?APP_NAME is required}"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
WINDOW_NAME="${SUISUI_PROJECT_BOARD_WINDOW_NAME:-}"
TIMEOUT_SECONDS="${SUISUI_LAYOUT_STABILITY_TIMEOUT_SECONDS:-60}"
LAYOUT_STABILITY_OUTPUT_DIR="${SUISUI_LAYOUT_STABILITY_OUTPUT_DIR:-$ROOT_DIR/.tmp/layout-stability}"
LAYOUT_STABILITY_RUNTIME_DIR="${SUISUI_LAYOUT_STABILITY_RUNTIME_DIR:-${TMPDIR:-/tmp}/suisui-layout-stability}"
# Default to 0px because layout-sensitive mutations should settle
# synchronously. Set SUISUI_LAYOUT_STABILITY_FRAME_DELTA_THRESHOLD_PX=1 only
# for a documented macOS rendering/runtime tolerance.
LAYOUT_STABILITY_FRAME_DELTA_THRESHOLD_PX="${SUISUI_LAYOUT_STABILITY_FRAME_DELTA_THRESHOLD_PX:-0}"
LAYOUT_STABILITY_CLIPPING_TOLERANCE_PX="${SUISUI_LAYOUT_STABILITY_CLIPPING_TOLERANCE_PX:-1}"
LAYOUT_STABILITY_DATABASE_PATH="${SUISUI_LAYOUT_STABILITY_DATABASE_PATH:-$LAYOUT_STABILITY_RUNTIME_DIR/Suisui-layout-stability.sqlite}"
LAYOUT_STABILITY_WINDOW_BELOW_MIN_WIDTH="${SUISUI_LAYOUT_STABILITY_WINDOW_BELOW_MIN_WIDTH:-900}"
LAYOUT_STABILITY_WINDOW_COMPACT_WIDTH="${SUISUI_LAYOUT_STABILITY_WINDOW_COMPACT_WIDTH:-960}"
LAYOUT_STABILITY_WINDOW_CANONICAL_WIDTH="${SUISUI_LAYOUT_STABILITY_WINDOW_CANONICAL_WIDTH:-1024}"
LAYOUT_STABILITY_WINDOW_MIN_WIDTH="${SUISUI_LAYOUT_STABILITY_WINDOW_MIN_WIDTH:-960}"
LAYOUT_STABILITY_WINDOW_BELOW_MIN_HEIGHT="${SUISUI_LAYOUT_STABILITY_WINDOW_BELOW_MIN_HEIGHT:-580}"
LAYOUT_STABILITY_CONTENT_MIN_HEIGHT="${SUISUI_LAYOUT_STABILITY_CONTENT_MIN_HEIGHT:-620}"
LAYOUT_STABILITY_WINDOW_MIN_HEIGHT="${SUISUI_LAYOUT_STABILITY_WINDOW_MIN_HEIGHT:-720}"
LAYOUT_STABILITY_WINDOW_STANDARD_WIDTH="${SUISUI_LAYOUT_STABILITY_WINDOW_STANDARD_WIDTH:-1180}"
LAYOUT_STABILITY_WINDOW_STANDARD_HEIGHT="${SUISUI_LAYOUT_STABILITY_WINDOW_STANDARD_HEIGHT:-760}"
LAYOUT_STABILITY_WINDOW_WIDE_WIDTH="${SUISUI_LAYOUT_STABILITY_WINDOW_WIDE_WIDTH:-1420}"
LAYOUT_STABILITY_WINDOW_WIDE_HEIGHT="${SUISUI_LAYOUT_STABILITY_WINDOW_WIDE_HEIGHT:-860}"
readonly PRODUCT_LAYOUT_WINDOW_STANDARD_WIDTH_FLOOR=1180
readonly PRODUCT_LAYOUT_WINDOW_STANDARD_HEIGHT_FLOOR=760
readonly PRODUCT_LAYOUT_WINDOW_WIDE_WIDTH_FLOOR=1420
readonly PRODUCT_LAYOUT_WINDOW_WIDE_HEIGHT_FLOOR=860
# The custom sidebar starts below the 28px title bar, 10px outer padding,
# 32px brand row, 10px gap, 36px Search button, and another 10px gap. Its
# 32px destination buttons use 2px spacing, matching the approved today.png
# rhythm. Keep the fallback aimed at each Button center when AXPress is absent.
# The 180px minimum sidebar leaves the Button hit region from x=10 through x=170; x=112
# stays well inside those bounds, left of trailing count badges and away from the split divider.
readonly SIDEBAR_DESTINATION_ROW_CENTER_X_OFFSET_PX=112
readonly SIDEBAR_DESTINATION_FIRST_ROW_CENTER_Y_OFFSET_PX=142
readonly SIDEBAR_DESTINATION_ROW_STRIDE_PX=34
LAYOUT_STABILITY_VISIBLE_FRAME_WIDTH="${SUISUI_LAYOUT_STABILITY_VISIBLE_FRAME_WIDTH:-0}"
LAYOUT_STABILITY_VISIBLE_FRAME_HEIGHT="${SUISUI_LAYOUT_STABILITY_VISIBLE_FRAME_HEIGHT:-0}"
LAYOUT_STABILITY_AX_COLLECTION_TIMEOUT_SECONDS="${SUISUI_LAYOUT_STABILITY_AX_COLLECTION_TIMEOUT_SECONDS:-8}"
LAYOUT_STABILITY_AX_IDENTIFIER_RETRY_COUNT="${SUISUI_LAYOUT_STABILITY_AX_IDENTIFIER_RETRY_COUNT:-3}"
LAYOUT_STABILITY_AX_IDENTIFIER_RETRY_DELAY_MS="${SUISUI_LAYOUT_STABILITY_AX_IDENTIFIER_RETRY_DELAY_MS:-50}"
SQLITE3="${SQLITE3:-sqlite3}"
AX_HELPERS="${AX_HELPERS:-$ROOT_DIR/script/ui_accessibility_smoke_helpers.sh}"
AX_FRAME_HELPER="${AX_FRAME_HELPER:-$ROOT_DIR/script/ui_evidence_ax_frame_dump.swift}"
AX_PRESS_ELEMENT_HELPER="${AX_PRESS_ELEMENT_HELPER:-$ROOT_DIR/script/ui_evidence_ax_press_element.swift}"
AX_RESIZE_WINDOW_HELPER="${AX_RESIZE_WINDOW_HELPER:-$ROOT_DIR/script/ui_evidence_ax_resize_window.swift}"
WINDOW_CONTENT_SIZE_HELPER="${WINDOW_CONTENT_SIZE_HELPER:-$ROOT_DIR/script/ui_evidence_window_content_size.swift}"

if [[ ! "$TIMEOUT_SECONDS" =~ ^[0-9]+$ || "$TIMEOUT_SECONDS" -lt 1 ]]; then
  echo "SUISUI_LAYOUT_STABILITY_TIMEOUT_SECONDS must be a positive integer" >&2
  exit 2
fi

if [[ ! "$LAYOUT_STABILITY_FRAME_DELTA_THRESHOLD_PX" =~ ^[0-9]+$ ]]; then
  echo "LAYOUT_STABILITY_FRAME_DELTA_THRESHOLD_PX must be a non-negative integer" >&2
  exit 2
fi

if [[ ! "$LAYOUT_STABILITY_CLIPPING_TOLERANCE_PX" =~ ^[0-9]+$ ]]; then
  echo "LAYOUT_STABILITY_CLIPPING_TOLERANCE_PX must be a non-negative integer" >&2
  exit 2
fi

if [[ ! "$LAYOUT_STABILITY_AX_COLLECTION_TIMEOUT_SECONDS" =~ ^[0-9]+$ || "$LAYOUT_STABILITY_AX_COLLECTION_TIMEOUT_SECONDS" -lt 1 ]]; then
  echo "SUISUI_LAYOUT_STABILITY_AX_COLLECTION_TIMEOUT_SECONDS must be a positive integer" >&2
  exit 2
fi

if [[ ! "$LAYOUT_STABILITY_AX_IDENTIFIER_RETRY_COUNT" =~ ^[0-9]+$ ]]; then
  echo "SUISUI_LAYOUT_STABILITY_AX_IDENTIFIER_RETRY_COUNT must be a non-negative integer" >&2
  exit 2
fi

if [[ ! "$LAYOUT_STABILITY_AX_IDENTIFIER_RETRY_DELAY_MS" =~ ^[0-9]+$ ]]; then
  echo "SUISUI_LAYOUT_STABILITY_AX_IDENTIFIER_RETRY_DELAY_MS must be a non-negative integer" >&2
  exit 2
fi

for dimension_name in \
  LAYOUT_STABILITY_WINDOW_BELOW_MIN_WIDTH \
  LAYOUT_STABILITY_WINDOW_MIN_WIDTH \
  LAYOUT_STABILITY_WINDOW_COMPACT_WIDTH \
  LAYOUT_STABILITY_WINDOW_CANONICAL_WIDTH \
  LAYOUT_STABILITY_WINDOW_BELOW_MIN_HEIGHT \
  LAYOUT_STABILITY_CONTENT_MIN_HEIGHT \
  LAYOUT_STABILITY_WINDOW_MIN_HEIGHT \
  LAYOUT_STABILITY_WINDOW_STANDARD_WIDTH \
  LAYOUT_STABILITY_WINDOW_STANDARD_HEIGHT \
  LAYOUT_STABILITY_WINDOW_WIDE_WIDTH \
  LAYOUT_STABILITY_WINDOW_WIDE_HEIGHT; do
  dimension_value="${!dimension_name}"
  if [[ ! "$dimension_value" =~ ^[0-9]+$ || "$dimension_value" -lt 1 ]]; then
    echo "$dimension_name must be a positive integer" >&2
    exit 2
  fi
done

if [[ "$LAYOUT_STABILITY_WINDOW_STANDARD_WIDTH" -lt "$PRODUCT_LAYOUT_WINDOW_STANDARD_WIDTH_FLOOR" ||
  "$LAYOUT_STABILITY_WINDOW_STANDARD_HEIGHT" -lt "$PRODUCT_LAYOUT_WINDOW_STANDARD_HEIGHT_FLOOR" ||
  "$LAYOUT_STABILITY_WINDOW_WIDE_WIDTH" -lt "$PRODUCT_LAYOUT_WINDOW_WIDE_WIDTH_FLOOR" ||
  "$LAYOUT_STABILITY_WINDOW_WIDE_HEIGHT" -lt "$PRODUCT_LAYOUT_WINDOW_WIDE_HEIGHT_FLOOR" ]]; then
  printf 'failure_category=configuration\n' >&2
  printf 'failure_reason=layout-window-contract-below-product-floor\n' >&2
  printf 'BLOCKER: layout window override is below the immutable product contract (standard floor=%sx%s, wide floor=%sx%s; configured standard=%sx%s, wide=%sx%s).\n' \
    "$PRODUCT_LAYOUT_WINDOW_STANDARD_WIDTH_FLOOR" "$PRODUCT_LAYOUT_WINDOW_STANDARD_HEIGHT_FLOOR" \
    "$PRODUCT_LAYOUT_WINDOW_WIDE_WIDTH_FLOOR" "$PRODUCT_LAYOUT_WINDOW_WIDE_HEIGHT_FLOOR" \
    "$LAYOUT_STABILITY_WINDOW_STANDARD_WIDTH" "$LAYOUT_STABILITY_WINDOW_STANDARD_HEIGHT" \
    "$LAYOUT_STABILITY_WINDOW_WIDE_WIDTH" "$LAYOUT_STABILITY_WINDOW_WIDE_HEIGHT" >&2
  exit 2
fi

for visible_dimension_name in LAYOUT_STABILITY_VISIBLE_FRAME_WIDTH LAYOUT_STABILITY_VISIBLE_FRAME_HEIGHT; do
  visible_dimension_value="${!visible_dimension_name}"
  if [[ ! "$visible_dimension_value" =~ ^[0-9]+$ ]]; then
    echo "$visible_dimension_name must be a non-negative integer" >&2
    exit 2
  fi
done

require_layout_display_capacity() {
  if [[ "$LAYOUT_STABILITY_VISIBLE_FRAME_WIDTH" -lt "$LAYOUT_STABILITY_WINDOW_WIDE_WIDTH" ||
    "$LAYOUT_STABILITY_VISIBLE_FRAME_HEIGHT" -lt "$LAYOUT_STABILITY_WINDOW_WIDE_HEIGHT" ]]; then
    printf 'failure_category=runner-capability\n' >&2
    printf 'failure_reason=layout-visible-frame-too-small\n' >&2
    printf 'BLOCKER: UI runner visible frame %sx%s cannot exercise required layout windows (standard=%sx%s, wide=%sx%s); product contract was not downgraded.\n' \
      "$LAYOUT_STABILITY_VISIBLE_FRAME_WIDTH" "$LAYOUT_STABILITY_VISIBLE_FRAME_HEIGHT" \
      "$LAYOUT_STABILITY_WINDOW_STANDARD_WIDTH" "$LAYOUT_STABILITY_WINDOW_STANDARD_HEIGHT" \
      "$LAYOUT_STABILITY_WINDOW_WIDE_WIDTH" "$LAYOUT_STABILITY_WINDOW_WIDE_HEIGHT" >&2
    return 1
  fi
  printf 'OK: UI runner visible frame %sx%s can exercise required layout windows (standard=%sx%s, wide=%sx%s)\n' \
    "$LAYOUT_STABILITY_VISIBLE_FRAME_WIDTH" "$LAYOUT_STABILITY_VISIBLE_FRAME_HEIGHT" \
    "$LAYOUT_STABILITY_WINDOW_STANDARD_WIDTH" "$LAYOUT_STABILITY_WINDOW_STANDARD_HEIGHT" \
    "$LAYOUT_STABILITY_WINDOW_WIDE_WIDTH" "$LAYOUT_STABILITY_WINDOW_WIDE_HEIGHT"
}

if [[ "$LAYOUT_STABILITY_MODE" == "--check-display-capacity" ]]; then
  if [[ "$LAYOUT_STABILITY_VISIBLE_FRAME_WIDTH" -eq 0 || "$LAYOUT_STABILITY_VISIBLE_FRAME_HEIGHT" -eq 0 ]]; then
    echo "SUISUI_LAYOUT_STABILITY_VISIBLE_FRAME_WIDTH and SUISUI_LAYOUT_STABILITY_VISIBLE_FRAME_HEIGHT are required" >&2
    exit 2
  fi
  require_layout_display_capacity
  exit $?
fi

if ! command -v "$SQLITE3" >/dev/null 2>&1; then
  echo "BLOCKER: sqlite3 is required for layout stability smoke" >&2
  exit 2
fi

# shellcheck source=/dev/null
source "$AX_HELPERS"

cd "$ROOT_DIR"
mkdir -p "$LAYOUT_STABILITY_OUTPUT_DIR"
mkdir -p "$(dirname "$LAYOUT_STABILITY_DATABASE_PATH")"
mkdir -p "$LAYOUT_STABILITY_RUNTIME_DIR/home"

SUMMARY_FILE="$LAYOUT_STABILITY_OUTPUT_DIR/layout-stability-summary.md"
SAMPLES_FILE="$LAYOUT_STABILITY_OUTPUT_DIR/samples.tsv"
DIFF_FILE="$LAYOUT_STABILITY_OUTPUT_DIR/diff.tsv"
SAMPLES_JSON_FILE="$LAYOUT_STABILITY_OUTPUT_DIR/samples.json"
DIFF_JSON_FILE="$LAYOUT_STABILITY_OUTPUT_DIR/diff.json"
WINDOW_METADATA_FILE="$LAYOUT_STABILITY_OUTPUT_DIR/window.tsv"
WINDOW_CONTENT_SIZE_FILE="$LAYOUT_STABILITY_OUTPUT_DIR/window-content-size.tsv"
WINDOW_RESIZE_ATTEMPTS_FILE="$LAYOUT_STABILITY_OUTPUT_DIR/window-resize-attempts.tsv"
REQUIRED_AX_IDENTIFIERS=(
  "project-board-command-palette"
  "project-board-detail"
  "project-board-sidebar"
)
# Sampling schedule: t=0ms, t=50ms, t=150ms, t=300ms.
SAMPLE_OFFSETS_MS=(0 50 150 300)
layout_project_id=""
app_pid=""
app_launch_pid=""
app_identity=""
app_launch_identity=""
AX_FRAME_HELPER_BINARY="$LAYOUT_STABILITY_OUTPUT_DIR/ui-evidence-ax-frame-dump.$$"
AX_PRESS_ELEMENT_HELPER_BINARY="$LAYOUT_STABILITY_OUTPUT_DIR/ui-evidence-ax-press-element.$$"
AX_RESIZE_WINDOW_HELPER_BINARY="$LAYOUT_STABILITY_OUTPUT_DIR/ui-evidence-ax-resize-window.$$"
WINDOW_CONTENT_SIZE_HELPER_BINARY="$LAYOUT_STABILITY_OUTPUT_DIR/ui-evidence-window-content-size.$$"

: >"$SAMPLES_FILE"
: >"$DIFF_FILE"
printf 'attempt\trequested_width\trequested_height\texpected_width\tbefore_window_id\tbefore_x\tbefore_y\tbefore_width\tbefore_height\tax_status\tafter_window_id\tafter_x\tafter_y\tafter_width\tafter_height\n' >"$WINDOW_RESIZE_ATTEMPTS_FILE"

write_json_artifacts() {
  # JSON phase values: "phase":"before", "phase":"immediate", "phase":"after".
  awk -F $'\t' '
    function json_escape(value) {
      gsub(/\\/,"\\\\",value)
      gsub(/"/,"\\\"",value)
      return value
    }
    function phase_for(label) {
      if (label == "initial") return "before"
      if (label == "sidebar-hidden") return "immediate"
      if (label == "sidebar-restored") return "after"
      return label
    }
    BEGIN { print "[" }
    {
      if (count > 0) printf ",\n"
      printf "  {\"phase\":\"%s\",\"label\":\"%s\",\"sample\":%d,\"offset\":\"%s\",\"identifier\":\"%s\",\"x\":%d,\"y\":%d,\"width\":%d,\"height\":%d}",
        phase_for($1), json_escape($1), $2, json_escape($3), json_escape($4), $5, $6, $7, $8
      count += 1
    }
    END {
      if (count > 0) print ""
      print "]"
    }
  ' "$SAMPLES_FILE" >"$SAMPLES_JSON_FILE"

  awk -F $'\t' '
    function json_escape(value) {
      gsub(/\\/,"\\\\",value)
      gsub(/"/,"\\\"",value)
      return value
    }
    function phase_for(label) {
      if (label == "initial") return "before"
      if (label == "sidebar-hidden") return "immediate"
      if (label == "sidebar-restored") return "after"
      return label
    }
    BEGIN { print "[" }
    {
      if (count > 0) printf ",\n"
      printf "  {\"phase\":\"%s\",\"label\":\"%s\",\"offset\":\"%s\",\"identifier\":\"%s\",\"dx\":%d,\"dy\":%d,\"dw\":%d,\"dh\":%d,\"delta\":%d}",
        phase_for($1), json_escape($1), json_escape($2), json_escape($3), $4, $5, $6, $7, $8
      count += 1
    }
    END {
      if (count > 0) print ""
      print "]"
    }
  ' "$DIFF_FILE" >"$DIFF_JSON_FILE"
}

terminate_app() {
  local owned_pid="${app_pid:-}"
  local launch_pid="${app_launch_pid:-}"
  if [[ -n "$owned_pid" ]]; then
    ax_terminate_owned_process "$owned_pid" "$APP_BINARY" "${app_identity:-}"
  fi
  if [[ -n "$launch_pid" && "$launch_pid" != "$owned_pid" ]]; then
    ax_terminate_owned_process "$launch_pid" "$APP_BINARY" "${app_launch_identity:-}"
  fi
  app_pid=""
  app_launch_pid=""
  app_identity=""
  app_launch_identity=""
}

cleanup() {
  terminate_app
  rm -f "$AX_FRAME_HELPER_BINARY" "$AX_PRESS_ELEMENT_HELPER_BINARY" "$AX_RESIZE_WINDOW_HELPER_BINARY" "$WINDOW_CONTENT_SIZE_HELPER_BINARY"
}

prepare_ax_helpers() {
  # Compile before t=0 sampling. Interpreter compilation inside frame
  # collection would shift every requested sample beyond the 300ms window.
  /usr/bin/swiftc "$AX_FRAME_HELPER" -o "$AX_FRAME_HELPER_BINARY"
  /usr/bin/swiftc "$AX_PRESS_ELEMENT_HELPER" -o "$AX_PRESS_ELEMENT_HELPER_BINARY"
  /usr/bin/swiftc "$AX_RESIZE_WINDOW_HELPER" -o "$AX_RESIZE_WINDOW_HELPER_BINARY"
  /usr/bin/swiftc "$WINDOW_CONTENT_SIZE_HELPER" -o "$WINDOW_CONTENT_SIZE_HELPER_BINARY"
}

activate_app() {
  # PID ownership keeps the isolated layout database attached to every AX
  # action even when another developer-run Suisui instance exists.
  /usr/bin/osascript - "$app_pid" "$APP_NAME" <<'APPLESCRIPT' >/dev/null 2>&1 || true
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
end run
APPLESCRIPT
}

wait_for_app_process() {
  app_pid="$(ax_wait_for_owned_app_pid "$app_launch_pid" "$APP_BINARY" "$TIMEOUT_SECONDS")" || {
    ax_emit_failure_category "launch" "layout-owned-pid-unavailable"
    echo "BLOCKER: $APP_NAME did not launch from pid $app_launch_pid" >&2
    return 1
  }
  app_identity="$(ax_wait_for_owned_process_identity "$app_pid" "$APP_BINARY" 3)" || {
    ax_emit_failure_category "launch" "layout-owned-identity-unavailable"
    return 1
  }
  ax_wait_for_pid_owned_process "$APP_NAME" "$app_pid" "$TIMEOUT_SECONDS" "$APP_BINARY"
}

wait_for_visible_windows() {
  if ! ax_wait_for_pid_owned_window "$APP_NAME" "$app_pid" "$WINDOW_NAME" "$TIMEOUT_SECONDS" "" "$APP_BINARY"; then
    echo "BLOCKER: $APP_NAME did not expose a visible AX window for launched pid $app_pid" >&2
    return 1
  fi
  return 0
}

wait_for_database_table() {
  local table="$1"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while true; do
    if [[ -f "$LAYOUT_STABILITY_DATABASE_PATH" ]] &&
      "$SQLITE3" "$LAYOUT_STABILITY_DATABASE_PATH" "SELECT name FROM sqlite_master WHERE type='table' AND name='$table';" | grep -Fx "$table" >/dev/null; then
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: SQLite table '$table' was not created in layout stability database: $LAYOUT_STABILITY_DATABASE_PATH" >&2
      return 1
    fi
    sleep 1
  done
}

migrate_layout_database() {
  terminate_app
  rm -f "$LAYOUT_STABILITY_DATABASE_PATH" "$LAYOUT_STABILITY_DATABASE_PATH-shm" "$LAYOUT_STABILITY_DATABASE_PATH-wal"
  /usr/bin/env -i PATH="$PATH" TMPDIR="$LAYOUT_STABILITY_RUNTIME_DIR" HOME="$LAYOUT_STABILITY_RUNTIME_DIR/home" CFFIXED_USER_HOME="$LAYOUT_STABILITY_RUNTIME_DIR/home" \
    SUISUI_DISABLE_KEYCHAIN_SECRET_STORE=1 SUISUI_DATABASE_PATH="$LAYOUT_STABILITY_DATABASE_PATH" \
    SUISUI_PROJECT_BOARD_SELECTED_DESTINATION="projects" \
    "$APP_BINARY" -ApplePersistenceIgnoreState YES &
  app_launch_pid=$!
  app_launch_identity="$(ax_wait_for_owned_process_identity "$app_launch_pid" "$APP_BINARY" 3)" || return 1
  wait_for_app_process
  wait_for_database_table "projects"
  terminate_app
}

seed_layout_candidate() {
  # Keep layout fixtures local to this smoke. Reusing the VoiceOver recovery
  # candidate would make a required production-route gate depend on a recovery
  # launch and on process-name-wide cleanup.
  "$SQLITE3" "$LAYOUT_STABILITY_DATABASE_PATH" <<'SQL'
PRAGMA foreign_keys = ON;
DELETE FROM tasks WHERE source_command='layout-stability-seed';
DELETE FROM projects WHERE source_command='layout-stability-seed';
INSERT INTO projects (title, status, priority, deadline, workspace_path, tags_json, source_command, created_at, updated_at)
VALUES ('Layout Stability Project', 'active', 'high', NULL, NULL, '["layout"]', 'layout-stability-seed', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
SQL

  layout_project_id="$("$SQLITE3" -batch -noheader "$LAYOUT_STABILITY_DATABASE_PATH" "SELECT id FROM projects WHERE source_command='layout-stability-seed' ORDER BY id DESC LIMIT 1;" | tail -n 1)"
  if [[ -z "${layout_project_id//[[:space:]]/}" ]]; then
    echo "BLOCKER: layout stability candidate project was not seeded" >&2
    return 1
  fi

  "$SQLITE3" "$LAYOUT_STABILITY_DATABASE_PATH" <<SQL
PRAGMA foreign_keys = ON;
INSERT INTO tasks (project_id, title, status, detail, due_at, priority, source_command, created_at, updated_at)
VALUES
  ($layout_project_id, 'Layout backlog', 'backlog', 'Layout stability seed', NULL, 'medium', 'layout-stability-seed', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ($layout_project_id, 'Layout planned', 'planned', 'Layout stability seed', NULL, 'medium', 'layout-stability-seed', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ($layout_project_id, 'Layout in progress', 'in_progress', 'Layout stability seed', NULL, 'medium', 'layout-stability-seed', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ($layout_project_id, 'Layout blocked', 'blocked', 'Layout stability seed', NULL, 'medium', 'layout-stability-seed', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ($layout_project_id, 'Layout completed', 'completed', 'Layout stability seed', NULL, 'medium', 'layout-stability-seed', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
SQL
}

prepare_layout_candidate() {
  rm -rf "$LAYOUT_STABILITY_RUNTIME_DIR/home"
  mkdir -p "$LAYOUT_STABILITY_RUNTIME_DIR/home"
  rm -f "$WINDOW_CONTENT_SIZE_FILE"
  ./script/build_and_run.sh --build-only
  migrate_layout_database
  seed_layout_candidate
}

launch_layout_candidate() {
  terminate_app
  /usr/bin/env -i PATH="$PATH" TMPDIR="$LAYOUT_STABILITY_RUNTIME_DIR" HOME="$LAYOUT_STABILITY_RUNTIME_DIR/home" CFFIXED_USER_HOME="$LAYOUT_STABILITY_RUNTIME_DIR/home" \
    SUISUI_DISABLE_KEYCHAIN_SECRET_STORE=1 SUISUI_DATABASE_PATH="$LAYOUT_STABILITY_DATABASE_PATH" \
    SUISUI_DISABLE_PROJECT_BOARD_FALLBACK=1 \
    SUISUI_DISABLE_PROJECT_BOARD_PRESENTATION_PERSISTENCE=1 \
    SUISUI_LAYOUT_STABILITY_WINDOW_CONTENT_SIZE_PATH="$WINDOW_CONTENT_SIZE_FILE" \
    SUISUI_PROJECT_BOARD_SELECTED_DESTINATION="project:$layout_project_id" \
    "$APP_BINARY" -ApplePersistenceIgnoreState YES &
  app_launch_pid=$!
  app_launch_identity="$(ax_wait_for_owned_process_identity "$app_launch_pid" "$APP_BINARY" 3)" || return 1
  wait_for_app_process
  activate_app
  wait_for_visible_windows
}

read_window_metadata() {
  local require_single_window="${1:-0}"
  local output
  local metadata_status
  set +e
  output="$(
    SUISUI_WINDOW_OWNER="$APP_NAME" \
    SUISUI_WINDOW_OWNER_PID="$app_pid" \
    SUISUI_WINDOW_NAME="$WINDOW_NAME" \
    SUISUI_REQUIRE_SINGLE_WINDOW="$require_single_window" \
    /usr/bin/swift "$ROOT_DIR/script/ui_evidence_window_metadata.swift"
  )"
  metadata_status=$?
  set -e
  if [[ "$metadata_status" -ne 0 ]]; then
    : >"$WINDOW_METADATA_FILE"
    return "$metadata_status"
  fi
  printf '%s\n' "$output" >"$WINDOW_METADATA_FILE"
  window_metadata_has_positive_bounds
}

window_metadata_has_positive_bounds() {
  local window_id window_x window_y window_width window_height
  [[ -s "$WINDOW_METADATA_FILE" ]] || return 1
  read -r window_id window_x window_y window_width window_height <"$WINDOW_METADATA_FILE" || return 1
  [[ "$window_id" =~ ^[0-9]+$ ]] &&
    [[ "$window_x" =~ ^-?[0-9]+$ ]] &&
    [[ "$window_y" =~ ^-?[0-9]+$ ]] &&
    [[ "$window_width" =~ ^[0-9]+$ ]] &&
    [[ "$window_height" =~ ^[0-9]+$ ]] &&
    [[ "$window_width" -gt 0 ]] &&
    [[ "$window_height" -gt 0 ]]
}

wait_for_window_metadata() {
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while true; do
    if read_window_metadata >/dev/null 2>&1 && window_metadata_has_positive_bounds; then
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: Project Board window metadata was not available within ${TIMEOUT_SECONDS}s" >&2
      return 1
    fi
    sleep 1
  done
}

wait_for_window_width() {
  local expected_width="$1"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local window_id window_x window_y window_width window_height
  while true; do
    if read_window_metadata >/dev/null 2>&1 && window_metadata_has_positive_bounds; then
      read -r window_id window_x window_y window_width window_height <"$WINDOW_METADATA_FILE"
      if [[ "$window_width" -eq "$expected_width" ]]; then
        return 0
      fi
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: Project Board window width did not settle at ${expected_width}px within ${TIMEOUT_SECONDS}s (actual=${window_width:-unknown})" >&2
      return 1
    fi
    sleep 0.1
  done
}

set_project_board_window_size() {
  local width="$1"
  local height="$2"
  local expected_width="${3:-$width}"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local attempt=0
  local window_id window_x window_y window_width window_height
  local before_window_id before_x before_y before_width before_height
  local after_window_id after_x after_y after_width after_height ax_status
  # Resize the real app window through AX so the smoke covers AppKit/SwiftUI
  # bridge behavior instead of only source-level layout contracts. Route and
  # inspector transitions can recreate the SwiftUI window after AX accepted a
  # resize, so bind the unique AX window to the sole visible CG frame before
  # mutation, then reapply until fresh CG metadata proves the expected width.
  # AXMain is intentionally not used: a menu-bar panel can become main while
  # the visible Project Board remains the uniquely frame-matched target.
  while true; do
    attempt=$((attempt + 1))
    before_window_id=-1
    before_x=-1
    before_y=-1
    before_width=-1
    before_height=-1
    after_window_id=-1
    after_x=-1
    after_y=-1
    after_width=-1
    after_height=-1
    ax_status=125
    if wait_for_visible_windows >/dev/null 2>&1 &&
      read_window_metadata 1 >/dev/null 2>&1 && window_metadata_has_positive_bounds
    then
      read -r window_id window_x window_y window_width window_height <"$WINDOW_METADATA_FILE"
      before_window_id="$window_id"
      before_x="$window_x"
      before_y="$window_y"
      before_width="$window_width"
      before_height="$window_height"
      if "$AX_RESIZE_WINDOW_HELPER_BINARY" \
        "$app_pid" "$window_x" "$window_y" "$window_width" "$window_height" \
        "$width" "$height" >/dev/null 2>&1
      then
        ax_status=0
      else
        ax_status=$?
      fi
      if read_window_metadata 1 >/dev/null 2>&1 && window_metadata_has_positive_bounds; then
        read -r window_id window_x window_y window_width window_height <"$WINDOW_METADATA_FILE"
        after_window_id="$window_id"
        after_x="$window_x"
        after_y="$window_y"
        after_width="$window_width"
        after_height="$window_height"
      fi
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$attempt" "$width" "$height" "$expected_width" \
      "$before_window_id" "$before_x" "$before_y" "$before_width" "$before_height" \
      "$ax_status" "$after_window_id" "$after_x" "$after_y" "$after_width" "$after_height" \
      >>"$WINDOW_RESIZE_ATTEMPTS_FILE"
    if [[ "$after_width" -eq "$expected_width" ]]; then
      if [[ "$ax_status" -eq 0 ]]; then
        return 0
      fi
      if [[ "$width" -lt "$expected_width" ]]; then
        # AppKit can reject the below-minimum AX assignment while preserving
        # the product's exact minimum. The observed PID-owned CG width is the
        # required postcondition for this deliberate minimum-boundary probe.
        return 0
      fi
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: failed to resize named PID-owned app window pid=$app_pid to ${width}x${height} (observed=${window_width:-unknown}x${window_height:-unknown})" >&2
      return 1
    fi
    if [[ "$attempt" -gt 1 ]]; then
      echo "INFO: reapplying owned window size after route/window recreation (attempt=$attempt target=${width}x${height} observed=${window_width:-unknown}x${window_height:-unknown})" >&2
    fi
    activate_app
    sleep 0.2
  done
}

assert_window_minimum_width() {
  local state="$1"
  local window_id window_x window_y window_width window_height
  wait_for_window_metadata
  read -r window_id window_x window_y window_width window_height <"$WINDOW_METADATA_FILE"
  if [[ "$window_width" -lt "$LAYOUT_STABILITY_WINDOW_MIN_WIDTH" ]]; then
    echo "BLOCKER: Project Board window shrank below ${LAYOUT_STABILITY_WINDOW_MIN_WIDTH}px while inspector was ${state} (actual=${window_width}px)" >&2
    return 1
  fi
  printf 'OK: Project Board minimum width held at %spx while inspector was %s\n' "$window_width" "$state"
}

assert_window_content_minimum() {
  local state="$1"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local content_width content_height
  while true; do
    if read -r content_width content_height < <("$WINDOW_CONTENT_SIZE_HELPER_BINARY" "$WINDOW_CONTENT_SIZE_FILE" 2>/dev/null) &&
      [[ "$content_width" =~ ^[0-9]+$ ]] &&
      [[ "$content_height" =~ ^[0-9]+$ ]] &&
      [[ "$content_width" -ge "$LAYOUT_STABILITY_WINDOW_MIN_WIDTH" ]] &&
      [[ "$content_height" -ge "$LAYOUT_STABILITY_CONTENT_MIN_HEIGHT" ]]; then
      printf 'OK: Project Board content minimum held at %sx%s while inspector was %s\n' \
        "$content_width" "$content_height" "$state"
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: Project Board content size fell below ${LAYOUT_STABILITY_WINDOW_MIN_WIDTH}x${LAYOUT_STABILITY_CONTENT_MIN_HEIGHT} while inspector was ${state} (actual=${content_width:-unknown}x${content_height:-unknown})" >&2
      return 1
    fi
    sleep 0.1
  done
}

window_size_key() {
  local window_id window_x window_y window_width window_height
  wait_for_window_metadata
  read -r window_id window_x window_y window_width window_height <"$WINDOW_METADATA_FILE"
  printf '%s %s\n' "$window_width" "$window_height"
}

click_sidebar_destination() {
  local destination_identifier="$1"
  local destination_label="$2"
  if "$AX_PRESS_ELEMENT_HELPER_BINARY" "$app_pid" "$destination_identifier"; then
    return 0
  fi
  printf 'INFO: exact-PID AXPress did not select %s (%s); using measured coordinate fallback.\n' \
    "$destination_identifier" "$destination_label" >&2
  click_sidebar_destination_by_coordinate "$destination_identifier"
}

wait_for_ax_identifier() {
  local identifier="$1"
  local safe_identifier="${identifier//[^[:alnum:]_-]/_}"
  local probe_file="$LAYOUT_STABILITY_OUTPUT_DIR/wait-$safe_identifier.txt"

  if ax_wait_for_ax_identifier "$APP_NAME" "$identifier" "$TIMEOUT_SECONDS" "$ROOT_DIR" "$probe_file" "" "$app_pid"; then
    return 0
  fi
  echo "BLOCKER: AX identifier did not appear after sidebar destination selection: $identifier" >&2
  sed -n '1,20p' "$probe_file.err" >&2 || true
  return 1
}

wait_for_ax_identifier_absent() {
  local identifier="$1"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local probe_file="$LAYOUT_STABILITY_OUTPUT_DIR/wait-absent-${identifier//[^[:alnum:]_-]/_}.tsv"

  while true; do
    if collect_ax_frames >"$probe_file" 2>"$probe_file.err" &&
      ! awk -F $'\t' -v wanted="$identifier" '$1 == wanted { found = 1 } END { exit(found ? 0 : 1) }' "$probe_file"; then
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: AX identifier stayed visible: $identifier" >&2
      return 1
    fi
    sleep 0.2
  done
}

click_ax_identifier() {
  local identifier="$1"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))

  while true; do
    if wait_for_visible_windows >/dev/null 2>&1 &&
      "$AX_PRESS_ELEMENT_HELPER_BINARY" "$app_pid" "$identifier"; then
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: AXPress failed for identifier: $identifier" >&2
      return 1
    fi
    activate_app
    sleep 0.2
  done
}
click_sidebar_destination_by_coordinate() {
  local destination_identifier="$1"
  local window_id window_x window_y window_width window_height destination_index target_x target_y

  wait_for_window_metadata
  read -r window_id window_x window_y window_width window_height <"$WINDOW_METADATA_FILE"

  case "$destination_identifier" in
    sidebar-destination-inbox)
      destination_index=0
      ;;
    sidebar-destination-today)
      destination_index=1
      ;;
    sidebar-destination-projects)
      destination_index=2
      ;;
    sidebar-destination-schedule)
      destination_index=3
      ;;
    sidebar-destination-completed)
      destination_index=4
      ;;
    *)
      echo "BLOCKER: no coordinate fallback for sidebar destination: $destination_identifier" >&2
      return 1
      ;;
  esac

  # AXPress remains primary. The fallback uses measured window bounds plus the
  # fixed custom-sidebar geometry so it cannot silently target removed List rows.
  target_x=$((window_x + SIDEBAR_DESTINATION_ROW_CENTER_X_OFFSET_PX))
  target_y=$((window_y + SIDEBAR_DESTINATION_FIRST_ROW_CENTER_Y_OFFSET_PX + destination_index * SIDEBAR_DESTINATION_ROW_STRIDE_PX))
  /usr/bin/osascript - "$app_pid" "$target_x" "$target_y" <<'APPLESCRIPT' >/dev/null
on run argv
  set appPID to item 1 of argv as integer
  set targetX to (item 2 of argv) as integer
  set targetY to (item 3 of argv) as integer
  tell application "System Events"
    set matchingProcesses to application processes whose unix id is appPID
    if (count of matchingProcesses) is 0 then error "process missing"
    set targetProcess to item 1 of matchingProcesses
    tell targetProcess
      set frontmost to true
      if exists window 1 then
        try
          perform action "AXRaise" of window 1
        end try
      end if
    end tell
    click at {targetX, targetY}
  end tell
end run
APPLESCRIPT
}

assert_sidebar_destination_window_size_stable() {
  local label="$1"
  local destination_identifier="$2"
  local destination_label="$3"
  local workflow_identifier="$4"
  local before_size after_size

  before_size="$(window_size_key)"
  click_sidebar_destination "$destination_identifier" "$destination_label"
  wait_for_ax_identifier "$workflow_identifier"
  after_size="$(window_size_key)"

  if [[ "$after_size" != "$before_size" ]]; then
    echo "BLOCKER: Project Board window size changed after selecting $destination_identifier: before=$before_size after=$after_size" >&2
    return 1
  fi

  printf "OK: Project Board window size stayed %s after selecting %s\n" "$after_size" "$destination_identifier"
  printf -- '- `%s` kept window size `%s` after `%s`\n' "$label" "$after_size" "$destination_identifier" >>"$SUMMARY_FILE"
}

assert_ax_destination_window_size_stable() {
  local label="$1"
  local destination_identifier="$2"
  local workflow_identifier="$3"
  local before_size after_size

  before_size="$(window_size_key)"
  click_ax_identifier "$destination_identifier"
  wait_for_ax_identifier "$workflow_identifier"
  after_size="$(window_size_key)"

  if [[ "$after_size" != "$before_size" ]]; then
    echo "BLOCKER: Project Board window size changed after selecting $destination_identifier: before=$before_size after=$after_size" >&2
    return 1
  fi

  printf "OK: Project Board window size stayed %s after selecting %s\n" "$after_size" "$destination_identifier"
  printf -- '- `%s` kept window size `%s` after `%s`\n' "$label" "$after_size" "$destination_identifier" >>"$SUMMARY_FILE"
}

capture_layout_screenshot() {
  local label="$1"
  local offset_label="$2"
  local window_id window_x window_y window_width window_height
  wait_for_window_metadata
  read -r window_id window_x window_y window_width window_height <"$WINDOW_METADATA_FILE"
  local screenshot_path="$LAYOUT_STABILITY_OUTPUT_DIR/${label}-${offset_label}.png"
  /usr/sbin/screencapture -x -l "$window_id" "$screenshot_path"
  if [[ ! -s "$screenshot_path" ]]; then
    echo "BLOCKER: layout stability screenshot was not written: $screenshot_path" >&2
    return 1
  fi
}

collect_ax_frames() {
  local window_id window_x window_y window_width window_height
  wait_for_window_metadata
  read -r window_id window_x window_y window_width window_height <"$WINDOW_METADATA_FILE"
  "$AX_FRAME_HELPER_BINARY" "$app_pid" "$window_x" "$window_y" "$window_width" "$window_height"
}

collect_ax_frames_with_timeout() {
  local frame_file="$1"
  local err_file="$2"
  local timeout_marker="$err_file.timeout"
  local collect_pid watchdog_pid status
  rm -f "$timeout_marker"

  collect_ax_frames >"$frame_file" 2>"$err_file" &
  collect_pid=$!
  # Some macOS AX traversals hang instead of returning an error when SwiftUI is
  # rebuilding a large subtree. The watchdog preserves a bounded smoke test and
  # leaves the timeout cause in the per-sample artifact for triage.
  (
    sleep "$LAYOUT_STABILITY_AX_COLLECTION_TIMEOUT_SECONDS"
    if kill -0 "$collect_pid" >/dev/null 2>&1; then
      printf 'BLOCKER: layout AX frame collection timed out after %ss\n' "$LAYOUT_STABILITY_AX_COLLECTION_TIMEOUT_SECONDS" >>"$err_file"
      : >"$timeout_marker"
      kill "$collect_pid" >/dev/null 2>&1 || true
      sleep 1
      kill -9 "$collect_pid" >/dev/null 2>&1 || true
    fi
  ) &
  watchdog_pid=$!

  set +e
  wait "$collect_pid" 2>/dev/null
  status=$?
  set -e

  kill "$watchdog_pid" >/dev/null 2>&1 || true
  wait "$watchdog_pid" >/dev/null 2>&1 || true

  if [[ -f "$timeout_marker" ]]; then
    rm -f "$timeout_marker"
    return 124
  fi
  return "$status"
}

filter_ax_frames_to_window() {
  local frame_file="$1"
  local filtered_file="${frame_file}.in-window.$$"
  local window_id window_x window_y window_width window_height

  wait_for_window_metadata
  read -r window_id window_x window_y window_width window_height <"$WINDOW_METADATA_FILE"

  # SwiftUI can retain stale accessibility nodes from an earlier hosting
  # geometry while publishing the current nodes in the same traversal. Keep
  # only positive frames inside the PID-owned visible window, then deduplicate
  # identical rows. A genuinely clipped required region is removed and fails
  # the required-identifier check below instead of becoming false evidence.
  awk -F $'\t' \
    -v winX="$window_x" \
    -v winY="$window_y" \
    -v winW="$window_width" \
    -v winH="$window_height" \
    -v tolerance="$LAYOUT_STABILITY_CLIPPING_TOLERANCE_PX" '
      {
        x = $2 + 0
        y = $3 + 0
        width = $4 + 0
        height = $5 + 0
        if ($6 == "overlay" ||
          (width > 0 && height > 0 &&
          x >= winX - tolerance && y >= winY - tolerance &&
          x + width <= winX + winW + tolerance &&
          y + height <= winY + winH + tolerance)) {
          if (!seen[$0]++) {
            print
          }
        }
      }
    ' "$frame_file" >"$filtered_file"

  if [[ ! -s "$filtered_file" ]]; then
    rm -f "$filtered_file"
    echo "BLOCKER: no in-window AX frames remained after binding layout evidence to the visible PID-owned window" >&2
    return 1
  fi
  mv "$filtered_file" "$frame_file"
}

write_summary_header() {
  {
    printf '%s\n' '# Layout Stability Smoke'
    printf '\n'
    printf 'Generated at: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf '%s\n' 'Output artifact: `layout-stability`'
    printf 'Frame delta threshold: `%spx`\n' "$LAYOUT_STABILITY_FRAME_DELTA_THRESHOLD_PX"
    printf 'Clipping tolerance: `%spx`\n' "$LAYOUT_STABILITY_CLIPPING_TOLERANCE_PX"
    printf '\n'
    printf '%s\n' '## Samples'
  } >"$SUMMARY_FILE"
}

require_ax_identifiers() {
  local frame_file="$1"
  shift || true
  local required_identifiers=("$@")
  local missing=0
  local identifier
  if [[ "${#required_identifiers[@]}" -eq 0 ]]; then
    required_identifiers=("${REQUIRED_AX_IDENTIFIERS[@]}")
  fi
  for identifier in "${required_identifiers[@]}"; do
    if ! awk -F $'\t' -v wanted="$identifier" '$1 == wanted { found = 1 } END { exit(found ? 0 : 1) }' "$frame_file"; then
      printf 'BLOCKER: required AX identifier missing: %s\n' "$identifier" >&2
      missing=$((missing + 1))
    fi
  done
  if (( missing > 0 )); then
    printf 'Observed AX identifiers were written to %s\n' "$frame_file" >&2
    return 1
  fi
}

has_required_ax_identifiers() {
  local frame_file="$1"
  shift || true
  local required_identifiers=("$@")
  local identifier
  if [[ "${#required_identifiers[@]}" -eq 0 ]]; then
    required_identifiers=("${REQUIRED_AX_IDENTIFIERS[@]}")
  fi
  for identifier in "${required_identifiers[@]}"; do
    if ! awk -F $'\t' -v wanted="$identifier" '$1 == wanted { found = 1 } END { exit(found ? 0 : 1) }' "$frame_file"; then
      return 1
    fi
  done
}

wait_for_required_layout_subjects() {
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local probe_file="$LAYOUT_STABILITY_OUTPUT_DIR/required-identifiers-probe.tsv"

  while true; do
    if collect_ax_frames >"$probe_file" 2>"$LAYOUT_STABILITY_OUTPUT_DIR/required-identifiers-probe.err" &&
      has_required_ax_identifiers "$probe_file"; then
      return 0
    fi

    if [[ "$SECONDS" -ge "$deadline" ]]; then
      require_ax_identifiers "$probe_file"
      return 1
    fi
    sleep 1
  done
}

assert_no_negative_or_overlapping_frames() {
  local label="$1"
  local frame_file="$2"
  shift 2 || true
  local required_identifiers=("$@")
  local window_id window_x window_y window_width window_height required_list
  if [[ "${#required_identifiers[@]}" -eq 0 ]]; then
    required_identifiers=("${REQUIRED_AX_IDENTIFIERS[@]}")
  fi

  wait_for_window_metadata
  read -r window_id window_x window_y window_width window_height <"$WINDOW_METADATA_FILE"
  required_list="$(printf '%s,' "${required_identifiers[@]}")"

  # Body regions are the only sibling areas that must not overlap. Header is a
  # full-width bar by design, so it is clipped-checked but excluded from overlap.
  awk -F $'\t' \
    -v label="$label" \
    -v frameFile="$frame_file" \
    -v winX="$window_x" \
    -v winY="$window_y" \
    -v winW="$window_width" \
    -v winH="$window_height" \
    -v threshold="$LAYOUT_STABILITY_FRAME_DELTA_THRESHOLD_PX" \
    -v clipTolerance="$LAYOUT_STABILITY_CLIPPING_TOLERANCE_PX" \
    -v required="$required_list" '
      function right(id) { return x[id] + w[id] }
      function bottom(id) { return y[id] + h[id] }
      function isBodyRegion(id) {
        return id == "project-board-sidebar" ||
          id == "project-board-detail" ||
          id == "project-inspector" ||
          id == "task-inspector"
      }
      function overlaps(a, b) {
        return right(a) > x[b] + threshold &&
          right(b) > x[a] + threshold &&
          bottom(a) > y[b] + threshold &&
          bottom(b) > y[a] + threshold
      }
      BEGIN {
        split(required, requiredIds, ",")
        for (i in requiredIds) {
          if (requiredIds[i] != "") wanted[requiredIds[i]] = 1
        }
        winRight = winX + winW
        winBottom = winY + winH
      }
      ($1 in wanted) && !seen[$1] {
        id = $1
        x[id] = $2 + 0
        y[id] = $3 + 0
        w[id] = $4 + 0
        h[id] = $5 + 0
        scope[id] = $6
        seen[id] = 1

        if (scope[id] != "overlay" && (w[id] <= 0 || h[id] <= 0 ||
          x[id] < winX - clipTolerance || y[id] < winY - clipTolerance ||
          right(id) > winRight + clipTolerance || bottom(id) > winBottom + clipTolerance)) {
          printf "BLOCKER: layout frame is clipped outside window after %s: %s=(%d,%d %dx%d) window=(%d,%d %dx%d) file=%s\n",
            label, id, x[id], y[id], w[id], h[id], winX, winY, winW, winH, frameFile > "/dev/stderr"
          failed = 1
        }

        if (scope[id] != "overlay" && isBodyRegion(id)) {
          body[++bodyCount] = id
        }
      }
      END {
        for (i = 1; i <= bodyCount; i++) {
          for (j = i + 1; j <= bodyCount; j++) {
            a = body[i]
            b = body[j]
            if (overlaps(a, b)) {
              printf "BLOCKER: layout frame overlaps after %s: %s=(%d,%d %dx%d) %s=(%d,%d %dx%d) file=%s\n",
                label, a, x[a], y[a], w[a], h[a], b, x[b], y[b], w[b], h[b], frameFile > "/dev/stderr"
              failed = 1
            }
          }
        }
        exit failed ? 8 : 0
      }
    ' "$frame_file"
}

collect_layout_sample_frames() {
  local label="$1"
  local offset_ms="$2"
  local frame_file="$3"
  shift 3 || true
  local required_identifiers=("$@")
  local attempt=0
  if [[ "${#required_identifiers[@]}" -eq 0 ]]; then
    required_identifiers=("${REQUIRED_AX_IDENTIFIERS[@]}")
  fi

  while true; do
    # AX can briefly report zero windows immediately after toolbar-driven layout
    # mutations. We wait only for the real app window to be visible; there is no
    # fixed delay before t=0 frame collection, so layout jumps are still exposed.
    if ! wait_for_visible_windows; then
      printf 'BLOCKER: failed to collect layout AX frames after %s at t=%sms because the app window was not visible\n' "$label" "$offset_ms" >&2
      return 1
    fi
    if ! collect_ax_frames_with_timeout "$frame_file" "$frame_file.err"; then
      activate_app
      if ! wait_for_visible_windows; then
        printf 'BLOCKER: failed to collect layout AX frames after %s at t=%sms because the app window did not recover\n' "$label" "$offset_ms" >&2
        sed -n '1,20p' "$frame_file.err" >&2 || true
        return 1
      fi
      if ! collect_ax_frames_with_timeout "$frame_file" "$frame_file.err"; then
        printf 'BLOCKER: failed to collect layout AX frames after %s at t=%sms\n' "$label" "$offset_ms" >&2
        sed -n '1,20p' "$frame_file.err" >&2 || true
        return 1
      fi
    fi

    if ! filter_ax_frames_to_window "$frame_file"; then
      return 1
    fi

    if has_required_ax_identifiers "$frame_file" "${required_identifiers[@]}"; then
      return 0
    fi

    if (( attempt >= LAYOUT_STABILITY_AX_IDENTIFIER_RETRY_COUNT )); then
      require_ax_identifiers "$frame_file" "${required_identifiers[@]}"
      return 1
    fi

    # SwiftUI can momentarily expose child controls while omitting the parent
    # container AXIdentifier even though the visible layout is stable. Retry the
    # AX traversal itself, not the window mutation, so real frame jumps still
    # fail through the subsequent delta and clipping checks.
    attempt=$((attempt + 1))
    printf 'INFO: required AX identifiers missing after %s at t=%sms; retrying AX collection (%d/%d)\n' \
      "$label" "$offset_ms" "$attempt" "$LAYOUT_STABILITY_AX_IDENTIFIER_RETRY_COUNT" >&2
    sleep "$(awk -v ms="$LAYOUT_STABILITY_AX_IDENTIFIER_RETRY_DELAY_MS" 'BEGIN { printf "%.3f", ms / 1000 }')"
  done
}

sample_layout_frames() {
  local label="$1"
  shift || true
  local required_identifiers=("$@")
  local sample_index=0
  local previous_offset_ms=0
  local offset_ms sleep_ms frame_file
  if [[ "${#required_identifiers[@]}" -eq 0 ]]; then
    required_identifiers=("${REQUIRED_AX_IDENTIFIERS[@]}")
  fi

  for offset_ms in "${SAMPLE_OFFSETS_MS[@]}"; do
    if (( offset_ms > 0 )); then
      sleep_ms=$((offset_ms - previous_offset_ms))
      sleep "$(awk -v ms="$sleep_ms" 'BEGIN { printf "%.3f", ms / 1000 }')"
    fi

    frame_file="$LAYOUT_STABILITY_OUTPUT_DIR/${label}-t=${offset_ms}ms.tsv"
    if ! collect_layout_sample_frames "$label" "$offset_ms" "$frame_file" "${required_identifiers[@]}"; then
      return 1
    fi
    if ! capture_layout_screenshot "$label" "t=${offset_ms}ms"; then
      return 1
    fi

    # The first sample is intentionally taken at t=0ms so transient layout
    # correction cannot be hidden behind a delayed runloop retry.
    awk -F $'\t' -v label="$label" -v sample="$sample_index" -v offset="t=${offset_ms}ms" '
      $1 == "project-board-command-palette" ||
      $1 == "project-board-detail" ||
      $1 == "project-board-sidebar" ||
      $1 == "project-inspector" ||
      $1 == "task-inspector" {
        print label "\t" sample "\t" offset "\t" $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5
      }
    ' "$frame_file" >>"$SAMPLES_FILE"

    if ! assert_no_negative_or_overlapping_frames "$label" "$frame_file" "${required_identifiers[@]}"; then
      return 1
    fi

    printf -- '- `%s` sample %s (`t=%sms`) -> `%s`\n' "$label" "$sample_index" "$offset_ms" "${frame_file##*/}" >>"$SUMMARY_FILE"
    sample_index=$((sample_index + 1))
    previous_offset_ms="$offset_ms"
  done
}

assert_layout_stable() {
  local label="$1"
  shift || true
  local required_identifiers=("$@")
  local max_delta
  if [[ "${#required_identifiers[@]}" -eq 0 ]]; then
    required_identifiers=("${REQUIRED_AX_IDENTIFIERS[@]}")
  fi
  if ! sample_layout_frames "$label" "${required_identifiers[@]}"; then
    write_json_artifacts
    echo "BLOCKER: layout structural guard failed after $label" >&2
    echo "See $SAMPLES_FILE, $SAMPLES_JSON_FILE, $DIFF_FILE, and $DIFF_JSON_FILE" >&2
    return 1
  fi

  max_delta="$(
    awk -F $'\t' -v label="$label" -v threshold="$LAYOUT_STABILITY_FRAME_DELTA_THRESHOLD_PX" '
      function abs(value) { return value < 0 ? -value : value }
      $1 == label {
        key = $4
        if ($2 == 0) {
          baseX[key] = $5
          baseY[key] = $6
          baseW[key] = $7
          baseH[key] = $8
          baseSeen[key] = 1
          next
        }
        if (!(key in baseSeen)) {
          printf "BLOCKER: layout baseline sample missing after %s for %s before %s\n",
            label, key, $3 > "/dev/stderr"
          failed = 1
          next
        }
        dx = abs($5 - baseX[key])
        dy = abs($6 - baseY[key])
        dw = abs($7 - baseW[key])
        dh = abs($8 - baseH[key])
        delta = dx
        if (dy > delta) delta = dy
        if (dw > delta) delta = dw
        if (dh > delta) delta = dh
        if (delta > maxDelta) maxDelta = delta
        print label "\t" $3 "\t" key "\t" dx "\t" dy "\t" dw "\t" dh "\t" delta >> diffFile
        if (delta > threshold) failed = 1
      }
      END {
        printf "%d\n", maxDelta
        if (failed) exit 9
      }
    ' diffFile="$DIFF_FILE" "$SAMPLES_FILE"
  )" || {
    write_json_artifacts
    echo "BLOCKER: layout frame delta exceeded ${LAYOUT_STABILITY_FRAME_DELTA_THRESHOLD_PX}px after $label" >&2
    echo "See $SAMPLES_FILE, $SAMPLES_JSON_FILE, $DIFF_FILE, and $DIFF_JSON_FILE" >&2
    return 1
  }

  printf "OK: layout frame delta stayed within %spx after %s (max=%spx)\n" "$LAYOUT_STABILITY_FRAME_DELTA_THRESHOLD_PX" "$label" "$max_delta"
  printf -- '- `%s` max delta: `%spx`\n' "$label" "$max_delta" >>"$SUMMARY_FILE"
}

click_sidebar_toggle() {
  /usr/bin/osascript - "$app_pid" <<'APPLESCRIPT' >/dev/null
on run argv
  set appPID to item 1 of argv as integer
  tell application "System Events"
    set matchingProcesses to application processes whose unix id is appPID
    if (count of matchingProcesses) is 0 then error "process missing"
    set targetProcess to item 1 of matchingProcesses
    tell targetProcess
      tell toolbar 1 of window 1
        click (first button whose value of attribute "AXIdentifier" is "project-board-sidebar-toggle")
      end tell
    end tell
  end tell
end run
APPLESCRIPT
}

trap cleanup EXIT

write_summary_header
prepare_ax_helpers
prepare_layout_candidate
launch_layout_candidate
wait_for_required_layout_subjects

assert_layout_stable "initial"

click_sidebar_toggle
assert_layout_stable "sidebar-hidden" "project-board-command-palette" "project-board-detail"

click_sidebar_toggle
assert_layout_stable "sidebar-restored"

set_project_board_window_size "$LAYOUT_STABILITY_WINDOW_COMPACT_WIDTH" "$LAYOUT_STABILITY_WINDOW_MIN_HEIGHT"
wait_for_ax_identifier_absent "project-inspector"
assert_layout_stable "inspector-compact-closed"

set_project_board_window_size \
  "$LAYOUT_STABILITY_WINDOW_BELOW_MIN_WIDTH" \
  "$LAYOUT_STABILITY_WINDOW_MIN_HEIGHT" \
  "$LAYOUT_STABILITY_WINDOW_MIN_WIDTH"
wait_for_ax_identifier_absent "project-inspector"
assert_layout_stable "window-minimum-closed"
assert_window_minimum_width "closed"

set_project_board_window_size "$LAYOUT_STABILITY_WINDOW_CANONICAL_WIDTH" "$LAYOUT_STABILITY_WINDOW_MIN_HEIGHT"
wait_for_ax_identifier_absent "project-inspector"
assert_layout_stable "inspector-canonical-closed"

set_project_board_window_size "$LAYOUT_STABILITY_WINDOW_CANONICAL_WIDTH" "$LAYOUT_STABILITY_WINDOW_BELOW_MIN_HEIGHT"
wait_for_ax_identifier_absent "project-inspector"
assert_window_content_minimum "closed"
assert_layout_stable "content-minimum-closed"

click_ax_identifier "project-header-open-inspector"
wait_for_ax_identifier "project-inspector"
assert_layout_stable "inspector-explicit-open" "project-board-command-palette" "project-board-detail" "project-board-sidebar" "project-inspector"

set_project_board_window_size "$LAYOUT_STABILITY_WINDOW_CANONICAL_WIDTH" "$LAYOUT_STABILITY_WINDOW_BELOW_MIN_HEIGHT"
wait_for_ax_identifier "project-inspector"
assert_window_content_minimum "open"
assert_layout_stable "content-minimum-open" "project-board-command-palette" "project-board-detail" "project-board-sidebar" "project-inspector"

set_project_board_window_size \
  "$LAYOUT_STABILITY_WINDOW_BELOW_MIN_WIDTH" \
  "$LAYOUT_STABILITY_WINDOW_MIN_HEIGHT" \
  "$LAYOUT_STABILITY_WINDOW_MIN_WIDTH"
wait_for_ax_identifier "project-inspector"
assert_layout_stable "window-minimum-open" "project-board-command-palette" "project-board-detail" "project-board-sidebar" "project-inspector"
assert_window_minimum_width "open"

set_project_board_window_size "$LAYOUT_STABILITY_WINDOW_CANONICAL_WIDTH" "$LAYOUT_STABILITY_WINDOW_MIN_HEIGHT"
click_ax_identifier "project-inspector-close"
wait_for_ax_identifier_absent "project-inspector"
assert_layout_stable "inspector-explicit-close"

click_ax_identifier "task-card-open-details"
wait_for_ax_identifier "task-inspector"
wait_for_ax_identifier_absent "project-inspector"
assert_layout_stable "task-inspector-explicit-open" "project-board-command-palette" "project-board-detail" "project-board-sidebar" "task-inspector"
click_ax_identifier "task-inspector-close"
wait_for_ax_identifier_absent "task-inspector"
assert_layout_stable "task-inspector-explicit-close"

# Wide-window phases are a product contract, not a value to silently clamp to
# the hosted desktop. Preserve the earlier compact/canonical evidence, then
# classify an undersized work area as runner capability before AX retries can
# misreport the host limit as an app regression.
if [[ "$LAYOUT_STABILITY_VISIBLE_FRAME_WIDTH" -gt 0 && "$LAYOUT_STABILITY_VISIBLE_FRAME_HEIGHT" -gt 0 ]]; then
  require_layout_display_capacity
fi

set_project_board_window_size "$LAYOUT_STABILITY_WINDOW_STANDARD_WIDTH" "$LAYOUT_STABILITY_WINDOW_STANDARD_HEIGHT"
assert_layout_stable "inspector-wide-closed"
click_ax_identifier "project-header-open-inspector"
wait_for_ax_identifier "project-inspector"
assert_layout_stable "inspector-wide-open" "project-board-command-palette" "project-board-detail" "project-board-sidebar" "project-inspector"

# A native SwiftUI inspector contributes its own AppKit minimum width, so
# close it through the user-visible control before exercising the compact
# window contract. Compact inspector behavior is covered above by the sheet
# open/close phases; this phase measures the subsequent resize itself.
click_ax_identifier "project-inspector-close"
wait_for_ax_identifier_absent "project-inspector"
set_project_board_window_size "$LAYOUT_STABILITY_WINDOW_CANONICAL_WIDTH" "$LAYOUT_STABILITY_WINDOW_MIN_HEIGHT"
assert_layout_stable "inspector-resize-hidden"

set_project_board_window_size "$LAYOUT_STABILITY_WINDOW_STANDARD_WIDTH" "$LAYOUT_STABILITY_WINDOW_STANDARD_HEIGHT"
wait_for_ax_identifier_absent "project-inspector"
assert_layout_stable "inspector-wide-stays-closed"

set_project_board_window_size "$LAYOUT_STABILITY_WINDOW_WIDE_WIDTH" "$LAYOUT_STABILITY_WINDOW_WIDE_HEIGHT"
assert_layout_stable "window-wide"

assert_sidebar_destination_window_size_stable "destination-inbox" "sidebar-destination-inbox" "Inbox" "inbox-workflow"
assert_sidebar_destination_window_size_stable "destination-schedule" "sidebar-destination-schedule" "Schedule" "schedule-workflow"
assert_sidebar_destination_window_size_stable "destination-completed" "sidebar-destination-completed" "Completed" "done-workflow"
assert_ax_destination_window_size_stable "destination-review-assistant-queue" "review-destination-assistant-queue" "assistant-queue-workflow"
assert_sidebar_destination_window_size_stable "destination-today" "sidebar-destination-today" "Today" "today-workflow"

write_json_artifacts

{
  printf '\n'
  printf '%s\n' '## Artifacts'
  printf -- '- `samples.tsv`\n'
  printf -- '- `samples.json`\n'
  printf -- '- `diff.tsv`\n'
  printf -- '- `diff.json`\n'
  printf -- '- `window-resize-attempts.tsv`\n'
  printf '\n'
  printf '%s\n' 'Status: passed'
} >>"$SUMMARY_FILE"

printf "OK: layout stability smoke passed; artifacts written to %s\n" "$LAYOUT_STABILITY_OUTPUT_DIR"
