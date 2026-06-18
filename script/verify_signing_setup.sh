#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENTITLEMENTS_FILE="$ROOT_DIR/packaging/SoloPM.entitlements"
SIGNING_ENV_FILE="$ROOT_DIR/packaging/signing.env"
SIGNING_EXAMPLE_FILE="$ROOT_DIR/packaging/signing.env.example"
SIGN_SCRIPT="$ROOT_DIR/script/sign_app.sh"
SIGNING_DOCS="$ROOT_DIR/docs/release/signing.md"

plutil -lint "$ENTITLEMENTS_FILE" >/dev/null

if [[ ! -x "$SIGN_SCRIPT" ]]; then
  echo "signing script is not executable: $SIGN_SCRIPT" >&2
  exit 2
fi

if [[ ! -f "$SIGNING_EXAMPLE_FILE" ]]; then
  echo "missing signing environment example: $SIGNING_EXAMPLE_FILE" >&2
  exit 2
fi

if [[ ! -f "$SIGNING_DOCS" ]]; then
  echo "missing signing release docs: $SIGNING_DOCS" >&2
  exit 2
fi

if [[ -f "$SIGNING_ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$SIGNING_ENV_FILE"
fi

require_developer_id_application_identity() {
  local signing_identity="$1"
  case "$signing_identity" in
    "Developer ID Application:"*)
      ;;
    *)
      echo "SOLOPM_SIGNING_IDENTITY must be a Developer ID Application identity: $signing_identity" >&2
      exit 2
      ;;
  esac
}

if [[ -z "${SOLOPM_SIGNING_IDENTITY:-}" ]]; then
  echo "Signing setup files are valid. SOLOPM_SIGNING_IDENTITY is not set, so Developer ID signing was not attempted."
  exit 0
fi

require_developer_id_application_identity "$SOLOPM_SIGNING_IDENTITY"

if security find-identity -p codesigning -v | grep -F "$SOLOPM_SIGNING_IDENTITY" >/dev/null; then
  echo "Signing setup files are valid and the configured identity is available."
else
  echo "Configured signing identity is not available: $SOLOPM_SIGNING_IDENTITY" >&2
  exit 2
fi
