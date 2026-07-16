#!/usr/bin/env bash
set -euo pipefail

# Exercises the normal ProjectBoardView route with an isolated local database.
# This intentionally does not use launch recovery: a healthy production route
# must publish the real header and Today workflow without a recovery-only view.

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
SQLITE3="${SQLITE3:-sqlite3}"
SQLITE_BUSY_TIMEOUT_MS="${SOLOPM_RUNTIME_TODAY_SQLITE_BUSY_TIMEOUT_MS:-5000}"
RUNTIME_TIMEOUT_SECONDS="${SOLOPM_RUNTIME_TODAY_PRODUCTION_ROUTE_TIMEOUT_SECONDS:-30}"
RUNTIME_WINDOW_ATTEMPTS=2
CPU_CONVERGENCE_TIMEOUT_SECONDS="${SOLOPM_RUNTIME_TODAY_CPU_CONVERGENCE_TIMEOUT_SECONDS:-10}"
CPU_SAMPLE_INTERVAL_SECONDS=1
REQUIRED_CONSECUTIVE_CPU_SAMPLES=3
MAX_CPU_PERCENT=20
MAX_TOOLBAR_LAYOUT_DEPTH="${SOLOPM_RUNTIME_TODAY_MAX_TOOLBAR_LAYOUT_DEPTH:-1}"
WINDOW_WIDTH="${SOLOPM_RUNTIME_TODAY_WINDOW_WIDTH:-1024}"
WINDOW_HEIGHT="${SOLOPM_RUNTIME_TODAY_WINDOW_HEIGHT:-760}"
FIXTURES=("empty" "small")
LOCALES=("english" "japanese")
KEEP_ARTIFACTS="${SOLOPM_RUNTIME_TODAY_PRODUCTION_ROUTE_KEEP_ARTIFACTS:-0}"
ARTIFACT_ROOT="${SOLOPM_RUNTIME_TODAY_PRODUCTION_ROUTE_ARTIFACT_DIR:-$ROOT_DIR/.tmp/runtime-today-production-route}"
AX_HELPERS="${AX_HELPERS:-$ROOT_DIR/script/ui_accessibility_smoke_helpers.sh}"
AX_PRESS_ELEMENT_HELPER="${AX_PRESS_ELEMENT_HELPER:-$ROOT_DIR/script/ui_evidence_ax_press_element.swift}"
AX_IDENTIFIER_COUNT_HELPER="${AX_IDENTIFIER_COUNT_HELPER:-$ROOT_DIR/script/ui_evidence_ax_identifier_count.swift}"

if [[ ! "$RUNTIME_TIMEOUT_SECONDS" =~ ^[0-9]+$ || "$RUNTIME_TIMEOUT_SECONDS" -lt 3 ]]; then
  echo "SOLOPM_RUNTIME_TODAY_PRODUCTION_ROUTE_TIMEOUT_SECONDS must be an integer of at least 3" >&2
  exit 2
fi

if [[ ! "$CPU_CONVERGENCE_TIMEOUT_SECONDS" =~ ^[0-9]+$ || "$CPU_CONVERGENCE_TIMEOUT_SECONDS" -lt 3 ]]; then
  echo "SOLOPM_RUNTIME_TODAY_CPU_CONVERGENCE_TIMEOUT_SECONDS must be an integer of at least 3" >&2
  exit 2
fi

if [[ ! "$MAX_TOOLBAR_LAYOUT_DEPTH" =~ ^[0-9]+$ ]]; then
  echo "SOLOPM_RUNTIME_TODAY_MAX_TOOLBAR_LAYOUT_DEPTH must be a non-negative integer" >&2
  exit 2
fi

if [[ ! "$SQLITE_BUSY_TIMEOUT_MS" =~ ^[1-9][0-9]*$ ]]; then
  echo "SOLOPM_RUNTIME_TODAY_SQLITE_BUSY_TIMEOUT_MS must be a positive integer" >&2
  exit 2
fi

if ! command -v "$SQLITE3" >/dev/null 2>&1; then
  echo "BLOCKER: sqlite3 is required for runtime Today production-route smoke" >&2
  exit 2
fi

if [[ ! -r "$AX_HELPERS" ]]; then
  echo "BLOCKER: AX helpers are unavailable: $AX_HELPERS" >&2
  exit 2
fi
if [[ ! -r "$AX_IDENTIFIER_COUNT_HELPER" ]]; then
  echo "BLOCKER: AX identifier count helper is unavailable: $AX_IDENTIFIER_COUNT_HELPER" >&2
  exit 2
fi

# shellcheck source=/dev/null
source "$AX_HELPERS"

# A localized title must be below the Today container, not merely elsewhere in
# another visible app window. This makes the language matrix a runtime check.
export SOLOPM_UI_EVIDENCE_AX_REQUIRE_IDENTIFIER_SUBTREE=1

mkdir -p "$ROOT_DIR/.tmp" "$ARTIFACT_ROOT"

