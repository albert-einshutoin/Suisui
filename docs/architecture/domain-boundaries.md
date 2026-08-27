# Suisui Domain Boundaries

This document defines the current ownership areas for Suisui before broad
refactoring starts. It is intentionally conservative: Phase 0 documents and
tests boundaries first, then later PRs can move code without changing behavior,
release evidence, accessibility identifiers, localization keys, or
approval-before-execution guarantees.

## Dependency Direction

Allowed direction:

`UI/platform surfaces -> domain view models/snapshots -> domain services/ports -> infrastructure adapters`

The reverse direction is not allowed. Core and non-app runtime targets must not
import SwiftUI, AppKit, EventKit, AVFoundation, AuthenticationServices, Sparkle,
or SwiftTerm. SwiftUI feature views must not construct SQLite stores directly.
OAuth, network, Keychain, EventKit, and similar runtime adapters must stay in
app composition or adapter files.

## Domain Table

| Domain | Owns | Current code area | Boundary rule |
| --- | --- | --- | --- |
| Work Management | Projects, tasks, milestones, inbox capture, due work, done follow-up state, board snapshots, and local-first task lifecycle rules. | `Sources/SuisuiCore/App/ProjectBoard.swift`, `ProjectMilestones.swift`, `InboxCapture.swift`, `DailyWorkloadDashboard.swift`, `WeeklyScheduleCockpit.swift`, `DoneFollowUpActionDraft.swift`, `ExternalTaskInterop.swift` | Owns business decisions and persistence contracts. It can depend on stores/protocols but not SwiftUI/AppKit. UI receives snapshots/actions, not raw SQLite ownership. |
| Planning & Schedule | Today planning, missed work, daily workload, weekly cockpit, schedule drafts, calendar apply request shape, and local scheduling recommendations. | `DailyPlanning*.swift`, `DailyWorkloadDashboard.swift`, `WeeklyScheduleCockpit.swift`, `MissedTaskReview.swift`, `ProjectWorkflowTodayView.swift`, `ProjectWorkflowScheduleView.swift`, `ProjectWorkflowCatchUpView.swift` | Depends on Work Management and calendar ports, not concrete EventKit/Google clients or SwiftUI-owned persistence. Calendar writes stay approval-first. |
| Workflow Surfaces | Today, Schedule, Catch Up, Done, Inbox, Assistant Queue, inspector, toolbar, voice/review panels, menu bar panel, launch recovery, and settings presentation state. | `Sources/SuisuiApp/Views/ProjectWorkflow*View.swift`, `ProjectWorkflowSharedViews.swift`, `ProjectBoardView.swift`, `TerminalPanelView.swift`, `SettingsView.swift`, `VoiceCaptureView.swift`, `ActionReviewPanel.swift`, `MenuBarPanel.swift`, `ProjectBoardLaunchRecoveryViews.swift` | Owns SwiftUI layout and accessibility identifiers. It must call view models or injected closures instead of constructing persistence, OAuth, network, or EventKit adapters. |
| App Shell and Runtime Composition | Application launch, scene wiring, migrations, store factories, provider factories, settings runtime factories, and platform permission snapshots. | `Sources/SuisuiApp/SuisuiApp.swift`, `Sources/SuisuiApp/Composition/*`, `Sources/SuisuiApp/Adapters/*`, `Sources/SuisuiCore/Database/*` | Owns composition roots and platform adapter selection. It may instantiate SQLite, Keychain, EventKit, UserDefaults, and OAuth/network runtime services when kept out of feature view files. |
| Automation and Approval | Review-before-execution, assistant queue payload translation, assistant queue execution, task auto-execution policy, receipts, cost previews, and audit trail redaction. | `Sources/SuisuiCore/App/AssistantQueueAutomationPlanFactory.swift`, `AssistantQueueExecutionCoordinator.swift`, `AssistantQueueExecution.swift`, `TaskAutoExecution.swift`, `ExecutionReceipt*.swift`, `CostPreview.swift`, `Review/*`, `Audit/*` | Owns approval state transitions and auditable execution. UI can request review or approval, but execution remains behind domain services and explicit approval tokens. Payload-to-plan translation stays separate from queue execution and receipt persistence. |
| Integrations and Sync | Google Calendar readiness/sync, EventKit links, reminders, notifications, MCP registration/execution, SaaS connectors, and cloud sync boundaries. | `Sources/SuisuiCore/App/Sync*.swift`, `ExternalTaskInterop.swift`, `Sources/SuisuiGoogleCalendarRuntime/*`, `Sources/SuisuiCore/ExternalMCP/*`, `Sources/SuisuiCore/Tools/*`, `Sources/SuisuiApp/Adapters/EventKitToolClients.swift` | Owns external side effects behind ports/adapters. Secrets stay in `SecretStore`, Keychain, OAuth credential stores, or redacted audit payloads; feature views never materialize raw tokens. |
| Voice and Assistant Intake | Speech-to-text, text-to-speech, voice capture, clarification, command routing, inbox voice triage, and assistant request intake. | `Sources/SuisuiCore/Voice/*`, `Sources/SuisuiCore/App/InboxVoiceTriageCommand.swift`, `Sources/SuisuiApp/Adapters/AVFoundation*.swift` | Owns voice command interpretation and draft creation. Platform audio adapters remain in app adapters; domain command routing stays UI-framework-free. |
| Knowledge & Documents | Knowledge frames, vector indexes, artifacts, document-scoped automation, generated drafts, and source-bound evidence references. | `Sources/SuisuiCore/Knowledge/*`, `Sources/SuisuiCore/Artifacts/*`, `DocumentScopedAutomation.swift`, `ProjectTaskKnowledgeTools.swift` | Cross-domain references use stable evidence/artifact IDs or redacted paths. UI and automation should not pass raw local paths where an artifact/evidence reference is available. |
| Settings, Entitlements & Billing | App settings, provider readiness, task automation settings, entitlements, managed AI usage, and billing-facing usage snapshots. | `AppSettings*.swift`, `Entitlements.swift`, `ManagedAI*.swift`, `Sources/SuisuiApp/Views/SettingsView.swift` | Local non-secret configuration may use settings stores. Secrets stay behind `SecretStore`/Keychain/OAuth stores, and readiness rows expose presentation-safe state only. |
| Persistence, Security & Audit | SQLite connection/migrations, concrete stores, secret store abstractions, redaction, keychain access, permissions, and audit log writers. | `Sources/SuisuiCore/Database/*`, `Sources/SuisuiCore/Security/*`, `Sources/SuisuiCore/Audit/*`, `SQLite*Store` implementations | Infrastructure adapters may depend on SQLite, filesystem, Keychain, URLSession, or platform APIs only behind explicit ports. Errors and audit payloads are redacted before reaching UI. |
| Developer Mode and OSS Operations | Local development workflows, repository file access, PR/issue creation, verification commands, release readiness evidence, and CLI read-only reporting. | `Sources/SuisuiCore/DeveloperMode/*`, `Sources/SuisuiCore/App/SuisuiHarness.swift`, `script/*`, `docs/quality/*`, `docs/release/*` | Owns OSS automation and evidence generation. It may use local process/filesystem abstractions, but secrets must be redacted and destructive operations remain approval-gated. |

