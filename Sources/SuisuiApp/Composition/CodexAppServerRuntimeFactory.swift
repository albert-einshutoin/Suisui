import Foundation
import SuisuiCore

enum CodexAppServerRuntimeFactory {
    static func makeProvider(settings: AppSettings) -> any LLMProvider {
        let normalized = settings.normalizedForRuntime
        return CodexLocalRuntimeProvider(
            approvedExecutableProvider: {
                guard let current = try? UserDefaultsAppSettingsStore().load().normalizedForRuntime,
                      current.aiProvider == .codexLocal,
                      current.isCodexLocalExecutionApproved else {
                    return nil
                }
                return current.approvedCodexExecutable
            },
            modelID: normalized.codexModelID,
            clientVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            approvalInvalidator: {
                let store = UserDefaultsAppSettingsStore()
                guard var current = try? store.load(),
                      current.approvedCodexExecutable != nil else {
                    CodexExecutionApprovalChanges.invalidate()
                    return
                }
                current.isCodexLocalExecutionApproved = false
                current.approvedCodexExecutable = nil
                // A failed save must still stop in-memory operations. The next
                // launch will re-run identity verification and fail closed.
                try? store.save(current)
                CodexExecutionApprovalChanges.invalidate()
            }
        )
    }
}