app_pid=""
app_launch_pid=""
app_identity=""
app_launch_identity=""
case_artifact_dir=""
route_artifact_dir=""
case_home=""
case_cf_user_home=""
database_path=""
case_deadline=""
locale_label=""
expected_today_label=""
small_fixture_today_due_at=""
small_fixture_missed_due_at=""
seed_project_id=""
route_id=""
route_destination=""
route_sidebar_marker=""
route_content_marker=""
route_text=""
route_failure_category=""
route_failure_reason=""
route_start_day_key=""

terminate_app() {
  # A PID-scoped shutdown avoids terminating a developer's separately running
  # SoloPM instance while still guaranteeing each smoke launch is cleaned up.
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

sanitize_sample() {
  local output="$case_artifact_dir/diagnostic-sample.txt"
  [[ -n "${app_pid:-}" ]] || return 0
  command -v sample >/dev/null 2>&1 || return 0
  # `sample` is useful for a stalled main thread, but its raw report can embed
  # local paths. Retain symbols and remove slash-delimited values before saving.
  sample "$app_pid" 1 1 2>/dev/null | sed -E 's#/[[:graph:]]+#<path>#g' >"$output" || true
}

capture_sanitized_processes() {
  [[ -n "${app_pid:-}" ]] || return 0
  ps -p "$app_pid" -o pid=,ppid=,state=,%cpu=,comm= | awk -v app="$APP_NAME" '
    NF { printf "pid=%s ppid=%s state=%s cpu_percent=%s executable=%s\\n", $1, $2, $3, $4, app }
  ' >"$case_artifact_dir/sanitized-processes.txt" 2>/dev/null || true
}

capture_sanitized_windows() {
  [[ -n "${app_pid:-}" ]] || return 0
  /usr/bin/osascript - "$app_pid" <<'APPLESCRIPT' >"$case_artifact_dir/sanitized-windows.txt" 2>&1 || true
on run argv
  set appPID to (item 1 of argv) as integer
  tell application "System Events"
    set matchingProcesses to application processes whose unix id is appPID
    if (count of matchingProcesses) is 0 then return "pid=" & appPID & " process=missing windows=0"
    set targetProcess to item 1 of matchingProcesses
    tell targetProcess
      set output to "pid=" & appPID & " process=visible windows=" & (count of windows)
      repeat with windowIndex from 1 to count of windows
        set currentWindow to window windowIndex
        set windowSize to "unknown"
        try
          set windowSize to size of currentWindow as text
        end try
        set output to output & " window=" & windowIndex & " size=" & windowSize
      end repeat
      return output
    end tell
  end tell
end run
APPLESCRIPT
}

runtime_counter_value() {
  local counter_name="$1"
  # Do not persist raw unified logs: they can include local file paths or task
  # content. Only the numeric counter emitted by the launched PID is retained.
  /usr/bin/log show --style compact --last 2m --predicate "processID == $app_pid" 2>/dev/null \
    | /usr/bin/grep -Eo "${counter_name}=[0-9]+" \
    | /usr/bin/tail -n 1 \
    | /usr/bin/sed "s/^${counter_name}=//" || true
}

capture_runtime_route_diagnostics() {
  local preview_build_count
  local toolbar_layout_max_depth
  local current_day_key
  local allowed_preview_build_count=1
  local preview_build_reason="single-day-route"
  preview_build_count="$(runtime_counter_value 'solopm.dailyPlanningPreview.buildCount')"
  toolbar_layout_max_depth="$(runtime_counter_value 'solopm.toolbar.layout.maxDepth')"
  current_day_key="$(date '+%Y-%m-%d')"
  if [[ -n "$route_start_day_key" && "$current_day_key" != "$route_start_day_key" ]]; then
    # Today legitimately rebuilds once when the route crossed the local day boundary.
    # Keep the normal limit at one; only the observed midnight transition permits two.
    allowed_preview_build_count=2
    preview_build_reason="local-day-boundary-crossed"
  fi

  if [[ ! "$preview_build_count" =~ ^[0-9]+$ || ! "$toolbar_layout_max_depth" =~ ^[0-9]+$ ]]; then
    printf 'status=diagnostic-unavailable\npreview-build-count=%s\ntoolbar-layout-max-depth=%s\n' \
      "${preview_build_count:-missing}" "${toolbar_layout_max_depth:-missing}" \
      >"$case_artifact_dir/toolbar-recursion-diagnostic.txt"
    return 1
  fi

  printf 'status=measured\npreview-build-count=%s\nallowed-preview-build-count=%s\npreview-build-reason=%s\ntoolbar-layout-max-depth=%s\n' \
    "$preview_build_count" "$allowed_preview_build_count" "$preview_build_reason" "$toolbar_layout_max_depth" \
    >"$case_artifact_dir/toolbar-recursion-diagnostic.txt"
  printf '%s\n' "$preview_build_count" >"$case_artifact_dir/preview-build-count.txt"
  printf '%s\n' "$toolbar_layout_max_depth" >"$case_artifact_dir/toolbar-layout-max-depth.txt"

  [[ "$preview_build_count" -le "$allowed_preview_build_count" && "$toolbar_layout_max_depth" -le "$MAX_TOOLBAR_LAYOUT_DEPTH" ]]
}

capture_failure_artifact() {
  local reason="$1"
  mkdir -p "$case_artifact_dir/ax-probes"
  printf 'status=failed\nreason=%s\nfailure_category=%s\nfailure_reason=%s\nfixture=%s\nlocale=%s\nlanguage_preference=%s\nroute=%s\ndestination=%s\nsidebar_marker=%s\ncontent_marker=%s\n' \
    "$reason" "${route_failure_category:-unknown}" "${route_failure_reason:-$reason}" "${fixture:-unknown}" "${locale_label:-unknown}" "${locale:-unknown}" \
    "${route_id:-none}" "${route_destination:-none}" "${route_sidebar_marker:-none}" "${route_content_marker:-none}" >"$case_artifact_dir/summary.txt"
  capture_sanitized_processes
  capture_sanitized_windows
  capture_runtime_route_diagnostics || true
  sanitize_sample
}

cleanup() {
  terminate_app
}
trap cleanup EXIT INT TERM

remove_case_database_from_artifacts() {
  # Failure uploads need AX/process diagnostics, not the SQLite fixture. Even
  # isolated seed data is unnecessary binary payload in a public artifact.
  [[ -n "${database_path:-}" ]] || return 0
  rm -f "$database_path" "$database_path-shm" "$database_path-wal"
}

launch_app() {
  local locale="$1"
  local selected_destination="$2"
  terminate_app
  # Start from an empty environment so host API keys, proxy settings, and saved
  # smoke flags cannot supply credentials or alter this normal-route exercise.
  # The default Today route remains SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION="today";
  /usr/bin/env -i \
    PATH="$PATH" \
    TMPDIR="$case_artifact_dir/tmp" \
    HOME="$case_home" \
    CFFIXED_USER_HOME="$case_cf_user_home" \
    SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1 \
    SOLOPM_DATABASE_PATH="$database_path" \
    SOLOPM_LANGUAGE_PREFERENCE="$locale" \
    SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION="$selected_destination" \
    "$APP_BINARY" -ApplePersistenceIgnoreState YES >/dev/null 2>&1 &
  app_launch_pid=$!
  app_launch_identity="$(ax_wait_for_owned_process_identity "$app_launch_pid" "$APP_BINARY" 3)" || return 1
  app_pid=""
  app_identity=""
}

resolve_app_pid() {
  if app_pid="$(ax_wait_for_owned_app_pid "$app_launch_pid" "$APP_BINARY" "$RUNTIME_TIMEOUT_SECONDS")"; then
    app_identity="$(ax_wait_for_owned_process_identity "$app_pid" "$APP_BINARY" 3)" || return 1
    return 0
  fi
  app_pid=""
  return 1
}

wait_for_database_table() {
  local table="$1"
  local deadline=$((SECONDS + RUNTIME_TIMEOUT_SECONDS))
  while true; do
    if [[ -f "$database_path" ]] &&
      "$SQLITE3" -batch -bail -cmd ".timeout $SQLITE_BUSY_TIMEOUT_MS" "$database_path" \
        "SELECT name FROM sqlite_master WHERE type='table' AND name='$table';" 2>/dev/null | grep -Fx "$table" >/dev/null; then
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      return 1
    fi
    sleep 0.2
  done
}

wait_for_database_write_access() {
  [[ -f "$database_path" ]] || return 0
  local deadline=$((SECONDS + RUNTIME_TIMEOUT_SECONDS))
  while true; do
    # A successful immediate transaction proves the owned app has released its
    # SQLite writer before the next locale/route starts. This prevents a noisy
    # migration retry from being mistaken for a healthy deterministic launch.
    if "$SQLITE3" -batch -cmd ".timeout 250" "$database_path" "BEGIN IMMEDIATE; ROLLBACK;" >/dev/null 2>&1; then
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      ax_emit_failure_category "harness" "database-write-lock-timeout"
      echo "BLOCKER: isolated Today database remained write-locked after owned app shutdown" >&2
      return 1
    fi
    sleep 0.1
  done
}

seed_small_fixture() {
  local today_due_at
  local missed_due_at
  today_due_at="$(date '+%Y-%m-%dT12:00:00%z')"
  missed_due_at="$(date -v-1d '+%Y-%m-%dT12:00:00%z')"
  # Keep the exact local-noon value used for INSERT. Recomputing it after a
  # midnight boundary could verify a different calendar day than the fixture.
  small_fixture_today_due_at="$today_due_at"
  small_fixture_missed_due_at="$missed_due_at"
  if ! "$SQLITE3" -batch -bail -cmd ".timeout $SQLITE_BUSY_TIMEOUT_MS" "$database_path" <<SQL
BEGIN IMMEDIATE;
INSERT INTO projects (title, status, priority, deadline, workspace_path, tags_json, source_command, created_at, updated_at)
VALUES ('fixture-project-1', 'active', 'high', NULL, NULL, '[]', 'runtime-today-production-route', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
       ('fixture-project-2', 'active', 'medium', NULL, NULL, '[]', 'runtime-today-production-route', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
       ('fixture-project-3', 'active', 'low', NULL, NULL, '[]', 'runtime-today-production-route', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
INSERT INTO tasks (project_id, title, status, detail, due_at, completed_at, priority, source_command, created_at, updated_at)
VALUES ((SELECT id FROM projects WHERE source_command='runtime-today-production-route' AND title='fixture-project-1'), 'fixture-today-1', 'planned', NULL, '$today_due_at', NULL, 'high', 'runtime-today-production-route', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
       ((SELECT id FROM projects WHERE source_command='runtime-today-production-route' AND title='fixture-project-1'), 'fixture-today-2', 'in_progress', NULL, '$today_due_at', NULL, 'medium', 'runtime-today-production-route', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
       ((SELECT id FROM projects WHERE source_command='runtime-today-production-route' AND title='fixture-project-2'), 'fixture-later-1', 'backlog', NULL, NULL, NULL, 'low', 'runtime-today-production-route', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
       ((SELECT id FROM projects WHERE source_command='runtime-today-production-route' AND title='fixture-project-2'), 'fixture-done-1', 'completed', NULL, '$today_due_at', CURRENT_TIMESTAMP, 'low', 'runtime-today-production-route', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
       ((SELECT id FROM projects WHERE source_command='runtime-today-production-route' AND title='fixture-project-3'), 'fixture-today-3', 'planned', NULL, '$today_due_at', NULL, 'high', 'runtime-today-production-route', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
       ((SELECT id FROM projects WHERE source_command='runtime-today-production-route' AND title='fixture-project-3'), 'fixture-later-2', 'backlog', NULL, NULL, NULL, 'medium', 'runtime-today-production-route', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
       ((SELECT id FROM projects WHERE source_command='runtime-today-production-route' AND title='fixture-project-1'), 'fixture-catch-up-1', 'planned', NULL, '$missed_due_at', NULL, 'high', 'runtime-today-production-route', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
COMMIT;
SQL
  then
    return 1
  fi

  seed_project_id="$("$SQLITE3" -batch -bail -cmd ".timeout $SQLITE_BUSY_TIMEOUT_MS" "$database_path" "SELECT id FROM projects WHERE source_command='runtime-today-production-route' AND title='fixture-project-1' ORDER BY id DESC LIMIT 1;")" || return 1
}

verify_small_fixture_today_data() {
  local due_at="$1"
  local today_task_count
  today_task_count="$("$SQLITE3" "$database_path" "SELECT COUNT(*) FROM tasks WHERE source_command='runtime-today-production-route' AND due_at='$due_at' AND status IN ('planned', 'in_progress') AND completed_at IS NULL;")"
  [[ "$today_task_count" == "3" && "$seed_project_id" =~ ^[0-9]+$ ]]
}

verify_small_fixture_catch_up_data() {
  local due_at="$1"
  local missed_task_count
  missed_task_count="$("$SQLITE3" "$database_path" "SELECT COUNT(*) FROM tasks WHERE source_command='runtime-today-production-route' AND title='fixture-catch-up-1' AND due_at='$due_at' AND status IN ('planned', 'in_progress') AND completed_at IS NULL;")"
  [[ "$missed_task_count" == "1" ]]
}

locale_label_for() {
  case "$1" in
    english) printf '%s' "en" ;;
    japanese) printf '%s' "ja" ;;
    *) return 1 ;;
  esac
}

expected_today_label_for() {
  case "$1" in
    english) printf '%s' "Today" ;;
    japanese) printf '%s' "今日" ;;
    *) return 1 ;;
  esac
}

wait_for_marker_until() {
  local marker="$1"
  local required_text="$2"
  local deadline="$3"
  local probe_root="${route_artifact_dir:-$case_artifact_dir}"
  local probe_file="$probe_root/ax-probes/${marker}.txt"
  last_marker_probe_file="$probe_file"
  mkdir -p "$probe_root/ax-probes"
  while true; do
    if ax_wait_for_ax_identifier "$APP_NAME" "$marker" 1 "$ROOT_DIR" "$probe_file" "$required_text" "$app_pid"; then
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      return 1
    fi
  done
}

wait_for_required_markers() {
  wait_for_marker_until "project-board-command-palette" "" "$case_deadline"
  wait_for_marker_until "today-workflow" "$expected_today_label" "$case_deadline"
}

read_ax_identifier_counts() {
  local identifier_marker="$1"
  local output_file="$2"
  local error_file="$3"
  local helper_pid
  local watchdog_pid
  local status

  SOLOPM_UI_EVIDENCE_AX_MAX_NODES=9000 \
    /usr/bin/swift "$AX_IDENTIFIER_COUNT_HELPER" "$app_pid" "$identifier_marker" \
    >"$output_file" 2>"$error_file" &
  helper_pid=$!
  (
    sleep "$RUNTIME_TIMEOUT_SECONDS"
    kill "$helper_pid" >/dev/null 2>&1 || true
  ) &
  watchdog_pid=$!
  set +e
  wait "$helper_pid"
  status=$?
  set -e
  kill "$watchdog_pid" >/dev/null 2>&1 || true
  wait "$watchdog_pid" >/dev/null 2>&1 || true
  return "$status"
}

verify_today_action_contract() {
  local expected_primary_enabled=1
  local expected_catch_up_total=0
  local primary_output="$route_artifact_dir/primary-action-count.txt"
  local primary_error="$route_artifact_dir/primary-action-count.err"
  local catch_up_output="$route_artifact_dir/catch-up-count.txt"
  local catch_up_error="$route_artifact_dir/catch-up-count.err"

  [[ "$fixture" == "small" ]] && expected_catch_up_total=1

  if ! read_ax_identifier_counts "today-primary-action" "$primary_output" "$primary_error"; then
    cat "$primary_error" >&2
    return 1
  fi
  if ! grep -E "^total=[1-9][0-9]* enabled=[1-9][0-9]* actionable_enabled=${expected_primary_enabled}$" "$primary_output" >/dev/null; then
    echo "BLOCKER: Today must expose exactly one enabled prominent primary action for fixture=$fixture; got $(cat "$primary_output")" >&2
    return 1
  fi

  if ! read_ax_identifier_counts "today-catch-up-section" "$catch_up_output" "$catch_up_error"; then
    cat "$catch_up_error" >&2
    return 1
  fi
  local catch_up_pattern="^total=0 enabled=0 actionable_enabled=0$"
  if [[ "$expected_catch_up_total" -gt 0 ]]; then
    catch_up_pattern="^total=[1-9][0-9]* enabled=[1-9][0-9]* actionable_enabled=[0-9]+$"
  fi
  if ! grep -E "$catch_up_pattern" "$catch_up_output" >/dev/null; then
    echo "BLOCKER: Catch Up presence did not match fixture=$fixture; got $(cat "$catch_up_output")" >&2
    return 1
  fi
}

route_text_for() {
  local route="$1"
  case "$route:$locale_label" in
    inbox:en) printf '%s' "Inbox" ;;
    inbox:ja) printf '%s' "インボックス" ;;
    today:en) printf '%s' "Today" ;;
    today:ja) printf '%s' "今日" ;;
    projects:en) printf '%s' "Projects" ;;
    projects:ja) printf '%s' "プロジェクト" ;;
    review:en) printf '%s' "Review" ;;
    review:ja) printf '%s' "確認" ;;
    review-schedule:en) printf '%s' "Schedule" ;;
    review-schedule:ja) printf '%s' "予定" ;;
    review-completed:en) printf '%s' "Completed" ;;
    review-completed:ja) printf '%s' "完了" ;;
    review-automation:en) printf '%s' "Automation Activity" ;;
    review-automation:ja) printf '%s' "自動化アクティビティ" ;;
    review-assistant-queue:en) printf '%s' "Assistant Queue" ;;
    review-assistant-queue:ja) printf '%s' "アシスタントキュー" ;;
    project:*|inspector:*) printf '%s' "fixture-project-1" ;;
    *) return 1 ;;
  esac
}

