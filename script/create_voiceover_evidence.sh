#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METADATA_FILE="$ROOT_DIR/packaging/app_metadata.env"

if [[ ! -f "$METADATA_FILE" ]]; then
  echo "missing metadata file: $METADATA_FILE" >&2
  exit 2
fi

# shellcheck source=/dev/null
source "$METADATA_FILE"

APP_NAME="${APP_NAME:?APP_NAME is required}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:?BUNDLE_IDENTIFIER is required}"
MARKETING_VERSION="${MARKETING_VERSION:?MARKETING_VERSION is required}"
CURRENT_PROJECT_VERSION="${CURRENT_PROJECT_VERSION:?CURRENT_PROJECT_VERSION is required}"

OUTPUT_FILE=""
OUTPUT_FILE_WAS_SET=0
ACCESSIBILITY_PREFLIGHT_SCRIPT="${SOLOPM_ACCESSIBILITY_PREFLIGHT_SCRIPT:-$ROOT_DIR/script/check_accessibility_preflight.sh}"
VOICEOVER_STATUS="pending"
CHECKED_BY=""
CHECK_DATE="$(date +%F)"
MACOS_VERSION="macOS $(sw_vers -productVersion 2>/dev/null || printf 'unknown')"
EVIDENCE_SOURCE="dist/$APP_NAME.app manual VoiceOver pass"
ACCESSIBILITY_ENVIRONMENT=""
RUNTIME_AX_SMOKE_NOTE=""
CAPTURE_RUNTIME_AX_SMOKE=0
CONFIRM_MANUAL_PASS=0
VALIDATE_ONLY=0
PROJECT_NAVIGATION_NOTE=""
PROJECT_BOARD_DETAIL_NOTE=""
OPEN_TASK_NOTE=""
INLINE_TASK_COMPOSER_NOTE=""
STATUS_CONTROLS_NOTE=""
TASK_INSPECTOR_NOTE=""
SAVE_CHANGES_NOTE=""
DELETE_CONFIRMATION_NOTE=""
NO_KEYBOARD_TRAP_NOTE=""
NO_UNLABELED_CRUD_NOTE=""

release_candidate_source_commit() {
  local commit
  # Passed manual evidence is tracked after the pass, so bind it to the
  # release-candidate runtime/app metadata paths instead of the evidence commit.
  commit="$(
    git -C "$ROOT_DIR" log -1 --format=%h -- \
      Sources/SoloPMApp \
      Sources/SoloPMCore \
      Sources/SoloPMCLI \
      Sources/SoloPMExternalConnectors \
      Package.swift \
      packaging/app_metadata.env 2>/dev/null || true
  )"
  if [[ -n "$commit" ]]; then
    printf "%s" "$commit"
  else
    git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || printf "unknown"
  fi
}

SOURCE_COMMIT="$(release_candidate_source_commit)"

usage() {
  printf '%s\n' "usage: $0 (--pending|--passed|--validate-only) [--output PATH] [--checked-by NAME] [--macos-version VERSION] [--check-date YYYY-MM-DD] [--evidence-source TEXT] [--accessibility-environment TEXT] [--runtime-ax-smoke-note TEXT|--capture-runtime-ax-smoke] [--project-navigation-note TEXT] [--project-board-detail-note TEXT] [--open-task-note TEXT] [--inline-task-composer-note TEXT] [--status-controls-note TEXT] [--task-inspector-note TEXT] [--save-changes-note TEXT] [--delete-confirmation-note TEXT] [--no-keyboard-trap-note TEXT] [--no-unlabeled-crud-note TEXT] [--confirm-manual-voiceover-pass]"
  printf '%s\n' ""
  printf '%s\n' "Use --pending to write a safe worksheet that release readiness will reject."
  printf '%s\n' "Without --output, --pending writes .tmp/voiceover-review/accessibility-voiceover-pending-<commit>.md."
  printf '%s\n' "Use --passed only after a real VoiceOver pass on the release-candidate app."
  printf '%s\n' "Use --validate-only to run the passed-evidence validation without writing evidence."
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
    echo "BLOCKER: VoiceOver passed evidence requires git to verify the release source tree" >&2
    exit 2
  fi

  if ! git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "BLOCKER: VoiceOver passed evidence requires a git worktree" >&2
    exit 2
  fi

  tracked_source_status="$(git -C "$ROOT_DIR" status --porcelain --untracked-files=no)"
  if [[ -n "$tracked_source_status" ]]; then
    echo "BLOCKER: VoiceOver passed evidence requires a clean tracked source tree. Commit or revert tracked source changes, then rerun ./script/prepare_voiceover_review_candidate.sh for this release candidate." >&2
    exit 2
  fi
}

