# Security Policy

SoloPM is local-first and review-before-write. The MVP must avoid dangerous operations by default.

## Secret Handling

- Store API keys and provider tokens in macOS Keychain.
- Do not store secrets in SQLite settings, UserDefaults, logs, fixtures, screenshots, or crash reports.
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

## Reporting

This project is not yet in public alpha. Until a public security contact is published, report security issues privately to the repository owner.

