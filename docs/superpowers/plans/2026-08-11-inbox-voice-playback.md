# Inbox Voice Playback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist Inbox voice recordings in an app-owned directory and provide secure play, pause, seek, progress, and real waveform review without weakening Transcript-based triage.

**Architecture:** Inject a Core file-persistence contract into `InboxVoiceCaptureService`, implement managed Application Support storage in the app layer, and add an AVFoundation playback/waveform adapter behind a MainActor controller. Paths are canonicalized before import, playback, migration, or deletion; waveform data stays in memory and failures fall back to progress UI while Transcript, interpretation, and memo remain usable.

**Tech Stack:** Swift 6, Foundation, AVFoundation, SwiftUI, existing SQLite Inbox capture store, XCTest, macOS accessibility/runtime smoke scripts.

**Design:** `docs/superpowers/specs/2026-08-11-inbox-triage-lifecycle-and-voice-playback-design.md`

---

## File map

- Create `Sources/SuisuiCore/Voice/InboxAudio.swift`: persistence contract, managed audio descriptor, and sanitized errors.
- Modify `Sources/SuisuiCore/Voice/InboxCapture.swift`: compensated save and capture path update contract.
- Create `Sources/SuisuiApp/Adapters/ManagedInboxAudioFileStore.swift`: Application Support import, canonical-path validation, legacy migration, deletion, orphan cleanup.
- Create `Sources/SuisuiApp/Adapters/AVFoundationInboxAudio.swift`: player and streaming 64-bucket waveform loader.
- Create `Sources/SuisuiApp/Views/InboxVoicePlaybackView.swift`: MainActor controller and focused playback UI.
- Modify `Sources/SuisuiApp/Views/ProjectWorkflowInboxView.swift`: replace the fixed waveform block with the playback view.
- Modify `Sources/SuisuiApp/Composition/VoiceRuntimeFactory.swift`: inject managed persistence into voice capture.
- Modify `Sources/SuisuiApp/Composition/ProjectBoardRuntimeFactory.swift`: expose the managed audio root/playback dependencies to Inbox UI if composition injection is needed.
- Modify `Sources/SuisuiApp/Resources/{en,ja}.lproj/Localizable.strings`: playback states and sanitized failures.
- Modify `Tests/SuisuiCoreTests/InboxCaptureStoreTests.swift`: capture path update and compensated persistence.
- Create `Tests/SuisuiAppTests/InboxAudioPlaybackTests.swift`: managed storage, unsafe path, cleanup, playback controller, and waveform fixtures.
- Modify `Tests/SuisuiCoreTests/AppExperienceSourceTests.swift`: playback UI/AX source contracts.
- Modify `Tests/SuisuiCoreTests/ReleasePipelineTests.swift`: runtime smoke and security contract.
- Create `script/check_runtime_inbox_voice_playback_smoke.sh`: visible playback control and failure-state smoke.

### Task 1: Define the managed Inbox audio contract

**Files:**
- Create: `Sources/SuisuiCore/Voice/InboxAudio.swift`
- Create: `Tests/SuisuiAppTests/InboxAudioPlaybackTests.swift`

- [ ] **Step 1: Write failing contract tests**

```swift
func testManagedInboxAudioDescriptorRejectsNonFileURL() {
    XCTAssertThrowsError(try ManagedInboxAudioFile(
        fileURL: URL(string: "https://example.invalid/recording.m4a")!,
        durationSeconds: 2
    ))
}

func testInboxAudioErrorMessagesNeverExposePath() {
    let error = InboxAudioError.unsafePath
    XCTAssertEqual(error.userMessage, "This Inbox recording is outside Suisui's managed audio storage.")
    XCTAssertFalse(error.userMessage.contains("/Users/"))
}
```

- [ ] **Step 2: Run the new suite and verify red**

Run: `swift test --filter InboxAudioPlaybackTests`
Expected: compilation fails because the types do not exist.

- [ ] **Step 3: Add minimal Core contracts**

