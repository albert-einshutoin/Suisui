# SoloPM MCP Compliance Review

Last reviewed: 2026-06-19

## Baseline

SoloPM の外部MCP実装は、MCP specification `2025-11-25` を基準にする。現時点の実装対象は **client-side stdio Tools** に限定し、Resources、Prompts、Streamable HTTP、OAuth/remote MCP は未対応として扱う。

Primary references:

- MCP specification 2025-11-25: https://modelcontextprotocol.io/specification/2025-11-25
- Lifecycle: https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle
- Tools: https://modelcontextprotocol.io/specification/2025-11-25/server/tools
- Architecture: https://modelcontextprotocol.io/docs/learn/architecture
- Inspector: https://modelcontextprotocol.io/docs/tools/inspector

## Current Status

| Area | Status | Evidence |
|---|---|---|
| JSON-RPC 2.0 envelope | Implemented | `MCPJSONRPCRequest` / `MCPJSONRPCNotification` / `MCPJSONRPCResponse` set and validate `jsonrpc = "2.0"`. |
| Request id matching | Implemented | `MCPClient.send` rejects mismatched response id. |
| Lifecycle initialize | Implemented | `MCPClient.initialize` sends `initialize` with `protocolVersion = 2025-11-25`, empty client capabilities, and client info before any normal operation request. |
| Initialized notification | Implemented | `MCPClient.initialize` sends `notifications/initialized` only after a successful initialize result, and regression tests verify invalid initialize responses do not emit it. |
| Protocol version negotiation | Implemented for current release | SoloPM offers `2025-11-25`, rejects unsupported server response versions, and shows the accepted server version in Settings after Check Connection. |
| Tools list | Implemented | `MCPClient.listTools` calls `tools/list` and parses `tools` as an array of tool definitions. |
| Tools call | Implemented | `MCPClient.callTool` calls `tools/call` with `name` and `arguments`, and parses `content`, `isError`, and `structuredContent`. |
| Tool schema typing | Partially implemented | `inputSchema` must be an object; `required` must be an array of strings; `properties` must be an object when present. Full JSON Schema validation is not implemented yet. |
| Tool permission | Implemented for SoloPM policy | Unknown external tools default to disabled; write tools require approval; dangerous tools are blocked. |
| Audit | Implemented | External MCP execution records server/tool identity, permission, approval state, duration, result/error, and redacted arguments. |
| stdio transport | Implemented | `MCPStdioTransport` launches a configured command, writes JSON-RPC lines, reads stdout, redacts stderr, times out hung calls, and supports shutdown/kill. |
| Resources | Not implemented | No `resources/list` or resource read path is exposed; Settings displays "Not supported in this release". |
| Prompts | Not implemented | No `prompts/list` or prompt get path is exposed; Settings displays "Not supported in this release". |
| Streamable HTTP | Not implemented | Architecture leaves transport protocol extensibility, but only stdio is release path. |
| Official Inspector evidence | Recorded | `script/verify_mcp_compliance.sh` runs the official MCP Inspector CLI against `fixtures/mcp/stdio-fixture-server.mjs`; `docs/release/evidence/mcp-inspector.md` records `tools/list`, `tools/call`, and failure taxonomy smoke output. |

## Tests That Currently Guard Compliance

- `ExternalMCPTests.testClientInitializesListsAndCallsToolsWith20251125Protocol`
- `ExternalMCPTests.testClientRejectsUnsupportedInitializeProtocolVersionBeforeInitializedNotification`
- `ExternalMCPTests.testClientRejectsNonObjectInitializeServerInfo`
- `ExternalMCPTests.testClientRejectsNonStringInitializeServerName`
- `ExternalMCPTests.testExternalMCPSettingsViewModelChecksConnectionAndRefreshesToolCatalog`
- `ExternalMCPTests.testMCPStdioTransportRunsRealProcessAndParsesLineDelimitedResponses`
- `ExternalMCPTests.testMCPStdioTransportReportsMalformedJSONAsInvalidResponse`
- `ExternalMCPTests.testClientRejectsNonBooleanToolCallIsError`
- `ExternalMCPTests.testClientRejectsNonStringToolCallTextContent`
- `ExternalMCPTests.testClientRejectsInvalidToolInputSchema`
- `ExternalMCPTests.testClientRejectsInvalidRequiredSchemaEntries`
- `ExternalMCPTests.testClientRejectsNonStringToolDescription`
- `ExternalMCPTests.testClientRejectsNonStringToolTitle`
- `ExternalMCPTests.testClientRejectsMismatchedResponseIDAndInvalidJSONRPCVersion`
- `MCPInspectorEvidenceTests.testInspectorVerificationScriptUsesOfficialCLIAndFixturePaths`
- `MCPInspectorEvidenceTests.testMCPFixtureServerCoversSuccessAndFailureModesOutsideRuntimeSources`
- `MCPInspectorEvidenceTests.testInspectorEvidenceRecordsSuccessAndFailureTaxonomy`
- `MCPInspectorEvidenceTests.testInspectorVerificationScriptRunsWithFakeInspectorWithoutNetwork`

## Gaps Before Claiming Full Compliance

- Add a deeper method-by-method matrix for optional capabilities before adding Resources, Prompts, or Streamable HTTP.
- Validate more of `inputSchema` against JSON Schema rules or document the intentionally limited validation boundary.
- Add Streamable HTTP only after stdio compliance evidence is stable.

## Product Decision

SoloPM should not market itself as a full MCP host yet. Accurate wording for the current release is:

> External MCP stdio tools are supported with approval and audit controls. MCP Resources, Prompts, Streamable HTTP, and remote OAuth flows are planned but not included in this release.
