#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BLOCKER_COUNT=0
BLOCKER_MESSAGES=()
RELEASE_ENVIRONMENT_BLOCKER_MESSAGES=()
VOICEOVER_ACTION_BLOCKERS=()
COMPETITOR_ACTION_BLOCKERS=()
APP_METADATA_FILE="$ROOT_DIR/packaging/app_metadata.env"
RELEASE_ACTIONS_FILE="${SOLOPM_RELEASE_ACTIONS_FILE:-}"
AUTOMATED_PROOF_GATES="${SOLOPM_AUTOMATED_PROOF_GATES:-0}"
AUTOMATED_PREFLIGHT_EVIDENCE_FILE="${SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE:-}"
AUTOMATED_PREFLIGHT_EVIDENCE_VALID=0
AUTOMATED_PREFLIGHT_EVIDENCE_PATH=""
AUTOMATED_PREFLIGHT_EVIDENCE_REASON=""
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
XCODE_CONFIGURATION="${SOLOPM_XCODE_CONFIGURATION:-Debug}"
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
MCP_REVIEW_RELATIVE="docs/mcp-compliance.md"
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
  "Settings Appearance Light:settings-appearance-light.png"
  "Settings Appearance Dark:settings-appearance-dark.png"
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
  "Source commit"
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
  "Source commit"
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
  "Stable extension watchlist: Enterprise-Managed Authorization stable on 2026-06-18"
  "Enterprise-Managed Authorization source: https://blog.modelcontextprotocol.io/posts/enterprise-managed-auth/"
  "EMA remote authorization is not a SoloPM public-alpha release target"
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
MCP_REVIEW_REQUIRED_MARKERS=(
  'Stable baseline: `2025-11-25`'
  'Official stable latest: `2025-11-25`'
  "Stable extension watchlist: Enterprise-Managed Authorization stable on 2026-06-18"
  "Enterprise-Managed Authorization source: https://blog.modelcontextprotocol.io/posts/enterprise-managed-auth/"
  "EMA remote authorization is not a SoloPM public-alpha release target"
  "MCP specification 2025-11-25: https://modelcontextprotocol.io/specification/2025-11-25"
  'Draft watchlist: `2026-07-28`'
  "Draft versioning watchlist: https://modelcontextprotocol.io/specification/draft/basic/versioning"
  "Draft discovery watchlist: https://modelcontextprotocol.io/specification/draft/server/discover"
  "SoloPM does not send per-request protocol metadata"
  "server/discover"
  "will not claim draft or full-host compatibility"
  "not a full MCP host"
  "client-side stdio Tools"
)
AUTOMATED_PREFLIGHT_REQUIRED_GATES=(
  "Release CI"
  "Local CRUD smoke"
  "Runtime accessible CRUD smoke"
  "Xcode build preflight"
  "Launch preflight"
  "Runtime accessibility preflight"
  "MCP compliance preflight"
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
EXPECTED_AUTOMATED_PREFLIGHT_APP_NAME="${APP_NAME:-SoloPM}"
EXPECTED_AUTOMATED_PREFLIGHT_XCODE_WORKSPACE="$XCODE_WORKSPACE_RELATIVE"
EXPECTED_AUTOMATED_PREFLIGHT_XCODE_SCHEME="$XCODE_SCHEME"
EXPECTED_AUTOMATED_PREFLIGHT_XCODE_CONFIGURATION="$XCODE_CONFIGURATION"
EXPECTED_AUTOMATED_PREFLIGHT_XCODE_DESTINATION="$XCODE_DESTINATION"

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

blocker_bucket_for_message() {
  local message="$1"

  case "$message" in
    *"automated preflight"*|*"release CI preflight"*|*"local CRUD smoke"*|*"runtime accessible CRUD smoke"*|*"release Xcode preflight"*|*"release launch preflight"*|*"accessibility runtime preflight"*|*"UI screenshot"*|*"MCP compliance"*)
      printf "Automated Proof Gates"
      ;;
    *"VoiceOver"*|*"accessibility"*)
      printf "Manual VoiceOver"
      ;;
    *"Competitor"*|*"competitor"*|*"benchmark"*)
      printf "Competitor Hands-On"
      ;;
    *"phase checklist"*)
      printf "Phase Checklist"
      ;;
    *"release environment"*|*"signing"*|*"notarization"*|*"notarized"*|*"Sparkle"*|*"Gatekeeper"*)
      printf "Release Machine"
      ;;
    *)
      printf "Other"
      ;;
  esac
}

write_blocker_bucket_line() {
  local label="$1"
  local count="$2"
  local marker="x"

  if [[ "$count" -gt 0 ]]; then
    marker=" "
  fi

  printf -- "- [%s] %s: %d blocker group(s)\n" "$marker" "$label" "$count"
}

write_blocker_bucket_summary() {
  local automated_count=0
  local voiceover_count=0
  local competitor_count=0
  local release_machine_count=0
  local phase_count=0
  local other_count=0
  local blocker_message
  local blocker_bucket

  for blocker_message in "${BLOCKER_MESSAGES[@]}"; do
    blocker_bucket="$(blocker_bucket_for_message "$blocker_message")"
    case "$blocker_bucket" in
      "Automated Proof Gates")
        ((automated_count += 1))
        ;;
      "Manual VoiceOver")
        ((voiceover_count += 1))
        ;;
      "Competitor Hands-On")
        ((competitor_count += 1))
        ;;
      "Release Machine")
        ((release_machine_count += 1))
        ;;
      "Phase Checklist")
        ((phase_count += 1))
        ;;
      *)
        ((other_count += 1))
        ;;
    esac
  done

  printf "## Blocker Buckets\n"
  write_blocker_bucket_line "Automated Proof Gates" "$automated_count"
  write_blocker_bucket_line "Manual VoiceOver" "$voiceover_count"
  write_blocker_bucket_line "Competitor Hands-On" "$competitor_count"
  write_blocker_bucket_line "Release Machine" "$release_machine_count"
  write_blocker_bucket_line "Phase Checklist" "$phase_count"
  write_blocker_bucket_line "Other" "$other_count"
  printf "\n"
}

