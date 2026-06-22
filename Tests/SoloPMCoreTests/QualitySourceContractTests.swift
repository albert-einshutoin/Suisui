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
        XCTAssertFalse(doc.contains("sk-"))
    }

    func testManualToAutomatedRegressionBridgeDocumentsManualGateBackstops() throws {
        let doc = try readPackageFile("docs/quality/manual-to-automated-regression.md")

        for requiredSection in [
            "## Manual VoiceOver",
            "## Competitor Hands-On",
            "## Release Machine",
            "## Manual Finding Intake"
        ] {
            XCTAssertTrue(doc.contains(requiredSection), "manual bridge doc must include \(requiredSection)")
        }

        for requiredMarker in [
            "manual-only",
            "automation-backlog",
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

        XCTAssertFalse(doc.contains("sk-"))
    }

    func testQualityStatusDashboardScriptAndSnapshotDocumentQualityGates() throws {
        let script = try readPackageFile("script/quality_status_report.sh")
        let status = try readPackageFile("docs/quality/status.md")

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
        XCTAssertTrue(status.contains("## Unfinished Phase14 Items"))
        XCTAssertTrue(status.contains("## Open Risk Items"))
        XCTAssertTrue(status.contains("## Verification Commands"))
        XCTAssertNil(status.range(of: #"sk-[A-Za-z0-9_-]{8,}"#, options: .regularExpression))
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
