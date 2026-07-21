import Foundation

public protocol CodexRuntimeFileInspecting {
    func codexFileState(atPath path: String) -> (exists: Bool, isDirectory: Bool, isExecutable: Bool)
}

extension FileManager: CodexRuntimeFileInspecting {
    public func codexFileState(atPath path: String) -> (exists: Bool, isDirectory: Bool, isExecutable: Bool) {
        var isDirectory = ObjCBool(false)
        let exists = fileExists(atPath: path, isDirectory: &isDirectory)
        return (exists, isDirectory.boolValue, isExecutableFile(atPath: path))
    }
}

public struct CodexAppServerVersion: Comparable, Equatable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    public static func parse(_ output: String) -> Self? {
        let pattern = #"(?<![0-9.])([0-9]+)\.([0-9]+)\.([0-9]+)(?![0-9.])"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        let matches = expression.matches(in: output, range: range)
        guard matches.count == 1, let match = matches.first,
              let majorRange = Range(match.range(at: 1), in: output),
              let minorRange = Range(match.range(at: 2), in: output),
              let patchRange = Range(match.range(at: 3), in: output),
              let major = Int(output[majorRange]),
              let minor = Int(output[minorRange]),
              let patch = Int(output[patchRange]) else {
            return nil
        }
        return Self(major: major, minor: minor, patch: patch)
    }
}

public enum CodexAppServerRuntimeConfigurationError: Error, Equatable, Sendable {
    case absoluteExecutablePathRequired
    case credentialStorePathForbidden
    case executableMissing
    case executableIsDirectory
    case executablePermissionRequired
    case invalidVersionOutput
    case unsupportedVersion(installed: CodexAppServerVersion, minimum: CodexAppServerVersion)
}

public struct CodexAppServerRuntimeConfiguration: Equatable, Sendable {
    public static let minimumVersion = CodexAppServerVersion(major: 0, minor: 144, patch: 1)

    public let executablePath: String
    public let version: CodexAppServerVersion

    public static func validate(
        executablePath: String,
        reportedVersion: String,
        fileManager: any CodexRuntimeFileInspecting = FileManager.default
    ) throws -> Self {
        let trimmedPath = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPath.hasPrefix("/"), URL(fileURLWithPath: trimmedPath).path == trimmedPath else {
            throw CodexAppServerRuntimeConfigurationError.absoluteExecutablePathRequired
        }

        let pathComponents = URL(fileURLWithPath: trimmedPath).standardizedFileURL.pathComponents
        if pathComponents.last?.lowercased() == "auth.json" ||
            pathComponents.suffix(2).map({ $0.lowercased() }) == [".codex", "auth.json"] {
            throw CodexAppServerRuntimeConfigurationError.credentialStorePathForbidden
        }

        let fileState = fileManager.codexFileState(atPath: trimmedPath)
        guard fileState.exists else {
            throw CodexAppServerRuntimeConfigurationError.executableMissing
        }
        guard !fileState.isDirectory else {
            throw CodexAppServerRuntimeConfigurationError.executableIsDirectory
        }
        guard fileState.isExecutable else {
            throw CodexAppServerRuntimeConfigurationError.executablePermissionRequired
        }
        guard let version = CodexAppServerVersion.parse(reportedVersion) else {
            throw CodexAppServerRuntimeConfigurationError.invalidVersionOutput
        }
        guard version >= minimumVersion else {
            throw CodexAppServerRuntimeConfigurationError.unsupportedVersion(
                installed: version,
                minimum: minimumVersion
            )
        }
        return Self(executablePath: trimmedPath, version: version)
    }
}
