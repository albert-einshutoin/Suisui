import Foundation

public enum EncryptedSyncAlgorithm: String, Codable, Equatable, Sendable {
    case xChaCha20Poly1305 = "xchacha20_poly1305"
}

public struct EncryptedSyncPayload: Codable, Equatable, Sendable {
    public var algorithm: EncryptedSyncAlgorithm
    public var keyID: String
    public var nonce: String
    public var ciphertext: String
    public var plaintextDigest: String

    public init(
        algorithm: EncryptedSyncAlgorithm,
        keyID: String,
        nonce: String,
        ciphertext: String,
        plaintextDigest: String
    ) {
        self.algorithm = algorithm
        self.keyID = keyID
        self.nonce = nonce
        self.ciphertext = ciphertext
        self.plaintextDigest = plaintextDigest
    }
}

public enum SyncLedgerEntityKind: String, Codable, Equatable, Sendable {
    case project
    case task
    case settings
    case conversation
}

public struct SyncLedgerEntity: Codable, Equatable, Sendable {
    public var kind: SyncLedgerEntityKind
    public var id: String

    public init(kind: SyncLedgerEntityKind, id: String) {
        self.kind = kind
        self.id = id
    }
}

public enum SyncLedgerOperation: String, Codable, Equatable, Sendable {
    case create
    case update
    case delete
    case recover
}

public enum CloudSyncMergeResolution: String, Codable, Equatable, Sendable {
    case appendLedgerEntry
    case fieldWiseLastWriterWins
    case requiresReview
    case recoverAsPendingReview
}

public struct SyncLedgerEntry: Codable, Equatable, Sendable {
    public var id: String
    public var deviceID: String
    public var sequence: Int64
    public var entity: SyncLedgerEntity
    public var operation: SyncLedgerOperation
    public var encryptedPayload: EncryptedSyncPayload
    public var parentEntryID: String?
    public var createdAt: String
    public var mergePolicy: CloudSyncMergeResolution
    public var redactedAuditSummary: String?

    public init(
        id: String,
        deviceID: String,
        sequence: Int64,
        entity: SyncLedgerEntity,
        operation: SyncLedgerOperation,
        encryptedPayload: EncryptedSyncPayload,
        parentEntryID: String?,
        createdAt: String,
        mergePolicy: CloudSyncMergeResolution,
        redactedAuditSummary: String?
    ) {
        self.id = id
        self.deviceID = deviceID
        self.sequence = sequence
        self.entity = entity
        self.operation = operation
        self.encryptedPayload = encryptedPayload
        self.parentEntryID = parentEntryID
        self.createdAt = createdAt
        self.mergePolicy = mergePolicy
        // Ledger metadata is cloud-visible even when the payload is encrypted, so redact summaries at the envelope boundary.
        self.redactedAuditSummary = redactedAuditSummary.map { DeveloperSecretRedactor().redact($0).text }
    }
}

public enum CloudSyncSafeSettingsField: String, Codable, CaseIterable, Equatable, Sendable {
    case appearancePreference = "appearance_preference"
    case selectedLLMProviderID = "selected_llm_provider_id"
    case geminiModelID = "gemini_model_id"
    case openAIModelID = "openai_model_id"
    case syncEnabled = "sync_enabled"
}

public enum CloudSyncExcludedPlaintextClass: String, Codable, CaseIterable, Equatable, Sendable {
    case providerAPIKeys = "provider_api_keys"
    case mcpEnvironmentSecretValues = "mcp_environment_secret_values"
    case oauthTokens = "oauth_tokens"
    case localFilePaths = "local_file_paths"
    case rawDocumentBodies = "raw_document_bodies"
}

public struct CloudSyncDataPolicy: Codable, Equatable, Sendable {
    public var includedDataClasses: [SyncDataClass]
    public var safeSettingsFields: Set<CloudSyncSafeSettingsField>
    public var excludedPlaintextClasses: Set<CloudSyncExcludedPlaintextClass>

