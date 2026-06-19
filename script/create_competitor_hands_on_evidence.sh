#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_FILE="$ROOT_DIR/docs/release/evidence/competitor-hands-on.md"
BENCHMARK_FILE="$ROOT_DIR/docs/product/competitor-benchmark.md"
EVIDENCE_STATUS="pending"
CHECKED_BY=""
CHECK_DATE="$(date +%F)"
EVIDENCE_SOURCE="Notion/Todoist/Linear/Motion 2-4 hour hands-on pass"
ENVIRONMENT=""
CONFIRM_MANUAL_HANDS_ON=0
NOTION_NOTE=""
TODOIST_NOTE=""
LINEAR_NOTE=""
MOTION_NOTE=""
SHIP_DELTA=""
DEFER_DELTA=""
REJECT_DELTA=""

usage() {
  printf '%s\n' "usage: $0 (--pending|--passed) [--output PATH] [--benchmark-output PATH] [--checked-by NAME] [--check-date YYYY-MM-DD] [--evidence-source TEXT] [--environment TEXT] [--notion-note TEXT] [--todoist-note TEXT] [--linear-note TEXT] [--motion-note TEXT] [--ship TEXT] [--defer TEXT] [--reject TEXT] [--confirm-manual-hands-on]"
  printf '%s\n' ""
  printf '%s\n' "Use --pending to write a safe worksheet that release readiness will reject."
  printf '%s\n' "Use --passed only after a real Notion -> Todoist -> Linear -> Motion hands-on pass; it also writes the benchmark hands-on findings."
}

require_passed_value() {
  local flag="$1"
  local value="$2"

  if [[ -z "${value//[[:space:]]/}" ]]; then
    echo "$flag is required with --passed" >&2
    exit 2
  fi
}

is_boilerplate_competitor_value() {
  local normalized
  normalized="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[[:punct:]]+/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]]+/ /g')"
  case "$normalized" in
    verified|\
    checked|\
    confirmed|\
    passed|\
    ok|\
    okay|\
    works|\
    "looks good"|\
    "all good"|\
    "no issue"|\
    "no issues"|\
    "hands on complete"|\
    "hands on completed"|\
    "manual pass complete"|\
    "manual pass completed"|\
    "concrete notion observation"*|\
    "concrete todoist observation"*|\
    "concrete linear observation"*|\
    "concrete motion observation"*|\
    "solopm public alpha behavior to ship based on the benchmark"|\
    "behavior to defer until stronger reliability or demand evidence exists"|\
    "behavior to keep out of public alpha scope")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

require_concrete_competitor_value() {
  local flag="$1"
  local value="$2"

  require_passed_value "$flag" "$value"
  if is_boilerplate_competitor_value "$value"; then
    echo "$flag must include concrete competitor hands-on details" >&2
    exit 2
  fi
}

is_placeholder_environment() {
  local normalized
  normalized="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$normalized" in
    *"macos/browser versions"*|\
    *"macos / browser versions"*|\
    *"competitor app/account tiers"*|\
    *"competitor app / account tiers"*|\
    *"whether any paid trial"*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_placeholder_checked_by() {
  local normalized
  normalized="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]]+/ /g')"
  case "$normalized" in
    name|\
    reviewer|\
    "release reviewer"|\
    "product reviewer"|\
    tester|\
    qa|\
    unknown|\
    tbd|\
    todo|\
    n/a|\
    na)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_iso_date() {
  local value="$1"
  local normalized
  [[ "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
  normalized="$(/bin/date -j -f '%Y-%m-%d' "$value" '+%Y-%m-%d' 2>/dev/null)" || return 1
  [[ "$normalized" == "$value" ]]
}

is_future_date() {
  local value="$1"
  local today
  today="$(/bin/date '+%Y-%m-%d')"
  [[ "$value" > "$today" ]]
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --pending)
      EVIDENCE_STATUS="pending"
      shift
      ;;
    --passed)
      EVIDENCE_STATUS="passed"
      shift
      ;;
    --output)
      OUTPUT_FILE="${2:-}"
      shift 2
      ;;
    --benchmark-output)
      BENCHMARK_FILE="${2:-}"
      shift 2
      ;;
    --checked-by)
      CHECKED_BY="${2:-}"
      shift 2
      ;;
    --check-date)
      CHECK_DATE="${2:-}"
      shift 2
      ;;
    --evidence-source)
      EVIDENCE_SOURCE="${2:-}"
      shift 2
      ;;
    --environment)
      ENVIRONMENT="${2:-}"
      shift 2
      ;;
    --notion-note)
      NOTION_NOTE="${2:-}"
      shift 2
      ;;
    --todoist-note)
      TODOIST_NOTE="${2:-}"
      shift 2
      ;;
    --linear-note)
      LINEAR_NOTE="${2:-}"
      shift 2
      ;;
    --motion-note)
      MOTION_NOTE="${2:-}"
      shift 2
      ;;
    --ship)
      SHIP_DELTA="${2:-}"
      shift 2
      ;;
    --defer)
      DEFER_DELTA="${2:-}"
      shift 2
      ;;
    --reject)
      REJECT_DELTA="${2:-}"
      shift 2
      ;;
    --confirm-manual-hands-on)
      CONFIRM_MANUAL_HANDS_ON=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$EVIDENCE_STATUS" != "pending" && "$EVIDENCE_STATUS" != "passed" ]]; then
  usage >&2
  exit 2
