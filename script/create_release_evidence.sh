#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METADATA_FILE="$ROOT_DIR/packaging/app_metadata.env"
OUTPUT_FILE="${SOLOPM_RELEASE_EVIDENCE_FILE:-$ROOT_DIR/packaging/release-evidence.json}"
CHECKSUM_FILE="${SOLOPM_RELEASE_ARTIFACT_SHA256_FILE:-}"
FORCE=0
CLEAN_ENVIRONMENT_LAUNCH=false
LOGIN_ITEM_TOGGLE=false
MANUAL_ENVIRONMENT=""
CHECKED_BY="${SOLOPM_RELEASE_CHECKED_BY:-$(id -un 2>/dev/null || printf "release-owner")}"
NOTES=()

usage() {
  cat <<'USAGE'
Usage:
  create_release_evidence.sh [options]

Options:
  --force                         overwrite existing evidence file
  --clean-environment-launch      mark clean environment launch as manually checked
  --login-item-toggle             mark launch-at-login toggle as manually checked
  --manual-environment <text>     describe the manual check environment
  --checked-by <name>             reviewer name to record
  --note <text>                   append a review note; can be repeated
  -h, --help                      show this help

The script records metadata and artifact checksum evidence only. Pass manual
check flags only after testing the signed and notarized build.
USAGE
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --force)
      FORCE=1
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

if [[ -f "$OUTPUT_FILE" && "$FORCE" != "1" ]]; then
  echo "release evidence already exists: $OUTPUT_FILE" >&2
  echo "rerun with --force to overwrite it" >&2
  exit 2
fi

# shellcheck source=/dev/null
source "$METADATA_FILE"

APP_NAME="${APP_NAME:?APP_NAME is required}"
MARKETING_VERSION="${MARKETING_VERSION:?MARKETING_VERSION is required}"
CURRENT_PROJECT_VERSION="${CURRENT_PROJECT_VERSION:?CURRENT_PROJECT_VERSION is required}"
APP_BUNDLE_PATH="dist/$APP_NAME.app"
ARTIFACT_BASENAME="$APP_NAME-$MARKETING_VERSION+$CURRENT_PROJECT_VERSION"
CHECKED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf "%s" "$value"
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

if [[ "${#NOTES[@]}" -eq 0 ]]; then
  NOTES+=("Generated from packaging/app_metadata.env. Set manual check flags only after testing the signed and notarized build.")
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"
tmp_file="$OUTPUT_FILE.tmp"
artifact_sha="$(read_artifact_sha256)"
artifact_path="$(read_artifact_path)"

{
  printf '{\n'
  printf '  "release": {\n'
  printf '    "version": "%s",\n' "$(json_escape "$MARKETING_VERSION")"
  printf '    "buildNumber": "%s",\n' "$(json_escape "$CURRENT_PROJECT_VERSION")"
  printf '    "appBundlePath": "%s",\n' "$(json_escape "$APP_BUNDLE_PATH")"
  printf '    "artifactPath": "%s",\n' "$(json_escape "$artifact_path")"
  printf '    "artifactSha256": "%s"\n' "$(json_escape "$artifact_sha")"
  printf '  },\n'
  printf '  "manualChecks": {\n'
  printf '    "cleanEnvironmentLaunch": %s,\n' "$CLEAN_ENVIRONMENT_LAUNCH"
  printf '    "loginItemToggle": %s,\n' "$LOGIN_ITEM_TOGGLE"
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
