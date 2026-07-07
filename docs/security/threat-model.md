# SoloPM Threat Model

Verified: 2026-07-07

This document records what SoloPM protects, where trust boundaries sit, and which existing controls map to which threats. It complements [SECURITY.md](../../SECURITY.md) (policy and reporting) and [docs/sync/cloud-sync-foundation.md](../sync/cloud-sync-foundation.md) (the E2EE sync boundary). It describes the current local-first macOS app plus the planned sync/relay surfaces; it is not a compliance artifact.

## Scope and Assumptions

In scope:

- The macOS app, menu bar extra, CLI, and their local SQLite database.
- Secrets flowing between the app, macOS Keychain, and provider HTTPS endpoints.
- Content that leaves the process: LLM prompts, notifications, TTS, audit rows.
- The planned E2EE sync ledger and hosted MCP relay as designed surfaces.

Out of scope (assumed trusted or handled elsewhere):

- macOS itself, the Keychain implementation, and hardware security.
- A fully compromised user account or root-level malware; SoloPM cannot defend content from an attacker who owns the session.
- Physical attacks beyond casual lock-screen reading.

## Assets

| Asset | Where it lives | Sensitivity |
|---|---|---|
| Task and project content (titles, details, deadlines, workspace paths) | Local SQLite database | Customer/business content; may reference client names and internal plans |
| Knowledge frames and inbox captures (free text, voice transcripts) | Local SQLite database | Highest content sensitivity; users paste anything here |
| Provider API keys and OAuth tokens (LLM, Google Calendar) | macOS Keychain only | Credential material; compromise enables spend and account access |
| Audit logs | Local SQLite database | Metadata about actions; redacted before write |
| Execution receipts and automation plans | Local SQLite database | Reveal what the assistant was allowed to do |
| Release signing / notary / Sparkle keys | Keychain or CI secret store, never the repo | Supply-chain critical |

## Trust Boundaries

1. **Local process boundary.** The app, CLI, and SQLite database run in the user's macOS session. Anything inside this boundary trusts the local user account.
2. **Keychain.** Secrets cross out of process memory only into Keychain items. SQLite settings, UserDefaults, logs, and fixtures must never hold secrets.
3. **LLM providers over HTTPS.** Prompt content (task text the user chose to send) leaves the device to the configured provider. Keys travel only in request headers.
4. **Notification and speech surfaces.** Lock screen, Notification Center, and TTS output are readable by bystanders, so they are count-only or redacted.
5. **External MCP servers and connectors.** User-registered processes with their own environments; treated as semi-trusted executors behind review-before-write.
6. **Future cloud relay / sync backend.** Sees only the encrypted ledger envelope defined in the sync foundation document, never plaintext content or credentials.

## Data Flows Across Boundaries

| Flow | Data | Protection |
|---|---|---|
| App → Keychain | API keys, OAuth tokens | Keychain ACL scoped to the app; never mirrored to SQLite or UserDefaults |
| App → LLM provider | Prompt text, model parameters | HTTPS; key in header only; user chooses what content enters prompts |
| App → LLM provider (workspace Q&A) | User question plus retrieved workspace snippets (task, project, knowledge titles and details) | Explicit user action per question; secret-pattern and local-path redaction on snippets before send; HTTPS with key in header only |
| App → Notification Center | Digest and deadline notifications | Count-only bodies; no titles, paths, or customer names |
| App → TTS / audio out | Spoken summaries | Redaction before synthesis |
| App → audit_logs table | Action metadata | Secret-pattern redaction before insert; parameterized SQL |
| App → sync ledger (planned) | Encrypted payload envelope | XChaCha20-Poly1305 payloads, key IDs only, per the sync foundation doc |
| Sparkle → app | Update artifacts | EdDSA appcast signature verification |

## Threat Actors

- **Bystander / shoulder surfer:** reads the lock screen, a shared screen, or hears TTS output.
- **Local malware or another user process:** reads world-readable files, clipboard, or unencrypted databases in the user session.
- **Network attacker:** intercepts or tampers with provider traffic (mitigated by TLS, no pinning yet).
- **Malicious or compromised LLM response:** attempts prompt-injection to trigger destructive tool calls.
- **Curious cloud operator (future sync/relay):** inspects stored ledger payloads.
- **Supply-chain attacker:** tampers with update feeds or release artifacts.

## Mitigations Mapped to Existing Controls

| Threat | Control in place |
|---|---|
| Credential theft from disk | Keychain-only secret storage; secret-scan gates keep keys out of SQLite, logs, fixtures, and release notes |
| SQL injection via task/knowledge text | Parameterized SQL everywhere (`?` placeholders in all stores; enforced by database parameter-binding tests) |
| Content leaks through side channels | Redaction before TTS, audit logging, and notifications; digest and weekly-review notifications are count-only by design |
| Destructive automation (deletes, sends, pushes) | Review-before-write action plans; MVP safety boundaries in SECURITY.md forbid email/Slack sends, file deletion, and Git push |
| Voice auto-create bypassing review | Opt-in Settings mode limited to one validated low-risk `task.create` per plan; execution goes through the same audited, receipted ActionExecutor as manual review; result is undoable from the voice window; destructive or external writes always stay pending approval |
| Lock-screen exposure | Count-only notification bodies ("N overdue", "N completed this week"); titles and paths stay in the board UI |
| Cloud operator reading synced content | E2EE sync design: `EncryptedSyncPayload` envelope, key IDs instead of key material, no plaintext domain payloads server-side |
| Update tampering | Sparkle EdDSA-signed appcast; signing keys kept out of the repository |
| Audit log poisoning with secrets | Key/token/authorization patterns redacted before audit rows are written |

## Residual Risks

- **No TLS certificate pinning.** Provider traffic relies on the system trust store; a locally installed rogue CA could intercept prompts and keys in transit.
- **Local database unencrypted at rest.** SQLite content is protected only by file permissions and FileVault; malware running as the user can read it directly.
- **Clipboard and screenshot exposure.** Task content copied to the clipboard or captured in screen shares leaves every control above; no clipboard scrubbing exists.
- **Prompt injection.** Review-before-write limits blast radius but a user who approves a poisoned plan still executes it.
- **External MCP servers.** They run with the user's privileges; SoloPM constrains what it asks them to do, not what they can do.

## Review Cadence

Revisit this document whenever a new trust boundary ships (cloud relay, iOS companion, web app), and at minimum once per release phase. Update the "Verified" date on each pass, and record accepted risks here rather than in scattered code comments.
