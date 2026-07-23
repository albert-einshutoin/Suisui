#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="${SUISUI_SWIFTPM_ARTIFACT_DIR:-$ROOT_DIR/.tmp/ci-artifacts/swiftpm}"
BASELINE_FILE="${SUISUI_SWIFTPM_TEST_BASELINE_FILE:-$ROOT_DIR/config/quality/swiftpm-test-baseline.txt}"
DISCOVERED_TESTS_FILE="$ARTIFACT_DIR/discovered-tests.txt"
DISCOVERY_LOG_FILE="$ARTIFACT_DIR/discovery.log"
TEST_OUTPUT_FILE="$ARTIFACT_DIR/test-output.log"
SUMMARY_FILE="$ARTIFACT_DIR/swiftpm-test-summary.env"
XUNIT_OUTPUT_FILE="$ARTIFACT_DIR/test-results.xml"
LEGACY_SWIFT_TESTING_XUNIT_FILE="$ARTIFACT_DIR/test-results-swift-testing.xml"
RAW_DISCOVERY_LOG=""

sanitize_swift_output() {
  sed -E \
    -e 's#/(Users|Volumes)/[^[:space:]]+#<path>#g' \
    -e 's#(token|secret|password|api[_-]?key)=[^[:space:]]+#\1=<redacted>#g'
}

read_positive_count() {
  local label="$1"
  local value="$2"
  if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then
    printf 'BLOCKER: %s must be a positive integer, got %s\n' "$label" "${value:-<empty>}" >&2
    return 1
  fi
  printf '%s\n' "$value"
}

validate_test_counts() {
  local discovered_test_count="$1"
  local executed_test_count="$2"
  local baseline_test_count="$3"

  if [[ ! "$discovered_test_count" =~ ^[1-9][0-9]*$ ]]; then
    printf 'BLOCKER: discovered SwiftPM test count must be positive, got %s\n' \
      "${discovered_test_count:-<empty>}" >&2
    return 1
  fi
  if [[ "$discovered_test_count" -lt "$baseline_test_count" ]]; then
    printf 'BLOCKER: discovered SwiftPM test count %s is below baseline %s\n' \
      "$discovered_test_count" "$baseline_test_count" >&2
    return 1
  fi
  if [[ ! "$executed_test_count" =~ ^[1-9][0-9]*$ ]]; then
    printf 'BLOCKER: executed SwiftPM test count must be positive, got %s\n' \
      "${executed_test_count:-<empty>}" >&2
    return 1
  fi
  if [[ "$executed_test_count" -lt "$baseline_test_count" ]]; then
    printf 'BLOCKER: executed SwiftPM test count %s is below baseline %s\n' \
      "$executed_test_count" "$baseline_test_count" >&2
    return 1
  fi
}

write_xunit_summary() {
  local status="$1"
  local baseline_test_count="$2"
  local discovered_test_count="$3"
  local executed_test_count="$4"
  local skipped_test_count="$5"
  local output_file="$6"
  local failure_count=0
  local failure_element=""
  if [[ "$status" != "passed" ]]; then
    failure_count=1
    failure_element='    <failure message="Complete SwiftPM test gate failed; inspect sanitized test-output.log." />'
  fi
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '<testsuite name="Suisui SwiftPM complete suite" tests="1" failures="%s" skipped="0">\n' \
      "$failure_count"
    printf '%s\n' '  <properties>'
    printf '    <property name="baseline_test_count" value="%s" />\n' "$baseline_test_count"
    printf '    <property name="discovered_test_count" value="%s" />\n' "$discovered_test_count"
    printf '    <property name="executed_test_count" value="%s" />\n' "$executed_test_count"
    printf '    <property name="skipped_test_count" value="%s" />\n' "$skipped_test_count"
    printf '%s\n' '  </properties>'
    printf '%s\n' '  <testcase classname="Suisui.CI" name="complete-swiftpm-suite">'
    if [[ -n "$failure_element" ]]; then
      printf '%s\n' "$failure_element"
    fi
    printf '%s\n' '  </testcase>'
    printf '%s\n' '</testsuite>'
  } >"$output_file"
}

run_fixture_self_tests() {
  local fixture_dir
  local fixture_xunit
  if validate_test_counts 3 3 3 >/dev/null 2>&1; then
    printf 'fixture=valid status=passed\n'
  else
    printf 'fixture=valid status=unexpected-failure\n' >&2
    return 1
  fi

  if validate_test_counts 0 0 3 >/dev/null 2>&1; then
    printf 'fixture=zero-target status=unexpected-pass\n' >&2
    return 1
  else
    printf 'fixture=zero-target status=blocked\n'
  fi

  if validate_test_counts 2 2 3 >/dev/null 2>&1; then
    printf 'fixture=below-baseline status=unexpected-pass\n' >&2
    return 1
  else
    printf 'fixture=below-baseline status=blocked\n'
  fi

  if validate_test_counts 3 "" 3 >/dev/null 2>&1; then
    printf 'fixture=missing-execution-summary status=unexpected-pass\n' >&2
    return 1
  else
    printf 'fixture=missing-execution-summary status=blocked\n'
  fi

  fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/suisui-swiftpm-runner-self-test.XXXXXX")"
  fixture_xunit="$fixture_dir/test-results.xml"
  write_xunit_summary passed 3 3 3 0 "$fixture_xunit"
  if ! grep -q 'executed_test_count" value="3"' "$fixture_xunit"; then
    rm -rf "$fixture_dir"
    printf 'fixture=xunit-summary status=invalid\n' >&2
    return 1
  fi
  rm -rf "$fixture_dir"
  printf 'fixture=xunit-summary status=passed\n'

  printf 'OK: complete SwiftPM test runner fixture self-tests passed\n'
}

