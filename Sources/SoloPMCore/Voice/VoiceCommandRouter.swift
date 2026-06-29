import Foundation

public enum VoiceCommandIntent: String, Codable, CaseIterable, Equatable, Sendable {
    case task
    case schedule
    case document
    case execution
    case unknown
}

public enum VoiceCommandDisposition: String, Codable, Equatable, Sendable {
    case routed
    case needsClarification
}

public struct VoiceCommandRoute: Codable, Equatable, Sendable {
    public var utterance: String
    public var intent: VoiceCommandIntent
    public var disposition: VoiceCommandDisposition

    public init(
        utterance: String,
        intent: VoiceCommandIntent,
        disposition: VoiceCommandDisposition
    ) {
        self.utterance = utterance
        self.intent = intent
        self.disposition = disposition
    }
}

public struct VoiceCommandRouter: Sendable {
    public init() {}

    public func route(_ utterance: String) -> VoiceCommandRoute {
        let normalized = utterance.voiceCommandNormalized
        guard !normalized.isEmpty else {
            return VoiceCommandRoute(
                utterance: utterance,
                intent: .unknown,
                disposition: .needsClarification
            )
        }

        let matches = VoiceCommandIntent.allCases
            .filter { $0 != .unknown }
            .map { intent in
                IntentMatch(intent: intent, score: score(for: intent, normalizedUtterance: normalized))
            }
            .filter { $0.score > 0 }
            .sorted {
                if $0.score == $1.score {
                    return $0.intent.rawValue < $1.intent.rawValue
                }
                return $0.score > $1.score
            }

        guard let strongest = matches.first else {
            return VoiceCommandRoute(
                utterance: utterance,
                intent: .unknown,
                disposition: .needsClarification
            )
        }

        let nextStrongestScore = matches.dropFirst().first?.score ?? 0

        // Spoken commands frequently mix time and document words. Require a
        // real score margin so ambiguous requests fall into clarification
        // instead of drifting into the execution or mutation lanes.
        if strongest.score - nextStrongestScore <= 1 {
            return VoiceCommandRoute(
                utterance: utterance,
                intent: .unknown,
                disposition: .needsClarification
            )
        }

        return VoiceCommandRoute(
            utterance: utterance,
            intent: strongest.intent,
            disposition: .routed
        )
    }

    private func score(for intent: VoiceCommandIntent, normalizedUtterance: String) -> Int {
        switch intent {
        case .task:
            return score(
                normalizedUtterance,
                weightedSignals: [
                    ("create a task", 5),
                    ("taskを作", 5),
                    ("タスクを作", 5),
                    ("todo", 4),
                    ("to do", 4),
                    ("task", 3),
                    ("タスク", 3),
                    ("follow up", 2),
                    ("やること", 2),
                    ("作業", 2)
                ]
            )
        case .schedule:
            return score(
                normalizedUtterance,
                weightedSignals: [
                    ("schedule a", 5),
                    ("予定して", 5),
                    ("カレンダー", 4),
                    ("calendar", 4),
                    ("1on1", 4),
                    ("meeting", 3),
                    ("会議", 3),
                    ("work block", 3),
                    ("予定", 3),
                    ("明日", 1),
                    ("tomorrow", 1),
                    ("friday", 1),
                    ("午後", 1),
                    ("pm", 1)
                ]
            )
        case .document:
            return score(
                normalizedUtterance,
                weightedSignals: [
                    ("draft release notes", 5),
                    ("release notes", 4),
                    ("meeting notes", 4),
                    ("progress memo", 4),
                    ("メモをまとめ", 5),
                    ("議事録", 4),
                    ("資料", 3),
                    ("document", 3),
                    ("docs", 3),
                    ("メモ", 3),
                    ("ノート", 3),
                    ("下書き", 3),
                    ("まとめて", 2)
                ]
            )
        case .execution:
            return executionScore(for: normalizedUtterance)
        case .unknown:
            return 0
        }
    }

    private func executionScore(for normalizedUtterance: String) -> Int {
        let runSignals = [
            "run",
            "execute",
            "launch",
            "start",
            "走らせて",
            "実行",
            "開始"
        ]
        let approvalSignals = [
            "approved",
            "approval",
            "reviewed",
            "承認済み",
            "承認された",
            "レビュー済み"
        ]
        let planSignals = [
            "plan",
            "workspace",
            "local command",
            "execution plan",
            "プラン",
            "ワークスペース",
            "ローカル実行"
        ]

        let hasRunSignal = normalizedUtterance.containsAny(runSignals)
        let hasApprovalSignal = normalizedUtterance.containsAny(approvalSignals)
        let hasPlanSignal = normalizedUtterance.containsAny(planSignals)

        // Execution must stay conservative: a bare "run it" is too vague for
        // write-capable automation, so require either an approval or a concrete
        // plan/workspace signal before routing into the execution lane.
        guard hasRunSignal, hasApprovalSignal || hasPlanSignal else {
            return 0
        }

        var score = 0
        if hasRunSignal {
            score += 2
        }
        if hasApprovalSignal {
            score += 3
        }
        if hasPlanSignal {
            score += 2
        }

        if normalizedUtterance.contains("approved plan")
            || normalizedUtterance.contains("run the approved")
            || normalizedUtterance.contains("承認済みの実行")
            || normalizedUtterance.contains("承認済みのプラン") {
            score += 2
        }

        return score
    }

    private func score(_ normalizedUtterance: String, weightedSignals: [(String, Int)]) -> Int {
        weightedSignals.reduce(into: 0) { partialResult, entry in
            if normalizedUtterance.contains(entry.0.voiceCommandNormalized) {
                partialResult += entry.1
            }
        }
    }
}

private struct IntentMatch: Equatable, Sendable {
    var intent: VoiceCommandIntent
    var score: Int
}

private extension String {
    var voiceCommandNormalized: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func containsAny(_ candidates: [String]) -> Bool {
        candidates.contains { contains($0.voiceCommandNormalized) }
    }
}