is_boilerplate_voiceover_note() {
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
    "concrete voiceover observation"*|\
    "voiceover observation"*|\
    "manual pass complete"|\
    "manual pass completed")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

require_concrete_voiceover_note() {
  local flag="$1"
  local value="$2"

  require_passed_value "$flag" "$value"
  if is_boilerplate_voiceover_note "$value"; then
    echo "$flag must include concrete VoiceOver verification details" >&2
    exit 2
  fi
}

require_runtime_ax_smoke_note() {
  local value="$1"

  require_passed_value "--runtime-ax-smoke-note" "$value"
  if is_boilerplate_voiceover_note "$value"; then
    echo "--runtime-ax-smoke-note must include the concrete runtime AX smoke output" >&2
    exit 2
  fi
  for required_marker in "OK: runtime AX smoke visible" "buttons=" "textFields=" "staticTexts=" "unlabeledButtons=0" "genericButtons=0" "crudSignals=8/8" "focusPathSignals=6/6"; do
    if ! grep -F "$required_marker" <<<"$value" >/dev/null; then
      echo "--runtime-ax-smoke-note must include $required_marker from ./script/check_accessibility_preflight.sh --runtime" >&2
      exit 2
    fi
  done
}

capture_runtime_ax_smoke_note() {
  local output
  local status
  local ok_line

  if [[ -z "${ACCESSIBILITY_PREFLIGHT_SCRIPT//[[:space:]]/}" ]]; then
    echo "SOLOPM_ACCESSIBILITY_PREFLIGHT_SCRIPT is empty" >&2
    exit 2
  fi

  set +e
  output="$(bash "$ACCESSIBILITY_PREFLIGHT_SCRIPT" --runtime --skip-launch 2>&1)"
  status=$?
  set -e

  if [[ "$status" -ne 0 ]]; then
    printf '%s\n' "$output" >&2
    echo "--capture-runtime-ax-smoke failed; keep the release-candidate Project Board visible and rerun the accessibility preflight" >&2
    exit 2
  fi

  ok_line="$(printf '%s\n' "$output" | grep -F "OK: runtime AX smoke visible" | tail -n 1 || true)"
  if [[ -z "${ok_line//[[:space:]]/}" ]]; then
    printf '%s\n' "$output" >&2
    echo "--capture-runtime-ax-smoke could not find the runtime AX smoke OK line" >&2
    exit 2
  fi

  RUNTIME_AX_SMOKE_NOTE="$ok_line"
}

