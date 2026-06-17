import Foundation

public enum SoloPMCLICommand: Equatable, Sendable {
    case help
    case status
    case tasksDue
    case planValidate(path: String)
    case framesSearch(query: String)
}

public struct SoloPMCLIInvocation: Equatable, Sendable {
    public var command: SoloPMCLICommand

    public init(command: SoloPMCLICommand) {
        self.command = command
    }
}

public enum SoloPMCLIExitCode: Int32, Equatable, Sendable {
    case success = 0
    case runtimeFailure = 1
    case usage = 64
    case validationFailed = 65

    public static func planValidation(_ result: ActionPlanValidationResult) -> SoloPMCLIExitCode {
        result.isValid ? .success : .validationFailed
    }
}

public struct SoloPMCLIParseError: Error, Equatable, Sendable {
    public var message: String
    public var exitCode: SoloPMCLIExitCode

    public init(message: String, exitCode: SoloPMCLIExitCode = .usage) {
        self.message = message
        self.exitCode = exitCode
    }
}

public enum SoloPMCLIUsage {
    public static let text = """
    Usage:
      solopm-cli status
      solopm-cli tasks due
      solopm-cli plan validate <path>
      solopm-cli frames search <query>
      solopm-cli help

    Commands are read-only except plan validation. GUI and task writes must go through SoloPM review.
    """
}

public enum SoloPMCLIDatabaseConnectionPolicy: Equatable, Sendable {
    case appDefaultReadOnly

    public var description: String {
        switch self {
        case .appDefaultReadOnly:
            "app default database, read-only"
        }
    }
}

public struct SoloPMCLIParser: Sendable {
    public init() {}

    public func parse(_ arguments: [String]) throws -> SoloPMCLIInvocation {
        switch arguments {
        case [], ["help"], ["--help"], ["-h"]:
            return SoloPMCLIInvocation(command: .help)
        case ["status"]:
            return SoloPMCLIInvocation(command: .status)
        case ["tasks", "due"]:
            return SoloPMCLIInvocation(command: .tasksDue)
        case let values where values.count == 3
            && values[0] == "plan"
            && values[1] == "validate"
            && !values[2].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty:
            let path = values[2]
            return SoloPMCLIInvocation(command: .planValidate(path: path))
        case let values where values.count >= 3 && values[0] == "frames" && values[1] == "search":
            let query = values.dropFirst(2).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else {
                throw SoloPMCLIParseError(message: "frames search requires a query.")
            }
            return SoloPMCLIInvocation(command: .framesSearch(query: query))
        default:
            throw SoloPMCLIParseError(message: "Unsupported command.\n\(SoloPMCLIUsage.text)")
        }
    }
}
