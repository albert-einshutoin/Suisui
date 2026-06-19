#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FIXTURE_SERVER="fixtures/mcp/stdio-fixture-server.mjs"
SMOKE_CLIENT="fixtures/mcp/stdio-smoke-client.mjs"
EVIDENCE_FILE="${SOLOPM_MCP_EVIDENCE_FILE:-$ROOT_DIR/docs/release/evidence/mcp-inspector.md}"

# Inspector calls include --method tools/list and --method tools/call.
if [[ -n "${SOLOPM_MCP_INSPECTOR_BIN:-}" ]]; then
  INSPECTOR_COMMAND=("$SOLOPM_MCP_INSPECTOR_BIN")
else
  INSPECTOR_COMMAND=(npx --loglevel error -y @modelcontextprotocol/inspector)
fi

mkdir -p "$(dirname "$EVIDENCE_FILE")"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

run_and_record() {
  local title="$1"
  local expected_status="$2"
  shift 2

  local output_file="$WORK_DIR/output.log"
  local status=0

  {
    printf '## %s\n\n' "$title"
    printf '```console\n'
    printf '$'
    printf ' %q' "$@"
    printf '\n'
  } >>"$EVIDENCE_FILE"

  if "$@" >"$output_file" 2>&1; then
    status=0
  else
    status=$?
  fi

  cat "$output_file" >>"$EVIDENCE_FILE"
  {
    printf '\nexit: %s\n' "$status"
    printf '```\n\n'
  } >>"$EVIDENCE_FILE"

  if [[ "$expected_status" == "success" && "$status" -ne 0 ]]; then
    cat "$output_file" >&2
    echo "$title failed with exit $status" >&2
    return "$status"
  fi
  if [[ "$expected_status" == "failure" && "$status" -eq 0 ]]; then
    cat "$output_file" >&2
    echo "$title was expected to fail" >&2
    return 1
  fi
  return 0
}

cat >"$EVIDENCE_FILE" <<EOF
# MCP Inspector Evidence

Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

Scope: validate the release MCP stdio fixture with the official MCP Inspector CLI and SoloPM's local JSON-RPC smoke checks.

Stable baseline: \`2025-11-25\`

Draft watchlist: \`2026-07-28\`

Release positioning: SoloPM is not a full MCP host; this evidence covers stable client-side stdio Tools only. Resources, Prompts, Streamable HTTP, OAuth/remote MCP, draft per-request protocol metadata, and draft server/discover are not release targets.

Fixture: \`fixtures/mcp/stdio-fixture-server.mjs\`

Success path: \`initialize -> tools/list -> tools/call\`

EOF

run_and_record \
  "MCP Inspector CLI tools/list" \
  success \
  "${INSPECTOR_COMMAND[@]}" \
  --cli \
  node "$FIXTURE_SERVER" \
  --method tools/list

run_and_record \
  "MCP Inspector CLI tools/call" \
  success \
  "${INSPECTOR_COMMAND[@]}" \
  --cli \
  node "$FIXTURE_SERVER" \
  --method tools/call \
  --tool-name read_status \
  --tool-arg project=soloPM

run_and_record \
  "SoloPM local smoke success" \
  success \
  node "$SMOKE_CLIENT" \
  --mode success

for failure_mode in malformed-json mismatched-id invalid-schema timeout; do
  run_and_record \
    "SoloPM local failure smoke: $failure_mode" \
    success \
    node "$SMOKE_CLIENT" \
    --mode "$failure_mode" \
    --expect-failure "$failure_mode"
done

cat >>"$EVIDENCE_FILE" <<'EOF'
## Notes

- The Inspector commands above exercise the official MCP Inspector CLI against the same stdio fixture that SoloPM uses for automated smoke coverage.
- The failure taxonomy records malformed JSON-RPC, mismatched id, invalid schema, and timeout behavior without shipping fixture code in production sources.
- Structured output and `outputSchema` release-subset validation are covered by `ExternalMCPTests.testToolsListParsesStructuredOutputSchema`, `ExternalMCPTests.testExternalMCPExecutionRequiresStructuredContentWhenOutputSchemaProvided`, and related executor regression tests. The Inspector smoke remains focused on stable stdio Tools wiring and failure taxonomy.
EOF

echo "MCP compliance evidence written to $EVIDENCE_FILE"
