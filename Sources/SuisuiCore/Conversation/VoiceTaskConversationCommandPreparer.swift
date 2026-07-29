import Foundation

public struct VoiceTaskConversationPreparedBegin: Sendable {
    public let requiredSlots: [ClarificationSlot]
    public let intents: [ConversationTaskIntent]
    public let referenceRequest: VoiceTaskReferenceRequest?
    public let localAnswerItems: [VoiceTaskConversationAnswerItem]

    public init(
        requiredSlots: [ClarificationSlot] = [],
        intents: [ConversationTaskIntent],
        referenceRequest: VoiceTaskReferenceRequest? = nil,
        localAnswerItems: [VoiceTaskConversationAnswerItem] = []
    ) {
        self.requiredSlots = requiredSlots
        self.intents = intents
        self.referenceRequest = referenceRequest
        self.localAnswerItems = localAnswerItems
    }
}

public protocol VoiceTaskConversationCommandPreparing: Sendable {
    func prepare(
        transcript: String,
        sessionID: UUID,
        sourceTurnID: UUID,
        selectedProjectID: Int64?,
        selectedTaskID: Int64?,
        at date: Date
    ) throws -> VoiceTaskConversationPreparedBegin?
}

/// Builds only deterministic Task operations. Unrecognized language returns
/// `nil` so the existing provider planner remains the explicit fallback.
public final class SQLiteVoiceTaskConversationCommandPreparer:
    VoiceTaskConversationCommandPreparing,
    @unchecked Sendable
{
    private let taskStore: SQLiteTaskStore
    private let projectStore: SQLiteProjectStore
    private let conversationStore: SQLiteVoiceTaskConversationStore

    public init(
        taskStore: SQLiteTaskStore,
        projectStore: SQLiteProjectStore,
        conversationStore: SQLiteVoiceTaskConversationStore
    ) {
        self.taskStore = taskStore
        self.projectStore = projectStore
        self.conversationStore = conversationStore
    }

    public func prepare(
        transcript: String,
        sessionID: UUID,
        sourceTurnID: UUID,
        selectedProjectID: Int64?,
        selectedTaskID: Int64?,
        at date: Date
    ) throws -> VoiceTaskConversationPreparedBegin? {
        let normalized = transcript
            .folding(
                options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
        let visibleProjectIDs = Set(
            try projectStore.list().map(\.id)
        )
        let tasks = try taskStore.listAll()
            .filter { task in
                task.status != "completed"
                    && task.projectID.map(visibleProjectIDs.contains) ?? true
                    && selectedProjectID.map { task.projectID == $0 } ?? true
            }
            .sorted { $0.id < $1.id }
        let candidates = tasks.map {
            ConversationReferenceCandidate(
                target: .task(id: $0.id, projectID: $0.projectID),
                title: $0.title,
                stableSortKey: String(format: "%020lld", $0.id)
            )
        }

        if isTaskListRequest(normalized) {
            try persistListReferenceSet(
                transcript: transcript,
                sessionID: sessionID,
                sourceTurnID: sourceTurnID,
                tasks: tasks,
                candidates: candidates,
                at: date
            )
            return VoiceTaskConversationPreparedBegin(
                intents: [
                    ConversationTaskIntent(
                        utterance: transcript,
                        operation: .list,
                        tool: .taskList,
                        arguments: selectedProjectID.map {
                            ["projectId": .number(Double($0))]
                        } ?? [:],
                        summary: "List current tasks"
                    )
                ],
                localAnswerItems: tasks.map {
                    VoiceTaskConversationAnswerItem(
                        id: "task:\($0.id)",
                        label: $0.title
                    )
                }
            )
        }

        guard let priority = requestedPriority(in: normalized),
              requestsDueDateChange(normalized),
              refersToTask(normalized)
        else {
            return nil
        }

        let references = try conversationStore.listReferences(
            sessionID: sessionID,
            limit: 500
        )
        let latestSourceTurnID = references.first?.sourceTurnID
        let latestReferences = references.filter {
            $0.sourceTurnID == latestSourceTurnID
        }
        let fingerprint = latestReferences.first?.orderingFingerprint
        let ordinal = requestedOrdinal(in: normalized)
        let ordinalReference = ordinal.flatMap { requested in
            latestReferences.first { $0.ordinal == requested }
        }
        let selectedTask = selectedTaskID.flatMap { id in
            tasks.first(where: { $0.id == id }).map {
                ConversationResolvedTarget.task(
                    id: $0.id,
                    projectID: $0.projectID
                )
            }
        }
        let selectedProject = selectedProjectID.map(
            ConversationResolvedTarget.project
        )
        var arguments: [String: JSONValue] = [
            "priority": .string(priority),
        ]
        let dueDate = isoDate(in: normalized)
        if let dueDate {
            arguments["dueAt"] = .string(dueDate)
        }
        let intent = ConversationTaskIntent(
            utterance: transcript,
            operation: .updateDueDate,
            tool: .taskUpdate,
            arguments: arguments,
            summary: "Update task due date and priority"
        )
        return VoiceTaskConversationPreparedBegin(
            requiredSlots: dueDate == nil ? [.dueDate] : [],
            intents: [intent],
            referenceRequest: VoiceTaskReferenceRequest(
                sessionID: sessionID,
                utterance: transcript,
                selectedTask: selectedTask,
                selectedProject: selectedProject,
                ordinalReference: ordinalReference,
                candidateOrderingFingerprint: fingerprint,
                candidates: candidates
            )
        )
    }

    private func persistListReferenceSet(
        transcript: String,
        sessionID: UUID,
        sourceTurnID: UUID,
        tasks: [TaskRecord],
        candidates: [ConversationReferenceCandidate],
        at date: Date
    ) throws {
        if try conversationStore.loadSession(id: sessionID) == nil {
            try conversationStore.createSession(
                VoiceTaskConversationSession(
                    id: sessionID,
                    title: "Voice task conversation",
                    entryPoint: .voiceCommand,
                    createdAt: date
                )
            )
        }
        let turn = try VoiceTaskConversationTurn(
            id: sourceTurnID,
            sessionID: sessionID,
            author: .user,
            rawTranscript: nil,
            userConfirmedText: transcript,
            createdAt: date
        )
        let fingerprint = VoiceTaskReferenceResolver.orderingFingerprint(
            for: candidates
        )
        let references = try tasks.enumerated().map { ordinal, task in
            try ConversationReference(
                    sessionID: sessionID,
                    target: .task(task.id),
                    sourceTurnID: sourceTurnID,
                    ordinal: ordinal,
                    orderingFingerprint: fingerprint,
                    expiresAt: date.addingTimeInterval(24 * 60 * 60),
                    createdAt: date
                )
        }
        try conversationStore.saveTurnAndReferences(
            turn: turn,
            references: references
        )
    }

    private func isTaskListRequest(_ text: String) -> Bool {
        text.contains("task list")
            || text.contains("list tasks")
            || text.contains("show tasks")
            || text.contains("タスク一覧")
            || text.contains("タスクを一覧")
            || text.contains("タスクを見せ")
    }

    private func requestsDueDateChange(_ text: String) -> Bool {
        text.contains("due")
            || text.contains("deadline")
            || text.contains("期限")
            || text.contains("締切")
    }

    private func refersToTask(_ text: String) -> Bool {
        text.contains("task")
            || text.contains("タスク")
            || text.contains("それ")
            || text.contains("that")
            || requestedOrdinal(in: text) != nil
    }

    private func requestedPriority(in text: String) -> String? {
        if text.contains("high priority")
            || text.contains("priority high")
            || text.contains("優先度を高")
            || text.contains("優先度高")
        {
            return "high"
        }
        if text.contains("medium priority")
            || text.contains("priority medium")
            || text.contains("優先度を中")
            || text.contains("優先度中")
        {
            return "medium"
        }
        if text.contains("low priority")
            || text.contains("priority low")
            || text.contains("優先度を低")
            || text.contains("優先度低")
        {
            return "low"
        }
        return nil
    }

    private func requestedOrdinal(in text: String) -> Int? {
        let tokens: [(String, Int)] = [
            ("first", 0), ("1st", 0), ("一つ目", 0), ("1つ目", 0),
            ("second", 1), ("2nd", 1), ("二つ目", 1), ("2つ目", 1),
            ("third", 2), ("3rd", 2), ("三つ目", 2), ("3つ目", 2),
        ]
        return tokens.first { text.contains($0.0) }?.1
    }

    private func isoDate(in text: String) -> String? {
        let pattern = #"\b\d{4}-\d{2}-\d{2}\b"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ),
              let range = Range(match.range, in: text)
        else {
            return nil
        }
        return String(text[range])
    }
}
