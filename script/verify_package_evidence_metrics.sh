#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METADATA_FILE="$ROOT_DIR/packaging/app_metadata.env"
MANIFEST_PATH="${1:-}"
ARTIFACT_PATH="${2:-}"
APP_BUNDLE="${3:-}"

if [[ ! -f "$METADATA_FILE" ]]; then
  echo "missing metadata file: $METADATA_FILE" >&2
  exit 2
fi
# shellcheck source=/dev/null
source "$METADATA_FILE"

if [[ ! -f "$MANIFEST_PATH" ]]; then
  echo "missing package evidence manifest: $MANIFEST_PATH" >&2
  exit 2
fi
if [[ ! -f "$ARTIFACT_PATH" ]]; then
  echo "missing release artifact file: $ARTIFACT_PATH" >&2
  exit 2
fi
if ! plutil -convert json -o /dev/null "$MANIFEST_PATH" 2>/dev/null; then
  echo "package evidence manifest is not valid JSON or plist: $MANIFEST_PATH" >&2
  exit 2
fi

manifest_value() {
  plutil -extract "$1" raw -o - "$MANIFEST_PATH" 2>/dev/null || true
}

app_bundle_bytes="$(manifest_value package.appBundleBytes)"
app_binary_bytes="$(manifest_value package.appBinaryBytes)"
artifact_bytes="$(manifest_value package.artifactBytes)"
strip_mode="$(manifest_value package.stripMode)"
sparkle_prune_mode="$(manifest_value package.sparklePruneMode)"

for field_name in appBundleBytes appBinaryBytes artifactBytes; do
  case "$field_name" in
    appBundleBytes) value="$app_bundle_bytes" ;;
    appBinaryBytes) value="$app_binary_bytes" ;;
    artifactBytes) value="$artifact_bytes" ;;
  esac
  if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then
    echo "package evidence package.$field_name must be a positive integer" >&2
    exit 2
  fi
done

if [[ "$strip_mode" != "local-symbols-removed" ]]; then
  echo "package evidence package.stripMode must be local-symbols-removed" >&2
  exit 2
fi
if [[ "$sparkle_prune_mode" != "development-assets-removed" ]]; then
  echo "package evidence package.sparklePruneMode must be development-assets-removed" >&2
  exit 2
fi

actual_artifact_bytes="$(stat -f '%z' "$ARTIFACT_PATH")"
if [[ "$artifact_bytes" != "$actual_artifact_bytes" ]]; then
  echo "package evidence package.artifactBytes does not match artifact: expected $actual_artifact_bytes, got $artifact_bytes" >&2
  exit 2
fi

if [[ -n "$APP_BUNDLE" ]]; then
  if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "missing app bundle for package evidence verification: $APP_BUNDLE" >&2
    exit 2
  fi
  app_binary="$APP_BUNDLE/Contents/MacOS/${APP_NAME:?APP_NAME is required}"
  if [[ ! -f "$app_binary" ]]; then
    echo "missing app binary for package evidence verification: $app_binary" >&2
    exit 2
  fi

  actual_app_bundle_bytes="$(find "$APP_BUNDLE" -type f -exec stat -f '%z' {} + | awk '{ total += $1 } END { printf "%.0f", total }')"
  actual_app_binary_bytes="$(stat -f '%z' "$app_binary")"
  if [[ "$app_bundle_bytes" != "$actual_app_bundle_bytes" ]]; then
    echo "package evidence package.appBundleBytes does not match app bundle: expected $actual_app_bundle_bytes, got $app_bundle_bytes" >&2
    exit 2
  fi
  if [[ "$app_binary_bytes" != "$actual_app_binary_bytes" ]]; then
    echo "package evidence package.appBinaryBytes does not match app binary: expected $actual_app_binary_bytes, got $app_binary_bytes" >&2
    exit 2
  fi
fi

echo "OK: package evidence sizes and preparation modes match release artifacts."
