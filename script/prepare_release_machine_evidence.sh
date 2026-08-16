#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METADATA_FILE="$ROOT_DIR/packaging/app_metadata.env"
WORKSHEET_FILE="$ROOT_DIR/.tmp/release-machine/release-machine-worksheet.md"
COMMAND_FILE="$ROOT_DIR/.tmp/release-machine/create-release-evidence-command.sh"
EVIDENCE_OUTPUT_FILE="packaging/release-evidence.json"

usage() {
  printf '%s\n' "usage: $0 [--worksheet-output PATH] [--command-output PATH]"
  printf '%s\n' ""
  printf '%s\n' "Writes a release-machine worksheet and a fill-in create_release_evidence.sh command."
  printf '%s\n' "This script does not create release evidence or mark signing/notarization/manual gates passed."
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --worksheet-output)
      WORKSHEET_FILE="${2:-}"
      shift 2
      ;;
    --command-output)
      COMMAND_FILE="${2:-}"
      shift 2
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

if [[ -z "$WORKSHEET_FILE" || -z "$COMMAND_FILE" ]]; then
  echo "worksheet and command output paths must not be blank" >&2
  exit 2
fi

if [[ ! -f "$METADATA_FILE" ]]; then
  echo "missing metadata file: $METADATA_FILE" >&2
  exit 2
fi

# shellcheck source=/dev/null
source "$METADATA_FILE"

APP_NAME="${APP_NAME:?APP_NAME is required}"
MARKETING_VERSION="${MARKETING_VERSION:?MARKETING_VERSION is required}"
CURRENT_PROJECT_VERSION="${CURRENT_PROJECT_VERSION:?CURRENT_PROJECT_VERSION is required}"
SOURCE_COMMIT="$(git -C "$ROOT_DIR" rev-parse --short=8 HEAD 2>/dev/null || printf "unknown")"
ARTIFACT_SHA256_FILE="dist/releases/$APP_NAME-$MARKETING_VERSION+$CURRENT_PROJECT_VERSION.dmg.sha256"

display_path() {
  local path="$1"
  if [[ "$path" == "$ROOT_DIR/"* ]]; then
    printf '%s' "${path#"$ROOT_DIR/"}"
  else
    printf '%s' "$path"
  fi
}

write_release_evidence_invocation() {
  local first_argument="$1"

  printf './script/create_release_evidence.sh %s \\\n' "$first_argument"
  printf '%s\n' '  --release-machine-launch \'
  printf '%s\n' '  --checksum-verification \'
  printf '%s\n' '  --clean-dmg-install \'
  printf '%s\n' '  --applications-folder-install \'
  printf '%s\n' '  --gatekeeper-accepted \'
  printf '%s\n' '  --clean-environment-launch \'
  printf '%s\n' '  --login-item-toggle \'
  printf '%s\n' '  --sparkle-appcast-metadata \'
  printf '%s\n' '  --manual-environment "$WORKSHEET_MANUAL_ENVIRONMENT" \'
  printf '%s\n' '  --checked-by "$WORKSHEET_REVIEWER" \'
  printf '%s\n' '  --note "$WORKSHEET_NOTE"'
}

