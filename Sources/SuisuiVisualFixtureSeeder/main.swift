import Darwin
import Foundation
import SuisuiCore

private enum SecureEvidenceHomeOperation {
    private static let markerName = ".suisui-ui-evidence-home-v1"

    static func create(arguments: [String]) throws {
        let values = try parse(
            arguments: arguments,
            allowedFlags: ["--path", "--evidence-home-marker-token"]
        )
        let requestedURL = try requiredPath(flag: "--path", values: values)
        let markerToken = try requiredMarkerToken(values: values)
        let (parentURL, name) = try resolvedParentAndName(for: requestedURL)
        let parentDescriptor = parentURL.path.withCString { path in
            open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard parentDescriptor >= 0 else {
            throw SeederError.invalidPath("unable to pin isolated HOME parent")
        }
        defer { close(parentDescriptor) }
        try validateParentDescriptor(parentDescriptor)

        let previousMask = umask(0)
        let createStatus = name.withCString { component in
            mkdirat(parentDescriptor, component, S_IRWXU)
        }
        umask(previousMask)
        guard createStatus == 0 else {
            throw SeederError.invalidPath(
                "isolated HOME must be a new directory created exclusively for this capture"
            )
        }

        let createdIdentity = try identity(
            of: name,
            relativeTo: parentDescriptor,
            expectedKind: S_IFDIR
        )
        var shouldRemoveCreatedHome = true
        defer {
            if shouldRemoveCreatedHome {
                removeEmptyLeafIfIdentityMatches(
                    name,
                    relativeTo: parentDescriptor,
                    expectedIdentity: createdIdentity
                )
            }
        }

        let homeDescriptor = name.withCString { component in
            openat(
                parentDescriptor,
                component,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
        }
        guard homeDescriptor >= 0 else {
            throw SeederError.invalidPath("unable to pin the newly created isolated HOME")
        }
        defer { close(homeDescriptor) }

        let identity = try validateHomeDescriptor(homeDescriptor)
        guard identity == createdIdentity else {
            throw SeederError.invalidPath(
                "isolated HOME changed between exclusive creation and descriptor pinning"
            )
        }
        let markerDescriptor = markerName.withCString { marker in
            openat(
                homeDescriptor,
                marker,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                S_IRUSR | S_IWUSR
            )
        }
        guard markerDescriptor >= 0 else {
            throw SeederError.invalidPath("unable to create isolated HOME ownership marker")
        }
        defer { close(markerDescriptor) }
        defer {
            if shouldRemoveCreatedHome {
                _ = markerName.withCString { marker in
                    unlinkat(homeDescriptor, marker, 0)
                }
            }
        }
        try writeAll(
            Data("suisui-ui-evidence-home-v1:\(markerToken)\n".utf8),
            to: markerDescriptor
        )
        guard fsync(markerDescriptor) == 0 else {
            throw SeederError.invalidPath("unable to persist isolated HOME ownership marker")
        }

        shouldRemoveCreatedHome = false
        print("evidence_home_device=\(identity.device)")
        print("evidence_home_inode=\(identity.inode)")
    }

    static func cleanup(arguments: [String]) throws {
        let values = try parse(
            arguments: arguments,
            allowedFlags: [
                "--path",
                "--evidence-home-marker-token",
                "--expected-evidence-home-device",
                "--expected-evidence-home-inode"
            ]
        )
        let requestedURL = try requiredPath(flag: "--path", values: values)
        let markerToken = try requiredMarkerToken(values: values)
        let expectedIdentity = try requiredIdentity(values: values)
        let (parentURL, name) = try resolvedParentAndName(for: requestedURL)
        let parentDescriptor = parentURL.path.withCString { path in
            open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard parentDescriptor >= 0 else {
            throw SeederError.invalidPath("unable to pin isolated HOME parent for cleanup")
        }
        defer { close(parentDescriptor) }
        try validateParentDescriptor(parentDescriptor)

        let homeDescriptor = name.withCString { component in
            openat(
                parentDescriptor,
                component,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
        }
        guard homeDescriptor >= 0 else {
            throw SeederError.invalidPath("isolated HOME is unavailable for secure cleanup")
        }
        defer { close(homeDescriptor) }

        guard try validateHomeDescriptor(homeDescriptor) == expectedIdentity else {
            throw SeederError.invalidPath(
                "isolated HOME identity changed; refusing recursive cleanup"
            )
        }
        try validateMarker(
            in: homeDescriptor,
            expectedContents: Data("suisui-ui-evidence-home-v1:\(markerToken)\n".utf8)
        )
        try removeContents(
            of: homeDescriptor,
            rootDevice: expectedIdentity.device,
            protectedEntryName: markerName
        )
        // Keep the marker until every other entry has been removed. A partial
        // cleanup can therefore be retried with the same identity capability
        // instead of stranding an unverifiable directory.
        try validateMarker(
            in: homeDescriptor,
            expectedContents: Data("suisui-ui-evidence-home-v1:\(markerToken)\n".utf8)
        )
        guard try identity(
            of: name,
            relativeTo: parentDescriptor,
            expectedKind: S_IFDIR
        ) == expectedIdentity else {
            throw SeederError.invalidPath(
                "isolated HOME changed before final directory removal"
            )
        }
        guard markerName.withCString({
            unlinkat(homeDescriptor, $0, 0)
        }) == 0 else {
            throw SeederError.invalidPath("unable to remove isolated HOME ownership marker")
        }
        let removeStatus = name.withCString({
            unlinkat(parentDescriptor, $0, AT_REMOVEDIR)
        })
        guard removeStatus == 0 else {
            try restoreMarker(
                in: homeDescriptor,
                contents: Data("suisui-ui-evidence-home-v1:\(markerToken)\n".utf8)
            )
            throw SeederError.invalidPath("unable to remove empty isolated HOME")
        }
    }

    struct Identity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    private static func parse(
        arguments: [String],
        allowedFlags: Set<String>
    ) throws -> [String: String] {
        guard arguments.count.isMultiple(of: 2) else {
            throw SeederError.invalidArguments("secure HOME arguments must be flag-value pairs")
        }
        var values: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let flag = arguments[index]
            let value = arguments[index + 1]
            guard allowedFlags.contains(flag), !value.isEmpty, values[flag] == nil else {
                throw SeederError.invalidArguments("invalid or duplicate secure HOME argument: \(flag)")
            }
            values[flag] = value
            index += 2
        }
        return values
    }

    private static func requiredPath(
        flag: String,
        values: [String: String]
    ) throws -> URL {
        guard let value = values[flag] else {
            throw SeederError.invalidArguments("missing \(flag)")
        }
        return URL(
            fileURLWithPath: value,
            relativeTo: URL(
                fileURLWithPath: FileManager.default.currentDirectoryPath,
                isDirectory: true
            )
        ).standardizedFileURL
    }

    private static func requiredMarkerToken(values: [String: String]) throws -> String {
        guard let value = values["--evidence-home-marker-token"],
              UUID(uuidString: value) != nil else {
            throw SeederError.invalidArguments(
                "--evidence-home-marker-token must be a UUID generated for this capture"
            )
        }
        return value
    }

    private static func requiredIdentity(values: [String: String]) throws -> Identity {
        guard let rawDevice = values["--expected-evidence-home-device"],
              let deviceValue = Int64(rawDevice),
              let device = dev_t(exactly: deviceValue),
              let rawInode = values["--expected-evidence-home-inode"],
              let inodeValue = UInt64(rawInode),
              let inode = ino_t(exactly: inodeValue) else {
            throw SeederError.invalidArguments(
                "secure HOME cleanup requires valid expected device and inode values"
            )
        }
        return Identity(device: device, inode: inode)
    }

    private static func resolvedParentAndName(for url: URL) throws -> (URL, String) {
        let name = url.lastPathComponent
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else {
            throw SeederError.invalidPath("isolated HOME has an invalid leaf name")
        }
        let requestedParent = url.deletingLastPathComponent()
        var parentIsDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: requestedParent.path,
            isDirectory: &parentIsDirectory
        ), parentIsDirectory.boolValue else {
            throw SeederError.invalidPath("isolated HOME parent must be an existing directory")
        }
        return (
            requestedParent.resolvingSymlinksInPath().standardizedFileURL,
            name
        )
    }

    private static func validateParentDescriptor(_ descriptor: Int32) throws {
        var information = stat()
        guard fstat(descriptor, &information) == 0,
              information.st_mode & S_IFMT == S_IFDIR else {
            throw SeederError.invalidPath("isolated HOME parent must remain a directory")
        }
        let privatelyOwned = information.st_uid == geteuid()
            && information.st_mode & (S_IWGRP | S_IWOTH) == 0
        let stickySharedDirectory = information.st_mode & S_ISVTX != 0
        guard privatelyOwned || stickySharedDirectory else {
            throw SeederError.invalidPath(
                "isolated HOME parent must be private or a sticky shared directory"
            )
        }
    }

    private static func identity(
        of name: String,
        relativeTo parentDescriptor: Int32,
        expectedKind: mode_t
    ) throws -> Identity {
        var information = stat()
        guard name.withCString({
            fstatat(parentDescriptor, $0, &information, AT_SYMLINK_NOFOLLOW)
        }) == 0,
              information.st_mode & S_IFMT == expectedKind,
              information.st_uid == geteuid() else {
            throw SeederError.invalidPath(
                "isolated HOME leaf changed to an unsafe owner or file type"
            )
        }
        return Identity(device: information.st_dev, inode: information.st_ino)
    }

    private static func removeEmptyLeafIfIdentityMatches(
        _ name: String,
        relativeTo parentDescriptor: Int32,
        expectedIdentity: Identity
    ) {
        guard let currentIdentity = try? identity(
            of: name,
            relativeTo: parentDescriptor,
            expectedKind: S_IFDIR
        ), currentIdentity == expectedIdentity else {
            return
        }
        _ = name.withCString { component in
            unlinkat(parentDescriptor, component, AT_REMOVEDIR)
        }
    }

    private static func validateHomeDescriptor(_ descriptor: Int32) throws -> Identity {
        var information = stat()
        guard fstat(descriptor, &information) == 0,
              information.st_mode & S_IFMT == S_IFDIR,
              information.st_uid == geteuid(),
              information.st_mode & (S_IRWXG | S_IRWXO) == 0 else {
            throw SeederError.invalidPath(
                "isolated HOME must be a private directory owned by the current user"
            )
        }
        return Identity(device: information.st_dev, inode: information.st_ino)
    }

    private static func validateMarker(
        in homeDescriptor: Int32,
        expectedContents: Data
    ) throws {
        let markerDescriptor = markerName.withCString { marker in
            openat(
                homeDescriptor,
                marker,
                O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC
            )
        }
        guard markerDescriptor >= 0 else {
            throw SeederError.invalidPath("isolated HOME ownership marker is unavailable")
        }
        defer { close(markerDescriptor) }

        var information = stat()
        guard fstat(markerDescriptor, &information) == 0,
              information.st_mode & S_IFMT == S_IFREG,
              information.st_nlink == 1,
              information.st_uid == geteuid(),
              information.st_mode & (S_IRWXG | S_IRWXO) == 0 else {
            throw SeederError.invalidPath("isolated HOME ownership marker is unsafe")
        }
        let handle = FileHandle(fileDescriptor: markerDescriptor, closeOnDealloc: false)
        let data = try handle.read(upToCount: expectedContents.count + 1) ?? Data()
        guard data == expectedContents else {
            throw SeederError.invalidPath(
                "isolated HOME ownership marker does not match this capture"
            )
        }
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var written = 0
            while written < rawBuffer.count {
                let count = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: written),
                    rawBuffer.count - written
                )
                guard count > 0 else {
                    throw SeederError.invalidPath(
                        "unable to write isolated HOME ownership marker"
                    )
                }
                written += count
            }
        }
    }

    private static func restoreMarker(
        in homeDescriptor: Int32,
        contents: Data
    ) throws {
        let descriptor = markerName.withCString { marker in
            openat(
                homeDescriptor,
                marker,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                S_IRUSR | S_IWUSR
            )
        }
        guard descriptor >= 0 else {
            throw SeederError.invalidPath(
                "cleanup failed and ownership marker could not be restored"
            )
        }
        defer { close(descriptor) }
        try writeAll(contents, to: descriptor)
        guard fsync(descriptor) == 0 else {
            throw SeederError.invalidPath(
                "cleanup failed and restored ownership marker could not be persisted"
            )
        }
    }

    private static func removeContents(
        of directoryDescriptor: Int32,
        rootDevice: dev_t,
        protectedEntryName: String? = nil
    ) throws {
        let iterationDescriptor = dup(directoryDescriptor)
        guard iterationDescriptor >= 0,
              let directory = fdopendir(iterationDescriptor) else {
            if iterationDescriptor >= 0 {
                close(iterationDescriptor)
            }
            throw SeederError.invalidPath("unable to enumerate isolated HOME for cleanup")
        }
        defer { closedir(directory) }

        while true {
            errno = 0
            guard let entry = readdir(directory) else {
                guard errno == 0 else {
                    throw SeederError.invalidPath(
                        "unable to finish isolated HOME enumeration"
                    )
                }
                break
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
                    String(cString: $0)
                }
            }
            guard name != ".", name != ".." else { continue }
            if name == protectedEntryName {
                continue
            }

            var information = stat()
            guard name.withCString({
                fstatat(directoryDescriptor, $0, &information, AT_SYMLINK_NOFOLLOW)
            }) == 0 else {
                throw SeederError.invalidPath("unable to inspect isolated HOME entry")
            }
            guard information.st_dev == rootDevice else {
                throw SeederError.invalidPath(
                    "isolated HOME cleanup must not cross filesystem devices"
                )
            }
            if information.st_mode & S_IFMT == S_IFDIR {
                let expectedChildIdentity = Identity(
                    device: information.st_dev,
                    inode: information.st_ino
                )
                let childDescriptor = name.withCString {
                    openat(
                        directoryDescriptor,
                        $0,
                        O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
                    )
                }
                guard childDescriptor >= 0 else {
                    throw SeederError.invalidPath(
                        "unable to pin isolated HOME child directory"
                    )
                }
                do {
                    var openedChildInformation = stat()
                    guard fstat(childDescriptor, &openedChildInformation) == 0,
                          openedChildInformation.st_mode & S_IFMT == S_IFDIR,
                          Identity(
                              device: openedChildInformation.st_dev,
                              inode: openedChildInformation.st_ino
                          ) == expectedChildIdentity else {
                        throw SeederError.invalidPath(
                            "isolated HOME child changed before recursive cleanup"
                        )
                    }
                    try removeContents(
                        of: childDescriptor,
                        rootDevice: rootDevice
                    )
                    close(childDescriptor)
                } catch {
                    close(childDescriptor)
                    throw error
                }
                guard try identity(
                    of: name,
                    relativeTo: directoryDescriptor,
                    expectedKind: S_IFDIR
                ) == expectedChildIdentity else {
                    throw SeederError.invalidPath(
                        "isolated HOME child changed before directory removal"
                    )
                }
                guard name.withCString({
                    unlinkat(directoryDescriptor, $0, AT_REMOVEDIR)
                }) == 0 else {
                    throw SeederError.invalidPath(
                        "unable to remove isolated HOME child directory"
                    )
                }
            } else {
                guard name.withCString({
                    unlinkat(directoryDescriptor, $0, 0)
                }) == 0 else {
                    throw SeederError.invalidPath("unable to remove isolated HOME file")
                }
            }
        }
    }
}

