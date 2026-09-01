# Information Architecture

How Suisui's four surfaces divide responsibility, the modal rules they
follow, and the primary flows between them. Every claim below is grounded in
the current code (files cited inline); the final section lists honest gaps.

## Window responsibilities

### Project Board window (`project-board`)

The main window (`Sources/SuisuiApp/Views/ProjectBoardView.swift`,
`ProjectWorkflow*.swift`).

The source list owns exactly four stable product areas
(`ProjectBoardSidebarView.swift`): **Today → Inbox → Projects → Review**.
Feature-level navigation lives one level in, inside two hubs, so adding a
workflow cannot grow the top level again:

- **Projects hub** (`ProjectBoardProjectsHubView.swift`): Portfolio, Smart
  Lists, Active / Completed / Archived projects.
- **Review hub** (`ProjectBoardReviewHubView.swift`): Plan → Schedule; Work →
  Completed; Automation → Automation Activity, Assistant Queue.

Both hubs render a second list beside the detail above
`ProjectBoardHubPresentationPolicy.wideMinimumWidth` (1100 pt) and collapse to
a "Choose …" menu below it.

The default destination is **Today**
(`ProjectBoardSelectionPersistence.swift`: persisted
`defaultRawValue = "today"`; unresolved selections fall back to `.today`).

`⌘1`–`⌘4` select the four primary destinations in rendered order
(`BoardPrimaryDestination.orderedForKeyboardSelection`, wired in
`ProjectBoardView.swift`). Inbox classification uses `⌃⌘1`–`⌃⌘4`.

Owns:
- All task/project reading and mutation surfaces: workflow views per
  destination, kanban columns per project (`ProjectBoardDetail`), task and
  project editing via the inspector, board operation undo (⌘Z,
  `BoardOperationUndo.swift`).
- The command palette (⌘K, `CommandPaletteView.swift`), including quick
  Inbox task creation and content search.
- Assistant Queue review **and execution**: the Run button in
  `ProjectWorkflowAssistantQueueView.swift` calls
  `ProjectBoardViewModel.runAssistantQueueItem(id:)`, which drives
  `AssistantQueueExecutionCoordinator` and produces execution receipts.

Does not do: voice capture, plan drafting, or settings — commands arrive
here already interpreted (from the Voice window, palette, or notifications).

### Voice Command window (`voice-capture`)

`Sources/SuisuiApp/Views/VoiceCaptureView.swift`, three stacked zones.

Owns:
- Capture (Zone 1): record/stop, typed transcript editing, Save to Inbox,
  Ask (workspace Q&A), Generate Plan, low-latency agent mode.
- Interpretation (Zone 2): streaming plan preview, routed intent preview,
  clarification Q&A, workspace answer display and TTS replay.
- Review handoff (Zone 3): plan preview, Assistant Queue panel with
  Approve / Defer / Reject and "Open Assistant Queue".

Does not do: execution. `VoiceCaptureViewModel.approveAssistantQueueItem`
only advances queue state and persists it; running an approved item happens
in the Project Board's Assistant Queue view. The capture placeholder states
the boundary: "Inbox captures stay local. Plans wait in Review › Assistant
Queue before execution."

### Settings window

`Sources/SuisuiApp/Views/SettingsView.swift`. Six tabs
(`enum SettingsTab`): **Overview, Appearance, AI, MCP, Sync, Privacy**.

Owns:
- Two-tier disclosure: MCP and Sync are advanced tabs, hidden until the
  `suisui.settings.showAdvanced` toggle (`@AppStorage`, default off) is
  enabled; leaving advanced mode while on MCP/Sync falls back to Overview.
- Provider configuration and readiness (API keys in Keychain), voice model
  management, notification/quiet-hours preferences, backup/restore,
  diagnostics export, developer mode, launch-at-login, data location.
- Wide Settings desks (`CockpitLayoutPolicy.presentsSplitRail`) keep a
  readiness rail on Overview (`settings-overview-detail-rail`) and AI
  (`settings-ai-readiness-rail`). Below the split floor the same rail
  stacks under the form so readiness stays reachable. Appearance stays
  control-layer only (Liquid Glass theme/language pickers) and never shows
  a fake “Save Changes” hero — preference writes apply immediately.

Sample vocabulary mapping (marketing mock → product TabView):

| Sample label | Product tab / surface |
| --- | --- |
| 一般 / General | Overview |
| AIとモデル / AI & Models | AI |
| 音声 / Voice | AI (STT/TTS + voice models) |
| 連携 / Integrations | Sync + MCP (advanced) and Overview readiness tiles |
| セキュリティ / Security | Privacy |
| データ / Data | Privacy (data location / backup) |

