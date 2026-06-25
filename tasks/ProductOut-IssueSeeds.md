# Product-Out Issue Seeds

この索引は、Phase15-17をGitHub Issueへ起票するための入口です。Phase文書はEpicとして扱い、このファイルの1行を1 Issueの初期本文へ展開します。実装前に各Issueへ `Context`, `Scope`, `Non-goals`, `Implementation Steps`, `Tests First`, `Acceptance Criteria`, `Review Focus` を転記し、対象ファイルと検証コマンドを具体化してください。

Issueの粒度は0.5日から1日を基準にします。1行が1日を超える場合は、domain model、adapter、UI、script、docs、manual evidenceの単位に分割します。

Labels: `phase15`, `phase16`, `phase17`, `product-out`, `release`, `accessibility`, `security`, `provider`, `docs`, `support`, `post-launch`, `ai-secretary`, `tdd`

Suggested order:

1. P15-003 Keychain prompt hardening
2. P15-002 Manual VoiceOver task-listing evidence
3. P15-004 Gemini free-tier live task-list smoke
4. AS-001 Task and document intake
5. AS-002 Document draft studio
6. AS-003 Secretary queue
7. AS-004 Right assistant rail
8. AS-005 Schedule and reminder draft review
9. AS-006 Done recap and follow-up suggestions
10. AS-007 Settings readiness for secretary work
11. CN-001 Cursor/Notion response battlecard
12. CN-002 Agent work request handoff packet
13. CN-003 Remote MCP context pack
14. CN-004 Streaming progress and resumable run log
15. CN-005 VoiceOver-first agent queue
16. P15-001 Product-out gap ledger
17. P15-005 Release machine signing/notarization/Sparkle proof
18. P15-006 Product-out documentation truth sync
19. P15-007 Release notes, known limitations, and rollback plan
20. P15-008 Phase16/17 handoff backlog
21. Phase16 launch operations in P16-001 -> P16-007 order
22. Phase17 post-launch loop in P17-001 -> P17-007 order

## AI Secretary UX Lane

Use these issues to make SoloPM an AI secretary for ordinary tasks, documents, and chores before broadening the external-agent story. Keep the first implementation local-first, review-before-execution, and VoiceOver task listing friendly.

| Issue | Implementable feature | Primary files | Tests first | Acceptance |
| --- | --- | --- | --- | --- |
| AS-001 | Task and document intake | Inbox capture domain, Today command input, document request model, `docs/product/ai-secretary-ux-direction.md` | Source tests require `Inbox intake`, manual capture, voice capture, document request capture, and no unapproved provider call; unit tests cover conversion to task, document draft request, schedule draft, and follow-up | Users can capture ordinary tasks, chores, and document requests from Inbox or Today without choosing the final destination first. |
| AS-002 | Document draft studio | Project detail, document deliverable harness, draft artifact domain, `DocumentScopedAutomationTests` | Tests require article outline, memo, release notes, email draft, PR plan, source preview, duplicate output rejection, and draft-only approval gates | Selected project documents can create inspectable draft artifacts without writing files or sending external updates before review. |
| AS-003 | Secretary queue | Project Board task list, status model, Inbox/Today/Done views, accessibility focus paths | Unit and AX/source tests require captured, drafted, waiting-review, scheduled, and done states with stable ordering and `project-task-list` traversal | The main queue shows secretary work states clearly, including AI-created drafts and follow-ups, from task listing first. |
| AS-004 | Right assistant rail | ProjectBoardView inspector, Today/Inbox/Project/Schedule/Done assistant summaries, UI screenshots | Source/UI tests require next action, reason, risk, evidence link, approval action, and no secret-like content in the rail | The selected task, project, document draft, schedule proposal, or done recap always shows what the assistant recommends and why. |
| AS-005 | Schedule and reminder draft review | Schedule draft model, Calendar/Reminder adapters, permission readiness, Keychain/OAuth docs | Unit tests require schedule block proposals, reminder proposals, skip reasons, OAuth/API-key distinction, and approval before external write | SoloPM can propose calendar and reminder changes while keeping macOS prompts and external writes explicit. |
| AS-006 | Done recap and follow-up suggestions | Done analytics, completion history, recap generator, follow-up task proposal domain | Tests require completed-task sources, generated recap, follow-up suggestions, no manual-evidence claims, and no raw provider response persistence | Completed work becomes a reviewable daily or weekly recap with follow-up suggestions tied to source tasks. |
| AS-007 | Settings readiness for secretary work | Settings Overview/AI/MCP/Sync/Privacy views, provider/STT/TTS/Calendar/Reminder readiness models | Source/UI tests require provider, STT, TTS, Calendar, Reminder, MCP, notifications, privacy, data location, and Keychain prompt explanation | Settings explains which secretary capabilities are ready, blocked, skipped, or need approval without leaking secrets. |

