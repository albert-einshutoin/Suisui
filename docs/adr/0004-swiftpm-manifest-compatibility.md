# ADR 0004: SwiftPM Manifest Compatibility

Date: 2026-06-17  
Status: Accepted

## Context

The current local CommandLineTools installation reports SwiftPM 6.3.2, but `swift test` fails while linking the package manifest against `libPackageDescription.dylib`. Core sources compile with `swiftc`, so the issue is isolated to local SwiftPM manifest loading rather than application source code.

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

- Positive: Phase 0 implementation remains verifiable in this environment.
- Negative: `swift test` is currently blocked until the local Xcode / CommandLineTools installation is corrected.
- Follow-up: When full Xcode is configured, replace the fallback with normal `swift test` in CI.

## Links

- Related task: tasks/Phase0-Skeleton.md

