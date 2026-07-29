#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METADATA_FILE="$ROOT_DIR/packaging/app_metadata.env"
SIGNING_ENV_FILE="$ROOT_DIR/packaging/signing.env"
NOTARIZATION_ENV_FILE="$ROOT_DIR/packaging/notarization.env"
SPARKLE_ENV_FILE="$ROOT_DIR/packaging/sparkle.env"
OUTPUT_FILE="${SUISUI_RELEASE_EVIDENCE_FILE:-$ROOT_DIR/packaging/release-evidence.json}"
CHECKSUM_FILE="${SUISUI_RELEASE_ARTIFACT_SHA256_FILE:-}"
RELEASE_APPCAST_FILE="${SUISUI_RELEASE_APPCAST_FILE:-$ROOT_DIR/dist/releases/appcast.xml}"
FORCE=0
VALIDATE_ONLY=0
RELEASE_MACHINE_LAUNCH=false
CHECKSUM_VERIFICATION=false
CLEAN_DMG_INSTALL=false
APPLICATIONS_FOLDER_INSTALL=false
GATEKEEPER_ACCEPTED=false
CLEAN_ENVIRONMENT_LAUNCH=false
LOGIN_ITEM_TOGGLE=false
SPARKLE_APPCAST_METADATA=false
MANUAL_ENVIRONMENT=""
CHECKED_BY="${SUISUI_RELEASE_CHECKED_BY:-$(id -un 2>/dev/null || printf "release-owner")}"
NOTES=()

