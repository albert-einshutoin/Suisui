# Today Dashboard Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the approved `today.png`-aligned Today dashboard with responsive layout, local Focus/Workload, WeatherKit onboarding, and read-only Calendar/Slack updates.

**Architecture:** Keep `ProjectBoardDerivedReadModels` and the existing Today action facade as the source of truth. Add a pure `TodayDashboardSnapshotBuilder` for board data, and keep Focus, Weather, Calendar, and Slack state in independent stores/models so one failing provider cannot invalidate the whole screen. Compose a native SwiftUI dashboard that uses the approved wide two-column layout and moves the right rail below the main content when the available detail width is insufficient.

**Tech Stack:** Swift 6, SwiftUI/macOS 14, XCTest, Swift Package Manager, Core Location, WeatherKit, Keychain-backed OAuth, existing SQLite settings stores, existing visual evidence harness.

---

## Plan split and order

The approved specification contains four independently testable subsystems. Implement them in this order; each plan must leave the branch buildable and its focused tests green before the next plan starts.

1. [Dashboard foundation](2026-08-09-today-dashboard-foundation.md)
2. [Focus and Workload](2026-08-09-today-focus-workload.md)
3. [Weather and onboarding](2026-08-09-today-weather-onboarding.md)
4. [Calendar and Slack feed](2026-08-09-today-external-feed.md)

## Shared execution rules

- Work from `/Volumes/Satechi/Developer/Suisui-today-dashboard-design` on `design/today-dashboard-parity` or a feature branch created from it.
- Preserve the canonical checkout's dirty `outputs/` and `.superpowers/` artifacts.
- For each task: write the failing test, run the focused test and record the failure, implement the smallest change, rerun the focused test, run the nearest regression suite, then commit.
- Do not introduce a generic widget registry or copy task/schedule data into a new persistent store.
- Keep external Today paths read-only. Any Calendar/Slack write call is a test failure.
- Run `git diff --check` before every commit.
- Before handoff, run `swift test`, `script/build_and_run.sh --verify`, and the relevant visual evidence scripts. A runtime smoke pass is not a substitute for manual UI evidence.

## Global file ownership

| Responsibility | Files |
|---|---|
| Core dashboard projection | `Sources/SuisuiCore/App/TodayDashboardSnapshot.swift`, `Sources/SuisuiCore/App/TodayFeatureViewModel.swift` |
| Dashboard UI | `Sources/SuisuiApp/Views/ProjectWorkflowTodayView.swift` and new `Sources/SuisuiApp/Views/TodayDashboard*.swift` files |
| Settings and onboarding | `Sources/SuisuiCore/App/AppSettings.swift`, `Sources/SuisuiCore/App/FirstRunOnboarding.swift`, `Sources/SuisuiApp/Views/OnboardingWelcomeView.swift`, `Sources/SuisuiApp/Views/SettingsFeatureViews.swift` |
| Focus and local persistence | `Sources/SuisuiCore/App/FocusSession.swift`, `Sources/SuisuiApp/Views/TodayFocusCard.swift` |
| Weather | `Sources/SuisuiCore/App/WeatherLocationPreference.swift`, `Sources/SuisuiApp/Weather/TodayWeatherModel.swift`, `Sources/SuisuiApp/Weather/WeatherKitTodayProvider.swift` |
| Google Calendar | `Sources/SuisuiGoogleCalendarRuntime/GoogleCalendarAppRuntime.swift` plus focused new activity files and `Tests/SuisuiCoreTests/GoogleCalendarAppRuntimeTests.swift` |
| Slack | `Sources/SuisuiExternalConnectors/SlackReadOnlyActivity.swift` and focused tests |
| Visual/release evidence | existing `script/capture_ui_evidence.sh`, `script/check_ci_visual_gate.sh`, `docs/quality/*`, `docs/release/*` |

## Final verification

From the implementation branch, run:

```bash
swift test
script/build_and_run.sh --verify
SUISUI_UI_EVIDENCE_LOCALE=english ./script/capture_ui_evidence.sh
SUISUI_UI_EVIDENCE_LOCALE=japanese ./script/capture_ui_evidence.sh
./script/check_ci_visual_gate.sh
```

Record 1448×1086 Light/Dark/System and 1024×676 Compact evidence, the AX identifiers for `today-workflow`, `today-dashboard-header`, `today-recommendations`, `today-task-list`, `today-review-card`, `today-workload-card`, `today-focus-card`, and `today-assistant-card`, plus the no-write integration test results in the PR description.