fi

if [[ "$EVIDENCE_STATUS" == "passed" ]]; then
  if [[ "$CONFIRM_MANUAL_HANDS_ON" -ne 1 ]]; then
    echo "--confirm-manual-hands-on is required with --passed" >&2
    exit 2
  fi
  if [[ -z "${CHECKED_BY//[[:space:]]/}" ]]; then
    echo "--checked-by is required with --passed" >&2
    exit 2
  fi
  if is_placeholder_checked_by "$CHECKED_BY"; then
    echo "--checked-by must name the actual reviewer" >&2
    exit 2
  fi
  if [[ -z "${CHECK_DATE//[[:space:]]/}" ]]; then
    echo "--check-date is required with --passed" >&2
    exit 2
  fi
  if ! is_iso_date "$CHECK_DATE"; then
    echo "--check-date must use YYYY-MM-DD and be a real calendar date" >&2
    exit 2
  fi
  if is_future_date "$CHECK_DATE"; then
    echo "--check-date must not be in the future" >&2
    exit 2
  fi
  require_passed_value "--environment" "$ENVIRONMENT"
  if is_placeholder_environment "$ENVIRONMENT"; then
    echo "--environment must describe the actual hands-on environment" >&2
    exit 2
  fi
  require_concrete_competitor_value "--notion-note" "$NOTION_NOTE"
  require_concrete_competitor_value "--todoist-note" "$TODOIST_NOTE"
  require_concrete_competitor_value "--linear-note" "$LINEAR_NOTE"
  require_concrete_competitor_value "--motion-note" "$MOTION_NOTE"
  require_concrete_competitor_value "--ship" "$SHIP_DELTA"
  require_concrete_competitor_value "--defer" "$DEFER_DELTA"
  require_concrete_competitor_value "--reject" "$REJECT_DELTA"
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"

write_context() {
  printf '%s\n' '## Review Context'
  printf '\n'
  if [[ -n "$CHECKED_BY" ]]; then
    printf -- '- Checked by: %s\n' "$CHECKED_BY"
  else
    printf '%s\n' '- Checked by:'
  fi
  printf -- '- Check date: %s\n' "$CHECK_DATE"
  printf -- '- Evidence source: `%s`\n' "$EVIDENCE_SOURCE"
  if [[ -n "$ENVIRONMENT" ]]; then
    printf -- '- Environment: %s\n' "$ENVIRONMENT"
  else
    printf '%s\n' '- Environment:'
  fi
  printf '%s\n' '- Scope: Notion -> Todoist -> Linear -> Motion'
}

write_pending_evidence() {
  {
    printf '%s\n' '# Competitor Hands-On Evidence'
    printf '\n'
    printf '%s\n' 'Status: pending'
    printf '\n'
    printf '%s\n' 'Do not set `Status: passed` until every competitor path below is verified for 2-4 hours total.'
    printf '\n'
    write_context
    printf '\n'
    printf '%s\n' '## Required Hands-On Path'
    printf '\n'
    printf '%s\n' '- [ ] Notion: create a project database, board, three tasks, status grouping, and one artifact/doc/link.'
    printf '%s\n' '- [ ] Todoist: use Quick Add, date/priority/project/section capture, board/list switching, drag movement, and Today/Upcoming scan.'
    printf '%s\n' '- [ ] Linear: create a project and issue, move issue status, open details/sidebar, use keyboard command flow, and process one triage-like item.'
    printf '%s\n' '- [ ] Motion: create dated/prioritized tasks, inspect scheduling/risk surfaces, adjust a deadline, and record how recommendations are explained.'
    printf '%s\n' '- [ ] No external SaaS sync or team workflow was added to SoloPM public alpha scope because of this benchmark.'
    printf '\n'
    printf '%s\n' '## Ship / Defer / Reject Delta'
    printf '\n'
    printf '%s\n' '- Ship:'
    printf '%s\n' '- Defer:'
    printf '%s\n' '- Reject:'
    printf '\n'
    printf '%s\n' '## Completion Instructions'
    printf '\n'
    printf '%s\n' '1. Run this script with `--passed --checked-by NAME --confirm-manual-hands-on` only after the hands-on pass.'
    printf '%s\n' '2. Remove all `pending` and unchecked `[ ]` markers.'
    printf '%s\n' '3. Rerun `./script/release_readiness_report.sh` and confirm the competitor hands-on section is green.'
  } >"$OUTPUT_FILE"
}

