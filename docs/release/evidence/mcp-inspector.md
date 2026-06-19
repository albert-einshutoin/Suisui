# MCP Inspector Evidence

Generated: 2026-06-19T02:33:47Z

Scope: validate the release MCP stdio fixture with the official MCP Inspector CLI and SoloPM's local JSON-RPC smoke checks.

Stable baseline: `2025-11-25`

Draft watchlist: `2026-07-28`

Release positioning: SoloPM is not a full MCP host; this evidence covers stable client-side stdio Tools only. Resources, Prompts, Streamable HTTP, OAuth/remote MCP, draft per-request protocol metadata, and draft server/discover are not release targets.

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