usage() {
  cat <<'USAGE'
Usage:
  create_release_evidence.sh [options]

Options:
  --force                         overwrite existing evidence file
  --validate-only                 run validation without writing release evidence
  --release-machine-launch        mark signed/notarized app launch on release machine as checked
  --checksum-verification         mark release artifact checksum verification as checked
  --clean-dmg-install             mark clean environment DMG download/open as checked
  --applications-folder-install   mark Applications folder install flow as checked
  --gatekeeper-accepted           mark Gatekeeper acceptance as checked
  --clean-environment-launch      mark clean environment launch as manually checked
  --login-item-toggle             mark launch-at-login toggle as manually checked
  --sparkle-appcast-metadata      mark Sparkle appcast metadata check as checked
  --manual-environment <text>     describe the manual check environment
  --checked-by <name>             reviewer name to record
  --note <text>                   append a review note; can be repeated
  -h, --help                      show this help

The script records metadata and artifact checksum evidence only. Pass manual
check flags only after testing the signed and notarized build.

Manual flag evidence requirements:
  --release-machine-launch: signed/notarized app opens from dist/Suisui.app on the release machine
  --checksum-verification: shasum -a 256 matches the generated *.sha256 artifact
  --clean-dmg-install: DMG downloads and opens in a clean user or VM
  --applications-folder-install: app is dragged to /Applications and launches there
  --gatekeeper-accepted: spctl/Gatekeeper accepts the stapled app
  --clean-environment-launch: first launch succeeds in the clean user or VM
  --login-item-toggle: Settings toggles launch-at-login on and off in the signed app
  --sparkle-appcast-metadata: release appcast metadata points to this version/build
USAGE
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --force)
      FORCE=1
      shift
      ;;
    --validate-only)
      VALIDATE_ONLY=1
      shift
      ;;
    --release-machine-launch)
      RELEASE_MACHINE_LAUNCH=true
      shift
      ;;
    --checksum-verification)
      CHECKSUM_VERIFICATION=true
      shift
      ;;
    --clean-dmg-install)
      CLEAN_DMG_INSTALL=true
      shift
      ;;
    --applications-folder-install)
      APPLICATIONS_FOLDER_INSTALL=true
      shift
      ;;
    --gatekeeper-accepted)
      GATEKEEPER_ACCEPTED=true
      shift
      ;;
    --clean-environment-launch)
      CLEAN_ENVIRONMENT_LAUNCH=true
      shift
      ;;
    --login-item-toggle)
      LOGIN_ITEM_TOGGLE=true
      shift
      ;;
    --sparkle-appcast-metadata)
      SPARKLE_APPCAST_METADATA=true
      shift
      ;;
    --manual-environment)
      if [[ "$#" -lt 2 || -z "$2" ]]; then
        echo "--manual-environment requires a value" >&2
        exit 2
      fi
      MANUAL_ENVIRONMENT="$2"
      shift 2
      ;;
    --checked-by)
      if [[ "$#" -lt 2 || -z "$2" ]]; then
        echo "--checked-by requires a value" >&2
        exit 2
      fi
      CHECKED_BY="$2"
      shift 2
      ;;
    --note)
      if [[ "$#" -lt 2 || -z "$2" ]]; then
        echo "--note requires a value" >&2
        exit 2
      fi
      NOTES+=("$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unsupported option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! -f "$METADATA_FILE" ]]; then
  echo "missing metadata file: $METADATA_FILE" >&2
  exit 2
fi

if [[ "$VALIDATE_ONLY" != "1" && -f "$OUTPUT_FILE" && "$FORCE" != "1" ]]; then
  echo "release evidence already exists: $OUTPUT_FILE" >&2
  echo "rerun with --force to overwrite it" >&2
  exit 2
fi

# shellcheck source=/dev/null
source "$METADATA_FILE"

if [[ "${SUISUI_LOAD_LOCAL_RELEASE_CONFIG:-1}" == "1" && -f "$SIGNING_ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$SIGNING_ENV_FILE"
fi

if [[ "${SUISUI_LOAD_LOCAL_RELEASE_CONFIG:-1}" == "1" && -f "$NOTARIZATION_ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$NOTARIZATION_ENV_FILE"
fi

if [[ "${SUISUI_LOAD_LOCAL_RELEASE_CONFIG:-1}" == "1" && -f "$SPARKLE_ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$SPARKLE_ENV_FILE"
fi

APP_NAME="${APP_NAME:?APP_NAME is required}"
MARKETING_VERSION="${MARKETING_VERSION:?MARKETING_VERSION is required}"
CURRENT_PROJECT_VERSION="${CURRENT_PROJECT_VERSION:?CURRENT_PROJECT_VERSION is required}"
APP_BUNDLE_PATH="dist/$APP_NAME.app"
ARTIFACT_BASENAME="$APP_NAME-$MARKETING_VERSION+$CURRENT_PROJECT_VERSION"
CHECKED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
RELEASE_EVIDENCE_GENERATOR="script/create_release_evidence.sh"
SIGNING_IDENTITY="${SUISUI_SIGNING_IDENTITY:-}"
NOTARY_PROFILE="${SUISUI_NOTARY_PROFILE:-}"
SPARKLE_FEED_URL="${SUISUI_SPARKLE_FEED_URL:-${SPARKLE_FEED_URL:-}}"
SPARKLE_PUBLIC_ED_KEY="${SUISUI_SPARKLE_PUBLIC_ED_KEY:-${SPARKLE_PUBLIC_ED_KEY:-}}"

current_git_commit() {
  if command -v git >/dev/null 2>&1 && git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || true
  fi
}

SOURCE_GIT_COMMIT="$(current_git_commit)"

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf "%s" "$value"
}

trim_text() {
  printf "%s" "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

manual_environment_lacks_release_context() {
  local normalized
  normalized="$(trim_text "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[[:space:]]+/ /g')"

  case "$normalized" in
    *macos*)
      ;;
    *)
      return 0
      ;;
  esac

  case "$normalized" in
    *"clean user"*|\
    *"clean vm"*|\
    *"clean environment"*|\
    *"fresh user"*|\
    *"separate user"*|\
    *"virtual machine"*|\
    *"vm"*|\
    *install*)
      ;;
    *)
      return 0
      ;;
  esac

  case "$normalized" in
    *arm64*|\
    *arm64e*|\
    *x86_64*|\
    *intel*|\
    *"apple silicon"*|\
    *macbook*|\
    *"mac mini"*|\
    *"mac studio"*|\
    *imac*|\
    *m1*|\
    *m2*|\
    *m3*|\
    *m4*)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

is_placeholder_manual_environment() {
  local normalized
  normalized="$(trim_text "$1" | tr '[:upper:]' '[:lower:]')"
  case "$normalized" in
    ""|\
    \<*|\
    *\>|\
    "macos version, hardware, clean user/install notes"|\
    *placeholder*|\
    *replace*|\
    *sample*|\
    *example*|\
    *todo*)
      return 0
      ;;
    *)
      manual_environment_lacks_release_context "$1"
      ;;
  esac
}

is_placeholder_checked_by() {
  local normalized
  normalized="$(trim_text "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[[:space:]]+/ /g')"
  case "$normalized" in
    name|\
    \<*|\
    *\>|\
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

is_boilerplate_review_note() {
  local normalized
  normalized="$(trim_text "$1" | tr '[:upper:]' '[:lower:]')"
  normalized="${normalized//./}"
  normalized="${normalized//,/}"
  normalized="${normalized//;/}"
  case "$normalized" in
    ""|\
    "manual checks completed"|\
    "manual checks completed on signed build"|\
    "manual checks completed on the signed build"|\
    "set booleans true only after the signed and notarized build is tested"|\
    "generated from packaging/app_metadataenv set manual check flags only after testing the signed and notarized build"|\
    \<*|\
    *\>|\
    *placeholder*|\
    *replace*|\
    *sample*|\
    *example*|\
    *todo*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

require_clean_tracked_source_tree_for_passed_evidence() {
  local tracked_source_status

  if ! command -v git >/dev/null 2>&1; then
    echo "BLOCKER: release evidence requires git to verify the release source tree" >&2
    exit 2
  fi

  if ! git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "BLOCKER: release evidence requires a git worktree" >&2
    exit 2
  fi

  tracked_source_status="$(git -C "$ROOT_DIR" status --porcelain --untracked-files=no)"
  if [[ -n "$tracked_source_status" ]]; then
    echo "BLOCKER: release evidence requires a clean tracked source tree. Commit or revert tracked source changes, then rerun ./script/prepare_release_machine_evidence.sh for this release candidate." >&2
    exit 2
  fi
}

manual_checks_requested() {
  [[ "$RELEASE_MACHINE_LAUNCH" == "true" \
    || "$CHECKSUM_VERIFICATION" == "true" \
    || "$CLEAN_DMG_INSTALL" == "true" \
    || "$APPLICATIONS_FOLDER_INSTALL" == "true" \
    || "$GATEKEEPER_ACCEPTED" == "true" \
    || "$CLEAN_ENVIRONMENT_LAUNCH" == "true" \
    || "$LOGIN_ITEM_TOGGLE" == "true" \
    || "$SPARKLE_APPCAST_METADATA" == "true" ]]
}

review_notes_text() {
  printf '%s\n' "${NOTES[@]}"
}

require_manual_note_proof_if_checked() {
  local is_checked="$1"
  local label="$2"
  local pattern="$3"

  if [[ "$is_checked" != "true" ]]; then
    return
  fi

  if ! review_notes_text | grep -Eiq "$pattern"; then
    printf "manual release evidence note missing proof for %s\n" "$label" >&2
    exit 2
  fi
}

require_manual_note_proofs() {
  require_manual_note_proof_if_checked \
    "$RELEASE_MACHINE_LAUNCH" \
    "release machine launch" \
    'release[ -]?machine.*launch|launch.*release[ -]?machine|dist/suisui\.app'
  require_manual_note_proof_if_checked \
    "$CHECKSUM_VERIFICATION" \
    "checksum verification" \
    'checksum|sha-?256|shasum'
  require_manual_note_proof_if_checked \
    "$CLEAN_DMG_INSTALL" \
    "clean DMG install" \
    'clean.*dmg|dmg.*clean'
  require_manual_note_proof_if_checked \
    "$APPLICATIONS_FOLDER_INSTALL" \
    "Applications folder install" \
    'applications|/applications'
  require_manual_note_proof_if_checked \
    "$GATEKEEPER_ACCEPTED" \
    "Gatekeeper acceptance" \
    'gatekeeper|spctl'
  require_manual_note_proof_if_checked \
    "$CLEAN_ENVIRONMENT_LAUNCH" \
    "clean environment launch" \
    'clean.*environment.*launch|clean.*user.*launch|clean.*vm.*launch|first.*launch'
  require_manual_note_proof_if_checked \
    "$LOGIN_ITEM_TOGGLE" \
    "login item toggle" \
    'login[ -]?item|launch[ -]?at[ -]?login'
  require_manual_note_proof_if_checked \
    "$SPARKLE_APPCAST_METADATA" \
    "Sparkle appcast metadata" \
    'sparkle.*appcast|appcast.*sparkle'
}

artifact_path_for_compare() {
  local artifact_path="$1"
  if [[ "$artifact_path" == "$ROOT_DIR/"* ]]; then
    printf "%s" "${artifact_path#"$ROOT_DIR/"}"
  else
    printf "%s" "$artifact_path"
  fi
}

artifact_file_for_path() {
  local artifact_path="$1"
  if [[ "$artifact_path" == /* ]]; then
    printf "%s" "$artifact_path"
  else
    printf "%s/%s" "$ROOT_DIR" "$artifact_path"
  fi
}

find_checksum_file() {
  if [[ -n "$CHECKSUM_FILE" ]]; then
    printf "%s" "$CHECKSUM_FILE"
    return
  fi

  find "$ROOT_DIR/dist/releases" \
    -maxdepth 1 \
    -type f \
    -name "$ARTIFACT_BASENAME.*.sha256" \
    2>/dev/null \
    | sort \
    | head -n 1
}

read_artifact_sha256() {
  local checksum_path
  checksum_path="$(find_checksum_file)"

  if [[ -z "$checksum_path" || ! -f "$checksum_path" ]]; then
    printf "missing-release-artifact"
    return
  fi

  awk 'NF { print $1; exit }' "$checksum_path"
}

read_artifact_path() {
  local checksum_path
  checksum_path="$(find_checksum_file)"

  if [[ -z "$checksum_path" || ! -f "$checksum_path" ]]; then
    printf "missing-release-artifact"
    return
  fi

  awk 'NF >= 2 { print $2; exit }' "$checksum_path"
}

package_evidence_file() {
  local checksum_path
  checksum_path="$(find_checksum_file)"

  if [[ -z "$checksum_path" || ! -f "$checksum_path" ]]; then
    return
  fi

  printf "%s" "${checksum_path%.sha256}.package-evidence.json"
}

require_release_package_evidence() {
  local manifest_path
  local manifest_artifact_path
  local expected_artifact_path
  local signed_required
  local notarized_required
  local manifest_git_commit
  local artifact_file
  manifest_path="$(package_evidence_file)"

  if [[ -z "$manifest_path" || ! -f "$manifest_path" ]]; then
    echo "release evidence requires package evidence manifest from ./script/package_release.sh" >&2
    exit 2
  fi

  if command -v plutil >/dev/null 2>&1; then
    if ! plutil -convert json -o /dev/null "$manifest_path" 2>/dev/null; then
      echo "package evidence manifest is not valid JSON or plist: $manifest_path" >&2
      exit 2
    fi
    manifest_artifact_path="$(plutil -extract "package.artifactPath" raw -o - "$manifest_path" 2>/dev/null || true)"
    signed_required="$(plutil -extract "package.signedPackageRequired" raw -o - "$manifest_path" 2>/dev/null || true)"
    notarized_required="$(plutil -extract "package.notarizedPackageRequired" raw -o - "$manifest_path" 2>/dev/null || true)"
    manifest_git_commit="$(plutil -extract "source.gitCommit" raw -o - "$manifest_path" 2>/dev/null || true)"
  else
    manifest_artifact_path="$(awk -F': ' '/"artifactPath"/ { gsub(/[",]/, "", $2); print $2; exit }' "$manifest_path")"
    signed_required="$(awk -F': ' '/"signedPackageRequired"/ { gsub(/[ ,]/, "", $2); print $2; exit }' "$manifest_path")"
    notarized_required="$(awk -F': ' '/"notarizedPackageRequired"/ { gsub(/[ ,]/, "", $2); print $2; exit }' "$manifest_path")"
    manifest_git_commit="$(awk -F': ' '/"gitCommit"/ { gsub(/[",]/, "", $2); print $2; exit }' "$manifest_path")"
  fi

  expected_artifact_path="$(read_artifact_path)"
  if [[ -z "$manifest_artifact_path" ]]; then
    echo "package evidence manifest is missing artifact path" >&2
    exit 2
  fi

  if [[ "$(artifact_path_for_compare "$manifest_artifact_path")" != "$(artifact_path_for_compare "$expected_artifact_path")" ]]; then
    echo "package evidence artifact path does not match checksum: expected '$expected_artifact_path', got '$manifest_artifact_path'" >&2
    exit 2
  fi

  if [[ "$signed_required" != "true" || "$notarized_required" != "true" ]]; then
    echo "release evidence requires an artifact packaged with signed and notarized gates enabled" >&2
    exit 2
  fi

  if [[ -z "$manifest_git_commit" ]]; then
    echo "package evidence manifest is missing source git commit" >&2
    exit 2
  fi

  if [[ -n "$SOURCE_GIT_COMMIT" && "$manifest_git_commit" != "$SOURCE_GIT_COMMIT" ]]; then
    echo "package evidence source commit does not match current git commit" >&2
    exit 2
  fi

  artifact_file="$(artifact_file_for_path "$expected_artifact_path")"
  "$ROOT_DIR/script/verify_package_evidence_metrics.sh" \
    "$manifest_path" \
    "$artifact_file"
}

require_artifact_file_integrity() {
  local expected_sha="$1"
  local expected_artifact_path="$2"
  local artifact_file
  local actual_sha

  if [[ -z "$expected_artifact_path" ]]; then
    echo "release artifact checksum file is missing artifact path" >&2
    exit 2
  fi

  artifact_file="$(artifact_file_for_path "$expected_artifact_path")"
  if [[ ! -f "$artifact_file" ]]; then
    echo "missing release artifact file: $expected_artifact_path" >&2
    exit 2
  fi

  if ! command -v shasum >/dev/null 2>&1; then
    echo "release evidence requires shasum to verify artifact checksum" >&2
    exit 2
  fi

  actual_sha="$(shasum -a 256 "$artifact_file" | awk 'NF { print $1; exit }')"
  if [[ "$actual_sha" != "$expected_sha" ]]; then
    echo "release artifact SHA-256 does not match checksum file: expected '$expected_sha', got '$actual_sha'" >&2
    exit 2
  fi
}

require_release_signing_context() {
  if [[ -z "$SIGNING_IDENTITY" || -z "$NOTARY_PROFILE" ]]; then
    echo "release evidence requires SUISUI_SIGNING_IDENTITY and SUISUI_NOTARY_PROFILE" >&2
    exit 2
  fi

  case "$SIGNING_IDENTITY" in
    "Developer ID Application:"*)
      ;;
    *)
      echo "release evidence requires a Developer ID Application signing identity: $SIGNING_IDENTITY" >&2
      exit 2
      ;;
  esac
}

require_release_sparkle_context() {
  local validation_output
  if ! validation_output="$(
    SUISUI_BUILD_CONFIGURATION=release \
      SUISUI_SPARKLE_CONFIG_QUIET=1 \
      SUISUI_SPARKLE_FEED_URL="$SPARKLE_FEED_URL" \
      SUISUI_SPARKLE_PUBLIC_ED_KEY="$SPARKLE_PUBLIC_ED_KEY" \
      "$ROOT_DIR/script/validate_sparkle_release_config.sh" 2>&1
  )"; then
    printf "release evidence Sparkle config is invalid: %s\n" "$validation_output" >&2
    exit 2
  fi
}

require_release_appcast() {
  local validation_output
  if ! validation_output="$(
    SUISUI_REQUIRE_RELEASE_APPCAST=1 \
      "$ROOT_DIR/script/verify_appcast.sh" "$RELEASE_APPCAST_FILE" 2>&1
  )"; then
    printf "release evidence appcast verification failed: %s: %s\n" "$RELEASE_APPCAST_FILE" "$validation_output" >&2
    exit 2
  fi
}

EXPLICIT_NOTE_COUNT="${#NOTES[@]}"
if [[ "$EXPLICIT_NOTE_COUNT" -eq 0 ]]; then
  NOTES+=("Generated from packaging/app_metadata.env. Set manual check flags only after testing the signed and notarized build.")
fi

CHECKED_BY="$(trim_text "$CHECKED_BY")"
if [[ -z "$CHECKED_BY" ]]; then
  echo "release evidence requires --checked-by to name the reviewer" >&2
  exit 2
fi
if is_placeholder_checked_by "$CHECKED_BY"; then
  echo "release evidence requires --checked-by to name the actual reviewer" >&2
  exit 2
fi

for index in "${!NOTES[@]}"; do
  NOTES[$index]="$(trim_text "${NOTES[$index]}")"
  if [[ -z "${NOTES[$index]}" ]]; then
    echo "release evidence review notes cannot be blank" >&2
    exit 2
  fi
done

tmp_file="$OUTPUT_FILE.tmp"
artifact_sha="$(read_artifact_sha256)"
artifact_path="$(read_artifact_path)"
appcast_path="$(artifact_path_for_compare "$RELEASE_APPCAST_FILE")"
if [[ "$artifact_sha" == "missing-release-artifact" || "$artifact_path" == "missing-release-artifact" ]]; then
  echo "release evidence requires a packaged artifact checksum; run ./script/package_release.sh first or set SUISUI_RELEASE_ARTIFACT_SHA256_FILE" >&2
  exit 2
fi
if [[ -z "$SOURCE_GIT_COMMIT" ]]; then
  echo "release evidence requires a git commit from the release source checkout" >&2
  exit 2
fi
require_clean_tracked_source_tree_for_passed_evidence
require_release_package_evidence
require_artifact_file_integrity "$artifact_sha" "$artifact_path"

if manual_checks_requested; then
  MANUAL_ENVIRONMENT="$(trim_text "$MANUAL_ENVIRONMENT")"
  if is_placeholder_manual_environment "$MANUAL_ENVIRONMENT"; then
    echo "manual release evidence requires a concrete --manual-environment when manual check flags are set" >&2
    exit 2
  fi
  if [[ "$EXPLICIT_NOTE_COUNT" -eq 0 ]]; then
    echo "manual release evidence requires at least one explicit --note" >&2
    exit 2
  fi
  for note in "${NOTES[@]}"; do
    if is_boilerplate_review_note "$note"; then
      echo "release evidence review notes must include concrete verification details" >&2
      exit 2
    fi
  done
  require_manual_note_proofs
fi
require_release_signing_context
require_release_sparkle_context
require_release_appcast

if [[ "$VALIDATE_ONLY" == "1" ]]; then
  printf 'OK: release evidence command is valid for current source commit: %s\n' "$SOURCE_GIT_COMMIT"
  exit 0
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"

{
  printf '{\n'
  printf '  "release": {\n'
  printf '    "version": "%s",\n' "$(json_escape "$MARKETING_VERSION")"
  printf '    "buildNumber": "%s",\n' "$(json_escape "$CURRENT_PROJECT_VERSION")"
  printf '    "appBundlePath": "%s",\n' "$(json_escape "$APP_BUNDLE_PATH")"
  printf '    "artifactPath": "%s",\n' "$(json_escape "$artifact_path")"
  printf '    "artifactSha256": "%s",\n' "$(json_escape "$artifact_sha")"
  printf '    "signingIdentity": "%s",\n' "$(json_escape "$SIGNING_IDENTITY")"
  printf '    "notaryProfile": "%s",\n' "$(json_escape "$NOTARY_PROFILE")"
  printf '    "sparkleFeedURL": "%s",\n' "$(json_escape "$SPARKLE_FEED_URL")"
  printf '    "appcastPath": "%s"\n' "$(json_escape "$appcast_path")"
  printf '  },\n'
  printf '  "source": {\n'
  printf '    "gitCommit": "%s"\n' "$(json_escape "$SOURCE_GIT_COMMIT")"
  printf '  },\n'
  printf '  "generator": {\n'
  printf '    "name": "%s"\n' "$(json_escape "$RELEASE_EVIDENCE_GENERATOR")"
  printf '  },\n'
  printf '  "manualChecks": {\n'
  printf '    "releaseMachineLaunch": %s,\n' "$RELEASE_MACHINE_LAUNCH"
  printf '    "checksumVerification": %s,\n' "$CHECKSUM_VERIFICATION"
  printf '    "cleanDmgInstall": %s,\n' "$CLEAN_DMG_INSTALL"
  printf '    "applicationsFolderInstall": %s,\n' "$APPLICATIONS_FOLDER_INSTALL"
  printf '    "gatekeeperAccepted": %s,\n' "$GATEKEEPER_ACCEPTED"
  printf '    "cleanEnvironmentLaunch": %s,\n' "$CLEAN_ENVIRONMENT_LAUNCH"
  printf '    "loginItemToggle": %s,\n' "$LOGIN_ITEM_TOGGLE"
  printf '    "sparkleAppcastMetadata": %s,\n' "$SPARKLE_APPCAST_METADATA"
  printf '    "environment": "%s"\n' "$(json_escape "$MANUAL_ENVIRONMENT")"
  printf '  },\n'
  printf '  "review": {\n'
  printf '    "checkedBy": "%s",\n' "$(json_escape "$CHECKED_BY")"
  printf '    "checkedAt": "%s",\n' "$CHECKED_AT"
  printf '    "notes": [\n'
  for index in "${!NOTES[@]}"; do
    suffix=","
    if [[ "$index" == "$((${#NOTES[@]} - 1))" ]]; then
      suffix=""
    fi
    printf '      "%s"%s\n' "$(json_escape "${NOTES[$index]}")" "$suffix"
  done
  printf '    ]\n'
  printf '  }\n'
  printf '}\n'
} >"$tmp_file"

if command -v plutil >/dev/null 2>&1; then
  plutil -convert json -o /dev/null "$tmp_file"
fi

mv "$tmp_file" "$OUTPUT_FILE"
echo "wrote release evidence: $OUTPUT_FILE"
