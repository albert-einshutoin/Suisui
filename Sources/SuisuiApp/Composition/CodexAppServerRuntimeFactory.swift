import Foundation
import SuisuiCore

enum CodexAppServerRuntimeFactory {
    static func makeProvider(settings: AppSettings) -> any LLMProvider {
        let normalized = settings.normalizedForRuntime
        return CodexLocalRuntimeProvider(
            approvedExecutable: normalized.isCodexLocalExecutionApproved
                ? normalized.approvedCodexExecutable
                : nil,
            modelID: normalized.codexModelID,
            clientVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        )
    }
}