write_worksheet() {
  mkdir -p "$(dirname "$WORKSHEET_FILE")"

  {
    printf '%s\n' '# Release Machine Evidence Worksheet'
    printf '\n'
    printf '%s\n' 'Status: pending'
    printf '\n'
    printf '%s\n' 'This worksheet is not release evidence. Fill it on the release machine after building, signing, notarizing, packaging, and manually checking the release artifact.'
    printf '\n'
    printf '%s\n' '## Candidate Metadata'
    printf '\n'
    printf -- '- Release candidate source commit: `%s`\n' "$SOURCE_COMMIT"
    printf -- '- App: `%s`\n' "$APP_NAME"
    printf -- '- Version: `%s`\n' "$MARKETING_VERSION"
    printf -- '- Build: `%s`\n' "$CURRENT_PROJECT_VERSION"
    printf -- '- App bundle: `dist/%s.app`\n' "$APP_NAME"
    printf -- '- Artifact checksum: `%s`\n' "$ARTIFACT_SHA256_FILE"
    printf -- '- Evidence output: `%s`\n' "$EVIDENCE_OUTPUT_FILE"
    printf -- '- Evidence command: `%s`\n' "$(display_path "$COMMAND_FILE")"
    printf '\n'
    printf '%s\n' '## Prerequisite Checks'
    printf '\n'
    printf '%s\n' '- [ ] Developer ID signing identity is configured and verified.'
    printf '%s\n' '- [ ] Notary profile is configured and verified online.'
    printf '%s\n' '- [ ] Production Sparkle feed URL and public EdDSA key are configured.'
    printf '%s\n' '- [ ] Release app is signed, notarized, and stapled.'
    printf '%s\n' '- [ ] DMG and Sparkle artifacts were generated from this source commit.'
    printf '%s\n' '- [ ] Release appcast verifies with `SUISUI_REQUIRE_RELEASE_APPCAST=1 ./script/verify_appcast.sh dist/releases/appcast.xml`.'
    printf '\n'
    printf '%s\n' '## Manual Release Checks To Perform'
    printf '\n'
    printf '%s\n' '- [ ] Release-machine launch: open `dist/Suisui.app` after signing/notarization.'
    printf '%s\n' '- [ ] Checksum verification: verify the DMG SHA-256 against the generated `.sha256` file.'
    printf '%s\n' '- [ ] Clean DMG install: download/open the DMG in a clean user or VM.'
    printf '%s\n' '- [ ] Applications folder install: drag Suisui to `/Applications` and launch it there.'
    printf '%s\n' '- [ ] Gatekeeper acceptance: confirm `spctl` or Finder launch accepts the stapled app.'
    printf '%s\n' '- [ ] Clean environment launch: first launch succeeds in the clean user or VM.'
    printf '%s\n' '- [ ] Launch at Login toggle: Settings toggles Launch at Login on and off in the signed app.'
    printf '%s\n' '- [ ] Sparkle appcast metadata: appcast points to this version/build and artifact.'
    printf '\n'
    printf '%s\n' '## Release Evidence Notes To Fill'
    printf '\n'
    printf '%s\n' '- Reviewer:'
    printf '%s\n' '- Manual environment:'
    printf '%s\n' '- Signed artifact path:'
    printf '%s\n' '- Notarization ticket or log reference:'
    printf '%s\n' '- Appcast path and edSignature reference:'
    printf '%s\n' '- Release-machine launch:'
    printf '%s\n' '- Checksum verification:'
    printf '%s\n' '- Clean DMG install:'
    printf '%s\n' '- Applications folder install:'
    printf '%s\n' '- Gatekeeper acceptance:'
    printf '%s\n' '- Clean environment launch:'
    printf '%s\n' '- Launch at Login toggle:'
    printf '%s\n' '- Sparkle appcast metadata:'
    printf '\n'
    printf '%s\n' '## Evidence Command'
    printf '\n'
    printf -- 'Run `%s` only after every checked item above is true.\n' "$(display_path "$COMMAND_FILE")"
    printf '%s\n' 'The generated command reads concrete observations directly from this worksheet; do not duplicate them in the command file.'
    printf '%s\n' 'The generated command validates the filled evidence, writes `packaging/release-evidence.json`, then reruns the online release environment preflight.'
    printf '\n'
    printf '%s\n' '## Closeout'
    printf '\n'
    printf '%s\n' '1. Change `Status: pending` to `Status: completed` after every prerequisite and manual release check passes.'
    printf '%s\n' '2. Fill every release evidence note with concrete release-machine observations.'
    printf '%s\n' '3. Change every completed check from `[ ]` to `[x]`. Keep this instruction text; completion is determined by `Status: completed`, every `[x]` check, and every required observation.'
  } >"$WORKSHEET_FILE"
}