record_route_evidence() {
  local status="$1"
  local category="$2"
  local reason="$3"
  local evidence_file="$case_artifact_dir/route-evidence.tsv"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$status" "$route_id" "$route_destination" "$route_sidebar_marker" "$route_content_marker" "$route_text" "$category" "$reason" >>"$evidence_file"
  {
    printf 'status=%s\nroute=%s\ndestination=%s\nsidebar_marker=%s\ncontent_marker=%s\ntext=%s\nfailure_category=%s\nfailure_reason=%s\n' \
      "$status" "$route_id" "$route_destination" "$route_sidebar_marker" "$route_content_marker" "$route_text" "$category" "$reason"
  } >"$route_artifact_dir/summary.txt"
}

fail_route() {
  route_failure_category="$1"
  local reason="${2:-route-${route_id}-${route_failure_category}}"
  route_failure_reason="$reason"
  ax_emit_failure_category "$route_failure_category" "$reason"
  printf 'failure_route=%s\nfailure_destination=%s\nfailure_sidebar_marker=%s\nfailure_content_marker=%s\n' \
    "$route_id" "$route_destination" "$route_sidebar_marker" "$route_content_marker" >&2
  record_route_evidence "failed" "$route_failure_category" "$reason"
  capture_failure_artifact "$reason"
  terminate_app
  remove_case_database_from_artifacts
  return 1
}