has_runtime_product_source_blocker() {
  local blocker_message

  for blocker_message in "${BLOCKER_MESSAGES[@]}"; do
    case "$blocker_message" in
      *"runtime mock/fake/fixture scan failed"*|*"missing runtime source directory"*)
        return 0
        ;;
    esac
  done

  return 1
}

has_local_product_gate_blocker() {
  local blocker_message

  for blocker_message in "${BLOCKER_MESSAGES[@]}"; do
    case "$blocker_message" in
      *"automated preflight"*|\
      *"release CI preflight"*|\
      *"local CRUD smoke"*|\
      *"runtime accessible CRUD smoke"*|\
      *"release Xcode preflight"*|\
      *"release launch preflight"*|\
      *"accessibility runtime preflight"*|\
      *"MCP compliance"*)
        return 0
        ;;
    esac
  done

  return 1
}

write_local_product_gate_status() {
  printf "## Local Product Gate Status\n"
  if automated_preflight_evidence_covers "Release CI" &&
    ! has_local_product_gate_blocker &&
    ! has_runtime_product_source_blocker; then
    printf -- "- [x] Local product gates are green for this source commit.\n"
    printf -- "- [x] Runtime source scan has no mock/fake/fixture/demo markers in SoloPM app targets.\n"
    printf -- "- [x] MCP compliance, SQLite data CRUD, visible-app accessible CRUD, Xcode build, launch, and runtime AX proof are covered by accepted automated preflight evidence.\n"
    printf -- "- [ ] Remaining gates are manual VoiceOver, competitor hands-on, and release-machine signing/notarization/Sparkle/Gatekeeper evidence.\n"
  else
    printf -- "- [ ] Local product gates are not fully proven for this source commit.\n"
    if ! automated_preflight_evidence_covers "Release CI"; then
      printf -- "- [ ] Automated preflight evidence is missing or invalid; run \`script/check_automated_release_preflight.sh\` on a clean tracked source tree.\n"
    fi
    if has_local_product_gate_blocker; then
      printf -- "- [ ] One or more local proof gates still has blocker groups; inspect Current Blocker Groups before claiming MCP/data/CRUD readiness.\n"
    fi
    if has_runtime_product_source_blocker; then
      printf -- "- [ ] Runtime source scan still has product-source blockers; remove runtime mock/fake/fixture/demo paths before release.\n"
    fi
  fi
  printf "\n"
}

collect_release_environment_blockers() {
  local output="$1"
  local line
  local normalized
  local lowered
  local root_prefix="$ROOT_DIR/"

  RELEASE_ENVIRONMENT_BLOCKER_MESSAGES=()

  while IFS= read -r line; do
    normalized="${line#- }"
    if [[ "$normalized" != BLOCKER:* ]]; then
      continue
    fi

    normalized="${normalized#BLOCKER: }"
    normalized="${normalized//$root_prefix/}"
    lowered="$(printf "%s" "$normalized" | tr '[:upper:]' '[:lower:]')"
    case "$lowered" in
      *password*|*token*|*secret*)
        normalized="release environment blocker contained a sensitive field; inspect verify_release_environment.sh output locally"
        ;;
    esac
    RELEASE_ENVIRONMENT_BLOCKER_MESSAGES+=("$normalized")
  done <<<"$output"
}

release_environment_route_for_blocker() {
  local blocker_message="$1"
  local lowered

  lowered="$(printf "%s" "$blocker_message" | tr '[:upper:]' '[:lower:]')"
  case "$lowered" in
    *"sensitive field"*|*"inspect verify_release_environment.sh output locally"*)
      printf "Local Inspection"
      ;;
    *"source tree"*|*"tracked source"*)
      printf "Source Hygiene"
      ;;
    *"notarization"*|*"notary"*|*"notarize"*)
      printf "Notarization"
      ;;
    *"gatekeeper"*|*"stapled"*|*"stapler"*)
      printf "Gatekeeper / Stapling"
      ;;
    *"sparkle"*|*"appcast"*|*"sufeedurl"*|*"supublicedkey"*|*"edsignature"*|*"enclosure"*)
      printf "Sparkle / Appcast"
      ;;
    *"release evidence"*|*"package evidence"*|*"manual checks"*|*"create_release_evidence"*)
      printf "Release Evidence"
      ;;
    *"signing"*|*"developer id"*|*"codesign"*|*"hardened runtime"*|*"entitlements"*)
      printf "Signing Configuration"
      ;;
    *)
      printf "Local Inspection"
      ;;
  esac
}

write_release_environment_route_group() {
  local label="$1"
  local items="$2"
  local item

  if [[ -z "$items" ]]; then
    return 0
  fi

  printf "%s blockers:\n" "$label"
  while IFS= read -r item; do
    [[ -z "$item" ]] && continue
    printf -- "- [ ] %s\n" "$item"
  done <<<"$items"
  printf "\n"
}