Does not do: task or plan content display — Overview shows status labels
only, and diagnostics/backup surfaces deal in counts and files, not rows.
Does not do: fake Pro badges or a Settings-wide Save Changes CTA.

### Menu bar panel

`MenuBarExtra` in `Sources/SuisuiApp/SuisuiApp.swift`; panel content in
`Sources/SuisuiApp/Views/MenuBarPanel.swift`.

Owns:
- Glanceable summary: label badge with overdue count when > 0; panel card
  with Today / Overdue / This Week counts and up to three recent projects
  (`Sources/SuisuiCore/App/MenuBarSummary.swift`).
- Quick capture to Inbox: one text field + Add (⌘↩) via
  `MenuBarQuickCaptureController` (creates a backlog task in the Inbox
  project, with natural-language due-date parsing).
- Window shortcuts: the summary card is one big "Open Today" button
  (forces the board onto Today), plus Project Board and Voice Command
  (⌥Space) buttons and a Settings link.

Does not do: task editing, plan review, or execution — every affordance
either captures one Inbox task or routes to a full window.

## Modal usage rules (as they exist)

- **Sheets** are used for self-contained create/edit flows that block their
  window: the smart list editor
  (`.sheet(isPresented: $isPresentingSmartListEditor)` →
  `SmartListEditorSheet`, `ProjectBoardView.swift` /
  `ProjectBoardSmartListViews.swift`), first-run onboarding
  (`.sheet(isPresented: $isOnboardingPresented)` → `OnboardingWelcomeView`,
  `SuisuiApp.swift`), and the development automation review panel
  (`.sheet(item: $developmentAutomationReviewSheet)` → `ActionReviewPanel`,
  `ProjectBoardView.swift`).
- **Inspector** is the task/project editing surface, not a sheet:
  `.inspector(isPresented:)` in `ProjectBoardView.swift` hosts
  `TaskInspectorView` or `ProjectInspectorView`; project destinations
  auto-open it.
- **Confirmation dialogs** guard destructive or externally visible actions
  only: "Delete MCP Server" and "Disconnect Google Calendar" (both
  `role: .destructive`, `SettingsView.swift`), "Sync due tasks to Google
  Calendar?" (external write, `ProjectBoardView.swift`), and "Restore from
  backup?" (`SettingsView.swift` — additive confirm, message states
  "Existing data is never changed or deleted"). Task/project delete and
  archive use an inline two-step destructive confirmation inside the
  inspector (`InspectorDestructiveConfirmation`, `ProjectBoardView.swift`)
  rather than a dialog.

## Primary flows

### Thought → voice → review → board

```mermaid
sequenceDiagram
    participant U as User
    participant V as Voice Command window
    participant Q as Assistant Queue (store)
    participant B as Project Board window
    U->>V: speak or type a command
    V->>V: transcribe, route intent, generate plan (provider)
    V->>U: Zone 3 review (plan preview + queue panel)
    U->>V: Approve
    V->>Q: state -> approved (no execution)
    U->>V: Open Assistant Queue
    V->>B: open project-board + queue open request
    B->>B: select Assistant Queue destination
    U->>B: Run
    B->>Q: execute via AssistantQueueExecutionCoordinator
    B->>U: execution receipt on the queue row
```

Verified in `VoiceCaptureView.swift` (`postAssistantQueueOpenRequest`),
`ProjectBoardView.swift` (`handleAssistantQueueOpenRequest`), and
`ProjectWorkflowAssistantQueueView.swift` (Run →
`runAssistantQueueItem(id:)`).

### Morning digest → Today → work

```mermaid
flowchart LR
    W[DeadlineWatcherRuntime tick\n8s after launch, every 30 min] --> D[MorningDigestScheduler\ncount-only notification, from 09:00]
    D --> N[User taps notification]
    N --> R[SuisuiNotificationResponder\nposts digest-opened]
    R --> T[Scene coordinator requests Today + ensure board window visible]
    T --> B[Project Board on Today]
```

Verified in `Sources/SuisuiCore/Deadline/MorningDigest.swift` (one
count-only digest per day, hour ≥ 9),
`Sources/SuisuiApp/Composition/DeadlineWatcherRuntime.swift` and
`NotificationInteractionRuntime.swift`, and the app delegate observer in
`SuisuiApp.swift` (`ProjectBoardSceneCoordinator.shared.requestOpen(route: .primary(.today))`).

### Weekly review (notification-only today)

