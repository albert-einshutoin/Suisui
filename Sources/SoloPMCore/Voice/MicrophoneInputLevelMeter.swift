import Combine
import Foundation

/// Observable slice dedicated to the live microphone input level. Level
/// samples arrive at ~10Hz while recording; keeping them on their own
/// ObservableObject lets the small meter view re-render alone instead of
/// invalidating the whole voice capture window on every sample.
@MainActor
public final class MicrophoneInputLevelMeter: ObservableObject {
    /// Normalized microphone input level in 0...1.
    @Published public private(set) var inputLevel: Double = 0

    public init() {}

    func update(_ level: Double) {
        let clamped = min(1, max(0, level))
        guard inputLevel != clamped else {
            return
        }
        inputLevel = clamped
    }
}
