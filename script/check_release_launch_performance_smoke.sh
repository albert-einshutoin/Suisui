#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METADATA_FILE="$ROOT_DIR/packaging/app_metadata.env"
CI_REDACT_HELPER="$ROOT_DIR/script/ci_redact_stream.sh"

if [[ ! -f "$METADATA_FILE" ]]; then
  echo "missing metadata file: $METADATA_FILE" >&2
  exit 2
fi
if [[ ! -r "$CI_REDACT_HELPER" ]]; then
  echo "missing CI redaction helper: $CI_REDACT_HELPER" >&2
  exit 2
fi

# shellcheck source=/dev/null
source "$METADATA_FILE"
# shellcheck source=ci_redact_stream.sh
source "$CI_REDACT_HELPER"

APP_NAME="${APP_NAME:?APP_NAME is required}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-}"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
TIMEOUT_SECONDS="${SUISUI_PERFORMANCE_TIMEOUT_SECONDS:-30}"
OUTPUT_DIR="${SUISUI_PERFORMANCE_OUTPUT_DIR:-$ROOT_DIR/.tmp/release-launch-performance}"
PERFORMANCE_HOME="${SUISUI_PERFORMANCE_HOME:-$OUTPUT_DIR/home}"
PERFORMANCE_DATABASE_PATH="${SUISUI_PERFORMANCE_DATABASE_PATH:-$PERFORMANCE_HOME/Library/Application Support/Suisui/Suisui.sqlite}"
SUMMARY_FILE="$OUTPUT_DIR/summary.md"
SAMPLES_FILE="$OUTPUT_DIR/samples.tsv"
TIMELINE_FILE="$OUTPUT_DIR/launch-timeline.tsv"
QUIESCENCE_FILE="$OUTPUT_DIR/runner-quiescence.tsv"
QUIESCENCE_PROCESS_FILE="$OUTPUT_DIR/runner-quiescence-processes.tsv"
BOOTSTRAP_EXIT_FILE="$OUTPUT_DIR/bootstrap-exit.env"
APP_RAW_STDERR_FILE="$PERFORMANCE_HOME/app-stderr.raw.log"
APP_STDERR_FIFO="$PERFORMANCE_HOME/app-stderr.pipe"
APP_STDERR_DIAGNOSTIC_FILE="$OUTPUT_DIR/app-stderr-sanitized.log"
APP_UNIFIED_DIAGNOSTIC_FILE="$OUTPUT_DIR/app-unified-log-sanitized.log"
AX_HELPERS="${AX_HELPERS:-$ROOT_DIR/script/ui_accessibility_smoke_helpers.sh}"
AX_PRESS_ELEMENT_HELPER="${AX_PRESS_ELEMENT_HELPER:-$ROOT_DIR/script/ui_evidence_ax_press_element.swift}"
AX_MARKER_HELPER="${AX_MARKER_HELPER:-$ROOT_DIR/script/ui_evidence_ax_marker_check.swift}"
AX_PRESS_ELEMENT_HELPER_EXECUTABLE="$OUTPUT_DIR/ui-evidence-ax-press-element.$$"
AX_MARKER_HELPER_EXECUTABLE="$OUTPUT_DIR/ui-evidence-ax-marker-checker.$$"
SUISUI_PERFORMANCE_PROFILE="${SUISUI_PERFORMANCE_PROFILE:-release}"
SUISUI_PERFORMANCE_USE_PREBUILT_APP="${SUISUI_PERFORMANCE_USE_PREBUILT_APP:-0}"

case "$SUISUI_PERFORMANCE_PROFILE" in
  release)
    # Release profile keeps the build aligned with release-machine evidence and
    # the stricter Sparkle requirements already enforced by the release path.
    DEFAULT_BUILD_CONFIGURATION=release
    DEFAULT_COLD_LAUNCH_BUDGET_MS=1000
    DEFAULT_DESTINATION_SWITCH_BUDGET_MS=3000
    ;;
  debug)
    # Debug profile keeps local and CI diagnostics usable when release secrets
    # are intentionally absent, while still enforcing measured launch budgets.
    DEFAULT_BUILD_CONFIGURATION=debug
    DEFAULT_COLD_LAUNCH_BUDGET_MS=25000
    DEFAULT_DESTINATION_SWITCH_BUDGET_MS=5000
    ;;
  *)
    echo "BLOCKER: SUISUI_PERFORMANCE_PROFILE must be release or debug" >&2
    exit 2
    ;;
esac

PERFORMANCE_BUILD_CONFIGURATION_OVERRIDE="${SUISUI_PERFORMANCE_BUILD_CONFIGURATION:-}"
if [[ "$SUISUI_PERFORMANCE_PROFILE" == "release" && -n "$PERFORMANCE_BUILD_CONFIGURATION_OVERRIDE" && "$PERFORMANCE_BUILD_CONFIGURATION_OVERRIDE" != "release" ]]; then
  # Release safety stays strict here so release evidence cannot be weakened by
  # a debug build override hiding launch behavior differences.
  echo "BLOCKER: release performance profile requires release build configuration" >&2
  exit 2
fi

BUILD_CONFIGURATION="${PERFORMANCE_BUILD_CONFIGURATION_OVERRIDE:-$DEFAULT_BUILD_CONFIGURATION}"
MAX_COLD_LAUNCH_MS="${SUISUI_PERFORMANCE_MAX_COLD_LAUNCH_MS:-$DEFAULT_COLD_LAUNCH_BUDGET_MS}"
MAX_DESTINATION_SWITCH_MS="${SUISUI_PERFORMANCE_MAX_DESTINATION_SWITCH_MS:-$DEFAULT_DESTINATION_SWITCH_BUDGET_MS}"
# Fixed odd sample counts let the gate reject consistently slow product work
# while ignoring one noisy hosted-runner observation. Keeping these out of the
# environment prevents callers from weakening release evidence.
COLD_LAUNCH_SAMPLE_COUNT=3
DESTINATION_SAMPLE_COUNT=3
# Release compilation can leave a hosted runner CPU-bound immediately before
# launch. Keep these policy values source-owned so callers cannot weaken the
# product budget by skipping the bounded idle proof.
RUNNER_QUIESCENCE_MINIMUM_SETTLE_SECONDS=10
RUNNER_QUIESCENCE_MAX_WAIT_SECONDS=60
RUNNER_QUIESCENCE_MIN_CPU_IDLE_PERCENT=80
RUNNER_QUIESCENCE_REQUIRED_IDLE_SAMPLES=3