is_placeholder_accessibility_environment() {
  local normalized
  normalized="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[[:punct:]]+/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]]+/ /g')"
  case "$normalized" in
    *"voiceover keyboard device details"*|\
    *"macos version hardware voiceover input method clean user install context"*|\
    *"manual pass environment"*|\
    *"accessibility environment"*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_placeholder_macos_version() {
  local normalized
  normalized="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[[:punct:]]+/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]]+/ /g')"
  case "$normalized" in
    macos|\
    "macos version"|\
    "macos unknown"|\
    unknown|\
    tbd|\
    todo|\
    placeholder|\
    sample|\
    example|\
    "replace me")
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
      VOICEOVER_STATUS="pending"
      VALIDATE_ONLY=0
      shift
      ;;
    --passed)
      VOICEOVER_STATUS="passed"
      VALIDATE_ONLY=0
      shift
      ;;
    --validate-only)
      VOICEOVER_STATUS="passed"
      VALIDATE_ONLY=1
      shift
      ;;
    --output)
      OUTPUT_FILE="${2:-}"
      OUTPUT_FILE_WAS_SET=1
      shift 2
      ;;
    --checked-by)
      CHECKED_BY="${2:-}"
      shift 2
      ;;
    --macos-version)
      MACOS_VERSION="${2:-}"
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
    --accessibility-environment)
      ACCESSIBILITY_ENVIRONMENT="${2:-}"
      shift 2
      ;;
    --runtime-ax-smoke-note)
      RUNTIME_AX_SMOKE_NOTE="${2:-}"
      shift 2
      ;;
    --capture-runtime-ax-smoke)
      CAPTURE_RUNTIME_AX_SMOKE=1
      shift
      ;;
    --project-navigation-note)
      PROJECT_NAVIGATION_NOTE="${2:-}"
      shift 2
      ;;
    --project-board-detail-note)
      PROJECT_BOARD_DETAIL_NOTE="${2:-}"
      shift 2
      ;;
    --open-task-note)
      OPEN_TASK_NOTE="${2:-}"
      shift 2
      ;;
    --inline-task-composer-note)
      INLINE_TASK_COMPOSER_NOTE="${2:-}"
      shift 2
      ;;
    --status-controls-note)
      STATUS_CONTROLS_NOTE="${2:-}"
      shift 2
      ;;
    --task-inspector-note)
      TASK_INSPECTOR_NOTE="${2:-}"
      shift 2
      ;;
    --save-changes-note)
      SAVE_CHANGES_NOTE="${2:-}"
      shift 2
      ;;
    --delete-confirmation-note)
      DELETE_CONFIRMATION_NOTE="${2:-}"
      shift 2
      ;;
    --no-keyboard-trap-note)
      NO_KEYBOARD_TRAP_NOTE="${2:-}"
      shift 2
      ;;
    --no-unlabeled-crud-note)
      NO_UNLABELED_CRUD_NOTE="${2:-}"
      shift 2
      ;;
    --confirm-manual-voiceover-pass)
      CONFIRM_MANUAL_PASS=1
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

if [[ "$VOICEOVER_STATUS" != "pending" && "$VOICEOVER_STATUS" != "passed" ]]; then
  usage >&2
  exit 2
fi

if [[ "$OUTPUT_FILE_WAS_SET" -eq 0 ]]; then
  if [[ "$VOICEOVER_STATUS" == "pending" ]]; then
    OUTPUT_FILE="$ROOT_DIR/.tmp/voiceover-review/accessibility-voiceover-pending-$SOURCE_COMMIT.md"
  else
    OUTPUT_FILE="$ROOT_DIR/docs/release/evidence/accessibility-voiceover.md"
  fi
fi

if [[ -z "${OUTPUT_FILE//[[:space:]]/}" ]]; then
  echo "--output must not be blank" >&2
  exit 2
fi

