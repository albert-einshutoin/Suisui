#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METADATA_FILE="$ROOT_DIR/packaging/app_metadata.env"
SIGNING_ENV_FILE="$ROOT_DIR/packaging/signing.env"
ENTITLEMENTS_FILE="$ROOT_DIR/packaging/Suisui.entitlements"

if [[ ! -f "$METADATA_FILE" ]]; then
  echo "missing metadata file: $METADATA_FILE" >&2
  exit 2
fi

if [[ ! -f "$ENTITLEMENTS_FILE" ]]; then
  echo "missing entitlements file: $ENTITLEMENTS_FILE" >&2
  exit 2
fi

# shellcheck source=/dev/null
source "$METADATA_FILE"

if [[ -f "$SIGNING_ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$SIGNING_ENV_FILE"
fi

APP_NAME="${APP_NAME:?APP_NAME is required}"
SIGNING_IDENTITY="${SUISUI_SIGNING_IDENTITY:-}"
SIGNING_KEYCHAIN="${SUISUI_CODESIGN_KEYCHAIN:-}"
REQUIRE_SIGNING="${SUISUI_REQUIRE_SIGNING:-1}"
SKIP_BUILD="${SUISUI_SIGNING_SKIP_BUILD:-0}"

DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_BINARY="$APP_CONTENTS/MacOS/$APP_NAME"

case "$REQUIRE_SIGNING" in
  0|1)
    ;;
  *)
    echo "SUISUI_REQUIRE_SIGNING must be 0 or 1" >&2
    exit 2
    ;;
esac

require_developer_id_application_identity() {
  local signing_identity="$1"
  case "$signing_identity" in
    "Developer ID Application:"*)
      ;;
    *)
      echo "SUISUI_SIGNING_IDENTITY must be a Developer ID Application identity: $signing_identity" >&2
      exit 2
      ;;
  esac
}

if [[ -z "$SIGNING_IDENTITY" ]]; then
  if [[ "$REQUIRE_SIGNING" == "0" ]]; then
    echo "SUISUI_SIGNING_IDENTITY is empty; signing skipped because SUISUI_REQUIRE_SIGNING=0."
    exit 0
  fi

  echo "SUISUI_SIGNING_IDENTITY is required for Developer ID signing." >&2
  echo "Run 'security find-identity -p codesigning -v' and use a Developer ID Application identity." >&2
  exit 2
fi

require_developer_id_application_identity "$SIGNING_IDENTITY"

if ! security find-identity -p codesigning -v | grep -F "$SIGNING_IDENTITY" >/dev/null; then
  echo "Developer ID signing identity was not found in the available keychains: $SIGNING_IDENTITY" >&2
  echo "Run 'security find-identity -p codesigning -v' to inspect installed code signing identities." >&2
  exit 2
fi

case "$SKIP_BUILD" in
  0)
    SUISUI_BUILD_CONFIGURATION=release "$ROOT_DIR/script/build_and_run.sh" --build-only
    ;;
  1)
    if [[ ! -d "$APP_BUNDLE" ]]; then
      echo "app bundle does not exist and SUISUI_SIGNING_SKIP_BUILD=1: $APP_BUNDLE" >&2
      exit 2
    fi
    ;;
  *)
    echo "SUISUI_SIGNING_SKIP_BUILD must be 0 or 1" >&2
    exit 2
    ;;
esac

if [[ ! -x "$APP_BINARY" ]]; then
  echo "missing executable app binary: $APP_BINARY" >&2
  exit 2
fi

"$ROOT_DIR/script/prepare_release_bundle.sh" "$APP_BUNDLE"
"$ROOT_DIR/script/check_release_bundle_inventory.sh" "$APP_BUNDLE"
"$ROOT_DIR/script/verify_release_architecture.sh" "$APP_BUNDLE"

NESTED_CODESIGN_ARGS=(
  --force
  --timestamp
  --options runtime
  --sign "$SIGNING_IDENTITY"
)

if [[ -n "$SIGNING_KEYCHAIN" ]]; then
  NESTED_CODESIGN_ARGS+=(--keychain "$SIGNING_KEYCHAIN")
fi

# Apple recommends granting entitlements only to the executable that needs them.
# Sparkle helpers are separate executables and do not record audio, so they keep
# Hardened Runtime enabled without inheriting Suisui's audio-input permission.
APP_CODESIGN_ARGS=(
  "${NESTED_CODESIGN_ARGS[@]}"
  --entitlements "$ENTITLEMENTS_FILE"
)

if [[ -d "$APP_CONTENTS/Frameworks" ]]; then
  while IFS= read -r -d '' nested_code; do
    # Sparkle ships extensionless Mach-O helpers such as Autoupdate. Signing only
    # bundle directories and dylibs leaves those helpers ad hoc signed, which the
    # Apple notary service rejects even though local deep verification succeeds.
    if [[ -f "$nested_code" ]] && ! file -b "$nested_code" | grep -F "Mach-O" >/dev/null; then
      continue
    fi
    codesign "${NESTED_CODESIGN_ARGS[@]}" "$nested_code"
  done < <(find "$APP_CONTENTS/Frameworks" -depth \( \
    \( -type d \( -name "*.framework" -o -name "*.xpc" -o -name "*.appex" -o -name "*.app" \) \) \
    -o \( -type f \( -name "*.dylib" -o -perm -111 \) \) \
  \) -print0)
fi

codesign "${APP_CODESIGN_ARGS[@]}" "$APP_BUNDLE"
codesign --verify --strict --deep --verbose=2 "$APP_BUNDLE"
codesign -dvvv --entitlements :- "$APP_BUNDLE" >/dev/null

echo "Signed and verified $APP_BUNDLE with $SIGNING_IDENTITY."
