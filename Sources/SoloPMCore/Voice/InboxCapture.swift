import Foundation

public enum InboxCaptureSourceKind: String, Codable, Equatable, Sendable {
    case voiceMemo = "voice_memo"
}

public enum InboxCaptureClassificationStatus: String, Codable, Equatable, Sendable {
    case unclassified
    case classified
    case dismissed
}

public enum InboxCaptureTranscriptionStatus: String, Codable, Equatable, Sendable {
    case pending
    case succeeded
    case failed
}

public struct InboxCaptureRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: Int64
    public var taskID: Int64
    public var sourceKind: InboxCaptureSourceKind
    public var audioFilePath: String
    public var durationSeconds: Double
    public var transcript: String?
    public var interpretationSummary: String?
    public var memo: String?
    public var classificationStatus: InboxCaptureClassificationStatus
    public var transcriptionStatus: InboxCaptureTranscriptionStatus
    public var createdAt: String

    public init(
        id: Int64,
        taskID: Int64,
        sourceKind: InboxCaptureSourceKind,
        audioFilePath: String,
        durationSeconds: Double,
        transcript: String?,
        interpretationSummary: String?,
        memo: String?,
        classificationStatus: InboxCaptureClassificationStatus,
        transcriptionStatus: InboxCaptureTranscriptionStatus,
        createdAt: String
    ) {
        self.id = id
        self.taskID = taskID
        self.sourceKind = sourceKind
        self.audioFilePath = audioFilePath
        self.durationSeconds = durationSeconds
        self.transcript = transcript
        self.interpretationSummary = interpretationSummary
        self.memo = memo
        self.classificationStatus = classificationStatus
        self.transcriptionStatus = transcriptionStatus
        self.createdAt = createdAt
    }

    public var retryTranscriptionActionTitle: String? {
        transcriptionStatus == .failed ? "Retry Transcription" : nil
    }

    public var durationLabel: String {
        let rounded = Int(durationSeconds.rounded())
        return "\(rounded)s"
    }
}

public struct InboxVoiceCaptureDraft: Equatable, Sendable {
    public var taskID: Int64
    public var audioFilePath: String
    public var durationSeconds: Double
    public var transcript: String?
    public var interpretationSummary: String?
    public var memo: String?
    public var classificationStatus: InboxCaptureClassificationStatus
    public var transcriptionStatus: InboxCaptureTranscriptionStatus
    public var createdAt: String?

    public init(
        taskID: Int64,
        audioFilePath: String,
        durationSeconds: Double,
        transcript: String?,
        interpretationSummary: String?,
        memo: String?,
        classificationStatus: InboxCaptureClassificationStatus = .unclassified,
        transcriptionStatus: InboxCaptureTranscriptionStatus = .pending,
        createdAt: String? = nil
    ) {
        self.taskID = taskID
        self.audioFilePath = audioFilePath
        self.durationSeconds = durationSeconds
        self.transcript = transcript
        self.interpretationSummary = interpretationSummary
        self.memo = memo
        self.classificationStatus = classificationStatus
        self.transcriptionStatus = transcriptionStatus
        self.createdAt = createdAt
    }
}

public enum InboxCaptureStoreError: Error, Equatable, Sendable {
    case notFound(Int64)
    case emptyAudioFilePath
    case invalidDuration
    case linkedTaskMissing
    case invalidStoredValue(column: String, value: String)

    public static func userMessage(for error: Error) -> String {
        if let storeError = error as? InboxCaptureStoreError {
            switch storeError {
            case .emptyAudioFilePath:
                return "Inbox capture could not be saved. Audio storage is not configured."
            case .invalidDuration:
                return "Inbox capture could not be saved. Recording duration is invalid."
            case .linkedTaskMissing:
                return "Inbox capture could not be saved. Confirm the linked Inbox task still exists."
            case .notFound:
                return "Inbox capture is no longer available."
            case .invalidStoredValue:
                return "Local Inbox capture data needs repair. Restore from backup or repair the local database, then reopen SoloPM."
            }
        }

        switch error {
        case DatabaseError.executeFailed:
            return "Inbox capture could not be saved. Confirm the linked Inbox task still exists."
        default:
            return "Inbox capture could not be saved."
        }
    }
}

public protocol InboxCaptureStore {
    func createVoiceCapture(_ draft: InboxVoiceCaptureDraft) throws -> InboxCaptureRecord
    func get(id: Int64) throws -> InboxCaptureRecord
    func list(taskID: Int64) throws -> [InboxCaptureRecord]
    func list(taskIDs: Set<Int64>) throws -> [Int64: [InboxCaptureRecord]]
    func updateMemo(id: Int64, memo: String?) throws -> InboxCaptureRecord
    func relinkCaptures(fromTaskID: Int64, toTaskID: Int64) throws -> Int
    func delete(id: Int64) throws
}