```mermaid
flowchart LR
    W[DeadlineWatcherRuntime tick] --> S[WeeklyReviewSummaryScheduler\nFriday from 16:00, once per ISO week]
    S --> N["Notification: 'X completed this week, Y still open.'"]
    N --> T[Tap lands on board Today\nsame handler as the daily digest]
    T -.->|future| R[Dedicated weekly review surface\ndoes not exist yet]
```

Verified in `Sources/SuisuiCore/Deadline/WeeklyReviewSummary.swift`
(schedule-only, count-only body) and
`NotificationInteractionRuntime.swift`, where `suisui-weekly-review-`
notification taps share the daily digest branch and therefore open Today.
**Future marker:** there is no weekly-review window or destination; the
notification is currently the entire feature.

## MVP0 surface inventory

The target is 17 product groups, not 17 windows. A group may be a nested
workflow or a settings tab. Recovery-only views, the app shell, and Web Surface
definitions are implementation surfaces and are not counted as product screens.
The action column is the decision for the current MVP0 consolidation:
`reuse` keeps the owner and route, `move` puts an existing capability under a
canonical group, `change` keeps the capability but changes its contract, `add`
is a missing capability, and `remove` deletes a duplicate route after its
replacement is reachable.

| Product group | MVP0 functions | Current route / owner | Domain authority | Action |
| --- | --- | --- | --- | --- |
| Project Board common | Search, task add, Voice Capture entry, Inspector, Undo, Review notification (6) | `ProjectBoardView.swift`, `ProjectBoardSidebarView.swift`, `CommandPaletteView.swift` | `ProjectBoard` / Work Management stores | change |
| Today | Today/overdue, Current Focus, Next Tasks, scheduled tasks, Needs Attention, quick add, Catch Up (7) | `ProjectWorkflowTodayView.swift`, `TodayDashboardView.swift`, `TodayFeatureViewModel.swift` | Today snapshots + Work Management | change |
| Inbox | Capture list, quick add, select/note, project assignment, Today, Schedule, Later, delete, Undo, continuous triage (10) | `ProjectWorkflowInboxView.swift`, `InboxTriage.swift` | Work Management / Inbox triage | change |
| Projects Portfolio | Active projects, progress, due date, next action, archived projects, project creation (6) | `ProjectBoardProjectsHubView.swift` | Project store | reuse |
| Project Detail | Board/List, task CRUD/move, project edit, project summary, task Inspector, related material (6) | `ProjectBoardDetailViews.swift`, `ProjectBoardInspectors.swift` | Project/Task stores + evidence references | reuse |
| Smart List | Presets: Blocked, Unscheduled, No Project, Someday; custom lists Advanced (4) | `ProjectBoardSmartListViews.swift`, `BoardRoute.smartList` | Smart List definitions + Task store | move |
| Schedule | Week view, external Calendar events, task time blocks, unscheduled tasks, AI placement proposal, Calendar apply (6) | `ProjectWorkflowScheduleView.swift`, `ScheduleTimelineGeometry.swift` | Schedule cockpit + Calendar adapter | change |
| Completed | Completion history, reopen task, follow-up creation, simple recap (4) | `ProjectWorkflowDoneView.swift` | Work Management / completion history | change |
| Review / Pending Actions | External-write/high-risk diff, edit, Approve & Run, Reject, failure recovery (5) | `ProjectBoardReviewHubView.swift`, `ActionReviewPanel.swift`, `ProjectWorkflowAssistantQueueView.swift` | Assistant Queue execution coordinator + receipts | change |
| Voice Quick Capture | Record, transcription, correction, intent confirmation, one clarification, Inbox/Task save (6) | `VoiceCaptureView.swift`, `VoiceCaptureViewModel.swift`, `VoiceCommandRouter.swift` | Speech providers + Inbox/Assistant Queue | change |
| Settings: Overview | AI/Calendar/Voice/Notification readiness, Advanced toggle (5) | `SettingsView.swift`, `SettingsStatusOverviewView.swift` | `AppSettingsModel` / readiness presentation | change |
| Settings: Appearance | Theme, language (2) | `SettingsAppearanceSection.swift` | `AppSettingsModel` | reuse |
| Settings: AI & Voice | Provider/auth, STT/TTS, basic model, shortcut (5) | `SettingsAIFeatureView.swift`, `VoiceModelManagement.swift` | Keychain-backed settings + speech providers | change |
| Settings: Calendar | Google Calendar auth/disconnect, calendar selection, sync setting (3) | `SettingsView.swift`, `SettingsSyncFeatureView.swift` | Calendar adapter + Keychain; external writes remain Review-gated | change |
| Settings: Privacy | Audio retention, retention policy, quiet hours, backup, data location (5) | `SettingsPrivacyFeatureView.swift`, `SettingsFeatureViews.swift` | Privacy/settings stores | change |
| Menu Bar | Overdue summary, Inbox quick add, Today open, Voice Capture entry (4) | `MenuBarPanel.swift`, `MenuBarSummary.swift`, `MenuBarQuickCaptureController.swift` | Work Management read model + route coordinator | move |
| Onboarding | First capture, first triage, optional AI, optional Calendar, completion (5) | `OnboardingWelcomeView.swift`, `FirstRunOnboarding.swift`, `OnboardingExperience.swift` | Onboarding gate + Work Management | change |

