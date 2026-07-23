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
            clientVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        )
    }
}
