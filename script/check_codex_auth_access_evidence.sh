#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
auth_path_suffix=".codex/auth.json"
ktrace_filter="C3,S0x040c,S0x040e,S0x040f"
capture_timeout_seconds=90
max_raw_trace_bytes=536870912

run_root_capture() {
  if [[ "$EUID" -ne 0 || "$#" -ne 7 ]]; then
    echo "Root capture helper requires root and exact audited arguments." >&2
    return 64
  fi

  local raw_trace="$1"
  local trace_diagnostic="$2"
  local trace_ready="$3"
  local trace_stop="$4"
  local notification_key="$5"
  local output_uid="$6"
  local output_gid="$7"
  if [[ "$raw_trace" != /* || "$trace_diagnostic" != /* ||
        "$trace_ready" != /* || "$trace_stop" != /* ||
        ! "$output_uid" =~ ^[0-9]+$ || ! "$output_gid" =~ ^[0-9]+$ ||
        -z "$notification_key" ]]; then
    echo "Root capture helper received unsafe paths, notification, or ownership." >&2
    return 64
  fi

  validate_capture_channel() {
    local channel_path="$1"
    local channel_uid
    local channel_gid
    local channel_size
    local channel_mode
    if [[ ! -f "$channel_path" || -L "$channel_path" ]]; then
      return 1
    fi
    channel_uid="$(/usr/bin/stat -f %u "$channel_path")"
    channel_gid="$(/usr/bin/stat -f %g "$channel_path")"
    channel_size="$(/usr/bin/stat -f %z "$channel_path")"
    channel_mode="$(/usr/bin/stat -f %Lp "$channel_path")"
    [[ "$channel_uid" == "$output_uid" &&
       "$channel_gid" == "$output_gid" &&
       "$channel_size" -eq 0 &&
       "$channel_mode" == "600" ]]
  }
  if ! validate_capture_channel "$trace_ready" ||
     ! validate_capture_channel "$trace_stop"; then
    echo "Root capture helper requires empty caller-owned 0600 IPC channels." >&2
    return 64
  fi

  # Raw kernel traces can contain unrelated filesystem metadata. Remove them
  # inside the privileged shell unless every completeness check succeeds.
  local capture_succeeded=0
  trap 'if [[ "${capture_succeeded:-0}" -ne 1 ]]; then /bin/rm -f -- "$raw_trace" "$trace_diagnostic"; fi' RETURN
  umask 077
  /usr/bin/perl -e 'alarm 15; exec @ARGV' \
    /usr/bin/notifyutil -1 "$notification_key" >/dev/null 2>&1 &
  local notify_pid=$!
  /usr/bin/ktrace dump \
    -f "$ktrace_filter" \
    -l fast \
    -b 16 \
    -T "$capture_timeout_seconds" \
    --notify-tracing-started "$notification_key" \
    "$raw_trace" >"$trace_diagnostic" 2>&1 &
  local ktrace_pid=$!

  local notify_status=0
  wait "$notify_pid" || notify_status=$?
  if [[ "$notify_status" -ne 0 ]] || ! kill -0 "$ktrace_pid" >/dev/null 2>&1; then
    kill -INT "$ktrace_pid" >/dev/null 2>&1 || true
    wait "$ktrace_pid" >/dev/null 2>&1 || true
    echo "Kernel trace did not publish its started notification." >&2
    return 1
  fi
  printf 'ready\n' >"$trace_ready"

  local deadline=$((SECONDS + capture_timeout_seconds))
  while [[ ! -s "$trace_stop" ]]; do
    if ! kill -0 "$ktrace_pid" >/dev/null 2>&1; then
      wait "$ktrace_pid" >/dev/null 2>&1 || true
      echo "Kernel trace ended before the audited window closed." >&2
      return 1
    fi
    if [[ -f "$raw_trace" ]]; then
      local raw_size
      raw_size="$(/usr/bin/stat -f %z "$raw_trace")"
      if [[ "$raw_size" -gt "$max_raw_trace_bytes" ]]; then
        kill -INT "$ktrace_pid" >/dev/null 2>&1 || true
        wait "$ktrace_pid" >/dev/null 2>&1 || true
        echo "Kernel trace exceeded the bounded raw evidence size." >&2
        return 1
      fi
    fi
    if (( SECONDS >= deadline )); then
      kill -INT "$ktrace_pid" >/dev/null 2>&1 || true
      wait "$ktrace_pid" >/dev/null 2>&1 || true
      echo "Kernel trace exceeded the bounded audit window." >&2
      return 1
    fi
    sleep 0.05
  done

  kill -INT "$ktrace_pid" >/dev/null 2>&1 || true
  local trace_status=0
  wait "$ktrace_pid" || trace_status=$?
  if [[ "$trace_status" -ne 0 ]]; then
    echo "Kernel trace failed or ended incompletely." >&2
    return 1
  fi
  if [[ ! -s "$raw_trace" ]]; then
    echo "Kernel trace did not publish raw evidence." >&2
    return 1
  fi
  local final_raw_size
  final_raw_size="$(/usr/bin/stat -f %z "$raw_trace")"
  if [[ "$final_raw_size" -gt "$max_raw_trace_bytes" ]]; then
    echo "Kernel trace exceeded the bounded raw evidence size." >&2
    return 1
  fi

  local trace_loss_marker_count
  trace_loss_marker_count="$(
    /usr/bin/grep -Eic 'lost [1-9]|dropped [1-9]|overflow' "$trace_diagnostic" 2>/dev/null || true
  )"
  if [[ "$trace_loss_marker_count" -ne 0 ]]; then
    echo "Kernel trace reported lost or overflowed events." >&2
    return 1
  fi

  /usr/sbin/chown "$output_uid:$output_gid" "$raw_trace" "$trace_diagnostic"
  /bin/chmod 0600 "$raw_trace" "$trace_diagnostic"
  capture_succeeded=1
}

if [[ "${1:-}" == "--run-root-capture" ]]; then
  shift
  run_root_capture "$@"
  exit $?
fi

if [[ "${SUISUI_CODEX_RUN_AUTH_ACCESS_EVIDENCE:-0}" != "1" ]]; then
  echo "Codex auth-access evidence is opt-in and requires an administrator kernel trace."
  echo "Run with SUISUI_CODEX_RUN_AUTH_ACCESS_EVIDENCE=1 and optionally SUISUI_CODEX_EXECUTABLE=/absolute/path/to/codex."
  exit 2
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Codex auth-access evidence requires macOS ktrace and fs_usage raw replay." >&2
  exit 1
fi
if [[ ! -x /usr/bin/ktrace || ! -x /usr/bin/fs_usage || ! -x /usr/bin/notifyutil ]]; then
  echo "Codex auth-access evidence requires ktrace, fs_usage, and notifyutil." >&2
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
test_pid=""
trace_pid=""
evidence_temp=""
capture_sequence=0

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

printf -v root_trace_program \
  'set -euo pipefail\nktrace_filter=%q\ncapture_timeout_seconds=%q\nmax_raw_trace_bytes=%q\n%s\nrun_root_capture "$@"\n' \
  "$ktrace_filter" \
  "$capture_timeout_seconds" \
  "$max_raw_trace_bytes" \
  "$(declare -f run_root_capture)"

launch_capture() {
  local raw_trace="$1"
  local trace_diagnostic="$2"
  local trace_ready="$3"
  local trace_stop="$4"
  if [[ -e "$trace_ready" || -e "$trace_stop" ]]; then
    echo "Kernel trace IPC channel already exists." >&2
    exit 1
  fi
  # Precreate both IPC channels under the invoking user. The privileged helper
  # validates their identity before writing, avoiding root-owned marker files
  # that the unprivileged coordinator cannot reliably observe.
  : >"$trace_ready"
  : >"$trace_stop"
  chmod 0600 "$trace_ready" "$trace_stop"
  capture_sequence=$((capture_sequence + 1))
  local notification_key="com.suisui.codex-auth-audit.$$.${capture_sequence}"
  local root_trace_command=(
    # Administrator shells cannot open scripts on some removable-volume
    # configurations. Pass only the audited helper body and inert argv.
    /bin/bash
    -c
    "$root_trace_program"
    --
    "$raw_trace"
    "$trace_diagnostic"
    "$trace_ready"
    "$trace_stop"
    "$notification_key"
    "$(id -u)"
    "$(id -g)"
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
}

wait_for_capture_ready() {
  local trace_ready="$1"
  local label="$2"
  local deadline=$((SECONDS + 180))
  while [[ ! -s "$trace_ready" ]]; do
    if ! kill -0 "$trace_pid" >/dev/null 2>&1; then
      wait "$trace_pid" >/dev/null 2>&1 || true
      trace_pid=""
      echo "$label kernel trace exited before becoming ready." >&2
      exit 1
    fi
    if (( SECONDS >= deadline )); then
      echo "Timed out waiting for administrator approval for $label kernel tracing." >&2
      exit 1
    fi
    sleep 0.1
  done
}

finish_capture() {
  local trace_stop="$1"
  local label="$2"
  printf 'stop\n' >"$trace_stop"
  local trace_status=0
  wait "$trace_pid" || trace_status=$?
  trace_pid=""
  if [[ "$trace_status" -ne 0 ]]; then
    echo "$label kernel trace failed or ended incompletely." >&2
    exit "$trace_status"
  fi
}

replay_access_count() {
  local raw_trace="$1"
  local audited_path="$2"
  local replay_label="$3"
  local audited_pid="${4:-}"
  local count_output="$audit_dir/replay-${replay_label}.count"
  local replay_diagnostic="$audit_dir/replay-${replay_label}.diagnostic"
  local replay_command=(/usr/bin/fs_usage -w -f pathname -R "$raw_trace")
  if [[ -n "$audited_pid" ]]; then
    replay_command+=("$audited_pid")
  fi

  set +e
  "${replay_command[@]}" 2>"$replay_diagnostic" \
    | LC_ALL=C /usr/bin/awk -v needle="$audited_path" \
      'index($0, needle) { count++ } END { print count + 0 }' >"$count_output"
  local replay_statuses=("${PIPESTATUS[@]}")
  set -e
  if [[ "${replay_statuses[0]}" -ne 0 || "${replay_statuses[1]}" -ne 0 ]]; then
    echo "Raw trace replay failed for $replay_label." >&2
    return 1
  fi
  local replay_loss_marker_count
  replay_loss_marker_count="$(
    /usr/bin/grep -Eic 'lost [1-9]|dropped [1-9]|overflow' "$replay_diagnostic" 2>/dev/null || true
  )"
  if [[ "$replay_loss_marker_count" -ne 0 ]]; then
    echo "Raw trace replay reported lost or overflowed events for $replay_label." >&2
    return 1
  fi
  tr -d '[:space:]' <"$count_output"
}

open_for_calibration() {
  local sentinel="$1"
  /bin/cat "$sentinel" >/dev/null &
  local opener_pid=$!
  wait "$opener_pid"
  printf '%s\n' "$opener_pid"
}

# Prove that this exact raw-replay parser can distinguish ended PIDs and the
# capture window before it is trusted with the real Codex credential path.
calibration_sentinel="$audit_dir/calibration-sentinel"
printf 'suisui-ktrace-calibration\n' >"$calibration_sentinel"
calibration_before_pid="$(open_for_calibration "$calibration_sentinel")"
calibration_raw_trace="$audit_dir/calibration.ktrace"
calibration_trace_diagnostic="$audit_dir/calibration-ktrace.log"
calibration_trace_ready="$audit_dir/calibration.ready"
calibration_trace_stop="$audit_dir/calibration.stop"
launch_capture \
  "$calibration_raw_trace" \
  "$calibration_trace_diagnostic" \
  "$calibration_trace_ready" \
  "$calibration_trace_stop"
wait_for_capture_ready "$calibration_trace_ready" "calibration"
calibration_parent_pid="$(open_for_calibration "$calibration_sentinel")"
calibration_child_pid="$(open_for_calibration "$calibration_sentinel")"
calibration_unexpected_pid="$(open_for_calibration "$calibration_sentinel")"
finish_capture "$calibration_trace_stop" "calibration"
calibration_after_pid="$(open_for_calibration "$calibration_sentinel")"

calibration_pids=(
  "$calibration_before_pid"
  "$calibration_parent_pid"
  "$calibration_child_pid"
  "$calibration_unexpected_pid"
  "$calibration_after_pid"
)
if [[ "$(printf '%s\n' "${calibration_pids[@]}" | sort -u | wc -l | tr -d '[:space:]')" -ne 5 ]]; then
  echo "Calibration process identities were reused or invalid." >&2
  exit 1
fi

calibration_system_count="$(
  replay_access_count "$calibration_raw_trace" "$calibration_sentinel" calibration-system
)"
calibration_parent_count="$(
  replay_access_count "$calibration_raw_trace" "$calibration_sentinel" calibration-parent "$calibration_parent_pid"
)"
calibration_child_count="$(
  replay_access_count "$calibration_raw_trace" "$calibration_sentinel" calibration-child "$calibration_child_pid"
)"
calibration_unexpected_count="$(
  replay_access_count "$calibration_raw_trace" "$calibration_sentinel" calibration-unexpected "$calibration_unexpected_pid"
)"
calibration_before_count="$(
  replay_access_count "$calibration_raw_trace" "$calibration_sentinel" calibration-before "$calibration_before_pid"
)"
calibration_after_count="$(
  replay_access_count "$calibration_raw_trace" "$calibration_sentinel" calibration-after "$calibration_after_pid"
)"
calibration_expected_total=$(
  calibration_parent_count + calibration_child_count + calibration_unexpected_count
)
if [[ "$calibration_parent_count" -lt 1 ||
      "$calibration_child_count" -lt 1 ||
      "$calibration_unexpected_count" -lt 1 ||
      "$calibration_before_count" -ne 0 ||
      "$calibration_after_count" -ne 0 ||
      "$calibration_system_count" -ne "$calibration_expected_total" ]]; then
  echo "BLOCKER: single-trace PID and capture-window calibration failed." >&2
  exit 1
fi
printf 'calibration_counts=parent:%s,child:%s,unexpected:%s,before:%s,after:%s\n' \
  "$calibration_parent_count" \
  "$calibration_child_count" \
  "$calibration_unexpected_count" \
  "$calibration_before_count" \
  "$calibration_after_count"
/usr/bin/unlink "$calibration_raw_trace"
/usr/bin/unlink "$calibration_trace_diagnostic"

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
while [[ ! -s "${wrapper_path}.parent-pid" ]]; do
  if ! kill -0 "$test_pid" >/dev/null 2>&1; then
    echo "Codex auth-access audit test exited before publishing its parent identity." >&2
    sed -n '1,160p' "$test_log" >&2
    exit 1
  fi
  if (( SECONDS >= deadline )); then
    echo "Timed out waiting for the Codex audit parent handshake." >&2
    exit 1
  fi
  sleep 0.05
done

parent_pid="$(tr -d '[:space:]' <"${wrapper_path}.parent-pid")"
if [[ ! "$parent_pid" =~ ^[1-9][0-9]*$ ]]; then
  echo "Invalid parent PID evidence." >&2
  exit 1
fi

auth_raw_trace="$audit_dir/auth-access.ktrace"
auth_trace_diagnostic="$audit_dir/auth-access-ktrace.log"
auth_trace_ready="$audit_dir/auth-access.ready"
auth_trace_stop="$audit_dir/auth-access.stop"
launch_capture "$auth_raw_trace" "$auth_trace_diagnostic" "$auth_trace_ready" "$auth_trace_stop"
wait_for_capture_ready "$auth_trace_ready" "auth-access"
touch "${wrapper_path}.parent-route-ready"

deadline=$((SECONDS + 30))
while [[ ! -s "${wrapper_path}.child-pid" ]]; do
  if ! kill -0 "$test_pid" >/dev/null 2>&1; then
    echo "Codex auth-access audit test exited before publishing its child identity." >&2
    sed -n '1,160p' "$test_log" >&2
    exit 1
  fi
  if (( SECONDS >= deadline )); then
    echo "Timed out waiting for the Codex audit child handshake." >&2
    exit 1
  fi
  sleep 0.05
done

child_pid="$(tr -d '[:space:]' <"${wrapper_path}.child-pid")"
if [[ ! "$child_pid" =~ ^[1-9][0-9]*$ || "$parent_pid" == "$child_pid" ]]; then
  echo "Invalid or non-distinct parent/child PID evidence." >&2
  exit 1
fi
observed_child_parent="$(ps -p "$child_pid" -o ppid= | tr -d '[:space:]')"
if [[ "$observed_child_parent" != "$parent_pid" ]]; then
  echo "Codex audit wrapper is not owned by the expected test parent PID." >&2
  exit 1
fi
touch "${wrapper_path}.ready"

test_status=0
wait "$test_pid" || test_status=$?
test_pid=""
printf 'stop\n' >"$auth_trace_stop"
trace_status=0
wait "$trace_pid" || trace_status=$?
trace_pid=""
if [[ "$test_status" -ne 0 ]]; then
  echo "Codex auth-access audit live test failed." >&2
  sed -n '1,200p' "$test_log" >&2
  exit "$test_status"
fi
if [[ "$trace_status" -ne 0 ]]; then
  echo "Codex auth-access kernel trace failed or ended incompletely." >&2
  exit "$trace_status"
fi

total_auth_access_count="$(
  replay_access_count "$auth_raw_trace" "$auth_path_suffix" auth-system
)"
harness_parent_auth_access_count="$(
  replay_access_count "$auth_raw_trace" "$auth_path_suffix" auth-parent "$parent_pid"
)"
codex_child_auth_access_count="$(
  replay_access_count "$auth_raw_trace" "$auth_path_suffix" auth-child "$child_pid"
)"
unexpected_auth_access_count=$(
  total_auth_access_count - harness_parent_auth_access_count - codex_child_auth_access_count
)
printf 'sanitized_counts=parent:%s,child:%s,unexpected:%s\n' \
  "$harness_parent_auth_access_count" \
  "$codex_child_auth_access_count" \
  "$unexpected_auth_access_count"

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
/usr/bin/unlink "$auth_raw_trace"
/usr/bin/unlink "$auth_trace_diagnostic"

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
macos_build="$(sw_vers -buildVersion)"
evidence_output="${SUISUI_CODEX_AUTH_ACCESS_EVIDENCE_OUTPUT:-$ROOT_DIR/.tmp/codex-auth-access-evidence.json}"
mkdir -p "$(dirname "$evidence_output")"
evidence_temp="$(mktemp "$(dirname "$evidence_output")/.codex-auth-access-evidence.XXXXXX")"
printf '{\n' >"$evidence_temp"
printf '  "schemaVersion": 4,\n' >>"$evidence_temp"
printf '  "status": "passed",\n' >>"$evidence_temp"
printf '  "auditBackend": "ktrace_raw_fs_usage_replay",\n' >>"$evidence_temp"
printf '  "macOSBuild": "%s",\n' "$macos_build" >>"$evidence_temp"
printf '  "ktraceFilter": "%s",\n' "$ktrace_filter" >>"$evidence_temp"
printf '  "productSourceCommit": "%s",\n' "$product_source_commit" >>"$evidence_temp"
printf '  "auditHarnessCommit": "%s",\n' "$audit_harness_commit" >>"$evidence_temp"
printf '  "auditHarnessSHA256": {\n' >>"$evidence_temp"
printf '    "swiftTest": "%s",\n' "$audit_harness_sha256_swift_test" >>"$evidence_temp"
printf '    "shellScript": "%s",\n' "$audit_harness_sha256_shell_script" >>"$evidence_temp"
printf '    "nativeWrapper": "%s"\n' "$audit_harness_sha256_native_wrapper" >>"$evidence_temp"
printf '  },\n' >>"$evidence_temp"
printf '  "calibration": {\n' >>"$evidence_temp"
printf '    "parentCount": %s,\n' "$calibration_parent_count" >>"$evidence_temp"
printf '    "childCount": %s,\n' "$calibration_child_count" >>"$evidence_temp"
printf '    "unexpectedCount": %s,\n' "$calibration_unexpected_count" >>"$evidence_temp"
printf '    "beforeWindowCount": %s,\n' "$calibration_before_count" >>"$evidence_temp"
printf '    "afterWindowCount": %s\n' "$calibration_after_count" >>"$evidence_temp"
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

echo "OK: single-trace PID-classified Codex auth-access evidence passed."
echo "evidence=$evidence_output"
