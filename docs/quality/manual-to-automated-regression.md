# Manual to Automated Regression Bridge

This document defines how SoloPM turns manual release findings into future automated regression coverage.

Manual evidence is still required for assistive-technology judgment, competitor hands-on review, and signed release-machine checks. The rule is that a finding discovered manually must not remain manual-only unless the remaining part truly cannot be automated.

## Manual Finding Intake

For every failed or risky manual observation, record these fields in the relevant evidence or follow-up issue before closing the release lane:

| Field | Required content |
| --- | --- |
| Manual lane | Manual VoiceOver, Competitor Hands-On, or Release Machine |
| Evidence source | The file or command that produced the observation |
| User-visible risk | What the user would see or lose |
| manual-only | The part that still requires a human reviewer |
| automation-backlog | The source, runtime, visual, or release test that should catch recurrence |
| Owner test | The XCTest, shell smoke, or evidence verifier that will fail next time |

The action summary points back to this document so temporary `.tmp/` worksheets do not become the only place where follow-up routing is described.

## Failure Note Contract

Manual evidence files that include `## Failure Notes` must use
`Follow-up source/test link` to point at the regression target before the lane is
closed. Valid targets include `Tests/`, `script/`, `docs/product/`,
`docs/quality/`, `tasks/`, or a tracked follow-up issue. `none`, `TBD`,
`pending`, or a blank value is only valid when `Blocker observed` is also
explicitly `none`.

## Manual VoiceOver

Evidence source: `docs/release/evidence/accessibility-voiceover.md`

Manual-only:
- Real VoiceOver announcement quality, focus comfort, and reviewer judgment on the release-candidate app.
- Confirmation that keyboard and VoiceOver navigation feel usable across the seeded Project Board path.

automation-backlog:
- Missing labels, hints, generic buttons, focus anchors, and destructive confirmations must become checks in `script/check_accessibility_preflight.sh --runtime`.
- SwiftUI source anchors and keyboard paths belong in `Tests/SoloPMCoreTests/AppExperienceSourceTests.swift`.
- Runtime CRUD and destructive confirmation regressions belong in `script/check_runtime_accessible_crud_smoke.sh`.
- Pseudo VoiceOver focus-path coverage belongs in `Tests/SoloPMCoreTests/SoloPMHarnessTests.swift` and `docs/quality/accessibility-focus-paths.md`.
- Task lifecycle omissions across create, edit, status movement, automation review, approved execution, or delete confirmation belong in `SoloPMHarnessScenario.requiredTaskLifecycleOperations` so MCP/E2E harness coverage fails before manual evidence is reused.

Close rule:
- If the VoiceOver pass records a blocker, it must link a source/runtime regression test or a follow-up issue before the evidence lane is considered closed.

## Competitor Hands-On

Evidence source: `docs/release/evidence/competitor-hands-on.md`

Manual-only:
- Real 2-4 hour hands-on comparison of Notion, Todoist, Linear, and Motion.
- Product judgment on what SoloPM should Ship, Defer, or Reject.

automation-backlog:
- Product deltas and scope decisions must update `docs/product/competitor-benchmark.md`.
- UX deltas that affect public-alpha behavior must become a Phase task in `tasks/Phase14-QualityRegressionHardening.md` or the next product phase.
- Regressions in repeated task creation, editing, status movement, or review-before-execution should become focused tests in `Tests/SoloPMCoreTests/ProjectBoardStoreTests.swift` or `Tests/SoloPMCoreTests/ReleasePipelineTests.swift`.
- Visual or layout differences inspired by `ui-samples/` should be reflected in screenshot evidence or a visual/layout smoke test rather than only prose.

Close rule:
- Every hands-on finding must land as a benchmark decision, a Phase task, or a focused regression test reference.

## Document Automation

Evidence source: `Tests/SoloPMCoreTests/SoloPMHarnessTests.swift`

Manual-only:
- Product judgment on whether a generated preparation checklist, draft artifact, release notes draft, or PR plan is useful enough to ship.

automation-backlog:
- Missing preparation checklists, draft artifacts, release notes, or PR plans belong in `SoloPMHarnessScenario.requiredDocumentDeliverableKinds`.
- Missing approval gates, source document IDs, or draft risk classification belong in `SoloPMHarnessDocumentAutomationRunner`.
- Planner output selection belongs in `Tests/SoloPMCoreTests/DocumentScopedAutomationTests.swift` before any provider-backed drafting is allowed.

Close rule:
- A document automation finding can be closed only when the selected docs, proposed deliverable kind, approval gate, and harness failure mode are all represented in a focused test.

## Release Machine

Evidence source: `packaging/release-evidence.json`

Manual-only:
- Developer ID account ownership, notarization account access, Gatekeeper assessment on the signed artifact, clean install, Launch at Login, and Sparkle update feed verification on the release machine.

automation-backlog:
- Signing, notarization, Sparkle, appcast, Gatekeeper, stapling, and release evidence shape failures belong in `script/verify_release_environment.sh`.
- Release-machine verifier behavior belongs in `Tests/SoloPMCoreTests/ReleasePipelineTests.swift`.
- Runtime launch or clean-environment regressions should be routed to `./script/build_and_run.sh --verify` or the release preflight scripts.

Close rule:
- A release-machine failure can stay manual-only only when the remaining proof depends on external Apple services or a signed artifact. Any parseable metadata or repeatable local failure must become verifier coverage.
