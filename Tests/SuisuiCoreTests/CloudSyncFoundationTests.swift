import XCTest
@testable import SuisuiCore

final class CloudSyncFoundationTests: XCTestCase {
    func testLedgerEntryEncodesEncryptedPayloadWithoutPlaintextSecrets() throws {
        let secret = "sk-cloud-sync-secret"
        let encryptedPayload = EncryptedSyncPayload(
            algorithm: .xChaCha20Poly1305,
            keyID: "device-key-1",
            nonce: "nonce-base64",
            ciphertext: "ciphertext-base64",
            plaintextDigest: "sha256-digest"
        )

        let entry = SyncLedgerEntry(
            id: "ledger-1",
            deviceID: "macbook",
            sequence: 7,
            entity: SyncLedgerEntity(kind: .task, id: "task-42"),
            operation: .update,
            encryptedPayload: encryptedPayload,
            parentEntryID: "ledger-0",
            createdAt: "2026-06-21T06:00:00Z",
            mergePolicy: .fieldWiseLastWriterWins,
            redactedAuditSummary: "Updated task token=\(secret)"
        )

        let encoded = try String(data: JSONEncoder().encode(entry), encoding: .utf8).unwrapForTest()

        XCTAssertTrue(encoded.contains("ciphertext-base64"))
        XCTAssertTrue(encoded.contains("xchacha20_poly1305"))
        XCTAssertFalse(encoded.contains(secret))
        XCTAssertFalse(encoded.contains("Updated task token=\(secret)"))
        XCTAssertTrue(encoded.contains("[REDACTED_SECRET]"))
    }

    func testSyncDataPolicyDocumentsIncludedAndExcludedDataClasses() {
        let policy = CloudSyncDataPolicy.defaultPersonalSync

        XCTAssertEqual(policy.includedDataClasses, [.projects, .tasks, .settings, .conversations])
        XCTAssertTrue(policy.safeSettingsFields.contains(.appearancePreference))
        XCTAssertTrue(policy.safeSettingsFields.contains(.selectedLLMProviderID))
        XCTAssertTrue(policy.excludedPlaintextClasses.contains(.providerAPIKeys))
        XCTAssertTrue(policy.excludedPlaintextClasses.contains(.mcpEnvironmentSecretValues))
        XCTAssertTrue(policy.excludedPlaintextClasses.contains(.oauthTokens))
        XCTAssertTrue(policy.excludedPlaintextClasses.contains(.localFilePaths))
        XCTAssertFalse(policy.allowsPlaintextSync(of: .providerAPIKeys))
        XCTAssertFalse(policy.allowsPlaintextSync(of: .oauthTokens))
    }

    func testPlaintextPayloadGuardRejectsProviderMCPAndOAuthSecrets() {
        let guardrail = CloudSyncPlaintextGuard(policy: .defaultPersonalSync)

        XCTAssertThrowsError(
            try guardrail.validatePlaintextFields([
                "openai_api_key": "sk-provider-secret",
                "mcp_env": "GITHUB_TOKEN=actual-token-value",
                "oauth_refresh_token": "refresh-token-value"
            ])
        ) { error in
            XCTAssertEqual(
                error as? CloudSyncPlaintextViolation,
                .forbiddenField("openai_api_key")
            )
        }

        XCTAssertNoThrow(
            try guardrail.validatePlaintextFields([
                "appearance_preference": "system",
                "selected_llm_provider_id": "geminiDirect"
            ])
        )
    }

    func testMergePolicyCoversOfflineCreateUpdateConflictAndDeletedRecovery() {
        XCTAssertEqual(
            CloudSyncMergePolicy.defaultPersonalSync.resolution(for: .offlineCreateWithoutRemote),
            .appendLedgerEntry
        )
        XCTAssertEqual(
            CloudSyncMergePolicy.defaultPersonalSync.resolution(for: .concurrentFieldUpdate),
            .fieldWiseLastWriterWins
        )
        XCTAssertEqual(
            CloudSyncMergePolicy.defaultPersonalSync.resolution(for: .sameFieldConflict),
            .requiresReview
        )
        XCTAssertEqual(
            CloudSyncMergePolicy.defaultPersonalSync.resolution(for: .deletedRemoteWithLocalUpdate),
            .recoverAsPendingReview
        )
    }
}

private extension Optional where Wrapped == String {
    func unwrapForTest(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        try XCTUnwrap(self, file: file, line: line)
    }
}
