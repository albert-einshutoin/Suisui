import XCTest
@testable import SuisuiCore

final class DevelopmentRepositoryFileAccessTests: XCTestCase {
    func testWorkspaceScopeUsesStoredBookmarkAndStopsAccessWhenReleased() throws {
        let workspace = temporaryDirectory()
        let bookmarkData = Data("workspace-bookmark".utf8)
        let accessCounter = RecordingAccessCounter()
        let resolver = RecordingProjectWorkspaceBookmarkResolver(
            resolution: ProjectWorkspaceBookmarkResolution(
                url: workspace,
                isStale: false,
                didStartAccessing: true,
                stopAccessing: { accessCounter.increment() }
            )
        )
        let project = ProjectRecord(
            id: 42,
            title: "Suisui",
            status: "active",
            workspacePath: workspace.path,
            workspaceBookmarkData: bookmarkData
        )

        do {
            let scope = try ProjectWorkspaceScope(project: project, bookmarkResolver: resolver)
            XCTAssertEqual(scope.rootURL.path, workspace.resolvingSymlinksInPath().path)
            XCTAssertEqual(resolver.resolvedBookmarks, [bookmarkData])
            XCTAssertEqual(accessCounter.value, 0)
        }

        XCTAssertEqual(accessCounter.value, 1)
    }

    func testWorkspaceScopeRejectsStaleStoredBookmarkBeforePathOnlyFallback() throws {
        let workspace = temporaryDirectory()
        let bookmarkData = Data("stale-bookmark".utf8)
        let resolver = RecordingProjectWorkspaceBookmarkResolver(
            resolution: ProjectWorkspaceBookmarkResolution(
                url: workspace,
                isStale: true,
                didStartAccessing: false
            )
        )
        let project = ProjectRecord(
            id: 42,
            title: "Suisui",
            status: "active",
            workspacePath: workspace.path,
            workspaceBookmarkData: bookmarkData
        )

        XCTAssertThrowsError(try ProjectWorkspaceScope(project: project, bookmarkResolver: resolver)) { error in
            XCTAssertEqual(error as? DevelopmentPRWorkflowError, .projectWorkspaceBookmarkStale)
        }
        XCTAssertEqual(resolver.resolvedBookmarks, [bookmarkData])
    }

    func testWorkspaceScopeRejectsBookmarkWhenSecurityScopeCannotStart() throws {
        let workspace = temporaryDirectory()
        let bookmarkData = Data("denied-bookmark".utf8)
        let resolver = RecordingProjectWorkspaceBookmarkResolver(
            resolution: ProjectWorkspaceBookmarkResolution(
                url: workspace,
                isStale: false,
                didStartAccessing: false
            )
        )
        let project = ProjectRecord(
            id: 42,
            title: "Suisui",
            status: "active",
            workspacePath: workspace.path,
            workspaceBookmarkData: bookmarkData
        )

        XCTAssertThrowsError(try ProjectWorkspaceScope(project: project, bookmarkResolver: resolver)) { error in
            XCTAssertEqual(error as? DevelopmentPRWorkflowError, .projectWorkspaceBookmarkUnavailable)
        }
        XCTAssertEqual(resolver.resolvedBookmarks, [bookmarkData])
    }

    func testWorkspaceScopeRejectsEmptyStoredBookmarkInsteadOfPathOnlyFallback() throws {
        let workspace = temporaryDirectory()
        let resolver = RecordingProjectWorkspaceBookmarkResolver(
            resolution: ProjectWorkspaceBookmarkResolution(
                url: workspace,
                isStale: false,
                didStartAccessing: true
            )
        )
        let project = ProjectRecord(
            id: 42,
            title: "Suisui",
            status: "active",
            workspacePath: workspace.path,
            workspaceBookmarkData: Data()
        )

        XCTAssertThrowsError(try ProjectWorkspaceScope(project: project, bookmarkResolver: resolver)) { error in
            XCTAssertEqual(error as? DevelopmentPRWorkflowError, .projectWorkspaceBookmarkUnavailable)
        }
        XCTAssertEqual(resolver.resolvedBookmarks, [])
    }

    func testWorkspaceScopeCanRequireBookmarkForExternalDeveloperAutomation() throws {
        let workspace = temporaryDirectory()
        let resolver = RecordingProjectWorkspaceBookmarkResolver(
            resolution: ProjectWorkspaceBookmarkResolution(
                url: workspace,
                isStale: false,
                didStartAccessing: true
            )
        )
        let project = ProjectRecord(
            id: 42,
            title: "Suisui",
            status: "active",
            workspacePath: workspace.path,
            workspaceBookmarkData: nil
        )

        XCTAssertThrowsError(try ProjectWorkspaceScope(
            project: project,
            bookmarkResolver: resolver,
            requireBookmark: true
        )) { error in
            XCTAssertEqual(error as? DevelopmentPRWorkflowError, .projectWorkspaceBookmarkUnavailable)
        }
        XCTAssertEqual(resolver.resolvedBookmarks, [])
    }

