import CryptoKit
import Darwin
import Foundation
#if os(macOS)
import Security
#endif

public struct CodexCodeSignatureIdentity: Codable, Equatable, Sendable {
    public let signingIdentifier: String
    public let teamIdentifier: String?
    public let designatedRequirement: String

    public init(
        signingIdentifier: String,
        teamIdentifier: String?,
        designatedRequirement: String
    ) {
        self.signingIdentifier = signingIdentifier
        self.teamIdentifier = teamIdentifier
        self.designatedRequirement = designatedRequirement
    }
}

public enum CodexExecutableTrustPolicy: String, Codable, Equatable, Sendable {
    /// Normal product operation requires a valid macOS code signature.
    case signedProduction
    /// Unsigned scripts and package-manager shims are restricted to Developer Mode.
    case developerUnsignedAllowed
}

public struct CodexExecutableIdentity: Codable, Equatable, Sendable {
    public let resolvedPath: String
    public let deviceID: UInt64
    public let inode: UInt64
    public let modificationTime: TimeInterval
    public let fileSize: UInt64
    public let contentSHA256: String
    public let codeSignature: CodexCodeSignatureIdentity?

    private enum CodingKeys: String, CodingKey {
        case resolvedPath
        case deviceID
        case inode
        case modificationTime
        case fileSize
        case contentSHA256
        case codeSignature
    }

    public init(
        resolvedPath: String,
        deviceID: UInt64,
        inode: UInt64,
        modificationTime: TimeInterval,
        fileSize: UInt64,
        contentSHA256: String = "",
        codeSignature: CodexCodeSignatureIdentity? = nil
    ) {
        self.resolvedPath = resolvedPath
        self.deviceID = deviceID
        self.inode = inode
        self.modificationTime = modificationTime
        self.fileSize = fileSize
        self.contentSHA256 = contentSHA256
        self.codeSignature = codeSignature
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        resolvedPath = try container.decode(String.self, forKey: .resolvedPath)
        deviceID = try container.decode(UInt64.self, forKey: .deviceID)
        inode = try container.decode(UInt64.self, forKey: .inode)
        modificationTime = try container.decode(TimeInterval.self, forKey: .modificationTime)
        fileSize = try container.decode(UInt64.self, forKey: .fileSize)
        // A metadata-only approval from an older build must decode so Settings
        // can revoke it cleanly, but it is never considered launchable.
        contentSHA256 = try container.decodeIfPresent(String.self, forKey: .contentSHA256) ?? ""
        codeSignature = try container.decodeIfPresent(
            CodexCodeSignatureIdentity.self,
            forKey: .codeSignature
        )
    }

    public var hasContentIntegrityEvidence: Bool {
        contentSHA256.count == 64 && contentSHA256.allSatisfy(\.isHexDigit)
    }
}

public struct ApprovedCodexExecutable: Codable, Equatable, Sendable {
    public let path: String
    public let identity: CodexExecutableIdentity
    public let approvedAt: Date
    public let trustPolicy: CodexExecutableTrustPolicy

    public var resolvedPath: String { identity.resolvedPath }

    private enum CodingKeys: String, CodingKey {
        case path
        case identity
        case approvedAt
        case trustPolicy
    }

