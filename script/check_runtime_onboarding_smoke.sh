#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT_DIR/packaging/app_metadata.env"

APP_BINARY="$ROOT_DIR/dist/${APP_NAME:?APP_NAME is required}.app/Contents/MacOS/$APP_NAME"
AX_HELPERS="${AX_HELPERS:-$ROOT_DIR/script/ui_accessibility_smoke_helpers.sh}"
AX_BUTTON_HELPER="${AX_BUTTON_HELPER:-$ROOT_DIR/script/ui_evidence_ax_press_button.swift}"
AX_MARKER_HELPER="${AX_MARKER_HELPER:-$ROOT_DIR/script/ui_evidence_ax_marker_check.swift}"
SQLITE3="${SQLITE3:-sqlite3}"
TIMEOUT_SECONDS="${SOLOPM_RUNTIME_ONBOARDING_TIMEOUT_SECONDS:-45}"
KEEP_HOME="${SOLOPM_RUNTIME_ONBOARDING_KEEP_HOME:-0}"

[[ -r "$AX_HELPERS" ]] || { echo "BLOCKER: AX helpers unavailable: $AX_HELPERS" >&2; exit 2; }
command -v "$SQLITE3" >/dev/null || { echo "BLOCKER: sqlite3 is required" >&2; exit 2; }

"$ROOT_DIR/script/build_and_run.sh" --build-only
[[ -x "$APP_BINARY" ]] || { echo "BLOCKER: app bundle was not built: $APP_BINARY" >&2; exit 2; }

# shellcheck source=/dev/null
source "$AX_HELPERS"
mkdir -p "$ROOT_DIR/.tmp"
tmp_dir="$(mktemp -d "$ROOT_DIR/.tmp/solopm-runtime-onboarding.XXXXXX")"
runtime_home="$tmp_dir/home"
database_path="$tmp_dir/SoloPM-runtime-onboarding.sqlite"
app_pid=""
app_launch_pid=""
app_identity=""
app_launch_identity=""
mkdir -p "$runtime_home/Library/Application Support" "$runtime_home/Library/Preferences"

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
  if [[ "$KEEP_HOME" == "1" ]]; then
    printf 'INFO: kept runtime onboarding home at %s\n' "$runtime_home"
  else
    rm -rf "$tmp_dir"
  fi
}
trap cleanup EXIT

launch_app() {
  local open_settings="${1:-0}"
  local reset_first_run_defaults="${2:-0}"
  terminate_app
  local -a environment=(
    /usr/bin/env -i
    PATH="$PATH"
    TMPDIR="$tmp_dir"
    HOME="$runtime_home"
    CFFIXED_USER_HOME="$runtime_home"
    SOLOPM_DATABASE_PATH="$database_path"
    SOLOPM_ONBOARDING_RUNTIME_SMOKE=1
    SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1
    SOLOPM_LANGUAGE_PREFERENCE=english
  )
  if [[ "$open_settings" == "1" ]]; then
    environment+=(SOLOPM_OPEN_SETTINGS_ON_LAUNCH=1)
  fi
  local -a app_arguments=(
    -ApplePersistenceIgnoreState YES
    -AppleLanguages '(en)'
    -AppleLocale en_US
  )
  if [[ "$reset_first_run_defaults" == "1" ]]; then
    # cfprefsd can outlive a process and ignore HOME for an already registered
    # bundle ID. NSArgumentDomain resets only this owned launch while leaving
    # the product's normal FirstRunOnboardingGate decision in control.
    app_arguments+=(
      -solopm.onboarding.dismissed NO
      -solopm.onboarding.completed NO
      -solopm.onboarding.sampleProjectCreated NO
    )
  fi
  "${environment[@]}" "$APP_BINARY" "${app_arguments[@]}" &
  app_launch_pid=$!
  app_launch_identity="$(ax_wait_for_owned_process_identity "$app_launch_pid" "$APP_BINARY" 3)" || return 1
  app_pid="$(ax_wait_for_owned_app_pid "$app_launch_pid" "$APP_BINARY" "$TIMEOUT_SECONDS")"
  app_identity="$(ax_wait_for_owned_process_identity "$app_pid" "$APP_BINARY" 3)" || return 1
  ax_wait_for_pid_owned_process "$APP_NAME" "$app_pid" "$TIMEOUT_SECONDS" "$APP_BINARY"
  ax_wait_for_pid_owned_window "$APP_NAME" "$app_pid" "" "$TIMEOUT_SECONDS" "" "$APP_BINARY"
}

