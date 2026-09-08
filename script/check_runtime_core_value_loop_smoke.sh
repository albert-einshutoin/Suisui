#!/usr/bin/env bash
# Observed #617 evidence for one normal conversation job across the product route.
# The locale runs share the same harness contract but each uses a fresh isolated
# database and process, so no run can hide a missing state transition.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_ROOT="${SUISUI_CORE_VALUE_LOOP_ARTIFACT_DIR:-$ROOT_DIR/.tmp/suisui-core-value-loop}"
CONTINUITY_SCRIPT="$ROOT_DIR/script/check_runtime_voice_task_continuity_smoke.sh"

source_commit=""
failure_locale=""
failure_reason=""
status="passed"

usage() {
  printf '%s\n' "usage: $0" >&2
}

contains_rejected_evidence() {
  local file="$1"
  grep -Eq '(/Users/|/home/|sk-[[:alnum:]_-]{8,}|AIza[[:alnum:]_-]{12,}|raw[ _-]?transcript|audio[ _-]?transcript)' "$file"
}

read_fact() {
  local file="$1" key="$2"
  grep -E "^${key}=" "$file" | tail -1 | cut -d= -f2-
}

fact_is_number() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

read_number_fact() {
  local file="$1" key="$2" value
  value="$(read_fact "$file" "$key" || true)"
  fact_is_number "$value" && printf '%s\n' "$value" || printf 'null\n'
}

validate_locale_facts() {
  local locale="$1"
  local facts_file="$ARTIFACT_ROOT/$locale/facts.env"
  local continuity_artifact="$ARTIFACT_ROOT/$locale/voice-task-continuity.json"
  local stage_set
  [[ -s "$facts_file" && -f "$continuity_artifact" ]] || return 1
  contains_rejected_evidence "$facts_file" && return 1
  contains_rejected_evidence "$continuity_artifact" && return 1
  jq -e --arg source "$source_commit" '
    .status == "passed"
    and .sourceCommit == $source
    and .manualVoiceOver == "not-run"
  ' "$continuity_artifact" >/dev/null || return 1
  [[ "$(read_fact "$facts_file" locale)" == "$locale" ]] || return 1
  [[ "$(read_fact "$facts_file" same_work_id)" == "true" ]] || return 1
  [[ "$(read_fact "$facts_file" candidate_build_matches_source)" == "true" ]] || return 1
  [[ "$(read_fact "$facts_file" candidate_result_matches_source)" == "true" ]] || return 1
  [[ "$(read_fact "$facts_file" input_proposal_queue_result_receipt)" == "present" ]] || return 1
  [[ "$(read_fact "$facts_file" result_receipt_ax)" == "visible" ]] || return 1
  [[ "$(read_fact "$facts_file" result_status)" == "done" ]] || return 1
  [[ "$(read_fact "$facts_file" same_session)" == "true" ]] || return 1
  [[ "$(read_fact "$facts_file" proposal_preserved)" == "true" ]] || return 1
  [[ "$(read_fact "$facts_file" queue_item_preserved)" == "true" ]] || return 1
  fact_is_number "$(read_fact "$facts_file" route_transitions)" || return 1
  fact_is_number "$(read_fact "$facts_file" external_write_count)" || return 1
  fact_is_number "$(read_fact "$facts_file" transcript_row_count)" || return 1
  fact_is_number "$(read_fact "$facts_file" screen_transition_count)" || return 1
  stage_set=",$(read_fact "$facts_file" candidate_stage_count),"
  for stage in first_capture reviewable_action_plan approved_local_action local_execution result_displayed; do
    [[ "$stage_set" == *",$stage,"* ]] || return 1
  done
}

run_locale() {
  local locale="$1"
  local locale_root="$ARTIFACT_ROOT/$locale"
  mkdir -p "$locale_root"
  if ! env -i \
    PATH="$PATH" \
    HOME="$HOME" \
    SUISUI_VOICE_TASK_CONTINUITY_ARTIFACT_DIR="$locale_root" \
    SUISUI_VOICE_TASK_CONTINUITY_FACTS_FILE="$locale_root/facts.env" \
    SUISUI_VOICE_TASK_CONTINUITY_LOCALE="$locale" \
    "$CONTINUITY_SCRIPT"; then
    failure_locale="$locale"
    failure_reason="continuity_runtime_failed"
    return 1
  fi
  if ! validate_locale_facts "$locale"; then
    failure_locale="$locale"
    failure_reason="continuity_evidence_invalid"
    return 1
  fi
}

