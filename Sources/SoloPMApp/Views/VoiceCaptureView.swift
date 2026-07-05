import Foundation
import SoloPMCore
import SwiftUI

struct VoiceCaptureView: View {
    @Environment(\.openWindow) private var openWindow
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Voice Command", systemImage: "mic")
                    .font(.headline)
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

            StatusRow(phase: viewModel.phase)
            if let message = viewModel.auditErrorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
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
            .frame(minHeight: 150, idealHeight: 180, maxHeight: 180)
            .overlay(alignment: .topLeading) {
                if isVoiceCommandInputEmpty {
                    VoiceCommandInputPrompt()
                        .padding(.top, 8)
                        .padding(.horizontal, 8)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.quaternary)
            }
            .accessibilityIdentifier("voice-command-input")

            VoiceCommandActionReadinessRow(message: actionReadinessMessage)

            LowLatencyVoiceAgentPanel(viewModel: viewModel)

            HStack {
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
                    Label(viewModel.isRecording ? "Stop" : "Record", systemImage: viewModel.isRecording ? "stop.circle" : "record.circle")
                }
                .disabled(viewModel.phase == .generatingPlan || viewModel.phase == .transcribing || viewModel.isLowLatencyVoiceAgentListening)
                .accessibilityIdentifier("voice-command-record")

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

                Spacer()

                Button {
                    Task {
                        await viewModel.generatePlan()
                    }
                } label: {
                    Label("Generate Plan", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.phase == .generatingPlan || viewModel.phase == .recording || viewModel.phase == .transcribing || viewModel.isLowLatencyVoiceAgentListening)
                .accessibilityIdentifier("voice-command-generate-plan")
                .accessibilityHint(localizedSettingsDisplay(actionReadinessMessage))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                if let routingResult = viewModel.routingResult {
                    VoiceIntentPreview(result: routingResult)
                }

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
                        openWindow(id: "project-board")
                    }
                }

                if let item = viewModel.assistantQueueItem {
                    Divider()
                    AssistantQueuePanel(
                        item: item,
                        executionHandoffItemID: viewModel.assistantQueueExecutionHandoffItemID,
                        onApprove: { viewModel.approveAssistantQueueItem() },
                        onDefer: { viewModel.deferAssistantQueueItem() },
                        onReject: { viewModel.rejectAssistantQueueItem() },
                        onOpenQueue: { postAssistantQueueOpenRequest() }
                    )
                }

                if let response = viewModel.planningResponse {
                    Divider()
                    ActionPlanPreview(response: response)
                }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("voice-command-root")
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

    private func recordingOutputURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("solopm-recording-\(UUID().uuidString).m4a")
    }

    private func postDailyPlanningReviewRequest(_ request: VoiceDailyPlanningReviewRequest) {
        openWindow(id: "project-board")
        guard let bridgeRequest = SoloPMVoiceDailyPlanningReviewBridge.storePendingRequest(request) else {
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
        openWindow(id: "project-board")
        NotificationCenter.default.post(
            name: .soloPMAssistantQueueRequested,
            object: nil,
            userInfo: [SoloPMAssistantQueueBridge.requestUserInfoKey: bridgeRequest]
        )
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label("Low-latency agent", systemImage: "waveform")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if viewModel.isLowLatencyVoiceAgentListening {
                    Button {
                        viewModel.stopLowLatencyVoiceAgentMode()
                    } label: {
                        Label("Stop", systemImage: "stop.circle")
                    }
                    .accessibilityIdentifier("voice-agent-stop")
                } else {
                    Button {
                        Task {
                            await viewModel.startLowLatencyVoiceAgentMode()
                        }
                    } label: {
                        Label("Start", systemImage: "play.circle")
                    }
                    .disabled(isBusyOutsideVoiceAgent)
                    .accessibilityIdentifier("voice-agent-start")
                }
            }

            Label(stateLabel, systemImage: stateSystemImage)
                .font(.caption)
                .foregroundStyle(stateTone)
                .accessibilityIdentifier("voice-agent-status")

            if !viewModel.liveTranscript.isEmpty {
                Text(viewModel.liveTranscript)
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
        .padding(10)
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(.quaternary)
        }
        .accessibilityIdentifier("voice-agent-panel")
    }

    private var stateLabel: String {
        switch viewModel.lowLatencyVoiceAgentState {
        case .idle:
            String(localized: "Idle")
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
            .red
        case .disabled, .unavailable:
            .secondary
        case .idle, .listening:
            .primary
        }
    }
}

private struct VoiceCommandInputPrompt: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try one of these commands")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            placeholderExample("Capture follow-up for launch review", systemImage: "tray")
            placeholderExample("Plan tomorrow: review release risks", systemImage: "checklist")
            Text("Inbox captures stay local. Plans wait in Assistant Queue before execution.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("voice-command-input-prompt")
    }

    private func placeholderExample(_ text: LocalizedStringKey, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
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
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
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
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
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
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
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
                    .foregroundStyle(.red)
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
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityIdentifier("voice-assistant-queue-panel")
    }

    private var queueStateLabel: some View {
        Text(localizedSettingsDisplay(stateLabel))
            .font(.caption)
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
            .red
        case .approved, .done:
            .green
        case .deferred:
            .orange
        case .captured, .interpreted, .drafted, .waitingReview, .running:
            .secondary
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
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityIdentifier("voice-command-clarification-panel")
    }
}

private struct StatusRow: View {
    let phase: VoiceCapturePhase

    var body: some View {
        Label(localizedSettingsDisplay(label), systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(isError ? .red : .secondary)
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
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
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
            .foregroundStyle(result.needsClarification ? .orange : .secondary)
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
                        .foregroundStyle(plan.riskLevel >= .write ? .orange : .secondary)
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
                        .foregroundStyle(issue.severity == .blocking ? .red : .orange)
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
