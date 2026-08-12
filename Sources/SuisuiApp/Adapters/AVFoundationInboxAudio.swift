@preconcurrency import AVFoundation
import Combine
import Foundation
import SuisuiCore

enum InboxAudioPlaybackError: Error, Equatable, LocalizedError {
    case recordingUnavailable
    case playbackFailed

    var userMessage: String {
        switch self {
        case .recordingUnavailable:
            String(localized: "Audio playback is unavailable for this capture.")
        case .playbackFailed:
            String(localized: "The Inbox recording could not be played.")
        }
    }

    var errorDescription: String? { userMessage }
}

enum InboxAudioPlaybackTerminalEvent: Sendable {
    case finishedSuccessfully
    case decodingFailed
}

@MainActor
protocol InboxAudioPlaybackEngine: AnyObject, Sendable {
    var duration: TimeInterval { get }
    var currentTime: TimeInterval { get set }
    var isPlaying: Bool { get }
    var terminalEventHandler: (@MainActor @Sendable (InboxAudioPlaybackTerminalEvent) -> Void)? { get set }

    func managedModificationDate(for fileURL: URL) throws -> Date
    func load(_ fileURL: URL) throws
    func play() throws
    func pause()
    func stop()
}

protocol InboxAudioWaveformLoading: Sendable {
    func loadWaveform(from fileURL: URL) async throws -> [Double]
}

@MainActor
final class AVFoundationInboxAudioPlayer: NSObject, InboxAudioPlaybackEngine, AVAudioPlayerDelegate {
    private let validator: ManagedInboxAudioPathValidator
    private var player: AVAudioPlayer?
    var terminalEventHandler: (@MainActor @Sendable (InboxAudioPlaybackTerminalEvent) -> Void)?

    init(validator: ManagedInboxAudioPathValidator) {
        self.validator = validator
        super.init()
    }

    var duration: TimeInterval { player?.duration ?? 0 }
    var isPlaying: Bool { player?.isPlaying ?? false }
    var currentTime: TimeInterval {
        get { player?.currentTime ?? 0 }
        set {
            guard let player else { return }
            player.currentTime = min(max(newValue, 0), player.duration)
        }
    }

    func managedModificationDate(for fileURL: URL) throws -> Date {
        let managedURL = try validator.validatedManagedURL(fileURL)
        guard let modificationDate = try managedURL.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate else {
            throw InboxAudioPlaybackError.recordingUnavailable
        }
        return modificationDate
    }

    func load(_ fileURL: URL) throws {
        stop()
        do {
            let managedURL = try validator.validatedManagedURL(fileURL)
            let loadedPlayer = try AVAudioPlayer(contentsOf: managedURL)
            guard loadedPlayer.prepareToPlay() else {
                throw InboxAudioPlaybackError.playbackFailed
            }
            loadedPlayer.delegate = self
            player = loadedPlayer
        } catch let error as InboxAudioPlaybackError {
            throw error
        } catch {
            throw InboxAudioPlaybackError.playbackFailed
        }
    }

    func play() throws {
        guard let player, player.play() else {
            throw InboxAudioPlaybackError.playbackFailed
        }
    }

    func pause() {
        player?.pause()
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        player = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.handleTerminalEvent(
                for: player,
                event: flag ? .finishedSuccessfully : .decodingFailed
            )
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        Task { @MainActor [weak self] in
            self?.handleTerminalEvent(for: player, event: .decodingFailed)
        }
    }

    private func handleTerminalEvent(
        for reportingPlayer: AVAudioPlayer,
        event: InboxAudioPlaybackTerminalEvent
    ) {
        // A stopped player may report after a new selection loads; only the
        // active player is allowed to change the controller's state.
        guard reportingPlayer === player else { return }
        terminalEventHandler?(event)
    }
}

struct AVFoundationInboxWaveformLoader: InboxAudioWaveformLoading {
    private let validator: ManagedInboxAudioPathValidator

    init(validator: ManagedInboxAudioPathValidator) {
        self.validator = validator
    }

    func loadWaveform(from fileURL: URL) async throws -> [Double] {
        let managedURL = try validator.validatedManagedURL(fileURL)
        // AVAudioFile reads stay off the caller's executor, while the explicit
        // handler restores cancellation propagation lost by Task.detached.
        let readTask = Task.detached(priority: .utility) {
            try Self.readWaveform(from: managedURL)
        }
        return try await withTaskCancellationHandler {
            try await readTask.value
        } onCancel: {
            readTask.cancel()
        }
    }