## Known Exceptions

- `Sources/SuisuiApp/SuisuiApp.swift` remains the app scene composition root.
  Runtime construction lives in `Sources/SuisuiApp/Composition/*`, where SQLite
  stores, `UserDefaults` settings stores, Keychain-backed stores, OAuth
  services, EventKit clients, and Google Calendar runtime factories are allowed.
- Core presentation view-model exception: `Sources/SuisuiCore/App/ProjectBoard.swift`
  currently contains `ObservableObject`/`@Published` view-model state without
  importing SwiftUI. This is allowed until Phase 1 isolates Work Management
  value types, stores, services, and presentation state in smaller files.
- SQLite ownership exception: Core may contain SQLite store implementations and
  app/runtime composition may instantiate them. The boundary violation is a
  SwiftUI feature view owning `SQLiteConnection`, `SQLite*Store`,
  `CoreMigrations`, or `migratedConnection()` directly.
- `Sources/SuisuiApp/Adapters/*` may import platform frameworks such as
  AVFoundation, EventKit, UserNotifications, and ServiceManagement because
  those files are adapter boundaries, not feature views.
- `Sources/SuisuiApp/Views/ProjectBoardView.swift` and
  `Sources/SuisuiApp/Views/TerminalPanelView.swift` currently import AppKit for
  macOS-specific presentation/terminal bridging. New business logic, persistence,
  OAuth, network, or EventKit ownership must not be added there.
- The app target may link narrow runtime packages such as
  `SuisuiGoogleCalendarRuntime`, but optional connector targets such as
  `SuisuiExternalConnectors` must stay outside the app runtime unless a later PR
  explicitly documents and tests the link boundary.
- Core infrastructure files may contain SQLite, URLSession, filesystem, process,
  or Keychain implementations when they sit behind protocols such as
  `SecretStore`, `HTTPDataClient`, tool clients, stores, or runtime services.
- No broad file moves before boundary tests. Extraction PRs should move one
  domain at a time and prove behavior preservation with focused tests plus the
  release/security gates listed below.

## Boundary Tests

`ArchitectureBoundaryTests` pins the Phase 0 rules:

- Core sources do not import SwiftUI or AppKit.
- Core/runtime targets do not import UI or app-only platform frameworks.
- SwiftUI feature views do not directly construct SQLite or app secret stores
  outside `SuisuiApp.swift`.
- OAuth, network, Keychain, and EventKit runtime adapters stay out of
  `Sources/SuisuiApp/Views`.
- This document must continue to define domain ownership, dependency direction,
  and known exceptions.

## Refactoring Sequence

1. Phase 0: add this document and boundary tests only.
2. Phase 1: split Work Management from `ProjectBoard.swift` into board
   snapshots, command/application services, stores, and scheduler/read-model
   helpers without changing public behavior.
3. Phase 2: keep Today, Schedule, Catch Up, Done, Inbox, Assistant Queue, and
   shared layout in their feature-owned view files while preserving stable
   accessibility identifiers and localization. The superseded
   `ProjectWorkflowViews.swift` owner has been removed.
4. Phase 3: extract app shell/runtime composition from `SuisuiApp.swift` into
   composition factories and settings runtime modules, keeping settings UX and
   Google Calendar readiness behavior unchanged.
5. Phase 4: normalize Automation and Approval so approval tokens, queue
   transitions, execution receipts, and audit redaction stay in one domain.
6. Phase 5: de-duplicate integration/runtime adapters for Google Calendar,
   EventKit, notifications, MCP, and provider secrets behind explicit ports.
7. Phase 6: consider target/package splits only after the boundaries are stable
   and every domain can be verified independently.

## Verification Required Per Extraction PR

- `swift test --filter ArchitectureBoundaryTests`
- `swift test --filter AppExperienceSourceTests`
- Relevant domain tests for the moved code
- `./script/check_security_regressions.sh`
- `git diff --check`

Behavior-preserving extraction PRs must also keep release evidence, smoke
scripts, accessibility identifiers, localization keys, VoiceOver/manual gates,
and approval-first execution flows stable unless the PR explicitly changes and
documents them.