The inventory deliberately keeps existing stores, coordinators, and platform
adapters. It does not create a second Task/Review/Calendar authority. The
resulting ownership graph is:

```mermaid
flowchart LR
  subgraph UI["17 product groups"]
    Board["Project Board common"]
    Today[Today]
    Inbox[Inbox]
    Projects["Projects Portfolio"]
    Detail["Project Detail"]
    Smart["Smart List"]
    Schedule[Schedule]
    Done[Completed]
    Review["Review / Pending Actions"]
    Voice["Voice Quick Capture"]
    Settings["Settings groups"]
    Menu["Menu Bar"]
    Onboarding[Onboarding]
  end

  subgraph Feature["Feature / use case owners"]
    WorkF["Work Management / ProjectBoard"]
    TodayF[TodayFeature]
    InboxF[InboxTriage]
    ReviewF["Assistant Queue / Review"]
    VoiceF[VoiceCapture]
    ScheduleF[ScheduleCockpit]
    SettingsF[SettingsReadiness]
    RouteF["Route / Scene Coordinator"]
  end

  subgraph Domain["Domain / authority"]
    Work["Task + Project stores"]
    Planning[Planning]
    Speech["STT / TTS"]
    Execution["Canonical reviewed-action executor"]
    Calendar["Calendar adapter"]
    Receipt["Receipt / recoverable failure"]
    Preferences["App settings + Keychain"]
  end

  Board --> WorkF
  Today --> TodayF
  Inbox --> InboxF
  Projects --> WorkF
  Detail --> WorkF
  Smart --> WorkF
  Schedule --> ScheduleF
  Done --> WorkF
  Review --> ReviewF
  Voice --> VoiceF
  Settings --> SettingsF
  Menu --> RouteF
  Onboarding --> RouteF

  WorkF --> Work
  TodayF --> Work
  TodayF --> Planning
  InboxF --> Work
  ReviewF --> Execution
  VoiceF --> Speech
  VoiceF --> ReviewF
  ScheduleF --> Planning
  ScheduleF --> ReviewF
  Execution --> Calendar
  Execution --> Receipt
  SettingsF --> Preferences
  RouteF --> WorkF
  RouteF --> VoiceF
```

The normal product path is therefore `Capture -> Interpret -> Review -> Move
-> Evidence`: Inbox/Menu Bar/Voice capture owns intake, Review owns approval,
the canonical executor owns external writes, and receipts remain visible in
Review or Completed. No direct-write edge exists from Capture, Today, Schedule,
or Voice.

## Gaps and tensions

- **Knowledge frames have no viewing surface.** The command palette finds
  them in content search but "Knowledge frames do not have a dedicated view
  yet" (`CommandPaletteView.swift`); executing that palette action just
  closes the palette (`ProjectBoardView.swift`). They are effectively
  write/import-only (backup restore) plus search snippets.
- **Weekly review has no destination.** The Friday notification's tap falls
  through to Today; nothing shows more than the two counts in its body.
- **Workspace Q&A answers are ephemeral.** `workspaceAnswer` is in-memory
  state on `VoiceCaptureViewModel`; answers are lost on clear/new capture
  and are never persisted or linked to tasks.
- **Menu bar quick capture is deliberately narrow.** Inbox-only, backlog
  status, no project targeting — by design it skips queue/receipt/connector
  runtimes (`MenuBarQuickCaptureController.swift`), so triage always
  happens later on the board.
- **Approve and Run are two steps in two windows.** The voice window can
  approve but never run; users must cross to the board's Assistant Queue to
  execute. This is an intentional safety boundary, but the IA cost is a
  mandatory window switch in the happiest voice path — and since Assistant
  Queue moved inside the Review hub, the cost is now a window switch plus two
  levels of navigation. The capture placeholder names the full path
  ("Review › Assistant Queue") so the destination is at least findable, but
  the split itself is still an open product decision.
- **Assistant Queue is two levels deep.** It is the terminal step of the
  headline voice flow yet sits under Review → Automation. Nothing in the
  top-level sidebar names it.
