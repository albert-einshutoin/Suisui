import Foundation

public enum SuisuiCLICommand: Equatable, Sendable {
    case help
    case status
    case tasksDue
    case planValidate(path: String)
    case framesSearch(query: String)
}

public struct SuisuiCLIInvocation: Equatable, Sendable {
    public var command: SuisuiCLICommand

    public init(command: SuisuiCLICommand) {
        self.command = command
    }
}

public enum SuisuiCLIExitCode: Int32, Equatable, Sendable {
    case success = 0
    case runtimeFailure = 1
    case usage = 64
    case validationFailed = 65

    public static func planValidation(_ result: ActionPlanValidationResult) -> SuisuiCLIExitCode {
        result.isValid ? .success : .validationFailed
    }
}

public struct SuisuiCLIParseError: Error, Equatable, Sendable {
    public var message: String
    public var exitCode: SuisuiCLIExitCode

    public init(message: String, exitCode: SuisuiCLIExitCode = .usage) {
        self.message = message
        self.exitCode = exitCode
    }
}

public enum SuisuiCLIUsage {
    public static let text = """
    Usage:
      suisui-cli status
      suisui-cli tasks due
      suisui-cli plan validate <path>
      suisui-cli frames search <query>
      suisui-cli help

    Commands are read-only except plan validation. GUI and task writes must go through Suisui review.
    """
}

public struct SuisuiCLIParser: Sendable {
    public init() {}

    public func parse(_ arguments: [String]) throws -> SuisuiCLIInvocation {
        switch arguments {
        case [], ["help"], ["--help"], ["-h"]:
            return SuisuiCLIInvocation(command: .help)
        case ["status"]:
            return SuisuiCLIInvocation(command: .status)
        case ["tasks", "due"]:
            return SuisuiCLIInvocation(command: .tasksDue)
        case let values where values.count == 3
            && values[0] == "plan"
            && values[1] == "validate"
            && !values[2].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty:
            let path = values[2]
            return SuisuiCLIInvocation(command: .planValidate(path: path))
        case let values where values.count >= 3 && values[0] == "frames" && values[1] == "search":
            let query = values.dropFirst(2).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else {
                throw SuisuiCLIParseError(message: "frames search requires a query.")
            }
            return SuisuiCLIInvocation(command: .framesSearch(query: query))
        default:
            throw SuisuiCLIParseError(message: "Unsupported command.\n\(SuisuiCLIUsage.text)")
        }
    }
}
