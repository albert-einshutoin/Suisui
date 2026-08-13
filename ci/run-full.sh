#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_ROOT="${SUISUI_CI_IMPACT_ARTIFACT_DIR:-$ROOT_DIR/.tmp/ci-impact}"
REPORT_PATH="${SUISUI_CI_EXECUTION_REPORT:-$ARTIFACT_ROOT/full-execution.json}"
STARTED_AT="$(date +%s)"
SWIFTPM_STATUS=0
ACCESSIBILITY_MARKER_STATUS=0
SECURITY_STATUS=0
COUNT_STATUS=0

mkdir -p "$ARTIFACT_ROOT" "$(dirname "$REPORT_PATH")"
cd "$ROOT_DIR" || exit 2

SUISUI_SWIFTPM_ARTIFACT_DIR="${SUISUI_SWIFTPM_ARTIFACT_DIR:-$ROOT_DIR/.tmp/ci-artifacts/swiftpm}" \
  ./scripts/ci.sh swiftpm || SWIFTPM_STATUS=$?
./script/check_pseudo_voiceover_paths.sh || ACCESSIBILITY_MARKER_STATUS=$?
./script/check_security_regressions.sh || SECURITY_STATUS=$?

FINISHED_AT="$(date +%s)"
DURATION_SECONDS=$((FINISHED_AT - STARTED_AT))
SUMMARY_PATH="${SUISUI_SWIFTPM_ARTIFACT_DIR:-$ROOT_DIR/.tmp/ci-artifacts/swiftpm}/swiftpm-test-summary.env"

read_count() {
  local key="$1"
  local value="0"
  if [[ -f "$SUMMARY_PATH" ]]; then
    value="$(awk -F= -v key="$key" '$1 == key && $2 ~ /^[0-9]+$/ {value=$2} END {print value+0}' "$SUMMARY_PATH")"
  fi
  printf '%s\n' "$value"
}

DISCOVERED_TEST_COUNT="$(read_count discovered_test_count)"
EXECUTED_TEST_COUNT="$(read_count executed_test_count)"
SKIPPED_TEST_COUNT="$(read_count skipped_test_count)"

if [[ "$SWIFTPM_STATUS" -eq 0 ]] \
  && [[ "$DISCOVERED_TEST_COUNT" -le 0 || "$EXECUTED_TEST_COUNT" -le 0 \
    || "$EXECUTED_TEST_COUNT" -gt "$DISCOVERED_TEST_COUNT" ]]; then
  echo "BLOCKER: full test count evidence is missing or invalid" >&2
  COUNT_STATUS=1
fi

if ! python3 - "$REPORT_PATH" "$DURATION_SECONDS" "$DISCOVERED_TEST_COUNT" \
  "$EXECUTED_TEST_COUNT" "$SKIPPED_TEST_COUNT" "$SWIFTPM_STATUS" \
  "$ACCESSIBILITY_MARKER_STATUS" "$SECURITY_STATUS" "$COUNT_STATUS" <<'PY'
import json
import os
import sys
from pathlib import Path

(
    report_path,
    duration,
    discovered,
    executed,
    skipped,
    swiftpm_status,
    accessibility_marker_status,
    security_status,
    count_status,
) = sys.argv[1:]
statuses = [
    int(swiftpm_status),
    int(accessibility_marker_status),
    int(security_status),
    int(count_status),
]
report = {
    "schemaVersion": 1,
    "strategy": "full",
    "status": "passed" if all(status == 0 for status in statuses) else "failed",
    "commit": os.environ.get("GITHUB_SHA", ""),
    "branch": os.environ.get("GITHUB_REF_NAME", ""),
    "discoveredTestCount": int(discovered),
    "executedTestCount": int(executed),
    "successCount": max(0, int(executed) - int(skipped)) if statuses[0] == 0 else 0,
    "failureCount": sum(status != 0 for status in statuses),
    "skippedCount": int(skipped),
    "durationSeconds": int(duration),
    "totalComputeSeconds": int(duration),
    "gates": {
        "swiftpm": int(swiftpm_status),
        "accessibilityMarkers": int(accessibility_marker_status),
        "security": int(security_status),
        "testCountEvidence": int(count_status),
    },
}
Path(report_path).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
then
  echo "BLOCKER: full execution report could not be written" >&2
  exit 1
fi

if [[ "$SWIFTPM_STATUS" -ne 0 || "$ACCESSIBILITY_MARKER_STATUS" -ne 0 \
  || "$SECURITY_STATUS" -ne 0 || "$COUNT_STATUS" -ne 0 ]]; then
  exit 1
fi
