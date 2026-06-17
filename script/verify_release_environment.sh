#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METADATA_FILE="$ROOT_DIR/packaging/app_metadata.env"
SIGNING_ENV_FILE="$ROOT_DIR/packaging/signing.env"
NOTARIZATION_ENV_FILE="$ROOT_DIR/packaging/notarization.env"
RELEASE_EVIDENCE_FILE="${SOLOPM_RELEASE_EVIDENCE_FILE:-$ROOT_DIR/packaging/release-evidence.json}"

BLOCKERS=()
WARNINGS=()

add_blocker() {
  BLOCKERS+=("BLOCKER: $1")
}

add_warning() {
  WARNINGS+=("WARNING: $1")
}

require_file() {
  local path="$1"
  local label="$2"
  if [[ ! -f "$path" ]]; then
    add_blocker "missing $label: $path"
  fi
}

require_executable() {
  local path="$1"
  local label="$2"
  if [[ ! -x "$path" ]]; then
    add_blocker "$label is not executable: $path"
  fi
}

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    add_blocker "required command is unavailable: $command_name"
  fi
}

require_file "$METADATA_FILE" "app metadata"
require_file "$ROOT_DIR/packaging/SoloPM.entitlements" "entitlements"
require_file "$ROOT_DIR/packaging/signing.env.example" "signing env example"
require_file "$ROOT_DIR/packaging/notarization.env.example" "notarization env example"
require_executable "$ROOT_DIR/script/create_release_evidence.sh" "release evidence script"
require_executable "$ROOT_DIR/script/sign_app.sh" "signing script"
require_executable "$ROOT_DIR/script/notarize_app.sh" "notarization script"
require_executable "$ROOT_DIR/script/package_release.sh" "packaging script"
require_command codesign
require_command security
require_command spctl
require_command xcrun
require_command hdiutil
require_command ditto
require_command plutil

require_evidence_true() {
  local key_path="$1"
  local label="$2"
  local value

  if ! value="$(plutil -extract "$key_path" raw -o - "$RELEASE_EVIDENCE_FILE" 2>/dev/null)"; then
    add_blocker "release evidence missing $label: $key_path"
    return
  fi

  if [[ "$value" != "true" ]]; then
    add_blocker "release evidence not confirmed: $label ($key_path must be true)"
  fi
}

require_evidence_equals() {
  local key_path="$1"
  local label="$2"
  local expected="$3"
  local value

  if ! value="$(plutil -extract "$key_path" raw -o - "$RELEASE_EVIDENCE_FILE" 2>/dev/null)"; then
    add_blocker "release evidence missing $label: $key_path"
    return
  fi

  if [[ "$value" != "$expected" ]]; then
    add_blocker "release evidence $label does not match metadata: expected '$expected', got '$value'"
  fi
}

require_evidence_non_empty() {
  local key_path="$1"
  local label="$2"
  local value

  if ! value="$(plutil -extract "$key_path" raw -o - "$RELEASE_EVIDENCE_FILE" 2>/dev/null)"; then
    add_blocker "release evidence missing $label: $key_path"
    return
  fi

  if [[ -z "$value" ]]; then
    add_blocker "release evidence missing $label: $key_path must be non-empty"
  fi
}

release_artifact_checksum_file() {
  if [[ -n "$RELEASE_ARTIFACT_SHA256_FILE" ]]; then
    printf "%s" "$RELEASE_ARTIFACT_SHA256_FILE"
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

require_evidence_artifact_sha256() {
  local evidence_sha
  local evidence_path
  local checksum_file
  local package_sha
  local package_path

  if ! evidence_sha="$(plutil -extract "release.artifactSha256" raw -o - "$RELEASE_EVIDENCE_FILE" 2>/dev/null)"; then
    add_blocker "release evidence missing artifact SHA-256: release.artifactSha256"
    return
  fi

  if ! evidence_path="$(plutil -extract "release.artifactPath" raw -o - "$RELEASE_EVIDENCE_FILE" 2>/dev/null)"; then
    add_blocker "release evidence missing artifact path: release.artifactPath"
    return
  fi

  case "$evidence_sha" in
    ""|"replace-after-package"|"missing-release-artifact")
      add_blocker "release evidence artifact SHA-256 is not recorded from a packaged artifact"
      return
      ;;
  esac

  case "$evidence_path" in
    ""|"missing-release-artifact")
      add_blocker "release evidence artifact path is not recorded from a packaged artifact"
      return
      ;;
  esac

  checksum_file="$(release_artifact_checksum_file)"
  if [[ -z "$checksum_file" || ! -f "$checksum_file" ]]; then
    add_blocker "missing release artifact checksum file: run ./script/package_release.sh before final release validation"
    return
  fi

  package_sha="$(awk 'NF { print $1; exit }' "$checksum_file")"
  package_path="$(awk 'NF >= 2 { print $2; exit }' "$checksum_file")"
  if [[ -z "$package_sha" ]]; then
    add_blocker "release artifact checksum file is empty: $checksum_file"
    return
  fi

  if [[ "$evidence_sha" != "$package_sha" ]]; then
    add_blocker "release evidence artifact SHA-256 does not match package checksum: expected '$package_sha', got '$evidence_sha'"
  fi

  if [[ -n "$package_path" && "$evidence_path" != "$package_path" ]]; then
    add_blocker "release evidence artifact path does not match package checksum: expected '$package_path', got '$evidence_path'"
  fi
}