## Cursor/Notion Acceleration Lane

Use these issues to respond to the 2026-06-25 Cursor/Notion launch without creating another Phase. Keep them attached to Phase15 unless the issue explicitly needs Phase16 onboarding or Phase17 post-launch learning.

| Issue | Implementable feature | Primary files | Tests first | Acceptance |
| --- | --- | --- | --- | --- |
| CN-001 | Cursor/Notion response battlecard | `docs/product/cursor-notion-competitive-response.md`, `docs/product/role-and-strengths.md`, `docs/product/competitor-benchmark.md` | `QualitySourceContractTests` requires source URL, threat summary, SoloPM counter-position, and acceleration lane | Product, release, and issue planning clearly explain how SoloPM differs from Notion+Cursor: local-first personal PM, VoiceOver task listing, review-before-execution, and document-scoped automation. |
| CN-002 | Agent work request handoff packet | Project/task automation domain, document deliverable harness, export UI, `docs/sync/solopm-harness.md` | Unit tests require selected task/doc/project context, acceptance criteria, target repo/branch, redacted prompt, verification commands, and approval boundary; security tests reject secrets/raw provider keys | A user can turn selected SoloPM tasks into a reviewed external-agent work packet without granting automatic write/PR authority. |
| CN-003 | Remote MCP context pack | MCP registry, selected document/task context, hosted relay docs, `docs/mcp-compliance.md` | Contract tests require MCP server allowlist, selected scope, redaction, expiry, and read/write boundary; fixture tests reject unscoped workspace export | SoloPM can generate a small, explicit MCP context pack for an external coding agent while preserving local-first and review-only defaults. |
| CN-004 | Streaming progress and resumable run log | Harness run history, external agent run model, sync payload, UI progress surface | Unit tests require run id, event cursor, last event replay, failed/resumed states, redacted logs, and no raw token persistence | External agent progress can be shown as a resumable run log, matching the competitor expectation of live progress without depending on their infrastructure. |
| CN-005 | VoiceOver-first agent queue | Project Board task list, accessibility focus path docs, issue seed export, onboarding docs | AX/source tests require `project-task-list`, task title, due/priority, handoff status, review action, and keyboard/VoiceOver traversal order | The main queue for agent work is usable from VoiceOver task listing first, not hidden behind a developer-only command surface. |
| CN-006 | Verification-before-handoff gate | `SoloPMHarness`, release readiness scripts, generated work packet schema | Tests require focused verifier commands, expected artifacts, rollback note, and explicit "do not auto-merge/auto-push" policy before export | Every agent handoff packet includes how to prove success before PR/merge and keeps destructive or remote writes approval-gated. |
| CN-007 | Competitive launch messaging update | README, Public Alpha notes, release notes, product role docs | Source tests require Notion/Cursor comparison, local-first boundary, personal PM scope, and honest non-goals | Public Alpha messaging acknowledges the market move and explains why SoloPM focuses on private individual project execution rather than team workspace coding automation. |

## Phase 15 Issue Seeds

