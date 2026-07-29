import Foundation
import SuisuiCore
import SwiftUI

/// A macOS work surface for one voice-task conversation. This view composes
/// presentation and input controls; task resolution, approval, and execution
/// remain in Core/Assistant Queue so the workspace cannot create a shadow path.
struct VoiceTaskConversationWorkspaceView: View {
    @ObservedObject var viewModel: VoiceCaptureViewModel
    let scope: VoiceTaskConversationWorkspacePresentation.Scope
    let onOpenAssistantQueue: () -> Void
    let onPauseSession: () -> Void
    let onResumeSession: () -> Void
    let onArchiveSession: () -> Void

    init(
        viewModel: VoiceCaptureViewModel,
        scope: VoiceTaskConversationWorkspacePresentation.Scope = .init(),
        onOpenAssistantQueue: @escaping () -> Void = {},
        onPauseSession: @escaping () -> Void = {},
        onResumeSession: @escaping () -> Void = {},
        onArchiveSession: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.scope = scope
        self.onOpenAssistantQueue = onOpenAssistantQueue
        self.onPauseSession = onPauseSession
        self.onResumeSession = onResumeSession
        self.onArchiveSession = onArchiveSession
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = VoiceTaskConversationWorkspaceLayout(width: proxy.size.width)
            let presentation = currentPresentation
            VStack(alignment: .leading, spacing: SuisuiSpacing.md) {
                VoiceTaskConversationWorkspaceHeader(
                    presentation: presentation,
                    onPauseSession: onPauseSession,
                    onResumeSession: onResumeSession,
                    onArchiveSession: onArchiveSession
                )

                ScrollView {
                    Group {
                        switch layout {
                        case .regular:
                            HStack(alignment: .top, spacing: SuisuiSpacing.md) {
                                conversationColumn(presentation)
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                VoiceTaskConversationUnderstandingView(
                                    presentation: presentation,
                                    isCompact: false,
                                    onOpenAssistantQueue: onOpenAssistantQueue
                                )
                                .frame(maxWidth: 330, alignment: .topLeading)
                            }
                        case .compact:
                            VStack(alignment: .leading, spacing: SuisuiSpacing.md) {
                                conversationColumn(presentation)
                                VoiceTaskConversationUnderstandingView(
                                    presentation: presentation,
                                    isCompact: true,
                                    onOpenAssistantQueue: onOpenAssistantQueue
                                )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VoiceTaskConversationComposer(viewModel: viewModel)
            }
            .padding(SuisuiSpacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voice-conversation-workspace")
        .onAppear {
            viewModel.refreshConversationWorkspaceCloseout()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .suisuiProjectBoardDidChange
            )
        ) { _ in
            viewModel.refreshConversationWorkspaceCloseout()
        }
    }

    @ViewBuilder
    private func conversationColumn(
        _ presentation: VoiceTaskConversationWorkspacePresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.md) {
            VoiceTaskConversationTurnList(
                presentation: presentation,
                onLoadEarlier: viewModel.loadEarlierConversationTurns
            )
            if !viewModel.conversationWorkspaceLocalAnswerItems.isEmpty {
                VoiceTaskConversationLocalAnswer(
                    items: viewModel.conversationWorkspaceLocalAnswerItems
                )
            }
            if let clarification = presentation.clarification {
                VoiceTaskConversationClarification(
                    clarification: clarification,
                    onCancel: viewModel.cancelClarification
                )
            }
            VoiceTaskConversationCloseout(closeout: presentation.closeout)
        }
    }

    private var currentPresentation: VoiceTaskConversationWorkspacePresentation {
        let current = VoiceTaskConversationWorkspacePresentation.make(
            phase: viewModel.phase,
            scope: viewModel.conversationWorkspaceScope == .init()
                ? scope
                : viewModel.conversationWorkspaceScope,
            confirmedTranscript: viewModel.draft.normalizedText,
            clarificationQuestion: viewModel.clarificationQuestion,
            planningResponse: viewModel.planningResponse,
            assistantQueueItem: viewModel.assistantQueueItem,
            closeout: viewModel.conversationWorkspaceCloseout
        )
        return VoiceTaskConversationWorkspacePresentation(
            scope: current.scope,
            sessionState:
                viewModel.conversationWorkspaceSessionState
                ?? current.sessionState,
            turns: viewModel.conversationWorkspaceTurns.isEmpty
                ? current.turns
                : viewModel.conversationWorkspaceTurns,
            turnListState: viewModel.conversationWorkspaceTurns.isEmpty
                ? current.turnListState
                : viewModel.conversationWorkspaceTurnListState,
            clarification: current.clarification,
            resolvedTarget: current.resolvedTarget,
            proposal: current.proposal,
            factCandidates: current.factCandidates,
            queueHandoff: current.queueHandoff,
            closeout: current.closeout
        )
    }
}

private struct VoiceTaskConversationLocalAnswer: View {
    let items: [VoiceTaskConversationAnswerItem]

    var body: some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.sm) {
            Label("Task list", systemImage: "checklist")
                .font(.headline)
            ForEach(items, id: \.id) { item in
                Text(verbatim: item.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .soloCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voice-conversation-task-list-answer")
    }
}

private enum VoiceTaskConversationWorkspaceLayout {
    case compact
    case regular

    init(width: CGFloat) {
        self = width < 840 ? .compact : .regular
    }
}

private struct VoiceTaskConversationWorkspaceHeader: View {
    let presentation: VoiceTaskConversationWorkspacePresentation
    let onPauseSession: () -> Void
    let onResumeSession: () -> Void
    let onArchiveSession: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SuisuiSpacing.sm) {
            Label(presentation.scope.sessionTitle, systemImage: presentation.sessionState.systemImage)
                .font(.headline)
                .accessibilityLabel("Voice conversation session")
                .accessibilityValue(presentation.scope.accessibilityValue)
            Text(presentation.sessionState.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Session state")
                .accessibilityValue(presentation.sessionState.title)
            if let message = presentation.sessionState.blockedMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(SuisuiTone.attention.color)
                    .lineLimit(2)
                    .accessibilityIdentifier("voice-conversation-blocked")
            }
            Spacer(minLength: SuisuiSpacing.sm)
            Menu {
                if presentation.sessionState == .paused {
                    Button("Resume session", action: onResumeSession)
                } else if presentation.sessionState != .archived {
                    Button("Pause session", action: onPauseSession)
                }
                if presentation.sessionState != .archived {
                    Button(
                        "Archive session",
                        role: .destructive,
                        action: onArchiveSession
                    )
                }
            } label: {
                Label("Session actions", systemImage: "ellipsis.circle")
            }
            .accessibilityIdentifier("voice-conversation-session-actions")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voice-conversation-scope")
    }
}

private struct VoiceTaskConversationTurnList: View {
    let presentation: VoiceTaskConversationWorkspacePresentation
    let onLoadEarlier: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.sm) {
            Label("Conversation", systemImage: "text.bubble")
                .font(.headline)
            switch presentation.turnListState {
            case .empty:
                ContentUnavailableView(
                    "Start a conversation",
                    systemImage: "mic",
                    description: Text("Record or type a request. Your confirmed text appears here."))
            case .loaded(let hasMore):
                turns
                if hasMore {
                    Button("Load earlier turns", action: onLoadEarlier)
                        .accessibilityHint("Loads older confirmed conversation turns.")
                }
            case .loadingMore:
                turns
                ProgressView("Loading earlier turns")
            case .failed(let message):
                turns
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(SuisuiTone.attention.color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .soloCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voice-conversation-turn-list")
    }

    @ViewBuilder
    private var turns: some View {
        ForEach(presentation.turns) { turn in
            VStack(alignment: .leading, spacing: 2) {
                Text(turn.author.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(verbatim: turn.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(turn.author.label)
        }
    }
}

private struct VoiceTaskConversationClarification: View {
    let clarification: VoiceTaskConversationWorkspacePresentation.Clarification
    let onCancel: () -> Void
    @AccessibilityFocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.sm) {
            Label("One clarification needed", systemImage: "questionmark.circle")
                .font(.headline)
            Text(verbatim: clarification.prompt)
                .fixedSize(horizontal: false, vertical: true)
            Button("Cancel clarification", action: onCancel)
                .accessibilityHint("Cancels this question without changing Tasks or Projects.")
        }
        .soloCard()
        .accessibilityFocused($isFocused)
        .onAppear { isFocused = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voice-conversation-clarification")
    }
}

private struct VoiceTaskConversationComposer: View {
    @ObservedObject var viewModel: VoiceCaptureViewModel
    @State private var clarificationAnswer = ""

    private var isRecording: Bool {
        if case .recording = viewModel.phase { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.sm) {
            TextField(
                viewModel.clarificationQuestion == nil
                    ? "Type a voice task request"
                    : "Answer the clarification",
                text: Binding(
                    get: {
                        viewModel.clarificationQuestion == nil
                            ? viewModel.draft.text
                            : clarificationAnswer
                    },
                    set: { value in
                        if viewModel.clarificationQuestion == nil {
                            viewModel.updateDraftText(value)
                        } else {
                            clarificationAnswer = value
                        }
                    }
                ),
                axis: .vertical
            )
            .lineLimit(3...6)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Voice task request")
            .accessibilityIdentifier("voice-conversation-input")

            HStack {
                Button {
                    Task {
                        if isRecording {
                            await viewModel.stopRecording(outputURL: recordingOutputURL())
                        } else {
                            await viewModel.startRecording()
                        }
                    }
                } label: {
                    Label(isRecording ? "Stop recording" : "Record", systemImage: isRecording ? "stop.fill" : "mic.fill")
                }
                .accessibilityLabel(isRecording ? "Stop recording" : "Record voice task")

                Button("Cancel") {
                    if viewModel.clarificationQuestion != nil {
                        viewModel.cancelClarification()
                    }
                    clarificationAnswer = ""
                    viewModel.updateDraftText("")
                }
                Spacer()
                Button {
                    Task {
                        if viewModel.clarificationQuestion != nil {
                            let answer = clarificationAnswer
                            clarificationAnswer = ""
                            await viewModel.submitClarificationAnswer(answer)
                        } else {
                            await viewModel.generatePlan()
                        }
                    }
                } label: {
                    Label(
                        viewModel.clarificationQuestion == nil
                            ? "Send for review"
                            : "Answer clarification",
                        systemImage: "paperplane"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    viewModel.clarificationQuestion == nil
                        ? !viewModel.canGeneratePlan
                        : clarificationAnswer
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                            .isEmpty
                )
                .accessibilityHint("Creates an approval-gated proposal. It does not run changes.")
                .accessibilityIdentifier(
                    viewModel.clarificationQuestion == nil
                        ? "voice-conversation-send-review"
                        : "voice-conversation-submit-clarification"
                )
            }
        }
        .soloCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voice-conversation-composer")
    }

    private func recordingOutputURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-conversation-\(UUID().uuidString).m4a")
    }
}

private struct VoiceTaskConversationCloseout: View {
    let closeout: VoiceTaskConversationWorkspacePresentation.Closeout

    var body: some View {
        HStack(spacing: SuisuiSpacing.sm) {
            closeoutValue(
                String(localized: "Created"),
                closeout.createdCount,
                icon: "plus.circle"
            )
            closeoutValue(
                String(localized: "Changed"),
                closeout.changedCount,
                icon: "pencil.circle"
            )
            closeoutValue(
                String(localized: "Pending"),
                closeout.pendingCount,
                icon: "clock"
            )
            closeoutValue(
                String(localized: "Unresolved"),
                closeout.unresolvedCount,
                icon: "questionmark.circle"
            )
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("voice-conversation-closeout")
    }

    private func closeoutValue(_ title: String, _ count: Int, icon: String) -> some View {
        Label("\(title): \(count)", systemImage: icon)
    }
}
