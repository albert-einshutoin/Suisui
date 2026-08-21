import Foundation
import SuisuiCore
import SwiftUI

private enum VoiceVisualEvidenceSurface: String {
    case idle
    case listening

    /// Evidence launches one Voice desk per isolated process so Listening does
    /// not depend on timing a real microphone session.
    static func resolved(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> VoiceVisualEvidenceSurface {
        guard environment["SUISUI_VISUAL_EVIDENCE_REFERENCE_INSTANT"] != nil,
              environment["SUISUI_VISUAL_EVIDENCE_VOICE_SURFACE"] == "listening" else {
            return .idle
        }
        return .listening
    }
}

private struct VoiceUnderstoodActionCard: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let timeLabel: String?
    let systemImage: String
}

private struct VoiceConversationEvidenceTurn: Identifiable, Equatable {
    let id: String
    let speaker: String
    let text: String
    let timeLabel: String
}

private enum VoiceVisualEvidenceFixture {
    static let listeningTimerLabel = "00:12"
    static let currentUtterance = """
    Schedule a product strategy review tomorrow from 2pm to 3pm. Add a prep \
    task for related docs and a 30-minute team reminder under Launch Readiness.
    """

    static let understoodActions: [VoiceUnderstoodActionCard] = [
        VoiceUnderstoodActionCard(
            id: "prep-task",
            title: "Create preparation task",
            detail: "Prepare related documents beforehand",
            timeLabel: "Tomorrow 11:00",
            systemImage: "checklist"
        ),
        VoiceUnderstoodActionCard(
            id: "calendar-block",
            title: "Block calendar time",
            detail: "Product strategy review meeting",
            timeLabel: "14:00–15:00",
            systemImage: "calendar"
        ),
        VoiceUnderstoodActionCard(
            id: "reminder",
            title: "Suggest reminder",
            detail: "Notify the team 30 minutes before",
            timeLabel: "13:30",
            systemImage: "bell"
        ),
        VoiceUnderstoodActionCard(
            id: "project-link",
            title: "Link to project",
            detail: "Launch Readiness",
            timeLabel: nil,
            systemImage: "folder"
        )
    ]

    static let conversationTurns: [VoiceConversationEvidenceTurn] = [
        VoiceConversationEvidenceTurn(
            id: "u1",
            speaker: "You",
            text: "Put a strategy review on the calendar tomorrow afternoon.",
            timeLabel: "13:41"
        ),
        VoiceConversationEvidenceTurn(
            id: "a1",
            speaker: "Suisui",
            text: "Does 14:00–15:00 work for the meeting?",
            timeLabel: "13:41"
        ),
        VoiceConversationEvidenceTurn(
            id: "u2",
            speaker: "You",
            text: "Yes. Add a prep task and reminder too.",
            timeLabel: "13:42"
        )
    ]

    static let confirmationOptions = [
        "Tomorrow by 11:00",
        "1 hour before the meeting",
        "No due date"
    ]
}

struct SuisuiVoiceConversationScopeRequest: Equatable, Sendable {
    let projectID: Int64?
    let projectName: String?
    let taskID: Int64?
    let taskName: String?

    var presentationScope: VoiceTaskConversationWorkspacePresentation.Scope {
        .init(
            projectName: projectName,
            taskName: taskName,
            sessionTitle: taskName ?? projectName ?? "Voice conversation"
        )
    }
}

@MainActor
enum SuisuiVoiceConversationScopeBridge {
    private static var pendingRequest: SuisuiVoiceConversationScopeRequest?

    static func store(_ request: SuisuiVoiceConversationScopeRequest) {
        pendingRequest = request
    }

    static func consume() -> SuisuiVoiceConversationScopeRequest? {
        defer { pendingRequest = nil }
        return pendingRequest
    }
}

