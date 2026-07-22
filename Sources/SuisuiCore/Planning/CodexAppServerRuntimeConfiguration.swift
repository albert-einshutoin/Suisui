import Foundation

public struct CodexExecutableIdentity: Codable, Equatable, Sendable {
    public let resolvedPath: String
    public let deviceID: UInt64
    public let inode: UInt64
    public let modificationTime: TimeInterval
    public let fileSize: UInt64

    public init(
        resolvedPath: String,
        deviceID: UInt64,
        inode: UInt64,
        modificationTime: TimeInterval,
        fileSize: UInt64
    ) {
        self.resolvedPath = resolvedPath
        self.deviceID = deviceID
        self.inode = inode
        self.modificationTime = modificationTime
        self.fileSize = fileSize
    }
}

public struct ApprovedCodexExecutable: Codable, Equatable, Sendable {
    public let path: String
    public let identity: CodexExecutableIdentity
    public let approvedAt: Date

    public var resolvedPath: String { identity.resolvedPath }

    public init(path: String, identity: CodexExecutableIdentity, approvedAt: Date) {
        self.path = path
        self.identity = identity
        self.approvedAt = approvedAt
    }
}

public struct CodexRuntimeFileState: Equatable, Sendable {
    public let exists: Bool
    public let isDirectory: Bool
    public let isExecutable: Bool
    public let isRegularFile: Bool
    public let identity: CodexExecutableIdentity?

    public init(
        exists: Bool,
        isDirectory: Bool,
        isExecutable: Bool,
        isRegularFile: Bool,
        identity: CodexExecutableIdentity?
    ) {
        self.exists = exists
        self.isDirectory = isDirectory
        self.isExecutable = isExecutable
        self.isRegularFile = isRegularFile
        self.identity = identity
    }
}

public protocol CodexRuntimeFileInspecting {
    func codexFileState(atPath path: String) -> CodexRuntimeFileState
}

extension FileManager: CodexRuntimeFileInspecting {
    public func codexFileState(atPath path: String) -> CodexRuntimeFileState {
        let resolvedPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
        var isDirectory = ObjCBool(false)
        let exists = fileExists(atPath: resolvedPath, isDirectory: &isDirectory)
        guard exists, let attributes = try? attributesOfItem(atPath: resolvedPath) else {
            return CodexRuntimeFileState(
                exists: exists,
                isDirectory: isDirectory.boolValue,
                isExecutable: false,
                isRegularFile: false,
                identity: nil
            )
        }
        let isRegularFile = attributes[.type] as? FileAttributeType == .typeRegular
        let identity = CodexExecutableIdentity(
            resolvedPath: resolvedPath,
            deviceID: (attributes[.systemNumber] as? NSNumber)?.uint64Value ?? 0,
            inode: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
            modificationTime: (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0,
            fileSize: (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        )
        return CodexRuntimeFileState(
            exists: true,
            isDirectory: isDirectory.boolValue,
            isExecutable: isExecutableFile(atPath: resolvedPath),
            isRegularFile: isRegularFile,
            identity: identity
        )
    }
}

public struct CodexAppServerVersion: Comparable, Equatable, Hashable, Sendable {
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
    case executableMustBeRegularFile
    case executablePermissionRequired
    case executionApprovalRequired
    case approvedExecutableChanged
    case invalidVersionOutput
    case unverifiedVersion(installed: CodexAppServerVersion, verified: Set<CodexAppServerVersion>)
}

public struct CodexAppServerRuntimeConfiguration: Equatable, Sendable {
    /// The current release accepts only protocol surfaces covered by checked-in contracts.
    /// Adding a version requires updating schemas, adversarial tests, and release evidence together.
    public static let verifiedVersions: Set<CodexAppServerVersion> = [
        CodexAppServerVersion(major: 0, minor: 144, patch: 1),
    ]

    public let executablePath: String
    public let version: CodexAppServerVersion

    public static func approve(
        executablePath: String,
        approvedAt: Date = Date(),
        fileManager: any CodexRuntimeFileInspecting = FileManager.default
    ) throws -> ApprovedCodexExecutable {
        let candidate = try preflight(executablePath: executablePath, fileManager: fileManager)
        return ApprovedCodexExecutable(path: candidate.path, identity: candidate.identity, approvedAt: approvedAt)
    }

    public static func preflight(
        approvedExecutable: ApprovedCodexExecutable?,
        fileManager: any CodexRuntimeFileInspecting = FileManager.default
    ) throws -> ApprovedCodexExecutable {
        guard let approvedExecutable else {
            throw CodexAppServerRuntimeConfigurationError.executionApprovalRequired
        }
        let candidate = try preflight(executablePath: approvedExecutable.path, fileManager: fileManager)
        guard candidate.identity == approvedExecutable.identity else {
            throw CodexAppServerRuntimeConfigurationError.approvedExecutableChanged
        }
        return candidate
    }

    public static func validate(
        approvedExecutable: ApprovedCodexExecutable?,
        reportedVersion: String,
        fileManager: any CodexRuntimeFileInspecting = FileManager.default
    ) throws -> Self {
        let executable = try preflight(approvedExecutable: approvedExecutable, fileManager: fileManager)
        guard let version = CodexAppServerVersion.parse(reportedVersion) else {
            throw CodexAppServerRuntimeConfigurationError.invalidVersionOutput
        }
        guard verifiedVersions.contains(version) else {
            throw CodexAppServerRuntimeConfigurationError.unverifiedVersion(
                installed: version,
                verified: verifiedVersions
            )
        }
        return Self(executablePath: executable.resolvedPath, version: version)
    }

    private static func preflight(
        executablePath: String,
        fileManager: any CodexRuntimeFileInspecting
    ) throws -> ApprovedCodexExecutable {
        let trimmedPath = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPath.hasPrefix("/"), URL(fileURLWithPath: trimmedPath).path == trimmedPath else {
            throw CodexAppServerRuntimeConfigurationError.absoluteExecutablePathRequired
        }
        try rejectCredentialStorePath(trimmedPath)

        let fileState = fileManager.codexFileState(atPath: trimmedPath)
        guard fileState.exists else {
            throw CodexAppServerRuntimeConfigurationError.executableMissing
        }
        guard !fileState.isDirectory else {
            throw CodexAppServerRuntimeConfigurationError.executableIsDirectory
        }
        guard fileState.isRegularFile, let identity = fileState.identity else {
            throw CodexAppServerRuntimeConfigurationError.executableMustBeRegularFile
        }
        try rejectCredentialStorePath(identity.resolvedPath)
        guard fileState.isExecutable else {
            throw CodexAppServerRuntimeConfigurationError.executablePermissionRequired
        }
        return ApprovedCodexExecutable(path: trimmedPath, identity: identity, approvedAt: .distantPast)
    }

    private static func rejectCredentialStorePath(_ path: String) throws {
        let components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        if components.last?.lowercased() == "auth.json" ||
            components.suffix(2).map({ $0.lowercased() }) == [".codex", "auth.json"] {
            throw CodexAppServerRuntimeConfigurationError.credentialStorePathForbidden
        }
    }
}