    func testWorkspaceScopeRejectsBookmarkResolvingToDifferentDirectory() throws {
        let workspace = temporaryDirectory()
        let outside = temporaryDirectory()
        let bookmarkData = Data("mismatched-bookmark".utf8)
        let accessCounter = RecordingAccessCounter()
        let resolver = RecordingProjectWorkspaceBookmarkResolver(
            resolution: ProjectWorkspaceBookmarkResolution(
                url: outside,
                isStale: false,
                didStartAccessing: true,
                stopAccessing: { accessCounter.increment() }
            )
        )
        let project = ProjectRecord(
            id: 42,
            title: "Suisui",
            status: "active",
            workspacePath: workspace.path,
            workspaceBookmarkData: bookmarkData
        )

        XCTAssertThrowsError(try ProjectWorkspaceScope(project: project, bookmarkResolver: resolver)) { error in
            XCTAssertEqual(error as? DevelopmentPRWorkflowError, .projectWorkspaceBookmarkPathMismatch)
        }
        XCTAssertEqual(resolver.resolvedBookmarks, [bookmarkData])
        XCTAssertEqual(accessCounter.value, 1)
    }

    func testRepositoryFileClientKeepsBookmarkAccessThroughRead() throws {
        let workspace = temporaryDirectory()
        try write("let value = 1\n", to: workspace.appendingPathComponent("Sources/App.swift"))
        let bookmarkData = Data("read-workspace-bookmark".utf8)
        let accessCounter = RecordingAccessCounter()
        let resolver = RecordingProjectWorkspaceBookmarkResolver(
            resolution: ProjectWorkspaceBookmarkResolution(
                url: workspace,
                isStale: false,
                didStartAccessing: true,
                stopAccessing: { accessCounter.increment() }
            )
        )
        let project = ProjectRecord(
            id: 42,
            title: "Suisui",
            status: "active",
            workspacePath: workspace.path,
            workspaceBookmarkData: bookmarkData
        )
        let client = DevelopmentRepositoryFileClient(project: project, bookmarkResolver: resolver)

        let record = try client.read(relativePath: "Sources/App.swift")

        XCTAssertEqual(record.contents, "let value = 1\n")
        XCTAssertEqual(resolver.resolvedBookmarks, [bookmarkData])
        XCTAssertEqual(accessCounter.value, 1)
    }

    func testRepositoryFileClientAllowsSwiftAuthorizationTypesButRejectsLiteralCredentials() throws {
        let workspace = temporaryDirectory()
        let safeSource = """
        struct Tooling {
            var authorization: ToolActionAuthorization?

            func use(authorization: AuthorizationPolicy) {
                request(authorization: authorizationStatus())
            }
        }
        """
        try write(safeSource, to: workspace.appendingPathComponent("Sources/Tooling.swift"))
        try write(
            "request(authorization: \"Token file-access-secret-marker\")\n",
            to: workspace.appendingPathComponent("Sources/Unsafe.swift")
        )
        let project = ProjectRecord(
            id: 42,
            title: "Suisui",
            status: "active",
            workspacePath: workspace.path
        )
        let client = DevelopmentRepositoryFileClient(project: project)

        let safeRecord = try client.read(relativePath: "Sources/Tooling.swift")

        XCTAssertEqual(safeRecord.contents, safeSource)
        XCTAssertThrowsError(try client.read(relativePath: "Sources/Unsafe.swift")) { error in
            guard case .secretLikeContent = error as? DevelopmentRepositoryFileError else {
                return XCTFail("Expected secret-like content rejection, got \(error)")
            }
        }
    }

