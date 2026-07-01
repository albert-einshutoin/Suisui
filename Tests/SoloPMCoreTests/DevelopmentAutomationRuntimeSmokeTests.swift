import XCTest
@testable import SoloPMCore

final class DevelopmentAutomationRuntimeSmokeTests: XCTestCase {
    func testApprovedProjectDirectoryCanEditVerifyCommitAndPreparePullRequestBranch() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        defer { cleanupTemporaryDirectory(workspace) }
        try seedGitRepository(at: workspace)

        let bookmarkData = Data("approved-development-runtime-workspace".utf8)
        let project = try stores.projects.create(
            title: "Runtime Dev Repo",
            workspacePath: workspace.path,
            workspaceBookmarkData: bookmarkData
        )
        let task = try stores.tasks.create(
            title: "Implement runtime smoke fixture",
            projectID: project.id,
            sourceCommand: "runtime-development-pr-smoke"
        )
        let resolver = RuntimeSmokeBookmarkResolver(workspace: workspace, expectedBookmarkData: bookmarkData)
        let context = approvedContext()
        let branchName = "feature/solopm-\(project.id)-\(task.id)-runtime-smoke"

        let prepareResult = try DevelopmentPRWorkflowTool(
            projectStore: stores.projects,
            taskStore: stores.tasks,
            bookmarkResolver: resolver,
            requireBookmark: true
        ).execute(
            arguments: [
                "projectId": .number(Double(project.id)),
                "taskId": .number(Double(task.id)),
                "branchName": .string(branchName)
            ],
            context: context
        )

        XCTAssertEqual(prepareResult.status, .succeeded)
        XCTAssertEqual(prepareResult.output["branchName"], .string(branchName))
        XCTAssertEqual(prepareResult.output["requiresPushApproval"], .bool(true))
        XCTAssertEqual(prepareResult.output["requiresPullRequestApproval"], .bool(true))

        let listResult = try DevelopmentRepositoryFileTool(
            name: .developmentRepositoryListFiles,
            projectStore: stores.projects,
            artifactStore: stores.artifacts,
            bookmarkResolver: resolver,
            requireBookmark: true
        ).execute(arguments: ["projectId": .number(Double(project.id))], context: context)

        XCTAssertEqual(listResult.status, .succeeded)
        let listedPaths = try XCTUnwrap(listResult.output["entries"]?.arrayValue).compactMap {
            $0.objectValue?["relativePath"]?.stringValue
        }
        XCTAssertTrue(listedPaths.contains("README.md"))

        let readResult = try DevelopmentRepositoryFileTool(
            name: .developmentRepositoryReadFile,
            projectStore: stores.projects,
            artifactStore: stores.artifacts,
            bookmarkResolver: resolver,
            requireBookmark: true
        ).execute(
            arguments: [
                "projectId": .number(Double(project.id)),
                "relativePath": .string("README.md")
            ],
            context: context
        )
        let readSHA = try XCTUnwrap(readResult.output["sha256"]?.stringValue)

        let createResult = try DevelopmentRepositoryFileTool(
            name: .developmentRepositoryCreateFile,
            projectStore: stores.projects,
            artifactStore: stores.artifacts,
            bookmarkResolver: resolver,
            requireBookmark: true
        ).execute(
            arguments: [
                "projectId": .number(Double(project.id)),
                "relativePath": .string("docs/runtime-smoke.md"),
                "contents": .string("# Runtime Smoke\n\n- Runs inside the approved project directory.\n")
            ],
            context: context
        )

        XCTAssertEqual(createResult.status, .succeeded)
        XCTAssertNotNil(createResult.output["artifactId"])

        let updateResult = try DevelopmentRepositoryFileTool(
            name: .developmentRepositoryUpdateFile,
            projectStore: stores.projects,
            artifactStore: stores.artifacts,
            bookmarkResolver: resolver,
            requireBookmark: true
        ).execute(
            arguments: [
                "projectId": .number(Double(project.id)),
                "relativePath": .string("README.md"),
                "expectedSHA256": .string(readSHA),
                "contents": .string("# Runtime Dev Repo\n\nUpdated by SoloPM development runtime smoke.\n")
            ],
            context: context
        )

