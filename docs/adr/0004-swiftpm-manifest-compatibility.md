# ADR 0004: SwiftPM Manifest Compatibility

Date: 2026-06-17  
Status: Accepted

## Context

The current local CommandLineTools installation reports SwiftPM 6.3.2, but `swift test` fails while linking the package manifest against `libPackageDescription.dylib`. Core sources compile with `swiftc`, so the issue is isolated to local SwiftPM manifest loading rather than application source code.

After installing and selecting full Xcode 26.5, normal `swift test` and `swift build` work. The fallback verifier remains useful as a low-level diagnostic path.

## Decision

Keep `Package.swift` aligned with the intended Swift 6 / macOS 14 project baseline. Add `scripts/verify.sh` as a local fallback that directly compiles the core module, typechecks the SwiftUI app target, and runs a small manual test runner without relying on SwiftPM manifest loading.

## Options Considered

### Downgrade Package.swift until this CLT accepts it

- Pros: Might make `swift test` work on this single machine.
- Cons: Conflicts with the technical baseline and still did not resolve the local linker mismatch.

### Keep modern Package.swift and add a fallback verifier

- Pros: Preserves the project baseline while keeping local verification possible.
- Cons: Requires replacing the fallback once full Xcode / working SwiftPM is available.

## Consequences

- Positive: Phase 0 implementation remains verifiable even if SwiftPM manifest loading regresses.
- Negative: The fallback verifier duplicates a small amount of SwiftPM behavior.
- Follow-up: Use `swift test` and `swift build` as primary CI checks. Keep the fallback only for diagnostics.

## Links

- Related task: tasks/Phase0-Skeleton.md
