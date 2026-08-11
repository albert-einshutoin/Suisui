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
}