| Issue | Implementable feature | Primary files | Tests first | Acceptance |
| --- | --- | --- | --- | --- |
| P15-001 | Product-out gap ledger | `docs/release/product-out-gap-ledger.md`, `script/release_readiness_report.sh`, `script/quality_status_report.sh`, `docs/release/checklist.md` | `ReleasePipelineTests` fixture for release-candidate source commit, stale evidence, and blocker/accepted-risk/deferred classification | Current release-candidate source commit, automated evidence, manual evidence, release-machine evidence, blockers, accepted risks, and deferred work are visible in one ledger. |
| P15-002 | Manual VoiceOver task-listing evidence | `docs/release/evidence/accessibility-voiceover.md`, `script/prepare_voiceover_review_candidate.sh`, `script/create_voiceover_evidence.sh`, `docs/quality/accessibility-focus-paths.md` | `QualitySourceContractTests` requires `task listing`, `project-task-list`, and `taskList` in worksheet/evidence routing; `ReleasePipelineTests` rejects stale/manual placeholder evidence | Current manual VoiceOver evidence proves task list -> task card -> inline composer -> status controls -> inspector -> delete confirmation -> approved execution receipt. |
| P15-003 | Keychain prompt hardening | Keychain adapter, AI provider settings view model, Google Calendar readiness, MCP credential storage, `docs/release/privacy-security.md` | Fake Keychain read-count tests, readiness error redaction tests, doc/source tests distinguishing Google OAuth from API keys, security tests preventing UserDefaults/SQLite secret caching | Normal Project Board/task operations do not trigger repeated macOS Keychain prompts; required first-run/key-update/OAuth prompts remain explicit and safe. |
| P15-004 | Gemini free-tier live task-list smoke | Gemini provider adapter, provider smoke script, runtime task-list smoke, release readiness report | Source test requires explicit `SOLOPM_GEMINI_LIVE_SMOKE=1`; fixture tests distinguish pass, quota skip, 503 skip, network skip, validation failure | Gemini free-tier key is used only when configured and explicitly enabled; task listing smoke passes or records a non-fake skip reason without writing data. |
| P15-005 | Release machine signing/notarization/Sparkle proof | `script/check_release_machine_local_doctor.sh`, `script/sign_app.sh`, `script/notarize_app.sh`, `script/package_release.sh`, `script/generate_appcast.sh`, `script/verify_release_environment.sh`, `packaging/release-evidence.json` | Release fixture tests reject unsigned, unstapled, placeholder Sparkle, checksum mismatch, source/build/version mismatch | Signed, notarized, stapled app, DMG/zip, checksum, appcast, Gatekeeper, clean install, and Launch at Login proof are recorded for the candidate. |
| P15-006 | Product-out documentation truth sync | `README.md`, `docs/release/public-alpha.md`, `docs/product/role-and-strengths.md`, `docs/release/privacy-security.md`, `docs/release/checklist.md` | Source tests require task listing, review-before-execution, document-scoped automation, VoiceOver-aware workflow, provider skip contract, known limitations, and no secret-like values | User-facing docs describe the current product honestly and do not promise unimplemented SaaS/team/hosted automation. |
| P15-007 | Release notes, known limitations, and rollback plan | `CHANGELOG.md` or release notes doc, `docs/release/checklist.md`, `docs/release/public-alpha.md` | Source tests require version, build, source commit, fixed/changed/known limitations, rollback, verification, and feedback route | Alpha release notes align with the signed artifact, known limitations, accepted risks, rollback path, and support intake. |
| P15-008 | Phase16/17 handoff backlog | `tasks/Phase16-PublicAlphaLaunchOperations.md`, `tasks/Phase17-PostLaunchLearningLoop.md`, `docs/release/product-out-gap-ledger.md` | Source test requires every deferred product-out item to link to P16/P17 and explain why it is not a release blocker | Non-blocking improvements are routed to launch or post-launch work without bloating the release candidate closure. |

## Phase 16 Issue Seeds

