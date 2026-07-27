#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FIXTURE_SERVER="fixtures/mcp/stdio-fixture-server.mjs"
SMOKE_CLIENT="fixtures/mcp/stdio-smoke-client.mjs"
EVIDENCE_FILE="${SUISUI_MCP_EVIDENCE_FILE:-$ROOT_DIR/docs/release/evidence/mcp-inspector.md}"
MCP_SOURCE_REF="${SUISUI_MCP_SOURCE_REF:-HEAD}"

mcp_evidence_source_commit() {
  local commit
  # PR CI checks out GitHub's synthetic merge commit. Evidence must stay bound
  # to the contributor head so a base-branch commit cannot satisfy provenance.
  if ! git -C "$ROOT_DIR" rev-parse --verify "${MCP_SOURCE_REF}^{commit}" >/dev/null 2>&1; then
    printf "Invalid SUISUI_MCP_SOURCE_REF: %s\n" "$MCP_SOURCE_REF" >&2
    return 1
  fi

  commit="$(
    git -C "$ROOT_DIR" log -1 --format=%h "$MCP_SOURCE_REF" -- \
      Sources/SuisuiCore/ExternalMCP \
      Sources/SuisuiApp/SuisuiApp.swift \
      Sources/SuisuiApp/Composition \
      fixtures/mcp \
      Package.swift
  )"
  if [[ -n "$commit" ]]; then
    printf "%s" "$commit"
  else
    git -C "$ROOT_DIR" rev-parse --short "$MCP_SOURCE_REF"
  fi
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

Stable baseline: \`2025-11-25\`

Official stable latest: \`2025-11-25\`

Official latest source: https://modelcontextprotocol.io/specification

Official GitHub releases source: https://github.com/modelcontextprotocol/modelcontextprotocol/releases

Official GitHub release assertion: GitHub marks 2025-11-25 as Latest stable release and 2026-07-28 RC as Pre-release.

Official versioning source: https://modelcontextprotocol.io/docs/learn/versioning

Official versioning assertion: current protocol version is \`2025-11-25\`

Official latest checked: 2026-06-24

Official stable source: https://modelcontextprotocol.io/specification/2025-11-25

Stable extension watchlist: Enterprise-Managed Authorization stable on 2026-06-18

Enterprise-Managed Authorization source: https://blog.modelcontextprotocol.io/posts/enterprise-managed-auth/

EMA remote authorization is not a Suisui public-alpha release target

Draft watchlist: \`2026-07-28\`

Draft release-candidate source: https://blog.modelcontextprotocol.io/posts/2026-07-28-release-candidate/

Draft changelog source: https://modelcontextprotocol.io/specification/draft/changelog

Draft changelog assertion: changes are listed since \`2025-11-25\`; it is not the current release baseline.

2026-07-28 is release-candidate; final specification is scheduled for 2026-07-28.

Draft 2026-07-28 removes initialize/notifications/initialized and protocol-level sessions.

Draft 2026-07-28 uses per-request \`_meta\` protocolVersion/clientInfo/clientCapabilities.

Draft \`server/discover\` is required for draft 2026-07-28 version and capability discovery.

Draft tools/list cache hints \`ttlMs\` / \`cacheScope\` are not implemented in Suisui public alpha.

Release positioning: Suisui is not a full MCP host; this evidence covers stable client-side stdio Tools only. Resources, Prompts, Streamable HTTP, OAuth/remote MCP, Enterprise-Managed Authorization, draft per-request protocol metadata, and draft server/discover are not release targets.

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
