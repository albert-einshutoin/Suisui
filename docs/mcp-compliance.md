# SoloPM MCP Compliance Review

Last reviewed: 2026-06-19

## Baseline

SoloPM の外部MCP実装は、MCP specification `2025-11-25` を基準にする。現時点の実装対象は **client-side stdio Tools** に限定し、Resources、Prompts、Streamable HTTP、OAuth/remote MCP は未対応として扱う。

- Stable baseline: `2025-11-25`
- Official stable latest: `2025-11-25`
- Draft watchlist: `2026-07-28`
- Release positioning: SoloPM is not a full MCP host; it supports the stable stdio Tools subset described in this document.

`2026-07-28` は draft / release-candidate として監視するが、今回の release target には含めない。The final specification is scheduled for 2026-07-28. SoloPM does not send per-request protocol metadata, does not implement draft `server/discover`, and will not claim draft or full-host compatibility until those paths are implemented, tested, and inspector-backed.

Primary references:

- MCP specification 2025-11-25: https://modelcontextprotocol.io/specification/2025-11-25
- Lifecycle: https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle
- Tools: https://modelcontextprotocol.io/specification/2025-11-25/server/tools
- Architecture: https://modelcontextprotocol.io/docs/learn/architecture
- Inspector: https://modelcontextprotocol.io/docs/tools/inspector
- Draft versioning watchlist: https://modelcontextprotocol.io/specification/draft/basic/versioning
- Draft discovery watchlist: https://modelcontextprotocol.io/specification/draft/server/discover

## Current Status

