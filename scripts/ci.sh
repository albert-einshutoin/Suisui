#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CI_TMP_ROOT="${SOLOPM_CI_TMP_ROOT:-$ROOT_DIR/.tmp}"
CI_TMPDIR_CREATED=0
CI_RUNTIME_GATES="${SOLOPM_CI_RUNTIME_GATES:-0}"
CI_VISUAL_GATES="${SOLOPM_CI_VISUAL_GATES:-0}"
CI_RELEASE_GATES="${SOLOPM_CI_RELEASE_GATES:-0}"

mkdir -p "$CI_TMP_ROOT"

if [[ -n "${SOLOPM_CI_TMPDIR:-}" ]]; then
  CI_TMPDIR="${SOLOPM_CI_TMPDIR%/}"
  mkdir -p "$CI_TMPDIR"
else
  CI_TMPDIR="$(mktemp -d "$CI_TMP_ROOT/solopm-ci-tmp.XXXXXX")"
  CI_TMPDIR_CREATED=1
fi

export TMPDIR="$CI_TMPDIR/"

cleanup_ci_tmpdir() {
  if [[ "${CI_TMPDIR_CREATED:-0}" == "1" ]]; then
    rm -rf "$CI_TMPDIR"
    CI_TMPDIR_CREATED=0
  fi
}

cleanup_ci() {
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

run_pr_gate() {
  # PR CI intentionally stays source/unit oriented so local contributors can run
  # the same command without requiring Screen Recording, a visible app, or visual baselines.
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

run_runtime_gates() {
  script/check_runtime_accessible_crud_smoke.sh
  script/check_layout_stability_smoke.sh
  script/check_accessibility_preflight.sh --runtime
}

run_visual_gates() {
  script/check_visual_regression_smoke.sh
}

validate_ci_flag "SOLOPM_CI_RUNTIME_GATES" "$CI_RUNTIME_GATES"
validate_ci_flag "SOLOPM_CI_VISUAL_GATES" "$CI_VISUAL_GATES"
validate_ci_flag "SOLOPM_CI_RELEASE_GATES" "$CI_RELEASE_GATES"

run_pr_gate
if [[ "$CI_RELEASE_GATES" == "1" ]]; then
  run_release_gates
fi
if [[ "$CI_RUNTIME_GATES" == "1" ]]; then
  run_runtime_gates
fi
if [[ "$CI_VISUAL_GATES" == "1" ]]; then
  run_visual_gates
fi