```swift
import Foundation

public enum InboxAudioError: Error, Equatable, Sendable {
    case invalidSource
    case unsafePath
    case missingFile
    case importFailed
    case playbackFailed

    public var userMessage: String {
        switch self {
        case .invalidSource: "The recorded audio could not be read."
        case .unsafePath: "This Inbox recording is outside Suisui's managed audio storage."
        case .missingFile: "This Inbox recording is no longer available."
        case .importFailed: "The recording could not be saved to Inbox."
        case .playbackFailed: "The Inbox recording could not be played."
        }
    }
}

public struct ManagedInboxAudioFile: Equatable, Sendable {
    public let fileURL: URL
    public let durationSeconds: Double

    public init(fileURL: URL, durationSeconds: Double) throws {
        guard fileURL.isFileURL, fileURL.path.hasPrefix("/") else {
            throw InboxAudioError.invalidSource
        }
        self.fileURL = fileURL
        self.durationSeconds = durationSeconds
    }
}

public protocol InboxAudioPersisting: Sendable {
    func importRecording(_ audio: RecordedAudio) throws -> ManagedInboxAudioFile
    func removeManagedFile(at fileURL: URL) throws
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter InboxAudioPlaybackTests`
Expected: contract tests pass.

- [ ] **Step 5: Commit the contract**

```bash
git add Sources/SuisuiCore/Voice/InboxAudio.swift Tests/SuisuiAppTests/InboxAudioPlaybackTests.swift
git commit -m "feat(inbox): define managed voice audio contract"
```

### Task 2: Persist capture paths and compensate partial saves

**Files:**
- Modify: `Sources/SuisuiCore/Voice/InboxCapture.swift`
- Test: `Tests/SuisuiCoreTests/InboxCaptureStoreTests.swift`

- [ ] **Step 1: Write failing path-update and compensation tests**

Use a fake persister and failing capture store:

```swift
@MainActor
func testVoiceCaptureSaveRemovesImportedAudioWhenCaptureInsertFails() throws {
    let persister = RecordingInboxAudioPersister(
        importedURL: URL(fileURLWithPath: "/managed/voice.m4a")
    )
    let service = InboxVoiceCaptureService(
        audioRecorder: StubAudioRecorder(),
        sttProvider: StubSTTProvider(),
        projectBoardStore: InMemoryProjectBoardStore(),
        inboxCaptureStore: AlwaysFailingInboxCaptureStore(),
        audioPersister: persister
    )

    XCTAssertThrowsError(try service.saveTranscribedCapture(
        audio: recordedAudioFixture(), transcript: STTTranscript(text: "Launch review", duration: 2)
    ))
    XCTAssertEqual(persister.removedURLs, [URL(fileURLWithPath: "/managed/voice.m4a")])
}

func testSQLiteInboxCaptureStoreUpdatesManagedAudioPath() throws {
    let stores = try makeStores()
    let capture = try makeVoiceCapture(stores: stores)
    let updated = try stores.captures.updateAudioFilePath(
        id: capture.id, audioFilePath: "/managed/migrated.m4a"
    )
    XCTAssertEqual(updated.audioFilePath, "/managed/migrated.m4a")
}
```

- [ ] **Step 2: Run focused tests and verify failure**

Run: `swift test --filter InboxCaptureStoreTests.testVoiceCaptureSaveRemovesImportedAudio`
Expected: missing initializer dependency and path update method.

- [ ] **Step 3: Extend `InboxCaptureStore` with path update**

Add:

```swift
func updateAudioFilePath(id: Int64, audioFilePath: String) throws -> InboxCaptureRecord
```

SQLite must trim/validate the path, update `updated_at`, and decode the updated record. Update all test doubles explicitly.

- [ ] **Step 4: Inject persistence and implement compensation**

Add `audioPersister: any InboxAudioPersisting` to `InboxVoiceCaptureService`. In `saveTranscribedCapture`:

```swift
let managed = try audioPersister.importRecording(audio)
do {
    let task = try projectBoardStore.createInboxTask(title: resolvedTitle)
    do {
        let capture = try inboxCaptureStore.createVoiceCapture(
            InboxVoiceCaptureDraft(
                taskID: task.id,
                audioFilePath: managed.fileURL.path,
                durationSeconds: managed.durationSeconds,
                transcript: title,
                interpretationSummary: interpretation?.summary,
                memo: interpretation?.memo,
                classificationStatus: .unclassified,
                transcriptionStatus: transcriptionStatus,
                createdAt: captureCreatedAt
            )
        )
        return InboxVoiceCaptureResult(task: task, capture: capture, transcriptionErrorMessage: transcriptionErrorMessage)
    } catch {
        try? projectBoardStore.deleteTask(id: task.id)
        throw error
    }
} catch {
    try? audioPersister.removeManagedFile(at: managed.fileURL)
    throw error
}
```

