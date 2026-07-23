#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CI_TMP_ROOT="${SUISUI_CI_TMP_ROOT:-$ROOT_DIR/.tmp}"
CI_TMPDIR_CREATED=0
CI_RUNTIME_GATES="${SUISUI_CI_RUNTIME_GATES:-0}"
CI_VISUAL_GATES="${SUISUI_CI_VISUAL_GATES:-0}"
CI_RELEASE_GATES="${SUISUI_CI_RELEASE_GATES:-0}"
CI_PERFORMANCE_GATES="${SUISUI_CI_PERFORMANCE_GATES:-0}"
CI_STRESS_GATES="${SUISUI_CI_STRESS_GATES:-0}"
CI_LANE="${1:-${SUISUI_CI_LANE:-swiftpm}}"
CI_LANE_WAS_EXPLICIT=0
CI_ARTIFACT_ROOT="${SUISUI_CI_ARTIFACT_ROOT:-$ROOT_DIR/.tmp/ci-artifacts}"
UI_GATE_LOCK_DIR="${SUISUI_UI_GATE_LOCK_DIR:-/tmp/suisui-ui-gate-${UID}.lock}"
UI_GATE_LOCK_TIMEOUT_SECONDS="${SUISUI_UI_GATE_LOCK_TIMEOUT_SECONDS:-180}"
UI_GATE_LOCK_ACQUIRED=0

