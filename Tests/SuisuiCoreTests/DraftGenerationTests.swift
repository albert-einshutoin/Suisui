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

    func testConnectionURIUserInfoIsRedacted() {
        let fixtureCredential = ["fixture", "credential"].joined(separator: "-")
        let redaction = DeveloperSecretRedactor().redact(
            "dsn=postgres://alice:\(fixtureCredential)@db.example/app"
        )

        XCTAssertFalse(redaction.text.contains(fixtureCredential))
        XCTAssertTrue(redaction.text.contains("[REDACTED_SECRET]"))
        XCTAssertTrue(redaction.report.matchedPatternNames.contains("credential_uri"))
    }

    func testAuthorizationHeadersAndJWTsAreRedacted() {
        let bearer = "Bearer bearercredentialmarker"
        let basic = "Basic basiccredentialmarker"
        let shortBearer = "Bearer abc"
        let shortBasic = "Basic dTpw"
        let jwt = "eyJheadersentinel.payloadsentinel.signaturesentinel"
        let unsignedJWT = "eyJhbGciOiJub25lIn0.e30."
        let trailingHyphenJWT = "eyJhbGciOiJub25lIn0.e30.signaturesentinel-"
        let redaction = DeveloperSecretRedactor().redact(
            "Authorization: \(bearer)\nAuthorization: \(basic)\nAuthorization: \(shortBearer)\nAuthorization: \(shortBasic)\ncredential=\(jwt)\ncredential=\(unsignedJWT)\ncredential=\(trailingHyphenJWT)"
        )

        XCTAssertFalse(redaction.text.contains("bearercredentialmarker"))
        XCTAssertFalse(redaction.text.contains("basiccredentialmarker"))
        XCTAssertFalse(redaction.text.contains("Authorization: Bearer abc"))
        XCTAssertFalse(redaction.text.contains("Authorization: Basic dTpw"))
        XCTAssertFalse(redaction.text.contains("signaturesentinel"))
        XCTAssertFalse(redaction.text.contains(unsignedJWT))
        XCTAssertFalse(redaction.text.contains(trailingHyphenJWT))
        XCTAssertTrue(redaction.report.matchedPatternNames.contains("authorization_header"))
        XCTAssertTrue(redaction.report.matchedPatternNames.contains("jwt"))
    }

    func testEscapedCredentialKeysFailClosed() {
        for fixture in [
            #"{"to\u006ben":"long-secret-value"}"#,
            #"{"client_\u0073ecret":"long-secret-value"}"#,
            #"{"au\u0074h":"long-secret-value"}"#,
            #"prefix " junk {"to\u006ben":"long-secret-value"}"#,
            #""to\u006ben" = "long-secret-value""#,
        ] {
            let redaction = DeveloperSecretRedactor().redact(fixture)

            XCTAssertEqual(redaction.text, "[REDACTED_SECRET]")
            XCTAssertEqual(redaction.report.matchedPatternNames, ["credential_json"])
        }
    }

    func testEscapedCredentialKeyScanBudgetFailsClosed() {
        let adversarialQuotes = String(repeating: #"\""#, count: 10_000)

        XCTAssertEqual(
            DeveloperSecretRedactor().redact(adversarialQuotes).text,
            "[REDACTED_SECRET]"
        )
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
