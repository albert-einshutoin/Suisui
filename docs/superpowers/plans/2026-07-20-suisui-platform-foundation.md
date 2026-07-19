# Suisui platform foundation implementation plan

> Status: execution plan for the unreleased product rename and the paid, multi-device roadmap.

## Product decisions

- The public brand, package, executable, modules, source paths, configuration keys, bundle artifacts, documentation, and GitHub repository become `Suisui` before the first release.
- Local-first remains the free product. Paid sync adds Web/iOS access and team sharing without silently granting cloud access to local files or local credentials.
- PostgreSQL is the primary shared-data store. SQLite remains the offline device store. Cloudflare D1 stays an evaluated personal/small-tenant deployment option, not the default Team/Enterprise database.
- Provider API keys remain in the macOS Keychain by default. Subscription-based tools run through their official local CLI/SDK authentication boundary. Server-side use requires a separately consented OAuth or managed credential.
- Raw meeting audio is opt-in, retention-bounded, exportable, and deletable. A transcript and derived tasks have separate retention controls.
- Local automation executes in an isolated worktree/sandbox with deletion denied by default and every side effect represented by an approval and receipt.

## Phase 1: Complete the source and repository rename

### Task 1.1: Pin the new SwiftPM contract with tests

Files:
- Modify: `Tests/SoloPMCoreTests/PackageContractTests.swift` (or the existing package contract test)
- Modify: `Package.swift`

Steps:

- [ ] Add a failing test/script assertion that package, products, targets, and executable names contain `Suisui` and no longer expose `SoloPM`.
- [ ] Rename package products and targets to `SuisuiCore`, `SuisuiExternalConnectors`, `SuisuiGoogleCalendarRuntime`, `SuisuiiOS`, `SuisuiWeb`, `Suisui`, `SuisuiCLI`, and `SuisuiCoreTests`.
- [ ] Rename the command-line executable to `suisui-cli`.
- [ ] Run `swift package describe` and the focused contract tests.
- [ ] Commit the package contract separately.

### Task 1.2: Rename modules, source paths, symbols, and configuration keys

Files:
- Rename: `Sources/SoloPMCore` -> `Sources/SuisuiCore`
- Rename: `Sources/SoloPMApp` -> `Sources/SuisuiApp`
- Rename: `Sources/SoloPMCLI` -> `Sources/SuisuiCLI`
- Rename: `Sources/SoloPMExternalConnectors` -> `Sources/SuisuiExternalConnectors`
- Rename: `Sources/SoloPMGoogleCalendarRuntime` -> `Sources/SuisuiGoogleCalendarRuntime`
- Rename: `Sources/SoloPMiOS` -> `Sources/SuisuiiOS`
- Rename: `Sources/SoloPMWeb` -> `Sources/SuisuiWeb`
- Rename: `Tests/SoloPMCoreTests` -> `Tests/SuisuiCoreTests`
- Modify: tracked Swift, scripts, workflows, docs, plist, localization, and packaging files containing old identifiers

Steps:

- [ ] Apply case-aware replacements: `SOLOPM` -> `SUISUI`, `SoloPM` -> `Suisui`, `soloPM`/`solopm` -> `suisui`.
- [ ] Rename tracked filenames and bundle resources that contain the old name.
- [ ] Remove the temporary compatibility comment/keys because no released installation requires migration.
- [ ] Assert `git grep` finds no old product identifier in tracked files.
- [ ] Run `swift test`, release build, packaging inventory, localization, and security checks.
- [ ] Commit the mechanical rename separately from behavior changes.

### Task 1.3: Rename GitHub and update clone metadata

Files:
- Modify: repository badges, clone URLs, issue/PR templates, release docs

Steps:

- [ ] Rename `albert-einshutoin/soloPM` to `albert-einshutoin/Suisui` after the source rename is pushed.
- [ ] Update the local `origin` URL and verify fetch/push.
- [ ] Verify workflows do not reference the old repository through hosted reusable-action paths.
- [ ] Do not recreate the old GitHub repository name because that would break redirects.
- [ ] Move the local checkout only after open stacked PRs are merged; preserve the user-owned untracked `outputs/` directory.

## Phase 2: Make sync identifiers and contracts server-safe

### Task 2.1: Introduce globally stable domain identifiers

Files:
- Modify: `Sources/SuisuiCore/Sync/SyncDomainContract.swift`
- Modify: `Sources/SuisuiCore/Sync/CloudSyncFoundation.swift`
- Modify: SQLite schema/store files under `Sources/SuisuiCore`
- Test: corresponding sync and SQLite tests under `Tests/SuisuiCoreTests`

Steps:

