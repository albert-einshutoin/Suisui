#!/usr/bin/env bash
set -euo pipefail

# Exercises the normal ProjectBoard route with an isolated local database.  This
# intentionally does not use launch recovery: a healthy production route must
# publish the real header and Today workflow without a recovery-only view.

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
RUNTIME_TIMEOUT_SECONDS="${SOLOPM_RUNTIME_TODAY_PRODUCTION_ROUTE_TIMEOUT_SECONDS:-10}"
CPU_CONVERGENCE_TIMEOUT_SECONDS="${SOLOPM_RUNTIME_TODAY_CPU_CONVERGENCE_TIMEOUT_SECONDS:-10}"
CPU_SAMPLE_INTERVAL_SECONDS=1
REQUIRED_CONSECUTIVE_CPU_SAMPLES=3
MAX_CPU_PERCENT=20
MAX_TOOLBAR_LAYOUT_DEPTH="${SOLOPM_RUNTIME_TODAY_MAX_TOOLBAR_LAYOUT_DEPTH:-1}"
FIXTURES=("empty" "small")
LOCALES=("english" "japanese")
KEEP_ARTIFACTS="${SOLOPM_RUNTIME_TODAY_PRODUCTION_ROUTE_KEEP_ARTIFACTS:-0}"
ARTIFACT_ROOT="${SOLOPM_RUNTIME_TODAY_PRODUCTION_ROUTE_ARTIFACT_DIR:-$ROOT_DIR/.tmp/runtime-today-production-route}"
AX_HELPERS="${AX_HELPERS:-$ROOT_DIR/script/ui_accessibility_smoke_helpers.sh}"

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

if ! command -v "$SQLITE3" >/dev/null 2>&1; then
  echo "BLOCKER: sqlite3 is required for runtime Today production-route smoke" >&2
  exit 2
fi

if [[ ! -r "$AX_HELPERS" ]]; then
  echo "BLOCKER: AX helpers are unavailable: $AX_HELPERS" >&2
  exit 2
fi

# shellcheck source=/dev/null
source "$AX_HELPERS"

# A localized title must be below the Today container, not merely elsewhere in
# another visible app window. This makes the language matrix a runtime check.
export SOLOPM_UI_EVIDENCE_AX_REQUIRE_IDENTIFIER_SUBTREE=1

mkdir -p "$ROOT_DIR/.tmp" "$ARTIFACT_ROOT"

app_pid=""
case_artifact_dir=""
case_home=""
case_cf_user_home=""
database_path=""
case_deadline=""
locale_label=""
expected_today_label=""
small_fixture_today_due_at=""

terminate_app() {
  # A PID-scoped shutdown avoids terminating a developer's separately running
  # SoloPM instance while still guaranteeing each smoke launch is cleaned up.
  if [[ -n "${app_pid:-}" ]]; then
    kill "$app_pid" >/dev/null 2>&1 || true
    local deadline=$((SECONDS + 3))
    while kill -0 "$app_pid" >/dev/null 2>&1 && [[ "$SECONDS" -lt "$deadline" ]]; do
      sleep 0.1
    done
    kill -9 "$app_pid" >/dev/null 2>&1 || true
    wait "$app_pid" >/dev/null 2>&1 || true
    app_pid=""
  fi
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
  preview_build_count="$(runtime_counter_value 'solopm.dailyPlanningPreview.buildCount')"
  toolbar_layout_max_depth="$(runtime_counter_value 'solopm.toolbar.layout.maxDepth')"

  if [[ ! "$preview_build_count" =~ ^[0-9]+$ || ! "$toolbar_layout_max_depth" =~ ^[0-9]+$ ]]; then
    printf 'status=diagnostic-unavailable\npreview-build-count=%s\ntoolbar-layout-max-depth=%s\n' \
      "${preview_build_count:-missing}" "${toolbar_layout_max_depth:-missing}" \
      >"$case_artifact_dir/toolbar-recursion-diagnostic.txt"
    return 1
  fi

  printf 'status=measured\npreview-build-count=%s\ntoolbar-layout-max-depth=%s\n' \
    "$preview_build_count" "$toolbar_layout_max_depth" \
    >"$case_artifact_dir/toolbar-recursion-diagnostic.txt"
  printf '%s\n' "$preview_build_count" >"$case_artifact_dir/preview-build-count.txt"
  printf '%s\n' "$toolbar_layout_max_depth" >"$case_artifact_dir/toolbar-layout-max-depth.txt"

  [[ "$preview_build_count" -le 1 && "$toolbar_layout_max_depth" -le "$MAX_TOOLBAR_LAYOUT_DEPTH" ]]
}

