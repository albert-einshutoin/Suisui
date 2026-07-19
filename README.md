# Suisui

[日本語版 README](README.ja.md)

**Speak it. Review it. Move it.**

Suisui is a macOS-first AI personal project manager that turns voice or text into projects, tasks, calendar events, reminders, notifications, and local work artifacts after user review.

![Suisui public alpha preview](docs/assets/screenshots/solopm-alpha-preview.svg)

## Public Alpha

Suisui is preparing its first public alpha. The current build is intended for local-first evaluation by individual developers and makers who want a voice-first workflow for project planning and deadline follow-up.

The product specification lives in [docs/README.md](docs/README.md), the product roadmap lives in [docs/product/roadmap.md](docs/product/roadmap.md), the technical baseline lives in [docs/tech_stack.md](docs/tech_stack.md), and the release runbook lives in [docs/release/checklist.md](docs/release/checklist.md).

## MVP Scope

Suisui ships the Personal MVP first. The smallest MVP is a local-first voice-task loop for one user: capture work by voice or text, clarify missing details, create reviewed tasks/projects/schedule artifacts, and prevent forgotten work.

- macOS menu bar app
- voice / text input
- LLM-generated Action Plan
- review-before-write execution
- local Project / Task / Knowledge storage
- Apple Calendar / Reminders / Notifications adapters
- Markdown artifact creation
- deadline watcher and overdue notification foundation
- Keychain-backed secret boundary
- local audit logs with redaction
- Developer ID signing, notarization, DMG packaging, and Sparkle update foundation

The Business MVP is a later target. Organizations, roles, tenant policies, KnowledgeBase integration, QZT evidence refs, Memory Pager context assembly, cloud execution policy, and audit export must not block the first personal release.

## Known Limitations

- External MCP servers are not part of the public alpha runtime.
- SaaS connectors such as GitHub, Gmail, Slack, Google Drive, and Notion are not enabled.
- Full RAG / WeKnora-style knowledge indexing is out of scope for alpha.
- Team, cloud sync, and shared workspace features are not implemented.
- Release signing and notarization require a Developer ID Application certificate and Apple notary profile on the release machine.
- Sparkle update checks require a signed appcast and Sparkle EdDSA key stored in Keychain.

## Development

Suisui follows GitHub Flow and TDD. Work should start from the current target branch using a short-lived feature branch, then return by pull request:

```sh
git checkout main
git pull --ff-only
git checkout -b feature/short-name
```

Local verification:

```sh
./scripts/ci.sh
./script/build_and_run.sh --verify
swift build --product solopm-cli
.build/debug/solopm-cli --help
```

`./scripts/ci.sh` is the shared non-GUI verification entrypoint for local development and GitHub Actions. `./script/build_and_run.sh --verify` additionally launches the app and is intended for local macOS UI smoke checks.

`./script/build_and_run.sh --verify` is product-path proof: it launches the normal ProjectBoard with isolated `HOME`, `CFFIXED_USER_HOME`, SQLite, and keychain-disabled settings, then checks the PID-owned window and the native-toolbar `project-board-command-palette`, `project-board-sidebar`, and `project-board-detail` product markers. Failures use the machine-readable categories `launch`, `window`, `accessibility`, or `product-marker`.

Recovery diagnostics are a separate contract for designated diagnostic scripts. Those scripts may use `SOLOPM_LAUNCH_RECOVERY_MODE=1` and related recovery flags to inspect a degraded or recovery-only surface. Recovery success is diagnostic evidence, not product or release proof; release evidence must pass the normal `--verify` path. Today, Inbox, accessible CRUD, layout, launch-performance, and UI screenshot release flows launch the normal `ProjectBoardView` route with an explicit selected destination instead.

Release verification starts from the [Release Checklist](docs/release/checklist.md).

## Release Checklist

The public alpha release order is test, build, sign, notarize, package, checksum, appcast, tag, and release notes. The full checklist, rollback path, and known issues template are in [docs/release/checklist.md](docs/release/checklist.md).

## Security

API keys and provider tokens must be stored in macOS Keychain. Secrets must not be written to logs, SQLite settings, UserDefaults, fixtures, screenshots, or crash reports.

See [SECURITY.md](SECURITY.md) and [Privacy / Security](docs/release/privacy-security.md).
