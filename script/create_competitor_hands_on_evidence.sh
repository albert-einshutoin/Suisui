#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_FILE=""
BENCHMARK_FILE=""
COMMAND_FILE="$ROOT_DIR/.tmp/competitor-hands-on/create-evidence-command.sh"
WORKSHEET_FILE="$ROOT_DIR/.tmp/competitor-hands-on/hands-on-worksheet.md"
EVIDENCE_STATUS="pending"
CHECKED_BY=""
CHECK_DATE="$(date +%F)"
EVIDENCE_SOURCE="Notion/Todoist/Linear/Motion 2-4 hour hands-on pass"
ENVIRONMENT=""
HANDS_ON_DURATION=""
CONFIRM_MANUAL_HANDS_ON=0
VALIDATE_ONLY=0
OUTPUT_FILE_WAS_SET=0
BENCHMARK_FILE_WAS_SET=0
NOTION_NOTE=""
TODOIST_NOTE=""
LINEAR_NOTE=""
MOTION_NOTE=""
SHIP_DELTA=""
DEFER_DELTA=""
REJECT_DELTA=""

release_candidate_source_commit() {
  local commit
  # Competitor findings are committed after the review pass, so tie the
  # evidence to the release-candidate product source instead of the evidence
  # commit itself.
  commit="$(
    git -C "$ROOT_DIR" -c core.abbrev=8 log -1 --format=%h -- \
      Sources/SuisuiApp \
      Sources/SuisuiCore \
      Sources/SuisuiCLI \
      Sources/SuisuiExternalConnectors \
      Package.swift \
      packaging/app_metadata.env 2>/dev/null || true
  )"
  if [[ -n "$commit" ]]; then
    printf "%s" "$commit"
  else
    git -C "$ROOT_DIR" rev-parse --short=8 HEAD 2>/dev/null || printf "unknown"
  fi
}

SOURCE_COMMIT="$(release_candidate_source_commit)"

usage() {
  printf '%s\n' "usage: $0 (--pending|--passed|--validate-only) [--output PATH] [--benchmark-output PATH] [--command-output PATH] [--worksheet-output PATH] [--checked-by NAME] [--check-date YYYY-MM-DD] [--evidence-source TEXT] [--environment TEXT] [--hands-on-duration TEXT] [--notion-note TEXT] [--todoist-note TEXT] [--linear-note TEXT] [--motion-note TEXT] [--ship TEXT] [--defer TEXT] [--reject TEXT] [--confirm-manual-hands-on]"
  printf '%s\n' ""
  printf '%s\n' "Use --pending to write safe pending evidence that release readiness will reject."
  printf '%s\n' "Use --pending to also write a hands-on worksheet, benchmark worksheet, and fill-in command template for the later manual evidence pass."
  printf '%s\n' "Use --passed only after a real Notion -> Todoist -> Linear -> Motion hands-on pass; it also writes the benchmark hands-on findings."
  printf '%s\n' "Use --validate-only to run the passed-evidence validation without writing evidence or benchmark findings."
}

require_passed_value() {
  local flag="$1"
  local value="$2"

  if [[ -z "${value//[[:space:]]/}" ]]; then
    echo "$flag is required with --passed" >&2
    exit 2
  fi
}