if [[ -f "$METADATA_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$METADATA_FILE"
fi

if [[ -f "$SIGNING_ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$SIGNING_ENV_FILE"
else
  add_blocker "missing local signing config: copy packaging/signing.env.example to packaging/signing.env on the release machine"
fi

if [[ -f "$NOTARIZATION_ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$NOTARIZATION_ENV_FILE"
else
  add_blocker "missing local notarization config: copy packaging/notarization.env.example to packaging/notarization.env on the release machine"
fi

APP_NAME="${APP_NAME:-SoloPM}"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
EXPECTED_APP_BUNDLE_PATH="dist/$APP_NAME.app"
ARTIFACT_BASENAME="$APP_NAME-${MARKETING_VERSION:-}+${CURRENT_PROJECT_VERSION:-}"
RELEASE_ARTIFACT_SHA256_FILE="${SOLOPM_RELEASE_ARTIFACT_SHA256_FILE:-}"
SIGNING_IDENTITY="${SOLOPM_SIGNING_IDENTITY:-}"
NOTARY_PROFILE="${SOLOPM_NOTARY_PROFILE:-}"
ONLINE_PREFLIGHT="${SOLOPM_RELEASE_PREFLIGHT_ONLINE:-0}"

case "$ONLINE_PREFLIGHT" in
  0|1)
    ;;
  *)
    add_blocker "SOLOPM_RELEASE_PREFLIGHT_ONLINE must be 0 or 1"
    ;;
esac

if [[ -z "$SIGNING_IDENTITY" ]]; then
  add_blocker "SOLOPM_SIGNING_IDENTITY is not set; Developer ID Application signing cannot run"
elif ! security find-identity -p codesigning -v | grep -F "$SIGNING_IDENTITY" >/dev/null; then
  add_blocker "configured Developer ID signing identity is unavailable: $SIGNING_IDENTITY"
fi

if [[ -z "$NOTARY_PROFILE" ]]; then
  add_blocker "SOLOPM_NOTARY_PROFILE is not set; notarization cannot run"
elif [[ "$ONLINE_PREFLIGHT" == "1" ]]; then
  if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null; then
    add_blocker "notarytool keychain profile could not be validated online: $NOTARY_PROFILE"
  fi
else
  add_warning "notary profile existence was not validated online; rerun with SOLOPM_RELEASE_PREFLIGHT_ONLINE=1 before release"
fi

if [[ -d "$APP_BUNDLE" ]]; then
  if ! codesign --verify --strict --deep --verbose=2 "$APP_BUNDLE" >/dev/null 2>&1; then
    add_blocker "dist app failed codesign verification: $APP_BUNDLE"
  fi

  if ! spctl -a -vv "$APP_BUNDLE" >/dev/null 2>&1; then
    add_blocker "dist app failed Gatekeeper assessment: $APP_BUNDLE"
  fi

  if ! xcrun stapler validate "$APP_BUNDLE" >/dev/null 2>&1; then
    add_blocker "dist app is not stapled or stapler validation failed: $APP_BUNDLE"
  fi
else
  add_blocker "missing signed release app bundle: run ./script/sign_app.sh before final release validation"
fi

if [[ -f "$RELEASE_EVIDENCE_FILE" ]]; then
  if plutil -convert json -o /dev/null "$RELEASE_EVIDENCE_FILE" 2>/dev/null; then
    require_evidence_equals "release.version" "version" "${MARKETING_VERSION:-}"
    require_evidence_equals "release.buildNumber" "build number" "${CURRENT_PROJECT_VERSION:-}"
    require_evidence_equals "release.appBundlePath" "app bundle path" "$EXPECTED_APP_BUNDLE_PATH"
    require_evidence_artifact_sha256
    require_evidence_true "manualChecks.cleanEnvironmentLaunch" "clean environment launch"
    require_evidence_true "manualChecks.loginItemToggle" "login item toggle in signed app"
    require_evidence_non_empty "manualChecks.environment" "manual check environment"
  else
    add_blocker "release evidence is not valid JSON or plist: $RELEASE_EVIDENCE_FILE"
  fi
else
  add_blocker "missing local release evidence: run ./script/create_release_evidence.sh after packaging and manual checks"
fi

printf "SoloPM release environment preflight\n"
printf "app bundle: %s\n" "$APP_BUNDLE"
printf "online notary check: %s\n" "$ONLINE_PREFLIGHT"
printf "release evidence: %s\n" "$RELEASE_EVIDENCE_FILE"

if [[ "${#WARNINGS[@]}" -gt 0 ]]; then
  printf "\nWarnings:\n"
  for warning in "${WARNINGS[@]}"; do
    printf "%s\n" "- $warning"
  done
fi

if [[ "${#BLOCKERS[@]}" -gt 0 ]]; then
  printf "\nBlockers:\n"
  for blocker in "${BLOCKERS[@]}"; do
    printf "%s\n" "- $blocker"
  done
  exit 2
fi

printf "\nREADY: release environment and manual gates are satisfied.\n"
