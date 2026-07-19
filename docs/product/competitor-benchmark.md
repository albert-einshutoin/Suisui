# Competitor Benchmark and Feature Fit

Verified: 2026-06-19

Scope: Notion, Todoist, Linear, and Motion were reviewed from official product/help/docs pages. This is not a full hands-on trial record. Treat it as product benchmark evidence and a release-candidate hands-on worksheet for Suisui feature fit; visual screenshot evidence remains tracked in Phase 11.

Official references rechecked on 2026-06-19:
- Notion board/status model: https://www.notion.com/help/boards
- Notion Projects: https://www.notion.com/product/projects
- Todoist Quick Add: https://www.todoist.com/help/articles/use-task-quick-add-in-todoist-va4Lhpzz
- Todoist board layout: https://www.todoist.com/help/articles/use-the-board-layout-in-todoist-AiAVsyEI
- Linear quick navigation and command-menu model: https://linear.app/docs/conceptual-model
- Linear Projects and Triage: https://linear.app/docs/projects / https://linear.app/docs/triage
- Motion AI Project Manager and AI Task Manager: https://www.usemotion.com/features/ai-project-manager / https://www.usemotion.com/features/ai-task-manager

## Decision Summary

| Competitor signal | User pain it solves | Suisui fit | Decision |
| --- | --- | --- | --- |
| Notion flexible project databases, filtered kanban, forms, and automations | Teams need one workspace for docs, tasks, and requests, but structure can become heavy for individual PM use. | Suisui should keep Project/Task/Artifact structured by default and use Markdown artifacts as the flexible layer. | Adopt structured overview and artifact links; do not adopt arbitrary database builders in MVP. |
| Notion AI status summaries and meeting-note-to-action flows | Users want updates and action extraction without manually filtering databases. | Suisui already has approval-first action plans and local suggestions. | Adopt review-before-apply AI summaries later; keep local suggestions deterministic for public alpha. |
| Todoist Quick Add, natural language dates, board sections, Ramble voice capture | Individual users need capture speed more than configuration depth. | Suisui's strongest capture surface should be Inbox plus voice/text review. | Adopt fast Inbox capture and voice-to-structured tasks; avoid team-heavy fields in capture. |
| Todoist board/list/calendar layouts | Users change mental mode between capture, scan, and schedule. | Suisui has board/list/overview and Today time blocks. | Adopt fast mode switching; defer full calendar layout until scheduling is real. |
| Linear keyboard-first issues, command menu, triage, project progress | Product teams need low-friction execution and clean intake review. | Suisui can borrow speed and inspector density without becoming team issue tracking. | Adopt keyboard shortcuts, right inspector, triage-like Inbox; do not adopt multi-team workflow/cycles in MVP. |
| Linear project updates and initiatives | Leaders need progress health and objective-level visibility. | Suisui is personal PM, so status health should be project-local. | Adopt project progress and health later; reject org-wide initiatives for MVP. |
| Motion AI project/task scheduling and delay prediction | Users do not want to constantly reprioritize, chase status, or guess if deadlines will slip. | Suisui's differentiator is local-first, BYOK, approval-first planning. | Adopt explainable risk/suggestion panels; defer autonomous rescheduling until Calendar integration is trustworthy. |

## Official Source Snapshot

| Product | Current official signal | Suisui interpretation |
| --- | --- | --- |
| Notion | Board views can group database pages by status, assignee, priority, or other properties, with filters, sorts, custom properties, drag/reorder, and card sizing. | Suisui should keep fixed Project/Task semantics for speed, while artifacts provide flexible context without turning the MVP into a database builder. |
| Todoist | Quick Add is available across macOS/iOS/Android/Windows, supports `Q`, natural-language date/deadline, project/section, priority, reminders, labels, and a desktop global shortcut. Board layout exposes section columns and drag movement. | Suisui's menu bar Quick Add and Inbox capture match the low-friction direction; natural-language date parsing remains valuable but must be deterministic before adoption. |
| Linear | Projects are outcome/date-oriented units with issues, optional documents, progress graph, notification options, detail sidebar, and `Shift P` / `C` shortcuts. Triage is a special inbox for review before team workflow. | Suisui should keep Project Overview, right inspector, keyboard CRUD, and Inbox triage. Multi-team, cycles, initiatives, and bulk issue operations remain out of scope. |
| Motion | AI Project Manager emphasizes automatic project movement, prioritization, delay prediction, capacity balancing, and status visibility. AI Task Manager plans days around deadlines, priorities, dependencies, and at-risk tasks. | Suisui should adopt explainable local risk/suggestion panels first. Autonomous rescheduling is too trust-sensitive without reliable calendar data and user-visible reasoning. |

## Release Candidate Hands-On Worksheet

This section is the exact manual pass required before checking the Phase 11 hands-on item. The goal is not to copy competitors. The goal is to decide whether Suisui's public alpha loop is competitive enough for a personal, local-first PM app.

| Competitor | 30-minute hands-on path | Measure | Suisui decision gate |
| --- | --- | --- | --- |
| Notion | Create a project database, switch to board, add three tasks, group by status, attach one doc/link, and try an AI/project summary if available. | Setup steps before first useful board; number of choices before first task; clarity of project context. | Suisui passes if a new user can create project/task/artifact context faster without schema setup. |
| Todoist | Use global/desktop Quick Add, create tasks with date/priority/project/section, switch board/list, drag a task, and inspect Today/Upcoming. | Keystrokes/clicks to capture; confidence that task landed in the right place; speed of status movement. | Suisui passes if Inbox/Menu Bar capture and Today/Board answer "where did it go?" within one screen. |
| Linear | Create project, create issue, move issue status, open details/sidebar, use command menu/keyboard shortcut, process one triage-like item. | Repeated-operation speed; inspector density; keyboard affordance discoverability. | Suisui passes if task create/edit/move/delete flows work by mouse and keyboard without leaving the board context. |
| Motion | Create tasks with due dates/priorities, observe scheduling/risk surfaces, adjust a deadline, and inspect how the tool explains changes. | Whether recommendations are understandable; how much calendar data is required; risk of over-automation. | Suisui passes if suggestions explain why before applying, and if local-first review prevents surprise schedule changes. |

