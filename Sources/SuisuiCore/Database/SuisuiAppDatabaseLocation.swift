import Foundation

public enum SuisuiAppDatabaseLocation {
    public static let databasePathOverrideEnvironmentKey = "SUISUI_DATABASE_PATH"

    public static func defaultDatabaseURL(
        createDirectory: Bool,
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
        if let override = environment[databasePathOverrideEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !override.isEmpty {
            guard override.hasPrefix("/") else {
                throw DatabaseError.openFailed("\(databasePathOverrideEnvironmentKey) must be an absolute file path.")
            }
            let url = URL(fileURLWithPath: override)
            if createDirectory {
                try fileManager.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
            }
            return url
        }

        return try applicationSupportDirectoryURL(
            createDirectory: createDirectory,
            fileManager: fileManager
        )
        .appendingPathComponent("Suisui.sqlite")
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

        let directory = applicationSupportURL.appendingPathComponent("Suisui", isDirectory: true)
        if createDirectory {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }
}
