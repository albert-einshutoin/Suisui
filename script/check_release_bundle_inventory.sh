#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METADATA_FILE="$ROOT_DIR/packaging/app_metadata.env"

if [[ ! -f "$METADATA_FILE" ]]; then
  echo "missing metadata file: $METADATA_FILE" >&2
  exit 2
fi

# shellcheck source=/dev/null
source "$METADATA_FILE"

APP_NAME="${APP_NAME:?APP_NAME is required}"
APP_BUNDLE="${1:-$ROOT_DIR/dist/$APP_NAME.app}"
TOP_COUNT="${SUISUI_PACKAGE_INVENTORY_TOP_COUNT:-15}"
MAX_APP_BUNDLE_BYTES="${SUISUI_MAX_APP_BUNDLE_BYTES:-52428800}"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "missing app bundle: $APP_BUNDLE" >&2
  exit 2
fi
if [[ ! "$TOP_COUNT" =~ ^[1-9][0-9]*$ ]]; then
  echo "SUISUI_PACKAGE_INVENTORY_TOP_COUNT must be a positive integer" >&2
  exit 2
fi
if [[ ! "$MAX_APP_BUNDLE_BYTES" =~ ^[1-9][0-9]*$ ]]; then
  echo "SUISUI_MAX_APP_BUNDLE_BYTES must be a positive integer" >&2
  exit 2
fi

inventory_file="$(mktemp "${TMPDIR:-/tmp}/suisui-release-inventory.XXXXXX")"
trap 'rm -f "$inventory_file"' EXIT INT TERM

while IFS= read -r -d '' bundled_file; do
  relative_path="${bundled_file#"$APP_BUNDLE/"}"
  file_bytes="$(stat -f '%z' "$bundled_file")"
  printf '%s\t%s\n' "$file_bytes" "$relative_path" >>"$inventory_file"
done < <(find "$APP_BUNDLE" -type f -print0)

app_bundle_bytes="$(awk -F '\t' '{ total += $1 } END { printf "%.0f", total }' "$inventory_file")"
printf 'App bundle bytes: %s (budget: %s)\n' "$app_bundle_bytes" "$MAX_APP_BUNDLE_BYTES"
printf 'Largest bundled files (top %s):\n' "$TOP_COUNT"
# awk intentionally consumes the complete sort stream. Exiting after TOP_COUNT
# would close the pipe early and make sort fail with SIGPIPE under pipefail.
sort -nr -k1,1 "$inventory_file" \
  | awk -F '\t' -v limit="$TOP_COUNT" 'NR <= limit { printf "  %s bytes\t%s\n", $1, $2 }'

failed=0
while IFS=$'\t' read -r _ relative_path; do
  lower_path="$(printf '%s' "$relative_path" | tr '[:upper:]' '[:lower:]')"
  case "$lower_path" in
    *.gguf|*.ggml|*.onnx|*.safetensors|*.pt|*.pth|*.tflite|*.mlmodel|*.mlpackage/*|*ggml*.bin|*whisper*.bin|*model*.bin|models/*.bin|*/models/*.bin|voice-models/*.bin|*/voice-models/*.bin|voice_models/*.bin|*/voice_models/*.bin)
      printf 'BLOCKER: bundled voice model binary is not allowed: %s\n' "$relative_path" >&2
      failed=1
      ;;
    .ds_store|*/.ds_store|._*|*/._*|*.dsym/*)
      printf 'BLOCKER: bundled packaging debris is not allowed: %s\n' "$relative_path" >&2
      failed=1
      ;;
  esac
done <"$inventory_file"

if [[ "$app_bundle_bytes" -gt "$MAX_APP_BUNDLE_BYTES" ]]; then
  printf 'BLOCKER: app bundle exceeds production size budget: %s > %s bytes\n' \
    "$app_bundle_bytes" "$MAX_APP_BUNDLE_BYTES" >&2
  failed=1
fi

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi

printf 'OK: release bundle inventory passed (%s bytes, no bundled voice models)\n' "$app_bundle_bytes"