if [[ $# -gt 1 ]]; then
  echo "usage: $0 [swiftpm|source-contracts|ui-runtime|ui-visual|ui-performance]" >&2
  exit 2
fi
if [[ $# -eq 1 || -n "${SUISUI_CI_LANE:-}" ]]; then
  CI_LANE_WAS_EXPLICIT=1
fi

mkdir -p "$CI_TMP_ROOT" "$CI_ARTIFACT_ROOT"

if [[ -n "${SUISUI_CI_TMPDIR:-}" ]]; then
  CI_TMPDIR="${SUISUI_CI_TMPDIR%/}"
  mkdir -p "$CI_TMPDIR"
else
  CI_TMPDIR="$(mktemp -d "$CI_TMP_ROOT/suisui-ci-tmp.XXXXXX")"
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
  ./script/run_complete_swiftpm_tests.sh
  swift build
  swift build --product suisui-cli
  ./script/build_and_run.sh --build-only
}

run_source_contract_gates() {
  swift test --filter AppExperienceSourceTests
  swift test --filter QualitySourceContractTests
  script/check_pseudo_voiceover_paths.sh --swift-test
  swift test --filter ProjectBoardStoreTests
}

run_release_gates() {
  swift test --filter ReleasePipelineTests
}

run_performance_gates() {
  local artifact_dir="$CI_ARTIFACT_ROOT/ui-performance"
  SUISUI_UI_RUNNER_CAPABILITY_ARTIFACT_DIR="$artifact_dir/runner-capability" \
    ./script/check_macos_ui_runner_capabilities.sh performance
  # The production-route lane must fail closed against the public Release SLO.
  # Debug remains available only through an explicit local override.
  SUISUI_PERFORMANCE_PROFILE="${SUISUI_PERFORMANCE_PROFILE:-release}" \
  SUISUI_PERFORMANCE_BUILD_CONFIGURATION="${SUISUI_PERFORMANCE_BUILD_CONFIGURATION:-release}" \
  SUISUI_PERFORMANCE_OUTPUT_DIR="$artifact_dir/performance" \
  SUISUI_PERFORMANCE_HOME="$CI_TMPDIR/ui-performance-home" \
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
  SUISUI_TMPDIR="$verify_tmp" ./script/build_and_run.sh --verify
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

read_capability_positive_dimension() {
  local summary_file="$1"
  local key="$2"
  awk -F= -v key="$key" '
    $1 == key {
      count += 1
      if (NF != 2 || $2 !~ /^[1-9][0-9]*$/) invalid = 1
      value = $2
    }
    END {
      if (count != 1 || invalid) exit 1
      print value
    }
  ' "$summary_file"
}

read_layout_visible_frame_dimensions() {
  local capability_summary="$1"
  local visible_frame_width
  local visible_frame_height
  if ! visible_frame_width="$(read_capability_positive_dimension "$capability_summary" display_visible_frame_width)" ||
    ! visible_frame_height="$(read_capability_positive_dimension "$capability_summary" display_visible_frame_height)"; then
    printf 'failure_category=runner-capability\n' >&2
    printf 'failure_reason=invalid-display-geometry-summary\n' >&2
    printf 'BLOCKER: UI runner capability summary must contain exactly one positive integer visible-frame width and height.\n' >&2
    return 1
  fi
  printf '%s %s\n' "$visible_frame_width" "$visible_frame_height"
}

layout_capacity_is_known_limitation() {
  local capacity_log="$1"
  awk '
    /^failure_category=/ {
      category_count += 1
      if ($0 != "failure_category=runner-capability") invalid = 1
    }
    /^failure_reason=/ {
      reason_count += 1
      if ($0 != "failure_reason=layout-visible-frame-too-small") invalid = 1
    }
    END {
      if (category_count != 1 || reason_count != 1 || invalid) exit 1
    }
  ' "$capacity_log"
}

run_layout_stability_gate() {
  local artifact_dir="$1"
  local visible_frame_width="$2"
  local visible_frame_height="$3"
  local layout_dir="$artifact_dir/layout-stability"
  local capacity_log="$layout_dir/layout-capacity.log"
  local capacity_summary="$layout_dir/layout-capacity-summary.env"
  local capacity_status=0
  local runtime_status=0
  mkdir -p "$layout_dir"

  set +e
  SUISUI_LAYOUT_STABILITY_VISIBLE_FRAME_WIDTH="$visible_frame_width" \
  SUISUI_LAYOUT_STABILITY_VISIBLE_FRAME_HEIGHT="$visible_frame_height" \
    ./script/check_layout_stability_smoke.sh --check-display-capacity \
    >"$capacity_log" 2>&1
  capacity_status=$?
  set -e

  if [[ "$capacity_status" -eq 0 ]]; then
    cat "$capacity_log"
    printf 'status=capable\nproduct_contract=unchanged\n' >"$capacity_summary"
    set +e
    SUISUI_LAYOUT_STABILITY_OUTPUT_DIR="$layout_dir" \
    SUISUI_LAYOUT_STABILITY_RUNTIME_DIR="$CI_TMPDIR/layout-stability-runtime" \
    SUISUI_LAYOUT_STABILITY_VISIBLE_FRAME_WIDTH="$visible_frame_width" \
    SUISUI_LAYOUT_STABILITY_VISIBLE_FRAME_HEIGHT="$visible_frame_height" \
      ./script/check_layout_stability_smoke.sh
    runtime_status=$?
    set -e
    return "$runtime_status"
  fi

  if [[ "$capacity_status" -eq 1 ]] && layout_capacity_is_known_limitation "$capacity_log"; then
    # Hosted macOS runners can be smaller than the immutable product window
    # contract. Record an explicit non-execution instead of weakening the
    # product floor or reporting a fake layout pass; capable local/release
    # runners remain responsible for the wide-window evidence.
    printf 'status=not-exercised\nfailure_category=runner-capability\nfailure_reason=layout-visible-frame-too-small\nproduct_contract=unchanged\n' \
      >"$capacity_summary"
    printf 'gate_notice_category=runner-capability\n'
    printf 'NOTICE: layout stability was not exercised because this runner is smaller than the immutable product contract.\n'
    return 0
  fi

  # Unexpected probe output remains lane-visible so its own exact failure
  # category can classify the failed gate. The known limitation above uses a
  # notice-only marker, preventing it from contaminating a later gate failure.
  cat "$capacity_log"
  return "$capacity_status"
}

run_runtime_gates() {
  local artifact_dir="$CI_ARTIFACT_ROOT/ui-runtime"
  local capability_summary="$artifact_dir/runner-capability/ui-runner-capability-summary.env"
  local visible_frame_dimensions
  local visible_frame_width
  local visible_frame_height
  SUISUI_UI_RUNNER_CAPABILITY_ARTIFACT_DIR="$artifact_dir/runner-capability" \
    ./script/check_macos_ui_runner_capabilities.sh runtime
  if ! visible_frame_dimensions="$(read_layout_visible_frame_dimensions "$capability_summary")"; then
    return 1
  fi
  read -r visible_frame_width visible_frame_height <<<"$visible_frame_dimensions"
  run_build_and_run_verify "$artifact_dir"
  SUISUI_RUNTIME_ACCESSIBLE_CRUD_ARTIFACT_DIR="$artifact_dir/runtime-accessible-crud" \
    ./script/check_runtime_accessible_crud_smoke.sh
  run_layout_stability_gate "$artifact_dir" "$visible_frame_width" "$visible_frame_height"
  SUISUI_RUNTIME_TODAY_PRODUCTION_ROUTE_ARTIFACT_DIR="$artifact_dir/today-production-route" \
    ./script/check_runtime_today_production_route_smoke.sh
}

run_visual_gates() {
  SUISUI_CI_VISUAL_GATE_OUTPUT_DIR="$CI_ARTIFACT_ROOT/ui-visual" \
    ./script/check_ci_visual_gate.sh
}

sanitize_gate_log() {
  local input="$1"
  local output="${2:-}"
  # When invoked with `-` as the input path, the sanitizer reads from
  # stdin and writes to stdout so the caller can pipe the lane output
  # through the sanitizer before `tee` exposes it to the Actions job
  # log. The path- and secret-pattern redactions are shared with the
  # file mode so the runtime/file pipelines stay equivalent.
  if [[ "$input" == "-" ]]; then
    sed -E \
      -e 's#/(Users|Volumes)/[^[:space:]]+#<path>#g' \
      -e 's#(token|secret|password|api[_-]?key)=[^[:space:]]+#\1=<redacted>#g'
    return 0
  fi
  if [[ -z "$output" ]]; then
    echo "BLOCKER: sanitize_gate_log output path is required in file mode" >&2
    return 2
  fi
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
  local status_label="passed"
  local category="passed"
  local notice_category=""
  rm -rf "$lane_dir"
  mkdir -p "$lane_dir"

  set +e
  # Pipe the lane output through the sanitizer before `tee` so the Actions
  # job log only ever sees redacted stdout/stderr. The sanitized stream is
  # the single source of truth for both the captured artifact and the
  # GitHub Actions log; the raw log never reaches the public surface.
  (set -e; "$lane_function") 2>&1 | sanitize_gate_log - | tee "$raw_log"
  status=${PIPESTATUS[0]}
  set -e

  cp "$raw_log" "$lane_dir/output.log"
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
    status_label="failed"
  else
    notice_category="$(sed -n 's/^gate_notice_category=//p' "$lane_dir/output.log" | tail -n 1)"
    if [[ -n "$notice_category" ]]; then
      category="$notice_category"
      status_label="passed-with-limitation"
    fi
  fi
  printf 'lane=%s\nstatus=%s\nfailure_category=%s\n' \
    "$lane" "$status_label" "$category" \
    >"$lane_dir/gate-summary.txt"
  return "$status"
}

validate_ci_flag "SUISUI_CI_RUNTIME_GATES" "$CI_RUNTIME_GATES"
validate_ci_flag "SUISUI_CI_VISUAL_GATES" "$CI_VISUAL_GATES"
validate_ci_flag "SUISUI_CI_RELEASE_GATES" "$CI_RELEASE_GATES"
validate_ci_flag "SUISUI_CI_PERFORMANCE_GATES" "$CI_PERFORMANCE_GATES"
validate_ci_flag "SUISUI_CI_STRESS_GATES" "$CI_STRESS_GATES"
validate_positive_integer "SUISUI_UI_GATE_LOCK_TIMEOUT_SECONDS" "$UI_GATE_LOCK_TIMEOUT_SECONDS"

case "$CI_LANE" in
  swiftpm)
    run_pr_gate
    ;;
  source-contracts)
    run_source_contract_gates
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
    echo "usage: $0 [swiftpm|source-contracts|ui-runtime|ui-visual|ui-performance]" >&2
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