private struct SeederOptions {
    private static let evidenceHomeMarkerName = ".suisui-ui-evidence-home-v1"

    let databaseURL: URL
    let evidenceHomeURL: URL
    let captureReferenceInstant: Date?
    private let evidenceHomeIdentity: FileIdentity
    private let evidenceHomeMarkerContents: Data

    struct FileIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    final class PreparedDatabaseFile {
        let descriptor: Int32
        let identity: FileIdentity

        init(descriptor: Int32, identity: FileIdentity) {
            self.descriptor = descriptor
            self.identity = identity
        }

        deinit {
            close(descriptor)
        }
    }

    init(arguments: [String]) throws {
        var databasePath: String?
        var evidenceHomePath: String?
        var evidenceHomeMarkerToken: String?
        var expectedEvidenceHomeDevice: dev_t?
        var expectedEvidenceHomeInode: ino_t?
        var captureReferenceInstant: Date?
        var index = 0

        while index < arguments.count {
            let flag = arguments[index]
            guard flag == "--database"
                    || flag == "--evidence-home"
                    || flag == "--evidence-home-marker-token"
                    || flag == "--expected-evidence-home-device"
                    || flag == "--expected-evidence-home-inode"
                    || flag == "--capture-reference-instant" else {
                throw SeederError.invalidArguments("unknown argument: \(flag)")
            }
            guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
                throw SeederError.invalidArguments("missing value for \(flag)")
            }

            let value = arguments[index + 1]
            guard !value.isEmpty else {
                throw SeederError.invalidArguments("empty value for \(flag)")
            }
            switch flag {
            case "--database":
                guard databasePath == nil else {
                    throw SeederError.invalidArguments("duplicate --database")
                }
                databasePath = value
            case "--evidence-home":
                guard evidenceHomePath == nil else {
                    throw SeederError.invalidArguments("duplicate --evidence-home")
                }
                evidenceHomePath = value
            case "--evidence-home-marker-token":
                guard evidenceHomeMarkerToken == nil else {
                    throw SeederError.invalidArguments("duplicate --evidence-home-marker-token")
                }
                guard UUID(uuidString: value) != nil else {
                    throw SeederError.invalidArguments(
                        "--evidence-home-marker-token must be a UUID generated for this capture"
                    )
                }
                evidenceHomeMarkerToken = value
            case "--expected-evidence-home-device":
                guard expectedEvidenceHomeDevice == nil,
                      let rawValue = Int64(value),
                      let parsedValue = dev_t(exactly: rawValue) else {
                    throw SeederError.invalidArguments(
                        "--expected-evidence-home-device must be one unique device identifier"
                    )
                }
                expectedEvidenceHomeDevice = parsedValue
            case "--expected-evidence-home-inode":
                guard expectedEvidenceHomeInode == nil,
                      let rawValue = UInt64(value),
                      let parsedValue = ino_t(exactly: rawValue) else {
                    throw SeederError.invalidArguments(
                        "--expected-evidence-home-inode must be one unique inode identifier"
                    )
                }
                expectedEvidenceHomeInode = parsedValue
            case "--capture-reference-instant":
                guard captureReferenceInstant == nil else {
                    throw SeederError.invalidArguments("duplicate --capture-reference-instant")
                }
                guard value.wholeMatch(of: /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/) != nil else {
                    throw SeederError.invalidArguments(
                        "--capture-reference-instant must be a whole-second UTC ISO-8601 instant"
                    )
                }
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime]
                guard let parsedInstant = formatter.date(from: value) else {
                    throw SeederError.invalidArguments(
                        "--capture-reference-instant must be a valid UTC ISO-8601 instant"
                    )
                }
                captureReferenceInstant = parsedInstant
            default:
                preconditionFailure("validated flag")
            }
            index += 2
        }

        guard let databasePath,
              let evidenceHomePath,
              let evidenceHomeMarkerToken,
              let expectedEvidenceHomeDevice,
              let expectedEvidenceHomeInode else {
            throw SeederError.invalidArguments(
                "usage: SuisuiVisualFixtureSeeder --database <path> --evidence-home <path> "
                    + "--evidence-home-marker-token <uuid> --expected-evidence-home-device <device> "
                    + "--expected-evidence-home-inode <inode> "
                    + "[--capture-reference-instant <UTC ISO-8601 instant>]"
            )
        }

        let requestedDatabaseURL = Self.standardizedURL(for: databasePath)
        let requestedEvidenceHomeURL = Self.standardizedURL(for: evidenceHomePath)
        if try Self.existingPathKind(at: requestedDatabaseURL) == .symbolicLink {
            throw SeederError.invalidPath("--database must not be a symbolic link")
        }

        // Resolve the deepest component that already exists, then append the
        // uncreated suffix. Resolving the complete nonexistent database path
        // can retain an ancestor alias such as /tmp while the existing home is
        // canonicalized to /private/tmp, producing a false containment failure.
        databaseURL = try Self.canonicalURLPreservingUncreatedSuffix(for: requestedDatabaseURL)
        evidenceHomeURL = try Self.canonicalURLPreservingUncreatedSuffix(for: requestedEvidenceHomeURL)
        self.captureReferenceInstant = captureReferenceInstant
        try Self.validate(databaseURL: databaseURL, evidenceHomeURL: evidenceHomeURL)
        evidenceHomeIdentity = try Self.identity(
            at: evidenceHomeURL,
            expectedKind: .directory,
            description: "--evidence-home"
        )
        guard evidenceHomeIdentity == FileIdentity(
            device: expectedEvidenceHomeDevice,
            inode: expectedEvidenceHomeInode
        ) else {
            throw SeederError.invalidPath(
                "--evidence-home no longer matches the directory created for this capture"
            )
        }
        evidenceHomeMarkerContents = Data(
            "suisui-ui-evidence-home-v1:\(evidenceHomeMarkerToken)\n".utf8
        )
        try Self.rejectUnsafeExistingDatabase(at: databaseURL)
    }

    private enum ExistingPathKind: Equatable {
        case directory
        case symbolicLink
        case other
    }

    private static func standardizedURL(for path: String) -> URL {
        URL(
            fileURLWithPath: path,
            relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        )
        .standardizedFileURL
    }

    private static func existingPathKind(at url: URL) throws -> ExistingPathKind? {
        var fileInformation = stat()
        let status = url.path.withCString { path in
            lstat(path, &fileInformation)
        }
        guard status == 0 else {
            if errno == ENOENT || errno == ENOTDIR {
                return nil
            }
            throw SeederError.invalidPath("unable to inspect path: \(url.path)")
        }

        switch fileInformation.st_mode & S_IFMT {
        case S_IFDIR:
            return .directory
        case S_IFLNK:
            return .symbolicLink
        default:
            return .other
        }
    }

    private static func canonicalURLPreservingUncreatedSuffix(for url: URL) throws -> URL {
        var existingAncestor = url
        var uncreatedComponents: [String] = []

        while try existingPathKind(at: existingAncestor) == nil {
            guard existingAncestor.path != "/" else {
                throw SeederError.invalidPath("path has no existing ancestor: \(url.path)")
            }
            uncreatedComponents.append(existingAncestor.lastPathComponent)
            existingAncestor.deleteLastPathComponent()
        }

        let canonicalAncestor = existingAncestor
            .resolvingSymlinksInPath()
            .standardizedFileURL
        if !uncreatedComponents.isEmpty {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(
                atPath: canonicalAncestor.path,
                isDirectory: &isDirectory
            ), isDirectory.boolValue else {
                throw SeederError.invalidPath("uncreated path suffix must follow an existing directory")
            }
        }

        return uncreatedComponents.reversed().reduce(canonicalAncestor) { partialURL, component in
            partialURL.appendingPathComponent(component)
        }
    }

    private static func validate(databaseURL: URL, evidenceHomeURL: URL) throws {
        var evidenceHomeIsDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: evidenceHomeURL.path,
            isDirectory: &evidenceHomeIsDirectory
        ), evidenceHomeIsDirectory.boolValue else {
            throw SeederError.invalidPath("--evidence-home must resolve to an existing directory")
        }

        var databaseIsDirectory: ObjCBool = false
        if FileManager.default.fileExists(
            atPath: databaseURL.path,
            isDirectory: &databaseIsDirectory
        ), databaseIsDirectory.boolValue {
            throw SeederError.invalidPath("--database must resolve to a file")
        }

        let homeComponents = evidenceHomeURL.pathComponents
        let databaseComponents = databaseURL.pathComponents
        guard databaseComponents.count > homeComponents.count,
              Array(databaseComponents.prefix(homeComponents.count)) == homeComponents else {
            throw SeederError.invalidPath(
                "--database must be a file below the resolved --evidence-home"
            )
        }
    }

    private static func identity(
        at url: URL,
        expectedKind: ExistingPathKind,
        description: String
    ) throws -> FileIdentity {
        var fileInformation = stat()
        let status = url.path.withCString { path in
            lstat(path, &fileInformation)
        }
        guard status == 0 else {
            throw SeederError.invalidPath("unable to inspect \(description): \(url.path)")
        }

        let actualKind: ExistingPathKind
        switch fileInformation.st_mode & S_IFMT {
        case S_IFDIR:
            actualKind = .directory
        case S_IFLNK:
            actualKind = .symbolicLink
        default:
            actualKind = .other
        }
        guard actualKind == expectedKind else {
            throw SeederError.invalidPath("\(description) changed to an unsafe path type")
        }
        return FileIdentity(device: fileInformation.st_dev, inode: fileInformation.st_ino)
    }

    private static func rejectUnsafeExistingDatabase(at url: URL) throws {
        var fileInformation = stat()
        let status = url.path.withCString { path in
            lstat(path, &fileInformation)
        }
        guard status == 0 else {
            if errno == ENOENT || errno == ENOTDIR {
                return
            }
            throw SeederError.invalidPath("unable to inspect database path: \(url.path)")
        }
        guard fileInformation.st_mode & S_IFMT == S_IFREG else {
            throw SeederError.invalidPath("--database must resolve to a regular file")
        }
        guard fileInformation.st_nlink == 1 else {
            throw SeederError.invalidPath("--database must not be a hard link")
        }
    }

    private func validateDatabaseParentContainment() throws {
        let resolvedParent = databaseURL
            .deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let homeComponents = evidenceHomeURL.pathComponents
        let parentComponents = resolvedParent.pathComponents
        guard parentComponents.count >= homeComponents.count,
              Array(parentComponents.prefix(homeComponents.count)) == homeComponents else {
            throw SeederError.invalidPath("--database parent escaped the resolved --evidence-home")
        }
        guard try Self.identity(
            at: evidenceHomeURL,
            expectedKind: .directory,
            description: "--evidence-home"
        ) == evidenceHomeIdentity else {
            throw SeederError.invalidPath("--evidence-home changed during database preparation")
        }
    }

    func prepareDatabaseFile() throws -> PreparedDatabaseFile {
        let evidenceHomeDescriptor = evidenceHomeURL.path.withCString { path in
            open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard evidenceHomeDescriptor >= 0 else {
            throw SeederError.invalidPath("unable to pin --evidence-home")
        }
        var openedDirectoryDescriptors = [evidenceHomeDescriptor]
        defer {
            for descriptor in openedDirectoryDescriptors.reversed() {
                close(descriptor)
            }
        }

        var evidenceHomeInformation = stat()
        guard fstat(evidenceHomeDescriptor, &evidenceHomeInformation) == 0,
              evidenceHomeInformation.st_mode & S_IFMT == S_IFDIR,
              evidenceHomeInformation.st_uid == geteuid(),
              evidenceHomeInformation.st_mode & (S_IRWXG | S_IRWXO) == 0,
              FileIdentity(
                  device: evidenceHomeInformation.st_dev,
                  inode: evidenceHomeInformation.st_ino
              ) == evidenceHomeIdentity else {
            throw SeederError.invalidPath("--evidence-home changed after validation")
        }
        try validateEvidenceHomeMarker(in: evidenceHomeDescriptor)

        let homeComponentCount = evidenceHomeURL.pathComponents.count
        let relativeComponents = Array(databaseURL.pathComponents.dropFirst(homeComponentCount))
        guard let databaseName = relativeComponents.last,
              !databaseName.isEmpty,
              databaseName != ".",
              databaseName != "..",
              !databaseName.contains("/") else {
            throw SeederError.invalidPath("--database has an invalid file name")
        }

        var currentDirectoryDescriptor = evidenceHomeDescriptor
        for component in relativeComponents.dropLast() {
            guard !component.isEmpty,
                  component != ".",
                  component != "..",
                  !component.contains("/") else {
                throw SeederError.invalidPath("--database contains an invalid directory component")
            }

            var childDescriptor = component.withCString { name in
                openat(
                    currentDirectoryDescriptor,
                    name,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
                )
            }
            if childDescriptor == -1, errno == ENOENT {
                // Create each component relative to the already pinned parent.
                // A path-based recursive mkdir could follow a directory swapped
                // to a symlink between validation and creation.
                let createStatus = component.withCString { name in
                    mkdirat(currentDirectoryDescriptor, name, S_IRWXU)
                }
                guard createStatus == 0 || errno == EEXIST else {
                    throw SeederError.invalidPath("unable to create a secure database directory")
                }
                childDescriptor = component.withCString { name in
                    openat(
                        currentDirectoryDescriptor,
                        name,
                        O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
                    )
                }
            }
            guard childDescriptor >= 0 else {
                throw SeederError.invalidPath(
                    "unable to traverse the database directory without following links"
                )
            }

            var childInformation = stat()
            guard fstat(childDescriptor, &childInformation) == 0,
                  childInformation.st_mode & S_IFMT == S_IFDIR else {
                close(childDescriptor)
                throw SeederError.invalidPath("database path component must remain a directory")
            }
            openedDirectoryDescriptors.append(childDescriptor)
            currentDirectoryDescriptor = childDescriptor
        }

        let flags = O_RDWR | O_NOFOLLOW | O_CLOEXEC
        var descriptor = databaseName.withCString { name in
            openat(currentDirectoryDescriptor, name, flags)
        }
        if descriptor == -1, errno == ENOENT {
            descriptor = databaseName.withCString { name in
                openat(
                    currentDirectoryDescriptor,
                    name,
                    flags | O_CREAT | O_EXCL,
                    S_IRUSR | S_IWUSR
                )
            }
        }
        guard descriptor >= 0 else {
            throw SeederError.invalidPath("unable to open database without following links")
        }
        var fileInformation = stat()
        guard fstat(descriptor, &fileInformation) == 0,
              fileInformation.st_mode & S_IFMT == S_IFREG else {
            close(descriptor)
            throw SeederError.invalidPath("--database must remain a regular file")
        }
        guard fileInformation.st_nlink == 1 else {
            close(descriptor)
            throw SeederError.invalidPath("--database must not be a hard link")
        }
        try validateDatabaseParentContainment()
        return PreparedDatabaseFile(
            descriptor: descriptor,
            identity: FileIdentity(device: fileInformation.st_dev, inode: fileInformation.st_ino)
        )
    }

    private func validateEvidenceHomeMarker(in evidenceHomeDescriptor: Int32) throws {
        let markerDescriptor = Self.evidenceHomeMarkerName.withCString { name in
            openat(
                evidenceHomeDescriptor,
                name,
                O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC
            )
        }
        guard markerDescriptor >= 0 else {
            throw SeederError.invalidPath(
                "--evidence-home is not a capture-owned isolated home"
            )
        }
        defer { close(markerDescriptor) }

        var markerInformation = stat()
        guard fstat(markerDescriptor, &markerInformation) == 0,
              markerInformation.st_mode & S_IFMT == S_IFREG,
              markerInformation.st_nlink == 1,
              markerInformation.st_uid == geteuid(),
              markerInformation.st_mode & (S_IRWXG | S_IRWXO) == 0 else {
            throw SeederError.invalidPath(
                "--evidence-home ownership marker must be a single-link file owned by the current user"
            )
        }

        // Read at most one byte beyond the exact token-bound payload. This
        // rejects appended data without trusting an unbounded marker supplied
        // through a filesystem path that may be controlled by another process.
        let markerHandle = FileHandle(
            fileDescriptor: markerDescriptor,
            closeOnDealloc: false
        )
        let markerData = try markerHandle.read(
            upToCount: evidenceHomeMarkerContents.count + 1
        ) ?? Data()
        guard markerData == evidenceHomeMarkerContents else {
            throw SeederError.invalidPath(
                "--evidence-home ownership marker does not match this capture"
            )
        }
    }

    func validatePreparedDatabase(_ preparedDatabase: PreparedDatabaseFile) throws {
        // SQLite opens the pinned descriptor through /dev/fd. Rechecking the
        // public path still makes a concurrent rename or link swap fail closed.
        try validateDatabaseParentContainment()
        try Self.rejectUnsafeExistingDatabase(at: databaseURL)
        let currentIdentity = try Self.identity(
            at: databaseURL,
            expectedKind: .other,
            description: "--database"
        )
        guard currentIdentity == preparedDatabase.identity else {
            throw SeederError.invalidPath("--database changed after secure preparation")
        }

        var descriptorInformation = stat()
        guard fstat(preparedDatabase.descriptor, &descriptorInformation) == 0,
              descriptorInformation.st_mode & S_IFMT == S_IFREG,
              descriptorInformation.st_nlink == 1,
              descriptorInformation.st_uid == geteuid(),
              FileIdentity(
                  device: descriptorInformation.st_dev,
                  inode: descriptorInformation.st_ino
              ) == preparedDatabase.identity else {
            throw SeederError.invalidPath("--database descriptor changed after secure preparation")
        }
    }
}

