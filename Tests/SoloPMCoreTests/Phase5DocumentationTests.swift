import Foundation
import XCTest

final class Phase5DocumentationTests: XCTestCase {
    func testReadmeIsPublicAlphaReady() throws {
        let readme = try readPackageFile("README.md")

        XCTAssertTrue(readme.contains("Public Alpha"))
        XCTAssertTrue(readme.contains("MVP Scope"))
        XCTAssertTrue(readme.contains("Personal MVP"))
        XCTAssertTrue(readme.contains("Business MVP"))
        XCTAssertTrue(readme.contains("GitHub Flow"))
        XCTAssertTrue(readme.contains("Known Limitations"))
        XCTAssertTrue(readme.contains("docs/assets/screenshots/solopm-alpha-preview.svg"))
        XCTAssertTrue(readme.contains("Release Checklist"))
    }

    func testProductRoadmapSeparatesPersonalAndBusinessMVPs() throws {
        let roadmap = try readPackageFile("docs/product/roadmap.md")

        XCTAssertTrue(roadmap.contains("Personal MVP"))
        XCTAssertTrue(roadmap.contains("Business MVP"))
        XCTAssertTrue(roadmap.contains("voice-task loop"))
        XCTAssertTrue(roadmap.contains("KnowledgeBase"))
        XCTAssertTrue(roadmap.contains("QZT"))
        XCTAssertTrue(roadmap.contains("Memory Pager"))
        XCTAssertTrue(roadmap.contains("Organizations, roles, tenant policies, and audit export are Business MVP scope"))
    }

    func testOssDocumentsCoverLicenseContributingAndSecurity() throws {
        let license = try readPackageFile("LICENSE")
        let contributing = try readPackageFile("CONTRIBUTING.md")
        let security = try readPackageFile("SECURITY.md")

        XCTAssertTrue(license.contains("MIT License"))
        XCTAssertTrue(contributing.contains("GitHub Flow"))
        XCTAssertTrue(contributing.contains("Issue Triage"))
        XCTAssertTrue(contributing.contains("Review Policy"))
        XCTAssertTrue(contributing.contains("Supported Environment"))
        XCTAssertTrue(security.contains("Supported Versions"))
        XCTAssertTrue(security.contains("GitHub Security Advisory"))
        XCTAssertTrue(security.contains("secret handling"))
    }

    func testPrivacySecurityDocsDeclareLocalFirstBoundaries() throws {
        let docs = try readPackageFile("docs/release/privacy-security.md")

        XCTAssertTrue(docs.contains("Keychain"))
        XCTAssertTrue(docs.contains("local"))
        XCTAssertTrue(docs.contains("LLM 送信文脈"))
        XCTAssertTrue(docs.contains("送信しない"))
        XCTAssertTrue(docs.contains("削除しない"))
        XCTAssertTrue(docs.contains("自動投稿しない"))
        XCTAssertTrue(docs.contains("opt-in"))
    }

    func testReleaseChecklistContainsFullOrderRollbackAndKnownIssues() throws {
        let checklist = try readPackageFile("docs/release/checklist.md")

        for keyword in ["test", "build", "sign", "notarize", "package", "checksum", "appcast", "tag", "release notes"] {
            XCTAssertTrue(checklist.contains(keyword), "Missing \(keyword)")
        }

        XCTAssertTrue(checklist.contains("Rollback"))
        XCTAssertTrue(checklist.contains("Known Issues"))
        XCTAssertTrue(checklist.contains("Developer ID Application"))
    }

    func testPublicAlphaNotesDeclareScopeLimitationsWorkflowsAndFeedback() throws {
        let alpha = try readPackageFile("docs/release/public-alpha.md")

        XCTAssertTrue(alpha.contains("Phase 0-4"))
        XCTAssertTrue(alpha.contains("External MCP"))
        XCTAssertTrue(alpha.contains("SaaS"))
        XCTAssertTrue(alpha.contains("RAG"))
        XCTAssertTrue(alpha.contains("Team"))
        XCTAssertTrue(alpha.contains("Sample Workflows"))
        XCTAssertTrue(alpha.contains("Feedback"))
        XCTAssertGreaterThanOrEqual(alpha.components(separatedBy: "Workflow ").count - 1, 3)
    }

    func testJapanesePublicAlphaEntryPointsExplainSetupSafetyAndLimits() throws {
        let englishReadme = try readPackageFile("README.md")
        let japaneseReadme = try readPackageFile("README.ja.md")
        let englishAlpha = try readPackageFile("docs/release/public-alpha.md")
        let japaneseAlpha = try readPackageFile("docs/release/public-alpha-ja.md")

        XCTAssertTrue(englishReadme.contains("[日本語版 README](README.ja.md)"))
        XCTAssertTrue(englishAlpha.contains("[日本語版](public-alpha-ja.md)"))

        for marker in [
            "最初の5分",
            "./script/build_and_run.sh",
            "Voice Command",
            "承認後に実行",
            "Keychain",
            "STT",
            "TTS",
            "Finder",
            "できること",
            "まだできないこと",
            "既知の制限",
            "手動VoiceOver",
            "Notarization"
        ] {
            XCTAssertTrue(japaneseReadme.contains(marker), "Japanese README must include \(marker)")
        }

        for marker in [
            "対象ユーザー",
            "主要ワークフロー",
            "承認後に実行",
            "ローカルファースト",
            "既知の制限",
            "フィードバック",
            "チーム",
            "クラウド同期",
            "外部SaaS"
        ] {
            XCTAssertTrue(japaneseAlpha.contains(marker), "Japanese alpha notes must include \(marker)")
        }

        XCTAssertNil(japaneseReadme.range(of: #"sk-[A-Za-z0-9_-]{8,}"#, options: .regularExpression))
        XCTAssertNil(japaneseAlpha.range(of: #"sk-[A-Za-z0-9_-]{8,}"#, options: .regularExpression))
    }

    private func readPackageFile(_ relativePath: String) throws -> String {
        let url = packageRoot().appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }
}
