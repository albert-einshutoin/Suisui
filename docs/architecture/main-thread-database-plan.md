# Main-Thread Database Access: Assessment and Migration Plan

Status: foundation implemented by ADR 0012. Drafted 2026-07-07, updated 2026-07-24.

The connection-level serialization, WAL/busy policy, cancellation-aware
`SQLiteDatabaseWorker`, and non-escapable row boundary described below now
exist. Store-by-store async migration remains follow-up work; ADR 0012 is the
authoritative ownership decision.

## Current state

Suisui's SQLite stores are synchronous classes guarded by `NSLock`
(`@unchecked Sendable`), called both from background contexts and from
`@MainActor` view models. The launch path already protects first paint:
`prepareProjectBoardRuntimeBundle` opens and migrates the database off the
main actor before the board view model is published, and background surfaces
added recently (deadline watcher ticks, Dock badge refresh, notification
actions) run store work on detached tasks or utility queues.

What still runs on the main actor synchronously:

- `ProjectBoardViewModel.load()` and mutation methods (create/update/move),
  re-invoked on every `suisuiProjectBoardDidChange` notification.
- Settings readiness refreshes that read stores after the settings window
  opens.
- Menu bar summary refresh when the panel opens (single aggregate query).

## Why a full async/actor refactor is deferred

1. **Measured reads are bounded.** The deterministic stress suite pins the
   hot read models to indexed queries (`idx_tasks_*`,
   `idx_project_milestones_*`) and verifies large-board loads avoid full
   scans and full-payload decodes. At personal-workspace scale the observed
   read cost is low single-digit milliseconds.
2. **Blast radius.** The stores are consumed by ~50 call sites across view
   models, tools, watchers, and tests. Converting the store layer to an
   actor (or async facade) invalidates the locking assumptions everywhere
   at once; doing it inside a feature branch would couple an infrastructure
   rewrite to product changes and defeat reviewability.
3. **The lock composition is now load-bearing.** Completion-driven
   recurrence intentionally composes multiple statements under one
   `NSLock` acquisition (`completeAndRegenerate`); an actor migration must
   redesign that transactional grouping deliberately, not mechanically.

## Migration plan (own PR series)

1. Introduce `DatabaseWorker` — a serial executor (actor wrapping the
   `SQLiteConnection`) exposing `func run<T>(_ body: (SQLiteConnection)
   throws -> T) async throws -> T`, with statement grouping preserved by
   running composed operations inside a single `run` block.
2. Migrate read models first (board snapshot, menu bar summary, settings
   readiness) — view models `await` snapshots and publish on the main
   actor; UI states gain explicit loading placeholders where reads were
   previously synchronous.
3. Migrate mutations store-by-store, deleting each `NSLock` as its store
   moves onto the worker; `@unchecked Sendable` conformances go with them.
4. Gate with the existing stress suite plus a new main-thread watchdog test
   (fail if any store call executes on the main thread in debug builds).

## Interim guardrails (in place on this branch)

- All periodic/background work (watcher, digest, weekly review, badge,
  notification actions) performs store access off the main actor.
- New store compositions must follow the `completeAndRegenerate` pattern:
  one lock acquisition per user-visible operation, no nested transactions.
