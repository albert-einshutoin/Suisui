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
        var draft = dueAt == nil ? InboxTaskDraft.parsing(title) : InboxTaskDraft(title: title, dueAt: dueAt)
        draft.detail = detail
        draft.priority = priority
        return createInboxTask(draft)
    }

    @discardableResult
    public func createInboxTask(_ draft: InboxTaskDraft) -> ProjectBoardTask? {
        do {
            let task = try resolvedStore().createInboxTask(draft)
            errorMessage = nil
            onChange()
            return task
        } catch {
            errorMessage = LocalPathRedactor.redact(LocalWorkspaceFailureMessage.message(for: error))
            return nil
        }
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

}
