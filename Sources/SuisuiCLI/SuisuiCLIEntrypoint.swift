import Darwin
import Foundation
import SuisuiCore

@main
struct SuisuiCLI {
    static func main() async {
        let exitCode = await run(arguments: Array(CommandLine.arguments.dropFirst()))
        exit(exitCode.rawValue)
    }

    private static func run(arguments: [String]) async -> SuisuiCLIExitCode {
        do {
            let invocation = try SuisuiCLIParser().parse(arguments)
            return await run(invocation: invocation)
        } catch let error as SuisuiCLIParseError {
            fputs("\(error.message)\n", stderr)
            return error.exitCode
        } catch {
            fputs("Unexpected error: Suisui CLI failed unexpectedly.\n", stderr)
            return .runtimeFailure
        }
    }

    private static func run(invocation: SuisuiCLIInvocation) async -> SuisuiCLIExitCode {
        switch invocation.command {
        case .help:
            print(SuisuiCLIUsage.text)
            return .success
        case .status:
            return printReadOnlyLines { try $0.statusLines() }
        case .tasksDue:
            return printReadOnlyLines { try $0.tasksDueLines() }
        case .framesSearch(let query):
            return printReadOnlyLines { try $0.framesSearchLines(query: query) }
        case .planValidate(let path):
            return validatePlan(atPath: path)
        }
    }

    private static func printReadOnlyLines(_ makeLines: (SuisuiCLIReadOnlyReporter) throws -> [String]) -> SuisuiCLIExitCode {
        do {
            let reporter = SuisuiCLIReadOnlyReporter(
                databaseURL: try SuisuiAppDatabaseLocation.defaultDatabaseURL(createDirectory: false)
            )
            for line in try makeLines(reporter) {
                print(line)
            }
            return .success
        } catch {
            fputs("local read failed: Suisui local data could not be read.\n", stderr)
            return .runtimeFailure
        }
    }

    private static func validatePlan(atPath path: String) -> SuisuiCLIExitCode {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let result = ActionPlanValidator().validate(jsonData: data)
            for issue in result.issues {
                print("\(issue.severity.rawValue): \(issue.path): \(issue.message)")
            }
            return SuisuiCLIExitCode.planValidation(result)
        } catch {
            fputs("plan validate failed: Action plan file could not be read or validated.\n", stderr)
            return .runtimeFailure
        }
    }
}
