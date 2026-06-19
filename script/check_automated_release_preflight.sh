#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METADATA_FILE="$ROOT_DIR/packaging/app_metadata.env"
TMP_ROOT="$ROOT_DIR/.tmp"
XCODE_WORKSPACE_RELATIVE=".swiftpm/xcode/package.xcworkspace"
XCODE_SCHEME="${SOLOPM_XCODE_SCHEME:-SoloPM}"
XCODE_DESTINATION="${SOLOPM_XCODE_DESTINATION:-platform=macOS}"
XCODE_CONFIGURATION="${SOLOPM_XCODE_CONFIGURATION:-Debug}"
AUTOMATED_PREFLIGHT_EVIDENCE_FILE="${SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE:-}"
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

require_clean_source_tree_for_evidence() {
  if [[ -z "$AUTOMATED_PREFLIGHT_EVIDENCE_FILE" ]]; then
    return 0
  fi

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "BLOCKER: automated preflight evidence requires a git worktree" >&2
    exit 2
  fi

  if ! git diff --quiet -- . || ! git diff --cached --quiet -- .; then
    echo "BLOCKER: automated preflight evidence requires a clean tracked source tree" >&2
    exit 2
  fi
}

write_automated_preflight_evidence() {
  if [[ -z "$AUTOMATED_PREFLIGHT_EVIDENCE_FILE" ]]; then
    return 0
  fi

  local evidence_file="$AUTOMATED_PREFLIGHT_EVIDENCE_FILE"
  if [[ "$evidence_file" != /* ]]; then
    evidence_file="$ROOT_DIR/$evidence_file"
  fi

  local evidence_dir generated_at source_commit
  evidence_dir="$(dirname "$evidence_file")"
  mkdir -p "$evidence_dir"
  generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  source_commit="$(git rev-parse --short HEAD 2>/dev/null || printf "unknown")"

  cat > "$evidence_file" <<EOF
# Automated Release Preflight Evidence

Status: passed
Generated at: $generated_at
Source commit: $source_commit
Tracked source tree: clean
App: $APP_NAME
Xcode workspace: $XCODE_WORKSPACE_RELATIVE
Xcode scheme: $XCODE_SCHEME
Xcode configuration: $XCODE_CONFIGURATION
Xcode destination: $XCODE_DESTINATION

## Passed Gates

- Release CI: passed
- Local CRUD smoke: passed
- Runtime accessible CRUD smoke: passed
- Xcode build preflight: passed
- Launch preflight: passed
- Runtime accessibility preflight: passed
- MCP compliance preflight: passed

## Boundaries

- This does not mark the release ready.
- Manual VoiceOver evidence remains separate.
- Competitor hands-on evidence remains separate.
- Developer ID signing, notarization, Sparkle, Gatekeeper, and clean-environment evidence remain separate.
EOF

  printf "Automated release preflight evidence written to %s\n" "$evidence_file"
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

require_clean_source_tree_for_evidence

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

write_automated_preflight_evidence

printf "\nOK: automated release preflight passed\n"
printf "This does not mark the release ready.\n"
printf "NEXT: run SOLOPM_AUTOMATED_PROOF_GATES=1 ./script/release_readiness_report.sh to combine automated proof gates with the remaining release blockers.\n"
printf "NEXT: complete manual VoiceOver, competitor hands-on, and signing/notarization/Sparkle/Gatekeeper evidence before release.\n"
