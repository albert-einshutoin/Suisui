#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"

ROOT_DIR="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT_DIR"
source "$ROOT_DIR/script/mcp_source_provenance.sh"

FIXTURE_SERVER="fixtures/mcp/stdio-fixture-server.mjs"
SMOKE_CLIENT="fixtures/mcp/stdio-smoke-client.mjs"
TARGET_EVIDENCE_FILE="${SUISUI_MCP_EVIDENCE_FILE:-$ROOT_DIR/docs/release/evidence/mcp-inspector.md}"
MCP_SOURCE_REF="${SUISUI_MCP_SOURCE_REF:-HEAD}"
ROOT_CANONICAL="$(pwd -P)"
INSPECTOR_PACKAGE="@modelcontextprotocol/inspector@2.2.0"
CUSTOM_INSPECTOR=0

mcp_evidence_source_commit() {
  # PR CI checks out GitHub's synthetic merge commit. Evidence must stay bound
  # to the contributor head so a base-branch commit cannot satisfy provenance.
  mcp_evidence_source_commit_for_ref "$ROOT_DIR" "$MCP_SOURCE_REF"
}

if ! MCP_SOURCE_COMMIT="$(mcp_evidence_source_commit)"; then
  exit 1
fi

# Inspector calls include --method tools/list and --method tools/call.
trusted_npx_path() {
  local requested="${SUISUI_MCP_NPX_BIN:-}"
  local candidate
  for candidate in /opt/homebrew/bin/npx /usr/local/bin/npx /usr/bin/npx; do
    if [[ -n "$requested" && "$requested" != "$candidate" ]]; then
      continue
    fi
    if [[ -f "$candidate" && -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  echo "BLOCKER: trusted npx is unavailable; install Node in a standard system location" >&2
  return 2
}

unsafe_mcp_evidence_destination() {
  echo "BLOCKER: unsafe MCP evidence destination; use a regular file below docs/release/evidence, .tmp, or .build" >&2
  return 2
}

initialize_mcp_evidence_destination() {
  local evidence_file="$TARGET_EVIDENCE_FILE"
  local evidence_parent existing_ancestor ancestor_canonical parent_canonical basename trusted_root trusted_root_canonical

  if [[ "$evidence_file" != /* ]]; then
    evidence_file="$ROOT_CANONICAL/$evidence_file"
  fi
  case "$evidence_file" in
    */../*|*/./*) unsafe_mcp_evidence_destination; return 2 ;;
  esac
  case "$evidence_file" in
    "$ROOT_CANONICAL/docs/release/evidence/"*) trusted_root="$ROOT_CANONICAL/docs/release/evidence" ;;
    "$ROOT_CANONICAL/.tmp/"*) trusted_root="$ROOT_CANONICAL/.tmp" ;;
    "$ROOT_CANONICAL/.build/"*) trusted_root="$ROOT_CANONICAL/.build" ;;
    *) unsafe_mcp_evidence_destination; return 2 ;;
  esac
  if [[ -L "$trusted_root" || ( -e "$trusted_root" && ! -d "$trusted_root" ) ]]; then
    unsafe_mcp_evidence_destination
    return 2
  fi
  mkdir -p "$trusted_root"
  trusted_root_canonical="$(cd "$trusted_root" && pwd -P)"
  if [[ "$trusted_root_canonical" != "$trusted_root" ]]; then
    unsafe_mcp_evidence_destination
    return 2
  fi

  evidence_parent="$(dirname "$evidence_file")"
  basename="$(basename "$evidence_file")"
  if [[ -z "$basename" || "$basename" == "." || "$basename" == ".." ]]; then
    unsafe_mcp_evidence_destination
    return 2
  fi
  existing_ancestor="$evidence_parent"
  while [[ ! -e "$existing_ancestor" && ! -L "$existing_ancestor" ]]; do
    existing_ancestor="$(dirname "$existing_ancestor")"
  done
  if [[ ! -d "$existing_ancestor" || -L "$existing_ancestor" ]]; then
    unsafe_mcp_evidence_destination
    return 2
  fi
  ancestor_canonical="$(cd "$existing_ancestor" && pwd -P)"
  case "$ancestor_canonical/" in
    "$trusted_root_canonical/"*) ;;
    *) unsafe_mcp_evidence_destination; return 2 ;;
  esac

  mkdir -p "$evidence_parent"
  if [[ ! -d "$evidence_parent" || -L "$evidence_parent" ]]; then
    unsafe_mcp_evidence_destination
    return 2
  fi
  parent_canonical="$(cd "$evidence_parent" && pwd -P)"
  case "$parent_canonical/" in
    "$trusted_root_canonical/"*) ;;
    *) unsafe_mcp_evidence_destination; return 2 ;;
  esac
  if [[ "$CUSTOM_INSPECTOR" == "1" && "$parent_canonical/$basename" == "$ROOT_CANONICAL/docs/release/evidence/"* ]]; then
    echo "BLOCKER: custom MCP Inspector may write test evidence only below .tmp or .build" >&2
    return 2
  fi
  if [[ -L "$evidence_file" || ( -e "$evidence_file" && ! -f "$evidence_file" ) ]]; then
    unsafe_mcp_evidence_destination
    return 2
  fi
  TARGET_EVIDENCE_FILE="$parent_canonical/$basename"
}

if [[ -n "${SUISUI_MCP_INSPECTOR_BIN:-}" ]]; then
  CUSTOM_INSPECTOR=1
  INSPECTOR_COMMAND=("$SUISUI_MCP_INSPECTOR_BIN")
else
  if ! NPX_BIN="$(trusted_npx_path)"; then
    exit 2
  fi
  NODE_BIN="${NPX_BIN%/*}/node"
  if [[ ! -f "$NODE_BIN" || ! -x "$NODE_BIN" ]]; then
    echo "BLOCKER: trusted node is unavailable beside $NPX_BIN" >&2
    exit 2
  fi
fi
NODE_BIN="${NODE_BIN:-$(command -v node)}"

initialize_mcp_evidence_destination
mkdir -p "$ROOT_DIR/.tmp"
WORK_DIR="$(mktemp -d "$ROOT_DIR/.tmp/suisui-mcp-compliance.XXXXXX")"
EVIDENCE_FILE="$WORK_DIR/evidence.md"
trap 'rm -rf "$WORK_DIR"' EXIT

if [[ "$CUSTOM_INSPECTOR" == "0" ]]; then
  printf '{"private":true}\n' >"$WORK_DIR/package.json"
  : >"$WORK_DIR/npm-globalconfig"
  mkdir -p "$WORK_DIR/npm-cache" "$WORK_DIR/npm-prefix"
  INSPECTOR_COMMAND=(
    /usr/bin/env
    -u npm_config_registry
    -u NPM_CONFIG_REGISTRY
    -u npm_config_userconfig
    -u NPM_CONFIG_USERCONFIG
    -u npm_config_globalconfig
    -u NPM_CONFIG_GLOBALCONFIG
    -u npm_config_cache
    -u NPM_CONFIG_CACHE
    -u npm_config_prefix
    -u NPM_CONFIG_PREFIX
    -u npm_config_offline
    -u NPM_CONFIG_OFFLINE
    -u npm_config_prefer_offline
    -u NPM_CONFIG_PREFER_OFFLINE
    -u npm_config_strict_ssl
    -u NPM_CONFIG_STRICT_SSL
    -u NODE_OPTIONS
    -u NODE_PATH
    NPM_CONFIG_REGISTRY=https://registry.npmjs.org/
    NPM_CONFIG_USERCONFIG=/dev/null
    NPM_CONFIG_GLOBALCONFIG="$WORK_DIR/npm-globalconfig"
    NPM_CONFIG_CACHE="$WORK_DIR/npm-cache"
    NPM_CONFIG_PREFIX="$WORK_DIR/npm-prefix"
    NPM_CONFIG_IGNORE_SCRIPTS=true
    NPM_CONFIG_OFFLINE=false
    NPM_CONFIG_PREFER_OFFLINE=false
    NPM_CONFIG_UPDATE_NOTIFIER=false
    NPM_CONFIG_STRICT_SSL=true
    PATH="${NODE_BIN%/*}:/usr/bin:/bin"
    "$NODE_BIN" "$NPX_BIN" --loglevel error -y "$INSPECTOR_PACKAGE"
  )
fi

run_and_record() {
  local title="$1"
  local expected_status="$2"
  local argument recorded_argument
  shift 2

  local output_file="$WORK_DIR/output.log"
  local status=0

  {
    printf '## %s\n\n' "$title"
    printf '```console\n'
    printf '$'
    for argument in "$@"; do
      # Evidence records stable trust-boundary labels, not machine-local paths.
      recorded_argument="${argument//$WORK_DIR/<mcp-work-dir>}"
      recorded_argument="${recorded_argument//$ROOT_DIR/<repository-root>}"
      printf ' %q' "$recorded_argument"
    done
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

run_inspector_and_record() {
  (
    cd "$WORK_DIR"
    run_and_record "$@"
  )
}

validate_inspector_list_output() {
  local tool_name
  tool_name="$(/usr/bin/plutil -extract tools.0.name raw -o - "$WORK_DIR/output.log" 2>/dev/null || true)"
  if [[ "$tool_name" != "read_status" ]]; then
    echo "BLOCKER: Inspector tools/list output is invalid" >&2
    return 1
  fi
}

validate_inspector_call_output() {
  local content_text is_error
  content_text="$(/usr/bin/plutil -extract content.0.text raw -o - "$WORK_DIR/output.log" 2>/dev/null || true)"
  is_error="$(/usr/bin/plutil -extract isError raw -o - "$WORK_DIR/output.log" 2>/dev/null || true)"
  if [[ "$content_text" != "status: ok project=suisui" || "$is_error" != "false" ]]; then
    echo "BLOCKER: Inspector tools/call output is invalid" >&2
    return 1
  fi
}

cat >"$EVIDENCE_FILE" <<EOF
# MCP Inspector Evidence

Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

- Source commit: \`$MCP_SOURCE_COMMIT\`
- Inspector identity: $(if [[ "$CUSTOM_INSPECTOR" == "1" ]]; then printf 'custom test override'; else printf '%s' "$INSPECTOR_PACKAGE"; fi)

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

run_inspector_and_record \
  "MCP Inspector CLI tools/list" \
  success \
  "${INSPECTOR_COMMAND[@]}" \
  --cli \
  "$NODE_BIN" "$ROOT_DIR/$FIXTURE_SERVER" \
  --method tools/list
validate_inspector_list_output

run_inspector_and_record \
  "MCP Inspector CLI tools/call" \
  success \
  "${INSPECTOR_COMMAND[@]}" \
  --cli \
  "$NODE_BIN" "$ROOT_DIR/$FIXTURE_SERVER" \
  --method tools/call \
  --tool-name read_status \
  --tool-arg project=suisui
validate_inspector_call_output

run_and_record \
  "Suisui local smoke success" \
  success \
  "$NODE_BIN" "$SMOKE_CLIENT" \
  --mode success

for failure_mode in malformed-json mismatched-id invalid-schema timeout; do
  run_and_record \
    "Suisui local failure smoke: $failure_mode" \
    success \
    "$NODE_BIN" "$SMOKE_CLIENT" \
    --mode "$failure_mode" \
    --expect-failure "$failure_mode"
done

cat >>"$EVIDENCE_FILE" <<'EOF'
## Notes

- The Inspector commands above exercise the official MCP Inspector CLI against the same stdio fixture that Suisui uses for automated smoke coverage.
- The failure taxonomy records malformed JSON-RPC, mismatched id, invalid schema, and timeout behavior without shipping fixture code in production sources.
- Structured output and `outputSchema` release-subset validation are covered by `ExternalMCPTests.testToolsListParsesStructuredOutputSchema`, `ExternalMCPTests.testExternalMCPExecutionRequiresStructuredContentWhenOutputSchemaProvided`, and related executor regression tests. The Inspector smoke remains focused on stable stdio Tools wiring and failure taxonomy.
EOF

evidence_parent="$(dirname "$TARGET_EVIDENCE_FILE")"
if [[ ! -d "$evidence_parent" || -L "$evidence_parent" || -L "$TARGET_EVIDENCE_FILE" || ( -e "$TARGET_EVIDENCE_FILE" && ! -f "$TARGET_EVIDENCE_FILE" ) ]]; then
  unsafe_mcp_evidence_destination
  exit 2
fi
if [[ "$(cd "$evidence_parent" && pwd -P)" != "$evidence_parent" ]]; then
  unsafe_mcp_evidence_destination
  exit 2
fi
/bin/mv -fh "$EVIDENCE_FILE" "$TARGET_EVIDENCE_FILE"

echo "MCP compliance evidence written to $TARGET_EVIDENCE_FILE"
