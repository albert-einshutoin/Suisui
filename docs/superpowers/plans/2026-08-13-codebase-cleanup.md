# Codebase Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove verified dead code and low-value test duplication while keeping product behavior, accessibility, security, persistence, and public API compatibility intact.

**Architecture:** Correct quality gates so they inspect the live SwiftUI owners, then delete obsolete private implementation. Reuse the production migration runner, avoid rerunning Swift suites after the complete suite, and shrink only repetitive release/document contracts; runtime, security, persistence, and artifact validation remain unchanged.

**Tech Stack:** Swift 6, SwiftUI/AppKit, XCTest, SwiftPM, Bash, GitHub Actions.

---

### Task 1: Point accessibility contracts at live UI owners

**Files:**
- Modify: `Tests/SuisuiCoreTests/QualitySourceContractTests.swift`
- Modify: `Tests/SuisuiCoreTests/AppExperienceSourceTests.swift`
- Modify: `Tests/SuisuiCoreTests/ArchitectureBoundaryTests.swift`
- Modify: `Tests/SuisuiCoreTests/LaunchExperienceTests.swift`
- Modify: `script/check_pseudo_voiceover_paths.sh`
- Modify: `Sources/SuisuiApp/Views/ProjectBoardProjectsHubView.swift`
- Modify: `Sources/SuisuiApp/Views/ProjectBoardSmartListViews.swift`
- Delete: `Sources/SuisuiApp/Views/ProjectWorkflowViews.swift`

- [x] **Step 1: Write the failing live-owner contracts**

Change the quality contract to require `ProjectBoardSidebarView.swift`, reject `ProjectWorkflowViews.swift`, and inspect `ProjectBoardProjectsHubView.swift` for the Smart List selected trait.

```swift
XCTAssertTrue(script.contains("ProjectBoardSidebarView.swift"))
XCTAssertFalse(script.contains("ProjectWorkflowViews.swift"))
XCTAssertTrue(projectsHubSource.contains(".accessibilityAddTraits(isSelected ? .isSelected : [])"))
```

- [x] **Step 2: Run RED**

Run: `swift test --filter QualitySourceContractTests && swift test --filter AppExperienceSourceTests/testCalmSignalDeskStatusAndMotionKeepNonColorAccessibilityCues`

Expected: failure because the script and Smart List assertion still point to obsolete owners.

- [x] **Step 3: Commit RED evidence**

```bash
git add Tests/SuisuiCoreTests
git commit -m "test: require accessibility gates to inspect live sidebar owners"
```

- [x] **Step 4: Implement the minimal live-owner fix**

Make `check_pseudo_voiceover_paths.sh` validate each concrete `sidebar-destination-*` identifier in `ProjectBoardSidebarView.swift`. Add the selected accessibility trait to the live Smart List row. Remove the obsolete sidebar row file and the unused `SmartListSidebarSection`; remove obsolete file aggregation from tests.

- [x] **Step 5: Run GREEN and commit**

Run: `swift test --filter QualitySourceContractTests && swift test --filter AppExperienceSourceTests/testCalmSignalDeskStatusAndMotionKeepNonColorAccessibilityCues && ./script/check_pseudo_voiceover_paths.sh --swift-test`

```bash
git add Sources Tests script
git commit -m "fix: validate accessibility against live sidebar views"
```

### Task 2: Delete private dead Swift and unused shell state

**Files:**
- Modify: `Sources/SuisuiApp/Views/ProjectBoardView.swift`
- Modify: `Sources/SuisuiApp/Views/ProjectWorkflowInboxView.swift`
- Modify: `Sources/SuisuiApp/Views/SettingsView.swift`
- Modify: `Sources/SuisuiApp/SuisuiApp.swift`
- Modify: `Sources/SuisuiApp/Views/SuisuiDesignSystem.swift`
- Modify: `Tests/SuisuiCoreTests/SuisuiDesignTokenContractTests.swift`
- Modify: `.takt/automation/full-auto-devloop.sh`
- Modify: `script/release_readiness_report.sh`
- Modify: `script/check_security_regressions.sh`
- Modify: `script/check_runtime_voice_task_continuity_smoke.sh`
- Modify: `script/check_runtime_development_pr_smoke.sh`
- Modify: `script/check_runtime_accessible_crud_smoke.sh`
- Modify: `script/capture_ui_evidence.sh`

- [x] **Step 1: Delete only declaration-only private code**

Remove `selectedSmartList`, the three unused sidebar project filters, `ProjectSidebarRow` and its dedicated extensions, `InboxTriageStateBadge`, the unused Settings snapshot input chain, and declaration-only design tokens. Remove shell variables with no reads. Do not touch public `SuisuiCore` declarations.

- [x] **Step 2: Verify behavior remains GREEN**

Run: `swift test --filter SuisuiDesignTokenContractTests && swift build --product Suisui && shellcheck -x <modified-shell-files>`

- [x] **Step 3: Commit**

