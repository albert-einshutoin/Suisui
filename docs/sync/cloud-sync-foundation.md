# Cloud Sync Foundation

Verified: 2026-06-21

This document fixes the first Suisui Cloud Sync boundary for Phase 13. The goal is not to implement a production sync backend yet. The goal is to make the shared data model safe enough that iOS, Web, and macOS can later exchange task data without introducing plaintext secrets or ambiguous merge behavior.

## Ledger Shape

Cloud Sync uses an append-only ledger. Each `SyncLedgerEntry` contains:

- `id`, `deviceID`, and `sequence` for per-device ordering.
- `entity.kind` and `entity.id` for Project, Task, safe Settings, or Conversation metadata.
- `operation` for create, update, delete, or recovery.
- `encryptedPayload` as `EncryptedSyncPayload`.
- `parentEntryID` for causal history.
- `mergePolicy` for deterministic conflict handling.
- `redactedAuditSummary` for operator/debug visibility without raw secrets.

The ledger entry intentionally does not accept a raw `SyncDomainPayload`. A caller must provide encrypted payload metadata: algorithm, key id, nonce, ciphertext, and plaintext digest. This keeps the cloud-visible envelope separate from local decrypted domain data.

## E2EE Boundary

The initial encryption envelope is represented by `EncryptedSyncPayload`:

- `algorithm`: currently `xchacha20_poly1305`.
- `keyID`: the local/device/user key reference, not the key material.
- `nonce`: encoded nonce.
- `ciphertext`: encoded encrypted bytes.
- `plaintextDigest`: digest for local integrity and conflict diagnostics.

The Sync backend may store ledger metadata and encrypted payloads. It must not receive provider API keys, MCP raw environment values, OAuth tokens, local file paths, or raw document bodies in plaintext.

## Included Data

`CloudSyncDataPolicy.defaultPersonalSync` currently includes:

- Projects.
- Tasks.
- Safe Settings fields.
- Conversation metadata.

Safe Settings fields are limited to values that help restore UX and routing without granting access:

- Appearance preference.
- Selected LLM provider id.
- Model ids.
- Sync enabled flag.

## Excluded Plaintext Data

These classes are explicitly excluded by `CloudSyncExcludedPlaintextClass`:

- Provider API keys.
- MCP environment secret values.
- OAuth access and refresh tokens.
- Local file paths.
- Raw document bodies.

MCP registrations may sync only redacted descriptors or Keychain references. Provider API keys remain in platform secure storage. Document sync starts with metadata only; raw body and embedding policy must be designed in P13-007.

## Plaintext Guard

`CloudSyncPlaintextGuard` rejects fields that look like:

- API keys, such as `openai_api_key`.
- MCP environment secrets, such as `mcp_env`.
- OAuth tokens, such as `oauth_refresh_token`.

This guard is not a cryptographic control. It is a fail-closed developer guard so future sync exporters cannot accidentally add obvious secret fields to a plaintext manifest.

## Merge Policy

`CloudSyncMergePolicy.defaultPersonalSync` defines the first offline merge behavior:

| Scenario | Resolution |
| --- | --- |
| Offline create without remote row | Append ledger entry |
| Concurrent updates to different fields | Field-wise last writer wins |
| Same-field conflict | Requires review |
| Remote deleted but local update exists | Recover as pending review |

Why: task capture should continue while devices are offline, but destructive or ambiguous results must become reviewable rather than silently overwriting user work.

## Verification

The contract is covered by `CloudSyncFoundationTests`:

- Ledger entries encode encrypted payload metadata without plaintext secrets.
- Sync data policy lists included classes and excluded plaintext classes.
- Plaintext guard rejects provider, MCP, and OAuth secret fields.
- Merge policy covers offline create, update conflict, same-field conflict, and deleted recovery.