| Area | Status | Evidence |
|---|---|---|
| JSON-RPC 2.0 envelope | Implemented | `MCPJSONRPCRequest` / `MCPJSONRPCNotification` / `MCPJSONRPCResponse` set and validate `jsonrpc = "2.0"`. |
| Request id matching | Implemented | `MCPClient.send` rejects mismatched response id. |
| Lifecycle initialize | Implemented | `MCPClient.initialize` sends `initialize` with `protocolVersion = 2025-11-25`, empty client capabilities, and client info before any normal operation request. It requires result `capabilities` to be an object and `serverInfo.name` / `serverInfo.version` to be strings before accepting the server. |
| Initialized notification | Implemented | `MCPClient.initialize` sends `notifications/initialized` only after a successful initialize result, and regression tests verify invalid initialize responses do not emit it. Missing or malformed `capabilities` / `serverInfo` responses fail before the initialized notification. |
| Protocol version negotiation | Implemented for current release | SoloPM offers `2025-11-25`, rejects unsupported server response versions, and shows the accepted server version in Settings after Check Connection. |
| Tools list | Implemented | `MCPClient.listTools` calls `tools/list` and parses `tools` as an array of tool definitions. |
| Tools list pagination | Implemented | `MCPClient.listTools` follows `result.nextCursor` with `params.cursor`, rejects malformed cursor metadata, and guards against repeated cursors so paginated servers are not silently truncated. |
| Tool name policy | Implemented for release subset | MCP marks 1-128 character ASCII tool names with letters, digits, underscore, hyphen, and dot as the interoperable shape, and expects names to be unique within a server. SoloPM treats names outside that shape or duplicate names across paginated responses as invalid to keep Settings, audit rows, and approval policies deterministic. |
| Tools call | Implemented | `MCPClient.callTool` calls `tools/call` with `name` and `arguments`, and parses `content`, `isError`, and `structuredContent`. When present, `structuredContent` must be a JSON object. Successful tool results with a declared `outputSchema` are validated before success audit; tool execution errors with `isError = true` stay actionable and skip output schema validation. |
| Tool schema typing | Implemented for release subset | `inputSchema` is required, root `type` must be `object`, omitted `$schema` is treated as JSON Schema 2020-12, explicit 2020-12 and draft-07 dialects are accepted, unsupported dialects are rejected with `invalid-schema`, `required` must be an array of strings, and every `properties.*` schema must be an object. `outputSchema` is optional, must be a JSON object when present, may omit root `type`, rejects non-object root `type`, accepts the same supported `$schema` dialects, and validates `structuredContent` required fields plus primitive property types. Full JSON Schema keyword validation is not claimed yet. |
| Tool permission | Implemented for SoloPM policy | Unknown external tools default to disabled; write tools require approval; dangerous tools are blocked even after paid entitlement approval. |
| Paid execution boundary | Implemented | External MCP registrations and diagnostics are available on Free, but `tools/call` execution requires `FeatureGate.advancedMCPExecution`; ADR 0008 records the decision. |
| Audit | Implemented | External MCP execution records server/tool identity, permission, approval state, duration, result/error, and redacted arguments. |
| stdio transport | Implemented | `MCPStdioTransport` launches a configured command, writes JSON-RPC lines, reads stdout, redacts stderr, times out hung calls, and supports shutdown/kill. |
| stdio command boundary | Implemented for SoloPM policy | Settings rejects composite command strings like `node server.js` before saving and requires arguments to live in the Arguments field, while still allowing exact executable paths that contain spaces. |
| Resources | Not implemented | No `resources/list` or resource read path is exposed; Settings displays "Not supported in this release". |
| Prompts | Not implemented | No `prompts/list` or prompt get path is exposed; Settings displays "Not supported in this release". |
| Streamable HTTP | Not implemented | Architecture leaves transport protocol extensibility, but only stdio is release path. |
| Draft modern protocol metadata | Not implemented | The draft `2026-07-28` path uses modern per-request protocol metadata and discovery. SoloPM remains on the stable `2025-11-25` initialize lifecycle for this release. |
| Draft server discovery | Not implemented | `server/discover` is draft-only for SoloPM's current release boundary and must not be advertised as supported. |
| Official Inspector evidence | Recorded | `script/verify_mcp_compliance.sh` runs the official MCP Inspector CLI against `fixtures/mcp/stdio-fixture-server.mjs`; `docs/release/evidence/mcp-inspector.md` records `tools/list`, `tools/call`, and failure taxonomy smoke output. |
| Settings failure taxonomy | Implemented | Settings `Check Connection` exposes `malformed-json`, `mismatched-id`, `invalid-schema`, and `timeout` through `connectionCheckResultLabel` and prefixes matching user-facing errors with the same taxonomy. |

## Tests That Currently Guard Compliance

