#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="${SUISUI_SWIFTPM_ARTIFACT_DIR:-$ROOT_DIR/.tmp/ci-artifacts/swiftpm}"
BASELINE_FILE="${SUISUI_SWIFTPM_TEST_BASELINE_FILE:-$ROOT_DIR/config/quality/swiftpm-test-baseline.txt}"
MAX_SKIPPED_FILE="${SUISUI_SWIFTPM_MAX_SKIPPED_FILE:-$ROOT_DIR/config/quality/swiftpm-max-skipped-tests.txt}"
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
    -e 's#/private/var/folders/[^[:space:]]+#<temp-path>#g' \
    -e 's#(/var)?/tmp/[^[:space:]]+#<temp-path>#g' \
    -e 's#(Authorization[[:space:]]*:[[:space:]]*Bearer)[[:space:]]+[^[:space:]]+#\1 <redacted>#Ig' \
    -e 's#(^|[^[:alnum:]_])sk-[A-Za-z0-9_-]{8,}#\1<redacted>#g' \
    -e 's#github_pat_[A-Za-z0-9_]{8,}#<redacted>#g' \
    -e 's#gh[pousr]_[A-Za-z0-9_]{8,}#<redacted>#g' \
    -e 's#xox[baprs]-[A-Za-z0-9-]{8,}#<redacted>#g' \
    -e 's#AKIA[0-9A-Z]{16}#<redacted>#g' \
    -e 's#(token|secret|password|api[_-]?key)[[:space:]]*[=:][[:space:]]*[^[:space:]]+#\1=<redacted>#Ig'
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

read_nonnegative_count() {
  local label="$1"
  local value="$2"
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    printf 'BLOCKER: %s must be a non-negative integer, got %s\n' "$label" "${value:-<empty>}" >&2
    return 1
  fi
  printf '%s\n' "$value"
}

validate_discovered_count() {
  local discovered_test_count="$1"
  local baseline_test_count="$2"

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
}

validate_test_counts() {
  local discovered_test_count="$1"
  local executed_test_count="$2"
  local baseline_test_count="$3"

  validate_discovered_count "$discovered_test_count" "$baseline_test_count" || return 1
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
  if [[ "$executed_test_count" -lt "$discovered_test_count" ]]; then
    printf 'BLOCKER: executed SwiftPM test count %s is below discovered count %s\n' \
      "$executed_test_count" "$discovered_test_count" >&2
    return 1
  fi
}

validate_skipped_count() {
  local skipped_test_count="$1"
  local max_skipped_test_count="$2"

  if [[ ! "$skipped_test_count" =~ ^[0-9]+$ ]]; then
    printf 'BLOCKER: skipped SwiftPM test count must be non-negative, got %s\n' \
      "${skipped_test_count:-<empty>}" >&2
    return 1
  fi
  if [[ "$skipped_test_count" -gt "$max_skipped_test_count" ]]; then
    printf 'BLOCKER: skipped SwiftPM test count %s exceeds allowed maximum %s\n' \
      "$skipped_test_count" "$max_skipped_test_count" >&2
    return 1
  fi
}

parse_executed_test_count() {
  local output_file="$1"
  local xctest_count
  local swift_testing_count

  xctest_count="$(
    sed -nE 's/.*Executed ([0-9]+) tests?.*/\1/p' "$output_file" | tail -n 1
  )"
  swift_testing_count="$(
    sed -nE 's/.*Test run with ([0-9]+) tests?.*/\1/p' "$output_file" | tail -n 1
  )"
  if [[ -z "$xctest_count" && -z "$swift_testing_count" ]]; then
    return 1
  fi

  printf '%s\n' "$((${xctest_count:-0} + ${swift_testing_count:-0}))"
}

parse_skipped_test_count() {
  local output_file="$1"
  local xctest_skipped_count
  local swift_testing_skipped_count

  xctest_skipped_count="$(
    sed -nE 's/.*with ([0-9]+) tests? skipped.*/\1/p' "$output_file" | tail -n 1
  )"
  # Swift Testing emits one symbol-prefixed `Test … skipped:` event per skipped
  # case instead of including skips in its final run summary. Requiring both
  # the line prefix and trailing colon avoids double-counting XCTest summaries.
  swift_testing_skipped_count="$(
    grep -Ec '^[^[:alnum:]]*Test .* skipped:' "$output_file" || true
  )"

  printf '%s\n' "$((${xctest_skipped_count:-0} + swift_testing_skipped_count))"
}

write_xunit_summary() {
  local status="$1"
  local baseline_test_count="$2"
  local discovered_test_count="$3"
  local executed_test_count="$4"
  local skipped_test_count="$5"
  local max_skipped_test_count="$6"
  local output_file="$7"
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
    printf '    <property name="max_skipped_test_count" value="%s" />\n' "$max_skipped_test_count"
    printf '%s\n' '  </properties>'
    printf '%s\n' '  <testcase classname="Suisui.CI" name="complete-swiftpm-suite">'
    if [[ -n "$failure_element" ]]; then
      printf '%s\n' "$failure_element"
    fi
    printf '%s\n' '  </testcase>'
    printf '%s\n' '</testsuite>'
  } >"$output_file"
}

