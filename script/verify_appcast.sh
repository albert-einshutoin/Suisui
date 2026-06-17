#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METADATA_FILE="$ROOT_DIR/packaging/app_metadata.env"
APPCAST_FILE="${1:-$ROOT_DIR/packaging/appcast.sample.xml}"

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

echo "Appcast smoke passed: $APPCAST_FILE"
