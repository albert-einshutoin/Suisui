# SoloPM

SoloPM is a macOS-first personal PM app that turns voice or text into projects, tasks, calendar events, reminders, notifications, and local work artifacts after user review.

![SoloPM public alpha preview](docs/assets/screenshots/solopm-alpha-preview.svg)

## Public Alpha

SoloPM is preparing its first public alpha. The current build is intended for local-first evaluation by individual developers and makers who want a voice-first workflow for project planning and deadline follow-up.

The product specification lives in [docs/README.md](docs/README.md), the technical baseline lives in [docs/tech_stack.md](docs/tech_stack.md), and the release runbook lives in [docs/release/checklist.md](docs/release/checklist.md).

## MVP Scope

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

## Known Limitations

- External MCP servers are not part of the public alpha runtime.
- SaaS connectors such as GitHub, Gmail, Slack, Google Drive, and Notion are not enabled.
- Full RAG / WeKnora-style knowledge indexing is out of scope for alpha.
- Team, cloud sync, and shared workspace features are not implemented.
- Release signing and notarization require a Developer ID Application certificate and Apple notary profile on the release machine.
- Sparkle update checks require a signed appcast and Sparkle EdDSA key stored in Keychain.

## Development

SoloPM follows Gitflow and TDD. Work should start from `develop` using a feature branch:

```sh
git checkout develop
git checkout -b feature/phaseN-short-name
```

Local verification:

```sh
./scripts/ci.sh
./script/build_and_run.sh --verify
swift build --product solopm-cli
.build/debug/solopm-cli --help
```

`./scripts/ci.sh` is the shared non-GUI verification entrypoint for local development and GitHub Actions. `./script/build_and_run.sh --verify` additionally launches the app and is intended for local macOS UI smoke checks.

Release verification starts from the [Release Checklist](docs/release/checklist.md).

## Release Checklist

The public alpha release order is test, build, sign, notarize, package, checksum, appcast, tag, and release notes. The full checklist, rollback path, and known issues template are in [docs/release/checklist.md](docs/release/checklist.md).

## Security

API keys and provider tokens must be stored in macOS Keychain. Secrets must not be written to logs, SQLite settings, UserDefaults, fixtures, screenshots, or crash reports.

See [SECURITY.md](SECURITY.md) and [Privacy / Security](docs/release/privacy-security.md).
