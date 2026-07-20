# AI Billing Model: Managed AI Alongside Obsidian-Style Plans

Status: design proposal. Drafted 2026-07-07.

This document extends `docs/product/pricing.md`. That document defines the infrastructure plans (Free / Sync / Pro / Founder / Team) and keeps the principle "Suisui should not pay for general LLM inference … unless a later hosted AI plan is explicitly introduced." This document is that explicit introduction: it defines how a managed AI offering is packaged, metered, and kept profitable without breaking the local-first and BYOK promises.

## Two-Axis Model

Billing separates into two orthogonal axes because they have different cost structures:

| Axis | Nature | Products |
| --- | --- | --- |
| Infrastructure | Fixed cost, per-seat | Free / Sync / Pro / Team (unchanged from `pricing.md`) |
| AI usage | Variable cost, metered | BYOK (free on every plan, forever) / Managed AI (credit-based) |

Rules:

- BYOK stays free on every plan. Managed AI never becomes a requirement for core functionality.
- Managed AI is an add-on available on any paid plan, plus small included credit allotments to create the habit.
- AI credits are denominated in currency (cents), not tokens. Model prices change; the rate card converts credits to tokens at request time. The existing ledger already records `cost_cents`, so no schema change is needed.

## Plan Matrix (proposal)

| Plan | Price | Infrastructure (axis 1) | AI (axis 2) |
| --- | ---: | --- | --- |
| Free | $0 | Local only | BYOK only |
| Sync | $5/mo | E2EE sync (iOS/Web/macOS), history | BYOK + small trial credits |
| Pro | $10/mo | + Cloud Relay, Hosted MCP, PC-off capture | BYOK + ~$3/mo included credits |
| Managed AI add-on | +$8–10/mo | — | Larger credit allotment (e.g. ~$6/mo at cost) + overage: metered or auto-degrade |
| Team | $15/seat/mo | Shared spaces, RBAC, org audit | Seat credits pooled per organization + admin budget caps |

Overage policy is a product decision, not only a billing one: prefer "auto mode locks to the economy tier when credits run out" over hard cutoffs, with metered overage as an opt-in.

## Existing Implementation Assets

Most of the client-side plumbing already exists and should be reused, not rebuilt:

| Concern | Existing asset |
| --- | --- |
| Billing modes | `AssistantQueueCostBillingMode`: `localOnly` / `userProviderBilled` / `suisuiManaged` |
| Pre-run cost estimate | `AssistantQueueCostRateCard` + `AssistantQueueCostPreview` (approval gate blocks `wouldExceedLimit`) |
| Rate card delivery | `ManagedAICostRateCardConfiguration` — injected at runtime so price changes never require an app release. Extend from environment variables to a signed remote JSON catalog. |
| Token measurement | All LLM providers parse `input_tokens` / `output_tokens` from responses (`measured` / `estimated` / `unknown` states) |
| Usage ledger | `managed_ai_usage_ledger` (SQLite) with idempotent digests (double-charge protection) and daily/monthly/workspace aggregates |
| Spending caps | Per-run / daily / monthly / workspace caps in `ManagedAIBillingSettings`, enforced before execution, already exposed in Settings |
| Entitlements | `FeatureGate` model from `pricing.md` — add `managedAI` plus a credit-balance entitlement |

## What Must Be Built

1. **Model catalog metadata** — `LLMProviderCatalogEntry` gains `inputCentsPerMillion`, `outputCentsPerMillion`, `contextWindowTokens`, and capability tags (fast / cheap / accurate). Prerequisite for both the picker and auto mode.
2. **Multi-model picker + auto mode** — user selects a model or `auto` per workspace.
3. **Cloud Relay metering (authoritative)** — managed AI calls providers with Suisui-owned keys, so the key must live server-side (Cloud Relay, already a Pro feature in `pricing.md`) and the relay must meter usage server-side. The client ledger stays as the user-facing display; the relay record is the billing source of truth (client-only metering is tamperable).
4. **Stripe integration** — subscription (seats) + metered usage item (overage); organization invoicing for Team.
5. **Profitability reporting** — ledger/relay aggregates grouped by model and period vs. plan revenue; margin dashboard for operations.
6. **Org budget controls** — the existing four-tier caps re-scoped to organization budgets for Team admins.

