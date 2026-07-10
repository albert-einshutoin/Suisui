#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CI_TMP_ROOT="${SOLOPM_CI_TMP_ROOT:-$ROOT_DIR/.tmp}"
CI_TMPDIR_CREATED=0
CI_RUNTIME_GATES="${SOLOPM_CI_RUNTIME_GATES:-0}"
CI_VISUAL_GATES="${SOLOPM_CI_VISUAL_GATES:-0}"
CI_RELEASE_GATES="${SOLOPM_CI_RELEASE_GATES:-0}"
CI_PERFORMANCE_GATES="${SOLOPM_CI_PERFORMANCE_GATES:-0}"
CI_STRESS_GATES="${SOLOPM_CI_STRESS_GATES:-0}"
CI_LANE="${1:-${SOLOPM_CI_LANE:-swiftpm}}"
CI_LANE_WAS_EXPLICIT=0
CI_ARTIFACT_ROOT="${SOLOPM_CI_ARTIFACT_ROOT:-$ROOT_DIR/.tmp/ci-artifacts}"
UI_GATE_LOCK_DIR="${SOLOPM_UI_GATE_LOCK_DIR:-/tmp/solopm-ui-gate-${UID}.lock}"
UI_GATE_LOCK_TIMEOUT_SECONDS="${SOLOPM_UI_GATE_LOCK_TIMEOUT_SECONDS:-180}"
UI_GATE_LOCK_ACQUIRED=0

