#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METADATA_FILE="$ROOT_DIR/packaging/app_metadata.env"
SIGNING_ENV_FILE="$ROOT_DIR/packaging/signing.env"
NOTARIZATION_ENV_FILE="$ROOT_DIR/packaging/notarization.env"
RELEASE_EVIDENCE_FILE="${SOLOPM_RELEASE_EVIDENCE_FILE:-$ROOT_DIR/packaging/release-evidence.json}"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

BLOCKERS=()
WARNINGS=()

add_blocker() {
  BLOCKERS+=("BLOCKER: $1")
}

add_warning() {
  WARNINGS+=("WARNING: $1")
}

artifact_path_for_compare() {
  local artifact_path="$1"
  if [[ "$artifact_path" == "$ROOT_DIR/"* ]]; then
    printf "%s" "${artifact_path#"$ROOT_DIR/"}"
  else
    printf "%s" "$artifact_path"
  fi
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

require_clean_source_tree() {
  local source_status

  if [[ ! -d "$ROOT_DIR/.git" ]]; then
    return
  fi

  if ! command -v git >/dev/null 2>&1; then
    add_blocker "required command is unavailable: git"
    return
  fi

  source_status="$(git -C "$ROOT_DIR" status --porcelain --untracked-files=no 2>/dev/null || true)"
  if [[ -n "$source_status" ]]; then
    add_blocker "source tree has uncommitted tracked changes; commit or revert before release"
  fi
}

require_developer_id_application_identity() {
  local signing_identity="$1"
  case "$signing_identity" in
    "Developer ID Application:"*)
      return 0
      ;;
    *)
      add_blocker "SOLOPM_SIGNING_IDENTITY must be a Developer ID Application identity: $signing_identity"
      return 1
      ;;
  esac
}

read_app_info_plist_key() {
  local app_bundle="$1"
  local key="$2"
  "$PLIST_BUDDY" -c "Print :$key" "$app_bundle/Contents/Info.plist" 2>/dev/null || true
}

require_app_bundle_metadata() {
  local app_bundle="$1"
  local expected_bundle_id="$2"
  local expected_version="$3"
  local expected_build="$4"
  local info_plist="$app_bundle/Contents/Info.plist"
  local actual_bundle_id
  local actual_version
  local actual_build

  if [[ ! -f "$info_plist" ]]; then
    add_blocker "missing release app Info.plist: $info_plist"
    return
  fi

  actual_bundle_id="$(read_app_info_plist_key "$app_bundle" "CFBundleIdentifier")"
  actual_version="$(read_app_info_plist_key "$app_bundle" "CFBundleShortVersionString")"
  actual_build="$(read_app_info_plist_key "$app_bundle" "CFBundleVersion")"

  if [[ "$actual_bundle_id" != "$expected_bundle_id" ]]; then
    add_blocker "release app bundle metadata mismatch: CFBundleIdentifier expected '$expected_bundle_id', got '$actual_bundle_id'"
  fi

  if [[ "$actual_version" != "$expected_version" ]]; then
    add_blocker "release app bundle metadata mismatch: CFBundleShortVersionString expected '$expected_version', got '$actual_version'"
  fi

  if [[ "$actual_build" != "$expected_build" ]]; then
    add_blocker "release app bundle metadata mismatch: CFBundleVersion expected '$expected_build', got '$actual_build'"
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
require_command "$PLIST_BUDDY"

require_clean_source_tree

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

require_release_package_evidence() {
  local checksum_file="$1"
  local package_path="$2"
  local manifest_path
  local manifest_artifact_path
  local signed_required
  local notarized_required

  manifest_path="${checksum_file%.sha256}.package-evidence.json"
  if [[ ! -f "$manifest_path" ]]; then
    add_blocker "missing release package evidence manifest: $manifest_path"
    return
  fi

  if ! plutil -convert json -o /dev/null "$manifest_path" 2>/dev/null; then
    add_blocker "release package evidence manifest is not valid JSON or plist: $manifest_path"
    return
  fi

  manifest_artifact_path="$(plutil -extract "package.artifactPath" raw -o - "$manifest_path" 2>/dev/null || true)"
  signed_required="$(plutil -extract "package.signedPackageRequired" raw -o - "$manifest_path" 2>/dev/null || true)"
  notarized_required="$(plutil -extract "package.notarizedPackageRequired" raw -o - "$manifest_path" 2>/dev/null || true)"

  if [[ -z "$manifest_artifact_path" ]]; then
    add_blocker "release package evidence manifest is missing artifact path"
  elif [[ "$(artifact_path_for_compare "$manifest_artifact_path")" != "$(artifact_path_for_compare "$package_path")" ]]; then
    add_blocker "release package evidence artifact path does not match checksum: expected '$package_path', got '$manifest_artifact_path'"
  fi

  if [[ "$signed_required" != "true" || "$notarized_required" != "true" ]]; then
    add_blocker "release package evidence requires signed and notarized gates enabled"
  fi
}

require_app_signature_identity() {
  local app_bundle="$1"
  local signing_identity="$2"
  local signature_details

  if [[ -z "$signing_identity" || ! -d "$app_bundle" ]]; then
    return
  fi

  case "$signing_identity" in
    "Developer ID Application:"*)
      ;;
    *)
      return
      ;;
  esac

  signature_details="$(codesign -dv --verbose=4 "$app_bundle" 2>&1 || true)"
  if ! grep -F "Authority=$signing_identity" <<<"$signature_details" >/dev/null; then
    add_blocker "release app signature does not include configured Developer ID identity: $signing_identity"
  fi

  if ! grep -E 'flags=.*runtime' <<<"$signature_details" >/dev/null; then
    add_blocker "release app signature is missing hardened runtime"
  fi
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

  require_release_package_evidence "$checksum_file" "$package_path"
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
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-}"
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
else
  if require_developer_id_application_identity "$SIGNING_IDENTITY" \
    && ! security find-identity -p codesigning -v | grep -F "$SIGNING_IDENTITY" >/dev/null; then
    add_blocker "configured Developer ID signing identity is unavailable: $SIGNING_IDENTITY"
  fi
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
  require_app_bundle_metadata "$APP_BUNDLE" "$BUNDLE_IDENTIFIER" "${MARKETING_VERSION:-}" "${CURRENT_PROJECT_VERSION:-}"

  if ! codesign --verify --strict --deep --verbose=2 "$APP_BUNDLE" >/dev/null 2>&1; then
    add_blocker "dist app failed codesign verification: $APP_BUNDLE"
  fi
  require_app_signature_identity "$APP_BUNDLE" "$SIGNING_IDENTITY"

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
