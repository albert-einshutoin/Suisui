# Codebase cleanup: TDD and verification evidence

Date: 2026-08-13

## Goal and design boundary

This cleanup removes code only when repository references, runtime ownership,
and compatibility boundaries establish that it is unused. The implementation
keeps public `SuisuiCore` APIs, persisted-data migrations, security fail-closed
paths, and selective CI lanes intact.

The work was split into five independently reviewable changes:

1. Point accessibility contracts at the live sidebar and Smart List owners,
   then delete the superseded views.
2. Delete unreferenced private Swift declarations, design tokens, and shell
   state while retaining live loaders, stores, and positional input semantics.
3. Replace 16 test-only migration runners with the production
   `SQLiteMigrationRunner`.
4. Stop the full CI lane from rerunning source-contract XCTest suites after the
   complete SwiftPM suite, while retaining the cheap marker scan and security
   scan. The selective `source-contracts` lane remains available.
5. Remove prose-only documentation assertions and their stale CI impact target.

## RED and GREEN evidence

| Change | RED evidence | GREEN evidence |
| --- | --- | --- |
| Live accessibility owners | `QualitySourceContractTests`: 7 failures; focused `AppExperienceSourceTests`: 1 failure | Quality 19/19, focused AppExperience 1/1, pseudo VoiceOver 21/21 + 29/29, build passed |
| Fail-closed sidebar marker gate | Focused contract produced 8 failed assertions when the modifier hookup was absent | Modifier hookup, five exact mappings, and a negative fixture pass |
| Private implementation deletion | Related suites were green before the behavior-preserving refactor | Design token, Quality, UI gate, and AppExperience suites: 328 tests, 0 failures; build and security passed |
| Migration runner consolidation | 328 tests, 1 skipped, 0 failures before replacement | Same 328 tests, 1 skipped, 0 failures; additional 17 related tests passed |
| Full CI de-duplication | Swift and Python orchestration contracts failed against the old `source-contracts` invocation | Both focused contracts pass; `--swift-test` reintroduction is explicitly rejected |
| Prose-only suite removal | Impact-analysis contract failed while `Phase5DocumentationTests` remained selected | Impact-analysis contract and `PublicBrandSurfaceTests` pass; no stale suite reference remains |

During final verification, the release fixture group first failed while another
test process used the same fixed `.build` fixtures, then passed 253/253 when run
alone. A later full run correctly failed because this evidence plan was modified
while tests enforced a clean tracked tree. After committing all inputs and
running without concurrent fixture writers, the complete suite passed.

## Final verification

| Command | Result |
| --- | --- |
| `./script/run_complete_swiftpm_tests.sh` | 3,298 discovered/executed, 6 skipped, 0 failures |
| `swift build --product Suisui` | Passed |
| `python3 -m unittest discover -s ci/tests -p 'test_*.py'` | 34 tests passed |
| `./script/check_security_regressions.sh` | Passed |
| `./script/check_pseudo_voiceover_paths.sh` | Passed without `--swift-test` |
| `actionlint .github/workflows/ci.yml` | Passed |
| `bash -n` for every modified shell file | Passed |
| ShellCheck for every modified shell file | No new warning/error codes; existing SC1010, SC2318, SC2053, and SC1087 remain unchanged from `origin/main` |
| `git diff --check origin/main...HEAD` | Passed before evidence commit |

The baseline complete suite executed 3,304 tests. The final suite executes six
fewer tests: seven prose-only documentation tests were removed and one negative
accessibility gate contract was added.

Before this evidence file, the branch changed 49 files with 336 additions and
779 deletions (net -443 lines).

## Review outcomes

- Accessibility specification and quality reviews: approved after strengthening
  the shell gate to verify the live modifier hookup and an explicit negative
  fixture.
- Migration specification and quality reviews: approved; all 27 call sites kept
  their connection and migration arrays.
- Private cleanup specification and quality reviews: approved after aligning the
  living design-system documentation with the remaining tokens.
- CI de-duplication review: approved after contracts explicitly rejected
  `--swift-test` in the full marker scan.
- Prose-test removal review: approved; executable release, security,
  accessibility, schema, and public-brand contracts remain.

## Intentional exclusions

- Public or compatibility-sensitive `SuisuiCore` declarations were not removed
  without a versioned deprecation decision.
- `SuisuiExternalConnectors`, `SuisuiiOS`, and `SuisuiWeb` remain because their
  target and roadmap ownership needs a product decision, not a dead-reference
  inference.
- Persisted-data migration, legacy route decoding, and fail-closed deprecated
  overloads remain.
- Recovery flags without tracked writers remain until external/manual operator
  use is verified.
- The 18,000-line `ReleasePipelineTests` suite was not broadly table-driven in
  this branch. Its fixed-directory and failure-classification fixtures need an
  isolated, dedicated TDD change rather than being mixed into a deletion PR.
