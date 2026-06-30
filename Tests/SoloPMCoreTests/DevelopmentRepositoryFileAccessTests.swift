import XCTest
@testable import SoloPMCore

final class DevelopmentRepositoryFileAccessTests: XCTestCase {
    func testReadTextFileWithinApprovedWorkspaceReturnsContentAndDigest() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        try write("let value = 1\n", to: workspace.appendingPathComponent("Sources/App.swift"))
        try write("struct SecretStore {}\n", to: workspace.appendingPathComponent("Sources/SecretStore.swift"))
        let project = try stores.projects.create(title: "SoloPM", workspacePath: workspace.path)
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

    func testCreateAndUpdateTextFileRequireApprovalAndStayInsideWorkspace() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let project = try stores.projects.create(title: "SoloPM", workspacePath: workspace.path)
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

    func testUpdateRejectsStaleDigestBeforeWriting() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        try write("old\n", to: workspace.appendingPathComponent("docs/plan.md"))
        let project = try stores.projects.create(title: "SoloPM", workspacePath: workspace.path)
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

    func testCreateRejectsOverwriteAndSecretLikeContents() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        try write("existing\n", to: workspace.appendingPathComponent("docs/plan.md"))
        let project = try stores.projects.create(title: "SoloPM", workspacePath: workspace.path)
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
        let project = try stores.projects.create(title: "SoloPM", workspacePath: workspace.path)
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
        let project = try stores.projects.create(title: "SoloPM", workspacePath: workspace.path)
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
        let project = try stores.projects.create(title: "SoloPM", workspacePath: workspace.path)
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

    func testRepositoryFileAccessRejectsOversizedAndNonUTF8Files() throws {
        let stores = try makeStores()
        let workspace = temporaryDirectory()
        let oversized = String(repeating: "a", count: DevelopmentRepositoryFilePathPolicy.maximumContentBytes + 1)
        try write(oversized, to: workspace.appendingPathComponent("docs/large.md"))
        try FileManager.default.createDirectory(at: workspace.appendingPathComponent("docs"), withIntermediateDirectories: true)
        try Data([0xFF, 0xFE, 0x00]).write(to: workspace.appendingPathComponent("docs/binary.txt"))
        let project = try stores.projects.create(title: "SoloPM", workspacePath: workspace.path)
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
            taskStore: stores.tasks
        )

        XCTAssertTrue(registry.contains(.developmentRepositoryReadFile))
        XCTAssertTrue(registry.contains(.developmentRepositoryCreateFile))
        XCTAssertTrue(registry.contains(.developmentRepositoryUpdateFile))
    }

    private func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func makeStores() throws -> (projects: SQLiteProjectStore, tasks: SQLiteTaskStore) {
        let connection = try SQLiteConnection(path: ":memory:")
        try DevelopmentRepositoryFileTestMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
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
            .appendingPathComponent("SoloPMDevelopmentRepositoryFileAccessTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private enum DevelopmentRepositoryFileTestMigrationRunner {
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
