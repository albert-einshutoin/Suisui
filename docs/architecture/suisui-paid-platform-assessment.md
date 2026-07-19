# Suisui paid platform architecture assessment

Last reviewed: 2026-07-20

## Executive decision

The requested product is technically achievable, but the current repository is a strong local-first macOS foundation rather than a production multi-tenant sync product. The existing encrypted sync ledger and secret-free payload policy are useful foundations. The network sync client, stable server identifiers, tenant/RBAC model, production Web client, production iOS client, backend, and conflict protocol are not complete.

Use these boundaries:

- **Free / Local:** full macOS task management, voice capture, local automation, local providers, manual export.
- **Sync:** personal cross-device task/project/inbox/approval synchronization and device management.
- **Pro:** recurring workflows, advanced local agents, connector automations, larger history/retention, optional managed AI credits.
- **Team:** shared workspaces/projects, roles, policies, shared connectors, audit log, consolidated billing.
- **Enterprise:** SSO/SCIM, custom retention, legal/audit export, data residency/dedicated tenant options, support/SLA.

Web and iOS may create cloud-safe mutations. Operations requiring a local repository, filesystem bookmark, Keychain secret, microphone, or local MCP server become queued requests for an online Mac executor.

## Current implementation audit

### What can be reused

- `CloudSyncFoundation.swift` already models an encrypted operation ledger and rejects provider keys, OAuth tokens, local paths, and raw documents from plaintext sync metadata.
- `SyncDomainContract.swift` defines versioned `Codable` payloads for projects, tasks, conversations, documents, plans, automation requests, and harness state.
- Local filesystem permissions use security-scoped bookmarks and are intentionally excluded from portable backup/sync state.
- Approval queues and execution receipts already establish the correct product pattern for reviewing side effects.

### What blocks production sync

- Project/task identifiers in network-shaped contracts are local `Int64` SQLite row IDs. They can collide across devices and tenants.
- Several timestamps and states are free-form strings, weakening validation across Swift, TypeScript, SQL, and future API versions.
- No account, tenant, workspace, membership, role, device identity, remote revision, tombstone, or idempotency contract exists across all shared aggregates.
- `SyncService` has plan gating but no production network transport/backend.
- The iOS target uses local/in-memory companion state, and the Web target is a Swift contract/surface MVP rather than a deployed browser application.
- SQLite has hard-delete operations, while distributed sync requires tombstones and delayed purge.

## Database choice and type safety

### Recommended production path: SQLite + PostgreSQL

- SQLite remains the device cache and offline source of truth for a single installation.
- PostgreSQL is the shared Team/Enterprise system of record because transactions, constraints, JSON support, mature backup/observability, and row-level security fit multi-tenant collaboration.
- Enable PostgreSQL row-level security on every tenant-owned table and use a default-deny policy. Application authorization remains required; RLS is defense in depth.
- Use typed UUIDs at the domain/API boundary. Local integer primary keys may remain an adapter implementation detail.
- Generate Swift and TypeScript API types from versioned OpenAPI/JSON Schema, then validate again at the server and database boundary.
- Represent money/bytes/counters with bounded integers, instants with RFC 3339 UTC plus a separate IANA timezone where local scheduling matters, and states with extensible versioned enums.

PostgreSQL RLS reference: https://www.postgresql.org/docs/current/ddl-rowsecurity.html

### Cloudflare D1 option

D1 is viable for personal sync or a database-per-tenant small-team topology. It is not the default recommendation for a shared high-write enterprise task ledger: each database processes queries sequentially, read replication requires the Sessions API for sequential consistency, and the paid per-database limit is currently 10 GB. A D1 deployment therefore needs sharding/tenant routing and different operational assumptions from a conventional shared PostgreSQL service.

References:

- https://developers.cloudflare.com/d1/platform/limits/
- https://developers.cloudflare.com/d1/best-practices/read-replication/

## LLM provider authentication

### Safe provider modes

| Mode | Credential owner | Execution location | Product use |
| --- | --- | --- | --- |
| BYOK | User | Local Mac by default | Broad provider support; key stored in Keychain |
| GitHub Copilot SDK OAuth | User GitHub account | Local or isolated backend session | Uses the user's Copilot subscription/quota |
| Codex CLI/SDK | User ChatGPT login or API key | Local Mac | Reuse the local authenticated Codex runtime; do not copy OAuth tokens |
| OpenCode CLI | User/OpenCode provider login | Local Mac | Delegate to its auth store and permission model |
| Managed AI | Suisui | Cloud | Metered Pro/Team feature with explicit data policy |