Keep the original error as the user-facing cause; cleanup failures are handled by orphan cleanup rather than replacing it.

- [ ] **Step 5: Run capture tests**

Run: `swift test --filter InboxCaptureStoreTests`
Expected: capture creation, path update, compensation, and existing transcription tests pass.

- [ ] **Step 6: Commit compensated persistence**

```bash
git add Sources/SuisuiCore/Voice/InboxCapture.swift Tests/SuisuiCoreTests/InboxCaptureStoreTests.swift
git commit -m "fix(inbox): persist voice captures without orphan state"
```

### Task 3: Implement managed Application Support storage

**Files:**
- Create: `Sources/SuisuiApp/Adapters/ManagedInboxAudioFileStore.swift`
- Modify: `Sources/SuisuiApp/Composition/VoiceRuntimeFactory.swift`
- Test: `Tests/SuisuiAppTests/InboxAudioPlaybackTests.swift`

- [ ] **Step 1: Write failing file ownership tests**

Test import, UUID naming, symlink escape rejection, legacy Suisui temp migration, missing legacy file, deletion boundary, and orphan cleanup:

```swift
func testManagedInboxAudioStoreNeverDeletesOutsideRoot() throws {
    let fixture = try makeAudioStoreFixture()
    let outside = fixture.parent.appendingPathComponent("keep.m4a")
    try Data([0, 1]).write(to: outside)

    XCTAssertThrowsError(try fixture.store.removeManagedFile(at: outside))
    XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
}

func testManagedInboxAudioStoreRejectsSymlinkEscape() throws {
    let fixture = try makeAudioStoreFixture()
    let link = fixture.root.appendingPathComponent("escape.m4a")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.outsideAudio)
    XCTAssertThrowsError(try fixture.store.validatedManagedURL(link))
}
```

- [ ] **Step 2: Run tests and verify failure**

Run: `swift test --filter InboxAudioPlaybackTests.testManagedInboxAudioStore`
Expected: missing `ManagedInboxAudioFileStore`.

- [ ] **Step 3: Implement canonical containment once**

Resolve symlinks and standardize both root and candidate. Accept only regular files whose canonical parent remains under the canonical root. Reuse this helper for playback, migration, and deletion.

```swift
private func contains(_ candidate: URL) -> Bool {
    let rootPath = rootURL.resolvingSymlinksInPath().standardizedFileURL.path + "/"
    let candidatePath = candidate.resolvingSymlinksInPath().standardizedFileURL.path
    return candidatePath.hasPrefix(rootPath)
}
```

Also request `.isRegularFileKey` and reject symlinks that resolve outside root.

- [ ] **Step 4: Implement atomic import and cleanup**

Create the directory with user-only defaults, copy/move to a UUID temporary destination within root, then atomically rename to the final `.m4a`, `.wav`, or `.caf` path. Orphan cleanup lists only direct regular-file children of root and removes files not present in the supplied referenced-path Set. Never recurse outside root.

- [ ] **Step 5: Implement legacy migration**

Only accept existing files under `FileManager.default.temporaryDirectory` whose names begin with `suisui-recording-` or `suisui-conversation-`. Import them, call `updateAudioFilePath`, then remove the old owned file. Missing or caller-owned paths return sanitized failure without reading them.

- [ ] **Step 6: Inject the production store**

In `VoiceRuntimeFactory`, create the root with:

```swift
let inboxAudioRoot = try applicationSupportDirectoryURL()
    .appendingPathComponent("InboxAudio", isDirectory: true)
let audioPersister = ManagedInboxAudioFileStore(rootURL: inboxAudioRoot)
```

Pass it to `InboxVoiceCaptureService`.

- [ ] **Step 7: Run managed storage and security tests**

Run:

