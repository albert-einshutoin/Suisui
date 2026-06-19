#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_FILE="$ROOT_DIR/docs/release/evidence/competitor-hands-on.md"
BENCHMARK_FILE="$ROOT_DIR/docs/product/competitor-benchmark.md"
COMMAND_FILE="$ROOT_DIR/.tmp/competitor-hands-on/create-evidence-command.sh"
WORKSHEET_FILE="$ROOT_DIR/.tmp/competitor-hands-on/hands-on-worksheet.md"
EVIDENCE_STATUS="pending"
CHECKED_BY=""
CHECK_DATE="$(date +%F)"
EVIDENCE_SOURCE="Notion/Todoist/Linear/Motion 2-4 hour hands-on pass"
ENVIRONMENT=""
CONFIRM_MANUAL_HANDS_ON=0
SOURCE_COMMIT="$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || printf "unknown")"
NOTION_NOTE=""
TODOIST_NOTE=""
LINEAR_NOTE=""
MOTION_NOTE=""
SHIP_DELTA=""
DEFER_DELTA=""
REJECT_DELTA=""

usage() {
  printf '%s\n' "usage: $0 (--pending|--passed) [--output PATH] [--benchmark-output PATH] [--command-output PATH] [--worksheet-output PATH] [--checked-by NAME] [--check-date YYYY-MM-DD] [--evidence-source TEXT] [--environment TEXT] [--notion-note TEXT] [--todoist-note TEXT] [--linear-note TEXT] [--motion-note TEXT] [--ship TEXT] [--defer TEXT] [--reject TEXT] [--confirm-manual-hands-on]"
  printf '%s\n' ""
  printf '%s\n' "Use --pending to write safe pending evidence that release readiness will reject."
  printf '%s\n' "Use --pending to also write a hands-on worksheet and fill-in command template for the later manual evidence pass."
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
    "hands on notion project database board task and artifact observation"|\
    "hands on todoist quick add board list drag movement today upcoming observation"|\
    "hands on linear project issue detail keyboard command and triage observation"|\
    "hands on motion scheduling risk deadline change and recommendation explanation observation"|\
    "solopm public alpha behavior to ship based on the benchmark"|\
    "public alpha behavior observed during the hands on pass that should ship"|\
    "behavior to defer until stronger reliability or demand evidence exists"|\
    "behavior observed but deferred until stronger reliability or demand evidence exists"|\
    "behaviors deliberately kept out of public alpha scope"|\
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
  normalized="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[[:punct:]]+/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]]+/ /g')"
  case "$normalized" in
    name|\
    reviewer|\
    "reviewer name"|\
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
    --command-output)
      COMMAND_FILE="${2:-}"
      shift 2
      ;;
    --worksheet-output)
      WORKSHEET_FILE="${2:-}"
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
  if [[ "$EVIDENCE_STATUS" == "passed" ]]; then
    printf -- '- Source commit: `%s`\n' "$SOURCE_COMMIT"
  else
    printf '%s\n' '- Source commit:'
  fi
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

write_hands_on_worksheet() {
  mkdir -p "$(dirname "$WORKSHEET_FILE")"

  {
    printf '%s\n' '# Competitor Hands-On Worksheet'
    printf '\n'
    printf '%s\n' 'Status: pending'
    printf '\n'
    printf '%s\n' 'This worksheet is not release evidence. Fill it during the real 2-4 hour Notion/Todoist/Linear/Motion pass, then run the generated passed command with concrete observations.'
    printf '\n'
    printf '%s\n' '## Candidate Metadata'
    printf '\n'
    printf -- '- Release candidate source commit: `%s`\n' "$SOURCE_COMMIT"
    printf -- '- Output evidence: `%s`\n' "$OUTPUT_FILE"
    printf -- '- Benchmark output: `%s`\n' "$BENCHMARK_FILE"
    printf -- '- Passed command: `%s`\n' "$COMMAND_FILE"
    printf -- '- Evidence source: `%s`\n' "$EVIDENCE_SOURCE"
    printf '\n'
    printf '%s\n' '## Review Context To Fill'
    printf '\n'
    printf '%s\n' '- Reviewer:'
    printf -- '- Review date: %s\n' "$CHECK_DATE"
    printf '%s\n' '- macOS version:'
    printf '%s\n' '- Browser / desktop app versions:'
    printf '%s\n' '- Account tiers / paid trial details:'
    printf '%s\n' '- Screenshot or note locations kept outside release evidence:'
    printf '\n'
    printf '%s\n' '## Competitor Paths'
    printf '\n'
    printf '%s\n' '- [ ] Notion: create a project database, switch to board, add 3 tasks, group by status, attach one doc/link/artifact, and try summary/context review.'
    printf '%s\n' '- [ ] Todoist: capture with Quick Add, set date/priority/project/section, switch board/list, drag a task, and scan Today/Upcoming.'
    printf '%s\n' '- [ ] Linear: create a project and issue, move status, inspect details/sidebar density, use the command or keyboard flow, and process one triage-like item.'
    printf '%s\n' '- [ ] Motion: create due/prioritized tasks, inspect schedule/risk surfaces, adjust a deadline, and record whether recommendation reasoning is understandable.'
    printf '%s\n' '- [ ] No external SaaS sync or team workflow was added to SoloPM public alpha scope.'
    printf '\n'
    printf '%s\n' '## Measurements'
    printf '\n'
    printf '%s\n' '- Setup steps before first useful task:'
    printf '%s\n' '- Clicks / keystrokes for capture and status movement:'
    printf '%s\n' '- Inspector/detail clarity for repeated solo PM work:'
    printf '%s\n' '- Automation or recommendation trust issues:'
    printf '\n'
    printf '%s\n' '## Ship / Defer / Reject Capture'
    printf '\n'
    printf '%s\n' '- Ship:'
    printf '%s\n' '- Defer:'
    printf '%s\n' '- Reject:'
    printf '\n'
    printf '%s\n' '## Closeout'
    printf '\n'
    printf '%s\n' '1. Replace every placeholder in the generated passed command with observations from this worksheet.'
    printf '%s\n' '2. Run the generated command only after the hands-on pass is complete.'
    printf '%s\n' '3. Rerun `./script/release_readiness_report.sh` and confirm the competitor hands-on section is green.'
  } >"$WORKSHEET_FILE"
}