private enum SeederError: Error, CustomStringConvertible {
    case invalidArguments(String)
    case invalidPath(String)
    case invalidCaptureFixture(String)
    case invalidPresentation(id: String, expected: String)

    var description: String {
        switch self {
        case .invalidArguments(let message), .invalidPath(let message):
            message
        case .invalidCaptureFixture(let message):
            "invalid capture fixture: \(message)"
        case .invalidPresentation(let id, let expected):
            "seeded \(id) did not expose \(expected) as its primary action"
        }
    }
}

private struct FixtureDefinition {
    let id: String
    let planID: String
    let actionID: String
}

private let waitingFixture = FixtureDefinition(
    id: "visual-waiting",
    planID: "visual-plan-waiting",
    actionID: "visual-action-waiting"
)

private let approvedFixture = FixtureDefinition(
    id: "visual-approved",
    planID: "visual-plan-approved",
    actionID: "visual-action-approved"
)

private let failedFixture = FixtureDefinition(
    id: "visual-failed",
    planID: "visual-plan-failed",
    actionID: "visual-action-failed"
)

private func waitingItem(for fixture: FixtureDefinition) -> AssistantQueueItem {
    let plan = ActionPlan(
        id: fixture.planID,
        userInput: "Prepare local visual evidence",
        summary: "Prepare local visual evidence",
        actions: [
            PlanAction(
                id: fixture.actionID,
                tool: .taskCreate,
                // All visual states intentionally share one inert local action.
                // This isolates state presentation from payload wording and
                // proves that captures never exercise an external connector.
                arguments: [
                    "title": .string("Review local visual evidence"),
                    "detail": .string("Visual fixture only; no external connector is invoked.")
                ],
                riskLevel: .write
            )
        ],
        riskLevel: .write,
        requiresApproval: true
    )
    var item = AssistantQueueAdapter.makeItem(
        actionPlan: plan,
        sourceTranscript: nil,
        interpretationSummary: "Local visual evidence task draft.",
        reason: "Review this local visual fixture before approval."
    )
    // The adapter owns every approval-related field. Only the fixture identity
    // is replaced so captures can address stable rows without hand-building
    // approval JSON that could drift from the production model.
    item.id = fixture.id
    return item
}

