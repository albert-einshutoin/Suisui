import Foundation

public enum LocalPathRedactor {
    public static func redact(_ text: String) -> String {
        // Speech and playback errors can include customer/project names inside
        // macOS paths, including paths with spaces, so redact the full path
        // before user-facing UI or TTS prompts can expose it.
        let pattern = #"(?:(?:~|/(?:Users|Volumes|private|tmp|var))(?:/[^\n\r,;)]+?)+)(?=(?:\s+(?:api[_-]?key|token|password|secret)\s*[:=])|[\n\r,;)]|$)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.stringByReplacingMatches(in: text, range: range, withTemplate: "[REDACTED_PATH]")
    }
}
