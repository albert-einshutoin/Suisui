#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METADATA_FILE="$ROOT_DIR/packaging/app_metadata.env"
SPARKLE_ENV_FILE="$ROOT_DIR/packaging/sparkle.env"
APPCAST_FILE="${1:-$ROOT_DIR/packaging/appcast.sample.xml}"
SAMPLE_APPCAST_FILE="$ROOT_DIR/packaging/appcast.sample.xml"
REQUIRE_RELEASE_APPCAST="${SOLOPM_REQUIRE_RELEASE_APPCAST:-0}"

if [[ -f "$SPARKLE_ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$SPARKLE_ENV_FILE"
fi

DOWNLOAD_URL_PREFIX="${SOLOPM_SPARKLE_DOWNLOAD_URL_PREFIX:-${SPARKLE_DOWNLOAD_URL_PREFIX:-}}"

artifact_path_for_compare() {
  local artifact_path="$1"
  if [[ "$artifact_path" == "$ROOT_DIR/"* ]]; then
    printf "%s" "${artifact_path#"$ROOT_DIR/"}"
  else
    printf "%s" "$artifact_path"
  fi
}

case "$REQUIRE_RELEASE_APPCAST" in
  0|1)
    ;;
  *)
    echo "SOLOPM_REQUIRE_RELEASE_APPCAST must be 0 or 1" >&2
    exit 2
    ;;
esac

if [[ ! -f "$METADATA_FILE" ]]; then
  echo "missing metadata file: $METADATA_FILE" >&2
  exit 2
fi

if [[ ! -f "$APPCAST_FILE" ]]; then
  echo "missing appcast file: $APPCAST_FILE" >&2
  exit 2
fi

# shellcheck source=/dev/null
source "$METADATA_FILE"

if ! xmllint --noout "$APPCAST_FILE"; then
  echo "appcast XML is invalid: $APPCAST_FILE" >&2
  exit 2
fi

if ! grep -F "sparkle:version=\"$CURRENT_PROJECT_VERSION\"" "$APPCAST_FILE" >/dev/null \
  && ! grep -F "<sparkle:version>$CURRENT_PROJECT_VERSION</sparkle:version>" "$APPCAST_FILE" >/dev/null; then
  echo "appcast missing current Sparkle build version: $CURRENT_PROJECT_VERSION" >&2
  exit 2
fi

if ! grep -F "sparkle:shortVersionString=\"$MARKETING_VERSION\"" "$APPCAST_FILE" >/dev/null \
  && ! grep -F "<sparkle:shortVersionString>$MARKETING_VERSION</sparkle:shortVersionString>" "$APPCAST_FILE" >/dev/null; then
  echo "appcast missing current Sparkle marketing version: $MARKETING_VERSION" >&2
  exit 2
fi

if ! grep -F "$APP_NAME-$MARKETING_VERSION+$CURRENT_PROJECT_VERSION.zip" "$APPCAST_FILE" >/dev/null; then
  echo "appcast missing current release artifact: $APP_NAME-$MARKETING_VERSION+$CURRENT_PROJECT_VERSION.zip" >&2
  exit 2
fi

