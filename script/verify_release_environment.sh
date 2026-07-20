#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METADATA_FILE="$ROOT_DIR/packaging/app_metadata.env"
SIGNING_ENV_FILE="$ROOT_DIR/packaging/signing.env"
NOTARIZATION_ENV_FILE="$ROOT_DIR/packaging/notarization.env"
SPARKLE_ENV_FILE="$ROOT_DIR/packaging/sparkle.env"
ENTITLEMENTS_FILE="$ROOT_DIR/packaging/Suisui.entitlements"
RELEASE_EVIDENCE_FILE="${SUISUI_RELEASE_EVIDENCE_FILE:-$ROOT_DIR/packaging/release-evidence.json}"
RELEASE_APPCAST_FILE="${SUISUI_RELEASE_APPCAST_FILE:-$ROOT_DIR/dist/releases/appcast.xml}"
PLIST_BUDDY="/usr/libexec/PlistBuddy"
MULTIPLE_RELEASE_ARTIFACT_CHECKSUMS="__multiple_release_artifact_checksums__"
RELEASE_EVIDENCE_GENERATOR="script/create_release_evidence.sh"

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

artifact_file_for_path() {
  local artifact_path="$1"
  if [[ "$artifact_path" == /* ]]; then
    printf "%s" "$artifact_path"
  else
    printf "%s/%s" "$ROOT_DIR" "$artifact_path"
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

  if ! command -v git >/dev/null 2>&1; then
    add_blocker "required command is unavailable: git"
    return
  fi

  if ! git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return
  fi

  source_status="$(git -C "$ROOT_DIR" status --porcelain --untracked-files=no 2>/dev/null || true)"
  if [[ -n "$source_status" ]]; then
    add_blocker "source tree has uncommitted tracked changes; commit or revert before release"
  fi
}

current_git_commit() {
  if command -v git >/dev/null 2>&1 && git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || true
  fi
}

validate_release_sparkle_config() {
  local validation_output

  if ! validation_output="$(SUISUI_BUILD_CONFIGURATION=release "$ROOT_DIR/script/validate_sparkle_release_config.sh" 2>&1)"; then
    add_blocker "release Sparkle config is invalid: $validation_output"
  fi
}

require_developer_id_application_identity() {
  local signing_identity="$1"
  case "$signing_identity" in
    "Developer ID Application:"*)
      return 0
      ;;
    *)
      add_blocker "SUISUI_SIGNING_IDENTITY must be a Developer ID Application identity: $signing_identity"
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

require_app_bundle_structure() {
  local app_bundle="$1"
  local executable_path="$app_bundle/Contents/MacOS/$APP_NAME"
  local resources_path="$app_bundle/Contents/Resources"
  local action_plan_schema_path="$resources_path/action-plan.schema.json"
  local sparkle_framework_path="$app_bundle/Contents/Frameworks/Sparkle.framework"
  local sparkle_binary_path="$sparkle_framework_path/Sparkle"
  local sparkle_updater_path="$sparkle_framework_path/Updater.app"

  if [[ ! -f "$executable_path" ]]; then
    add_blocker "release app bundle is missing executable: $executable_path"
  elif [[ ! -x "$executable_path" ]]; then
    add_blocker "release app bundle executable is not executable: $executable_path"
  fi

  if [[ ! -d "$resources_path" ]]; then
    add_blocker "release app bundle is missing resources directory: $resources_path"
  fi

  if [[ ! -f "$action_plan_schema_path" ]]; then
    add_blocker "release app bundle is missing action plan schema resource: $action_plan_schema_path"
  fi

  if [[ ! -d "$sparkle_framework_path" || ! -f "$sparkle_binary_path" ]]; then
    add_blocker "release app bundle is missing Sparkle framework: $sparkle_framework_path"
  fi

  if [[ ! -d "$sparkle_updater_path" ]]; then
    add_blocker "release app bundle is missing Sparkle updater app: $sparkle_updater_path"
  fi
}

require_release_bundle_preparation() {
  local app_bundle="$1"
  local preparation_marker="$app_bundle/Contents/Resources/release-preparation.env"
  local strip_mode
  local sparkle_prune_mode

  if [[ ! -f "$preparation_marker" ]]; then
    add_blocker "release app is missing pre-sign preparation marker: $preparation_marker"
    return
  fi

  strip_mode="$(awk -F= '$1 == "STRIP_MODE" { print $2; exit }' "$preparation_marker")"
  sparkle_prune_mode="$(awk -F= '$1 == "SPARKLE_PRUNE_MODE" { print $2; exit }' "$preparation_marker")"
  if [[ "$strip_mode" != "local-symbols-removed" ]]; then
    add_blocker "release app was not stripped before signing; rebuild with ./script/sign_app.sh"
  fi
  if [[ "$sparkle_prune_mode" != "development-assets-removed" ]]; then
    add_blocker "Sparkle development assets were not pruned before signing; rebuild with ./script/sign_app.sh"
  fi

  if ! "$ROOT_DIR/script/check_release_bundle_inventory.sh" "$app_bundle" >/dev/null 2>&1; then
    add_blocker "release bundle inventory failed; run ./script/check_release_bundle_inventory.sh '$app_bundle' for size or forbidden-content details"
  fi
}

require_release_sparkle_metadata() {
  local app_bundle="$1"
  local feed_url
  local public_ed_key

  feed_url="$(read_app_info_plist_key "$app_bundle" "SUFeedURL")"
  public_ed_key="$(read_app_info_plist_key "$app_bundle" "SUPublicEDKey")"

  if [[ -z "$feed_url" ]]; then
    add_blocker "release app is missing Sparkle feed URL: SUFeedURL"
  elif [[ -n "${SPARKLE_FEED_URL:-}" && "$feed_url" != "$SPARKLE_FEED_URL" ]]; then
    add_blocker "release app Sparkle feed URL does not match configured SUISUI_SPARKLE_FEED_URL: SUFeedURL"
  fi

  if [[ -z "$public_ed_key" ]]; then
    add_blocker "release app is missing Sparkle public EdDSA key: SUPublicEDKey"
  elif [[ -n "${SPARKLE_PUBLIC_ED_KEY:-}" && "$public_ed_key" != "$SPARKLE_PUBLIC_ED_KEY" ]]; then
    add_blocker "release app Sparkle public EdDSA key does not match configured SUISUI_SPARKLE_PUBLIC_ED_KEY: SUPublicEDKey"
  else
    case "$public_ed_key" in
      base64-public-key-from-generate_keys|"<public key from generate_keys>")
        add_blocker "release app Sparkle public EdDSA key must not use a placeholder key: SUPublicEDKey"
        ;;
    esac

    if ! [[ "$public_ed_key" =~ ^[A-Za-z0-9+/=]{32,}$ ]]; then
      add_blocker "release app Sparkle public EdDSA key must be a base64 public key: SUPublicEDKey"
    fi
  fi

  if [[ -z "$feed_url" ]]; then
    return
  fi

  case "$feed_url" in
    https://*)
      ;;
    *)
      add_blocker "release app Sparkle feed URL must use https: SUFeedURL"
      return
      ;;
  esac

  case "$feed_url" in
    https://example.com|https://example.com/*|\
    https://*.example.com|https://*.example.com/*|\
    https://example.org|https://example.org/*|\
    https://*.example.org|https://*.example.org/*|\
    https://example.net|https://example.net/*|\
    https://*.example.net|https://*.example.net/*|\
    https://*.invalid|https://*.invalid/*|\
    https://*.test|https://*.test/*|\
    https://localhost|https://localhost/*|\
    https://127.0.0.1|https://127.0.0.1/*|\
    https://0.0.0.0|https://0.0.0.0/*)
      add_blocker "release app Sparkle feed URL must not use placeholder or local domains: SUFeedURL"
      ;;
  esac
}

normalized_entitlements_json() {
  local entitlements_path="$1"
  plutil -convert json -o - "$entitlements_path" 2>/dev/null
}

signed_entitlements_json() {
  local app_bundle="$1"
  local signed_entitlements

  signed_entitlements="$(codesign -d --entitlements :- "$app_bundle" 2>/dev/null || true)"
  if [[ -z "$signed_entitlements" ]]; then
    printf "{}"
    return
  fi

  printf "%s" "$signed_entitlements" | plutil -convert json -o - - 2>/dev/null
}

require_app_entitlements() {
  local app_bundle="$1"
  local expected_entitlements
  local actual_entitlements

  if [[ ! -f "$ENTITLEMENTS_FILE" ]]; then
    return
  fi

  expected_entitlements="$(normalized_entitlements_json "$ENTITLEMENTS_FILE" || true)"
  actual_entitlements="$(signed_entitlements_json "$app_bundle" || true)"

  if [[ -z "$expected_entitlements" ]]; then
    add_blocker "packaging/Suisui.entitlements is not valid plist"
    return
  fi

  if [[ -z "$actual_entitlements" ]]; then
    add_blocker "release app entitlements could not be read: $app_bundle"
    return
  fi

  if [[ "$actual_entitlements" != "$expected_entitlements" ]]; then
    add_blocker "release app entitlements do not match packaging/Suisui.entitlements"
  fi
}

require_file "$METADATA_FILE" "app metadata"
require_file "$ENTITLEMENTS_FILE" "entitlements"
require_file "$ROOT_DIR/packaging/signing.env.example" "signing env example"
require_file "$ROOT_DIR/packaging/notarization.env.example" "notarization env example"
require_executable "$ROOT_DIR/script/create_release_evidence.sh" "release evidence script"
require_executable "$ROOT_DIR/script/sign_app.sh" "signing script"
require_executable "$ROOT_DIR/script/notarize_app.sh" "notarization script"
require_executable "$ROOT_DIR/script/notarize_release_dmg.sh" "release DMG notarization script"
require_executable "$ROOT_DIR/script/package_release.sh" "packaging script"
require_executable "$ROOT_DIR/script/check_release_bundle_inventory.sh" "release bundle inventory script"
require_executable "$ROOT_DIR/script/check_release_artifact_size.sh" "release artifact size script"
require_executable "$ROOT_DIR/script/verify_package_evidence_metrics.sh" "package evidence metrics verifier"
require_executable "$ROOT_DIR/script/verify_appcast.sh" "appcast verification script"
require_executable "$ROOT_DIR/script/verify_dmg_notarization_evidence.sh" "DMG notarization evidence verifier"
require_executable "$ROOT_DIR/script/validate_sparkle_release_config.sh" "Sparkle release config validator"
require_command codesign
require_command security
require_command spctl
require_command xcrun
require_command hdiutil
require_command ditto
require_command shasum
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

release_evidence_review_notes_text() {
  local value
  local index=0

  while value="$(plutil -extract "review.notes.$index" raw -o - "$RELEASE_EVIDENCE_FILE" 2>/dev/null)"; do
    printf '%s\n' "$value"
    index=$((index + 1))
  done
}

require_evidence_note_proof_if_checked() {
  local key_path="$1"
  local label="$2"
  local pattern="$3"
  local value

  if ! value="$(plutil -extract "$key_path" raw -o - "$RELEASE_EVIDENCE_FILE" 2>/dev/null)"; then
    return
  fi

  if [[ "$value" != "true" ]]; then
    return
  fi

  if ! release_evidence_review_notes_text | grep -Eiq "$pattern"; then
    add_blocker "release evidence review notes missing proof for $label: $key_path"
  fi
}

require_evidence_manual_note_proofs() {
  require_evidence_note_proof_if_checked \
    "manualChecks.releaseMachineLaunch" \
    "release machine launch" \
    'release[ -]?machine.*launch|launch.*release[ -]?machine|dist/suisui\.app'
  require_evidence_note_proof_if_checked \
    "manualChecks.checksumVerification" \
    "checksum verification" \
    'checksum|sha-?256|shasum'
  require_evidence_note_proof_if_checked \
    "manualChecks.cleanDmgInstall" \
    "clean DMG install" \
    'clean.*dmg|dmg.*clean'
  require_evidence_note_proof_if_checked \
    "manualChecks.applicationsFolderInstall" \
    "Applications folder install" \
    'applications|/applications'
  require_evidence_note_proof_if_checked \
    "manualChecks.gatekeeperAccepted" \
    "Gatekeeper acceptance" \
    'gatekeeper|spctl'
  require_evidence_note_proof_if_checked \
    "manualChecks.cleanEnvironmentLaunch" \
    "clean environment launch" \
    'clean.*environment.*launch|clean.*user.*launch|clean.*vm.*launch|first.*launch'
  require_evidence_note_proof_if_checked \
    "manualChecks.loginItemToggle" \
    "login item toggle" \
    'login[ -]?item|launch[ -]?at[ -]?login'
  require_evidence_note_proof_if_checked \
    "manualChecks.sparkleAppcastMetadata" \
    "Sparkle appcast metadata" \
    'sparkle.*appcast|appcast.*sparkle'
}

require_evidence_concrete_manual_environment() {
  local value

  if ! value="$(plutil -extract "manualChecks.environment" raw -o - "$RELEASE_EVIDENCE_FILE" 2>/dev/null)"; then
    add_blocker "release evidence missing manual check environment: manualChecks.environment"
    return
  fi

  if is_placeholder_manual_environment "$value"; then
    add_blocker "release evidence manual check environment is not concrete: manualChecks.environment"
  fi
}

require_evidence_concrete_reviewer() {
  local value

  if ! value="$(plutil -extract "review.checkedBy" raw -o - "$RELEASE_EVIDENCE_FILE" 2>/dev/null)"; then
    add_blocker "release evidence missing reviewer: review.checkedBy"
    return
  fi

  value="$(trim_text "$value")"
  if [[ -z "$value" ]]; then
    add_blocker "release evidence missing reviewer: review.checkedBy must be non-empty"
  elif is_placeholder_checked_by "$value"; then
    add_blocker "release evidence reviewer is not concrete: review.checkedBy"
  fi
}

require_evidence_review_notes() {
  local value
  local index=0
  local has_note=0
  local has_concrete_note=0

  while value="$(plutil -extract "review.notes.$index" raw -o - "$RELEASE_EVIDENCE_FILE" 2>/dev/null)"; do
    has_note=1
    value="$(trim_text "$value")"
    if [[ -n "$value" ]]; then
      if ! is_boilerplate_review_note "$value"; then
        has_concrete_note=1
        break
      fi
    fi
    index=$((index + 1))
  done

  if [[ "$has_note" != "1" ]]; then
    add_blocker "release evidence missing review notes: review.notes must include at least one explicit note"
  elif [[ "$has_concrete_note" != "1" ]]; then
    add_blocker "release evidence review notes must include concrete verification details"
  fi
}

require_evidence_current_git_commit() {
  local value

  if [[ -z "$CURRENT_GIT_COMMIT" ]]; then
    add_blocker "release evidence cannot be tied to a git commit from the current checkout"
    return
  fi

  if ! value="$(plutil -extract "source.gitCommit" raw -o - "$RELEASE_EVIDENCE_FILE" 2>/dev/null)"; then
    add_blocker "release evidence missing source git commit: source.gitCommit"
    return
  fi

  if [[ "$value" != "$CURRENT_GIT_COMMIT" ]]; then
    add_blocker "release evidence source commit does not match current git commit: expected '$CURRENT_GIT_COMMIT', got '$value'"
  fi
}

require_release_evidence_generator() {
  local value

  if ! value="$(plutil -extract "generator.name" raw -o - "$RELEASE_EVIDENCE_FILE" 2>/dev/null)"; then
    add_blocker "release evidence missing generator provenance: generator.name"
    return
  fi

  if [[ "$value" != "$RELEASE_EVIDENCE_GENERATOR" ]]; then
    add_blocker "release evidence generator provenance is not canonical: expected '$RELEASE_EVIDENCE_GENERATOR', got '$value'"
  fi
}

release_artifact_checksum_file() {
  local checksum_files
  local checksum_count

  if [[ -n "$RELEASE_ARTIFACT_SHA256_FILE" ]]; then
    printf "%s" "$RELEASE_ARTIFACT_SHA256_FILE"
    return
  fi

  checksum_files="$(find "$ROOT_DIR/dist/releases" \
    -maxdepth 1 \
    -type f \
    -name "$ARTIFACT_BASENAME.*.sha256" \
    2>/dev/null \
    | sort || true)"
  checksum_count="$(printf "%s\n" "$checksum_files" | sed '/^$/d' | wc -l | tr -d ' ')"

  if [[ "$checksum_count" -gt 1 ]]; then
    printf "%s" "$MULTIPLE_RELEASE_ARTIFACT_CHECKSUMS"
    return
  fi

  printf "%s" "$checksum_files"
}

require_release_package_evidence() {
  local checksum_file="$1"
  local package_path="$2"
  local manifest_path
  local manifest_artifact_path
  local signed_required
  local notarized_required
  local manifest_git_commit
  local metrics_output

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
  manifest_git_commit="$(plutil -extract "source.gitCommit" raw -o - "$manifest_path" 2>/dev/null || true)"

  if [[ -z "$manifest_artifact_path" ]]; then
    add_blocker "release package evidence manifest is missing artifact path"
  elif [[ "$(artifact_path_for_compare "$manifest_artifact_path")" != "$(artifact_path_for_compare "$package_path")" ]]; then
    add_blocker "release package evidence artifact path does not match checksum: expected '$package_path', got '$manifest_artifact_path'"
  fi

  if [[ "$signed_required" != "true" || "$notarized_required" != "true" ]]; then
    add_blocker "release package evidence requires signed and notarized gates enabled"
  fi

  if [[ -z "$manifest_git_commit" ]]; then
    add_blocker "release package evidence manifest is missing source git commit"
  elif [[ -n "$CURRENT_GIT_COMMIT" && "$manifest_git_commit" != "$CURRENT_GIT_COMMIT" ]]; then
    add_blocker "release package evidence source commit does not match current git commit: expected '$CURRENT_GIT_COMMIT', got '$manifest_git_commit'"
  fi

  metrics_output=""
  if ! metrics_output="$("$ROOT_DIR/script/verify_package_evidence_metrics.sh" \
    "$manifest_path" \
    "$(artifact_file_for_path "$package_path")" \
    "$APP_BUNDLE" 2>&1)"; then
    add_blocker "release package evidence metrics failed: $metrics_output"
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

require_release_dmg_notarization() {
  local package_file="$1"

  case "$package_file" in
    *.dmg)
      ;;
    *)
      return
      ;;
  esac

  if ! xcrun stapler validate "$package_file" >/dev/null 2>&1; then
    add_blocker "release DMG is not stapled or stapler validation failed: $package_file"
  fi

  # Gatekeeper must assess the downloaded container, not only the nested app.
  if ! spctl -a -t open --context context:primary-signature -vv "$package_file" >/dev/null 2>&1; then
    add_blocker "release DMG failed Gatekeeper assessment: $package_file"
  fi

  notarization_evidence_output=""
  if ! notarization_evidence_output="$("$ROOT_DIR/script/verify_dmg_notarization_evidence.sh" "$package_file" 2>&1)"; then
    add_blocker "release DMG structured notarization evidence failed: $notarization_evidence_output"
  fi
}

require_evidence_artifact_sha256() {
  local evidence_sha
  local evidence_path
  local checksum_file
  local package_sha
  local package_path
  local package_file
  local actual_package_sha

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
  if [[ "$checksum_file" == "$MULTIPLE_RELEASE_ARTIFACT_CHECKSUMS" ]]; then
    add_blocker "multiple release artifact checksum files found; set SUISUI_RELEASE_ARTIFACT_SHA256_FILE to the exact package checksum"
    return
  fi

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
  if [[ -z "$package_path" ]]; then
    add_blocker "release artifact checksum file is missing artifact path: $checksum_file"
    return
  fi

  package_file="$(artifact_file_for_path "$package_path")"
  if [[ ! -f "$package_file" ]]; then
    add_blocker "missing release artifact file: $package_path"
  elif command -v shasum >/dev/null 2>&1; then
    actual_package_sha="$(shasum -a 256 "$package_file" | awk 'NF { print $1; exit }')"
    if [[ "$actual_package_sha" != "$package_sha" ]]; then
      add_blocker "release artifact SHA-256 does not match checksum file: expected '$package_sha', got '$actual_package_sha'"
    fi
  fi

  if [[ -f "$package_file" ]]; then
    require_release_dmg_notarization "$package_file"
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

if [[ -f "$SPARKLE_ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$SPARKLE_ENV_FILE"
fi

APP_NAME="${APP_NAME:-Suisui}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-}"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
EXPECTED_APP_BUNDLE_PATH="dist/$APP_NAME.app"
ARTIFACT_BASENAME="$APP_NAME-${MARKETING_VERSION:-}+${CURRENT_PROJECT_VERSION:-}"
RELEASE_ARTIFACT_SHA256_FILE="${SUISUI_RELEASE_ARTIFACT_SHA256_FILE:-}"
SIGNING_IDENTITY="${SUISUI_SIGNING_IDENTITY:-}"
NOTARY_PROFILE="${SUISUI_NOTARY_PROFILE:-}"
SPARKLE_FEED_URL="${SUISUI_SPARKLE_FEED_URL:-${SPARKLE_FEED_URL:-}}"
SPARKLE_PUBLIC_ED_KEY="${SUISUI_SPARKLE_PUBLIC_ED_KEY:-${SPARKLE_PUBLIC_ED_KEY:-}}"
ONLINE_PREFLIGHT="${SUISUI_RELEASE_PREFLIGHT_ONLINE:-0}"
CURRENT_GIT_COMMIT="$(current_git_commit)"

validate_release_sparkle_config

case "$ONLINE_PREFLIGHT" in
  0|1)
    ;;
  *)
    add_blocker "SUISUI_RELEASE_PREFLIGHT_ONLINE must be 0 or 1"
    ;;
esac

if [[ -z "$SIGNING_IDENTITY" ]]; then
  add_blocker "SUISUI_SIGNING_IDENTITY is not set; Developer ID Application signing cannot run"
else
  if require_developer_id_application_identity "$SIGNING_IDENTITY" \
    && ! security find-identity -p codesigning -v | grep -F "$SIGNING_IDENTITY" >/dev/null; then
    add_blocker "configured Developer ID signing identity is unavailable: $SIGNING_IDENTITY"
  fi
fi

if [[ -z "$NOTARY_PROFILE" ]]; then
  add_blocker "SUISUI_NOTARY_PROFILE is not set; notarization cannot run"
elif [[ "$ONLINE_PREFLIGHT" == "1" ]]; then
  if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null; then
    add_blocker "notarytool keychain profile could not be validated online: $NOTARY_PROFILE"
  fi
else
  add_warning "notary profile existence was not validated online; rerun with SUISUI_RELEASE_PREFLIGHT_ONLINE=1 before release"
fi

if [[ -d "$APP_BUNDLE" ]]; then
  require_app_bundle_structure "$APP_BUNDLE"
  require_release_bundle_preparation "$APP_BUNDLE"
  require_app_bundle_metadata "$APP_BUNDLE" "$BUNDLE_IDENTIFIER" "${MARKETING_VERSION:-}" "${CURRENT_PROJECT_VERSION:-}"
  require_release_sparkle_metadata "$APP_BUNDLE"
  require_app_entitlements "$APP_BUNDLE"

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
    require_evidence_current_git_commit
    require_release_evidence_generator
    require_evidence_non_empty "release.signingIdentity" "signing identity"
    require_evidence_non_empty "release.notaryProfile" "notary profile"
    require_evidence_non_empty "release.sparkleFeedURL" "Sparkle feed URL"
    require_evidence_non_empty "release.appcastPath" "appcast path"
    if [[ -n "$SIGNING_IDENTITY" ]]; then
      require_evidence_equals "release.signingIdentity" "signing identity" "$SIGNING_IDENTITY"
    fi
    if [[ -n "$NOTARY_PROFILE" ]]; then
      require_evidence_equals "release.notaryProfile" "notary profile" "$NOTARY_PROFILE"
    fi
    if [[ -n "$SPARKLE_FEED_URL" ]]; then
      require_evidence_equals "release.sparkleFeedURL" "Sparkle feed URL" "$SPARKLE_FEED_URL"
    fi
    require_evidence_equals "release.appcastPath" "appcast path" "$(artifact_path_for_compare "$RELEASE_APPCAST_FILE")"
    require_evidence_artifact_sha256
    require_evidence_true "manualChecks.releaseMachineLaunch" "signed and notarized app launch on release machine"
    require_evidence_true "manualChecks.checksumVerification" "release artifact checksum verification"
    require_evidence_true "manualChecks.cleanDmgInstall" "clean environment DMG install"
    require_evidence_true "manualChecks.applicationsFolderInstall" "Applications folder install"
    require_evidence_true "manualChecks.gatekeeperAccepted" "Gatekeeper acceptance"
    require_evidence_true "manualChecks.cleanEnvironmentLaunch" "clean environment launch"
    require_evidence_true "manualChecks.loginItemToggle" "login item toggle in signed app"
    require_evidence_true "manualChecks.sparkleAppcastMetadata" "Sparkle appcast metadata check"
    require_evidence_concrete_manual_environment
    require_evidence_concrete_reviewer
    require_evidence_non_empty "review.checkedAt" "review timestamp"
    require_evidence_review_notes
    require_evidence_manual_note_proofs
  else
    add_blocker "release evidence is not valid JSON or plist: $RELEASE_EVIDENCE_FILE"
  fi
else
  add_blocker "missing local release evidence: run ./script/create_release_evidence.sh after packaging and manual checks"
fi

if [[ -f "$RELEASE_APPCAST_FILE" ]]; then
  appcast_validation_output=""
  if ! appcast_validation_output="$(SUISUI_REQUIRE_RELEASE_APPCAST=1 SUISUI_VERIFY_REMOTE_SPARKLE="$ONLINE_PREFLIGHT" "$ROOT_DIR/script/verify_appcast.sh" "$RELEASE_APPCAST_FILE" 2>&1)"; then
    add_blocker "release appcast verification failed: $RELEASE_APPCAST_FILE: $appcast_validation_output"
  fi
else
  add_blocker "missing release appcast: run ./script/generate_appcast.sh before final release validation"
fi

printf "Suisui release environment preflight\n"
printf "app bundle: %s\n" "$APP_BUNDLE"
printf "online notary check: %s\n" "$ONLINE_PREFLIGHT"
printf "release evidence: %s\n" "$RELEASE_EVIDENCE_FILE"
printf "release appcast: %s\n" "$RELEASE_APPCAST_FILE"

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
