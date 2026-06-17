# Contributing

SoloPM is developed with Gitflow, TDD, and a review-before-write safety model.

## Branches

- `main`: release-ready code only.
- `develop`: integration branch for the next release.
- `feature/phaseN-short-name`: feature work.
- `fix/phaseN-short-name`: bug fixes.
- `docs/phaseN-short-name`: documentation-only changes.

Do not push directly to `main`.

## Supported Environment

- macOS 14 or later
- Swift 6 toolchain
- Xcode command line tools or Xcode
- Developer ID Application certificate only for release signing
- Apple notary profile only for notarization

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

If the expanded task is larger than one day, split it by domain model, adapter, UI, fixture, script, or test scope.

## TDD

- Write a failing test first.
- Keep macOS APIs behind protocols and adapters.
- Use fakes for EventKit, UserNotifications, Keychain, FSEvents, LLM, and STT in unit tests.
- Validate dangerous and approval-required behavior explicitly.

Local verification:

```sh
./scripts/ci.sh
./script/build_and_run.sh --verify
```

`./scripts/ci.sh` is the shared CI/local command and intentionally avoids GUI launch. The SwiftPM build and test suite are the current lint gate. A separate formatter is not enforced during alpha because the codebase is still small and relies on focused review plus `git diff --check`; introduce SwiftFormat or SwiftLint only when formatting drift becomes a recurring review cost.

## Issue Triage

- `bug`: behavior regression or broken release workflow.
- `security`: secret handling, unsafe action execution, or trust boundary issue.
- `phaseN`: work linked to the task phase files.
- `good first issue`: isolated doc, test, or small fake-adapter improvement.
- `blocked`: requires certificate, external account, Apple notary profile, or product decision.

Alpha issues should include reproduction steps, expected behavior, actual behavior, environment, and whether the issue touches user data or secrets.

## Review Policy

Every PR should include:

- Linked task or issue
- Summary
- Test results
- Manual verification
- Safety / privacy review
- Remaining risk

Reviewers should prioritize correctness, security boundaries, secret handling, release reproducibility, and user-visible regressions. Do not mix unrelated UI, storage, external API, and packaging changes in one PR.

## Architecture Decisions

Use [docs/adr](docs/adr) for important technical decisions. Do not leave durable decisions only in chat, issue comments, or PR comments.
