import Foundation

public enum ProjectBoardFailure: Equatable, Sendable {
    case initialLoadFailed(String)
    case saveFailed(String)
    case providerFailed(String)
    case readinessCheckFailed(String)

    public var message: String {
        switch self {
        case .initialLoadFailed(let message),
             .saveFailed(let message),
             .providerFailed(let message),
             .readinessCheckFailed(let message):
            return message
        }
    }
}

public enum ProjectBoardErrorPresentation: Equatable, Sendable {
    case fatal(message: String, canRetry: Bool)
    case inline(message: String, canRetry: Bool)

    public static func classify(_ failure: ProjectBoardFailure) -> Self {
        switch failure {
        case .initialLoadFailed(let message):
            return .fatal(message: message, canRetry: true)
        case .saveFailed(let message),
             .providerFailed(let message),
             .readinessCheckFailed(let message):
            return .inline(message: message, canRetry: true)
        }
    }
}