write_manifest() {
  local manifest_file="$ARTIFACT_ROOT/manifest.json"
  local temporary_file
  local english_facts="$ARTIFACT_ROOT/english/facts.env"
  local japanese_facts="$ARTIFACT_ROOT/japanese/facts.env"
  local english_external_writes=null english_transcript_rows=null english_screen_transitions=null english_route_transitions=null
  local japanese_external_writes=null japanese_transcript_rows=null japanese_screen_transitions=null japanese_route_transitions=null
  local english_stages="" japanese_stages=""
  local candidate_ok=false

  if [[ -s "$english_facts" ]]; then
    english_external_writes="$(read_number_fact "$english_facts" external_write_count)"
    english_transcript_rows="$(read_number_fact "$english_facts" transcript_row_count)"
    english_screen_transitions="$(read_number_fact "$english_facts" screen_transition_count)"
    english_route_transitions="$(read_number_fact "$english_facts" route_transitions)"
    english_stages="$(read_fact "$english_facts" candidate_stage_count || true)"
  fi
  if [[ -s "$japanese_facts" ]]; then
    japanese_external_writes="$(read_number_fact "$japanese_facts" external_write_count)"
    japanese_transcript_rows="$(read_number_fact "$japanese_facts" transcript_row_count)"
    japanese_screen_transitions="$(read_number_fact "$japanese_facts" screen_transition_count)"
    japanese_route_transitions="$(read_number_fact "$japanese_facts" route_transitions)"
    japanese_stages="$(read_fact "$japanese_facts" candidate_stage_count || true)"
  fi
  if [[ "$status" == "passed" ]]; then
    candidate_ok=true
  fi

  mkdir -p "$ARTIFACT_ROOT"
  temporary_file="$(mktemp "$ARTIFACT_ROOT/.manifest.XXXXXX")"
  jq -n \
    --arg status "$status" \
    --arg source "$source_commit" \
    --arg failure_locale "$failure_locale" \
    --arg failure_reason "$failure_reason" \
    --arg english_stages "$english_stages" \
    --arg japanese_stages "$japanese_stages" \
    --argjson candidate_ok "$candidate_ok" \
    --argjson english_external_writes "${english_external_writes:-0}" \
    --argjson english_transcript_rows "${english_transcript_rows:-0}" \
    --argjson english_screen_transitions "${english_screen_transitions:-0}" \
    --argjson english_route_transitions "${english_route_transitions:-0}" \
    --argjson japanese_external_writes "${japanese_external_writes:-0}" \
    --argjson japanese_transcript_rows "${japanese_transcript_rows:-0}" \
    --argjson japanese_screen_transitions "${japanese_screen_transitions:-0}" \
    --argjson japanese_route_transitions "${japanese_route_transitions:-0}" \
    '{
      schema: "suisui.core_value_loop.v1",
      status: $status,
      sourceCommit: $source,
      candidate: {
        locales: ["english", "japanese"],
        sameJobID: $candidate_ok,
        buildMatchesSource: $candidate_ok,
        resultMatchesSource: $candidate_ok
      },
      journey: {
        route: "normal-product-secretary",
        inputMode: "typed-AX",
        handoff: "input-proposal-queue-result-receipt",
        observations: {
          english: {
            candidateStages: $english_stages,
            externalWrites: $english_external_writes,
            transcriptRowsObserved: $english_transcript_rows,
            screenTransitions: $english_screen_transitions,
            routeTransitions: $english_route_transitions
          },
          japanese: {
            candidateStages: $japanese_stages,
            externalWrites: $japanese_external_writes,
            transcriptRowsObserved: $japanese_transcript_rows,
            screenTransitions: $japanese_screen_transitions,
            routeTransitions: $japanese_route_transitions
          }
        }
      },
      manualVoiceOver: "not-run",
      realAudio: "not-run",
      externalCalendar: "not-run",
      failure: {
        locale: (if $failure_locale == "" then null else $failure_locale end),
        reason: (if $failure_reason == "" then null else $failure_reason end)
      }
    }' >"$temporary_file"
  contains_rejected_evidence "$temporary_file" && {
    rm -f "$temporary_file"
    return 1
  }
  mv -f "$temporary_file" "$manifest_file"
}

main() {
  [[ $# -eq 0 ]] || { usage; exit 2; }
  command -v git >/dev/null 2>&1 || { status="failed"; failure_reason="git_unavailable"; write_manifest; exit 1; }
  command -v jq >/dev/null 2>&1 || { status="failed"; failure_reason="jq_unavailable"; write_manifest; exit 1; }
  [[ -x "$CONTINUITY_SCRIPT" ]] || { status="failed"; failure_reason="continuity_script_missing"; write_manifest; exit 1; }
  source_commit="$(git -C "$ROOT_DIR" rev-parse HEAD)" || {
    status="failed"
    failure_reason="source_commit_unavailable"
    write_manifest
    exit 1
  }
  [[ -z "$(git -C "$ROOT_DIR" status --porcelain --untracked-files=all)" ]] || {
    status="failed"
    failure_reason="source_tree_not_clean"
    write_manifest
    exit 1
  }
  run_locale english || status="failed"
  if [[ "$status" == "passed" ]]; then
    run_locale japanese || status="failed"
  fi
  write_manifest || {
    printf '%s\n' "BLOCKER: core value loop manifest could not be written safely" >&2
    exit 1
  }
  if [[ "$status" != "passed" ]]; then
    printf 'BLOCKER: core value loop locale=%s reason=%s artifact=%s\n' "$failure_locale" "$failure_reason" "$ARTIFACT_ROOT/manifest.json" >&2
    exit 1
  fi
  printf 'OK: core value loop passed (2 locales, source %s, artifact %s)\n' "$source_commit" "$ARTIFACT_ROOT/manifest.json"
}

main "$@"
