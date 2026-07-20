import SuisuiCore
import SwiftUI

public struct SuisuiiOSCompanionApp: App {
    public init() {}

    public var body: some Scene {
        WindowGroup {
            SuisuiiOSRootView()
        }
    }
}

public struct SuisuiiOSRootView: View {
    @State private var viewModel: SuisuiiOSCompanionViewModel

    public init(viewModel: SuisuiiOSCompanionViewModel = SuisuiiOSCompanionViewModel()) {
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        TabView {
            SuisuiiOSInboxView(viewModel: viewModel)
                .tabItem {
                    Label("Inbox", systemImage: "tray")
                }
            SuisuiiOSTodayView(viewModel: viewModel)
                .tabItem {
                    Label("Today", systemImage: "calendar")
                }
            SuisuiiOSProjectsView(viewModel: viewModel)
                .tabItem {
                    Label("Projects", systemImage: "rectangle.stack")
                }
            SuisuiiOSApprovalInboxView(viewModel: viewModel)
                .tabItem {
                    Label("Approvals", systemImage: "checkmark.seal")
                }
            SuisuiiOSConversationView(viewModel: viewModel)
                .tabItem {
                    Label("Ask", systemImage: "bubble.left.and.text.bubble.right")
                }
        }
    }
}

@Observable
public final class SuisuiiOSCompanionViewModel {
    public private(set) var configuration: IOSCompanionMVPConfiguration
    public var draftTaskTitle: String
    public var conversationPrompt: String
    public private(set) var pendingMutations: [SyncTaskMutationPayload]
    public private(set) var pendingApprovals: [SyncAutomationRequestPayload]

    public init(
        configuration: IOSCompanionMVPConfiguration = .default,
        draftTaskTitle: String = "",
        conversationPrompt: String = "",
        pendingMutations: [SyncTaskMutationPayload] = [],
        pendingApprovals: [SyncAutomationRequestPayload] = []
    ) {
        self.configuration = configuration
        self.draftTaskTitle = draftTaskTitle
        self.conversationPrompt = conversationPrompt
        self.pendingMutations = pendingMutations
        self.pendingApprovals = pendingApprovals
    }

    public func createInboxTask() {
        guard let mutation = try? IOSCompanionTaskAction
            .create(title: draftTaskTitle, projectID: nil)
            .mutationPayload(source: .conversation) else {
            return
        }
        pendingMutations.append(mutation)
        draftTaskTitle = ""
    }

    public func complete(taskID: Int64) {
        append(.complete(taskID: taskID))
    }

    public func move(taskID: Int64, toStatus status: String) {
        append(.changeStatus(taskID: taskID, status: status))
    }

    public func reschedule(taskID: Int64, dueAt: String) {
        append(.changeDueDate(taskID: taskID, dueAt: dueAt))
    }

    public func move(taskID: Int64, toProjectID projectID: Int64) {
        append(.moveToProject(taskID: taskID, projectID: projectID))
    }

    public func approve(_ request: SyncAutomationRequestPayload) {
        guard let approved = try? IOSPendingActionApproval.approve(request) else {
            return
        }
        pendingApprovals.removeAll { $0.id == request.id }
        pendingApprovals.append(approved)
    }

    private func append(_ action: IOSCompanionTaskAction) {
        guard let mutation = try? action.mutationPayload(source: .conversation) else {
            return
        }
        pendingMutations.append(mutation)
    }
}

public struct SuisuiiOSInboxView: View {
    @Bindable var viewModel: SuisuiiOSCompanionViewModel

    public init(viewModel: SuisuiiOSCompanionViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Capture") {
                    TextField("Task title", text: $viewModel.draftTaskTitle)
                    Button("Add to Inbox") {
                        viewModel.createInboxTask()
                    }
                }
                Section("Pending changes") {
                    ForEach(Array(viewModel.pendingMutations.enumerated()), id: \.offset) { _, mutation in
                        Text(mutation.title ?? mutation.status ?? mutation.operation.rawValue)
                    }
                }
            }
            .navigationTitle("Inbox")
        }
    }
}

public struct SuisuiiOSTodayView: View {
    let viewModel: SuisuiiOSCompanionViewModel

    public init(viewModel: SuisuiiOSCompanionViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            List {
                Label("Due today and overdue synced tasks appear here.", systemImage: "calendar.badge.clock")
                Label("Board-lite controls can complete or reschedule selected tasks.", systemImage: "slider.horizontal.3")
            }
            .navigationTitle("Today")
        }
    }
}

public struct SuisuiiOSProjectsView: View {
    let viewModel: SuisuiiOSCompanionViewModel

    public init(viewModel: SuisuiiOSCompanionViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            List {
                Label("Project task list", systemImage: "list.bullet.rectangle")
                Label("Board-lite status controls", systemImage: "rectangle.3.group")
            }
            .navigationTitle("Projects")
        }
    }
}

public struct SuisuiiOSApprovalInboxView: View {
    let viewModel: SuisuiiOSCompanionViewModel

    public init(viewModel: SuisuiiOSCompanionViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            List(viewModel.pendingApprovals, id: \.id) { request in
                VStack(alignment: .leading) {
                    Text(request.toolName ?? "Pending action")
                    Text(request.redactedArgumentSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Approvals")
        }
    }
}

public struct SuisuiiOSConversationView: View {
    @Bindable var viewModel: SuisuiiOSCompanionViewModel

    public init(viewModel: SuisuiiOSCompanionViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Conversation") {
                    TextField("What should Suisui do?", text: $viewModel.conversationPrompt, axis: .vertical)
                    Label("Voice, Shortcuts, and Share Sheet capture use the same action contract.", systemImage: "waveform")
                }
            }
            .navigationTitle("Ask")
        }
    }
}
