# SoloPM Product Roadmap

This roadmap fixes the product order for the current public-alpha work: Personal MVP first, Business MVP after the personal voice-task loop is proven.

## Product Order

1. Personal MVP: a local-first voice-task loop for one user.
2. Personal automation and sync: richer personal workflows after the core loop works.
3. Business MVP: organization, governance, KnowledgeBase/RAG, QZT, Memory Pager, billing, and audit controls.

## Personal MVP

Goal: prove that a single user can speak work into SoloPM and get reliable task, project, schedule, reminder, and approval state without team setup.

Core scope:

- Voice or text capture for loose work requests.
- Local OSS STT/TTS readiness where practical, with provider fallbacks kept explicit.
- Voice Command Router for task, schedule, document, and development-work intents.
- Clarification loop for missing due date, project, action scope, or execution risk.
- Inbox triage, Today planning, missed-task review, and daily follow-up.
- Local tasks/projects CRUD and calendar/reminder/notification drafts with approval.
- Personal project directory selection with scoped file create/read/update permissions.
- Assistant Queue, approval-first execution, and redacted local receipts.
- Settings readiness for provider, STT/TTS, calendar, reminders, and sync-disabled state.

Non-goals for the first personal release:

- Organizations, roles, tenant policies, and audit export are Business MVP scope.
- KnowledgeBase production connector is Business MVP scope.
- QZT-backed evidence storage is Business MVP scope.
- Memory Pager production context assembly is Business MVP scope.
- Remote task execution while the user's PC is offline is not part of the first personal release.

## Personal Automation And Sync

Goal: extend the personal loop after the core value is usable.

Scope:

- Google Calendar OAuth/runtime sync after the local calendar cockpit is reliable.
- LINE, Slack, Discord, and other connector drafts with explicit approval.
- Meeting brief generation from local related documents and prior conversation history.
- Read-aloud meeting briefs through the TTS path.
- Web and iOS sync as paid add-ons, following local-first and E2EE boundaries.
- Developer task automation from an approved project directory into branch/PR workflows.

## Business MVP

Goal: make SoloPM usable for small companies where task quality depends on internal documents, governance, and shared execution policy.

Scope:

- Organization/workspace model, members, roles, and tenant-safe settings.
- Business plan entitlement, billing, and usage ledger.
- KnowledgeBase project linking and tenant-safe RAG query contract.
- QZT evidence refs for citations, receipts, and document provenance.
- Memory Pager context assembly for tasks, projects, customer docs, and meeting prep.
- Knowledge-backed task generation, decision history, and current-status summaries.
- Workspace policies for AI execution, external connectors, retention, and audit export.

## Cross-Product Boundary

SoloPM should not absorb every adjacent product.

- SoloPM owns voice-first task organization, approval queues, personal automation, and later business governance.
- KnowledgeBase owns small-business internal document search and web voice customer support.
- QZT owns seekable, verifiable evidence storage.
- Memory Pager owns memory extraction, ranking, retrieval, and context assembly.

The products can share identity, billing, EvidenceRef, and connector contracts, but the first SoloPM MVP must remain useful without KnowledgeBase, QZT, or Memory Pager running.

## Tracking

- Roadmap tracker: https://github.com/albert-einshutoin/soloPM/issues/50
- Cross-product boundary: https://github.com/albert-einshutoin/soloPM/issues/41
- Business knowledge-work milestone: https://github.com/albert-einshutoin/soloPM/milestone/3