require_clean_tracked_source_tree_for_passed_evidence() {
  local tracked_source_status

  if ! command -v git >/dev/null 2>&1; then
    echo "BLOCKER: competitor hands-on passed evidence requires git to verify the release source tree" >&2
    exit 2
  fi

  if ! git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "BLOCKER: competitor hands-on passed evidence requires a git worktree" >&2
    exit 2
  fi

  tracked_source_status="$(git -C "$ROOT_DIR" status --porcelain --untracked-files=no)"
  if [[ -n "$tracked_source_status" ]]; then
    echo "BLOCKER: competitor hands-on passed evidence requires a clean tracked source tree. Commit or revert tracked source changes, then rerun ./script/create_competitor_hands_on_evidence.sh --pending for this release candidate." >&2
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
    "suisui public alpha behavior to ship based on the benchmark"|\
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

hands_on_total_minutes() {
  local value="$1"
  local normalized
  local total_segment
  normalized="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  total_segment="${normalized%%total*}"
  if [[ "$total_segment" == "$normalized" ]]; then
    total_segment="$normalized"
  fi

  awk '
    {
      total = 0
      for (i = 1; i <= NF; i++) {
        token = $i
        gsub(/[^0-9.a-z]/, "", token)
        if (token ~ /^[0-9]+(\.[0-9]+)?h(r|rs|our|ours)?$/) {
          number = token
          sub(/h.*/, "", number)
          total += number * 60
        } else if (token ~ /^[0-9]+(\.[0-9]+)?m(in|ins|inute|inutes)?$/) {
          number = token
          sub(/m.*/, "", number)
          total += number
        }
      }
      printf "%d\n", total + 0.5
    }
  ' <<<"$total_segment"
}

require_concrete_hands_on_duration() {
  local value="$1"
  local normalized
  local total_minutes
  local competitor

  require_passed_value "--hands-on-duration" "$value"
  normalized="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  if grep -Eiq '<|>|2-4h|including notion|(^|[^[:alnum:]_])(todo|tbd|placeholder|sample|example)([^[:alnum:]_]|$)|replace me' <<<"$normalized"; then
    echo "--hands-on-duration must describe a real 2-4 hour hands-on pass" >&2
    exit 2
  fi

  total_minutes="$(hands_on_total_minutes "$value")"
  if [[ "$total_minutes" -lt 120 || "$total_minutes" -gt 240 ]]; then
    echo "--hands-on-duration must describe a real 2-4 hour hands-on pass" >&2
    exit 2
  fi

  for competitor in notion todoist linear motion; do
    if ! grep -Eiq "$competitor[^0-9]*[0-9]+([.][0-9]+)?[[:space:]]*(h|hr|hrs|hour|hours|m|min|mins|minute|minutes)" <<<"$normalized"; then
      echo "--hands-on-duration must include per-competitor timing for Notion, Todoist, Linear, and Motion" >&2
      exit 2
    fi
  done
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
      VALIDATE_ONLY=0
      shift
      ;;
    --passed)
      EVIDENCE_STATUS="passed"
      VALIDATE_ONLY=0
      shift
      ;;
    --validate-only)
      EVIDENCE_STATUS="passed"
      VALIDATE_ONLY=1
      shift
      ;;
    --output)
      OUTPUT_FILE="${2:-}"
      OUTPUT_FILE_WAS_SET=1
      shift 2
      ;;
    --benchmark-output)
      BENCHMARK_FILE="${2:-}"
      BENCHMARK_FILE_WAS_SET=1
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
    --hands-on-duration)
      HANDS_ON_DURATION="${2:-}"
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

if [[ "$OUTPUT_FILE_WAS_SET" -eq 0 ]]; then
  if [[ "$EVIDENCE_STATUS" == "pending" ]]; then
    OUTPUT_FILE="$ROOT_DIR/.tmp/competitor-hands-on/competitor-hands-on-pending-$SOURCE_COMMIT.md"
  else
    OUTPUT_FILE="$ROOT_DIR/docs/release/evidence/competitor-hands-on.md"
  fi
fi

if [[ "$BENCHMARK_FILE_WAS_SET" -eq 0 ]]; then
  if [[ "$EVIDENCE_STATUS" == "pending" ]]; then
    BENCHMARK_FILE="$ROOT_DIR/.tmp/competitor-hands-on/competitor-benchmark-pending-$SOURCE_COMMIT.md"
  else
    BENCHMARK_FILE="$ROOT_DIR/docs/product/competitor-benchmark.md"
  fi
fi