```bash
swift test --filter InboxAudioPlaybackTests.testManagedInboxAudioStore
swift test --filter InboxCaptureStoreTests
```

Expected: all managed-root, symlink, migration, compensation, and capture tests pass.

- [ ] **Step 8: Commit file ownership**

```bash
git add Sources/SuisuiApp/Adapters/ManagedInboxAudioFileStore.swift Sources/SuisuiApp/Composition/VoiceRuntimeFactory.swift Tests/SuisuiAppTests/InboxAudioPlaybackTests.swift
git commit -m "feat(inbox): own voice recordings in application support"
```

### Task 4: Build the AVFoundation player and real waveform loader

**Files:**
- Create: `Sources/SuisuiApp/Adapters/AVFoundationInboxAudio.swift`
- Test: `Tests/SuisuiAppTests/InboxAudioPlaybackTests.swift`

- [ ] **Step 1: Write failing player and waveform tests**

Define a fake engine for controller tests and generate a short sine-wave fixture for adapter tests:

```swift
@MainActor
func testInboxPlaybackControllerStopsWhenCaptureChanges() throws {
    let engine = FakeInboxAudioPlaybackEngine(duration: 8)
    let controller = InboxAudioPlaybackController(engine: engine)
    try controller.load(captureID: 1, fileURL: managedURL("one.m4a"))
    controller.play()

    try controller.load(captureID: 2, fileURL: managedURL("two.m4a"))

    XCTAssertEqual(engine.stopCount, 1)
    XCTAssertEqual(controller.state, .idle)
}

func testAVFoundationWaveformReturnsNormalized64Buckets() async throws {
    let values = try await AVFoundationInboxWaveformLoader().loadWaveform(from: sineWaveFixtureURL())
    XCTAssertEqual(values.count, 64)
    XCTAssertTrue(values.allSatisfy { 0 ... 1 ~= $0 })
    XCTAssertTrue(values.contains { $0 > 0.5 })
}
```

- [ ] **Step 2: Run focused tests and verify failure**

Run: `swift test --filter InboxAudioPlaybackTests.testInboxPlaybackController`
Expected: missing playback contracts/controller.

- [ ] **Step 3: Add focused playback contracts**

```swift
@MainActor
protocol InboxAudioPlaybackEngine: AnyObject {
    var duration: TimeInterval { get }
    var currentTime: TimeInterval { get set }
    var isPlaying: Bool { get }
    func load(_ fileURL: URL) throws
    func play() throws
    func pause()
    func stop()
}

protocol InboxAudioWaveformLoading: Sendable {
    func loadWaveform(from fileURL: URL) async throws -> [Double]
}
```

- [ ] **Step 4: Implement AVAudioPlayer engine**

Wrap one `AVAudioPlayer`, call `prepareToPlay`, expose duration/current time, and translate every error to `InboxAudioError.playbackFailed` after redaction. Validate the managed URL before loading.

- [ ] **Step 5: Implement streaming waveform reduction**

Use AVFoundation PCM reading in chunks. Accumulate absolute peaks into exactly 64 proportional frame buckets, normalize by the maximum peak, and return 64 zeros for valid silence. Do not use the fixed bar array from the current SwiftUI file.

- [ ] **Step 6: Add a bounded in-memory cache**

Cache only the currently selected capture key `(captureID, modificationDate)`. Replacing the selected capture drops the old waveform; do not add a general disk cache or eviction framework.

- [ ] **Step 7: Run player and waveform tests**

Run: `swift test --filter InboxAudioPlaybackTests`
Expected: fake controller and native waveform fixture tests pass.

- [ ] **Step 8: Commit native playback**

```bash
git add Sources/SuisuiApp/Adapters/AVFoundationInboxAudio.swift Tests/SuisuiAppTests/InboxAudioPlaybackTests.swift
git commit -m "feat(inbox): add native voice playback and waveform"
```

### Task 5: Replace the fixed waveform with accessible playback UI

**Files:**
- Create: `Sources/SuisuiApp/Views/InboxVoicePlaybackView.swift`
- Modify: `Sources/SuisuiApp/Views/ProjectWorkflowInboxView.swift`
- Modify: `Sources/SuisuiApp/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/SuisuiApp/Resources/ja.lproj/Localizable.strings`
- Test: `Tests/SuisuiCoreTests/AppExperienceSourceTests.swift`

