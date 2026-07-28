import Darwin
import Foundation
import SuisuiCore

private struct SeederOptions {
    let databaseURL: URL
    let evidenceHomeURL: URL
    let captureReferenceInstant: Date?
    private let evidenceHomeIdentity: FileIdentity

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
        var captureReferenceInstant: Date?
        var index = 0

        while index < arguments.count {
            let flag = arguments[index]
            guard flag == "--database"
                    || flag == "--evidence-home"
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

        guard let databasePath, let evidenceHomePath else {
            throw SeederError.invalidArguments(
                "usage: SuisuiVisualFixtureSeeder --database <path> --evidence-home <path> "
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
              FileIdentity(
                  device: evidenceHomeInformation.st_dev,
                  inode: evidenceHomeInformation.st_ino
              ) == evidenceHomeIdentity else {
            throw SeederError.invalidPath("--evidence-home changed after validation")
        }

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
            DELETE FROM mcp_server_registrations;
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
    let options = try SeederOptions(arguments: Array(CommandLine.arguments.dropFirst()))
    try run(options: options)
} catch {
    fputs("BLOCKER: \(error)\n", stderr)
    exit(2)
}