struct VoiceCaptureView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.cockpitAuthoritativeContentWidth) private var authoritativeContentWidth
    @StateObject private var viewModel: VoiceCaptureViewModel
    @State private var clarificationAnswer = ""

    init(viewModel: VoiceCaptureViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    private var presentsListeningEvidenceDesk: Bool {
        VoiceVisualEvidenceSurface.resolved() == .listening
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
        viewModel.phase == .generatingPlan
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
        TabView {
            VoiceTaskConversationWorkspaceView(
                viewModel: viewModel,
                onOpenAssistantQueue: {
                    postAssistantQueueOpenRequest(
                        itemID: viewModel.assistantQueueItem?.id
                    )
                },
                onPauseSession: viewModel.pauseConversationWorkspace,
                onResumeSession: viewModel.resumeConversationWorkspace,
                onArchiveSession: viewModel.archiveConversationWorkspace
            )
            .tabItem {
                Label("Conversation", systemImage: "text.bubble")
            }

            quickCommandWorkspace
                .tabItem {
                    Label("Quick Command", systemImage: "waveform")
                        .accessibilityIdentifier("voice-command-quick-command-tab")
                }
        }
        .task {
            await viewModel.restoreConversationIfNeeded()
        }
        .onDisappear {
            viewModel.releaseTemporaryRecordingResources()
        }
        .onChange(of: viewModel.dailyPlanningReviewRequest) { _, request in
            guard let request else { return }
            postDailyPlanningReviewRequest(request)
        }
        .onChange(of: viewModel.inboxTriageRequest) { _, request in
            guard let request else { return }
            postInboxTriageRequest(request)
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .suisuiVoiceConversationScopeRequested
            )
        ) { _ in
            guard let request = SuisuiVoiceConversationScopeBridge.consume()
            else { return }
            viewModel.updateConversationWorkspaceScope(
                request.presentationScope,
                activeProjectID: request.projectID,
                activeTaskID: request.taskID
            )
        }
    }

    private var quickCommandWorkspace: some View {
        GeometryReader { proxy in
            let layoutWidth = CockpitSplitLayout.layoutWidth(measuredWidth: proxy.size.width, authoritativeContentWidth: authoritativeContentWidth)
            let isWide = CockpitSplitLayout.presentsSplitRail(
                measuredWidth: proxy.size.width,
                authoritativeContentWidth: authoritativeContentWidth
            )
            let railWidth = CockpitSplitLayout.railWidth(for: .voiceQuickCommand, contentWidth: layoutWidth)
            VStack(alignment: .leading, spacing: SuisuiSpacing.md) {
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

                if isWide {
                    HStack(alignment: .top, spacing: CGFloat(CockpitLayoutPolicy.splitSpacing)) {
                        quickCommandPrimaryScroll
                            .cockpitSplitPrimaryColumn()
                        quickCommandSecondaryRail
                            .cockpitSplitSecondaryRail(width: railWidth)
                    }
                    .frame(width: max(layoutWidth - CGFloat(SuisuiSpacing.lg) * 2, 1), alignment: .topLeading)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: SuisuiSpacing.md) {
                            quickCommandPrimaryContent
                            quickCommandSecondaryRail
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .padding(SuisuiSpacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var quickCommandPrimaryScroll: some View {
        ScrollView {
            quickCommandPrimaryContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var quickCommandPrimaryContent: some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.md) {
            // Capture belongs to the same scroll boundary as later
            // states so larger text and compact displays never make
            // the primary controls increase the window minimum size.
            if presentsListeningEvidenceDesk {
                listeningEvidenceDesk
            } else {
                captureZone
            }

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
            SuisuiMotion.animation(duration: SuisuiMotion.standard, reduceMotion: reduceMotion),
            value: hasWorkingContent
        )
        .animation(
            SuisuiMotion.animation(duration: SuisuiMotion.standard, reduceMotion: reduceMotion),
            value: hasReviewContent
        )
    }

    private var quickCommandSecondaryRail: some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.md) {
            VoiceUnderstoodActionsRail(
                routingResult: viewModel.routingResult,
                planActionTitles: understoodPlanActionTitles,
                evidenceActions: presentsListeningEvidenceDesk
                    ? VoiceVisualEvidenceFixture.understoodActions
                    : []
            )
            VoiceQuickCommandContextRail(
                destinationTitle: quickCommandDestinationTitle,
                isHandsFreeListening: viewModel.isLowLatencyVoiceAgentListening
                    || presentsListeningEvidenceDesk,
                speechProviderName: viewModel.handsFreeModeProviderName,
                needsClarification: presentsListeningEvidenceDesk
                    || viewModel.routingResult?.needsClarification == true
                    || viewModel.clarificationQuestion != nil,
                conversationTurns: presentsListeningEvidenceDesk
                    ? VoiceVisualEvidenceFixture.conversationTurns
                    : [],
                confirmationOptions: presentsListeningEvidenceDesk
                    ? VoiceVisualEvidenceFixture.confirmationOptions
                    : []
            )
            Spacer(minLength: 0)
        }
    }

    private var understoodPlanActionTitles: [String] {
        guard let actions = viewModel.planningResponse?.actionPlan?.actions else {
            return []
        }
        return actions.prefix(5).map(\.tool.rawValue)
    }

    private var quickCommandDestinationTitle: String {
        let scope = viewModel.conversationWorkspaceScope
        if let taskName = scope.taskName, !taskName.isEmpty {
            return taskName
        }
        if let projectName = scope.projectName, !projectName.isEmpty {
            return projectName
        }
        return scope.sessionTitle
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

    private var isListeningHeroActive: Bool {
        viewModel.isRecording || viewModel.isLowLatencyVoiceAgentListening
    }

    /// Hero capture affordance: a large circular microphone button centered
    /// above the input, with the current phase word beneath it. While listening
    /// or recording, a larger orb, ring pulse, and waveform meter take over.
    private var heroCaptureControl: some View {
        VStack(spacing: SuisuiSpacing.sm) {
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
                VoiceListeningOrb(
                    isListening: isListeningHeroActive,
                    isRecording: viewModel.isRecording,
                    meter: viewModel.inputLevelMeter
                )
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

            if isListeningHeroActive {
                VoiceInputLevelMeter(meter: viewModel.inputLevelMeter)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Deterministic Listening desk for visual evidence: orb, timer, waveform,
    /// and current utterance without opening a real microphone session.
    private var listeningEvidenceDesk: some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.md) {
            VStack(spacing: SuisuiSpacing.sm) {
                VoiceListeningOrb(
                    isListening: true,
                    isRecording: false,
                    meter: viewModel.inputLevelMeter
                )
                Text("Listening")
                    .font(.subheadline.weight(.semibold))
                Text(VoiceVisualEvidenceFixture.listeningTimerLabel)
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .accessibilityIdentifier("voice-command-listening-timer")
                VoiceInputLevelMeter(meter: viewModel.inputLevelMeter)
            }
            .frame(maxWidth: .infinity)
            .padding(14)
            .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("voice-command-listening-hero")

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Current utterance")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text("Pause")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SuisuiBrand.soloBlue)
                }
                Text(VoiceVisualEvidenceFixture.currentUtterance)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("voice-command-listening-transcript")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card, style: .continuous))

            Text("Listening evidence is a frozen review desk. Plans still wait in Review before any Calendar or task writes.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voice-command-listening-desk")
    }

    /// Zone 1: everything needed to enter a command and start work, grouped in
    /// one card so it reads as a single surface above the working/review zones.
    /// The microphone is the visual anchor; example commands sit between it and
    /// the input so an empty window still reads as a guided capture surface.
    private var captureZone: some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.md) {
            heroCaptureControl
            failureRecoveryRow
            if let message = viewModel.auditErrorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(SuisuiTone.attention.color)
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
            // A finite ceiling keeps the editor comfortable without feeding
            // an unbounded intrinsic height into AppKit window fitting.
            .frame(minHeight: 150, idealHeight: 180, maxHeight: 220, alignment: .topLeading)
            .overlay(alignment: .topLeading) {
                if isVoiceCommandInputEmpty {
                    VoiceCommandInputPrompt()
                        .padding(.top, 8)
                        .padding(.horizontal, 8)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: SuisuiRadius.control)
                    .stroke(.quaternary)
            }
            .accessibilityIdentifier("voice-command-input")

            VoiceCommandActionReadinessRow(message: actionReadinessMessage)

            LowLatencyVoiceAgentPanel(viewModel: viewModel)

            HStack {
                Button {
                    viewModel.saveDraftToInbox()
                    if viewModel.inboxCaptureResult != nil {
                        NotificationCenter.default.post(name: .suisuiProjectBoardDidChange, object: nil)
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
                    .foregroundStyle(SuisuiTone.attention.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("voice-silence-hint")
            }
        }
        .suisuiLiquidGlassCapturePanel()
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
                Button {
                    openWindow(id: "project-board")
                    SuisuiInAppSettingsNavigation.requestOpen()
                } label: {
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
        VStack(alignment: .leading, spacing: SuisuiSpacing.sm) {
            if viewModel.phase == .generatingPlan {
                PlanGenerationLivePreview()
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
            HStack(spacing: SuisuiSpacing.sm) {
                ProgressView()
                    .controlSize(.small)
                Text("Searching your workspace")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("voice-answer-retrieving")
        case .answering:
            HStack(spacing: SuisuiSpacing.sm) {
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
            VStack(alignment: .leading, spacing: SuisuiSpacing.xs) {
                Label(localizedSettingsDisplay(message), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(SuisuiTone.attention.color)
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
        VStack(alignment: .leading, spacing: SuisuiSpacing.sm) {
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
                VStack(alignment: .leading, spacing: SuisuiSpacing.xs) {
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
            .appendingPathComponent("suisui-recording-\(UUID().uuidString).m4a")
    }

    private func postDailyPlanningReviewRequest(_ request: VoiceDailyPlanningReviewRequest) {
        openWindow(id: "project-board")
        let route: BoardRoute = request.requestedActionDraftKind == nil
            ? .primary(.today)
            : .review(.assistantQueue)
        guard let bridgeRequest = SuisuiVoiceDailyPlanningReviewBridge.storePendingRequest(request) else {
            return
        }
        guard ProjectBoardSceneCoordinator.shared.requestOpen(id: request.id, route: route) != nil else {
            SuisuiVoiceDailyPlanningReviewBridge.discardPendingRequest(id: bridgeRequest.id)
            return
        }
        NotificationCenter.default.post(
            name: .suisuiVoiceDailyPlanningReviewRequested,
            object: nil,
            userInfo: [SuisuiVoiceDailyPlanningReviewBridge.requestUserInfoKey: bridgeRequest]
        )
    }

    private func postInboxTriageRequest(_ request: VoiceInboxTriageRequest) {
        openWindow(id: "project-board")
        guard let bridgeRequest = SuisuiVoiceInboxTriageBridge.storePendingRequest(request) else {
            return
        }
        guard ProjectBoardSceneCoordinator.shared.requestOpen(
            id: request.id,
            route: .primary(.inbox)
        ) != nil else {
            SuisuiVoiceInboxTriageBridge.discardPendingRequest(id: bridgeRequest.id)
            return
        }
        NotificationCenter.default.post(
            name: .suisuiVoiceInboxTriageRequested,
            object: nil,
            userInfo: [SuisuiVoiceInboxTriageBridge.requestUserInfoKey: bridgeRequest]
        )
    }

    private func postAssistantQueueOpenRequest(itemID: String? = nil) {
        guard let bridgeRequest = SuisuiAssistantQueueBridge.storePendingOpen(
            itemID: itemID
                ?? viewModel.assistantQueueExecutionHandoffItemID
        ) else {
            return
        }
        guard ProjectBoardSceneCoordinator.shared.requestOpen(
            id: bridgeRequest.id,
            route: .review(.assistantQueue)
        ) != nil else {
            SuisuiAssistantQueueBridge.discardPendingOpen(id: bridgeRequest.id)
            return
        }
        openWindow(id: "project-board")
        NotificationCenter.default.post(
            name: .suisuiAssistantQueueRequested,
            object: nil,
            userInfo: [SuisuiAssistantQueueBridge.requestUserInfoKey: bridgeRequest]
        )
    }
}

extension Notification.Name {
    static let suisuiVoiceConversationScopeRequested =
        Notification.Name("dev.suisui.voiceConversationScopeRequested")
}

/// Typed progress only. Raw provider deltas can contain secrets or malformed
/// tool payloads, so they never cross the presentation boundary.
private struct PlanGenerationLivePreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.xs) {
            Label("Preparing structured proposal", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ProgressView()
                .controlSize(.small)
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
        VStack(alignment: .leading, spacing: SuisuiSpacing.xs) {
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
        VStack(alignment: .leading, spacing: SuisuiSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: SuisuiSpacing.sm) {
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

                Spacer(minLength: SuisuiSpacing.sm)

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
            SuisuiTone.danger.color
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
                    .background(SuisuiSurface.groupedContent, in: Capsule())
            } else {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(Self.barThresholds.enumerated()), id: \.offset) { index, threshold in
                        Capsule()
                            .fill(meter.inputLevel >= threshold ? AnyShapeStyle(.tint) : SuisuiSurface.groupedContent)
                            .frame(width: 4, height: 8 + CGFloat(index) * 3)
                    }
                }
                .animation(
                    SuisuiMotion.animation(duration: SuisuiMotion.quick, reduceMotion: reduceMotion),
                    value: meter.inputLevel
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Microphone input level")
        .accessibilityIdentifier("voice-input-level-meter")
    }
}

/// Large listening orb used by the Quick Command hero. Idle shows a compact
/// mic; listening/recording expands the orb with a soft ring and level-driven
/// glow while keeping the control a single tappable surface.
private struct VoiceListeningOrb: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isListening: Bool
    let isRecording: Bool
    @ObservedObject var meter: MicrophoneInputLevelMeter

    private var orbSize: CGFloat {
        isListening ? 96 : 64
    }

    private var ringScale: CGFloat {
        guard isListening, !reduceMotion else { return 1 }
        return 1.08 + CGFloat(min(max(meter.inputLevel, 0), 1)) * 0.12
    }

    var body: some View {
        ZStack {
            if isListening {
                Circle()
                    .stroke(Color.accentColor.opacity(0.28), lineWidth: 2)
                    .frame(width: orbSize + 18, height: orbSize + 18)
                    .scaleEffect(ringScale)
                    .animation(
                        SuisuiMotion.animation(duration: SuisuiMotion.quick, reduceMotion: reduceMotion),
                        value: meter.inputLevel
                    )
            }

            Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                .font(.system(size: isListening ? 34 : 26, weight: .semibold))
                .foregroundStyle(isListening ? AnyShapeStyle(Color.white) : AnyShapeStyle(.tint))
                .frame(width: orbSize, height: orbSize)
                .background(
                    Circle()
                        .fill(
                            isListening
                                ? AnyShapeStyle(.tint)
                                : AnyShapeStyle(SuisuiBrand.soloBlue.opacity(0.14))
                        )
                )
                .contentShape(Circle())
        }
        .frame(width: orbSize + 24, height: orbSize + 24)
        .animation(
            SuisuiMotion.animation(duration: SuisuiMotion.standard, reduceMotion: reduceMotion),
            value: isListening
        )
    }
}

/// Lightweight "understood" list for Quick Command — intent summary plus plan
/// action titles when a reviewable plan exists. Distinct from Conversation
/// Understanding so the capture desk stays compact.
private struct VoiceUnderstoodActionsRail: View {
    let routingResult: VoiceCommandRoutingResult?
    let planActionTitles: [String]
    var evidenceActions: [VoiceUnderstoodActionCard] = []

    var body: some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.sm) {
            Label("Understood", systemImage: "checkmark.seal")
                .font(SuisuiTypography.sectionTitle)

            if !evidenceActions.isEmpty {
                ForEach(evidenceActions) { action in
                    VoiceUnderstoodActionCardView(action: action)
                }
            } else if let routingResult {
                Text(localizedSettingsDisplay(routingResult.intent.displayName))
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(localizedSettingsDisplay(routingResult.interpretationSummary))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(routingResult.matchedSignals.prefix(3).enumerated()), id: \.offset) { _, signal in
                    Label(signal, systemImage: "sparkle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("Speak or type a command to see what Suisui understood.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if evidenceActions.isEmpty, !planActionTitles.isEmpty {
                Text("Planned actions")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                ForEach(Array(planActionTitles.enumerated()), id: \.offset) { _, title in
                    Label(title, systemImage: "arrow.right.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voice-command-understood-rail")
    }
}

private struct VoiceUnderstoodActionCardView: View {
    let action: VoiceUnderstoodActionCard

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: action.systemImage)
                .foregroundStyle(SuisuiBrand.soloBlue)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                Text(action.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if let timeLabel = action.timeLabel {
                Text(timeLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            SuisuiTone.neutral.color.opacity(0.1),
            in: RoundedRectangle(cornerRadius: SuisuiRadius.control, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("voice-command-understood-action-\(action.id)")
    }
}

/// Quick Command context chips: current destination, hands-free state, speech
/// provider, and whether clarification is required.
private struct VoiceQuickCommandContextRail: View {
    let destinationTitle: String
    let isHandsFreeListening: Bool
    let speechProviderName: String
    let needsClarification: Bool
    var conversationTurns: [VoiceConversationEvidenceTurn] = []
    var confirmationOptions: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.sm) {
            Label("Context", systemImage: "sidebar.right")
                .font(SuisuiTypography.sectionTitle)

            contextChip(title: destinationTitle, systemImage: "mappin.and.ellipse")
            contextChip(
                title: isHandsFreeListening ? "Hands-free listening" : "Push to talk",
                systemImage: isHandsFreeListening ? "ear" : "hand.tap"
            )
            contextChip(title: speechProviderName, systemImage: "waveform")
            contextChip(
                title: needsClarification ? "Clarification needed" : "Ready to continue",
                systemImage: needsClarification ? "questionmark.circle" : "checkmark.circle"
            )

            if !conversationTurns.isEmpty {
                VStack(alignment: .leading, spacing: SuisuiSpacing.sm) {
                    Text("Current conversation")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    ForEach(conversationTurns) { turn in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(turn.speaker)
                                    .font(.caption2.weight(.semibold))
                                Spacer(minLength: 4)
                                Text(turn.timeLabel)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Text(turn.text)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            SuisuiTone.neutral.color.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: SuisuiRadius.control, style: .continuous)
                        )
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("voice-command-conversation-log")
            }

            if !confirmationOptions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Confirmation needed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    Text("Preparation task due date")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ForEach(Array(confirmationOptions.enumerated()), id: \.offset) { index, option in
                        Text(option)
                            .font(.caption2.weight(index == 0 ? .semibold : .regular))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                index == 0
                                    ? AnyShapeStyle(SuisuiBrand.soloBlue.opacity(0.14))
                                    : AnyShapeStyle(SuisuiTone.neutral.color.opacity(0.08)),
                                in: RoundedRectangle(cornerRadius: SuisuiRadius.control, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: SuisuiRadius.control, style: .continuous)
                                    .stroke(index == 0 ? SuisuiBrand.soloBlue.opacity(0.55) : .clear, lineWidth: 1)
                            }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("voice-command-confirmation-chips")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voice-command-context-rail")
    }

    private func contextChip(title: String, systemImage: String) -> some View {
        Label(localizedSettingsDisplay(title), systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                SuisuiTone.neutral.color.opacity(0.12),
                in: RoundedRectangle(cornerRadius: SuisuiRadius.control, style: .continuous)
            )
            .lineLimit(2)
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
            // "Assistant Queue" is not a place the user can find: the sidebar
            // has Today / Inbox / Projects / Review, and the queue lives two
            // levels inside Review. Name the destination they can actually
            // click, and keep the queue name attached to it.
            Text("Inbox captures stay local. Plans wait in Review › Assistant Queue before execution.")
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
        VStack(alignment: .leading, spacing: SuisuiSpacing.xs) {
            Text("Try one of these commands")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("voice-command-example-chips")
            HStack(spacing: SuisuiSpacing.sm) {
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
        .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.control))
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
        .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.control))
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
                    .foregroundStyle(SuisuiTone.danger.color)
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
            .font(SuisuiTypography.metadata)
            .foregroundStyle(stateColor)
            .lineLimit(1)
            .accessibilityIdentifier("voice-assistant-queue-state")
    }

    private var riskLabel: some View {
        Text(String(format: localizedSettingsDisplay("Risk: %@"), localizedRiskLevel(item.riskLevel)))
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
            SuisuiTone.danger.color
        case .approved, .done:
            SuisuiTone.positive.color
        case .deferred:
            SuisuiTone.attention.color
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
            return localizedActionTool(tool)
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
            .foregroundStyle(isError ? SuisuiTone.danger.color : .secondary)
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
                    .foregroundStyle(SuisuiTone.attention.color)
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

    /// A raw model confidence percentage is false precision: nobody can act
    /// differently on 62% versus 78%, and the number invites trust it has not
    /// earned. The band says the only thing that changes the user's next move —
    /// whether this reading needs a second look.
    private var confidenceLabel: some View {
        Text(localizedSettingsDisplay(confidenceBandTitle))
            .font(.caption)
            .foregroundStyle(result.needsClarification ? SuisuiTone.attention.color : .secondary)
            .lineLimit(1)
            .accessibilityLabel(localizedSettingsDisplay("Voice command confidence"))
            .accessibilityValue(localizedSettingsDisplay(confidenceBandTitle))
    }

    private var confidenceBandTitle: String {
        if result.needsClarification || result.confidence < 0.5 {
            return "Needs a check"
        }
        return result.confidence < 0.8 ? "Likely right" : "Clear reading"
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
                    Text(localizedRiskLevel(plan.riskLevel))
                        .font(.caption)
                        .foregroundStyle(plan.riskLevel >= .write ? SuisuiTone.attention.color : .secondary)
                }

                ForEach(plan.actions, id: \.id) { action in
                    HStack(alignment: .top) {
                        Image(systemName: iconName(for: action.actionType))
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(localizedActionTool(action.tool))
                                .font(.subheadline)
                            planActionSummary(action)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .accessibilityLabel(fullArgumentText(action))
                        }
                    }
                }
            }

            if !response.validationResult.issues.isEmpty {
                ForEach(response.validationResult.issues, id: \.message) { issue in
                    Label(issue.message, systemImage: issue.severity == .blocking ? "xmark.octagon" : "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(issue.severity == .blocking ? SuisuiTone.danger.color : SuisuiTone.attention.color)
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

    /// The streaming preview used to dump sorted `key: value` pairs straight
    /// from the JSON arguments, so the first thing a user saw after speaking
    /// was `dueAt: 2026-07-10T09:00:00Z, projectId: 3`. It now shares the
    /// approval surface's field vocabulary and date formatting.
    @ViewBuilder
    private func planActionSummary(_ action: PlanAction) -> some View {
        let fields = action.argumentDisplayFields()
        if fields.isEmpty {
            Text("No arguments")
        } else {
            Text(verbatim: humanArgumentText(fields))
        }
    }

    private func fullArgumentText(_ action: PlanAction) -> String {
        let fields = action.argumentDisplayFields()
        guard !fields.isEmpty else {
            return localizedDisplay("No arguments")
        }
        return humanArgumentText(fields)
    }

    private func humanArgumentText(_ fields: [ReviewActionField]) -> String {
        fields
            .map { "\(localizedReviewFieldLabel($0)): \(localizedReviewFieldValue($0))" }
            .joined(separator: " · ")
    }
}

enum VoiceEvidenceLaunch {
    static var shouldOpenOnLaunch: Bool {
        ProcessInfo.processInfo.environment["SUISUI_OPEN_VOICE_COMMAND_ON_LAUNCH"] == "1"
    }
}

@MainActor
enum SuisuiInAppVoiceNavigation {
    static func requestOpen() {
        _ = ProjectBoardSceneCoordinator.shared.requestOpen(route: .voiceCommand)
        NotificationCenter.default.post(name: .suisuiOpenBoardVoiceCommand, object: nil)
    }
}

struct VoiceCaptureWorkspaceHost: View {
    @State private var viewModel: VoiceCaptureViewModel?

    var body: some View {
        Group {
            if let viewModel {
                VoiceCaptureView(viewModel: viewModel)
            } else {
                ProgressView("Opening Voice Command")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("voice-capture-loading")
            }
        }
        .task {
            guard viewModel == nil else {
                return
            }
            // Voice runtime construction touches audio, model providers, audit
            // logging, and local stores. Defer it until this workspace is
            // opened so primary Project Board launch is not blocked.
            viewModel = AppRuntimeFactory.makeVoiceCaptureViewModel()
        }
    }
}
