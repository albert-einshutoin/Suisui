# Investor-Grade Product Review Loop

Verified: 2026-06-19

Purpose: keep SoloPM release decisions tied to user pull, retention, monetization, and risk. This file is not a marketing narrative; it is a decision log for whether the product is becoming more releasable.

## Current Position

SoloPM is no longer just a mock task board. It now has local SQLite-backed Project/Task CRUD, artifact visibility from real rows, provider catalog boundaries, MCP compliance documentation, paid sync gating, Project/Task inspectors, and deterministic local suggestions.

The product is still not release-complete. Visual evidence, VoiceOver focus order, and full release packaging evidence remain open. Those gaps should stay visible because they directly affect trust.

## Review Matrix

| Area | Problem | User pull | Retention hook | Monetization | Risk | Decision |
| --- | --- | --- | --- | --- | --- | --- |
| Local Project/Task CRUD | Users need a tangible app, not only AI planning docs. | Board/list/overview and inspectors let users create and change real tasks. | Project board and Today can become repeated-use surfaces. | Keep basic local CRUD free. | Without screenshot evidence, UI quality is not fully proven. | Continue hardening; do not add new broad entities yet. |
| Inbox / Voice Capture | Users lose work when capture is slow or unclear. | Inbox triage and Voice Command map capture into reviewable work. | Fast capture gives a daily entry point. | Advanced provider execution can be paid, but capture must remain useful free. | Voice capture must not inject canned data or hide provider errors. | Keep regression tests for no mock transcript and real provider readiness. |
| Provider catalog | BYOK users need OpenAI, Claude, Gemini, Groq, and local OpenCode boundaries. | Settings surfaces selectable providers and not-configured states. | Users return if provider failures are actionable, not mysterious. | BYOK provider setup is OSS value; managed sync/advanced automation can be paid. | API keys must never leak to logs, SQLite, screenshots, or fixtures. | Keep Keychain separation and provider-specific smoke states. |
| MCP compliance | Advanced users want tool execution, but unsafe tool calls damage trust. | Compliance docs and inspector evidence make capability boundaries auditable. | Tool confidence can become a power-user retention hook. | Advanced MCP execution is a plausible Pro feature. | Spec drift can make claims stale. | Keep protocol version and inspector evidence explicit. |
| Sync gate | Users expect paid sync, but mock success would destroy trust. | Free users see upgrade gate before network; Pro without backend sees not configured. | Sync can retain users once multi-device use exists. | This is the clearest paid feature. Settings/Sync now surfaces the Pro value and local-only safety boundary before the toggle. | Premature external SaaS sync expands scope. | Keep external SaaS connectors excluded; build backend only after alpha UX is stable. |
| Project Overview / Inspector UX | Users need to know what to do next after opening a project. | Overview shows tasks/artifacts/timeline/suggestions; inspector centralizes CRUD. | Weekly project review becomes a habit. | Better UX supports conversion, but should not gate core editing. | Visual proof is still missing in this environment. | Keep UI work focused on evidence and accessibility before adding features. |
| Competitor fit | Copying competitors creates a bloated tool. | Benchmark now maps Notion/Todoist/Linear/Motion signals to adopt/defer/reject. | Focused adoption improves repeated workflows. | Pro must sell sync/automation confidence, not generic task boards. | Desk research is not a full hands-on trial. | Use benchmark as scope control, not final market validation. |

## Feature Admission Rules

1. A feature must reduce click count, clarify the next action, improve retention, create a defensible paid boundary, or reduce release risk.
2. If a feature is "nice to have" but does not meet one of those tests, it stays out of Phase 11.
3. AI behavior must be grounded in local data, schema validation, and review-before-apply unless the user explicitly runs a local deterministic action.
4. Paid features must fail closed before external communication when entitlement or backend configuration is missing.
5. OSS value must remain tangible: provider adapters, MCP fixtures/compliance docs, local-first stores, and release scripts should be understandable to outside contributors.

## Release Investor Narrative

Why it can grow:
- SoloPM targets users who already feel overloaded by task tools but still need local trust and AI assistance.
- The capture -> review -> execute loop is narrower than Notion and less team-heavy than Linear.
- BYOK and local-first storage give a trust wedge for technical users.

Why users may pay:
- Sync across devices is a clear paid expansion once the local app is useful.
- Advanced MCP execution and stronger automation evidence can be paid without breaking the free local task app.
- Provider setup remains BYOK-friendly, reducing platform lock-in concerns.

Why it may fail:
- If visual quality and accessibility are not proven, users will not trust the app for daily operations.
- If AI suggestions become opaque or autonomous too early, SoloPM loses its approval-first differentiator.
- If settings/provider complexity dominates the first-run experience, the app will feel like infrastructure rather than a PM tool.

## Next Review Gates

| Gate | Required evidence |
| --- | --- |
| Visual quality | Light/Dark/System screenshots showing sidebar, board card, and inspector without overlap. |
| Accessibility | VoiceOver path from sidebar project -> task card -> inspector edit/save/delete. |
| Paid value | Settings/Sync/MCP surfaces explain Pro value without blocking free CRUD. Sync now shows Pro value and local-only safety before the toggle; MCP Pro value still needs equivalent surface evidence. |
| OSS readiness | README or docs point contributors to provider adapters, MCP compliance, and local stores. |
| Release truthfulness | Release report separates local runtime readiness from signing/notarization/manual evidence. |