- [ ] **Step 1: Write failing UI/AX source contracts**

```swift
func testInboxVoiceDetailUsesRealPlaybackInsteadOfFixedWaveform() throws {
    let inbox = try readPackageFile("Sources/SuisuiApp/Views/ProjectWorkflowInboxView.swift")
    let playback = try readPackageFile("Sources/SuisuiApp/Views/InboxVoicePlaybackView.swift")
    XCTAssertTrue(inbox.contains("InboxVoicePlaybackView(capture:"))
    XCTAssertFalse(inbox.contains("[8, 14, 10, 20"))
    XCTAssertTrue(playback.contains("inbox-voice-play-pause"))
    XCTAssertTrue(playback.contains("inbox-voice-seek"))
    XCTAssertTrue(playback.contains("accessibilityHidden(true)"))
}
```

- [ ] **Step 2: Run the source contract and verify failure**

Run: `swift test --filter AppExperienceSourceTests.testInboxVoiceDetailUsesRealPlayback`
Expected: playback file is missing and fixed bars remain.

- [ ] **Step 3: Implement `InboxAudioPlaybackController`**

Expose `idle/loading/playing/paused/failed`, current time, duration, waveform, and sanitized error. A 50ms MainActor timer updates progress only while playing; pause/stop invalidates it. `load(capture:)` stops the previous capture before loading the next.

- [ ] **Step 4: Build the SwiftUI control**

Render:

```swift
HStack(spacing: 8) {
    Button(action: controller.togglePlayback) {
        Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
    }
    .accessibilityIdentifier("inbox-voice-play-pause")

    InboxWaveformShape(samples: controller.waveform)
        .accessibilityHidden(true)

    Slider(value: controller.seekBinding, in: 0 ... max(controller.duration, 0.001))
        .accessibilityIdentifier("inbox-voice-seek")

    Text(controller.timeLabel).monospacedDigit()
}
```

When waveform loading fails but playback loads, render `ProgressView(value:currentTime,total:duration)` instead of fake bars. When playback fails, show visible error below but leave Transcript, Interpretation, and memo views enabled.

- [ ] **Step 5: Add focus-scoped Space handling**

Attach Space only to the focused play/pause control. Do not add a window-level keyboard shortcut.

- [ ] **Step 6: Add English and Japanese strings**

Translate Play recording, Pause recording, Recording unavailable, Playback failed, current/total time, and waveform fallback. Ensure visible text and accessibility values use the same failure reason.

Add a VoiceOver-focused App test that asserts the play/pause label changes with state, the seek control announces elapsed and total time, and a missing recording exposes the same sanitized sentence shown visually.

- [ ] **Step 7: Run UI and localization tests**

Run:

```bash
swift test --filter AppExperienceSourceTests.testInboxVoice
swift test --filter LocalizationStaticTests
```

Expected: fixed waveform is absent and playback AX anchors exist in both locales.

- [ ] **Step 8: Commit the playback UI**

```bash
git add Sources/SuisuiApp/Views/InboxVoicePlaybackView.swift Sources/SuisuiApp/Views/ProjectWorkflowInboxView.swift Sources/SuisuiApp/Resources/en.lproj/Localizable.strings Sources/SuisuiApp/Resources/ja.lproj/Localizable.strings Tests/SuisuiCoreTests/AppExperienceSourceTests.swift
git commit -m "feat(inbox): add accessible voice review controls"
```

### Task 6: Add deletion cleanup and startup orphan sweep

**Files:**
- Modify: `Sources/SuisuiCore/Voice/InboxCapture.swift`
- Modify: `Sources/SuisuiApp/Adapters/ManagedInboxAudioFileStore.swift`
- Modify: `Sources/SuisuiApp/Composition/ProjectBoardRuntimeFactory.swift`
- Test: `Tests/SuisuiAppTests/InboxAudioPlaybackTests.swift`
- Test: `Tests/SuisuiCoreTests/InboxCaptureStoreTests.swift`

- [ ] **Step 1: Write failing cleanup tests**

