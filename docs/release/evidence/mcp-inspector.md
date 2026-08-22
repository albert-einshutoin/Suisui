# MCP Inspector Evidence

Generated: 2026-08-22T14:55:08Z

- Source commit: `d82f4ed5`
- Inspector identity: @modelcontextprotocol/inspector@2.2.0

Scope: validate the release MCP stdio fixture with the official MCP Inspector CLI and Suisui's local JSON-RPC smoke checks.

Implemented legacy baseline: `2025-11-25`

Official stable latest: `2026-07-28`

Official latest source: https://modelcontextprotocol.io/specification

Official GitHub releases source: https://github.com/modelcontextprotocol/modelcontextprotocol/releases

Official GitHub release assertion: GitHub marks 2026-07-28 as Latest stable release and 2026-07-28 RC as Pre-release.

Official versioning source: https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning

Official versioning assertion: current stable protocol version is `2026-07-28`; `2025-11-25` is a legacy protocol revision.

Official latest checked: 2026-07-31

Implemented legacy source: https://modelcontextprotocol.io/specification/2025-11-25

Current stable source: https://modelcontextprotocol.io/specification/2026-07-28

Stable extension watchlist: Enterprise-Managed Authorization stable on 2026-06-18

Enterprise-Managed Authorization source: https://blog.modelcontextprotocol.io/posts/enterprise-managed-auth/

EMA remote authorization is not a Suisui public-alpha release target

Historical RC source: https://blog.modelcontextprotocol.io/posts/2026-07-28-release-candidate/

Historical RC assertion: GitHub marks 2026-07-28 RC as Pre-release; it is superseded by stable 2026-07-28.

Current stable changelog source: https://modelcontextprotocol.io/specification/2026-07-28/changelog

Current stable changelog assertion: changes are listed since legacy `2025-11-25`; `2026-07-28` is the current stable release.

Current stable support status: MCP 2026-07-28 is not implemented in Suisui public alpha.

Current stable 2026-07-28 removes initialize/notifications/initialized and protocol-level sessions.

Current stable 2026-07-28 uses per-request `_meta` protocolVersion/clientInfo/clientCapabilities.

Current stable `server/discover` is required for 2026-07-28 version and capability discovery.

Current stable tools/list cache hints `ttlMs` / `cacheScope` are not implemented in Suisui public alpha.

Release positioning: Suisui is not a full MCP host; this evidence covers legacy 2025-11-25 client-side stdio Tools only. Resources, Prompts, Streamable HTTP, OAuth/remote MCP, Enterprise-Managed Authorization, current stable per-request protocol metadata, and current stable server/discover are not release targets.

Fixture: `fixtures/mcp/stdio-fixture-server.mjs`

Success path: `initialize -> tools/list -> tools/call`

## MCP Inspector CLI tools/list

```console
$ /usr/bin/env -i HOME=\<mcp-work-dir\>/home TMPDIR=\<mcp-work-dir\>/tmp NPM_CONFIG_REGISTRY=https://registry.npmjs.org/ NPM_CONFIG_USERCONFIG=/dev/null NPM_CONFIG_GLOBALCONFIG=\<mcp-work-dir\>/npm-globalconfig NPM_CONFIG_CACHE=\<mcp-work-dir\>/npm-cache NPM_CONFIG_PREFIX=\<mcp-work-dir\>/npm-prefix NPM_CONFIG_IGNORE_SCRIPTS=true NPM_CONFIG_OFFLINE=false NPM_CONFIG_PREFER_OFFLINE=false NPM_CONFIG_UPDATE_NOTIFIER=false NPM_CONFIG_STRICT_SSL=true PATH=/opt/homebrew/bin:/usr/bin:/bin /opt/homebrew/bin/node /opt/homebrew/bin/npx --loglevel error -y @modelcontextprotocol/inspector@2.2.0 --cli /opt/homebrew/bin/node \<repository-root\>/fixtures/mcp/stdio-fixture-server.mjs --method tools/list
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
$ /usr/bin/env -i HOME=\<mcp-work-dir\>/home TMPDIR=\<mcp-work-dir\>/tmp NPM_CONFIG_REGISTRY=https://registry.npmjs.org/ NPM_CONFIG_USERCONFIG=/dev/null NPM_CONFIG_GLOBALCONFIG=\<mcp-work-dir\>/npm-globalconfig NPM_CONFIG_CACHE=\<mcp-work-dir\>/npm-cache NPM_CONFIG_PREFIX=\<mcp-work-dir\>/npm-prefix NPM_CONFIG_IGNORE_SCRIPTS=true NPM_CONFIG_OFFLINE=false NPM_CONFIG_PREFER_OFFLINE=false NPM_CONFIG_UPDATE_NOTIFIER=false NPM_CONFIG_STRICT_SSL=true PATH=/opt/homebrew/bin:/usr/bin:/bin /opt/homebrew/bin/node /opt/homebrew/bin/npx --loglevel error -y @modelcontextprotocol/inspector@2.2.0 --cli /opt/homebrew/bin/node \<repository-root\>/fixtures/mcp/stdio-fixture-server.mjs --method tools/call --tool-name read_status --tool-arg project=suisui
{
  "content": [
    {
      "type": "text",
      "text": "status: ok project=suisui"
    }
  ],
  "isError": false
}

exit: 0
```

