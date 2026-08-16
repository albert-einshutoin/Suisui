#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METADATA_FILE="$ROOT_DIR/packaging/app_metadata.env"
TMP_ROOT="$ROOT_DIR/.tmp"
XCODE_WORKSPACE_RELATIVE=".swiftpm/xcode/package.xcworkspace"
XCODE_SCHEME="Suisui"
XCODE_DESTINATION="platform=macOS"
XCODE_CONFIGURATION="Debug"
XCODE_PREFLIGHT_TIMEOUT_SECONDS="${SUISUI_XCODE_PREFLIGHT_TIMEOUT_SECONDS:-600}"
AUTOMATED_PREFLIGHT_EVIDENCE_FILE="${SUISUI_AUTOMATED_PREFLIGHT_EVIDENCE_FILE:-}"
REFRESH_MANUAL_HELPERS="${SUISUI_REFRESH_MANUAL_HELPERS:-1}"
APP_NAME="Suisui"
RUNTIME_AX_SMOKE_OUTPUT=""
VOICEOVER_CANDIDATE_SOURCE_COMMIT=""
VOICEOVER_CANDIDATE_PROJECT_ID=""
VOICEOVER_CANDIDATE_DATABASE=""
VOICEOVER_CANDIDATE_SELECTED_DESTINATION=""