private struct CaptureSeedReceipt {
    let projectID: String
    let inboxVoiceTaskID: String
    let captureTaskID: String
    let reviewTaskID: String
    let unscheduledTaskID: String
    let captureDueDate: String
    let reviewDueDate: String

    var shellLines: [String] {
        [
            "project_id=\(projectID)",
            "inbox_voice_task_id=\(inboxVoiceTaskID)",
            "capture_task_id=\(captureTaskID)",
            "review_task_id=\(reviewTaskID)",
            "unscheduled_task_id=\(unscheduledTaskID)",
            "capture_due_date=\(captureDueDate)",
            "review_due_date=\(reviewDueDate)"
        ]
    }
}

private func requiredCaptureValue(
    _ connection: SQLiteConnection,
    sql: String,
    parameters: [SQLiteValue] = [],
    description: String
) throws -> String {
    let values = try connection.queryStrings(sql, parameters: parameters)
    guard values.count == 1, let value = values.first, !value.isEmpty else {
        throw SeederError.invalidCaptureFixture("\(description) was not uniquely seeded")
    }
    return value
}

private func requiredCaptureID(
    _ connection: SQLiteConnection,
    title: String,
    table: String
) throws -> String {
    let sql: String
    switch table {
    case "projects":
        sql = """
            SELECT id
            FROM projects
            WHERE source_command = 'ui-evidence' AND title = ?
            ORDER BY id DESC
            LIMIT 1;
            """
    case "tasks":
        sql = """
            SELECT id
            FROM tasks
            WHERE source_command = 'ui-evidence' AND title = ?
            ORDER BY id DESC
            LIMIT 1;
            """
    default:
        preconditionFailure("capture fixture table must be statically selected")
    }
    let value = try requiredCaptureValue(
        connection,
        sql: sql,
        parameters: [.text(title)],
        description: title
    )
    guard !value.isEmpty, value.allSatisfy(\.isNumber), Int64(value) != nil else {
        throw SeederError.invalidCaptureFixture("\(title) has a non-numeric identifier")
    }
    return value
}