        XCTAssertEqual(updateResult.status, .succeeded)
        XCTAssertNotNil(updateResult.output["artifactId"])

        let verificationResult = try DevelopmentVerificationCommandTool(
            projectStore: stores.projects,
            bookmarkResolver: resolver,
            requireBookmark: true
        ).execute(
            arguments: [
                "projectId": .number(Double(project.id)),
                "commandId": .string("git.diff_check")
            ],
            context: context
        )

        XCTAssertEqual(verificationResult.status, .succeeded)
        XCTAssertEqual(verificationResult.output["passed"], .bool(true))

        let commitResult = try DevelopmentCommitWorkflowTool(
            projectStore: stores.projects,
            bookmarkResolver: resolver,
            requireBookmark: true
        ).execute(
            arguments: [
                "projectId": .number(Double(project.id)),
                "relativePaths": .array([
                    .string("README.md"),
                    .string("docs/runtime-smoke.md")
                ]),
                "commitMessage": .string("Add development runtime smoke fixture")
            ],
            context: context
        )

        XCTAssertEqual(commitResult.status, .succeeded)
        XCTAssertEqual(commitResult.output["requiresPushApproval"], .bool(true))
        XCTAssertEqual(commitResult.output["requiresPullRequestApproval"], .bool(true))
        XCTAssertEqual(try stores.artifacts.list().count, 2)

        let status = try runGit(["status", "--short", "--branch"], in: workspace)
        XCTAssertTrue(status.standardOutput.contains("## \(branchName)"))
        XCTAssertFalse(status.standardOutput.contains("README.md"))
        XCTAssertFalse(status.standardOutput.contains("runtime-smoke.md"))

        try runGit(["remote", "add", "origin", "https://github.com/albert-einshutoin/soloPM.git"], in: workspace)
        let githubRunner = RuntimeSmokeGitHubRunner(
            output: GitHubCLICommandOutput(
                standardOutput: "https://github.com/albert-einshutoin/soloPM/pull/9999\n",
                standardError: "",
                exitCode: 0
            )
        )
        let pullRequestResult = try DevelopmentPullRequestCreationTool(
            projectStore: stores.projects,
            githubRunner: githubRunner,
            bookmarkResolver: resolver
        ).execute(
            arguments: [
                "projectId": .number(Double(project.id)),
                "branchName": .string(branchName),
                "baseBranch": .string("feature/phase14-product-completion"),
                "title": .string("Add development runtime smoke fixture"),
                "body": .string("## Summary\n- Adds approved project-directory runtime smoke evidence\n")
            ],
            context: context
        )

        XCTAssertEqual(pullRequestResult.status, .succeeded)
        XCTAssertEqual(
            pullRequestResult.output["pullRequestURL"],
            .string("https://github.com/albert-einshutoin/soloPM/pull/9999")
        )
        let githubInvocation = try XCTUnwrap(githubRunner.recordedInvocations.first)
        XCTAssertEqual(githubRunner.recordedInvocations.count, 1)
        XCTAssertEqual(githubInvocation.workingDirectory, workspace.resolvingSymlinksInPath().standardizedFileURL)
        XCTAssertEqual(githubInvocation.arguments.count, 10)
        XCTAssertEqual(Array(githubInvocation.arguments.prefix(8)), [
            "pr", "create",
            "--base", "feature/phase14-product-completion",
            "--head", branchName,
            "--title", "Add development runtime smoke fixture"
        ])
        XCTAssertEqual(githubInvocation.arguments[8], "--body-file")
        XCTAssertEqual(githubRunner.recordedBodyFiles, [
            "## Summary\n- Adds approved project-directory runtime smoke evidence\n"
        ])
        XCTAssertFalse(githubInvocation.arguments.contains("--body"))
        XCTAssertFalse(githubInvocation.arguments.contains("--fill"))

