#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DMG_PATH="${1:-}"
EVIDENCE_FILE="${2:-${DMG_PATH}.notarization.json}"

if [[ -z "$DMG_PATH" || ! -f "$DMG_PATH" ]]; then
  echo "missing release DMG for notarization evidence verification: $DMG_PATH" >&2
  exit 2
fi
if [[ ! -f "$EVIDENCE_FILE" ]]; then
  echo "missing DMG notarization evidence: $EVIDENCE_FILE" >&2
  exit 2
fi
if ! plutil -convert json -o /dev/null "$EVIDENCE_FILE" 2>/dev/null; then
  echo "DMG notarization evidence is not valid JSON or plist: $EVIDENCE_FILE" >&2
  exit 2
fi

value() {
  plutil -extract "$1" raw -o - "$EVIDENCE_FILE" 2>/dev/null || true
}

expected_path="$DMG_PATH"
if [[ "$expected_path" == "$ROOT_DIR/"* ]]; then
  expected_path="${expected_path#"$ROOT_DIR/"}"
fi
artifact_path="$(value notarization.artifactPath)"
artifact_sha256="$(value notarization.artifactSha256)"
submission_id="$(value notarization.submissionID)"
status="$(value notarization.status)"
stapler_validated="$(value notarization.staplerValidated)"
gatekeeper_accepted="$(value notarization.gatekeeperAccepted)"
actual_sha256="$(shasum -a 256 "$DMG_PATH" | awk 'NF { print $1; exit }')"

if [[ "$artifact_path" != "$expected_path" ]]; then
  echo "DMG notarization evidence artifact path mismatch: expected '$expected_path', got '$artifact_path'" >&2
  exit 2
fi
if [[ -z "$submission_id" ]]; then
  echo "DMG notarization evidence notarization.submissionID is required" >&2
  exit 2
fi
if [[ "$status" != "Accepted" ]]; then
  echo "DMG notarization evidence notarization.status must be Accepted" >&2
  exit 2
fi
if [[ "$artifact_sha256" != "$actual_sha256" ]]; then
  echo "DMG notarization evidence notarization.artifactSha256 does not match artifact" >&2
  exit 2
fi
if [[ "$stapler_validated" != "true" ]]; then
  echo "DMG notarization evidence notarization.staplerValidated must be true" >&2
  exit 2
fi
if [[ "$gatekeeper_accepted" != "true" ]]; then
  echo "DMG notarization evidence notarization.gatekeeperAccepted must be true" >&2
  exit 2
fi

echo "OK: structured DMG notarization evidence matches the distributed artifact."