if [[ $# -gt 1 ]]; then
  echo "usage: $0 [swiftpm|ui-runtime|ui-visual|ui-performance]" >&2
  exit 2
fi
if [[ $# -eq 1 || -n "${SOLOPM_CI_LANE:-}" ]]; then
  CI_LANE_WAS_EXPLICIT=1
fi

mkdir -p "$CI_TMP_ROOT" "$CI_ARTIFACT_ROOT"

if [[ -n "${SOLOPM_CI_TMPDIR:-}" ]]; then
  CI_TMPDIR="${SOLOPM_CI_TMPDIR%/}"
  mkdir -p "$CI_TMPDIR"
else
  CI_TMPDIR="$(mktemp -d "$CI_TMP_ROOT/solopm-ci-tmp.XXXXXX")"
  CI_TMPDIR_CREATED=1
fi

export TMPDIR="$CI_TMPDIR/"

release_ui_gate_lock() {
  if [[ "$UI_GATE_LOCK_ACQUIRED" == "1" ]]; then
    rm -f "$UI_GATE_LOCK_DIR/owner-pid"
    rmdir "$UI_GATE_LOCK_DIR" >/dev/null 2>&1 || true
    UI_GATE_LOCK_ACQUIRED=0
  fi
}

cleanup_ci_tmpdir() {
  if [[ "$CI_TMPDIR_CREATED" == "1" ]]; then
    rm -rf "$CI_TMPDIR"
    CI_TMPDIR_CREATED=0
  fi
}

cleanup_ci() {
  release_ui_gate_lock
  cleanup_ci_tmpdir
}
trap cleanup_ci EXIT INT TERM

cd "$ROOT_DIR"

validate_ci_flag() {
  local name="$1"
  local value="$2"
  if [[ "$value" != "0" && "$value" != "1" ]]; then
    echo "BLOCKER: $name must be 0 or 1" >&2
    exit 2
  fi
}

validate_positive_integer() {
  local name="$1"
  local value="$2"
  if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then
    echo "BLOCKER: $name must be a positive integer" >&2
    exit 2
  fi
}

acquire_ui_gate_lock() {
  if [[ "$UI_GATE_LOCK_ACQUIRED" == "1" ]]; then
    return 0
  fi
  local deadline=$((SECONDS + UI_GATE_LOCK_TIMEOUT_SECONDS))
  local owner_pid=""
  local lock_owner=""
  while ! mkdir "$UI_GATE_LOCK_DIR" >/dev/null 2>&1; do
    # UI automation shares one WindowServer session. A host-wide lock prevents
    # otherwise-correct PID-scoped gates from competing for focus and capture.
    if [[ -d "$UI_GATE_LOCK_DIR" && ! -L "$UI_GATE_LOCK_DIR" ]]; then
      lock_owner="$(stat -f '%Su' "$UI_GATE_LOCK_DIR" 2>/dev/null || true)"
      owner_pid="$(sed -n '1p' "$UI_GATE_LOCK_DIR/owner-pid" 2>/dev/null || true)"
      if [[ "$lock_owner" == "$(id -un)" && "$owner_pid" =~ ^[1-9][0-9]*$ ]] && ! kill -0 "$owner_pid" >/dev/null 2>&1; then
        rm -f "$UI_GATE_LOCK_DIR/owner-pid"
        rmdir "$UI_GATE_LOCK_DIR" >/dev/null 2>&1 || true
        continue
      fi
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "failure_category=harness" >&2
      echo "BLOCKER: timed out waiting for the host UI gate lock" >&2
      return 1
    fi
    sleep 1
  done
  printf '%s\n' "$$" >"$UI_GATE_LOCK_DIR/owner-pid"
  UI_GATE_LOCK_ACQUIRED=1
}

run_pr_gate() {
  swift test --filter AppExperienceSourceTests
  swift test --filter QualitySourceContractTests
  script/check_pseudo_voiceover_paths.sh --swift-test
  swift test --filter ProjectBoardStoreTests
  swift build
  swift build --product solopm-cli
  ./script/build_and_run.sh --build-only
}

run_release_gates() {
  swift test --filter ReleasePipelineTests
}

run_performance_gates() {
  local artifact_dir="$CI_ARTIFACT_ROOT/ui-performance"
  SOLOPM_UI_RUNNER_CAPABILITY_ARTIFACT_DIR="$artifact_dir/runner-capability" \
    ./script/check_macos_ui_runner_capabilities.sh performance
  SOLOPM_PERFORMANCE_PROFILE="${SOLOPM_PERFORMANCE_PROFILE:-debug}" \
  SOLOPM_PERFORMANCE_BUILD_CONFIGURATION="${SOLOPM_PERFORMANCE_BUILD_CONFIGURATION:-debug}" \
  SOLOPM_PERFORMANCE_OUTPUT_DIR="$artifact_dir/performance" \
  SOLOPM_PERFORMANCE_HOME="$CI_TMPDIR/ui-performance-home" \
    ./script/check_release_launch_performance_smoke.sh
}

run_stress_gates() {
  ./script/check_performance_stress_suite.sh
}

run_build_and_run_verify() {
  local artifact_dir="$1"
  local verify_tmp="$CI_TMPDIR/build-and-run-verify"
  local verify_artifact_dir="$artifact_dir/build-and-run-verify"
  local verify_status=0
  local source_file
  rm -rf "$verify_tmp" "$verify_artifact_dir"
  mkdir -p "$verify_tmp" "$verify_artifact_dir"

  set +e
  SOLOPM_TMPDIR="$verify_tmp" ./script/build_and_run.sh --verify
  verify_status=$?
  set -e

  # Only copy the path-free AX/window diagnostics. SwiftPM locks, temporary
  # filenames, and the isolated SQLite database are intentionally excluded.
  for source_file in "$verify_tmp"/verify/*.txt "$verify_tmp"/verify/*.err; do
    [[ -f "$source_file" ]] || continue
    cp "$source_file" "$verify_artifact_dir/$(basename "$source_file")"
  done
  return "$verify_status"
}

run_runtime_gates() {
  local artifact_dir="$CI_ARTIFACT_ROOT/ui-runtime"
  SOLOPM_UI_RUNNER_CAPABILITY_ARTIFACT_DIR="$artifact_dir/runner-capability" \
    ./script/check_macos_ui_runner_capabilities.sh runtime
  run_build_and_run_verify "$artifact_dir"
  SOLOPM_RUNTIME_ACCESSIBLE_CRUD_ARTIFACT_DIR="$artifact_dir/runtime-accessible-crud" \
    ./script/check_runtime_accessible_crud_smoke.sh
  SOLOPM_LAYOUT_STABILITY_OUTPUT_DIR="$artifact_dir/layout-stability" \
  SOLOPM_LAYOUT_STABILITY_RUNTIME_DIR="$CI_TMPDIR/layout-stability-runtime" \
    ./script/check_layout_stability_smoke.sh
  SOLOPM_RUNTIME_TODAY_PRODUCTION_ROUTE_ARTIFACT_DIR="$artifact_dir/today-production-route" \
    ./script/check_runtime_today_production_route_smoke.sh
}

run_visual_gates() {
  SOLOPM_CI_VISUAL_GATE_OUTPUT_DIR="$CI_ARTIFACT_ROOT/ui-visual" \
    ./script/check_ci_visual_gate.sh
}

sanitize_gate_log() {
  local input="$1"
  local output="$2"
  sed -E \
    -e 's#/(Users|Volumes)/[^[:space:]]+#<path>#g' \
    -e 's#(token|secret|password|api[_-]?key)=[^[:space:]]+#\1=<redacted>#g' \
    "$input" >"$output"
}

run_lane_with_artifacts() {
  local lane="$1"
  local lane_function="$2"
  local lane_dir="$CI_ARTIFACT_ROOT/$lane"
  local raw_log="$CI_TMPDIR/$lane.raw.log"
  local status=0
  local category="passed"
  rm -rf "$lane_dir"
  mkdir -p "$lane_dir"

  set +e
  (set -e; "$lane_function") 2>&1 | tee "$raw_log"
  status=${PIPESTATUS[0]}
  set -e

  sanitize_gate_log "$raw_log" "$lane_dir/output.log"
  rm -f "$raw_log"
  if [[ "$status" -ne 0 ]]; then
    category="$(sed -n 's/^failure_category=//p' "$lane_dir/output.log" | tail -n 1)"
    if [[ -z "$category" ]]; then
      case "$lane" in
        ui-runtime|ui-performance) category="app-regression" ;;
        ui-visual) category="visual" ;;
        *) category="harness" ;;
      esac
    fi
  fi
  printf 'lane=%s\nstatus=%s\nfailure_category=%s\n' \
    "$lane" "$([[ "$status" -eq 0 ]] && printf passed || printf failed)" "$category" \
    >"$lane_dir/gate-summary.txt"
  return "$status"
}

validate_ci_flag "SOLOPM_CI_RUNTIME_GATES" "$CI_RUNTIME_GATES"
validate_ci_flag "SOLOPM_CI_VISUAL_GATES" "$CI_VISUAL_GATES"
validate_ci_flag "SOLOPM_CI_RELEASE_GATES" "$CI_RELEASE_GATES"
validate_ci_flag "SOLOPM_CI_PERFORMANCE_GATES" "$CI_PERFORMANCE_GATES"
validate_ci_flag "SOLOPM_CI_STRESS_GATES" "$CI_STRESS_GATES"
validate_positive_integer "SOLOPM_UI_GATE_LOCK_TIMEOUT_SECONDS" "$UI_GATE_LOCK_TIMEOUT_SECONDS"

case "$CI_LANE" in
  swiftpm)
    run_pr_gate
    ;;
  ui-runtime)
    acquire_ui_gate_lock
    run_lane_with_artifacts "ui-runtime" run_runtime_gates
    ;;
  ui-visual)
    acquire_ui_gate_lock
    run_lane_with_artifacts "ui-visual" run_visual_gates
    ;;
  ui-performance)
    acquire_ui_gate_lock
    run_lane_with_artifacts "ui-performance" run_performance_gates
    ;;
  *)
    echo "usage: $0 [swiftpm|ui-runtime|ui-visual|ui-performance]" >&2
    exit 2
    ;;
esac

# Keep the legacy flag interface for contributors and older automation. New
# workflow jobs pass an explicit lane so the lightweight suite is not repeated.
if [[ "$CI_LANE_WAS_EXPLICIT" == "0" ]]; then
  if [[ "$CI_RELEASE_GATES" == "1" ]]; then
    run_release_gates
  fi
  if [[ "$CI_PERFORMANCE_GATES" == "1" ]]; then
    acquire_ui_gate_lock
    run_lane_with_artifacts "ui-performance" run_performance_gates
  fi
  if [[ "$CI_STRESS_GATES" == "1" ]]; then
    run_stress_gates
  fi
  if [[ "$CI_RUNTIME_GATES" == "1" ]]; then
    acquire_ui_gate_lock
    run_lane_with_artifacts "ui-runtime" run_runtime_gates
  fi
  if [[ "$CI_VISUAL_GATES" == "1" ]]; then
    acquire_ui_gate_lock
    run_lane_with_artifacts "ui-visual" run_visual_gates
  fi
fi
