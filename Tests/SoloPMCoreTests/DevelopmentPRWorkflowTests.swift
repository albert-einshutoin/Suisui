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

    func testPushBranchRequiresApprovalBeforeExternalWrite() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try stores.projects.create(title: "SoloPM", workspacePath: workspace.path)
        let runner = RecordingDevelopmentGitRunner()
        let tool = DevelopmentPushWorkflowTool(projectStore: stores.projects, gitRunner: runner)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "branchName": .string("feature/solopm-1-task")
                ],
                context: ToolExecutionContext(source: .reviewUI)
            )
        ) { error in
            XCTAssertEqual(error as? ToolExecutionError, .approvalRequired(.developmentPushBranch))
        }
        XCTAssertEqual(runner.recordedInvocations, [])
    }

    func testPushBranchRequiresCleanExpectedBranchAndUsesNarrowPushCommand() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try stores.projects.create(title: "SoloPM", workspacePath: workspace.path)
        let branchName = "feature/solopm-\(project.id)-publish-gate"
        let runner = RecordingDevelopmentGitRunner()
        runner.stub(
            arguments: ["status", "--short", "--branch"],
            output: GitCommandOutput(standardOutput: "## \(branchName)\n", standardError: "", exitCode: 0)
        )
        runner.stub(
            arguments: ["push", "-u", "origin", branchName],
            output: GitCommandOutput(standardOutput: "pushed token=push-secret\n", standardError: "", exitCode: 0)
        )
        let tool = DevelopmentPushWorkflowTool(projectStore: stores.projects, gitRunner: runner)

        let result = try tool.execute(
            arguments: [
                "projectId": .number(Double(project.id)),
                "branchName": .string(branchName)
            ],
            context: approvedContext()
        )

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(result.output["projectId"], .number(Double(project.id)))
        XCTAssertEqual(result.output["branchName"], .string(branchName))
        XCTAssertEqual(result.output["remoteName"], .string("origin"))
        XCTAssertEqual(result.output["requiresPullRequestApproval"], .bool(true))
        XCTAssertEqual(result.output["pushSummary"], .string("pushed [REDACTED_SECRET]\n"))
        XCTAssertFalse(result.summary.contains("push-secret"))
        XCTAssertEqual(runner.recordedInvocations, [
            GitCommandInvocation(arguments: ["status", "--short", "--branch"], workingDirectory: workspace.standardizedFileURL.resolvingSymlinksInPath()),
            GitCommandInvocation(arguments: ["push", "-u", "origin", branchName], workingDirectory: workspace.standardizedFileURL.resolvingSymlinksInPath())
        ])
    }

    func testPushBranchRejectsDirtyOrWrongBranchBeforeRunningExternalWrite() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try stores.projects.create(title: "SoloPM", workspacePath: workspace.path)
        let runner = RecordingDevelopmentGitRunner()
        runner.stub(
            arguments: ["status", "--short", "--branch"],
            output: GitCommandOutput(
                standardOutput: """
                ## feature/other
                 M Sources/SoloPMCore/App.swift
                """,
                standardError: "",
                exitCode: 0
            )
        )
        let tool = DevelopmentPushWorkflowTool(projectStore: stores.projects, gitRunner: runner)

        let result = try tool.execute(
            arguments: [
                "projectId": .number(Double(project.id)),
                "branchName": .string("feature/solopm-\(project.id)-publish-gate")
            ],
            context: approvedContext()
        )

        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.output["branchName"], .string("feature/solopm-\(project.id)-publish-gate"))
        XCTAssertEqual(result.output["workspaceClean"], .bool(false))
        XCTAssertEqual(runner.recordedInvocations, [
            GitCommandInvocation(arguments: ["status", "--short", "--branch"], workingDirectory: workspace.standardizedFileURL.resolvingSymlinksInPath())
        ])
    }

    func testCreatePullRequestRequiresSeparateApprovalAndBodyFileCommand() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try stores.projects.create(title: "SoloPM", workspacePath: workspace.path)
        let branchName = "feature/solopm-\(project.id)-publish-gate"
        let baseBranch = "feature/phase14-product-completion"
        let title = "Add development publish gate"
        let body = "## Summary\n- Add approval-gated publish tools\n"
        let gitRunner = RecordingDevelopmentGitRunner()
        gitRunner.stub(
            arguments: ["status", "--short", "--branch"],
            output: GitCommandOutput(standardOutput: "## \(branchName)\n", standardError: "", exitCode: 0)
        )
        let githubRunner = RecordingGitHubCLICommandRunner(
            output: GitHubCLICommandOutput(
                standardOutput: "https://github.com/albert-einshutoin/soloPM/pull/106\n",
                standardError: "",
                exitCode: 0
            )
        )
        let tool = DevelopmentPullRequestCreationTool(
            projectStore: stores.projects,
            gitRunner: gitRunner,
            githubRunner: githubRunner
        )

        let result = try tool.execute(
            arguments: [
                "projectId": .number(Double(project.id)),
                "branchName": .string(branchName),
                "baseBranch": .string(baseBranch),
                "title": .string(title),
                "body": .string(body)
            ],
            context: approvedContext()
        )

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(result.output["projectId"], .number(Double(project.id)))
        XCTAssertEqual(result.output["branchName"], .string(branchName))
        XCTAssertEqual(result.output["baseBranch"], .string(baseBranch))
        XCTAssertEqual(result.output["pullRequestURL"], .string("https://github.com/albert-einshutoin/soloPM/pull/106"))
        XCTAssertEqual(githubRunner.recordedInvocations.count, 1)
        let invocation = try XCTUnwrap(githubRunner.recordedInvocations.first)
        XCTAssertEqual(invocation.workingDirectory, workspace.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertEqual(Array(invocation.arguments.prefix(8)), [
            "pr", "create",
            "--base", baseBranch,
            "--head", branchName,
            "--title", title
        ])
        XCTAssertEqual(invocation.arguments[8], "--body-file")
        XCTAssertFalse(invocation.arguments.contains("--body"))
        XCTAssertFalse(invocation.arguments.contains("--fill"))
        XCTAssertEqual(githubRunner.recordedBodyFiles, [body])
    }

    func testCreatePullRequestRejectsSecretLikeTitleOrBodyBeforeGitHubCommand() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try stores.projects.create(title: "SoloPM", workspacePath: workspace.path)
        let branchName = "feature/solopm-\(project.id)-publish-gate"
        let gitRunner = RecordingDevelopmentGitRunner()
        gitRunner.stub(
            arguments: ["status", "--short", "--branch"],
            output: GitCommandOutput(standardOutput: "## \(branchName)\n", standardError: "", exitCode: 0)
        )
        let githubRunner = RecordingGitHubCLICommandRunner()
        let tool = DevelopmentPullRequestCreationTool(
            projectStore: stores.projects,
            gitRunner: gitRunner,
            githubRunner: githubRunner
        )

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "branchName": .string(branchName),
                    "baseBranch": .string("main"),
                    "title": .string("Add token=ghp_supersecret"),
                    "body": .string("safe body")
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(.developmentCreatePullRequest, "Pull request title or body looks like it contains credentials or secrets.")
            )
        }
        XCTAssertEqual(githubRunner.recordedInvocations, [])
    }

    func testCreatePullRequestFailureRedactsCommandBodyFileAndSecrets() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try stores.projects.create(title: "SoloPM", workspacePath: workspace.path)
        let branchName = "feature/solopm-\(project.id)-publish-gate"
        let gitRunner = RecordingDevelopmentGitRunner()
        gitRunner.stub(
            arguments: ["status", "--short", "--branch"],
            output: GitCommandOutput(standardOutput: "## \(branchName)\n", standardError: "", exitCode: 0)
        )
        let githubRunner = RecordingGitHubCLICommandRunner(
            output: GitHubCLICommandOutput(
                standardOutput: "",
                standardError: "gh failed token=pr-secret",
                exitCode: 1
            )
        )
        let tool = DevelopmentPullRequestCreationTool(
            projectStore: stores.projects,
            gitRunner: gitRunner,
            githubRunner: githubRunner
        )

        let result = try tool.execute(
            arguments: [
                "projectId": .number(Double(project.id)),
                "branchName": .string(branchName),
                "baseBranch": .string("main"),
                "title": .string("Add publish gate"),
                "body": .string("Reviewed pull request body")
            ],
            context: approvedContext()
        )

        XCTAssertEqual(result.status, .failed)
        XCTAssertTrue(result.summary.contains("[REDACTED_SECRET]"))
        XCTAssertFalse(result.summary.contains("pr-secret"))
        XCTAssertFalse(result.summary.contains("--body-file"))
        XCTAssertFalse(result.summary.contains("Reviewed pull request body"))
        guard case .string(let publishError)? = result.output["publishError"] else {
            return XCTFail("Expected publishError output")
        }
        XCTAssertFalse(publishError.contains("--body-file"))
        XCTAssertFalse(publishError.contains(workspace.path))
    }

    func testDevelopmentPublishPoliciesRejectUnsafeCommands() {
        XCTAssertTrue(DevelopmentPublishGitCommandPolicy.isAllowed(arguments: ["status", "--short", "--branch"]))
        XCTAssertTrue(DevelopmentPublishGitCommandPolicy.isAllowed(arguments: ["push", "-u", "origin", "feature/solopm-1-task"]))
        XCTAssertFalse(DevelopmentPublishGitCommandPolicy.isAllowed(arguments: ["push"]))
        XCTAssertFalse(DevelopmentPublishGitCommandPolicy.isAllowed(arguments: ["push", "--force", "origin", "feature/solopm-1-task"]))
        XCTAssertFalse(DevelopmentPublishGitCommandPolicy.isAllowed(arguments: ["push", "--mirror"]))
        XCTAssertFalse(DevelopmentPublishGitCommandPolicy.isAllowed(arguments: ["push", "--tags"]))
        XCTAssertFalse(DevelopmentPublishGitCommandPolicy.isAllowed(arguments: ["reset", "--hard"]))

        let bodyFile = FileManager.default.temporaryDirectory.appendingPathComponent("solopm-pr-body-test.md").path
        XCTAssertTrue(DevelopmentGitHubPRCommandPolicy.isAllowed(arguments: [
            "pr", "create",
            "--base", "main",
            "--head", "feature/solopm-1-task",
            "--title", "Add publish gate",
            "--body-file", bodyFile
        ]))
        XCTAssertFalse(DevelopmentGitHubPRCommandPolicy.isAllowed(arguments: ["pr", "merge", "1"]))
        XCTAssertFalse(DevelopmentGitHubPRCommandPolicy.isAllowed(arguments: [
            "pr", "create",
            "--base", "main",
            "--head", "feature/solopm-1-task",
            "--title", "Add publish gate",
            "--body", "inline body"
        ]))
        XCTAssertFalse(DevelopmentGitHubPRCommandPolicy.isAllowed(arguments: [
            "pr", "create",
            "--base", "main",
            "--head", "feature/solopm-1-task",
            "--title", "Add publish gate",
            "--body-file", "--editor"
        ]))
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

private final class RecordingGitHubCLICommandRunner: GitHubCLICommandRunner, @unchecked Sendable {
    private let output: GitHubCLICommandOutput
    private(set) var recordedInvocations: [GitHubCLICommandInvocation] = []
    private(set) var recordedBodyFiles: [String] = []

    init(
        output: GitHubCLICommandOutput = GitHubCLICommandOutput(
            standardOutput: "",
            standardError: "unexpected command",
            exitCode: 127
        )
    ) {
        self.output = output
    }

    func runGitHub(arguments: [String], workingDirectory: URL) throws -> GitHubCLICommandOutput {
        recordedInvocations.append(GitHubCLICommandInvocation(arguments: arguments, workingDirectory: workingDirectory))
        if let bodyFileIndex = arguments.firstIndex(of: "--body-file"),
           arguments.indices.contains(arguments.index(after: bodyFileIndex)) {
            let bodyFile = arguments[arguments.index(after: bodyFileIndex)]
            recordedBodyFiles.append((try? String(contentsOfFile: bodyFile, encoding: .utf8)) ?? "")
        }
        return output
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
