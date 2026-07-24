# Suisui Threat Model

Verified: 2026-07-24

This document records what Suisui protects, where trust boundaries sit, and which existing controls map to which threats. It complements [SECURITY.md](../../SECURITY.md) (policy and reporting) and [docs/sync/cloud-sync-foundation.md](../sync/cloud-sync-foundation.md) (the E2EE sync boundary). It describes the current local-first macOS app plus the planned sync/relay surfaces; it is not a compliance artifact.

## Scope and Assumptions

In scope:

- The macOS app, menu bar extra, CLI, and their local SQLite database.
- Secrets flowing between the app, macOS Keychain, and provider HTTPS endpoints.
- Content that leaves the process: LLM prompts, notifications, TTS, audit rows.
- The planned E2EE sync ledger and hosted MCP relay as designed surfaces.

Out of scope (assumed trusted or handled elsewhere):

- macOS itself, the Keychain implementation, and hardware security.
- A fully compromised user account or root-level malware; Suisui cannot defend content from an attacker who owns the session.
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
7. **Codex App Server child process.** For Codex Local, the user-selected executable owns ChatGPT authentication and its credential store. Suisui communicates only over a dedicated stdio JSON-RPC channel and never reads, copies, logs, or syncs `~/.codex/auth.json` or token fields.

## Data Flows Across Boundaries

| Flow | Data | Protection |
|---|---|---|
| App → Keychain | API keys, OAuth tokens | Keychain ACL scoped to the app; never mirrored to SQLite or UserDefaults |
| App → LLM provider | Prompt text, model parameters | HTTPS; key in header only; user chooses what content enters prompts |
| App → LLM provider (workspace Q&A) | User question plus retrieved workspace snippets (task, project, knowledge titles and details) | Explicit user action per question; secret-pattern and local-path redaction on snippets before send; HTTPS with key in header only |
| App → Notification Center | Digest and deadline notifications | Count-only bodies; no titles, paths, or customer names |
| App → TTS / audio out | Spoken summaries | Redaction before synthesis |
| App → audit_logs table | Action metadata | Secret-pattern redaction before insert; parameterized SQL |
| Review UI → ActionExecutor → write tool | Canonical reviewed plan, enabled action IDs, typed output references, execution policy, short-lived approval envelope | SHA-256 binding over canonical JSON; session/plan/expiry validation; persistent single-use nonce claim; output references resolved only from prior successful actions; schema validation repeated after resolution; each write tool receives an action/tool/resolved-arguments authorization |
| Write tool → Calendar/Reminders/Notifications/filesystem | Approved external mutation plus a digest-only idempotency identity | A SQLite journal claims each item before the external call. External success followed by local persistence failure becomes `unknown`; automatic retry is blocked until reconciliation. Files use exclusive create semantics. |
| App → sync ledger (planned) | Encrypted payload envelope | XChaCha20-Poly1305 payloads, key IDs only, per the sync foundation doc |
| Sparkle → app | Update artifacts | EdDSA appcast signature verification |
| App → local Codex App Server | Explicit planning prompt, model selection, typed account/readiness state | User approval bound to resolved path/device/inode/mtime/size, streaming SHA-256, signing identifier, Team ID, designated requirement, and the Apple-anchored production requirement result; the same identity is rechecked before `--version` and immediately before App Server launch; Stable accepts only signing identifier `codex` from OpenAI Team ID `2DC432GLL2` under an Apple Developer ID Application chain; Developer Mode is required for unsigned/custom executables and disabling it revokes that approval; Personal Preview exact-version allowlist; allowlisted child environment; short-lived process and scratch workspace per request; shell/file/web/MCP features disabled before initialize; approval or tool lifecycle interrupts the turn and fails closed |

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
| Approval replay or post-approval mutation | `ApprovedExecution` binds the session, plan, action order, tools, risk, enabled set, arguments, typed dependencies, and execution policy. SQLite atomically claims its nonce before execution and never permits reuse after success, failure, crash, or restart. Write tools verify their action/tool/resolved-argument digest instead of accepting a non-nil token. |
| Dependency substitution after review | Implicit project/task dependencies become typed action-output references before review. Resolution can read only prior successful action output, records digest-only evidence, and must pass the target tool schema immediately before execution. |
| Duplicate external resources after an ambiguous failure | Calendar, Reminder, Notification, and filesystem creates use a persistent per-action/per-item idempotency key. `succeeded` returns its saved result, `failed_before_side_effect` alone is retryable, and `started` records recovered after restart become `unknown` rather than being replayed. |
| Voice auto-create bypassing review | Opt-in Settings mode limited to one validated low-risk `task.create` per plan; execution goes through the same audited, receipted ActionExecutor as manual review; result is undoable from the voice window; destructive or external writes always stay pending approval |
| Lock-screen exposure | Count-only notification bodies ("N overdue", "N completed this week"); titles and paths stay in the board UI |
| Cloud operator reading synced content | E2EE sync design: `EncryptedSyncPayload` envelope, key IDs instead of key material, no plaintext domain payloads server-side |
| Update tampering | Sparkle EdDSA-signed appcast; signing keys kept out of the repository |
| Audit log poisoning with secrets | Key/token/authorization patterns redacted before audit rows are written |
| Codex credential duplication | Production login types expose browser/device login only; no token-injection type; Suisui rejects an executable path targeting `auth.json` and stores no account email |
| Codex executable substitution | Approval and both process launch paths compare streaming SHA-256 plus macOS signing identity. Stable compiles and evaluates an Apple-anchored Developer ID requirement that pins OpenAI Team ID `2DC432GLL2` and identifier `codex`; matching metadata strings without that certificate chain are rejected. Security.framework path validation is bracketed by descriptor-identity checks so signature evidence is discarded if the selected path changes during validation. Same-size edits, restored mtimes, symlink retargets, signature changes, and package-manager replacements fail closed until explicit reapproval. |
| Malicious App Server tool request | Command, file-change, permission, web, MCP, and dynamic-tool lifecycle messages are never approved; the turn is interrupted and planning fails |
| Codex workspace policy denial | Account errors naming organization/workspace policy are mapped to a stable administrator-disabled state instead of triggering repeated login |

## Residual Risks

- **No TLS certificate pinning.** Provider traffic relies on the system trust store; a locally installed rogue CA could intercept prompts and keys in transit.
- **Local database unencrypted at rest.** SQLite content is protected only by file permissions and FileVault; malware running as the user can read it directly.
- **Clipboard and screenshot exposure.** Task content copied to the clipboard or captured in screen shares leaves every control above; no clipboard scrubbing exists.
- **Prompt injection.** Review-before-write limits blast radius but a user who approves a poisoned plan still executes it.
- **External MCP servers.** They run with the user's privileges; Suisui constrains what it asks them to do, not what they can do.
- **Local child-process TOCTOU.** Hashing uses a streaming file read and launch-time path re-resolution, and the signature is validated immediately before each launch. `Process` cannot execute an already-open file descriptor, so a same-user attacker may still race the final check and `exec`. An immutable Application Support snapshot or descriptor-based launcher would narrow this further. Quarantined downloads remain subject to macOS policy; Suisui does not bypass quarantine.
- **Enterprise compliance identity.** `clientInfo.name` is `suisui`; Enterprise support must not be claimed until OpenAI registers the client or the limitation for unregistered clients in Compliance Logs is documented and accepted.

## Review Cadence

Revisit this document whenever a new trust boundary ships (cloud relay, iOS companion, web app), and at minimum once per release phase. Update the "Verified" date on each pass, and record accepted risks here rather than in scattered code comments.
