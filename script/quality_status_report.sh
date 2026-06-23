#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PHASE14_FILE="$ROOT_DIR/tasks/Phase14-QualityRegressionHardening.md"
RISK_MAP_FILE="$ROOT_DIR/docs/quality/regression-risk-map.md"
UI_EVIDENCE_FILE="$ROOT_DIR/docs/release/evidence/ui-screenshots.md"
MCP_EVIDENCE_FILE="$ROOT_DIR/docs/release/evidence/mcp-inspector.md"
VOICEOVER_EVIDENCE_FILE="$ROOT_DIR/docs/release/evidence/accessibility-voiceover.md"
COMPETITOR_EVIDENCE_FILE="$ROOT_DIR/docs/release/evidence/competitor-hands-on.md"
OUTPUT_FILE="${SOLOPM_QUALITY_STATUS_FILE:-$ROOT_DIR/docs/quality/status.md}"

redact() {
  sed -E \
    -e 's/sk-[A-Za-z0-9_-]{8,}/[redacted-secret]/g' \
    -e 's/(xox[baprs]-)[A-Za-z0-9-]{8,}/\1[redacted-secret]/g' \
    -e 's/(gh[pousr]_)[A-Za-z0-9_]{8,}/\1[redacted-secret]/g' \
    -e 's/AKIA[0-9A-Z]{16}/[redacted-aws-key]/g' \
    -e 's/(password|token|secret|api[_-]?key)=([^[:space:]]+)/\1=[redacted]/Ig'
}

