# SoloPM

SoloPM is a macOS-first personal PM app that turns voice or text into projects, tasks, calendar events, reminders, notifications, and local work artifacts after user review.

## Status

This repository is in Phase 0 skeleton development. The current implementation provides:

- Swift Package baseline
- SwiftUI MenuBarExtra skeleton
- Settings window skeleton
- Testable core models
- SQLite migration bootstrap
- Keychain secret storage boundary
- Audit log redaction boundary

The product specification lives in [docs/README.md](docs/README.md), and the current technical baseline lives in [docs/tech_stack.md](docs/tech_stack.md).

## MVP Scope

The MVP focuses on:

- macOS menu bar app
- voice / text input
- LLM-generated Action Plan
- review-before-write execution
- local Project / Task storage
- Apple Calendar / Reminders / Notifications
- Markdown artifact creation
- Knowledge Frames
- local audit logs

The MVP does not include team management, automatic email sending, automatic Slack posting, Git push, file deletion, full RAG, or bundled WeKnora.

## Development

SoloPM follows Gitflow and TDD. Work should start from `develop` using a feature branch:

```sh
git checkout develop
git checkout -b feature/phase0-skeleton
```

Local verification:

```sh
./scripts/verify.sh
```

When full Xcode and a working SwiftPM manifest toolchain are available, also run `swift test` and `swift build`.

The active task plan is in [tasks/README.md](tasks/README.md). Phase files are issue seeds; expand each `Pn-xxx` task into an issue before implementation.

## Architecture Decisions

Architecture Decision Records live in [docs/adr](docs/adr). Important toolchain, storage, dependency, and safety decisions should be captured there before implementation.

## Security

API keys and provider tokens must be stored in macOS Keychain. Secrets must not be written to logs, SQLite settings, UserDefaults, fixtures, or screenshots.

See [SECURITY.md](SECURITY.md).