write_command() {
  mkdir -p "$(dirname "$COMMAND_FILE")"

  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' 'set -euo pipefail'
    printf '\n'
    printf '%s\n' '# Generated by script/prepare_release_machine_evidence.sh.'
    printf '# Fill %s while reviewing; this command reads the completed worksheet directly.\n' "$WORKSHEET_FILE"
    printf '%s\n' '# Keep worksheet instructions, set Status: completed, check every item, and fill every required value.'
    printf '%s\n' '# This command must only be run after the signed, notarized, stapled release artifact and appcast are verified.'
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
    printf '%s\n' '  printf "BLOCKER: release evidence command requires a clean tracked source tree. Commit or revert tracked source changes, then rerun ./script/prepare_release_machine_evidence.sh for this release candidate.\n" >&2'
    printf '%s\n' '  exit 2'
    printf '%s\n' 'fi'
    printf '\n'
    printf 'EXPECTED_SOURCE_COMMIT=%q\n' "$SOURCE_COMMIT"
    printf '%s\n' 'CURRENT_SOURCE_COMMIT="$(git rev-parse --short=8 HEAD 2>/dev/null || printf unknown)"'
    printf '%s\n' 'if [[ "$CURRENT_SOURCE_COMMIT" != "$EXPECTED_SOURCE_COMMIT" ]]; then'
    printf '%s\n' '  printf "BLOCKER: release evidence command was generated for source commit %s but current source commit is %s. Rerun ./script/prepare_release_machine_evidence.sh for this release candidate.\n" "$EXPECTED_SOURCE_COMMIT" "$CURRENT_SOURCE_COMMIT" >&2'
    printf '%s\n' '  exit 2'
    printf '%s\n' 'fi'
    printf '\n'
    printf 'RELEASE_MACHINE_WORKSHEET_FILE=%q\n' "$WORKSHEET_FILE"
    printf '%s\n' 'release_machine_worksheet_value_is_placeholder_or_boilerplate() {'
    printf '%s\n' '  local raw'
    printf '%s\n' '  local normalized'
    printf '%s\n' '  raw="$(printf "%s" "$1" | tr "[:upper:]" "[:lower:]")"'
    printf '%s\n' '  case "$raw" in'
    printf '%s\n' '    ""|\<*|*\>|*placeholder*|*replace*|*sample*|*example*|*todo*|*tbd*)'
    printf '%s\n' '      return 0'
    printf '%s\n' '      ;;'
    printf '%s\n' '  esac'
    printf '%s\n' '  normalized="$(printf "%s" "$1" | tr "[:upper:]" "[:lower:]" | sed -E "s/[[:punct:]]+/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]]+/ /g")"'
    printf '%s\n' '  case "$normalized" in'
    printf '%s\n' '    verified|checked|done|passed|ok|okay|"looks good"|"no issue"|"no issues"|"manual checks completed"|"manual release pass completed")'
    printf '%s\n' '      return 0'
    printf '%s\n' '      ;;'
    printf '%s\n' '    *)'
    printf '%s\n' '      return 1'
    printf '%s\n' '      ;;'
    printf '%s\n' '  esac'
    printf '%s\n' '}'
    printf '\n'
    printf '%s\n' 'verify_release_machine_worksheet_for_evidence() {'
    printf '%s\n' '  local expected_commit_marker'
    printf '%s\n' '  local required_label'
    printf '%s\n' '  local worksheet_value'
    printf '%s\n' '  expected_commit_marker="Release candidate source commit: \`$EXPECTED_SOURCE_COMMIT\`"'
    printf '%s\n' ''
    printf '%s\n' '  if [[ ! -f "$RELEASE_MACHINE_WORKSHEET_FILE" ]]; then'
    printf '%s\n' '    printf "BLOCKER: release-machine worksheet is missing, stale, or incomplete: %s does not exist.\n" "$RELEASE_MACHINE_WORKSHEET_FILE" >&2'
    printf '%s\n' '    exit 2'
    printf '%s\n' '  fi'
    printf '%s\n' ''
    printf '%s\n' '  if ! grep -F -- "$expected_commit_marker" "$RELEASE_MACHINE_WORKSHEET_FILE" >/dev/null; then'
    printf '%s\n' '    printf "BLOCKER: release-machine worksheet is missing, stale, or incomplete: expected release candidate source commit %s.\n" "$EXPECTED_SOURCE_COMMIT" >&2'
    printf '%s\n' '    exit 2'
    printf '%s\n' '  fi'
    printf '%s\n' ''
    printf '%s\n' '  if ! grep -Fx -- "Status: completed" "$RELEASE_MACHINE_WORKSHEET_FILE" >/dev/null; then'
    printf '%s\n' '    printf "BLOCKER: release-machine worksheet is missing, stale, or incomplete: set Status: completed after the release-machine pass.\n" >&2'
    printf '%s\n' '    exit 2'
    printf '%s\n' '  fi'
    printf '%s\n' ''
    printf '%s\n' '  if grep -F -- "- [ ]" "$RELEASE_MACHINE_WORKSHEET_FILE" >/dev/null; then'
    printf '%s\n' '    printf "BLOCKER: release-machine worksheet is missing, stale, or incomplete: unchecked release-machine items remain.\n" >&2'
    printf '%s\n' '    exit 2'
    printf '%s\n' '  fi'
    printf '%s\n' ''
    printf '%s\n' '  for required_check in "Developer ID signing identity" "Notary profile" "Production Sparkle feed URL" "Release app is signed, notarized, and stapled" "DMG and Sparkle artifacts" "Release appcast verifies" "Release-machine launch:" "Checksum verification:" "Clean DMG install:" "Applications folder install:" "Gatekeeper acceptance:" "Clean environment launch:" "Launch at Login toggle:" "Sparkle appcast metadata:"; do'
    printf '%s\n' '    if ! grep -F -- "- [x] $required_check" "$RELEASE_MACHINE_WORKSHEET_FILE" >/dev/null; then'
    printf '%s\n' '      printf "BLOCKER: release-machine worksheet is missing, stale, or incomplete: required checked item is missing: %s\n" "$required_check" >&2'
    printf '%s\n' '      exit 2'
    printf '%s\n' '    fi'
    printf '%s\n' '  done'
    printf '%s\n' ''
    printf '%s\n' '  for required_label in "Reviewer" "Manual environment" "Signed artifact path" "Notarization ticket or log reference" "Appcast path and edSignature reference" "Release-machine launch" "Checksum verification" "Clean DMG install" "Applications folder install" "Gatekeeper acceptance" "Clean environment launch" "Launch at Login toggle" "Sparkle appcast metadata"; do'
    printf '%s\n' '    worksheet_value="$(sed -n -E "s/^- ${required_label}:[[:space:]]*(.*)$/\1/p" "$RELEASE_MACHINE_WORKSHEET_FILE" | tail -n 1)"'
    printf '%s\n' '    if [[ -z "${worksheet_value//[[:space:]]/}" ]]; then'
    printf '%s\n' '      printf "BLOCKER: release-machine worksheet is missing, stale, or incomplete: fill %s.\n" "$required_label" >&2'
    printf '%s\n' '      exit 2'
    printf '%s\n' '    fi'
    printf '%s\n' '    if release_machine_worksheet_value_is_placeholder_or_boilerplate "$worksheet_value"; then'
    printf '%s\n' '      printf "BLOCKER: release-machine worksheet is missing, stale, or incomplete: fill %s with concrete release-machine observation.\n" "$required_label" >&2'
    printf '%s\n' '      exit 2'
    printf '%s\n' '    fi'
    printf '%s\n' '  done'
    printf '%s\n' '}'
    printf '\n'
    printf '%s\n' 'verify_release_machine_worksheet_for_evidence'
    printf '\n'
    printf '%s\n' 'release_machine_worksheet_value() {'
    printf '%s\n' '  local label="$1"'
    printf '%s\n' '  sed -n -E "s/^- ${label}:[[:space:]]*(.*)$/\1/p" "$RELEASE_MACHINE_WORKSHEET_FILE" | tail -n 1'
    printf '%s\n' '}'
    printf '\n'
    printf '%s\n' '# The worksheet is the single source of release-machine observations.'
    printf '%s\n' '# Building the evidence note here prevents the generated command and worksheet from drifting.'
    printf '%s\n' 'WORKSHEET_REVIEWER="$(release_machine_worksheet_value "Reviewer")"'
    printf '%s\n' 'WORKSHEET_MANUAL_ENVIRONMENT="$(release_machine_worksheet_value "Manual environment")"'
    printf '%s\n' 'WORKSHEET_NOTE="release-machine launch: $(release_machine_worksheet_value "Release-machine launch"); checksum SHA-256: $(release_machine_worksheet_value "Checksum verification"); clean DMG install: $(release_machine_worksheet_value "Clean DMG install"); /Applications launch: $(release_machine_worksheet_value "Applications folder install"); Gatekeeper/spctl acceptance: $(release_machine_worksheet_value "Gatekeeper acceptance"); clean environment first launch: $(release_machine_worksheet_value "Clean environment launch"); Launch at Login toggle on/off: $(release_machine_worksheet_value "Launch at Login toggle"); Sparkle appcast metadata: $(release_machine_worksheet_value "Sparkle appcast metadata")"'
    printf '\n'
    printf '%s\n' 'source packaging/app_metadata.env'
    printf '%s\n' 'for release_config_file in packaging/signing.env packaging/notarization.env packaging/sparkle.env; do'
    printf '%s\n' '  if [[ ! -f "$release_config_file" ]]; then'
    printf '%s\n' '    printf "BLOCKER: release evidence command requires $release_config_file on the release machine. Copy the matching .example file, replace placeholders with production values, then rerun ./script/prepare_release_machine_evidence.sh for this release candidate.\n" >&2'
    printf '%s\n' '    exit 2'
    printf '%s\n' '  fi'
    printf '%s\n' '  source "$release_config_file"'
    printf '%s\n' 'done'
    printf '%s\n' 'export SUISUI_RELEASE_ARTIFACT_SHA256_FILE="dist/releases/$APP_NAME-$MARKETING_VERSION+$CURRENT_PROJECT_VERSION.dmg.sha256"'
    printf '\n'
    printf '%s\n' '# Verify release-machine signing, notarization, and Sparkle setup before validating manual evidence.'
    printf '%s\n' './script/verify_signing_setup.sh'
    printf '%s\n' 'SUISUI_RELEASE_PREFLIGHT_ONLINE=1 ./script/verify_notarization_setup.sh'
    printf '%s\n' 'SUISUI_BUILD_CONFIGURATION=release SUISUI_SPARKLE_CONFIG_QUIET=1 ./script/validate_sparkle_release_config.sh'
    printf '\n'
    printf '%s\n' '# Validate the filled release-machine evidence command before writing tracked evidence.'
    write_release_evidence_invocation "--validate-only"
    printf '\n'
    printf '%s\n' 'if [[ "$VALIDATE_ONLY" == 1 ]]; then'
    printf '%s\n' '  printf "%s\n" "Release evidence validation passed; packaging/release-evidence.json was not written."'
    printf '%s\n' '  exit 0'
    printf '%s\n' 'fi'
    printf '\n'
    printf '%s\n' '# If validation passes and every release-machine manual check is complete, write tracked evidence.'
    write_release_evidence_invocation "--force"
    printf '\n'
    printf '%s\n' '# Run final release-machine preflight after evidence is written.'
    printf '%s\n' 'SUISUI_RELEASE_PREFLIGHT_ONLINE=1 ./script/verify_release_environment.sh'
  } >"$COMMAND_FILE"

  chmod +x "$COMMAND_FILE"
}

write_worksheet
write_command

printf 'Release machine worksheet written: %s\n' "$WORKSHEET_FILE"
printf 'Release evidence command written: %s\n' "$COMMAND_FILE"
