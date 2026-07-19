# Performance Budget

Launch-path performance budgets and how to measure them against the
signposts that ship in the app. Budgets are hold-the-line numbers: a
measurement over budget is a regression to investigate, not a target to
relax.

## Instrumented signposts

Subsystem: `dev.solopm.performance`
Category: `launch`

| Signpost (interval) | What it measures | Emitting code |
| --- | --- | --- |
| `LaunchToRuntimeBundle` | Preparation of the Project Board runtime bundle on the detached launch task (SQLite open + migration + store composition), from the start of `prepareProjectBoardRuntimeBundle()` work to bundle ready. | `Sources/SoloPMApp/Composition/ProjectBoardRuntimeFactory.swift` |
| `DatabaseOpenMigrate` | SQLite connection open plus `CoreMigrations` migration inside bundle preparation. Sub-interval of `LaunchToRuntimeBundle`. | `Sources/SoloPMApp/Composition/ProjectBoardRuntimeFactory.swift` |
| `FirstBoardLoad` | The first `ProjectBoardViewModel.load()` of the process (snapshot load + derived read model rebuild) inside the board view's initial `.task`. Emitted once per process; later reloads are unmeasured. | `Sources/SoloPMApp/Views/ProjectBoardView.swift` via `Sources/SoloPMApp/Composition/LaunchPerformanceSignposts.swift` |

Signposts are measurement-only: no call site branches on them and they wrap
existing work without changing behavior.

## How to measure

1. Build and launch the app (a release-configuration build for numbers you
   intend to record).
2. In Instruments, use the **os_signpost** instrument (or start from the
   **App Launch** template and add os_signpost), then filter to subsystem
   `dev.solopm.performance`, category `launch`.
3. Record from process start through the first fully painted Project Board.
4. Read the interval durations for `LaunchToRuntimeBundle`,
   `DatabaseOpenMigrate`, and `FirstBoardLoad`.

Command-line alternative while the app runs:

```
log stream --predicate 'subsystem == "dev.solopm.performance"' --signpost
```

Note the intentional gap: `LaunchToRuntimeBundle` starts when the launch
task begins bundle preparation, not at `main()`. There is no fixed hydration
delay on the launch path; SwiftUI receives one scheduling yield before the
detached runtime work begins. For true process-start-to-ready numbers, run
`script/check_release_launch_performance_smoke.sh`. The harness budgets the
app-emitted `command-ready` milestone and separately requires the matching AX
markers, so accessibility traversal overhead cannot weaken or inflate the SLO.

## Budgets to hold

| Metric | Budget | Primary signpost / probe |
| --- | --- | --- |
| Cold launch → command-ready board | 1.0 s | Release smoke app-owned `command-ready` milestone plus mandatory `project-board-command-palette` AX proof |
| Board reload at 1k tasks | 100 ms | `FirstBoardLoad` measured against a seeded 1k-task database |
| Command palette content search | 50 ms | `CommandPaletteContentSearchService` query (no signpost yet; measure with Instruments Time Profiler or a test harness) |

## Recorded measurements

Record real numbers here after each profiling run (machine, build
configuration, dataset size, date).

| Date | Machine / build | Window visible | Command ready | Today ready | Result |
| --- | --- | --- | --- | --- | --- |
| 2026-07-20 | Mac mini (M4, 32 GB), Release | 494 ms | 450 ms | 451 ms | GREEN (`.tmp/suisui-release-performance-after-5/`) |
| 2026-07-20 | Mac mini (M4, 32 GB), branded `Suisui.app` Release | 212 ms | 447 ms | 448 ms | GREEN (`.tmp/suisui-branded-release-performance-3/`) |
| 2026-07-20 | Mac mini (M4, 32 GB), final compact-window `Suisui.app` Release | 350 ms | 553 ms | 554 ms | GREEN (`.tmp/suisui-final-release-performance/`) |

## Scale guard

`script/check_performance_stress_suite.sh` is the existing regression guard
for scale-sensitive paths (large boards, large assistant queues, receipt
listing, vector search, calendar sync bounds). It runs deterministic
`swift test` filters and, with `SOLOPM_STRESS_RUNTIME_PERFORMANCE=1`, the
release launch performance smoke
(`script/check_release_launch_performance_smoke.sh`). Keep that suite green
before trusting any budget number recorded above.