private func seedCaptureFixtures(
    connection: SQLiteConnection,
    referenceInstant: Date
) throws -> CaptureSeedReceipt {
    var calendar = Calendar(identifier: .iso8601)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let dayFormatter = DateFormatter()
    dayFormatter.calendar = calendar
    dayFormatter.locale = Locale(identifier: "en_US_POSIX")
    dayFormatter.timeZone = calendar.timeZone
    dayFormatter.dateFormat = "yyyy-MM-dd"
    guard let tomorrowInstant = calendar.date(byAdding: .day, value: 1, to: referenceInstant),
          let yesterdayInstant = calendar.date(byAdding: .day, value: -1, to: referenceInstant) else {
        throw SeederError.invalidCaptureFixture("reference instant could not produce relative dates")
    }
    let today = dayFormatter.string(from: referenceInstant)
    let tomorrow = dayFormatter.string(from: tomorrowInstant)
    let yesterday = ISO8601DateFormatter().string(from: yesterdayInstant)

    return try connection.transaction {
        try connection.execute(
            """
            DELETE FROM inbox_capture_records
            WHERE task_id IN (SELECT id FROM tasks WHERE source_command = 'ui-evidence');
            DELETE FROM project_milestones
            WHERE project_id IN (SELECT id FROM projects WHERE source_command = 'ui-evidence');
            DELETE FROM tasks WHERE source_command = 'ui-evidence';
            DELETE FROM projects WHERE source_command = 'ui-evidence';
            DELETE FROM mcp_server_registrations
            WHERE id IN ('ui-evidence-filesystem', 'ui-evidence-issues');
            """
        )

        // Relative dates are always bound values. Keeping the capture clock out
        // of SQL text prevents shell quoting or future caller input from becoming
        // executable fixture SQL.
        try connection.execute(
            """
            INSERT INTO projects (
                title, status, priority, deadline, workspace_path, tags_json, source_command
            ) VALUES (
                'Launch Readiness', 'active', 'high', ?, NULL,
                '["ui-evidence","local"]', 'ui-evidence'
            );
            """,
            parameters: [.text(tomorrow)]
        )
        try connection.execute(
            """
            INSERT INTO projects (
                title, status, priority, deadline, workspace_path, tags_json, source_command
            ) VALUES (
                'Inbox', 'active', NULL, NULL, NULL,
                '["ui-evidence","inbox"]', 'ui-evidence'
            );
            """,
            parameters: []
        )
        try connection.execute(
            """
            INSERT INTO projects (
                title, status, priority, deadline, workspace_path, tags_json, source_command
            ) VALUES (
                'Completed Evidence Project', 'completed', 'medium', ?, NULL,
                '["ui-evidence","done"]', 'ui-evidence'
            );
            """,
            parameters: [.text(tomorrow)]
        )

        let projectID = try requiredCaptureID(
            connection,
            title: "Launch Readiness",
            table: "projects"
        )
        let inboxProjectID = try requiredCaptureID(
            connection,
            title: "Inbox",
            table: "projects"
        )
        let completedProjectID = try requiredCaptureID(
            connection,
            title: "Completed Evidence Project",
            table: "projects"
        )
        guard let projectIDValue = Int64(projectID),
              let inboxProjectIDValue = Int64(inboxProjectID),
              let completedProjectIDValue = Int64(completedProjectID) else {
            throw SeederError.invalidCaptureFixture("project identifiers could not be bound")
        }

        let taskFixtures: [(Int64, String, String, String, SQLiteValue, SQLiteValue, String)] = [
            (
                projectIDValue,
                "Capture launch screenshots",
                "planned",
                "Verify board card density, sidebar, and inspector in each theme.",
                .text(tomorrow),
                .null,
                "high"
            ),
            (
                projectIDValue,
                "Review VoiceOver focus path",
                "in_progress",
                "Confirm project board to task card to inspector path before public alpha.",
                .text(today),
                .null,
                "high"
            ),
            (
                projectIDValue,
                "Document remaining release blockers",
                "blocked",
                "Keep signing, notarization, and manual accessibility gates visible.",
                .null,
                .null,
                "medium"
            ),
            (
                inboxProjectIDValue,
                "Scheduled manual capture",
                "planned",
                "Voice memo capture with transcript and local interpretation metadata.",
                .null,
                .null,
                "high"
            ),
            (
                inboxProjectIDValue,
                "Review captured note",
                "backlog",
                "Manual Inbox item keeps the normal route visually distinct from the seeded voice intake detail.",
                .null,
                .null,
                "medium"
            ),
            (
                projectIDValue,
                "Unscheduled schedule draft input",
                "planned",
                "Appears in Schedule cockpit as an unscheduled task.",
                .null,
                .null,
                "medium"
            ),
            (
                completedProjectIDValue,
                "Done analytics sample",
                "completed",
                "Completed history appears in Done analytics evidence.",
                .text(tomorrow),
                .text(yesterday),
                "medium"
            )
        ]
        for fixture in taskFixtures {
            try connection.execute(
                """
                INSERT INTO tasks (
                    project_id, title, status, detail, due_at, completed_at,
                    priority, source_command
                ) VALUES (?, ?, ?, ?, ?, ?, ?, 'ui-evidence');
                """,
                parameters: [
                    .integer(fixture.0),
                    .text(fixture.1),
                    .text(fixture.2),
                    .text(fixture.3),
                    fixture.4,
                    fixture.5,
                    .text(fixture.6)
                ]
            )
        }

        let inboxVoiceTaskID = try requiredCaptureID(
            connection,
            title: "Scheduled manual capture",
            table: "tasks"
        )
        guard let inboxVoiceTaskIDValue = Int64(inboxVoiceTaskID) else {
            throw SeederError.invalidCaptureFixture("Inbox voice task identifier could not be bound")
        }
        try connection.execute(
            """
            INSERT INTO inbox_capture_records (
                task_id, source_kind, audio_file_path, duration_seconds,
                transcript, interpretation_summary, memo,
                classification_status, transcription_status, created_at
            ) VALUES (
                ?, 'voice_memo', '/tmp/suisui-ui-evidence-redacted.m4a', 18.5,
                'Schedule launch review and capture visual evidence.',
                'Create a task for launch review evidence.',
                'Seeded local transcript for UI screenshot evidence.',
                'unclassified', 'succeeded', ?
            );
            """,
            parameters: [.integer(inboxVoiceTaskIDValue), .text(yesterday)]
        )
        try connection.execute(
            """
            INSERT INTO project_milestones (project_id, title, due_at, is_completed)
            VALUES (?, 'Launch milestone', ?, 0);
            """,
            parameters: [.integer(projectIDValue), .text(tomorrow)]
        )

        try connection.execute(
            """
            INSERT INTO mcp_server_registrations (
                id, sort_order, display_name, command, arguments_json,
                environment_json, working_directory, is_enabled
            ) VALUES (
                'ui-evidence-filesystem', 0, 'Local Filesystem MCP', '/usr/bin/env',
                '["node","@modelcontextprotocol/server-filesystem","/tmp"]',
                '{"SUISUI_FILESYSTEM_TOKEN":{"type":"keychain","key":"mcp_filesystem_token"}}',
                './fixtures/mcp-workspace', 1
            );

            INSERT INTO mcp_server_registrations (
                id, sort_order, display_name, command, arguments_json,
                environment_json, working_directory, is_enabled
            ) VALUES (
                'ui-evidence-issues', 1, 'Issue Tracker MCP', '/usr/bin/env',
                '["npx","-y","@modelcontextprotocol/server-github"]',
                '{"GITHUB_TOKEN":{"type":"keychain","key":"mcp_github_token"}}',
                './fixtures/mcp-workspace', 0
            );
            """
        )

        let countChecks = [
            (
                "Scheduled manual capture",
                "SELECT COUNT(*) FROM tasks WHERE source_command = 'ui-evidence' AND title = ?;"
            ),
            (
                "Done analytics sample",
                "SELECT COUNT(*) FROM tasks WHERE source_command = 'ui-evidence' AND title = ?;"
            ),
            (
                "Completed Evidence Project",
                "SELECT COUNT(*) FROM projects WHERE source_command = 'ui-evidence' AND title = ?;"
            ),
            (
                "Inbox",
                "SELECT COUNT(*) FROM projects WHERE source_command = 'ui-evidence' AND title = ?;"
            )
        ]
        for (title, countSQL) in countChecks {
            let count = try requiredCaptureValue(
                connection,
                sql: countSQL,
                parameters: [.text(title)],
                description: "\(title) count"
            )
            guard count == "1" else {
                throw SeederError.invalidCaptureFixture("missing Phase 12 UI evidence seed: \(title)")
            }
        }
        let invalidStatuses = try connection.queryStrings(
            """
            SELECT DISTINCT status
            FROM tasks
            WHERE source_command = 'ui-evidence'
              AND status NOT IN ('open', 'backlog', 'planned', 'in_progress', 'blocked', 'completed')
            ORDER BY status;
            """
        )
        guard invalidStatuses.isEmpty else {
            throw SeederError.invalidCaptureFixture(
                "unsupported Phase 12 UI evidence task status: \(invalidStatuses.joined(separator: ","))"
            )
        }

        let captureTaskID = try requiredCaptureID(
            connection,
            title: "Capture launch screenshots",
            table: "tasks"
        )
        let reviewTaskID = try requiredCaptureID(
            connection,
            title: "Review VoiceOver focus path",
            table: "tasks"
        )
        let unscheduledTaskID = try requiredCaptureID(
            connection,
            title: "Unscheduled schedule draft input",
            table: "tasks"
        )
        let captureDueDate = try requiredCaptureValue(
            connection,
            sql: "SELECT substr(due_at, 1, 10) FROM tasks WHERE id = ?;",
            parameters: [.integer(Int64(captureTaskID)!)],
            description: "capture task due date"
        )
        let reviewDueDate = try requiredCaptureValue(
            connection,
            sql: "SELECT substr(due_at, 1, 10) FROM tasks WHERE id = ?;",
            parameters: [.integer(Int64(reviewTaskID)!)],
            description: "review task due date"
        )
        let canonicalDayPattern = /^\d{4}-\d{2}-\d{2}$/
        guard captureDueDate.wholeMatch(of: canonicalDayPattern) != nil,
              reviewDueDate.wholeMatch(of: canonicalDayPattern) != nil else {
            throw SeederError.invalidCaptureFixture(
                "project-board evidence tasks have no canonical due date"
            )
        }

        return CaptureSeedReceipt(
            projectID: projectID,
            inboxVoiceTaskID: inboxVoiceTaskID,
            captureTaskID: captureTaskID,
            reviewTaskID: reviewTaskID,
            unscheduledTaskID: unscheduledTaskID,
            captureDueDate: captureDueDate,
            reviewDueDate: reviewDueDate
        )
    }
}