## Suisui local smoke success

```console
$ /usr/bin/env -i HOME=\<mcp-work-dir\>/home TMPDIR=\<mcp-work-dir\>/tmp PATH=/opt/homebrew/bin:/usr/bin:/bin /opt/homebrew/bin/node \<repository-root\>/fixtures/mcp/stdio-smoke-client.mjs --mode success
initialize: protocolVersion=2025-11-25
tools/list: read_status
tools/call: status: ok project=suisui
result: success initialize -> tools/list -> tools/call

exit: 0
```

## Suisui local failure smoke: malformed-json

```console
$ /usr/bin/env -i HOME=\<mcp-work-dir\>/home TMPDIR=\<mcp-work-dir\>/tmp PATH=/opt/homebrew/bin:/usr/bin:/bin /opt/homebrew/bin/node \<repository-root\>/fixtures/mcp/stdio-smoke-client.mjs --mode malformed-json --expect-failure malformed-json
malformed-json: Malformed JSON-RPC response.

exit: 0
```

## Suisui local failure smoke: mismatched-id

```console
$ /usr/bin/env -i HOME=\<mcp-work-dir\>/home TMPDIR=\<mcp-work-dir\>/tmp PATH=/opt/homebrew/bin:/usr/bin:/bin /opt/homebrew/bin/node \<repository-root\>/fixtures/mcp/stdio-smoke-client.mjs --mode mismatched-id --expect-failure mismatched-id
initialize: protocolVersion=2025-11-25
mismatched-id: Mismatched response id.

exit: 0
```

## Suisui local failure smoke: invalid-schema

```console
$ /usr/bin/env -i HOME=\<mcp-work-dir\>/home TMPDIR=\<mcp-work-dir\>/tmp PATH=/opt/homebrew/bin:/usr/bin:/bin /opt/homebrew/bin/node \<repository-root\>/fixtures/mcp/stdio-smoke-client.mjs --mode invalid-schema --expect-failure invalid-schema
initialize: protocolVersion=2025-11-25
invalid-schema: Tool entry inputSchema must be an object.

exit: 0
```

## Suisui local failure smoke: timeout

```console
$ /usr/bin/env -i HOME=\<mcp-work-dir\>/home TMPDIR=\<mcp-work-dir\>/tmp PATH=/opt/homebrew/bin:/usr/bin:/bin /opt/homebrew/bin/node \<repository-root\>/fixtures/mcp/stdio-smoke-client.mjs --mode timeout --expect-failure timeout
initialize: protocolVersion=2025-11-25
timeout: Timed out waiting for JSON-RPC response.

exit: 0
```

## Notes

- The Inspector commands above exercise the official MCP Inspector CLI against the same stdio fixture that Suisui uses for automated smoke coverage.
- The failure taxonomy records malformed JSON-RPC, mismatched id, invalid schema, and timeout behavior without shipping fixture code in production sources.
- Structured output and `outputSchema` release-subset validation are covered by `ExternalMCPTests.testToolsListParsesStructuredOutputSchema`, `ExternalMCPTests.testExternalMCPExecutionRequiresStructuredContentWhenOutputSchemaProvided`, and related executor regression tests. The Inspector smoke remains focused on stable stdio Tools wiring and failure taxonomy.
