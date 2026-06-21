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
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
DEFAULT_DATABASE_PATH="$ROOT_DIR/.tmp/voiceover-review/SoloPM-voiceover-review.sqlite"
VOICEOVER_REVIEW_ARTIFACT_PATH="$ROOT_DIR/docs/release/evidence/accessibility-voiceover.md"
TIMEOUT_SECONDS="${SOLOPM_VOICEOVER_REVIEW_TIMEOUT_SECONDS:-30}"
SQLITE3="${SQLITE3:-sqlite3}"
SOURCE_COMMIT="$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || printf "unknown")"

database_path="$DEFAULT_DATABASE_PATH"
launch_app=1
build_app=1
app_pid=""

usage() {
  printf '%s\n' "usage: $0 [--database PATH] [--no-launch] [--skip-build]"
  printf '%s\n' ""
  printf '%s\n' "Creates deterministic local Project Board data for the manual VoiceOver release pass."
  printf '%s\n' "The default database is isolated under .tmp/voiceover-review and does not touch the user's app data."
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --database)
      database_path="${2:-}"
      shift 2
      ;;
    --no-launch)
      launch_app=0
      shift
      ;;
    --skip-build)
      build_app=0
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

if [[ -z "${database_path//[[:space:]]/}" ]]; then
  echo "--database must not be blank" >&2
  exit 2
fi