private func run(options: SeederOptions) throws {
    let preparedDatabase = try options.prepareDatabaseFile()
    let connection = try SQLiteConnection(
        secureFileDescriptor: preparedDatabase.descriptor,
        secureFileValidation: {
            try options.validatePreparedDatabase(preparedDatabase)
        }
    )
    try SQLiteMigrationRunner.migrate(
        connection: connection,
        migrations: CoreMigrations.current
    )
    let captureReceipt = try options.captureReferenceInstant.map {
        try seedCaptureFixtures(connection: connection, referenceInstant: $0)
    }
    let store = SQLiteAssistantQueueStore(connection: connection)

    let waiting = waitingItem(for: waitingFixture)
    let approved = try AssistantQueueStateMachine.approve(
        waitingItem(for: approvedFixture),
        reviewerID: "visual-evidence-reviewer"
    )
    let failed = try AssistantQueueStateMachine.markFailed(
        AssistantQueueStateMachine.startRunning(
            AssistantQueueStateMachine.approve(
                waitingItem(for: failedFixture),
                reviewerID: "visual-evidence-reviewer"
            )
        ),
        reason: "visual-evidence-simulated-failure"
    )

    for item in [waiting, approved, failed] {
        try store.save(item)
    }
    try options.validatePreparedDatabase(preparedDatabase)

    let snapshot = try store.readModelSnapshot(filter: .all(limit: 100))
    let rowsByID = Dictionary(uniqueKeysWithValues: snapshot.rows.map { ($0.id, $0) })
    let expectedActions: [(String, AssistantQueueRowActionPresentation.Action, String)] = [
        (waiting.id, .approve, "approve"),
        (approved.id, .run, "run"),
        (failed.id, .reopen, "reopen")
    ]
    for (id, expectedAction, expectedName) in expectedActions {
        guard let row = rowsByID[id],
              AssistantQueueRowActionPresentation.make(for: row).primaryAction == expectedAction else {
            throw SeederError.invalidPresentation(id: id, expected: expectedName)
        }
    }
    for line in captureReceipt?.shellLines ?? [] {
        print(line)
    }
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    switch arguments.first {
    case "--create-evidence-home":
        try SecureEvidenceHomeOperation.create(arguments: Array(arguments.dropFirst()))
    case "--cleanup-evidence-home":
        try SecureEvidenceHomeOperation.cleanup(arguments: Array(arguments.dropFirst()))
    default:
        let options = try SeederOptions(arguments: arguments)
        try run(options: options)
    }
} catch {
    fputs("BLOCKER: \(error)\n", stderr)
    exit(2)
}
