# Multiplatform Task Management and Automation Vision

Verified: 2026-06-21

## Positioning

SoloPM starts as a macOS-first local app, but the long-term product should become a task management and automation layer that is available from iOS, Web, and macOS.

The target promise is:

> Talk to SoloPM from any device, review what it understood, and let it turn project context into tasks, status updates, preparation work, and draft artifacts.

This expands the product beyond a desktop task board without turning it into an unrestricted cloud agent. The product should remain approval-first, auditable, and local-first where the platform allows it.

## Product Shape

| Surface | Primary job | Notes |
| --- | --- | --- |
| macOS app | Power-user workspace, local files, Calendar/Reminders/Notifications, local MCP, local review and execution | Remains the strongest execution surface because it can access local OS capabilities. |
| iOS app | Capture, conversation, task review, notifications, lightweight project status changes | Best surface for PC-off task creation and mobile approval. |
| Web app | Cross-device task board, account/billing, automation review, project docs, team/admin later | Should not require local Mac availability for basic task management. |
| Cloud Relay / Hosted MCP | Always-on API endpoint for task capture and pending automation requests | Pro capability; remote writes must be policy-gated and audited. |

## Core Experience

The core interaction should be conversational:

```text
User: "今週やるべきリリース準備タスクを列挙して"
SoloPM: lists current tasks and missing preparation items
User: "署名まわりを進行中にして、Notarization確認は明日までにして"
SoloPM: proposes status and due-date changes
User: approves
SoloPM: updates tasks and records an audit trail
```

Supported conversation operations:

- List tasks by project, status, due date, priority, source, or stale state.
- Create tasks from natural language.
- Change task status.
- Move tasks between projects.
- Change due dates and priority.
- Summarize project health.
- Identify blocked or missing preparation work.
- Produce draft artifacts from project context.

## Automation From Project Context

SoloPM should optionally let AI inspect scoped app and project documents before proposing work.

Sources:

- App documentation, such as setup guides, release checklists, coding standards, and runbooks.
- Project documentation, such as specs, PRDs, task plans, ADRs, issue notes, and local artifacts.
- Existing tasks, project metadata, audit log summaries, and conversation history.
- Optional external connectors later, such as GitHub issues or calendar state.

Outputs:

- Tasks.
- Status changes.
- Due-date changes.
- Preparation checklists.
- Draft documents.
- Release notes.
- Pull request plans.
- MCP/tool execution plans.
- Harness test runs and reports.

The default output should be a reviewed plan, not surprise execution. Low-risk task creation can be auto-applied only when a user-configured policy allows it.

## Safety Model

The automation model must preserve SoloPM's existing trust boundaries:

- Every AI-generated mutation is represented as an Action Plan or pending action.
- Writes are categorized by risk.
- User approval is required for risky, destructive, external, or ambiguous changes.
- External MCP and Cloud Relay execution remains a paid and gated capability.
- Audit logs record input source, scoped documents, tool calls, approvals, and redacted arguments.
- Secrets stay in platform secure storage and must not be synced or logged in plaintext.

Why: cross-platform automation increases the blast radius. The product should win trust by being clear about what it read, what it plans to change, and what was actually executed.

## Data Architecture

SoloPM needs a shared domain model across iOS, Web, and macOS:

| Domain | Purpose |
| --- | --- |
| Project | Work container with status, goals, docs, artifacts, and tasks. |
| Task | Concrete unit with title, status, due date, priority, project, source, and audit metadata. |
| Conversation | User requests, AI responses, extracted intents, approvals, and references. |
| Document | App/project context that can be indexed and scoped for AI requests. |
| Action Plan | Provider-neutral plan for task changes, artifact drafts, and tool calls. |
| Automation Request | Cloud-created pending work that can be reviewed and executed later. |
| Harness Run | Repeatable verification result for prompts, providers, tool calls, and automation behavior. |

