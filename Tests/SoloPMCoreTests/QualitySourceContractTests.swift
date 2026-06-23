import XCTest

final class QualitySourceContractTests: XCTestCase {
    func testPseudoVoiceOverFocusPathDocumentationAndScriptCoverTaskLifecycle() throws {
        let docs = try readPackageFile("docs/quality/accessibility-focus-paths.md")
        let script = try readPackageFile("script/check_pseudo_voiceover_paths.sh")
        let preflight = try readPackageFile("script/check_accessibility_preflight.sh")

        for marker in [
            "project-board-sidebar",
            "project-header-add-task",
            "inline-task-create",
            "project-board-task-auto-execution-review",
            "task-card-open-details",
            "task-inspector-save",
            "task-status-move-controls",
            "task-auto-execution-review",
            "task-auto-execution-run-plan",
            "task-inspector-delete",
            "task-inspector-delete-confirmation-confirm"
        ] {
            XCTAssertTrue(docs.contains(marker), "docs must cover \(marker)")
            XCTAssertTrue(script.contains(marker), "script must check \(marker)")
        }

        XCTAssertTrue(preflight.contains("project-board-task-auto-execution-review"))
        XCTAssertTrue(preflight.contains("task-auto-execution-review"))
        XCTAssertTrue(preflight.contains("task-auto-execution-run-plan"))
        XCTAssertTrue(docs.contains("Manual VoiceOver is still required"))
        XCTAssertTrue(docs.contains("SoloPMHarnessAccessibilityAuditRunner"))
        XCTAssertTrue(docs.contains("mcp-pseudo-voiceover-focus-path"))
        XCTAssertTrue(script.contains("AccessibilityFocusPathAudit"))
    }