public final class SQLiteInboxCaptureStore: InboxCaptureStore, @unchecked Sendable {
    private let connection: SQLiteConnection
    private let lock = NSLock()

    public init(connection: SQLiteConnection) {
        self.connection = connection
    }

    public convenience init(path: String, migrations: [DatabaseMigration] = CoreMigrations.current) throws {
        let connection = try SQLiteConnection(path: path)
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: migrations)
        self.init(connection: connection)
    }

    @discardableResult
    public func createVoiceCapture(_ draft: InboxVoiceCaptureDraft) throws -> InboxCaptureRecord {
        let normalizedPath = try requiredTrimmedPath(draft.audioFilePath)
        guard draft.durationSeconds >= 0, draft.durationSeconds.isFinite else {
            throw InboxCaptureStoreError.invalidDuration
        }

        lock.lock()
        defer { lock.unlock() }

        do {
            try connection.execute(
                """
                INSERT INTO inbox_capture_records (
                  task_id,
                  source_kind,
                  audio_file_path,
                  duration_seconds,
                  transcript,
                  interpretation_summary,
                  memo,
                  classification_status,
                  transcription_status,
                  created_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, COALESCE(?, CURRENT_TIMESTAMP));
                """,
                parameters: [
                    .integer(draft.taskID),
                    .text(InboxCaptureSourceKind.voiceMemo.rawValue),
                    .text(normalizedPath),
                    .real(draft.durationSeconds),
                    SQLiteValue(draft.transcript),
                    SQLiteValue(draft.interpretationSummary),
                    SQLiteValue(draft.memo),
                    .text(draft.classificationStatus.rawValue),
                    .text(draft.transcriptionStatus.rawValue),
                    SQLiteValue(draft.createdAt)
                ]
            )
        } catch DatabaseError.executeFailed, DatabaseError.stepFailed {
            throw InboxCaptureStoreError.linkedTaskMissing
        }

        return try getLocked(id: connection.lastInsertedRowID)
    }

    public func get(id: Int64) throws -> InboxCaptureRecord {
        lock.lock()
        defer { lock.unlock() }

        return try getLocked(id: id)
    }

    public func list(taskID: Int64) throws -> [InboxCaptureRecord] {
        lock.lock()
        defer { lock.unlock() }

        return try connection.queryRows(
            """
            SELECT * FROM inbox_capture_records
            WHERE task_id = ?
            ORDER BY id DESC;
            """,
            parameters: [.integer(taskID)]
        ).map(Self.record(row:))
    }

    public func list(taskIDs: Set<Int64>) throws -> [Int64: [InboxCaptureRecord]] {
        guard !taskIDs.isEmpty else {
            return [:]
        }

        lock.lock()
        defer { lock.unlock() }

        let sortedTaskIDs = taskIDs.sorted()
        let placeholders = Array(repeating: "?", count: sortedTaskIDs.count).joined(separator: ", ")
        let rows = try connection.queryRows(
            """
            SELECT * FROM inbox_capture_records
            WHERE task_id IN (\(placeholders))
            ORDER BY task_id ASC, id DESC;
            """,
            parameters: sortedTaskIDs.map(SQLiteValue.integer)
        ).map(Self.record(row:))
        var recordsByTaskID = Dictionary(uniqueKeysWithValues: taskIDs.map { ($0, [InboxCaptureRecord]()) })
        for row in rows {
            recordsByTaskID[row.taskID, default: []].append(row)
        }
        return recordsByTaskID
    }

    @discardableResult
    public func updateMemo(id: Int64, memo: String?) throws -> InboxCaptureRecord {
        lock.lock()
        defer { lock.unlock() }

        _ = try getLocked(id: id)
        let normalizedMemo = Self.normalizedOptionalMemo(memo)
        // Empty notes are stored as NULL so filters and review summaries do not
        // have to treat whitespace as meaningful user context.
        try connection.execute(
            """
            UPDATE inbox_capture_records
            SET memo = ?,
                updated_at = CURRENT_TIMESTAMP
            WHERE id = ?;
            """,
            parameters: [SQLiteValue(normalizedMemo), .integer(id)]
        )
        return try getLocked(id: id)
    }

    @discardableResult
    public func relinkCaptures(fromTaskID: Int64, toTaskID: Int64) throws -> Int {
        lock.lock()
        defer { lock.unlock() }

        let count = try connection.queryRows(
            "SELECT COUNT(*) AS count FROM inbox_capture_records WHERE task_id = ?;",
            parameters: [.integer(fromTaskID)]
        ).first?["count"].flatMap(Int.init) ?? 0
        guard count > 0 else {
            return 0
        }

        do {
            try connection.execute(
                """
                UPDATE inbox_capture_records
                SET task_id = ?,
                    updated_at = CURRENT_TIMESTAMP
                WHERE task_id = ?;
                """,
                parameters: [.integer(toTaskID), .integer(fromTaskID)]
            )
        } catch DatabaseError.executeFailed, DatabaseError.stepFailed {
            throw InboxCaptureStoreError.linkedTaskMissing
        }

        return count
    }

    public func delete(id: Int64) throws {
        lock.lock()
        defer { lock.unlock() }

        _ = try getLocked(id: id)
        try connection.execute("DELETE FROM inbox_capture_records WHERE id = ?;", parameters: [.integer(id)])
    }

    private func getLocked(id: Int64) throws -> InboxCaptureRecord {
        guard let row = try connection.queryRows(
            "SELECT * FROM inbox_capture_records WHERE id = ? LIMIT 1;",
            parameters: [.integer(id)]
        ).first else {
            throw InboxCaptureStoreError.notFound(id)
        }

        return try Self.record(row: row)
    }

    private func requiredTrimmedPath(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw InboxCaptureStoreError.emptyAudioFilePath
        }
        return trimmed
    }

    private static func record(row: [String: String]) throws -> InboxCaptureRecord {
        let sourceKind = try enumValue(
            InboxCaptureSourceKind.self,
            rawValue: requiredString(row["source_kind"], column: "inbox_capture_records.source_kind"),
            column: "inbox_capture_records.source_kind"
        )
        let classificationStatus = try enumValue(
            InboxCaptureClassificationStatus.self,
            rawValue: requiredString(row["classification_status"], column: "inbox_capture_records.classification_status"),
            column: "inbox_capture_records.classification_status"
        )
        let transcriptionStatus = try enumValue(
            InboxCaptureTranscriptionStatus.self,
            rawValue: requiredString(row["transcription_status"], column: "inbox_capture_records.transcription_status"),
            column: "inbox_capture_records.transcription_status"
        )

        return InboxCaptureRecord(
            id: try requiredInt64(row["id"], column: "inbox_capture_records.id"),
            taskID: try requiredInt64(row["task_id"], column: "inbox_capture_records.task_id"),
            sourceKind: sourceKind,
            audioFilePath: try requiredString(row["audio_file_path"], column: "inbox_capture_records.audio_file_path"),
            durationSeconds: try requiredDouble(row["duration_seconds"], column: "inbox_capture_records.duration_seconds"),
            transcript: nilIfEmpty(row["transcript"]),
            interpretationSummary: nilIfEmpty(row["interpretation_summary"]),
            memo: nilIfEmpty(row["memo"]),
            classificationStatus: classificationStatus,
            transcriptionStatus: transcriptionStatus,
            createdAt: try requiredString(row["created_at"], column: "inbox_capture_records.created_at")
        )
    }

    private static func enumValue<Value: RawRepresentable>(
        _ type: Value.Type,
        rawValue: String,
        column: String
    ) throws -> Value where Value.RawValue == String {
        guard let value = Value(rawValue: rawValue) else {
            throw InboxCaptureStoreError.invalidStoredValue(column: column, value: rawValue)
        }
        return value
    }

    private static func requiredString(_ value: String?, column: String) throws -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw InboxCaptureStoreError.invalidStoredValue(column: column, value: "")
        }
        return value
    }

    private static func requiredInt64(_ value: String?, column: String) throws -> Int64 {
        let required = try requiredString(value, column: column)
        guard let int = Int64(required) else {
            throw InboxCaptureStoreError.invalidStoredValue(column: column, value: required)
        }
        return int
    }

    private static func requiredDouble(_ value: String?, column: String) throws -> Double {
        let required = try requiredString(value, column: column)
        guard let double = Double(required), double.isFinite else {
            throw InboxCaptureStoreError.invalidStoredValue(column: column, value: required)
        }
        return double
    }

    private static func nilIfEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func normalizedOptionalMemo(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

}

