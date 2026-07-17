import Foundation
import SoloPMCore
import SwiftUI

struct VoiceCaptureView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var viewModel: VoiceCaptureViewModel
    @State private var clarificationAnswer = ""

    init(viewModel: VoiceCaptureViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    private var isVoiceCommandInputEmpty: Bool {
        viewModel.draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var actionReadinessMessage: String {
        switch viewModel.phase {
        case .recording:
            String(localized: "Stop recording to transcribe before Inbox capture or planning.")
        case .transcribing:
            String(localized: "Transcription is running; Save to Inbox unlocks after the recording is transcribed.")
        case .generatingPlan:
            String(localized: "Plan generation is running; review appears below before execution.")
        case .needsClarification:
            String(localized: "Answer the clarification question before saving or generating a plan.")
        case .failed:
            String(localized: "Resolve the current voice warning before saving or generating a plan.")
        case .idle, .reviewReady:
            if isVoiceCommandInputEmpty {
                String(localized: "Type a command to generate a plan, or record audio to save a transcript to Inbox.")
            } else if viewModel.canSaveDraftToInbox && viewModel.canGeneratePlan {
                String(localized: "Save the transcript to Inbox, or generate an approval-gated plan.")
            } else if viewModel.canGeneratePlan {
                String(localized: "Typed commands can generate approval-gated plans. Record audio first to save a voice capture to Inbox.")
            } else {
                String(localized: "Review the command before choosing Inbox capture or an approval-gated plan.")
            }
        }
    }

    /// Zone 2 ("Working") renders only while the command is being interpreted:
    /// streaming plan text, an open clarification question, a routed intent,
    /// or an in-flight/finished workspace answer.
    private var hasWorkingContent: Bool {
        (viewModel.phase == .generatingPlan && !viewModel.planGenerationLiveText.isEmpty)
            || viewModel.clarificationQuestion != nil
            || viewModel.routingResult != nil
            || viewModel.workspaceAnswer != .idle
    }

    private var isWorkspaceAnswerBusy: Bool {
        viewModel.workspaceAnswer == .retrieving || viewModel.workspaceAnswer == .answering
    }

    /// Zone 3 ("Review") renders only when there is an approval-gated result
    /// to inspect, so the capture zone keeps the window to itself otherwise.
    private var hasReviewContent: Bool {
        viewModel.dailyPlanningReviewRequest != nil
            || viewModel.inboxTriageRequest != nil
            || viewModel.inboxCaptureResult != nil
            || viewModel.assistantQueueItem != nil
            || viewModel.planningResponse != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SoloPMSpacing.md) {
            HStack {
                // Structural identifiers stay on leaf headings. SwiftUI
                // propagates container identifiers into descendants, which
                // would hide action and mode-control identifiers from AX.
                Label("Voice Command", systemImage: "mic")
                    .font(.headline)
                    .accessibilityIdentifier("voice-command-root")
                Spacer()
                Button {
                    viewModel.clear()
                    clarificationAnswer = ""
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
                .disabled(viewModel.draft.text.isEmpty && viewModel.planningResponse == nil)
                .accessibilityIdentifier("voice-command-clear")
            }

            captureZone

            ScrollView {
                VStack(alignment: .leading, spacing: SoloPMSpacing.md) {
                    if hasWorkingContent {
                        workingZone
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if hasReviewContent {
                        reviewZone
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Zones fade/slide in briefly as they appear; Reduce Motion
                // disables the animation so state changes apply instantly.
                .animation(
                    SoloPMMotion.animation(duration: SoloPMMotion.standard, reduceMotion: reduceMotion),
                    value: hasWorkingContent
                )
                .animation(
                    SoloPMMotion.animation(duration: SoloPMMotion.standard, reduceMotion: reduceMotion),
                    value: hasReviewContent
                )
            }
            // While idle there is no working/review content; collapsing the
            // empty scroll region hands the window height to the capture zone
            // above instead of rendering it as blank space.
            .frame(
                maxWidth: .infinity,
                maxHeight: hasWorkingContent || hasReviewContent ? .infinity : 0,
                alignment: .topLeading
            )
        }
        .padding(SoloPMSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: viewModel.dailyPlanningReviewRequest) { _, request in
            guard let request else {
                return
            }
            postDailyPlanningReviewRequest(request)
        }
        .onChange(of: viewModel.inboxTriageRequest) { _, request in
            guard let request else {
                return
            }
            postInboxTriageRequest(request)
        }
    }

    /// Whether the tappable example commands render: only while the command
    /// field is empty and no capture path (push-to-record or the hands-free
    /// voice agent) is currently filling it.
    private var isExampleCommandRowVisible: Bool {
        isVoiceCommandInputEmpty
            && !viewModel.isRecording
            && !viewModel.isLowLatencyVoiceAgentListening
    }

    /// Recording gate for the hero microphone, unchanged from the previous
    /// Record button: no new capture while a plan is generating, a
    /// transcription is running, or the hands-free voice agent is listening.
    private var isHeroRecordDisabled: Bool {
        viewModel.phase == .generatingPlan || viewModel.phase == .transcribing || viewModel.isLowLatencyVoiceAgentListening
    }

    /// Hero capture affordance: a large circular microphone button centered
    /// above the input, with the current phase word beneath it. While a
    /// recording is live the glyph swaps to a stop square and the input level
    /// meter renders directly under the status word.
    private var heroCaptureControl: some View {
        VStack(spacing: SoloPMSpacing.sm) {
            Button {
                if viewModel.isRecording {
                    Task {
                        await viewModel.stopRecording(
                            outputURL: recordingOutputURL()
                        )
                    }
                } else {
                    Task {
                        await viewModel.startRecording()
                    }
                }
            } label: {
                Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(viewModel.isRecording ? AnyShapeStyle(Color.white) : AnyShapeStyle(.tint))
                    .frame(width: 64, height: 64)
                    .background(
                        Circle()
                            .fill(viewModel.isRecording ? AnyShapeStyle(.tint) : AnyShapeStyle(SoloPMBrand.soloBlue.opacity(0.14)))
                    )
                    .contentShape(Circle())
                    .opacity(isHeroRecordDisabled ? 0.45 : 1)
            }
            .buttonStyle(.plain)
            .disabled(isHeroRecordDisabled)
            .help("Records audio, then transcribes it into the command field.")
            .accessibilityLabel(localizedSettingsDisplay(viewModel.isRecording ? "Stop recording" : "Record once"))
            .accessibilityIdentifier("voice-command-record")

            Label("Record once", systemImage: "waveform.badge.mic")
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("voice-command-capture-zone")

            StatusRow(phase: viewModel.phase)

            if viewModel.isRecording {
                VoiceInputLevelMeter(meter: viewModel.inputLevelMeter)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Zone 1: everything needed to enter a command and start work, grouped in
    /// one card so it reads as a single surface above the working/review zones.
    /// The microphone is the visual anchor; example commands sit between it and
    /// the input so an empty window still reads as a guided capture surface.
    private var captureZone: some View {
        VStack(alignment: .leading, spacing: SoloPMSpacing.md) {
            heroCaptureControl
            failureRecoveryRow
            if let message = viewModel.auditErrorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(SoloPMTone.attention.color)
            }

            if isExampleCommandRowVisible {
                VoiceCommandExampleChips { example in
                    viewModel.updateDraftText(example)
                }
            }

            TextField(
                "",
                text: Binding(
                    get: { viewModel.draft.text },
                    set: { viewModel.updateDraftText($0) }
                ),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.body)
            .lineLimit(5...8)
            .padding(8)
            // The input area absorbs leftover window height (content stays
            // top-aligned) so the idle window reads as one intentional
            // capture surface instead of leaving a dead lower half.
            .frame(minHeight: 150, idealHeight: 180, maxHeight: .infinity, alignment: .topLeading)
            .overlay(alignment: .topLeading) {
                if isVoiceCommandInputEmpty {
                    VoiceCommandInputPrompt()
                        .padding(.top, 8)
                        .padding(.horizontal, 8)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: SoloPMRadius.control)
                    .stroke(.quaternary)
            }
            .accessibilityIdentifier("voice-command-input")

            VoiceCommandActionReadinessRow(message: actionReadinessMessage)

            LowLatencyVoiceAgentPanel(viewModel: viewModel)

            HStack {
                Button {
                    viewModel.saveDraftToInbox()
                    if viewModel.inboxCaptureResult != nil {
                        NotificationCenter.default.post(name: .soloPMProjectBoardDidChange, object: nil)
                    }
                } label: {
                    Label("Save to Inbox", systemImage: "tray.and.arrow.down")
                }
                .disabled(!viewModel.canSaveDraftToInbox || viewModel.isLowLatencyVoiceAgentListening)
                .accessibilityIdentifier("voice-command-save-to-inbox")

                Button {
                    Task {
                        await viewModel.askWorkspaceQuestion()
                    }
                } label: {
                    Label("Ask", systemImage: "questionmark.bubble")
                }
                .disabled(
                    isVoiceCommandInputEmpty
                        || viewModel.phase == .recording
                        || viewModel.phase == .transcribing
                        || viewModel.phase == .generatingPlan
                        || isWorkspaceAnswerBusy
                )
                .accessibilityIdentifier("voice-ask-button")
                .accessibilityHint("Answers a question from local workspace data using the configured AI provider.")

                Spacer()

                Button {
                    Task {
                        await viewModel.generatePlan()
                    }
                } label: {
                    Label("Generate Plan", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canGeneratePlan || viewModel.phase == .generatingPlan || viewModel.phase == .recording || viewModel.phase == .transcribing || viewModel.isLowLatencyVoiceAgentListening)
                .help(localizedSettingsDisplay(actionReadinessMessage))
                .accessibilityIdentifier("voice-command-generate-plan")
                .accessibilityHint(localizedSettingsDisplay(actionReadinessMessage))
            }

            if viewModel.isMicrophoneSilenceHintVisible {
                Label("No microphone input detected. Check your input device in System Settings.", systemImage: "mic.slash")
                    .font(.caption)
                    .foregroundStyle(SoloPMTone.attention.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("voice-silence-hint")
            }
        }
        .soloCard()
    }

    /// Next-step affordance next to a failed status: Open Settings when the
    /// provider is unconfigured or unapproved, Try Again for transient
    /// network-style provider failures. Derived from the typed error in the
    /// view model, never from the failure message text.
    @ViewBuilder
    private var failureRecoveryRow: some View {
        if case .failed = viewModel.phase {
            switch viewModel.failureRecovery {
            case .openSettings:
                SettingsLink {
                    Label("Open Settings", systemImage: "gearshape")
                }
                .help("Opens Settings to choose an AI provider and store its API key in Keychain.")
                .accessibilityIdentifier("voice-error-open-settings")
            case .retryPlanGeneration:
                Button {
                    Task {
                        await viewModel.generatePlan()
                    }
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                }
                .help("Runs plan generation again with the current transcript.")
                .accessibilityIdentifier("voice-error-retry")
                .accessibilityHint("Generates the plan again using the same transcript.")
            case nil:
                EmptyView()
            }
        }
    }

    /// Zone 2: transient interpretation state. Panels self-title, so the zone
    /// stays header-free and simply stacks whichever surface is active.
    @ViewBuilder
    private var workingZone: some View {
        VStack(alignment: .leading, spacing: SoloPMSpacing.sm) {
            if viewModel.phase == .generatingPlan && !viewModel.planGenerationLiveText.isEmpty {
                PlanGenerationLivePreview(text: viewModel.planGenerationLiveText)
            }

            if let routingResult = viewModel.routingResult {
                VoiceIntentPreview(result: routingResult)
            }

            workspaceAnswerZone

            if let question = viewModel.clarificationQuestion {
                ClarificationPanel(
                    question: question,
                    turns: viewModel.clarificationSession?.turns ?? [],
                    answerText: $clarificationAnswer,
                    onSubmit: { answer in
                        Task {
                            await viewModel.submitClarificationAnswer(answer)
                            clarificationAnswer = ""
                        }
                    },
                    onCancel: {
                        viewModel.cancelClarification()
                        clarificationAnswer = ""
                    }
                )
            }
        }
        .accessibilityIdentifier("voice-command-working-zone")
    }

    /// Workspace Q&A state inside the working zone: progress while
    /// retrieving/answering, the answer card, or an attention-tone failure.
    @ViewBuilder
    private var workspaceAnswerZone: some View {
        switch viewModel.workspaceAnswer {
        case .idle:
            EmptyView()
        case .retrieving:
            HStack(spacing: SoloPMSpacing.sm) {
                ProgressView()
                    .controlSize(.small)
                Text("Searching your workspace")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("voice-answer-retrieving")
        case .answering:
            HStack(spacing: SoloPMSpacing.sm) {
                ProgressView()
                    .controlSize(.small)
                Text("Composing answer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("voice-answer-answering")
        case .answered(let text, let contextCount):
            WorkspaceAnswerPanel(answer: text, contextCount: contextCount) {
                viewModel.replayWorkspaceAnswer()
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: SoloPMSpacing.xs) {
                Label(localizedSettingsDisplay(message), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(SoloPMTone.attention.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("voice-answer-failed")
                Button {
                    Task {
                        await viewModel.askWorkspaceQuestion()
                    }
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                }
                .help("Asks the workspace question again with the current text.")
                .accessibilityIdentifier("voice-answer-retry")
                .accessibilityHint("Retries the workspace question with the same text.")
            }
        }
    }

    /// Zone 3: approval-gated outcomes. A small secondary header marks the
    /// review boundary; each panel keeps its own title and actions.
    @ViewBuilder
    private var reviewZone: some View {
        VStack(alignment: .leading, spacing: SoloPMSpacing.sm) {
            Label("Review", systemImage: "checklist")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("voice-command-review-header")

            if let request = viewModel.dailyPlanningReviewRequest {
                VoiceDailyPlanningReviewRequestPanel(request: request) {
                    postDailyPlanningReviewRequest(request)
                }
            }

            if let request = viewModel.inboxTriageRequest {
                VoiceInboxTriageRequestPanel(request: request) {
                    postInboxTriageRequest(request)
                }
            }

            if let result = viewModel.inboxCaptureResult {
                VoiceInboxCaptureSavedPanel(result: result) {
                    _ = ProjectBoardSceneCoordinator.shared.requestOpen(route: .primary(.inbox))
                    openWindow(id: "project-board")
                }
            }

            if let item = viewModel.assistantQueueItem {
                AssistantQueuePanel(
                    item: item,
                    executionHandoffItemID: viewModel.assistantQueueExecutionHandoffItemID,
                    onApprove: { viewModel.approveAssistantQueueItem() },
                    onDefer: { viewModel.deferAssistantQueueItem() },
                    onReject: { viewModel.rejectAssistantQueueItem() },
                    onOpenQueue: { postAssistantQueueOpenRequest() }
                )
            }

            if let autoCreatedTask = viewModel.autoCreatedTask {
                VStack(alignment: .leading, spacing: SoloPMSpacing.xs) {
                    Label("Task created", systemImage: "checkmark.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(verbatim: autoCreatedTask.title)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        viewModel.undoAutoCreatedTask()
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                    }
                    .accessibilityIdentifier("voice-auto-created-undo")
                    .accessibilityHint("Deletes the automatically created task.")
                }
                .soloCard()
                .accessibilityIdentifier("voice-auto-created-banner")
            }

            if let response = viewModel.planningResponse {
                ActionPlanPreview(response: response)
                    .soloCard()
            }
        }
        .accessibilityIdentifier("voice-command-review-zone")
    }

    private func recordingOutputURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("solopm-recording-\(UUID().uuidString).m4a")
    }

    private func postDailyPlanningReviewRequest(_ request: VoiceDailyPlanningReviewRequest) {
        openWindow(id: "project-board")
        let route: BoardRoute = request.requestedActionDraftKind == nil
            ? .primary(.today)
            : .review(.assistantQueue)
        guard let bridgeRequest = SoloPMVoiceDailyPlanningReviewBridge.storePendingRequest(request) else {
            return
        }
        guard ProjectBoardSceneCoordinator.shared.requestOpen(id: request.id, route: route) != nil else {
            SoloPMVoiceDailyPlanningReviewBridge.discardPendingRequest(id: bridgeRequest.id)
            return
        }
        NotificationCenter.default.post(
            name: .soloPMVoiceDailyPlanningReviewRequested,
            object: nil,
            userInfo: [SoloPMVoiceDailyPlanningReviewBridge.requestUserInfoKey: bridgeRequest]
        )
    }

    private func postInboxTriageRequest(_ request: VoiceInboxTriageRequest) {
        openWindow(id: "project-board")
        guard let bridgeRequest = SoloPMVoiceInboxTriageBridge.storePendingRequest(request) else {
            return
        }
        guard ProjectBoardSceneCoordinator.shared.requestOpen(
            id: request.id,
            route: .primary(.inbox)
        ) != nil else {
            SoloPMVoiceInboxTriageBridge.discardPendingRequest(id: bridgeRequest.id)
            return
        }
        NotificationCenter.default.post(
            name: .soloPMVoiceInboxTriageRequested,
            object: nil,
            userInfo: [SoloPMVoiceInboxTriageBridge.requestUserInfoKey: bridgeRequest]
        )
    }

    private func postAssistantQueueOpenRequest() {
        guard let bridgeRequest = SoloPMAssistantQueueBridge.storePendingOpen(itemID: viewModel.assistantQueueExecutionHandoffItemID) else {
            return
        }
        guard ProjectBoardSceneCoordinator.shared.requestOpen(
            id: bridgeRequest.id,
            route: .review(.assistantQueue)
        ) != nil else {
            SoloPMAssistantQueueBridge.discardPendingOpen(id: bridgeRequest.id)
            return
        }
        openWindow(id: "project-board")
        NotificationCenter.default.post(
            name: .soloPMAssistantQueueRequested,
            object: nil,
            userInfo: [SoloPMAssistantQueueBridge.requestUserInfoKey: bridgeRequest]
        )
    }
}

/// Tail of the provider's raw streamed output while a plan is generating,
/// so the wait feels alive and obviously in progress. The full response is
/// replaced by the structured plan preview once parsing completes.
private struct PlanGenerationLivePreview: View {
    let text: String

    private var tailText: String {
        String(text.suffix(600))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SoloPMSpacing.xs) {
            Label("Drafting plan", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(verbatim: tailText)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(6)
                .truncationMode(.head)
        }
        .soloCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("voice-plan-live-preview")
    }
}

/// Written result of a workspace question with a replay control, so the
/// spoken answer can be re-read without asking the provider again.
private struct WorkspaceAnswerPanel: View {
    let answer: String
    let contextCount: Int
    let onSpeak: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SoloPMSpacing.xs) {
            Label("Answer", systemImage: "text.bubble")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(verbatim: answer)
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(localizedDisplay("Based on %d workspace items", contextCount))
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                onSpeak()
            } label: {
                Label("Speak", systemImage: "speaker.wave.2")
            }
            .accessibilityIdentifier("voice-answer-speak")
            .accessibilityHint("Speaks the workspace answer with the local text-to-speech voice.")
        }
        .soloCard()
        .accessibilityIdentifier("voice-answer-panel")
    }
}

private struct LowLatencyVoiceAgentPanel: View {
    @ObservedObject var viewModel: VoiceCaptureViewModel

    private var isBusyOutsideVoiceAgent: Bool {
        switch viewModel.phase {
        case .recording, .transcribing, .generatingPlan:
            true
        case .idle, .needsClarification, .reviewReady, .failed:
            false
        }
    }

    /// A single compact status line instead of the previous boxed card: the
    /// hands-free recognition mode is secondary to the hero microphone, so it
    /// reads as one caption row with its Start/Stop control trailing. Live
    /// transcript and intent lines still appear beneath while listening.
    var body: some View {
        VStack(alignment: .leading, spacing: SoloPMSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: SoloPMSpacing.sm) {
                Label("Hands-free mode", systemImage: "waveform")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("voice-agent-panel")

                Label(stateLabel, systemImage: stateSystemImage)
                    .font(.caption)
                    .foregroundStyle(stateTone)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("voice-agent-status")

                Spacer(minLength: SoloPMSpacing.sm)

                if viewModel.isLowLatencyVoiceAgentListening {
                    Button {
                        viewModel.stopLowLatencyVoiceAgentMode()
                    } label: {
                        Label("Stop", systemImage: "stop.circle")
                    }
                    .controlSize(.small)
                    .accessibilityLabel("Stop Hands-free mode")
                    .accessibilityIdentifier("voice-agent-stop")
                } else {
                    Button {
                        Task {
                            await viewModel.startLowLatencyVoiceAgentMode()
                        }
                    } label: {
                        Label("Start", systemImage: "play.circle")
                    }
                    .controlSize(.small)
                    .disabled(isBusyOutsideVoiceAgent)
                    .help("Starts continuous hands-free recognition, separate from push-to-record.")
                    .accessibilityLabel("Start Hands-free mode")
                    .accessibilityIdentifier("voice-agent-start")
                }
            }

            Text(localizedDisplay("Speech provider: %@", viewModel.handsFreeModeProviderName))
            .font(.caption2)
            .foregroundStyle(.secondary)

            Text("Audio is processed by the selected speech-to-text provider only while Hands-free mode is listening.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("voice-hands-free-provider-privacy")

            if !viewModel.liveTranscript.isEmpty {
                liveTranscriptText
                    .font(.caption)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("voice-agent-live-transcript")
            }

            if let preview = viewModel.liveIntentPreview {
                Label(preview.interpretationSummary, systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("voice-agent-live-intent")
            }
        }
    }

    /// Finalized speech renders in primary color; the trailing partial segment
    /// that may still change renders secondary until STT finalizes it.
    private var liveTranscriptText: Text {
        let finalized = Text(verbatim: viewModel.finalizedTranscript)
            .foregroundStyle(.primary)
        let pending = Text(verbatim: viewModel.pendingTranscript)
            .foregroundStyle(.secondary)
        if viewModel.finalizedTranscript.isEmpty {
            return pending
        }
        if viewModel.pendingTranscript.isEmpty {
            return finalized
        }
        return finalized + Text(verbatim: " ") + pending
    }

    private var stateLabel: String {
        switch viewModel.lowLatencyVoiceAgentState {
        case .idle:
            // Display-only mapping: the .idle state name stays internal while the
            // status line speaks user language ("Ready", ja: 待機中). The key is
            // distinct because "Ready" already exists with a different ja reading.
            String(localized: "voice-agent-status-ready", defaultValue: "Ready")
        case .listening:
            String(localized: "Listening")
        case .disabled(let message), .unavailable(let message), .failed(let message):
            localizedSettingsDisplay(message)
        }
    }

    private var stateSystemImage: String {
        switch viewModel.lowLatencyVoiceAgentState {
        case .idle:
            "pause.circle"
        case .listening:
            "waveform.circle"
        case .disabled, .unavailable:
            "lock.circle"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    private var stateTone: Color {
        switch viewModel.lowLatencyVoiceAgentState {
        case .failed:
            SoloPMTone.danger.color
        case .disabled, .unavailable:
            .secondary
        case .idle, .listening:
            .primary
        }
    }
}

/// Compact five-bar microphone level indicator shown while recording. It
/// observes only the dedicated level slice so the ~10Hz samples re-render this
/// small view instead of the whole voice capture window. With Reduce Motion
/// enabled the animated bars become a static localized "Recording" chip.
private struct VoiceInputLevelMeter: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var meter: MicrophoneInputLevelMeter

    /// Fill thresholds for each bar; the first lights up on faint input so a
    /// live microphone is visibly distinct from silence.
    private static let barThresholds: [Double] = [0.05, 0.2, 0.4, 0.6, 0.8]

    var body: some View {
        Group {
            if reduceMotion {
                Text("Recording")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(SoloPMSurface.groupedContent, in: Capsule())
            } else {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(Self.barThresholds.enumerated()), id: \.offset) { index, threshold in
                        Capsule()
                            .fill(meter.inputLevel >= threshold ? AnyShapeStyle(.tint) : SoloPMSurface.groupedContent)
                            .frame(width: 4, height: 8 + CGFloat(index) * 3)
                    }
                }
                .animation(
                    SoloPMMotion.animation(duration: SoloPMMotion.quick, reduceMotion: reduceMotion),
                    value: meter.inputLevel
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Microphone input level")
        .accessibilityIdentifier("voice-input-level-meter")
    }
}

private struct VoiceCommandInputPrompt: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Placeholder guidance stays at .secondary or stronger; .tertiary
            // fails readable contrast against the card background. The example
            // commands moved out of this passive overlay into the tappable
            // VoiceCommandExampleChips row above the input.
            Text("Type a command, or tap the microphone above to dictate one.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Inbox captures stay local. Plans wait in Assistant Queue before execution.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("voice-command-input-prompt")
    }
}

/// Tappable example commands shown while the command field is empty. Each chip
/// inserts its localized text into the input for editing or running — tapping
/// never executes anything by itself.
private struct VoiceCommandExampleChips: View {
    let onInsert: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SoloPMSpacing.xs) {
            Text("Try one of these commands")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("voice-command-example-chips")
            HStack(spacing: SoloPMSpacing.sm) {
                exampleChip(
                    String(localized: "Capture follow-up for launch review"),
                    systemImage: "tray",
                    index: 1
                )
                exampleChip(
                    String(localized: "Plan tomorrow: review release risks"),
                    systemImage: "checklist",
                    index: 2
                )
            }
        }
    }

    private func exampleChip(_ text: String, systemImage: String, index: Int) -> some View {
        Button {
            onInsert(text)
        } label: {
            Label(text, systemImage: systemImage)
                .font(.caption)
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .help("Inserts the example into the command field without running it.")
        .accessibilityIdentifier("voice-example-\(index)")
    }
}

private struct VoiceCommandActionReadinessRow: View {
    let message: String

    var body: some View {
        Label(localizedSettingsDisplay(message), systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("voice-command-action-readiness")
    }
}

private struct VoiceInboxCaptureSavedPanel: View {
    let result: InboxVoiceCaptureResult
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(localizedSettingsDisplay("Saved to Inbox"), systemImage: "tray.full")
                .font(.subheadline)

            Label(result.task.title, systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let summary = result.capture.interpretationSummary {
                Label(summary, systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                onOpen()
            } label: {
                Label(localizedSettingsDisplay("Open Inbox"), systemImage: "arrow.forward.circle")
            }
            .accessibilityIdentifier("voice-inbox-capture-open-board")
        }
        .padding(10)
        .background(SoloPMSurface.groupedContent, in: RoundedRectangle(cornerRadius: SoloPMRadius.control))
        .accessibilityIdentifier("voice-inbox-capture-saved")
    }
}

private struct VoiceDailyPlanningReviewRequestPanel: View {
    let request: VoiceDailyPlanningReviewRequest
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(localizedSettingsDisplay("Daily Planning Review"), systemImage: "sun.max")
                .font(.subheadline)

            Text(localizedSettingsDisplay("Opening a local Today review. No provider, Calendar, Reminder, connector, or file write is run."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let requestedActionDraftKind = request.requestedActionDraftKind {
                Label(localizedSettingsDisplay(actionDraftLabel(for: requestedActionDraftKind)), systemImage: "checklist")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !request.sourceTranscript.isEmpty {
                Label(request.sourceTranscript, systemImage: "quote.bubble")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                onOpen()
            } label: {
                Label(localizedSettingsDisplay("Open Today Review"), systemImage: "arrow.forward.circle")
            }
            .accessibilityIdentifier("voice-daily-planning-open-board")
        }
        .soloAssistantSignal()
        .accessibilityIdentifier("voice-daily-planning-request")
    }

    private func actionDraftLabel(for kind: DailyPlanningActionDraftKind) -> String {
        switch kind {
        case .startRecommended:
            "Queue a start-task draft for approval"
        case .deferRecommendedToTomorrow:
            "Queue a defer-to-tomorrow draft for approval"
        case .moveRecommendedDueDateToToday:
            "Queue a move-to-today draft for approval"
        case .splitRecommendedTask:
            "Queue a split-task draft for approval"
        }
    }
}

private struct VoiceInboxTriageRequestPanel: View {
    let request: VoiceInboxTriageRequest
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(localizedSettingsDisplay("Inbox Voice Triage"), systemImage: "tray.and.arrow.down")
                .font(.subheadline)

            Text(localizedSettingsDisplay("Applying a local Inbox command. No provider, Calendar, Reminder, connector, or file write is run."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Label(localizedSettingsDisplay(request.command.action.accessibilityLabel), systemImage: "waveform")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if !request.sourceTranscript.isEmpty {
                Label(request.sourceTranscript, systemImage: "quote.bubble")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                onOpen()
            } label: {
                Label(localizedSettingsDisplay("Open Inbox"), systemImage: "arrow.forward.circle")
            }
            .accessibilityIdentifier("voice-inbox-triage-open-board")
        }
        .padding(10)
        .background(SoloPMSurface.groupedContent, in: RoundedRectangle(cornerRadius: SoloPMRadius.control))
        .accessibilityIdentifier("voice-inbox-triage-request")
    }
}

private struct AssistantQueuePanel: View {
    let item: AssistantQueueItem
    let executionHandoffItemID: String?
    let onApprove: () -> Void
    let onDefer: () -> Void
    let onReject: () -> Void
    let onOpenQueue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Label(localizedSettingsDisplay("Assistant Queue"), systemImage: "tray.full")
                        .font(.subheadline)
                    queueStateLabel
                    Spacer(minLength: 8)
                    riskLabel
                }
                VStack(alignment: .leading, spacing: 4) {
                    Label(localizedSettingsDisplay("Assistant Queue"), systemImage: "tray.full")
                        .font(.subheadline)
                    HStack(spacing: 8) {
                        queueStateLabel
                        riskLabel
                    }
                }
            }

            Text(localizedSettingsDisplay(item.redactedSummary))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            Text(localizedSettingsDisplay(item.reviewReason))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let source = item.sourceTranscript, !source.isEmpty {
                Label(source, systemImage: "quote.bubble")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !item.requiredCapabilities.isEmpty {
                Text(item.requiredCapabilities.map(capabilityLabel).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("voice-assistant-queue-capabilities")
            }

            if let blockingReason = item.blockingReason {
                Label(localizedSettingsDisplay(blockingReason), systemImage: "exclamationmark.octagon")
                    .font(.caption)
                    .foregroundStyle(SoloPMTone.danger.color)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button {
                    onApprove()
                } label: {
                    Label(localizedSettingsDisplay("Approve"), systemImage: "checkmark.seal")
                }
                .disabled(item.state != .waitingReview)
                .accessibilityIdentifier("voice-assistant-queue-approve")

                Button {
                    onDefer()
                } label: {
                    Label(localizedSettingsDisplay("Defer"), systemImage: "clock")
                }
                .disabled(item.state == .blocked || item.state == .done || item.state == .rejected)
                .accessibilityIdentifier("voice-assistant-queue-defer")

                Button {
                    onReject()
                } label: {
                    Label(localizedSettingsDisplay("Reject"), systemImage: "xmark.circle")
                }
                .disabled(item.state == .done || item.state == .rejected)
                .accessibilityIdentifier("voice-assistant-queue-reject")
            }

            if canOpenQueueForExecution {
                Button {
                    onOpenQueue()
                } label: {
                    Label(localizedSettingsDisplay("Open Assistant Queue"), systemImage: "arrow.forward.circle")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("voice-assistant-queue-open-board")
                .accessibilityHint(localizedSettingsDisplay("Opens the Assistant Queue without running the item."))
            }
        }
        .soloAssistantSignal()
        .accessibilityIdentifier("voice-assistant-queue-panel")
    }

    private var queueStateLabel: some View {
        Label {
            Text(localizedSettingsDisplay(stateLabel))
        } icon: {
            Image(systemName: stateSystemImage)
        }
            .font(SoloPMTypography.metadata)
            .foregroundStyle(stateColor)
            .lineLimit(1)
            .accessibilityIdentifier("voice-assistant-queue-state")
    }

    private var riskLabel: some View {
        Text(String(format: localizedSettingsDisplay("Risk: %@"), item.riskLevel.rawValue))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .accessibilityIdentifier("voice-assistant-queue-risk")
    }

    private var canOpenQueueForExecution: Bool {
        executionHandoffItemID == item.id
    }

    private var stateLabel: String {
        switch item.state {
        case .captured:
            "Captured"
        case .interpreted:
            "Interpreted"
        case .drafted:
            "Drafted"
        case .waitingReview:
            "Waiting review"
        case .approved:
            "Approved"
        case .running:
            "Running"
        case .blocked:
            "Blocked"
        case .done:
            "Done"
        case .failed:
            "Failed"
        case .rejected:
            "Rejected"
        case .deferred:
            "Deferred"
        }
    }

    private var stateColor: Color {
        switch item.state {
        case .blocked, .failed, .rejected:
            SoloPMTone.danger.color
        case .approved, .done:
            SoloPMTone.positive.color
        case .deferred:
            SoloPMTone.attention.color
        case .captured, .interpreted, .drafted, .waitingReview, .running:
            .secondary
        }
    }

    private var stateSystemImage: String {
        switch item.state {
        case .captured, .interpreted, .drafted:
            "pencil.circle"
        case .waitingReview:
            "person.crop.circle.badge.questionmark"
        case .approved:
            "checkmark.seal"
        case .running:
            "arrow.triangle.2.circlepath"
        case .blocked, .failed:
            "exclamationmark.octagon.fill"
        case .done:
            "checkmark.circle.fill"
        case .rejected:
            "xmark.circle.fill"
        case .deferred:
            "clock"
        }
    }

    private func capabilityLabel(_ capability: AssistantQueueRequiredCapability) -> String {
        switch capability {
        case .tool(let tool):
            return tool.rawValue
        case .appPermission(let permission):
            return permission.rawValue
        case .connectedMacRequired:
            return localizedSettingsDisplay("Connected Mac required")
        case .providerExecutionApproval:
            return localizedSettingsDisplay("Execution approval")
        case .externalMCP(let serverID, let toolName):
            return "\(serverID):\(toolName)"
        case .externalConnector(let serviceID, let action):
            return "\(serviceID):\(action)"
        }
    }
}

private struct ClarificationPanel: View {
    let question: ClarificationQuestion
    let turns: [ClarificationTurn]
    @Binding var answerText: String
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(localizedSettingsDisplay("Clarification"), systemImage: "questionmark.bubble")
                .font(.subheadline)

            Text(localizedSettingsDisplay(question.prompt))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            if !turns.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(turns.enumerated()), id: \.offset) { _, turn in
                        Text(String(format: localizedSettingsDisplay("Answered: %@"), turn.response))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack(spacing: 8) {
                TextField(localizedSettingsDisplay("Clarification answer"), text: $answerText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("voice-command-clarification-answer")

                Button {
                    let trimmed = answerText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        return
                    }
                    onSubmit(trimmed)
                } label: {
                    Label(localizedSettingsDisplay("Answer"), systemImage: "arrow.turn.down.left")
                }
                .disabled(answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("voice-command-clarification-submit")

                Button {
                    onCancel()
                } label: {
                    Label(localizedSettingsDisplay("Cancel"), systemImage: "xmark.circle")
                }
                .accessibilityIdentifier("voice-command-clarification-cancel")
            }
        }
        .soloAssistantSignal()
        .accessibilityIdentifier("voice-command-clarification-panel")
    }
}

private struct StatusRow: View {
    let phase: VoiceCapturePhase

    var body: some View {
        Label(localizedSettingsDisplay(label), systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(isError ? SoloPMTone.danger.color : .secondary)
            .accessibilityIdentifier("voice-command-status")
    }

    private var label: String {
        switch phase {
        case .idle:
            "Ready"
        case .recording:
            "Recording"
        case .transcribing:
            "Transcribing"
        case .needsClarification:
            "Clarification needed"
        case .generatingPlan:
            "Generating"
        case .reviewReady:
            "Review ready"
        case .failed(let message):
            message
        }
    }

    private var systemImage: String {
        switch phase {
        case .idle, .reviewReady:
            "checkmark.circle"
        case .recording:
            "record.circle"
        case .transcribing, .generatingPlan:
            "hourglass"
        case .needsClarification:
            "questionmark.circle"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    private var isError: Bool {
        if case .failed = phase {
            return true
        }
        return false
    }
}

private struct VoiceIntentPreview: View {
    let result: VoiceCommandRoutingResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    intentLabel
                    confidenceLabel
                    Spacer(minLength: 8)
                    reviewLabel
                }
                VStack(alignment: .leading, spacing: 4) {
                    intentLabel
                    HStack(spacing: 8) {
                        confidenceLabel
                        reviewLabel
                    }
                }
            }

            Text(localizedSettingsDisplay(result.interpretationSummary))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let reason = result.clarificationReason {
                Label(localizedSettingsDisplay(reason), systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(SoloPMTone.attention.color)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .soloAssistantSignal()
        .accessibilityIdentifier("voice-command-intent-preview")
    }

    private var intentLabel: some View {
        Label(localizedSettingsDisplay(result.intent.displayName), systemImage: iconName)
            .font(.subheadline)
            .lineLimit(1)
            .help(localizedSettingsDisplay(result.intent.displayName))
    }

    private var confidenceLabel: some View {
        Text("\(Int((result.confidence * 100).rounded()))%")
            .font(.caption)
            .foregroundStyle(result.needsClarification ? SoloPMTone.attention.color : .secondary)
            .lineLimit(1)
            .accessibilityLabel(localizedSettingsDisplay("Voice command confidence"))
    }

    private var reviewLabel: some View {
        Text(localizedSettingsDisplay("Review-only"))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var iconName: String {
        switch result.intent {
        case .taskCreate, .taskTriage:
            "checkmark.circle"
        case .dailyPlanningReview:
            "sun.max"
        case .schedulePlan:
            "calendar"
        case .documentBrief:
            "doc.text"
        case .developmentPRWorkflow:
            "terminal"
        case .notificationDraft:
            "bell"
        case .connectorSendGate:
            "paperplane"
        case .statusAsk:
            "chart.bar"
        case .clarify:
            "questionmark.circle"
        }
    }
}

private struct ActionPlanPreview: View {
    let response: PlanningResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let plan = response.actionPlan {
                HStack {
                    Text(plan.summary)
                        .font(.headline)
                    Spacer()
                    Text(plan.riskLevel.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(plan.riskLevel >= .write ? SoloPMTone.attention.color : .secondary)
                }

                ForEach(plan.actions, id: \.id) { action in
                    HStack(alignment: .top) {
                        Image(systemName: iconName(for: action.actionType))
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.tool.rawValue)
                                .font(.subheadline)
                            Text(argumentSummary(action.arguments))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }

            if !response.validationResult.issues.isEmpty {
                ForEach(response.validationResult.issues, id: \.message) { issue in
                    Label(issue.message, systemImage: issue.severity == .blocking ? "xmark.octagon" : "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(issue.severity == .blocking ? SoloPMTone.danger.color : SoloPMTone.attention.color)
                }
            }
        }
    }

    private func iconName(for actionType: ActionType) -> String {
        switch actionType {
        case .project:
            "folder"
        case .task:
            "checkmark.circle"
        case .notification:
            "bell"
        case .calendar:
            "calendar"
        case .reminder:
            "list.bullet"
        case .filesystem:
            "doc"
        case .knowledgeFrame:
            "text.book.closed"
        case .mailDraft:
            "envelope"
        case .developer:
            "terminal"
        }
    }

    private func argumentSummary(_ arguments: [String: JSONValue]) -> String {
        guard !arguments.isEmpty else {
            return "No arguments"
        }

        return arguments
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value.displayValue)" }
            .joined(separator: ", ")
    }
}