write_competitor_evidence_command() {
  local output_path="$1"
  mkdir -p "$(dirname "$output_path")"

  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' 'set -euo pipefail'
    printf '\n'
    printf '%s\n' '# Generated by script/create_competitor_hands_on_evidence.sh.'
    printf '# Fill %s while reviewing, then replace every placeholder below.\n' "$WORKSHEET_FILE"
    printf '%s\n' '# Replace every placeholder below with concrete observations from the real Notion/Todoist/Linear/Motion hands-on pass before running.'
    printf '%s\n' '# This command must fail if placeholders are not replaced; it does not mark hands-on evidence as passed by itself.'
    printf '\n'
    printf 'REPO_ROOT=%q\n' "$ROOT_DIR"
    printf '%s\n' 'cd "$REPO_ROOT"'
    printf '\n'
    printf '%s\n' './script/create_competitor_hands_on_evidence.sh --passed \'
    printf '%s\n' '  --checked-by "<reviewer name>" \'
    printf '%s\n' '  --environment "<macOS/browser versions, competitor app/account tiers, and paid trial details>" \'
    printf '  --evidence-source %q \\\n' "$EVIDENCE_SOURCE"
    printf '%s\n' '  --notion-note "<hands-on Notion project database, board, task, and artifact observation>" \'
    printf '%s\n' '  --todoist-note "<hands-on Todoist quick add, board/list, drag movement, Today/Upcoming observation>" \'
    printf '%s\n' '  --linear-note "<hands-on Linear project, issue detail, keyboard command, and triage observation>" \'
    printf '%s\n' '  --motion-note "<hands-on Motion scheduling, risk, deadline change, and recommendation explanation observation>" \'
    printf '%s\n' '  --ship "<public alpha behavior observed during the hands-on pass that should ship>" \'
    printf '%s\n' '  --defer "<behavior observed but deferred until stronger reliability or demand evidence exists>" \'
    printf '%s\n' '  --reject "<behaviors deliberately kept out of public alpha scope>" \'
    printf '  --output %q \\\n' "$OUTPUT_FILE"
    printf '  --benchmark-output %q \\\n' "$BENCHMARK_FILE"
    printf '%s\n' '  --confirm-manual-hands-on'
  } >"$output_path"

  chmod +x "$output_path"
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
    printf -- 'Source commit: `%s`\n' "$SOURCE_COMMIT"
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
  write_hands_on_worksheet
  write_competitor_evidence_command "$COMMAND_FILE"
fi

printf 'Competitor hands-on evidence written: %s\n' "$OUTPUT_FILE"
if [[ "$EVIDENCE_STATUS" == "pending" ]]; then
  printf 'Competitor hands-on worksheet written: %s\n' "$WORKSHEET_FILE"
  printf 'Competitor hands-on evidence command written: %s\n' "$COMMAND_FILE"
fi
if [[ "$EVIDENCE_STATUS" == "passed" ]]; then
  printf 'Competitor benchmark hands-on findings written: %s\n' "$BENCHMARK_FILE"
fi
