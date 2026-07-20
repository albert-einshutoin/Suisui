# ADR 0003: Global Shortcut Library

Date: 2026-06-17  
Updated: 2026-07-17
Status: Accepted

## Context

Suisui needs a process-wide global shortcut for Voice Command, with `Option + Space` as the fixed first-release shortcut. It must not require Input Monitoring, must not create duplicate Voice windows, and must report registration conflicts truthfully.

## Decision

Keep the `ShortcutClient` abstraction and implement its production adapter in the App target with Carbon `RegisterEventHotKey`.

- Register only `Option + Space`.
- Own one registration token for the process and make repeated registration idempotent.
- Unregister on explicit disable and adapter deinitialization.
- Dispatch shortcut handling to `MainActor`.
- Activate the existing Voice Command window when present. Otherwise issue one in-app Voice window request and suppress repeats until the window appears or the request fails.
- Represent `Registered`, `Not registered`, `Conflict`, and `Unavailable` as `ShortcutRegistrationState`, and keep `Shift + Command + V` visible as the in-app fallback when global registration is not active.
- Do not add Input Monitoring entitlements or broad keyboard event taps.

## Options Considered

### KeyboardShortcuts package

- Pros: Higher-level API and configurable shortcut support.
- Cons: Adds a dependency for a single fixed shortcut and obscures the exact permission boundary.

### Carbon RegisterEventHotKey behind the existing protocol

- Pros: Native process-wide registration, explicit conflict result, no Input Monitoring permission, no new package.
- Cons: Requires a small App-target adapter and lifecycle ownership.

### NSEvent global monitor or CGEvent tap

- Pros: Can observe broader keyboard input.
- Cons: Broader than the product need and can require Input Monitoring. Rejected.

## Consequences

- Positive: Core lifecycle and conflict behavior remain unit-testable without macOS event hooks.
- Positive: The production adapter listens only for Option + Space and does not request arbitrary keyboard monitoring.
- Positive: Settings reflects real registration state and preserves a discoverable in-app fallback.
- Negative: The global shortcut is intentionally fixed for this release. User customization requires a later ADR.
- Runtime verification must distinguish successful registration from a real conflict with another process.

## Links

- Related plan: `docs/superpowers/plans/2026-07-14-product-experience-renewal.md`
