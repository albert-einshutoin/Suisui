# Competitor Benchmark and Feature Fit

Verified: 2026-06-19

Scope: Notion, Todoist, Linear, and Motion were reviewed from official product/help/docs pages. This is not a full hands-on trial record. Treat it as product benchmark evidence for SoloPM feature fit; visual screenshot evidence remains tracked in Phase 11.

Official references rechecked on 2026-06-19:
- Notion board/status model: https://www.notion.com/help/boards
- Todoist Quick Add: https://www.todoist.com/help/articles/use-task-quick-add-in-todoist-va4Lhpzz
- Linear quick navigation and command-menu model: https://linear.app/docs/conceptual-model
- Motion automatic scheduling positioning: https://www.usemotion.com/help

## Decision Summary

| Competitor signal | User pain it solves | SoloPM fit | Decision |
| --- | --- | --- | --- |
| Notion flexible project databases, filtered kanban, forms, and automations | Teams need one workspace for docs, tasks, and requests, but structure can become heavy for individual PM use. | SoloPM should keep Project/Task/Artifact structured by default and use Markdown artifacts as the flexible layer. | Adopt structured overview and artifact links; do not adopt arbitrary database builders in MVP. |
| Notion AI status summaries and meeting-note-to-action flows | Users want updates and action extraction without manually filtering databases. | SoloPM already has approval-first action plans and local suggestions. | Adopt review-before-apply AI summaries later; keep local suggestions deterministic for public alpha. |
| Todoist Quick Add, natural language dates, board sections, Ramble voice capture | Individual users need capture speed more than configuration depth. | SoloPM's strongest capture surface should be Inbox plus voice/text review. | Adopt fast Inbox capture and voice-to-structured tasks; avoid team-heavy fields in capture. |
| Todoist board/list/calendar layouts | Users change mental mode between capture, scan, and schedule. | SoloPM has board/list/overview and Today time blocks. | Adopt fast mode switching; defer full calendar layout until scheduling is real. |
| Linear keyboard-first issues, command menu, triage, project progress | Product teams need low-friction execution and clean intake review. | SoloPM can borrow speed and inspector density without becoming team issue tracking. | Adopt keyboard shortcuts, right inspector, triage-like Inbox; do not adopt multi-team workflow/cycles in MVP. |
| Linear project updates and initiatives | Leaders need progress health and objective-level visibility. | SoloPM is personal PM, so status health should be project-local. | Adopt project progress and health later; reject org-wide initiatives for MVP. |
| Motion AI project/task scheduling and delay prediction | Users do not want to constantly reprioritize, chase status, or guess if deadlines will slip. | SoloPM's differentiator is local-first, BYOK, approval-first planning. | Adopt explainable risk/suggestion panels; defer autonomous rescheduling until Calendar integration is trustworthy. |

## Competitor Notes

### Notion

