# ADR 0002: Audit Log Primary Store

Date: 2026-06-17  
Status: Accepted

## Context

SoloPM must record Action Plans, user approvals, and tool invocations locally. The technical plan mentions SQLite and local JSONL logs. Phase 0 needs one primary store to avoid duplicating write paths too early.

## Decision

Use SQLite as the primary audit log store for the MVP skeleton. JSONL export can be added later for diagnostics or portability.

## Options Considered

### SQLite primary

- Pros: Queryable, already required for local app state, easy to join with projects and tasks.
- Cons: Less convenient for manual inspection than JSONL.

### JSONL primary

- Pros: Easy to inspect and append.
- Cons: Harder to query for UI, filtering, and diagnostics.

### Dual write from Phase 0

- Pros: Gives both queryability and manual inspection.
- Cons: Increases consistency and redaction risk too early.

## Consequences

- Positive: One local persistence path for settings and audit logs.
- Negative: Debug export needs a later task.
- Follow-up: Add JSONL export only after audit schema stabilizes.

## Links

- Related task: tasks/Phase0-Skeleton.md