capture_failure_artifact() {
  local reason="$1"
  mkdir -p "$case_artifact_dir/ax-probes"
  printf 'status=failed\nreason=%s\nfixture=%s\nlocale=%s\nlanguage_preference=%s\n' "$reason" "${fixture:-unknown}" "${locale_label:-unknown}" "${locale:-unknown}" >"$case_artifact_dir/summary.txt"
  capture_sanitized_processes
  capture_sanitized_windows
  capture_runtime_route_diagnostics || true
  sanitize_sample
}

cleanup() {
  terminate_app
}
trap cleanup EXIT INT TERM

launch_app() {
  local locale="$1"
  terminate_app
  # Start from an empty environment so host API keys, proxy settings, and saved
  # smoke flags cannot supply credentials or alter this normal-route exercise.
  /usr/bin/env -i \
    PATH="$PATH" \
    TMPDIR="$case_artifact_dir/tmp" \
    HOME="$case_home" \
    CFFIXED_USER_HOME="$case_cf_user_home" \
    SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1 \
    SOLOPM_DATABASE_PATH="$database_path" \
    SOLOPM_LANGUAGE_PREFERENCE="$locale" \
    SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION="today" \
    "$APP_BINARY" -ApplePersistenceIgnoreState YES >/dev/null 2>&1 &
  app_pid=$!
}

wait_for_database_table() {
  local table="$1"
  local deadline=$((SECONDS + RUNTIME_TIMEOUT_SECONDS))
  while true; do
    if [[ -f "$database_path" ]] && "$SQLITE3" "$database_path" "SELECT name FROM sqlite_master WHERE type='table' AND name='$table';" | grep -Fx "$table" >/dev/null; then
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      return 1
    fi
    sleep 0.2
  done
}

seed_small_fixture() {
  local today_due_at
  today_due_at="$(date '+%Y-%m-%dT12:00:00%z')"
  # Keep the exact local-noon value used for INSERT. Recomputing it after a
  # midnight boundary could verify a different calendar day than the fixture.
  small_fixture_today_due_at="$today_due_at"
  "$SQLITE3" "$database_path" <<SQL
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
       ((SELECT id FROM projects WHERE source_command='runtime-today-production-route' AND title='fixture-project-3'), 'fixture-later-2', 'backlog', NULL, NULL, NULL, 'medium', 'runtime-today-production-route', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
SQL
}

verify_small_fixture_today_data() {
  local due_at="$1"
  local today_task_count
  today_task_count="$("$SQLITE3" "$database_path" "SELECT COUNT(*) FROM tasks WHERE source_command='runtime-today-production-route' AND due_at='$due_at' AND status IN ('planned', 'in_progress') AND completed_at IS NULL;")"
  [[ "$today_task_count" == "3" ]]
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
  local probe_file="$case_artifact_dir/ax-probes/${marker}.txt"
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
  wait_for_marker_until "project-board-header-bar" "" "$case_deadline"
  wait_for_marker_until "today-workflow" "$expected_today_label" "$case_deadline"
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
  rm -rf "$case_artifact_dir"
  mkdir -p "$case_home/Library/Preferences" "$case_cf_user_home" "$case_artifact_dir/ax-probes" "$case_artifact_dir/tmp"

  # The first normal launch creates the schema. It uses the same isolated home,
  # database, and no-Keychain configuration as the measured launch.
  launch_app "$locale"
  if ! wait_for_database_table "projects" || ! wait_for_database_table "tasks"; then
    capture_failure_artifact "database-schema-timeout"
    return 1
  fi
  terminate_app

  if [[ "$fixture" == "small" ]]; then
    if ! seed_small_fixture; then
      capture_failure_artifact "fixture-seed-failed"
      return 1
    fi
    if ! verify_small_fixture_today_data "$small_fixture_today_due_at"; then
      capture_failure_artifact "fixture-today-data-missing"
      return 1
    fi
  fi

  launch_app "$locale"
  case_deadline=$((SECONDS + RUNTIME_TIMEOUT_SECONDS))
  if ! wait_for_required_markers; then
    capture_failure_artifact "today-route-marker-timeout"
    return 1
  fi
  # AX probes compile and traverse accessibility state inside the route-ready
  # budget. CPU stabilization is a separate post-ready acceptance condition,
  # so it needs its own bounded window and must always collect real samples.
  case_deadline=$((SECONDS + CPU_CONVERGENCE_TIMEOUT_SECONDS))
  if ! cpu_convergence_gate; then
    capture_failure_artifact "cpu-convergence-timeout"
    return 1
  fi
  if ! capture_runtime_route_diagnostics; then
    capture_failure_artifact "runtime-route-diagnostics-failed"
    return 1
  fi

  printf 'status=passed\nfixture=%s\nlocale=%s\nlanguage_preference=%s\n' "$fixture" "$locale_label" "$locale" >"$case_artifact_dir/summary.txt"
  terminate_app
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
