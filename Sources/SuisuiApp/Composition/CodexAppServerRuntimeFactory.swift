import Foundation
import SuisuiCore

enum CodexAppServerRuntimeFactory {
    static func makeProvider(settings: AppSettings) -> any LLMProvider {
        let normalized = settings.normalizedForRuntime
        return CodexLocalRuntimeProvider(
            executablePath: normalized.codexExecutablePath,
            modelID: normalized.codexModelID,
            isExecutionApproved: normalized.isCodexLocalExecutionApproved,
            clientVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        )
    }
}
