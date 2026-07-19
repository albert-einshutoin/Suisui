#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOTARIZATION_ENV_FILE="$ROOT_DIR/packaging/notarization.env"

if [[ -f "$NOTARIZATION_ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$NOTARIZATION_ENV_FILE"
fi

DMG_PATH="${1:-}"
NOTARY_PROFILE="${SOLOPM_NOTARY_PROFILE:-}"

if [[ -z "$DMG_PATH" ]]; then
  echo "usage: $0 <release.dmg>" >&2
  exit 2
fi

case "$DMG_PATH" in
  *.dmg)
    ;;
  *)
    echo "release notarization requires a DMG artifact: $DMG_PATH" >&2
    exit 2
    ;;
esac

if [[ ! -f "$DMG_PATH" ]]; then
  echo "missing release DMG: $DMG_PATH" >&2
  exit 2
fi

if [[ -z "$NOTARY_PROFILE" ]]; then
  echo "SOLOPM_NOTARY_PROFILE is required to notarize the release DMG." >&2
  echo "Create it with 'xcrun notarytool store-credentials <profile-name>' on the release machine." >&2
  exit 2
fi

NOTARY_DIR="$ROOT_DIR/dist/notary"
DMG_BASENAME="$(basename "$DMG_PATH" .dmg)"
SUBMISSION_LOG="$NOTARY_DIR/$DMG_BASENAME-dmg-notarytool-submit.json"
mkdir -p "$NOTARY_DIR"

set +e
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait \
  --output-format json 2>&1 | tee "$SUBMISSION_LOG"
submit_status="${PIPESTATUS[0]}"
set -e

submission_id="$(plutil -extract id raw -o - "$SUBMISSION_LOG" 2>/dev/null || true)"
notary_status="$(plutil -extract status raw -o - "$SUBMISSION_LOG" 2>/dev/null || true)"

if [[ "$submit_status" -ne 0 || "$notary_status" != "Accepted" ]]; then
  if [[ -n "$submission_id" ]]; then
    echo "DMG notarization was not accepted. Fetch details with:" >&2
    echo "xcrun notarytool log $submission_id --keychain-profile $NOTARY_PROFILE" >&2
  else
    echo "DMG notarization failed before a submission id was returned." >&2
  fi
  exit 1
fi

# The DMG is the outermost artifact users download. Stapling and assessing only
# the nested app is insufficient for offline Gatekeeper verification of the
# actual distribution artifact.
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl -a -t open --context context:primary-signature -vv "$DMG_PATH"

echo "Notarized, stapled, and Gatekeeper-validated release DMG: $DMG_PATH"
