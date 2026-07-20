# Security Policy

Suisui is local-first and review-before-write. The MVP must avoid dangerous operations by default.

## Supported Versions

| Version | Supported |
|---|---|
| public alpha | Security fixes accepted |
| pre-alpha branches | Best effort only |

## secret handling

- Store API keys and provider tokens in macOS Keychain.
- Store Developer ID certificates, notary credentials, and Sparkle private update keys in Keychain or a CI secret store.
- Do not store secrets in SQLite settings, UserDefaults, logs, fixtures, screenshots, crash reports, appcast files, or release notes.
- Redact keys and values containing `api_key`, `token`, `authorization`, `secret`, `password`, or bearer-style credentials before audit logging.

## MVP Safety Boundaries

The MVP must not implement:

- automatic email sending
- automatic Slack posting
- file deletion
- existing file overwrite
- Git push
- Calendar / Reminder deletion
- unapproved full-folder scans

Write operations must go through a review and approval flow.

## LLM And Local Data

Suisui should make the LLM send context inspectable before execution. Local audit logs remain local. The app must not upload local files, secrets, transcripts, or project data except through explicit user-approved provider requests.

## Reporting

Use GitHub Security Advisory when the repository is public. Until the public advisory channel is enabled, report security issues privately to the repository owner and do not disclose exploit details in public issues.
