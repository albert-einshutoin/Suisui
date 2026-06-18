#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOTARIZATION_ENV_FILE="$ROOT_DIR/packaging/notarization.env"
NOTARIZATION_EXAMPLE_FILE="$ROOT_DIR/packaging/notarization.env.example"
NOTARIZATION_DOCS="$ROOT_DIR/docs/release/notarization.md"
NOTARIZE_SCRIPT="$ROOT_DIR/script/notarize_app.sh"
ONLINE_PREFLIGHT="${SOLOPM_RELEASE_PREFLIGHT_ONLINE:-0}"

require_file() {
  local path="$1"
  local label="$2"
  if [[ ! -f "$path" ]]; then
    echo "missing $label: $path" >&2
    exit 2
  fi
}

require_executable() {
  local path="$1"
  local label="$2"
  if [[ ! -x "$path" ]]; then
    echo "$label is not executable: $path" >&2
    exit 2
  fi
}

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "required command is unavailable: $command_name" >&2
    exit 2
  fi
}

case "$ONLINE_PREFLIGHT" in
  0|1)
    ;;
  *)
    echo "SOLOPM_RELEASE_PREFLIGHT_ONLINE must be 0 or 1" >&2
    exit 2
    ;;
esac

require_file "$NOTARIZATION_EXAMPLE_FILE" "notarization environment example"
require_file "$NOTARIZATION_DOCS" "notarization release docs"
require_executable "$NOTARIZE_SCRIPT" "notarization script"
require_command xcrun

if [[ -f "$NOTARIZATION_ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$NOTARIZATION_ENV_FILE"
fi

NOTARY_PROFILE="${SOLOPM_NOTARY_PROFILE:-}"

if [[ -z "$NOTARY_PROFILE" ]]; then
  echo "Notarization setup files are valid. SOLOPM_NOTARY_PROFILE is not set, so notary profile validation was not attempted."
  exit 0
fi

if [[ "$ONLINE_PREFLIGHT" != "1" ]]; then
  echo "Notarization setup files are valid. Configured profile was not validated online; rerun with SOLOPM_RELEASE_PREFLIGHT_ONLINE=1."
  exit 0
fi

if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null; then
  echo "Notarization setup files are valid and the configured notary profile is available."
else
  echo "Configured notary keychain profile could not be validated: $NOTARY_PROFILE" >&2
  exit 2
fi
