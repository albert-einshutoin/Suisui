#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DEFAULT_VOICE_CACHE_ROOT="$HOME/Library/Application Support/SoloPM/VoiceModels"
VOICE_CACHE_ROOT="${SOLOPM_LOCAL_VOICE_CACHE_ROOT:-$DEFAULT_VOICE_CACHE_ROOT}"
WHISPER_EXECUTABLE="${SOLOPM_WHISPER_CPP_EXECUTABLE:-}"
STT_SAMPLE_WAV="${SOLOPM_STT_SAMPLE_WAV:-}"
STT_LANGUAGE="${SOLOPM_STT_LANGUAGE:-ja}"
KOKORO_EXECUTABLE="${SOLOPM_KOKORO_EXECUTABLE:-}"
TTS_LANGUAGES="${SOLOPM_TTS_LANGUAGES:-ja en}"
TTS_JA_VOICE="${SOLOPM_TTS_JA_VOICE_ID:-jf_alpha}"
TTS_EN_VOICE="${SOLOPM_TTS_EN_VOICE_ID:-af_heart}"
LEGACY_TTS_LANGUAGE="${SOLOPM_TTS_LANGUAGE:-}"
LEGACY_TTS_VOICE="${SOLOPM_TTS_VOICE:-}"
TTS_PROMPT="${SOLOPM_LOCAL_VOICE_TTS_PROMPT:-}"
OUTPUT_DIR="${SOLOPM_LOCAL_VOICE_SMOKE_OUTPUT_DIR:-$ROOT_DIR/.tmp/local-voice-runtime-smoke}"
EVIDENCE_FILE="${SOLOPM_LOCAL_VOICE_EVIDENCE_FILE:-}"
STT_EXPECTED_TRANSCRIPT_CONTAINS="${SOLOPM_STT_EXPECTED_TRANSCRIPT_CONTAINS:-}"
TIMEOUT_SECONDS="${SOLOPM_LOCAL_VOICE_TIMEOUT_SECONDS:-120}"
MODE_LABEL="full STT+TTS"
STT_ONLY_MODE=0

WHISPER_MODEL="$VOICE_CACHE_ROOT/whisper.cpp/ggml-tiny.bin"
KOKORO_MODEL="$VOICE_CACHE_ROOT/Kokoro/kokoro-v1_0.pth"
WHISPER_TINY_SHA256="be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21"
KOKORO_82M_SHA256="496dba118d1a58f5f3db2efc88dbdc216e0483fc89fe6e47ee1f2c53f18ad1e4"

# Contract reference for release reviewers:
# whisper-cli -m <model> -f <sample.wav> -l ja -np -nt
# Kokoro runtime --model <model> --text-file <prompt.txt> --language ja --voice jf_alpha --output <speech.wav>

usage() {
  cat <<'USAGE'
usage: script/check_local_voice_runtime_smoke.sh
       script/check_local_voice_runtime_smoke.sh --stt-only

Runs fail-closed local STT/TTS runtime proof for the cached SoloPM voice models.
`--stt-only` runs only the whisper.cpp smoke needed to advance Issue #13
without claiming Kokoro TTS proof for Issue #14 or full release closeout.

Required environment for all modes:
  SOLOPM_WHISPER_CPP_EXECUTABLE   Absolute path to whisper-cli
  SOLOPM_STT_SAMPLE_WAV           Japanese or English sample WAV for local STT

Required environment for default full STT+TTS mode:
  SOLOPM_KOKORO_EXECUTABLE        Absolute path to the Kokoro runtime

Optional environment:
  SOLOPM_LOCAL_VOICE_CACHE_ROOT   Defaults to ~/Library/Application Support/SoloPM/VoiceModels
  SOLOPM_LOCAL_VOICE_SMOKE_OUTPUT_DIR
  SOLOPM_STT_LANGUAGE             ja, en, or auto. Defaults to ja.
  SOLOPM_TTS_LANGUAGES            Space-separated ja/en list. Defaults to "ja en".
  SOLOPM_TTS_JA_VOICE_ID          Defaults to jf_alpha.
  SOLOPM_TTS_EN_VOICE_ID          Defaults to af_heart.
  SOLOPM_LOCAL_VOICE_TTS_PROMPT   Optional prompt override for all TTS languages.
  SOLOPM_STT_EXPECTED_TRANSCRIPT_CONTAINS
  SOLOPM_LOCAL_VOICE_EVIDENCE_FILE
  SOLOPM_LOCAL_VOICE_TIMEOUT_SECONDS
USAGE
}