- `ExternalMCPTests.testClientInitializesListsAndCallsToolsWith20251125Protocol`
- `ExternalMCPTests.testClientFollowsToolsListPaginationCursor`
- `ExternalMCPTests.testClientRejectsMalformedToolsListPaginationCursor`
- `ExternalMCPTests.testClientRejectsRepeatedToolsListPaginationCursor`
- `ExternalMCPTests.testToolsListRejectsInvalidToolNames`
- `ExternalMCPTests.testToolsListRejectsDuplicateToolNamesAcrossPages`
- `ExternalMCPTests.testClientRejectsUnsupportedInitializeProtocolVersionBeforeInitializedNotification`
- `ExternalMCPTests.testClientRejectsNonObjectInitializeServerInfo`
- `ExternalMCPTests.testClientRequiresInitializeCapabilitiesObject`
- `ExternalMCPTests.testClientRequiresInitializeServerInfoNameAndVersion`
- `ExternalMCPTests.testClientRejectsNonStringInitializeServerName`
- `ExternalMCPTests.testExternalMCPSettingsViewModelChecksConnectionAndRefreshesToolCatalog`
- `ExternalMCPTests.testMCPStdioTransportRunsRealProcessAndParsesLineDelimitedResponses`
- `ExternalMCPTests.testMCPStdioTransportReportsMalformedJSONAsInvalidResponse`
- `ExternalMCPTests.testClientRejectsNonBooleanToolCallIsError`
- `ExternalMCPTests.testClientRejectsNonObjectToolCallStructuredContent`
- `ExternalMCPTests.testClientRejectsNonStringToolCallTextContent`
- `ExternalMCPTests.testToolsListParsesStructuredOutputSchema`
- `ExternalMCPTests.testToolsListRejectsMalformedOutputSchema`
- `ExternalMCPTests.testExternalMCPExecutionAcceptsStructuredContentMatchingOutputSchema`
- `ExternalMCPTests.testExternalMCPExecutionRequiresStructuredContentWhenOutputSchemaProvided`
- `ExternalMCPTests.testExternalMCPExecutionRejectsStructuredContentViolatingOutputSchema`
- `ExternalMCPTests.testExternalMCPExecutionRejectsStructuredContentTypeMismatch`
- `ExternalMCPTests.testExternalMCPExecutionSkipsOutputSchemaValidationForToolErrors`
- `ExternalMCPTests.testToolsListRejectsInvalidToolInputSchema`
- `ExternalMCPTests.testToolsListRequiresToolInputSchema`
- `ExternalMCPTests.testToolsListRequiresObjectRootInputSchemaType`
- `ExternalMCPTests.testToolsListRejectsUnsupportedInputSchemaDialect`
- `ExternalMCPTests.testToolsListRejectsNonObjectPropertySchemas`
- `ExternalMCPTests.testToolsListAcceptsDefault202012InputSchemaDialect`
- `ExternalMCPTests.testToolsListAcceptsExplicitDraft07InputSchemaDialect`
- `ExternalMCPTests.testToolsListRejectsMalformedRequiredSchema`
- `ExternalMCPTests.testToolsListRejectsNonStringDescriptionMetadata`
- `ExternalMCPTests.testToolsListRejectsNonStringTitleMetadata`
- `ExternalMCPTests.testClientRejectsMismatchedResponseIDAndInvalidJSONRPCVersion`
- `ExternalMCPTests.testExternalMCPSettingsViewModelDisplaysInspectorFailureTaxonomy`
- `ExternalMCPTests.testExternalMCPSettingsRejectsCompositeCommandBeforeSavingRegistration`
- `ExternalMCPTests.testExternalMCPExecutionRequiresPaidEntitlementBeforeToolCall`
- `ExternalMCPTests.testPaidEntitlementDoesNotBypassDangerousOrApprovalGuards`
- `MCPInspectorEvidenceTests.testInspectorVerificationScriptUsesOfficialCLIAndFixturePaths`
- `MCPInspectorEvidenceTests.testMCPFixtureServerCoversSuccessAndFailureModesOutsideRuntimeSources`
- `MCPInspectorEvidenceTests.testInspectorEvidenceRecordsSuccessAndFailureTaxonomy`
- `MCPInspectorEvidenceTests.testComplianceReviewAndEvidenceRecordStableSpecAndDraftBoundary`
- `MCPInspectorEvidenceTests.testInspectorVerificationScriptRunsWithFakeInspectorWithoutNetwork`

## Gaps Before Claiming Full Compliance

- Add a deeper method-by-method matrix for optional capabilities before adding Resources, Prompts, or Streamable HTTP.
- Add comprehensive JSON Schema keyword validation only when SoloPM needs to reason about server tool arguments or outputs beyond the release subset. The current release validates MCP-required schema shape, dialect boundaries, `outputSchema` object shape, required structured output fields, and primitive output types, but does not claim full keyword-level JSON Schema validation.
- Track the draft `2026-07-28` discovery / metadata model separately from the release baseline.
- Add Streamable HTTP only after stdio compliance evidence is stable.

## Product Decision

SoloPM should not market itself as a full MCP host yet. Accurate wording for the current release is:

> External MCP stdio tools are supported with approval and audit controls. MCP Resources, Prompts, Streamable HTTP, and remote OAuth flows are planned but not included in this release.
