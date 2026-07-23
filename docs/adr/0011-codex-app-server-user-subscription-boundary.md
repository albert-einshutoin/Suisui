# ADR 0011: Codex App Server User-Subscription Boundary

Date: 2026-07-21
Status: Accepted

## Context

Suisui needs an opt-in AI planning path that can use each Mac user's existing ChatGPT Codex entitlement. A ChatGPT subscription is not an OpenAI API balance, and its credentials must not be copied into Suisui. Codex App Server exposes account and planning operations over local stdio while Codex owns login, token persistence, refresh, rate limits, and provider policy.

The app-server is also a coding-agent surface. Suisui's standard voice-task flow must therefore prove that built-in command, file, web, and MCP tools are disabled before a turn starts. A read-only sandbox and `approvalPolicy: never` are defense in depth, not the primary isolation mechanism.

## Decision

Add `codexLocal` as a distinct, user-Mac provider with provider-managed subscription authentication and user-provider billing.

Suisui will:

- Launch one `codex app-server --listen stdio://` child for the current OS-user and workspace boundary.
- Use only the documented JSON-RPC subset needed for account state, model discovery, and ephemeral Action Plan generation.
- Require an explicit approval bound to the executable's resolved path and filesystem identity. A path, symlink target, inode, modification time, or size change invalidates approval before even a version probe can run.
- Accept only Codex `0.144.1` in Personal Preview. A new version requires matching generated-schema fixtures, adversarial protocol tests, and release evidence before it enters the allowlist.
- Let Codex own browser login, token storage, token refresh, workspace policy, and rate-limit accounting.
- Never read or copy `~/.codex/auth.json`, access tokens, refresh tokens, or API keys.
- Keep `codexLocal` unavailable and absent from Settings until the product GO gates in `P11-016` pass.
- Disable built-in tools at process launch, reject any tool lifecycle or approval request, and interrupt the turn fail-closed.
- Record Codex usage as `userProviderBilled`; it is never added to Suisui-managed AI cost.
- Advertise structured output as unavailable for this adapter until the dynamic per-tool `arguments` contract has a Codex-compatible strict schema. Codex 0.144.1 exposes `outputSchema`, but sending the current Action Plan schema fails the live turn; Personal Preview therefore keeps prompt-requested JSON plus independent `ActionPlanResponseParser` validation rather than claiming a capability that is not operational.
- Treat primary rate-limit exhaustion as provider readiness, so no planning thread starts while usage is exhausted.
- Separate a Suisui disconnect (revoking local execution approval) from Codex logout. Logout is available only for a verified ChatGPT account and requires confirmation that it changes Codex-managed state on the Mac.

The tool-free profile is the mandatory default for Personal Preview voice-task planning, not a permanent claim that Codex can never delegate work. A future task-bound delegation feature must use a separate capability profile, threat model, approval contract, receipt type, and release gate; it must not widen this profile in place.

## Options Considered

### Dedicated local Codex App Server provider — Accepted

- Preserves the user's Codex-owned login and subscription boundary.
- Keeps credentials out of Suisui and enables typed account/readiness reporting.
- Requires version compatibility, subprocess hardening, and strict tool isolation.

### Treat Codex as an OpenAI API-key provider — Rejected

- ChatGPT subscriptions and OpenAI API billing are separate products.
- This would misrepresent authentication, quota, receipts, and user expectations.

### Extract Codex credentials and call services directly — Rejected

- Couples Suisui to private credential formats and expands secret exposure.
- Breaks the rule that Codex alone owns persistence and refresh.

### Relay the user's ChatGPT session through Suisui cloud — Rejected

- Requires Suisui to custody or proxy user credentials and obscures the local execution boundary.
- Cannot truthfully provide the same behavior while the user's Mac is offline.

## Consequences

- Positive: users can opt into their own Codex entitlement without entering an API key into Suisui.
- Positive: API-key, local-runtime, provider-subscription, and Suisui-managed billing remain explicit domain concepts.
- Positive: the boundary is useful to OSS contributors implementing other provider-managed local adapters.
- Negative: Codex CLI installation, supported-version checks, login state, workspace policy, and local process health become readiness dependencies.
- Negative: Enterprise support remains gated on OpenAI client identification and administrator policy behavior.
- Fallback: if tool isolation cannot be proven for a supported Codex version, the provider stays unavailable in standard Settings and may only be considered for an explicit Developer Mode coding workflow.

## Links

- Phase task: `tasks/Phase11-ProviderSyncUXProductization.md#p11-016-codex-app-server-user-subscription-provider`
- Implementation plan: `docs/superpowers/plans/2026-07-21-codex-app-server-subscription-provider.md`
- Stable hardening follow-up: https://github.com/albert-einshutoin/Suisui/issues/343
- Provider catalog: `Sources/SuisuiCore/Planning/LLMProviderCatalog.swift`
- Codex App Server protocol: https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md
