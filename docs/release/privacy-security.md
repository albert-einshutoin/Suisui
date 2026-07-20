# Privacy / Security

Suisui public alpha is local-first. The app is designed so users can inspect the plan before write actions run.

## Local Data

- Projects, tasks, Knowledge Frames, deadlines, and audit logs are local.
- API Key values are stored in Keychain.
- Release credentials, Developer ID certificates, notary credentials, and Sparkle private keys stay in Keychain or a CI secret store.
- Local logs must redact API keys, bearer tokens, authorization headers, passwords, and secret-like values.

## LLM 送信文脈

LLM 送信文脈 is limited to the text needed to generate an Action Plan. The app should keep the generated plan visible before execution, and write actions require approval.

## 送信しない

- Raw Keychain secrets
- Developer ID certificate material
- Sparkle private update keys
- Full local folder contents without explicit user approval
- Hidden files or private project files unrelated to the user request

## 削除しない

- Local files
- Calendar events
- Reminders
- Knowledge Frames
- Audit logs

The public alpha does not include destructive delete tools.

## 自動投稿しない

- Email send
- Slack post
- Git push
- GitHub issue or PR mutation
- External SaaS write actions

The MVP may create drafts or local plans only after review.

## Telemetry

Crash reporting and telemetry are not enabled by default. If telemetry is added later, it must be opt-in and documented before release.
