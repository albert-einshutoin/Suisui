# ADR 0001: macOS Deployment Target

Date: 2026-06-17  
Status: Accepted

## Context

SoloPM is a macOS-native menu bar app. The product should use modern SwiftUI APIs such as `MenuBarExtra` while keeping optional macOS 26 APIs, including SpeechAnalyzer and Foundation Models, behind availability checks.

## Decision

Use macOS 14 as the initial minimum deployment target for the Swift Package skeleton. macOS 26-only APIs remain optional and must be guarded by availability checks.

## Options Considered

### macOS 13

- Pros: Earliest practical target for `MenuBarExtra`.
- Cons: Wider compatibility increases testing matrix before the product has a stable MVP.

### macOS 14

- Pros: Modern baseline, supports `MenuBarExtra`, keeps the initial support matrix manageable.
- Cons: Excludes some older Macs that could technically run a menu bar app.

### macOS 26

- Pros: Matches the newest local toolchain and optional native AI APIs.
- Cons: Too narrow for an MVP and would make SpeechAnalyzer / Foundation Models hard dependencies.

## Consequences

- Positive: The skeleton can use current SwiftUI menu bar APIs without a large compatibility matrix.
- Negative: macOS 13 users are not supported in the first skeleton.
- Follow-up: Revisit the minimum target before public alpha.

## Links

- Related task: tasks/Phase0-Skeleton.md

