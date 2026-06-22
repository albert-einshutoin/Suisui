# SoloPM Role And Strengths

SoloPM is a Local-first personal AI PM for macOS. Its role is to turn captured work, project documents, due dates, and local context into reviewable next actions without moving ownership away from the user.

## Strengths

- Local-first data boundary: projects, tasks, settings, and release evidence stay on the Mac unless the user chooses a provider or connector.
- review-before-execution: AI and MCP flows propose task changes, schedule blocks, artifacts, and plans before write actions run.
- MCP-ready extensibility: external tools can be connected through explicit registration, audit history, structured content validation, and paid execution boundaries.
- VoiceOver-aware workflow: source anchors, pseudo VoiceOver focus-path checks, runtime AX smoke, and manual VoiceOver evidence are separated so accessibility regressions are caught early without pretending automation replaces assistive-technology review.
- document-scoped automation: selected docs can produce task drafts, release notes, PR plans, and draft artifacts with document reasons and approval gates.
- Practical solo operator cockpit: Today, Inbox, Project Board, Done analytics, Settings, and local assistant affordances stay close to daily execution rather than becoming a generic chat surface.

## Product Boundary

SoloPM should not silently execute destructive actions, leak provider keys, or treat generated summaries as proof of manual checks. High-risk work stays explicit: review the plan, inspect the documents used, approve the action, then run it.