    public init(
        path: String,
        identity: CodexExecutableIdentity,
        approvedAt: Date,
        trustPolicy: CodexExecutableTrustPolicy = .signedProduction
    ) {
        self.path = path
        self.identity = identity
        self.approvedAt = approvedAt
        self.trustPolicy = trustPolicy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        identity = try container.decode(CodexExecutableIdentity.self, forKey: .identity)
        approvedAt = try container.decode(Date.self, forKey: .approvedAt)
        trustPolicy = try container.decodeIfPresent(
            CodexExecutableTrustPolicy.self,
            forKey: .trustPolicy
        ) ?? .signedProduction
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
        guard exists else {
            return CodexRuntimeFileState(
                exists: exists,
                isDirectory: isDirectory.boolValue,
                isExecutable: false,
                isRegularFile: false,
                identity: nil
            )
        }
        let descriptor = Darwin.open(resolvedPath, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            return CodexRuntimeFileState(
                exists: true,
                isDirectory: isDirectory.boolValue,
                isExecutable: isExecutableFile(atPath: resolvedPath),
                isRegularFile: false,
                identity: nil
            )
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var descriptorState = stat()
        guard Darwin.fstat(descriptor, &descriptorState) == 0 else {
            try? handle.close()
            return CodexRuntimeFileState(
                exists: true,
                isDirectory: isDirectory.boolValue,
                isExecutable: isExecutableFile(atPath: resolvedPath),
                isRegularFile: false,
                identity: nil
            )
        }
        let isRegularFile = (descriptorState.st_mode & S_IFMT) == S_IFREG
        let contentSHA256 = isRegularFile ? (try? Self.sha256Hex(from: handle)) : nil
        try? handle.close()
        guard let contentSHA256 else {
            return CodexRuntimeFileState(
                exists: true,
                isDirectory: isDirectory.boolValue,
                isExecutable: isExecutableFile(atPath: resolvedPath),
                isRegularFile: isRegularFile,
                identity: nil
            )
        }
        let codeSignature = Self.validCodeSignature(atPath: resolvedPath)
        var finalPathState = stat()
        guard Darwin.lstat(resolvedPath, &finalPathState) == 0,
              Self.sameFileState(descriptorState, finalPathState) else {
            return CodexRuntimeFileState(
                exists: true,
                isDirectory: false,
                isExecutable: false,
                isRegularFile: isRegularFile,
                identity: nil
            )
        }
        let identity = CodexExecutableIdentity(
            resolvedPath: resolvedPath,
            deviceID: UInt64(descriptorState.st_dev),
            inode: UInt64(descriptorState.st_ino),
            modificationTime: TimeInterval(descriptorState.st_mtimespec.tv_sec) +
                TimeInterval(descriptorState.st_mtimespec.tv_nsec) / 1_000_000_000,
            fileSize: UInt64(descriptorState.st_size),
            contentSHA256: contentSHA256,
            codeSignature: codeSignature
        )
        return CodexRuntimeFileState(
            exists: true,
            isDirectory: isDirectory.boolValue,
            isExecutable: isExecutableFile(atPath: resolvedPath),
            isRegularFile: isRegularFile,
            identity: identity
        )
    }

    private static func sha256Hex(from handle: FileHandle) throws -> String {
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func sameFileState(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev &&
            lhs.st_ino == rhs.st_ino &&
            lhs.st_size == rhs.st_size &&
            lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec &&
            lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
    }

    private static func validCodeSignature(atPath path: String) -> CodexCodeSignatureIdentity? {
        #if os(macOS)
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(
            URL(fileURLWithPath: path) as CFURL,
            SecCSFlags(),
            &staticCode
        ) == errSecSuccess, let staticCode else {
            return nil
        }
        let strictFlags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures)
        guard SecStaticCodeCheckValidity(staticCode, strictFlags, nil) == errSecSuccess else {
            return nil
        }
        var signingInformation: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        ) == errSecSuccess,
        let information = signingInformation as? [CFString: Any],
        let identifier = information[kSecCodeInfoIdentifier] as? String else {
            return nil
        }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, SecCSFlags(), &requirement) == errSecSuccess,
              let requirement else {
            return nil
        }
        var requirementText: CFString?
        guard SecRequirementCopyString(requirement, SecCSFlags(), &requirementText) == errSecSuccess,
              let requirementText = requirementText as String? else {
            return nil
        }
        return CodexCodeSignatureIdentity(
            signingIdentifier: identifier,
            teamIdentifier: information[kSecCodeInfoTeamIdentifier] as? String,
            designatedRequirement: requirementText
        )
        #else
        return nil
        #endif
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
        let normalized = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^codex-cli ([0-9]+)\.([0-9]+)\.([0-9]+)$"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        let matches = expression.matches(in: normalized, range: range)
        guard matches.count == 1, let match = matches.first,
              let majorRange = Range(match.range(at: 1), in: normalized),
              let minorRange = Range(match.range(at: 2), in: normalized),
              let patchRange = Range(match.range(at: 3), in: normalized),
              let major = Int(normalized[majorRange]),
              let minor = Int(normalized[minorRange]),
              let patch = Int(normalized[patchRange]) else {
            return nil
        }
        // Integer parsing alone would accept non-canonical builds such as
        // 00.144.1. Reconstructing the literal keeps the product runtime,
        // audit harness, and documented Personal Preview policy identical.
        guard normalized == "codex-cli \(major).\(minor).\(patch)" else {
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
    case validCodeSignatureRequired
    case unexpectedCodeSignature
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
    /// OpenAI's notarized macOS Codex distribution is the only Stable signing
    /// identity. Package-manager scripts remain available through Developer Mode.
    public static let productionSigningIdentifier = "codex"
    public static let productionTeamIdentifier = "2DC432GLL2"

    public let executablePath: String
    public let version: CodexAppServerVersion
    public let approvedExecutable: ApprovedCodexExecutable

    public static func approve(
        executablePath: String,
        approvedAt: Date = Date(),
        trustPolicy: CodexExecutableTrustPolicy = .signedProduction,
        fileManager: any CodexRuntimeFileInspecting = FileManager.default
    ) throws -> ApprovedCodexExecutable {
        let candidate = try preflight(
            executablePath: executablePath,
            trustPolicy: trustPolicy,
            fileManager: fileManager
        )
        return ApprovedCodexExecutable(
            path: candidate.path,
            identity: candidate.identity,
            approvedAt: approvedAt,
            trustPolicy: trustPolicy
        )
    }

    public static func preflight(
        approvedExecutable: ApprovedCodexExecutable?,
        fileManager: any CodexRuntimeFileInspecting = FileManager.default
    ) throws -> ApprovedCodexExecutable {
        guard let approvedExecutable else {
            throw CodexAppServerRuntimeConfigurationError.executionApprovalRequired
        }
        guard approvedExecutable.identity.hasContentIntegrityEvidence else {
            throw CodexAppServerRuntimeConfigurationError.executionApprovalRequired
        }
        let candidate: ApprovedCodexExecutable
        do {
            candidate = try preflight(
                executablePath: approvedExecutable.path,
                trustPolicy: approvedExecutable.trustPolicy,
                fileManager: fileManager
            )
        } catch {
            // Once an approval exists, disappearance, permission changes,
            // signature failures, and content changes all invalidate that
            // approval instead of preserving a stale persisted capability.
            throw CodexAppServerRuntimeConfigurationError.approvedExecutableChanged
        }
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
        return Self(
            executablePath: executable.resolvedPath,
            version: version,
            approvedExecutable: executable
        )
    }

    private static func preflight(
        executablePath: String,
        trustPolicy: CodexExecutableTrustPolicy,
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
        guard identity.hasContentIntegrityEvidence else {
            throw CodexAppServerRuntimeConfigurationError.executableMustBeRegularFile
        }
        if trustPolicy == .signedProduction {
            guard let signature = identity.codeSignature else {
                throw CodexAppServerRuntimeConfigurationError.validCodeSignatureRequired
            }
            guard signature.signingIdentifier == productionSigningIdentifier,
                  signature.teamIdentifier == productionTeamIdentifier else {
                throw CodexAppServerRuntimeConfigurationError.unexpectedCodeSignature
            }
        }
        return ApprovedCodexExecutable(
            path: trimmedPath,
            identity: identity,
            approvedAt: .distantPast,
            trustPolicy: trustPolicy
        )
    }

    private static func rejectCredentialStorePath(_ path: String) throws {
        let components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        if components.last?.lowercased() == "auth.json" ||
            components.suffix(2).map({ $0.lowercased() }) == [".codex", "auth.json"] {
            throw CodexAppServerRuntimeConfigurationError.credentialStorePathForbidden
        }
    }
}
