import XCTest
@testable import SoloPMCore

final class DevelopmentVerificationCommandTests: XCTestCase {
    func testVerificationCommandRequiresApprovalAndRunsAllowlistedCommandInApprovedWorkspace() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try stores.projects.create(title: "SoloPM", workspacePath: workspace.path)
        let runner = RecordingDevelopmentCommandRunner(output: DevelopmentCommandOutput(
            standardOutput: "All tests passed\n",
            standardError: "",
            exitCode: 0
        ))
        let tool = DevelopmentVerificationCommandTool(projectStore: stores.projects, commandRunner: runner)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "commandId": .string("swift.test")
                ],
                context: ToolExecutionContext(source: .reviewUI)
            )
        ) { error in
            XCTAssertEqual(error as? ToolExecutionError, .approvalRequired(.developmentRunVerification))
        }

        let result = try tool.execute(
            arguments: [
                "projectId": .number(Double(project.id)),
                "commandId": .string("swift.test")
            ],
            context: approvedContext()
        )

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(result.output["commandId"], .string("swift.test"))
        XCTAssertEqual(result.output["command"], .string("swift test --quiet"))
        XCTAssertEqual(result.output["passed"], .bool(true))
        XCTAssertEqual(result.output["exitCode"], .number(0))
        XCTAssertEqual(result.output["stdout"], .string("All tests passed\n"))
        XCTAssertEqual(result.output["stderr"], .string(""))
        XCTAssertEqual(runner.recordedInvocations, [
            DevelopmentCommandInvocation(
                executable: "swift",
                arguments: ["test", "--quiet"],
                workingDirectory: workspace.resolvingSymlinksInPath().standardizedFileURL
            )
        ])
    }

    func testVerificationCommandAllowsSecurityRegressionAndGitDiffCheckPresets() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let securityScript = try writeExecutableScript(
            workspace
                .appendingPathComponent("script", isDirectory: true)
                .appendingPathComponent("check_security_regressions.sh", isDirectory: false),
            contents: "#!/bin/sh\nexit 0\n"
        )
        let project = try stores.projects.create(title: "SoloPM", workspacePath: workspace.path)
        let runner = RecordingDevelopmentCommandRunner(output: DevelopmentCommandOutput(
            standardOutput: "",
            standardError: "",
            exitCode: 0
        ))
        let tool = DevelopmentVerificationCommandTool(projectStore: stores.projects, commandRunner: runner)

        _ = try tool.execute(
            arguments: [
                "projectId": .number(Double(project.id)),
                "commandId": .string("git.diff_check")
            ],
            context: approvedContext()
        )
        _ = try tool.execute(
            arguments: [
                "projectId": .number(Double(project.id)),
                "commandId": .string("security.regression_scan")
            ],
            context: approvedContext()
        )

        XCTAssertEqual(runner.recordedInvocations.map(\.commandDisplay), [
            "git diff --check",
            securityScript.resolvingSymlinksInPath().standardizedFileURL.path
        ])
    }

    func testVerificationCommandRejectsSymlinkedRepoLocalPresetBeforeRunning() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let externalScript = try writeExecutableScript(
            temporaryDirectory().appendingPathComponent("outside.sh", isDirectory: false),
            contents: "#!/bin/sh\nexit 0\n"
        )
        let scriptURL = workspace
            .appendingPathComponent("script", isDirectory: true)
            .appendingPathComponent("check_security_regressions.sh", isDirectory: false)
        try FileManager.default.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: scriptURL, withDestinationURL: externalScript)
        let project = try stores.projects.create(title: "SoloPM", workspacePath: workspace.path)
        let runner = RecordingDevelopmentCommandRunner(output: DevelopmentCommandOutput(
            standardOutput: "",
            standardError: "",
            exitCode: 0
        ))
        let tool = DevelopmentVerificationCommandTool(projectStore: stores.projects, commandRunner: runner)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "commandId": .string("security.regression_scan")
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(.developmentRunVerification, "Verification command script must not contain symlink components.")
            )
        }

        XCTAssertEqual(runner.recordedInvocations, [])
    }

    func testVerificationCommandRejectsUnknownDestructiveAndShellLikeCommands() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try stores.projects.create(title: "SoloPM", workspacePath: workspace.path)
        let runner = RecordingDevelopmentCommandRunner(output: DevelopmentCommandOutput(
            standardOutput: "",
            standardError: "",
            exitCode: 0
        ))
        let tool = DevelopmentVerificationCommandTool(projectStore: stores.projects, commandRunner: runner)

        let commandIDs = [
            "git.push",
            "git.reset_hard",
            "swift.package.resolve",
            "shell.run",
            "./script/deploy.sh",
            "swift;rm"
        ]

        for commandID in commandIDs {
            XCTAssertThrowsError(
                try tool.execute(
                    arguments: [
                        "projectId": .number(Double(project.id)),
                        "commandId": .string(commandID)
                    ],
                    context: approvedContext()
                ),
                commandID
            ) { error in
                XCTAssertEqual(
                    error as? ToolExecutionError,
                    .executionFailed(.developmentRunVerification, "Verification command is not in the approved local command allowlist.")
                )
            }
        }

        XCTAssertEqual(runner.recordedInvocations, [])
    }

    func testVerificationCommandRedactsAndTruncatesOutput() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try stores.projects.create(title: "SoloPM", workspacePath: workspace.path)
        let secret = "sk-proj-secretvalue"
        let runner = RecordingDevelopmentCommandRunner(output: DevelopmentCommandOutput(
            standardOutput: "token=\(secret)\n" + String(repeating: "a", count: DevelopmentVerificationOutputPolicy.maximumOutputCharacters + 50),
            standardError: "warning only\n",
            exitCode: 0
        ))
        let tool = DevelopmentVerificationCommandTool(projectStore: stores.projects, commandRunner: runner)

        let result = try tool.execute(
            arguments: [
                "projectId": .number(Double(project.id)),
                "commandId": .string("swift.test")
            ],
            context: approvedContext()
        )

        let stdout = try XCTUnwrap(result.output["stdout"]?.stringValue)
        XCTAssertFalse(stdout.contains(secret))
        XCTAssertTrue(stdout.contains("[REDACTED_SECRET]"))
        XCTAssertEqual(result.output["stdoutTruncated"], .bool(true))
        XCTAssertLessThanOrEqual(stdout.count, DevelopmentVerificationOutputPolicy.maximumOutputCharacters + 40)
    }

    func testVerificationCommandFailsClosedOnNonZeroExitWithRedactedOutput() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try stores.projects.create(title: "SoloPM", workspacePath: workspace.path)
        let secret = "ghp_secretvalue"
        let runner = RecordingDevelopmentCommandRunner(output: DevelopmentCommandOutput(
            standardOutput: "partial output\n",
            standardError: "token=\(secret) failed\n",
            exitCode: 1
        ))
        let tool = DevelopmentVerificationCommandTool(projectStore: stores.projects, commandRunner: runner)

        let result = try tool.execute(
            arguments: [
                "projectId": .number(Double(project.id)),
                "commandId": .string("swift.test")
            ],
            context: approvedContext()
        )

        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.output["passed"], .bool(false))
        XCTAssertEqual(result.output["exitCode"], .number(1))
        let stderr = try XCTUnwrap(result.output["stderr"]?.stringValue)
        XCTAssertTrue(stderr.contains("[REDACTED_SECRET]"))
        XCTAssertFalse(stderr.contains(secret))
    }

    func testVerificationCommandFailsClosedOnTimeout() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try stores.projects.create(title: "SoloPM", workspacePath: workspace.path)
        let runner = RecordingDevelopmentCommandRunner(output: DevelopmentCommandOutput(
            standardOutput: "still running\n",
            standardError: "",
            exitCode: 124,
            timedOut: true
        ))
        let tool = DevelopmentVerificationCommandTool(projectStore: stores.projects, commandRunner: runner)

        let result = try tool.execute(
            arguments: [
                "projectId": .number(Double(project.id)),
                "commandId": .string("swift.test")
            ],
            context: approvedContext()
        )

        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.output["passed"], .bool(false))
        XCTAssertEqual(result.output["timedOut"], .bool(true))
        XCTAssertTrue(result.summary.contains("timed out"))
    }

    func testProcessRunnerBoundsCapturedOutputAndReportsTruncation() throws {
        let workspace = temporaryDirectory()
        let script = try writeExecutableScript(
            workspace.appendingPathComponent("spam-output.sh", isDirectory: false),
            contents: """
            #!/bin/sh
            i=0
            while [ "$i" -lt 200 ]; do
              printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
              i=$((i + 1))
            done
            """
        )
        let runner = ProcessDevelopmentCommandRunner(timeoutSeconds: 5, outputCaptureLimitBytes: 1_024)

        let output = try runner.run(executable: script.path, arguments: [], workingDirectory: workspace)

        XCTAssertEqual(output.exitCode, 0)
        XCTAssertLessThanOrEqual(output.standardOutput.utf8.count, 1_024)
        XCTAssertTrue(output.standardOutputTruncated)
        XCTAssertFalse(output.standardErrorTruncated)
    }

    func testProcessRunnerDoesNotInheritProviderSecretsFromParentEnvironment() throws {
        let workspace = temporaryDirectory()
        let script = try writeExecutableScript(
            workspace.appendingPathComponent("print-secret-env.sh", isDirectory: false),
            contents: """
            #!/bin/sh
            printf '%s' "${OPENAI_API_KEY-unset}"
            """
        )
        setenv("OPENAI_API_KEY", "sk-proj-parent-secret", 1)
        defer {
            unsetenv("OPENAI_API_KEY")
        }
        let runner = ProcessDevelopmentCommandRunner(timeoutSeconds: 5, outputCaptureLimitBytes: 1_024)

        let output = try runner.run(executable: script.path, arguments: [], workingDirectory: workspace)

        XCTAssertEqual(output.exitCode, 0)
        XCTAssertEqual(output.standardOutput, "unset")
    }

    func testProcessRunnerTerminatesTimedOutCommand() throws {
        let workspace = temporaryDirectory()
        let script = try writeExecutableScript(
            workspace.appendingPathComponent("ignore-term.sh", isDirectory: false),
            contents: """
            #!/bin/sh
            trap '' TERM
            while true; do :; done
            """
        )
        let runner = ProcessDevelopmentCommandRunner(timeoutSeconds: 0.1, outputCaptureLimitBytes: 1_024)
        let startedAt = Date()

        let output = try runner.run(executable: script.path, arguments: [], workingDirectory: workspace)

        XCTAssertTrue(output.timedOut)
        XCTAssertEqual(output.exitCode, 124)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 4)
    }

    func testDevelopmentModeRegistersVerificationToolOnlyWhenCapabilityIsEnabled() throws {
        let stores = try makeStores()
        let root = temporaryDirectory()

        let fileOnlyRegistry = try ToolRegistryFactory.developerMode(
            settings: DeveloperModeSettings(
                isEnabled: true,
                workspaceRoot: root,
                enabledCapabilities: [.developmentRepositoryFiles]
            ),
            projectStore: stores.projects,
            taskStore: stores.tasks
        )
        XCTAssertFalse(fileOnlyRegistry.contains(.developmentRunVerification))

        XCTAssertThrowsError(try ToolRegistryFactory.developerMode(
            settings: DeveloperModeSettings(
                isEnabled: true,
                workspaceRoot: root,
                enabledCapabilities: [.developmentVerificationCommands]
            )
        )) { error in
            XCTAssertEqual(error as? DeveloperModeError, .projectStoresRequired)
        }

        let verificationRegistry = try ToolRegistryFactory.developerMode(
            settings: DeveloperModeSettings(
                isEnabled: true,
                workspaceRoot: root,
                enabledCapabilities: [.developmentVerificationCommands]
            ),
            projectStore: stores.projects,
            taskStore: stores.tasks
        )

        XCTAssertTrue(verificationRegistry.contains(.developmentRunVerification))
        XCTAssertTrue(DeveloperModeCapability.developmentVerificationCommands.disclosure.summary.contains("approved project directory"))
    }

    private func makeStores() throws -> (projects: SQLiteProjectStore, tasks: SQLiteTaskStore) {
        let connection = try SQLiteConnection(path: ":memory:")
        try DevelopmentVerificationCommandTestMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        return (
            SQLiteProjectStore(connection: connection),
            SQLiteTaskStore(connection: connection)
        )
    }

    private func approvedContext() -> ToolExecutionContext {
        ToolExecutionContext(
            approvalToken: ApprovalToken(id: "approval-1", sessionID: "session-1"),
            source: .reviewUI
        )
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SoloPMDevelopmentVerificationCommandTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func writeExecutableScript(_ url: URL, contents: String) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}

private final class RecordingDevelopmentCommandRunner: DevelopmentCommandRunner, @unchecked Sendable {
    private let output: DevelopmentCommandOutput
    private let lock = NSLock()
    private var invocations: [DevelopmentCommandInvocation] = []

    init(output: DevelopmentCommandOutput) {
        self.output = output
    }

    var recordedInvocations: [DevelopmentCommandInvocation] {
        lock.lock()
        defer { lock.unlock() }
        return invocations
    }

    func run(executable: String, arguments: [String], workingDirectory: URL) throws -> DevelopmentCommandOutput {
        lock.lock()
        invocations.append(DevelopmentCommandInvocation(
            executable: executable,
            arguments: arguments,
            workingDirectory: workingDirectory
        ))
        lock.unlock()
        return output
    }
}

private enum DevelopmentVerificationCommandTestMigrationRunner {
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
}