if [[ -z "$OUTPUT_FILE" || -z "$BENCHMARK_FILE" || -z "$COMMAND_FILE" || -z "$WORKSHEET_FILE" ]]; then
  echo "output, benchmark, command, and worksheet paths must not be blank" >&2
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
  require_concrete_hands_on_duration "$HANDS_ON_DURATION"
fi

if [[ "$VALIDATE_ONLY" -eq 1 ]]; then
  require_clean_tracked_source_tree_for_passed_evidence
  printf 'OK: competitor hands-on evidence command is valid for current source commit: %s\n' "$SOURCE_COMMIT"
  exit 0
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
  printf -- '- Source commit: `%s`\n' "$SOURCE_COMMIT"
  printf -- '- Evidence source: `%s`\n' "$EVIDENCE_SOURCE"
  if [[ -n "$ENVIRONMENT" ]]; then
    printf -- '- Environment: %s\n' "$ENVIRONMENT"
  else
    printf '%s\n' '- Environment:'
  fi
  if [[ -n "$HANDS_ON_DURATION" ]]; then
    printf -- '- Elapsed hands-on time: %s\n' "$HANDS_ON_DURATION"
  else
    printf '%s\n' '- Elapsed hands-on time:'
  fi
  printf '%s\n' '- Scope: Notion -> Todoist -> Linear -> Motion'
}

write_pending_evidence() {
  {
    printf '%s\n' '# Competitor Hands-On Evidence'
    printf '\n'
    printf '%s\n' 'Status: pending'
    printf '%s\n' 'Generated by: script/create_competitor_hands_on_evidence.sh'
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
    printf '%s\n' '- [ ] No external SaaS sync or team workflow was added to Suisui public alpha scope because of this benchmark.'
    printf '\n'
    printf '%s\n' '## Ship / Defer / Reject Delta'
    printf '\n'
    printf '%s\n' '- Ship:'
    printf '%s\n' '- Defer:'
    printf '%s\n' '- Reject:'
    printf '\n'
    printf '%s\n' '## Failure Notes'
    printf '\n'
    printf '%s\n' '- Blocker observed:'
    printf '%s\n' '- Affected path:'
    printf '%s\n' '- Follow-up source/test link:'
    printf '%s\n' '- Fix owner:'
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
    printf '%s\n' '- Elapsed hands-on time with per-competitor timing:'
    printf '%s\n' '- Screenshot or note locations kept outside release evidence:'
    printf '\n'
    printf '%s\n' '## Competitor Paths'
    printf '\n'
    printf '%s\n' '- [ ] Notion: create a project database, switch to board, add 3 tasks, group by status, attach one doc/link/artifact, and try summary/context review.'
    printf '%s\n' '- [ ] Todoist: capture with Quick Add, set date/priority/project/section, switch board/list, drag a task, and scan Today/Upcoming.'
    printf '%s\n' '- [ ] Linear: create a project and issue, move status, inspect details/sidebar density, use the command or keyboard flow, and process one triage-like item.'
    printf '%s\n' '- [ ] Motion: create due/prioritized tasks, inspect schedule/risk surfaces, adjust a deadline, and record whether recommendation reasoning is understandable.'
    printf '%s\n' '- [ ] No external SaaS sync or team workflow was added to Suisui public alpha scope.'
    printf '\n'
    printf '%s\n' '## Competitor Observations'
    printf '\n'
    printf '%s\n' '- Notion observation:'
    printf '%s\n' '- Todoist observation:'
    printf '%s\n' '- Linear observation:'
    printf '%s\n' '- Motion observation:'
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
    printf '%s\n' '1. Change `Status: pending` to `Status: completed` after the hands-on pass.'
    printf '%s\n' '2. Fill every blank context, measurement, and Ship / Defer / Reject row with concrete observations.'
    printf '%s\n' '3. Change every completed check from `[ ]` to `[x]`. Keep this instruction text; completion is determined by `Status: completed`, every `[x]` check, and every required observation.'
    printf '%s\n' '4. Run the generated command; it reads reviewer, environment, duration, competitor notes, and Ship / Defer / Reject directly from this worksheet.'
    printf '%s\n' '5. Rerun `./script/release_readiness_report.sh` and confirm the competitor hands-on section is green.'
  } >"$WORKSHEET_FILE"
}