    private static func readWaveform(from fileURL: URL) throws -> [Double] {
        do {
            let audioFile = try AVAudioFile(forReading: fileURL)
            let totalFrames = audioFile.length
            guard totalFrames > 0 else { return Array(repeating: 0, count: 64) }
            let format = audioFile.processingFormat
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_096) else {
                throw InboxAudioPlaybackError.playbackFailed
            }
            var peaks = [Float](repeating: 0, count: 64)
            var framesRead: AVAudioFramePosition = 0

            while framesRead < totalFrames {
                try Task.checkCancellation()
                buffer.frameLength = 0
                let remaining = totalFrames - framesRead
                try audioFile.read(
                    into: buffer,
                    frameCount: AVAudioFrameCount(min(remaining, 4_096))
                )
                let frameCount = Int(buffer.frameLength)
                guard frameCount > 0, let channelData = buffer.floatChannelData else { break }
                for frame in 0 ..< frameCount {
                    var peak: Float = 0
                    for channel in 0 ..< Int(format.channelCount) {
                        peak = max(peak, abs(channelData[channel][frame]))
                    }
                    let position = Double(framesRead + AVAudioFramePosition(frame)) / Double(totalFrames)
                    let bucket = min(63, Int(position * 64))
                    peaks[bucket] = max(peaks[bucket], peak)
                }
                framesRead += AVAudioFramePosition(frameCount)
            }

            let maximum = peaks.max() ?? 0
            guard maximum > 0 else { return Array(repeating: 0, count: 64) }
            return peaks.map { Double($0 / maximum) }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as InboxAudioPlaybackError {
            throw error
        } catch {
            throw InboxAudioPlaybackError.playbackFailed
        }
    }
}

enum InboxAudioPlaybackState: Equatable {
    case idle
    case loading
    case paused
    case playing
    case failed(String)
}

/// Owns only the active capture's playback and waveform work. A selection
/// change deliberately drops the previous key instead of growing a cache.
@MainActor
final class InboxAudioPlaybackController: ObservableObject {
    @Published private(set) var state: InboxAudioPlaybackState = .idle
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var waveform: [Double]?

    var isPlaying: Bool { state == .playing }
    var isRetryAvailable: Bool {
        guard case .failed = state else { return false }
        return retryFileURL != nil && selectedKey != nil
    }
    var isPlayable: Bool {
        switch state {
        case .paused, .playing:
            true
        case .failed:
            isRetryAvailable
        case .idle, .loading:
            false
        }
    }
    var isSeekable: Bool { state == .paused || state == .playing }
    var errorMessage: String? {
        guard case let .failed(message) = state else { return nil }
        return message
    }

    private struct SelectionKey: Equatable {
        let captureID: Int64
        let modificationDate: Date
    }

    private let engine: any InboxAudioPlaybackEngine
    private let waveformLoader: any InboxAudioWaveformLoading
    private var selectedKey: SelectionKey?
    private var progressTask: Task<Void, Never>?
    private var waveformTask: Task<Void, Never>?
    private var loadToken = UUID()
    private var retryFileURL: URL?
    private var retryFallbackDuration: TimeInterval = 0

    init(engine: any InboxAudioPlaybackEngine, waveformLoader: any InboxAudioWaveformLoading) {
        self.engine = engine
        self.waveformLoader = waveformLoader
        engine.terminalEventHandler = { [weak self] event in
            self?.handleTerminalEvent(event)
        }
    }

    static func live() -> InboxAudioPlaybackController {
        do {
            // Reuse the store's root hardening so playback cannot accept an
            // InboxAudio leaf symlink that startup maintenance would reject.
            let validator = try ManagedInboxAudioFileStore().validator
            return InboxAudioPlaybackController(
                engine: AVFoundationInboxAudioPlayer(validator: validator),
                waveformLoader: AVFoundationInboxWaveformLoader(validator: validator)
            )
        } catch {
            // Inbox must remain readable when Application Support is
            // unavailable; loading then presents the same sanitized failure.
            return InboxAudioPlaybackController(
                engine: UnavailableInboxAudioPlaybackEngine(),
                waveformLoader: UnavailableInboxAudioWaveformLoader()
            )
        }
    }

    deinit {
        progressTask?.cancel()
        waveformTask?.cancel()
        let engine = engine
        Task { @MainActor in engine.stop() }
    }

    func load(captureID: Int64, fileURL: URL, fallbackDuration: TimeInterval = 0) {
        do {
            let modificationDate = try engine.managedModificationDate(for: fileURL)
            let key = SelectionKey(captureID: captureID, modificationDate: modificationDate)
            guard key != selectedKey else { return }
            reset(stoppingEngine: selectedKey != nil)
            selectedKey = key
            state = .loading
            try engine.load(fileURL)
            duration = max(engine.duration, fallbackDuration, 0)
            retryFileURL = fileURL
            retryFallbackDuration = fallbackDuration
            state = .paused
            loadWaveform(from: fileURL, for: key)
        } catch let error as InboxAudioPlaybackError {
            fail(with: error)
        } catch {
            fail(with: .recordingUnavailable)
        }
    }

