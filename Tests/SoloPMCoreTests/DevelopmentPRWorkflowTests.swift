import XCTest
@testable import SoloPMCore

final class DevelopmentPRWorkflowTests: XCTestCase {
    func testPreparePullRequestWorkflowRequiresApprovalBeforeBranchMutation() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try stores.projects.create(title: "SoloPM", workspacePath: workspace.path)
        let runner = RecordingDevelopmentGitRunner()
        let tool = DevelopmentPRWorkflowTool(
            projectStore: stores.projects,
            taskStore: stores.tasks,
            gitRunner: runner
        )

        XCTAssertThrowsError(
            try tool.execute(
                arguments: ["projectId": .number(Double(project.id))],
                context: ToolExecutionContext(source: .reviewUI)
            )
        ) { error in
            XCTAssertEqual(error as? ToolExecutionError, .approvalRequired(.developmentPreparePullRequestWorkflow))
        }
        XCTAssertEqual(runner.recordedInvocations, [])
    }

    func testPreparePullRequestWorkflowFailsClosedWithoutApprovedProjectWorkspace() throws {
        let stores = try makeStores()
        let project = try stores.projects.create(title: "SoloPM")
        let tool = DevelopmentPRWorkflowTool(
            projectStore: stores.projects,
            taskStore: stores.tasks,
            gitRunner: RecordingDevelopmentGitRunner()
        )

        XCTAssertThrowsError(
            try tool.execute(
                arguments: ["projectId": .number(Double(project.id))],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(
                    .developmentPreparePullRequestWorkflow,
                    "Project \(project.id) must have an approved workspace directory before preparing a PR workflow."
                )
            )
        }
    }

    func testPreparePullRequestWorkflowCreatesDeterministicBranchInsideApprovedWorkspace() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try stores.projects.create(title: "SoloPM", workspacePath: workspace.path)
        let task = try stores.tasks.create(
            title: "Fix calendar sync",
            projectID: project.id,
            sourceCommand: "voice"
        )
        let branchName = "feature/solopm-\(project.id)-\(task.id)-fix-calendar-sync"
        let runner = RecordingDevelopmentGitRunner()
        runner.stub(
            arguments: ["switch", "-c", branchName],
            output: GitCommandOutput(standardOutput: "", standardError: "", exitCode: 0)
        )
        runner.stub(
            arguments: ["status", "--short", "--branch"],
            output: GitCommandOutput(standardOutput: "## \(branchName)\n", standardError: "", exitCode: 0)
        )
        runner.stub(
            arguments: ["diff", "--stat"],
            output: GitCommandOutput(standardOutput: "README.md | 1 +\n", standardError: "", exitCode: 0)
        )
        let tool = DevelopmentPRWorkflowTool(
            projectStore: stores.projects,
            taskStore: stores.tasks,
            gitRunner: runner
        )

        let result = try tool.execute(
            arguments: [
                "projectId": .number(Double(project.id)),
                "taskId": .number(Double(task.id))
            ],
            context: approvedContext()
        )

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(result.output["branchName"], .string(branchName))
        XCTAssertEqual(result.output["projectId"], .number(Double(project.id)))
        XCTAssertEqual(result.output["taskId"], .number(Double(task.id)))
        XCTAssertEqual(result.output["requiresPushApproval"], .bool(true))
        XCTAssertEqual(result.output["requiresPullRequestApproval"], .bool(true))
        XCTAssertEqual(result.output["externalWritePreview"], .string("git push -u origin \(branchName) && gh pr create --fill"))
        XCTAssertEqual(runner.recordedInvocations, [
            GitCommandInvocation(arguments: ["switch", "-c", branchName], workingDirectory: workspace.standardizedFileURL.resolvingSymlinksInPath()),
            GitCommandInvocation(arguments: ["status", "--short", "--branch"], workingDirectory: workspace.standardizedFileURL.resolvingSymlinksInPath()),
            GitCommandInvocation(arguments: ["diff", "--stat"], workingDirectory: workspace.standardizedFileURL.resolvingSymlinksInPath())
        ])
    }

    func testPreparePullRequestWorkflowReturnsFailedResultWithBranchEvidenceWhenPostSwitchGitEvidenceFails() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try stores.projects.create(title: "SoloPM", workspacePath: workspace.path)
        let task = try stores.tasks.create(
            title: "Fix calendar sync",
            projectID: project.id,
            sourceCommand: "voice"
        )
        let branchName = "feature/solopm-\(project.id)-\(task.id)-fix-calendar-sync"
        let runner = RecordingDevelopmentGitRunner()
        runner.stub(
            arguments: ["switch", "-c", branchName],
            output: GitCommandOutput(standardOutput: "", standardError: "", exitCode: 0)
        )
        runner.stub(
            arguments: ["status", "--short", "--branch"],
            output: GitCommandOutput(standardOutput: "", standardError: "fatal token=git-secret", exitCode: 128)
        )
        let tool = DevelopmentPRWorkflowTool(
            projectStore: stores.projects,
            taskStore: stores.tasks,
            gitRunner: runner
        )

        let result = try tool.execute(
            arguments: [
                "projectId": .number(Double(project.id)),
                "taskId": .number(Double(task.id))
            ],
            context: approvedContext()
        )

        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.output["branchName"], .string(branchName))
        XCTAssertEqual(result.output["projectId"], .number(Double(project.id)))
        XCTAssertEqual(result.output["taskId"], .number(Double(task.id)))
        XCTAssertEqual(result.output["requiresPushApproval"], .bool(true))
        XCTAssertEqual(result.output["requiresPullRequestApproval"], .bool(true))
        XCTAssertTrue(result.summary.contains(branchName))
        XCTAssertTrue(result.summary.contains("could not capture git evidence"))
        XCTAssertFalse(result.summary.contains("git-secret"))
        XCTAssertEqual(runner.recordedInvocations, [
            GitCommandInvocation(arguments: ["switch", "-c", branchName], workingDirectory: workspace.standardizedFileURL.resolvingSymlinksInPath()),
            GitCommandInvocation(arguments: ["status", "--short", "--branch"], workingDirectory: workspace.standardizedFileURL.resolvingSymlinksInPath())
        ])
    }

    func testPreparePullRequestWorkflowKeepsPartialGitEvidenceWhenDiffStatFails() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try stores.projects.create(title: "SoloPM", workspacePath: workspace.path)
        let task = try stores.tasks.create(
            title: "Fix calendar sync",
            projectID: project.id,
            sourceCommand: "voice"
        )
        let branchName = "feature/solopm-\(project.id)-\(task.id)-fix-calendar-sync"
        let runner = RecordingDevelopmentGitRunner()
        runner.stub(
            arguments: ["switch", "-c", branchName],
            output: GitCommandOutput(standardOutput: "", standardError: "", exitCode: 0)
        )
        runner.stub(
            arguments: ["status", "--short", "--branch"],
            output: GitCommandOutput(standardOutput: "## \(branchName)\n M Package.swift\n", standardError: "", exitCode: 0)
        )
        runner.stub(
            arguments: ["diff", "--stat"],
            output: GitCommandOutput(standardOutput: "", standardError: "fatal token=diff-secret", exitCode: 128)
        )
        let tool = DevelopmentPRWorkflowTool(
            projectStore: stores.projects,
            taskStore: stores.tasks,
            gitRunner: runner
        )

        let result = try tool.execute(
            arguments: [
                "projectId": .number(Double(project.id)),
                "taskId": .number(Double(task.id))
            ],
            context: approvedContext()
        )

        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.output["branchName"], .string(branchName))
        XCTAssertEqual(result.output["status"], .string("## \(branchName)\n M Package.swift\n"))
        XCTAssertEqual(result.output["diffStat"], nil)
        XCTAssertEqual(result.output["requiresPushApproval"], .bool(true))
        XCTAssertEqual(result.output["requiresPullRequestApproval"], .bool(true))
        guard case .string(let gitEvidenceError)? = result.output["gitEvidenceError"] else {
            return XCTFail("Expected redacted git evidence error")
        }
        XCTAssertTrue(gitEvidenceError.contains("[REDACTED_SECRET]"))
        XCTAssertFalse(gitEvidenceError.contains("diff-secret"))
        XCTAssertFalse(result.summary.contains("diff-secret"))
        XCTAssertEqual(runner.recordedInvocations, [
            GitCommandInvocation(arguments: ["switch", "-c", branchName], workingDirectory: workspace.standardizedFileURL.resolvingSymlinksInPath()),
            GitCommandInvocation(arguments: ["status", "--short", "--branch"], workingDirectory: workspace.standardizedFileURL.resolvingSymlinksInPath()),
            GitCommandInvocation(arguments: ["diff", "--stat"], workingDirectory: workspace.standardizedFileURL.resolvingSymlinksInPath())
        ])
    }

    func testPreparePullRequestWorkflowRejectsUnsafeBranchNameBeforeRunningGit() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try stores.projects.create(title: "SoloPM", workspacePath: workspace.path)
        let runner = RecordingDevelopmentGitRunner()
        let tool = DevelopmentPRWorkflowTool(
            projectStore: stores.projects,
            taskStore: stores.tasks,
            gitRunner: runner
        )

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "branchName": .string("main; rm -rf /")
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(.developmentPreparePullRequestWorkflow, "Branch name contains characters outside the safe GitHub Flow subset.")
            )
        }
        XCTAssertEqual(runner.recordedInvocations, [])
    }

    func testDevelopmentGitPolicyRejectsDestructiveAndExternalWriteCommands() {
        XCTAssertTrue(DevelopmentGitCommandPolicy.isAllowed(arguments: ["switch", "-c", "feature/solopm-1-task"]))
        XCTAssertTrue(DevelopmentGitCommandPolicy.isAllowed(arguments: ["status", "--short", "--branch"]))
        XCTAssertTrue(DevelopmentGitCommandPolicy.isAllowed(arguments: ["diff", "--stat"]))

        XCTAssertFalse(DevelopmentGitCommandPolicy.isAllowed(arguments: ["push"]))
        XCTAssertFalse(DevelopmentGitCommandPolicy.isAllowed(arguments: ["push", "--force"]))
        XCTAssertFalse(DevelopmentGitCommandPolicy.isAllowed(arguments: ["reset", "--hard"]))
        XCTAssertFalse(DevelopmentGitCommandPolicy.isAllowed(arguments: ["clean", "-fd"]))
        XCTAssertFalse(DevelopmentGitCommandPolicy.isAllowed(arguments: ["checkout", "--", "README.md"]))
        XCTAssertFalse(DevelopmentGitCommandPolicy.isAllowed(arguments: ["switch", "-c", "feature/unsafe;rm"]))
    }

    func testPreparePullRequestWorkflowRejectsSymlinkWorkspace() throws {
        let stores = try makeStores()
        let base = temporaryDirectory()
        let outside = temporaryDirectory()
        let symlink = base.appendingPathComponent("linked-workspace", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outside)
        let project = try stores.projects.create(title: "SoloPM", workspacePath: symlink.path)
        let runner = RecordingDevelopmentGitRunner()
        let tool = DevelopmentPRWorkflowTool(
            projectStore: stores.projects,
            taskStore: stores.tasks,
            gitRunner: runner
        )

        XCTAssertThrowsError(
            try tool.execute(
                arguments: ["projectId": .number(Double(project.id))],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(.developmentPreparePullRequestWorkflow, "Project workspace must not be a symlink.")
            )
        }
        XCTAssertEqual(runner.recordedInvocations, [])
    }

    private func makeStores() throws -> (projects: SQLiteProjectStore, tasks: SQLiteTaskStore) {
        let connection = try SQLiteConnection(path: ":memory:")
        try DevelopmentPRWorkflowTestMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
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
            .appendingPathComponent("SoloPMDevelopmentPRWorkflowTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class RecordingDevelopmentGitRunner: GitCommandRunner, @unchecked Sendable {
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

private enum DevelopmentPRWorkflowTestMigrationRunner {
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
