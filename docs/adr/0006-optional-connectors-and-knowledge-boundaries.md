# ADR 0006: Optional Connectors And Knowledge Boundaries

Date: 2026-06-17
Status: Accepted

## Context

Phase8 and Phase9 add external SaaS connectors and advanced knowledge retrieval. Both areas can easily expand into cloud sync, automatic posting, broad file scanning, or always-on RAG. SoloPM's product boundary remains local-first, approval-first, and BYOK-only for any optional cloud path.

## Decision

Implement SaaS connectors and advanced knowledge retrieval as Core protocols, fake clients, local stores, and approval gates first. Production network adapters can be added later behind the same protocols, but the core app must continue to work without Google, Slack, Notion, WeKnora, sqlite-vec, or cloud embedding services.

## Options Considered

### Core Protocols With Local Fallbacks

- Pros:
  - Keeps tests deterministic and fast.
  - Preserves local-first behavior.
  - Lets production adapters be added without changing Review / Tool safety boundaries.
  - Avoids committing to a hosted knowledge backend.
- Cons:
  - End-to-end OAuth browser flows and real SaaS calls still need adapter work.

### Direct SaaS And RAG Integration

- Pros:
  - Faster path to live integrations in demos.
- Cons:
  - Higher risk of token leakage, unapproved writes, and brittle tests.
  - Makes SoloPM less useful offline.
  - Couples the core app to external service availability.

## Consequences

- Positive:
  - OAuth token material stays in `SecretStore`.
  - Gmail send and Slack automatic posting remain unsupported.
  - Knowledge embedding is opt-in and user-approved.
  - WeKnora is optional and never a core dependency.
- Negative:
  - Real SaaS adapters remain future work.
  - sqlite-vec is represented by a capability/fallback boundary until bundled or installed.
- Follow-up:
  - Add production adapters one connector at a time with connector-specific smoke tests.
  - Add UI wiring for connector health snapshots and Knowledge eval reports.

## Links

- Related task: `tasks/Phase8-SaaSConnectors.md`
- Related task: `tasks/Phase9-KnowledgeAdvanced.md`
