@preconcurrency import AVFoundation
import Foundation
import SuisuiCore

final class AVFoundationSpeechAudioPlayer: SpeechAudioPlaying, @unchecked Sendable {
    init() {}

    func play(_ speech: SynthesizedSpeech) async throws {
        guard speech.format == .wav else {
            throw SpeechAudioPlaybackError.unsupportedFormat(speech.format)
        }

        do {
            try await playAudioFile(at: speech.fileURL)
        } catch let error as CancellationError {
            throw error
        } catch let error as SpeechAudioPlaybackError {
            throw error
        } catch {
            throw SpeechAudioPlaybackError.playbackFailed(
                UserFacingErrorMessageSanitizer.message(
                    from: error,
                    fallback: "Speech preview playback failed."
                )
            )
        }
    }

    private func playAudioFile(at fileURL: URL) async throws {
        let player = try AVAudioPlayer(contentsOf: fileURL)
        guard player.prepareToPlay(), player.play() else {
            throw SpeechAudioPlaybackError.playbackFailed("Speech preview playback did not start.")
        }

        defer {
            player.stop()
        }

        while player.isPlaying {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}

struct TemporaryDirectoryTextToSpeechPreviewer: TextToSpeechPreviewing {
    private let previewer: any TextToSpeechPreviewing
    private let temporaryDirectory: URL

    init(previewer: any TextToSpeechPreviewing, temporaryDirectory: URL) {
        self.previewer = previewer
        self.temporaryDirectory = temporaryDirectory
    }

    func playPreview(_ request: TextToSpeechRequest) async throws {
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try await previewer.playPreview(request)
    }
}