fail_case() {
  route_failure_category="$1"
  route_failure_reason="$2"
  ax_emit_failure_category "$route_failure_category" "$route_failure_reason"
  capture_failure_artifact "$route_failure_reason"
  terminate_app
  remove_case_database_from_artifacts
  return 1
}

set_owned_window_size() {
  local deadline=$((SECONDS + RUNTIME_TIMEOUT_SECONDS))
  while true; do
    if /usr/bin/osascript - "$app_pid" "$WINDOW_WIDTH" "$WINDOW_HEIGHT" <<'APPLESCRIPT' >/dev/null 2>&1
on run argv
  set appPID to item 1 of argv as integer
  set targetWidth to item 2 of argv as integer
  set targetHeight to item 3 of argv as integer
  tell application "System Events"
    set matchingProcesses to application processes whose unix id is appPID
    if (count of matchingProcesses) is 0 then error "pid-owned process missing"
    tell item 1 of matchingProcesses
      if not (exists window 1) then error "pid-owned window missing"
      set size of window 1 to {targetWidth, targetHeight}
      set actualSize to size of window 1
      if item 1 of actualSize is not targetWidth or item 2 of actualSize is not targetHeight then
        error "pid-owned window size mismatch"
      end if
    end tell
  end tell
end run
APPLESCRIPT
    then
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      return 1
    fi
    sleep 1
  done
}

