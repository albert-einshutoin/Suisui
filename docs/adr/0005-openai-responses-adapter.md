# ADR 0005: OpenAI Responses Adapter

Date: 2026-06-17  
Status: Accepted

## Context

SoloPM Phase 1 needs an LLM provider that converts a planning prompt into an `ActionPlan`. The provider must keep API keys behind `SecretStore`, avoid logging secrets or full private context by default, and remain testable without live network calls.

## Decision

Add an `OpenAIResponsesProvider` behind the existing `LLMProvider` protocol. Unit tests cover URLRequest construction, response text extraction, status-code mapping, and fake HTTP success paths. Live OpenAI calls are not part of the default test suite.

The adapter uses a configurable timeout with a 60-second default and does not retry automatically in Phase 1.

## Options Considered

### Live API Test in Unit Suite

- Pros: Detects API compatibility drift quickly.
- Cons: Requires secrets, costs money, is flaky under network issues, and is unsafe for OSS contributors.

### URLRequest Builder Plus Fake HTTP Client

- Pros: Keeps TDD local, avoids secret requirements, and verifies the API boundary shape.
- Cons: Does not prove a real model currently accepts the request.

### Automatic Retry in Phase 1

- Pros: Can smooth transient failures.
- Cons: Complicates rate-limit behavior, increases cost risk, and hides failure modes before the review UI exists.

## Consequences

- Positive: Contributors can verify the provider boundary with `swift test` and no API key.
- Positive: API key access is isolated to `SecretStore`.
- Negative: A separate opt-in integration smoke test is still needed before public alpha.
- Follow-up: Add an explicit integration smoke command that reads a developer-provided API key from Keychain and redacts request metadata.

## Links

- Related task: tasks/Phase1-VoiceToActionPlan.md
