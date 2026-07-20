#!/usr/bin/env bash
set -u -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BLOCKERS=()

cd "$ROOT_DIR"

section() {
  printf "\n== %s ==\n" "$1"
}

add_blocker() {
  BLOCKERS+=("$1")
  printf "BLOCKER: %s\n" "$1"
}

redact_sensitive_line() {
  local line="$1"
  local lowered
  local root_path="${ROOT_DIR%/}"
  local root_prefix="${root_path}/"
  lowered="$(printf "%s" "$line" | tr '[:upper:]' '[:lower:]')"
  case "$lowered" in
    *password*|*token*|*secret*|*"private key"*|*credential*|*"certificate material"*)
      printf "[redacted sensitive diagnostic line]"
      ;;
    *)
      line="${line//$root_prefix/}"
      line="${line//$root_path/}"
      printf "%s" "$line"
      ;;
  esac
}

print_redacted_output() {
  local output="$1"
  local line

  while IFS= read -r line; do
    redact_sensitive_line "$line"
    printf "\n"
  done <<<"$output"
}

check_developer_id_identities() {
  local output
  local status

  section "Developer ID identities"
  if ! command -v security >/dev/null 2>&1; then
    add_blocker "security command is unavailable; inspect Developer ID identities on the release machine"
    return 0
  fi

  output="$(security find-identity -p codesigning -v 2>&1)"
  status=$?
  if [[ -n "$output" ]]; then
    print_redacted_output "$output"
  fi
  if [[ "$status" -ne 0 ]]; then
    add_blocker "security find-identity -p codesigning -v failed"
    return 0
  fi
  if ! grep -F "Developer ID Application:" <<<"$output" >/dev/null; then
    add_blocker "no Developer ID Application identities found"
  fi
}

check_local_env_files() {
  local env_file

  section "Local release config files"
  for env_file in packaging/signing.env packaging/notarization.env packaging/sparkle.env; do
    if [[ -f "$ROOT_DIR/$env_file" ]]; then
      printf "OK: local release config exists: %s\n" "$env_file"
    else
      add_blocker "missing local release config: $env_file"
    fi
  done
}

run_diagnostic() {
  local display="$1"
  shift
  local output
  local status

  section "$display"
  if [[ "$#" -eq 1 && "$1" == ./* && ! -x "$ROOT_DIR/${1#./}" ]]; then
    add_blocker "missing executable release machine diagnostic: $display"
    return 0
  fi

  output="$("$@" 2>&1)"
  status=$?
  if [[ -n "$output" ]]; then
    print_redacted_output "$output"
  fi
  if [[ "$status" -ne 0 ]]; then
    add_blocker "release machine diagnostic failed: $display"
  else
    printf "OK: release machine diagnostic passed: %s\n" "$display"
  fi
}

printf "Suisui release machine local doctor\n"
printf "Do not paste Developer ID certificate material, notary credentials, Sparkle private keys, tokens, or passwords into shared logs or action summaries.\n"

check_developer_id_identities
check_local_env_files
run_diagnostic "./script/verify_signing_setup.sh" ./script/verify_signing_setup.sh
run_diagnostic \
  "SUISUI_RELEASE_PREFLIGHT_ONLINE=1 ./script/verify_notarization_setup.sh" \
  env SUISUI_RELEASE_PREFLIGHT_ONLINE=1 ./script/verify_notarization_setup.sh
run_diagnostic \
  "SUISUI_BUILD_CONFIGURATION=release SUISUI_SPARKLE_CONFIG_QUIET=1 ./script/validate_sparkle_release_config.sh" \
  env SUISUI_BUILD_CONFIGURATION=release SUISUI_SPARKLE_CONFIG_QUIET=1 ./script/validate_sparkle_release_config.sh
run_diagnostic "./script/verify_release_environment.sh" ./script/verify_release_environment.sh

if [[ "${#BLOCKERS[@]}" -gt 0 ]]; then
  printf "\n== Blockers ==\n"
  for blocker in "${BLOCKERS[@]}"; do
    printf -- "- BLOCKER: %s\n" "$blocker"
  done
  printf "\nNOT READY: release machine local doctor found %s blocker(s).\n" "${#BLOCKERS[@]}"
  exit 2
fi

printf "\nOK: release machine local doctor passed\n"