write_pending_benchmark() {
  mkdir -p "$(dirname "$BENCHMARK_FILE")"

  {
    printf '%s\n' '# Competitor Benchmark Pending Worksheet'
    printf '\n'
    printf '%s\n' 'Status: pending'
    printf '\n'
    printf '%s\n' 'This file is a read-only pending preview. Do not fill it: the generated command creates final evidence and benchmark findings from the hands-on worksheet, which is the single source of manual observations.'
    printf '\n'
    printf '%s\n' '## Candidate Metadata'
    printf '\n'
    printf -- '- Source commit: `%s`\n' "$SOURCE_COMMIT"
    printf -- '- Evidence output: `%s`\n' "$OUTPUT_FILE"
    printf -- '- Passed benchmark output: `%s`\n' "$BENCHMARK_FILE"
    printf -- '- Worksheet: `%s`\n' "$WORKSHEET_FILE"
    printf -- '- Passed command: `%s`\n' "$COMMAND_FILE"
    printf -- '- Evidence source: `%s`\n' "$EVIDENCE_SOURCE"
    printf '\n'
    printf '%s\n' '## Next Step'
    printf '\n'
    printf -- 'Fill `%s`, mark it `Status: completed`, check every item, then run `%s --validate-only`.\n' "$WORKSHEET_FILE" "$COMMAND_FILE"
  } >"$BENCHMARK_FILE"
}

write_competitor_evidence_invocation() {
  local mode="$1"

  printf './script/create_competitor_hands_on_evidence.sh %s \\\n' "$mode"
  printf '%s\n' '  --checked-by "$WORKSHEET_REVIEWER" \'
  printf '%s\n' '  --check-date "$WORKSHEET_REVIEW_DATE" \'
  printf '%s\n' '  --environment "$WORKSHEET_ENVIRONMENT" \'
  printf '%s\n' '  --hands-on-duration "$WORKSHEET_HANDS_ON_DURATION" \'
  printf '  --evidence-source %q \\\n' "$EVIDENCE_SOURCE"
  printf '%s\n' '  --notion-note "$WORKSHEET_NOTION_NOTE" \'
  printf '%s\n' '  --todoist-note "$WORKSHEET_TODOIST_NOTE" \'
  printf '%s\n' '  --linear-note "$WORKSHEET_LINEAR_NOTE" \'
  printf '%s\n' '  --motion-note "$WORKSHEET_MOTION_NOTE" \'
  printf '%s\n' '  --ship "$WORKSHEET_SHIP" \'
  printf '%s\n' '  --defer "$WORKSHEET_DEFER" \'
  printf '%s\n' '  --reject "$WORKSHEET_REJECT" \'
  printf '  --output %q \\\n' "$OUTPUT_FILE"
  printf '  --benchmark-output %q \\\n' "$BENCHMARK_FILE"
  printf '%s\n' '  --confirm-manual-hands-on'
}

