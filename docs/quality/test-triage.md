# Test Triage

Status: P14-012 source contract
Owner: SoloPM quality gate

This document classifies failures before retrying or quarantining them. A failing
test should keep failing until the category, owner, and next command are clear.

## Failure Categories

| Category | Meaning | First action | Minimal reproduction command |
| --- | --- | --- | --- |
| build | Compilation, linking, package resolution, or generated-code failure | Fix the build before classifying product behavior | `swift test --filter <suite>` or `swift build` |
| assertion | XCTest or script assertion failed with a stable mismatch | Read the assertion, add the smallest regression test, then fix | The focused test or script printed in the failure |
| crash | Process terminated unexpectedly, signaled, or produced a crash log | Capture the crash reason and keep the failing artifact | The shortest command that still crashes |
| timing | Race, ordering, timeout, animation, or AX frame stabilization issue | Reproduce locally, then convert the timing assumption into a deterministic gate | Runtime smoke command plus the failing scenario id |
| environment | Missing command, permission, Xcode, Screen Recording, signing, or machine state | Record the host requirement and fail with a clear blocker | The doctor/preflight command that reports the blocker |
| manual gate | VoiceOver, Gatekeeper, clean environment, or competitor hands-on evidence gap | Keep it as a release blocker or route it to automation-backlog | The evidence generator or manual runbook command |

## Routing

- PR gate failures start with `scripts/ci.sh`, which runs source/unit checks and build checks.
- Runtime and visual failures require explicit CI flags, because they depend on a visible app, Screen Recording, or screenshot baselines.
- Manual gate failures must not be hidden as flakes. They either remain manual-only release blockers or move to automation-backlog with a linked regression target.
- If quarantine is proposed, update `docs/quality/flake-quarantine.md` with owner, reason, expiry, and minimal reproduction command.

## Quarantine Rules

No indefinite quarantine is allowed. Quarantine is a short-lived routing state,
not a way to keep shipping around a failing test.

Required fields for every non-empty quarantine entry:

- owner
- reason
- expiry
- minimal reproduction command
- category from the table above
- automation-backlog or linked follow-up when the fix is not immediate
