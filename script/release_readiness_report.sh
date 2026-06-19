#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BLOCKER_COUNT=0
BLOCKER_MESSAGES=()
APP_METADATA_FILE="$ROOT_DIR/packaging/app_metadata.env"
RELEASE_ACTIONS_FILE="${SOLOPM_RELEASE_ACTIONS_FILE:-}"
AUTOMATED_PROOF_GATES="${SOLOPM_AUTOMATED_PROOF_GATES:-0}"
RELEASE_CI_PREFLIGHT="${SOLOPM_RELEASE_CI_PREFLIGHT:-$AUTOMATED_PROOF_GATES}"
RELEASE_CI_PREFLIGHT_RELATIVE="scripts/ci.sh"
LOCAL_CRUD_SMOKE="${SOLOPM_LOCAL_CRUD_SMOKE:-$AUTOMATED_PROOF_GATES}"
LOCAL_CRUD_SMOKE_RELATIVE="script/check_local_crud_smoke.sh"
RUNTIME_ACCESSIBLE_CRUD_SMOKE="${SOLOPM_RUNTIME_ACCESSIBLE_CRUD_SMOKE:-$AUTOMATED_PROOF_GATES}"
RUNTIME_ACCESSIBLE_CRUD_SMOKE_RELATIVE="script/check_runtime_accessible_crud_smoke.sh"
RELEASE_XCODE_PREFLIGHT="${SOLOPM_RELEASE_XCODE_PREFLIGHT:-$AUTOMATED_PROOF_GATES}"
XCODE_WORKSPACE_RELATIVE=".swiftpm/xcode/package.xcworkspace"
XCODE_SCHEME="${SOLOPM_XCODE_SCHEME:-SoloPM}"
XCODE_DESTINATION="${SOLOPM_XCODE_DESTINATION:-platform=macOS}"
RELEASE_LAUNCH_PREFLIGHT="${SOLOPM_RELEASE_LAUNCH_PREFLIGHT:-$AUTOMATED_PROOF_GATES}"
RELEASE_LAUNCH_PREFLIGHT_RELATIVE="script/build_and_run.sh"
MOCK_PATTERN="(?i:fake|mock|fixture|canned|stub|skeleton|todo|fixme|not[[:space:]_-]*implemented|notimplemented|inmemory)|(?i:(^|[^[:alnum:]_])(demo|sample|placeholder)([^[:alnum:]_]|$))|Static[A-Za-z0-9_]*|:memory:|fatalError|preconditionFailure"
UI_EVIDENCE_RELATIVE="docs/release/evidence/ui-screenshots.md"
UI_SCREENSHOT_RELATIVE_DIR="docs/release/evidence/ui-screenshots"
UI_SCREENSHOT_MIN_BYTES=50000
UI_SCREENSHOT_MIN_WIDTH=640
UI_SCREENSHOT_MIN_HEIGHT=420
VOICEOVER_EVIDENCE_RELATIVE="docs/release/evidence/accessibility-voiceover.md"
ACCESSIBILITY_PREFLIGHT_RELATIVE="script/check_accessibility_preflight.sh"
ACCESSIBILITY_RUNTIME_PREFLIGHT="${SOLOPM_ACCESSIBILITY_RUNTIME_PREFLIGHT:-$AUTOMATED_PROOF_GATES}"
COMPETITOR_EVIDENCE_RELATIVE="docs/release/evidence/competitor-hands-on.md"
COMPETITOR_BENCHMARK_RELATIVE="docs/product/competitor-benchmark.md"
MCP_EVIDENCE_RELATIVE="docs/release/evidence/mcp-inspector.md"
MCP_COMPLIANCE_RELATIVE="script/verify_mcp_compliance.sh"
RUNTIME_SOURCE_DIRS=(
  "$ROOT_DIR/Sources/SoloPMCore"
  "$ROOT_DIR/Sources/SoloPMApp"
  "$ROOT_DIR/Sources/SoloPMCLI"
)
UI_SCREENSHOTS=(
  "Light:project-board-light.png"
  "Dark:project-board-dark.png"
  "System:project-board-system.png"
  "Settings Overview Light:settings-overview-light.png"
  "Settings Overview Dark:settings-overview-dark.png"
  "MCP Settings Light:settings-mcp-light.png"
  "MCP Settings Dark:settings-mcp-dark.png"
)
VOICEOVER_REQUIRED_MARKERS=(
  "Status: passed"
  "Project navigation"
  "Project board detail"
  "Open task"
  "Inline Task Composer"
  "Status controls"
  "Task inspector"
  "Save Changes"
  "Delete Task confirmation"
  "No keyboard trap"
  "No unlabeled primary CRUD controls"
)
VOICEOVER_REQUIRED_CONTEXT_LABELS=(
  "macOS version"
  "App build"
  "Bundle identifier"
  "Checked by"
  "Check date"
  "Evidence source"
  "Accessibility environment"
  "Runtime AX smoke"
)
VOICEOVER_REQUIRED_NOTE_LABELS=(
  "Project navigation"
  "Project board detail"
  "Open task"
  "Inline Task Composer"
  "Status controls"
  "Task inspector"
  "Save Changes"
  "Delete Task confirmation"
  "No keyboard trap"
  "No unlabeled primary CRUD controls"
)
COMPETITOR_REQUIRED_MARKERS=(
  "Status: passed"
  "Notion"
  "Todoist"
  "Linear"
  "Motion"
  "No external SaaS sync or team workflow was added"
  "Ship / Defer / Reject Delta"
)
COMPETITOR_REQUIRED_CONTEXT_LABELS=(
  "Checked by"
  "Check date"
  "Evidence source"
  "Environment"
  "Scope"
)
COMPETITOR_REQUIRED_NOTE_LABELS=(
  "Notion"
  "Todoist"
  "Linear"
  "Motion"
)
COMPETITOR_REQUIRED_DECISION_LABELS=(
  "Ship"
  "Defer"
  "Reject"
)
MCP_EVIDENCE_REQUIRED_MARKERS=(
  "Generated:"
  "Scope: validate the release MCP stdio fixture"
  'Stable baseline: `2025-11-25`'
  'Official stable latest: `2025-11-25`'
  "Official stable source: https://modelcontextprotocol.io/specification/2025-11-25"
  'Draft watchlist: `2026-07-28`'
  "Draft release-candidate source: https://blog.modelcontextprotocol.io/posts/2026-07-28-release-candidate/"
  "2026-07-28 is release-candidate; final specification is scheduled for 2026-07-28."
  "not a full MCP host"
  "initialize -> tools/list -> tools/call"
  "MCP Inspector CLI tools/list"
  "MCP Inspector CLI tools/call"
  "SoloPM local smoke success"
  "malformed-json"
  "mismatched-id"
  "invalid-schema"
  "timeout"
  "exit: 0"
)