- [ ] Add typed UUID-backed IDs for account, tenant, workspace, membership, device, project, task, meeting, attachment, and operation.
- [ ] Keep local integer row IDs private to SQLite adapters; never expose them in network contracts.
- [ ] Replace stringly typed status/time fields with versioned enums and `Date` encoded as RFC 3339.
- [ ] Add `createdAt`, `updatedAt`, `deletedAt`, revision, origin device, idempotency key, and schema version.
- [ ] Add migration tests from the current schema and round-trip tests shared by Swift and generated Web fixtures.

### Task 2.2: Define the offline-first conflict protocol

Files:
- Add: `docs/sync/suisui-sync-protocol.md`
- Modify: sync ledger/service files
- Test: sync conflict, replay, duplicate, and authorization tests

Steps:

- [ ] Define append-only operations, tombstones, per-device cursors, idempotent replay, and server acknowledgement.
- [ ] Use field-aware merge only for explicitly mergeable data; route destructive or ambiguous conflicts to the Assistant Queue.
- [ ] Add transactional outbox/inbox storage so app termination cannot lose an accepted mutation.
- [ ] Add server contract generation from OpenAPI/JSON Schema for Swift and TypeScript clients.

## Phase 3: Build the paid account, workspace, and sharing boundary

### Task 3.1: Implement tenancy and authorization contracts

Files:
- Add: workspace/account domain files under `Sources/SuisuiCore`
- Modify: entitlement models and Web/iOS surface contracts
- Test: tenant isolation and RBAC matrix tests

Steps:

- [ ] Model Personal, Team, and Enterprise workspaces with owner/admin/member/viewer/automation-reviewer/billing-admin roles.
- [ ] Require `workspaceID` in every shared aggregate and authorization decision.
- [ ] Enforce policy in the server/database layer, not only the UI.
- [ ] Add audit events for membership, role, policy, export, deletion, connector, and approval changes.

### Task 3.2: Implement backend and device synchronization

Files:
- Add: backend service as a separate workspace package after ADR approval
- Modify: `Sources/SuisuiCore/Sync/SyncService.swift`
- Modify: `Sources/SuisuiiOS` and `Sources/SuisuiWeb`

Steps:

- [ ] Use PostgreSQL with row-level security for the production Team/Enterprise path.
- [ ] Add OAuth/OIDC account sessions, short-lived access tokens, refresh rotation, device registration, and remote revocation.
- [ ] Implement encrypted transport, structured payload validation, rate limits, quotas, observability, and backups.
- [ ] Replace the current unavailable network client and in-memory iOS/Web mutations with real generated clients.

## Phase 4: Provider authentication and safe AI execution

### Task 4.1: Add a provider capability registry

Files:
- Add: provider auth/capability domain files under `Sources/SuisuiCore`
- Modify: Settings provider UI and Keychain storage
- Test: credential isolation, revocation, and capability tests

Steps:

- [ ] Support local BYOK providers using Keychain references only.
- [ ] Support GitHub Copilot SDK through GitHub OAuth/per-user tokens and explicitly label its public-preview status.
- [ ] Support Codex SDK by delegating to a user-authenticated local Codex CLI or an API key; do not invent a third-party ChatGPT token exchange.
- [ ] Support OpenCode by launching the approved local binary with its own auth store and permission policy; do not copy provider tokens into Suisui.
- [ ] Separate local subscription execution from cloud-managed execution in entitlements, receipts, and UI copy.

### Task 4.2: Enforce execution isolation

Files:
- Modify: developer-mode execution and approval code under `Sources/SuisuiCore/DeveloperMode`
- Add: worktree/sandbox policy and executor tests

Steps:

- [ ] Create a disposable git worktree for repository mutations.
- [ ] Run commands with a minimal environment and an explicit writable-path allowlist.
- [ ] Deny deletion, force push, credential reads, and writes outside the sandbox by default.
- [ ] Require a separate approval for publishing, merging, deleting, or copying changes back.
- [ ] Persist command, diff, policy decision, and result in redacted execution receipts.

## Phase 5: Storage, retention, export, and deletion controls

### Task 5.1: Add storage accounting

Files:
- Add: storage usage domain/service under `Sources/SuisuiCore`
- Modify: Settings views under `Sources/SuisuiApp`
- Test: byte accounting and Japanese accessibility/localization tests

Steps:

- [ ] Report database, active tasks, completed tasks, archived projects, documents, transcripts, raw audio, backups, caches, and total bytes.
- [ ] Calculate expensive file sizes off the main actor and cache results with an invalidation token.
- [ ] Show local and cloud quota separately.
- [ ] Add CSV export with stable UTF-8 headers, ISO dates, formula-injection escaping, and a privacy preview.