```swift
func testOrphanSweepDeletesOnlyUnreferencedManagedFiles() throws {
    let fixture = try makeAudioStoreFixture()
    let referenced = try fixture.makeManagedAudio(named: "referenced.m4a")
    let orphan = try fixture.makeManagedAudio(named: "orphan.m4a")

    try fixture.store.removeOrphans(referencedPaths: [referenced.path])

    XCTAssertTrue(FileManager.default.fileExists(atPath: referenced.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.outsideAudio.path))
}
```

- [ ] **Step 2: Run cleanup tests and verify failure**

Run: `swift test --filter InboxAudioPlaybackTests.testOrphanSweep`
Expected: missing cleanup method.

- [ ] **Step 3: Add referenced-path listing**

Add `listAll()` or a narrower `referencedAudioFilePaths()` to `InboxCaptureStore`; SQLite returns only capture audio paths. Do not expose raw paths to SwiftUI.

- [ ] **Step 4: Run startup cleanup off MainActor**

After the Project Board runtime opens the migrated connection, load referenced paths and sweep direct regular files under InboxAudio. A cleanup failure is advisory and sanitized; it must not block Project Board launch.

- [ ] **Step 5: Clean up after explicit capture/task deletion**

Collect managed capture URLs before DB deletion, delete DB state first, then remove owned files. If immediate file removal fails, leave it for startup cleanup. Project deletion and Undo paths are covered by the same orphan sweep.

- [ ] **Step 6: Run cleanup and capture suites**

Run:

```bash
swift test --filter InboxAudioPlaybackTests
swift test --filter InboxCaptureStoreTests
```

Expected: referenced files survive; only unreferenced managed files are removed.

- [ ] **Step 7: Commit lifecycle cleanup**

```bash
git add Sources/SuisuiCore/Voice/InboxCapture.swift Sources/SuisuiApp/Adapters/ManagedInboxAudioFileStore.swift Sources/SuisuiApp/Composition/ProjectBoardRuntimeFactory.swift Tests/SuisuiAppTests/InboxAudioPlaybackTests.swift Tests/SuisuiCoreTests/InboxCaptureStoreTests.swift
git commit -m "fix(inbox): clean up owned voice recordings safely"
```

### Task 7: Add runtime playback and security gates

**Files:**
- Create: `script/check_runtime_inbox_voice_playback_smoke.sh`
- Create: `script/generate_inbox_audio_fixture.swift`
- Modify: `script/check_accessibility_preflight.sh`
- Modify: `script/check_security_regressions.sh`
- Modify: `Tests/SuisuiCoreTests/ReleasePipelineTests.swift`

- [ ] **Step 1: Write failing release-pipeline contracts**

```swift
func testInboxVoicePlaybackSmokeCoversControlsAndMissingFile() throws {
    let script = try readPackageFile("script/check_runtime_inbox_voice_playback_smoke.sh")
    XCTAssertTrue(script.contains("inbox-voice-play-pause"))
    XCTAssertTrue(script.contains("inbox-voice-seek"))
    XCTAssertTrue(script.contains("Recording unavailable"))
    XCTAssertTrue(script.contains("SUISUI_RUNTIME_INBOX_VOICE_PLAYBACK_KEEP_DATABASE"))
}
```

- [ ] **Step 2: Run contract test and verify failure**

Run: `swift test --filter ReleasePipelineTests.testInboxVoicePlaybackSmoke`
Expected: script is missing.

- [ ] **Step 3: Add deterministic audio fixture and visible-app smoke**

Use `script/generate_inbox_audio_fixture.swift` with AVFoundation to write a deterministic one-second mono CAF sine wave, seed a capture pointing to the managed copied fixture, launch Inbox, then:

```swift
import AVFoundation
import Foundation

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let format = AVAudioFormat(standardFormatWithSampleRate: 22_050, channels: 1)!
let frameCount = AVAudioFrameCount(format.sampleRate)
let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
buffer.frameLength = frameCount
let samples = buffer.floatChannelData![0]
for frame in 0 ..< Int(frameCount) {
    samples[frame] = sin(2 * .pi * 440 * Float(frame) / Float(format.sampleRate)) * 0.5
}
let file = try AVAudioFile(forWriting: outputURL, settings: format.settings)
try file.write(from: buffer)
```

