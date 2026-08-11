import XCTest
@testable import SuisuiCore

final class InboxCaptureStoreTests: XCTestCase {
    @MainActor
    func testInboxVoiceCaptureServiceCreatesInboxTaskAndCaptureAfterSuccessfulTranscription() async throws {
        let stores = try makeStores()
        let service = InboxVoiceCaptureService(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "Create a task called launch checklist", duration: 3.5)),
            projectBoardStore: stores.board,
            inboxCaptureStore: stores.captures
        )

        try await service.startRecording(at: Date(timeIntervalSince1970: 100))
        let result = try await service.stopAndSave(
            outputURL: URL(filePath: "/Users/example/Library/Application Support/Suisui/InboxAudio/success.m4a"),
            at: Date(timeIntervalSince1970: 103),
            createdAt: "2026-06-21T10:25:00Z"
        )

        XCTAssertEqual(result.task.title, "Create a task called launch checklist")
        XCTAssertEqual(result.capture.transcript, "Create a task called launch checklist")
        XCTAssertEqual(result.capture.interpretationSummary, "Route as task.create for a reviewable local task draft.")
        XCTAssertTrue(result.capture.memo?.hasPrefix("Confidence: ") ?? false)
        XCTAssertEqual(result.capture.durationSeconds, 3)
        XCTAssertEqual(result.capture.transcriptionStatus, .succeeded)
        XCTAssertNil(result.transcriptionErrorMessage)
        XCTAssertEqual(try stores.captures.list(taskID: result.task.id), [result.capture])
    }

    @MainActor
    func testInboxVoiceCaptureServicePersistsAudioBeforeWritingCaptureRecord() throws {
        let stores = try makeStores()
        let managedURL = URL(filePath: "/Users/example/Library/Application Support/Suisui/InboxAudio/managed.m4a")
        let persister = RecordingInboxAudioPersister(managedURL: managedURL)
        let service = InboxVoiceCaptureService(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "Persist this recording", duration: 2)),
            projectBoardStore: stores.board,
            inboxCaptureStore: stores.captures,
            inboxAudioPersister: persister
        )

        let result = try service.saveTranscribedCapture(
            audio: RecordedAudio(fileURL: URL(filePath: "/tmp/suisui-recording.m4a"), format: .m4a, duration: 2),
            transcript: STTTranscript(text: "Persist this recording", duration: 2),
            at: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(result.capture.audioFilePath, managedURL.path)
        XCTAssertEqual(persister.importedSource, URL(filePath: "/tmp/suisui-recording.m4a"))
        XCTAssertEqual(persister.removedURLs, [])
    }

    @MainActor
    func testInboxVoiceCaptureServiceCompensatesManagedAudioAndTaskWhenCaptureInsertFails() throws {
        let stores = try makeStores()
        let persister = RecordingInboxAudioPersister(
            managedURL: URL(filePath: "/Users/example/Library/Application Support/Suisui/InboxAudio/failed.m4a")
        )
        let service = InboxVoiceCaptureService(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "Will fail", duration: 1)),
            projectBoardStore: stores.board,
            inboxCaptureStore: FailingInboxCaptureStore(),
            inboxAudioPersister: persister
        )

        XCTAssertThrowsError(
            try service.saveTranscribedCapture(
                audio: RecordedAudio(fileURL: URL(filePath: "/tmp/suisui-recording-failed.m4a"), format: .m4a, duration: 1),
                transcript: STTTranscript(text: "Will fail", duration: 1),
                at: Date(timeIntervalSince1970: 100)
            )
        )

        XCTAssertEqual(persister.removedURLs, [persister.managedURL])
        XCTAssertTrue(try stores.board.loadSnapshot().projects.flatMap(\.tasks).isEmpty)
    }

    @MainActor
    func testInboxVoiceCaptureServiceRedactsInterpretationInputsAndAppearsAsAISuggested() async throws {
        let stores = try makeStores()
        let router = RecordingVoiceCommandRouter(result: VoiceCommandRoutingResult(
            originalTranscript: "",
            normalizedTranscript: "",
            intent: .taskCreate,
            interpretationSummary: """
            Route as task.create with sk-proj-voiceSECRET123 token=voice-secret /Users/shutoide/Private /var/tmp/voice.log ~/Private/config.yml file:///Users/shutoide/Secret/file.txt
            """,
            confidence: 0.82,
            decision: .reviewOnly
        ))
        let service = InboxVoiceCaptureService(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(
                transcript: STTTranscript(
                    text: "  Create a task called launch checklist token=voice-secret /Users/shutoide/Private  ",
                    duration: 3.5
                )
            ),
            projectBoardStore: stores.board,
            inboxCaptureStore: stores.captures,
            commandRouter: router
        )

        try await service.startRecording(at: Date(timeIntervalSince1970: 100))
        let result = try await service.stopAndSave(
            outputURL: URL(filePath: "/Users/example/Library/Application Support/Suisui/InboxAudio/secret.m4a"),
            at: Date(timeIntervalSince1970: 103),
            createdAt: "2026-06-21T10:25:00Z"
        )
        let viewModel = ProjectBoardViewModel(store: stores.board, inboxCaptureStore: stores.captures)
        viewModel.load()
        viewModel.setInboxTriageFilter(.aiSuggested)

        XCTAssertEqual(router.routedTranscripts, ["Create a task called launch checklist token=voice-secret /Users/shutoide/Private"])
        XCTAssertTrue(result.capture.interpretationSummary?.contains("task.create") ?? false)
        XCTAssertFalse(result.capture.interpretationSummary?.contains("sk-proj-voiceSECRET123") ?? true)
        XCTAssertFalse(result.capture.interpretationSummary?.contains("voice-secret") ?? true)
        XCTAssertFalse(result.capture.interpretationSummary?.contains("/Users/shutoide") ?? true)
        XCTAssertFalse(result.capture.interpretationSummary?.contains("/var/tmp") ?? true)
        XCTAssertFalse(result.capture.interpretationSummary?.contains("~/Private") ?? true)
        XCTAssertFalse(result.capture.interpretationSummary?.contains("file:///Users") ?? true)
        XCTAssertEqual(result.capture.memo, "Confidence: 0.82")
        XCTAssertEqual(viewModel.filteredInboxTasks.map(\.id), [result.task.id])
        XCTAssertEqual(viewModel.inboxTriageSummary(for: result.task).interpretationLabel, "AI interpreted")
    }

    @MainActor
    func testInboxVoiceCaptureServiceKeepsInboxItemWhenTranscriptionFails() async throws {
        let stores = try makeStores()
        let router = RecordingVoiceCommandRouter(result: VoiceCommandRoutingResult(
            originalTranscript: "",
            normalizedTranscript: "",
            intent: .taskCreate,
            interpretationSummary: "Should not be saved",
            confidence: 0.9,
            decision: .reviewOnly
        ))
        let service = InboxVoiceCaptureService(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(
                availability: STTProviderAvailability(providerID: .whisperKit, isAvailable: false, reason: "Model missing for /secret/audio.m4a"),
                transcript: STTTranscript(text: "")
            ),
            projectBoardStore: stores.board,
            inboxCaptureStore: stores.captures,
            commandRouter: router
        )

        try await service.startRecording(at: Date(timeIntervalSince1970: 200))
        let result = try await service.stopAndSave(
            outputURL: URL(filePath: "/Users/example/Library/Application Support/Suisui/InboxAudio/failure.m4a"),
            at: Date(timeIntervalSince1970: 209),
            createdAt: "2026-06-21T10:30:00Z"
        )

        XCTAssertEqual(result.task.title, "Voice memo")
        XCTAssertNil(result.capture.transcript)
        XCTAssertNil(result.capture.interpretationSummary)
        XCTAssertNil(result.capture.memo)
        XCTAssertEqual(result.capture.transcriptionStatus, .failed)
        XCTAssertEqual(result.capture.retryTranscriptionActionTitle, "Retry Transcription")
        XCTAssertTrue(result.transcriptionErrorMessage?.contains("Model missing") == true)
        XCTAssertFalse(result.transcriptionErrorMessage?.contains("/secret/audio.m4a") ?? true)
        XCTAssertEqual(router.routedTranscripts, [])
        XCTAssertEqual(try stores.captures.list(taskID: result.task.id), [result.capture])
    }

    @MainActor
    func testInboxVoiceCaptureServiceDoesNotSuggestEmptyTranscripts() async throws {
        let stores = try makeStores()
        let router = RecordingVoiceCommandRouter(result: VoiceCommandRoutingResult(
            originalTranscript: "",
            normalizedTranscript: "",
            intent: .taskCreate,
            interpretationSummary: "Should not be saved",
            confidence: 0.9,
            decision: .reviewOnly
        ))
        let service = InboxVoiceCaptureService(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "   ", duration: 1)),
            projectBoardStore: stores.board,
            inboxCaptureStore: stores.captures,
            commandRouter: router
        )

        try await service.startRecording(at: Date(timeIntervalSince1970: 200))
        let result = try await service.stopAndSave(
            outputURL: URL(filePath: "/Users/example/Library/Application Support/Suisui/InboxAudio/empty.m4a"),
            at: Date(timeIntervalSince1970: 201),
            createdAt: "2026-06-21T10:26:00Z"
        )
        let viewModel = ProjectBoardViewModel(store: stores.board, inboxCaptureStore: stores.captures)
        viewModel.load()
        viewModel.setInboxTriageFilter(.aiSuggested)

        XCTAssertEqual(result.task.title, "Voice memo")
        XCTAssertNil(result.capture.interpretationSummary)
        XCTAssertNil(result.capture.memo)
        XCTAssertEqual(result.capture.transcriptionStatus, .failed)
        XCTAssertEqual(router.routedTranscripts, [])
        XCTAssertEqual(viewModel.filteredInboxTasks, [])
    }

    func testSQLiteInboxCaptureStorePersistsLoadsAndDeletesVoiceCaptureRecords() throws {
        let stores = try makeStores()
        let inboxID = try XCTUnwrap(stores.board.loadSnapshot().projects.first?.id)
        let task = try stores.board.createTask(ProjectBoardTaskDraft(
            projectID: inboxID,
            title: "Follow up from voice memo",
            status: .backlog
        ))

        let record = try stores.captures.createVoiceCapture(InboxVoiceCaptureDraft(
            taskID: task.id,
            audioFilePath: "/Users/example/Library/Application Support/Suisui/InboxAudio/voice-1.m4a",
            durationSeconds: 42.25,
            transcript: "Call supplier about launch date",
            interpretationSummary: "Likely task: call supplier",
            memo: "Captured after standup.",
            classificationStatus: .unclassified,
            transcriptionStatus: .succeeded,
            createdAt: "2026-06-21T10:00:00Z"
        ))

        let loaded = try stores.captures.get(id: record.id)
        XCTAssertEqual(loaded.taskID, task.id)
        XCTAssertEqual(loaded.sourceKind, .voiceMemo)
        XCTAssertEqual(loaded.audioFilePath, "/Users/example/Library/Application Support/Suisui/InboxAudio/voice-1.m4a")
        XCTAssertEqual(loaded.durationSeconds, 42.25)
        XCTAssertEqual(loaded.transcript, "Call supplier about launch date")
        XCTAssertEqual(loaded.interpretationSummary, "Likely task: call supplier")
        XCTAssertEqual(loaded.memo, "Captured after standup.")
        XCTAssertEqual(loaded.classificationStatus, .unclassified)
        XCTAssertEqual(loaded.transcriptionStatus, .succeeded)
        XCTAssertEqual(try stores.captures.list(taskID: task.id), [loaded])

        try stores.captures.delete(id: record.id)

        XCTAssertThrowsError(try stores.captures.get(id: record.id)) { error in
            XCTAssertEqual(error as? InboxCaptureStoreError, .notFound(record.id))
        }
    }

    func testSQLiteInboxCaptureStoreListsVoiceCapturesForTaskBatch() throws {
        let stores = try makeStores()
        let firstTask = try stores.board.createInboxTask(title: "First voice capture")
        let secondTask = try stores.board.createInboxTask(title: "Second voice capture")
        let emptyTask = try stores.board.createInboxTask(title: "No capture yet")
        let olderFirstCapture = try stores.captures.createVoiceCapture(InboxVoiceCaptureDraft(
            taskID: firstTask.id,
            audioFilePath: "/Users/example/Library/Application Support/Suisui/InboxAudio/first-old.m4a",
            durationSeconds: 6,
            transcript: "First old",
            interpretationSummary: nil,
            memo: nil,
            transcriptionStatus: .succeeded,
            createdAt: "2026-06-21T10:00:00Z"
        ))
        let newerFirstCapture = try stores.captures.createVoiceCapture(InboxVoiceCaptureDraft(
            taskID: firstTask.id,
            audioFilePath: "/Users/example/Library/Application Support/Suisui/InboxAudio/first-new.m4a",
            durationSeconds: 9,
            transcript: "First new",
            interpretationSummary: nil,
            memo: nil,
            transcriptionStatus: .succeeded,
            createdAt: "2026-06-21T10:05:00Z"
        ))
        let secondCapture = try stores.captures.createVoiceCapture(InboxVoiceCaptureDraft(
            taskID: secondTask.id,
            audioFilePath: "/Users/example/Library/Application Support/Suisui/InboxAudio/second.m4a",
            durationSeconds: 7,
            transcript: "Second",
            interpretationSummary: nil,
            memo: nil,
            transcriptionStatus: .succeeded,
            createdAt: "2026-06-21T10:10:00Z"
        ))

        let recordsByTaskID = try stores.captures.list(taskIDs: [firstTask.id, secondTask.id, emptyTask.id])

        XCTAssertEqual(Set(recordsByTaskID.keys), [firstTask.id, secondTask.id, emptyTask.id])
        XCTAssertEqual(recordsByTaskID[firstTask.id]?.map(\.id), [newerFirstCapture.id, olderFirstCapture.id])
        XCTAssertEqual(recordsByTaskID[secondTask.id]?.map(\.id), [secondCapture.id])
        XCTAssertEqual(recordsByTaskID[emptyTask.id], [])
        XCTAssertEqual(try stores.captures.list(taskIDs: []), [:])
    }

    func testSQLiteInboxCaptureStoreUpdatesVoiceCaptureMemo() throws {
        let stores = try makeStores()
        let task = try stores.board.createInboxTask(title: "Annotate capture")
        let record = try stores.captures.createVoiceCapture(InboxVoiceCaptureDraft(
            taskID: task.id,
            audioFilePath: "/Users/example/Library/Application Support/Suisui/InboxAudio/memo-update.m4a",
            durationSeconds: 14,
            transcript: "Clarify launch owner",
            interpretationSummary: "Likely task: clarify launch owner",
            memo: nil,
            classificationStatus: .unclassified,
            transcriptionStatus: .succeeded,
            createdAt: "2026-06-21T10:40:00Z"
        ))

        let updated = try stores.captures.updateMemo(id: record.id, memo: "  Needs owner review.  ")

        XCTAssertEqual(updated.memo, "Needs owner review.")
        XCTAssertEqual(try stores.captures.get(id: record.id).memo, "Needs owner review.")

        let cleared = try stores.captures.updateMemo(id: record.id, memo: "   ")

        XCTAssertNil(cleared.memo)
        XCTAssertNil(try stores.captures.get(id: record.id).memo)
    }

    func testFailedTranscriptionStillPersistsVoiceCaptureWithoutTranscript() throws {
        let stores = try makeStores()
        let task = try stores.board.createInboxTask(title: "Retry transcription later")

        let record = try stores.captures.createVoiceCapture(InboxVoiceCaptureDraft(
            taskID: task.id,
            audioFilePath: "/Users/example/Library/Application Support/Suisui/InboxAudio/failed.m4a",
            durationSeconds: 9,
            transcript: nil,
            interpretationSummary: nil,
            memo: nil,
            classificationStatus: .unclassified,
            transcriptionStatus: .failed,
            createdAt: "2026-06-21T10:05:00Z"
        ))

        XCTAssertEqual(record.transcriptionStatus, .failed)
        XCTAssertNil(record.transcript)
        XCTAssertEqual(record.retryTranscriptionActionTitle, "Retry Transcription")
        XCTAssertEqual(try stores.captures.list(taskID: task.id).map(\.id), [record.id])
    }

    func testSQLiteInboxCaptureStoreUsesCurrentTimestampWhenCreatedAtIsOmitted() throws {
        let stores = try makeStores()
        let task = try stores.board.createInboxTask(title: "Timestamp default")

        let record = try stores.captures.createVoiceCapture(InboxVoiceCaptureDraft(
            taskID: task.id,
            audioFilePath: "/Users/example/Library/Application Support/Suisui/InboxAudio/default-created-at.m4a",
            durationSeconds: 4,
            transcript: "Default timestamp",
            interpretationSummary: nil,
            memo: nil,
            transcriptionStatus: .succeeded
        ))

        XCTAssertFalse(record.createdAt.isEmpty)
        XCTAssertNotEqual(record.createdAt, "NULL")
    }

    @MainActor
    func testInboxClassificationUndoAndNextSelectionWorksForVoiceCaptureBackedTasks() throws {
        let stores = try makeStores()
        let viewModel = ProjectBoardViewModel(store: stores.board, inboxCaptureStore: stores.captures)
        viewModel.load()
        let inboxID = try XCTUnwrap(viewModel.inboxProject?.id)
        let plain = try XCTUnwrap(viewModel.createTask(title: "Plain capture", projectID: inboxID))
        let voiceTask = try XCTUnwrap(viewModel.createTask(title: "Voice capture", projectID: inboxID))
        _ = try stores.captures.createVoiceCapture(InboxVoiceCaptureDraft(
            taskID: voiceTask.id,
            audioFilePath: "/Users/example/Library/Application Support/Suisui/InboxAudio/voice-2.m4a",
            durationSeconds: 12,
            transcript: "Make launch checklist",
            interpretationSummary: nil,
            memo: nil,
            classificationStatus: .unclassified,
            transcriptionStatus: .succeeded,
            createdAt: "2026-06-21T10:10:00Z"
        ))

        viewModel.selectedTaskID = voiceTask.id
        viewModel.convertSelectedTaskToProject()

        XCTAssertEqual(viewModel.selectedTaskID, plain.id)
        XCTAssertEqual(viewModel.inboxClassificationFeedback?.canUndo, true)

        viewModel.undoLastInboxClassification()

        let restoredTask = try XCTUnwrap(viewModel.selectedTask)
        XCTAssertEqual(restoredTask.title, "Voice capture")
        XCTAssertEqual(restoredTask.projectID, inboxID)
        XCTAssertEqual(try stores.captures.list(taskID: restoredTask.id).first?.transcript, "Make launch checklist")
        // Atomic project conversion keeps the task identity, so the voice
        // capture remains linked without a delete/recreate relink dance.
        XCTAssertEqual(try stores.captures.list(taskID: voiceTask.id).count, 1)
    }

    @MainActor
    func testProjectBoardViewModelExposesSelectedVoiceCaptureMetadata() throws {
        let stores = try makeStores()
        let viewModel = ProjectBoardViewModel(store: stores.board, inboxCaptureStore: stores.captures)
        viewModel.load()
        let task = try XCTUnwrap(viewModel.createInboxTask(title: "Voice-backed inbox item"))
        _ = try stores.captures.createVoiceCapture(InboxVoiceCaptureDraft(
            taskID: task.id,
            audioFilePath: "/Users/example/Library/Application Support/Suisui/InboxAudio/voice-detail.m4a",
            durationSeconds: 18.5,
            transcript: "Draft launch checklist",
            interpretationSummary: "Create checklist task",
            memo: "Needs review",
            classificationStatus: .unclassified,
            transcriptionStatus: .succeeded,
            createdAt: "2026-06-21T10:20:00Z"
        ))
        viewModel.load()
        viewModel.selectedTaskID = task.id

        let metadata = try XCTUnwrap(viewModel.selectedInboxCaptureRecords.first)

        XCTAssertEqual(metadata.taskID, task.id)
        XCTAssertEqual(metadata.durationSeconds, 18.5)
        XCTAssertEqual(metadata.transcript, "Draft launch checklist")
        XCTAssertEqual(metadata.sourceKind, .voiceMemo)
        XCTAssertEqual(metadata.classificationStatus, .unclassified)
    }

    @MainActor
    func testProjectBoardViewModelUpdatesSelectedVoiceCaptureMemo() throws {
        let stores = try makeStores()
        let viewModel = ProjectBoardViewModel(store: stores.board, inboxCaptureStore: stores.captures)
        viewModel.load()
        let task = try XCTUnwrap(viewModel.createInboxTask(title: "Voice-backed inbox item"))
        _ = try stores.captures.createVoiceCapture(InboxVoiceCaptureDraft(
            taskID: task.id,
            audioFilePath: "/Users/example/Library/Application Support/Suisui/InboxAudio/voice-memo-note.m4a",
            durationSeconds: 18.5,
            transcript: "Draft launch checklist",
            interpretationSummary: "Create checklist task",
            memo: nil,
            classificationStatus: .unclassified,
            transcriptionStatus: .succeeded,
            createdAt: "2026-06-21T10:45:00Z"
        ))
        viewModel.load()
        viewModel.selectedTaskID = task.id

        let updated = try XCTUnwrap(viewModel.updateSelectedInboxCaptureMemo(" Confirm owner before converting. "))

        XCTAssertEqual(updated.memo, "Confirm owner before converting.")
        XCTAssertEqual(viewModel.selectedInboxCaptureRecords.first?.memo, "Confirm owner before converting.")
        XCTAssertEqual(
            viewModel.inboxClassificationFeedback,
            InboxClassificationFeedback(
                message: "Saved note for \"Voice-backed inbox item\".",
                systemImage: "note.text",
                canUndo: false
            )
        )
    }

    @MainActor
    func testProjectBoardViewModelBuildsInboxTriageSummariesForListRows() throws {
        let stores = try makeStores()
        let viewModel = ProjectBoardViewModel(store: stores.board, inboxCaptureStore: stores.captures)
        viewModel.load()

        let manual = try stores.board.createInboxTask(title: "Manual note")
        let failedVoice = try stores.board.createInboxTask(title: "Failed voice memo")
        _ = try stores.captures.createVoiceCapture(InboxVoiceCaptureDraft(
            taskID: failedVoice.id,
            audioFilePath: "/Users/example/Library/Application Support/Suisui/InboxAudio/failed-summary.m4a",
            durationSeconds: 9,
            transcript: nil,
            interpretationSummary: nil,
            memo: nil,
            classificationStatus: .unclassified,
            transcriptionStatus: .failed,
            createdAt: "2026-06-21T10:05:00Z"
        ))
        let interpretedVoice = try stores.board.createInboxTask(title: "AI interpreted voice memo")
        _ = try stores.captures.createVoiceCapture(InboxVoiceCaptureDraft(
            taskID: interpretedVoice.id,
            audioFilePath: "/Users/example/Library/Application Support/Suisui/InboxAudio/interpreted-summary.m4a",
            durationSeconds: 18,
            transcript: "Draft launch checklist",
            interpretationSummary: "Likely task: draft launch checklist",
            memo: "Confidence: high",
            classificationStatus: .unclassified,
            transcriptionStatus: .succeeded,
            createdAt: "2026-06-21T10:20:00Z"
        ))
        let failedWithStaleInterpretation = try stores.board.createInboxTask(title: "Failed voice with stale interpretation")
        _ = try stores.captures.createVoiceCapture(InboxVoiceCaptureDraft(
            taskID: failedWithStaleInterpretation.id,
            audioFilePath: "/Users/example/Library/Application Support/Suisui/InboxAudio/stale-ai.m4a",
            durationSeconds: 21,
            transcript: nil,
            interpretationSummary: "Stale interpretation from a previous provider run",
            memo: nil,
            classificationStatus: .unclassified,
            transcriptionStatus: .failed,
            createdAt: "2026-06-21T10:25:00Z"
        ))
        viewModel.load()

        XCTAssertEqual(
            viewModel.inboxTriageSummary(for: manual),
            InboxTriageSummary(
                sourceLabel: "Manual",
                interpretationLabel: "Manual",
                systemImage: "square.and.pencil",
                tintName: "secondary",
                accessibilityValue: "Source: Manual, Interpretation: Manual"
            )
        )
        XCTAssertEqual(
            viewModel.inboxTriageSummary(for: failedVoice),
            InboxTriageSummary(
                sourceLabel: "Voice",
                interpretationLabel: "Transcript failed",
                systemImage: "waveform.badge.exclamationmark",
                tintName: "red",
                accessibilityValue: "Source: Voice, Interpretation: Transcript failed"
            )
        )
        XCTAssertEqual(
            viewModel.inboxTriageSummary(for: interpretedVoice),
            InboxTriageSummary(
                sourceLabel: "Voice",
                interpretationLabel: "AI interpreted",
                systemImage: "sparkles",
                tintName: "blue",
                accessibilityValue: "Source: Voice, Interpretation: AI interpreted, Confidence: high"
            )
        )
        viewModel.setInboxTriageFilter(.aiSuggested)
        XCTAssertEqual(viewModel.filteredInboxTasks.map(\.id), [interpretedVoice.id])
    }

    func testCaptureValidationRedactsTranscriptAndAudioPathFromUserFacingErrors() throws {
        let stores = try makeStores()
        let secretPath = "/Users/example/Library/Application Support/Suisui/InboxAudio/secret-client-call.m4a"
        let transcript = "Call Alice about confidential launch terms"

        XCTAssertThrowsError(
            try stores.captures.createVoiceCapture(InboxVoiceCaptureDraft(
                taskID: 999_999,
                audioFilePath: secretPath,
                durationSeconds: 10,
                transcript: transcript,
                interpretationSummary: "Potential task",
                memo: nil,
                classificationStatus: .unclassified,
                transcriptionStatus: .succeeded,
                createdAt: "2026-06-21T10:15:00Z"
            ))
        ) { error in
            let message = InboxCaptureStoreError.userMessage(for: error)
            XCTAssertFalse(message.contains(secretPath))
            XCTAssertFalse(message.contains(transcript))
            XCTAssertEqual(message, "Inbox capture could not be saved. Confirm the linked Inbox task still exists.")
        }
    }

    @MainActor
    func testInboxVoiceCaptureServiceDefaultsCaptureCreatedAtToStopDate() async throws {
        let stores = try makeStores()
        let stopDate = Date(timeIntervalSince1970: 300)
        let service = InboxVoiceCaptureService(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "Schedule launch review", duration: 4)),
            projectBoardStore: stores.board,
            inboxCaptureStore: stores.captures
        )

        try await service.startRecording(at: Date(timeIntervalSince1970: 296))
        let result = try await service.stopAndSave(
            outputURL: URL(filePath: "/Users/example/Library/Application Support/Suisui/InboxAudio/default-date.m4a"),
            at: stopDate
        )

        XCTAssertEqual(result.capture.createdAt, ISO8601DateFormatter().string(from: stopDate))
    }

    private func makeStores() throws -> (
        connection: SQLiteConnection,
        board: SQLiteProjectBoardStore,
        captures: SQLiteInboxCaptureStore
    ) {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        return (
            connection,
            SQLiteProjectBoardStore(connection: connection),
            SQLiteInboxCaptureStore(connection: connection)
        )
    }
}