### Task 5.2: Make audio retention an explicit choice

Files:
- Modify: inbox/voice capture schema and Settings
- Test: no-audio, session-only, retained, expiration, export, and deletion behavior

Steps:

- [ ] Allow `audio_file_path` to be absent and store a retention policy instead.
- [ ] Default to deleting raw audio after transcription while keeping a reviewable transcript only when approved.
- [ ] Offer never store, until transcription, 7/30/90 days, and keep until deleted.
- [ ] Keep transcript, summary, tasks, and raw audio as separate deletion/export scopes.
- [ ] Use soft deletion/tombstones for synced records and an explicit second confirmation for permanent purge.

## Phase 6: Meeting minutes MVP and provider adapters

### Task 6.1: macOS-only capture MVP

Files:
- Add: meeting capture/consent domain under `Sources/SuisuiCore`
- Add: ScreenCaptureKit adapter under `Sources/SuisuiApp`
- Modify: calendar meeting UI and Settings
- Test: consent, prompt preference, capture state, retention, and task extraction

Steps:

- [ ] Detect calendar events with conference URLs locally.
- [ ] Ask before capture at the first matching meeting and persist one of: always ask, automatically prepare but never record, or do nothing.
- [ ] Require a visible start action and recording indicator for every capture.
- [ ] Capture system audio/microphone through ScreenCaptureKit only after macOS permission succeeds.
- [ ] Produce transcript, summary, decisions, owners, due dates, and reviewable task drafts.
- [ ] Treat speaker attribution from a single mixed audio stream as best-effort diarization, not verified identity.

### Task 6.2: Add official artifact adapters later

Files:
- Add: Google Meet, Microsoft Teams, and Zoom connector adapters
- Test: provider auth, tenant policy, participant mapping, and missing-artifact behavior

Steps:

- [ ] Google Meet: import conference transcript entries and participant resources when available.
- [ ] Microsoft Teams: import Graph transcripts where tenant recording/transcription policy permits it.
- [ ] Zoom: import cloud recording VTT and participant audio tracks only when the account/meeting configuration provides them.
- [ ] Never promise speaker identity when the provider returns anonymous/unknown speakers.

## Phase 7: Calendar, task, and communication integrations

### Task 7.1: Publish and implement the connector priority matrix

Files:
- Modify: `docs/integrations/integration-capability-matrix.md`
- Modify: Settings integration readiness UI

Priority:

1. Google Calendar and Apple Calendar: meeting detection, time blocking, due-task scheduling.
2. Microsoft 365 Calendar/Teams and Zoom: enterprise meetings and transcript import.
3. GitHub: issues/PRs/receipts linked to projects.
4. Slack and Microsoft Teams messaging: approval-gated notification and task capture.
5. Linear, Jira, Todoist, Notion, Google Drive, and Gmail: import/link first, bidirectional mutation only after conflict semantics are defined.

Steps:

- [ ] Define execution location, OAuth scopes, stored data, plan gate, review requirement, webhook model, and failure mode for each connector.
- [ ] Start read-only and draft-only; require explicit approval for external writes.
- [ ] Encrypt refresh tokens, rotate/revoke them, and never include them in sync payloads or diagnostics.

## Phase 8: Local scheduled workflows and voice-triggered batches

### Task 8.1: Implement a declarative workflow model

Files:
- Modify: automation domain under `Sources/SuisuiCore`
- Modify: automation Settings/UI under `Sources/SuisuiApp`
- Test: schedule, missed run, pause, duplicate suppression, and voice command tests

Steps:

- [ ] Store schedule, timezone, command/template, approved inputs, sandbox policy, output expectations, and notification policy.
- [ ] Use `launchd` for durable macOS scheduling instead of embedding a fragile long-running cron loop.
- [ ] Provide voice commands to create, review, run, pause, and edit a workflow.
- [ ] Require preview and approval before installation; default external sends and filesystem mutations to draft-only.
- [ ] Show next run, last run, duration, result, receipt, and retry state.

## Quality gates for every phase

- [ ] Write or update tests first and confirm the intended failure.
- [ ] Keep business logic independent of SwiftUI and persistence adapters.
- [ ] Add comments explaining non-obvious safety, memory, and efficiency decisions.
- [ ] Run focused tests, full `swift test`, Release build, localization/AX checks, secret scan, dependency scan, and `git diff --check` as appropriate.
- [ ] Self-review the diff for tenant leaks, destructive defaults, secret exposure, and main-thread work.
- [ ] Use small commits and keep each PR independently understandable.
- [ ] Update existing detailed issues rather than creating duplicates; create new issues only for uncovered deliverables.
