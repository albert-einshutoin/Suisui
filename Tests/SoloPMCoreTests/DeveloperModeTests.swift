import XCTest
@testable import SoloPMCore

final class DeveloperModeTests: XCTestCase {
    func testDeveloperToolsStayHiddenUntilExplicitOptIn() throws {
        let root = temporaryDirectory()
        let runner = RecordingGitCommandRunner()
        let disabled = DeveloperModeSettings(
            isEnabled: false,
            workspaceRoot: root,
            enabledCapabilities: [.gitReadOnly]
        )

        let disabledRegistry = try ToolRegistryFactory.developerMode(
            settings: disabled,
            gitRunner: runner
        )

        XCTAssertFalse(disabledRegistry.contains(.gitStatus))
        XCTAssertFalse(disabledRegistry.contains(.gitBranch))
        XCTAssertEqual(disabled.permissionDisclosureItems, [])

        let enabled = DeveloperModeSettings(
            isEnabled: true,
            workspaceRoot: root,
            enabledCapabilities: [.gitReadOnly]
        )
        let enabledRegistry = try ToolRegistryFactory.developerMode(
            settings: enabled,
            gitRunner: runner
        )

        XCTAssertTrue(enabledRegistry.contains(.gitStatus))
        XCTAssertTrue(enabledRegistry.contains(.gitBranch))
        XCTAssertTrue(enabledRegistry.contains(.gitLogSummary))
        XCTAssertTrue(enabledRegistry.contains(.gitDiffSummary))
        XCTAssertTrue(enabled.permissionDisclosureItems.contains(.gitReadOnly))
        XCTAssertTrue(enabled.permissionDisclosures.contains {
            $0.capability == .gitReadOnly && $0.summary.contains("selected workspace only")
        })
    }

    func testDeveloperModeRequiresSelectedWorkspaceForTools() throws {
        let settings = DeveloperModeSettings(
            isEnabled: true,
            workspaceRoot: nil,
            enabledCapabilities: [.gitReadOnly]
        )

        XCTAssertThrowsError(try ToolRegistryFactory.developerMode(
            settings: settings,
            gitRunner: RecordingGitCommandRunner()
        )) { error in
            XCTAssertEqual(error as? DeveloperModeError, .workspaceRequired)
        }
    }

    func testDefaultPlanningRequestDoesNotExposeDeveloperTools() {
        let request = PlanningRequest(userInput: "Create a normal task")

        XCTAssertFalse(request.availableTools.contains(.gitStatus))
        XCTAssertFalse(request.availableTools.contains(.gitBranch))
        XCTAssertFalse(request.availableTools.contains(.gitLogSummary))
        XCTAssertFalse(request.availableTools.contains(.gitDiffSummary))
        XCTAssertEqual(ActionTool.developerModePlanningTools, [
            .gitStatus,
            .gitBranch,
            .gitLogSummary,
            .gitDiffSummary,
            .developmentPreparePullRequestWorkflow,
            .developmentRepositoryReadFile,
            .developmentRepositoryCreateFile,
            .developmentRepositoryUpdateFile,
            .developmentRunVerification
        ])
    }

    func testDevelopmentPRWorkflowToolRequiresExplicitOptInAndProjectStores() throws {
        let root = temporaryDirectory()
        let connection = try SQLiteConnection(path: ":memory:")
        try DeveloperModeTestMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let projectStore = SQLiteProjectStore(connection: connection)
        let taskStore = SQLiteTaskStore(connection: connection)

        let gitOnlyRegistry = try ToolRegistryFactory.developerMode(
            settings: DeveloperModeSettings(
                isEnabled: true,
                workspaceRoot: root,
                enabledCapabilities: [.gitReadOnly]
            ),
            gitRunner: RecordingGitCommandRunner(),
            projectStore: projectStore,
            taskStore: taskStore
        )

        XCTAssertFalse(gitOnlyRegistry.contains(.developmentPreparePullRequestWorkflow))

        XCTAssertThrowsError(try ToolRegistryFactory.developerMode(
            settings: DeveloperModeSettings(
                isEnabled: true,
                workspaceRoot: root,
                enabledCapabilities: [.developmentPRWorkflow]
            ),
            gitRunner: RecordingGitCommandRunner()
        )) { error in
            XCTAssertEqual(error as? DeveloperModeError, .projectStoresRequired)
        }

        let developmentRegistry = try ToolRegistryFactory.developerMode(
            settings: DeveloperModeSettings(
                isEnabled: true,
                workspaceRoot: root,
                enabledCapabilities: [.developmentPRWorkflow]
            ),
            gitRunner: RecordingGitCommandRunner(),
            projectStore: projectStore,
            taskStore: taskStore
        )

        XCTAssertTrue(developmentRegistry.contains(.developmentPreparePullRequestWorkflow))
        XCTAssertTrue(DeveloperModeCapability.developmentPRWorkflow.disclosure.summary.contains("separate approval"))
    }

