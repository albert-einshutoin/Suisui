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

    func testGitHubTokenFamilyIsRedactedWithCompatiblePatternName() {
        let tokens = ["gho", "ghu", "ghs", "ghr"].map { $0 + "_" + "githubsecretmarker" }
        let redaction = DeveloperSecretRedactor().redact(tokens.joined(separator: "\n"))

        XCTAssertTrue(tokens.allSatisfy { !redaction.text.contains($0) })
        XCTAssertEqual(redaction.report.replacementCount, tokens.count)
        XCTAssertEqual(redaction.report.matchedPatternNames, ["ghp"])
    }

    func testSlackBotAndAppTokensAreRedactedWithoutMatchingShortDocumentation() {
        let tokens = [
            "xoxb-" + "slackdraftsecretmarker",
            "xapp-" + "slackappdraftsecretmarker"
        ]
        let harmless = "Slack prefix xapp-short harmlessslackdraftmarker"
        let redaction = DeveloperSecretRedactor().redact(tokens.joined(separator: "\n") + "\n" + harmless)

        XCTAssertTrue(tokens.allSatisfy { !redaction.text.contains($0) })
        XCTAssertTrue(redaction.text.contains(harmless))
        XCTAssertEqual(redaction.report.replacementCount, tokens.count)
        XCTAssertEqual(redaction.report.matchedPatternNames, ["slack"])
    }

    func testStripeSecretVariantsAndPrivateKeyBlocksAreRedacted() {
        let stripeTokens = ["sk_live", "sk_test", "rk_live", "rk_test"].map {
            $0 + "_" + "stripedraftsecretmarker"
        }
        let privateKeyMarker = "pgpdraftsecretmarker"
        let harmless = "Stripe modes sk_test and rk_live; PGP PRIVATE KEY BLOCK documentation harmlessstripemarker"
        let redaction = DeveloperSecretRedactor().redact(
            stripeTokens.joined(separator: "\n") + "\n" +
                "-----BEGIN PGP PRIVATE KEY BLOCK-----\n\(privateKeyMarker)\n-----END PGP PRIVATE KEY BLOCK-----\n" +
                harmless
        )

        XCTAssertTrue(stripeTokens.allSatisfy { !redaction.text.contains($0) })
        XCTAssertFalse(redaction.text.contains(privateKeyMarker))
        XCTAssertTrue(redaction.text.contains(harmless))
        XCTAssertEqual(Set(redaction.report.matchedPatternNames), ["stripe", "private_key_block"])
    }

    func testReleaseNoteDraftRedactsPrivateKeyBlockEmbeddedAfterPrefix() {
        let marker = "embeddedprivatekeydraftmarker"
        let embeddedKey = #"{"blob":"prefix -----BEGIN PRIVATE KEY-----"# +
            "\n\(marker)\n-----END PRIVATE KEY----- suffix\"}"
        let context = DraftGenerationContext(
            repositoryName: "suisui",
            currentBranch: "release/security",
            gitStatusSummary: "clean",
            commitSummaries: [embeddedKey],
            taskSummaries: [],
            generatedAt: Date(timeIntervalSince1970: 1_783_200_000)
        )

        let draft = DeveloperDraftGenerator().generateReleaseNoteDraft(from: context)

        XCTAssertFalse(draft.body.contains(marker))
        XCTAssertTrue(draft.body.contains("[REDACTED_SECRET]"))
        XCTAssertTrue(draft.redactionReport.matchedPatternNames.contains("private_key_block"))
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

    func testPasswordAliasKeysAreRedactedFromJSONAndConfig() {
        let fixtures = [
            (#"{"db_pass":"db-pass-draft-marker"}"#, "db-pass-draft-marker"),
            (#"{"db_\u0070ass":"escaped-db-pass-draft-marker"}"#, "escaped-db-pass-draft-marker"),
            (#"passwd = "passwd-draft-marker""#, "passwd-draft-marker"),
            ("passphrase: passphrase-draft-marker", "passphrase-draft-marker"),
        ]

        for (fixture, marker) in fixtures {
            let redaction = DeveloperSecretRedactor().redact(fixture)

            XCTAssertFalse(redaction.text.contains(marker), fixture)
            XCTAssertTrue(redaction.text.contains("[REDACTED_SECRET]"), fixture)
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

    func testConnectionURIWithEmptyUsernameIsRedacted() {
        let redisPassword = "redissecretmarker"
        let amqpPassword = "amqpsecretmarker"
        let redaction = DeveloperSecretRedactor().redact(
            "redis://:\(redisPassword)@cache.example/0 amqp://:\(amqpPassword)@queue.example/vhost"
        )

        XCTAssertFalse(redaction.text.contains(redisPassword))
        XCTAssertFalse(redaction.text.contains(amqpPassword))
        XCTAssertTrue(redaction.report.matchedPatternNames.contains("credential_uri"))
        XCTAssertEqual(DeveloperSecretRedactor().redact("redis://cache.example/0").text, "redis://cache.example/0")
    }

    func testAuthorizationHeadersAndJWTsAreRedacted() {
        let bearer = "Bearer bearercredentialmarker"
        let basic = "Basic basiccredentialmarker"
        let shortBearer = "Bearer abc"
        let shortBasic = "Basic dTpw"
        let quotedBearer = "\"Bearer quotedbearermarker\""
        let quotedBasic = "\"Basic quotedbasicmarker\""
        let equalsBearer = "\"Bearer equalsbearermarker\""
        let equalsBasic = "Basic equalsbasicmarker"
        let customToken = "\"Token customtokenmarker\""
        let awsCredential = "AWS4-HMAC-SHA256 Credential=awscredentialmarker"
        let digest = "Digest digestmarker"
        let negotiate = "Negotiate negotiatemarker"
        let jwt = "eyJheadersentinel.payloadsentinel.signaturesentinel"
        let unsignedJWT = "eyJhbGciOiJub25lIn0.e30."
        let trailingHyphenJWT = "eyJhbGciOiJub25lIn0.e30.signaturesentinel-"
        let redaction = DeveloperSecretRedactor().redact(
            "Authorization: \(bearer)\nAuthorization: \(basic)\nAuthorization: \(shortBearer)\nAuthorization: \(shortBasic)\nAuthorization: \(quotedBearer)\n{\"Authorization\":\(quotedBasic)}\nAuthorization = \(equalsBearer)\nAUTHORIZATION=\(equalsBasic)\nAuthorization = \(customToken)\nAuthorization: \(awsCredential)\nAuthorization: \(digest)\nAuthorization: \(negotiate)\nAuthorizationPolicy = harmlessauthorizationmarker\ncredential=\(jwt)\ncredential=\(unsignedJWT)\ncredential=\(trailingHyphenJWT)"
        )

        XCTAssertFalse(redaction.text.contains("bearercredentialmarker"))
        XCTAssertFalse(redaction.text.contains("basiccredentialmarker"))
        XCTAssertFalse(redaction.text.contains("Authorization: Bearer abc"))
        XCTAssertFalse(redaction.text.contains("Authorization: Basic dTpw"))
        XCTAssertFalse(redaction.text.contains("quotedbearermarker"))
        XCTAssertFalse(redaction.text.contains("quotedbasicmarker"))
        XCTAssertFalse(redaction.text.contains("equalsbearermarker"))
        XCTAssertFalse(redaction.text.contains("equalsbasicmarker"))
        XCTAssertFalse(redaction.text.contains("customtokenmarker"))
        XCTAssertFalse(redaction.text.contains("awscredentialmarker"))
        XCTAssertFalse(redaction.text.contains("digestmarker"))
        XCTAssertFalse(redaction.text.contains("negotiatemarker"))
        XCTAssertTrue(redaction.text.contains("harmlessauthorizationmarker"))
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
            #"{"Authoriz\u0061tion":"Bearer escaped-authorization-marker"}"#,
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