if [[ -f "$METADATA_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$METADATA_FILE"
fi

APP_NAME="${APP_NAME:-Suisui}"
cd "$ROOT_DIR"
ROOT_CANONICAL="$(pwd -P)"
TRUSTED_GIT="$ROOT_DIR/ci/trusted-bin/git"

# Release evidence must use repository-owned probes. Local helper overrides
# remain available to focused scripts but cannot produce reusable proof here.
unset \
  SQLITE3 \
  AX_HELPERS \
  AX_TEXT_INPUT_HELPER \
  AX_SCROLL_HELPER \
  AX_BUTTON_HELPER \
  AX_MARKER_HELPER \
  AX_FRAME_HELPER \
  AX_PRESS_ELEMENT_HELPER \
  AX_RESIZE_WINDOW_HELPER \
  AX_IDENTIFIER_COUNT_HELPER \
  WINDOW_CONTENT_SIZE_HELPER \
  GIT_DIR \
  GIT_WORK_TREE \
  GIT_COMMON_DIR \
  GIT_INDEX_FILE \
  GIT_OBJECT_DIRECTORY \
  GIT_ALTERNATE_OBJECT_DIRECTORIES \
  GIT_SHALLOW_FILE \
  GIT_NAMESPACE \
  GIT_REPLACE_REF_BASE \
  GIT_CONFIG_PARAMETERS \
  GIT_CONFIG_COUNT \
  GIT_CONFIG_GLOBAL \
  GIT_CONFIG_SYSTEM \
  GIT_CONFIG_NOSYSTEM \
  GIT_EXEC_PATH \
  GIT_EXTERNAL_DIFF \
  GIT_DIFF_OPTS
export GIT_NO_REPLACE_OBJECTS=1
export PATH="$ROOT_DIR/ci/trusted-bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin:$PATH"

default_automated_preflight_evidence_file() {
  local commit
  commit="$("$TRUSTED_GIT" rev-parse --short HEAD 2>/dev/null || true)"

  if [[ -z "${commit//[[:space:]]/}" ]]; then
    printf ".tmp/automated-release-preflight.md"
  else
    printf ".tmp/automated-release-preflight-${commit}.md"
  fi
}

unsafe_automated_preflight_evidence_destination() {
  echo "BLOCKER: unsafe automated preflight evidence destination; use a regular file below the repository .tmp directory" >&2
  return 2
}

initialize_automated_preflight_evidence_destination() {
  local evidence_file="$AUTOMATED_PREFLIGHT_EVIDENCE_FILE"
  local evidence_parent existing_ancestor ancestor_canonical parent_canonical basename

  if [[ "$evidence_file" != /* ]]; then
    evidence_file="$ROOT_CANONICAL/$evidence_file"
  fi
  case "$evidence_file" in
    */../*|*/./*) unsafe_automated_preflight_evidence_destination; return 2 ;;
  esac
  case "$evidence_file" in
    "$ROOT_CANONICAL/.tmp/"*) ;;
    *) unsafe_automated_preflight_evidence_destination; return 2 ;;
  esac

  if [[ -L "$TMP_ROOT" || ( -e "$TMP_ROOT" && ! -d "$TMP_ROOT" ) ]]; then
    unsafe_automated_preflight_evidence_destination
    return 2
  fi
  mkdir -p "$TMP_ROOT"
  if [[ "$(cd "$TMP_ROOT" && pwd -P)" != "$ROOT_CANONICAL/.tmp" ]]; then
    unsafe_automated_preflight_evidence_destination
    return 2
  fi

  evidence_parent="$(dirname "$evidence_file")"
  basename="$(basename "$evidence_file")"
  if [[ -z "$basename" || "$basename" == "." || "$basename" == ".." ]]; then
    unsafe_automated_preflight_evidence_destination
    return 2
  fi
  existing_ancestor="$evidence_parent"
  while [[ ! -e "$existing_ancestor" && ! -L "$existing_ancestor" ]]; do
    existing_ancestor="$(dirname "$existing_ancestor")"
  done
  if [[ ! -d "$existing_ancestor" || -L "$existing_ancestor" ]]; then
    unsafe_automated_preflight_evidence_destination
    return 2
  fi
  ancestor_canonical="$(cd "$existing_ancestor" && pwd -P)"
  case "$ancestor_canonical/" in
    "$ROOT_CANONICAL/.tmp/"*) ;;
    *) unsafe_automated_preflight_evidence_destination; return 2 ;;
  esac

  mkdir -p "$evidence_parent"
  if [[ ! -d "$evidence_parent" || -L "$evidence_parent" ]]; then
    unsafe_automated_preflight_evidence_destination
    return 2
  fi
  parent_canonical="$(cd "$evidence_parent" && pwd -P)"
  case "$parent_canonical/" in
    "$ROOT_CANONICAL/.tmp/"*) ;;
    *) unsafe_automated_preflight_evidence_destination; return 2 ;;
  esac
  if [[ -L "$evidence_file" || ( -e "$evidence_file" && ! -f "$evidence_file" ) ]]; then
    unsafe_automated_preflight_evidence_destination
    return 2
  fi
  AUTOMATED_PREFLIGHT_EVIDENCE_FILE="$parent_canonical/$basename"
}

if [[ -z "$AUTOMATED_PREFLIGHT_EVIDENCE_FILE" ]]; then
  # Release readiness auto-discovers this exact path, so the standard sweep
  # writes reusable proof instead of forcing operators to run the heavy gates
  # a second time just to produce evidence.
  AUTOMATED_PREFLIGHT_EVIDENCE_FILE="$(default_automated_preflight_evidence_file)"
fi

initialize_automated_preflight_evidence_destination
TMP_DIR="$(mktemp -d "$TMP_ROOT/suisui-automated-release-preflight.XXXXXX")"
MCP_EVIDENCE_FILE="$TMP_DIR/mcp-inspector.md"

section() {
  printf "\n== %s ==\n" "$1"
}

require_clean_source_tree_for_evidence() {
  if [[ -z "$AUTOMATED_PREFLIGHT_EVIDENCE_FILE" ]]; then
    return 0
  fi

  if ! "$TRUSTED_GIT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "BLOCKER: automated preflight evidence requires a git worktree" >&2
    exit 2
  fi

  if ! "$TRUSTED_GIT" diff --quiet -- . || ! "$TRUSTED_GIT" diff --cached --quiet -- .; then
    echo "BLOCKER: automated preflight evidence requires a clean tracked source tree" >&2
    exit 2
  fi
}

tracked_source_tree_is_clean() {
  "$TRUSTED_GIT" rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
    "$TRUSTED_GIT" diff --quiet -- . &&
    "$TRUSTED_GIT" diff --cached --quiet -- .
}

refresh_manual_release_helpers() {
  if [[ "$REFRESH_MANUAL_HELPERS" != "1" ]]; then
    echo "INFO: manual release helper refresh skipped because SUISUI_REFRESH_MANUAL_HELPERS is not 1"
    return 0
  fi

  if ! tracked_source_tree_is_clean; then
    echo "INFO: manual release helper refresh skipped because tracked source tree is not clean"
    return 0
  fi

  ./script/prepare_release_manual_helpers.sh
}

write_automated_preflight_evidence() {
  if [[ -z "$AUTOMATED_PREFLIGHT_EVIDENCE_FILE" ]]; then
    return 0
  fi

  local evidence_file="$AUTOMATED_PREFLIGHT_EVIDENCE_FILE"
  local evidence_dir generated_at source_commit private_dir private_file parent_canonical
  evidence_dir="$(dirname "$evidence_file")"
  generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  source_commit="$("$TRUSTED_GIT" rev-parse --short HEAD 2>/dev/null || printf "unknown")"
  private_dir="$(mktemp -d "$evidence_dir/.automated-release-preflight.XXXXXX")"
  private_file="$private_dir/evidence.md"
  umask 077

  cat > "$private_file" <<EOF
# Automated Release Preflight Evidence

Status: passed
Generated by: script/check_automated_release_preflight.sh
Generated at: $generated_at
Source commit: $source_commit
Tracked source tree: clean
App: $APP_NAME
Xcode workspace: $XCODE_WORKSPACE_RELATIVE
Xcode scheme: $XCODE_SCHEME
Xcode configuration: $XCODE_CONFIGURATION
Xcode destination: $XCODE_DESTINATION
VoiceOver candidate source commit: $VOICEOVER_CANDIDATE_SOURCE_COMMIT
VoiceOver candidate project ID: $VOICEOVER_CANDIDATE_PROJECT_ID
VoiceOver candidate database: $VOICEOVER_CANDIDATE_DATABASE
VoiceOver candidate selected destination: $VOICEOVER_CANDIDATE_SELECTED_DESTINATION

## Passed Gates

- Release CI: passed
- Release launch performance smoke: passed
- Real visual regression: passed
- Local CRUD smoke: passed
- Runtime accessible CRUD smoke: passed
- Layout stability smoke: passed
- Xcode build preflight: passed
- Launch preflight: passed
- Runtime accessibility preflight: passed
- MCP compliance preflight: passed

## Runtime AX Smoke

Runtime AX smoke: $RUNTIME_AX_SMOKE_OUTPUT

## Boundaries

- This does not mark the release ready.
- Manual VoiceOver evidence remains separate.
- Competitor hands-on evidence remains separate.
- Developer ID signing, notarization, Sparkle, Gatekeeper, and clean-environment evidence remain separate.
EOF

  if [[ ! -d "$evidence_dir" || -L "$evidence_dir" ]]; then
    unsafe_automated_preflight_evidence_destination
    return 2
  fi
  parent_canonical="$(cd "$evidence_dir" && pwd -P)"
  if [[ "$parent_canonical" != "$evidence_dir" || -L "$evidence_file" || ( -e "$evidence_file" && ! -f "$evidence_file" ) ]]; then
    unsafe_automated_preflight_evidence_destination
    return 2
  fi
  /bin/mv -fh "$private_file" "$evidence_file"
  rmdir "$private_dir"

  printf "Automated release preflight evidence written to %s\n" "$evidence_file"
}

capture_voiceover_candidate_context() {
  local launch_env_file="$ROOT_DIR/.tmp/voiceover-review/launch.env"

  if [[ ! -f "$launch_env_file" ]]; then
    echo "BLOCKER: VoiceOver candidate launch env was not generated: $launch_env_file" >&2
    exit 2
  fi

  # Source the generated launch env instead of re-deriving values so the evidence
  # records the exact seeded candidate used by the runtime AX smoke gate.
  # shellcheck source=/dev/null
  source "$launch_env_file"
  VOICEOVER_CANDIDATE_SOURCE_COMMIT="${SUISUI_VOICEOVER_REVIEW_SOURCE_COMMIT:-}"
  VOICEOVER_CANDIDATE_PROJECT_ID="${SUISUI_VOICEOVER_REVIEW_PROJECT_ID:-}"
  VOICEOVER_CANDIDATE_DATABASE="${SUISUI_DATABASE_PATH:-}"
  VOICEOVER_CANDIDATE_SELECTED_DESTINATION="${SUISUI_PROJECT_BOARD_SELECTED_DESTINATION:-}"

  if [[ -z "${VOICEOVER_CANDIDATE_SOURCE_COMMIT//[[:space:]]/}" ||
    -z "${VOICEOVER_CANDIDATE_PROJECT_ID//[[:space:]]/}" ||
    -z "${VOICEOVER_CANDIDATE_DATABASE//[[:space:]]/}" ||
    -z "${VOICEOVER_CANDIDATE_SELECTED_DESTINATION//[[:space:]]/}" ]]; then
    echo "BLOCKER: VoiceOver candidate launch env is missing source/project/database/destination context" >&2
    exit 2
  fi
}

run_xcodebuild_with_timeout() {
  local timeout_marker="$TMP_DIR/xcodebuild-timeout"
  rm -f "$timeout_marker"

  # Xcode/SwiftBuild can hang before returning an actionable failure; fail closed
  # so release automation never records stale local proof as reusable evidence.
  (
    cd "$ROOT_DIR"
    # Xcode materializes `.swiftpm/xcode/package.xcworkspace` when it opens a
    # Swift package. Invoking from the package root keeps this gate valid on a
    # pristine checkout instead of requiring an untracked local derivative.
    exec /usr/bin/xcodebuild \
      -scheme "$XCODE_SCHEME" \
      -configuration "$XCODE_CONFIGURATION" \
      -destination "$XCODE_DESTINATION" \
      build
  ) &
  local xcode_pid=$!

  (
    sleep "$XCODE_PREFLIGHT_TIMEOUT_SECONDS"
    if kill -0 "$xcode_pid" >/dev/null 2>&1; then
      : >"$timeout_marker"
      echo "BLOCKER: Xcode build preflight timed out after ${XCODE_PREFLIGHT_TIMEOUT_SECONDS}s" >&2
      printf 'NEXT: reproduce from %q with xcodebuild -scheme %q -configuration %q -destination %q build\n' \
        "$ROOT_DIR" "$XCODE_SCHEME" "$XCODE_CONFIGURATION" "$XCODE_DESTINATION" >&2
      printf 'NEXT: this is separate from the SwiftPM native build; do not reuse automated preflight evidence until the Xcode build gate passes.\n' >&2
      kill "$xcode_pid" >/dev/null 2>&1 || true
      sleep 2
      kill -KILL "$xcode_pid" >/dev/null 2>&1 || true
    fi
  ) &
  local watchdog_pid=$!

  set +e
  wait "$xcode_pid"
  local xcode_status=$?
  set -e

  kill "$watchdog_pid" >/dev/null 2>&1 || true
  wait "$watchdog_pid" >/dev/null 2>&1 || true

  if [[ -f "$timeout_marker" ]]; then
    rm -f "$timeout_marker"
    return 2
  fi

  return "$xcode_status"
}

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

require_clean_source_tree_for_evidence

if ! [[ "$XCODE_PREFLIGHT_TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] || [[ "$XCODE_PREFLIGHT_TIMEOUT_SECONDS" -le 0 ]]; then
  echo "BLOCKER: SUISUI_XCODE_PREFLIGHT_TIMEOUT_SECONDS must be a positive integer" >&2
  exit 2
fi

section "Release CI"
env \
  -u SUISUI_CI_LANE \
  -u SUISUI_SWIFTPM_TEST_BASELINE_FILE \
  -u SUISUI_SWIFTPM_MAX_SKIPPED_FILE \
  SUISUI_CI_RELEASE_GATES=1 \
  ./scripts/ci.sh

section "Local CRUD smoke"
./script/check_local_crud_smoke.sh

section "Production UI runtime gate"
env \
  -u SUISUI_RUNTIME_ACCESSIBLE_CRUD_RECOVERABLE_ONLY \
  -u SUISUI_LAYOUT_STABILITY_FRAME_DELTA_THRESHOLD_PX \
  -u SUISUI_LAYOUT_STABILITY_CLIPPING_TOLERANCE_PX \
  -u SUISUI_LAYOUT_STABILITY_DATABASE_PATH \
  -u SUISUI_HEADER_LAYOUT_DATABASE_PATH \
  -u SUISUI_HEADER_LAYOUT_ENTRYPOINTS_ONLY \
  -u SUISUI_LAYOUT_STABILITY_CONTENT_MIN_HEIGHT \
  -u SUISUI_LAYOUT_STABILITY_WINDOW_BELOW_MIN_WIDTH \
  -u SUISUI_LAYOUT_STABILITY_WINDOW_COMPACT_WIDTH \
  -u SUISUI_LAYOUT_STABILITY_WINDOW_CANONICAL_WIDTH \
  -u SUISUI_LAYOUT_STABILITY_WINDOW_MIN_WIDTH \
  -u SUISUI_LAYOUT_STABILITY_WINDOW_BELOW_MIN_HEIGHT \
  -u SUISUI_LAYOUT_STABILITY_WINDOW_MIN_HEIGHT \
  -u SUISUI_LAYOUT_STABILITY_WINDOW_STANDARD_WIDTH \
  -u SUISUI_LAYOUT_STABILITY_WINDOW_STANDARD_HEIGHT \
  -u SUISUI_LAYOUT_STABILITY_WINDOW_WIDE_WIDTH \
  -u SUISUI_LAYOUT_STABILITY_WINDOW_WIDE_HEIGHT \
  -u SUISUI_RUNTIME_TODAY_MAX_TOOLBAR_LAYOUT_DEPTH \
  -u SUISUI_RUNTIME_TODAY_WINDOW_WIDTH \
  -u SUISUI_RUNTIME_TODAY_WINDOW_HEIGHT \
  SUISUI_CI_COMPLETE_RUNTIME=1 \
  SUISUI_RUNTIME_POLICY=public-alpha \
  SUISUI_CI_ARTIFACT_ROOT="$TMP_DIR/ui-gates" \
  ./scripts/ci.sh ui-runtime

section "Xcode build preflight"
if [[ ! -x /usr/bin/xcodebuild ]]; then
  echo "BLOCKER: xcodebuild is required for the automated release preflight" >&2
  exit 2
fi
run_xcodebuild_with_timeout

section "Real visual regression"
env \
  -u SUISUI_CI_VISUAL_GATE_LOCALE \
  -u SUISUI_VISUAL_SOURCE_REF \
  -u SUISUI_VISUAL_FIXTURE_SEEDER_BIN \
  -u SUISUI_AX_AUDIT_RESULT \
  -u SUISUI_VISUAL_CURRENT_SOURCE_COMMIT \
  -u SUISUI_VISUAL_BASELINE_VIEWPORT \
  -u SUISUI_SETTINGS_VISUAL_BASELINE_VIEWPORT \
  -u SUISUI_VOICE_COMMAND_VISUAL_BASELINE_VIEWPORT \
  -u SUISUI_VISUAL_EVIDENCE_REFERENCE_INSTANT \
  -u SUISUI_VISUAL_EVIDENCE_TIME_ZONE \
  -u SUISUI_VISUAL_EVIDENCE_LOCALE_IDENTIFIER \
  -u SUISUI_VISUAL_EVIDENCE_SCHEDULE_MODE \
  -u SUISUI_VISUAL_EVIDENCE_STABLE_BACKDROP \
  -u SUISUI_VISUAL_EVIDENCE_SYSTEM_APPEARANCE \
  -u SUISUI_UI_EVIDENCE_TARGET_TIMEOUT_SECONDS \
  -u SUISUI_UI_EVIDENCE_AX_MAX_NODES \
  SUISUI_CI_VISUAL_BASELINE_PROFILE=local-display \
  SUISUI_RUNTIME_POLICY=public-alpha \
  SUISUI_CI_ARTIFACT_ROOT="$TMP_DIR/ui-gates" \
  ./scripts/ci.sh ui-visual

section "Release launch performance smoke"
# Release preflight should validate the same release-oriented launch budgets
# that operators rely on for release evidence. Keep these assignments fixed so
# caller-provided debug or relaxed-budget env cannot weaken automated evidence.
env \
  -u SUISUI_PERFORMANCE_USE_PREBUILT_APP \
  -u SUISUI_PERFORMANCE_DATABASE_PATH \
  SUISUI_PERFORMANCE_PROFILE=release \
  SUISUI_PERFORMANCE_BUILD_CONFIGURATION=release \
  SUISUI_PERFORMANCE_MAX_COLD_LAUNCH_MS=1000 \
  SUISUI_PERFORMANCE_MAX_DESTINATION_SWITCH_MS=3000 \
  SUISUI_RUNTIME_POLICY=public-alpha \
  SUISUI_CI_ARTIFACT_ROOT="$TMP_DIR/ui-gates" \
  ./scripts/ci.sh ui-performance

section "Runtime accessibility candidate"
./script/prepare_voiceover_review_candidate.sh --skip-build --no-launch
capture_voiceover_candidate_context

section "Runtime accessibility preflight"
set +e
# macOS can expose the visible Project Board before the accessibility tree settles.
# Keep this gate deterministic by giving the seeded AX smoke a longer bounded wait.
runtime_accessibility_output="$(./script/check_accessibility_preflight.sh --runtime --launch-env .tmp/voiceover-review/launch.env --timeout 30 2>&1)"
runtime_accessibility_status=$?
set -e
if [[ -n "$runtime_accessibility_output" ]]; then
  printf "%s\n" "$runtime_accessibility_output"
fi
if [[ "$runtime_accessibility_status" -ne 0 ]]; then
  exit "$runtime_accessibility_status"
fi
if ! RUNTIME_AX_SMOKE_OUTPUT="$(printf "%s\n" "$runtime_accessibility_output" | awk '/^OK: runtime AX smoke visible/ { print; found = 1; exit } END { if (found != 1) { exit 1 } }')"; then
  echo "BLOCKER: runtime accessibility preflight did not emit a runtime AX smoke OK line" >&2
  exit 1
fi
if [[ -z "${RUNTIME_AX_SMOKE_OUTPUT//[[:space:]]/}" ]]; then
  echo "BLOCKER: runtime accessibility preflight did not emit a runtime AX smoke OK line" >&2
  exit 1
fi

section "MCP compliance preflight"
env \
  -u SUISUI_MCP_INSPECTOR_BIN \
  -u SUISUI_MCP_NPX_BIN \
  SUISUI_MCP_SOURCE_REF=HEAD \
  SUISUI_MCP_EVIDENCE_FILE="$MCP_EVIDENCE_FILE" \
  ./script/verify_mcp_compliance.sh

section "Refresh manual release helpers"
refresh_manual_release_helpers

write_automated_preflight_evidence

printf "\nOK: automated release preflight passed\n"
printf "This does not mark the release ready.\n"
if [[ -n "$AUTOMATED_PREFLIGHT_EVIDENCE_FILE" ]]; then
  printf "NEXT: run "
  printf 'SUISUI_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=%q ./script/release_readiness_report.sh' "$AUTOMATED_PREFLIGHT_EVIDENCE_FILE"
  printf " to reuse this evidence with the remaining release blockers.\n"
else
  printf "NEXT: run SUISUI_AUTOMATED_PROOF_GATES=1 ./script/release_readiness_report.sh to combine automated proof gates with the remaining release blockers.\n"
fi
printf "NEXT: complete manual VoiceOver, competitor hands-on, and signing/notarization/Sparkle/Gatekeeper evidence before release.\n"