case "$database_path" in
  /*) ;;
  *) database_path="$ROOT_DIR/$database_path" ;;
esac

if [[ ! "$TIMEOUT_SECONDS" =~ ^[0-9]+$ || "$TIMEOUT_SECONDS" -lt 1 ]]; then
  echo "SOLOPM_VOICEOVER_REVIEW_TIMEOUT_SECONDS must be a positive integer" >&2
  exit 2
fi

if ! command -v "$SQLITE3" >/dev/null 2>&1; then
  echo "BLOCKER: sqlite3 is required to prepare VoiceOver review data" >&2
  exit 2
fi

sql_escape() {
  printf "%s" "$1" | sed "s/'/''/g"
}

query_single_value() {
  local sql="$1"
  "$SQLITE3" -batch -noheader "$database_path" "$sql" | tail -n 1
}

write_voiceover_evidence_invocation() {
  local mode="$1"
  local evidence_source="$2"

  printf './script/create_voiceover_evidence.sh %s \\\n' "$mode"
  printf '%s\n' '  --checked-by "<reviewer name>" \'
  printf '%s\n' '  --accessibility-environment "<macOS version, hardware, VoiceOver input method, clean user/install context>" \'
  printf '  --evidence-source %q \\\n' "$evidence_source"
  printf '%s\n' '  --capture-runtime-ax-smoke \'
  printf '%s\n' '  --project-navigation-note "<VoiceOver observation for sidebar Inbox, Today, Projects, and selected review project navigation>" \'
  printf '%s\n' '  --project-board-detail-note "<VoiceOver observation for the seeded review project board context>" \'
  printf '%s\n' '  --open-task-note "<VoiceOver observation for focusing a seeded task card and opening details>" \'
  printf '%s\n' '  --inline-task-composer-note "<VoiceOver observation for title/detail/priority/due create flow, Command+Return, and Escape>" \'
  printf '%s\n' '  --status-controls-note "<VoiceOver observation for previous/next status controls and target status labels>" \'
  printf '%s\n' '  --task-inspector-note "<VoiceOver observation for inspector fields, summary, suggestion, save, and danger actions>" \'
  printf '%s\n' '  --save-changes-note "<VoiceOver observation proving keyboard activation saves local task changes>" \'
  printf '%s\n' '  --delete-confirmation-note "<VoiceOver observation proving Delete Task opens an inline inspector confirmation panel before deletion>" \'
  printf '%s\n' '  --no-keyboard-trap-note "<VoiceOver observation proving focus leaves sidebar, board, inspector, and inline confirmation panels>" \'
  printf '%s\n' '  --no-unlabeled-crud-note "<VoiceOver observation proving primary CRUD controls have labels or help>" \'
  printf '%s\n' '  --confirm-manual-voiceover-pass'
}

write_voiceover_review_worksheet() {
  local output_path="$1"
  local candidate_database_path="$2"
  local candidate_project_id="$3"
  local evidence_source="$4"

  {
    printf '%s\n' '# SoloPM VoiceOver Manual Review Worksheet'
    printf '\n'
    printf '%s\n' 'Status: pending'
    printf -- '- Source commit: `%s`\n' "$SOURCE_COMMIT"
    printf -- '- Candidate database: `%s`\n' "$candidate_database_path"
    printf -- '- Selected destination: `project:%s`\n' "$candidate_project_id"
    printf -- '- Evidence source: `%s`\n' "$evidence_source"
    printf '\n'
    printf '%s\n' 'This worksheet is not release evidence. Fill it during the real manual VoiceOver pass, then run the generated evidence command.'
    printf '\n'
    printf '%s\n' '## Manual VoiceOver Checks'
    printf '\n'
    printf '%s\n' '- [ ] Project navigation: sidebar Inbox, Today, Projects, and selected review project navigation are announced in order.'
    printf '%s\n' '- [ ] Project board detail: selected project context is announced before card navigation.'
    printf '%s\n' '- [ ] Open task: a seeded task card can receive focus and open details without pointer-only drag.'
    printf '%s\n' '- [ ] Inline Task Composer: title, detail, priority, due, create, cancel, Command+Return, and Escape are reachable.'
    printf '%s\n' '- [ ] Status controls: previous/next status controls announce target status labels.'
    printf '%s\n' '- [ ] Task inspector: fields, summary, suggestion, save, and danger actions are reachable.'
    printf '%s\n' '- [ ] Save Changes: keyboard activation saves local task edits.'
    printf '%s\n' '- [ ] Delete Task confirmation: destructive action opens an inline inspector confirmation panel before deletion.'
    printf '%s\n' '- [ ] No keyboard trap: focus leaves sidebar, board, inspector, and inline confirmation panels.'
    printf '%s\n' '- [ ] No unlabeled primary CRUD controls: primary CRUD controls have labels or help.'
    printf '\n'
    printf '%s\n' '## VoiceOver Observations To Fill'
    printf '\n'
    printf '%s\n' '- Reviewer:'
    printf '%s\n' '- Accessibility environment:'
    printf '%s\n' '- Runtime AX smoke:'
    printf '%s\n' '- Project navigation:'
    printf '%s\n' '- Project board detail:'
    printf '%s\n' '- Open task:'
    printf '%s\n' '- Inline Task Composer:'
    printf '%s\n' '- Status controls:'
    printf '%s\n' '- Task inspector:'
    printf '%s\n' '- Save Changes:'
    printf '%s\n' '- Delete Task confirmation:'
    printf '%s\n' '- No keyboard trap:'
    printf '%s\n' '- No unlabeled primary CRUD controls:'
    printf '\n'
    printf '%s\n' '## Closeout'
    printf '\n'
    printf '%s\n' '1. Change `Status: pending` to `Status: completed` after the real VoiceOver pass is complete.'
    printf '%s\n' '2. Fill every VoiceOver observation with concrete behavior from this candidate app.'
    printf '%s\n' '3. Remove unchecked `[ ]`, pending, and template/instructional text before running the generated command.'
  } >"$output_path"
}

write_voiceover_evidence_command() {
  local output_path="$1"
  local candidate_database_path="$2"
  local candidate_project_id="$3"
  local evidence_source

  evidence_source="dist/$APP_NAME.app manual VoiceOver pass using $candidate_database_path project:$candidate_project_id"

  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' 'set -euo pipefail'
    printf '\n'
    printf '%s\n' '# Generated by script/prepare_voiceover_review_candidate.sh.'
    printf '# Candidate database: %q\n' "$candidate_database_path"
    printf '# Candidate selected destination: %q\n' "project:$candidate_project_id"
    printf '%s\n' '# Replace every placeholder below with concrete observations from the manual VoiceOver pass before running.'
    printf '%s\n' '# This command must fail if placeholders are not replaced.'
    printf '\n'
    printf 'REPO_ROOT=%q\n' "$ROOT_DIR"
    printf '%s\n' 'cd "$REPO_ROOT"'
    printf '\n'
    printf '%s\n' 'TRACKED_SOURCE_STATUS="$(git status --porcelain --untracked-files=no)"'
    printf '%s\n' 'if [[ -n "$TRACKED_SOURCE_STATUS" ]]; then'
    printf '%s\n' '  printf "BLOCKER: VoiceOver evidence command requires a clean tracked source tree. Commit or revert tracked source changes, then rerun ./script/prepare_voiceover_review_candidate.sh for this release candidate.\n" >&2'
    printf '%s\n' '  exit 2'
    printf '%s\n' 'fi'
    printf '\n'
    printf 'EXPECTED_SOURCE_COMMIT=%q\n' "$SOURCE_COMMIT"
    printf '%s\n' 'CURRENT_SOURCE_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || printf unknown)"'
    printf '%s\n' 'if [[ "$CURRENT_SOURCE_COMMIT" != "$EXPECTED_SOURCE_COMMIT" ]]; then'
    printf '%s\n' '  printf "BLOCKER: VoiceOver evidence command was generated for source commit %s but current source commit is %s. Rerun ./script/prepare_voiceover_review_candidate.sh for this release candidate.\n" "$EXPECTED_SOURCE_COMMIT" "$CURRENT_SOURCE_COMMIT" >&2'
    printf '%s\n' '  exit 2'
    printf '%s\n' 'fi'
    printf '\n'
    printf 'APP_NAME=%q\n' "$APP_NAME"
    printf '%s\n' 'APP_BINARY="$REPO_ROOT/dist/$APP_NAME.app/Contents/MacOS/$APP_NAME"'
    printf '%s\n' 'VOICEOVER_LAUNCH_ENV_FILE="$REPO_ROOT/.tmp/voiceover-review/launch.env"'
    printf '%s\n' 'VOICEOVER_WORKSHEET_FILE="$REPO_ROOT/.tmp/voiceover-review/voiceover-worksheet.md"'
    printf 'EXPECTED_DATABASE_PATH=%q\n' "$candidate_database_path"
    printf 'EXPECTED_PROJECT_ID=%q\n' "$candidate_project_id"
    printf 'EXPECTED_SELECTED_DESTINATION=%q\n' "project:$candidate_project_id"
    printf '%s\n' 'SQLITE3="${SQLITE3:-sqlite3}"'
    printf '%s\n' 'CANDIDATE_APP_PID=""'
    printf '\n'
    printf '%s\n' 'if [[ ! -f "$VOICEOVER_LAUNCH_ENV_FILE" ]]; then'
    printf '%s\n' '  printf "BLOCKER: VoiceOver evidence command launch env is missing or stale: %s\n" "$VOICEOVER_LAUNCH_ENV_FILE" >&2'
    printf '%s\n' '  exit 2'
    printf '%s\n' 'fi'
    printf '%s\n' '# shellcheck source=/dev/null'
    printf '%s\n' 'source "$VOICEOVER_LAUNCH_ENV_FILE"'
    printf '%s\n' 'if [[ "${SOLOPM_VOICEOVER_REVIEW_SOURCE_COMMIT:-}" != "$EXPECTED_SOURCE_COMMIT" || "${SOLOPM_VOICEOVER_REVIEW_PROJECT_ID:-}" != "$EXPECTED_PROJECT_ID" || "${SOLOPM_DATABASE_PATH:-}" != "$EXPECTED_DATABASE_PATH" || "${SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION:-}" != "$EXPECTED_SELECTED_DESTINATION" ]]; then'
    printf '%s\n' '  printf "BLOCKER: VoiceOver evidence command launch env is missing or stale for source=%s project=%s database=%s destination=%s\n" "$EXPECTED_SOURCE_COMMIT" "$EXPECTED_PROJECT_ID" "$EXPECTED_DATABASE_PATH" "$EXPECTED_SELECTED_DESTINATION" >&2'
    printf '%s\n' '  exit 2'
    printf '%s\n' 'fi'
    printf '%s\n' 'if ! command -v "$SQLITE3" >/dev/null 2>&1; then'
    printf '%s\n' '  printf "BLOCKER: sqlite3 is required to verify the VoiceOver evidence candidate database\n" >&2'
    printf '%s\n' '  exit 2'
    printf '%s\n' 'fi'
    printf '%s\n' 'if [[ ! -x "$APP_BINARY" ]]; then'
    printf '%s\n' '  printf "BLOCKER: VoiceOver evidence command app binary is missing or not executable: %s\n" "$APP_BINARY" >&2'
    printf '%s\n' '  exit 2'
    printf '%s\n' 'fi'
    printf '%s\n' 'if [[ ! -f "$EXPECTED_DATABASE_PATH" ]]; then'
    printf '%s\n' '  printf "BLOCKER: VoiceOver evidence command database is missing the seeded review tasks: %s\n" "$EXPECTED_DATABASE_PATH" >&2'
    printf '%s\n' '  exit 2'
    printf '%s\n' 'fi'
    printf '%s\n' 'SEEDED_TASK_COUNT="$("$SQLITE3" -batch -noheader "$EXPECTED_DATABASE_PATH" "SELECT count(*) FROM tasks WHERE project_id=$EXPECTED_PROJECT_ID AND source_command='"'"'voiceover-review-seed'"'"';" | tail -n 1 || true)"'
    printf '%s\n' 'if [[ "$SEEDED_TASK_COUNT" != "5" ]]; then'
    printf '%s\n' '  printf "BLOCKER: VoiceOver evidence command database is missing the seeded review tasks for project %s: got %s\n" "$EXPECTED_PROJECT_ID" "${SEEDED_TASK_COUNT:-<empty>}" >&2'
    printf '%s\n' '  exit 2'
    printf '%s\n' 'fi'
    printf '\n'
    printf '%s\n' 'verify_voiceover_worksheet_for_evidence() {'
    printf '%s\n' '  local expected_commit_marker'
    printf '%s\n' '  local expected_database_marker'
    printf '%s\n' '  local expected_destination_marker'
    printf '%s\n' '  local required_label'
    printf '%s\n' '  local required_value'
    printf '%s\n' '  expected_commit_marker="Source commit: \`$EXPECTED_SOURCE_COMMIT\`"'
    printf '%s\n' '  expected_database_marker="Candidate database: \`$EXPECTED_DATABASE_PATH\`"'
    printf '%s\n' '  expected_destination_marker="Selected destination: \`$EXPECTED_SELECTED_DESTINATION\`"'
    printf '%s\n' ''
    printf '%s\n' '  if [[ ! -f "$VOICEOVER_WORKSHEET_FILE" ]]; then'
    printf '%s\n' '    printf "BLOCKER: VoiceOver worksheet is missing, stale, or incomplete: %s does not exist.\n" "$VOICEOVER_WORKSHEET_FILE" >&2'
    printf '%s\n' '    exit 2'
    printf '%s\n' '  fi'
    printf '%s\n' ''
    printf '%s\n' '  if ! grep -F -- "$expected_commit_marker" "$VOICEOVER_WORKSHEET_FILE" >/dev/null; then'
    printf '%s\n' '    printf "BLOCKER: VoiceOver worksheet is missing, stale, or incomplete: expected source commit %s.\n" "$EXPECTED_SOURCE_COMMIT" >&2'
    printf '%s\n' '    exit 2'
    printf '%s\n' '  fi'
    printf '%s\n' '  if ! grep -F -- "$expected_database_marker" "$VOICEOVER_WORKSHEET_FILE" >/dev/null; then'
    printf '%s\n' '    printf "BLOCKER: VoiceOver worksheet is missing, stale, or incomplete: expected candidate database %s.\n" "$EXPECTED_DATABASE_PATH" >&2'
    printf '%s\n' '    exit 2'
    printf '%s\n' '  fi'
    printf '%s\n' '  if ! grep -F -- "$expected_destination_marker" "$VOICEOVER_WORKSHEET_FILE" >/dev/null; then'
    printf '%s\n' '    printf "BLOCKER: VoiceOver worksheet is missing, stale, or incomplete: expected selected destination %s.\n" "$EXPECTED_SELECTED_DESTINATION" >&2'
    printf '%s\n' '    exit 2'
    printf '%s\n' '  fi'
    printf '%s\n' ''
    printf '%s\n' '  if ! grep -Fx -- "Status: completed" "$VOICEOVER_WORKSHEET_FILE" >/dev/null; then'
    printf '%s\n' '    printf "BLOCKER: VoiceOver worksheet is missing, stale, or incomplete: set Status: completed after the manual VoiceOver pass.\n" >&2'
    printf '%s\n' '    exit 2'
    printf '%s\n' '  fi'
    printf '%s\n' ''
    printf '%s\n' '  if grep -Eq "(Status:[[:space:]]*pending|To Fill|^## Closeout$|This worksheet is not release evidence|Replace every placeholder|not release evidence|<VoiceOver observation|placeholder)" "$VOICEOVER_WORKSHEET_FILE"; then'
    printf '%s\n' '    printf "BLOCKER: VoiceOver worksheet is missing, stale, or incomplete: remove pending/template instructions before writing evidence.\n" >&2'
    printf '%s\n' '    exit 2'
    printf '%s\n' '  fi'
    printf '%s\n' ''
    printf '%s\n' '  if grep -F -- "- [ ]" "$VOICEOVER_WORKSHEET_FILE" >/dev/null; then'
    printf '%s\n' '    printf "BLOCKER: VoiceOver worksheet is missing, stale, or incomplete: unchecked VoiceOver items remain.\n" >&2'
    printf '%s\n' '    exit 2'
    printf '%s\n' '  fi'
    printf '%s\n' ''
    printf '%s\n' '  voiceover_worksheet_value_is_placeholder_or_boilerplate() {'
    printf '%s\n' '    local normalized'
    printf '%s\n' '    normalized="$(printf "%s" "$1" | tr "[:upper:]" "[:lower:]" | sed -E "s/[[:punct:]]+/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]]+/ /g")"'
    printf '%s\n' '    case "$normalized" in'
    printf '%s\n' '      verified|\'
    printf '%s\n' '      checked|\'
    printf '%s\n' '      confirmed|\'
    printf '%s\n' '      passed|\'
    printf '%s\n' '      ok|\'
    printf '%s\n' '      okay|\'
    printf '%s\n' '      works|\'
    printf '%s\n' '      "looks good"|\'
    printf '%s\n' '      "all good"|\'
    printf '%s\n' '      "no issue"|\'
    printf '%s\n' '      "no issues"|\'
    printf '%s\n' '      "manual pass complete"|\'
    printf '%s\n' '      "manual pass completed"|\'
    printf '%s\n' '      "voiceover pass complete"|\'
    printf '%s\n' '      "voiceover pass completed"|\'
    printf '%s\n' '      "runtime ax smoke ok"|\'
    printf '%s\n' '      "concrete voiceover observation"*)'
    printf '%s\n' '        return 0'
    printf '%s\n' '        ;;'
    printf '%s\n' '      *)'
    printf '%s\n' '        ;;'
    printf '%s\n' '    esac'
    printf '%s\n' '    grep -Eiq "(^|[[:space:]])(todo|tbd|placeholder|sample|example)([[:space:]]|$)|replace" <<<"$normalized"'
    printf '%s\n' '  }'
    printf '%s\n' ''
    printf '%s\n' '  for required_label in "Reviewer" "Accessibility environment" "Runtime AX smoke" "Project navigation" "Project board detail" "Open task" "Inline Task Composer" "Status controls" "Task inspector" "Save Changes" "Delete Task confirmation" "No keyboard trap" "No unlabeled primary CRUD controls"; do'
    printf '%s\n' '    required_value="$(sed -n -E "s/^- ${required_label}:[[:space:]]*(.*)$/\1/p" "$VOICEOVER_WORKSHEET_FILE" | head -n 1)"'
    printf '%s\n' '    if [[ -z "${required_value//[[:space:]]/}" ]]; then'
    printf '%s\n' '      printf "BLOCKER: VoiceOver worksheet is missing, stale, or incomplete: fill %s.\n" "$required_label" >&2'
    printf '%s\n' '      exit 2'
    printf '%s\n' '    fi'
    printf '%s\n' '    if voiceover_worksheet_value_is_placeholder_or_boilerplate "$required_value"; then'
    printf '%s\n' '      printf "BLOCKER: VoiceOver worksheet is missing, stale, or incomplete: fill %s with concrete VoiceOver observation.\n" "$required_label" >&2'
    printf '%s\n' '      exit 2'
    printf '%s\n' '    fi'
    printf '%s\n' '  done'
    printf '%s\n' '}'
    printf '\n'
    printf '%s\n' 'verify_voiceover_worksheet_for_evidence'
    printf '\n'
	    printf '%s\n' 'terminate_voiceover_candidate() {'
	    printf '%s\n' '  pkill -x "$APP_NAME" >/dev/null 2>&1 || true'
    printf '%s\n' '  if [[ -n "${CANDIDATE_APP_PID:-}" ]]; then'
    printf '%s\n' '    wait "$CANDIDATE_APP_PID" >/dev/null 2>&1 || true'
    printf '%s\n' '    CANDIDATE_APP_PID=""'
    printf '%s\n' '  fi'
	    printf '%s\n' '}'
	    printf '\n'
	    printf '%s\n' 'activate_voiceover_candidate() {'
	    printf '%s\n' '  /usr/bin/osascript - "$APP_NAME" <<'"'"'APPLESCRIPT'"'"' >/dev/null 2>&1 || true'
	    printf '%s\n' 'on run argv'
	    printf '%s\n' '  set appName to item 1 of argv'
	    printf '%s\n' '  tell application "System Events"'
	    printf '%s\n' '    if not (exists process appName) then return "missing"'
	    printf '%s\n' '    tell process appName'
	    printf '%s\n' '      set frontmost to true'
	    printf '%s\n' '      if (count of windows) > 0 then'
	    printf '%s\n' '        try'
	    printf '%s\n' '          perform action "AXRaise" of window 1'
	    printf '%s\n' '        end try'
	    printf '%s\n' '      end if'
	    printf '%s\n' '    end tell'
	    printf '%s\n' '  end tell'
	    printf '%s\n' '  return "activated"'
	    printf '%s\n' 'end run'
	    printf '%s\n' 'APPLESCRIPT'
	    printf '%s\n' '}'
	    printf '\n'
	    printf '%s\n' 'wait_for_voiceover_candidate_process() {'
    printf '%s\n' '  local timeout_seconds="${SOLOPM_VOICEOVER_REVIEW_TIMEOUT_SECONDS:-30}"'
    printf '%s\n' '  local deadline=$((SECONDS + timeout_seconds))'
    printf '%s\n' '  while ! pgrep -x "$APP_NAME" >/dev/null 2>&1; do'
    printf '%s\n' '    if [[ "$SECONDS" -ge "$deadline" ]]; then'
    printf '%s\n' '      printf "BLOCKER: %s process did not appear for VoiceOver evidence within %ss\n" "$APP_NAME" "$timeout_seconds" >&2'
    printf '%s\n' '      exit 2'
    printf '%s\n' '    fi'
    printf '%s\n' '    sleep 1'
	    printf '%s\n' '  done'
	    printf '%s\n' '}'
	    printf '\n'
	    printf '%s\n' 'wait_for_voiceover_candidate_windows() {'
	    printf '%s\n' '  local timeout_seconds="${SOLOPM_VOICEOVER_REVIEW_TIMEOUT_SECONDS:-30}"'
	    printf '%s\n' '  local deadline=$((SECONDS + timeout_seconds))'
	    printf '%s\n' '  local window_count=""'
	    printf '%s\n' '  local osascript_status=1'
	    printf '%s\n' '  while true; do'
	    printf '%s\n' '    set +e'
	    printf '%s\n' '    window_count="$(/usr/bin/osascript - "$APP_NAME" <<'"'"'APPLESCRIPT'"'"' 2>/dev/null'
	    printf '%s\n' 'on run argv'
	    printf '%s\n' '  set appName to item 1 of argv'
	    printf '%s\n' '  tell application "System Events"'
	    printf '%s\n' '    if not (exists process appName) then return "0"'
	    printf '%s\n' '    tell process appName'
	    printf '%s\n' '      return (count of windows) as text'
	    printf '%s\n' '    end tell'
	    printf '%s\n' '  end tell'
	    printf '%s\n' 'end run'
	    printf '%s\n' 'APPLESCRIPT'
	    printf '%s\n' ')"'
	    printf '%s\n' '    osascript_status=$?'
	    printf '%s\n' '    set -e'
	    printf '%s\n' '    if [[ "$osascript_status" -eq 0 && "${window_count:-0}" =~ ^[0-9]+$ && "$window_count" -ge 1 ]]; then'
	    printf '%s\n' '      return 0'
	    printf '%s\n' '    fi'
	    printf '%s\n' '    activate_voiceover_candidate'
	    printf '%s\n' '    if [[ "$SECONDS" -ge "$deadline" ]]; then'
	    printf '%s\n' '      printf "BLOCKER: %s did not expose a visible AX window for VoiceOver evidence within %ss\n" "$APP_NAME" "$timeout_seconds" >&2'
	    printf '%s\n' '      exit 2'
	    printf '%s\n' '    fi'
	    printf '%s\n' '    sleep 1'
	    printf '%s\n' '  done'
	    printf '%s\n' '}'
	    printf '\n'
	    printf '%s\n' 'launch_voiceover_candidate_for_evidence() {'
	    printf '%s\n' '  terminate_voiceover_candidate'
	    printf '%s\n' '  SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1 \'
	    printf '%s\n' '    SOLOPM_DATABASE_PATH="$EXPECTED_DATABASE_PATH" \'
	    printf '%s\n' '    SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION="$EXPECTED_SELECTED_DESTINATION" \'
	    printf '%s\n' '    "$APP_BINARY" &'
	    printf '%s\n' '  CANDIDATE_APP_PID=$!'
	    printf '%s\n' '  wait_for_voiceover_candidate_process'
	    printf '%s\n' '  activate_voiceover_candidate'
	    printf '%s\n' '  wait_for_voiceover_candidate_windows'
	    printf '%s\n' '}'
    printf '\n'
    printf '%s\n' 'trap terminate_voiceover_candidate EXIT INT TERM'
    printf '\n'
    printf '%s\n' 'launch_voiceover_candidate_for_evidence'
    printf '\n'
    printf '%s\n' '# Validate the filled VoiceOver evidence command before writing tracked evidence.'
    write_voiceover_evidence_invocation "--validate-only" "$evidence_source"
    printf '\n'
    printf '%s\n' '# If validation passes and the manual VoiceOver pass is complete, write tracked evidence.'
    write_voiceover_evidence_invocation "--passed" "$evidence_source"
  } >"$output_path"

  chmod +x "$output_path"
}

wait_for_app_process() {
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while ! pgrep -x "$APP_NAME" >/dev/null 2>&1; do
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: $APP_NAME process did not appear within ${TIMEOUT_SECONDS}s" >&2
      return 1
    fi
    sleep 1
  done
}

wait_for_no_app_process() {
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while pgrep -x "$APP_NAME" >/dev/null 2>&1; do
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      pkill -x "$APP_NAME" >/dev/null 2>&1 || true
      return 0
    fi
    sleep 1
  done
}

terminate_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  if [[ -n "${app_pid:-}" ]]; then
    wait "$app_pid" >/dev/null 2>&1 || true
    app_pid=""
  fi
}

activate_app() {
  # Avoid LaunchServices activation here; it can start a second instance without
  # the isolated VoiceOver review database environment.
  /usr/bin/osascript - "$APP_NAME" <<'APPLESCRIPT' >/dev/null 2>&1 || true
on run argv
  set appName to item 1 of argv
  tell application "System Events"
    if not (exists process appName) then return "missing"
    tell process appName
      set frontmost to true
      if (count of windows) > 0 then
        try
          perform action "AXRaise" of window 1
        end try
      end if
    end tell
  end tell
  return "activated"
end run
APPLESCRIPT
}

wait_for_visible_windows() {
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local window_count=""
  local osascript_status=1

  while true; do
    set +e
    window_count="$(/usr/bin/osascript - "$APP_NAME" <<'APPLESCRIPT' 2>/dev/null
on run argv
  set appName to item 1 of argv
  tell application "System Events"
    if not (exists process appName) then return "0"
    tell process appName
      return (count of windows) as text
    end tell
  end tell
end run
APPLESCRIPT
)"
    osascript_status=$?
    set -e

    if [[ "$osascript_status" -eq 0 && "${window_count:-0}" =~ ^[0-9]+$ && "$window_count" -ge 1 ]]; then
      return 0
    fi

    activate_app
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: $APP_NAME did not expose a visible AX window within ${TIMEOUT_SECONDS}s" >&2
      return 1
    fi
    sleep 1
  done
}

wait_for_database_table() {
  local table="$1"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while true; do
    if [[ -f "$database_path" ]] && "$SQLITE3" "$database_path" "SELECT name FROM sqlite_master WHERE type='table' AND name='$table';" | grep -Fx "$table" >/dev/null; then
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: SQLite table '$table' was not created in VoiceOver review database: $database_path" >&2
      return 1
    fi
    sleep 1
  done
}

seed_voiceover_review_data() {
  local workspace_path="$ROOT_DIR/docs/release/evidence"
  local artifact_path="$VOICEOVER_REVIEW_ARTIFACT_PATH"
  local escaped_workspace_path
  local escaped_artifact_path
  local seeded_project_id

  escaped_workspace_path="$(sql_escape "$workspace_path")"
  escaped_artifact_path="$(sql_escape "$artifact_path")"

  "$SQLITE3" "$database_path" <<SQL
PRAGMA foreign_keys = ON;

DELETE FROM artifacts
WHERE project_id IN (SELECT id FROM projects WHERE source_command='voiceover-review-seed')
   OR task_id IN (SELECT id FROM tasks WHERE source_command='voiceover-review-seed');
DELETE FROM tasks WHERE source_command='voiceover-review-seed';
DELETE FROM projects WHERE source_command='voiceover-review-seed';

INSERT INTO projects (title, status, priority, deadline, workspace_path, tags_json, source_command, created_at, updated_at)
VALUES (
  'VoiceOver Review Project',
  'active',
  'high',
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '+7 days'),
  '$escaped_workspace_path',
  '["release","accessibility"]',
  'voiceover-review-seed',
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
);
SQL

  seeded_project_id="$(query_single_value "SELECT id FROM projects WHERE title='VoiceOver Review Project' AND source_command='voiceover-review-seed' ORDER BY id DESC LIMIT 1;")"
  if [[ -z "${seeded_project_id//[[:space:]]/}" ]]; then
    echo "BLOCKER: VoiceOver review project was not inserted" >&2
    exit 1
  fi

  "$SQLITE3" "$database_path" <<SQL
PRAGMA foreign_keys = ON;
INSERT INTO tasks (project_id, title, status, detail, due_at, priority, source_command, created_at, updated_at)
VALUES (
  $seeded_project_id,
  'Review Project navigation',
  'backlog',
  'Use VoiceOver to move through Inbox, Today, Projects, and back to the selected project.',
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '+1 day'),
  'high',
  'voiceover-review-seed',
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
);

INSERT INTO tasks (project_id, title, status, detail, due_at, priority, source_command, created_at, updated_at)
VALUES (
  $seeded_project_id,
  'Verify inline composer keyboard path',
  'planned',
  'Create a new task from a board column, then confirm Command+Return and Escape are reachable.',
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '+2 days'),
  'medium',
  'voiceover-review-seed',
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
);

INSERT INTO tasks (project_id, title, status, detail, due_at, priority, source_command, created_at, updated_at)
VALUES (
  $seeded_project_id,
  'Move status with card controls',
  'in_progress',
  'Use previous and next status buttons from the task card without relying on drag only.',
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '+3 days'),
  'medium',
  'voiceover-review-seed',
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
);

INSERT INTO tasks (project_id, title, status, detail, due_at, priority, source_command, created_at, updated_at)
VALUES (
  $seeded_project_id,
  'Confirm destructive confirmation labels',
  'blocked',
  'Open task details and verify Delete Task announces an inline inspector confirmation panel before deletion.',
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '+4 days'),
  'high',
  'voiceover-review-seed',
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
);

INSERT INTO tasks (project_id, title, status, detail, due_at, priority, source_command, created_at, updated_at)
VALUES (
  $seeded_project_id,
  'Save release accessibility notes',
  'completed',
  'Use the inspector title and detail fields, then activate Save Changes from the keyboard.',
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '+5 days'),
  'low',
  'voiceover-review-seed',
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
);

INSERT INTO artifacts (project_id, task_id, workspace_path, expected_path, created_state, created_at, updated_at)
VALUES (
  $seeded_project_id,
  NULL,
  '$escaped_workspace_path',
  '$escaped_artifact_path',
  'expected',
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
);
SQL
}

verify_seed() {
  local expected="$1"
  local label="$2"
  local sql="$3"
  local actual

  actual="$(query_single_value "$sql" || true)"
  if [[ "$actual" != "$expected" ]]; then
    echo "BLOCKER: $label verification failed: expected '$expected', got '${actual:-<empty>}'" >&2
    echo "SQL: $sql" >&2
    exit 1
  fi
}

cd "$ROOT_DIR"
mkdir -p "$(dirname "$database_path")"

if [[ "$build_app" -eq 1 ]]; then
  ./script/build_and_run.sh --build-only
fi

if [[ ! -x "$APP_BINARY" ]]; then
  echo "BLOCKER: app binary not found or not executable: $APP_BINARY" >&2
  exit 2
fi

terminate_app
SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1 SOLOPM_DATABASE_PATH="$database_path" "$APP_BINARY" &
app_pid=$!
wait_for_app_process
activate_app
wait_for_visible_windows
wait_for_database_table "projects"
terminate_app
wait_for_no_app_process

seed_voiceover_review_data
seed_project_id="$(query_single_value "SELECT id FROM projects WHERE title='VoiceOver Review Project' AND source_command='voiceover-review-seed' ORDER BY id DESC LIMIT 1;")"

if [[ -z "${seed_project_id//[[:space:]]/}" ]]; then
  echo "BLOCKER: VoiceOver review project was not inserted" >&2
  exit 1
fi

verify_seed "5" "seed task count" "SELECT count(*) FROM tasks WHERE project_id=$seed_project_id AND source_command='voiceover-review-seed';"
verify_seed "1" "seed artifact count" "SELECT count(*) FROM artifacts WHERE project_id=$seed_project_id AND expected_path='$(sql_escape "$VOICEOVER_REVIEW_ARTIFACT_PATH")';"
verify_seed "1" "seed task spread" "SELECT CASE WHEN count(DISTINCT status) = 5 THEN 1 ELSE 0 END FROM tasks WHERE project_id=$seed_project_id AND source_command='voiceover-review-seed';"
verify_seed "1" "VoiceOver release project selection" "SELECT CASE WHEN count(*) = 5 THEN 1 ELSE 0 END FROM tasks WHERE project_id=$seed_project_id AND source_command='voiceover-review-seed';"

launch_env_file="$ROOT_DIR/.tmp/voiceover-review/launch.env"
evidence_command_file="$ROOT_DIR/.tmp/voiceover-review/create-evidence-command.sh"
worksheet_file="$ROOT_DIR/.tmp/voiceover-review/voiceover-worksheet.md"
pending_evidence_file="$ROOT_DIR/.tmp/voiceover-review/accessibility-voiceover-pending-$SOURCE_COMMIT.md"
pending_evidence_source="dist/$APP_NAME.app manual VoiceOver pass using $database_path project:$seed_project_id"
{
  printf 'SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1\n'
  printf 'SOLOPM_DATABASE_PATH=%q\n' "$database_path"
  printf 'SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION=%q\n' "project:$seed_project_id"
  printf 'SOLOPM_VOICEOVER_REVIEW_SOURCE_COMMIT=%q\n' "$SOURCE_COMMIT"
  printf 'SOLOPM_VOICEOVER_REVIEW_PROJECT_ID=%q\n' "$seed_project_id"
} >"$launch_env_file"
write_voiceover_review_worksheet "$worksheet_file" "$database_path" "$seed_project_id" "$pending_evidence_source"
write_voiceover_evidence_command "$evidence_command_file" "$database_path" "$seed_project_id"
./script/create_voiceover_evidence.sh --pending --output "$pending_evidence_file" --evidence-source "$pending_evidence_source" >/dev/null

printf 'OK: VoiceOver review candidate ready\n'
printf 'Database: %s\n' "$database_path"
printf 'Project ID: %s\n' "$seed_project_id"
printf 'Artifact: VoiceOver review artifact -> %s\n' "$VOICEOVER_REVIEW_ARTIFACT_PATH"
printf 'Launch env: %s\n' "$launch_env_file"
printf 'Pending evidence: %s\n' "$pending_evidence_file"
printf 'Worksheet: %s\n' "$worksheet_file"
printf 'Evidence command: %s\n' "$evidence_command_file"

if [[ "$launch_app" -eq 1 ]]; then
  SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1 \
    SOLOPM_DATABASE_PATH="$database_path" \
    SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION="project:$seed_project_id" \
    "$APP_BINARY" &
  app_pid=$!
  wait_for_app_process
  activate_app
  wait_for_visible_windows
  printf 'App launched for manual VoiceOver review with SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION="project:%s"\n' "$seed_project_id"
else
  printf 'Launch skipped. To open the same candidate manually, run:\n'
  printf 'SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1 SOLOPM_DATABASE_PATH=%q SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION=%q %q\n' "$database_path" "project:$seed_project_id" "$APP_BINARY"
fi
