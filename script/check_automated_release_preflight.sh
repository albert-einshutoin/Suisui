#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METADATA_FILE="$ROOT_DIR/packaging/app_metadata.env"
TMP_ROOT="$ROOT_DIR/.tmp"
XCODE_WORKSPACE_RELATIVE=".swiftpm/xcode/package.xcworkspace"
XCODE_SCHEME="${SOLOPM_XCODE_SCHEME:-SoloPM}"
XCODE_DESTINATION="${SOLOPM_XCODE_DESTINATION:-platform=macOS}"
XCODE_CONFIGURATION="${SOLOPM_XCODE_CONFIGURATION:-Debug}"
APP_NAME="SoloPM"

if [[ -f "$METADATA_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$METADATA_FILE"
fi

APP_NAME="${APP_NAME:-SoloPM}"
mkdir -p "$TMP_ROOT"
TMP_DIR="$(mktemp -d "$TMP_ROOT/solopm-automated-release-preflight.XXXXXX")"
MCP_EVIDENCE_FILE="$TMP_DIR/mcp-inspector.md"

cd "$ROOT_DIR"

section() {
  printf "\n== %s ==\n" "$1"
}

terminate_app() {
  local quit_pid=""

  /usr/bin/osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 &
  quit_pid=$!

  for _ in {1..30}; do
    if ! kill -0 "$quit_pid" >/dev/null 2>&1; then
      wait "$quit_pid" >/dev/null 2>&1 || true
      break
    fi
    sleep 0.1
  done

  if kill -0 "$quit_pid" >/dev/null 2>&1; then
    kill "$quit_pid" >/dev/null 2>&1 || true
    wait "$quit_pid" >/dev/null 2>&1 || true
  fi

  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

cleanup() {
  terminate_app
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

section "Release CI"
./scripts/ci.sh

section "Local CRUD smoke"
./script/check_local_crud_smoke.sh

section "Runtime accessible CRUD smoke"
./script/check_runtime_accessible_crud_smoke.sh

section "Xcode build preflight"
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "BLOCKER: xcodebuild is required for the automated release preflight" >&2
  exit 2
fi
if [[ ! -d "$ROOT_DIR/$XCODE_WORKSPACE_RELATIVE" ]]; then
  echo "BLOCKER: missing SwiftPM Xcode workspace: $XCODE_WORKSPACE_RELATIVE" >&2
  exit 2
fi
xcodebuild \
  -workspace "$ROOT_DIR/$XCODE_WORKSPACE_RELATIVE" \
  -scheme "$XCODE_SCHEME" \
  -configuration "$XCODE_CONFIGURATION" \
  -destination "$XCODE_DESTINATION" \
  build

section "Launch preflight"
./script/build_and_run.sh --verify

section "Runtime accessibility preflight"
./script/check_accessibility_preflight.sh --runtime --skip-launch

section "MCP compliance preflight"
SOLOPM_MCP_EVIDENCE_FILE="$MCP_EVIDENCE_FILE" ./script/verify_mcp_compliance.sh

printf "\nOK: automated release preflight passed\n"
printf "This does not mark the release ready.\n"
printf "NEXT: run SOLOPM_AUTOMATED_PROOF_GATES=1 ./script/release_readiness_report.sh to combine automated proof gates with the remaining release blockers.\n"
printf "NEXT: complete manual VoiceOver, competitor hands-on, and signing/notarization/Sparkle/Gatekeeper evidence before release.\n"
