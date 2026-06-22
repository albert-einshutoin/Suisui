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
