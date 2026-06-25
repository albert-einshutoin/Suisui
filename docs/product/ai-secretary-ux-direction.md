# AI Secretary UX Direction

Date: 2026-06-25

SoloPM should grow from a personal AI PM into an AI secretary for tasks, documents, and chores. The product role is not a generic chat surface. It is a local-first work desk that receives ordinary work, turns it into reviewable tasks, drafts, schedules, reminders, and follow-ups, then asks the user before external writes or destructive actions.

## Product Stance

- Purpose: turn incoming personal work into reviewed task, document, schedule, and reminder actions.
- Primary audience: a solo operator who repeats the same capture, triage, draft, schedule, and follow-up loops every day.
- Tone: quiet, dense, Mac-native, and practical enough for recurring desk work.
- Memorable detail: a Right assistant rail that always explains the next mundane action, the evidence behind it, and the approval boundary.
- Constraints: local-first storage, Keychain-backed secrets, review-before-execution, VoiceOver task listing, and no unapproved external provider or connector calls.

## UI Sample Translation

| Source | Secretary role | Product direction |
| --- | --- | --- |
| `ui-samples/01.png` | Today desk | Add a Today command bar for quick instructions, suggestion chips, prioritized tasks, time blocks, and a Right assistant rail that explains the next ordinary action. |
| `ui-samples/02.png` | Inbox intake | Treat voice, manual notes, AI proposals, and copied text as one Inbox intake stream with transcript, interpretation, classification, and reviewable conversion actions. |
| `ui-samples/03.png` | Project watchlist | Present projects as a lightweight watchlist with progress, risk, next action, and recent movement instead of a passive list. |
| `ui-samples/04.png` | Document draft studio | Let a selected project expose tasks, milestones, source documents, draft artifacts, timeline context, and approval-only AI actions such as outline, memo, release notes, email draft, PR plan, and follow-up task creation. |
| `ui-samples/05.png` | Schedule desk | Convert unscheduled tasks into schedule and reminder drafts, then require review before Calendar or Reminder writes. |
| `ui-samples/06.png` | Done recap | Use completed work to create a daily or weekly recap, productivity hints, and follow-up suggestions without treating generated insight as proof of manual review. |
| `ui-samples/07.png` | Secretary readiness | Show whether provider, STT, TTS, Calendar, Reminder, MCP, notification, privacy, and data-location capabilities are ready for secretary work. |

## Core Flows

1. Task and document intake: the user can throw ordinary work into Inbox or Today without choosing the final structure first.
2. Chore delegation: the assistant can propose subtasks, reminders, schedule blocks, status updates, and follow-ups, but writes only after review.
3. Document draft studio: selected tasks and documents can create draft artifacts such as article outlines, meeting prep, release notes, PR plans, emails, and summaries.
4. Secretary queue: captured, drafted, waiting-review, scheduled, and done items are visible as a task-first queue rather than hidden in provider logs.
5. VoiceOver task listing: the main queue, task detail, document drafts, and approval actions must be reachable from keyboard and VoiceOver-first navigation.

## Prioritized UX Lanes

- AS-001 Task and document intake: merge manual capture, voice capture, document request capture, and AI-proposed chores into an Inbox intake model.
- AS-002 Document draft studio: make project detail the place to produce review-only drafts from selected documents and task context.
- AS-003 Secretary queue: add explicit secretary statuses so the user can scan captured, drafted, waiting-review, scheduled, and done work.
- AS-004 Right assistant rail: keep next action, reason, risk, evidence, and approval action visible for Today, Inbox, Project, Document, Schedule, and Done contexts.
- AS-005 Schedule and reminder draft review: generate schedule and reminder proposals without silently writing to Calendar or Reminders.
- AS-006 Done recap and follow-up suggestions: turn completed tasks into recap and follow-up proposals with clear source links.
- AS-007 Settings readiness for secretary work: surface provider, speech, calendar, reminder, MCP, notification, privacy, and data-location readiness in one place.

## Non-goals

- Replacing the task list with open-ended chat.
- Sending email, Slack, GitHub, Calendar, Reminder, or MCP writes without review.
- Claiming team workspace collaboration before personal local workflows are product-complete.
- Hiding task state, document drafts, or provider calls behind an assistant transcript.
- Persisting API keys, OAuth tokens, or raw provider responses outside their approved secure storage boundary.

## Quality Bar

- Time to capture: a normal task, chore, or document request must be captured from Today or Inbox in one short path.
- Time to first reviewed draft: a document request must produce an inspectable draft or a skip reason without unreviewed external writes.
- Queue clarity: no captured or generated work disappears from task listing, Secretary queue, or Done recap.
- Permission clarity: Keychain, OAuth, provider, Calendar, Reminder, STT, TTS, and MCP readiness must be explainable before the user hits a blocking prompt.
- Evidence: source tests, UI screenshots, runtime CRUD smoke, pseudo VoiceOver, and manual VoiceOver evidence must cover the secretary path before release claims change.
