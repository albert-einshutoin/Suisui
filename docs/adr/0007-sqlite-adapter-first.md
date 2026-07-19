# ADR 0007: SQLite Adapter First

Date: 2026-06-17  
Status: Accepted

## Context

Suisui originally listed GRDB.swift as the first candidate for the local SQLite wrapper. The implemented codebase already has a small `sqlite3`-backed adapter, migration runner, in-memory test path, FTS5 usage, and focused store APIs for projects, tasks, knowledge frames, notifications, calendar links, reminders, deadlines, artifacts, and knowledge vectors.

## Decision

Keep the internal `sqlite3` adapter as the MVP persistence boundary. Defer GRDB.swift until the local store layer needs richer query composition, observation, or migration ergonomics that outweigh the additional dependency and migration cost.

## Options Considered

### Keep Internal SQLite Adapter

- Pros: Minimal dependency surface, already covered by tests, easy to reason about for local-first storage.
- Cons: More manual SQL and escaping discipline.

### Migrate To GRDB.swift Now

- Pros: Mature Swift SQLite wrapper, stronger ergonomics for records and migrations.
- Cons: Broad rewrite across existing stores without immediate product value.

## Consequences

- Positive: Phase 0-9 work can continue on the tested storage boundary.
- Positive: SQLite and FTS5 remain the persistence truth source.
- Negative: The team must keep SQL construction small, reviewed, and covered by tests.
- Follow-up: Re-evaluate GRDB when queries become more complex or when observation support becomes necessary.

## Links

- Related task: tasks/Phase0-Skeleton.md
- Related implementation: Sources/SuisuiCore/Database/SQLiteDatabaseClient.swift