write_release_environment_routes() {
  local blocker_message
  local route
  local signing_items=""
  local notarization_items=""
  local sparkle_items=""
  local gatekeeper_items=""
  local evidence_items=""
  local source_hygiene_items=""
  local local_inspection_items=""

  if [[ "${#RELEASE_ENVIRONMENT_BLOCKER_MESSAGES[@]}" -eq 0 ]]; then
    return 0
  fi

  for blocker_message in "${RELEASE_ENVIRONMENT_BLOCKER_MESSAGES[@]}"; do
    route="$(release_environment_route_for_blocker "$blocker_message")"
    case "$route" in
      "Signing Configuration")
        signing_items="$(append_line "$signing_items" "$blocker_message")"
        ;;
      "Notarization")
        notarization_items="$(append_line "$notarization_items" "$blocker_message")"
        ;;
      "Sparkle / Appcast")
        sparkle_items="$(append_line "$sparkle_items" "$blocker_message")"
        ;;
      "Gatekeeper / Stapling")
        gatekeeper_items="$(append_line "$gatekeeper_items" "$blocker_message")"
        ;;
      "Release Evidence")
        evidence_items="$(append_line "$evidence_items" "$blocker_message")"
        ;;
      "Source Hygiene")
        source_hygiene_items="$(append_line "$source_hygiene_items" "$blocker_message")"
        ;;
      *)
        local_inspection_items="$(append_line "$local_inspection_items" "$blocker_message")"
        ;;
    esac
  done

  printf "## Release Environment Routes\n"
  write_release_environment_route_group "Signing Configuration" "$signing_items"
  write_release_environment_route_group "Notarization" "$notarization_items"
  write_release_environment_route_group "Sparkle / Appcast" "$sparkle_items"
  write_release_environment_route_group "Gatekeeper / Stapling" "$gatekeeper_items"
  write_release_environment_route_group "Release Evidence" "$evidence_items"
  write_release_environment_route_group "Source Hygiene" "$source_hygiene_items"
  write_release_environment_route_group "Local Inspection" "$local_inspection_items"
}

collect_manual_action_blocker() {
  local action_group="$1"
  local message="$2"

  case "$action_group" in
    voiceover)
      VOICEOVER_ACTION_BLOCKERS+=("$message")
      ;;
    competitor)
      COMPETITOR_ACTION_BLOCKERS+=("$message")
      ;;
  esac
}

write_manual_evidence_blocker_actions() {
  local manual_blocker

  if [[ "${#VOICEOVER_ACTION_BLOCKERS[@]}" -gt 0 ]]; then
    printf "## Manual VoiceOver Blockers\n"
    for manual_blocker in "${VOICEOVER_ACTION_BLOCKERS[@]}"; do
      printf -- "- [ ] %s\n" "$manual_blocker"
    done
    printf "\n"
  fi

  if [[ "${#COMPETITOR_ACTION_BLOCKERS[@]}" -gt 0 ]]; then
    printf "## Competitor Hands-On Blockers\n"
    for manual_blocker in "${COMPETITOR_ACTION_BLOCKERS[@]}"; do
      printf -- "- [ ] %s\n" "$manual_blocker"
    done
    printf "\n"
  fi
}

write_automated_proof_gate_actions() {
  local required_gate

  printf "## Automated Proof Gates\n"
  if automated_preflight_evidence_covers "Release CI"; then
    printf -- "- [x] Automated preflight evidence accepted: \`%s\`\n" "${AUTOMATED_PREFLIGHT_EVIDENCE_PATH#"$ROOT_DIR/"}"
    printf -- "- Source commit: \`%s\`\n" "$(automated_preflight_context_value "Source commit")"
    printf -- "- Generated at: \`%s\`\n" "$(automated_preflight_context_value "Generated at")"
    printf -- "- This proves local automated gates only; it does not mark manual VoiceOver, competitor hands-on, signing, notarization, Sparkle, or Gatekeeper checks as passed.\n"
    for required_gate in "${AUTOMATED_PREFLIGHT_REQUIRED_GATES[@]}"; do
      printf -- "- [x] %s: passed\n" "$required_gate"
    done
  elif [[ "$AUTOMATED_PROOF_GATES" == "1" ]]; then
    printf -- "- Automated proof gates were requested in this report. Inspect the report output for pass/fail details before treating any automated gate as proven.\n"
  else
    printf -- "- Run: \`SOLOPM_AUTOMATED_PROOF_GATES=1 ./script/release_readiness_report.sh\`\n"
    printf -- "- Or reuse clean-tree evidence in the report: \`SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=.tmp/automated-release-preflight.md ./script/release_readiness_report.sh\`\n"
    printf -- "- Or produce clean-tree evidence: \`SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=.tmp/automated-release-preflight.md ./script/check_automated_release_preflight.sh\`\n"
  fi
  printf "\n"
}

write_voiceover_manual_evidence_command() {
  printf '%s\n' '```bash'
  printf '%s\n' './script/create_voiceover_evidence.sh --passed \'
  printf '%s\n' '  --checked-by "<reviewer name>" \'
  printf '%s\n' '  --accessibility-environment "<macOS version, hardware, VoiceOver input method, clean user/install context>" \'
  printf '%s\n' '  --capture-runtime-ax-smoke \'
  printf '%s\n' '  --project-navigation-note "<VoiceOver observation for sidebar project navigation>" \'
  printf '%s\n' '  --project-board-detail-note "<VoiceOver observation for selected project board context>" \'
  printf '%s\n' '  --open-task-note "<VoiceOver observation for focusing a task card and opening details>" \'
  printf '%s\n' '  --inline-task-composer-note "<VoiceOver observation for title/detail/priority/due create flow>" \'
  printf '%s\n' '  --status-controls-note "<VoiceOver observation for previous/next status controls>" \'
  printf '%s\n' '  --task-inspector-note "<VoiceOver observation for inspector fields and actions>" \'
  printf '%s\n' '  --save-changes-note "<VoiceOver observation proving keyboard activation saves local changes>" \'
  printf '%s\n' '  --delete-confirmation-note "<VoiceOver observation proving destructive confirmation appears before deletion>" \'
  printf '%s\n' '  --no-keyboard-trap-note "<VoiceOver observation proving focus leaves sidebar, board, inspector, and dialogs>" \'
  printf '%s\n' '  --no-unlabeled-crud-note "<VoiceOver observation proving primary CRUD controls have labels or help>" \'
  printf '%s\n' '  --confirm-manual-voiceover-pass'
  printf '%s\n' '```'
}