write_competitor_evidence_command() {
  local output_path="$1"
  mkdir -p "$(dirname "$output_path")"

  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' 'set -euo pipefail'
    printf '\n'
    printf '%s\n' '# Generated by script/create_competitor_hands_on_evidence.sh.'
    printf '# Fill %s while reviewing; this command reads the completed worksheet directly.\n' "$WORKSHEET_FILE"
    printf '%s\n' '# Keep worksheet instructions, set Status: completed, check every item, and fill every required value.'
    printf '%s\n' '# This command fails closed when worksheet facts are incomplete or boilerplate.'
    printf '\n'
    printf '%s\n' 'VALIDATE_ONLY=0'
    printf '%s\n' 'usage() {'
    printf '%s\n' '  printf "%s\n" "usage: $0 [--validate-only]"'
    printf '%s\n' '}'
    printf '%s\n' 'if [[ "$#" -gt 1 ]]; then usage >&2; exit 2; fi'
    printf '%s\n' 'if [[ "$#" -eq 1 ]]; then'
    printf '%s\n' '  if [[ "$1" != "--validate-only" ]]; then usage >&2; exit 2; fi'
    printf '%s\n' '  VALIDATE_ONLY=1'
    printf '%s\n' 'fi'
    printf '\n'
    printf 'REPO_ROOT=%q\n' "$ROOT_DIR"
    printf '%s\n' 'cd "$REPO_ROOT"'
    printf '\n'
    printf '%s\n' 'TRACKED_SOURCE_STATUS="$(git status --porcelain --untracked-files=no)"'
    printf '%s\n' 'if [[ -n "$TRACKED_SOURCE_STATUS" ]]; then'
    printf '%s\n' '  printf "BLOCKER: competitor hands-on evidence command requires a clean tracked source tree. Commit or revert tracked source changes, then rerun ./script/create_competitor_hands_on_evidence.sh --pending for this release candidate.\n" >&2'
    printf '%s\n' '  exit 2'
    printf '%s\n' 'fi'
    printf '\n'
    printf 'EXPECTED_SOURCE_COMMIT=%q\n' "$SOURCE_COMMIT"
    printf '%s\n' 'release_candidate_source_commit() {'
    printf '%s\n' '  local commit'
    printf '%s\n' '  commit="$(git -c core.abbrev=8 log -1 --format=%h -- Sources/SuisuiApp Sources/SuisuiCore Sources/SuisuiCLI Sources/SuisuiExternalConnectors Package.swift packaging/app_metadata.env 2>/dev/null || true)"'
    printf '%s\n' '  if [[ -n "$commit" ]]; then printf "%s" "$commit"; else git rev-parse --short=8 HEAD 2>/dev/null || printf unknown; fi'
    printf '%s\n' '}'
    printf '%s\n' 'CURRENT_SOURCE_COMMIT="$(release_candidate_source_commit)"'
    printf '%s\n' 'if [[ "$CURRENT_SOURCE_COMMIT" != "$EXPECTED_SOURCE_COMMIT" ]]; then'
    printf '%s\n' '  printf "BLOCKER: competitor hands-on evidence command was generated for source commit %s but current source commit is %s. Rerun ./script/create_competitor_hands_on_evidence.sh --pending for this release candidate.\n" "$EXPECTED_SOURCE_COMMIT" "$CURRENT_SOURCE_COMMIT" >&2'
    printf '%s\n' '  exit 2'
    printf '%s\n' 'fi'
    printf '\n'
    printf 'COMPETITOR_WORKSHEET_FILE=%q\n' "$WORKSHEET_FILE"
    printf '%s\n' 'competitor_worksheet_value_is_placeholder_or_boilerplate() {'
    printf '%s\n' '  local normalized'
    printf '%s\n' '  normalized="$(printf "%s" "$1" | tr "[:upper:]" "[:lower:]" | sed -E "s/[[:punct:]]+/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]]+/ /g")"'
    printf '%s\n' '  case "$normalized" in'
    printf '%s\n' '    verified|\'
    printf '%s\n' '    checked|\'
    printf '%s\n' '    confirmed|\'
    printf '%s\n' '    passed|\'
    printf '%s\n' '    ok|\'
    printf '%s\n' '    okay|\'
    printf '%s\n' '    works|\'
    printf '%s\n' '    "looks good"|\'
    printf '%s\n' '    "all good"|\'
    printf '%s\n' '    "no issue"|\'
    printf '%s\n' '    "no issues"|\'
    printf '%s\n' '    "hands on complete"|\'
    printf '%s\n' '    "hands on completed"|\'
    printf '%s\n' '    "manual pass complete"|\'
    printf '%s\n' '    "manual pass completed"|\'
    printf '%s\n' '    "concrete notion observation"|\'
    printf '%s\n' '    "concrete todoist observation"|\'
    printf '%s\n' '    "concrete linear observation"|\'
    printf '%s\n' '    "concrete motion observation"|\'
    printf '%s\n' '    "concrete hands on observation"|\'
    printf '%s\n' '    "concrete competitor observation"|\'
    printf '%s\n' '    "ship defer reject captured")'
    printf '%s\n' '      return 0'
    printf '%s\n' '      ;;'
    printf '%s\n' '    *)'
    printf '%s\n' '      ;;'
    printf '%s\n' '  esac'
    printf '%s\n' '  grep -Eiq "(^|[[:space:]])(todo|tbd|placeholder|sample|example)([[:space:]]|$)|replace" <<<"$normalized"'
    printf '%s\n' '}'
    printf '\n'
    printf '%s\n' 'verify_competitor_worksheet_for_evidence() {'
    printf '%s\n' '  local expected_commit_marker'
    printf '%s\n' '  local required_label'
    printf '%s\n' '  local required_value'
    printf '%s\n' '  expected_commit_marker="Release candidate source commit: \`$EXPECTED_SOURCE_COMMIT\`"'
    printf '%s\n' ''
    printf '%s\n' '  if [[ ! -f "$COMPETITOR_WORKSHEET_FILE" ]]; then'
    printf '%s\n' '    printf "BLOCKER: competitor hands-on worksheet is missing, stale, or incomplete: %s does not exist.\n" "$COMPETITOR_WORKSHEET_FILE" >&2'
    printf '%s\n' '    exit 2'
    printf '%s\n' '  fi'
    printf '%s\n' ''
    printf '%s\n' '  if ! grep -F -- "$expected_commit_marker" "$COMPETITOR_WORKSHEET_FILE" >/dev/null; then'
    printf '%s\n' '    printf "BLOCKER: competitor hands-on worksheet is missing, stale, or incomplete: expected release candidate source commit %s.\n" "$EXPECTED_SOURCE_COMMIT" >&2'
    printf '%s\n' '    exit 2'
    printf '%s\n' '  fi'
    printf '%s\n' ''
    printf '%s\n' '  if ! grep -Fx -- "Status: completed" "$COMPETITOR_WORKSHEET_FILE" >/dev/null; then'
    printf '%s\n' '    printf "BLOCKER: competitor hands-on worksheet is missing, stale, or incomplete: set Status: completed after the hands-on pass.\n" >&2'
    printf '%s\n' '    exit 2'
    printf '%s\n' '  fi'
    printf '%s\n' ''
    printf '%s\n' '  if grep -F -- "- [ ]" "$COMPETITOR_WORKSHEET_FILE" >/dev/null; then'
    printf '%s\n' '    printf "BLOCKER: competitor hands-on worksheet is missing, stale, or incomplete: unchecked competitor path items remain.\n" >&2'
    printf '%s\n' '    exit 2'
    printf '%s\n' '  fi'
    printf '%s\n' ''
    printf '%s\n' '  for required_check in "Notion:" "Todoist:" "Linear:" "Motion:" "No external SaaS sync or team workflow"; do'
    printf '%s\n' '    if ! grep -F -- "- [x] $required_check" "$COMPETITOR_WORKSHEET_FILE" >/dev/null; then'
    printf '%s\n' '      printf "BLOCKER: competitor hands-on worksheet is missing, stale, or incomplete: required checked item is missing: %s\n" "$required_check" >&2'
    printf '%s\n' '      exit 2'
    printf '%s\n' '    fi'
    printf '%s\n' '  done'
    printf '%s\n' ''
    printf '%s\n' '  for required_label in "Reviewer" "Review date" "macOS version" "Browser / desktop app versions" "Account tiers / paid trial details" "Elapsed hands-on time with per-competitor timing" "Screenshot or note locations kept outside release evidence" "Notion observation" "Todoist observation" "Linear observation" "Motion observation" "Setup steps before first useful task" "Clicks / keystrokes for capture and status movement" "Inspector/detail clarity for repeated solo PM work" "Automation or recommendation trust issues" "Ship" "Defer" "Reject"; do'
    printf '%s\n' '    required_value="$(awk -v label="$required_label" '\''index($0, "- " label ":") == 1 { value = $0; sub("^- " label ":[[:space:]]*", "", value); print value; exit }'\'' "$COMPETITOR_WORKSHEET_FILE")"'
    printf '%s\n' '    if [[ -z "${required_value//[[:space:]]/}" ]]; then'
    printf '%s\n' '      printf "BLOCKER: competitor hands-on worksheet is missing, stale, or incomplete: fill %s.\n" "$required_label" >&2'
    printf '%s\n' '      exit 2'
    printf '%s\n' '    fi'
    printf '%s\n' '    if competitor_worksheet_value_is_placeholder_or_boilerplate "$required_value"; then'
    printf '%s\n' '      printf "BLOCKER: competitor hands-on worksheet is missing, stale, or incomplete: fill %s with concrete competitor hands-on observation.\n" "$required_label" >&2'
    printf '%s\n' '      exit 2'
    printf '%s\n' '    fi'
    printf '%s\n' '  done'
    printf '%s\n' '}'
    printf '\n'
    printf '%s\n' 'verify_competitor_worksheet_for_evidence'
    printf '\n'
    printf '%s\n' 'competitor_worksheet_value() {'
    printf '%s\n' '  local label="$1"'
    printf '%s\n' '  awk -v label="$label" '\''index($0, "- " label ":") == 1 { value = $0; sub("^- " label ":[[:space:]]*", "", value); print value; exit }'\'' "$COMPETITOR_WORKSHEET_FILE"'
    printf '%s\n' '}'
    printf '\n'
    printf '%s\n' '# The worksheet is the single source of competitor observations.'
    printf '%s\n' '# Both validate-only and passed output read the same values to prevent drift or duplicate entry.'
    printf '%s\n' 'WORKSHEET_REVIEWER="$(competitor_worksheet_value "Reviewer")"'
    printf '%s\n' 'WORKSHEET_REVIEW_DATE="$(competitor_worksheet_value "Review date")"'
    printf '%s\n' 'WORKSHEET_ENVIRONMENT="$(competitor_worksheet_value "macOS version"), $(competitor_worksheet_value "Browser / desktop app versions"), $(competitor_worksheet_value "Account tiers / paid trial details")"'
    printf '%s\n' 'WORKSHEET_HANDS_ON_DURATION="$(competitor_worksheet_value "Elapsed hands-on time with per-competitor timing")"'
    printf '%s\n' 'WORKSHEET_NOTION_NOTE="$(competitor_worksheet_value "Notion observation")"'
    printf '%s\n' 'WORKSHEET_TODOIST_NOTE="$(competitor_worksheet_value "Todoist observation")"'
    printf '%s\n' 'WORKSHEET_LINEAR_NOTE="$(competitor_worksheet_value "Linear observation")"'
    printf '%s\n' 'WORKSHEET_MOTION_NOTE="$(competitor_worksheet_value "Motion observation")"'
    printf '%s\n' 'WORKSHEET_SHIP="$(competitor_worksheet_value "Ship")"'
    printf '%s\n' 'WORKSHEET_DEFER="$(competitor_worksheet_value "Defer")"'
    printf '%s\n' 'WORKSHEET_REJECT="$(competitor_worksheet_value "Reject")"'
    printf '\n'
    printf '%s\n' '# Validate the filled competitor hands-on command before writing tracked evidence.'
    write_competitor_evidence_invocation "--validate-only"
    printf '\n'
    printf '%s\n' 'if [[ "$VALIDATE_ONLY" == 1 ]]; then'
    printf '%s\n' '  printf "%s\n" "Competitor evidence validation passed; tracked evidence and benchmark were not written."'
    printf '%s\n' '  exit 0'
    printf '%s\n' 'fi'
    printf '\n'
    printf '%s\n' '# If validation passes and the manual hands-on pass is complete, write tracked evidence and benchmark findings.'
    write_competitor_evidence_invocation "--passed"
  } >"$output_path"

  chmod +x "$output_path"
}

