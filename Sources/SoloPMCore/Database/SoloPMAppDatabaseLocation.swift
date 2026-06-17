import Foundation

public enum SoloPMAppDatabaseLocation {
    public static func defaultDatabaseURL(
        createDirectory: Bool,
        fileManager: FileManager = .default
    ) throws -> URL {
        try applicationSupportDirectoryURL(
            createDirectory: createDirectory,
            fileManager: fileManager
        )
        .appendingPathComponent("SoloPM.sqlite")
    }

    public static func applicationSupportDirectoryURL(
        createDirectory: Bool,
        fileManager: FileManager = .default
    ) throws -> URL {
        guard let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw DatabaseError.openFailed("Application Support directory was not found.")
        }

        let directory = applicationSupportURL.appendingPathComponent("SoloPM", isDirectory: true)
        if createDirectory {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }
}