    func testListFilesWithinApprovedWorkspaceReturnsSortedEntries() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        try write("# Suisui\n", to: workspace.appendingPathComponent("README.md"))
        try write("let value = 1\n", to: workspace.appendingPathComponent("Sources/App.swift"))
        try write("# Plan\n", to: workspace.appendingPathComponent("docs/plan.md"))
        try write("ignored\n", to: workspace.appendingPathComponent("docs/image.png"))
        try Data([0xFF, 0xFE, 0x00]).write(to: workspace.appendingPathComponent("docs/binary.txt"))
        try write("token=secret\n", to: workspace.appendingPathComponent(".env"))
        try FileManager.default.createDirectory(at: workspace.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try write("ref: refs/heads/main\n", to: workspace.appendingPathComponent(".git/HEAD"))
        let project = try stores.projects.create(title: "Suisui", workspacePath: workspace.path)
        let tool = DevelopmentRepositoryFileTool(name: .developmentRepositoryListFiles, projectStore: stores.projects)

        let result = try tool.execute(
            arguments: ["projectId": .number(Double(project.id))],
            context: ToolExecutionContext(source: .reviewUI)
        )

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(result.output["entryCount"], .number(3))
        XCTAssertEqual(result.output["truncated"], .bool(false))
        let entries = try XCTUnwrap(result.output["entries"]?.arrayValue)
        XCTAssertEqual(entries.map { $0.objectValue?["relativePath"] }, [
            .string("README.md"),
            .string("Sources/App.swift"),
            .string("docs/plan.md")
        ])
        XCTAssertEqual(entries.map { $0.objectValue?["byteCount"] }, [
            .number(9),
            .number(14),
            .number(7)
        ])

        let docsOnly = try tool.execute(
            arguments: [
                "projectId": .number(Double(project.id)),
                "relativePath": .string("docs")
            ],
            context: ToolExecutionContext(source: .reviewUI)
        )

        XCTAssertEqual(docsOnly.output["entryCount"], .number(1))
        XCTAssertEqual(
            docsOnly.output["entries"]?.arrayValue?.first?.objectValue?["relativePath"],
            .string("docs/plan.md")
        )
    }

    func testListFilesCapsLargeWorkspaceResults() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        for index in 0...DevelopmentRepositoryFilePathPolicy.maximumListedFileEntries {
            try write("file \(index)\n", to: workspace.appendingPathComponent("docs/file-\(index).md"))
        }
        let project = try stores.projects.create(title: "Suisui", workspacePath: workspace.path)
        let tool = DevelopmentRepositoryFileTool(name: .developmentRepositoryListFiles, projectStore: stores.projects)

        let result = try tool.execute(
            arguments: [
                "projectId": .number(Double(project.id)),
                "relativePath": .string("docs")
            ],
            context: ToolExecutionContext(source: .reviewUI)
        )