relative_path() {
  local path="$1"
  case "$path" in
    "$ROOT_DIR"/*)
      printf "%s" "${path#"$ROOT_DIR/"}"
      ;;
    *)
      printf "%s" "$path"
      ;;
  esac
}

first_status_line() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    printf "missing"
    return 0
  fi
  awk -F': ' '/^Status:/ { print $2; found=1; exit } END { if (!found) print "present" }' "$file" | redact
}

first_commit_line() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    printf "missing"
    return 0
  fi
  awk -F'`' '/Source commit:/ { if (NF >= 2) { print $2; found=1; exit } } END { if (!found) print "unknown" }' "$file" | redact
}

manual_release_evidence_source_commit() {
  local commit
  # Manual evidence is committed after a review pass, so HEAD would make a
  # fresh evidence commit invalidate itself. Use the product/runtime inputs that
  # define the release candidate and flag stale manual observations after those
  # inputs move.
  commit="$(
    git -C "$ROOT_DIR" log -1 --format=%h -- \
      Sources/SoloPMApp \
      Sources/SoloPMCore \
      Sources/SoloPMCLI \
      Sources/SoloPMExternalConnectors \
      Package.swift \
      packaging/app_metadata.env 2>/dev/null || true
  )"
  if [[ -n "$commit" ]]; then
    printf "%s" "$commit"
  else
    git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || printf "unknown"
  fi
}

manual_evidence_status() {
  local file="$1"
  local expected_commit="$2"
  local status
  local evidence_commit

  status="$(first_status_line "$file")"
  evidence_commit="$(first_commit_line "$file")"

  if [[ "$status" == "passed" &&
    -n "$(tr -d '[:space:]' <<<"$expected_commit")" &&
    "$expected_commit" != "unknown" &&
    "$evidence_commit" != "$expected_commit" ]]; then
    printf "stale (passed; expected %s)" "$expected_commit"
    return 0
  fi

  printf "%s" "$status"
}

count_pattern() {
  local file="$1"
  local pattern="$2"
  if [[ ! -f "$file" ]]; then
    printf "0"
    return 0
  fi
  (grep -E "$pattern" "$file" || true) | wc -l | tr -d ' '
}

count_risk_coverage() {
  local coverage="$1"
  if [[ ! -f "$RISK_MAP_FILE" ]]; then
    printf "0"
    return 0
  fi
  awk -v coverage="$coverage" '
    /^## How to use/ { exit }
    $0 ~ "Coverage:[[:space:]]*" coverage || $0 ~ "\\|[[:space:]]*" coverage "[[:space:]]*\\|" { count += 1 }
    END { print count + 0 }
  ' "$RISK_MAP_FILE"
}

write_matching_lines() {
  local file="$1"
  local pattern="$2"
  local limit="$3"
  local empty_message="$4"

  if [[ ! -f "$file" ]]; then
    printf -- "- [ ] missing %s\n" "$(relative_path "$file")"
    return 0
  fi

  local matches
  matches="$(grep -En "$pattern" "$file" | head -n "$limit" | redact || true)"
  if [[ -z "$matches" ]]; then
    printf -- "- [x] %s\n" "$empty_message"
    return 0
  fi

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    printf -- "- [ ] %s:%s\n" "$(relative_path "$file")" "$line"
  done <<<"$matches"
}

write_risk_coverage_lines() {
  local coverage="$1"
  local limit="$2"
  local empty_message="$3"

  if [[ ! -f "$RISK_MAP_FILE" ]]; then
    printf -- "- [ ] missing %s\n" "$(relative_path "$RISK_MAP_FILE")"
    return 0
  fi

  local matches
  matches="$(awk -v coverage="$coverage" '
    /^## How to use/ { exit }
    $0 ~ "Coverage:[[:space:]]*" coverage || $0 ~ "\\|[[:space:]]*" coverage "[[:space:]]*\\|" {
      print NR ":" $0
    }
  ' "$RISK_MAP_FILE" | head -n "$limit" | redact || true)"
  if [[ -z "$matches" ]]; then
    printf -- "- [x] %s\n" "$empty_message"
    return 0
  fi

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    printf -- "- [ ] %s:%s\n" "$(relative_path "$RISK_MAP_FILE")" "$line"
  done <<<"$matches"
}

latest_automated_preflight() {
  local head_commit="$1"
  local expected="$ROOT_DIR/.tmp/automated-release-preflight-$head_commit.md"
  if [[ -f "$expected" ]]; then
    printf "%s" "$(relative_path "$expected")"
    return 0
  fi
  printf "missing .tmp/automated-release-preflight-%s.md" "$head_commit"
}

phase_item_status() {
  local item="$1"

  if [[ ! -f "$PHASE14_FILE" ]]; then
    printf "missing phase checklist"
    return 0
  fi

  if grep -F -- "- [x] $item" "$PHASE14_FILE" >/dev/null; then
    printf "passed"
  elif grep -F -- "- [ ] $item" "$PHASE14_FILE" >/dev/null; then
    printf "pending"
  else
    printf "not listed"
  fi
}

combined_phase_status() {
  local item
  local item_status
  local status="passed"

  for item in "$@"; do
    item_status="$(phase_item_status "$item")"
    if [[ "$item_status" == "pending" ]]; then
      status="pending"
    elif [[ "$status" == "passed" && "$item_status" != "passed" ]]; then
      status="$item_status"
    fi
  done

  printf "%s" "$status"
}

script_status() {
  local relative="$1"
  if [[ -x "$ROOT_DIR/$relative" ]]; then
    printf "available"
  else
    printf "missing"
  fi
}

write_gate_row() {
  local gate="$1"
  local layer="$2"
  local status="$3"
  local evidence="$4"
  local next="$5"

  printf '| %s | %s | %s | `%s` | %s |\n' \
    "$gate" \
    "$layer" \
    "$status" \
    "$evidence" \
    "$next"
}

write_gate_classification() {
  local voiceover_status
  local competitor_status
  local expected_manual_commit

  expected_manual_commit="$(manual_release_evidence_source_commit)"
  voiceover_status="$(manual_evidence_status "$VOICEOVER_EVIDENCE_FILE" "$expected_manual_commit")"
  competitor_status="$(manual_evidence_status "$COMPETITOR_EVIDENCE_FILE" "$expected_manual_commit")"

  printf "## Gate Classification\n\n"
  printf "| Gate | Layer | Status | Evidence / command | Next action |\n"
  printf "| --- | --- | --- | --- | --- |\n"
  write_gate_row \
    "Lightweight PR gate" \
    "source + build" \
    "$(script_status "scripts/ci.sh")" \
    "scripts/ci.sh" \
    "Use as the default fast PR verifier; opt into runtime, visual, or release lanes with SOLOPM_CI_* flags."
  write_gate_row \
    "Focused tests" \
    "source + unit" \
    "$(combined_phase_status '`swift test --filter AppExperienceSourceTests`' '`swift test --filter ReleasePipelineTests`' '`swift test --filter ProjectBoardStoreTests`')" \
    "swift test --filter <suite>" \
    "Run the three owner suites when touching UI contracts, release gates, or Project Board persistence."
  write_gate_row \
    "Full test suite" \
    "unit + integration" \
    "$(phase_item_status '`swift test`')" \
    "swift test" \
    "Run before closing the Phase14 exit gate."
  write_gate_row \
    "Runtime smoke" \
    "runtime AX" \
    "$(combined_phase_status '`script/check_project_board_header_layout_smoke.sh`' '`script/check_layout_stability_smoke.sh`' '`script/check_runtime_accessible_crud_smoke.sh`' '`script/check_accessibility_preflight.sh --runtime`')" \
    "script/check_runtime_accessible_crud_smoke.sh" \
    "Run on a visible macOS session to cover CRUD, Inbox, Today, Settings, Voice Command, and layout stability."
  write_gate_row \
    "Visual smoke" \
    "visual" \
    "$(combined_phase_status '`script/capture_ui_evidence.sh --doctor`' '`script/check_visual_regression_smoke.sh`')" \
    "script/check_visual_regression_smoke.sh" \
    "Use screenshot doctor first, then compare Light/Dark/System evidence."
  write_gate_row \
    "Manual evidence" \
    "manual" \
    "VoiceOver: $voiceover_status; Competitor: $competitor_status" \
    "docs/release/evidence/accessibility-voiceover.md" \
    "Manual findings must link back through docs/quality/manual-to-automated-regression.md."
  write_gate_row \
    "Release readiness handoff" \
    "release" \
    "$(script_status "script/release_readiness_report.sh")" \
    "script/release_readiness_report.sh" \
    "Run after quality gaps are classified; readiness remains the release gate, not this dashboard."
  printf "\n"
}

write_next_quality_gaps() {
  local gap_count=0
  local voiceover_status
  local competitor_status
  local full_suite_status
  local expected_manual_commit

  expected_manual_commit="$(manual_release_evidence_source_commit)"
  voiceover_status="$(manual_evidence_status "$VOICEOVER_EVIDENCE_FILE" "$expected_manual_commit")"
  competitor_status="$(manual_evidence_status "$COMPETITOR_EVIDENCE_FILE" "$expected_manual_commit")"
  full_suite_status="$(phase_item_status '`swift test`')"

  printf "## Next Quality Gaps\n\n"

  if [[ "$phase_open" -gt 0 ]]; then
    gap_count=$((gap_count + 1))
    printf "Unchecked Phase14 items to close next:\n"
    write_matching_lines "$PHASE14_FILE" '^- \[ \]' 5 "No unchecked Phase14 items found."
    printf "\n"
  fi

  if [[ "$risk_open" -gt 0 ]]; then
    gap_count=$((gap_count + 1))
    printf "Open risk markers to either automate or explicitly route:\n"
    write_risk_coverage_lines "open" 5 "No open risk markers found."
    printf "\n"
  fi

  if [[ "$full_suite_status" != "passed" ]]; then
    gap_count=$((gap_count + 1))
    printf -- "- [ ] Full test suite is %s in the Phase14 checklist. Next: run \`swift test\` and update the exit gate evidence.\n" "$full_suite_status"
  fi

  if [[ "$voiceover_status" != "passed" || "$competitor_status" != "passed" ]]; then
    gap_count=$((gap_count + 1))
    printf -- "- [ ] Manual evidence status is VoiceOver=%s, Competitor=%s. Next: use \`script/release_readiness_report.sh\` for release evidence blockers and link any findings to regression coverage.\n" "$voiceover_status" "$competitor_status"
  fi

  if [[ "$gap_count" -eq 0 ]]; then
    printf -- "- [x] No quality dashboard gaps found; rerun \`script/release_readiness_report.sh\` for release evidence gates.\n"
  fi

  printf "\n"
}

mkdir -p "$(dirname "$OUTPUT_FILE")"

source_commit="$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || printf "unknown")"
generated_at="$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')"
phase_total="$(count_pattern "$PHASE14_FILE" '^- \[[ x]\]')"
phase_done="$(count_pattern "$PHASE14_FILE" '^- \[x\]')"
phase_open=$((phase_total - phase_done))
risk_open="$(count_risk_coverage "open")"
risk_manual="$(count_risk_coverage "manual-only")"
expected_manual_commit="$(manual_release_evidence_source_commit)"

{
  printf "# SoloPM Quality Status\n\n"
  printf "Generated at: %s\n" "$generated_at"
  printf "Source commit: %s\n\n" "$source_commit"

  printf "## Summary\n\n"
  printf -- '- Phase14 completion: %s/%s checked, %s remaining (`tasks/Phase14-QualityRegressionHardening.md`)\n' "$phase_done" "$phase_total" "$phase_open"
  printf -- '- Open risk items: %s (`docs/quality/regression-risk-map.md`)\n' "$risk_open"
  printf -- '- Manual-only risk items: %s (`docs/quality/regression-risk-map.md`)\n' "$risk_manual"
  printf -- '- Automated preflight evidence: `%s`\n\n' "$(latest_automated_preflight "$source_commit")"

  printf "## Unfinished Phase14 Items\n\n"
  write_matching_lines "$PHASE14_FILE" '^- \[ \]' 30 "No unchecked Phase14 items found."
  printf "\n"

  printf "## Open Risk Items\n\n"
  write_risk_coverage_lines "open" 20 "No open risk markers found."
  printf "\n"

  printf "## Runtime / Visual / Manual Evidence\n\n"
  printf "| Evidence | Status | Source commit |\n"
  printf "| --- | --- | --- |\n"
  printf '| `docs/release/evidence/ui-screenshots.md` | %s | %s |\n' "$(first_status_line "$UI_EVIDENCE_FILE")" "$(first_commit_line "$UI_EVIDENCE_FILE")"
  printf '| `docs/release/evidence/mcp-inspector.md` | %s | %s |\n' "$(first_status_line "$MCP_EVIDENCE_FILE")" "$(first_commit_line "$MCP_EVIDENCE_FILE")"
  printf '| `docs/release/evidence/accessibility-voiceover.md` | %s | %s |\n' "$(manual_evidence_status "$VOICEOVER_EVIDENCE_FILE" "$expected_manual_commit")" "$(first_commit_line "$VOICEOVER_EVIDENCE_FILE")"
  printf '| `docs/release/evidence/competitor-hands-on.md` | %s | %s |\n\n' "$(manual_evidence_status "$COMPETITOR_EVIDENCE_FILE" "$expected_manual_commit")" "$(first_commit_line "$COMPETITOR_EVIDENCE_FILE")"

  write_gate_classification

  write_next_quality_gaps

  printf "## Verification Commands\n\n"
  printf -- '- `scripts/ci.sh`\n'
  printf -- '- `swift test --filter AppExperienceSourceTests`\n'
  printf -- '- `swift test --filter ReleasePipelineTests`\n'
  printf -- '- `swift test --filter ProjectBoardStoreTests`\n'
  printf -- '- `swift test`\n'
  printf -- '- `bash -n script/check_project_board_header_layout_smoke.sh`\n'
  printf -- '- `script/check_project_board_header_layout_smoke.sh`\n'
  printf -- '- `script/check_layout_stability_smoke.sh`\n'
  printf -- '- `script/check_runtime_accessible_crud_smoke.sh`\n'
  printf -- '- `script/check_accessibility_preflight.sh --runtime`\n'
  printf -- '- `script/capture_ui_evidence.sh --doctor`\n'
  printf -- '- `script/check_visual_regression_smoke.sh`\n'
  printf -- '- `script/check_security_regressions.sh`\n'
  printf -- '- `script/quality_status_report.sh`\n'
  printf -- '- `docs/quality/test-triage.md`\n'
  printf -- '- `docs/quality/flake-quarantine.md`\n'
  printf -- '- `./script/check_automated_release_preflight.sh`\n'
  printf -- '- `SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=.tmp/automated-release-preflight-%s.md ./script/release_readiness_report.sh`\n\n' "$source_commit"

  printf "## Notes\n\n"
  printf -- "- This dashboard is a quality triage aid, not release evidence.\n"
  printf -- "- Manual VoiceOver, competitor hands-on, and release-machine evidence remain separate release gates.\n"
  printf -- "- Secret-like values are redacted before writing this report.\n"
} | redact >"$OUTPUT_FILE"

printf "Quality status report written to %s\n" "$(relative_path "$OUTPUT_FILE")"