@MainActor
public struct InboxVoiceCaptureResult: Equatable, Sendable {
    public var task: ProjectBoardTask
    public var capture: InboxCaptureRecord
    public var transcriptionErrorMessage: String?

    public init(task: ProjectBoardTask, capture: InboxCaptureRecord, transcriptionErrorMessage: String? = nil) {
        self.task = task
        self.capture = capture
        self.transcriptionErrorMessage = transcriptionErrorMessage
    }
}

@MainActor
public protocol InboxVoiceCaptureSaving: AnyObject {
    func saveTranscribedCapture(
        audio: RecordedAudio,
        transcript: STTTranscript?,
        transcriptionErrorMessage: String?,
        at date: Date,
        createdAt: String?
    ) throws -> InboxVoiceCaptureResult
}

@MainActor
public final class InboxVoiceCaptureService: InboxVoiceCaptureSaving {
    private var audioRecorder: any AudioRecorder
    private let sttProvider: any SpeechToTextProvider
    private let projectBoardStore: any ProjectBoardStore
    private let inboxCaptureStore: any InboxCaptureStore
    private let commandRouter: any VoiceCommandRouting

    public init(
        audioRecorder: any AudioRecorder,
        sttProvider: any SpeechToTextProvider,
        projectBoardStore: any ProjectBoardStore,
        inboxCaptureStore: any InboxCaptureStore,
        commandRouter: any VoiceCommandRouting = VoiceCommandRouter()
    ) {
        self.audioRecorder = audioRecorder
        self.sttProvider = sttProvider
        self.projectBoardStore = projectBoardStore
        self.inboxCaptureStore = inboxCaptureStore
        self.commandRouter = commandRouter
    }

