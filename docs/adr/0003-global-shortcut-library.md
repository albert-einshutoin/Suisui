# ADR 0003: Global Shortcut Library

Date: 2026-06-17  
Status: Proposed

## Context

SoloPM needs a global shortcut for voice capture, with `Option + Space` as the default candidate. The technical stack lists `KeyboardShortcuts` as the likely library, but Phase 0 only needs the abstraction boundary.

## Decision

Start with a `ShortcutClient` abstraction and a domain-level shortcut registration state. Defer adding the `KeyboardShortcuts` package until the overlay is wired in Phase 1.

## Options Considered

### Add KeyboardShortcuts in Phase 0

- Pros: Validates the real library immediately.
- Cons: Adds dependency and runtime behavior before the voice overlay exists.

### Protocol first, dependency later

- Pros: Keeps Phase 0 small and testable, lets Phase 1 connect the real shortcut to the overlay.
- Cons: Manual shortcut behavior is not validated in Phase 0.

## Consequences

- Positive: Core shortcut state is testable without macOS event hooks.
- Negative: The first skeleton only has a placeholder action.
- Follow-up: Accept or supersede this ADR when Phase 1 connects the real global shortcut implementation.

## Links

- Related task: tasks/Phase0-Skeleton.md

