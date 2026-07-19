#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_OUTPUT="$ROOT_DIR/docs/release/evidence/google-calendar-live-sync.md"

OUTPUT="$DEFAULT_OUTPUT"
VALIDATE_ONLY=0
FORCE=0
CHECKED_BY=""
ENVIRONMENT=""
SOURCE_COMMIT=""
CALENDAR_ID=""
TASK_ID=""
EVENT_ID=""
OAUTH_NOTE=""
CALENDAR_LIST_NOTE=""
APPROVAL_NOTE=""
SYNC_NOTE=""
DUPLICATE_NOTE=""
KEYCHAIN_NOTE=""

usage() {
  cat >&2 <<'USAGE'
usage: script/create_google_calendar_live_evidence.sh --validate-only|--force \
  --checked-by NAME \
  --environment TEXT \
  --source-commit COMMIT \
  --calendar-id ID \
  --task-id ID \
  --event-id ID \
  --oauth-note TEXT \
  --calendar-list-note TEXT \
  --approval-note TEXT \
  --sync-note TEXT \
  --duplicate-note TEXT \
  --keychain-note TEXT \
  [--output PATH]

This script records evidence from a real Google Calendar OAuth live sync pass.
It does not perform OAuth, read raw OAuth tokens, accept API keys, or create
fake success. Run the app on a credentialed release machine first, then record
the concrete observations here.
USAGE
}

fail() {
  printf 'BLOCKER: %s\n' "$1" >&2
  exit 1
}

current_product_source_commit() {
  git -C "$ROOT_DIR" log -1 --format=%h -- \
    Sources/SuisuiCore \
    Sources/SuisuiApp \
    Sources/SuisuiGoogleCalendarRuntime \
    Package.swift
}

require_clean_tracked_tree() {
  local status
  status="$(git -C "$ROOT_DIR" status --porcelain --untracked-files=no)"
  if [[ -n "$status" ]]; then
    fail "Google Calendar live evidence requires a clean tracked source tree. Commit or revert tracked changes, then rerun."
  fi
}

reject_secret_like_text() {
  local label="$1"
  local value="$2"
  if printf '%s\n' "$value" | grep -Eiq '(Bearer[[:space:]]+|access[_ -]?token|refresh[_ -]?token|ya29\.|AIza[0-9A-Za-z_-]{20,}|sk-[A-Za-z0-9_-]{8,})'; then
    fail "$label contains secret-like material; keep OAuth tokens, API keys, and bearer headers out of release evidence"
  fi
}

reject_placeholder() {
  local label="$1"
  local value="$2"
  if [[ -z "${value//[[:space:]]/}" ]]; then
    fail "$label is required"
  fi
  if printf '%s\n' "$value" | grep -Eiq '(<[^>]+>|To Fill|TBD|TODO|placeholder|pending|not release evidence|Replace this|example only)'; then
    fail "$label still looks like a placeholder"
  fi
  reject_secret_like_text "$label" "$value"
}

