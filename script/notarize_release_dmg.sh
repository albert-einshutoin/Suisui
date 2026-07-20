#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOTARIZATION_ENV_FILE="$ROOT_DIR/packaging/notarization.env"

if [[ -f "$NOTARIZATION_ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$NOTARIZATION_ENV_FILE"
fi

DMG_PATH="${1:-}"
NOTARY_PROFILE="${SUISUI_NOTARY_PROFILE:-}"

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
  echo "SUISUI_NOTARY_PROFILE is required to notarize the release DMG." >&2
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

NOTARIZATION_EVIDENCE_FILE="${SUISUI_DMG_NOTARIZATION_EVIDENCE_FILE:-$DMG_PATH.notarization.json}"
artifact_path="$DMG_PATH"
submission_log_path="$SUBMISSION_LOG"
if [[ "$artifact_path" == "$ROOT_DIR/"* ]]; then
  artifact_path="${artifact_path#"$ROOT_DIR/"}"
fi
if [[ "$submission_log_path" == "$ROOT_DIR/"* ]]; then
  submission_log_path="${submission_log_path#"$ROOT_DIR/"}"
fi
artifact_sha256="$(shasum -a 256 "$DMG_PATH" | awk 'NF { print $1; exit }')"
checked_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# Persist only non-secret Apple acceptance data. The final preflight binds this
# submission id and stapled artifact digest to the exact DMG users download.
mkdir -p "$(dirname "$NOTARIZATION_EVIDENCE_FILE")"
cat >"$NOTARIZATION_EVIDENCE_FILE" <<EOF
{
  "notarization": {
    "artifactPath": "$artifact_path",
    "artifactSha256": "$artifact_sha256",
    "submissionID": "$submission_id",
    "status": "$notary_status",
    "staplerValidated": true,
    "gatekeeperAccepted": true,
    "submissionLog": "$submission_log_path",
    "checkedAt": "$checked_at"
  }
}
EOF

echo "Notarized, stapled, and Gatekeeper-validated release DMG: $DMG_PATH"
echo "DMG notarization evidence written: $NOTARIZATION_EVIDENCE_FILE"