    func play() throws {
        if isRetryAvailable {
            try retryPlayback()
            return
        }
        do {
            try engine.play()
            state = .playing
            startProgressTracking()
        } catch {
            fail(with: .playbackFailed, preservingLoadedSelection: true)
            throw InboxAudioPlaybackError.playbackFailed
        }
    }

    func pause() {
        engine.pause()
        progressTask?.cancel()
        progressTask = nil
        currentTime = engine.currentTime
        if selectedKey != nil { state = .paused }
    }

    func toggle() {
        if isPlaying {
            pause()
        } else {
            try? play()
        }
    }

    func seek(to value: TimeInterval) {
        let upperBound = max(duration, engine.duration, 0)
        engine.currentTime = min(max(value, 0), upperBound)
        currentTime = engine.currentTime
        if currentTime >= upperBound, engine.isPlaying {
            pause()
        }
    }

    func stop() {
        reset(stoppingEngine: selectedKey != nil)
    }

    private func loadWaveform(from fileURL: URL, for key: SelectionKey) {
        let token = loadToken
        waveformTask = Task { @MainActor [weak self, waveformLoader] in
            do {
                let samples = try await waveformLoader.loadWaveform(from: fileURL)
                guard let self, self.loadToken == token, self.selectedKey == key else { return }
                self.waveform = samples
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.loadToken == token, self.selectedKey == key else { return }
                self.waveform = nil
            }
        }
    }

    private func startProgressTracking() {
        progressTask?.cancel()
        progressTask = Task { @MainActor [weak self] in
            while let self, self.engine.isPlaying {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                self.currentTime = self.engine.currentTime
            }
            guard let self, !Task.isCancelled else { return }
            self.currentTime = self.engine.currentTime
            self.state = self.selectedKey == nil ? .idle : .paused
            self.progressTask = nil
        }
    }

    private func handleTerminalEvent(_ event: InboxAudioPlaybackTerminalEvent) {
        switch event {
        case .finishedSuccessfully:
            progressTask?.cancel()
            progressTask = nil
            currentTime = engine.currentTime
            state = selectedKey == nil ? .idle : .paused
        case .decodingFailed:
            fail(with: .playbackFailed, preservingLoadedSelection: true)
        }
    }

    private func retryPlayback() throws {
        guard let retryFileURL, let selectedKey else {
            throw InboxAudioPlaybackError.playbackFailed
        }
        do {
            try engine.load(retryFileURL)
            currentTime = 0
            duration = max(engine.duration, retryFallbackDuration, 0)
            if waveform == nil {
                loadWaveform(from: retryFileURL, for: selectedKey)
            }
            try engine.play()
            state = .playing
            startProgressTracking()
        } catch {
            fail(with: .playbackFailed)
            throw InboxAudioPlaybackError.playbackFailed
        }
    }

    private func fail(
        with error: InboxAudioPlaybackError,
        preservingLoadedSelection: Bool = false
    ) {
        if preservingLoadedSelection, selectedKey != nil, retryFileURL != nil {
            loadToken = UUID()
            progressTask?.cancel()
            progressTask = nil
            waveformTask?.cancel()
            waveformTask = nil
            engine.stop()
            currentTime = 0
            state = .failed(error.userMessage)
            return
        }
        reset(stoppingEngine: selectedKey != nil)
        state = .failed(error.userMessage)
    }

    private func reset(stoppingEngine: Bool) {
        loadToken = UUID()
        progressTask?.cancel()
        progressTask = nil
        waveformTask?.cancel()
        waveformTask = nil
        if stoppingEngine { engine.stop() }
        selectedKey = nil
        currentTime = 0
        duration = 0
        waveform = nil
        retryFileURL = nil
        retryFallbackDuration = 0
        state = .idle
    }
}

@MainActor
private final class UnavailableInboxAudioPlaybackEngine: InboxAudioPlaybackEngine {
    var duration: TimeInterval { 0 }
    var currentTime: TimeInterval {
        get { 0 }
        set {}
    }
    var isPlaying: Bool { false }
    var terminalEventHandler: (@MainActor @Sendable (InboxAudioPlaybackTerminalEvent) -> Void)?

    func managedModificationDate(for fileURL: URL) throws -> Date {
        throw InboxAudioPlaybackError.recordingUnavailable
    }

    func load(_ fileURL: URL) throws {
        throw InboxAudioPlaybackError.recordingUnavailable
    }

    func play() throws {
        throw InboxAudioPlaybackError.playbackFailed
    }

    func pause() {}
    func stop() {}
}

private struct UnavailableInboxAudioWaveformLoader: InboxAudioWaveformLoading {
    func loadWaveform(from fileURL: URL) async throws -> [Double] {
        throw InboxAudioPlaybackError.recordingUnavailable
    }
}
