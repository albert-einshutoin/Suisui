import Foundation
import SuisuiCore

/// Canonicalizes the managed root and every playback candidate before a file
/// is opened. Keeping this rule in one value prevents import, cleanup, player,
/// and waveform code from drifting into subtly different path checks.
struct ManagedInboxAudioPathValidator: Sendable {
    private let canonicalRootURL: URL

    init(rootURL: URL) {
        canonicalRootURL = rootURL.resolvingSymlinksInPath().standardizedFileURL
    }

    func validatedManagedURL(_ url: URL) throws -> URL {
        let candidate = url.resolvingSymlinksInPath().standardizedFileURL
        let rootPath = canonicalRootURL.path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard url.isFileURL,
              candidate.path.hasPrefix(rootPrefix),
              isRegularFile(candidate) else {
            throw InboxAudioPlaybackError.recordingUnavailable
        }
        return candidate
    }

    private func isRegularFile(_ url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return false
        }
        return attributes[.type] as? FileAttributeType == .typeRegular
    }
}

/// Owns completed Inbox recordings so playback never depends on a temporary
/// URL that can disappear when the app or the OS cleans its temp directory.
final class ManagedInboxAudioFileStore {
    private let fileManager: FileManager
    private let rootURL: URL
    let validator: ManagedInboxAudioPathValidator

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
        let requestedRootURL = rootURL.standardizedFileURL
        guard (try? fileManager.destinationOfSymbolicLink(atPath: requestedRootURL.path)) == nil else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try fileManager.createDirectory(
            at: requestedRootURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard (try? fileManager.destinationOfSymbolicLink(atPath: requestedRootURL.path)) == nil else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let rootAttributes = try fileManager.attributesOfItem(atPath: requestedRootURL.path)
        guard rootAttributes[.type] as? FileAttributeType == .typeDirectory else {
            throw CocoaError(.fileWriteInvalidFileName)
        }

        // Pin every later operation to the directory resolved at startup. A
        // symlink as the managed root leaf could otherwise redirect cleanup
        // or imports after validation to a location the app does not own.
        let canonicalRootURL = requestedRootURL.resolvingSymlinksInPath().standardizedFileURL
        self.fileManager = fileManager
        self.rootURL = canonicalRootURL
        self.validator = ManagedInboxAudioPathValidator(rootURL: canonicalRootURL)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: canonicalRootURL.path)
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
        let staging = rootURL.appendingPathComponent(".import-\(UUID().uuidString)", isDirectory: false)
        do {
            try fileManager.copyItem(at: source, to: staging)
            try fileManager.moveItem(at: staging, to: destination)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            return destination
        } catch {
            try? fileManager.removeItem(at: staging)
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    func validatedManagedURL(_ url: URL) throws -> URL {
        try validator.validatedManagedURL(url)
    }

    /// Migrates the recorder's legacy temporary output exactly once. Only the
    /// app-owned recording prefix is accepted so an arbitrary path in /tmp can
    /// never be copied into the managed Inbox directory during startup.
    func migrateLegacyRecordingIfNeeded(from sourceURL: URL) throws -> URL? {
        let candidate = sourceURL.resolvingSymlinksInPath().standardizedFileURL
        if isManagedFile(candidate) {
            return isRegularFile(candidate) ? candidate : nil
        }

        let temporaryRoot = fileManager.temporaryDirectory
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let temporaryPrefix = temporaryRoot.path.hasSuffix("/") ? temporaryRoot.path : temporaryRoot.path + "/"
        guard sourceURL.isFileURL,
              candidate.path.hasPrefix(temporaryPrefix),
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
            options: []
        )
        for child in children where isRegularFile(child) {
            // A process can exit between copy and rename. Sweep only our
            // hidden staging namespace; unrelated hidden metadata in the
            // managed directory does not become ours to delete.
            guard !child.lastPathComponent.hasPrefix(".")
                    || child.lastPathComponent.hasPrefix(".import-") else {
                continue
            }
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
        try? validator.validatedManagedURL(url).path
    }
}

// Voice capture is MainActor-owned, but startup maintenance uses the same
// filesystem policy off-main before the board view model is constructed.
extension ManagedInboxAudioFileStore: InboxAudioPersisting {}