        XCTAssertEqual(
            result.output["entryCount"],
            .number(Double(DevelopmentRepositoryFilePathPolicy.maximumListedFileEntries))
        )
        XCTAssertEqual(result.output["truncated"], .bool(true))
    }

    func testListFilesCapsVisitedNodesEvenWhenMostFilesAreUnsupported() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let generatedDirectory = workspace.appendingPathComponent("generated")
        try FileManager.default.createDirectory(at: generatedDirectory, withIntermediateDirectories: true)
        for index in 0...DevelopmentRepositoryFilePathPolicy.maximumListedFileSystemNodes {
            try Data([0xFF, 0xFE, 0x00]).write(to: generatedDirectory.appendingPathComponent("blob-\(index).bin"))
        }
        let project = try stores.projects.create(title: "Suisui", workspacePath: workspace.path)
        let tool = DevelopmentRepositoryFileTool(name: .developmentRepositoryListFiles, projectStore: stores.projects)

        let result = try tool.execute(
            arguments: [
                "projectId": .number(Double(project.id)),
                "relativePath": .string("generated")
            ],
            context: ToolExecutionContext(source: .reviewUI)
        )

        XCTAssertEqual(result.output["entryCount"], .number(0))
        XCTAssertEqual(result.output["truncated"], .bool(true))
    }

    func testReadTextFileWithinApprovedWorkspaceReturnsContentAndDigest() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        try write("let value = 1\n", to: workspace.appendingPathComponent("Sources/App.swift"))
        try write("struct SecretStore {}\n", to: workspace.appendingPathComponent("Sources/SecretStore.swift"))
        let project = try stores.projects.create(title: "Suisui", workspacePath: workspace.path)
        let tool = DevelopmentRepositoryFileTool(name: .developmentRepositoryReadFile, projectStore: stores.projects)

        let result = try tool.execute(
            arguments: [
                "projectId": .number(Double(project.id)),
                "relativePath": .string("Sources/App.swift")
            ],
            context: ToolExecutionContext(source: .reviewUI)
        )

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(result.output["relativePath"], .string("Sources/App.swift"))
        XCTAssertEqual(result.output["contents"], .string("let value = 1\n"))
        XCTAssertEqual(result.output["byteCount"], .number(14))
        XCTAssertNotNil(result.output["sha256"])

        let sourceAboutSecrets = try tool.execute(
            arguments: [
                "projectId": .number(Double(project.id)),
                "relativePath": .string("Sources/SecretStore.swift")
            ],
            context: ToolExecutionContext(source: .reviewUI)
        )

        XCTAssertEqual(sourceAboutSecrets.status, .succeeded)
        XCTAssertEqual(sourceAboutSecrets.output["contents"], .string("struct SecretStore {}\n"))
    }

    func testRepositoryFileToolRejectsInvalidStoredBookmarkInsteadOfPathFallback() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        try write("# Plan\n", to: workspace.appendingPathComponent("docs/plan.md"))
        let project = try stores.projects.create(
            title: "Suisui",
            workspacePath: workspace.path,
            workspaceBookmarkData: Data("invalid-bookmark".utf8)
        )
        let tool = DevelopmentRepositoryFileTool(name: .developmentRepositoryListFiles, projectStore: stores.projects)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: ["projectId": .number(Double(project.id))],
                context: ToolExecutionContext(source: .reviewUI)
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(
                    .developmentRepositoryListFiles,
                    "Project workspace access bookmark could not be resolved and must be renewed."
                )
            )
        }
    }

    func testCreateAndUpdateTextFileRequireApprovalAndStayInsideWorkspace() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try stores.projects.create(title: "Suisui", workspacePath: workspace.path)
        let createTool = DevelopmentRepositoryFileTool(name: .developmentRepositoryCreateFile, projectStore: stores.projects)
        let updateTool = DevelopmentRepositoryFileTool(name: .developmentRepositoryUpdateFile, projectStore: stores.projects)

        XCTAssertThrowsError(
            try createTool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "relativePath": .string("docs/plan.md"),
                    "contents": .string("# Plan\n")
                ],
                context: ToolExecutionContext(source: .reviewUI)
            )
        ) { error in
            XCTAssertEqual(error as? ToolExecutionError, .approvalRequired(.developmentRepositoryCreateFile))
        }

        let created = try createTool.execute(
            arguments: [
                "projectId": .number(Double(project.id)),
                "relativePath": .string("docs/plan.md"),
                "contents": .string("# Plan\n")
            ],
            context: approvedContext()
        )
        let createdDigest = try XCTUnwrap(created.output["sha256"]?.stringValue)

        let updated = try updateTool.execute(
            arguments: [
                "projectId": .number(Double(project.id)),
                "relativePath": .string("docs/plan.md"),
                "contents": .string("# Updated\n"),
                "expectedSHA256": .string(createdDigest)
            ],
            context: approvedContext()
        )

        XCTAssertEqual(updated.status, .succeeded)
        XCTAssertEqual(try String(contentsOf: workspace.appendingPathComponent("docs/plan.md"), encoding: .utf8), "# Updated\n")
        XCTAssertEqual(updated.output["relativePath"], .string("docs/plan.md"))
        XCTAssertNotEqual(updated.output["sha256"], .string(createdDigest))
    }

    func testCreateRepositoryFilePersistsProjectArtifactLinkForProjectOverview() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let bookmarkData = Data("approved-repository-workspace".utf8)
        let resolver = RecordingProjectWorkspaceBookmarkResolver(
            resolution: ProjectWorkspaceBookmarkResolution(
                url: workspace,
                isStale: false,
                didStartAccessing: true,
                stopAccessing: {}
            )
        )
        let project = try stores.projects.create(
            title: "Suisui",
            workspacePath: workspace.path,
            workspaceBookmarkData: bookmarkData
        )
        let createTool = DevelopmentRepositoryFileTool(
            name: .developmentRepositoryCreateFile,
            projectStore: stores.projects,
            artifactStore: stores.artifacts,
            bookmarkResolver: resolver,
            requireBookmark: true
        )

        let result = try createTool.execute(
            arguments: [
                "projectId": .number(Double(project.id)),
                "relativePath": .string("docs/plan.md"),
                "contents": .string("# Plan\n")
            ],
            context: approvedContext()
        )

        let artifactURL = workspace.appendingPathComponent("docs/plan.md").standardizedFileURL
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifactURL.path))
        XCTAssertEqual(result.output["artifactId"], .number(1))
        XCTAssertEqual(result.rollbackMetadata["artifactId"], .number(1))
        XCTAssertEqual(resolver.resolvedBookmarks, [bookmarkData])

        let artifacts = try stores.artifacts.list()
        XCTAssertEqual(artifacts.count, 1)
        XCTAssertEqual(artifacts.first?.projectID, project.id)
        XCTAssertNil(artifacts.first?.taskID)
        XCTAssertEqual(artifacts.first?.workspacePath, workspace.resolvingSymlinksInPath().standardizedFileURL.path)
        XCTAssertEqual(artifacts.first?.expectedPath, artifactURL.path)
        XCTAssertEqual(artifacts.first?.createdState, .created)
    }

    func testCreateRepositoryFileReusesExistingExpectedProjectArtifact() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let artifactURL = workspace.appendingPathComponent("docs/plan.md").standardizedFileURL
        let bookmarkData = Data("approved-repository-create-workspace".utf8)
        let resolver = RecordingProjectWorkspaceBookmarkResolver(
            resolution: ProjectWorkspaceBookmarkResolution(
                url: workspace,
                isStale: false,
                didStartAccessing: true,
                stopAccessing: {}
            )
        )
        let project = try stores.projects.create(
            title: "Suisui",
            workspacePath: workspace.path,
            workspaceBookmarkData: bookmarkData
        )
        let existingArtifact = try stores.artifacts.create(
            projectID: project.id,
            workspacePath: artifactURL.deletingLastPathComponent().path,
            expectedPath: artifactURL.path,
            createdState: .expected
        )
        let createTool = DevelopmentRepositoryFileTool(
            name: .developmentRepositoryCreateFile,
            projectStore: stores.projects,
            artifactStore: stores.artifacts,
            bookmarkResolver: resolver,
            requireBookmark: true
        )

        let result = try createTool.execute(
            arguments: [
                "projectId": .number(Double(project.id)),
                "relativePath": .string("docs/plan.md"),
                "contents": .string("# Plan\n")
            ],
            context: approvedContext()
        )

        XCTAssertEqual(result.output["artifactId"], .number(Double(existingArtifact.id)))
        let artifacts = try stores.artifacts.list()
        XCTAssertEqual(artifacts.count, 1)
        XCTAssertEqual(artifacts.first?.id, existingArtifact.id)
        XCTAssertEqual(artifacts.first?.workspacePath, workspace.resolvingSymlinksInPath().standardizedFileURL.path)
        XCTAssertEqual(artifacts.first?.expectedPath, artifactURL.path)
        XCTAssertEqual(artifacts.first?.createdState, .created)
    }

    func testUpdateRepositoryFileRefreshesProjectArtifactLinkForProjectOverview() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        try write("# Draft\n", to: workspace.appendingPathComponent("docs/plan.md"))
        let artifactURL = workspace.appendingPathComponent("docs/plan.md").standardizedFileURL
        let bookmarkData = Data("approved-update-workspace".utf8)
        let resolver = RecordingProjectWorkspaceBookmarkResolver(
            resolution: ProjectWorkspaceBookmarkResolution(
                url: workspace,
                isStale: false,
                didStartAccessing: true,
                stopAccessing: {}
            )
        )
        let project = try stores.projects.create(
            title: "Suisui",
            workspacePath: workspace.path,
            workspaceBookmarkData: bookmarkData
        )
        let existingArtifact = try stores.artifacts.create(
            projectID: project.id,
            workspacePath: artifactURL.deletingLastPathComponent().path,
            expectedPath: artifactURL.path,
            createdState: .expected
        )
        let updateTool = DevelopmentRepositoryFileTool(
            name: .developmentRepositoryUpdateFile,
            projectStore: stores.projects,
            artifactStore: stores.artifacts,
            bookmarkResolver: resolver,
            requireBookmark: true
        )
        let readTool = DevelopmentRepositoryFileTool(
            name: .developmentRepositoryReadFile,
            projectStore: stores.projects,
            artifactStore: stores.artifacts,
            bookmarkResolver: resolver,
            requireBookmark: true
        )
        let readResult = try readTool.execute(
            arguments: [
                "projectId": .number(Double(project.id)),
                "relativePath": .string("docs/plan.md")
            ],
            context: ToolExecutionContext(source: .reviewUI)
        )
        let expectedSHA256 = try XCTUnwrap(readResult.output["sha256"]?.stringValue)

        let result = try updateTool.execute(
            arguments: [
                "projectId": .number(Double(project.id)),
                "relativePath": .string("docs/plan.md"),
                "contents": .string("# Updated\n"),
                "expectedSHA256": .string(expectedSHA256)
            ],
            context: approvedContext()
        )

        XCTAssertEqual(result.output["artifactId"], .number(Double(existingArtifact.id)))
        XCTAssertEqual(try String(contentsOf: artifactURL, encoding: .utf8), "# Updated\n")
        let artifacts = try stores.artifacts.list()
        XCTAssertEqual(artifacts.count, 1)
        XCTAssertEqual(artifacts.first?.id, existingArtifact.id)
        XCTAssertEqual(artifacts.first?.projectID, project.id)
        XCTAssertEqual(artifacts.first?.createdState, .created)
        XCTAssertNotNil(artifacts.first?.lastModifiedAt)
    }

    func testRepositoryFileToolRequiresStoredBookmarkBeforePathOnlyWorkspaceAccess() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        try write("# Plan\n", to: workspace.appendingPathComponent("docs/plan.md"))
        let project = try stores.projects.create(title: "Suisui", workspacePath: workspace.path)
        let listTool = DevelopmentRepositoryFileTool(
            name: .developmentRepositoryListFiles,
            projectStore: stores.projects,
            requireBookmark: true
        )

        XCTAssertThrowsError(
            try listTool.execute(
                arguments: ["projectId": .number(Double(project.id))],
                context: ToolExecutionContext(source: .reviewUI)
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(
                    .developmentRepositoryListFiles,
                    "Project workspace access bookmark could not be resolved and must be renewed."
                )
            )
        }
    }

    func testUpdateRejectsStaleDigestBeforeWriting() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        try write("old\n", to: workspace.appendingPathComponent("docs/plan.md"))
        let project = try stores.projects.create(title: "Suisui", workspacePath: workspace.path)
        let updateTool = DevelopmentRepositoryFileTool(name: .developmentRepositoryUpdateFile, projectStore: stores.projects)

        XCTAssertThrowsError(
            try updateTool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "relativePath": .string("docs/plan.md"),
                    "contents": .string("new\n"),
                    "expectedSHA256": .string(String(repeating: "0", count: 64))
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(.developmentRepositoryUpdateFile, "File changed since review; refresh the diff before updating.")
            )
        }

        XCTAssertEqual(try String(contentsOf: workspace.appendingPathComponent("docs/plan.md"), encoding: .utf8), "old\n")
    }

    func testUpdateRequiresExpectedSHAAndValidatesDigestShapeBeforeWriting() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        try write("old\n", to: workspace.appendingPathComponent("docs/plan.md"))
        let project = try stores.projects.create(title: "Suisui", workspacePath: workspace.path)
        let updateTool = DevelopmentRepositoryFileTool(name: .developmentRepositoryUpdateFile, projectStore: stores.projects)

        XCTAssertThrowsError(
            try updateTool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "relativePath": .string("docs/plan.md"),
                    "contents": .string("new\n")
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .validationFailed(.developmentRepositoryUpdateFile, "Missing required argument 'expectedSHA256'.")
            )
        }

        XCTAssertThrowsError(
            try updateTool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "relativePath": .string("docs/plan.md"),
                    "contents": .string("new\n"),
                    "expectedSHA256": .string("not-a-sha")
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(.developmentRepositoryUpdateFile, "Expected SHA must be a 64 character hex digest.")
            )
        }

        XCTAssertEqual(try String(contentsOf: workspace.appendingPathComponent("docs/plan.md"), encoding: .utf8), "old\n")
    }

    func testRepositoryWriteRejectsReviewedBranchMismatchBeforeWriting() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try stores.projects.create(title: "Suisui", workspacePath: workspace.path)
        let gitRunner = RecordingRepositoryFileGitRunner()
        gitRunner.stub(
            arguments: ["branch", "--show-current"],
            output: GitCommandOutput(standardOutput: "feature/other\n", standardError: "", exitCode: 0)
        )
        let createTool = DevelopmentRepositoryFileTool(
            name: .developmentRepositoryCreateFile,
            projectStore: stores.projects,
            gitRunner: gitRunner
        )

        XCTAssertThrowsError(
            try createTool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "branchName": .string("feature/reviewed"),
                    "relativePath": .string("docs/plan.md"),
                    "contents": .string("# Plan\n")
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(
                    .developmentRepositoryCreateFile,
                    "Repository branch mismatch: expected feature/reviewed, found feature/other."
                )
            )
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("docs/plan.md").path))
        XCTAssertEqual(gitRunner.recordedInvocations, [
            GitCommandInvocation(arguments: ["branch", "--show-current"], workingDirectory: workspace.standardizedFileURL.resolvingSymlinksInPath())
        ])
    }

    func testCreateRejectsOverwriteAndSecretLikeContents() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        try write("existing\n", to: workspace.appendingPathComponent("docs/plan.md"))
        let project = try stores.projects.create(title: "Suisui", workspacePath: workspace.path)
        let createTool = DevelopmentRepositoryFileTool(name: .developmentRepositoryCreateFile, projectStore: stores.projects)

        XCTAssertThrowsError(
            try createTool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "relativePath": .string("docs/plan.md"),
                    "contents": .string("replacement\n")
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(.developmentRepositoryCreateFile, "Repository file already exists; use update instead.")
            )
        }

        XCTAssertThrowsError(
            try createTool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "relativePath": .string("docs/notes.md"),
                    "contents": .string("api_key=sk-proj-secret\n")
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(.developmentRepositoryCreateFile, "Repository file content looks like it contains credentials or secrets.")
            )
        }

        XCTAssertEqual(try String(contentsOf: workspace.appendingPathComponent("docs/plan.md"), encoding: .utf8), "existing\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("docs/notes.md").path))
    }

    func testRepositoryFileAccessRejectsTraversalAndSymlinkEscapes() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let outside = temporaryDirectory()
        try write("outside\n", to: outside.appendingPathComponent("secret.md"))
        try FileManager.default.createSymbolicLink(
            at: workspace.appendingPathComponent("linked.md"),
            withDestinationURL: outside.appendingPathComponent("secret.md")
        )
        let project = try stores.projects.create(title: "Suisui", workspacePath: workspace.path)
        let readTool = DevelopmentRepositoryFileTool(name: .developmentRepositoryReadFile, projectStore: stores.projects)

        XCTAssertThrowsError(
            try readTool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "relativePath": .string(workspace.appendingPathComponent("Sources/App.swift").path)
                ],
                context: ToolExecutionContext(source: .reviewUI)
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(.developmentRepositoryReadFile, "Repository file path must not contain traversal or empty components.")
            )
        }

        XCTAssertThrowsError(
            try readTool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "relativePath": .string("../escape.md")
                ],
                context: ToolExecutionContext(source: .reviewUI)
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(.developmentRepositoryReadFile, "Repository file path must not contain traversal or empty components.")
            )
        }

        XCTAssertThrowsError(
            try readTool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "relativePath": .string("linked.md")
                ],
                context: ToolExecutionContext(source: .reviewUI)
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(.developmentRepositoryReadFile, "Repository file path must not resolve outside the approved workspace.")
            )
        }
    }

    func testListFilesRejectsTraversalAbsolutePathAndSymlinkEscape() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let outside = temporaryDirectory()
        try write("outside\n", to: outside.appendingPathComponent("notes.md"))
        try FileManager.default.createSymbolicLink(
            at: workspace.appendingPathComponent("linked"),
            withDestinationURL: outside
        )
        let project = try stores.projects.create(title: "Suisui", workspacePath: workspace.path)
        let listTool = DevelopmentRepositoryFileTool(name: .developmentRepositoryListFiles, projectStore: stores.projects)

        for path in [workspace.path, "../escape", "linked"] {
            XCTAssertThrowsError(
                try listTool.execute(
                    arguments: [
                        "projectId": .number(Double(project.id)),
                        "relativePath": .string(path)
                    ],
                    context: ToolExecutionContext(source: .reviewUI)
                ),
                path
            ) { error in
                let expectedMessage = path == "linked"
                    ? "Repository file path must not resolve outside the approved workspace."
                    : "Repository file path must not contain traversal or empty components."
                XCTAssertEqual(
                    error as? ToolExecutionError,
                    .executionFailed(.developmentRepositoryListFiles, expectedMessage)
                )
            }
        }
    }

    func testRepositoryFileAccessRejectsParentSymlinkAndSecretLikeContents() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let outside = temporaryDirectory()
        try write("outside\n", to: outside.appendingPathComponent("notes.md"))
        try FileManager.default.createSymbolicLink(
            at: workspace.appendingPathComponent("docs"),
            withDestinationURL: outside
        )
        try write("token=ghp_secretvalue\n", to: workspace.appendingPathComponent("safe/config.md"))
        let project = try stores.projects.create(title: "Suisui", workspacePath: workspace.path)
        let readTool = DevelopmentRepositoryFileTool(name: .developmentRepositoryReadFile, projectStore: stores.projects)

        XCTAssertThrowsError(
            try readTool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "relativePath": .string("docs/notes.md")
                ],
                context: ToolExecutionContext(source: .reviewUI)
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(.developmentRepositoryReadFile, "Repository file path must not traverse or target a symlink.")
            )
        }

        XCTAssertThrowsError(
            try readTool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "relativePath": .string("safe/config.md")
                ],
                context: ToolExecutionContext(source: .reviewUI)
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(.developmentRepositoryReadFile, "Repository file content looks like it contains credentials or secrets.")
            )
        }
    }

    func testRepositoryFileAccessRejectsGitMetadataSecretLikeAndBinaryPaths() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        try FileManager.default.createDirectory(at: workspace.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try write("ref: refs/heads/main\n", to: workspace.appendingPathComponent(".git/HEAD"))
        try write("token=secret\n", to: workspace.appendingPathComponent(".env"))
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: workspace.appendingPathComponent("image.png"))
        let project = try stores.projects.create(title: "Suisui", workspacePath: workspace.path)
        let readTool = DevelopmentRepositoryFileTool(name: .developmentRepositoryReadFile, projectStore: stores.projects)

        for (path, message) in [
            (".git/HEAD", "Repository file path must not target git metadata."),
            (".env", "Repository file path looks like a credential or secret file."),
            ("image.png", "Repository file path must target a supported text file.")
        ] {
            XCTAssertThrowsError(
                try readTool.execute(
                    arguments: [
                        "projectId": .number(Double(project.id)),
                        "relativePath": .string(path)
                    ],
                    context: ToolExecutionContext(source: .reviewUI)
                ),
                path
            ) { error in
                XCTAssertEqual(
                    error as? ToolExecutionError,
                    .executionFailed(.developmentRepositoryReadFile, message)
                )
            }
        }
    }

    func testListFilesRejectsGitMetadataAndSecretLikeRoots() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        try FileManager.default.createDirectory(at: workspace.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try write("ref: refs/heads/main\n", to: workspace.appendingPathComponent(".git/HEAD"))
        try write("token=secret\n", to: workspace.appendingPathComponent(".env"))
        let project = try stores.projects.create(title: "Suisui", workspacePath: workspace.path)
        let listTool = DevelopmentRepositoryFileTool(name: .developmentRepositoryListFiles, projectStore: stores.projects)

        for (path, message) in [
            (".git", "Repository file path must not target git metadata."),
            (".git/HEAD", "Repository file path must not target git metadata."),
            (".env", "Repository file path looks like a credential or secret file.")
        ] {
            XCTAssertThrowsError(
                try listTool.execute(
                    arguments: [
                        "projectId": .number(Double(project.id)),
                        "relativePath": .string(path)
                    ],
                    context: ToolExecutionContext(source: .reviewUI)
                ),
                path
            ) { error in
                XCTAssertEqual(
                    error as? ToolExecutionError,
                    .executionFailed(.developmentRepositoryListFiles, message)
                )
            }
        }
    }

    func testRepositoryFileAccessRejectsOversizedAndNonUTF8Files() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let oversized = String(repeating: "a", count: DevelopmentRepositoryFilePathPolicy.maximumContentBytes + 1)
        try write(oversized, to: workspace.appendingPathComponent("docs/large.md"))
        try FileManager.default.createDirectory(at: workspace.appendingPathComponent("docs"), withIntermediateDirectories: true)
        try Data([0xFF, 0xFE, 0x00]).write(to: workspace.appendingPathComponent("docs/binary.txt"))
        let project = try stores.projects.create(title: "Suisui", workspacePath: workspace.path)
        let readTool = DevelopmentRepositoryFileTool(name: .developmentRepositoryReadFile, projectStore: stores.projects)

        XCTAssertThrowsError(
            try readTool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "relativePath": .string("docs/large.md")
                ],
                context: ToolExecutionContext(source: .reviewUI)
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(
                    .developmentRepositoryReadFile,
                    "Repository file content exceeds the \(DevelopmentRepositoryFilePathPolicy.maximumContentBytes) byte limit."
                )
            )
        }

        XCTAssertThrowsError(
            try readTool.execute(
                arguments: [
                    "projectId": .number(Double(project.id)),
                    "relativePath": .string("docs/binary.txt")
                ],
                context: ToolExecutionContext(source: .reviewUI)
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(.developmentRepositoryReadFile, "Repository file content must be UTF-8 text.")
            )
        }
    }

    func testDevelopmentModeRegistersRepositoryFileToolsOnlyWhenCapabilityIsEnabled() throws {
        let stores = try makeStores()
        let registry = try ToolRegistryFactory.developerMode(
            settings: DeveloperModeSettings(
                isEnabled: true,
                workspaceRoot: temporaryDirectory(),
                enabledCapabilities: [.developmentRepositoryFiles]
            ),
            projectStore: stores.projects,
            taskStore: stores.tasks,
            artifactStore: stores.artifacts
        )

        XCTAssertTrue(registry.contains(.developmentRepositoryListFiles))
        XCTAssertTrue(registry.contains(.developmentRepositoryReadFile))
        XCTAssertTrue(registry.contains(.developmentRepositoryCreateFile))
        XCTAssertTrue(registry.contains(.developmentRepositoryUpdateFile))
    }

    func testDevelopmentModeRequiresArtifactStoreForRepositoryFileCapability() throws {
        let stores = try makeStores()

        XCTAssertThrowsError(try ToolRegistryFactory.developerMode(
            settings: DeveloperModeSettings(
                isEnabled: true,
                workspaceRoot: temporaryDirectory(),
                enabledCapabilities: [.developmentRepositoryFiles]
            ),
            projectStore: stores.projects,
            taskStore: stores.tasks
        )) { error in
            XCTAssertEqual(error as? DeveloperModeError, .artifactStoreRequired)
        }
    }

    private func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func makeStores() throws -> (projects: SQLiteProjectStore, tasks: SQLiteTaskStore, artifacts: SQLiteArtifactStore) {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        return (
            SQLiteProjectStore(connection: connection),
            SQLiteTaskStore(connection: connection),
            SQLiteArtifactStore(connection: connection)
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
            .appendingPathComponent("SuisuiDevelopmentRepositoryFileAccessTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class RecordingAccessCounter: @unchecked Sendable {
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

private final class RecordingProjectWorkspaceBookmarkResolver: ProjectWorkspaceBookmarkResolving, @unchecked Sendable {
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

private final class RecordingRepositoryFileGitRunner: GitCommandRunner, @unchecked Sendable {
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

private extension JSONValue {
    var arrayValue: [JSONValue]? {
        guard case .array(let value) = self else {
            return nil
        }
        return value
    }

    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else {
            return nil
        }
        return value
    }

    var stringValue: String? {
        guard case .string(let value) = self else {
            return nil
        }
        return value
    }
}
