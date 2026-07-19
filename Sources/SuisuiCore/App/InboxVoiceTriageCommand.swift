import Foundation

public enum InboxVoiceTriageCommandAction: Equatable, Sendable {
    case selectNext
    case scheduleToday
    case reviewLater
    case complete
    case undo
    case setPriority(ProjectTaskPriority)

    public var accessibilityLabel: String {
        switch self {
        case .selectNext:
            "Next Inbox item"
        case .scheduleToday:
            "Schedule selected Inbox item for today"
        case .reviewLater:
            "Review selected Inbox item later"
        case .complete:
            "Complete selected Inbox item"
        case .undo:
            "Undo last Inbox triage action"
        case .setPriority(let priority):
            "Set selected Inbox item priority to \(priority.label)"
        }
    }
}

public struct InboxVoiceTriageCommand: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var action: InboxVoiceTriageCommandAction
    public var sourceTranscript: String

    public init(
        id: UUID = UUID(),
        action: InboxVoiceTriageCommandAction,
        sourceTranscript: String
    ) {
        self.id = id
        self.action = action
        self.sourceTranscript = sourceTranscript
    }
}

public struct InboxVoiceTriageCommandParser: Sendable {
    public init() {}

    public func parse(_ transcript: String) -> InboxVoiceTriageCommand? {
        let normalized = Self.normalized(transcript)
        guard !normalized.isEmpty else {
            return nil
        }

        guard let action = Self.actionAliases[normalized] else {
            return nil
        }

        return InboxVoiceTriageCommand(
            action: action,
            sourceTranscript: transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    public func parseVoiceCommand(_ transcript: String) -> InboxVoiceTriageCommand? {
        let normalized = Self.normalized(transcript)
        guard !normalized.isEmpty else {
            return nil
        }

        for contextPrefix in Self.voiceCommandContextPrefixes {
            guard normalized.hasPrefix(contextPrefix) else {
                continue
            }

            let actionText = String(normalized.dropFirst(contextPrefix.count))
            guard !actionText.isEmpty, let action = Self.actionAliases[actionText] else {
                continue
            }

            return InboxVoiceTriageCommand(
                action: action,
                sourceTranscript: transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return nil
    }

    private static let voiceCommandContextPrefixes = [
        "inboxtriage",
        "inbox",
        "triage",
        "インボックス",
        "仕分け"
    ]

    private static let actionAliases: [String: InboxVoiceTriageCommandAction] = [
        "next": .selectNext,
        "nextitem": .selectNext,
        "nextinbox": .selectNext,
        "次": .selectNext,
        "次へ": .selectNext,
        "次のタスク": .selectNext,
        "次のインボックス": .selectNext,
        "today": .scheduleToday,
        "dotoday": .scheduleToday,
        "scheduletoday": .scheduleToday,
        "fortoday": .scheduleToday,
        "今日": .scheduleToday,
        "今日やる": .scheduleToday,
        "今日にする": .scheduleToday,
        "今日にして": .scheduleToday,
        "今日へ": .scheduleToday,
        "later": .reviewLater,
        "reviewlater": .reviewLater,
        "defer": .reviewLater,
        "deferlater": .reviewLater,
        "後で": .reviewLater,
        "あとで": .reviewLater,
        "後で見る": .reviewLater,
        "あとで見る": .reviewLater,
        "後回し": .reviewLater,
        "done": .complete,
        "complete": .complete,
        "completed": .complete,
        "finish": .complete,
        "完了": .complete,
        "終わり": .complete,
        "終わった": .complete,
        "済み": .complete,
        "undo": .undo,
        "revert": .undo,
        "取り消し": .undo,
        "取消": .undo,
        "元に戻す": .undo,
        "やり直し": .undo,
        "high": .setPriority(.high),
        "highpriority": .setPriority(.high),
        "priorityhigh": .setPriority(.high),
        "優先度高": .setPriority(.high),
        "高優先度": .setPriority(.high),
        "高": .setPriority(.high),
        "medium": .setPriority(.medium),
        "mediumpriority": .setPriority(.medium),
        "prioritymedium": .setPriority(.medium),
        "優先度中": .setPriority(.medium),
        "中優先度": .setPriority(.medium),
        "中": .setPriority(.medium),
        "low": .setPriority(.low),
        "lowpriority": .setPriority(.low),
        "prioritylow": .setPriority(.low),
        "優先度低": .setPriority(.low),
        "低優先度": .setPriority(.low),
        "低": .setPriority(.low)
    ]

    private static func normalized(_ transcript: String) -> String {
        // Short voice commands are intentionally allow-listed. Free-form
        // matching would make a command fast, but it would also turn unrelated
        // planning speech into local task mutations.
        transcript
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .filter { !$0.isWhitespace && !$0.isPunctuation }
    }
}