Official sources:
- [Notion Projects](https://www.notion.com/product/projects)
- [Notion project management automation and Custom Agents](https://www.notion.com/blog/project-management-automation)

Observed strengths:
- Project databases can be filtered/sorted into multiple views and customized heavily.
- Forms and automations turn inbound requests into structured work.
- AI can summarize project databases, extract action items from notes, and answer filtered project questions.

SoloPM implication:
- Adopt: Project Overview with tasks, artifacts, timeline, and suggestions is the right direction.
- Adopt later: AI weekly status summary from local Project/Task/Artifact data.
- Avoid for MVP: user-defined database schemas, arbitrary relation builders, and workspace-wide customization. They raise setup cost and dilute SoloPM's "say it, review it, execute it" loop.

### Todoist

Official sources:
- [Todoist Quick Add](https://www.todoist.com/help/articles/use-task-quick-add-in-todoist-va4Lhpzz)
- [Todoist board layout](https://www.todoist.com/help/articles/use-the-board-layout-in-todoist-AiAVsyEI)
- [Todoist Ramble voice capture](https://www.todoist.com/help/articles/dictate-to-add-tasks-with-ramble-P1Raq7vVF)
- [Todoist Calendar integration](https://www.todoist.com/help/articles/use-the-calendar-integration-rCqwLCt3G)

Observed strengths:
- Quick Add is optimized for task capture with natural-language dates, labels, priority, and reminders.
- Board sections are simple phase columns with drag movement.
- Ramble captures tasks from speech and supports correction phrases before final add.
- Calendar integration makes Today/Upcoming scheduling visible.

SoloPM implication:
- Adopted: Menu bar Quick Add and Inbox header capture make local Inbox task creation one of the fastest paths in the app.
- Adopt: voice/text capture must remain one of the fastest paths in the app.
- Adopt: mouse drag plus card move buttons are the right accessibility pair.
- Adopt later: natural-language date parsing and calendar reflection only when local scheduling semantics are reliable.
- Avoid for MVP: broad label/filter taxonomy before the task creation loop is sharp.

### Linear

Official sources:
- [Linear Projects](https://linear.app/docs/projects)
- [Linear Triage](https://linear.app/docs/triage)
- [Linear concepts and command menu](https://linear.app/docs/conceptual-model)
- [Linear board layout](https://linear.app/docs/board-layout)
- [Linear initiative and project updates](https://linear.app/docs/initiative-and-project-updates)

Observed strengths:
- Projects have clear outcomes, planned completion, issues, documents, progress graph, and notifications.
- Triage is a first-class intake inbox with accept/duplicate/decline/snooze actions and keyboard shortcuts.
- Command menu and keyboard-first selection keep repeated issue operations fast.
- Project updates communicate health, progress, challenges, and next steps.

SoloPM implication:
- Adopt: right inspector for selected task/project, keyboard shortcuts, and Inbox triage actions.
- Adopt later: project health updates generated from local tasks and artifacts.
- Avoid for MVP: teams, cycles, workspace-wide initiatives, and issue relations beyond blocked/open/done. SoloPM is not trying to replace team issue trackers.

### Motion

Official sources:
- [Motion AI Project Manager](https://www.usemotion.com/features/ai-project-manager)
- [Motion AI Task Manager](https://www.usemotion.com/features/ai-task-manager)

Observed strengths:
- AI Project Manager promises automated project movement, delay prediction, capacity balancing, and reduced status chasing.
- AI Task Manager auto-plans the day, re-optimizes schedules, surfaces hourly priority, and warns when due dates are at risk.

SoloPM implication:
- Adopt: explain why a task/project needs attention, especially blocked work, high priority work, and due work.
- Adopt later: risk forecast and calendar scheduling after local task duration/dependency data exists.
- Avoid for MVP: autonomous rescheduling and capacity balancing. Without transparent evidence and a real calendar source, it would feel like mock intelligence.

## Adopt / Defer / Reject Backlog

| Item | Decision | Product reason | Evidence needed before release claim |
| --- | --- | --- | --- |
| Project overview with tasks/artifacts/timeline/suggestions | Adopted | Reduces "what should I inspect next?" after opening a project. | Source tests and screenshot evidence. |
| Project expected artifact links | Adopted | Keeps Notion-like flexible project evidence without adding arbitrary database schemas; Review Execute-created files also return to the project artifact list, while link removal stays safe by not deleting local files. | Local SQLite mutation tests, filesystem tool mutation tests, and Project Overview source tests. |
| Right inspector for task/project edit/delete/suggestion | Adopted | Keeps repeated CRUD in one stable place. | Source tests and VoiceOver focus pass. |
| Menu bar Quick Add to Inbox | Adopted | Captures a task without opening the Project Board, matching Todoist-like speed while staying local-first. | Source tests; manual smoke capture remains release evidence. |
| Inbox triage actions | Adopted | Converts capture into task/project/schedule/review-later quickly. | Click-path audit and mutation tests. |
| Natural-language date parsing | Defer | Valuable for Todoist-like capture, but date semantics must be deterministic. | Parser unit tests for locale/time zone. |
| Calendar layout / auto-scheduling | Defer | Motion-like value requires real calendar sync and user trust. | Calendar write/read smoke and rollback path. |
| AI weekly project status | Defer | Strong Notion/Linear fit, but must be review-before-apply and local-data grounded. | LLM schema tests and audit log. |
| Custom database schema builder | Reject for MVP | Increases setup cost and makes SoloPM less opinionated. | Revisit only if users request non-task entities repeatedly. |
| Team cycles/initiatives/capacity planning | Reject for MVP | SoloPM is personal PM, not a team issue tracker. | Revisit only for paid team edition. |

## Phase 11 Fit Closure

The Phase 11 productization gate is satisfied for the subset SoloPM actually needs:

| Competitor trait | SoloPM implementation | Evidence |
| --- | --- | --- |
| Notion-like flexible project context | Project Overview shows tasks, artifacts, timeline, and local suggestions. Artifact links provide flexible project evidence without arbitrary database schemas. | `AppExperienceSourceTests.testProjectDetailOrganizesTasksArtifactsTimelineAndSuggestions`, `ProjectBoardStoreTests.testCreateProjectArtifactPersistsExpectedArtifactInSnapshot`, `ProjectBoardStoreTests.testDeleteProjectArtifactRemovesLinkFromSnapshot` |
| Linear-like execution speed | Board cards support one-click status move controls, drag/drop status changes, keyboard shortcuts, and a stable right inspector for repeated edits. | `AppExperienceSourceTests.testKanbanTaskCardsExposeMouseDrivenStatusMoveControls`, `AppExperienceSourceTests.testKanbanCardsUseTaskComponentDragPreview`, `AppExperienceSourceTests.testInspectorsExposeKeyboardOnlyCrudShortcuts` |
| Todoist-like immediate input | Menu bar Quick Add and Inbox capture create local SQLite tasks without opening the full Project Board; Inline Task Composer supports fast board-column task creation. | `AppExperienceSourceTests.testMenuBarPanelProvidesFastInboxCaptureWithRuntimeBoardViewModel`, `ProjectBoardStoreTests.testProjectBoardViewModelQuickCapturePersistsToSQLiteInbox`, `AppExperienceSourceTests.testInlineTaskComposerExposesKeyboardAndVoiceOverCreateAnchors` |

Not adopted for public alpha: Notion-style arbitrary database builders, Linear-style team cycles/initiatives, and Motion-style autonomous rescheduling. Those would make the app broader but less trustworthy before release evidence, calendar semantics, and user control are stronger.

## VC-Grade Feature Fit

Problem: SoloPM users need the capture speed of Todoist, the execution clarity of Linear, and the AI planning help promised by Motion without giving up local-first trust.

User pull: The strongest repeated-use loop is Inbox or Voice Capture -> review -> Project/Today -> inspector action. Features that do not shorten or clarify that loop should be deferred.

Retention hook: Today and Project Overview should become daily and weekly surfaces. Retention depends more on seeing the next concrete action than on adding more provider settings.

Monetization: Free should stay useful for local Project/Task CRUD and BYOK planning. Pro value should be cloud sync, advanced MCP execution, and higher-confidence automation evidence, not basic task management.

Risk: Competing head-on with Notion customization, Linear team workflows, or Motion autonomous scheduling would expand scope faster than trust. SoloPM should win on local-first execution, explicit review, and transparent suggestions.