if [[ "${1:-}" == "--self-test" ]]; then
  if [[ $# -ne 1 ]]; then
    echo "usage: $0 [--self-test]" >&2
    exit 2
  fi
  run_fixture_self_tests
  exit 0
fi
if [[ $# -ne 0 ]]; then
  echo "usage: $0 [--self-test]" >&2
  exit 2
fi

mkdir -p "$ARTIFACT_DIR"
rm -f \
  "$DISCOVERED_TESTS_FILE" \
  "$DISCOVERY_LOG_FILE" \
  "$TEST_OUTPUT_FILE" \
  "$SUMMARY_FILE" \
  "$XUNIT_OUTPUT_FILE" \
  "$LEGACY_SWIFT_TESTING_XUNIT_FILE"
RAW_DISCOVERY_LOG="$(mktemp "$ARTIFACT_DIR/discovery.raw.XXXXXX")"
trap 'rm -f "$RAW_DISCOVERY_LOG"' EXIT INT TERM

baseline_test_count="$(read_positive_count \
  "baseline SwiftPM test count" \
  "$(tr -d '[:space:]' <"$BASELINE_FILE" 2>/dev/null || true)")"

cd "$ROOT_DIR"

discovery_status=0
set +e
swift test list >"$DISCOVERED_TESTS_FILE" 2>"$RAW_DISCOVERY_LOG"
discovery_status=$?
set -e
sanitize_swift_output <"$RAW_DISCOVERY_LOG" >"$DISCOVERY_LOG_FILE"
rm -f "$RAW_DISCOVERY_LOG"
RAW_DISCOVERY_LOG=""
if [[ "$discovery_status" -ne 0 ]]; then
  cat "$DISCOVERY_LOG_FILE" >&2
  printf 'BLOCKER: SwiftPM test discovery failed\n' >&2
  exit "$discovery_status"
fi

discovered_test_count="$(awk 'NF { count += 1 } END { print count + 0 }' "$DISCOVERED_TESTS_FILE")"
if ! validate_test_counts "$discovered_test_count" "$baseline_test_count" "$baseline_test_count" >/dev/null; then
  printf 'status=failed\nbaseline_test_count=%s\ndiscovered_test_count=%s\nexecuted_test_count=0\nskipped_test_count=0\n' \
    "$baseline_test_count" "$discovered_test_count" >"$SUMMARY_FILE"
  write_xunit_summary failed "$baseline_test_count" "$discovered_test_count" 0 0 "$XUNIT_OUTPUT_FILE"
  exit 1
fi

test_status=0
set +e
swift test 2>&1 | sanitize_swift_output | tee "$TEST_OUTPUT_FILE"
test_status=${PIPESTATUS[0]}
set -e

executed_test_count="$(
  sed -nE 's/.*Executed ([0-9]+) tests?.*/\1/p' "$TEST_OUTPUT_FILE" | tail -n 1
)"
skipped_test_count="$(
  sed -nE 's/.*with ([0-9]+) tests? skipped.*/\1/p' "$TEST_OUTPUT_FILE" | tail -n 1
)"
skipped_test_count="${skipped_test_count:-0}"
status_label="passed"
if [[ "$test_status" -ne 0 ]]; then
  status_label="failed"
fi

printf 'status=%s\nbaseline_test_count=%s\ndiscovered_test_count=%s\nexecuted_test_count=%s\nskipped_test_count=%s\n' \
  "$status_label" \
  "$baseline_test_count" \
  "$discovered_test_count" \
  "${executed_test_count:-0}" \
  "$skipped_test_count" \
  >"$SUMMARY_FILE"
write_xunit_summary \
  "$status_label" \
  "$baseline_test_count" \
  "$discovered_test_count" \
  "${executed_test_count:-0}" \
  "$skipped_test_count" \
  "$XUNIT_OUTPUT_FILE"

if [[ "$test_status" -ne 0 ]]; then
  printf 'BLOCKER: complete SwiftPM test suite failed with exit code %s\n' "$test_status" >&2
  exit "$test_status"
fi
validate_test_counts "$discovered_test_count" "$executed_test_count" "$baseline_test_count"
printf 'OK: complete SwiftPM suite passed (%s discovered, %s executed, %s skipped)\n' \
  "$discovered_test_count" "$executed_test_count" "$skipped_test_count"
