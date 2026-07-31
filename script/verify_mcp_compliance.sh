#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/script/mcp_source_provenance.sh"

FIXTURE_SERVER="fixtures/mcp/stdio-fixture-server.mjs"
SMOKE_CLIENT="fixtures/mcp/stdio-smoke-client.mjs"
EVIDENCE_FILE="${SUISUI_MCP_EVIDENCE_FILE:-$ROOT_DIR/docs/release/evidence/mcp-inspector.md}"
MCP_SOURCE_REF="${SUISUI_MCP_SOURCE_REF:-HEAD}"

mcp_evidence_source_commit() {
  # PR CI checks out GitHub's synthetic merge commit. Evidence must stay bound
  # to the contributor head so a base-branch commit cannot satisfy provenance.
  mcp_evidence_source_commit_for_ref "$ROOT_DIR" "$MCP_SOURCE_REF"
}

if ! MCP_SOURCE_COMMIT="$(mcp_evidence_source_commit)"; then
  exit 1
fi

# Inspector calls include --method tools/list and --method tools/call.
if [[ -n "${SUISUI_MCP_INSPECTOR_BIN:-}" ]]; then
  INSPECTOR_COMMAND=("$SUISUI_MCP_INSPECTOR_BIN")
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

- Source commit: \`$MCP_SOURCE_COMMIT\`

Scope: validate the release MCP stdio fixture with the official MCP Inspector CLI and Suisui's local JSON-RPC smoke checks.

Implemented legacy baseline: \`2025-11-25\`

Official stable latest: \`2026-07-28\`

Official latest source: https://modelcontextprotocol.io/specification

Official GitHub releases source: https://github.com/modelcontextprotocol/modelcontextprotocol/releases

Official GitHub release assertion: GitHub marks 2026-07-28 as Latest stable release and 2026-07-28 RC as Pre-release.

Official versioning source: https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning

Official versioning assertion: current stable protocol version is \`2026-07-28\`; \`2025-11-25\` is a legacy protocol revision.

Official latest checked: 2026-07-31

Implemented legacy source: https://modelcontextprotocol.io/specification/2025-11-25

Current stable source: https://modelcontextprotocol.io/specification/2026-07-28

Stable extension watchlist: Enterprise-Managed Authorization stable on 2026-06-18

Enterprise-Managed Authorization source: https://blog.modelcontextprotocol.io/posts/enterprise-managed-auth/

EMA remote authorization is not a Suisui public-alpha release target

Historical RC source: https://blog.modelcontextprotocol.io/posts/2026-07-28-release-candidate/

Historical RC assertion: GitHub marks 2026-07-28 RC as Pre-release; it is superseded by stable 2026-07-28.

Current stable changelog source: https://modelcontextprotocol.io/specification/2026-07-28/changelog

Current stable changelog assertion: changes are listed since legacy \`2025-11-25\`; \`2026-07-28\` is the current stable release.

Current stable support status: MCP 2026-07-28 is not implemented in Suisui public alpha.

Current stable 2026-07-28 removes initialize/notifications/initialized and protocol-level sessions.

Current stable 2026-07-28 uses per-request \`_meta\` protocolVersion/clientInfo/clientCapabilities.

Current stable \`server/discover\` is required for 2026-07-28 version and capability discovery.

Current stable tools/list cache hints \`ttlMs\` / \`cacheScope\` are not implemented in Suisui public alpha.

Release positioning: Suisui is not a full MCP host; this evidence covers legacy 2025-11-25 client-side stdio Tools only. Resources, Prompts, Streamable HTTP, OAuth/remote MCP, Enterprise-Managed Authorization, current stable per-request protocol metadata, and current stable server/discover are not release targets.

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
  --tool-arg project=suisui

run_and_record \
  "Suisui local smoke success" \
  success \
  node "$SMOKE_CLIENT" \
  --mode success

for failure_mode in malformed-json mismatched-id invalid-schema timeout; do
  run_and_record \
    "Suisui local failure smoke: $failure_mode" \
    success \
    node "$SMOKE_CLIENT" \
    --mode "$failure_mode" \
    --expect-failure "$failure_mode"
done

cat >>"$EVIDENCE_FILE" <<'EOF'
## Notes

- The Inspector commands above exercise the official MCP Inspector CLI against the same stdio fixture that Suisui uses for automated smoke coverage.
- The failure taxonomy records malformed JSON-RPC, mismatched id, invalid schema, and timeout behavior without shipping fixture code in production sources.
- Structured output and `outputSchema` release-subset validation are covered by `ExternalMCPTests.testToolsListParsesStructuredOutputSchema`, `ExternalMCPTests.testExternalMCPExecutionRequiresStructuredContentWhenOutputSchemaProvided`, and related executor regression tests. The Inspector smoke remains focused on stable stdio Tools wiring and failure taxonomy.
EOF

echo "MCP compliance evidence written to $EVIDENCE_FILE"
