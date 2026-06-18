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
fi

echo "Appcast smoke passed: $APPCAST_FILE"
