import XCTest
@testable import SuisuiCore

final class DevelopmentCommitWorkflowTests: XCTestCase {
    func testCommitWorkflowRequiresApprovalBeforeStagingOrCommit() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        try write("let value = 1\n", to: workspace.appendingPathComponent("Sources/App.swift"))
        let project = try stores.projects.create(title: "Suisui", workspacePath: workspace.path)
        let runner = RecordingDevelopmentCommitGitRunner()
        let tool = DevelopmentCommitWorkflowTool(projectStore: stores.projects, gitRunner: runner)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "branchName": .string("feature/suisui-1-task"),
                    "relativePaths": .array([.string("Sources/App.swift")]),
                    "commitMessage": .string("Implement app shell")
                ],
                context: ToolExecutionContext(source: .reviewUI)
            )
        ) { error in
            XCTAssertEqual(error as? ToolExecutionError, .approvalRequired(.developmentCommitChanges))
        }
        XCTAssertEqual(runner.recordedInvocations, [])
    }

    func testCommitWorkflowStagesApprovedTextPathsAndCreatesLocalCommitOnly() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let branchName = "feature/suisui-1-task"
        let headRefOID = "0123456789abcdef0123456789abcdef01234567"
        try write("let value = 1\n", to: workspace.appendingPathComponent("Sources/App.swift"))
        try write("# Plan\n", to: workspace.appendingPathComponent("docs/plan.md"))
        let project = try stores.projects.create(title: "Suisui", workspacePath: workspace.path)
        let runner = RecordingDevelopmentCommitGitRunner()
        runner.stub(
            arguments: ["branch", "--show-current"],
            output: GitCommandOutput(standardOutput: "\(branchName)\n", standardError: "", exitCode: 0)
        )
        runner.stub(
            arguments: ["diff", "--cached", "--name-only", "-z"],
            output: GitCommandOutput(standardOutput: "", standardError: "", exitCode: 0)
        )
        runner.stub(
            arguments: ["add", "--", "Sources/App.swift", "docs/plan.md"],
            output: GitCommandOutput(standardOutput: "", standardError: "", exitCode: 0)
        )
        runner.stub(
            arguments: ["diff", "--cached", "--name-only", "-z"],
            output: GitCommandOutput(standardOutput: "Sources/App.swift\u{0}docs/plan.md\u{0}", standardError: "", exitCode: 0)
        )
        runner.stub(
            arguments: ["-c", "core.hooksPath=/dev/null", "commit", "-m", "Implement app shell"],
            output: GitCommandOutput(standardOutput: "[feature abc1234] Implement app shell\n", standardError: "", exitCode: 0)
        )
        runner.stub(
            arguments: ["status", "--short", "--branch"],
            output: GitCommandOutput(standardOutput: "## \(branchName)\n", standardError: "", exitCode: 0)
        )
        runner.stub(
            arguments: ["rev-parse", "HEAD"],
            output: GitCommandOutput(standardOutput: "\(headRefOID)\n", standardError: "", exitCode: 0)
        )
        let tool = DevelopmentCommitWorkflowTool(projectStore: stores.projects, gitRunner: runner)

        let result = try tool.execute(
            arguments: [
                "projectId": .number(Double(project.id)),
                "branchName": .string(branchName),
                "relativePaths": .array([.string("Sources/App.swift"), .string("docs/plan.md")]),
                "commitMessage": .string("Implement app shell")
            ],
            context: approvedContext()
        )

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(result.output["projectId"], .number(Double(project.id)))
        XCTAssertEqual(result.output["branchName"], .string(branchName))
        XCTAssertEqual(result.output["headRefOid"], .string(headRefOID))
        XCTAssertEqual(result.output["relativePaths"], .array([.string("Sources/App.swift"), .string("docs/plan.md")]))
        XCTAssertEqual(result.output["commitMessage"], .string("Implement app shell"))
        XCTAssertEqual(result.output["commitSummary"], .string("[feature abc1234] Implement app shell\n"))
        XCTAssertEqual(result.output["status"], .string("## \(branchName)\n"))
        XCTAssertEqual(result.output["requiresPushApproval"], .bool(true))
        XCTAssertEqual(result.output["requiresPullRequestApproval"], .bool(true))
        XCTAssertEqual(result.output["externalWritePreview"], .string("git push -u origin HEAD && gh pr create --fill"))
        XCTAssertEqual(runner.recordedInvocations, [
            GitCommandInvocation(arguments: ["branch", "--show-current"], workingDirectory: workspace.standardizedFileURL.resolvingSymlinksInPath()),
            GitCommandInvocation(arguments: ["diff", "--cached", "--name-only", "-z"], workingDirectory: workspace.standardizedFileURL.resolvingSymlinksInPath()),
            GitCommandInvocation(arguments: ["add", "--", "Sources/App.swift", "docs/plan.md"], workingDirectory: workspace.standardizedFileURL.resolvingSymlinksInPath()),
            GitCommandInvocation(arguments: ["diff", "--cached", "--name-only", "-z"], workingDirectory: workspace.standardizedFileURL.resolvingSymlinksInPath()),
            GitCommandInvocation(arguments: ["-c", "core.hooksPath=/dev/null", "commit", "-m", "Implement app shell"], workingDirectory: workspace.standardizedFileURL.resolvingSymlinksInPath()),
            GitCommandInvocation(arguments: ["status", "--short", "--branch"], workingDirectory: workspace.standardizedFileURL.resolvingSymlinksInPath()),
            GitCommandInvocation(arguments: ["rev-parse", "HEAD"], workingDirectory: workspace.standardizedFileURL.resolvingSymlinksInPath())
        ])
    }

    func testCommitWorkflowRejectsReviewedBranchMismatchBeforeStaging() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        try write("let value = 1\n", to: workspace.appendingPathComponent("Sources/App.swift"))
        let project = try stores.projects.create(title: "Suisui", workspacePath: workspace.path)
        let runner = RecordingDevelopmentCommitGitRunner()
        runner.stub(
            arguments: ["branch", "--show-current"],
            output: GitCommandOutput(standardOutput: "feature/other-task\n", standardError: "", exitCode: 0)
        )
        let tool = DevelopmentCommitWorkflowTool(projectStore: stores.projects, gitRunner: runner)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "branchName": .string("feature/suisui-1-task"),
                    "relativePaths": .array([.string("Sources/App.swift")]),
                    "commitMessage": .string("Implement app shell")
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(.developmentCommitChanges, "Expected current branch feature/suisui-1-task before committing, but found feature/other-task.")
            )
        }
        XCTAssertEqual(runner.recordedInvocations, [
            GitCommandInvocation(arguments: ["branch", "--show-current"], workingDirectory: workspace.standardizedFileURL.resolvingSymlinksInPath())
        ])
    }

    func testCommitWorkflowRejectsNonFeatureBranchBeforeRunningGit() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        try write("let value = 1\n", to: workspace.appendingPathComponent("Sources/App.swift"))
        let project = try stores.projects.create(title: "Suisui", workspacePath: workspace.path)
        let runner = RecordingDevelopmentCommitGitRunner()
        let tool = DevelopmentCommitWorkflowTool(projectStore: stores.projects, gitRunner: runner)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "branchName": .string("main"),
                    "relativePaths": .array([.string("Sources/App.swift")]),
                    "commitMessage": .string("Implement app shell")
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(.developmentCommitChanges, "Publish head branch must use a reviewed feature branch.")
            )
        }
        XCTAssertEqual(runner.recordedInvocations, [])
    }

    func testCommitWorkflowRejectsEmptyCurrentBranchBeforeStaging() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        try write("let value = 1\n", to: workspace.appendingPathComponent("Sources/App.swift"))
        let project = try stores.projects.create(title: "Suisui", workspacePath: workspace.path)
        let runner = RecordingDevelopmentCommitGitRunner()
        runner.stub(
            arguments: ["branch", "--show-current"],
            output: GitCommandOutput(standardOutput: "\n", standardError: "", exitCode: 0)
        )
        let tool = DevelopmentCommitWorkflowTool(projectStore: stores.projects, gitRunner: runner)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "branchName": .string("feature/suisui-1-task"),
                    "relativePaths": .array([.string("Sources/App.swift")]),
                    "commitMessage": .string("Implement app shell")
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(.developmentCommitChanges, "Git current branch could not be read before creating the local commit.")
            )
        }
        XCTAssertEqual(runner.recordedInvocations, [
            GitCommandInvocation(arguments: ["branch", "--show-current"], workingDirectory: workspace.standardizedFileURL.resolvingSymlinksInPath())
        ])
    }

    func testCommitWorkflowRejectsUnreadableHeadOIDAfterCommit() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let branchName = "feature/suisui-1-task"
        try write("let value = 1\n", to: workspace.appendingPathComponent("Sources/App.swift"))
        let project = try stores.projects.create(title: "Suisui", workspacePath: workspace.path)
        let runner = RecordingDevelopmentCommitGitRunner()
        runner.stub(
            arguments: ["branch", "--show-current"],
            output: GitCommandOutput(standardOutput: "\(branchName)\n", standardError: "", exitCode: 0)
        )
        runner.stub(
            arguments: ["diff", "--cached", "--name-only", "-z"],
            output: GitCommandOutput(standardOutput: "", standardError: "", exitCode: 0)
        )
        runner.stub(
            arguments: ["add", "--", "Sources/App.swift"],
            output: GitCommandOutput(standardOutput: "", standardError: "", exitCode: 0)
        )
        runner.stub(
            arguments: ["diff", "--cached", "--name-only", "-z"],
            output: GitCommandOutput(standardOutput: "Sources/App.swift\u{0}", standardError: "", exitCode: 0)
        )
        runner.stub(
            arguments: ["-c", "core.hooksPath=/dev/null", "commit", "-m", "Implement app shell"],
            output: GitCommandOutput(standardOutput: "[feature abc1234] Implement app shell\n", standardError: "", exitCode: 0)
        )
        runner.stub(
            arguments: ["status", "--short", "--branch"],
            output: GitCommandOutput(standardOutput: "## \(branchName)\n", standardError: "", exitCode: 0)
        )
        runner.stub(
            arguments: ["rev-parse", "HEAD"],
            output: GitCommandOutput(standardOutput: "HEAD\n", standardError: "", exitCode: 0)
        )
        let tool = DevelopmentCommitWorkflowTool(projectStore: stores.projects, gitRunner: runner)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "branchName": .string(branchName),
                    "relativePaths": .array([.string("Sources/App.swift")]),
                    "commitMessage": .string("Implement app shell")
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(.developmentCommitChanges, "Git returned an unreadable commit OID after creating the local commit.")
            )
        }
    }

    func testCommitWorkflowRejectsPreexistingStagedChangesWithRealGitIndex() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        try runGit(["init"], in: workspace)
        try runGit(["switch", "-c", "feature/suisui-1-task"], in: workspace)
        try write("let value = 1\n", to: workspace.appendingPathComponent("Sources/App.swift"))
        try write("token=ghp_secretvalue\n", to: workspace.appendingPathComponent(".env"))
        try runGit(["add", ".env"], in: workspace)
        let project = try stores.projects.create(title: "Suisui", workspacePath: workspace.path)
        let tool = DevelopmentCommitWorkflowTool(projectStore: stores.projects)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "branchName": .string("feature/suisui-1-task"),
                    "relativePaths": .array([.string("Sources/App.swift")]),
                    "commitMessage": .string("Implement app shell")
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(.developmentCommitChanges, "Git index already contains staged changes outside the approved file list.")
            )
        }
    }

    func testCommitWorkflowRejectsPostAddStagedPathMismatchBeforeCommit() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        try write("let value = 1\n", to: workspace.appendingPathComponent("Sources/App.swift"))
        let project = try stores.projects.create(title: "Suisui", workspacePath: workspace.path)
        let runner = RecordingDevelopmentCommitGitRunner()
        runner.stub(
            arguments: ["branch", "--show-current"],
            output: GitCommandOutput(standardOutput: "feature/suisui-1-task\n", standardError: "", exitCode: 0)
        )
        runner.stub(
            arguments: ["diff", "--cached", "--name-only", "-z"],
            output: GitCommandOutput(standardOutput: "", standardError: "", exitCode: 0)
        )
        runner.stub(
            arguments: ["add", "--", "Sources/App.swift"],
            output: GitCommandOutput(standardOutput: "", standardError: "", exitCode: 0)
        )
        runner.stub(
            arguments: ["diff", "--cached", "--name-only", "-z"],
            output: GitCommandOutput(standardOutput: "Sources/App.swift\u{0}README.md\u{0}", standardError: "", exitCode: 0)
        )
        let tool = DevelopmentCommitWorkflowTool(projectStore: stores.projects, gitRunner: runner)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "branchName": .string("feature/suisui-1-task"),
                    "relativePaths": .array([.string("Sources/App.swift")]),
                    "commitMessage": .string("Implement app shell")
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(.developmentCommitChanges, "Git staged changes did not match the approved file list.")
            )
        }
        XCTAssertEqual(runner.recordedInvocations, [
            GitCommandInvocation(arguments: ["branch", "--show-current"], workingDirectory: workspace.standardizedFileURL.resolvingSymlinksInPath()),
            GitCommandInvocation(arguments: ["diff", "--cached", "--name-only", "-z"], workingDirectory: workspace.standardizedFileURL.resolvingSymlinksInPath()),
            GitCommandInvocation(arguments: ["add", "--", "Sources/App.swift"], workingDirectory: workspace.standardizedFileURL.resolvingSymlinksInPath()),
            GitCommandInvocation(arguments: ["diff", "--cached", "--name-only", "-z"], workingDirectory: workspace.standardizedFileURL.resolvingSymlinksInPath())
        ])
    }

    func testCommitWorkflowRejectsUnsafePathsBeforeRunningGit() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        try write("token=ghp_secretvalue\n", to: workspace.appendingPathComponent("safe/config.md"))
        let project = try stores.projects.create(title: "Suisui", workspacePath: workspace.path)
        let runner = RecordingDevelopmentCommitGitRunner()
        let tool = DevelopmentCommitWorkflowTool(projectStore: stores.projects, gitRunner: runner)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "branchName": .string("feature/suisui-1-task"),
                    "relativePaths": .array([.string("../escape.md")]),
                    "commitMessage": .string("Update config")
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(.developmentCommitChanges, "Repository file path must not contain traversal or empty components.")
            )
        }

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "branchName": .string("feature/suisui-1-task"),
                    "relativePaths": .array([.string("safe/config.md")]),
                    "commitMessage": .string("Update config")
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(.developmentCommitChanges, "Repository file content looks like it contains credentials or secrets.")
            )
        }
        XCTAssertEqual(runner.recordedInvocations, [])
    }

    func testCommitWorkflowRejectsSecretLikeCommitMessageBeforeRunningGit() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        try write("let value = 1\n", to: workspace.appendingPathComponent("Sources/App.swift"))
        let project = try stores.projects.create(title: "Suisui", workspacePath: workspace.path)
        let runner = RecordingDevelopmentCommitGitRunner()
        let tool = DevelopmentCommitWorkflowTool(projectStore: stores.projects, gitRunner: runner)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "branchName": .string("feature/suisui-1-task"),
                    "relativePaths": .array([.string("Sources/App.swift")]),
                    "commitMessage": .string("token=ghp_secretvalue")
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(.developmentCommitChanges, "Commit message looks like it contains credentials or secrets.")
            )
        }
        XCTAssertEqual(runner.recordedInvocations, [])
    }

    func testDevelopmentCommitGitPolicyRejectsPushAndHookRunningCommitForms() {
        XCTAssertTrue(DevelopmentCommitGitCommandPolicy.isAllowed(arguments: ["add", "--", "Sources/App.swift"]))
        XCTAssertTrue(DevelopmentCommitGitCommandPolicy.isAllowed(arguments: ["-c", "core.hooksPath=/dev/null", "commit", "-m", "Implement app shell"]))
        XCTAssertTrue(DevelopmentCommitGitCommandPolicy.isAllowed(arguments: ["status", "--short", "--branch"]))
        XCTAssertTrue(DevelopmentCommitGitCommandPolicy.isAllowed(arguments: ["diff", "--cached", "--name-only", "-z"]))
        XCTAssertTrue(DevelopmentCommitGitCommandPolicy.isAllowed(arguments: ["branch", "--show-current"]))
        XCTAssertTrue(DevelopmentCommitGitCommandPolicy.isAllowed(arguments: ["rev-parse", "HEAD"]))

        XCTAssertFalse(DevelopmentCommitGitCommandPolicy.isAllowed(arguments: ["add", "Sources/App.swift"]))
        XCTAssertFalse(DevelopmentCommitGitCommandPolicy.isAllowed(arguments: ["add", "--", ".git/HEAD"]))
        XCTAssertFalse(DevelopmentCommitGitCommandPolicy.isAllowed(arguments: ["commit", "-m", "Implement app shell"]))
        XCTAssertFalse(DevelopmentCommitGitCommandPolicy.isAllowed(arguments: ["diff", "--cached"]))
        XCTAssertFalse(DevelopmentCommitGitCommandPolicy.isAllowed(arguments: ["rev-parse", "--verify", "HEAD"]))
        XCTAssertFalse(DevelopmentCommitGitCommandPolicy.isAllowed(arguments: ["push"]))
        XCTAssertFalse(DevelopmentCommitGitCommandPolicy.isAllowed(arguments: ["reset", "--hard"]))
    }

    func testDeveloperModeRegistersCommitWorkflowWithPRWorkflowCapability() throws {
        let stores = try makeStores()
        let registry = try ToolRegistryFactory.developerMode(
            settings: DeveloperModeSettings(
                isEnabled: true,
                workspaceRoot: temporaryDirectory(),
                enabledCapabilities: [.developmentPRWorkflow]
            ),
            gitRunner: RecordingDevelopmentCommitGitRunner(),
            projectStore: stores.projects,
            taskStore: stores.tasks
        )

        XCTAssertTrue(registry.contains(.developmentPreparePullRequestWorkflow))
        XCTAssertTrue(registry.contains(.developmentCommitChanges))
        XCTAssertTrue(DeveloperModeCapability.developmentPRWorkflow.disclosure.summary.contains("local commits"))
    }

    func testDeveloperModeCommitRequiresStoredBookmarkBeforeGit() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        try write("let value = 1\n", to: workspace.appendingPathComponent("Sources/App.swift"))
        let project = try stores.projects.create(title: "Suisui", workspacePath: workspace.path)
        let runner = RecordingDevelopmentCommitGitRunner()
        let registry = try ToolRegistryFactory.developerMode(
            settings: DeveloperModeSettings(
                isEnabled: true,
                workspaceRoot: workspace,
                enabledCapabilities: [.developmentPRWorkflow]
            ),
            gitRunner: runner,
            projectStore: stores.projects,
            taskStore: stores.tasks
        )

        XCTAssertThrowsError(
            try registry.tool(named: .developmentCommitChanges).execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "branchName": .string("feature/suisui-1-task"),
                    "relativePaths": .array([.string("Sources/App.swift")]),
                    "commitMessage": .string("Implement app shell")
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(
                    .developmentCommitChanges,
                    "Project workspace access bookmark could not be resolved and must be renewed."
                )
            )
        }
        XCTAssertEqual(runner.recordedInvocations, [])
    }

    private func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func makeStores() throws -> (projects: SQLiteProjectStore, tasks: SQLiteTaskStore) {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
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
            .appendingPathComponent("SuisuiDevelopmentCommitWorkflowTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func runGit(_ arguments: [String], in workspace: URL) throws {
        let output = try ProcessGitCommandRunner().runGit(arguments: arguments, workingDirectory: workspace)
        XCTAssertEqual(output.exitCode, 0, output.standardError)
    }
}

private final class RecordingDevelopmentCommitGitRunner: GitCommandRunner, @unchecked Sendable {
    private var stubs: [String: [GitCommandOutput]] = [:]
    private(set) var recordedInvocations: [GitCommandInvocation] = []

    func stub(arguments: [String], output: GitCommandOutput) {
        stubs[arguments.joined(separator: "\u{1f}"), default: []].append(output)
    }

    func runGit(arguments: [String], workingDirectory: URL) throws -> GitCommandOutput {
        recordedInvocations.append(GitCommandInvocation(arguments: arguments, workingDirectory: workingDirectory))
        let key = arguments.joined(separator: "\u{1f}")
        if var outputs = stubs[key], !outputs.isEmpty {
            let output = outputs.removeFirst()
            stubs[key] = outputs
            return output
        }
        return GitCommandOutput(
            standardOutput: "",
            standardError: "unexpected command",
            exitCode: 127
        )
    }
}
