# Document-Scoped Automation Contract

Verified: 2026-06-23

## Purpose

Document-scoped automation lets SoloPM use selected app and project context to propose tasks, status changes, preparation work, and draft artifacts. It remains review-first: the user must see which documents were considered, why they were included, and what changes are proposed.

## Scopes

| Scope | Default | Notes |
| --- | --- | --- |
| App docs | Off until selected | Release checklists, coding standards, runbooks, onboarding docs. |
| Project docs | Project opt-in | PRDs, ADRs, task phase docs, specs, issue notes. |
| Task artifacts | Project opt-in | Draft notes, generated files, release notes, task-attached artifacts. |
| External sources | Later connector-specific | GitHub issues, calendars, SaaS docs, and other connector state. |

## Review Summary

Every request should produce a review summary with:

- Documents considered.
- Inclusion reason per document.
- Proposed changes.
- Highest risk level.
- Whether approval is required.

The current default requires review for draft-or-higher outputs. This keeps the first implementation conservative until project-level auto-apply policies are explicit.

## Deliverable Drafts

When selected documents imply file-like deliverables, SoloPM creates reviewable draft specs before any file write. Each draft records:

- Output kind.
- Suggested path.
- Source document IDs.
- Redacted source document previews with title, summary, and inclusion reason.
- Rationale.
- Risk level.
- Approval requirement.

External sources are excluded from source document IDs and source previews until their connector-specific approval flow is implemented. If only external sources are selected, no deliverable draft is created. This keeps GitHub, calendar, SaaS docs, and other remote connector state from silently becoming the basis for local deliverables.

Deliverable source binding is output-specific. Release notes cite release-note or changelog sources, PR plans cite implementation / regression / pull request sources, and draft artifacts cite artifact or Markdown draft sources. User request text can describe the desired work, but it is not treated as source evidence for a specific deliverable. If approved selected documents do not carry a direct deliverable signal, SoloPM falls back to a preparation checklist only. This keeps review evidence useful instead of over-citing unrelated background docs. The LLM review request keeps these source previews inside fenced redacted JSON, so the model has enough approved document context to draft useful artifacts while copied secrets and unapproved external connector previews stay out of provider context.

Project Board also keeps the same source-bound deliverables in review state after a planning request is assembled. The Task inspector can show the draft output title, suggested path, rationale, and redacted source document previews before the user runs any approved task automation. This makes the provider payload auditable in the product UI instead of leaving source evidence only inside logs or test fixtures.

## Proposed Output Kinds

The Pro tool flow can propose:

- Task drafts.
- Status changes.
- Due-date changes.
- Preparation checklists.
- Draft artifacts.
- Release notes.
- Pull request plans.

These are proposals, not surprise execution. Write-like changes should be represented as Action Plan actions or pending automation requests before they mutate local state.

## Context Strategies

SoloPM can choose where document context is processed:

| Strategy | Boundary | Use |
| --- | --- | --- |
| Local FTS | Local index | Fast keyword retrieval from local text. |
| Local embeddings | Local vector index | Semantic retrieval without provider-side storage. |
| Provider prompt context | Provider request | Explicitly selected snippets are attached to a BYOK provider request. |

Provider prompt context must only include selected, redacted context. Raw secrets, local-only file paths, and unapproved documents stay out of provider prompts and sync plaintext.