if [[ "$VOICEOVER_STATUS" == "passed" ]]; then
  if [[ "$CONFIRM_MANUAL_PASS" -ne 1 ]]; then
    echo "--confirm-manual-voiceover-pass is required with --passed" >&2
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
  if [[ -z "${MACOS_VERSION//[[:space:]]/}" || -z "${CHECK_DATE//[[:space:]]/}" ]]; then
    echo "--macos-version and --check-date are required with --passed" >&2
    exit 2
  fi
  if is_placeholder_macos_version "$MACOS_VERSION"; then
    echo "--macos-version must identify the actual macOS version" >&2
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
  require_passed_value "--accessibility-environment" "$ACCESSIBILITY_ENVIRONMENT"
  if is_placeholder_accessibility_environment "$ACCESSIBILITY_ENVIRONMENT"; then
    echo "--accessibility-environment must describe the actual VoiceOver, keyboard, and device environment" >&2
    exit 2
  fi
  require_concrete_voiceover_note "--project-navigation-note" "$PROJECT_NAVIGATION_NOTE"
  require_concrete_voiceover_note "--project-board-detail-note" "$PROJECT_BOARD_DETAIL_NOTE"
  require_concrete_voiceover_note "--open-task-note" "$OPEN_TASK_NOTE"
  require_concrete_voiceover_note "--inline-task-composer-note" "$INLINE_TASK_COMPOSER_NOTE"
  require_concrete_voiceover_note "--status-controls-note" "$STATUS_CONTROLS_NOTE"
  require_concrete_voiceover_note "--task-inspector-note" "$TASK_INSPECTOR_NOTE"
  require_concrete_voiceover_note "--save-changes-note" "$SAVE_CHANGES_NOTE"
  require_concrete_voiceover_note "--delete-confirmation-note" "$DELETE_CONFIRMATION_NOTE"
  require_concrete_voiceover_note "--no-keyboard-trap-note" "$NO_KEYBOARD_TRAP_NOTE"
  require_concrete_voiceover_note "--no-unlabeled-crud-note" "$NO_UNLABELED_CRUD_NOTE"
  if [[ "$CAPTURE_RUNTIME_AX_SMOKE" -eq 1 ]]; then
    capture_runtime_ax_smoke_note
  fi
  require_runtime_ax_smoke_note "$RUNTIME_AX_SMOKE_NOTE"
fi

if [[ "$VALIDATE_ONLY" -eq 1 ]]; then
  require_clean_tracked_source_tree_for_passed_evidence
  printf 'OK: VoiceOver evidence command is valid for current source commit: %s\n' "$SOURCE_COMMIT"
  exit 0
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"

write_context() {
  printf '%s\n' '## Release Candidate Context'
  printf '\n'
  printf -- '- macOS version: %s\n' "$MACOS_VERSION"
  printf -- '- App build: `%s (%s)`\n' "$MARKETING_VERSION" "$CURRENT_PROJECT_VERSION"
  printf -- '- Bundle identifier: `%s`\n' "$BUNDLE_IDENTIFIER"
  printf -- '- Source commit: `%s`\n' "$SOURCE_COMMIT"
  if [[ -n "$CHECKED_BY" ]]; then
    printf -- '- Checked by: %s\n' "$CHECKED_BY"
  else
    printf '%s\n' '- Checked by:'
  fi
  printf -- '- Check date: %s\n' "$CHECK_DATE"
  printf -- '- Evidence source: `%s`\n' "$EVIDENCE_SOURCE"
  if [[ -n "$ACCESSIBILITY_ENVIRONMENT" ]]; then
    printf -- '- Accessibility environment: %s\n' "$ACCESSIBILITY_ENVIRONMENT"
  else
    printf '%s\n' '- Accessibility environment:'
  fi
  if [[ -n "$RUNTIME_AX_SMOKE_NOTE" ]]; then
    printf -- '- Runtime AX smoke: %s\n' "$RUNTIME_AX_SMOKE_NOTE"
  else
    printf '%s\n' '- Runtime AX smoke:'
  fi
}