## Auto Mode and Unit Economics

Auto routing is not a convenience feature; it is what makes included credits affordable. `VoiceCommandRouter` already classifies intents, so routing is an intent-to-tier map:

| Intent class | Tier | Example models (rate-card driven, not hardcoded) |
| --- | --- | --- |
| Inbox triage, classification, short voice answers | Economy | Haiku-class |
| Task/plan generation (default) | Standard | Sonnet-class |
| Complex project planning, long document briefs | Premium | Opus-class |

Adjustment rules: escalate one tier when router confidence is low or schema validation fails; degrade to economy when remaining credits are low (reuses the caps machinery).

Worked example (Anthropic list prices as of 2026-06; all provider prices live in the injected rate card):

- One plan generation, Sonnet-class, ~3K input / ~0.8K output tokens ≈ **$0.021**
- The same operation routed to Haiku-class ≈ **$0.003** (~1/7)
- Prompt caching: Suisui's prompt prefix (system + tool schema + knowledge frames) is stable, so cache reads price input at ~0.1x; with ~70% of input cached, input cost drops ~65%

Consequence: $3 of included credits covers roughly 150 Sonnet-class operations, or on the order of 1,000 operations under auto routing with caching. A heavy user doing 500 Sonnet-class operations/month would cost ~$10.5 — unprofitable on a $10 plan — which is why auto + caching are launch requirements for managed AI, not follow-ups.

## Data Policy: E2EE Three-Layer Model

Managed AI, the Web app, and Team sharing all interact with the E2EE sync boundary (`docs/sync/cloud-sync-foundation.md`). The policy is three explicit layers:

| Layer | Encryption | Rationale |
| --- | --- | --- |
| Personal vault (projects, tasks, knowledge) | E2EE — server can never read | The Obsidian-model promise; already the direction of `EncryptedSyncPayload` / `CloudSyncDataPolicy` |
| Team shared spaces | Organization-readable (server-side, org boundary) | Per-member key wrapping is heavy crypto engineering, and enterprise buyers typically require server-side audit/DLP. Personal data never migrates into a shared space implicitly. |
| AI requests | Explicit-send only | An AI call sends exactly the user-selected/retrieved fragments (redacted) to the relay; it is not derived from the encrypted vault server-side. Consistent with `CloudSyncExcludedPlaintextClass` and SECURITY.md's "explicit user-approved provider requests" boundary. |

The Web app must decrypt personal-vault data client-side (WebCrypto) to preserve layer 1. This is the main cost of keeping the Obsidian-style E2EE promise while still shipping a web surface, and it should be decided before Web/Team/AI implementation to avoid rework.

## Rollout Phases (profitability-risk ascending)

1. **Phase A — Sync revenue, BYOK visibility.** Launch Sync ($5) with E2EE + iOS/Web. AI stays BYOK (zero inference cost risk). Ship the model picker, auto mode, and "your API spend this month" visibility for BYOK users — this validates auto routing and collects real token-shape data for credit sizing.
2. **Phase B — Managed AI add-on.** Size included credits from Phase A data. Ship Cloud Relay key custody + server-side metering + Stripe metered billing for individuals.
3. **Phase C — Team.** Shared spaces (organization-readable layer), seat-pooled credits, admin budget caps, org invoicing. Matches the Business MVP position in `docs/product/roadmap.md`.

## Open Decisions

- Overage default: auto-degrade to economy tier vs. metered billing vs. hard stop (recommendation: degrade by default, metered opt-in).
- Credit expiry: monthly reset (simple, predictable margin) vs. rollover (customer-friendly, complicates liability accounting). Recommendation: monthly reset with a small rollover cap.
- Whether Sync-tier trial credits are one-time or recurring.
- Which providers the managed tier fronts at launch (fewer providers = simpler rate cards and margin control; BYOK covers the long tail).
- Web client-side crypto scope for layer 1 (full vault vs. task/project subset first).
