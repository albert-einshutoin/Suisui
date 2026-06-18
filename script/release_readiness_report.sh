#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BLOCKER_COUNT=0
MOCK_PATTERN="(?i:fake|mock|demo|canned|stub|skeleton|todo|fixme|not[[:space:]_-]*implemented|notimplemented|inmemory)|(?i:(^|[^[:alnum:]_])(sample|placeholder)([^[:alnum:]_]|$))|Static[A-Za-z0-9_]*|:memory:|fatalError|preconditionFailure"
RUNTIME_SOURCE_DIRS=(
  "$ROOT_DIR/Sources/SoloPMCore"
  "$ROOT_DIR/Sources/SoloPMApp"
  "$ROOT_DIR/Sources/SoloPMCLI"
)

section() {
  printf "\n== %s ==\n" "$1"
}

blocker() {
  BLOCKER_COUNT=$((BLOCKER_COUNT + 1))
  printf "BLOCKER: %s\n" "$1"
}

printf "SoloPM release readiness report\n"

section "Runtime mock/fake scan"
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
        blocker "runtime source contains mock/fake/demo/test-only markers"
        ;;
      1)
        printf "OK: no runtime mock/fake/demo markers in Sources/SoloPMCore Sources/SoloPMApp Sources/SoloPMCLI\n"
        ;;
      *)
        if [[ -n "$scan_output" ]]; then
          printf "%s\n" "$scan_output"
        fi
        blocker "runtime mock/fake scan failed"
        ;;
    esac
  fi
fi

section "Phase checklist blockers"
phase_unchecked=""
if [[ -d "$ROOT_DIR/tasks" ]]; then
  while IFS= read -r phase_file; do
    phase_name="$(basename "$phase_file")"
    case "$phase_name" in
      Phase[0-9].md|Phase[0-9]-*.md|Phase10.md|Phase10-*.md)
        unchecked_items="$(rg -n --with-filename -- "- \\[ \\]" "$phase_file" || true)"
        if [[ -n "$unchecked_items" ]]; then
          if [[ -n "$phase_unchecked" ]]; then
            phase_unchecked+=$'\n'
          fi
          phase_unchecked+="$unchecked_items"
        fi
        ;;
    esac
  done < <(find "$ROOT_DIR/tasks" -maxdepth 1 -type f -name 'Phase*.md' | sort)
else
  blocker "missing tasks directory"
fi
readme_template_unchecked="$(rg -n -g '*.md' -- "- \\[ \\]" "$ROOT_DIR/tasks/README.md" || true)"

if [[ -n "$phase_unchecked" ]]; then
  printf "%s\n" "$phase_unchecked"
  blocker "phase checklist still has unchecked release/manual gates"
else
  printf "OK: no unchecked items in release phase checklists (Phase0-Phase10)\n"
fi

if [[ -n "$readme_template_unchecked" ]]; then
  printf "INFO: tasks/README.md contains unchecked template examples and is not counted as a release blocker.\n"
fi

section "Release environment preflight"
set +e
preflight_output="$("$ROOT_DIR/script/verify_release_environment.sh" 2>&1)"
preflight_status=$?
set -e

printf "%s\n" "$preflight_output"
if [[ "$preflight_status" -ne 0 ]]; then
  blocker "release environment preflight did not pass"
else
  printf "OK: release environment preflight passed\n"
fi

section "Summary"
if [[ "$BLOCKER_COUNT" -gt 0 ]]; then
  printf "NOT READY: %d blocker group(s) remain.\n" "$BLOCKER_COUNT"
  exit 2
fi

printf "READY: runtime, task checklist, and release environment gates passed.\n"
