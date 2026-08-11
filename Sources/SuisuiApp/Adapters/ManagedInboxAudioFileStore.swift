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

    func removeImportedRecording(at url: URL) {
        let candidate = url.resolvingSymlinksInPath().standardizedFileURL
        let rootPath = rootURL.resolvingSymlinksInPath().standardizedFileURL.path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard candidate.path.hasPrefix(rootPrefix) else { return }
        try? fileManager.removeItem(at: candidate)
    }
}