wait_ax_signals() {
  local first="$1"
  local second="${2:-}"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while (( SECONDS < deadline )); do
    if SOLOPM_UI_EVIDENCE_AX_REQUIRE_IDENTIFIER_SUBTREE=1 \
       /usr/bin/swift "$AX_MARKER_HELPER" "$APP_NAME" "$first" "$second" "$app_pid" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5
  done
  echo "BLOCKER: AX markers did not appear: $first / $second" >&2
  return 1
}

press_button() {
  local marker="$1"
  local fallback_marker="${2:-}"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while (( SECONDS < deadline )); do
    if /usr/bin/swift "$AX_BUTTON_HELPER" "$app_pid" "$marker" >/dev/null 2>&1; then
      return 0
    fi
    if [[ -n "$fallback_marker" ]] &&
       /usr/bin/swift "$AX_BUTTON_HELPER" "$app_pid" "$fallback_marker" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5
  done
  echo "BLOCKER: enabled AX button did not appear: $marker" >&2
  return 1
}

wait_sql_value() {
  local sql="$1"
  local expected="$2"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local actual=""
  while (( SECONDS < deadline )); do
    if [[ -f "$database_path" ]]; then
      actual="$($SQLITE3 "$database_path" "$sql" 2>/dev/null || true)"
      [[ "$actual" == "$expected" ]] && return 0
    fi
    sleep 0.25
  done
  echo "BLOCKER: SQLite expected '$expected', got '${actual:-<empty>}' for: $sql" >&2
  return 1
}

launch_app 0 1
press_button "Try SoloPM now" "今すぐSoloPMを試す"
wait_sql_value "SELECT count(*) FROM projects WHERE source_command='onboarding-sample';" "1"
wait_sql_value "SELECT count(*) FROM tasks WHERE source_command='onboarding-sample';" "6"
first_lesson_id="$($SQLITE3 "$database_path" "SELECT id FROM tasks WHERE source_command='onboarding-sample' ORDER BY id LIMIT 1;")"
wait_ax_signals "today-workflow" "Press ⌘K and search for anything"
wait_ax_signals "workflow-task-row-$first_lesson_id" "Selected"
press_button "workflow-task-completion-$first_lesson_id"
wait_sql_value "SELECT status FROM tasks WHERE id=$first_lesson_id;" "completed"

# Settings owns the supported rerun path. A harness relaunch skips automatic
# onboarding, then the visible Settings button must reopen exactly one sheet.
launch_app 1
press_button "Run Setup Again" "セットアップを再実行"
press_button "Try SoloPM now" "今すぐSoloPMを試す"
wait_sql_value "SELECT count(*) FROM projects WHERE source_command='onboarding-sample';" "1"
wait_sql_value "SELECT count(*) FROM tasks WHERE source_command='onboarding-sample';" "6"
wait_sql_value "SELECT status FROM tasks WHERE id=$first_lesson_id;" "completed"

launch_app 1
press_button "Run Setup Again" "セットアップを再実行"
press_button "Skip Setup" "セットアップをスキップ"
wait_sql_value "SELECT count(*) FROM projects WHERE source_command='onboarding-sample';" "1"
wait_sql_value "SELECT count(*) FROM tasks WHERE source_command='onboarding-sample';" "6"
wait_sql_value "SELECT status FROM tasks WHERE id=$first_lesson_id;" "completed"

printf 'OK: fresh HOME onboarding created six lessons without setup, routed to Today, focused and completed lesson one, reran idempotently, and skipped without data loss\n'
