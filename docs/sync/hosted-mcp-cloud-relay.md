# Hosted MCP and Cloud Relay Contract

Verified: 2026-06-21

## Purpose

Hosted MCP and Cloud Relay let external LLM/API clients capture task work while the primary Mac is unavailable. The contract is intentionally task-first and pending-action-first; it is not a general remote executor.

## Endpoint Credentials

Each user-owned endpoint should have:

- Endpoint ID.
- Client ID.
- Hashed bearer token or OAuth client reference.
- Created-at and last-used-at timestamps.
- Revoked-at timestamp.
- Tool allowlist.
- Per-client rate limit.

Tokens must be shown only once, stored hashed server-side, and never written to local SQLite, logs, sync payload plaintext, screenshots, or test fixtures.

## Initial Hosted MCP Tools

Suisui exposes only remote-safe task mutation tools:

| Tool | Required arguments | Approval state |
| --- | --- | --- |
| `task_create` | `title` | Not required when the user's policy allows plain task auto-create |
| `task_update` | `taskID` | Pending approval |
| `task_complete` | `taskID` | Pending approval |
| `task_due_date_update` | `taskID`, `dueAt` | Pending approval |
| `task_project_move` | `taskID`, `projectID` | Pending approval |

Calendar, filesystem, external connector, and destructive task deletion tools are deliberately excluded from the Hosted MCP task schema. They can be proposed later as pending actions only after a dedicated policy and audit surface exists.

## Sync Ledger Behavior

Incoming requests are represented as `SyncAutomationRequestPayload` records with:

- Source client ID.
- Tool name.
- Redacted argument summary.
- Platform-neutral `SyncTaskMutationPayload`.
- Approval state.

The encrypted sync ledger stores the request as `SyncLedgerEntityKind.automationRequest` with `appendLedgerEntry` merge behavior. This lets mobile/Web/cloud capture append work while offline devices reconcile later.

## Approval Rules

The default personal policy permits only plain `task_create` to become `.notRequired`. Updates, completion, due-date changes, and project moves stay `.pendingApproval` because they mutate existing work and can surprise the user if applied remotely.

Dangerous, destructive, external write, and OS-bound actions must not be accepted through this task schema. They should be converted into a pending action with explicit review, or rejected until a dedicated Pro policy is implemented.

## Rate Limits and Revocation

Initial hosted endpoints should enforce:

- Per-client request rate limits.
- Per-workspace burst limits.
- Replay protection using request IDs.
- Immediate revocation by token/client ID.
- Audit entries for accepted, rejected, and rate-limited requests.

Rate-limit failures should not create sync ledger entries. Accepted but approval-required requests should create a pending automation request so every device can show the review state.