        XCTAssertGreaterThanOrEqual(resolver.resolvedBookmarks.count, 7)
        XCTAssertEqual(Set(resolver.resolvedBookmarks), [bookmarkData])
    }

    private func makeStores() throws -> (
        projects: SQLiteProjectStore,
        tasks: SQLiteTaskStore,
        artifacts: SQLiteArtifactStore
    ) {
        let connection = try SQLiteConnection(path: ":memory:")
        try DevelopmentAutomationRuntimeSmokeMigrationRunner.migrate(
            connection: connection,
            migrations: CoreMigrations.current
        )
        return (
            SQLiteProjectStore(connection: connection),
            SQLiteTaskStore(connection: connection),
            SQLiteArtifactStore(connection: connection)
        )
    }

    private func approvedContext() -> ToolExecutionContext {
        ToolExecutionContext(
            approvalToken: ApprovalToken(id: "runtime-smoke-approval", sessionID: "runtime-smoke-session"),
            source: .reviewUI
        )
    }

    private func temporaryDirectory() -> URL {
        let parent = ProcessInfo.processInfo.environment["SOLOPM_RUNTIME_DEVELOPMENT_PR_WORKSPACE_ROOT"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
        let url = parent
            .appendingPathComponent("SoloPMDevelopmentAutomationRuntimeSmokeTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanupTemporaryDirectory(_ workspace: URL) {
        guard ProcessInfo.processInfo.environment["SOLOPM_RUNTIME_DEVELOPMENT_PR_KEEP_WORKSPACE"] != "1" else {
            return
        }
        try? FileManager.default.removeItem(at: workspace)
    }

    private func seedGitRepository(at workspace: URL) throws {
        try write("# Runtime Dev Repo\n", to: workspace.appendingPathComponent("README.md"))
        try runGit(["init"], in: workspace)
        try runGit(["config", "user.email", "runtime-smoke@example.invalid"], in: workspace)
        try runGit(["config", "user.name", "SoloPM Runtime Smoke"], in: workspace)
        try runGit(["add", "README.md"], in: workspace)
        try runGit(["commit", "-m", "Initial fixture"], in: workspace)
    }

    @discardableResult
    private func runGit(_ arguments: [String], in workspace: URL) throws -> GitCommandOutput {
        let output = try ProcessGitCommandRunner().runGit(arguments: arguments, workingDirectory: workspace)
        XCTAssertEqual(output.exitCode, 0, output.standardError)
        return output
    }

    private func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}

private final class RuntimeSmokeBookmarkResolver: ProjectWorkspaceBookmarkResolving, @unchecked Sendable {
    private let workspace: URL
    private let expectedBookmarkData: Data
    private let lock = NSLock()
    private var bookmarks: [Data] = []

    init(workspace: URL, expectedBookmarkData: Data) {
        self.workspace = workspace
        self.expectedBookmarkData = expectedBookmarkData
    }

    var resolvedBookmarks: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return bookmarks
    }

    func resolve(bookmarkData: Data) throws -> ProjectWorkspaceBookmarkResolution {
        XCTAssertEqual(bookmarkData, expectedBookmarkData)
        lock.lock()
        bookmarks.append(bookmarkData)
        lock.unlock()
        return ProjectWorkspaceBookmarkResolution(
            url: workspace,
            isStale: false,
            didStartAccessing: true,
            stopAccessing: {}
        )
    }
}

private final class RuntimeSmokeGitHubRunner: GitHubCLICommandRunner, @unchecked Sendable {
    private let output: GitHubCLICommandOutput
    private(set) var recordedInvocations: [GitHubCLICommandInvocation] = []
    private(set) var recordedBodyFiles: [String] = []

    init(output: GitHubCLICommandOutput) {
        self.output = output
    }

    func runGitHub(arguments: [String], workingDirectory: URL) throws -> GitHubCLICommandOutput {
        recordedInvocations.append(
            GitHubCLICommandInvocation(
                arguments: arguments,
                workingDirectory: workingDirectory
            )
        )
        if let bodyFileIndex = arguments.firstIndex(of: "--body-file"),
           arguments.indices.contains(bodyFileIndex + 1) {
            let bodyFile = arguments[bodyFileIndex + 1]
            recordedBodyFiles.append(
                (try? String(contentsOfFile: bodyFile, encoding: .utf8)) ?? ""
            )
        }
        return output
    }
}

private enum DevelopmentAutomationRuntimeSmokeMigrationRunner {
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
