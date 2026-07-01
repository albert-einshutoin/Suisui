# MCP Inspector Evidence

Generated: 2026-07-01T08:01:42Z

- Source commit: `90bb44b4`

Scope: validate the release MCP stdio fixture with the official MCP Inspector CLI and SoloPM's local JSON-RPC smoke checks.

Stable baseline: `2025-11-25`

Official stable latest: `2025-11-25`

Official latest source: https://modelcontextprotocol.io/specification

Official GitHub releases source: https://github.com/modelcontextprotocol/modelcontextprotocol/releases

Official GitHub release assertion: GitHub marks 2025-11-25 as Latest stable release and 2026-07-28 RC as Pre-release.

Official versioning source: https://modelcontextprotocol.io/docs/learn/versioning

Official versioning assertion: current protocol version is `2025-11-25`

Official latest checked: 2026-06-24

Official stable source: https://modelcontextprotocol.io/specification/2025-11-25

Stable extension watchlist: Enterprise-Managed Authorization stable on 2026-06-18

Enterprise-Managed Authorization source: https://blog.modelcontextprotocol.io/posts/enterprise-managed-auth/

EMA remote authorization is not a SoloPM public-alpha release target

Draft watchlist: `2026-07-28`

Draft release-candidate source: https://blog.modelcontextprotocol.io/posts/2026-07-28-release-candidate/

Draft changelog source: https://modelcontextprotocol.io/specification/draft/changelog

Draft changelog assertion: changes are listed since `2025-11-25`; it is not the current release baseline.

2026-07-28 is release-candidate; final specification is scheduled for 2026-07-28.

Draft 2026-07-28 removes initialize/notifications/initialized and protocol-level sessions.

Draft 2026-07-28 uses per-request `_meta` protocolVersion/clientInfo/clientCapabilities.

Draft `server/discover` is required for draft 2026-07-28 version and capability discovery.

Draft tools/list cache hints `ttlMs` / `cacheScope` are not implemented in SoloPM public alpha.

Release positioning: SoloPM is not a full MCP host; this evidence covers stable client-side stdio Tools only. Resources, Prompts, Streamable HTTP, OAuth/remote MCP, Enterprise-Managed Authorization, draft per-request protocol metadata, and draft server/discover are not release targets.

Fixture: `fixtures/mcp/stdio-fixture-server.mjs`

Success path: `initialize -> tools/list -> tools/call`

## MCP Inspector CLI tools/list

```console
$ npx --loglevel error -y @modelcontextprotocol/inspector --cli node fixtures/mcp/stdio-fixture-server.mjs --method tools/list
{
  "tools": [
    {
      "name": "read_status",
      "title": "Read Status",
      "description": "Read local project status.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "project": {
            "type": "string",
            "description": "Project name"
          }
        },
        "required": [
          "project"
        ],
        "additionalProperties": false
      }
    }
  ]
}
exit: 0
```

## MCP Inspector CLI tools/call

```console
$ npx --loglevel error -y @modelcontextprotocol/inspector --cli node fixtures/mcp/stdio-fixture-server.mjs --method tools/call --tool-name read_status --tool-arg project=soloPM
{
  "content": [
    {
      "type": "text",
      "text": "status: ok project=soloPM"
    }
  ],
  "isError": false
}
exit: 0
```

## SoloPM local smoke success

```console
$ node fixtures/mcp/stdio-smoke-client.mjs --mode success
initialize: protocolVersion=2025-11-25
tools/list: read_status
tools/call: status: ok project=soloPM
result: success initialize -> tools/list -> tools/call

exit: 0
```

## SoloPM local failure smoke: malformed-json

```console
$ node fixtures/mcp/stdio-smoke-client.mjs --mode malformed-json --expect-failure malformed-json
malformed-json: Malformed JSON-RPC response.

exit: 0
```

## SoloPM local failure smoke: mismatched-id

```console
$ node fixtures/mcp/stdio-smoke-client.mjs --mode mismatched-id --expect-failure mismatched-id
initialize: protocolVersion=2025-11-25
mismatched-id: Mismatched response id.

exit: 0
```

## SoloPM local failure smoke: invalid-schema

```console
$ node fixtures/mcp/stdio-smoke-client.mjs --mode invalid-schema --expect-failure invalid-schema
initialize: protocolVersion=2025-11-25
invalid-schema: Tool entry inputSchema must be an object.

exit: 0
```

## SoloPM local failure smoke: timeout

```console
$ node fixtures/mcp/stdio-smoke-client.mjs --mode timeout --expect-failure timeout
initialize: protocolVersion=2025-11-25
timeout: Timed out waiting for JSON-RPC response.

exit: 0
```

## Notes

- The Inspector commands above exercise the official MCP Inspector CLI against the same stdio fixture that SoloPM uses for automated smoke coverage.
- The failure taxonomy records malformed JSON-RPC, mismatched id, invalid schema, and timeout behavior without shipping fixture code in production sources.
- Structured output and `outputSchema` release-subset validation are covered by `ExternalMCPTests.testToolsListParsesStructuredOutputSchema`, `ExternalMCPTests.testExternalMCPExecutionRequiresStructuredContentWhenOutputSchemaProvided`, and related executor regression tests. The Inspector smoke remains focused on stable stdio Tools wiring and failure taxonomy.