Manual evidence to attach after the pass:
- Date, reviewer, macOS/browser/app versions, account tier used, and whether a paid trial was required.
- One screenshot or note per competitor showing the critical screen used for the path.
- A short "ship / defer / reject" delta section covering only changes that would alter Suisui's current backlog.
- Explicit confirmation that no external SaaS sync or team workflow was added to Suisui's public alpha scope because of the benchmark.

## Competitor Notes

### Notion

Official sources:
- [Notion Projects](https://www.notion.com/product/projects)
- [Notion project management automation and Custom Agents](https://www.notion.com/blog/project-management-automation)

Observed strengths:
- Project databases can be filtered/sorted into multiple views and customized heavily.
- Forms and automations turn inbound requests into structured work.
- AI can summarize project databases, extract action items from notes, and answer filtered project questions.

Suisui implication:
- Adopt: Project Overview with tasks, artifacts, timeline, and suggestions is the right direction.
- Adopt later: AI weekly status summary from local Project/Task/Artifact data.
- Avoid for MVP: user-defined database schemas, arbitrary relation builders, and workspace-wide customization. They raise setup cost and dilute Suisui's "say it, review it, execute it" loop.

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

Suisui implication:
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

Suisui implication:
- Adopt: right inspector for selected task/project, keyboard shortcuts, and Inbox triage actions.
- Adopt later: project health updates generated from local tasks and artifacts.
- Avoid for MVP: teams, cycles, workspace-wide initiatives, and issue relations beyond blocked/open/done. Suisui is not trying to replace team issue trackers.

### Motion

Official sources:
- [Motion AI Project Manager](https://www.usemotion.com/features/ai-project-manager)
- [Motion AI Task Manager](https://www.usemotion.com/features/ai-task-manager)

Observed strengths:
- AI Project Manager promises automated project movement, delay prediction, capacity balancing, and reduced status chasing.
- AI Task Manager auto-plans the day, re-optimizes schedules, surfaces hourly priority, and warns when due dates are at risk.

Suisui implication:
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
| Custom database schema builder | Reject for MVP | Increases setup cost and makes Suisui less opinionated. | Revisit only if users request non-task entities repeatedly. |
| Team cycles/initiatives/capacity planning | Reject for MVP | Suisui is personal PM, not a team issue tracker. | Revisit only for paid team edition. |

## Phase 11 Fit Closure

The Phase 11 productization gate is satisfied for the subset Suisui actually needs:

| Competitor trait | Suisui implementation | Evidence |
| --- | --- | --- |
| Notion-like flexible project context | Project Overview shows tasks, artifacts, timeline, and local suggestions. Artifact links provide flexible project evidence without arbitrary database schemas. | `AppExperienceSourceTests.testProjectDetailOrganizesTasksArtifactsTimelineAndSuggestions`, `ProjectBoardStoreTests.testCreateProjectArtifactPersistsExpectedArtifactInSnapshot`, `ProjectBoardStoreTests.testDeleteProjectArtifactRemovesLinkFromSnapshot` |
| Linear-like execution speed | Board cards support one-click status move controls, drag/drop status changes, keyboard shortcuts, and a stable right inspector for repeated edits. | `AppExperienceSourceTests.testKanbanTaskCardsExposeMouseDrivenStatusMoveControls`, `AppExperienceSourceTests.testKanbanCardsUseTaskComponentDragPreview`, `AppExperienceSourceTests.testInspectorsExposeKeyboardOnlyCrudShortcuts` |
| Todoist-like immediate input | Menu bar Quick Add and Inbox capture create local SQLite tasks without opening the full Project Board; Inline Task Composer supports fast board-column task creation. | `AppExperienceSourceTests.testMenuBarPanelProvidesFastInboxCaptureWithRuntimeBoardViewModel`, `ProjectBoardStoreTests.testProjectBoardViewModelQuickCapturePersistsToSQLiteInbox`, `AppExperienceSourceTests.testInlineTaskComposerExposesKeyboardAndVoiceOverCreateAnchors` |

Not adopted for public alpha: Notion-style arbitrary database builders, Linear-style team cycles/initiatives, and Motion-style autonomous rescheduling. Those would make the app broader but less trustworthy before release evidence, calendar semantics, and user control are stronger.

## VC-Grade Feature Fit

Problem: Suisui users need the capture speed of Todoist, the execution clarity of Linear, and the AI planning help promised by Motion without giving up local-first trust.

User pull: The strongest repeated-use loop is Inbox or Voice Capture -> review -> Project/Today -> inspector action. Features that do not shorten or clarify that loop should be deferred.

Retention hook: Today and Project Overview should become daily and weekly surfaces. Retention depends more on seeing the next concrete action than on adding more provider settings.

Monetization: Free should stay useful for local Project/Task CRUD and BYOK planning. Pro value should be cloud sync, advanced MCP execution, and higher-confidence automation evidence, not basic task management.

Risk: Competing head-on with Notion customization, Linear team workflows, or Motion autonomous scheduling would expand scope faster than trust. Suisui should win on local-first execution, explicit review, and transparent suggestions.