    func testGitStatusToolParsesBranchAndDirtyEntries() throws {
        let root = temporaryDirectory()
        let runner = RecordingGitCommandRunner()
        runner.stub(
            arguments: ["status", "--short", "--branch"],
            output: GitCommandOutput(
                standardOutput: """
                ## feature/phase6-developer-mode
                 M Package.swift
                ?? Sources/SoloPMCore/DeveloperMode/GitReadOnlyTools.swift
                """,
                standardError: "",
                exitCode: 0
            )
        )
        let registry = try ToolRegistryFactory.developerMode(
            settings: DeveloperModeSettings(
                isEnabled: true,
                workspaceRoot: root,
                enabledCapabilities: [.gitReadOnly]
            ),
            gitRunner: runner
        )

        let result = try registry.tool(named: .gitStatus).execute(
            arguments: [:],
            context: ToolExecutionContext(source: .developerTool)
        )

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(result.output["branch"]?.stringValue, "feature/phase6-developer-mode")
        XCTAssertEqual(result.output["isClean"]?.boolValue, false)
        XCTAssertEqual(result.output["entries"]?.arrayValue.count, 2)
        XCTAssertEqual(runner.recordedInvocations, [
            GitCommandInvocation(arguments: ["status", "--short", "--branch"], workingDirectory: root)
        ])
    }

    func testGitClientReportsMissingWorkspaceBeforeRunningCommand() {
        let missingRoot = temporaryDirectory().appendingPathComponent("missing", isDirectory: true)
        let runner = RecordingGitCommandRunner()
        let client = GitReadOnlyClient(workspaceRoot: missingRoot, runner: runner)

        XCTAssertThrowsError(try client.status()) { error in
            XCTAssertEqual(error as? GitReadOnlyError, .workspaceUnavailable(missingRoot.path))
        }
        XCTAssertEqual(runner.recordedInvocations, [])
    }

    func testGitClientReportsCommandFailureForNonGitDirectory() throws {
        let root = temporaryDirectory()
        let runner = RecordingGitCommandRunner()
        runner.stub(
            arguments: ["status", "--short", "--branch"],
            output: GitCommandOutput(
                standardOutput: "",
                standardError: "fatal: not a git repository",
                exitCode: 128
            )
        )
        let client = GitReadOnlyClient(workspaceRoot: root, runner: runner)

        XCTAssertThrowsError(try client.status()) { error in
            XCTAssertEqual(
                error as? GitReadOnlyError,
                .commandFailed(
                    arguments: ["status", "--short", "--branch"],
                    exitCode: 128,
                    standardError: "fatal: not a git repository"
                )
            )
        }
    }

    func testGitAllowlistExcludesDestructiveCommands() {
        XCTAssertTrue(GitReadOnlyCommandPolicy.isAllowed(arguments: ["status", "--short", "--branch"]))
        XCTAssertTrue(GitReadOnlyCommandPolicy.isAllowed(arguments: ["branch", "--show-current"]))
        XCTAssertTrue(GitReadOnlyCommandPolicy.isAllowed(arguments: ["log", "--oneline", "-n", "10"]))
        XCTAssertTrue(GitReadOnlyCommandPolicy.isAllowed(arguments: ["diff", "--stat"]))

        XCTAssertFalse(GitReadOnlyCommandPolicy.isAllowed(arguments: ["push"]))
        XCTAssertFalse(GitReadOnlyCommandPolicy.isAllowed(arguments: ["reset", "--hard"]))
        XCTAssertFalse(GitReadOnlyCommandPolicy.isAllowed(arguments: ["checkout", "--", "README.md"]))
        XCTAssertFalse(GitReadOnlyCommandPolicy.isAllowed(arguments: ["clean", "-fd"]))
        XCTAssertFalse(ActionTool.allCases.contains { $0.rawValue == "git.push" })
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SoloPMDeveloperModeTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class RecordingGitCommandRunner: GitCommandRunner, @unchecked Sendable {
    private var stubs: [String: GitCommandOutput] = [:]
    private(set) var recordedInvocations: [GitCommandInvocation] = []

    func stub(arguments: [String], output: GitCommandOutput) {
        stubs[arguments.joined(separator: "\u{1f}")] = output
    }

    func runGit(arguments: [String], workingDirectory: URL) throws -> GitCommandOutput {
        recordedInvocations.append(GitCommandInvocation(arguments: arguments, workingDirectory: workingDirectory))
        return stubs[arguments.joined(separator: "\u{1f}")] ?? GitCommandOutput(
            standardOutput: "",
            standardError: "unexpected command",
            exitCode: 127
        )
    }
}

private enum DeveloperModeTestMigrationRunner {
    static func migrate(connection: SQLiteConnection, migrations: [DatabaseMigration]) throws {
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS schema_migrations (
                id TEXT PRIMARY KEY NOT NULL,
                applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );
            """
        )
        let alreadyApplied = Set(try connection.queryStrings("SELECT id FROM schema_migrations ORDER BY id;"))
        for migration in migrations where !alreadyApplied.contains(migration.id) {
            try migration.apply(connection)
            try connection.execute("INSERT INTO schema_migrations (id) VALUES ('\(migration.id)');")
        }
    }
}

private extension JSONValue {
    var stringValue: String? {
        guard case .string(let value) = self else {
            return nil
        }
        return value
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else {
            return nil
        }
        return value
    }

    var arrayValue: [JSONValue] {
        guard case .array(let values) = self else {
            return []
        }
        return values
    }
}