if [[ "$SUISUI_PERFORMANCE_USE_PREBUILT_APP" != "0" && "$SUISUI_PERFORMANCE_USE_PREBUILT_APP" != "1" ]]; then
  echo "BLOCKER: SUISUI_PERFORMANCE_USE_PREBUILT_APP must be 0 or 1" >&2
  exit 2
fi
if [[ "$SUISUI_PERFORMANCE_USE_PREBUILT_APP" == "1" && "$SUISUI_PERFORMANCE_PROFILE" != "release" ]]; then
  echo "BLOCKER: release performance profile is required for a prebuilt app" >&2
  exit 2
fi

require_positive_integer_budget() {
  local name="$1"
  local value="$2"
  if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then
    echo "BLOCKER: $name must be a positive integer millisecond budget" >&2
    exit 2
  fi
}

reject_relaxed_release_budget() {
  local name="$1"
  local value="$2"
  local default_value="$3"
  if [[ "$SUISUI_PERFORMANCE_PROFILE" == "release" && "$value" -gt "$default_value" ]]; then
    # Release evidence must not be made easier by env overrides; lower values are
    # allowed because they are stricter and preserve the release baseline.
    echo "BLOCKER: release performance budget override cannot exceed default $name budget (${default_value}ms)" >&2
    exit 2
  fi
}

require_positive_integer_budget "SUISUI_PERFORMANCE_MAX_COLD_LAUNCH_MS" "$MAX_COLD_LAUNCH_MS"
require_positive_integer_budget "SUISUI_PERFORMANCE_MAX_DESTINATION_SWITCH_MS" "$MAX_DESTINATION_SWITCH_MS"
reject_relaxed_release_budget "cold launch" "$MAX_COLD_LAUNCH_MS" "$DEFAULT_COLD_LAUNCH_BUDGET_MS"
reject_relaxed_release_budget "destination switch" "$MAX_DESTINATION_SWITCH_MS" "$DEFAULT_DESTINATION_SWITCH_BUDGET_MS"

cd "$ROOT_DIR"
mkdir -p "$OUTPUT_DIR"
mkdir -p "$(dirname "$PERFORMANCE_DATABASE_PATH")"

# shellcheck source=/dev/null
source "$AX_HELPERS"

# A one-second product SLO needs finer sampling than the conservative shared
# smoke default. This changes only observer cadence, never the product budget.
AX_WAIT_POLL_INTERVAL_SECONDS=0.05
export AX_WAIT_POLL_INTERVAL_SECONDS

sanitize_app_diagnostic_stream() {
  ci_redact_stream
}

start_app_stderr_capture() {
  finish_app_stderr_capture
  rm -f "$APP_RAW_STDERR_FILE" "$APP_STDERR_FIFO"
  mkfifo "$APP_STDERR_FIFO"
  # Keep only a fixed-size tail while the app runs; the raw producer can never
  # grow an unbounded temporary file or perturb disk capacity during a sample.
  /usr/bin/perl -e '
    use strict;
    use warnings;
    my $limit = 32768;
    my $tail = "";
    while (read(STDIN, my $chunk, 4096)) {
      $tail .= $chunk;
      substr($tail, 0, length($tail) - $limit, "") if length($tail) > $limit;
    }
    print $tail;
  ' <"$APP_STDERR_FIFO" >"$APP_RAW_STDERR_FILE" &
  APP_STDERR_CAPTURE_PID=$!
}

finish_app_stderr_capture() {
  local capture_pid="${APP_STDERR_CAPTURE_PID:-}"
  if [[ "$capture_pid" =~ ^[0-9]+$ ]]; then
    for _ in {1..20}; do
      kill -0 "$capture_pid" >/dev/null 2>&1 || break
      sleep 0.05
    done
    if kill -0 "$capture_pid" >/dev/null 2>&1; then
      kill -TERM "$capture_pid" >/dev/null 2>&1 || true
    fi
    wait "$capture_pid" 2>/dev/null || true
  fi
  APP_STDERR_CAPTURE_PID=""
  rm -f "$APP_STDERR_FIFO"
}

run_with_app_diagnostic_timeout() {
  local timeout_seconds="$1"
  shift
  LC_ALL=C /usr/bin/perl -MTime::HiRes=alarm -e '
    my $timeout_seconds = shift @ARGV;
    $SIG{ALRM} = "DEFAULT";
    alarm($timeout_seconds);
    exec @ARGV;
  ' "$timeout_seconds" "$@"
}

capture_app_failure_diagnostics() {
  local failed_pid="${1:-}"
  if [[ -f "$APP_RAW_STDERR_FILE" ]]; then
    tail -c 32768 "$APP_RAW_STDERR_FILE" 2>/dev/null \
      | sanitize_app_diagnostic_stream \
      >"$APP_STDERR_DIAGNOSTIC_FILE" || printf '%s\n' "diagnostic-unavailable" >"$APP_STDERR_DIAGNOSTIC_FILE"
  else
    printf '%s\n' "diagnostic-unavailable" >"$APP_STDERR_DIAGNOSTIC_FILE"
  fi
  if [[ "$failed_pid" =~ ^[0-9]+$ ]]; then
    set +e
    run_with_app_diagnostic_timeout 5 /usr/bin/log show --last 2m --style compact \
      --predicate "processIdentifier == $failed_pid" 2>/dev/null \
      | tail -n 120 \
      | tail -c 32768 \
      | sanitize_app_diagnostic_stream \
      >"$APP_UNIFIED_DIAGNOSTIC_FILE"
    set -e
    [[ -s "$APP_UNIFIED_DIAGNOSTIC_FILE" ]] || printf '%s\n' "diagnostic-unavailable" >"$APP_UNIFIED_DIAGNOSTIC_FILE"
  else
    printf '%s\n' "diagnostic-unavailable" >"$APP_UNIFIED_DIAGNOSTIC_FILE"
  fi
}

