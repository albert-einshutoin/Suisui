#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_FILE="$ROOT_DIR/docs/release/evidence/competitor-hands-on.md"
EVIDENCE_STATUS="pending"
CHECKED_BY=""
CHECK_DATE="$(date +%F)"
EVIDENCE_SOURCE="Notion/Todoist/Linear/Motion 2-4 hour hands-on pass"
CONFIRM_MANUAL_HANDS_ON=0

usage() {
  printf '%s\n' "usage: $0 (--pending|--passed) [--output PATH] [--checked-by NAME] [--check-date YYYY-MM-DD] [--evidence-source TEXT] [--confirm-manual-hands-on]"
  printf '%s\n' ""
  printf '%s\n' "Use --pending to write a safe worksheet that release readiness will reject."
  printf '%s\n' "Use --passed only after a real Notion -> Todoist -> Linear -> Motion hands-on pass."
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
  if [[ -z "${CHECK_DATE//[[:space:]]/}" ]]; then
    echo "--check-date is required with --passed" >&2
    exit 2
  fi
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
    printf '%s\n' '- Notion: passed - Project database, board grouping, task creation, and artifact/doc/link context were reviewed.'
    printf '%s\n' '- Todoist: passed - Quick Add, date/priority/project capture, board/list switching, drag movement, and Today/Upcoming were reviewed.'
    printf '%s\n' '- Linear: passed - Project/issue creation, status movement, details/sidebar, keyboard flow, and triage-like intake were reviewed.'
    printf '%s\n' '- Motion: passed - Dated/prioritized tasks, scheduling/risk surfaces, deadline adjustment, and recommendation explanation were reviewed.'
    printf '%s\n' '- No external SaaS sync or team workflow was added to SoloPM public alpha scope because of this benchmark.'
    printf '\n'
    printf '%s\n' '## Ship / Defer / Reject Delta'
    printf '\n'
    printf '%s\n' '- Ship: Keep local Inbox/Menu Bar capture, Project Overview, board status movement, and right inspector as the public alpha loop.'
    printf '%s\n' '- Defer: Natural-language date parsing, calendar layout, AI status updates, and autonomous scheduling stay outside public alpha until reliability evidence exists.'
    printf '%s\n' '- Reject: Arbitrary database builders, team cycles, initiatives, and external SaaS sync remain out of public alpha scope.'
  } >"$OUTPUT_FILE"
}

if [[ "$EVIDENCE_STATUS" == "passed" ]]; then
  write_passed_evidence
else
  write_pending_evidence
fi

printf 'Competitor hands-on evidence written: %s\n' "$OUTPUT_FILE"
