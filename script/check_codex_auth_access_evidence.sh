#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
auth_path_suffix=".codex/auth.json"
trace_filter_program='index($0, needle) { print; fflush() }'

if [[ "${1:-}" == "--run-root-traces" ]]; then
  if [[ "$EUID" -ne 0 || "$#" -ne 6 ]]; then
    echo "Root trace helper requires root and exact audited arguments." >&2
    exit 64
  fi
  system_trace_output="$2"
  parent_trace_output="$3"
  child_trace_output="$4"
  audited_parent_pid="$5"
  audited_child_pid="$6"
  if [[ "$system_trace_output" != /* || "$parent_trace_output" != /* || "$child_trace_output" != /* ||
        ! "$audited_parent_pid" =~ ^[1-9][0-9]*$ || ! "$audited_child_pid" =~ ^[1-9][0-9]*$ ||
        "$audited_parent_pid" == "$audited_child_pid" ]]; then
    echo "Root trace helper received unsafe output paths or process identities." >&2
    exit 64
  fi

  run_filtered_trace() {
    local trace_output="$1"
    shift
    /usr/bin/fs_usage -w -f pathname -t 75 "$@" 2>&1 \
      | LC_ALL=C /usr/bin/awk -v needle="$auth_path_suffix" "$trace_filter_program" >"$trace_output"
  }

  # Wide fs_usage output appends a thread ID, not a PID. Run PID-scoped
  # traces beside the system trace so ownership is proven by the sampler
  # itself while the count difference still detects unexpected processes.
  run_filtered_trace "$system_trace_output" -e &
  system_trace_pid=$!
  run_filtered_trace "$parent_trace_output" "$audited_parent_pid" &
  parent_trace_pid=$!
  run_filtered_trace "$child_trace_output" "$audited_child_pid" &
  child_trace_pid=$!

  system_trace_status=0
  parent_trace_status=0
  child_trace_status=0
  wait "$system_trace_pid" || system_trace_status=$?
  wait "$parent_trace_pid" || parent_trace_status=$?
  wait "$child_trace_pid" || child_trace_status=$?
  if [[ "$system_trace_status" -ne 0 || "$parent_trace_status" -ne 0 || "$child_trace_status" -ne 0 ]]; then
    exit 1
  fi
  exit 0
fi

if [[ "${SUISUI_CODEX_RUN_AUTH_ACCESS_EVIDENCE:-0}" != "1" ]]; then
  echo "Codex auth-access evidence is opt-in and requires an administrator filesystem trace."
  echo "Run with SUISUI_CODEX_RUN_AUTH_ACCESS_EVIDENCE=1 and optionally SUISUI_CODEX_EXECUTABLE=/absolute/path/to/codex."
  exit 2
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Codex auth-access evidence requires macOS fs_usage." >&2
  exit 1
fi

audited_paths=(
  Sources
  Package.swift
  Tests/SuisuiCoreTests/CodexLocalRuntimeProviderTests.swift
  script/check_codex_auth_access_evidence.sh
  script/codex_auth_access_audit_wrapper.c
)
if [[ -n "$(git -C "$ROOT_DIR" status --porcelain=v1 -- "${audited_paths[@]}")" ]]; then
  echo "Codex auth-access evidence requires a clean product and audit-harness source tree." >&2
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

codex_version_output="$("$codex_executable" --version 2>/dev/null || true)"
if [[ "$codex_version_output" == "codex-cli 0.144.1" ]]; then
  codex_version="0.144.1"
else
  echo "Codex version is not the exact Personal Preview verified build: codex-cli 0.144.1." >&2
  exit 1
fi

audit_dir="$(mktemp -d "${TMPDIR:-/tmp}/suisui-codex-auth-audit.XXXXXX")"
wrapper_path="$audit_dir/codex-auth-audit-wrapper"
test_log="$audit_dir/test.log"
trace_log="$audit_dir/fs-usage.log"
parent_trace_log="$audit_dir/fs-usage-parent.log"
child_trace_log="$audit_dir/fs-usage-child.log"
test_pid=""
trace_pid=""
evidence_temp=""

cleanup() {
  if [[ -n "$test_pid" ]] && kill -0 "$test_pid" >/dev/null 2>&1; then
    kill "$test_pid" >/dev/null 2>&1 || true
  fi
  if [[ -n "$trace_pid" ]] && kill -0 "$trace_pid" >/dev/null 2>&1; then
    kill "$trace_pid" >/dev/null 2>&1 || true
  fi
  if [[ -n "$evidence_temp" ]]; then
    rm -f "$evidence_temp"
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

root_trace_command=(
  # Administrator shells can be denied direct execution from removable
  # volumes; invoke the audited script through the system shell instead.
  /bin/bash
  "$ROOT_DIR/script/check_codex_auth_access_evidence.sh"
  --run-root-traces
  "$trace_log"
  "$parent_trace_log"
  "$child_trace_log"
  "$parent_pid"
  "$child_pid"
)
if sudo -n true >/dev/null 2>&1; then
  sudo "${root_trace_command[@]}" &
else
  /usr/bin/osascript - "${root_trace_command[@]}" <<'APPLESCRIPT' &
on run argv
  set traceCommand to quoted form of item 1 of argv
  repeat with argumentIndex from 2 to count of argv
    set traceCommand to traceCommand & " " & quoted form of item argumentIndex of argv
  end repeat
  do shell script traceCommand with administrator privileges
end run
APPLESCRIPT
fi
trace_pid=$!

trace_deadline=$((SECONDS + 180))
while [[ ! -f "$trace_log" || ! -f "$parent_trace_log" || ! -f "$child_trace_log" ]]; do
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
# A successful trace exit is insufficient if it happened before the audited
# route finished. Require continuous coverage through the test completion edge.
if ! kill -0 "$trace_pid" >/dev/null 2>&1; then
  trace_pid=""
  echo "BLOCKER: filesystem trace ended before the audited test completed." >&2
  exit 1
fi
trace_status=0
wait "$trace_pid" || trace_status=$?
trace_pid=""
if [[ "$test_status" -ne 0 ]]; then
  echo "Codex auth-access audit live test failed." >&2
  sed -n '1,200p' "$test_log" >&2
  exit "$test_status"
fi
if [[ "$trace_status" -ne 0 ]]; then
  echo "Codex auth-access filesystem trace failed or ended incompletely." >&2
  exit "$trace_status"
fi

harness_parent_auth_access_count="$(wc -l <"$parent_trace_log" | tr -d '[:space:]')"
codex_child_auth_access_count="$(wc -l <"$child_trace_log" | tr -d '[:space:]')"
total_auth_access_count="$(wc -l <"$trace_log" | tr -d '[:space:]')"
unexpected_auth_access_count=$((total_auth_access_count - harness_parent_auth_access_count - codex_child_auth_access_count))

if [[ "$harness_parent_auth_access_count" -ne 0 ]]; then
  echo "BLOCKER: the Swift test harness parent accessed the Codex auth store." >&2
  exit 1
fi
if [[ "$codex_child_auth_access_count" -lt 1 ]]; then
  echo "BLOCKER: no Codex child auth-store access was observed; evidence is inconclusive." >&2
  exit 1
fi
if [[ "$unexpected_auth_access_count" -ne 0 ]]; then
  echo "BLOCKER: auth-store access from an unexpected PID was observed." >&2
  exit 1
fi

product_source_commit="$(git -C "$ROOT_DIR" log -1 --format=%H -- Sources Package.swift)"
audit_harness_commit="$(
  git -C "$ROOT_DIR" log -1 --format=%H -- \
    Tests/SuisuiCoreTests/CodexLocalRuntimeProviderTests.swift \
    script/check_codex_auth_access_evidence.sh \
    script/codex_auth_access_audit_wrapper.c
)"
if [[ -z "$product_source_commit" || -z "$audit_harness_commit" ]]; then
  echo "Product or audit-harness source commit is unavailable." >&2
  exit 1
fi
audit_harness_sha256_swift_test="$(shasum -a 256 "$ROOT_DIR/Tests/SuisuiCoreTests/CodexLocalRuntimeProviderTests.swift" | awk '{print $1}')"
audit_harness_sha256_shell_script="$(shasum -a 256 "$ROOT_DIR/script/check_codex_auth_access_evidence.sh" | awk '{print $1}')"
audit_harness_sha256_native_wrapper="$(shasum -a 256 "$ROOT_DIR/script/codex_auth_access_audit_wrapper.c" | awk '{print $1}')"
generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
evidence_output="${SUISUI_CODEX_AUTH_ACCESS_EVIDENCE_OUTPUT:-$ROOT_DIR/.tmp/codex-auth-access-evidence.json}"
mkdir -p "$(dirname "$evidence_output")"
evidence_temp="$(mktemp "$(dirname "$evidence_output")/.codex-auth-access-evidence.XXXXXX")"
printf '{\n' >"$evidence_temp"
printf '  "schemaVersion": 4,\n' >>"$evidence_temp"
printf '  "status": "passed",\n' >>"$evidence_temp"
printf '  "productSourceCommit": "%s",\n' "$product_source_commit" >>"$evidence_temp"
printf '  "auditHarnessCommit": "%s",\n' "$audit_harness_commit" >>"$evidence_temp"
printf '  "auditHarnessSHA256": {\n' >>"$evidence_temp"
printf '    "swiftTest": "%s",\n' "$audit_harness_sha256_swift_test" >>"$evidence_temp"
printf '    "shellScript": "%s",\n' "$audit_harness_sha256_shell_script" >>"$evidence_temp"
printf '    "nativeWrapper": "%s"\n' "$audit_harness_sha256_native_wrapper" >>"$evidence_temp"
printf '  },\n' >>"$evidence_temp"
printf '  "codexVersion": "%s",\n' "$codex_version" >>"$evidence_temp"
printf '  "generatedAt": "%s",\n' "$generated_at" >>"$evidence_temp"
printf '  "credentialPathClass": "codex_user_auth_store",\n' >>"$evidence_temp"
printf '  "harnessParentPID": %s,\n' "$parent_pid" >>"$evidence_temp"
printf '  "codexChildPID": %s,\n' "$child_pid" >>"$evidence_temp"
printf '  "harnessParentAuthAccessCount": %s,\n' "$harness_parent_auth_access_count" >>"$evidence_temp"
printf '  "codexChildAuthAccessCount": %s,\n' "$codex_child_auth_access_count" >>"$evidence_temp"
printf '  "unexpectedAuthAccessCount": %s\n' "$unexpected_auth_access_count" >>"$evidence_temp"
printf '}\n' >>"$evidence_temp"
mv "$evidence_temp" "$evidence_output"
evidence_temp=""

echo "OK: PID-classified Codex auth-access evidence passed."
echo "evidence=$evidence_output"