launch_route_process_and_window() {
  local window_diagnostic="$1"
  route_failure_category=""

  if ! launch_app "$locale" "$route_destination"; then
    route_failure_category="launch"
    return 1
  fi
  if ! resolve_app_pid; then
    route_failure_category="launch"
    return 1
  fi
  if ! ax_wait_for_pid_owned_process "$APP_NAME" "$app_pid" "$RUNTIME_TIMEOUT_SECONDS" "$APP_BINARY"; then
    route_failure_category="launch"
    return 1
  fi
  if ! ax_wait_for_pid_owned_window "$APP_NAME" "$app_pid" "" "$RUNTIME_TIMEOUT_SECONDS" "$window_diagnostic" "$APP_BINARY"; then
    route_failure_category="$(ax_classify_window_failure "$window_diagnostic" "$app_pid")"
    return 1
  fi
  if ! set_owned_window_size; then
    route_failure_category="window"
    return 1
  fi
  return 0
}

launch_route_and_wait_for_markers() {
  local window_diagnostic="$1"

  if ! launch_route_process_and_window "$window_diagnostic"; then
    return 1
  fi
  if [[ -z "$app_pid" ]]; then
    route_failure_category="launch"
    return 1
  fi

  # Window publication and the first production-route markers form one
  # readiness unit. Hosted SwiftUI can briefly publish a real window before
  # its AX route subtree is queryable; only a window-classified failure gets
  # one clean relaunch below.
  case_deadline=$((SECONDS + RUNTIME_TIMEOUT_SECONDS))
  if ! wait_for_marker_until "project-board-command-palette" "" "$case_deadline"; then
    route_failure_category="$(ax_classify_marker_failure "$last_marker_probe_file" "$app_pid")"
    return 1
  fi
  if ! wait_for_marker_until "$route_sidebar_marker" "" "$case_deadline"; then
    route_failure_category="$(ax_classify_marker_failure "$last_marker_probe_file" "$app_pid")"
    return 1
  fi
  if ! wait_for_marker_until "$route_content_marker" "$route_text" "$case_deadline"; then
    route_failure_category="$(ax_classify_marker_failure "$last_marker_probe_file" "$app_pid")"
    return 1
  fi
  return 0
}

