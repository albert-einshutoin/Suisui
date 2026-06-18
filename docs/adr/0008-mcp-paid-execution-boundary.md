# ADR 0008: MCP Paid Execution Boundary

Date: 2026-06-19
Status: Accepted

## Context

External MCP support expands SoloPM beyond local built-in tools. Phase 11 defines `advancedMCPExecution` as a paid feature, but MCP registrations and connection diagnostics are still useful for setup, OSS contribution, and troubleshooting before a user upgrades.

The paid boundary must not weaken the existing safety model. A paid plan should unlock the ability to execute eligible external MCP tools, not bypass disabled, dangerous, or write-without-approval checks.

## Decision

Allow users to create, save, and check External MCP server registrations on Free. Gate actual `tools/call` execution with `FeatureGate.advancedMCPExecution` before any external tool call is sent.

After the paid gate passes, keep the normal permission checks:

- Unknown tools remain `disabled`.
- `dangerous` tools remain blocked.
- `writeWithApproval` tools still require an explicit approval token.
- Audit metadata must record server id, server name, tool name, permission, approval state, duration/result/error, and redacted arguments.

## Options Considered

### Gate Registration

- Pros: Simple product messaging; fewer configured integrations for Free users.
- Cons: Blocks setup, OSS fixture testing, and diagnostics; makes it harder to understand what Pro would unlock.

### Gate Execution

- Pros: Lets Free users configure and diagnose safely; keeps paid value at the real automation boundary; avoids external calls before entitlement approval.
- Cons: Requires execution-path tests to prove permission checks still run after entitlement approval.

## Consequences

- Positive: Free users can prepare MCP setup without sending tool calls.
- Positive: Paid entitlement cannot turn dangerous or unapproved write tools into executable tools.
- Negative: Settings must clearly distinguish connection diagnostics from paid execution.
- Follow-up: When MCP execution UI is exposed beyond developer paths, show the Pro gate before the approval prompt for external MCP tools.

## Links

- Related task: tasks/Phase11-ProviderSyncUXProductization.md
- Related implementation: Sources/SoloPMCore/ExternalMCP/MCPExecution.swift
- Related tests: Tests/SoloPMCoreTests/ExternalMCPTests.swift
