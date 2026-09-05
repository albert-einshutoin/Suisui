# AI Secretary UX Direction

Date: 2026-06-25

Suisui should grow from a personal AI PM into an AI secretary for tasks, documents, and chores. The product role is not a generic chat surface. It is a local-first work desk that receives ordinary work, turns it into reviewable tasks, drafts, schedules, reminders, and follow-ups, then asks the user before external writes or destructive actions.

## Product Stance

- Purpose: turn incoming personal work into reviewed task, document, schedule, and reminder actions.
- Primary audience: a solo operator who repeats the same capture, triage, draft, schedule, and follow-up loops every day.
- Tone: quiet, dense, Mac-native, and practical enough for recurring desk work.
- Memorable detail: a contextual Inspector or Review surface that explains the next mundane action, the evidence behind it, and the approval boundary without requiring a permanent rail on every screen.
- Constraints: local-first storage, Keychain-backed secrets, review-before-execution, VoiceOver task listing, and no unapproved external provider or connector calls.

## Core Value Invariants

Screen consolidation may change navigation and presentation, but it must preserve the product loop: **Capture -> Interpret -> Review -> Move -> Evidence**.

1. **Voice remains structured capture:** raw transcripts may be saved directly to Inbox, but inferred tasks, projects, dates, destinations, or operations must be shown as an editable proposal before they are applied. Voice must not become dictation-only capture.
2. **Approval remains bound to reviewed content:** the UI may present `Approve & Run` as one action, but approval and execution remain separate internal states. Editing approved content invalidates its approval, and execution must use the canonical reviewed-action executor.
3. **External writes always cross the Review boundary:** AI schedule placement may create a proposal in Schedule, but Calendar, Reminder, provider, connector, file, or other external writes require explicit review. There is no direct-write path from Capture, Today, Schedule, or Voice.
4. **Accepted work remains visible:** saved or executed work must land in Inbox, Today, a Project, Schedule, Completed, or Pending Actions. No captured or generated work may disappear into an assistant transcript or provider log.
5. **Execution leaves evidence:** every attempted external or high-risk action produces a visible receipt or recoverable failure state linked to the reviewed proposal.

These invariants are release gates for removing, merging, or simplifying screens. A smaller surface is acceptable only when the complete product loop remains reachable and inspectable.

## Delivery Scope

The product direction describes both the Public Alpha and later secretary capabilities. Only the MVP 0 rows below block Public Alpha validation. Post-MVP work starts only after the design-partner gate records `Go`.

| Capability | Delivery phase | Tracking issues |
| --- | --- | --- |
| Screen and feature inventory for the 17 product groups | MVP 0 | #611, #612 |
| Canonical Review / Pending Actions boundary | MVP 0 | #613 |
| Deterministic interpretation and one-step clarification | MVP 0 | #408 |
| Structured Voice Quick Capture | MVP 0 | #614 |
| Schedule proposals and reviewed Apple Calendar application | MVP 0 | #615 |
| Today, Inbox, Projects, Smart List, Completed, Settings, Menu Bar, and Onboarding consolidation | MVP 0 | #616 |
| End-to-end product-loop, accessibility, and release evidence | MVP 0 | #617, #244, #246 |
| Public Alpha product validation | MVP 0 exit gate | #407 |
| Generated document draft studio and richer project context | Post-MVP | #8, #17, #27, #340 |
| Document read-aloud and meeting-material voice workflows | Post-MVP | #18 |
| Recurring reminder workflows and external connector drafts | Post-MVP | #29, #33 |
| Google Calendar live sync | Post-MVP | #434 |

For MVP 0, a document request may be captured as a reviewable Task with related-material links. Generating the document itself is not required. Settings must show readiness for supported AI, Voice, Apple Calendar, Notification, and Privacy capabilities; Reminder, MCP, external connectors, and Google Calendar must remain absent, clearly unsupported, or Advanced/Post-MVP rather than appearing ready.

## Issue and PR Order

Each implementation issue is delivered by one focused PR. #611 is a tracker and does not receive its own implementation PR.

1. **PR 1 — #612:** inventory current routes and owners, publish the `reuse / move / change / add / remove` table and Mermaid, and finalize this delivery boundary. No product code changes.
2. **PR 2 — #613:** consolidate Review / Pending Actions and preserve approval binding, edit invalidation, canonical execution, and receipts.
3. **PR 3 — #408:** connect deterministic Triage to the proposal and Review handoff established by PR 2.
4. **PR 4 — #614:** consolidate Voice Quick Capture on top of the reviewed proposal path.
5. **PR 5 — #615:** connect Schedule proposals to reviewed Apple Calendar application.
6. **PR 6 — #616:** consolidate the remaining product surfaces and delete routes classified `remove` by PR 1.
7. **PR 7 — #617:** add only the missing end-to-end checks and current-source runtime evidence for the complete product loop.
8. **PR 8A — #244 / PR 8B — #246:** update manual VoiceOver evidence and signed/notarized release evidence for the same release candidate. These may proceed in parallel after PR 7.
9. **Validation — #407:** run the four-week design-partner program. Product changes found during validation return to MVP 0 as separate issues; the final result is recorded in one evidence/ADR PR.

