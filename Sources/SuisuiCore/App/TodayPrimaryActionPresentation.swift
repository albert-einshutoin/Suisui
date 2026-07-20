import Foundation

public enum TodayPrimaryActionPresentation: Equatable, Sendable {
    case startFocus(taskID: Int64, title: String)
    case addToInbox(text: String)
    case addTaskForToday
    case unavailable(reason: String)

    public static func make(
        recommendedTaskID: Int64?,
        recommendedTaskTitle: String?,
        commandText: String,
        taskCount: Int
    ) -> Self {
        if let recommendedTaskID,
           let title = normalizedText(recommendedTaskTitle) {
            return .startFocus(taskID: recommendedTaskID, title: title)
        }

        let normalizedCommand = normalizedText(commandText)
        if let normalizedCommand, !normalizedCommand.hasSuffix(":") {
            return .addToInbox(text: normalizedCommand)
        }

        if taskCount == 0 {
            return .addTaskForToday
        }

        // An open Today with no recommendation should not invent a destructive
        // or ambiguous fallback. The UI keeps the reason visible and lets the
        // user choose from contextual secondary actions instead.
        return .unavailable(reason: "No recommended task is ready to focus.")
    }

    private static func normalizedText(_ text: String?) -> String? {
        guard let text else {
            return nil
        }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}
