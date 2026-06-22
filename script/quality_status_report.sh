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

mkdir -p "$(dirname "$OUTPUT_FILE")"

source_commit="$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || printf "unknown")"
generated_at="$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')"
phase_total="$(count_pattern "$PHASE14_FILE" '^- \[[ x]\]')"
phase_done="$(count_pattern "$PHASE14_FILE" '^- \[x\]')"
phase_open=$((phase_total - phase_done))
risk_open="$(count_risk_coverage "open")"
risk_manual="$(count_risk_coverage "manual-only")"

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
  printf '| `docs/release/evidence/accessibility-voiceover.md` | %s | %s |\n' "$(first_status_line "$VOICEOVER_EVIDENCE_FILE")" "$(first_commit_line "$VOICEOVER_EVIDENCE_FILE")"
  printf '| `docs/release/evidence/competitor-hands-on.md` | %s | %s |\n\n' "$(first_status_line "$COMPETITOR_EVIDENCE_FILE")" "$(first_commit_line "$COMPETITOR_EVIDENCE_FILE")"

  printf "## Verification Commands\n\n"
  printf -- '- `swift test --filter AppExperienceSourceTests`\n'
  printf -- '- `swift test --filter ReleasePipelineTests`\n'
  printf -- '- `swift test --filter ProjectBoardStoreTests`\n'
  printf -- '- `script/check_runtime_accessible_crud_smoke.sh`\n'
  printf -- '- `script/check_accessibility_preflight.sh --runtime`\n'
  printf -- '- `script/capture_ui_evidence.sh --doctor`\n'
  printf -- '- `SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=.tmp/automated-release-preflight-%s.md ./script/check_automated_release_preflight.sh`\n' "$source_commit"
  printf -- '- `SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=.tmp/automated-release-preflight-%s.md ./script/release_readiness_report.sh`\n\n' "$source_commit"

  printf "## Notes\n\n"
  printf -- "- This dashboard is a quality triage aid, not release evidence.\n"
  printf -- "- Manual VoiceOver, competitor hands-on, and release-machine evidence remain separate release gates.\n"
  printf -- "- Secret-like values are redacted before writing this report.\n"
} | redact >"$OUTPUT_FILE"

printf "Quality status report written to %s\n" "$(relative_path "$OUTPUT_FILE")"