if [[ "$REQUIRE_RELEASE_APPCAST" == "1" ]]; then
  enclosure_urls="$(grep -Eo 'url="[^"]+"' "$APPCAST_FILE" || true)"

  sample_path="$(cd "$(dirname "$SAMPLE_APPCAST_FILE")" && pwd)/$(basename "$SAMPLE_APPCAST_FILE")"
  appcast_path="$(cd "$(dirname "$APPCAST_FILE")" && pwd)/$(basename "$APPCAST_FILE")"
  if [[ "$appcast_path" == "$sample_path" ]]; then
    echo "release appcast must be generated from dist/releases, not packaging/appcast.sample.xml" >&2
    exit 2
  fi

  if grep -F "local-smoke-signature-placeholder" "$APPCAST_FILE" >/dev/null; then
    echo "release appcast still contains local smoke placeholder signature" >&2
    exit 2
  fi

  if grep -F "https://example.com/solopm/" "$APPCAST_FILE" >/dev/null; then
    echo "release appcast still contains example.com smoke URL" >&2
    exit 2
  fi

  if [[ -z "$enclosure_urls" ]] || ! grep -E '^url="https://[^"]+"$' <<<"$enclosure_urls" >/dev/null; then
    echo "release appcast enclosure URL must use https" >&2
    exit 2
  fi

  if grep -Ev '^url="https://[^"]+"$' <<<"$enclosure_urls" >/dev/null; then
    echo "release appcast enclosure URL must use https" >&2
    exit 2
  fi

  if grep -E 'url="https://([^"/]+\.)?(example\.com|example\.org|example\.net)(/|")|url="https://[^"/]+\.(invalid|test)(/|")|url="https://(localhost|127\.0\.0\.1|0\.0\.0\.0)(/|")' <<<"$enclosure_urls" >/dev/null; then
    echo "release appcast enclosure URL must not use placeholder or local domains" >&2
    exit 2
  fi

  if [[ -n "$DOWNLOAD_URL_PREFIX" ]]; then
    normalized_download_prefix="${DOWNLOAD_URL_PREFIX%/}/"
    while IFS= read -r enclosure_url; do
      enclosure_url="${enclosure_url#url=\"}"
      enclosure_url="${enclosure_url%\"}"
      case "$enclosure_url" in
        "$normalized_download_prefix"*)
          ;;
        *)
          echo "release appcast enclosure URL does not match configured SOLOPM_SPARKLE_DOWNLOAD_URL_PREFIX" >&2
          exit 2
          ;;
      esac
    done <<<"$enclosure_urls"
  fi

  if ! grep -E 'sparkle:edSignature="[^"]+"' "$APPCAST_FILE" >/dev/null; then
    echo "release appcast is missing Sparkle edSignature" >&2
    exit 2
  fi

  if grep -E 'length="0"' "$APPCAST_FILE" >/dev/null; then
    echo "release appcast has zero-length enclosure" >&2
    exit 2
  fi

  appcast_dir="$(cd "$(dirname "$APPCAST_FILE")" && pwd)"
  expected_zip_name="$APP_NAME-$MARKETING_VERSION+$CURRENT_PROJECT_VERSION.zip"
  expected_zip_path="$appcast_dir/$expected_zip_name"
  expected_zip_checksum="$expected_zip_path.sha256"
  expected_zip_package_evidence="$expected_zip_path.package-evidence.json"

  if [[ ! -f "$expected_zip_path" ]]; then
    echo "release appcast artifact is missing: $expected_zip_path" >&2
    exit 2
  fi

  if [[ ! -s "$expected_zip_path" ]]; then
    echo "release appcast artifact is empty: $expected_zip_path" >&2
    exit 2
  fi

  if [[ ! -f "$expected_zip_checksum" ]]; then
    echo "release appcast artifact checksum is missing: $expected_zip_checksum" >&2
    exit 2
  fi

  checksum_sha="$(awk 'NF { print $1; exit }' "$expected_zip_checksum")"
  checksum_artifact_path="$(awk 'NF >= 2 { print $2; exit }' "$expected_zip_checksum")"
  if [[ -z "$checksum_sha" || -z "$checksum_artifact_path" ]]; then
    echo "release appcast artifact checksum must include sha256 and artifact path: $expected_zip_checksum" >&2
    exit 2
  fi

  if [[ "$(artifact_path_for_compare "$checksum_artifact_path")" != "$(artifact_path_for_compare "$expected_zip_path")" ]]; then
    echo "release appcast artifact checksum path does not match appcast artifact: expected '$expected_zip_path', got '$checksum_artifact_path'" >&2
    exit 2
  fi

  actual_zip_sha="$(shasum -a 256 "$expected_zip_path" | awk 'NF { print $1; exit }')"
  if [[ "$actual_zip_sha" != "$checksum_sha" ]]; then
    echo "release appcast artifact SHA-256 does not match checksum file: expected '$checksum_sha', got '$actual_zip_sha'" >&2
    exit 2
  fi

  if [[ ! -f "$expected_zip_package_evidence" ]]; then
    echo "release appcast package evidence is missing: $expected_zip_package_evidence" >&2
    exit 2
  fi

  if ! plutil -convert json -o /dev/null "$expected_zip_package_evidence" 2>/dev/null; then
    echo "release appcast package evidence is not valid JSON or plist: $expected_zip_package_evidence" >&2
    exit 2
  fi

  manifest_artifact_path="$(plutil -extract "package.artifactPath" raw -o - "$expected_zip_package_evidence" 2>/dev/null || true)"
  signed_required="$(plutil -extract "package.signedPackageRequired" raw -o - "$expected_zip_package_evidence" 2>/dev/null || true)"
  notarized_required="$(plutil -extract "package.notarizedPackageRequired" raw -o - "$expected_zip_package_evidence" 2>/dev/null || true)"

  if [[ -z "$manifest_artifact_path" ]]; then
    echo "release appcast package evidence is missing artifact path" >&2
    exit 2
  fi

  if [[ "$(artifact_path_for_compare "$manifest_artifact_path")" != "$(artifact_path_for_compare "$expected_zip_path")" ]]; then
    echo "release appcast package evidence artifact path does not match appcast artifact: expected '$expected_zip_path', got '$manifest_artifact_path'" >&2
    exit 2
  fi

  if [[ "$signed_required" != "true" || "$notarized_required" != "true" ]]; then
    echo "release appcast package evidence requires signed and notarized gates enabled" >&2
    exit 2
  fi

  "$ROOT_DIR/script/verify_package_evidence_metrics.sh" \
    "$expected_zip_package_evidence" \
    "$expected_zip_path"
fi

echo "Appcast smoke passed: $APPCAST_FILE"