write_failed_evidence() {
  local baseline_test_count="$1"
  local discovered_test_count="$2"
  local max_skipped_test_count="$3"

  printf 'status=failed\nbaseline_test_count=%s\ndiscovered_test_count=%s\nexecuted_test_count=0\nskipped_test_count=0\nmax_skipped_test_count=%s\n' \
    "$baseline_test_count" \
    "$discovered_test_count" \
    "$max_skipped_test_count" \
    >"$SUMMARY_FILE"
  write_xunit_summary failed \
    "$baseline_test_count" \
    "$discovered_test_count" \
    0 \
    0 \
    "$max_skipped_test_count" \
    "$XUNIT_OUTPUT_FILE"
}

run_fixture_self_tests() {
  local fixture_dir
  local mixed_framework_output
  local sanitized_output
  local sanitized_secret_output
  local sanitized_provider_output
  local fixture_xunit
  if validate_discovered_count 4 3 >/dev/null 2>&1; then
    printf 'fixture=discovery-above-baseline status=passed\n'
  else
    printf 'fixture=discovery-above-baseline status=unexpected-failure\n' >&2
    return 1
  fi

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

  if validate_test_counts 4 3 3 >/dev/null 2>&1; then
    printf 'fixture=partial-execution status=unexpected-pass\n' >&2
    return 1
  else
    printf 'fixture=partial-execution status=blocked\n'
  fi

  if validate_test_counts 3 "" 3 >/dev/null 2>&1; then
    printf 'fixture=missing-execution-summary status=unexpected-pass\n' >&2
    return 1
  else
    printf 'fixture=missing-execution-summary status=blocked\n'
  fi

  if validate_skipped_count 6 6 >/dev/null 2>&1; then
    printf 'fixture=expected-skips status=passed\n'
  else
    printf 'fixture=expected-skips status=unexpected-failure\n' >&2
    return 1
  fi

  if validate_skipped_count 7 6 >/dev/null 2>&1; then
    printf 'fixture=skip-growth status=unexpected-pass\n' >&2
    return 1
  else
    printf 'fixture=skip-growth status=blocked\n'
  fi

  fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/suisui-swiftpm-runner-self-test.XXXXXX")"
  mixed_framework_output="$fixture_dir/mixed-framework-output.log"
  {
    printf '%s\n' "Test Suite 'All tests' passed."
    printf '%s\n' 'Executed 3 tests, with 1 test skipped and 0 failures.'
    printf '%s\n' '➜ Test conditionalSwiftTestingCase() skipped: "capability unavailable"'
    printf '%s\n' '✔ Test run with 2 tests in 1 suite passed after 0.001 seconds.'
  } >"$mixed_framework_output"
  if [[ "$(parse_executed_test_count "$mixed_framework_output")" != "5" ]]; then
    rm -rf "$fixture_dir"
    printf 'fixture=mixed-framework-execution status=invalid\n' >&2
    return 1
  fi
  if [[ "$(parse_skipped_test_count "$mixed_framework_output")" != "2" ]]; then
    rm -rf "$fixture_dir"
    printf 'fixture=mixed-framework-skips status=invalid\n' >&2
    return 1
  fi
  printf 'fixture=mixed-framework-counts status=passed\n'

  sanitized_output="$fixture_dir/sanitized-output.log"
  printf '%s\n' \
    'compiler cache /private/var/folders/ab/cd/T/module.cache' \
    'temporary result /var/tmp/suisui/test-result.json' \
    'fallback result /tmp/suisui/test-result.json' \
    | sanitize_swift_output >"$sanitized_output"
  if grep -Eq '/private/var/folders/|(/var)?/tmp/' "$sanitized_output"; then
    rm -rf "$fixture_dir"
    printf 'fixture=temporary-path-redaction status=invalid\n' >&2
    return 1
  fi
  if [[ "$(grep -c '<temp-path>' "$sanitized_output")" -ne 3 ]]; then
    rm -rf "$fixture_dir"
    printf 'fixture=temporary-path-redaction status=invalid\n' >&2
    return 1
  fi
  printf 'fixture=temporary-path-redaction status=passed\n'

  sanitized_secret_output="$fixture_dir/sanitized-secret-output.log"
  printf '%s\n' \
    'GITHUB_TOKEN=github-secret-value' \
    'OPENAI_API_KEY = openai-secret-value' \
    'Password: password-secret-value' \
    'secret = lowercase-secret-value' \
    | sanitize_swift_output >"$sanitized_secret_output"
  if grep -Eq 'github-secret-value|openai-secret-value|password-secret-value|lowercase-secret-value' \
    "$sanitized_secret_output"; then
    rm -rf "$fixture_dir"
    printf 'fixture=secret-assignment-redaction status=invalid\n' >&2
    return 1
  fi
  if [[ "$(grep -c '<redacted>' "$sanitized_secret_output")" -ne 4 ]]; then
    rm -rf "$fixture_dir"
    printf 'fixture=secret-assignment-redaction status=invalid\n' >&2
    return 1
  fi
  printf 'fixture=secret-assignment-redaction status=passed\n'

  sanitized_provider_output="$fixture_dir/sanitized-provider-output.log"
  printf '%s\n' \
    'Authorization: Bearer bearer-provider-value' \
    'Anthropic sk-ant-providerfixture' \
    'GitHub fine-grained github_pat_providerfixture1234' \
    'GitHub classic ghp_providerfixture1234' \
    'Slack xoxb-providerfixture1234' \
    'AWS AKIAABCDEFGHIJKLMNOP' \
    'ordinary risk-assessment and task-completion' \
    | sanitize_swift_output >"$sanitized_provider_output"
  if grep -Eq 'bearer-provider-value|sk-ant-providerfixture|github_pat_providerfixture1234|ghp_providerfixture1234|xoxb-providerfixture1234|AKIAABCDEFGHIJKLMNOP' \
    "$sanitized_provider_output"; then
    rm -rf "$fixture_dir"
    printf 'fixture=provider-token-redaction status=invalid\n' >&2
    return 1
  fi
  if [[ "$(grep -c '<redacted>' "$sanitized_provider_output")" -ne 6 ]]; then
    rm -rf "$fixture_dir"
    printf 'fixture=provider-token-redaction status=invalid\n' >&2
    return 1
  fi
  printf 'fixture=provider-token-redaction status=passed\n'
  if ! grep -q 'ordinary risk-assessment and task-completion' "$sanitized_provider_output"; then
    rm -rf "$fixture_dir"
    printf 'fixture=provider-token-boundary status=invalid\n' >&2
    return 1
  fi
  printf 'fixture=provider-token-boundary status=passed\n'

  fixture_xunit="$fixture_dir/test-results.xml"
  write_xunit_summary passed 3 3 3 0 0 "$fixture_xunit"
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
max_skipped_test_count="$(read_nonnegative_count \
  "maximum skipped SwiftPM test count" \
  "$(tr -d '[:space:]' <"$MAX_SKIPPED_FILE" 2>/dev/null || true)")"

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
  write_failed_evidence "$baseline_test_count" 0 "$max_skipped_test_count"
  cat "$DISCOVERY_LOG_FILE" >&2
  printf 'BLOCKER: SwiftPM test discovery failed\n' >&2
  exit "$discovery_status"
fi

discovered_test_count="$(awk 'NF { count += 1 } END { print count + 0 }' "$DISCOVERED_TESTS_FILE")"
if ! validate_discovered_count "$discovered_test_count" "$baseline_test_count" >/dev/null; then
  write_failed_evidence "$baseline_test_count" "$discovered_test_count" "$max_skipped_test_count"
  exit 1
fi

test_status=0
set +e
swift test 2>&1 | sanitize_swift_output | tee "$TEST_OUTPUT_FILE"
test_status=${PIPESTATUS[0]}
set -e

executed_test_count="$(parse_executed_test_count "$TEST_OUTPUT_FILE" || true)"
skipped_test_count="$(parse_skipped_test_count "$TEST_OUTPUT_FILE")"
skipped_test_count="${skipped_test_count:-0}"
count_status=0
if ! validate_test_counts \
  "$discovered_test_count" \
  "$executed_test_count" \
  "$baseline_test_count" \
  >/dev/null 2>&1; then
  count_status=1
fi
if ! validate_skipped_count "$skipped_test_count" "$max_skipped_test_count" >/dev/null 2>&1; then
  count_status=1
fi
status_label="passed"
if [[ "$test_status" -ne 0 || "$count_status" -ne 0 ]]; then
  status_label="failed"
fi

printf 'status=%s\nbaseline_test_count=%s\ndiscovered_test_count=%s\nexecuted_test_count=%s\nskipped_test_count=%s\nmax_skipped_test_count=%s\n' \
  "$status_label" \
  "$baseline_test_count" \
  "$discovered_test_count" \
  "${executed_test_count:-0}" \
  "$skipped_test_count" \
  "$max_skipped_test_count" \
  >"$SUMMARY_FILE"
write_xunit_summary \
  "$status_label" \
  "$baseline_test_count" \
  "$discovered_test_count" \
  "${executed_test_count:-0}" \
  "$skipped_test_count" \
  "$max_skipped_test_count" \
  "$XUNIT_OUTPUT_FILE"

if [[ "$test_status" -ne 0 ]]; then
  printf 'BLOCKER: complete SwiftPM test suite failed with exit code %s\n' "$test_status" >&2
  exit "$test_status"
fi
if [[ "$count_status" -ne 0 ]]; then
  validate_test_counts "$discovered_test_count" "$executed_test_count" "$baseline_test_count"
  validate_skipped_count "$skipped_test_count" "$max_skipped_test_count"
  exit 1
fi
printf 'OK: complete SwiftPM suite passed (%s discovered, %s executed, %s skipped)\n' \
  "$discovered_test_count" "$executed_test_count" "$skipped_test_count"
