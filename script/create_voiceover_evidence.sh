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

OUTPUT_FILE="$ROOT_DIR/docs/release/evidence/accessibility-voiceover.md"
VOICEOVER_STATUS="pending"
CHECKED_BY=""
CHECK_DATE="$(date +%F)"
MACOS_VERSION="macOS $(sw_vers -productVersion 2>/dev/null || printf 'unknown')"
EVIDENCE_SOURCE="dist/$APP_NAME.app manual VoiceOver pass"
CONFIRM_MANUAL_PASS=0
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

usage() {
  printf '%s\n' "usage: $0 (--pending|--passed) [--output PATH] [--checked-by NAME] [--macos-version VERSION] [--check-date YYYY-MM-DD] [--evidence-source TEXT] [--project-navigation-note TEXT] [--project-board-detail-note TEXT] [--open-task-note TEXT] [--inline-task-composer-note TEXT] [--status-controls-note TEXT] [--task-inspector-note TEXT] [--save-changes-note TEXT] [--delete-confirmation-note TEXT] [--no-keyboard-trap-note TEXT] [--no-unlabeled-crud-note TEXT] [--confirm-manual-voiceover-pass]"
  printf '%s\n' ""
  printf '%s\n' "Use --pending to write a safe worksheet that release readiness will reject."
  printf '%s\n' "Use --passed only after a real VoiceOver pass on the release-candidate app."
}

require_passed_value() {
  local flag="$1"
  local value="$2"

  if [[ -z "${value//[[:space:]]/}" ]]; then
    echo "$flag is required with --passed" >&2
    exit 2
  fi
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --pending)
      VOICEOVER_STATUS="pending"
      shift
      ;;
    --passed)
      VOICEOVER_STATUS="passed"
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

if [[ "$VOICEOVER_STATUS" == "passed" ]]; then
  if [[ "$CONFIRM_MANUAL_PASS" -ne 1 ]]; then
    echo "--confirm-manual-voiceover-pass is required with --passed" >&2
    exit 2
  fi
  if [[ -z "${CHECKED_BY//[[:space:]]/}" ]]; then
    echo "--checked-by is required with --passed" >&2
    exit 2
  fi
  if [[ -z "${MACOS_VERSION//[[:space:]]/}" || -z "${CHECK_DATE//[[:space:]]/}" ]]; then
    echo "--macos-version and --check-date are required with --passed" >&2
    exit 2
  fi
  require_passed_value "--project-navigation-note" "$PROJECT_NAVIGATION_NOTE"
  require_passed_value "--project-board-detail-note" "$PROJECT_BOARD_DETAIL_NOTE"
  require_passed_value "--open-task-note" "$OPEN_TASK_NOTE"
  require_passed_value "--inline-task-composer-note" "$INLINE_TASK_COMPOSER_NOTE"
  require_passed_value "--status-controls-note" "$STATUS_CONTROLS_NOTE"
  require_passed_value "--task-inspector-note" "$TASK_INSPECTOR_NOTE"
  require_passed_value "--save-changes-note" "$SAVE_CHANGES_NOTE"
  require_passed_value "--delete-confirmation-note" "$DELETE_CONFIRMATION_NOTE"
  require_passed_value "--no-keyboard-trap-note" "$NO_KEYBOARD_TRAP_NOTE"
  require_passed_value "--no-unlabeled-crud-note" "$NO_UNLABELED_CRUD_NOTE"
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"

write_context() {
  printf '%s\n' '## Release Candidate Context'
  printf '\n'
  printf -- '- macOS version: %s\n' "$MACOS_VERSION"
  printf -- '- App build: `%s (%s)`\n' "$MARKETING_VERSION" "$CURRENT_PROJECT_VERSION"
  printf -- '- Bundle identifier: `%s`\n' "$BUNDLE_IDENTIFIER"
  if [[ -n "$CHECKED_BY" ]]; then
    printf -- '- Checked by: %s\n' "$CHECKED_BY"
  else
    printf '%s\n' '- Checked by:'
  fi
  printf -- '- Check date: %s\n' "$CHECK_DATE"
  printf -- '- Evidence source: `%s`\n' "$EVIDENCE_SOURCE"
}

write_pending_evidence() {
  {
    printf '%s\n' '# VoiceOver Accessibility Evidence'
    printf '\n'
    printf '%s\n' 'Status: pending'
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
    printf '%s\n' '5. Navigate using keyboard and VoiceOver commands before using the pointer.'
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
    printf '%s\n' '- [ ] Delete Task confirmation: confirm destructive action opens confirmation before local deletion.'
    printf '%s\n' '- [ ] No keyboard trap: confirm focus can leave sidebar, board, card controls, inspector fields, and confirmation dialogs.'
    printf '%s\n' '- [ ] No unlabeled primary CRUD controls: confirm create, update, status move, complete/archive, and delete actions have labels or help.'
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
  write_passed_evidence
else
  write_pending_evidence
fi

printf 'VoiceOver accessibility evidence written: %s\n' "$OUTPUT_FILE"