    func testProductRoleDocumentationStatesLocalFirstReviewBeforeExecutionStrength() throws {
        let doc = try readPackageFile("docs/product/role-and-strengths.md")

        XCTAssertTrue(doc.contains("Local-first"))
        XCTAssertTrue(doc.contains("review-before-execution"))
        XCTAssertTrue(doc.contains("MCP"))
        XCTAssertTrue(doc.contains("VoiceOver"))
        XCTAssertTrue(doc.contains("document-scoped automation"))
        XCTAssertTrue(doc.contains("status/due-date proposals"))
        XCTAssertTrue(doc.contains("task automation selection reasons"))
        XCTAssertTrue(doc.contains("priority and due-date tradeoffs"))
        XCTAssertNil(doc.range(of: #"sk-[A-Za-z0-9_-]{8,}"#, options: .regularExpression))
    }

    func testManualToAutomatedRegressionBridgeDocumentsManualGateBackstops() throws {
        let doc = try readPackageFile("docs/quality/manual-to-automated-regression.md")

        for requiredSection in [
            "## Manual VoiceOver",
            "## Competitor Hands-On",
            "## Release Machine",
            "## Manual Finding Intake",
            "## Failure Note Contract"
        ] {
            XCTAssertTrue(doc.contains(requiredSection), "manual bridge doc must include \(requiredSection)")
        }

        for requiredMarker in [
            "manual-only",
            "automation-backlog",
            "Follow-up source/test link",
            "Blocker observed",
            "docs/release/evidence/accessibility-voiceover.md",
            "docs/release/evidence/competitor-hands-on.md",
            "packaging/release-evidence.json",
            "script/check_accessibility_preflight.sh --runtime",
            "script/check_runtime_accessible_crud_smoke.sh",
            "script/verify_release_environment.sh",
            "Tests/SoloPMCoreTests/AppExperienceSourceTests.swift",
            "Tests/SoloPMCoreTests/ReleasePipelineTests.swift",
            "tasks/Phase14-QualityRegressionHardening.md"
        ] {
            XCTAssertTrue(doc.contains(requiredMarker), "manual bridge doc must route \(requiredMarker)")
        }

        XCTAssertNil(doc.range(of: #"sk-[A-Za-z0-9_-]{8,}"#, options: .regularExpression))
    }

    func testAccessibilityIdentifierGuidelinesDefineStableComponentNaming() throws {
        let doc = try readPackageFile("docs/quality/accessibility-identifiers.md")
        let phase = try readPackageFile("tasks/Phase14-QualityRegressionHardening.md")

        for marker in [
            "## Naming Contract",
            "screen-area-action",
            "dynamic suffix",
            "project-board",
            "inbox",
            "today",
            "settings",
            "task-inspector-save",
            "sidebar-destination-<destination>",
            "workflow-task-row-<taskID>",
            "settings-task-auto-execution-toggle",
            "settings-task-auto-execution-urgent-cooldown",
            "Required for new interactive components",
            "Do not encode user-provided content, secrets, or filesystem paths"
        ] {
            XCTAssertTrue(doc.contains(marker), "identifier guidelines must document \(marker)")
        }

        XCTAssertTrue(phase.contains("- [x] UI component追加時のAX identifier命名規則を定義する。"))
    }

    func testAccessibilityFocusPathsMapRuntimeSmokeMarkersToManualWorksheet() throws {
        let doc = try readPackageFile("docs/quality/accessibility-focus-paths.md")
        let candidateScript = try readPackageFile("script/prepare_voiceover_review_candidate.sh")
        let phase = try readPackageFile("tasks/Phase14-QualityRegressionHardening.md")

        for marker in [
            "## Runtime Smoke To Manual Worksheet Mapping",
            "`unlabeledButtons=0`",
            "`genericButtons=0`",
            "`crudSignals=8/8`",
            "`buttonA11ySignals=8/8`",
            "`screenSignals=4/4`",
            "`focusPathSignals=6/6`",
            "No unlabeled primary CRUD controls",
            "Project navigation",
            "Project board detail",
            "Open task",
            "Inline Task Composer",
            "Status controls",
            "Task inspector"
        ] {
            XCTAssertTrue(doc.contains(marker), "focus path doc must map \(marker)")
            XCTAssertTrue(candidateScript.contains(marker), "worksheet generator must map \(marker)")
        }

        XCTAssertTrue(phase.contains("- [x] Manual VoiceOver worksheetとruntime AX smokeの項目を対応付ける。"))
    }

    func testPhase14AccessibilityAcceptanceIsBackedByAutomatedContracts() throws {
        let phase = try readPackageFile("tasks/Phase14-QualityRegressionHardening.md")
        let accessibilityPreflight = try readPackageFile("script/check_accessibility_preflight.sh")
        let runtimeWorkflow = try readPackageFile("script/check_runtime_workflow_smoke.sh")
        let focusPaths = try readPackageFile("docs/quality/accessibility-focus-paths.md")

        for marker in [
            "crudSignals=",
            "buttonA11ySignals=",
            "screenSignals=",
            "focusPathSignals=",
            "runtime AX smoke is missing primary button label or help",
            "runtime AX smoke is missing workflow screen entry labels or help"
        ] {
            XCTAssertTrue(accessibilityPreflight.contains(marker), "preflight must enforce \(marker)")
        }

        XCTAssertTrue(runtimeWorkflow.contains("project_task_crud"))
        XCTAssertTrue(runtimeWorkflow.contains("inbox_triage"))
        XCTAssertTrue(runtimeWorkflow.contains("today_complete"))
        XCTAssertTrue(runtimeWorkflow.contains("settings_save"))
        XCTAssertTrue(focusPaths.contains("Runtime Smoke To Manual Worksheet Mapping"))
        XCTAssertTrue(phase.contains("- [x] Mouse、keyboard、VoiceOver前提のAX pathで主要CRUD入口が検出できる。"))
        XCTAssertTrue(phase.contains("- [x] 手動VoiceOver前に明らかなlabel/focus漏れを自動検出できる。"))
    }

    func testQualityStatusDashboardScriptAndSnapshotDocumentQualityGates() throws {
        let script = try readPackageFile("script/quality_status_report.sh")
        let status = try readPackageFile("docs/quality/status.md")
        let releaseReadiness = try readPackageFile("script/release_readiness_report.sh")
        let riskMap = try readPackageFile("docs/quality/regression-risk-map.md")

        for marker in [
            "tasks/Phase14-QualityRegressionHardening.md",
            "docs/quality/regression-risk-map.md",
            "docs/release/evidence/ui-screenshots.md",
            "docs/release/evidence/mcp-inspector.md",
            "docs/release/evidence/accessibility-voiceover.md",
            "docs/release/evidence/competitor-hands-on.md"
        ] {
            XCTAssertTrue(script.contains(marker), "quality status script must read \(marker)")
            XCTAssertTrue(status.contains(marker), "quality status snapshot must mention \(marker)")
        }

        XCTAssertTrue(script.contains("SOLOPM_QUALITY_STATUS_FILE"))
        XCTAssertTrue(script.contains("script/check_layout_stability_smoke.sh"))
        XCTAssertTrue(status.contains("script/check_layout_stability_smoke.sh"))
        XCTAssertTrue(script.contains("script/check_visual_regression_smoke.sh"))
        XCTAssertTrue(status.contains("script/check_visual_regression_smoke.sh"))
        XCTAssertTrue(script.contains("## Gate Classification"))
        XCTAssertTrue(status.contains("## Gate Classification"))
        XCTAssertTrue(status.contains("Lightweight PR gate"))
        XCTAssertTrue(status.contains("Focused tests"))
        XCTAssertTrue(status.contains("Runtime smoke"))
        XCTAssertTrue(status.contains("Visual smoke"))
        XCTAssertTrue(status.contains("Manual evidence"))
        XCTAssertTrue(status.contains("Release readiness handoff"))
        XCTAssertTrue(script.contains("script/release_readiness_report.sh"))
        XCTAssertTrue(status.contains("script/release_readiness_report.sh"))
        XCTAssertTrue(releaseReadiness.contains("Quality status dashboard"))
        XCTAssertTrue(releaseReadiness.contains("script/quality_status_report.sh"))
        XCTAssertTrue(releaseReadiness.contains("quality triage aid, not release evidence"))
        XCTAssertTrue(status.contains("## Next Quality Gaps"))
        XCTAssertTrue(status.contains("## Unfinished Phase14 Items"))
        XCTAssertTrue(status.contains("## Open Risk Items"))
        XCTAssertTrue(status.contains("## Verification Commands"))
        XCTAssertFalse(riskMap.contains("Coverage: open。"))
        XCTAssertNil(status.range(of: #"sk-[A-Za-z0-9_-]{8,}"#, options: .regularExpression))
    }

    func testSecurityRegressionScriptCoversArtifactsAndSecretTaxonomy() throws {
        let script = try readPackageFile("script/check_security_regressions.sh")
        let gitignore = try readPackageFile(".gitignore")
        let phase = try readPackageFile("tasks/Phase14-QualityRegressionHardening.md")

        for marker in [
            "Tests/SoloPMCoreTests/Fixtures",
            "docs/release/evidence",
            "docs/release/evidence/ui-screenshots",
            "packaging",
            "TOKEN_PATTERNS",
            "sk-[A-Za-z0-9_-]",
            "xox[baprs]-",
            "ghp_",
            "github_pat_",
            "AIza",
            "AKIA",
            "PRIVATE KEY",
            "OAUTH",
            "MCP",
            "NOTARY",
            "KEYCHAIN_REFERENCE_ALLOWLIST",
            "RAW_SECRET_DENYLIST",
            "SOLOPM_SECURITY_SCAN_INCLUDE_TMP"
        ] {
            XCTAssertTrue(script.contains(marker), "security regression script must cover \(marker)")
        }

        XCTAssertTrue(gitignore.contains("/.tmp/"))
        XCTAssertTrue(phase.contains("- [x] secret-like patternがtest fixture、screenshot metadata、release evidenceに出たら失敗するscanを追加する。"))
        XCTAssertTrue(phase.contains("- [x] Runtime smoke artifact directoryが `.gitignore` 対象であることをテストする。"))
        XCTAssertTrue(phase.contains("- [x] Keychain referenceとraw secretの区別をsource testで固定する。"))
    }

    func testVisualEvidenceContractExcludesUnmaskedSecretInputScreens() throws {
        let visualDoc = try readPackageFile("docs/quality/visual-baselines.md")
        let evidenceDoc = try readPackageFile("docs/release/evidence/ui-screenshots.md")
        let captureScript = try readPackageFile("script/capture_ui_evidence.sh")
        let manifest = try readPackageFile("docs/quality/visual-baseline-manifest.json")
        let phase = try readPackageFile("tasks/Phase14-QualityRegressionHardening.md")

        for marker in [
            "Secret input screens are excluded from the default visual baseline manifest.",
            "Only masked SecureField state may be captured",
            "masked SecureField",
            "API keys and provider tokens are not read, written, logged, rendered, or captured unmasked"
        ] {
            XCTAssertTrue(visualDoc.contains(marker), "visual baseline doc must mention \(marker)")
            XCTAssertTrue(evidenceDoc.contains(marker), "screenshot evidence doc must mention \(marker)")
            XCTAssertTrue(captureScript.contains(marker), "capture script must write \(marker)")
        }

        XCTAssertNil(manifest.range(of: #"(?i)(api[-_ ]?key|secret|token)"#, options: .regularExpression))
        XCTAssertTrue(phase.contains("- [x] Screenshotは必要最小限にし、secret入力画面を撮る場合はmask状態を検証する。"))
    }

    func testFlakeTriageRequiresOwnedReasonedExpiringQuarantineEntries() throws {
        let triage = try readPackageFile("docs/quality/test-triage.md")
        let quarantine = try readPackageFile("docs/quality/flake-quarantine.md")
        let releaseReport = try readPackageFile("script/release_readiness_report.sh")
        let status = try readPackageFile("docs/quality/status.md")
        let phase = try readPackageFile("tasks/Phase14-QualityRegressionHardening.md")

        for category in [
            "build",
            "assertion",
            "crash",
            "timing",
            "environment",
            "manual gate"
        ] {
            XCTAssertTrue(triage.contains(category), "test triage doc must classify \(category)")
        }

        for marker in [
            "owner",
            "reason",
            "expiry",
            "minimal reproduction command",
            "No indefinite quarantine",
            "automation-backlog"
        ] {
            XCTAssertTrue(quarantine.contains(marker), "flake quarantine doc must require \(marker)")
            XCTAssertTrue(triage.contains(marker), "test triage doc must route \(marker)")
        }

        XCTAssertTrue(releaseReport.contains("write_failure_triage_actions"))
        XCTAssertTrue(releaseReport.contains("minimal reproduction command"))
        XCTAssertTrue(releaseReport.contains("failure_reproduction_command"))
        XCTAssertTrue(status.contains("docs/quality/flake-quarantine.md"))
        XCTAssertTrue(phase.contains("- [x] Flake quarantine listが空でない場合、owner/reason/expiryが必要なことをテストする。"))
        XCTAssertTrue(phase.contains("- [x] `docs/quality/test-triage.md` にfailure categoryを書く。"))
        XCTAssertTrue(phase.contains("- [x] `docs/quality/flake-quarantine.md` を作り、期限付きでしかskipできない運用にする。"))
        XCTAssertTrue(phase.contains("- [x] 失敗時は最小再現コマンドをaction summaryに出す。"))
        XCTAssertTrue(phase.contains("- [x] フレークを無期限skipできない。"))
        XCTAssertTrue(phase.contains("- [x] 失敗分類がbuild / assertion / crash / timing / environment / manual gateに分かれる。"))
    }

    func testGitignoreKeepsLocalAgentArtifactsAndRuntimeEvidenceOutOfSource() throws {
        let gitignore = try readPackageFile(".gitignore")

        XCTAssertTrue(gitignore.contains(".codex/hooks.json"))
        XCTAssertTrue(gitignore.contains(".opencode/"))
        XCTAssertTrue(gitignore.contains("/.tmp/"))
        XCTAssertTrue(gitignore.contains("/ui-samples/"))
    }

    private func readPackageFile(_ relativePath: String) throws -> String {
        let url = packageRoot().appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func packageRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}