APP_PID=""
APP_LAUNCH_PID=""
APP_IDENTITY=""
APP_LAUNCH_IDENTITY=""
APP_STDERR_CAPTURE_PID=""
TRACK_LAUNCH_MILESTONES=0

now_ms() {
  /usr/bin/perl -MTime::HiRes=time -e 'printf "%d\n", time() * 1000'
}

monotonic_ms() {
  /usr/bin/perl -MTime::HiRes=clock_gettime,CLOCK_MONOTONIC \
    -e 'printf "%d\n", clock_gettime(CLOCK_MONOTONIC) * 1000'
}

parse_macos_cpu_idle_percent() {
  local idle_percent
  idle_percent="$(awk '
    /^CPU usage:/ {
      sample_count += 1
      if (sample_count != 2) {
        next
      }
      for (field_index = 1; field_index <= NF; field_index += 1) {
        if ($field_index == "idle") {
          value = $(field_index - 1)
          gsub(/%/, "", value)
          second_idle_percent = value
        }
      }
    }
    END {
      if (sample_count == 2 && second_idle_percent != "") {
        print second_idle_percent
      }
    }
  ')"
  [[ "$idle_percent" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
  printf '%s\n' "$idle_percent"
}

read_macos_cpu_idle_percent() {
  local deadline_ms="$1"
  local snapshot
  snapshot="$(
    LC_ALL=C /usr/bin/perl -MTime::HiRes=clock_gettime,alarm,CLOCK_MONOTONIC -e '
      my $deadline_ms = shift @ARGV;
      my $remaining_seconds =
        ($deadline_ms - (clock_gettime(CLOCK_MONOTONIC) * 1000)) / 1000;
      exit 124 if $remaining_seconds <= 0;
      $SIG{ALRM} = "DEFAULT";
      alarm($remaining_seconds);
      exec @ARGV;
    ' "$deadline_ms" /usr/bin/top -l 2 -s 1 -n 0 2>/dev/null
  )" || return 1
  printf '%s\n' "$snapshot" | parse_macos_cpu_idle_percent
}

wait_for_runner_quiescence() {
  local started_ms deadline_ms observed_ms elapsed_ms idle_percent
  local sample_index=0
  local consecutive_idle_samples=0

  started_ms="$(monotonic_ms)"
  deadline_ms=$((started_ms + RUNNER_QUIESCENCE_MAX_WAIT_SECONDS * 1000))
  sleep "$RUNNER_QUIESCENCE_MINIMUM_SETTLE_SECONDS"

  while [[ "$(monotonic_ms)" -lt "$deadline_ms" ]]; do
    sample_index=$((sample_index + 1))
    if idle_percent="$(read_macos_cpu_idle_percent "$deadline_ms")"; then
      if awk -v observed="$idle_percent" -v minimum="$RUNNER_QUIESCENCE_MIN_CPU_IDLE_PERCENT" \
        'BEGIN { exit !(observed >= minimum) }'; then
        consecutive_idle_samples=$((consecutive_idle_samples + 1))
      else
        consecutive_idle_samples=0
      fi
    else
      idle_percent="unavailable"
      consecutive_idle_samples=0
    fi

    observed_ms="$(monotonic_ms)"
    printf '%s\t%s\t%s\t%s\n' \
      "$sample_index" "$observed_ms" "$idle_percent" "$consecutive_idle_samples" \
      >>"$QUIESCENCE_FILE"

    # A sample that completed after the strict deadline cannot establish an
    # idle precondition for the launch that follows.
    if [[ "$observed_ms" -le "$deadline_ms" ]] &&
      (( consecutive_idle_samples >= RUNNER_QUIESCENCE_REQUIRED_IDLE_SAMPLES )); then
      elapsed_ms=$((observed_ms - started_ms))
      printf -- '- Result: `PASS` after `%sms` with `%s` consecutive idle samples.\n' \
        "$elapsed_ms" "$consecutive_idle_samples" >>"$SUMMARY_FILE"
      printf 'OK: runner quiescence established in %sms (%s%% CPU idle)\n' \
        "$elapsed_ms" "$idle_percent"
      return 0
    fi

    [[ "$observed_ms" -lt "$deadline_ms" ]] || break
    sleep 1
  done

  elapsed_ms=$(($(monotonic_ms) - started_ms))
  {
    printf '%s\t%s\t%s\n' "pid" "cpu_percent" "process"
    # `ucomm` exposes only the executable name, never arguments or workspace
    # paths, so the failure artifact remains useful without leaking user data.
    LC_ALL=C ps -Ao pid=,%cpu=,ucomm= 2>/dev/null \
      | sort -k2,2nr \
      | awk 'NR <= 12'
  } >"$QUIESCENCE_PROCESS_FILE" || printf '%s\n' "diagnostic-unavailable" >"$QUIESCENCE_PROCESS_FILE"
  printf -- '- Result: `FAIL` after `%sms`; runner never produced `%s` consecutive samples at or above `%s%%` CPU idle.\n' \
    "$elapsed_ms" "$RUNNER_QUIESCENCE_REQUIRED_IDLE_SAMPLES" \
    "$RUNNER_QUIESCENCE_MIN_CPU_IDLE_PERCENT" >>"$SUMMARY_FILE"
  printf 'failure_category=runner-quiescence\n' >&2
  echo "BLOCKER: runner did not become quiescent within ${RUNNER_QUIESCENCE_MAX_WAIT_SECONDS}s" >&2
  return 1
}

terminate_app() {
  local owned_pid="${APP_PID:-}"
  local launch_pid="${APP_LAUNCH_PID:-}"
  if [[ -n "$owned_pid" ]]; then
    ax_terminate_owned_process "$owned_pid" "$APP_BINARY" "${APP_IDENTITY:-}"
  fi
  if [[ -n "$launch_pid" && "$launch_pid" != "$owned_pid" ]]; then
    ax_terminate_owned_process "$launch_pid" "$APP_BINARY" "${APP_LAUNCH_IDENTITY:-}"
  fi
  APP_PID=""
  APP_LAUNCH_PID=""
  APP_IDENTITY=""
  APP_LAUNCH_IDENTITY=""
  finish_app_stderr_capture
}

cleanup() {
  terminate_app || true
  finish_app_stderr_capture || true
  rm -f "$AX_PRESS_ELEMENT_HELPER_EXECUTABLE" "$AX_MARKER_HELPER_EXECUTABLE"
}

prepare_ax_helpers() {
  # Compilation is harness setup, not product latency. Reuse these executables
  # so destination samples start with a ready AX selector and marker checker.
  /usr/bin/swiftc "$AX_PRESS_ELEMENT_HELPER" -o "$AX_PRESS_ELEMENT_HELPER_EXECUTABLE"
  /usr/bin/swiftc "$AX_MARKER_HELPER" -o "$AX_MARKER_HELPER_EXECUTABLE"
}

activate_app() {
  # Target the process we launched. Addressing the application by name can make
  # LaunchServices start or activate a different Suisui instance and invalidate
  # both the isolated database and the performance sample.
  /usr/bin/osascript - "$APP_PID" "$APP_NAME" <<'APPLESCRIPT' >/dev/null 2>&1 &
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
  return "activated " & appName
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

open_app() {
  # Direct launch retains the deterministic HOME/SQLite/selection contract;
  # unlike LaunchServices it cannot silently drop normal-route environment.
  local timeline_path=""
  if [[ "$TRACK_LAUNCH_MILESTONES" == "1" ]]; then
    timeline_path="$TIMELINE_FILE"
  fi
  start_app_stderr_capture
  /usr/bin/env -i PATH="$PATH" TMPDIR="$OUTPUT_DIR" HOME="$PERFORMANCE_HOME" CFFIXED_USER_HOME="$PERFORMANCE_HOME" \
    SUISUI_DISABLE_KEYCHAIN_SECRET_STORE=1 SUISUI_DATABASE_PATH="$PERFORMANCE_DATABASE_PATH" \
    SUISUI_PROJECT_BOARD_SELECTED_DESTINATION="today" \
    SUISUI_LAUNCH_TIMELINE_PATH="$timeline_path" \
    "$APP_BINARY" -ApplePersistenceIgnoreState YES >/dev/null 2>"$APP_STDERR_FIFO" &
  APP_LAUNCH_PID=$!
  APP_LAUNCH_IDENTITY="$(ax_wait_for_owned_process_identity "$APP_LAUNCH_PID" "$APP_BINARY" 3)" || {
    ax_emit_failure_category "launch" "performance-launch-identity-unavailable"
    return 1
  }
  APP_PID="$(ax_wait_for_owned_app_pid "$APP_LAUNCH_PID" "$APP_BINARY" "$TIMEOUT_SECONDS")" || {
    ax_emit_failure_category "launch" "performance-owned-pid-unavailable"
    echo "BLOCKER: performance app did not launch from pid $APP_LAUNCH_PID" >&2
    return 1
  }
  APP_IDENTITY="$(ax_wait_for_owned_process_identity "$APP_PID" "$APP_BINARY" 3)" || {
    ax_emit_failure_category "launch" "performance-owned-identity-unavailable"
    return 1
  }
  ax_wait_for_pid_owned_process "$APP_NAME" "$APP_PID" "$TIMEOUT_SECONDS" "$APP_BINARY"
}

wait_for_launch_milestone() {
  local label="$1"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local timestamp=""
  while true; do
    timestamp="$(awk -F '\t' -v label="$label" '$1 == label { print $2; exit }' "$TIMELINE_FILE" 2>/dev/null || true)"
    if [[ "$timestamp" =~ ^[0-9]+$ ]]; then
      printf '%s\n' "$timestamp"
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      ax_emit_failure_category "product-marker" "performance-launch-milestone-unavailable"
      echo "BLOCKER: app did not emit launch milestone: $label" >&2
      return 1
    fi
    sleep 0.05
  done
}

wait_for_visible_window() {
  local probe_file="$OUTPUT_DIR/wait-visible-window.txt"
  # Reuse the compiled AX probe and its explicit any-window token to detect an
  # owned window at sub-second cadence. The shared AppleScript helper polls at
  # one-second intervals and would otherwise dominate a one-second launch SLO.
  if ! ax_wait_for_ax_identifier "$APP_NAME" "__AX_ANY_WINDOW__" "$TIMEOUT_SECONDS" "$ROOT_DIR" "$probe_file" "" "$APP_PID"; then
    ax_emit_failure_category "window" "performance-window-unavailable"
    echo "BLOCKER: $APP_NAME did not publish a visible window for launched pid $APP_PID within ${TIMEOUT_SECONDS}s" >&2
    return 1
  fi
  return 0
}

wait_for_database_schema() {
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while true; do
    if ! ax_process_matches_identity "$APP_PID" "$APP_BINARY" "$APP_IDENTITY"; then
      ax_emit_failure_category "launch" "performance-bootstrap-exited"
      echo "BLOCKER: performance bootstrap app exited before its database schema was ready" >&2
      return 1
    fi
    if [[ -f "$PERFORMANCE_DATABASE_PATH" ]] &&
      [[ "$(sqlite3 -batch -noheader "$PERFORMANCE_DATABASE_PATH" \
        "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name IN ('projects', 'tasks');" 2>/dev/null || true)" == "2" ]]; then
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      ax_emit_failure_category "launch" "performance-database-schema-unavailable"
      echo "BLOCKER: performance database schema was not ready within ${TIMEOUT_SECONDS}s" >&2
      return 1
    fi
    sleep 0.2
  done
}

record_unexpected_bootstrap_exit() {
  local wait_status="unavailable"
  local failed_pid="${APP_PID:-}"
  if [[ "${APP_PID:-}" =~ ^[0-9]+$ ]]; then
    # Never block on an unexpected process that is still running. A child that
    # already exited remains waitable, so its raw status can be recorded.
    if ! kill -0 "$APP_PID" >/dev/null 2>&1; then
      if wait "$APP_PID" 2>/dev/null; then
        wait_status=0
      else
        wait_status=$?
      fi
    fi
  fi
  printf 'status=failed\nwait_status=%s\ntermination=unexpected-exit\nfailure_reason=performance-bootstrap-exited\n' \
    "$wait_status" >"$BOOTSTRAP_EXIT_FILE"
  finish_app_stderr_capture
  capture_app_failure_diagnostics "$failed_pid"
}

require_bootstrap_process_alive() {
  if ax_process_matches_identity "$APP_PID" "$APP_BINARY" "$APP_IDENTITY"; then
    return 0
  fi
  record_unexpected_bootstrap_exit
  ax_emit_failure_category "launch" "performance-bootstrap-exited"
  echo "BLOCKER: performance bootstrap app exited after creating its database schema" >&2
  return 1
}

terminate_bootstrap_app() {
  local bootstrap_pid="${APP_PID:-}"
  local deadline wait_status expected_wait_status termination

  if [[ ! "$bootstrap_pid" =~ ^[0-9]+$ || "$bootstrap_pid" != "${APP_LAUNCH_PID:-}" ]] ||
    ! ax_process_matches_identity "$bootstrap_pid" "$APP_BINARY" "$APP_IDENTITY"; then
    record_unexpected_bootstrap_exit
    ax_emit_failure_category "launch" "performance-bootstrap-exited"
    echo "BLOCKER: performance bootstrap app exited before harness termination" >&2
    return 1
  fi
  if ! kill -TERM "$bootstrap_pid" >/dev/null 2>&1; then
    record_unexpected_bootstrap_exit
    ax_emit_failure_category "launch" "performance-bootstrap-termination-failed"
    echo "BLOCKER: performance bootstrap app could not be terminated by the harness" >&2
    return 1
  fi

  expected_wait_status=143
  termination="harness-term"
  deadline=$((SECONDS + 3))
  while ax_process_matches_identity "$bootstrap_pid" "$APP_BINARY" "$APP_IDENTITY" &&
    [[ "$SECONDS" -lt "$deadline" ]]; do
    sleep 0.1
  done
  if ax_process_matches_identity "$bootstrap_pid" "$APP_BINARY" "$APP_IDENTITY"; then
    if ! kill -KILL "$bootstrap_pid" >/dev/null 2>&1; then
      record_unexpected_bootstrap_exit
      ax_emit_failure_category "launch" "performance-bootstrap-termination-failed"
      echo "BLOCKER: performance bootstrap app ignored harness termination" >&2
      return 1
    fi
    expected_wait_status=137
    termination="harness-kill"
  elif kill -0 "$bootstrap_pid" >/dev/null 2>&1; then
    record_unexpected_bootstrap_exit
    ax_emit_failure_category "launch" "performance-bootstrap-identity-changed"
    echo "BLOCKER: performance bootstrap process identity changed during termination" >&2
    return 1
  fi

  if wait "$bootstrap_pid" 2>/dev/null; then
    wait_status=0
  else
    wait_status=$?
  fi
  finish_app_stderr_capture
  APP_PID=""
  APP_LAUNCH_PID=""
  APP_IDENTITY=""
  APP_LAUNCH_IDENTITY=""
  if [[ "$wait_status" != "$expected_wait_status" ]]; then
    printf 'status=failed\nwait_status=%s\ntermination=unexpected-exit\nfailure_reason=performance-bootstrap-exited\n' \
      "$wait_status" >"$BOOTSTRAP_EXIT_FILE"
    capture_app_failure_diagnostics "$bootstrap_pid"
    ax_emit_failure_category "launch" "performance-bootstrap-exited"
    echo "BLOCKER: performance bootstrap app exited with unexpected wait status $wait_status" >&2
    return 1
  fi
  printf 'status=passed\nwait_status=%s\ntermination=%s\nfailure_reason=none\n' \
    "$wait_status" "$termination" >"$BOOTSTRAP_EXIT_FILE"
}

seed_production_fixture() {
  # A fresh CI workspace otherwise opens the recovery route because it has no
  # projects. Seed one deterministic local project before starting the measured
  # launch so the sample can only pass through the production Project Board.
  if ! sqlite3 "$PERFORMANCE_DATABASE_PATH" <<'SQL'
.bail on
.timeout 5000
BEGIN IMMEDIATE;
DELETE FROM tasks WHERE source_command = 'ui-performance';
DELETE FROM projects WHERE source_command = 'ui-performance';
INSERT INTO projects (
  title, status, priority, deadline, workspace_path, tags_json, source_command,
  created_at, updated_at
) VALUES (
  'UI performance fixture', 'active', 'high', NULL, NULL, '[]', 'ui-performance',
  CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
);
INSERT INTO tasks (
  project_id, title, status, detail, due_at, completed_at, priority,
  source_command, created_at, updated_at
) VALUES (
  (SELECT id FROM projects WHERE source_command = 'ui-performance' ORDER BY id DESC LIMIT 1),
  'Measure production destinations', 'planned',
  'Deterministic local task for production-route launch performance.',
  NULL, NULL, 'high', 'ui-performance', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
);
COMMIT;
SQL
  then
    ax_emit_failure_category "harness" "performance-fixture-seed-failed"
    echo "BLOCKER: performance production fixture could not be seeded" >&2
    return 1
  fi
}

prepare_production_fixture() {
  rm -f "$PERFORMANCE_DATABASE_PATH" "$PERFORMANCE_DATABASE_PATH-wal" "$PERFORMANCE_DATABASE_PATH-shm"
  open_app
  if ! wait_for_database_schema; then
    if ! ax_process_matches_identity "$APP_PID" "$APP_BINARY" "$APP_IDENTITY"; then
      record_unexpected_bootstrap_exit
    fi
    return 1
  fi
  require_bootstrap_process_alive
  terminate_bootstrap_app
  seed_production_fixture
}

try_click_destination() {
  local destination_identifier="$1"
  "$AX_PRESS_ELEMENT_HELPER_EXECUTABLE" "$APP_PID" "$destination_identifier" >/dev/null 2>&1
}

click_sidebar_destination() {
  local destination_identifier="$1"
  local destination_label="$2"
  if ! "$AX_PRESS_ELEMENT_HELPER_EXECUTABLE" "$APP_PID" "$destination_identifier"; then
    ax_emit_failure_category "product-marker" "performance-destination-unavailable"
    echo "BLOCKER: performance smoke could not select $destination_label in owned app pid $APP_PID" >&2
    return 1
  fi
}

run_ax_press_before_deadline() {
  local destination_identifier="$1"
  local deadline_ms="$2"
  local press_status

  if [[ "$(monotonic_ms)" -ge "$deadline_ms" ]]; then
    return 124
  fi
  # Arm the kernel timer before exec replaces this wrapper with the AX helper.
  # The same process is terminated by SIGALRM at the absolute deadline, which
  # avoids both an unbounded TERM wait and a shell PID lookup/reuse race.
  if /usr/bin/perl -MTime::HiRes=clock_gettime,alarm,CLOCK_MONOTONIC -e '
    my $deadline_ms = shift @ARGV;
    my $remaining_seconds =
      ($deadline_ms - (clock_gettime(CLOCK_MONOTONIC) * 1000)) / 1000;
    exit 124 if $remaining_seconds <= 0;
    $SIG{ALRM} = "DEFAULT";
    alarm($remaining_seconds);
    exec @ARGV or exit 126;
  ' "$deadline_ms" "$AX_PRESS_ELEMENT_HELPER_EXECUTABLE" "$APP_PID" "$destination_identifier"; then
    press_status=0
  else
    press_status=$?
  fi
  if [[ "$press_status" -eq 142 || "$(monotonic_ms)" -ge "$deadline_ms" ]]; then
    return 124
  fi
  return "$press_status"
}

click_destination_until_available() {
  local destination_identifier="$1"
  local destination_label="$2"
  local deadline_ms
  deadline_ms=$(($(monotonic_ms) + (TIMEOUT_SECONDS * 1000)))
  local press_status
  while true; do
    if [[ "$(monotonic_ms)" -ge "$deadline_ms" ]]; then
      ax_emit_failure_category "product-marker" "performance-destination-unavailable"
      echo "BLOCKER: performance smoke could not select $destination_label in owned app pid $APP_PID" >&2
      return 1
    fi
    # The retry window increases the time in which macOS could recycle APP_PID.
    # Re-pin every press to the launched binary identity so AX never targets an
    # unrelated process that inherited the same numeric PID.
    if ! ax_process_matches_identity "$APP_PID" "$APP_BINARY" "$APP_IDENTITY"; then
      ax_emit_failure_category "launch" "performance-owned-identity-changed"
      return 1
    fi
    if run_ax_press_before_deadline "$destination_identifier" "$deadline_ms"; then
      return 0
    else
      press_status=$?
    fi
    if [[ "$press_status" -eq 124 || "$(monotonic_ms)" -ge "$deadline_ms" ]]; then
      ax_emit_failure_category "product-marker" "performance-destination-unavailable"
      echo "BLOCKER: performance smoke could not select $destination_label in owned app pid $APP_PID" >&2
      return 1
    fi
    activate_app
    sleep 0.2
  done
}

wait_for_marker() {
  local identifier="$1"
  local safe_identifier="${identifier//[^[:alnum:]_-]/_}"
  local probe_file="$OUTPUT_DIR/wait-$safe_identifier.txt"
  if ax_wait_for_ax_identifier "$APP_NAME" "$identifier" "$TIMEOUT_SECONDS" "$ROOT_DIR" "$probe_file" "" "$APP_PID"; then
    return 0
  fi
  echo "BLOCKER: performance smoke could not inspect the AX marker: $identifier" >&2
  ax_emit_failure_category "product-marker" "performance-marker-unavailable"
  sed -n '1,20p' "$probe_file.err" >&2 || true
  sed -n '1,20p' "$probe_file" >&2 || true
  return 1
}

assert_sample_within_budget() {
  local label="$1"
  local elapsed_ms="$2"
  local budget_ms="$3"
  if [[ -z "$budget_ms" ]]; then
    return 0
  fi
  if [[ ! "$budget_ms" =~ ^[0-9]+$ ]]; then
    echo "BLOCKER: invalid performance budget for $label: $budget_ms" >&2
    return 1
  fi
  if (( elapsed_ms > budget_ms )); then
    printf 'failure_category=performance-budget\n' >&2
    echo "BLOCKER: performance budget exceeded for $label: ${elapsed_ms}ms > ${budget_ms}ms" >&2
    return 1
  fi
}

record_elapsed_sample() {
  local label="$1"
  local elapsed_ms="$2"
  local budget_ms="${3:-}"
  printf '%s\t%s\n' "$label" "$elapsed_ms" >>"$SAMPLES_FILE"
  if [[ -n "$budget_ms" ]]; then
    printf -- '- `%s`: `%sms` (budget `%sms`)\n' "$label" "$elapsed_ms" "$budget_ms" >>"$SUMMARY_FILE"
  else
    printf -- '- `%s`: `%sms`\n' "$label" "$elapsed_ms" >>"$SUMMARY_FILE"
  fi
  assert_sample_within_budget "$label" "$elapsed_ms" "$budget_ms"
  printf "OK: %s completed in %sms\n" "$label" "$elapsed_ms"
}

median_elapsed_ms() {
  if (( $# == 0 || $# % 2 == 0 )); then
    echo "BLOCKER: median performance sample requires a non-zero odd sample count" >&2
    return 2
  fi
  printf '%s\n' "$@" | sort -n | awk -v middle="$((($# + 1) / 2))" 'NR == middle { print; exit }'
}

COLD_LAUNCH_VISIBLE_SAMPLES=()
COLD_LAUNCH_COMMAND_READY_SAMPLES=()
COLD_LAUNCH_TODAY_READY_SAMPLES=()

measure_cold_launch_sample() {
  local sample_index="$1"
  local launch_start_ms visible_window_ms command_ready_ms today_ready_ms
  local visible_elapsed_ms command_ready_elapsed_ms today_ready_elapsed_ms

  launch_start_ms="$(now_ms)"
  rm -f "$TIMELINE_FILE"
  TRACK_LAUNCH_MILESTONES=1
  open_app
  visible_window_ms="$(wait_for_launch_milestone "window-visible")"
  command_ready_ms="$(wait_for_launch_milestone "command-ready")"
  today_ready_ms="$(wait_for_launch_milestone "today-ready")"
  # AX markers remain mandatory proof that the app-owned readiness milestones
  # correspond to real, operable UI rather than optimistic instrumentation.
  wait_for_visible_window
  wait_for_marker "project-board-command-palette"
  wait_for_marker "today-workflow"

  visible_elapsed_ms=$((visible_window_ms - launch_start_ms))
  command_ready_elapsed_ms=$((command_ready_ms - launch_start_ms))
  today_ready_elapsed_ms=$((today_ready_ms - launch_start_ms))
  COLD_LAUNCH_VISIBLE_SAMPLES+=("$visible_elapsed_ms")
  COLD_LAUNCH_COMMAND_READY_SAMPLES+=("$command_ready_elapsed_ms")
  COLD_LAUNCH_TODAY_READY_SAMPLES+=("$today_ready_elapsed_ms")

  # Preserve every raw observation for regression diagnosis. The SLO is
  # enforced on the median below so a single contended runner sample cannot
  # fail an otherwise healthy build.
  record_elapsed_sample "cold-launch-visible-window-sample-$sample_index" "$visible_elapsed_ms"
  record_elapsed_sample "cold-launch-command-ready-sample-$sample_index" "$command_ready_elapsed_ms"
  record_elapsed_sample "cold-launch-today-ready-sample-$sample_index" "$today_ready_elapsed_ms"
}

measure_destination() {
  local label="$1"
  local sample_index="$2"
  local destination_identifier="$3"
  local destination_label="$4"
  local marker="$5"
  local start_ms end_ms
  start_ms="$(now_ms)"
  # SwiftUI can briefly rebuild the sidebar AX subtree after the preceding
  # destination settles. Retry the same owned-PID press within the existing
  # deadline so transient AX absence is not misclassified as a product marker
  # regression; the helper still fails closed when the control stays missing.
  click_destination_until_available "$destination_identifier" "$destination_label"
  wait_for_marker "$marker"
  end_ms="$(now_ms)"
  LAST_DESTINATION_ELAPSED_MS=$((end_ms - start_ms))
  record_elapsed_sample "$label-sample-$sample_index" "$LAST_DESTINATION_ELAPSED_MS"
}

measure_review_assistant_queue() {
  local sample_index="$1"
  local start_ms end_ms
  start_ms="$(now_ms)"
  if try_click_destination "review-destination-assistant-queue"; then
    printf "OK: selected Assistant Queue from wide Review navigation\n"
  else
    # The default CI window can render Review in compact mode. Open the visible
    # chooser and press its stable menu-item identifier without changing the
    # product's adaptive breakpoint solely for performance evidence.
    click_sidebar_destination "review-hub-compact-navigation" "Review view chooser"
    click_destination_until_available "review-hub-compact-destination-assistant-queue" "Assistant Queue"
  fi
  wait_for_marker "assistant-queue-workflow"
  end_ms="$(now_ms)"
  LAST_DESTINATION_ELAPSED_MS=$((end_ms - start_ms))
  record_elapsed_sample "destination-assistant-queue-sample-$sample_index" "$LAST_DESTINATION_ELAPSED_MS"
}

trap cleanup EXIT

{
  printf '%s\n' '# Release Launch Performance Smoke'
  printf '\n'
  printf 'Generated at: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf 'Performance profile: `%s`\n' "$SUISUI_PERFORMANCE_PROFILE"
  printf 'Build configuration: `%s`\n' "$BUILD_CONFIGURATION"
  printf 'Default cold launch budget: `%sms`\n' "$MAX_COLD_LAUNCH_MS"
  printf 'Default destination switch budget: `%sms`\n' "$MAX_DESTINATION_SWITCH_MS"
  printf '\n'
  printf '%s\n' '## Runner quiescence'
  printf -- '- Policy: minimum `%ss` settle, then `%s` consecutive samples at or above `%s%%` CPU idle; fail closed after `%ss`.\n' \
    "$RUNNER_QUIESCENCE_MINIMUM_SETTLE_SECONDS" \
    "$RUNNER_QUIESCENCE_REQUIRED_IDLE_SAMPLES" \
    "$RUNNER_QUIESCENCE_MIN_CPU_IDLE_PERCENT" \
    "$RUNNER_QUIESCENCE_MAX_WAIT_SECONDS"
} >"$SUMMARY_FILE"
printf '%s\t%s\n' "label" "elapsed_ms" >"$SAMPLES_FILE"
printf '%s\t%s\t%s\t%s\n' \
  "sample" "monotonic_ms" "cpu_idle_percent" "consecutive_idle_samples" \
  >"$QUIESCENCE_FILE"

terminate_app
prepare_ax_helpers
if [[ "$SUISUI_PERFORMANCE_USE_PREBUILT_APP" == "1" ]]; then
  performance_artifact_dir="${SUISUI_PERFORMANCE_ARTIFACT_DIR:-}"
  if [[ -z "$performance_artifact_dir" ]]; then
    echo "BLOCKER: SUISUI_PERFORMANCE_ARTIFACT_DIR is required for a prebuilt app" >&2
    exit 2
  fi
  # The measurement process owns verification so a local caller cannot label a
  # stale or debug bundle as trusted merely by setting the prebuilt flag.
  "$ROOT_DIR/script/verify_ui_performance_artifact.sh" \
    "$performance_artifact_dir" \
    "$ROOT_DIR/dist" \
    "$APP_NAME" \
    "$(git rev-parse HEAD)" \
    "$OUTPUT_DIR"
  if [[ ! -f "$APP_BINARY" || -L "$APP_BINARY" || ! -x "$APP_BINARY" ]]; then
    echo "BLOCKER: verified prebuilt performance app is unavailable or not executable" >&2
    exit 2
  fi
  echo "OK: using verified prebuilt release app for performance measurement"
elif [[ "$SUISUI_PERFORMANCE_PROFILE" == "release" ]]; then
  SUISUI_RELEASE_BUILD_PURPOSE=performance \
    SUISUI_BUILD_CONFIGURATION="$BUILD_CONFIGURATION" ./script/build_and_run.sh --build-only
else
  SUISUI_BUILD_CONFIGURATION="$BUILD_CONFIGURATION" ./script/build_and_run.sh --build-only
fi
prepare_production_fixture
wait_for_runner_quiescence
printf '\n%s\n' '## Samples' >>"$SUMMARY_FILE"

for sample_index in $(seq 1 "$COLD_LAUNCH_SAMPLE_COUNT"); do
  measure_cold_launch_sample "$sample_index"
  if (( sample_index < COLD_LAUNCH_SAMPLE_COUNT )); then
    terminate_app
  fi
done

median_visible_window_ms="$(median_elapsed_ms "${COLD_LAUNCH_VISIBLE_SAMPLES[@]}")"
median_command_ready_ms="$(median_elapsed_ms "${COLD_LAUNCH_COMMAND_READY_SAMPLES[@]}")"
median_today_ready_ms="$(median_elapsed_ms "${COLD_LAUNCH_TODAY_READY_SAMPLES[@]}")"
record_elapsed_sample "cold-launch-visible-window" "$median_visible_window_ms"
record_elapsed_sample "cold-launch-command-ready" "$median_command_ready_ms" "$MAX_COLD_LAUNCH_MS"
record_elapsed_sample "cold-launch-today-ready" "$median_today_ready_ms"

# Activation is intentionally outside the cold-launch sample. The product is
# already command-ready; this only gives the AX destination benchmark a stable
# foreground window without charging automation setup to launch latency.
activate_app
# SwiftUI may publish the workflow marker before rebuilding the selectable
# sidebar subtree after activation. Resolve the stable sidebar marker outside
# the measured destination samples so AX setup latency cannot be mistaken for
# a product navigation regression.
wait_for_marker "project-board-sidebar"
DESTINATION_INBOX_SAMPLES=()
DESTINATION_SCHEDULE_SAMPLES=()
DESTINATION_ASSISTANT_QUEUE_SAMPLES=()
DESTINATION_TODAY_SAMPLES=()
LAST_DESTINATION_ELAPSED_MS=""

# Repeat the real navigation cycle instead of pressing an already-selected
# destination. This preserves the product route under test while median
# enforcement filters one contended hosted-runner transition.
for sample_index in $(seq 1 "$DESTINATION_SAMPLE_COUNT"); do
  measure_destination "destination-inbox" "$sample_index" "sidebar-destination-inbox" "Inbox" "inbox-workflow"
  DESTINATION_INBOX_SAMPLES+=("$LAST_DESTINATION_ELAPSED_MS")
  # Schedule is the represented sidebar entry for review workflows. Assistant
  # Queue remains a separately measured nested transition so the benchmark
  # proves both the new IA and the existing review workflow path.
  measure_destination "destination-schedule" "$sample_index" "sidebar-destination-schedule" "Schedule" "schedule-workflow"
  DESTINATION_SCHEDULE_SAMPLES+=("$LAST_DESTINATION_ELAPSED_MS")
  measure_review_assistant_queue "$sample_index"
  DESTINATION_ASSISTANT_QUEUE_SAMPLES+=("$LAST_DESTINATION_ELAPSED_MS")
  measure_destination "destination-today" "$sample_index" "sidebar-destination-today" "Today" "today-workflow"
  DESTINATION_TODAY_SAMPLES+=("$LAST_DESTINATION_ELAPSED_MS")
done

median_destination_inbox_ms="$(median_elapsed_ms "${DESTINATION_INBOX_SAMPLES[@]}")"
median_destination_schedule_ms="$(median_elapsed_ms "${DESTINATION_SCHEDULE_SAMPLES[@]}")"
median_destination_assistant_queue_ms="$(median_elapsed_ms "${DESTINATION_ASSISTANT_QUEUE_SAMPLES[@]}")"
median_destination_today_ms="$(median_elapsed_ms "${DESTINATION_TODAY_SAMPLES[@]}")"
record_elapsed_sample "destination-inbox" "$median_destination_inbox_ms" "$MAX_DESTINATION_SWITCH_MS"
record_elapsed_sample "destination-schedule" "$median_destination_schedule_ms" "$MAX_DESTINATION_SWITCH_MS"
record_elapsed_sample "destination-assistant-queue" "$median_destination_assistant_queue_ms" "$MAX_DESTINATION_SWITCH_MS"
record_elapsed_sample "destination-today" "$median_destination_today_ms" "$MAX_DESTINATION_SWITCH_MS"

printf '\nStatus: passed\n' >>"$SUMMARY_FILE"
printf "OK: release launch performance smoke passed; artifacts written to %s\n" "$OUTPUT_DIR"
