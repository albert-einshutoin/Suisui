# Contributing

SoloPM is developed with Gitflow, TDD, and a review-before-write safety model.

## Branches

- `main`: release-ready code only.
- `develop`: integration branch for the next release.
- `feature/phaseN-short-name`: feature work.
- `fix/phaseN-short-name`: bug fixes.
- `docs/phaseN-short-name`: documentation-only changes.

Do not push directly to `main`.

## Task Workflow

Use [tasks/README.md](tasks/README.md) as the source of task structure.

Before coding, expand each Phase item into an issue using the recommended format:

- Context
- Scope
- Non-goals
- Implementation steps
- Tests first
- Acceptance criteria
- Review focus

If the expanded task is larger than one day, split it by domain model, adapter, UI, fixture, or test scope.

## TDD

- Write a failing test first.
- Keep macOS APIs behind protocols and adapters.
- Use fakes for EventKit, UserNotifications, Keychain, FSEvents, LLM, and STT in unit tests.
- Validate dangerous and approval-required behavior explicitly.

Local verification:

```sh
./scripts/verify.sh
```

When full Xcode and a working SwiftPM manifest toolchain are available, also run `swift test` and `swift build`.

## Pull Requests

Every PR should include:

- Linked task
- Summary
- Test results
- Manual verification
- Safety / privacy review
- Remaining risk

Do not mix unrelated UI, storage, external API, and packaging changes in one PR.

## Architecture Decisions

Use [docs/adr](docs/adr) for important technical decisions. Do not leave durable decisions only in chat, issue comments, or PR comments.