write_competitor_hands_on_evidence_command() {
  printf '%s\n' '```bash'
  printf '%s\n' './script/create_competitor_hands_on_evidence.sh --passed \'
  printf '%s\n' '  --checked-by "<reviewer name>" \'
  printf '%s\n' '  --environment "<macOS/browser versions, competitor account tiers, paid trial status>" \'
  printf '%s\n' '  --notion-note "<hands-on Notion project database, board, task, and artifact observation>" \'
  printf '%s\n' '  --todoist-note "<hands-on Todoist quick add, board/list, drag movement, Today/Upcoming observation>" \'
  printf '%s\n' '  --linear-note "<hands-on Linear project/issue/status/sidebar/keyboard command observation>" \'
  printf '%s\n' '  --motion-note "<hands-on Motion dated task, prioritization, schedule/risk explanation observation>" \'
  printf '%s\n' '  --ship "<SoloPM behavior to ship now based on the hands-on benchmark>" \'
  printf '%s\n' '  --defer "<behavior deferred until reliability or demand evidence is stronger>" \'
  printf '%s\n' '  --reject "<behaviors deliberately kept out of public alpha scope>" \'
  printf '%s\n' '  --benchmark-output docs/product/competitor-benchmark.md \'
  printf '%s\n' '  --confirm-manual-hands-on'
  printf '%s\n' '```'
}

phase_manual_unchecked_has_login_item_gate() {
  if [[ -z "$phase_manual_unchecked" ]]; then
    return 1
  fi

  grep -Eiq 'login item|launch at login|ログイン' <<<"$phase_manual_unchecked"
}

write_release_evidence_login_item_command() {
  printf '%s\n' '```bash'
  printf '%s\n' 'SOLOPM_RELEASE_ARTIFACT_SHA256_FILE="<path to generated DMG .sha256>" \'
  printf '%s\n' './script/create_release_evidence.sh --force \'
  printf '%s\n' '  --release-machine-launch \'
  printf '%s\n' '  --checksum-verification \'
  printf '%s\n' '  --clean-dmg-install \'
  printf '%s\n' '  --applications-folder-install \'
  printf '%s\n' '  --gatekeeper-accepted \'
  printf '%s\n' '  --clean-environment-launch \'
  printf '%s\n' '  --login-item-toggle \'
  printf '%s\n' '  --sparkle-appcast-metadata \'
  printf '%s\n' '  --manual-environment "<macOS version, hardware, clean user or VM/install context>" \'
  printf '%s\n' '  --checked-by "<reviewer name>" \'
  printf '%s\n' '  --note "<concrete note covering Settings launch-at-login toggle on and off in the signed app>"'
  printf '%s\n' '```'
}

