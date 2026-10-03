import SuisuiCore
import SwiftUI

/// Focused-scene handle for the board-operation undo stack. Equality tracks the
/// owning view model and undo availability so SwiftUI refreshes the Edit-menu
/// item exactly when the stack flips between empty and undoable.
struct ProjectBoardUndoCommandAction: Equatable {
    let canUndo: Bool
    private let viewModelID: ObjectIdentifier
    private let perform: @MainActor () -> Void

    @MainActor
    init(viewModel: ProjectBoardViewModel) {
        canUndo = viewModel.canUndoBoardOperation
        viewModelID = ObjectIdentifier(viewModel)
        perform = { viewModel.undoLastBoardOperation() }
    }

    @MainActor
    func callAsFunction() {
        perform()
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.viewModelID == rhs.viewModelID && lhs.canUndo == rhs.canUndo
    }
}

private struct ProjectBoardUndoFocusedValueKey: FocusedValueKey {
    typealias Value = ProjectBoardUndoCommandAction
}

extension FocusedValues {
    var projectBoardUndo: ProjectBoardUndoCommandAction? {
        get { self[ProjectBoardUndoFocusedValueKey.self] }
        set { self[ProjectBoardUndoFocusedValueKey.self] = newValue }
    }
}

/// Edit-menu entry for the board-operation undo stack. The ⌘Z key itself is
/// handled by the focused Kanban container (so text fields keep the standard
/// text Undo); this command adds the discoverable menu affordance and stays
/// enabled only while the key Project Board window has an undoable operation.
struct SuisuiProjectBoardUndoCommands: Commands {
    @FocusedValue(\.projectBoardUndo) private var projectBoardUndo

    var body: some Commands {
        CommandGroup(after: .undoRedo) {
            Button {
                projectBoardUndo?()
            } label: {
                Label("Undo Board Operation", systemImage: "arrow.uturn.backward")
            }
            .disabled(projectBoardUndo?.canUndo != true)
            .help("Undo the last board task change")
            .accessibilityIdentifier("project-board-undo-command")
            .accessibilityHint("Reverts the most recent task completion, move, edit, or delete on the Project Board.")
        }
    }
}

extension Notification.Name {
    // .suisuiProjectBoardDidChange moved to SuisuiCore (FirstRunOnboarding.swift)
    // so core store writers can post it without duplicating the raw name.
    static let suisuiProjectBoardCommandReady = Notification.Name("dev.suisui.projectBoardCommandReady")
    static let suisuiVoiceDailyPlanningReviewRequested = Notification.Name("dev.suisui.voiceDailyPlanningReviewRequested")
    static let suisuiVoiceInboxTriageRequested = Notification.Name("dev.suisui.voiceInboxTriageRequested")
    static let suisuiAssistantQueueRequested = Notification.Name("dev.suisui.assistantQueueRequested")
    static let suisuiOpenBoardSettings = Notification.Name("dev.suisui.openBoardSettings")
    static let suisuiOpenBoardVoiceCommand = Notification.Name("dev.suisui.openBoardVoiceCommand")
}

@MainActor
enum SuisuiAssistantQueueBridge {
    struct Request: Equatable {
        var id: UUID
        var itemID: String
    }

    static let requestUserInfoKey = "request"
    private static var pendingRequests = ProjectBoardRequestPayloadStore<Request>()

    static func storePendingOpen(itemID: String?) -> Request? {
        guard let itemID = itemID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !itemID.isEmpty else {
            return nil
        }
        let request = Request(id: UUID(), itemID: itemID)
        return pendingRequests.store(request, id: request.id) ? request : nil
    }

    static func consumePendingOpen(id: UUID) -> Request? {
        pendingRequests.consume(id: id)
    }

    static func discardPendingOpen(id: UUID) {
        pendingRequests.discard(id: id)
    }
}

@MainActor
enum SuisuiVoiceDailyPlanningReviewBridge {
    struct Request: Equatable {
        var id: UUID
        var sourceTranscript: String
        var actionDraftKind: DailyPlanningActionDraftKind?
    }

    static let requestUserInfoKey = "request"
    private static var pendingRequests = ProjectBoardRequestPayloadStore<Request>()

    static func storePendingRequest(_ request: VoiceDailyPlanningReviewRequest) -> Request? {
        let bridgeRequest = Request(
            id: request.id,
            sourceTranscript: normalized(request.sourceTranscript),
            actionDraftKind: request.requestedActionDraftKind
        )
        return pendingRequests.store(bridgeRequest, id: bridgeRequest.id) ? bridgeRequest : nil
    }

    static func consumePendingRequest(id: UUID) -> Request? {
        pendingRequests.consume(id: id)
    }

    static func discardPendingRequest(id: UUID) {
        pendingRequests.discard(id: id)
    }

    private static func normalized(_ sourceTranscript: String) -> String {
        sourceTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
enum SuisuiVoiceInboxTriageBridge {
    struct Request: Equatable {
        var id: UUID
        var command: InboxVoiceTriageCommand
    }

    static let requestUserInfoKey = "request"
    private static var pendingRequests = ProjectBoardRequestPayloadStore<Request>()

    static func storePendingRequest(_ request: VoiceInboxTriageRequest) -> Request? {
        let bridgeRequest = Request(id: request.id, command: request.command)
        return pendingRequests.store(bridgeRequest, id: bridgeRequest.id) ? bridgeRequest : nil
    }

    static func consumePendingRequest(id: UUID) -> Request? {
        pendingRequests.consume(id: id)
    }

    static func discardPendingRequest(id: UUID) {
        pendingRequests.discard(id: id)
    }
}