run_route() {
  route_id="$1"
  route_destination="$2"
  route_sidebar_marker="$3"
  route_content_marker="$4"
  route_text="$5"
  local keep_app_running="${6:-0}"
  route_artifact_dir="$case_artifact_dir/routes/$route_id"
  route_failure_category=""
  route_failure_reason=""
  rm -rf "$route_artifact_dir"
  mkdir -p "$route_artifact_dir/ax-probes"

  route_start_day_key="$(date '+%Y-%m-%d')"
  if ! launch_route_and_wait_for_markers "$route_artifact_dir/window-attempt-1.err"; then
    if [[ "$route_failure_category" != "window" ]]; then
      fail_route "$route_failure_category"
      return 1
    fi
    echo "INFO: retrying production route after window-classified readiness failure (attempt 2/$RUNTIME_WINDOW_ATTEMPTS)" >&2
    terminate_app
    if ! wait_for_database_write_access; then
      fail_route "harness" "database-write-lock-timeout"
      return 1
    fi
    sleep 1
    if ! launch_route_and_wait_for_markers "$route_artifact_dir/window-attempt-2.err"; then
      # A second failure is evidence, not a reason to keep rerunning. Preserve
      # its concrete launch/window/accessibility classification and fail closed.
      fail_route "$route_failure_category"
      return 1
    fi
  fi

  if [[ "$route_id" == "today" ]]; then
    if ! verify_today_action_contract; then
      fail_route "product-marker" "today-primary-or-catch-up-contract"
      return 1
    fi
    # Keep the existing Today acceptance contract: the production route must
    # settle below the CPU threshold and retain the toolbar/preview recursion
    # diagnostics after AX readiness, for both empty and seeded databases.
    case_deadline=$((SECONDS + CPU_CONVERGENCE_TIMEOUT_SECONDS))
    if ! cpu_convergence_gate; then
      fail_route "product-marker" "cpu-convergence-timeout"
      return 1
    fi
    if ! capture_runtime_route_diagnostics; then
      fail_route "product-marker" "runtime-route-diagnostics-failed"
      return 1
    fi
  fi

  record_route_evidence "passed" "none" "none"
  printf 'OK: route=%s destination=%s sidebar=%s content=%s text=%s\n' \
    "$route_id" "$route_destination" "$route_sidebar_marker" "$route_content_marker" "$route_text"
  if [[ "$keep_app_running" != "1" ]]; then
    terminate_app
    # Propagate the post-route write-lock probe. A swallowed failure here
    # would let `run_normal_routes || return 1` report a passed route while
    # the database is still held by the just-terminated app.
    if ! wait_for_database_write_access; then
      fail_route "harness" "database-write-lock-timeout"
      return 1
    fi
  fi
  return 0
}

