import Foundation
import XCTest
@testable import SuisuiCore

final class DevelopmentRepositoryIndexTests: XCTestCase {
    func testRefreshIndexesTrackedAndUntrackedTextWhileSkippingSensitiveBinaryAndSymlinkFiles() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write("tracked needle", to: "Sources/Tracked.swift")
        try fixture.write("untracked needle", to: "Notes.md")
        try fixture.write("SECRET=value", to: ".env")
        try fixture.write("ignored needle", to: "ignored.md")
        try fixture.write(Data([0, 1, 2]), to: "binary.txt")
        try fixture.runGit(["add", "Sources/Tracked.swift", ".gitignore"])
        try fixture.write("ignored.md\n", to: ".gitignore")
        try fixture.runGit(["add", ".gitignore"])
        try FileManager.default.createSymbolicLink(
            at: fixture.url.appendingPathComponent("linked.md"),
            withDestinationURL: fixture.url.appendingPathComponent("Notes.md")
        )

        let index = try migratedIndex()
        try await index.refresh(workspace: workspace(fixture))

        let found = try await index.search(query: "needle", workspace: workspace(fixture))
        XCTAssertEqual(Set(found.map(\.sourcePath)), ["Notes.md", "Sources/Tracked.swift"])
    }

    func testRefreshReplacesSnapshotAndKeepsPreviousGenerationAfterGitFailure() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write("first value", to: "Notes.md")
        let index = try migratedIndex()
        try await index.refresh(workspace: workspace(fixture))

        try fixture.write("second value", to: "Notes.md")
        try fixture.write("new file", to: "Added.md")
        try await index.refresh(workspace: workspace(fixture))

        let oldResults = try await index.search(query: "first", workspace: workspace(fixture))
        let updatedResults = try await index.search(query: "second", workspace: workspace(fixture))
        let addedResults = try await index.search(query: "new", workspace: workspace(fixture))
        XCTAssertTrue(oldResults.isEmpty)
        XCTAssertEqual(updatedResults.map(\.sourcePath), ["Notes.md"])
        XCTAssertEqual(addedResults.map(\.sourcePath), ["Added.md"])

        let missingRepository = FileManager.default.temporaryDirectory.appendingPathComponent("suisui-index-not-a-repository-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: missingRepository, withIntermediateDirectories: true)
        try "gitdir: /definitely-missing-suisui-index-git-directory\n".write(
            to: missingRepository.appendingPathComponent(".git"),
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: missingRepository) }
        await XCTAssertThrowsErrorAsync(try await index.refresh(workspace: CodebaseMemoryWorkspace(rootPath: missingRepository.path, selectedRelativePaths: [])))
        let preservedResults = try await index.search(query: "second", workspace: workspace(fixture))
        XCTAssertEqual(preservedResults.map(\.sourcePath), ["Notes.md"])
    }

    func testSearchIsolatesWorkspaceAndSelectedPathsAndFallsBackForCJK() async throws {
        let first = try RepositoryFixture()
        let second = try RepositoryFixture()
        defer {
            first.remove()
            second.remove()
        }
        try first.write("東京の設計", to: "Docs/Japanese.md")
        try first.write("shared secret-free phrase", to: "Sources/Only.swift")
        try second.write("shared secret-free phrase", to: "Other.md")
        let index = try migratedIndex()
        try await index.refresh(workspace: workspace(first))
        try await index.refresh(workspace: workspace(second))
        try await index.refresh(workspace: workspace(first))

        let cjkResults = try await index.search(query: "東京", workspace: workspace(first))
        let selectedResults = try await index.search(
            query: "shared",
            workspace: CodebaseMemoryWorkspace(rootPath: first.url.path, selectedRelativePaths: ["Sources/Only.swift"])
        )
        let directoryResults = try await index.search(
            query: "shared",
            workspace: CodebaseMemoryWorkspace(rootPath: first.url.path, selectedRelativePaths: ["Sources"])
        )
        let isolatedResults = try await index.search(query: "shared", workspace: workspace(second))
        XCTAssertEqual(cjkResults.map(\.sourcePath), ["Docs/Japanese.md"])
        XCTAssertEqual(selectedResults.map(\.sourcePath), ["Sources/Only.swift"])
        XCTAssertEqual(directoryResults.map(\.sourcePath), ["Sources/Only.swift"])
        XCTAssertEqual(isolatedResults.map(\.sourcePath), ["Other.md"])
    }

    private func migratedIndex() throws -> DevelopmentRepositoryIndex {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        return DevelopmentRepositoryIndex(connection: connection)
    }

    private func workspace(_ fixture: RepositoryFixture) -> CodebaseMemoryWorkspace {
        CodebaseMemoryWorkspace(rootPath: fixture.url.path, selectedRelativePaths: [])
    }
}

private final class RepositoryFixture {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("suisui-repository-index-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try runGit(["init"])
        try runGit(["config", "user.email", "index@example.invalid"])
        try runGit(["config", "user.name", "Repository Index Test"])
        try write("", to: ".gitignore")
    }

    func write(_ contents: String, to relativePath: String) throws {
        try write(Data(contents.utf8), to: relativePath)
    }

    func write(_ data: Data, to relativePath: String) throws {
        let fileURL = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL)
    }

    func runGit(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = url
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error.", file: file, line: line)
    } catch {}
}