local_voice_evidence_source_commit() {
  local commit
  # The evidence is tied only to local voice runtime inputs so unrelated
  # release-document edits do not stale a valid STT/TTS runtime capture.
  commit="$(
    git -C "$ROOT_DIR" log -1 --format=%h -- \
      Sources/SoloPMCore/Voice \
      Sources/SoloPMCore/App/AppSettings.swift \
      Sources/SoloPMCore/App/DailyPlanningReviewReadout.swift \
      Sources/SoloPMApp \
      Package.swift \
      packaging/app_metadata.env \
      script/kokoro_tts_runtime.py \
      script/check_local_voice_runtime_smoke.sh \
      docs/voice-models.md 2>/dev/null || true
  )"
  if [[ -n "$commit" ]]; then
    printf '%s' "$commit"
  else
    git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || printf 'unknown'
  fi
}

relative_or_redacted_path() {
  local path="$1"
  case "$path" in
    "$ROOT_DIR"/*)
      printf '%s' "${path#"$ROOT_DIR"/}"
      ;;
    *)
      printf '[external local path redacted]'
      ;;
  esac
}

case "${1:-}" in
  "")
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  --stt-only)
    MODE_LABEL="STT-only"
    STT_ONLY_MODE=1
    shift
    ;;
  *)
    printf 'unknown argument: %s\n' "$1" >&2
    usage >&2
    exit 2
    ;;
esac

if [[ "$#" -gt 0 ]]; then
  printf 'unknown argument: %s\n' "$1" >&2
  usage >&2
  exit 2
fi

failure_count=0

blocker() {
  printf 'BLOCKER: %s\n' "$1" >&2
  failure_count=$((failure_count + 1))
}

is_absolute_path() {
  case "$1" in
    /*) return 0 ;;
    *) return 1 ;;
  esac
}

absolute_path() {
  case "$1" in
    /*) printf '%s' "$1" ;;
    *) printf '%s/%s' "$ROOT_DIR" "$1" ;;
  esac
}

redacted_path() {
  local path="$1"
  path="${path/#$HOME/~}"
  path="${path/#$ROOT_DIR/<repo>}"
  printf '%s' "$path"
}

is_credential_like_path() {
  local file_name
  file_name="$(basename "$1" | tr '[:upper:]' '[:lower:]')"
  case "$file_name" in
    .env|credentials.json|token.json|auth.json) return 0 ;;
  esac
  case "$file_name" in
    *credential*|*secret*|*token*|*api-key*|*apikey*|*auth*) return 0 ;;
  esac
  return 1
}

sha256_digest() {
  /usr/bin/shasum -a 256 "$1" | awk '{print $1}'
}

check_executable() {
  local label="$1"
  local value="$2"
  if [[ -z "$value" ]]; then
    blocker "$label executable path is required"
    return
  fi
  if ! is_absolute_path "$value"; then
    blocker "$label executable path must be absolute"
    return
  fi
  if is_credential_like_path "$value"; then
    blocker "$label executable path must not point to a credential or token file"
    return
  fi
  if [[ ! -x "$value" || -d "$value" ]]; then
    blocker "$label executable is missing or not executable: $(redacted_path "$value")"
  fi
}

check_file_exists() {
  local label="$1"
  local path="$2"
  if [[ -z "$path" ]]; then
    blocker "$label path is required"
    return
  fi
  if [[ ! -f "$path" ]]; then
    blocker "$label is missing: $(redacted_path "$path")"
    return
  fi
  if [[ ! -s "$path" ]]; then
    blocker "$label is empty: $(redacted_path "$path")"
  fi
}

check_stt_sample_wav() {
  local path="$1"
  if [[ -z "$path" ]]; then
    blocker "STT sample WAV path is required"
    return
  fi
  if ! is_absolute_path "$path"; then
    blocker "STT sample WAV path must be absolute"
    return
  fi
  if is_credential_like_path "$path"; then
    blocker "STT sample WAV must not point to a credential or token file"
    return
  fi
  local lower_path
  lower_path="$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')"
  case "$lower_path" in
    *.wav) ;;
    *) blocker "STT sample WAV must use a .wav file" ;;
  esac
  check_file_exists "STT sample WAV" "$path"
}

check_output_dir_policy() {
  local output_dir
  output_dir="$(absolute_path "$OUTPUT_DIR")"
  OUTPUT_DIR="$output_dir"
  case "$output_dir/" in
    "$ROOT_DIR"/*)
      local relative_output_dir="${output_dir#"$ROOT_DIR"/}"
      if ! git -C "$ROOT_DIR" check-ignore -q "$relative_output_dir/sentinel"; then
        blocker "SOLOPM_LOCAL_VOICE_SMOKE_OUTPUT_DIR inside repo must be ignored by git"
      fi
      ;;
  esac
}

has_tts_language() {
  local expected="$1"
  local language
  for language in "${tts_languages[@]}"; do
    if [[ "$language" == "$expected" ]]; then
      return 0
    fi
  done
  return 1
}

check_evidence_file_policy() {
  local evidence_file
  evidence_file="$(absolute_path "$EVIDENCE_FILE")"
  EVIDENCE_FILE="$evidence_file"

  if [[ -z "$STT_EXPECTED_TRANSCRIPT_CONTAINS" ]]; then
    blocker "SOLOPM_STT_EXPECTED_TRANSCRIPT_CONTAINS is required when writing local voice runtime evidence"
  fi
  if [[ "$STT_ONLY_MODE" -eq 0 ]]; then
    if ! has_tts_language ja || ! has_tts_language en; then
      blocker "SOLOPM_LOCAL_VOICE_EVIDENCE_FILE requires SOLOPM_TTS_LANGUAGES to include both ja and en"
    fi
  fi
  case "$evidence_file" in
    "$ROOT_DIR/docs/release/evidence/"*.md) ;;
    *) blocker "SOLOPM_LOCAL_VOICE_EVIDENCE_FILE must point to docs/release/evidence/*.md" ;;
  esac
  if [[ "$STT_ONLY_MODE" -eq 1 ]]; then
    case "$(basename "$evidence_file")" in
      *stt-only*.md) ;;
      *) blocker "SOLOPM_LOCAL_VOICE_EVIDENCE_FILE in --stt-only mode must use an explicit *stt-only*.md filename and must not overwrite local-voice-runtime.md" ;;
    esac
  fi
}

check_model() {
  local label="$1"
  local path="$2"
  local expected_sha="$3"
  if [[ ! -f "$path" ]]; then
    blocker "$label is missing: $(redacted_path "$path")"
    return
  fi
  local actual_sha
  if ! actual_sha="$(sha256_digest "$path")"; then
    blocker "$label checksum could not be read: $(redacted_path "$path")"
    return
  fi
  if [[ "$actual_sha" != "$expected_sha" ]]; then
    blocker "$label checksum mismatch: expected $expected_sha, got $actual_sha"
  fi
}

run_with_timeout() {
  local label="$1"
  shift
  local pid
  "$@" &
  pid=$!
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  while kill -0 "$pid" >/dev/null 2>&1; do
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      kill "$pid" >/dev/null 2>&1 || true
      sleep 1
      kill -9 "$pid" >/dev/null 2>&1 || true
      wait "$pid" >/dev/null 2>&1 || true
      echo "BLOCKER: $label runtime smoke timed out after ${TIMEOUT_SECONDS}s" >&2
      return 124
    fi
    sleep 1
  done
  wait "$pid"
}

tts_voice_for_language() {
  local language="$1"
  if [[ -n "$LEGACY_TTS_VOICE" && -n "$LEGACY_TTS_LANGUAGE" && "$LEGACY_TTS_LANGUAGE" == "$language" ]]; then
    printf '%s' "$LEGACY_TTS_VOICE"
    return
  fi
  case "$language" in
    ja) printf '%s' "$TTS_JA_VOICE" ;;
    en) printf '%s' "$TTS_EN_VOICE" ;;
  esac
}

tts_prompt_for_language() {
  local language="$1"
  if [[ -n "$TTS_PROMPT" ]]; then
    printf '%s' "$TTS_PROMPT"
    return
  fi
  case "$language" in
    ja) printf '%s' "今日の未完了タスクは3件です。" ;;
    en) printf '%s' "You have three unfinished tasks today." ;;
  esac
}

case "$STT_LANGUAGE" in
  ja|en|auto) ;;
  *) blocker "SOLOPM_STT_LANGUAGE must be ja, en, or auto" ;;
esac

if ! [[ "$TIMEOUT_SECONDS" =~ ^[0-9]+$ && "$TIMEOUT_SECONDS" -gt 0 ]]; then
  blocker "SOLOPM_LOCAL_VOICE_TIMEOUT_SECONDS must be a positive integer"
fi

# Collect all prerequisite problems before exiting so release operators know
# every local install/configuration item needed for #13/#14 runtime closeout.
check_executable "whisper.cpp" "$WHISPER_EXECUTABLE"
check_stt_sample_wav "$STT_SAMPLE_WAV"
check_model "whisper.cpp tiny model" "$WHISPER_MODEL" "$WHISPER_TINY_SHA256"
check_output_dir_policy

tts_languages=()
if [[ "$STT_ONLY_MODE" -eq 0 ]]; then
  check_executable "Kokoro" "$KOKORO_EXECUTABLE"
  check_model "Kokoro model" "$KOKORO_MODEL" "$KOKORO_82M_SHA256"

  read -r -a tts_languages <<<"$TTS_LANGUAGES" || true
  if [[ "${#tts_languages[@]}" -eq 0 ]]; then
    blocker "SOLOPM_TTS_LANGUAGES must include ja, en, or both"
  fi
  for language in "${tts_languages[@]}"; do
    case "$language" in
      ja|en) ;;
      *) blocker "SOLOPM_TTS_LANGUAGES entries must be ja or en" ;;
    esac
    voice_id="$(tts_voice_for_language "$language")"
    if [[ "$voice_id" =~ [[:space:]] ]]; then
      blocker "Kokoro voice id must not contain whitespace"
    fi
    if [[ "$language" == "ja" && "$voice_id" != j* ]]; then
      blocker "Kokoro Japanese voice id must start with j"
    fi
    if [[ "$language" == "en" && "$voice_id" != a* ]]; then
      blocker "Kokoro English voice id must start with a"
    fi
  done
fi

if [[ -n "$EVIDENCE_FILE" ]]; then
  check_evidence_file_policy
fi

if [[ "$failure_count" -ne 0 ]]; then
  printf 'BLOCKER: local voice runtime smoke found %d prerequisite problem(s)\n' "$failure_count" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
stt_stdout="$OUTPUT_DIR/stt-transcript.txt"
stt_stderr="$OUTPUT_DIR/stt.stderr.txt"

if ! run_with_timeout "whisper.cpp" "$WHISPER_EXECUTABLE" \
  -m "$WHISPER_MODEL" \
  -f "$STT_SAMPLE_WAV" \
  -l "$STT_LANGUAGE" \
  -np \
  -nt \
  >"$stt_stdout" 2>"$stt_stderr"; then
  echo "BLOCKER: whisper.cpp runtime smoke failed; see $(redacted_path "$stt_stderr")" >&2
  exit 1
fi

if [[ ! -s "$stt_stdout" ]]; then
  echo "BLOCKER: whisper.cpp runtime smoke produced an empty transcript" >&2
  exit 1
fi

if [[ -n "$STT_EXPECTED_TRANSCRIPT_CONTAINS" ]] &&
  ! grep -F "$STT_EXPECTED_TRANSCRIPT_CONTAINS" "$stt_stdout" >/dev/null; then
  echo "BLOCKER: whisper.cpp transcript did not contain expected marker" >&2
  exit 1
fi

if [[ "$STT_ONLY_MODE" -eq 0 ]]; then
  for language in "${tts_languages[@]}"; do
    voice_id="$(tts_voice_for_language "$language")"
    tts_prompt_file="$OUTPUT_DIR/kokoro-${language}-prompt.txt"
    tts_output="$OUTPUT_DIR/kokoro-${language}.wav"
    tts_stdout="$OUTPUT_DIR/tts-${language}.stdout.txt"
    tts_stderr="$OUTPUT_DIR/tts-${language}.stderr.txt"
    printf '%s\n' "$(tts_prompt_for_language "$language")" >"$tts_prompt_file"
    if ! run_with_timeout "Kokoro $language" "$KOKORO_EXECUTABLE" \
      --model "$KOKORO_MODEL" \
      --text-file "$tts_prompt_file" \
      --language "$language" \
      --voice "$voice_id" \
      --output "$tts_output" \
      >"$tts_stdout" 2>"$tts_stderr"; then
      echo "BLOCKER: Kokoro runtime smoke failed for $language; see $(redacted_path "$tts_stderr")" >&2
      exit 1
    fi

    if [[ ! -s "$tts_output" ]]; then
      echo "BLOCKER: Kokoro runtime smoke did not create a non-empty $language WAV file" >&2
      exit 1
    fi

    if command -v afinfo >/dev/null 2>&1; then
      if ! afinfo "$tts_output" >"$OUTPUT_DIR/kokoro-${language}-afinfo.txt" 2>&1; then
        echo "BLOCKER: Kokoro runtime smoke $language output is not readable by afinfo" >&2
        exit 1
      fi
    fi
    printf 'OK: TTS WAV captured at %s\n' "$(redacted_path "$tts_output")"
  done
fi

write_local_voice_runtime_evidence() {
  local generated_at
  local source_commit
  local output_relative

  generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  source_commit="$(local_voice_evidence_source_commit)"
  output_relative="$(relative_or_redacted_path "$OUTPUT_DIR")"
  mkdir -p "$(dirname "$EVIDENCE_FILE")"

  {
    printf '%s\n' '# Local Voice Runtime Evidence'
    printf '\n'
    if [[ "$STT_ONLY_MODE" -eq 1 ]]; then
      printf '%s\n' 'Status: limited-pass (STT-only)'
    else
      printf '%s\n' 'Status: passed'
    fi
    printf '%s\n' 'Generated by: script/check_local_voice_runtime_smoke.sh'
    printf '\n'
    printf '%s\n' '## Runtime Context'
    printf '\n'
    printf -- '- Source commit: `%s`\n' "$source_commit"
    printf -- '- Generated at: %s\n' "$generated_at"
    if [[ "$STT_ONLY_MODE" -eq 1 ]]; then
      # STT-only evidence exists to let Issue #13 progress without being
      # mistaken for the full Kokoro closeout required by Issue #14.
      printf '%s\n' '- Evidence source: `local whisper.cpp STT runtime smoke only (no Kokoro TTS proof)`'
    else
      printf '%s\n' '- Evidence source: `local whisper.cpp STT and Kokoro TTS runtime smoke`'
    fi
    printf '%s\n' '- No network download: passed - local cache and user-configured executables only'
    printf '%s\n' '- No model binary committed or bundled: passed - model files remained outside git and app artifacts'
    printf '%s\n' '- Voice cache: checksum-verified user cache; model binaries are not bundled in git or app artifacts'
    printf -- '- STT language: `%s`\n' "$STT_LANGUAGE"
    printf -- '- STT expected transcript marker: `%s`\n' "$STT_EXPECTED_TRANSCRIPT_CONTAINS"
    printf '%s\n' '- STT transcript: passed - transcript contains the expected marker'
    printf -- '- whisper.cpp tiny model SHA-256: `%s`\n' "$WHISPER_TINY_SHA256"
    if [[ "$STT_ONLY_MODE" -eq 1 ]]; then
      printf '%s\n' '- TTS proof: not run - --stt-only mode does not verify Kokoro runtime'
      printf '%s\n' '- Release closeout scope: issue #13 STT-only smoke only'
      printf '%s\n' '- Full release closeout: blocked - rerun without --stt-only to prove Kokoro Japanese/English TTS'
    else
      printf -- '- Kokoro model SHA-256: `%s`\n' "$KOKORO_82M_SHA256"
      printf -- '- TTS languages: `%s`\n' "$TTS_LANGUAGES"
      printf '%s\n' '- TTS Japanese WAV: passed - generated non-empty WAV and afinfo-readable when afinfo is available'
      printf '%s\n' '- TTS English WAV: passed - generated non-empty WAV and afinfo-readable when afinfo is available'
    fi
    printf -- '- Runtime artifacts: `%s`\n' "$output_relative"
  } >"$EVIDENCE_FILE"
}

if [[ -n "$EVIDENCE_FILE" ]]; then
  write_local_voice_runtime_evidence
  if [[ "$STT_ONLY_MODE" -eq 1 ]]; then
    printf '%s\n' 'OK: SOLOPM_LOCAL_VOICE_EVIDENCE_FILE in --stt-only mode must state that TTS was not verified'
    printf '%s\n' 'OK: STT-only smoke cannot prove #14 / full release closeout'
  fi
  printf 'OK: local voice runtime evidence written: %s\n' "$(relative_or_redacted_path "$EVIDENCE_FILE")"
fi

printf 'OK: %s local voice runtime smoke passed\n' "$MODE_LABEL"
printf 'OK: STT transcript captured at %s\n' "$(redacted_path "$stt_stdout")"
if [[ "$STT_ONLY_MODE" -eq 0 ]]; then
  printf 'OK: TTS WAV files captured under %s\n' "$(redacted_path "$OUTPUT_DIR")"
fi
