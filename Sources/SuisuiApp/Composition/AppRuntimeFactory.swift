import Foundation
import SuisuiCore

enum AppRuntimeFactory {
    private static let sharedSecretStore: any SecretStore = {
        if ProcessInfo.processInfo.environment["SUISUI_DISABLE_KEYCHAIN_SECRET_STORE"] == "1" {
            return LaunchVerificationSecretStore()
        }
        return KeychainSecretStore()
    }()

    static func migratedConnection() throws -> SQLiteConnection {
        let connection = try SQLiteConnection(path: applicationDatabaseURL().path)
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        return connection
    }

    static func makeSecretStore() -> any SecretStore {
        // Runtime surfaces can be recreated as windows open and close. Sharing the store keeps
        // successful Keychain reads in one process-local cache instead of prompting per surface.
        return sharedSecretStore
    }

    static func makeEntitlementStore(secretStore: any SecretStore) -> KeychainEntitlementStore {
        KeychainEntitlementStore(
            secretStore: secretStore,
            verifier: makeLocalLicenseVerifier()
        )
    }

    static func makeLocalLicenseVerifier() -> any LocalLicenseVerifier {
        guard let publicKeyBase64 = Bundle.main.object(forInfoDictionaryKey: "SuisuiLocalLicensePublicKey") as? String,
              !publicKeyBase64.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return NoBundledLocalLicenseVerifier()
        }
        return SignedLocalLicenseVerifier(publicKeyBase64: publicKeyBase64)
    }

    static func makeAuditLogger() throws -> any AuditLogger {
        RedactingAuditLogger(base: try SQLiteAuditLogger(path: applicationDatabaseURL().path))
    }

    static func makeExecutionReceiptStore() throws -> any ExecutionReceiptStore {
        try FileExecutionReceiptStore(
            directoryURL: applicationSupportDirectoryURL().appendingPathComponent("ExecutionReceipts", isDirectory: true)
        )
    }

    static func makeSmartListStore() throws -> any SmartListStore {
        try FileSmartListStore(
            directoryURL: applicationSupportDirectoryURL().appendingPathComponent("SmartLists", isDirectory: true)
        )
    }

    static func makeSmartListStoreIfAvailable() -> (any SmartListStore)? {
        // Smart lists degrade gracefully: presets still work if Application
        // Support is unavailable, so the board never blocks on this store.
        try? makeSmartListStore()
    }

    static func makeMailDraftClient() throws -> any MailDraftClient {
        LocalFileMailDraftClient(
            draftsDirectoryURL: try applicationSupportDirectoryURL().appendingPathComponent("MailDrafts", isDirectory: true)
        )
    }

    static func makeWorkspaceBackupExporter() throws -> WorkspaceBackupExporter {
        let connection = try migratedConnection()
        return WorkspaceBackupExporter(
            projectStore: SQLiteProjectStore(connection: connection),
            taskStore: SQLiteTaskStore(connection: connection),
            knowledgeFrameStore: SQLiteKnowledgeFrameStore(connection: connection)
        )
    }

    static func makeWorkspaceBackupImporter() throws -> WorkspaceBackupImporter {
        let connection = try migratedConnection()
        return WorkspaceBackupImporter(
            projectStore: SQLiteProjectStore(connection: connection),
            taskStore: SQLiteTaskStore(connection: connection),
            knowledgeFrameStore: SQLiteKnowledgeFrameStore(connection: connection)
        )
    }

    static func postProjectBoardDidChange() {
        NotificationCenter.default.post(name: .suisuiProjectBoardDidChange, object: nil)
    }

    static func applicationDatabaseURL() throws -> URL {
        try SuisuiAppDatabaseLocation.defaultDatabaseURL(createDirectory: true)
    }

    static func applicationSupportDirectoryURL() throws -> URL {
        try SuisuiAppDatabaseLocation.applicationSupportDirectoryURL(createDirectory: true)
    }
}

struct RuntimeSettingsLoadResult {
    let settings: AppSettings
    let errorMessage: String?

    init(settings: AppSettings, errorMessage: String? = nil) {
        self.settings = settings
        self.errorMessage = errorMessage
    }
}

private struct LaunchVerificationSecretStore: SecretStore {
    func save(_ value: String, for key: SecretKey) throws {
        throw SecretStoreError.unexpectedStatus(-25308)
    }

    func read(_ key: SecretKey) throws -> String? {
        return nil
    }

    func delete(_ key: SecretKey) throws {
        throw SecretStoreError.unexpectedStatus(-25308)
    }
}

extension JSONValue {
    var stringValue: String? {
        guard case .string(let value) = self else {
            return nil
        }
        return value
    }

    var displayValue: String {
        switch self {
        case .string(let value):
            value
        case .number(let value):
            String(value)
        case .bool(let value):
            value ? "true" : "false"
        case .object:
            "object"
        case .array:
            "list"
        case .null:
            "null"
        }
    }
}
