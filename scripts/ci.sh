#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CI_TMP_ROOT="${SOLOPM_CI_TMP_ROOT:-$ROOT_DIR/.tmp}"
CI_TMPDIR_CREATED=0

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

swift test
swift build
swift build --product solopm-cli
./script/build_and_run.sh --build-only
