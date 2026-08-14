import XCTest
@testable import SuisuiCore

final class DraftGenerationTests: XCTestCase {
    func testReadmeDraftIsPreviewOnlyAndDoesNotOverwriteExistingReadme() {
        let context = DraftGenerationContext(
            repositoryName: "suisui",
            currentBranch: "feature/phase6-developer-mode",
            gitStatusSummary: "clean",
            commitSummaries: ["abc123 Add CLI foundation"],
            taskSummaries: ["P6-005 CLI foundation"],
            generatedAt: Date(timeIntervalSince1970: 1_783_200_000)
        )

        let draft = DeveloperDraftGenerator().generateReadmeDraft(from: context)

        XCTAssertEqual(draft.kind, .readme)
        XCTAssertEqual(draft.writePolicy, .previewOnly(suggestedPath: "README.draft.md"))
        XCTAssertTrue(draft.body.contains("# suisui"))
        XCTAssertTrue(draft.body.contains("P6-005 CLI foundation"))
        XCTAssertTrue(draft.safetyNotes.contains(.doesNotOverwriteExistingReadme))
    }

    func testReleaseNoteDraftRedactsSecretsFromInputs() {
        let githubToken = "github" + "_pat_" + "11SECRETSECRETSECRETSECRETSECRETSECRETSECRET"
        let openAIKey = "sk" + "-proj-" + "SECRETSECRETSECRETSECRETSECRETSECRETSECRET"
        let classicToken = "ghp" + "_" + "secret"
        let context = DraftGenerationContext(
            repositoryName: "suisui",
            currentBranch: "release/test",
            gitStatusSummary: "modified Sources/SuisuiCore/DeveloperMode/DraftGeneration.swift",
            commitSummaries: [
                "Add GitHub token \(githubToken)",
                "Configure OpenAI key \(openAIKey)"
            ],
            taskSummaries: ["Release note should not leak \(classicToken)"],
            generatedAt: Date(timeIntervalSince1970: 1_783_200_000)
        )

        let draft = DeveloperDraftGenerator().generateReleaseNoteDraft(from: context)

        XCTAssertEqual(draft.kind, .releaseNotes)
        XCTAssertEqual(draft.writePolicy, .previewOnly(suggestedPath: "RELEASE_NOTES.draft.md"))
        XCTAssertFalse(draft.body.contains(githubToken))
        XCTAssertFalse(draft.body.contains(openAIKey))
        XCTAssertFalse(draft.body.contains(classicToken))
        XCTAssertTrue(draft.body.contains("[REDACTED_SECRET]"))
        XCTAssertEqual(draft.redactionReport.replacementCount, 3)
    }

    func testAssignmentRedactionDoesNotConsumeFollowingAuditFields() {
        let apiKey = "secret-value"
        let summary = "apiKey=string(\"\(apiKey)\"),title=string(\"Secret task\")"

        let redaction = DeveloperSecretRedactor().redact(summary)

        XCTAssertFalse(redaction.text.contains(apiKey))
        XCTAssertEqual(redaction.text, "[REDACTED_SECRET],title=string(\"Secret task\")")
        XCTAssertEqual(redaction.report.matchedPatternNames, ["assignment"])
    }

    func testJSONRedactionConsumesEscapedStringValues() {
        let secretSuffix = "TOPSECRET"
        let fixtures = [
            #"{"token":"prefix\"TOPSECRET"}"#,
            #"{"auth":"prefix\"TOPSECRET"}"#,
        ]

        for fixture in fixtures {
            let redaction = DeveloperSecretRedactor().redact(fixture)

            XCTAssertFalse(redaction.text.contains(secretSuffix))
            XCTAssertEqual(redaction.text, "{[REDACTED_SECRET]}")
        }
    }

    func testInvalidRedactionPatternFailsClosedWithoutLeakingInput() {
        let redactor = DeveloperSecretRedactor(patternDefinitions: [
            SecretRedactionPatternDefinition(name: "broken", expression: "[")
        ])

        let redaction = redactor.redact("token=secret-value")

        XCTAssertEqual(redaction.text, "[REDACTED_SECRET]")
        XCTAssertEqual(redaction.report.replacementCount, 1)
        XCTAssertEqual(redaction.report.matchedPatternNames, ["redactor_initialization_failed"])
    }
}
