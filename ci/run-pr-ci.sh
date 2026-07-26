#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLAN_PATH="${SUISUI_CI_TEST_PLAN:-$ROOT_DIR/.tmp/ci-impact/test-plan.json}"
SELECTED_REPORT_PATH="${SUISUI_CI_EXECUTION_REPORT:-$ROOT_DIR/.tmp/ci-impact/selective-execution.json}"

transition_for_status() {
  local planner_status="$1"
  local strategy="$2"
  local selected_status="$3"
  if [[ "$planner_status" -ne 0 ]]; then
    printf 'full-and-failed\n'
  elif [[ "$strategy" == "full" ]]; then
    printf 'full\n'
  elif [[ "$selected_status" -eq 2 ]]; then
    printf 'full-and-failed\n'
  elif [[ "$selected_status" -ne 0 ]]; then
    printf 'failed\n'
  else
    printf 'passed\n'
  fi
}

self_test() {
  [[ "$(transition_for_status 2 selective 0)" == "full-and-failed" ]] || return 1
  printf 'planner-failure -> full: passed\n'
  [[ "$(transition_for_status 0 selective 2)" == "full-and-failed" ]] || return 1
  printf 'selector-setup-failure -> full: passed\n'
  [[ "$(transition_for_status 0 selective 1)" == "failed" ]] || return 1
  printf 'selected-test-failure -> failed: passed\n'
}

if [[ "${1:-}" == "--self-test" ]]; then
  self_test
  exit $?
fi

BASE_REVISION=""
HEAD_REVISION=""
FORCE_FULL_REASON=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-revision)
      BASE_REVISION="${2:-}"
      shift 2
      ;;
    --head-revision)
      HEAD_REVISION="${2:-}"
      shift 2
      ;;
    --force-full-reason)
      FORCE_FULL_REASON="${2:-}"
      shift 2
      ;;
    *)
      echo "usage: $0 --base-revision REV --head-revision REV [--force-full-reason REASON]" >&2
      exit 2
      ;;
  esac
done
if [[ -z "$BASE_REVISION" || -z "$HEAD_REVISION" ]]; then
  echo "BLOCKER: base and head revisions are required" >&2
  exit 2
fi

mkdir -p "$(dirname "$PLAN_PATH")" "$(dirname "$SELECTED_REPORT_PATH")"
cd "$ROOT_DIR" || exit 2

python3 -m unittest discover -s ci/tests -v
PLANNER_TEST_STATUS=$?
if [[ "$PLANNER_TEST_STATUS" -ne 0 ]]; then
  echo "Fallback reason: impact analyzer self-tests failed" >&2
  "$ROOT_DIR/ci/run-full.sh"
  exit "$PLANNER_TEST_STATUS"
fi

ANALYZE_ARGUMENTS=(
  python3
  "$ROOT_DIR/ci/impact/analyze.py"
  --repo "$ROOT_DIR"
  --base-revision "$BASE_REVISION"
  --head-revision "$HEAD_REVISION"
  --config "$ROOT_DIR/ci/config/impact.json"
  --output "$PLAN_PATH"
)
if [[ -n "$FORCE_FULL_REASON" ]]; then
  ANALYZE_ARGUMENTS+=(--force-full-reason "$FORCE_FULL_REASON")
fi
"${ANALYZE_ARGUMENTS[@]}"
PLANNER_STATUS=$?
if [[ "$PLANNER_STATUS" -ne 0 ]]; then
  echo "Fallback reason: impact analysis failed before a trustworthy plan was emitted" >&2
  "$ROOT_DIR/ci/run-full.sh"
  exit "$PLANNER_STATUS"
fi

STRATEGY="$(python3 - "$PLAN_PATH" <<'PY'
import json
import sys
from pathlib import Path

try:
    plan = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    strategy = plan.get("strategy")
except (OSError, UnicodeDecodeError, json.JSONDecodeError):
    strategy = None
if strategy not in {"selective", "full"}:
    raise SystemExit(2)
print(strategy)
PY
)"
STRATEGY_STATUS=$?
if [[ "$STRATEGY_STATUS" -ne 0 ]]; then
  echo "Fallback reason: emitted plan could not be validated" >&2
  "$ROOT_DIR/ci/run-full.sh"
  exit "$STRATEGY_STATUS"
fi

if [[ "$STRATEGY" == "full" ]]; then
  "$ROOT_DIR/ci/run-full.sh"
  exit $?
fi

python3 "$ROOT_DIR/ci/run-selected.py" \
  --repo "$ROOT_DIR" \
  --plan "$PLAN_PATH" \
  --report "$SELECTED_REPORT_PATH"
SELECTED_STATUS=$?
if [[ "$SELECTED_STATUS" -eq 2 ]]; then
  echo "Fallback reason: selected test runner setup failed" >&2
  if ! python3 "$ROOT_DIR/ci/escalate-plan.py" \
    --plan "$PLAN_PATH" \
    --reason "selected test runner setup failed"; then
    # An invalid generated plan must make the output exporter choose its
    # complete-validation defaults instead of preserving narrow UI targets.
    rm -f "$PLAN_PATH"
  fi
  "$ROOT_DIR/ci/run-full.sh"
  FULL_STATUS=$?
  [[ "$FULL_STATUS" -eq 0 ]] || exit "$FULL_STATUS"
  exit "$SELECTED_STATUS"
fi
exit "$SELECTED_STATUS"
