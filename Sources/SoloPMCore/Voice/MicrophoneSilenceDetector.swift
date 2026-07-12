import Foundation

/// Pure detector for a microphone that appears to deliver no input: it reports
/// when the normalized input level has stayed below a threshold for a
/// continuous stretch of time since recording started. Any sample at or above
/// the threshold resets the window, so brief spikes clear the warning.
public struct MicrophoneSilenceDetector: Equatable, Sendable {
    /// Normalized level (0...1) under which a sample counts as silence.
    public let threshold: Double
    /// Continuous silence duration required before the detector triggers.
    public let requiredSilenceDuration: TimeInterval

    private var silenceWindowStart: Date?

    public init(threshold: Double = 0.03, requiredSilenceDuration: TimeInterval = 5.0) {
        self.threshold = threshold
        self.requiredSilenceDuration = requiredSilenceDuration
    }

    /// Starts a new observation window. Silence is measured from the recording
    /// start so a microphone that never produces input still triggers.
    public mutating func beginRecording(at date: Date) {
        silenceWindowStart = date
    }

    /// Ends the observation window; subsequent samples never trigger.
    public mutating func reset() {
        silenceWindowStart = nil
    }

    /// Feeds one (level, timestamp) sample and reports whether input has been
    /// below the threshold for at least `requiredSilenceDuration` continuous
    /// seconds. Returns `false` immediately when the level recovers.
    public mutating func recordSample(level: Double, at date: Date) -> Bool {
        guard let windowStart = silenceWindowStart else {
            return false
        }
        guard level < threshold else {
            // A spike means the microphone is alive: restart the continuous
            // silence window from this sample.
            silenceWindowStart = date
            return false
        }
        return date.timeIntervalSince(windowStart) >= requiredSilenceDuration
    }
}

/// Converts an average-power reading in decibels (as produced by audio
/// recording APIs, typically -160...0) into a normalized 0...1 level with a
/// noise floor, so UI meters and the silence detector share one scale.
public enum MicrophoneInputLevelNormalizer {
    public static let defaultFloorDecibels: Double = -50

    public static func normalizedLevel(
        fromAveragePowerDecibels decibels: Double,
        floorDecibels: Double = defaultFloorDecibels
    ) -> Double {
        guard floorDecibels < 0 else {
            return decibels >= 0 ? 1 : 0
        }
        let normalized = (decibels - floorDecibels) / -floorDecibels
        return min(1, max(0, normalized))
    }
}