write_release_machine_runbook_command() {
  printf '%s\n' '```bash'
  printf '%s\n' '# 1. Configure local release secrets; these files stay on the release machine.'
  printf '%s\n' '[ -f packaging/signing.env ] || cp packaging/signing.env.example packaging/signing.env'
  printf '%s\n' '[ -f packaging/notarization.env ] || cp packaging/notarization.env.example packaging/notarization.env'
  printf '%s\n' '[ -f packaging/sparkle.env ] || cp packaging/sparkle.env.example packaging/sparkle.env'
  printf '%s\n' '$EDITOR packaging/signing.env packaging/notarization.env packaging/sparkle.env'
  printf '%s\n' ''
  printf '%s\n' '# 2. Validate signing and notarization prerequisites.'
  printf '%s\n' './script/verify_signing_setup.sh'
  printf '%s\n' 'SOLOPM_RELEASE_PREFLIGHT_ONLINE=1 ./script/verify_notarization_setup.sh'
  printf '%s\n' ''
  printf '%s\n' '# 3. Build, sign, notarize, and package both user download and Sparkle artifacts.'
  printf '%s\n' 'SOLOPM_BUILD_CONFIGURATION=release ./script/build_and_run.sh --build-only'
  printf '%s\n' './script/sign_app.sh'
  printf '%s\n' './script/notarize_app.sh'
  printf '%s\n' 'SOLOPM_PACKAGE_FORMAT=all ./script/package_release.sh'
  printf '%s\n' ''
  printf '%s\n' '# 4. Generate and verify the release appcast.'
  printf '%s\n' 'SOLOPM_REQUIRE_RELEASE_APPCAST=1 ./script/generate_appcast.sh'
  printf '%s\n' 'SOLOPM_REQUIRE_RELEASE_APPCAST=1 ./script/verify_appcast.sh dist/releases/appcast.xml'
  printf '%s\n' ''
  printf '%s\n' '# 5. Bind manual release evidence to the generated DMG checksum.'
  printf '%s\n' 'source packaging/app_metadata.env'
  printf '%s\n' 'export SOLOPM_RELEASE_ARTIFACT_SHA256_FILE="dist/releases/SoloPM-$MARKETING_VERSION+$CURRENT_PROJECT_VERSION.dmg.sha256"'
  printf '%s\n' './script/create_release_evidence.sh --force \'
  printf '%s\n' '  --release-machine-launch \'
  printf '%s\n' '  --checksum-verification \'
  printf '%s\n' '  --clean-dmg-install \'
  printf '%s\n' '  --applications-folder-install \'
  printf '%s\n' '  --gatekeeper-accepted \'
  printf '%s\n' '  --clean-environment-launch \'
  printf '%s\n' '  --login-item-toggle \'
  printf '%s\n' '  --sparkle-appcast-metadata \'
  printf '%s\n' '  --manual-environment "<macOS version, hardware, clean user or VM/install context>" \'
  printf '%s\n' '  --checked-by "<reviewer name>" \'
  printf '%s\n' '  --note "<concrete note covering every enabled manual release flag>"'
  printf '%s\n' ''
  printf '%s\n' '# 6. Final release-machine validation.'
  printf '%s\n' 'SOLOPM_RELEASE_PREFLIGHT_ONLINE=1 ./script/verify_release_environment.sh'
  printf '%s\n' '```'
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

    write_blocker_bucket_summary

    write_local_product_gate_status

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

    write_phase_manual_gate_routes

    if [[ "${#RELEASE_ENVIRONMENT_BLOCKER_MESSAGES[@]}" -gt 0 ]]; then
      printf "## Release Environment Blockers\n"
      for release_environment_blocker in "${RELEASE_ENVIRONMENT_BLOCKER_MESSAGES[@]}"; do
        printf -- "- [ ] %s\n" "$release_environment_blocker"
      done
      printf "\n"
      write_release_environment_routes
    fi

    write_manual_evidence_blocker_actions

    write_automated_proof_gate_actions

    printf "## Manual VoiceOver\n"
    printf -- "- Run the source/runtime accessibility preflight first, then perform a real VoiceOver pass.\n"
    printf -- "- Replace every placeholder below with concrete observations from the real release-candidate app before running it.\n\n"
    write_voiceover_manual_evidence_command
    printf "\n"
    printf -- "- Required evidence stays manual: concrete Project navigation -> Project board detail -> Open task -> Inline Task Composer -> Status controls -> Task inspector observations.\n\n"

    printf "## Competitor Hands-On\n"
    printf -- "- Complete the 2-4 hour Notion, Todoist, Linear, and Motion hands-on pass before release.\n"
    printf -- "- Replace every placeholder below with concrete observations and Ship / Defer / Reject decisions before running it.\n\n"
    write_competitor_hands_on_evidence_command
    printf "\n"
    printf -- "- Record Ship / Defer / Reject decisions and keep external SaaS sync/team workflow outside public alpha scope.\n\n"

    if phase_manual_unchecked_has_login_item_gate; then
      printf "## Login Item Manual Check\n"
      printf -- "- Login item evidence is recorded through \`script/create_release_evidence.sh\`, not a standalone checkbox.\n"
      printf -- "- Use the signed and notarized app installed from the release artifact, toggle Launch at Login on and off in Settings, and record the concrete environment/note.\n"
      printf -- "- This command also binds the login item evidence to the packaged artifact, Developer ID signing context, notary profile, Sparkle metadata, and current source commit.\n\n"
      write_release_evidence_login_item_command
      printf "\n"
      printf -- "- Do not mark Phase4 login item complete until \`verify_release_environment.sh\` accepts \`manualChecks.loginItemToggle=true\` from this evidence.\n\n"
    fi

    printf "## Release Machine\n"
    printf -- "- Follow \`docs/release/checklist.md\` on the release machine.\n"
    printf -- "- Configure \`packaging/signing.env\`, \`packaging/notarization.env\`, production Sparkle feed/key, signed/notarized/stapled app, appcast metadata, and \`packaging/release-evidence.json\`.\n"
    printf -- "- Verify with \`./script/verify_release_environment.sh\` before expecting the readiness report to pass.\n"
    printf -- "- Replace placeholders below with production values and real manual observations before running the commands.\n\n"
    write_release_machine_runbook_command
    printf "\n"
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

phase_manual_gate_route_for_item() {
  local item="$1"
  local lowered

  lowered="$(printf "%s" "$item" | tr '[:upper:]' '[:lower:]')"
  case "$lowered" in
    *voiceover*|*accessibility*|*focus\ order*|*button\ help*|*destructive\ confirmation*|*支援技術*)
      printf "Manual VoiceOver"
      ;;
    *notion*|*todoist*|*linear*|*motion*|*competitor*|*benchmark*|*競合*)
      printf "Competitor Hands-On"
      ;;
    *developer\ id*|*signing*|*signed*|*codesign*|*notarization*|*notarized*|*gatekeeper*|*sparkle*|*appcast*|*clean\ environment*|*download*|*署名*|*公証*)
      printf "Release Machine"
      ;;
    *login\ item*|*launch\ at\ login*|*ログイン*)
      printf "Login Item Manual Check"
      ;;
    *)
      printf "Manual Review"
      ;;
  esac
}

write_phase_manual_route_group() {
  local label="$1"
  local items="$2"
  local item

  if [[ -z "$items" ]]; then
    return 0
  fi

  printf "%s phase gates:\n" "$label"
  while IFS= read -r item; do
    [[ -z "$item" ]] && continue
    printf -- "- [ ] %s\n" "${item#"$ROOT_DIR/"}"
  done <<<"$items"
  printf "\n"
}

write_phase_manual_gate_routes() {
  local item
  local route
  local voiceover_items=""
  local competitor_items=""
  local release_machine_items=""
  local login_item_items=""
  local manual_review_items=""

  if [[ -z "$phase_manual_unchecked" ]]; then
    return 0
  fi

  while IFS= read -r item; do
    [[ -z "$item" ]] && continue
    route="$(phase_manual_gate_route_for_item "$item")"
    case "$route" in
      "Manual VoiceOver")
        voiceover_items="$(append_line "$voiceover_items" "$item")"
        ;;
      "Competitor Hands-On")
        competitor_items="$(append_line "$competitor_items" "$item")"
        ;;
      "Release Machine")
        release_machine_items="$(append_line "$release_machine_items" "$item")"
        ;;
      "Login Item Manual Check")
        login_item_items="$(append_line "$login_item_items" "$item")"
        ;;
      *)
        manual_review_items="$(append_line "$manual_review_items" "$item")"
        ;;
    esac
  done <<<"$phase_manual_unchecked"

  printf "## Phase Manual Gate Routes\n"
  write_phase_manual_route_group "Manual VoiceOver" "$voiceover_items"
  write_phase_manual_route_group "Competitor Hands-On" "$competitor_items"
  write_phase_manual_route_group "Release Machine" "$release_machine_items"
  write_phase_manual_route_group "Login Item Manual Check" "$login_item_items"
  write_phase_manual_route_group "Manual Review" "$manual_review_items"
}

