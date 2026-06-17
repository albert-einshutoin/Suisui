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

if [[ -f "$NOTARIZATION_ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$NOTARIZATION_ENV_FILE"
fi

APP_NAME="${APP_NAME:?APP_NAME is required}"
NOTARY_PROFILE="${SOLOPM_NOTARY_PROFILE:-}"
REQUIRE_NOTARIZATION="${SOLOPM_REQUIRE_NOTARIZATION:-1}"

DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
NOTARY_DIR="$DIST_DIR/notary"
SUBMISSION_ZIP="$NOTARY_DIR/$APP_NAME-notary.zip"
SUBMISSION_LOG="$NOTARY_DIR/notarytool-submit.log"

case "$REQUIRE_NOTARIZATION" in
  0|1)
    ;;
  *)
    echo "SOLOPM_REQUIRE_NOTARIZATION must be 0 or 1" >&2
    exit 2
    ;;
esac

if [[ -z "$NOTARY_PROFILE" ]]; then
  if [[ "$REQUIRE_NOTARIZATION" == "0" ]]; then
    echo "SOLOPM_NOTARY_PROFILE is empty; notarization skipped because SOLOPM_REQUIRE_NOTARIZATION=0."
    exit 0
  fi

  echo "SOLOPM_NOTARY_PROFILE is required for notarization." >&2
  echo "Create it with 'xcrun notarytool store-credentials <profile-name>' on the release machine." >&2
  exit 2
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "missing app bundle: $APP_BUNDLE" >&2
  echo "Run './script/sign_app.sh' before notarization." >&2
  exit 2
fi

codesign --verify --strict --deep --verbose=2 "$APP_BUNDLE"

rm -rf "$NOTARY_DIR"
mkdir -p "$NOTARY_DIR"
ditto -c -k --keepParent "$APP_BUNDLE" "$SUBMISSION_ZIP"

set +e
xcrun notarytool submit "$SUBMISSION_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1 | tee "$SUBMISSION_LOG"
submit_status="${PIPESTATUS[0]}"
set -e

if [[ "$submit_status" -ne 0 ]]; then
  submission_id="$(awk '/id: / { print $2; exit }' "$SUBMISSION_LOG" || true)"
  if [[ -n "$submission_id" ]]; then
    echo "Notarization failed. Fetch details with:" >&2
    echo "xcrun notarytool log $submission_id --keychain-profile $NOTARY_PROFILE" >&2
  else
    echo "Notarization failed before a submission id was returned." >&2
    echo "If a submission id exists, run: xcrun notarytool log <submission-id> --keychain-profile $NOTARY_PROFILE" >&2
  fi
  exit "$submit_status"
fi

xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"
spctl -a -vv "$APP_BUNDLE"

echo "Notarized, stapled, and validated $APP_BUNDLE."