write_pending_evidence() {
  {
    printf '%s\n' '# VoiceOver Accessibility Evidence'
    printf '\n'
    printf '%s\n' 'Status: pending'
    printf '%s\n' 'Generated by: script/create_voiceover_evidence.sh'
    printf '\n'
    printf '%s\n' 'Do not set `Status: passed` until every item below is verified on the signed or release-candidate app.'
    printf '\n'
    write_context
    printf '\n'
    printf '%s\n' '## Setup'
    printf '\n'
    printf '%s\n' '1. Enable VoiceOver on macOS.'
    printf '%s\n' '2. Launch `dist/SoloPM.app`.'
    printf '%s\n' '3. Seed the Project Board with at least one active project and one task with a due date.'
    printf '%s\n' '4. Open the Project Board window and keep the right inspector visible.'
    printf '%s\n' '5. Run `./script/create_voiceover_evidence.sh --passed --capture-runtime-ax-smoke ...` after the manual pass, or run `./script/check_accessibility_preflight.sh --runtime` and paste the OK line into `Runtime AX smoke`.'
    printf '%s\n' '6. Navigate using keyboard and VoiceOver commands before using the pointer.'
    printf '\n'
    printf '%s\n' '## Required Focus Path'
    printf '\n'
    printf '%s\n' '- [ ] Project navigation: select Inbox, Today, and one Project from the sidebar.'
    printf '%s\n' '- [ ] Project board detail: confirm the selected project board is announced with project context.'
    printf '%s\n' '- [ ] Open task: focus a task card and open details without relying on pointer-only drag.'
    printf '%s\n' '- [ ] Inline Task Composer: create a task from a board column with title, detail, priority, due, Command+Return, and Escape paths.'
    printf '%s\n' '- [ ] Status controls: move focus to previous/next status controls and confirm button labels include target status.'
    printf '%s\n' '- [ ] Task inspector: focus title, detail, status, priority, due, summary, save, suggestion, and danger actions.'
    printf '%s\n' '- [ ] Save Changes: confirm keyboard activation reaches the local task save action.'
    printf '%s\n' '- [ ] Delete Task confirmation: confirm destructive action opens an inline inspector confirmation panel before local deletion.'
    printf '%s\n' '- [ ] No keyboard trap: confirm focus can leave sidebar, board, card controls, inspector fields, and inline confirmation panels.'
    printf '%s\n' '- [ ] No unlabeled primary CRUD controls: confirm create, update, status move, local suggestion apply, automation review, approved execution, and delete actions have labels or help.'
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
    printf '%s\n' '1. Run this script with `--passed --checked-by NAME --confirm-manual-voiceover-pass` only after the manual pass.'
    printf '%s\n' '2. Remove all `pending` and unchecked `[ ]` markers.'
    printf '%s\n' '3. Rerun `./script/release_readiness_report.sh` and confirm the VoiceOver section is green.'
  } >"$OUTPUT_FILE"
}

write_passed_evidence() {
  {
    printf '%s\n' '# VoiceOver Accessibility Evidence'
    printf '\n'
    printf '%s\n' 'Status: passed'
    printf '%s\n' 'Generated by: script/create_voiceover_evidence.sh'
    printf '\n'
    write_context
    printf '\n'
    printf '%s\n' '## Verified Focus Path'
    printf '\n'
    printf -- '- Project navigation: passed - %s\n' "$PROJECT_NAVIGATION_NOTE"
    printf -- '- Project board detail: passed - %s\n' "$PROJECT_BOARD_DETAIL_NOTE"
    printf -- '- Open task: passed - %s\n' "$OPEN_TASK_NOTE"
    printf -- '- Inline Task Composer: passed - %s\n' "$INLINE_TASK_COMPOSER_NOTE"
    printf -- '- Status controls: passed - %s\n' "$STATUS_CONTROLS_NOTE"
    printf -- '- Task inspector: passed - %s\n' "$TASK_INSPECTOR_NOTE"
    printf -- '- Save Changes: passed - %s\n' "$SAVE_CHANGES_NOTE"
    printf -- '- Delete Task confirmation: passed - %s\n' "$DELETE_CONFIRMATION_NOTE"
    printf -- '- No keyboard trap: passed - %s\n' "$NO_KEYBOARD_TRAP_NOTE"
    printf -- '- No unlabeled primary CRUD controls: passed - %s\n' "$NO_UNLABELED_CRUD_NOTE"
    printf '\n'
    printf '%s\n' '## Failure Notes'
    printf '\n'
    printf '%s\n' '- Blocker observed: none during the manual VoiceOver pass.'
    printf '%s\n' '- Affected path: none.'
    printf '%s\n' '- Follow-up source/test link: `Tests/SoloPMCoreTests/AppExperienceSourceTests.swift` VoiceOver source-anchor coverage.'
    printf '%s\n' '- Fix owner: none.'
  } >"$OUTPUT_FILE"
}

if [[ "$VOICEOVER_STATUS" == "passed" ]]; then
  require_clean_tracked_source_tree_for_passed_evidence
  write_passed_evidence
else
  write_pending_evidence
fi

printf 'VoiceOver accessibility evidence written: %s\n' "$OUTPUT_FILE"
