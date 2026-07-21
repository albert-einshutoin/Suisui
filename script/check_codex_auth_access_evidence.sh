#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [[ "${SUISUI_CODEX_RUN_AUTH_ACCESS_EVIDENCE:-0}" != "1" ]]; then
  echo "Codex auth-access evidence is opt-in and requires an administrator filesystem trace."
  echo "Run with SUISUI_CODEX_RUN_AUTH_ACCESS_EVIDENCE=1 and optionally SUISUI_CODEX_EXECUTABLE=/absolute/path/to/codex."
  exit 2
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Codex auth-access evidence requires macOS fs_usage." >&2
  exit 1
fi

codex_executable="${SUISUI_CODEX_EXECUTABLE:-}"
if [[ -z "$codex_executable" ]]; then
  codex_executable="$(command -v codex || true)"
fi
if [[ "$codex_executable" != /* || ! -x "$codex_executable" ]]; then
  echo "A valid absolute Codex executable path is required." >&2
  exit 1
fi

audit_dir="$(mktemp -d "${TMPDIR:-/tmp}/suisui-codex-auth-audit.XXXXXX")"
wrapper_path="$audit_dir/codex-auth-audit-wrapper"
test_log="$audit_dir/test.log"
trace_log="$audit_dir/fs-usage.log"
auth_lines="$audit_dir/auth-access.log"
test_pid=""
trace_pid=""

cleanup() {
  if [[ -n "$test_pid" ]] && kill -0 "$test_pid" >/dev/null 2>&1; then
    kill "$test_pid" >/dev/null 2>&1 || true
  fi
  if [[ -n "$trace_pid" ]] && kill -0 "$trace_pid" >/dev/null 2>&1; then
    kill "$trace_pid" >/dev/null 2>&1 || true
  fi
  rm -rf "$audit_dir"
}
trap cleanup EXIT

/usr/bin/clang \
  -std=c11 \
  -O2 \
  -Wall \
  -Wextra \
  -Werror \
  "$ROOT_DIR/script/codex_auth_access_audit_wrapper.c" \
  -o "$wrapper_path"
chmod 0700 "$wrapper_path"
ln -s "$codex_executable" "${wrapper_path}.real-codex"

SUISUI_CODEX_AUTH_ACCESS_AUDIT=1 \
SUISUI_CODEX_AUTH_ACCESS_AUDIT_WRAPPER="$wrapper_path" \
swift test --filter CodexLocalRuntimeProviderTests/testLiveAuthStoreAccessIsObservableUnderChildPIDWhenExplicitlyAudited \
  >"$test_log" 2>&1 &
test_pid=$!

deadline=$((SECONDS + 30))
while [[ ! -s "${wrapper_path}.parent-pid" || ! -s "${wrapper_path}.child-pid" ]]; do
  if ! kill -0 "$test_pid" >/dev/null 2>&1; then
    echo "Codex auth-access audit test exited before publishing process identities." >&2
    sed -n '1,160p' "$test_log" >&2
    exit 1
  fi
  if (( SECONDS >= deadline )); then
    echo "Timed out waiting for PID-scoped Codex audit handshake." >&2
    exit 1
  fi
  sleep 0.05
done

parent_pid="$(tr -d '[:space:]' <"${wrapper_path}.parent-pid")"
child_pid="$(tr -d '[:space:]' <"${wrapper_path}.child-pid")"
if [[ ! "$parent_pid" =~ ^[1-9][0-9]*$ || ! "$child_pid" =~ ^[1-9][0-9]*$ || "$parent_pid" == "$child_pid" ]]; then
  echo "Invalid or non-distinct parent/child PID evidence." >&2
  exit 1
fi

observed_child_parent="$(ps -p "$child_pid" -o ppid= | tr -d '[:space:]')"
if [[ "$observed_child_parent" != "$parent_pid" ]]; then
  echo "Codex audit wrapper is not owned by the expected test parent PID." >&2
  exit 1
fi

if sudo -n true >/dev/null 2>&1; then
  sudo /usr/bin/fs_usage -e -w -f pathname -t 12 >"$trace_log" 2>&1 &
else
  /usr/bin/osascript - "$trace_log" <<'APPLESCRIPT' &
on run argv
  set tracePath to item 1 of argv
  set traceCommand to "/usr/bin/fs_usage -e -w -f pathname -t 12 >" & quoted form of tracePath & " 2>&1"
  do shell script traceCommand with administrator privileges
end run
APPLESCRIPT
fi
trace_pid=$!

trace_deadline=$((SECONDS + 180))
while [[ ! -f "$trace_log" ]]; do
  if ! kill -0 "$trace_pid" >/dev/null 2>&1; then
    echo "Administrator filesystem trace exited before it became ready." >&2
    exit 1
  fi
  if (( SECONDS >= trace_deadline )); then
    echo "Timed out waiting for administrator approval for PID-classified filesystem tracing." >&2
    exit 1
  fi
  sleep 0.1
done
sleep 0.5
touch "${wrapper_path}.ready"

test_status=0
wait "$test_pid" || test_status=$?
test_pid=""
wait "$trace_pid" || true
trace_pid=""
if [[ "$test_status" -ne 0 ]]; then
  echo "Codex auth-access audit live test failed." >&2
  sed -n '1,200p' "$test_log" >&2
  exit "$test_status"
fi

auth_path_suffix=".codex/auth.json"
LC_ALL=C grep -F -- "$auth_path_suffix" "$trace_log" >"$auth_lines" || true
parent_auth_access_count="$(grep -Ec "\\.${parent_pid}([[:space:]]|$)" "$auth_lines" || true)"
child_auth_access_count="$(grep -Ec "\\.${child_pid}([[:space:]]|$)" "$auth_lines" || true)"
total_auth_access_count="$(wc -l <"$auth_lines" | tr -d '[:space:]')"
unexpected_auth_access_count=$((total_auth_access_count - parent_auth_access_count - child_auth_access_count))

if [[ "$parent_auth_access_count" -ne 0 ]]; then
  echo "BLOCKER: Suisui parent process accessed the Codex auth store." >&2
  exit 1
fi
if [[ "$child_auth_access_count" -lt 1 ]]; then
  echo "BLOCKER: no Codex child auth-store access was observed; evidence is inconclusive." >&2
  exit 1
fi
if [[ "$unexpected_auth_access_count" -ne 0 ]]; then
  echo "BLOCKER: auth-store access from an unexpected PID was observed." >&2
  exit 1
fi

source_commit="$(git -C "$ROOT_DIR" log -1 --format=%H -- Sources Package.swift)"
generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
evidence_output="${SUISUI_CODEX_AUTH_ACCESS_EVIDENCE_OUTPUT:-$ROOT_DIR/.tmp/codex-auth-access-evidence.json}"
mkdir -p "$(dirname "$evidence_output")"
printf '{\n' >"$evidence_output"
printf '  "schemaVersion": 1,\n' >>"$evidence_output"
printf '  "status": "passed",\n' >>"$evidence_output"
printf '  "sourceCommit": "%s",\n' "$source_commit" >>"$evidence_output"
printf '  "generatedAt": "%s",\n' "$generated_at" >>"$evidence_output"
printf '  "credentialPathClass": "codex_user_auth_store",\n' >>"$evidence_output"
printf '  "parentPID": %s,\n' "$parent_pid" >>"$evidence_output"
printf '  "childPID": %s,\n' "$child_pid" >>"$evidence_output"
printf '  "parentAuthAccessCount": %s,\n' "$parent_auth_access_count" >>"$evidence_output"
printf '  "childAuthAccessCount": %s,\n' "$child_auth_access_count" >>"$evidence_output"
printf '  "unexpectedAuthAccessCount": %s\n' "$unexpected_auth_access_count" >>"$evidence_output"
printf '}\n' >>"$evidence_output"

echo "OK: PID-classified Codex auth-access evidence passed."
echo "evidence=$evidence_output"