```bash
git add Sources Tests script .takt
git commit -m "refactor: remove unreferenced private implementation"
```

### Task 3: Reuse the production SQLite migration runner in tests

**Files:**
- Modify: the 16 test files declaring `TestMigrationRunner`, `ReviewTestMigrationRunner`, or feature-specific migration runners identified by `rg '^private enum .*MigrationRunner' Tests/SuisuiCoreTests`

- [x] **Step 1: Replace custom runner calls**

Use the already-tested production path:

```swift
try SQLiteMigrationRunner.migrate(connection: connection, migrations: migrations)
```

Delete only the duplicate enums. Preserve `LocalStoreTests` and `Support/ToolRegistryFactory.swift`, whose doubles intentionally exercise different boundaries.

- [x] **Step 2: Run focused migration/store suites**

Run: `swift test --filter DatabaseMigrationTests` followed by each modified test class.

- [x] **Step 3: Commit**

```bash
git add Tests/SuisuiCoreTests
git commit -m "refactor: reuse production migration runner in tests"
```

### Task 4: Stop complete CI from rerunning Swift suites

**Files:**
- Modify: `Tests/SuisuiCoreTests/ReleasePipelineTests.swift`
- Modify: `ci/run-full.sh`

- [x] **Step 1: Write the failing orchestration contract**

```swift
XCTAssertFalse(fullRunner.contains("./scripts/ci.sh source-contracts"))
XCTAssertTrue(fullRunner.contains("./script/check_pseudo_voiceover_paths.sh"))
```

- [x] **Step 2: Run RED**

Run: `swift test --filter ReleasePipelineTests/testGitHubCISeparatesCompleteSwiftPMSuiteFromSupplementalSourceContracts`

Expected: failure because `run-full.sh` still reruns source-contract Swift suites.

- [x] **Step 3: Commit RED evidence**

```bash
git add Tests/SuisuiCoreTests/ReleasePipelineTests.swift
git commit -m "test: prevent full CI from rerunning Swift source contracts"
```

- [x] **Step 4: Keep only the non-Swift static gate after the full suite**

Replace `./scripts/ci.sh source-contracts` with `./script/check_pseudo_voiceover_paths.sh`. Keep `scripts/ci.sh source-contracts` unchanged for focused/selective use.

- [x] **Step 5: Run GREEN and commit**

Run the focused contract and `./script/check_pseudo_voiceover_paths.sh`.

```bash
git add ci/run-full.sh
git commit -m "ci: avoid duplicate Swift test execution in full validation"
```

### Task 5: Remove prose-locking tests and shrink repetitive release fixtures

**Files:**
- Delete: `Tests/SuisuiCoreTests/Phase5DocumentationTests.swift`
- Modify: `ci/config/impact.json`
- Modify: `ci/tests/test_impact_analysis.py`
- Modify: `Tests/SuisuiCoreTests/ReleasePipelineTests.swift`

- [x] **Step 1: Remove prose keyword contracts**

Delete tests that make README/roadmap wording a product regression and remove their selective-CI mapping. Retain executable checks for links, schemas, secrets, release artifacts, signing, checksums, notarization, and security boundaries.

- [x] **Step 2: Review repeated release rejection cases**

Do not rewrite the full 18,000-line suite in this cleanup. Review found that even a shared fixture extraction would couple tests that intentionally preserve distinct failure classifications and fixed-directory behavior. Keep the suite unchanged in this branch; a broader table-driven rewrite belongs in a dedicated follow-up with isolated fixtures and its own RED/GREEN cycle.

- [x] **Step 3: Run release and full suites**

Run: `python3 -m unittest ci.tests.test_impact_analysis`, `swift test --filter ReleasePipelineTests`, then `./script/run_complete_swiftpm_tests.sh`.

- [x] **Step 4: Commit**

```bash
git add Tests/SuisuiCoreTests
git commit -m "refactor: reduce brittle and repetitive release tests"
```

### Task 6: Security, regression, and final review

**Files:**
- Create: `docs/testing/codebase-cleanup.tdd.md`

- [x] **Step 1: Run complete verification**

Run `swift build --product Suisui`, `./script/run_complete_swiftpm_tests.sh`, `python3 -m unittest discover -s ci/tests -p 'test_*.py'`, `./script/check_security_regressions.sh`, `actionlint .github/workflows/ci.yml`, and ShellCheck for all modified shell files.

- [x] **Step 2: Record RED/GREEN evidence and intentional exclusions**

Document commands, outcomes, line/test-runtime deltas, and why public APIs, ExternalConnectors/iOS/Web, compatibility migrations, and unverified recovery flags were not deleted.

- [x] **Step 3: Review the complete diff**

Review for specification compliance first, then Swift/shell quality, accessibility, security boundaries, and accidental tracked artifacts.

- [ ] **Step 4: Commit review evidence**

```bash
git add docs/testing/codebase-cleanup.tdd.md
git commit -m "docs: record codebase cleanup verification evidence"
```