The script requires exactly one output-path argument and exits non-zero with a path-redacted message if writing fails.

1. press Play and observe the pause label/state;
2. press Pause and confirm progress stops;
3. change Slider value and confirm the AX value changes;
4. select another Task and confirm the first playback returns idle;
5. seed a missing managed path and confirm `Recording unavailable` while Transcript remains visible.

Do not use microphone input, network STT, or a fake fixed waveform.

- [ ] **Step 4: Extend accessibility and security scans**

Require play/pause and seek anchors in source/runtime AX preflight. Add regression fixtures proving canonical root checks reject traversal and symlink escape without logging absolute paths.

- [ ] **Step 5: Run release contracts and runtime smoke**

Run:

```bash
swift test --filter ReleasePipelineTests.testInboxVoicePlayback
./script/check_runtime_inbox_voice_playback_smoke.sh
./script/check_accessibility_preflight.sh --source-only
./script/check_security_regressions.sh
```

Expected: all commands exit 0 and the runtime smoke reports play, pause, seek, selection stop, and missing-file fallback.

- [ ] **Step 6: Commit runtime gates**

```bash
git add script/check_runtime_inbox_voice_playback_smoke.sh script/generate_inbox_audio_fixture.swift script/check_accessibility_preflight.sh script/check_security_regressions.sh Tests/SuisuiCoreTests/ReleasePipelineTests.swift
git commit -m "test(inbox): cover voice playback and file boundaries"
```

### Task 8: Final validation and self-review

**Files:**
- Review all files changed in Tasks 1-7.

- [ ] **Step 1: Run focused suites**

```bash
swift test --filter InboxAudioPlaybackTests
swift test --filter InboxCaptureStoreTests
swift test --filter AppExperienceSourceTests
swift test --filter ReleasePipelineTests
```

Expected: all pass.

- [ ] **Step 2: Run runtime, AX, and security gates**

```bash
./script/check_runtime_inbox_voice_playback_smoke.sh
./script/check_accessibility_preflight.sh --source-only
./script/check_security_regressions.sh
```

Expected: every command prints `OK` and exits 0.

- [ ] **Step 3: Run full tests and build**

```bash
swift test
./script/build_and_run.sh --build-only
git diff --check
```

Expected: full suite and build pass; diff check is silent.

- [ ] **Step 4: Inspect the supported visual matrix**

Verify English/Japanese, Light/Dark, wide/compact, playing/paused/missing-file states. Perform a VoiceOver pass over play/pause, seek, elapsed time, failure text, Transcript, Interpretation, and memo. Confirm no control clipping, no horizontal scroll, right rail moves below in compact mode, and Transcript/Interpretation/memo remain usable for every playback failure.

- [ ] **Step 5: Self-review ownership and security**

Confirm one canonical containment helper guards import/playback/delete/migration, no arbitrary DB path is read, no absolute path enters UI/log/test artifacts, audio memory is bounded, waveform is real or absent, and every player/timer stops on selection/disappearance.

- [ ] **Step 6: Commit only corrective changes**

```bash
git add Sources/SuisuiCore/Voice/InboxAudio.swift Sources/SuisuiCore/Voice/InboxCapture.swift Sources/SuisuiApp/Adapters/ManagedInboxAudioFileStore.swift Sources/SuisuiApp/Adapters/AVFoundationInboxAudio.swift Sources/SuisuiApp/Views/InboxVoicePlaybackView.swift Sources/SuisuiApp/Views/ProjectWorkflowInboxView.swift Sources/SuisuiApp/Composition/VoiceRuntimeFactory.swift Sources/SuisuiApp/Composition/ProjectBoardRuntimeFactory.swift Tests/SuisuiAppTests/InboxAudioPlaybackTests.swift Tests/SuisuiCoreTests/InboxCaptureStoreTests.swift Tests/SuisuiCoreTests/AppExperienceSourceTests.swift Tests/SuisuiCoreTests/ReleasePipelineTests.swift script/check_runtime_inbox_voice_playback_smoke.sh script/generate_inbox_audio_fixture.swift script/check_accessibility_preflight.sh script/check_security_regressions.sh
git commit -m "fix(inbox): close voice playback validation gaps"
```

If validation produces no corrective diff, do not create an empty commit.
