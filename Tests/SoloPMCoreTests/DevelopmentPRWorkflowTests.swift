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

    func testDeveloperModePrepareWorkflowRequiresStoredBookmarkBeforeGit() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try stores.projects.create(title: "SoloPM", workspacePath: workspace.path)
        let runner = RecordingDevelopmentGitRunner()
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
            try registry.tool(named: .developmentPreparePullRequestWorkflow).execute(
                arguments: ["projectId": .number(Double(project.id))],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(
                    .developmentPreparePullRequestWorkflow,
                    "Project workspace access bookmark could not be resolved and must be renewed."
                )
            )
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
        let project = try createPublishProject(stores: stores, workspace: workspace)
        let runner = RecordingDevelopmentGitRunner()
        let tool = DevelopmentPushWorkflowTool(projectStore: stores.projects, gitRunner: runner, bookmarkResolver: publishBookmarkResolver(for: workspace))

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

    func testPushBranchRequiresApprovedBookmarkBeforeExternalGitWrite() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try stores.projects.create(title: "SoloPM", workspacePath: workspace.path)
        let branchName = "feature/solopm-\(project.id)-publish-gate"
        let runner = RecordingDevelopmentGitRunner()
        let tool = DevelopmentPushWorkflowTool(
            projectStore: stores.projects,
            gitRunner: runner,
            bookmarkResolver: publishBookmarkResolver(for: workspace)
        )

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "branchName": .string(branchName)
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(.developmentPushBranch, "Project workspace access bookmark could not be resolved and must be renewed.")
            )
        }
        XCTAssertEqual(runner.recordedInvocations, [])
    }

    func testPushBranchRequiresCleanExpectedBranchAndUsesNarrowPushCommand() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try createPublishProject(stores: stores, workspace: workspace)
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
        let tool = DevelopmentPushWorkflowTool(projectStore: stores.projects, gitRunner: runner, bookmarkResolver: publishBookmarkResolver(for: workspace))

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

    func testPushBranchRejectsProtectedHeadBranchBeforeRunningGit() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try createPublishProject(stores: stores, workspace: workspace)
        let runner = RecordingDevelopmentGitRunner()
        let tool = DevelopmentPushWorkflowTool(projectStore: stores.projects, gitRunner: runner, bookmarkResolver: publishBookmarkResolver(for: workspace))

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "branchName": .string("main")
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(.developmentPushBranch, "Publish head branch must use a reviewed feature branch.")
            )
        }
        XCTAssertEqual(runner.recordedInvocations, [])
    }

    func testPushBranchRejectsDirtyOrWrongBranchBeforeRunningExternalWrite() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try createPublishProject(stores: stores, workspace: workspace)
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
        let tool = DevelopmentPushWorkflowTool(projectStore: stores.projects, gitRunner: runner, bookmarkResolver: publishBookmarkResolver(for: workspace))

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
        let project = try createPublishProject(stores: stores, workspace: workspace)
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
            githubRunner: githubRunner,
            bookmarkResolver: publishBookmarkResolver(for: workspace)
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

    func testCreatePullRequestRequiresApprovedBookmarkBeforeExternalGitHubWrite() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try stores.projects.create(title: "SoloPM", workspacePath: workspace.path)
        let gitRunner = RecordingDevelopmentGitRunner()
        let githubRunner = RecordingGitHubCLICommandRunner()
        let tool = DevelopmentPullRequestCreationTool(
            projectStore: stores.projects,
            gitRunner: gitRunner,
            githubRunner: githubRunner,
            bookmarkResolver: publishBookmarkResolver(for: workspace)
        )

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "branchName": .string("feature/solopm-\(project.id)-publish-gate"),
                    "baseBranch": .string("feature/phase14-product-completion"),
                    "title": .string("Add development publish gate"),
                    "body": .string("## Summary\n- Add approval-gated publish tools\n")
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(.developmentCreatePullRequest, "Project workspace access bookmark could not be resolved and must be renewed.")
            )
        }
        XCTAssertEqual(gitRunner.recordedInvocations, [])
        XCTAssertEqual(githubRunner.recordedInvocations, [])
    }

    func testCreatePullRequestRejectsMalformedReturnedURLBeforeReceiptOutput() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try createPublishProject(stores: stores, workspace: workspace)
        let branchName = "feature/solopm-\(project.id)-publish-gate"
        let gitRunner = RecordingDevelopmentGitRunner()
        gitRunner.stub(
            arguments: ["status", "--short", "--branch"],
            output: GitCommandOutput(standardOutput: "## \(branchName)\n", standardError: "", exitCode: 0)
        )
        let githubRunner = RecordingGitHubCLICommandRunner(
            output: GitHubCLICommandOutput(
                standardOutput: "https://user:token@github.com/albert-einshutoin/soloPM/pull/106\n",
                standardError: "",
                exitCode: 0
            )
        )
        let tool = DevelopmentPullRequestCreationTool(
            projectStore: stores.projects,
            gitRunner: gitRunner,
            githubRunner: githubRunner,
            bookmarkResolver: publishBookmarkResolver(for: workspace)
        )

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "branchName": .string(branchName),
                    "baseBranch": .string("feature/phase14-product-completion"),
                    "title": .string("Add development publish gate"),
                    "body": .string("Reviewed pull request body")
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(.developmentCreatePullRequest, "Pull request URL must be a GitHub HTTPS pull request URL.")
            )
        }
    }

    func testCreatePullRequestRejectsProtectedOrMatchingHeadBeforeGitHubCommand() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try createPublishProject(stores: stores, workspace: workspace)
        let gitRunner = RecordingDevelopmentGitRunner()
        let githubRunner = RecordingGitHubCLICommandRunner()
        let tool = DevelopmentPullRequestCreationTool(
            projectStore: stores.projects,
            gitRunner: gitRunner,
            githubRunner: githubRunner,
            bookmarkResolver: publishBookmarkResolver(for: workspace)
        )

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "branchName": .string("main"),
                    "baseBranch": .string("main"),
                    "title": .string("Add publish gate"),
                    "body": .string("Reviewed body")
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(.developmentCreatePullRequest, "Publish head branch must use a reviewed feature branch.")
            )
        }
        XCTAssertEqual(gitRunner.recordedInvocations, [])
        XCTAssertEqual(githubRunner.recordedInvocations, [])
    }

    func testCreatePullRequestRejectsSecretLikeTitleOrBodyBeforeGitHubCommand() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try createPublishProject(stores: stores, workspace: workspace)
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
            githubRunner: githubRunner,
            bookmarkResolver: publishBookmarkResolver(for: workspace)
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

    func testCreatePullRequestRejectsLocalPathsInTitleOrBodyBeforeGitHubCommand() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try createPublishProject(stores: stores, workspace: workspace)
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
            githubRunner: githubRunner,
            bookmarkResolver: publishBookmarkResolver(for: workspace)
        )

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "branchName": .string(branchName),
                    "baseBranch": .string("main"),
                    "title": .string("Add publish gate"),
                    "body": .string("See /Volumes/Satechi/Developer/soloPM/Sources/SoloPMCore/App.swift")
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(.developmentCreatePullRequest, "Pull request title or body includes a local filesystem path.")
            )
        }
        XCTAssertEqual(githubRunner.recordedInvocations, [])
    }

    func testCreatePullRequestFailureRedactsCommandBodyFileAndSecrets() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try createPublishProject(stores: stores, workspace: workspace)
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
            githubRunner: githubRunner,
            bookmarkResolver: publishBookmarkResolver(for: workspace)
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

    func testPullRequestReviewGateReportsBlockedReasonsWithoutMergeCommand() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try createPublishProject(stores: stores, workspace: workspace)
        let branchName = "feature/solopm-\(project.id)-merge-gate"
        let pullRequestURL = "https://github.com/albert-einshutoin/soloPM/pull/116"
        let gitRunner = RecordingDevelopmentGitRunner()
        stubOrigin(gitRunner)
        let githubRunner = RecordingGitHubCLICommandRunner(outputs: [
            GitHubCLICommandOutput(
                standardOutput: pullRequestStatusJSON(
                    url: pullRequestURL,
                    headBranch: branchName,
                    baseBranch: "feature/phase14-product-completion",
                    reviewDecision: "CHANGES_REQUESTED",
                    mergeable: "CONFLICTING",
                    mergeStateStatus: "DIRTY",
                    checks: [
                        (name: "SwiftPM macOS", status: "COMPLETED", conclusion: "FAILURE"),
                        (name: "GitGuardian Security Checks", status: "IN_PROGRESS", conclusion: nil)
                    ]
                ),
                standardError: "",
                exitCode: 0
            )
        ])
        let tool = DevelopmentPullRequestReviewGateTool(
            projectStore: stores.projects,
            gitRunner: gitRunner,
            githubRunner: githubRunner,
            bookmarkResolver: publishBookmarkResolver(for: workspace)
        )

        let result = try tool.execute(
            arguments: [
                "projectId": .number(Double(project.id)),
                "pullRequestURL": .string(pullRequestURL),
                "branchName": .string(branchName),
                "baseBranch": .string("feature/phase14-product-completion")
            ],
            context: approvedContext()
        )

        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.output["readyToMerge"], .bool(false))
        XCTAssertEqual(result.output["reviewDecision"], .string("CHANGES_REQUESTED"))
        XCTAssertEqual(result.output["mergeable"], .string("CONFLICTING"))
        XCTAssertEqual(result.output["mergeStateStatus"], .string("DIRTY"))
        XCTAssertEqual(result.output["statusCheckCount"], .number(2))
        XCTAssertTrue(result.summary.contains("review decision is CHANGES_REQUESTED"))
        XCTAssertTrue(result.summary.contains("SwiftPM macOS concluded FAILURE"))
        XCTAssertTrue(result.summary.contains("GitGuardian Security Checks is IN_PROGRESS"))
        XCTAssertEqual(githubRunner.recordedInvocations, [
            GitHubCLICommandInvocation(
                arguments: [
                    "pr", "view", pullRequestURL,
                    "--json", DevelopmentGitHubPRCommandPolicy.statusJSONFields
                ],
                workingDirectory: workspace.standardizedFileURL.resolvingSymlinksInPath()
            )
        ])
    }

    func testPullRequestReviewGateRequiresApprovalBeforeExternalReads() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try createPublishProject(stores: stores, workspace: workspace)
        let gitRunner = RecordingDevelopmentGitRunner()
        let githubRunner = RecordingGitHubCLICommandRunner()
        let tool = DevelopmentPullRequestReviewGateTool(
            projectStore: stores.projects,
            gitRunner: gitRunner,
            githubRunner: githubRunner,
            bookmarkResolver: publishBookmarkResolver(for: workspace)
        )

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "pullRequestURL": .string("https://github.com/albert-einshutoin/soloPM/pull/116"),
                    "branchName": .string("feature/solopm-\(project.id)-merge-gate"),
                    "baseBranch": .string("feature/phase14-product-completion")
                ],
                context: ToolExecutionContext(source: .reviewUI)
            )
        ) { error in
            XCTAssertEqual(error as? ToolExecutionError, .approvalRequired(.developmentReviewPullRequestGate))
        }
        XCTAssertEqual(gitRunner.recordedInvocations, [])
        XCTAssertEqual(githubRunner.recordedInvocations, [])
    }

    func testPullRequestReviewGateRejectsDifferentOriginRepositoryBeforeGitHubRead() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try createPublishProject(stores: stores, workspace: workspace)
        let pullRequestURL = "https://github.com/albert-einshutoin/soloPM/pull/116"
        let gitRunner = RecordingDevelopmentGitRunner()
        stubOrigin(gitRunner, remoteURL: "https://github.com/other-org/other-repo.git")
        let githubRunner = RecordingGitHubCLICommandRunner()
        let tool = DevelopmentPullRequestReviewGateTool(
            projectStore: stores.projects,
            gitRunner: gitRunner,
            githubRunner: githubRunner,
            bookmarkResolver: publishBookmarkResolver(for: workspace)
        )

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "pullRequestURL": .string(pullRequestURL),
                    "branchName": .string("feature/solopm-\(project.id)-merge-gate"),
                    "baseBranch": .string("feature/phase14-product-completion")
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(
                    .developmentReviewPullRequestGate,
                    "Pull request repository albert-einshutoin/soloPM does not match origin repository other-org/other-repo."
                )
            )
        }
        XCTAssertEqual(githubRunner.recordedInvocations, [])
    }

    func testPullRequestReviewGateBlocksForkHeadRepositoryAndMissingChecks() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try createPublishProject(stores: stores, workspace: workspace)
        let branchName = "feature/solopm-\(project.id)-merge-gate"
        let baseBranch = "feature/phase14-product-completion"
        let pullRequestURL = "https://github.com/albert-einshutoin/soloPM/pull/116"
        let gitRunner = RecordingDevelopmentGitRunner()
        stubOrigin(gitRunner)
        let githubRunner = RecordingGitHubCLICommandRunner(outputs: [
            GitHubCLICommandOutput(
                standardOutput: pullRequestStatusJSON(
                    url: pullRequestURL,
                    headBranch: branchName,
                    baseBranch: baseBranch,
                    reviewDecision: "APPROVED",
                    mergeable: "MERGEABLE",
                    mergeStateStatus: "CLEAN",
                    checks: [],
                    headOwner: "outside-contributor",
                    headRepository: "soloPM-fork",
                    isCrossRepository: true
                ),
                standardError: "",
                exitCode: 0
            )
        ])
        let tool = DevelopmentPullRequestReviewGateTool(
            projectStore: stores.projects,
            gitRunner: gitRunner,
            githubRunner: githubRunner,
            bookmarkResolver: publishBookmarkResolver(for: workspace)
        )

        let result = try tool.execute(
            arguments: [
                "projectId": .number(Double(project.id)),
                "pullRequestURL": .string(pullRequestURL),
                "branchName": .string(branchName),
                "baseBranch": .string(baseBranch)
            ],
            context: approvedContext()
        )

        XCTAssertEqual(result.status, .failed)
        XCTAssertTrue(result.summary.contains("status checks are missing"))
        XCTAssertTrue(result.summary.contains("head repository is cross-repository"))
        XCTAssertTrue(result.summary.contains("head repository is outside-contributor/soloPM-fork"))
    }

    func testPullRequestReviewGateFailsClosedForGitHubStatusErrors() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try createPublishProject(stores: stores, workspace: workspace)
        let pullRequestURL = "https://github.com/albert-einshutoin/soloPM/pull/116"
        let gitRunner = RecordingDevelopmentGitRunner()
        stubOrigin(gitRunner)
        let githubRunner = RecordingGitHubCLICommandRunner(outputs: [
            GitHubCLICommandOutput(
                standardOutput: "not-json",
                standardError: "",
                exitCode: 0
            )
        ])
        let tool = DevelopmentPullRequestReviewGateTool(
            projectStore: stores.projects,
            gitRunner: gitRunner,
            githubRunner: githubRunner,
            bookmarkResolver: publishBookmarkResolver(for: workspace)
        )

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "pullRequestURL": .string(pullRequestURL),
                    "branchName": .string("feature/solopm-\(project.id)-merge-gate"),
                    "baseBranch": .string("feature/phase14-product-completion")
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(
                    .developmentReviewPullRequestGate,
                    "GitHub CLI returned an unreadable pull request status response."
                )
            )
        }
    }

    func testPullRequestReviewGateAcceptsSuccessfulStatusContextShape() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try createPublishProject(stores: stores, workspace: workspace)
        let branchName = "feature/solopm-\(project.id)-merge-gate"
        let baseBranch = "feature/phase14-product-completion"
        let pullRequestURL = "https://github.com/albert-einshutoin/soloPM/pull/116"
        let headRefOID = "0123456789abcdef0123456789abcdef01234567"
        let gitRunner = RecordingDevelopmentGitRunner()
        stubOrigin(gitRunner)
        let githubRunner = RecordingGitHubCLICommandRunner(outputs: [
            GitHubCLICommandOutput(
                standardOutput: """
                {
                  "url": "\(pullRequestURL)",
                  "headRefName": "\(branchName)",
                  "headRefOid": "\(headRefOID)",
                  "baseRefName": "\(baseBranch)",
                  "headRepository": {
                    "name": "soloPM",
                    "nameWithOwner": ""
                  },
                  "headRepositoryOwner": {
                    "login": "albert-einshutoin"
                  },
                  "isCrossRepository": false,
                  "reviewDecision": "APPROVED",
                  "mergeable": "MERGEABLE",
                  "mergeStateStatus": "CLEAN",
                  "statusCheckRollup": [
                    {
                      "__typename": "StatusContext",
                      "context": "legacy/status",
                      "state": "SUCCESS"
                    }
                  ]
                }
                """,
                standardError: "",
                exitCode: 0
            ),
            GitHubCLICommandOutput(
                standardOutput: reviewThreadsJSON(totalCount: 0, unresolvedCount: 0),
                standardError: "",
                exitCode: 0
            )
        ])
        let tool = DevelopmentPullRequestReviewGateTool(
            projectStore: stores.projects,
            gitRunner: gitRunner,
            githubRunner: githubRunner,
            bookmarkResolver: publishBookmarkResolver(for: workspace)
        )

        let result = try tool.execute(
            arguments: [
                "projectId": .number(Double(project.id)),
                "pullRequestURL": .string(pullRequestURL),
                "branchName": .string(branchName),
                "baseBranch": .string(baseBranch)
            ],
            context: approvedContext()
        )

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(result.output["readyToMerge"], .bool(true))
        XCTAssertEqual(result.output["statusCheckCount"], .number(1))
        XCTAssertEqual(result.output["headRefOid"], .string(headRefOID))
        XCTAssertEqual(result.output["unresolvedReviewThreadCount"], .number(0))
        XCTAssertFalse(result.summary.contains("legacy/status concluded"))
        XCTAssertEqual(githubRunner.recordedInvocations.first?.workingDirectory, workspace.standardizedFileURL.resolvingSymlinksInPath())
    }

    func testPullRequestReviewGateBlocksUnresolvedReviewThreadsBeforeMerge() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try createPublishProject(stores: stores, workspace: workspace)
        let branchName = "feature/solopm-\(project.id)-merge-gate"
        let baseBranch = "feature/phase14-product-completion"
        let pullRequestURL = "https://github.com/albert-einshutoin/soloPM/pull/116"
        let gitRunner = RecordingDevelopmentGitRunner()
        stubOrigin(gitRunner)
        let githubRunner = RecordingGitHubCLICommandRunner(outputs: [
            GitHubCLICommandOutput(
                standardOutput: pullRequestStatusJSON(
                    url: pullRequestURL,
                    headBranch: branchName,
                    baseBranch: baseBranch,
                    reviewDecision: "APPROVED",
                    mergeable: "MERGEABLE",
                    mergeStateStatus: "CLEAN",
                    checks: [
                        (name: "SwiftPM macOS", status: "COMPLETED", conclusion: "SUCCESS")
                    ]
                ),
                standardError: "",
                exitCode: 0
            ),
            GitHubCLICommandOutput(
                standardOutput: reviewThreadsJSON(totalCount: 2, unresolvedCount: 1),
                standardError: "",
                exitCode: 0
            )
        ])
        let tool = DevelopmentPullRequestReviewGateTool(
            projectStore: stores.projects,
            gitRunner: gitRunner,
            githubRunner: githubRunner,
            bookmarkResolver: publishBookmarkResolver(for: workspace)
        )

        let result = try tool.execute(
            arguments: [
                "projectId": .number(Double(project.id)),
                "pullRequestURL": .string(pullRequestURL),
                "branchName": .string(branchName),
                "baseBranch": .string(baseBranch)
            ],
            context: approvedContext()
        )

        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.output["readyToMerge"], .bool(false))
        XCTAssertEqual(result.output["reviewThreadCount"], .number(2))
        XCTAssertEqual(result.output["unresolvedReviewThreadCount"], .number(1))
        XCTAssertTrue(result.summary.contains("1 review thread is unresolved"))
        XCTAssertEqual(githubRunner.recordedInvocations.map(\.arguments), [
            [
                "pr", "view", pullRequestURL,
                "--json", DevelopmentGitHubPRCommandPolicy.statusJSONFields
            ],
            DevelopmentGitHubPRCommandPolicy.reviewThreadsArguments(
                owner: "albert-einshutoin",
                repository: "soloPM",
                number: 116
            )
        ])
        XCTAssertEqual(githubRunner.recordedInvocations.first?.workingDirectory, workspace.standardizedFileURL.resolvingSymlinksInPath())
    }

    func testMergePullRequestRequiresApprovalBeforeExternalWrite() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try createPublishProject(stores: stores, workspace: workspace)
        let gitRunner = RecordingDevelopmentGitRunner()
        let githubRunner = RecordingGitHubCLICommandRunner()
        let tool = DevelopmentPullRequestMergeTool(
            projectStore: stores.projects,
            gitRunner: gitRunner,
            githubRunner: githubRunner,
            bookmarkResolver: publishBookmarkResolver(for: workspace)
        )

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "pullRequestURL": .string("https://github.com/albert-einshutoin/soloPM/pull/116"),
                    "branchName": .string("feature/solopm-\(project.id)-merge-gate"),
                    "baseBranch": .string("feature/phase14-product-completion")
                ],
                context: ToolExecutionContext(source: .reviewUI)
            )
        ) { error in
            XCTAssertEqual(error as? ToolExecutionError, .approvalRequired(.developmentMergePullRequest))
        }
        XCTAssertEqual(githubRunner.recordedInvocations, [])
    }

    func testMergePullRequestRequiresApprovedBookmarkBeforeExternalGitHubWrite() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try stores.projects.create(title: "SoloPM", workspacePath: workspace.path)
        let branchName = "feature/solopm-\(project.id)-merge-gate"
        let gitRunner = RecordingDevelopmentGitRunner()
        let githubRunner = RecordingGitHubCLICommandRunner()
        let tool = DevelopmentPullRequestMergeTool(
            projectStore: stores.projects,
            gitRunner: gitRunner,
            githubRunner: githubRunner,
            bookmarkResolver: publishBookmarkResolver(for: workspace)
        )

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "pullRequestURL": .string("https://github.com/albert-einshutoin/soloPM/pull/116"),
                    "branchName": .string(branchName),
                    "baseBranch": .string("feature/phase14-product-completion")
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(.developmentMergePullRequest, "Project workspace access bookmark could not be resolved and must be renewed.")
            )
        }
        XCTAssertEqual(gitRunner.recordedInvocations, [])
        XCTAssertEqual(githubRunner.recordedInvocations, [])
    }

    func testPullRequestMergeGateBlocksWhenChecksOrReviewAreNotGreenBeforeGitHubMergeCommand() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try createPublishProject(stores: stores, workspace: workspace)
        let branchName = "feature/solopm-\(project.id)-merge-gate"
        let pullRequestURL = "https://github.com/albert-einshutoin/soloPM/pull/116"
        let gitRunner = RecordingDevelopmentGitRunner()
        stubOrigin(gitRunner)
        let githubRunner = RecordingGitHubCLICommandRunner(outputs: [
            GitHubCLICommandOutput(
                standardOutput: pullRequestStatusJSON(
                    url: pullRequestURL,
                    headBranch: branchName,
                    baseBranch: "feature/phase14-product-completion",
                    reviewDecision: "APPROVED",
                    mergeable: "MERGEABLE",
                    mergeStateStatus: "UNSTABLE",
                    checks: [
                        (name: "SwiftPM macOS", status: "COMPLETED", conclusion: "SUCCESS"),
                        (name: "GitGuardian Security Checks", status: "IN_PROGRESS", conclusion: nil)
                    ]
                ),
                standardError: "",
                exitCode: 0
            )
        ])
        let tool = DevelopmentPullRequestMergeTool(
            projectStore: stores.projects,
            gitRunner: gitRunner,
            githubRunner: githubRunner,
            bookmarkResolver: publishBookmarkResolver(for: workspace)
        )

        let result = try tool.execute(
            arguments: [
                "projectId": .number(Double(project.id)),
                "pullRequestURL": .string(pullRequestURL),
                "branchName": .string(branchName),
                "baseBranch": .string("feature/phase14-product-completion")
            ],
            context: approvedContext()
        )

        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.output["readyToMerge"], .bool(false))
        XCTAssertEqual(result.output["pullRequestURL"], .string(pullRequestURL))
        XCTAssertTrue(result.summary.contains("GitGuardian Security Checks is IN_PROGRESS"))
        XCTAssertTrue(result.summary.contains("merge state is UNSTABLE"))
        XCTAssertEqual(githubRunner.recordedInvocations.map(\.arguments), [
            [
                "pr", "view", pullRequestURL,
                "--json", DevelopmentGitHubPRCommandPolicy.statusJSONFields
            ]
        ])
    }

    func testMergePullRequestRechecksGateAndUsesNarrowMergeCommand() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try createPublishProject(stores: stores, workspace: workspace)
        let branchName = "feature/solopm-\(project.id)-merge-gate"
        let baseBranch = "feature/phase14-product-completion"
        let pullRequestURL = "https://github.com/albert-einshutoin/soloPM/pull/116"
        let headRefOID = "0123456789abcdef0123456789abcdef01234567"
        let gitRunner = RecordingDevelopmentGitRunner()
        stubOrigin(gitRunner)
        let githubRunner = RecordingGitHubCLICommandRunner(outputs: [
            GitHubCLICommandOutput(
                standardOutput: pullRequestStatusJSON(
                    url: pullRequestURL,
                    headBranch: branchName,
                    baseBranch: baseBranch,
                    headRefOID: headRefOID,
                    reviewDecision: "APPROVED",
                    mergeable: "MERGEABLE",
                    mergeStateStatus: "CLEAN",
                    checks: [
                        (name: "SwiftPM macOS", status: "COMPLETED", conclusion: "SUCCESS"),
                        (name: "GitGuardian Security Checks", status: "COMPLETED", conclusion: "SUCCESS")
                    ]
                ),
                standardError: "",
                exitCode: 0
            ),
            GitHubCLICommandOutput(
                standardOutput: reviewThreadsJSON(totalCount: 0, unresolvedCount: 0),
                standardError: "",
                exitCode: 0
            ),
            GitHubCLICommandOutput(
                standardOutput: "Merged pull request #116 token=merge-secret\n",
                standardError: "",
                exitCode: 0
            )
        ])
        let tool = DevelopmentPullRequestMergeTool(
            projectStore: stores.projects,
            gitRunner: gitRunner,
            githubRunner: githubRunner,
            bookmarkResolver: publishBookmarkResolver(for: workspace)
        )

        let result = try tool.execute(
            arguments: [
                "projectId": .number(Double(project.id)),
                "pullRequestURL": .string(pullRequestURL),
                "branchName": .string(branchName),
                "baseBranch": .string(baseBranch)
            ],
            context: approvedContext()
        )

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(result.output["readyToMerge"], .bool(true))
        XCTAssertEqual(result.output["merged"], .bool(true))
        XCTAssertEqual(result.output["pullRequestURL"], .string(pullRequestURL))
        XCTAssertEqual(result.output["branchName"], .string(branchName))
        XCTAssertEqual(result.output["baseBranch"], .string(baseBranch))
        XCTAssertEqual(result.output["headRefOid"], .string(headRefOID))
        XCTAssertEqual(result.output["unresolvedReviewThreadCount"], .number(0))
        XCTAssertEqual(result.output["statusCheckCount"], .number(2))
        XCTAssertEqual(result.output["mergeSummary"], .string("Merged pull request #116 [REDACTED_SECRET]\n"))
        XCTAssertFalse(result.summary.contains("merge-secret"))
        XCTAssertEqual(githubRunner.recordedInvocations, [
            GitHubCLICommandInvocation(
                arguments: [
                    "pr", "view", pullRequestURL,
                    "--json", DevelopmentGitHubPRCommandPolicy.statusJSONFields
                ],
                workingDirectory: workspace.standardizedFileURL.resolvingSymlinksInPath()
            ),
            GitHubCLICommandInvocation(
                arguments: DevelopmentGitHubPRCommandPolicy.reviewThreadsArguments(
                    owner: "albert-einshutoin",
                    repository: "soloPM",
                    number: 116
                ),
                workingDirectory: workspace.standardizedFileURL.resolvingSymlinksInPath()
            ),
            GitHubCLICommandInvocation(
                arguments: [
                    "pr", "merge", pullRequestURL,
                    "--merge", "--delete-branch",
                    "--match-head-commit", headRefOID
                ],
                workingDirectory: workspace.standardizedFileURL.resolvingSymlinksInPath()
            )
        ])
    }

    func testMergePullRequestKeepsBookmarkAccessUntilMergeCommandCompletes() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let bookmarkData = Data("merge-workspace-bookmark".utf8)
        let project = try stores.projects.create(
            title: "SoloPM",
            workspacePath: workspace.path,
            workspaceBookmarkData: bookmarkData
        )
        let branchName = "feature/solopm-\(project.id)-merge-gate"
        let baseBranch = "feature/phase14-product-completion"
        let pullRequestURL = "https://github.com/albert-einshutoin/soloPM/pull/116"
        let headRefOID = "0123456789abcdef0123456789abcdef01234567"
        let accessCounter = PRWorkflowRecordingAccessCounter()
        let resolver = PRWorkflowRecordingProjectWorkspaceBookmarkResolver(
            resolution: ProjectWorkspaceBookmarkResolution(
                url: workspace,
                isStale: false,
                didStartAccessing: true,
                stopAccessing: { accessCounter.increment() }
            )
        )
        let gitRunner = RecordingDevelopmentGitRunner()
        stubOrigin(gitRunner)
        let githubRunner = RecordingGitHubCLICommandRunner(
            outputs: [
                GitHubCLICommandOutput(
                    standardOutput: pullRequestStatusJSON(
                        url: pullRequestURL,
                        headBranch: branchName,
                        baseBranch: baseBranch,
                        headRefOID: headRefOID,
                        reviewDecision: "APPROVED",
                        mergeable: "MERGEABLE",
                        mergeStateStatus: "CLEAN",
                        checks: [
                            (name: "SwiftPM macOS", status: "COMPLETED", conclusion: "SUCCESS"),
                            (name: "GitGuardian Security Checks", status: "COMPLETED", conclusion: "SUCCESS")
                        ]
                    ),
                    standardError: "",
                    exitCode: 0
                ),
                GitHubCLICommandOutput(
                    standardOutput: reviewThreadsJSON(totalCount: 0, unresolvedCount: 0),
                    standardError: "",
                    exitCode: 0
                ),
                GitHubCLICommandOutput(
                    standardOutput: "Merged pull request #116\n",
                    standardError: "",
                    exitCode: 0
                )
            ],
            onInvocation: { invocation in
                if Array(invocation.arguments.prefix(2)) == ["pr", "merge"] {
                    XCTAssertEqual(accessCounter.value, 0)
                }
            }
        )
        let tool = DevelopmentPullRequestMergeTool(
            projectStore: stores.projects,
            gitRunner: gitRunner,
            githubRunner: githubRunner,
            bookmarkResolver: resolver
        )

        let result = try tool.execute(
            arguments: [
                "projectId": .number(Double(project.id)),
                "pullRequestURL": .string(pullRequestURL),
                "branchName": .string(branchName),
                "baseBranch": .string(baseBranch)
            ],
            context: approvedContext()
        )

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(result.output["merged"], .bool(true))
        XCTAssertEqual(resolver.resolvedBookmarks, [bookmarkData])
        XCTAssertEqual(accessCounter.value, 1)
    }

    func testDevelopmentPublishPoliciesRejectUnsafeCommands() {
        XCTAssertTrue(DevelopmentPublishGitCommandPolicy.isAllowed(arguments: ["status", "--short", "--branch"]))
        XCTAssertTrue(DevelopmentPublishGitCommandPolicy.isAllowed(arguments: ["remote", "get-url", "origin"]))
        XCTAssertTrue(DevelopmentPublishGitCommandPolicy.isAllowed(arguments: ["push", "-u", "origin", "feature/solopm-1-task"]))
        XCTAssertFalse(DevelopmentPublishGitCommandPolicy.isAllowed(arguments: ["push"]))
        XCTAssertFalse(DevelopmentPublishGitCommandPolicy.isAllowed(arguments: ["push", "--force", "origin", "feature/solopm-1-task"]))
        XCTAssertFalse(DevelopmentPublishGitCommandPolicy.isAllowed(arguments: ["push", "--mirror"]))
        XCTAssertFalse(DevelopmentPublishGitCommandPolicy.isAllowed(arguments: ["push", "--tags"]))
        XCTAssertFalse(DevelopmentPublishGitCommandPolicy.isAllowed(arguments: ["reset", "--hard"]))
        XCTAssertFalse(DevelopmentPublishGitCommandPolicy.isAllowed(arguments: ["push", "-u", "origin", "main"]))
        XCTAssertFalse(DevelopmentPublishGitCommandPolicy.isAllowed(arguments: ["push", "-u", "origin", "develop"]))

        let bodyFile = FileManager.default.temporaryDirectory.appendingPathComponent("solopm-pr-body-test.md").path
        XCTAssertTrue(DevelopmentGitHubPRCommandPolicy.isAllowed(arguments: [
            "pr", "create",
            "--base", "main",
            "--head", "feature/solopm-1-task",
            "--title", "Add publish gate",
            "--body-file", bodyFile
        ]))
        XCTAssertFalse(DevelopmentGitHubPRCommandPolicy.isAllowed(arguments: [
            "pr", "create",
            "--base", "main",
            "--head", "main",
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
        XCTAssertTrue(DevelopmentGitHubPRCommandPolicy.isAllowed(arguments: [
            "pr", "view", "https://github.com/albert-einshutoin/soloPM/pull/116",
            "--json", DevelopmentGitHubPRCommandPolicy.statusJSONFields
        ]))
        XCTAssertTrue(DevelopmentGitHubPRCommandPolicy.isAllowed(arguments: [
            "api", "graphql",
            "-f", "query=\(DevelopmentGitHubPRCommandPolicy.reviewThreadsQuery)",
            "-F", "owner=albert-einshutoin",
            "-F", "repo=soloPM",
            "-F", "number=116"
        ]))
        XCTAssertTrue(DevelopmentGitHubPRCommandPolicy.isAllowed(arguments: [
            "pr", "merge", "https://github.com/albert-einshutoin/soloPM/pull/116",
            "--merge", "--delete-branch",
            "--match-head-commit", "0123456789abcdef0123456789abcdef01234567"
        ]))
        XCTAssertFalse(DevelopmentGitHubPRCommandPolicy.isAllowed(arguments: [
            "pr", "merge", "https://github.com/albert-einshutoin/soloPM/pull/116",
            "--merge", "--delete-branch"
        ]))
        XCTAssertFalse(DevelopmentGitHubPRCommandPolicy.isAllowed(arguments: [
            "pr", "merge", "https://github.com/albert-einshutoin/soloPM/pull/116",
            "--squash", "--delete-branch"
        ]))
        XCTAssertFalse(DevelopmentGitHubPRCommandPolicy.isAllowed(arguments: [
            "pr", "merge", "https://github.com/albert-einshutoin/soloPM/pull/116",
            "--merge", "--admin"
        ]))
        XCTAssertFalse(DevelopmentGitHubPRCommandPolicy.isAllowed(arguments: [
            "pr", "view", "https://example.com/repo/pull/116",
            "--json", DevelopmentGitHubPRCommandPolicy.statusJSONFields
        ]))
        XCTAssertFalse(DevelopmentGitHubPRCommandPolicy.isAllowed(arguments: [
            "pr", "view", "https://user:token@github.com/albert-einshutoin/soloPM/pull/116",
            "--json", DevelopmentGitHubPRCommandPolicy.statusJSONFields
        ]))
        XCTAssertFalse(DevelopmentGitHubPRCommandPolicy.isAllowed(arguments: [
            "pr", "view", "https://github.com/albert-einshutoin/soloPM/pull/116?merge=1",
            "--json", DevelopmentGitHubPRCommandPolicy.statusJSONFields
        ]))
        XCTAssertFalse(DevelopmentGitHubPRCommandPolicy.isAllowed(arguments: [
            "pr", "view", "https://github.com/albert-einshutoin/soloPM/pull/not-a-number",
            "--json", DevelopmentGitHubPRCommandPolicy.statusJSONFields
        ]))
        XCTAssertFalse(DevelopmentGitHubPRCommandPolicy.isAllowed(arguments: [
            "pr", "view", "https://github.com/albert-einshutoin//soloPM/pull/116",
            "--json", DevelopmentGitHubPRCommandPolicy.statusJSONFields
        ]))
        XCTAssertFalse(DevelopmentGitHubPRCommandPolicy.isAllowed(arguments: [
            "pr", "view", "https://github.com/albert-einshutoin/soloPM/pull/116/",
            "--json", DevelopmentGitHubPRCommandPolicy.statusJSONFields
        ]))
    }

    func testPullRequestReviewGateRejectsMalformedOriginRemoteBeforeGitHubRead() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try createPublishProject(stores: stores, workspace: workspace)
        let gitRunner = RecordingDevelopmentGitRunner()
        stubOrigin(gitRunner, remoteURL: "https://github.com/albert-einshutoin//soloPM.git")
        let githubRunner = RecordingGitHubCLICommandRunner()
        let tool = DevelopmentPullRequestReviewGateTool(
            projectStore: stores.projects,
            gitRunner: gitRunner,
            githubRunner: githubRunner,
            bookmarkResolver: publishBookmarkResolver(for: workspace)
        )

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "pullRequestURL": .string("https://github.com/albert-einshutoin/soloPM/pull/116"),
                    "branchName": .string("feature/solopm-\(project.id)-merge-gate"),
                    "baseBranch": .string("feature/phase14-product-completion")
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(.developmentReviewPullRequestGate, "Origin remote must resolve to a GitHub repository.")
            )
        }
        XCTAssertEqual(githubRunner.recordedInvocations, [])
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

    private func createPublishProject(
        stores: (projects: SQLiteProjectStore, tasks: SQLiteTaskStore),
        workspace: URL
    ) throws -> ProjectRecord {
        try stores.projects.create(
            title: "SoloPM",
            workspacePath: workspace.path,
            workspaceBookmarkData: Data("publish-workspace-bookmark".utf8)
        )
    }

    private func publishBookmarkResolver(for workspace: URL) -> any ProjectWorkspaceBookmarkResolving {
        PRWorkflowRecordingProjectWorkspaceBookmarkResolver(
            resolution: ProjectWorkspaceBookmarkResolution(
                url: workspace,
                isStale: false,
                didStartAccessing: true,
                stopAccessing: {}
            )
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

    private func stubOrigin(
        _ runner: RecordingDevelopmentGitRunner,
        remoteURL: String = "https://github.com/albert-einshutoin/soloPM.git"
    ) {
        runner.stub(
            arguments: ["remote", "get-url", "origin"],
            output: GitCommandOutput(standardOutput: "\(remoteURL)\n", standardError: "", exitCode: 0)
        )
    }

    private func pullRequestStatusJSON(
        url: String,
        headBranch: String,
        baseBranch: String,
        headRefOID: String = "0123456789abcdef0123456789abcdef01234567",
        reviewDecision: String,
        mergeable: String,
        mergeStateStatus: String,
        checks: [(name: String, status: String, conclusion: String?)],
        headOwner: String = "albert-einshutoin",
        headRepository: String = "soloPM",
        isCrossRepository: Bool = false
    ) -> String {
        let checkObjects = checks.map { check -> String in
            let conclusion = check.conclusion.map { "\"\($0)\"" } ?? "null"
            return """
            {
              "__typename": "CheckRun",
              "name": "\(check.name)",
              "status": "\(check.status)",
              "conclusion": \(conclusion)
            }
            """
        }.joined(separator: ",")
        return """
        {
          "url": "\(url)",
          "headRefName": "\(headBranch)",
          "headRefOid": "\(headRefOID)",
          "baseRefName": "\(baseBranch)",
          "headRepository": {
            "name": "\(headRepository)",
            "nameWithOwner": "\(headOwner)/\(headRepository)"
          },
          "headRepositoryOwner": {
            "login": "\(headOwner)"
          },
          "isCrossRepository": \(isCrossRepository ? "true" : "false"),
          "reviewDecision": "\(reviewDecision)",
          "mergeable": "\(mergeable)",
          "mergeStateStatus": "\(mergeStateStatus)",
          "statusCheckRollup": [\(checkObjects)]
        }
        """
    }

    private func reviewThreadsJSON(
        totalCount: Int,
        unresolvedCount: Int,
        hasNextPage: Bool = false
    ) -> String {
        let resolvedCount = max(0, totalCount - unresolvedCount)
        let nodes = Array(repeating: #"{"isResolved": false}"#, count: unresolvedCount)
            + Array(repeating: #"{"isResolved": true}"#, count: resolvedCount)
        return """
        {
          "data": {
            "repository": {
              "pullRequest": {
                "reviewThreads": {
                  "totalCount": \(totalCount),
                  "nodes": [\(nodes.joined(separator: ","))],
                  "pageInfo": {
                    "hasNextPage": \(hasNextPage ? "true" : "false")
                  }
                }
              }
            }
          }
        }
        """
    }
}

private final class RecordingGitHubCLICommandRunner: GitHubCLICommandRunner, @unchecked Sendable {
    private var outputs: [GitHubCLICommandOutput]
    private let onInvocation: (@Sendable (GitHubCLICommandInvocation) -> Void)?
    private(set) var recordedInvocations: [GitHubCLICommandInvocation] = []
    private(set) var recordedBodyFiles: [String] = []

    init(
        output: GitHubCLICommandOutput = GitHubCLICommandOutput(
            standardOutput: "",
            standardError: "unexpected command",
            exitCode: 127
        ),
        onInvocation: (@Sendable (GitHubCLICommandInvocation) -> Void)? = nil
    ) {
        self.outputs = [output]
        self.onInvocation = onInvocation
    }

    init(
        outputs: [GitHubCLICommandOutput],
        onInvocation: (@Sendable (GitHubCLICommandInvocation) -> Void)? = nil
    ) {
        self.outputs = outputs
        self.onInvocation = onInvocation
    }

    func runGitHub(arguments: [String], workingDirectory: URL) throws -> GitHubCLICommandOutput {
        let invocation = GitHubCLICommandInvocation(arguments: arguments, workingDirectory: workingDirectory)
        recordedInvocations.append(invocation)
        onInvocation?(invocation)
        if let bodyFileIndex = arguments.firstIndex(of: "--body-file"),
           arguments.indices.contains(arguments.index(after: bodyFileIndex)) {
            let bodyFile = arguments[arguments.index(after: bodyFileIndex)]
            recordedBodyFiles.append((try? String(contentsOfFile: bodyFile, encoding: .utf8)) ?? "")
        }
        if outputs.count > 1 {
            return outputs.removeFirst()
        }
        return outputs.first ?? GitHubCLICommandOutput(
            standardOutput: "",
            standardError: "unexpected command",
            exitCode: 127
        )
    }
}

private final class PRWorkflowRecordingAccessCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

private final class PRWorkflowRecordingProjectWorkspaceBookmarkResolver: ProjectWorkspaceBookmarkResolving, @unchecked Sendable {
    private let resolution: ProjectWorkspaceBookmarkResolution
    private(set) var resolvedBookmarks: [Data] = []

    init(resolution: ProjectWorkspaceBookmarkResolution) {
        self.resolution = resolution
    }

    func resolve(bookmarkData: Data) throws -> ProjectWorkspaceBookmarkResolution {
        resolvedBookmarks.append(bookmarkData)
        return resolution
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