navigate_to_seed_project() {
  local marker
  local required_text
  local project_row_identifier="project-sidebar-row-$seed_project_id"

  route_id="project"
  route_destination="project:$seed_project_id"
  route_sidebar_marker="project-board-sidebar"
  route_content_marker="project-board-detail"
  route_text="$(route_text_for "$route_id")"
  route_artifact_dir="$case_artifact_dir/routes/$route_id"
  route_failure_category=""
  route_failure_reason=""
  rm -rf "$route_artifact_dir"
  mkdir -p "$route_artifact_dir/ax-probes"

  # Project cold-launch restoration belongs to the dedicated state-restoration
  # gate. Prove the user path from the already-published Projects window here;
  # the same CI lane separately verifies project cold launch, CRUD, and layout.
  if ! /usr/bin/swift "$AX_PRESS_ELEMENT_HELPER" "$app_pid" "$project_row_identifier"; then
    fail_route "product-marker" "route-project-selection"
    return 1
  fi

  case_deadline=$((SECONDS + RUNTIME_TIMEOUT_SECONDS))
  for marker in "project-board-command-palette" "$route_sidebar_marker" "$route_content_marker"; do
    required_text=""
    [[ "$marker" == "$route_content_marker" ]] && required_text="$route_text"
    if ! wait_for_marker_until "$marker" "$required_text" "$case_deadline"; then
      route_failure_category="$(ax_classify_marker_failure "$last_marker_probe_file" "$app_pid")"
      fail_route "$route_failure_category"
      return 1
    fi
  done
  record_route_evidence "passed" "none" "none"
  printf 'OK: route=%s destination=%s sidebar=%s content=%s text=%s\n' \
    "$route_id" "$route_destination" "$route_sidebar_marker" "$route_content_marker" "$route_text"

  route_id="inspector"
  route_content_marker="project-inspector"
  route_text="$(route_text_for "$route_id")"
  route_artifact_dir="$case_artifact_dir/routes/$route_id"
  rm -rf "$route_artifact_dir"
  mkdir -p "$route_artifact_dir/ax-probes"
  if ! wait_for_marker_until "$route_content_marker" "$route_text" "$case_deadline"; then
    route_failure_category="$(ax_classify_marker_failure "$last_marker_probe_file" "$app_pid")"
    fail_route "$route_failure_category"
    return 1
  fi
  record_route_evidence "passed" "none" "none"
  printf 'OK: route=%s destination=%s sidebar=%s content=%s text=%s\n' \
    "$route_id" "$route_destination" "$route_sidebar_marker" "$route_content_marker" "$route_text"

  terminate_app
  # Same write-lock probe as `run_route`; its failure must reach the caller so
  # the seeded `navigate_to_seed_project` is not declared passed against a
  # still-locked database.
  if ! wait_for_database_write_access; then
    fail_route "harness" "database-write-lock-timeout"
    return 1
  fi
}

run_normal_routes() {
  local route_spec
  local route_destination_value
  local route_sidebar_marker_value
  local route_content_marker_value
  local keep_app_running
  local routes=(
    "inbox|inbox|sidebar-destination-inbox|inbox-workflow"
    "today|today|sidebar-destination-today|today-workflow"
    "review|primary:review|sidebar-destination-review|review-hub"
    "review-schedule|review:schedule|sidebar-destination-review|schedule-workflow"
    "review-completed|review:completed|sidebar-destination-review|done-workflow"
    "review-automation|review:automation|sidebar-destination-review|automation-activity-workflow"
    "review-assistant-queue|review:assistant-queue|sidebar-destination-review|assistant-queue-workflow"
    "projects|projects|sidebar-destination-projects|projects-portfolio-overview"
  )

  for route_spec in "${routes[@]}"; do
    IFS='|' read -r route_id route_destination_value route_sidebar_marker_value route_content_marker_value <<<"$route_spec"
    route_text="$(route_text_for "$route_id")"
    keep_app_running=0
    [[ "$route_id" == "projects" ]] && keep_app_running=1
    if ! run_route "$route_id" "$route_destination_value" "$route_sidebar_marker_value" "$route_content_marker_value" "$route_text" "$keep_app_running"; then
      return 1
    fi
  done
  # The state-restoration lane owns AX row pressing and Inspector drill-down.
  # This route smoke verifies that the typed project deep link still resolves
  # through the Projects top-level selection to the real project detail.
  run_route \
    "project" \
    "project:$seed_project_id" \
    "sidebar-destination-projects" \
    "project-board-detail" \
    "$(route_text_for "project")"
}

cpu_percent_for_app() {
  [[ -n "${app_pid:-}" ]] || return 1
  ps -o %cpu= -p "$app_pid" | awk 'NF { print $1; exit }'
}