write_passed_evidence() {
  {
    printf '%s\n' '# Competitor Hands-On Evidence'
    printf '\n'
    printf '%s\n' 'Status: passed'
    printf '%s\n' 'Generated by: script/create_competitor_hands_on_evidence.sh'
    printf '\n'
    write_context
    printf '\n'
    printf '%s\n' '## Verified Hands-On Path'
    printf '\n'
    printf -- '- Notion: passed - %s\n' "$NOTION_NOTE"
    printf -- '- Todoist: passed - %s\n' "$TODOIST_NOTE"
    printf -- '- Linear: passed - %s\n' "$LINEAR_NOTE"
    printf -- '- Motion: passed - %s\n' "$MOTION_NOTE"
    printf '%s\n' '- No external SaaS sync or team workflow was added to Suisui public alpha scope because of this benchmark.'
    printf '\n'
    printf '%s\n' '## Ship / Defer / Reject Delta'
    printf '\n'
    printf -- '- Ship: %s\n' "$SHIP_DELTA"
    printf -- '- Defer: %s\n' "$DEFER_DELTA"
    printf -- '- Reject: %s\n' "$REJECT_DELTA"
    printf '\n'
    printf '%s\n' '## Failure Notes'
    printf '\n'
    printf '%s\n' '- Blocker observed: none during the competitor hands-on pass.'
    printf '%s\n' '- Affected path: none.'
    printf '%s\n' '- Follow-up source/test link: `docs/product/competitor-benchmark.md` hands-on benchmark closure.'
    printf '%s\n' '- Fix owner: none.'
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
    printf -- 'Elapsed hands-on time: %s\n' "$HANDS_ON_DURATION"
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
    printf -- '- Public alpha scope: No external SaaS sync or team workflow was added to Suisui public alpha scope because of this benchmark.\n'
    printf '\n'
    printf '%s\n' '## Ship / Defer / Reject'
    printf '\n'
    printf -- '- Ship: %s\n' "$SHIP_DELTA"
    printf -- '- Defer: %s\n' "$DEFER_DELTA"
    printf -- '- Reject: %s\n' "$REJECT_DELTA"
    printf '\n'
    printf '%s\n' '## Release Fit Closure'
    printf '\n'
    printf '%s\n' 'Suisui remains scoped to personal, local-first project/task execution for the public alpha. The benchmark only changes release scope when the observed behavior improves the Inbox -> Board/Today -> Inspector loop without adding external SaaS sync, team workflow, or autonomous scheduling surprises.'
  } >"$BENCHMARK_FILE"
}

if [[ "$EVIDENCE_STATUS" == "passed" ]]; then
  require_clean_tracked_source_tree_for_passed_evidence
  write_passed_evidence
  write_hands_on_benchmark
else
  write_pending_evidence
  write_hands_on_worksheet
  write_pending_benchmark
  write_competitor_evidence_command "$COMMAND_FILE"
fi

printf 'Competitor hands-on evidence written: %s\n' "$OUTPUT_FILE"
if [[ "$EVIDENCE_STATUS" == "pending" ]]; then
  printf 'Competitor hands-on worksheet written: %s\n' "$WORKSHEET_FILE"
  printf 'Competitor benchmark pending worksheet written: %s\n' "$BENCHMARK_FILE"
  printf 'Competitor hands-on evidence command written: %s\n' "$COMMAND_FILE"
fi
if [[ "$EVIDENCE_STATUS" == "passed" ]]; then
  printf 'Competitor benchmark hands-on findings written: %s\n' "$BENCHMARK_FILE"
fi