@MainActor
private final class RecordingInboxAudioPersister: InboxAudioPersisting {
    let managedURL: URL
    private(set) var importedSource: URL?
    private(set) var removedURLs: [URL] = []

    init(managedURL: URL) {
        self.managedURL = managedURL
    }

    func importRecording(from sourceURL: URL) throws -> URL {
        importedSource = sourceURL
        return managedURL
    }

    func removeImportedRecording(at url: URL) {
        removedURLs.append(url)
    }
}

private final class FailingInboxCaptureStore: InboxCaptureStore {
    func createVoiceCapture(_ draft: InboxVoiceCaptureDraft) throws -> InboxCaptureRecord {
        throw InboxCaptureStoreError.linkedTaskMissing
    }

    func get(id: Int64) throws -> InboxCaptureRecord {
        throw InboxCaptureStoreError.notFound(id)
    }

    func list(taskID: Int64) throws -> [InboxCaptureRecord] { [] }

    func list(taskIDs: Set<Int64>) throws -> [Int64: [InboxCaptureRecord]] { [:] }

    func updateMemo(id: Int64, memo: String?) throws -> InboxCaptureRecord {
        throw InboxCaptureStoreError.notFound(id)
    }

    func relinkCaptures(fromTaskID: Int64, toTaskID: Int64) throws -> Int { 0 }

    func delete(id: Int64) throws {}
}

private final class RecordingVoiceCommandRouter: VoiceCommandRouting, @unchecked Sendable {
    private let result: VoiceCommandRoutingResult
    private let lock = NSLock()
    private var recordedTranscripts: [String] = []

    var routedTranscripts: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedTranscripts
    }

    init(result: VoiceCommandRoutingResult) {
        self.result = result
    }

    func route(transcript: String) -> VoiceCommandRoutingResult {
        lock.lock()
        recordedTranscripts.append(transcript)
        lock.unlock()
        return result
    }
}