    public func startRecording(at date: Date = Date()) async throws {
        try await audioRecorder.start(at: date)
    }

    public func stopAndSave(
        outputURL: URL,
        at date: Date = Date(),
        createdAt: String? = nil
    ) async throws -> InboxVoiceCaptureResult {
        let audio = try audioRecorder.stop(outputURL: outputURL, at: date)
        let transcription = await transcribe(audio)
        return try saveTranscribedCapture(
            audio: audio,
            transcript: transcription.transcript,
            transcriptionErrorMessage: transcription.errorMessage,
            at: date,
            createdAt: createdAt
        )
    }

    public func saveTranscribedCapture(
        audio: RecordedAudio,
        transcript: STTTranscript?,
        transcriptionErrorMessage: String? = nil,
        at date: Date = Date(),
        createdAt: String? = nil
    ) throws -> InboxVoiceCaptureResult {
        let title = normalizedTranscriptText(transcript)
        let interpretation = makeInterpretation(for: title)
        let captureCreatedAt = createdAt ?? ISO8601DateFormatter().string(from: date)
        let task = try projectBoardStore.createInboxTask(title: title?.isEmpty == false ? title! : "Voice memo")
        let transcriptionStatus: InboxCaptureTranscriptionStatus = title == nil ? .failed : .succeeded
        let capture = try inboxCaptureStore.createVoiceCapture(InboxVoiceCaptureDraft(
            taskID: task.id,
            audioFilePath: audio.fileURL.path,
            durationSeconds: audio.duration ?? transcript?.duration ?? 0,
            transcript: title,
            interpretationSummary: interpretation?.summary,
            memo: interpretation?.memo,
            classificationStatus: .unclassified,
            transcriptionStatus: transcriptionStatus,
            createdAt: captureCreatedAt
        ))

        return InboxVoiceCaptureResult(
            task: task,
            capture: capture,
            transcriptionErrorMessage: transcriptionErrorMessage
        )
    }

    private func transcribe(_ audio: RecordedAudio) async -> (transcript: STTTranscript?, errorMessage: String?) {
        do {
            return (try await sttProvider.transcribe(audio), nil)
        } catch {
            return (nil, sanitizedTranscriptionMessage(error))
        }
    }

    private func makeInterpretation(for transcript: String?) -> (summary: String, memo: String)? {
        guard let transcript,
              !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let route = commandRouter.route(transcript: transcript)
        let summary = ExecutionReceiptRedactor()
            .redact(route.interpretationSummary)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else {
            return nil
        }
        return (
            summary,
            String(format: "Confidence: %.2f", route.confidence)
        )
    }

    private func normalizedTranscriptText(_ transcript: STTTranscript?) -> String? {
        guard let text = transcript?.text.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }
        return text
    }

    private func sanitizedTranscriptionMessage(_ error: Error) -> String {
        // Voice capture failures may include local audio paths. Keep the visible
        // message useful for retry decisions while avoiding transcript or file
        // path leakage into UI logs and planning audit surfaces.
        let sanitized = UserFacingErrorMessageSanitizer.message(from: error)
        return sanitized
            .replacingOccurrences(
                of: #"/[^\s,]+"#,
                with: "[REDACTED_PATH]",
                options: .regularExpression
            )
    }
}