The local closed-schema contract and operator runbook for Validation are kept
in [`public-alpha-validation.md`](public-alpha-validation.md). Preparing that
contract is not the same as completing the external four-week program; #407
stays open until its participant and evidence gates are met.

A PR does not absorb adjacent later work. If a newly discovered gap directly blocks the current issue's acceptance criteria, create one linked blocker and insert it immediately before the dependent PR. Otherwise keep it in Post-MVP.

## UI Sample Translation

| Source | Secretary role | Product direction |
| --- | --- | --- |
| `ui-samples/01.png` | Today desk | Add a Today command bar for quick instructions, suggestion chips, prioritized tasks, time blocks, and contextual Inspector access that explains the next ordinary action. A Right rail is optional when space allows. |
| `ui-samples/02.png` | Inbox intake | Treat voice, manual notes, AI proposals, and copied text as one Inbox intake stream with transcript, interpretation, classification, and reviewable conversion actions. |
| `ui-samples/03.png` | Project watchlist | Present projects as a lightweight watchlist with progress, risk, next action, and recent movement instead of a passive list. |
| `ui-samples/04.png` | Document draft studio | Post-MVP: let a selected project expose tasks, milestones, source documents, draft artifacts, timeline context, and approval-only AI actions such as outline, memo, release notes, email draft, PR plan, and follow-up task creation. |
| `ui-samples/05.png` | Schedule desk | In MVP 0, convert unscheduled tasks into schedule proposals and require review before Apple Calendar writes. Reminder drafts are Post-MVP. |
| `ui-samples/06.png` | Done recap | Use completed work to create a daily or weekly recap, productivity hints, and follow-up suggestions without treating generated insight as proof of manual review. |
| `ui-samples/07.png` | Secretary readiness | Show supported provider, STT, TTS, Apple Calendar, notification, privacy, and data-location readiness. Reminder, MCP, connector, and Google Calendar readiness appears only after its Post-MVP delivery gate. |

## Core Flows

1. Task and document-request intake: in MVP 0, the user can throw ordinary work into Inbox or Today without choosing the final structure first.
2. Chore delegation: in MVP 0, the assistant can propose subtasks, schedule blocks, status updates, and follow-ups, but writes only after review. Reminder writes are Post-MVP.
3. Document draft studio (Post-MVP): selected tasks and documents can create draft artifacts such as article outlines, meeting prep, release notes, PR plans, emails, and summaries.
4. Secretary queue: captured, drafted, waiting-review, scheduled, and done items are visible as a task-first queue rather than hidden in provider logs.
5. VoiceOver task listing: in MVP 0, the main queue, task detail, and approval actions must be reachable from keyboard and VoiceOver-first navigation. Document-draft coverage is added with the Post-MVP studio.

## Prioritized UX Lanes

- AS-001 Task and document intake: merge manual capture, voice capture, document request capture, and AI-proposed chores into an Inbox intake model.
- AS-002 Document draft studio (Post-MVP): make project detail the place to produce review-only drafts from selected documents and task context.
- AS-003 Secretary queue: add explicit secretary statuses so the user can scan captured, drafted, waiting-review, scheduled, and done work.
- AS-004 Contextual assistant surface: keep next action, reason, risk, evidence, and approval action reachable through Inspector or Review. A permanent Right rail is not required on every screen.
- AS-005 Schedule and external-write review: generate schedule proposals without silently writing to Apple Calendar. Reminder drafts are Post-MVP and use the same Review boundary when delivered.
- AS-006 Done recap and follow-up suggestions: turn completed tasks into recap and follow-up proposals with clear source links.
- AS-007 Settings readiness for secretary work: surface readiness for supported provider, speech, Apple Calendar, notification, privacy, and data-location capabilities. Post-MVP readiness appears only after the corresponding capability ships.

## Non-goals

- Replacing the task list with open-ended chat.
- Sending email, Slack, GitHub, Calendar, Reminder, or MCP writes without review.
- Claiming team workspace collaboration before personal local workflows are product-complete.
- Hiding task state, document drafts, or provider calls behind an assistant transcript.
- Persisting API keys, OAuth tokens, or raw provider responses outside their approved secure storage boundary.

## Quality Bar

- Time to capture: a normal task, chore, or document request must be captured from Today or Inbox in one short path.
- Time to first reviewed result: in MVP 0, a document request must produce an inspectable Task with source links or a skip reason. Post-MVP document generation must produce an inspectable draft without unreviewed external writes.
- Queue clarity: no captured or generated work disappears from task listing, Secretary queue, or Done recap.
- Permission clarity: supported Keychain, provider, Calendar, Notification, STT, and TTS readiness must be explainable before the user hits a blocking prompt. Post-MVP capabilities must not appear ready before their delivery gate is complete.
- Evidence: source tests, UI screenshots, runtime CRUD smoke, pseudo VoiceOver, and manual VoiceOver evidence must cover the secretary path before release claims change.
