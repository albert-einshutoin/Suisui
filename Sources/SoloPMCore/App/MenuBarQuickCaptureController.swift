import Combine
import Foundation

@MainActor
public final class MenuBarQuickCaptureController: ObservableObject {
    @Published public private(set) var errorMessage: String?

    private var store: (any ProjectBoardStore)?
    private let storeFactory: () throws -> any ProjectBoardStore
    private let onChange: () -> Void

    public init(
        store: any ProjectBoardStore,
        onChange: @escaping () -> Void = {}
    ) {
        self.store = store
        self.storeFactory = { store }
        self.onChange = onChange
    }

    public init(
        storeFactory: @escaping () throws -> any ProjectBoardStore,
        onChange: @escaping () -> Void = {}
    ) {
        self.store = nil
        self.storeFactory = storeFactory
        self.onChange = onChange
    }

    @discardableResult
    public func createInboxTask(
        title: String,
        detail: String = "",
        priority: ProjectTaskPriority = .medium,
        dueAt: String? = nil
    ) -> ProjectBoardTask? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            errorMessage = "Task title is required."
            return nil
        }

        do {
            let store = try resolvedStore()
            let snapshot = try store.loadSnapshot(includeArchived: false)
            let inboxProject = try activeInboxProject(in: snapshot, store: store)
            let task = try store.createTask(ProjectBoardTaskDraft(
                projectID: inboxProject.id,
                title: trimmedTitle,
                detail: detail,
                status: .backlog,
                priority: priority,
                dueAt: dueAt
            ))
            errorMessage = nil
            onChange()
            return task
        } catch ProjectBoardStoreError.emptyTitle {
            errorMessage = "Task title is required."
        } catch ProjectBoardStoreError.archivedProjectCannotAcceptTasks {
            errorMessage = "Restore the project before adding tasks."
        } catch ProjectBoardStoreError.emptyProjectTitle {
            errorMessage = "Project title is required."
        } catch {
            errorMessage = "Project board could not be updated: \(error.localizedDescription)"
        }
        return nil
    }

    private func resolvedStore() throws -> any ProjectBoardStore {
        if let store {
            return store
        }
        // Quick Add is a menu-only write path. Opening SQLite before the main
        // window is visible can block app launch, so resolve the store only when
        // the user actually submits a capture.
        let store = try storeFactory()
        self.store = store
        return store
    }

    private func activeInboxProject(
        in snapshot: ProjectBoardSnapshot,
        store: any ProjectBoardStore
    ) throws -> ProjectBoardProject {
        if let inboxProject = snapshot.projects.first(where: {
            $0.title.caseInsensitiveCompare("Inbox") == .orderedSame && !$0.isArchived
        }) {
            return inboxProject
        }

        // Menu bar capture is intentionally narrower than ProjectBoardViewModel:
        // it creates the Inbox only when needed and avoids loading receipt history,
        // assistant queue state, or connector runtimes before the main window opens.
        return try store.createProject(title: "Inbox")
    }
}
