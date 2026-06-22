#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

TOKEN_PATTERNS=(
  'sk-[A-Za-z0-9_-]{16,}'
  'xox[baprs]-[A-Za-z0-9-]{10,}'
  'ghp_[A-Za-z0-9]{20,}'
  'github_pat_[A-Za-z0-9_]{20,}'
  'AIza[0-9A-Za-z_-]{20,}'
  'AKIA[0-9A-Z]{16}'
  '-----BEGIN (RSA |EC |OPENSSH |)PRIVATE KEY-----'
)

KEYCHAIN_REFERENCE_ALLOWLIST=(
  'Keychain'
  'SecretStore'
  'SecItem'
  'keychain reference'
)

RAW_SECRET_DENYLIST=(
  'api[_-]?key[[:space:]]*[:=][[:space:]]*["'\''][^"'\'']{8,}'
  'OAUTH[^[:space:]]*(token|secret)[[:space:]]*[:=][[:space:]]*["'\''][^"'\'']{8,}'
  'MCP[^[:space:]]*(token|secret)[[:space:]]*[:=][[:space:]]*["'\''][^"'\'']{8,}'
  'NOTARY[^[:space:]]*password[[:space:]]*[:=][[:space:]]*["'\''][^"'\'']{8,}'
)

SCAN_PATHS=(
  "Tests/SoloPMCoreTests/Fixtures"
  "docs/release/evidence"
  "docs/release/evidence/ui-screenshots"
  "packaging"
)

RUNTIME_SMOKE_ARTIFACT_PATHS=(
  ".tmp/runtime-workflow-smoke"
  ".tmp/voiceover-review"
  ".tmp/project-board-state-restoration"
  ".tmp/layout-stability"
  ".tmp/project-board-header-layout-smoke"
)

if [[ "${SOLOPM_SECURITY_SCAN_INCLUDE_TMP:-0}" == "1" ]]; then
  SCAN_PATHS+=(".tmp")
fi

if [[ -n "${SOLOPM_SECURITY_SCAN_EXTRA_PATHS:-}" ]]; then
  IFS=':' read -r -a extra_scan_paths <<<"$SOLOPM_SECURITY_SCAN_EXTRA_PATHS"
  SCAN_PATHS+=("${extra_scan_paths[@]}")
fi

if ! grep -Fx "/.tmp/" "$ROOT_DIR/.gitignore" >/dev/null; then
  echo "BLOCKER: Runtime smoke artifact root /.tmp/ is not ignored by .gitignore" >&2
  exit 1
fi

for artifact_path in "${RUNTIME_SMOKE_ARTIFACT_PATHS[@]}"; do
  if ! git -C "$ROOT_DIR" check-ignore -q "$artifact_path/sentinel.md"; then
    echo "BLOCKER: runtime smoke artifact path is not ignored: $artifact_path" >&2
    exit 1
  fi
done

if ! command -v rg >/dev/null 2>&1; then
  echo "BLOCKER: rg is required for security regression scanning" >&2
  exit 1
fi

collect_files() {
  local relative_path
  for relative_path in "${SCAN_PATHS[@]}"; do
    local absolute_path="$ROOT_DIR/$relative_path"
    if [[ -d "$absolute_path" ]]; then
      find "$absolute_path" -type f -print
    elif [[ -f "$absolute_path" ]]; then
      printf '%s\n' "$absolute_path"
    fi
  done
}

scan_pattern_group() {
  local label="$1"
  shift
  local pattern
  local file
  local failed=0

  while IFS= read -r file; do
    for pattern in "$@"; do
      if LC_ALL=C rg -a -n --pcre2 -i -- "$pattern" "$file" >/dev/null; then
        printf 'BLOCKER: %s matched in %s\n' "$label" "${file#"$ROOT_DIR/"}" >&2
        failed=1
      fi
    done
  done < <(collect_files)

  return "$failed"
}

failure_count=0
if ! scan_pattern_group "secret-like token" "${TOKEN_PATTERNS[@]}"; then
  failure_count=$((failure_count + 1))
fi
if ! scan_pattern_group "raw secret assignment" "${RAW_SECRET_DENYLIST[@]}"; then
  failure_count=$((failure_count + 1))
fi

if [[ "$failure_count" -ne 0 ]]; then
  echo "BLOCKER: security regression scan found secret-like material in fixture, screenshot metadata, release evidence, or packaging artifacts" >&2
  exit 1
fi

printf 'OK: security regression scan passed for fixtures, screenshot metadata, release evidence, packaging, Keychain references, OAuth, MCP, NOTARY, and runtime smoke artifacts\n'
