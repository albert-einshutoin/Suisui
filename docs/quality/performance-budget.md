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
task begins bundle preparation (after a short `ProjectBoardLaunchHydrationDelay`
of 150 ms that keeps the first window paint responsive), not at `main()`.
For true process-start-to-paint numbers, combine with the App Launch
template's lifecycle phases.

## Budgets to hold

| Metric | Budget | Primary signpost / probe |
| --- | --- | --- |
| Cold launch → first board paint | 1.0 s | App Launch template end-to-end; `LaunchToRuntimeBundle` + `FirstBoardLoad` cover the SoloPM-owned share |
| Board reload at 1k tasks | 100 ms | `FirstBoardLoad` measured against a seeded 1k-task database |
| Command palette content search | 50 ms | `CommandPaletteContentSearchService` query (no signpost yet; measure with Instruments Time Profiler or a test harness) |

## Recorded measurements

Record real numbers here after each profiling run (machine, build
configuration, dataset size, date).

| Date | Machine / build | LaunchToRuntimeBundle | DatabaseOpenMigrate | FirstBoardLoad | Cold launch → first paint | Palette search |
| --- | --- | --- | --- | --- | --- | --- |
| — | — | unmeasured — record on first profiling run | unmeasured — record on first profiling run | unmeasured — record on first profiling run | unmeasured — record on first profiling run | unmeasured — record on first profiling run |

## Scale guard

`script/check_performance_stress_suite.sh` is the existing regression guard
for scale-sensitive paths (large boards, large assistant queues, receipt
listing, vector search, calendar sync bounds). It runs deterministic
`swift test` filters and, with `SOLOPM_STRESS_RUNTIME_PERFORMANCE=1`, the
release launch performance smoke
(`script/check_release_launch_performance_smoke.sh`). Keep that suite green
before trusting any budget number recorded above.