if [[ -f "$APP_METADATA_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$APP_METADATA_FILE"
fi

EXPECTED_VOICEOVER_BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-}"
EXPECTED_VOICEOVER_APP_BUILD=""
if [[ -n "${MARKETING_VERSION:-}" && -n "${CURRENT_PROJECT_VERSION:-}" ]]; then
  EXPECTED_VOICEOVER_APP_BUILD="$MARKETING_VERSION ($CURRENT_PROJECT_VERSION)"
fi

section() {
  printf "\n== %s ==\n" "$1"
}

blocker() {
  BLOCKER_COUNT=$((BLOCKER_COUNT + 1))
  BLOCKER_MESSAGES+=("$1")
  printf "BLOCKER: %s\n" "$1"
}

source_commit() {
  git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || printf "unknown"
}

tracked_source_tree_status() {
  local tracked_changes

  if ! git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf "unavailable"
    return 0
  fi

  tracked_changes="$(git -C "$ROOT_DIR" status --porcelain --untracked-files=no 2>/dev/null || true)"
  if [[ -n "$tracked_changes" ]]; then
    printf "dirty"
  else
    printf "clean"
  fi
}

write_release_actions() {
  local status="$1"
  local action_path="$RELEASE_ACTIONS_FILE"

  if [[ -z "$action_path" ]]; then
    return 0
  fi

  if [[ "$action_path" != /* ]]; then
    action_path="$ROOT_DIR/$action_path"
  fi

  mkdir -p "$(dirname "$action_path")"
  {
    printf "# SoloPM Release Actions\n\n"
    case "$status" in
      not-ready)
        printf "Status: not-ready\n"
        ;;
      ready)
        printf "Status: ready\n"
        ;;
      *)
        printf "Status: %s\n" "$status"
        ;;
    esac
    printf "Generated at: %s\n" "$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf "Source commit: %s\n" "$(source_commit)"
    printf "Tracked source tree: %s\n" "$(tracked_source_tree_status)"
    printf "Blocker groups: %d\n\n" "$BLOCKER_COUNT"
    printf "This file is an action summary, not release evidence.\n"
    printf "It does not mark manual VoiceOver, competitor hands-on, signing, notarization, Sparkle, or Gatekeeper checks as passed.\n\n"

    printf "## Current Blocker Groups\n"
    if [[ "${#BLOCKER_MESSAGES[@]}" -eq 0 ]]; then
      printf -- "- [x] No blocker groups were recorded in this report run.\n"
    else
      for blocker_message in "${BLOCKER_MESSAGES[@]}"; do
        printf -- "- [ ] %s\n" "$blocker_message"
      done
    fi
    printf "\n"

    if [[ -n "$phase_implementation_unchecked" || -n "$phase_manual_unchecked" ]]; then
      printf "## Phase Checklist Items\n"
      if [[ -n "$phase_implementation_unchecked" ]]; then
        printf "Unchecked implementation phase items:\n"
        while IFS= read -r phase_item; do
          printf -- "- [ ] %s\n" "${phase_item#"$ROOT_DIR/"}"
        done <<<"$phase_implementation_unchecked"
        printf "\n"
      fi
      if [[ -n "$phase_manual_unchecked" ]]; then
        printf "Unchecked manual/release phase gates:\n"
        while IFS= read -r phase_item; do
          printf -- "- [ ] %s\n" "${phase_item#"$ROOT_DIR/"}"
        done <<<"$phase_manual_unchecked"
        printf "\n"
      fi
    fi

    printf "## Automated Proof Gates\n"
    if [[ "$AUTOMATED_PROOF_GATES" == "1" ]]; then
      printf -- "- Automated proof gates were requested in this report. Inspect the report output for pass/fail details before treating any automated gate as proven.\n"
    else
      printf -- "- Run: \`SOLOPM_AUTOMATED_PROOF_GATES=1 ./script/release_readiness_report.sh\`\n"
      printf -- "- Or produce clean-tree evidence: \`SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=.tmp/automated-release-preflight.md ./script/check_automated_release_preflight.sh\`\n"
    fi
    printf "\n"

    printf "## Manual VoiceOver\n"
    printf -- "- Run the source/runtime accessibility preflight first, then perform a real VoiceOver pass.\n"
    printf -- "- Generator command: \`./script/create_voiceover_evidence.sh --passed --capture-runtime-ax-smoke --confirm-manual-voiceover-pass ...\`\n"
    printf -- "- Required evidence stays manual: concrete Project navigation -> Project board detail -> Open task -> Inline Task Composer -> Status controls -> Task inspector observations.\n\n"

    printf "## Competitor Hands-On\n"
    printf -- "- Complete the 2-4 hour Notion, Todoist, Linear, and Motion hands-on pass before release.\n"
    printf -- "- Generator command: \`./script/create_competitor_hands_on_evidence.sh --passed --benchmark-output docs/product/competitor-benchmark.md --confirm-manual-hands-on ...\`\n"
    printf -- "- Record Ship / Defer / Reject decisions and keep external SaaS sync/team workflow outside public alpha scope.\n\n"

    printf "## Release Machine\n"
    printf -- "- Follow \`docs/release/checklist.md\` on the release machine.\n"
    printf -- "- Configure \`packaging/signing.env\`, \`packaging/notarization.env\`, production Sparkle feed/key, signed/notarized/stapled app, appcast metadata, and \`packaging/release-evidence.json\`.\n"
    printf -- "- Verify with \`./script/verify_release_environment.sh\` before expecting the readiness report to pass.\n"
  } >"$action_path"

  printf "Release action summary written to %s\n" "${action_path#"$ROOT_DIR/"}"
}

append_line() {
  local current="$1"
  local line="$2"

  if [[ -n "$current" ]]; then
    current+=$'\n'
  fi
  current+="$line"
  printf "%s" "$current"
}

is_placeholder_checked_by() {
  local normalized
  normalized="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]]+/ /g')"
  case "$normalized" in
    name|\
    reviewer|\
    "reviewer name"|\
    "release reviewer"|\
    "product reviewer"|\
    tester|\
    qa|\
    unknown|\
    tbd|\
    todo|\
    n/a|\
    na)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_boilerplate_voiceover_note() {
  local normalized
  normalized="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[[:punct:]]+/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]]+/ /g')"
  case "$normalized" in
    verified|\
    checked|\
    confirmed|\
    passed|\
    ok|\
    okay|\
    works|\
    "looks good"|\
    "all good"|\
    "no issue"|\
    "no issues"|\
    "concrete voiceover observation"*|\
    "manual pass complete"|\
    "manual pass completed")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_boilerplate_competitor_value() {
  local normalized
  normalized="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[[:punct:]]+/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]]+/ /g')"
  case "$normalized" in
    verified|\
    checked|\
    confirmed|\
    passed|\
    ok|\
    okay|\
    works|\
    "looks good"|\
    "all good"|\
    "no issue"|\
    "no issues"|\
    "hands on complete"|\
    "hands on completed"|\
    "manual pass complete"|\
    "manual pass completed"|\
    "concrete notion observation"*|\
    "concrete todoist observation"*|\
    "concrete linear observation"*|\
    "concrete motion observation"*|\
    "solopm public alpha behavior to ship based on the benchmark"|\
    "behavior to defer until stronger reliability or demand evidence exists"|\
    "behavior to keep out of public alpha scope")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_manual_phase_gate() {
  local item="$1"
  grep -Eiq '(手動確認|実機|支援技術|VoiceOver|hands-on|2-4[[:space:]]*hour|2-4時間|Developer ID|notarization|notarized|公証|Gatekeeper|clean environment|clean 環境|別ユーザー|login item|signed app|signed / notarized|署名|release-machine|manual evidence)' <<<"$item"
}

is_iso_date() {
  local value="$1"
  local normalized
  value="$(printf '%s' "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
  normalized="$(/bin/date -j -f '%Y-%m-%d' "$value" '+%Y-%m-%d' 2>/dev/null)" || return 1
  [[ "$normalized" == "$value" ]]
}

is_future_date() {
  local value="$1"
  local today
  value="$(printf '%s' "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  today="$(/bin/date '+%Y-%m-%d')"
  is_iso_date "$value" && [[ "$value" > "$today" ]]
}

assert_screenshot_has_visible_content() {
  local image_path="$1"
  /usr/bin/swift "$ROOT_DIR/script/ui_evidence_content_check.swift" "$image_path"
}

printf "SoloPM release readiness report\n"

if [[ "$AUTOMATED_PROOF_GATES" != "0" && "$AUTOMATED_PROOF_GATES" != "1" ]]; then
  blocker "SOLOPM_AUTOMATED_PROOF_GATES must be 0 or 1"
fi

section "Runtime mock/fake/fixture scan"
if ! command -v rg >/dev/null 2>&1; then
  blocker "rg is required for source scanning"
else
  missing_runtime_source=0
  for source_dir in "${RUNTIME_SOURCE_DIRS[@]}"; do
    if [[ ! -d "$source_dir" ]]; then
      blocker "missing runtime source directory: ${source_dir#"$ROOT_DIR/"}"
      missing_runtime_source=1
    fi
  done

  if [[ "$missing_runtime_source" -eq 0 ]]; then
    set +e
    scan_output="$(rg -n "$MOCK_PATTERN" "${RUNTIME_SOURCE_DIRS[@]}" 2>&1)"
    scan_status=$?
    set -e

    case "$scan_status" in
      0)
        printf "%s\n" "$scan_output"
        blocker "runtime source contains mock/fake/fixture/demo/test-only markers"
        ;;
      1)
        printf "OK: no runtime mock/fake/fixture/demo markers in Sources/SoloPMCore Sources/SoloPMApp Sources/SoloPMCLI\n"
        ;;
      *)
        if [[ -n "$scan_output" ]]; then
          printf "%s\n" "$scan_output"
        fi
        blocker "runtime mock/fake/fixture scan failed"
        ;;
    esac
  fi
fi

section "Release CI preflight"
release_ci_preflight_script="$ROOT_DIR/$RELEASE_CI_PREFLIGHT_RELATIVE"
if [[ "$RELEASE_CI_PREFLIGHT" != "0" && "$RELEASE_CI_PREFLIGHT" != "1" ]]; then
  blocker "SOLOPM_RELEASE_CI_PREFLIGHT must be 0 or 1"
elif [[ "$RELEASE_CI_PREFLIGHT" == "1" ]]; then
  if [[ ! -x "$release_ci_preflight_script" ]]; then
    blocker "missing executable release CI preflight: $RELEASE_CI_PREFLIGHT_RELATIVE"
  else
    set +e
    release_ci_preflight_output="$("$release_ci_preflight_script" 2>&1)"
    release_ci_preflight_status=$?
    set -e

    if [[ -n "$release_ci_preflight_output" ]]; then
      printf "%s\n" "$release_ci_preflight_output"
    fi

    if [[ "$release_ci_preflight_status" -ne 0 ]]; then
      blocker "release CI preflight failed"
    else
      printf "OK: release CI preflight passed\n"
    fi
  fi
else
  printf "INFO: release CI preflight skipped; set SOLOPM_RELEASE_CI_PREFLIGHT=1 to run %s inside this report.\n" "$RELEASE_CI_PREFLIGHT_RELATIVE"
  blocker "release CI preflight was not run"
fi

section "Local CRUD smoke"
local_crud_smoke_script="$ROOT_DIR/$LOCAL_CRUD_SMOKE_RELATIVE"
if [[ "$LOCAL_CRUD_SMOKE" != "0" && "$LOCAL_CRUD_SMOKE" != "1" ]]; then
  blocker "SOLOPM_LOCAL_CRUD_SMOKE must be 0 or 1"
elif [[ "$LOCAL_CRUD_SMOKE" == "1" ]]; then
  if [[ ! -x "$local_crud_smoke_script" ]]; then
    blocker "missing executable local CRUD smoke: $LOCAL_CRUD_SMOKE_RELATIVE"
  else
    set +e
    local_crud_smoke_output="$("$local_crud_smoke_script" 2>&1)"
    local_crud_smoke_status=$?
    set -e

    if [[ -n "$local_crud_smoke_output" ]]; then
      printf "%s\n" "$local_crud_smoke_output"
    fi

    if [[ "$local_crud_smoke_status" -ne 0 ]]; then
      blocker "local CRUD smoke failed"
    else
      printf "OK: local CRUD smoke passed\n"
    fi
  fi
else
  printf "INFO: local CRUD smoke skipped; set SOLOPM_LOCAL_CRUD_SMOKE=1 to run %s inside this report.\n" "$LOCAL_CRUD_SMOKE_RELATIVE"
  blocker "local CRUD smoke was not run"
fi

section "Runtime accessible CRUD smoke"
runtime_accessible_crud_smoke_script="$ROOT_DIR/$RUNTIME_ACCESSIBLE_CRUD_SMOKE_RELATIVE"
if [[ "$RUNTIME_ACCESSIBLE_CRUD_SMOKE" != "0" && "$RUNTIME_ACCESSIBLE_CRUD_SMOKE" != "1" ]]; then
  blocker "SOLOPM_RUNTIME_ACCESSIBLE_CRUD_SMOKE must be 0 or 1"
elif [[ "$RUNTIME_ACCESSIBLE_CRUD_SMOKE" == "1" ]]; then
  if [[ ! -x "$runtime_accessible_crud_smoke_script" ]]; then
    blocker "missing executable runtime accessible CRUD smoke: $RUNTIME_ACCESSIBLE_CRUD_SMOKE_RELATIVE"
  else
    set +e
    runtime_accessible_crud_smoke_output="$("$runtime_accessible_crud_smoke_script" 2>&1)"
    runtime_accessible_crud_smoke_status=$?
    set -e

    if [[ -n "$runtime_accessible_crud_smoke_output" ]]; then
      printf "%s\n" "$runtime_accessible_crud_smoke_output"
    fi

    if [[ "$runtime_accessible_crud_smoke_status" -ne 0 ]]; then
      blocker "runtime accessible CRUD smoke failed"
    else
      printf "OK: runtime accessible CRUD smoke passed\n"
    fi
  fi
else
  printf "INFO: runtime accessible CRUD smoke skipped; set SOLOPM_RUNTIME_ACCESSIBLE_CRUD_SMOKE=1 to run %s against the visible app and isolated SQLite database.\n" "$RUNTIME_ACCESSIBLE_CRUD_SMOKE_RELATIVE"
  blocker "runtime accessible CRUD smoke was not run"
fi

section "Release Xcode preflight"
xcode_workspace="$ROOT_DIR/$XCODE_WORKSPACE_RELATIVE"
if [[ "$RELEASE_XCODE_PREFLIGHT" != "0" && "$RELEASE_XCODE_PREFLIGHT" != "1" ]]; then
  blocker "SOLOPM_RELEASE_XCODE_PREFLIGHT must be 0 or 1"
elif [[ "$RELEASE_XCODE_PREFLIGHT" == "1" ]]; then
  if ! command -v xcodebuild >/dev/null 2>&1; then
    blocker "xcodebuild is required for release Xcode preflight"
  elif [[ ! -d "$xcode_workspace" ]]; then
    blocker "missing SwiftPM Xcode workspace: $XCODE_WORKSPACE_RELATIVE"
  else
    set +e
    release_xcode_preflight_output="$(
      xcodebuild \
        -workspace "$xcode_workspace" \
        -scheme "$XCODE_SCHEME" \
        -configuration Debug \
        -destination "$XCODE_DESTINATION" \
        build 2>&1
    )"
    release_xcode_preflight_status=$?
    set -e

    if [[ -n "$release_xcode_preflight_output" ]]; then
      printf "%s\n" "$release_xcode_preflight_output"
    fi

    if [[ "$release_xcode_preflight_status" -ne 0 ]]; then
      blocker "release Xcode preflight failed"
    else
      printf "OK: release Xcode preflight passed\n"
    fi
  fi
else
  printf "INFO: release Xcode preflight skipped; set SOLOPM_RELEASE_XCODE_PREFLIGHT=1 to run xcodebuild against %s.\n" "$XCODE_WORKSPACE_RELATIVE"
  blocker "release Xcode preflight was not run"
fi

section "Release launch preflight"
release_launch_preflight_script="$ROOT_DIR/$RELEASE_LAUNCH_PREFLIGHT_RELATIVE"
if [[ "$RELEASE_LAUNCH_PREFLIGHT" != "0" && "$RELEASE_LAUNCH_PREFLIGHT" != "1" ]]; then
  blocker "SOLOPM_RELEASE_LAUNCH_PREFLIGHT must be 0 or 1"
elif [[ "$RELEASE_LAUNCH_PREFLIGHT" == "1" ]]; then
  if [[ ! -x "$release_launch_preflight_script" ]]; then
    blocker "missing executable release launch preflight: $RELEASE_LAUNCH_PREFLIGHT_RELATIVE"
  else
    set +e
    release_launch_preflight_output="$("$release_launch_preflight_script" --verify 2>&1)"
    release_launch_preflight_status=$?
    set -e

    if [[ -n "$release_launch_preflight_output" ]]; then
      printf "%s\n" "$release_launch_preflight_output"
    fi

    if [[ "$release_launch_preflight_status" -ne 0 ]]; then
      blocker "release launch preflight failed"
    else
      printf "OK: release launch preflight passed\n"
    fi
  fi
else
  printf "INFO: release launch preflight skipped; set SOLOPM_RELEASE_LAUNCH_PREFLIGHT=1 to run %s --verify inside this report.\n" "$RELEASE_LAUNCH_PREFLIGHT_RELATIVE"
  blocker "release launch preflight was not run"
fi

section "Phase checklist blockers"
phase_implementation_unchecked=""
phase_manual_unchecked=""
if [[ -d "$ROOT_DIR/tasks" ]]; then
  while IFS= read -r phase_file; do
    phase_name="$(basename "$phase_file")"
    case "$phase_name" in
      Phase[0-9].md|Phase[0-9]-*.md|Phase10.md|Phase10-*.md|Phase11.md|Phase11-*.md)
        unchecked_items="$(rg -n --with-filename -- "- \\[ \\]" "$phase_file" || true)"
        if [[ -n "$unchecked_items" ]]; then
          while IFS= read -r unchecked_item; do
            if is_manual_phase_gate "$unchecked_item"; then
              phase_manual_unchecked="$(append_line "$phase_manual_unchecked" "$unchecked_item")"
            else
              phase_implementation_unchecked="$(append_line "$phase_implementation_unchecked" "$unchecked_item")"
            fi
          done <<<"$unchecked_items"
        fi
        ;;
    esac
  done < <(find "$ROOT_DIR/tasks" -maxdepth 1 -type f -name 'Phase*.md' | sort)
else
  blocker "missing tasks directory"
fi
readme_template_unchecked="$(rg -n -g '*.md' -- "- \\[ \\]" "$ROOT_DIR/tasks/README.md" || true)"

if [[ -n "$phase_implementation_unchecked" ]]; then
  printf "Unchecked implementation phase items:\n"
  printf "%s\n" "$phase_implementation_unchecked"
  blocker "phase checklist still has unchecked implementation tasks"
fi

if [[ -n "$phase_manual_unchecked" ]]; then
  printf "Unchecked manual/release phase gates:\n"
  printf "%s\n" "$phase_manual_unchecked"
  blocker "phase checklist still has unchecked manual/release gates"
fi

if [[ -z "$phase_implementation_unchecked" && -z "$phase_manual_unchecked" ]]; then
  printf "OK: no unchecked items in release phase checklists (Phase0-Phase11)\n"
fi

if [[ -n "$readme_template_unchecked" ]]; then
  printf "INFO: tasks/README.md contains unchecked template examples and is not counted as a release blocker.\n"
fi

section "UI screenshot evidence"
ui_evidence_file="$ROOT_DIR/$UI_EVIDENCE_RELATIVE"
ui_evidence_blocker_count=0
ui_blocker() {
  blocker "$1"
  ui_evidence_blocker_count=$((ui_evidence_blocker_count + 1))
}
if [[ ! -f "$ui_evidence_file" ]]; then
  ui_blocker "missing UI screenshot evidence file: $UI_EVIDENCE_RELATIVE"
else
  if ! grep -F 'Generated with `script/capture_ui_evidence.sh`.' "$ui_evidence_file" >/dev/null; then
    ui_blocker "UI screenshot evidence file was not generated by script/capture_ui_evidence.sh"
  fi
  if ! grep -F -- "- Generated at:" "$ui_evidence_file" >/dev/null; then
    ui_blocker "UI screenshot evidence is missing generated timestamp"
  fi
fi

for screenshot_entry in "${UI_SCREENSHOTS[@]}"; do
  screenshot_label="${screenshot_entry%%:*}"
  screenshot_filename="${screenshot_entry#*:}"
  screenshot_relative="$UI_SCREENSHOT_RELATIVE_DIR/$screenshot_filename"
  screenshot_path="$ROOT_DIR/$screenshot_relative"

  if [[ ! -f "$screenshot_path" ]]; then
    ui_blocker "missing UI screenshot file: $screenshot_relative"
    continue
  fi

  if [[ ! -s "$screenshot_path" ]]; then
    ui_blocker "empty UI screenshot file: $screenshot_relative"
    continue
  fi

  screenshot_bytes="$(wc -c <"$screenshot_path" | tr -d '[:space:]')"
  if [[ "$screenshot_bytes" -lt "$UI_SCREENSHOT_MIN_BYTES" ]]; then
    ui_blocker "UI screenshot is unexpectedly small ($screenshot_bytes bytes): $screenshot_relative"
    continue
  fi

  if [[ -f "$ui_evidence_file" ]] && ! grep -F "$screenshot_relative" "$ui_evidence_file" >/dev/null; then
    ui_blocker "UI screenshot evidence does not reference $screenshot_relative"
  fi

  set +e
  dimensions_output="$(/usr/bin/sips -g pixelWidth -g pixelHeight "$screenshot_path" 2>&1)"
  dimensions_status=$?
  set -e

  if [[ "$dimensions_status" -ne 0 ]]; then
    printf "%s\n" "$dimensions_output"
    ui_blocker "UI screenshot dimensions are unreadable: $screenshot_relative"
    continue
  fi

  pixel_width="$(awk '/pixelWidth:/ {print $2}' <<<"$dimensions_output" | tail -1)"
  pixel_height="$(awk '/pixelHeight:/ {print $2}' <<<"$dimensions_output" | tail -1)"
  if [[ ! "$pixel_width" =~ ^[0-9]+$ || ! "$pixel_height" =~ ^[0-9]+$ ]]; then
    ui_blocker "UI screenshot dimensions are missing: $screenshot_relative"
    continue
  fi

  if [[ "$pixel_width" -lt "$UI_SCREENSHOT_MIN_WIDTH" || "$pixel_height" -lt "$UI_SCREENSHOT_MIN_HEIGHT" ]]; then
    ui_blocker "UI screenshot dimensions are too small (${pixel_width}x${pixel_height}): $screenshot_relative"
    continue
  fi

  if ! command -v swift >/dev/null 2>&1; then
    ui_blocker "swift is required for UI screenshot content validation"
    continue
  fi

  set +e
  content_output="$(assert_screenshot_has_visible_content "$screenshot_path" 2>&1)"
  content_status=$?
  set -e

  if [[ "$content_status" -ne 0 ]]; then
    if [[ -n "$content_output" ]]; then
      printf "%s\n" "$content_output"
    fi
    ui_blocker "UI screenshot appears blank or too low contrast: $screenshot_relative"
    continue
  fi

  printf "OK: %s screenshot %s (%sx%s, %s bytes)\n" \
    "$screenshot_label" \
    "$screenshot_relative" \
    "$pixel_width" \
    "$pixel_height" \
    "$screenshot_bytes"
done
if [[ "$ui_evidence_blocker_count" -gt 0 ]]; then
  printf "NEXT: run script/capture_ui_evidence.sh --doctor, then run script/capture_ui_evidence.sh on a visible macOS session with Screen Recording permission; verify generated Project Board and MCP Settings PNGs before release.\n"
fi

section "VoiceOver accessibility evidence"
voiceover_evidence_file="$ROOT_DIR/$VOICEOVER_EVIDENCE_RELATIVE"
accessibility_preflight_script="$ROOT_DIR/$ACCESSIBILITY_PREFLIGHT_RELATIVE"
voiceover_evidence_blocker_count=0
voiceover_blocker() {
  blocker "$1"
  voiceover_evidence_blocker_count=$((voiceover_evidence_blocker_count + 1))
}
voiceover_context_value() {
  local context_label="$1"
  awk -v label="$context_label" '
    index($0, "- " label ":") == 1 {
      value = $0
      sub("^- " label ":[[:space:]]*", "", value)
      print value
      found = 1
      exit
    }
    END {
      if (found != 1) {
        exit 1
      }
    }
  ' "$voiceover_evidence_file" || true
}
voiceover_note_value() {
  local note_label="$1"
  awk -v label="$note_label" '
    index($0, "- " label ": passed -") == 1 {
      value = $0
      sub("^- " label ": passed -[[:space:]]*", "", value)
      print value
      found = 1
      exit
    }
    END {
      if (found != 1) {
        exit 1
      }
    }
  ' "$voiceover_evidence_file" || true
}
normalize_voiceover_context_value() {
  local context_value="$1"
  context_value="${context_value//\`/}"
  printf '%s' "$context_value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}
if [[ ! -x "$accessibility_preflight_script" ]]; then
  voiceover_blocker "missing executable accessibility source preflight: $ACCESSIBILITY_PREFLIGHT_RELATIVE"
else
  if [[ "$ACCESSIBILITY_RUNTIME_PREFLIGHT" != "0" && "$ACCESSIBILITY_RUNTIME_PREFLIGHT" != "1" ]]; then
    voiceover_blocker "SOLOPM_ACCESSIBILITY_RUNTIME_PREFLIGHT must be 0 or 1"
  fi

  set +e
  accessibility_preflight_output="$("$accessibility_preflight_script" --source-only 2>&1)"
  accessibility_preflight_status=$?
  set -e

  if [[ "$accessibility_preflight_status" -ne 0 ]]; then
    if [[ -n "$accessibility_preflight_output" ]]; then
      printf "%s\n" "$accessibility_preflight_output"
    fi
    voiceover_blocker "accessibility source preflight failed"
  else
    printf "%s\n" "$accessibility_preflight_output"
  fi

  if [[ "$ACCESSIBILITY_RUNTIME_PREFLIGHT" == "1" ]]; then
    set +e
    accessibility_runtime_preflight_output="$("$accessibility_preflight_script" --runtime --skip-source-anchors 2>&1)"
    accessibility_runtime_preflight_status=$?
    set -e
    accessibility_runtime_preflight_report_output="$(
      printf "%s\n" "$accessibility_runtime_preflight_output" |
        grep -Fxv "This is not a substitute for the manual VoiceOver pass." || true
    )"

    if [[ "$accessibility_runtime_preflight_status" -ne 0 ]]; then
      if [[ -n "$accessibility_runtime_preflight_report_output" ]]; then
        printf "%s\n" "$accessibility_runtime_preflight_report_output"
      fi
      voiceover_blocker "accessibility runtime preflight failed"
    else
      if [[ -n "$accessibility_runtime_preflight_report_output" ]]; then
        printf "%s\n" "$accessibility_runtime_preflight_report_output"
      fi
    fi
  else
    printf "INFO: accessibility runtime preflight skipped; set SOLOPM_ACCESSIBILITY_RUNTIME_PREFLIGHT=1 to include the visible AX smoke check.\n"
    blocker "accessibility runtime preflight was not run"
  fi
fi
if [[ ! -f "$voiceover_evidence_file" ]]; then
  voiceover_blocker "missing VoiceOver accessibility evidence file: $VOICEOVER_EVIDENCE_RELATIVE"
else
  for required_marker in "${VOICEOVER_REQUIRED_MARKERS[@]}"; do
    if [[ "$required_marker" == "Status: passed" ]]; then
      marker_present=0
      grep -Fx "Status: passed" "$voiceover_evidence_file" >/dev/null && marker_present=1
    else
      marker_present=0
      grep -F "$required_marker" "$voiceover_evidence_file" >/dev/null && marker_present=1
    fi

    if [[ "$marker_present" -ne 1 ]]; then
      case "$required_marker" in
        "Status: passed")
          voiceover_blocker "VoiceOver accessibility evidence is not marked passed"
          ;;
        *)
          voiceover_blocker "VoiceOver accessibility evidence is missing marker: $required_marker"
          ;;
      esac
    fi
  done

  if grep -Eiq '(pending|todo|tbd|placeholder|sample|example|replace me)' "$voiceover_evidence_file"; then
    voiceover_blocker "VoiceOver accessibility evidence still contains pending/template/placeholder text"
  fi
  if grep -F -- '- [ ]' "$voiceover_evidence_file" >/dev/null; then
    voiceover_blocker "VoiceOver accessibility evidence still contains unchecked checklist markers"
  fi

  for context_label in "${VOICEOVER_REQUIRED_CONTEXT_LABELS[@]}"; do
    context_value="$(voiceover_context_value "$context_label")"
    compact_context_value="$(tr -d '[:space:]' <<<"$context_value")"

    if [[ -z "$compact_context_value" ]]; then
      voiceover_blocker "VoiceOver accessibility evidence missing release context: $context_label"
      continue
    fi

    has_template_context=0
    grep -Eiq '(pending|todo|tbd|placeholder|sample|example|replace me|signed or release-candidate|VoiceOver/keyboard/device details|VoiceOver / keyboard / device details|manual pass environment|accessibility environment)' <<<"$context_value" && has_template_context=1
    [[ "$context_label" == "Checked by" ]] && is_placeholder_checked_by "$context_value" && has_template_context=1
    if [[ "$has_template_context" -eq 1 ]]; then
      voiceover_blocker "VoiceOver accessibility evidence has template release context: $context_label"
    fi

    if [[ "$context_label" == "Check date" ]] && ! is_iso_date "$context_value"; then
      voiceover_blocker "VoiceOver accessibility evidence has invalid release context date: $context_label"
    elif [[ "$context_label" == "Check date" ]] && is_future_date "$context_value"; then
      voiceover_blocker "VoiceOver accessibility evidence has future release context date: $context_label"
    fi

    if [[ "$context_label" == "Runtime AX smoke" ]]; then
      for runtime_marker in "OK: runtime AX smoke visible" "buttons=" "textFields=" "staticTexts=" "unlabeledButtons=0" "genericButtons=0" "crudSignals=8/8"; do
        if ! grep -F "$runtime_marker" <<<"$context_value" >/dev/null; then
          voiceover_blocker "VoiceOver accessibility evidence runtime AX smoke missing marker: $runtime_marker"
        fi
      done
    fi
  done

  for note_label in "${VOICEOVER_REQUIRED_NOTE_LABELS[@]}"; do
    note_value="$(voiceover_note_value "$note_label")"
    compact_note_value="$(tr -d '[:space:]' <<<"$note_value")"

    if [[ -z "$compact_note_value" ]]; then
      voiceover_blocker "VoiceOver accessibility evidence missing concrete focus note: $note_label"
      continue
    fi

    if grep -Eiq '(pending|todo|tbd|placeholder|sample|example|replace me)' <<<"$note_value"; then
      voiceover_blocker "VoiceOver accessibility evidence has template focus note: $note_label"
    elif is_boilerplate_voiceover_note "$note_value"; then
      voiceover_blocker "VoiceOver accessibility evidence has boilerplate focus note: $note_label"
    fi
  done

  if [[ -n "$EXPECTED_VOICEOVER_BUNDLE_IDENTIFIER" ]]; then
    voiceover_bundle_identifier="$(normalize_voiceover_context_value "$(voiceover_context_value "Bundle identifier")")"
    if [[ -n "$voiceover_bundle_identifier" && "$voiceover_bundle_identifier" != "$EXPECTED_VOICEOVER_BUNDLE_IDENTIFIER" ]]; then
      voiceover_blocker "VoiceOver accessibility evidence bundle identifier does not match packaging metadata: expected $EXPECTED_VOICEOVER_BUNDLE_IDENTIFIER"
    fi
  fi

  if [[ -n "$EXPECTED_VOICEOVER_APP_BUILD" ]]; then
    voiceover_app_build="$(normalize_voiceover_context_value "$(voiceover_context_value "App build")")"
    if [[ -n "$voiceover_app_build" && "$voiceover_app_build" != "$EXPECTED_VOICEOVER_APP_BUILD" ]]; then
      voiceover_blocker "VoiceOver accessibility evidence app build does not match packaging metadata: expected $EXPECTED_VOICEOVER_APP_BUILD"
    fi
  fi
fi
if [[ "$voiceover_evidence_blocker_count" -gt 0 ]]; then
  printf "NEXT: replace docs/release/evidence/accessibility-voiceover.md with a real VoiceOver pass by running ./script/create_voiceover_evidence.sh --passed with complete release-candidate context, --capture-runtime-ax-smoke, complete focus-path notes, and no pending/template/unchecked markers; the generated evidence must include the runtime AX smoke OK line with unlabeledButtons=0, genericButtons=0, and crudSignals=8/8.\n"
fi

section "Competitor hands-on evidence"
competitor_evidence_file="$ROOT_DIR/$COMPETITOR_EVIDENCE_RELATIVE"
competitor_evidence_blocker_count=0
competitor_template_pattern='(^|[^[:alnum:]_])(pending|todo|tbd|placeholder|sample|example)([^[:alnum:]_]|$)|replace me|macOS/browser versions|competitor app/account tiers|whether any paid trial'
competitor_blocker() {
  blocker "$1"
  competitor_evidence_blocker_count=$((competitor_evidence_blocker_count + 1))
}
competitor_context_value() {
  local context_label="$1"
  awk -v label="$context_label" '
    index($0, "- " label ":") == 1 {
      value = $0
      sub("^- " label ":[[:space:]]*", "", value)
      print value
      found = 1
      exit
    }
    END {
      if (found != 1) {
        exit 1
      }
    }
  ' "$competitor_evidence_file" || true
}
competitor_note_value() {
  local note_label="$1"
  awk -v label="$note_label" '
    index($0, "- " label ": passed -") == 1 {
      value = $0
      sub("^- " label ": passed -[[:space:]]*", "", value)
      print value
      found = 1
      exit
    }
    END {
      if (found != 1) {
        exit 1
      }
    }
  ' "$competitor_evidence_file" || true
}
competitor_decision_value() {
  local decision_label="$1"
  awk -v label="$decision_label" '
    index($0, "- " label ":") == 1 {
      value = $0
      sub("^- " label ":[[:space:]]*", "", value)
      print value
      found = 1
      exit
    }
    END {
      if (found != 1) {
        exit 1
      }
    }
  ' "$competitor_evidence_file" || true
}
competitor_benchmark_file="$ROOT_DIR/$COMPETITOR_BENCHMARK_RELATIVE"
if [[ ! -f "$competitor_evidence_file" ]]; then
  competitor_blocker "missing competitor hands-on evidence file: $COMPETITOR_EVIDENCE_RELATIVE"
else
  for required_marker in "${COMPETITOR_REQUIRED_MARKERS[@]}"; do
    if [[ "$required_marker" == "Status: passed" ]]; then
      marker_present=0
      grep -Fx "Status: passed" "$competitor_evidence_file" >/dev/null && marker_present=1
    else
      marker_present=0
      grep -F "$required_marker" "$competitor_evidence_file" >/dev/null && marker_present=1
    fi

    if [[ "$marker_present" -ne 1 ]]; then
      case "$required_marker" in
        "Status: passed")
          competitor_blocker "Competitor hands-on evidence is not marked passed"
          ;;
        *)
          competitor_blocker "Competitor hands-on evidence is missing marker: $required_marker"
          ;;
      esac
    fi
  done

  if grep -Eiq "$competitor_template_pattern" "$competitor_evidence_file"; then
    competitor_blocker "Competitor hands-on evidence still contains pending/template/placeholder text"
  fi
  if grep -F -- '- [ ]' "$competitor_evidence_file" >/dev/null; then
    competitor_blocker "Competitor hands-on evidence still contains unchecked checklist markers"
  fi

  for context_label in "${COMPETITOR_REQUIRED_CONTEXT_LABELS[@]}"; do
    context_value="$(competitor_context_value "$context_label")"
    compact_context_value="$(tr -d '[:space:]' <<<"$context_value")"

    if [[ -z "$compact_context_value" ]]; then
      competitor_blocker "Competitor hands-on evidence missing review context: $context_label"
      continue
    fi

    has_template_context=0
    grep -Eiq "$competitor_template_pattern" <<<"$context_value" && has_template_context=1
    [[ "$context_label" == "Checked by" ]] && is_placeholder_checked_by "$context_value" && has_template_context=1
    if [[ "$has_template_context" -eq 1 ]]; then
      competitor_blocker "Competitor hands-on evidence has template review context: $context_label"
    fi

    if [[ "$context_label" == "Check date" ]] && ! is_iso_date "$context_value"; then
      competitor_blocker "Competitor hands-on evidence has invalid review context date: $context_label"
    elif [[ "$context_label" == "Check date" ]] && is_future_date "$context_value"; then
      competitor_blocker "Competitor hands-on evidence has future review context date: $context_label"
    fi
  done

  for note_label in "${COMPETITOR_REQUIRED_NOTE_LABELS[@]}"; do
    note_value="$(competitor_note_value "$note_label")"
    compact_note_value="$(tr -d '[:space:]' <<<"$note_value")"

    if [[ -z "$compact_note_value" ]]; then
      competitor_blocker "Competitor hands-on evidence missing concrete note: $note_label"
      continue
    fi

    if grep -Eiq "$competitor_template_pattern" <<<"$note_value"; then
      competitor_blocker "Competitor hands-on evidence has template concrete note: $note_label"
    elif is_boilerplate_competitor_value "$note_value"; then
      competitor_blocker "Competitor hands-on evidence has boilerplate concrete note: $note_label"
    fi
  done

  for decision_label in "${COMPETITOR_REQUIRED_DECISION_LABELS[@]}"; do
    decision_value="$(competitor_decision_value "$decision_label")"
    compact_decision_value="$(tr -d '[:space:]' <<<"$decision_value")"

    if [[ -z "$compact_decision_value" ]]; then
      competitor_blocker "Competitor hands-on evidence missing decision delta: $decision_label"
      continue
    fi

    if grep -Eiq "$competitor_template_pattern" <<<"$decision_value"; then
      competitor_blocker "Competitor hands-on evidence has template decision delta: $decision_label"
    elif is_boilerplate_competitor_value "$decision_value"; then
      competitor_blocker "Competitor hands-on evidence has boilerplate decision delta: $decision_label"
    fi
  done
fi
if [[ ! -f "$competitor_benchmark_file" ]]; then
  competitor_blocker "missing competitor benchmark document: $COMPETITOR_BENCHMARK_RELATIVE"
else
  if grep -Eiq '(not a full hands-on trial record|release candidate hands-on worksheet|manual evidence to attach after the pass)' "$competitor_benchmark_file"; then
    competitor_blocker "Competitor benchmark still reads as desk research or a hands-on worksheet"
  fi

  for benchmark_marker in "## Hands-On Findings" "Notion" "Todoist" "Linear" "Motion" "Ship / Defer / Reject"; do
    if ! grep -F "$benchmark_marker" "$competitor_benchmark_file" >/dev/null; then
      competitor_blocker "Competitor benchmark missing hands-on marker: $benchmark_marker"
    fi
  done
fi
if [[ "$competitor_evidence_blocker_count" -gt 0 ]]; then
  printf "NEXT: replace docs/release/evidence/competitor-hands-on.md with a real 2-4 hour hands-on pass by running ./script/create_competitor_hands_on_evidence.sh --passed with complete reviewer/date/source/environment context, complete Notion/Todoist/Linear/Motion notes, Ship/Defer/Reject deltas, --benchmark-output docs/product/competitor-benchmark.md, and no pending/template/unchecked markers; the generator also updates docs/product/competitor-benchmark.md from worksheet/desk research to hands-on findings.\n"
else
  printf "OK: competitor hands-on evidence covers Notion, Todoist, Linear, Motion, and public alpha scope boundaries\n"
fi

section "MCP Inspector evidence"
mcp_compliance_script="$ROOT_DIR/$MCP_COMPLIANCE_RELATIVE"
if [[ ! -x "$mcp_compliance_script" ]]; then
  blocker "missing executable MCP compliance verifier: $MCP_COMPLIANCE_RELATIVE"
else
  mcp_runtime_evidence_file="$(mktemp)"
  set +e
  mcp_compliance_output="$(SOLOPM_MCP_EVIDENCE_FILE="$mcp_runtime_evidence_file" "$mcp_compliance_script" 2>&1)"
  mcp_compliance_status=$?
  set -e

  printf "%s\n" "$mcp_compliance_output"
  if [[ "$mcp_compliance_status" -ne 0 ]]; then
    blocker "MCP compliance verifier failed"
  elif [[ ! -f "$mcp_runtime_evidence_file" ]]; then
    blocker "MCP compliance verifier did not write runtime evidence"
  else
    mcp_runtime_missing_marker_count=0
    for required_marker in "${MCP_EVIDENCE_REQUIRED_MARKERS[@]}"; do
      if ! grep -F "$required_marker" "$mcp_runtime_evidence_file" >/dev/null; then
        blocker "MCP compliance verifier output is missing marker: $required_marker"
        mcp_runtime_missing_marker_count=$((mcp_runtime_missing_marker_count + 1))
      fi
    done

    if [[ "$mcp_runtime_missing_marker_count" -eq 0 ]]; then
      printf "OK: MCP compliance verifier passed\n"
    fi
  fi
  rm -f "$mcp_runtime_evidence_file"
fi

mcp_evidence_file="$ROOT_DIR/$MCP_EVIDENCE_RELATIVE"
if [[ ! -f "$mcp_evidence_file" ]]; then
  blocker "missing MCP Inspector evidence file: $MCP_EVIDENCE_RELATIVE"
else
  mcp_missing_marker_count=0
  for required_marker in "${MCP_EVIDENCE_REQUIRED_MARKERS[@]}"; do
    if ! grep -F "$required_marker" "$mcp_evidence_file" >/dev/null; then
      blocker "MCP Inspector evidence is missing marker: $required_marker"
      mcp_missing_marker_count=$((mcp_missing_marker_count + 1))
    fi
  done
  if [[ "$mcp_missing_marker_count" -eq 0 ]]; then
    printf "OK: MCP Inspector evidence covers stable baseline, draft boundary, tools/list, tools/call, and failure taxonomy\n"
  fi
fi

section "Release environment preflight"
set +e
preflight_output="$("$ROOT_DIR/script/verify_release_environment.sh" 2>&1)"
preflight_status=$?
set -e

printf "%s\n" "$preflight_output"
if [[ "$preflight_status" -ne 0 ]]; then
  blocker "release environment preflight did not pass"
  printf "NEXT: complete docs/release/checklist.md release-machine steps: configure packaging/signing.env, packaging/notarization.env, production Sparkle feed/key, signed/notarized app, appcast, and packaging/release-evidence.json; then rerun ./script/release_readiness_report.sh.\n"
else
  printf "OK: release environment preflight passed\n"
fi

section "Summary"
if [[ "$BLOCKER_COUNT" -gt 0 ]]; then
  write_release_actions "not-ready"
  printf "NOT READY: %d blocker group(s) remain.\n" "$BLOCKER_COUNT"
  exit 2
fi

write_release_actions "ready"
printf "READY: runtime, task checklist, automated proof gates, and release environment gates passed.\n"