    public init(
        includedDataClasses: [SyncDataClass],
        safeSettingsFields: Set<CloudSyncSafeSettingsField>,
        excludedPlaintextClasses: Set<CloudSyncExcludedPlaintextClass>
    ) {
        self.includedDataClasses = includedDataClasses
        self.safeSettingsFields = safeSettingsFields
        self.excludedPlaintextClasses = excludedPlaintextClasses
    }

    public static let defaultPersonalSync = CloudSyncDataPolicy(
        includedDataClasses: [.projects, .tasks, .settings, .conversations],
        safeSettingsFields: [
            .appearancePreference,
            .selectedLLMProviderID,
            .geminiModelID,
            .openAIModelID,
            .syncEnabled
        ],
        excludedPlaintextClasses: Set(CloudSyncExcludedPlaintextClass.allCases)
    )

    public func allowsPlaintextSync(of excludedClass: CloudSyncExcludedPlaintextClass) -> Bool {
        !excludedPlaintextClasses.contains(excludedClass)
    }
}

public enum CloudSyncPlaintextViolation: Error, Equatable, Sendable {
    case forbiddenField(String)
}

public struct CloudSyncPlaintextGuard: Sendable {
    public var policy: CloudSyncDataPolicy

    public init(policy: CloudSyncDataPolicy) {
        self.policy = policy
    }

    public func validatePlaintextFields(_ fields: [String: String]) throws {
        let sortedKeys = fields.keys.sorted()
        // Provider credentials are the highest-risk accidental leak, so report them before secondary MCP/OAuth findings.
        for key in sortedKeys {
            let normalized = key.lowercased()
            if !policy.allowsPlaintextSync(of: .providerAPIKeys),
               isForbiddenProviderKey(normalized) {
                throw CloudSyncPlaintextViolation.forbiddenField(key)
            }
        }

        for key in sortedKeys {
            let normalized = key.lowercased()
            if !policy.allowsPlaintextSync(of: .mcpEnvironmentSecretValues),
               isForbiddenMCPSecret(normalized) {
                throw CloudSyncPlaintextViolation.forbiddenField(key)
            }
        }

        for key in sortedKeys {
            let normalized = key.lowercased()
            if !policy.allowsPlaintextSync(of: .oauthTokens),
               isForbiddenOAuthToken(normalized) {
                throw CloudSyncPlaintextViolation.forbiddenField(key)
            }
        }
    }

    private func isForbiddenProviderKey(_ key: String) -> Bool {
        key.contains("api_key") || key.contains("apikey") || key.contains("provider_key")
    }

    private func isForbiddenMCPSecret(_ key: String) -> Bool {
        key.contains("mcp") && (key.contains("env") || key.contains("secret") || key.contains("token"))
    }

    private func isForbiddenOAuthToken(_ key: String) -> Bool {
        key.contains("oauth") || key.contains("refresh_token") || key.contains("access_token")
    }
}

public enum CloudSyncMergeScenario: String, Codable, CaseIterable, Equatable, Sendable {
    case offlineCreateWithoutRemote
    case concurrentFieldUpdate
    case sameFieldConflict
    case deletedRemoteWithLocalUpdate
}

public struct CloudSyncMergePolicy: Codable, Equatable, Sendable {
    public var resolutions: [CloudSyncMergeScenario: CloudSyncMergeResolution]

    public init(resolutions: [CloudSyncMergeScenario: CloudSyncMergeResolution]) {
        self.resolutions = resolutions
    }

    public static let defaultPersonalSync = CloudSyncMergePolicy(
        resolutions: [
            // Offline capture should never block basic task creation; ambiguous destructive outcomes are routed to review below.
            .offlineCreateWithoutRemote: .appendLedgerEntry,
            .concurrentFieldUpdate: .fieldWiseLastWriterWins,
            .sameFieldConflict: .requiresReview,
            .deletedRemoteWithLocalUpdate: .recoverAsPendingReview
        ]
    )

    public func resolution(for scenario: CloudSyncMergeScenario) -> CloudSyncMergeResolution {
        resolutions[scenario] ?? .requiresReview
    }
}