write_passed_evidence() {
  {
    printf '%s\n' '# Competitor Hands-On Evidence'
    printf '\n'
    printf '%s\n' 'Status: passed'
    printf '\n'
    write_context
    printf '\n'
    printf '%s\n' '## Verified Hands-On Path'
    printf '\n'
    printf -- '- Notion: passed - %s\n' "$NOTION_NOTE"
    printf -- '- Todoist: passed - %s\n' "$TODOIST_NOTE"
    printf -- '- Linear: passed - %s\n' "$LINEAR_NOTE"
    printf -- '- Motion: passed - %s\n' "$MOTION_NOTE"
    printf '%s\n' '- No external SaaS sync or team workflow was added to SoloPM public alpha scope because of this benchmark.'
    printf '\n'
    printf '%s\n' '## Ship / Defer / Reject Delta'
    printf '\n'
    printf -- '- Ship: %s\n' "$SHIP_DELTA"
    printf -- '- Defer: %s\n' "$DEFER_DELTA"
    printf -- '- Reject: %s\n' "$REJECT_DELTA"
  } >"$OUTPUT_FILE"
}

write_hands_on_benchmark() {
  mkdir -p "$(dirname "$BENCHMARK_FILE")"
  {
    printf '%s\n' '# Competitor Benchmark and Hands-On Findings'
    printf '\n'
    printf -- 'Verified: %s\n' "$CHECK_DATE"
    printf '\n'
    printf -- 'Reviewed by: %s\n' "$CHECKED_BY"
    printf '\n'
    printf -- 'Environment: %s\n' "$ENVIRONMENT"
    printf '\n'
    printf -- 'Evidence source: `%s`\n' "$EVIDENCE_SOURCE"
    printf '\n'
    printf '%s\n' 'Scope: Notion -> Todoist -> Linear -> Motion'
    printf '\n'
    printf '%s\n' '## Hands-On Findings'
    printf '\n'
    printf -- '- Notion: %s\n' "$NOTION_NOTE"
    printf -- '- Todoist: %s\n' "$TODOIST_NOTE"
    printf -- '- Linear: %s\n' "$LINEAR_NOTE"
    printf -- '- Motion: %s\n' "$MOTION_NOTE"
    printf -- '- Public alpha scope: No external SaaS sync or team workflow was added to SoloPM public alpha scope because of this benchmark.\n'
    printf '\n'
    printf '%s\n' '## Ship / Defer / Reject'
    printf '\n'
    printf -- '- Ship: %s\n' "$SHIP_DELTA"
    printf -- '- Defer: %s\n' "$DEFER_DELTA"
    printf -- '- Reject: %s\n' "$REJECT_DELTA"
    printf '\n'
    printf '%s\n' '## Release Fit Closure'
    printf '\n'
    printf '%s\n' 'SoloPM remains scoped to personal, local-first project/task execution for the public alpha. The benchmark only changes release scope when the observed behavior improves the Inbox -> Board/Today -> Inspector loop without adding external SaaS sync, team workflow, or autonomous scheduling surprises.'
  } >"$BENCHMARK_FILE"
}

if [[ "$EVIDENCE_STATUS" == "passed" ]]; then
  write_passed_evidence
  write_hands_on_benchmark
else
  write_pending_evidence
fi

printf 'Competitor hands-on evidence written: %s\n' "$OUTPUT_FILE"
if [[ "$EVIDENCE_STATUS" == "passed" ]]; then
  printf 'Competitor benchmark hands-on findings written: %s\n' "$BENCHMARK_FILE"
fi
