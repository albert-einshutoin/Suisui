# Cursor / Notion Competitive Response

Date: 2026-06-25

Source: https://cursor.com/ja/blog/notion

## Threat Summary

Cursor announced that Notion can delegate work directly to Cursor from Notion docs, threads, and database Issues. The article says Cursor can take work through planning, building, testing, and verification before PR creation, and that Notion integrated this through Cursor SDK in a matter of weeks.

The strongest competitive signal is not "Notion has AI." It is that team workspaces are becoming agent launch surfaces. The workspace owns the context, the agent owns execution infrastructure, and the user expects live progress rather than a static task list.

Important details from the announcement:

- Notion can tag or assign work to Cursor from docs, threads, and database Issues.
- A run can include prompt, selected repository, model, optional MCP servers, and automatic PR creation settings.
- Follow-up messages create additional runs, and progress streams over SSE with resume support.
- Remote MCP gives the agent scoped workspace context instead of forcing blind coding.
- Notion treats Cursor as the agent engine while Notion remains the user-facing context surface.

## Suisui Counter-Position

Suisui should not try to out-Notion Notion or rebuild Cursor's coding-agent infrastructure. The stronger lane is:

- Local-first personal AI PM instead of team workspace automation.
- VoiceOver task listing as a first-class workflow, not a secondary accessibility pass.
- review-before-execution for task, document, provider, and external agent actions.
- Document-scoped automation with draft-only deliverables and explicit source reasons.
- Provider-neutral and MCP-ready, but scoped, redacted, and approval-gated.
- Mac-native Keychain, permissions, and release evidence as product trust signals.

The competitive response is to make Suisui the fastest private place to decide what should be delegated, package the work safely, and verify the result. External coding agents can be execution engines; Suisui should own personal context, prioritization, due dates, evidence, accessibility, and approval.

## Acceleration Lane

The next acceleration should be implemented as Issue seeds under Phase15-17, not as a new Phase.

| Lane | Product outcome | Why now |
| --- | --- | --- |
| Agent work request handoff | Convert selected tasks/docs/projects into a redacted external-agent work packet with acceptance criteria and verification commands. | Notion/Cursor makes assignment from a workspace table normal. Suisui needs a local-first equivalent that does not auto-write or leak secrets. |
| remote MCP context pack | Generate an explicit MCP scope for selected Suisui context, with allowlisted servers, expiry, and read/write boundary. | Cursor/Notion highlights remote MCP as the context layer. Suisui already has MCP foundations; it should expose scoped packs rather than broad workspace access. |
| streaming progress and resumable runs | Track external agent run events, last cursor, resumed state, failure reason, and redacted logs. | Users will expect live progress and resumability once agent work is delegated. |
| VoiceOver task listing agent queue | Make task listing the primary queue for work ready to review, hand off, execute, or verify. | Suisui's accessibility-first task model is a differentiator against workspace-first competitors. |
| Verification-before-handoff gate | Every handoff packet includes tests, artifacts, rollback, and "do not auto-merge/auto-push" policy. | Suisui should win on safe execution and proof, not raw autonomy. |
| Competitive launch messaging | Explain Suisui as private personal PM + safe delegation, not a generic Notion clone. | Product-out needs clear positioning before Public Alpha. |

## Immediate Issue Order

1. CN-001 Cursor/Notion response battlecard
2. CN-002 Agent work request handoff packet
3. CN-003 Remote MCP context pack
4. CN-004 Streaming progress and resumable run log
5. CN-005 VoiceOver-first agent queue
6. CN-006 Verification-before-handoff gate
7. CN-007 Competitive launch messaging update

## Product Bar

- The user can select a Suisui task or project and create a reviewed agent work request without exposing secrets.
- The work request carries task title, redacted detail, source documents, due date, priority, target repo/branch when provided, acceptance criteria, verification commands, and non-goals.
- The user sees what context will be shared before any external agent or MCP endpoint receives it.
- The generated request is accessible from VoiceOver task listing and keyboard navigation.
- Run progress can be tracked as redacted, resumable events rather than raw agent logs.
- The product copy explicitly states that automatic remote write, auto-merge, auto-push, and unscoped workspace export are not enabled by default.

## Non-Goals

- Do not build a full coding-agent cloud sandbox in Suisui.
- Do not auto-create PRs, auto-merge, auto-push, or grant broad repo/workspace access by default.
- Do not send raw personal task details, API keys, OAuth tokens, Keychain values, or full document bodies without explicit review.
- Do not make Notion integration the main product lane. Treat Notion/Cursor as a market signal, not the product definition.

## Review Questions

- Does this feature make Suisui faster for one person's real project execution?
- Does it preserve Local-first and review-before-execution boundaries?
- Can a VoiceOver user find the task, inspect the handoff, and approve or cancel?
- Can the result be verified with focused tests or release evidence?
- If an external agent fails, can Suisui explain what happened without leaking raw logs or secrets?