relative_output_path() {
  case "$OUTPUT" in
    "$ROOT_DIR"/*) printf '%s\n' "${OUTPUT#"$ROOT_DIR/"}" ;;
    *) printf '%s\n' "$OUTPUT" ;;
  esac
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --validate-only)
      VALIDATE_ONLY=1
      ;;
    --force)
      FORCE=1
      ;;
    --output)
      shift
      OUTPUT="${1:?--output requires a path}"
      ;;
    --checked-by)
      shift
      CHECKED_BY="${1:?--checked-by requires a value}"
      ;;
    --environment)
      shift
      ENVIRONMENT="${1:?--environment requires a value}"
      ;;
    --source-commit)
      shift
      SOURCE_COMMIT="${1:?--source-commit requires a value}"
      ;;
    --calendar-id)
      shift
      CALENDAR_ID="${1:?--calendar-id requires a value}"
      ;;
    --task-id)
      shift
      TASK_ID="${1:?--task-id requires a value}"
      ;;
    --event-id)
      shift
      EVENT_ID="${1:?--event-id requires a value}"
      ;;
    --oauth-note)
      shift
      OAUTH_NOTE="${1:?--oauth-note requires a value}"
      ;;
    --calendar-list-note)
      shift
      CALENDAR_LIST_NOTE="${1:?--calendar-list-note requires a value}"
      ;;
    --approval-note)
      shift
      APPROVAL_NOTE="${1:?--approval-note requires a value}"
      ;;
    --sync-note)
      shift
      SYNC_NOTE="${1:?--sync-note requires a value}"
      ;;
    --duplicate-note)
      shift
      DUPLICATE_NOTE="${1:?--duplicate-note requires a value}"
      ;;
    --keychain-note)
      shift
      KEYCHAIN_NOTE="${1:?--keychain-note requires a value}"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage
      fail "unknown argument: $1"
      ;;
  esac
  shift
done

if [[ "$VALIDATE_ONLY" == "1" && "$FORCE" == "1" ]]; then
  fail "choose either --validate-only or --force, not both"
fi
if [[ "$VALIDATE_ONLY" != "1" && "$FORCE" != "1" ]]; then
  usage
  fail "choose --validate-only before writing, or --force to write evidence"
fi

require_clean_tracked_tree

for pair in \
  "Checked by::$CHECKED_BY" \
  "Environment::$ENVIRONMENT" \
  "Source commit::$SOURCE_COMMIT" \
  "Calendar ID::$CALENDAR_ID" \
  "Task ID::$TASK_ID" \
  "Event ID::$EVENT_ID" \
  "OAuth consent completed::$OAUTH_NOTE" \
  "Writable calendar list loaded::$CALENDAR_LIST_NOTE" \
  "Approval-gated sync::$APPROVAL_NOTE" \
  "Approved sync created a Google Calendar event::$SYNC_NOTE" \
  "Rerun skipped the already-linked task::$DUPLICATE_NOTE" \
  "OAuth tokens stayed in Keychain::$KEYCHAIN_NOTE"; do
  reject_placeholder "${pair%%::*}" "${pair#*::}"
done

EXPECTED_SOURCE_COMMIT="$(current_product_source_commit)"
if [[ "$SOURCE_COMMIT" != "$EXPECTED_SOURCE_COMMIT" ]]; then
  fail "Google Calendar live evidence source commit mismatch: expected $EXPECTED_SOURCE_COMMIT, got $SOURCE_COMMIT"
fi

if [[ "$VALIDATE_ONLY" == "1" ]]; then
  printf 'OK: Google Calendar live sync evidence validated for %s; no release evidence written.\n' "$SOURCE_COMMIT"
  exit 0
fi

mkdir -p "$(dirname "$OUTPUT")"
GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
{
  printf '%s\n' '# Google Calendar Live Sync Evidence'
  printf '\n'
  printf '%s\n' 'Status: passed'
  printf '%s\n' 'Generated by: script/create_google_calendar_live_evidence.sh'
  printf -- '- Generated at: `%s`\n' "$GENERATED_AT"
  printf -- '- Source commit: `%s`\n' "$SOURCE_COMMIT"
  printf -- '- Checked by: `%s`\n' "$CHECKED_BY"
  printf -- '- Environment: `%s`\n' "$ENVIRONMENT"
  printf -- '- Calendar ID: `%s`\n' "$CALENDAR_ID"
  printf -- '- Task ID: `%s`\n' "$TASK_ID"
  printf -- '- Event ID: `%s`\n' "$EVENT_ID"
  printf '\n'
  printf '%s\n' '## Live Observations'
  printf '\n'
  printf -- '- OAuth consent completed: %s\n' "$OAUTH_NOTE"
  printf -- '- Writable calendar list loaded: %s\n' "$CALENDAR_LIST_NOTE"
  printf -- '- Approval-gated sync: %s\n' "$APPROVAL_NOTE"
  printf -- '- Approved sync created a Google Calendar event: %s\n' "$SYNC_NOTE"
  printf -- '- Rerun skipped the already-linked task: %s\n' "$DUPLICATE_NOTE"
  printf '\n'
  printf '%s\n' '## Security Boundary'
  printf '\n'
  printf -- '- OAuth tokens stayed in Keychain: %s\n' "$KEYCHAIN_NOTE"
  printf '%s\n' '- Raw OAuth access tokens, refresh tokens, Google API keys, and bearer headers were not copied into this evidence.'
  printf '%s\n' '- Calendar writes were triggered only after explicit in-app approval.'
} >"$OUTPUT"

printf 'OK: Google Calendar live sync evidence written: %s\n' "$(relative_output_path)"
