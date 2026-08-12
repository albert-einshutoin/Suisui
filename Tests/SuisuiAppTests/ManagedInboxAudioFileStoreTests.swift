import XCTest
@testable import Suisui

final class ManagedInboxAudioFileStoreTests: XCTestCase {
    @MainActor
    func testImportCopiesAudioIntoManagedInboxDirectoryAndCanCompensate() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-managed-inbox-audio-\(UUID().uuidString)", isDirectory: true)
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-source-\(UUID().uuidString).m4a")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: source)
        }

        try Data("fixture-audio".utf8).write(to: source)
        let store = try ManagedInboxAudioFileStore(rootURL: root)
        let managed = try store.importRecording(from: source)

        XCTAssertTrue(managed.path.hasPrefix(root.standardizedFileURL.path + "/"))
        XCTAssertEqual(try Data(contentsOf: managed), Data("fixture-audio".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))

        store.removeImportedRecording(at: managed)

        XCTAssertFalse(FileManager.default.fileExists(atPath: managed.path))
    }

    @MainActor
    func testRemoveImportedRecordingDoesNotDeleteOutsideManagedDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-managed-inbox-audio-\(UUID().uuidString)", isDirectory: true)
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-outside-\(UUID().uuidString).m4a")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }

        try Data("outside".utf8).write(to: outside)
        let store = try ManagedInboxAudioFileStore(rootURL: root)

        store.removeImportedRecording(at: outside)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    @MainActor
    func testStartupReconciliationMigratesOwnedLegacyRecordingAndRemovesOrphans() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-managed-inbox-audio-\(UUID().uuidString)", isDirectory: true)
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let legacy = temporaryDirectory
            .appendingPathComponent("suisui-recording-\(UUID().uuidString).m4a")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: legacy)
        }

        try Data("legacy-audio".utf8).write(to: legacy)
        let store = try ManagedInboxAudioFileStore(rootURL: root)
        let referenced = try store.migrateLegacyRecordingIfNeeded(from: legacy)
        let orphan = try store.importRecording(from: legacy)
        try store.removeOrphanedRecordings(referencedPaths: Set([referenced?.path ?? ""]))

        XCTAssertNotNil(referenced)
        XCTAssertTrue(FileManager.default.fileExists(atPath: referenced!.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
    }

    @MainActor
    func testLegacyMigrationRejectsUnownedTemporaryPath() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-managed-inbox-audio-\(UUID().uuidString)", isDirectory: true)
        let unrelated = FileManager.default.temporaryDirectory
            .appendingPathComponent("unrelated-\(UUID().uuidString).m4a")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: unrelated)
        }

        try Data("unrelated".utf8).write(to: unrelated)
        let store = try ManagedInboxAudioFileStore(rootURL: root)

        XCTAssertNil(try store.migrateLegacyRecordingIfNeeded(from: unrelated))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }
}
