import Foundation
import OSLog
import SuisuiCore

/// Starts privacy retention once per real app process without extending the
/// main-actor launch critical path.
@MainActor
final class ConversationRetentionRuntime {
    static let shared = ConversationRetentionRuntime()

    nonisolated private static let logger = Logger(
        subsystem: "dev.suisui.app",
        category: "conversation-retention"
    )
    private static let harnessEnvironmentKeys = [
        "SUISUI_DATABASE_PATH",
        "SUISUI_LAUNCH_RECOVERY_MODE",
        "SUISUI_FORCE_PROJECT_BOARD_FALLBACK",
        "SUISUI_UI_EVIDENCE_RECOVERY_MODE",
        "SUISUI_RUNTIME_CRUD_RECOVERY_MODE",
        "SUISUI_LAYOUT_STABILITY_RECOVERY_MODE",
        "SUISUI_OPEN_SETTINGS_ON_LAUNCH",
        "SUISUI_OPEN_VOICE_COMMAND_ON_LAUNCH",
        "SUISUI_RUNTIME_DEVELOPMENT_PR_SMOKE_BOOKMARK",
    ]

    private var didStart = false

    func start(
        environment: [String: String] =
            ProcessInfo.processInfo.environment,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        guard !didStart,
              Self.shouldStart(
                  environment: environment,
                  bundleIdentifier: bundleIdentifier
              )
        else {
            return
        }
        didStart = true

        Task.detached(priority: .utility) {
            Self.run()
        }
    }

    private static func shouldStart(
        environment: [String: String],
        bundleIdentifier: String?
    ) -> Bool {
        guard bundleIdentifier != nil else {
            return false
        }
        return !harnessEnvironmentKeys.contains { key in
            guard let value = environment[key], !value.isEmpty else {
                return false
            }
            return key == "SUISUI_DATABASE_PATH" || value == "1"
        }
    }

    private nonisolated static func run() {
        do {
            let connection = try AppRuntimeFactory.migratedConnection()
            let report =
                VoiceTaskConversationAutomaticRetentionRunner().run(
                    at: Date(),
                    policy: .init(),
                    store: SQLiteVoiceTaskConversationStore(
                        connection: connection
                    )
                )
            let auditLogger = RedactingAuditLogger(
                base: SQLiteAuditLogger(connection: connection)
            )
            for result in report.results {
                do {
                    try auditLogger.record(
                        auditEvent(for: result)
                    )
                } catch {
                    logger.error(
                        "Automatic conversation retention audit failed scope=\(result.scope.rawValue, privacy: .public) category=\(failureCategory(for: error), privacy: .public)"
                    )
                }
            }
        } catch {
            logger.error(
                "Automatic conversation retention startup failed category=\(failureCategory(for: error), privacy: .public)"
            )
        }
    }

    private nonisolated static func auditEvent(
        for result: VoiceTaskConversationAutomaticRetentionResult
    ) -> AuditEvent {
        var metadata = [
            "scope": result.scope.rawValue,
            "target_count": String(result.targetCount),
        ]
        if let fingerprint = result.reviewedFingerprint {
            metadata["reviewed_fingerprint"] = fingerprint
        }
        if let failureCategory = result.failureCategory {
            metadata["failure_category"] = failureCategory
        }
        let status: AuditStatus
        switch result.status {
        case .completed, .alreadyCompleted:
            status = .succeeded
        case .skipped:
            status = .skipped
        case .failed:
            status = .failed
        }
        return AuditEvent(
            category: "conversation_retention",
            action: "automatic_" + result.scope.rawValue,
            status: status,
            metadata: metadata
        )
    }

    private nonisolated static func failureCategory(
        for error: Error
    ) -> String {
        switch error {
        case is DatabaseError:
            "database_error"
        default:
            "observation_error"
        }
    }
}
