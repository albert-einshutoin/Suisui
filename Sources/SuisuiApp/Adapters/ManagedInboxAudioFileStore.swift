import Foundation
import SuisuiCore

/// Owns completed Inbox recordings so playback never depends on a temporary
/// URL that can disappear when the app or the OS cleans its temp directory.
@MainActor
final class ManagedInboxAudioFileStore: InboxAudioPersisting {
    private let fileManager: FileManager
    private let rootURL: URL

    convenience init(fileManager: FileManager = .default) throws {
        let appSupportURL = try SuisuiAppDatabaseLocation.applicationSupportDirectoryURL(
            createDirectory: true,
            fileManager: fileManager
        )
        try self.init(
            rootURL: appSupportURL.appendingPathComponent("InboxAudio", isDirectory: true),
            fileManager: fileManager
        )
    }

    init(rootURL: URL, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        self.rootURL = rootURL.standardizedFileURL
        try fileManager.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
    }

    func importRecording(from sourceURL: URL) throws -> URL {
        let source = sourceURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              let attributes = try? fileManager.attributesOfItem(atPath: source.path),
              attributes[.type] as? FileAttributeType == .typeRegular else {
            throw CocoaError(.fileNoSuchFile)
        }

        let extensionName = source.pathExtension.isEmpty ? "m4a" : source.pathExtension.lowercased()
        let destination = rootURL
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension(extensionName)
        try fileManager.copyItem(at: source, to: destination)
        return destination
    }

    /// Migrates the recorder's legacy temporary output exactly once. Only the
    /// app-owned recording prefix is accepted so an arbitrary path in /tmp can
    /// never be copied into the managed Inbox directory during startup.
    func migrateLegacyRecordingIfNeeded(from sourceURL: URL) throws -> URL? {
        let candidate = sourceURL.standardizedFileURL
        if isManagedFile(candidate) {
            return isRegularFile(candidate) ? candidate : nil
        }

        let temporaryRoot = fileManager.temporaryDirectory.standardizedFileURL
        let temporaryPrefix = temporaryRoot.path.hasSuffix("/") ? temporaryRoot.path : temporaryRoot.path + "/"
        guard candidate.path.hasPrefix(temporaryPrefix),
              candidate.lastPathComponent.hasPrefix("suisui-recording-"),
              isRegularFile(candidate) else {
            return nil
        }

        // The caller updates SQLite before deleting the legacy source. Keeping
        // it until that transaction succeeds avoids a data-loss window if the
        // database is locked or the row has been removed concurrently.
        return try importRecording(from: candidate)
    }

    /// Removes managed files no longer referenced by a capture row. This is a
    /// startup reconciliation rather than an immediate delete: retaining a
    /// file until the next launch keeps session Undo able to restore its row.
    func removeOrphanedRecordings(referencedPaths: Set<String>) throws {
        let canonicalReferences = Set(referencedPaths.compactMap { canonicalManagedPath(for: URL(fileURLWithPath: $0)) })
        let children = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        for child in children where isRegularFile(child) {
            guard let canonicalPath = canonicalManagedPath(for: child),
                  !canonicalReferences.contains(canonicalPath) else {
                continue
            }
            try fileManager.removeItem(at: child)
        }
    }

    func removeImportedRecording(at url: URL) {
        guard let candidatePath = canonicalManagedPath(for: url) else { return }
        try? fileManager.removeItem(atPath: candidatePath)
    }

    private func isManagedFile(_ url: URL) -> Bool {
        canonicalManagedPath(for: url) != nil
    }

    private func isRegularFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              let attributes = try? fileManager.attributesOfItem(atPath: url.path) else {
            return false
        }
        return attributes[.type] as? FileAttributeType == .typeRegular
    }

    private func canonicalManagedPath(for url: URL) -> String? {
        let candidate = url.resolvingSymlinksInPath().standardizedFileURL
        let rootPath = rootURL.resolvingSymlinksInPath().standardizedFileURL.path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard candidate.path.hasPrefix(rootPrefix) else { return nil }
        return candidate.path
    }
}