is_placeholder_checked_by() {
  local normalized
  normalized="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[[:punct:]]+/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]]+/ /g')"
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
    "voiceover observation"*|\
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

is_utc_timestamp() {
  local value="$1"
  local normalized
  value="$(printf '%s' "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || return 1
  normalized="$(/bin/date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$value" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)" || return 1
  [[ "$normalized" == "$value" ]]
}

is_future_utc_timestamp() {
  local value="$1"
  local timestamp_seconds now_seconds
  value="$(printf '%s' "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  is_utc_timestamp "$value" || return 1
  timestamp_seconds="$(/bin/date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$value" '+%s' 2>/dev/null)" || return 1
  now_seconds="$(/bin/date -u '+%s')"
  [[ "$timestamp_seconds" -gt "$now_seconds" ]]
}

assert_screenshot_has_visible_content() {
  local image_path="$1"
  /usr/bin/swift "$ROOT_DIR/script/ui_evidence_content_check.swift" "$image_path"
}

is_report_root_git_checkout_root() {
  local git_root
  git_root="$(git -C "$ROOT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "$git_root" && "$git_root" == "$ROOT_DIR" ]]
}

resolve_automated_preflight_evidence_path() {
  local evidence_file="$AUTOMATED_PREFLIGHT_EVIDENCE_FILE"

  if [[ -z "$evidence_file" ]]; then
    printf ""
    return 0
  fi

  if [[ "$evidence_file" == /* ]]; then
    printf "%s" "$evidence_file"
  else
    printf "%s/%s" "$ROOT_DIR" "$evidence_file"
  fi
}

automated_preflight_context_value() {
  local context_label="$1"
  awk -v label="$context_label" '
    index($0, label ":") == 1 {
      value = $0
      sub("^" label ":[[:space:]]*", "", value)
      print value
      found = 1
      exit
    }
    END {
      if (found != 1) {
        exit 1
      }
    }
  ' "$AUTOMATED_PREFLIGHT_EVIDENCE_PATH" || true
}

set_automated_preflight_evidence_reason() {
  AUTOMATED_PREFLIGHT_EVIDENCE_REASON="$1"
  AUTOMATED_PREFLIGHT_EVIDENCE_VALID=0
}

validate_automated_preflight_evidence() {
  AUTOMATED_PREFLIGHT_EVIDENCE_VALID=0
  AUTOMATED_PREFLIGHT_EVIDENCE_REASON=""
  AUTOMATED_PREFLIGHT_EVIDENCE_PATH="$(resolve_automated_preflight_evidence_path)"

  if [[ -z "$AUTOMATED_PREFLIGHT_EVIDENCE_PATH" ]]; then
    set_automated_preflight_evidence_reason "not provided"
    return 1
  fi

  if [[ ! -f "$AUTOMATED_PREFLIGHT_EVIDENCE_PATH" ]]; then
    set_automated_preflight_evidence_reason "file does not exist: ${AUTOMATED_PREFLIGHT_EVIDENCE_PATH#"$ROOT_DIR/"}"
    return 1
  fi

  if ! grep -Fx "Status: passed" "$AUTOMATED_PREFLIGHT_EVIDENCE_PATH" >/dev/null; then
    set_automated_preflight_evidence_reason "missing Status: passed"
    return 1
  fi

  if ! grep -Fx "Generated by: script/check_automated_release_preflight.sh" "$AUTOMATED_PREFLIGHT_EVIDENCE_PATH" >/dev/null; then
    set_automated_preflight_evidence_reason "missing generator identity"
    return 1
  fi

  local generated_at
  generated_at="$(automated_preflight_context_value "Generated at")"
  if [[ -z "$(tr -d '[:space:]' <<<"$generated_at")" ]]; then
    set_automated_preflight_evidence_reason "missing generated timestamp"
    return 1
  fi
  if ! is_utc_timestamp "$generated_at"; then
    set_automated_preflight_evidence_reason "invalid generated timestamp"
    return 1
  fi
  if is_future_utc_timestamp "$generated_at"; then
    set_automated_preflight_evidence_reason "generated timestamp is in the future"
    return 1
  fi

  if ! grep -Fx "Tracked source tree: clean" "$AUTOMATED_PREFLIGHT_EVIDENCE_PATH" >/dev/null; then
    set_automated_preflight_evidence_reason "missing clean tracked source tree marker"
    return 1
  fi

  if grep -Eiq '(pending|todo|tbd|placeholder|sample|example|replace me)' "$AUTOMATED_PREFLIGHT_EVIDENCE_PATH"; then
    set_automated_preflight_evidence_reason "contains template or placeholder text"
    return 1
  fi

  if grep -F -- '- [ ]' "$AUTOMATED_PREFLIGHT_EVIDENCE_PATH" >/dev/null; then
    set_automated_preflight_evidence_reason "contains unchecked checklist markers"
    return 1
  fi

  local evidence_commit expected_commit
  evidence_commit="$(automated_preflight_context_value "Source commit")"
  expected_commit="$(source_commit)"
  if [[ -z "$(tr -d '[:space:]' <<<"$evidence_commit")" ]]; then
    set_automated_preflight_evidence_reason "missing source commit"
    return 1
  fi
  if [[ "$expected_commit" != "unknown" && "$evidence_commit" != "$expected_commit" ]]; then
    set_automated_preflight_evidence_reason "source commit mismatch: expected $expected_commit"
    return 1
  fi

  if is_report_root_git_checkout_root && [[ "$(tracked_source_tree_status)" != "clean" ]]; then
    set_automated_preflight_evidence_reason "current tracked source tree is not clean"
    return 1
  fi

  local evidence_app evidence_workspace evidence_scheme evidence_configuration evidence_destination
  evidence_app="$(automated_preflight_context_value "App")"
  if [[ "$evidence_app" != "$EXPECTED_AUTOMATED_PREFLIGHT_APP_NAME" ]]; then
    set_automated_preflight_evidence_reason "app mismatch: expected $EXPECTED_AUTOMATED_PREFLIGHT_APP_NAME"
    return 1
  fi

  evidence_workspace="$(automated_preflight_context_value "Xcode workspace")"
  if [[ "$evidence_workspace" != "$EXPECTED_AUTOMATED_PREFLIGHT_XCODE_WORKSPACE" ]]; then
    set_automated_preflight_evidence_reason "Xcode workspace mismatch: expected $EXPECTED_AUTOMATED_PREFLIGHT_XCODE_WORKSPACE"
    return 1
  fi

  evidence_scheme="$(automated_preflight_context_value "Xcode scheme")"
  if [[ "$evidence_scheme" != "$EXPECTED_AUTOMATED_PREFLIGHT_XCODE_SCHEME" ]]; then
    set_automated_preflight_evidence_reason "Xcode scheme mismatch: expected $EXPECTED_AUTOMATED_PREFLIGHT_XCODE_SCHEME"
    return 1
  fi

  evidence_configuration="$(automated_preflight_context_value "Xcode configuration")"
  if [[ "$evidence_configuration" != "$EXPECTED_AUTOMATED_PREFLIGHT_XCODE_CONFIGURATION" ]]; then
    set_automated_preflight_evidence_reason "Xcode configuration mismatch: expected $EXPECTED_AUTOMATED_PREFLIGHT_XCODE_CONFIGURATION"
    return 1
  fi

  evidence_destination="$(automated_preflight_context_value "Xcode destination")"
  if [[ "$evidence_destination" != "$EXPECTED_AUTOMATED_PREFLIGHT_XCODE_DESTINATION" ]]; then
    set_automated_preflight_evidence_reason "Xcode destination mismatch: expected $EXPECTED_AUTOMATED_PREFLIGHT_XCODE_DESTINATION"
    return 1
  fi

  local required_gate
  for required_gate in "${AUTOMATED_PREFLIGHT_REQUIRED_GATES[@]}"; do
    if ! grep -Fx -- "- $required_gate: passed" "$AUTOMATED_PREFLIGHT_EVIDENCE_PATH" >/dev/null; then
      set_automated_preflight_evidence_reason "missing passed gate: $required_gate"
      return 1
    fi
  done

  if ! grep -Fx -- "- This does not mark the release ready." "$AUTOMATED_PREFLIGHT_EVIDENCE_PATH" >/dev/null; then
    set_automated_preflight_evidence_reason "missing release-readiness boundary"
    return 1
  fi

  for manual_boundary in \
    "- Manual VoiceOver evidence remains separate." \
    "- Competitor hands-on evidence remains separate." \
    "- Developer ID signing, notarization, Sparkle, Gatekeeper, and clean-environment evidence remain separate."; do
    if ! grep -Fx -- "$manual_boundary" "$AUTOMATED_PREFLIGHT_EVIDENCE_PATH" >/dev/null; then
      set_automated_preflight_evidence_reason "missing manual boundary: ${manual_boundary#- }"
      return 1
    fi
  done

  AUTOMATED_PREFLIGHT_EVIDENCE_VALID=1
  return 0
}

automated_preflight_evidence_covers() {
  [[ "$AUTOMATED_PREFLIGHT_EVIDENCE_VALID" -eq 1 ]]
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

section "Automated preflight evidence"
if [[ -z "$AUTOMATED_PREFLIGHT_EVIDENCE_FILE" ]]; then
  printf "INFO: no automated preflight evidence file provided; local proof gates must run in this report or remain blockers.\n"
else
  if validate_automated_preflight_evidence; then
    printf "OK: automated preflight evidence covers current commit and all local proof gates (%s)\n" "${AUTOMATED_PREFLIGHT_EVIDENCE_PATH#"$ROOT_DIR/"}"
  else
    blocker "automated preflight evidence is invalid: $AUTOMATED_PREFLIGHT_EVIDENCE_REASON"
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
elif automated_preflight_evidence_covers "Release CI"; then
  printf "OK: release CI preflight covered by automated preflight evidence (%s)\n" "${AUTOMATED_PREFLIGHT_EVIDENCE_PATH#"$ROOT_DIR/"}"
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
elif automated_preflight_evidence_covers "Local CRUD smoke"; then
  printf "OK: local CRUD smoke covered by automated preflight evidence (%s)\n" "${AUTOMATED_PREFLIGHT_EVIDENCE_PATH#"$ROOT_DIR/"}"
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
elif automated_preflight_evidence_covers "Runtime accessible CRUD smoke"; then
  printf "OK: runtime accessible CRUD smoke covered by automated preflight evidence (%s)\n" "${AUTOMATED_PREFLIGHT_EVIDENCE_PATH#"$ROOT_DIR/"}"
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
        -configuration "$XCODE_CONFIGURATION" \
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
elif automated_preflight_evidence_covers "Xcode build preflight"; then
  printf "OK: release Xcode preflight covered by automated preflight evidence (%s)\n" "${AUTOMATED_PREFLIGHT_EVIDENCE_PATH#"$ROOT_DIR/"}"
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
elif automated_preflight_evidence_covers "Launch preflight"; then
  printf "OK: release launch preflight covered by automated preflight evidence (%s)\n" "${AUTOMATED_PREFLIGHT_EVIDENCE_PATH#"$ROOT_DIR/"}"
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
voiceover_status_passed=0
voiceover_blocker() {
  collect_manual_action_blocker "voiceover" "$1"
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
  elif automated_preflight_evidence_covers "Runtime accessibility preflight"; then
    printf "OK: accessibility runtime preflight covered by automated preflight evidence (%s)\n" "${AUTOMATED_PREFLIGHT_EVIDENCE_PATH#"$ROOT_DIR/"}"
  else
    printf "INFO: accessibility runtime preflight skipped; set SOLOPM_ACCESSIBILITY_RUNTIME_PREFLIGHT=1 to include the visible AX smoke check.\n"
    blocker "accessibility runtime preflight was not run"
  fi
fi
if [[ ! -f "$voiceover_evidence_file" ]]; then
  voiceover_blocker "missing VoiceOver accessibility evidence file: $VOICEOVER_EVIDENCE_RELATIVE"
else
  grep -Fx "Status: passed" "$voiceover_evidence_file" >/dev/null && voiceover_status_passed=1
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
    grep -Eiq '(pending|todo|tbd|placeholder|sample|example|replace me|signed or release-candidate|VoiceOver/keyboard/device details|VoiceOver / keyboard / device details|macOS version.*hardware.*VoiceOver input method.*clean user|manual pass environment|accessibility environment)' <<<"$context_value" && has_template_context=1
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
      for runtime_marker in "OK: runtime AX smoke visible" "buttons=" "textFields=" "staticTexts=" "unlabeledButtons=0" "genericButtons=0" "crudSignals=8/8" "focusPathSignals=6/6"; do
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

  if [[ "$voiceover_status_passed" -eq 1 ]]; then
    expected_source_commit="$(source_commit)"
    voiceover_source_commit="$(normalize_voiceover_context_value "$(voiceover_context_value "Source commit")")"
    if [[ -n "$voiceover_source_commit" && "$voiceover_source_commit" != "$expected_source_commit" ]]; then
      voiceover_blocker "VoiceOver accessibility evidence source commit does not match current git commit: expected $expected_source_commit"
    fi
  fi
fi
if [[ "$voiceover_evidence_blocker_count" -gt 0 ]]; then
  printf "NEXT: replace docs/release/evidence/accessibility-voiceover.md with a real VoiceOver pass by running ./script/create_voiceover_evidence.sh --passed with complete release-candidate context, --capture-runtime-ax-smoke, complete focus-path notes, and no pending/template/unchecked markers; the generated evidence must include the runtime AX smoke OK line with unlabeledButtons=0, genericButtons=0, crudSignals=8/8, and focusPathSignals=6/6.\n"
fi

section "Competitor hands-on evidence"
competitor_evidence_file="$ROOT_DIR/$COMPETITOR_EVIDENCE_RELATIVE"
competitor_evidence_blocker_count=0
competitor_status_passed=0
competitor_template_pattern='(^|[^[:alnum:]_])(pending|todo|tbd|placeholder|sample|example)([^[:alnum:]_]|$)|replace me|macOS/browser versions|competitor app/account tiers|whether any paid trial'
competitor_blocker() {
  collect_manual_action_blocker "competitor" "$1"
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
competitor_benchmark_source_commit() {
  awk '
    index($0, "Source commit:") == 1 {
      value = $0
      sub("^Source commit:[[:space:]]*", "", value)
      print value
      found = 1
      exit
    }
    END {
      if (found != 1) {
        exit 1
      }
    }
  ' "$competitor_benchmark_file" || true
}
competitor_benchmark_file="$ROOT_DIR/$COMPETITOR_BENCHMARK_RELATIVE"
if [[ ! -f "$competitor_evidence_file" ]]; then
  competitor_blocker "missing competitor hands-on evidence file: $COMPETITOR_EVIDENCE_RELATIVE"
else
  grep -Fx "Status: passed" "$competitor_evidence_file" >/dev/null && competitor_status_passed=1
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

  if [[ "$competitor_status_passed" -eq 1 ]]; then
    expected_source_commit="$(source_commit)"
    competitor_source_commit="$(normalize_voiceover_context_value "$(competitor_context_value "Source commit")")"
    if [[ -n "$competitor_source_commit" && "$competitor_source_commit" != "$expected_source_commit" ]]; then
      competitor_blocker "Competitor hands-on evidence source commit does not match current git commit: expected $expected_source_commit"
    fi
  fi
fi
if [[ ! -f "$competitor_benchmark_file" ]]; then
  competitor_blocker "missing competitor benchmark document: $COMPETITOR_BENCHMARK_RELATIVE"
else
  if [[ "$competitor_status_passed" -eq 1 ]]; then
    expected_source_commit="$(source_commit)"
    competitor_benchmark_commit="$(normalize_voiceover_context_value "$(competitor_benchmark_source_commit)")"
    if [[ -n "$competitor_benchmark_commit" && "$competitor_benchmark_commit" != "$expected_source_commit" ]]; then
      competitor_blocker "Competitor benchmark source commit does not match current git commit: expected $expected_source_commit"
    fi
  fi

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
mcp_review_file="$ROOT_DIR/$MCP_REVIEW_RELATIVE"
if [[ ! -f "$mcp_review_file" ]]; then
  blocker "missing MCP compliance review: $MCP_REVIEW_RELATIVE"
else
  mcp_review_missing_marker_count=0
  for required_marker in "${MCP_REVIEW_REQUIRED_MARKERS[@]}"; do
    if ! grep -F "$required_marker" "$mcp_review_file" >/dev/null; then
      blocker "MCP compliance review is missing marker: $required_marker"
      mcp_review_missing_marker_count=$((mcp_review_missing_marker_count + 1))
    fi
  done
  if [[ "$mcp_review_missing_marker_count" -eq 0 ]]; then
    printf "OK: MCP compliance review covers stable baseline, draft boundary, release subset, and non-host positioning\n"
  fi
fi

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
  collect_release_environment_blockers "$preflight_output"
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
