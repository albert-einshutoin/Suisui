import Darwin
import Foundation
import SoloPMCore

@main
struct SoloPMCLI {
    static func main() async {
        let exitCode = await run(arguments: Array(CommandLine.arguments.dropFirst()))
        exit(exitCode.rawValue)
    }

    private static func run(arguments: [String]) async -> SoloPMCLIExitCode {
        do {
            let invocation = try SoloPMCLIParser().parse(arguments)
            return await run(invocation: invocation)
        } catch let error as SoloPMCLIParseError {
            fputs("\(error.message)\n", stderr)
            return error.exitCode
        } catch {
            fputs("Unexpected error: \(error.localizedDescription)\n", stderr)
            return .runtimeFailure
        }
    }

    private static func run(invocation: SoloPMCLIInvocation) async -> SoloPMCLIExitCode {
        switch invocation.command {
        case .help:
            print(SoloPMCLIUsage.text)
            return .success
        case .status:
            print("status: local read command skeleton")
            print("database: \(SoloPMCLIDatabaseConnectionPolicy.appDefaultReadOnly.description)")
            return .success
        case .tasksDue:
            print("tasks due: local read command skeleton")
            print("database: \(SoloPMCLIDatabaseConnectionPolicy.appDefaultReadOnly.description)")
            return .success
        case .framesSearch(let query):
            print("frames search: \(query)")
            print("database: \(SoloPMCLIDatabaseConnectionPolicy.appDefaultReadOnly.description)")
            return .success
        case .planValidate(let path):
            return validatePlan(atPath: path)
        }
    }

    private static func validatePlan(atPath path: String) -> SoloPMCLIExitCode {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let result = ActionPlanValidator().validate(jsonData: data)
            for issue in result.issues {
                print("\(issue.severity.rawValue): \(issue.path): \(issue.message)")
            }
            return SoloPMCLIExitCode.planValidation(result)
        } catch {
            fputs("plan validate failed: \(error.localizedDescription)\n", stderr)
            return .runtimeFailure
        }
    }
}
