#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METADATA_FILE="$ROOT_DIR/packaging/app_metadata.env"
APPCAST_FILE="${1:-$ROOT_DIR/packaging/appcast.sample.xml}"
SAMPLE_APPCAST_FILE="$ROOT_DIR/packaging/appcast.sample.xml"
REQUIRE_RELEASE_APPCAST="${SOLOPM_REQUIRE_RELEASE_APPCAST:-0}"

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

xmllint --noout "$APPCAST_FILE"
grep -F "sparkle:version=\"$CURRENT_PROJECT_VERSION\"" "$APPCAST_FILE" >/dev/null
grep -F "sparkle:shortVersionString=\"$MARKETING_VERSION\"" "$APPCAST_FILE" >/dev/null
grep -F "$APP_NAME-$MARKETING_VERSION+$CURRENT_PROJECT_VERSION.zip" "$APPCAST_FILE" >/dev/null

if [[ "$REQUIRE_RELEASE_APPCAST" == "1" ]]; then
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

  if ! grep -E 'url="https://[^"]+"' "$APPCAST_FILE" >/dev/null; then
    echo "release appcast enclosure URL must use https" >&2
    exit 2
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
