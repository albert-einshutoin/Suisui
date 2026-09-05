import Foundation

enum VoiceDailyPlanningActionDraftClassifier {
    static func requestedKind(
        from route: VoiceCommandRoutingResult
    ) -> DailyPlanningActionDraftKind? {
        let folded = route.normalizedTranscript
            .folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        let requestsStart = containsAnyExplicitPhrase(
            [
                "start recommended",
                "start the recommended",
                "begin recommended",
                "begin the recommended",
                "おすすめを開始",
                "おすすめを始め",
                "おすすめに着手",
                "推奨タスクを開始",
                "推奨タスクを始め",
                "推奨タスクに着手"
            ],
            in: folded
        )
        let requestsDefer = containsAnyExplicitPhrase(
            [
                "defer recommended to tomorrow",
                "defer recommended task",
                "defer the recommended task",
                "defer the recommended task to tomorrow",
                "move recommended to tomorrow",
                "move recommended task to tomorrow",
                "move the recommended task to tomorrow",
                "おすすめを明日に回",
                "おすすめを明日へ",
                "おすすめを延期",
                "推奨タスクを明日に回",
                "推奨タスクを明日へ",
                "推奨タスクを延期"
            ],
            in: folded
        )
        let requestsReschedule = containsAnyExplicitPhrase(
            [
                "reschedule recommended to today",
                "reschedule recommended task to today",
                "reschedule the recommended task to today",
                "move recommended to today",
                "move recommended task to today",
                "move the recommended task to today",
                "おすすめを今日にリスケ",
                "おすすめを今日へリスケ",
                "おすすめを今日に移動",
                "おすすめを今日へ移動",
                "推奨タスクを今日にリスケ",
                "推奨タスクを今日へリスケ",
                "推奨タスクを今日に移動",
                "推奨タスクを今日へ移動"
            ],
            in: folded
        )
        let requestsSplit = containsAnyExplicitPhrase(
            [
                "split recommended",
                "split recommended task",
                "split the recommended task",
                "break down recommended",
                "break down recommended task",
                "break down the recommended task",
                "おすすめを分割",
                "おすすめを分け",
                "おすすめを細分化",
                "推奨タスクを分割",
                "推奨タスクを分け",
                "推奨タスクを細分化"
            ],
            in: folded
        )
        let rejectsAction = containsAny(
            ["do not", "don't", "dont", "not start", "not defer", "not reschedule", "not split", "cancel", "しない", "始めない", "開始しない", "延期しない", "リスケしない", "分割しない", "分けない", "やめ"],
            in: folded
        )
        let asksForAdvice = containsAnyExplicitPhrase(
            ["should i", "should we", "whether", "do you think", "is it better"],
            in: folded
        ) || containsAny(
            ["すべき", "べきか", "するか", "回すか", "確認して", "相談", "どう思"],
            in: folded
        )

        // Voice Daily Planning may prefill an approval item, but ambiguous
        // phrases must stay as a read-only review so the assistant never turns
        // a vague planning prompt into a write-capable Queue action.
        let requestedKinds = [
            (requestsStart, DailyPlanningActionDraftKind.startRecommended),
            (requestsDefer, DailyPlanningActionDraftKind.deferRecommendedToTomorrow),
            (requestsReschedule, DailyPlanningActionDraftKind.moveRecommendedDueDateToToday),
            (requestsSplit, DailyPlanningActionDraftKind.splitRecommendedTask)
        ].compactMap { isRequested, kind in
            isRequested ? kind : nil
        }

        guard rejectsAction == false, asksForAdvice == false, requestedKinds.count == 1 else {
            return nil
        }
        return requestedKinds[0]
    }

    private static func containsAnyExplicitPhrase(_ phrases: [String], in foldedTranscript: String) -> Bool {
        phrases.contains { phrase in
            guard usesOnlyASCIILettersOrSpaces(phrase) else {
                return foldedTranscript.contains(phrase)
            }
            return containsLatinPhrase(phrase, in: foldedTranscript)
        }
    }

    private static func containsAny(_ needles: [String], in foldedTranscript: String) -> Bool {
        needles.contains { needle in
            foldedTranscript.contains(needle)
        }
    }

    private static func containsLatinPhrase(_ phrase: String, in foldedTranscript: String) -> Bool {
        var searchStart = foldedTranscript.startIndex
        while let range = foldedTranscript.range(of: phrase, range: searchStart..<foldedTranscript.endIndex) {
            if isLatinPhraseBoundary(before: range.lowerBound, after: range.upperBound, in: foldedTranscript) {
                return true
            }
            searchStart = range.upperBound
        }
        return false
    }

    private static func isLatinPhraseBoundary(
        before lowerBound: String.Index,
        after upperBound: String.Index,
        in text: String
    ) -> Bool {
        let beforeIsBoundary = lowerBound == text.startIndex
            || isLatinPhraseBoundaryCharacter(text[text.index(before: lowerBound)])
        let afterIsBoundary = upperBound == text.endIndex
            || isLatinPhraseBoundaryCharacter(text[upperBound])
        return beforeIsBoundary && afterIsBoundary
    }

    private static func isLatinPhraseBoundaryCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) == false
        }
    }

    private static func usesOnlyASCIILettersOrSpaces(_ phrase: String) -> Bool {
        phrase.unicodeScalars.allSatisfy { scalar in
            scalar.value == 32 || (scalar.value >= 97 && scalar.value <= 122)
        }
    }
}