GitHub documents per-user OAuth for Copilot SDK and charges requests against that user's Copilot subscription. The SDK is still public preview, so keep it behind a capability flag and adapter boundary.

Codex SDK wraps the Codex CLI. Suisui should either launch a user-authenticated local runtime or accept a real OpenAI API key. It must not extract or independently exchange ChatGPT OAuth tokens. OpenCode should similarly be treated as a local execution adapter rather than a source of credentials for Suisui.

References:

- https://docs.github.com/en/copilot/how-tos/copilot-sdk/setup/github-oauth
- https://docs.github.com/en/copilot/how-tos/copilot-sdk/auth/authenticate
- https://github.com/openai/codex/blob/main/sdk/typescript/README.md
- https://opencode.ai/docs/providers

## Meeting minutes feasibility

### macOS capture MVP

ScreenCaptureKit can capture system audio and microphone audio with the required macOS permissions. The MVP can detect a calendar conference URL, ask whether to prepare/capture, show a persistent recording indicator, transcribe locally or through the selected provider, and draft decisions/tasks for approval.

One mixed system-audio stream does not provide trustworthy participant identity. Local diarization can label `Speaker 1`, `Speaker 2`, and so on, but names must remain unverified unless matched to provider artifacts or confirmed by the user.

References:

- https://developer.apple.com/documentation/screencapturekit
- https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos

### Provider artifacts

- **Google Meet:** conference transcript entries include time ranges, text, language, and a participant resource. Participant resources can resolve signed-in, anonymous, or phone users, subject to availability/privacy constraints.
- **Microsoft Teams:** Microsoft Graph exposes meeting transcripts and metadata when recording/transcription and tenant policy permit access. Speaker attribution depends on the transcript content and tenant configuration.
- **Zoom:** cloud recording can expose VTT transcripts; separate participant audio tracks are only available when the host/account recording configuration enabled them. Unknown speakers must remain unknown.

References:

- https://developers.google.com/workspace/meet/api/reference/rest/v2/conferenceRecords.transcripts.entries
- https://developers.google.com/workspace/meet/api/guides/participants
- https://learn.microsoft.com/en-us/microsoftteams/platform/graph-api/meeting-transcripts/overview-transcripts
- https://learn.microsoft.com/en-us/graph/api/resources/calltranscript?view=graph-rest-1.0
- https://developers.zoom.us/docs/api/meetings/
- https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0064927

## Audio retention and storage controls

The current capture record requires an audio file path. Change it to an optional attachment plus an explicit retention policy. The Japanese-first default should be:

1. Explain that raw audio is optional and larger than transcripts/tasks.
2. Default to **delete after transcription**.
3. Offer never store, until transcription, 7 days, 30 days, 90 days, and keep until deleted.
4. Let users export/delete raw audio, transcript, summary, and derived tasks independently.
5. For Team/Enterprise, enforce the stricter of user and workspace retention policies and record consent/audit events.

Settings should show bytes for the database, active tasks, completed tasks, archived projects, documents, transcripts, raw audio, backups, and caches. CSV export must escape spreadsheet formulas (`=`, `+`, `-`, `@`), use UTF-8, and preview included private data.

## Safe local automation

Use a declarative workflow rather than storing arbitrary shell text as an invisible cron entry. Each workflow includes schedule/timezone, approved inputs, sandbox/worktree, writable paths, network policy, approval policy, and expected outputs.

- Schedule durable local runs with `launchd`.
- Create an isolated git worktree for repository mutations.
- Use a minimal environment so provider/API credentials are not inherited accidentally.
- Deny deletion, force push, destructive git operations, and writes outside approved paths by default.
- Voice may create or trigger a workflow, but installation and risky execution remain reviewable.
- Persist redacted receipts and show next run, last run, duration, failure, and retry state.

## Integration priorities

1. Google/Apple Calendar: event context, meeting detection, scheduling, and time blocking.
2. Microsoft 365 Calendar/Teams and Zoom: enterprise meetings and official transcript artifacts.
3. GitHub: issue/PR progress as project evidence.
4. Slack/Microsoft Teams messaging: task capture and approval-gated notifications.
5. Linear/Jira/Todoist: task import/link, then carefully scoped bidirectional sync.
6. Notion/Google Drive/Gmail: linked source context and draft creation before external writes.

Every connector needs a documented OAuth scope, execution location, plan, data classes, retention, rate-limit behavior, webhook verification, revocation flow, and approval requirement.
