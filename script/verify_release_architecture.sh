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

APP_NAME="${APP_NAME:-Suisui}"
APP_BUNDLE="${1:-$ROOT_DIR/dist/$APP_NAME.app}"
MAIN_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
SUPPORTED_ARCHITECTURES="${SUPPORTED_ARCHITECTURES:-}"

if [[ -z "${SUPPORTED_ARCHITECTURES//[[:space:]]/}" ]]; then
  echo "SUPPORTED_ARCHITECTURES is required in packaging/app_metadata.env" >&2
  exit 2
fi

if [[ ! -f "$MAIN_BINARY" ]]; then
  echo "release app main binary is missing: $MAIN_BINARY" >&2
  exit 2
fi

if ! command -v lipo >/dev/null 2>&1; then
  echo "required command is unavailable: lipo" >&2
  exit 2
fi

normalize_architectures() {
  tr ' ' '\n' | sed '/^$/d' | LC_ALL=C sort -u | paste -sd ' ' -
}

expected_architectures="$(printf '%s\n' "$SUPPORTED_ARCHITECTURES" | normalize_architectures)"
actual_architectures="$(lipo -archs "$MAIN_BINARY" | normalize_architectures)"

# The first public release deliberately supports Apple Silicon only. Exact
# equality prevents a host-specific build or an accidental unsupported slice
# from silently changing the published compatibility contract.
if [[ "$actual_architectures" != "$expected_architectures" ]]; then
  echo "release app architecture mismatch: expected '$expected_architectures', got '$actual_architectures'" >&2
  exit 2
fi

printf "OK: release app architecture matches supported policy (%s)\n" "$actual_architectures"