cpu_convergence_gate() {
  local consecutive=0
  local sample_index=0
  local cpu_percent=""
  local elapsed=""
  printf 'sample\telapsed_seconds\tcpu_percent\tconsecutive_at_or_below_%s\n' "$MAX_CPU_PERCENT" >"$case_artifact_dir/cpu-samples.tsv"

  while [[ "$SECONDS" -le "$case_deadline" ]]; do
    sample_index=$((sample_index + 1))
    elapsed=$((CPU_CONVERGENCE_TIMEOUT_SECONDS - (case_deadline - SECONDS)))
    cpu_percent="$(cpu_percent_for_app || true)"
    if [[ "$cpu_percent" =~ ^[0-9]+([.][0-9]+)?$ ]] && awk -v cpu="$cpu_percent" -v max="$MAX_CPU_PERCENT" 'BEGIN { exit !(cpu <= max) }'; then
      consecutive=$((consecutive + 1))
    else
      consecutive=0
    fi
    printf '%s\t%s\t%s\t%s\n' "$sample_index" "$elapsed" "${cpu_percent:-missing}" "$consecutive" >>"$case_artifact_dir/cpu-samples.tsv"
    if [[ "$consecutive" -ge "$REQUIRED_CONSECUTIVE_CPU_SAMPLES" ]]; then
      return 0
    fi
    [[ "$SECONDS" -ge "$case_deadline" ]] && break
    sleep "$CPU_SAMPLE_INTERVAL_SECONDS"
  done
  return 1
}

run_case() {
  fixture="$1"
  locale="$2"
  locale_label="$(locale_label_for "$locale")"
  expected_today_label="$(expected_today_label_for "$locale")"
  case_artifact_dir="$ARTIFACT_ROOT/${fixture}-${locale_label}"
  case_home="$case_artifact_dir/home"
  case_cf_user_home="$case_artifact_dir/cf-user-home"
  database_path="$case_artifact_dir/SoloPM.sqlite"
  route_artifact_dir=""
  route_id=""
  route_destination=""
  route_sidebar_marker=""
  route_content_marker=""
  route_text=""
  route_failure_category=""
  route_failure_reason=""
  seed_project_id=""
  rm -rf "$case_artifact_dir"
  mkdir -p "$case_home/Library/Preferences" "$case_cf_user_home" "$case_artifact_dir/ax-probes" "$case_artifact_dir/tmp"

  # The first normal launch creates the schema. It uses the same isolated home,
  # database, and no-Keychain configuration as the measured launch.
  launch_app "$locale" "today"
  if ! resolve_app_pid || ! ax_wait_for_pid_owned_process "$APP_NAME" "$app_pid" "$RUNTIME_TIMEOUT_SECONDS" "$APP_BINARY"; then
    fail_case "launch" "database-bootstrap-launch-failed"
    return 1
  fi
  if ! wait_for_database_table "projects" || ! wait_for_database_table "tasks"; then
    fail_case "launch" "database-schema-timeout"
    return 1
  fi
  terminate_app
  if ! wait_for_database_write_access; then
    fail_case "harness" "database-write-lock-timeout"
    return 1
  fi

  if [[ "$fixture" == "small" ]]; then
    if ! seed_small_fixture; then
      fail_case "launch" "fixture-seed-failed"
      return 1
    fi
    if ! verify_small_fixture_today_data "$small_fixture_today_due_at"; then
      fail_case "launch" "fixture-today-data-missing"
      return 1
    fi
    if ! verify_small_fixture_catch_up_data "$small_fixture_missed_due_at"; then
      fail_case "launch" "fixture-catch-up-data-missing"
      return 1
    fi
  fi

  : >"$case_artifact_dir/route-evidence.tsv"
  printf 'status\troute\tdestination\tsidebar_marker\tcontent_marker\ttext\tfailure_category\tfailure_reason\n' >"$case_artifact_dir/route-evidence.tsv"
  if [[ "$fixture" == "small" ]]; then
    run_normal_routes || return 1
  else
    # The empty fixture preserves the original Today CPU/toolbar regression
    # gate. The seeded fixture covers the complete navigation matrix in en/ja.
    route_text="$(route_text_for "today")"
    run_route "today" "today" "sidebar-destination-today" "today-workflow" "$route_text" || return 1
  fi

  printf 'status=passed\nfixture=%s\nlocale=%s\nlanguage_preference=%s\n' "$fixture" "$locale_label" "$locale" >"$case_artifact_dir/summary.txt"
  if [[ "$KEEP_ARTIFACTS" != "1" ]]; then
    rm -rf "$case_artifact_dir"
  fi
  return 0
}

printf '== Runtime Today production-route smoke ==\n'
./script/build_and_run.sh --build-only

if [[ ! -x "$APP_BINARY" ]]; then
  echo "BLOCKER: app binary not found after build: $APP_BINARY" >&2
  exit 2
fi

for fixture in "${FIXTURES[@]}"; do
  for locale in "${LOCALES[@]}"; do
    if run_case "$fixture" "$locale"; then
      printf 'OK: Today production route fixture=%s locale=%s reached localized markers, CPU convergence, and runtime diagnostics\n' "$fixture" "$(locale_label_for "$locale")"
    else
      echo "BLOCKER: Today production route fixture=$fixture locale=$locale failed; artifact=$case_artifact_dir" >&2
      exit 1
    fi
  done
done

printf 'OK: runtime Today production-route smoke passed; empty/small × en/ja reached normal Today markers and CPU convergence\n'