Sync should be ledger-based enough to handle offline clients and delayed execution. A task created on iOS while the Mac is offline must sync into the same project history when macOS later starts.

## Platform Strategy

Recommended order:

1. **macOS alpha**
   - Keep shipping the current local-first app.
   - Strengthen task CRUD, conversation-to-action, providers, and local auditability.

2. **Cloud Sync foundation**
   - E2EE sync for Project, Task, Settings-safe fields, Conversation metadata, and selected Document metadata.
   - Do not sync provider API keys in plaintext.

3. **iOS companion**
   - Capture, Inbox, task listing, status changes, due-date changes, conversation, notifications, and approval.
   - Defer heavy local execution and filesystem automation to macOS or Cloud Relay.

4. **Web app**
   - Task board, project docs, conversation, account/billing, automation review, and team foundations.
   - Keep Web execution limited to cloud-safe actions unless a local device or relay worker is explicitly connected.

5. **Cloud Relay / Hosted MCP**
   - Always-on task creation and pending automation endpoint.
   - External LLM/API clients can create tasks or pending actions when the user's devices are unavailable.

6. **Harness**
   - Verify provider prompts, task mutation flows, document-scoped automation, and MCP tool compatibility across platforms.

## iOS Scope

Initial iOS should not try to replicate every macOS power feature.

Must have:

- Sign in / restore entitlement.
- Sync task and project data.
- Inbox and Today.
- Project task list and board-lite status controls.
- Conversational command input.
- Task create, complete, status change, project move, due-date change.
- Push/local notifications.
- Approval inbox for pending actions.

Should have:

- Shortcuts integration for "create task" and "ask SoloPM".
- Voice input.
- Share sheet ingestion.
- Offline capture that syncs later.

Defer:

- Local filesystem artifact generation.
- Arbitrary external MCP execution.
- Heavy document indexing.

## Web Scope

Initial Web should focus on availability and administration:

- Task board and list.
- Project docs and artifacts.
- Conversation history and automation review.
- Account, billing, devices, and relay tokens.
- Hosted MCP endpoint management.
- Harness run history.

Web should not become the only source of truth for local-only data. It should operate on the synced domain and clearly show when a local Mac is required for OS-bound actions.

## Document-Scoped AI Requests

Users should be able to configure which documents AI may use:

| Scope | Example | Default |
| --- | --- | --- |
| App docs | release checklist, coding standards, onboarding docs | Off until selected |
| Project docs | PRD, task phase docs, ADRs, specs | Project-level opt-in |
| Task artifacts | draft notes, release notes, generated files | Opt-in per project |
| External sources | GitHub issues, calendar, SaaS docs | Later and connector-specific |

For each AI request, SoloPM should show:

- Documents considered.
- Why they were included.
- The proposed task or artifact changes.
- The write risk.
- Whether approval is required.

## Pricing Implication

This direction strengthens the existing pricing model:

- Free: local macOS app and BYOK task management.
- Sync: iOS/Web/macOS access to the same tasks and projects.
- Pro: Cloud Relay, Hosted MCP, PC-off task creation, document-scoped automation, and Harness.
- Team: shared projects, shared docs, organization policies, admin audit, and team harnesses.

The main paid wedge remains:

> SoloPM can receive and prepare work even when your Mac is not running.

## Non-Goals

- Do not market SoloPM as an unrestricted autonomous agent.
- Do not let a cloud LLM mutate local data without an explicit policy and audit trail.
- Do not sync raw secrets.
- Do not make Web-only behavior diverge from the shared Action Plan model.
- Do not add team/RBAC before personal cross-device sync is reliable.

## Open Decisions

- Whether iOS ships before Web or alongside the first Cloud Sync beta.
- Whether mobile low-risk task creation can auto-apply by default or must start as review-only.
- Which document formats are supported first for scoped AI context.
- Whether document embeddings are local-only, cloud-side encrypted, or provider-side per request.
- How much Harness execution history is retained on Sync versus Pro.