| Issue | Implementable feature | Primary files | Tests first | Acceptance |
| --- | --- | --- | --- | --- |
| P16-001 | First-run onboarding | Onboarding domain model, `Sources/SoloPMApp`, Settings replay entry, README/public alpha docs | UserDefaults persistence test, source test for local-first/review-before-execution/task listing/provider setup copy, AX label/hint/keyboard close test | New users can reach task list and task creation quickly; onboarding stores only non-secret state and is VoiceOver/keyboard usable. |
| P16-002 | Permission education | Settings readiness model, permission UI, support runbook, privacy docs | Source tests separate Keychain, OAuth, API key, OS permission; unit tests redact denied/error output | Users can see why a permission is needed, what it unlocks, how to recover, and which safe fallback remains. |
| P16-003 | Redacted diagnostics export | Diagnostics model/export UI, issue templates, support runbook, privacy docs | Unit tests reject API keys, OAuth tokens, bearer tokens, raw task detail, document body; source test forbids automatic upload | Users can create local redacted diagnostics for bug reports without leaking secrets or personal task content. |
| P16-004 | Public alpha release channel | `docs/release/public-alpha.md`, `docs/release/checklist.md`, GitHub Release draft template, README | Source tests require download, checksum, Gatekeeper, Sparkle, known limitations, feedback, rollback, version/build/source consistency | Public Alpha publish checklist and release draft are ready and match the signed artifact and known limitations. |
| P16-005 | Support runbook | `docs/release/support-runbook.md`, `CONTRIBUTING.md`, `SECURITY.md` | Source tests require blocker/bug/question/enhancement/security classification and security reports not routed to public issues | Maintainers can classify reports consistently and escalate security issues safely. |
| P16-006 | OSS contribution path | `CONTRIBUTING.md`, PR template, issue templates, ADR docs | Source tests require TDD, security, privacy, review-before-execution, Keychain handling, provider fake/test double guidance | Alpha users can contribute docs/tests/UI copy safely; provider/secret/MCP changes get stricter review. |
| P16-007 | Product presentation refresh | README screenshots, `docs/assets`, release notes, visual baseline manifest | Source/visual tests require screenshot paths to exist and exclude blank images, secret input screens, and personal data | README/release page communicates the current product with safe, current visuals. |

## Phase 17 Issue Seeds

| Issue | Implementable feature | Primary files | Tests first | Acceptance |
| --- | --- | --- | --- | --- |
| P17-001 | Post-launch issue triage | Issue labels/templates, `docs/release/support-runbook.md`, roadmap doc | Source tests require blocker/bug/question/enhancement/security/manual-evidence/provider/accessibility/docs taxonomy and blocker criteria | Alpha reports are consistently classified and release blockers do not disappear into the backlog. |
| P17-002 | Crash/error triage without secret leakage | Error sanitizer, diagnostics export, support runbook, security tests | Unit tests redact API keys, OAuth tokens, bearer tokens, raw task detail, document body; template tests require reproduction and sanitized logs | Crash/error reports carry enough context to debug without exposing secrets or personal work content. |
| P17-003 | Primary workflow regression intake | `docs/quality/manual-to-automated-regression.md`, runtime smoke scripts, issue template, relevant XCTest suites | Source tests require task listing/create/edit/delete/execute/document deliverable/provider setup routes and proposed test layer fields | User-reported workflow bugs are converted into unit/source/runtime/visual/manual regression work. |
| P17-004 | Usage feedback synthesis and roadmap update | `docs/product/roadmap.md`, product role docs, competitor benchmark, feedback notes | Source tests require VoiceOver task listing, review-before-execution, document automation, provider setup, sync/hosted expansion axes and no secret-like values | Feedback is classified as ship/improve/defer/reject/research with evidence links and no personal task content. |
| P17-005 | Release cadence and patch train | Release cadence doc, checklist, changelog/release notes | Source tests require hotfix/patch/minor alpha criteria and fixed/changed/known limitations/verification sections | Hotfix, patch, and minor alpha releases have clear criteria, regression requirements, and rollback expectations. |
| P17-006 | OSS contribution review loop | PR template, `CONTRIBUTING.md`, ADR process, `SECURITY.md` | Source tests require TDD/manual verification/security/privacy/self review and ADR/design note for provider/Keychain/OAuth/MCP changes | External PRs can be reviewed without weakening secret, provider, or execution boundaries. |
| P17-007 | Provider cost and reliability learning | Provider smoke summary, quality status, roadmap | Security tests ensure provider summaries omit API keys/raw prompts/raw responses; source test classifies Gemini free-tier pass/skip/fail as roadmap input | Provider reliability and cost learning feeds roadmap decisions without wasting free-tier quota or exposing keys. |

## Issue Body Template

```markdown
## Context

## Scope

## Non-goals

## Implementation Steps
- [ ] Add the failing test first.
- [ ] Implement the smallest production change.
- [ ] Update docs/evidence/runbooks that describe the changed behavior.
- [ ] Run focused verification and security checks.

## Tests First
- [ ] 

## Acceptance Criteria
- [ ] 

## Review Focus
- TDD order is visible in the PR.
- No secrets are logged, persisted outside Keychain, or written to evidence.
- Manual-only evidence is not replaced with fake automation.
- VoiceOver/keyboard paths are covered when UI changes.
```
