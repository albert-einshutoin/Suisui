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
    func testStartupReconciliationRemovesHiddenInterruptedImportStagingFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-managed-inbox-staging-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try ManagedInboxAudioFileStore(rootURL: root)
        let interruptedImport = root.appendingPathComponent(".import-interrupted")
        try Data("private-staging-audio".utf8).write(to: interruptedImport)

        try store.removeOrphanedRecordings(referencedPaths: [])

        XCTAssertFalse(FileManager.default.fileExists(atPath: interruptedImport.path))
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

    @MainActor
    func testInitializationRejectsManagedRootLeafSymlink() throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-managed-inbox-root-symlink-\(UUID().uuidString)", isDirectory: true)
        let target = fixtureRoot.appendingPathComponent("target", isDirectory: true)
        let rootSymlink = fixtureRoot.appendingPathComponent("InboxAudio", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: fixtureRoot)
        }

        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: rootSymlink, withDestinationURL: target)

        XCTAssertThrowsError(try ManagedInboxAudioFileStore(rootURL: rootSymlink))
    }

    @MainActor
    func testManagedRootPinsCanonicalParentWhenIntermediateSymlinkIsRetargeted() throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-managed-inbox-canonical-root-\(UUID().uuidString)", isDirectory: true)
        let firstParent = fixtureRoot.appendingPathComponent("first", isDirectory: true)
        let secondParent = fixtureRoot.appendingPathComponent("second", isDirectory: true)
        let parentSymlink = fixtureRoot.appendingPathComponent("current", isDirectory: true)
        let requestedRoot = parentSymlink.appendingPathComponent("InboxAudio", isDirectory: true)
        let source = fixtureRoot.appendingPathComponent("source.m4a")
        defer {
            try? FileManager.default.removeItem(at: fixtureRoot)
        }

        try FileManager.default.createDirectory(at: firstParent, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondParent, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: parentSymlink, withDestinationURL: firstParent)
        try Data("fixture-audio".utf8).write(to: source)
        let store = try ManagedInboxAudioFileStore(rootURL: requestedRoot)

        try FileManager.default.removeItem(at: parentSymlink)
        try FileManager.default.createSymbolicLink(at: parentSymlink, withDestinationURL: secondParent)
        let managed = try store.importRecording(from: source)

        XCTAssertTrue(
            managed.path.hasPrefix(
                firstParent.appendingPathComponent("InboxAudio", isDirectory: true).path + "/"
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: secondParent.appendingPathComponent("InboxAudio", isDirectory: true).path
            )
        )
    }

    @MainActor
    func testLegacyMigrationRejectsTemporaryPathWhoseIntermediateSymlinkEscapesTemporaryRoot() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let fixtureRoot = temporaryRoot
            .appendingPathComponent("suisui-legacy-intermediate-symlink-\(UUID().uuidString)", isDirectory: true)
        let outsideRoot = temporaryRoot
            .deletingLastPathComponent()
            .appendingPathComponent("suisui-legacy-outside-\(UUID().uuidString)", isDirectory: true)
        let intermediateSymlink = fixtureRoot.appendingPathComponent("escape", isDirectory: true)
        let outsideRecording = outsideRoot
            .appendingPathComponent("suisui-recording-\(UUID().uuidString).m4a")
        let escapedRecording = intermediateSymlink
            .appendingPathComponent(outsideRecording.lastPathComponent)
        let managedRoot = fixtureRoot.appendingPathComponent("managed", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: fixtureRoot)
            try? FileManager.default.removeItem(at: outsideRoot)
        }

        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
        try Data("outside-temp-audio".utf8).write(to: outsideRecording)
        try FileManager.default.createSymbolicLink(
            at: intermediateSymlink,
            withDestinationURL: outsideRoot
        )
        let store = try ManagedInboxAudioFileStore(rootURL: managedRoot)

        XCTAssertNil(try store.migrateLegacyRecordingIfNeeded(from: escapedRecording))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outsideRecording.path))
    }
}
