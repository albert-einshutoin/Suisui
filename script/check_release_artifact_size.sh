#!/usr/bin/env bash
set -euo pipefail

ARTIFACT_PATH="${1:-}"
ARTIFACT_FORMAT="${2:-}"
MAX_ZIP_BYTES="${SUISUI_MAX_ZIP_ARTIFACT_BYTES:-7864320}"
MAX_DMG_BYTES="${SUISUI_MAX_DMG_ARTIFACT_BYTES:-9437184}"

if [[ -z "$ARTIFACT_PATH" || ! -f "$ARTIFACT_PATH" ]]; then
  echo "missing release artifact: $ARTIFACT_PATH" >&2
  exit 2
fi

for variable_name in MAX_ZIP_BYTES MAX_DMG_BYTES; do
  value="${!variable_name}"
  if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then
    echo "$variable_name must be a positive integer" >&2
    exit 2
  fi
done

case "$ARTIFACT_FORMAT" in
  zip)
    max_bytes="$MAX_ZIP_BYTES"
    ;;
  dmg)
    max_bytes="$MAX_DMG_BYTES"
    ;;
  *)
    echo "artifact format must be zip or dmg: $ARTIFACT_FORMAT" >&2
    exit 2
    ;;
esac

artifact_bytes="$(stat -f '%z' "$ARTIFACT_PATH")"
if [[ "$artifact_bytes" -gt "$max_bytes" ]]; then
  printf 'BLOCKER: %s artifact exceeds production size budget: %s > %s bytes\n' \
    "$ARTIFACT_FORMAT" "$artifact_bytes" "$max_bytes" >&2
  exit 1
fi

printf 'OK: %s artifact size passed (%s bytes, budget: %s)\n' \
  "$ARTIFACT_FORMAT" "$artifact_bytes" "$max_bytes"
