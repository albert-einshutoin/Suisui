#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METADATA_FILE="$ROOT_DIR/packaging/app_metadata.env"
NOTARIZATION_ENV_FILE="$ROOT_DIR/packaging/notarization.env"

if [[ ! -f "$METADATA_FILE" ]]; then
  echo "missing metadata file: $METADATA_FILE" >&2
  exit 2
fi

# shellcheck source=/dev/null
source "$METADATA_FILE"

if [[ "${SUISUI_LOAD_LOCAL_RELEASE_CONFIG:-1}" == "1" && -f "$NOTARIZATION_ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$NOTARIZATION_ENV_FILE"
fi

APP_NAME="${APP_NAME:?APP_NAME is required}"
NOTARY_PROFILE="${SUISUI_NOTARY_PROFILE:-}"
REQUIRE_NOTARIZATION="${SUISUI_REQUIRE_NOTARIZATION:-1}"

DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
NOTARY_DIR="$DIST_DIR/notary"
SUBMISSION_ZIP="$NOTARY_DIR/$APP_NAME-notary.zip"
SUBMISSION_LOG="$NOTARY_DIR/notarytool-submit.log"

case "$REQUIRE_NOTARIZATION" in
  0|1)
    ;;
  *)
    echo "SUISUI_REQUIRE_NOTARIZATION must be 0 or 1" >&2
    exit 2
    ;;
esac

if [[ -z "$NOTARY_PROFILE" ]]; then
  if [[ "$REQUIRE_NOTARIZATION" == "0" ]]; then
    echo "SUISUI_NOTARY_PROFILE is empty; notarization skipped because SUISUI_REQUIRE_NOTARIZATION=0."
    exit 0
  fi

  echo "SUISUI_NOTARY_PROFILE is required for notarization." >&2
  echo "Create it with 'xcrun notarytool store-credentials <profile-name>' on the release machine." >&2
  exit 2
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "missing app bundle: $APP_BUNDLE" >&2
  echo "Run './script/sign_app.sh' before notarization." >&2
  exit 2
fi

require_distribution_signature() {
  local app_bundle="$1"
  local signature_details

  signature_details="$(codesign -dv --verbose=4 "$app_bundle" 2>&1 || true)"
  if ! grep -F "Authority=Developer ID Application:" <<<"$signature_details" >/dev/null; then
    echo "app bundle is not signed with a Developer ID Application identity: $app_bundle" >&2
    exit 2
  fi

  if ! grep -E "flags=.*runtime" <<<"$signature_details" >/dev/null; then
    echo "app bundle signature is missing hardened runtime: $app_bundle" >&2
    exit 2
  fi
}

codesign --verify --strict --deep --verbose=2 "$APP_BUNDLE"
require_distribution_signature "$APP_BUNDLE"

rm -rf "$NOTARY_DIR"
mkdir -p "$NOTARY_DIR"
COPYFILE_DISABLE=1 ditto -c -k --keepParent --norsrc --noextattr "$APP_BUNDLE" "$SUBMISSION_ZIP"

set +e
xcrun notarytool submit "$SUBMISSION_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait \
  --output-format json 2>&1 | tee "$SUBMISSION_LOG"
submit_status="${PIPESTATUS[0]}"
set -e

submission_id="$(plutil -extract id raw -o - "$SUBMISSION_LOG" 2>/dev/null || true)"
submission_status_value="$(plutil -extract status raw -o - "$SUBMISSION_LOG" 2>/dev/null || true)"

# notarytool may exit successfully after waiting even when Apple marks the
# submission Invalid. Gate stapling on the response status as well as the
# process exit code so a rejected archive can never advance as release-ready.
if [[ "$submit_status" -ne 0 || "$submission_status_value" != "Accepted" ]]; then
  if [[ -n "$submission_id" ]]; then
    echo "Notarization failed. Fetch details with:" >&2
    echo "xcrun notarytool log $submission_id --keychain-profile $NOTARY_PROFILE" >&2
  else
    echo "Notarization failed before a submission id was returned." >&2
    echo "If a submission id exists, run: xcrun notarytool log <submission-id> --keychain-profile $NOTARY_PROFILE" >&2
  fi
  if [[ -n "$submission_status_value" ]]; then
    echo "Notarization status: $submission_status_value" >&2
  fi
  if [[ "$submit_status" -ne 0 ]]; then
    exit "$submit_status"
  fi
  exit 2
fi

xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"
spctl -a -vv "$APP_BUNDLE"

echo "Notarized, stapled, and validated $APP_BUNDLE."
