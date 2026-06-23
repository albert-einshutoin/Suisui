# SoloPM Role And Strengths

SoloPM is a Local-first personal AI PM for macOS. Its role is to turn captured work, project documents, due dates, and local context into reviewable next actions without moving ownership away from the user.

## Strengths

- Local-first data boundary: projects, tasks, settings, and release evidence stay on the Mac unless the user chooses a provider or connector.
- review-before-execution: AI and MCP flows propose task changes, schedule blocks, artifacts, and plans before write actions run.
- MCP-ready extensibility: external tools can be connected through explicit registration, audit history, structured content validation, and paid execution boundaries.
- complete task lifecycle harness: task creation, content editing, status movement, automation review, approved local execution, and destructive delete confirmation are tracked as one E2E contract so product-critical CRUD does not regress silently.
- VoiceOver-aware workflow: source anchors, pseudo VoiceOver focus-path checks, runtime AX smoke, and manual VoiceOver evidence are separated so accessibility regressions are caught early without pretending automation replaces assistive-technology review.
- document-scoped automation: selected docs can produce task drafts, status/due-date proposals, release notes, PR plans, and draft artifacts with document reasons and approval gates.
- complete document deliverable harness: document-scoped automation must prove preparation checklists, draft artifacts, release notes, and PR plans independently before the E2E harness passes; external-source-only context stays excluded until connector-specific approval exists.
- task automation selection reasons: priority and due-date tradeoffs are carried into review-only LLM plans so the user can inspect why work was selected before approving any update. High-priority undated work stays ahead of lower-priority future work, while tasks outside the configured lookahead window are held back from LLM review. Overdue or due-today work can use a separate urgent review cooldown so daily automation does not hide urgent tasks, but the extra provider call only includes the urgent candidates.
- Practical solo operator cockpit: Today, Inbox, Project Board, Done analytics, Settings, and local assistant affordances stay close to daily execution rather than becoming a generic chat surface.

## Product Boundary

SoloPM should not silently execute destructive actions, leak provider keys, or treat generated summaries as proof of manual checks. High-risk work stays explicit: review the plan, inspect the documents used, approve the action, then run it.
