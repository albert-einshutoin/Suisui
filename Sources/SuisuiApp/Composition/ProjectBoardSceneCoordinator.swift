import Combine
import Foundation
import SuisuiCore

enum ProjectBoardShortcutAction {
    case commandPalette
    case destination(BoardPrimaryDestination)
    case route(BoardRoute)
}

struct ProjectBoardShortcutRequest {
    let sceneID: UUID
    let action: ProjectBoardShortcutAction
}

extension Notification.Name {
    static let suisuiProjectBoardShortcutRequested = Notification.Name(
        "dev.suisui.project-board-shortcut-requested"
    )
}

/// App-level serialization point for Project Board navigation requests.
///
/// SwiftUI can notify every window about the same published change. Claiming
/// through this MainActor owner keeps the pure reducer mutation atomic, so one
/// broadcast request cannot be applied by two windows.
@MainActor
final class ProjectBoardSceneCoordinator: ObservableObject {
    static let shared = ProjectBoardSceneCoordinator()

    @Published private(set) var deliveryRevision = 0
    @Published private(set) var lastAppliedRequestID: UUID?
    @Published private(set) var activeSceneID: UUID?

    private var state = ProjectBoardSceneNavigationState()
    private var applicationAcknowledgements = ProjectBoardSceneApplicationAcknowledgements()
    private var registeredSceneIDs: [UUID] = []
    private var pendingActiveSceneID: UUID?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func register(sceneID: UUID) {
        state.register(sceneID: sceneID)
        if !registeredSceneIDs.contains(sceneID) {
            registeredSceneIDs.append(sceneID)
        }
        if pendingActiveSceneID == sceneID {
            pendingActiveSceneID = nil
            setActive(sceneID: sceneID)
        }
        // SwiftUI can evaluate Commands before the backing NSWindow posts its
        // first key notification. Seed only the first registered board; window
        // notifications remain authoritative once multiple scenes exist.
        if activeSceneID == nil {
            activeSceneID = sceneID
        }
        publishDeliveryOpportunity()
    }

    func unregister(sceneID: UUID) {
        state.unregister(sceneID: sceneID)
        registeredSceneIDs.removeAll { $0 == sceneID }
        if pendingActiveSceneID == sceneID {
            pendingActiveSceneID = nil
        }
        if activeSceneID == sceneID {
            // Commands remain usable when the key board closes while a utility
            // window has focus and another registered board stays open.
            activeSceneID = registeredSceneIDs.last
        }
    }

    func markActive(sceneID: UUID) {
        guard registeredSceneIDs.contains(sceneID) else {
            pendingActiveSceneID = sceneID
            return
        }
        pendingActiveSceneID = nil
        setActive(sceneID: sceneID)
    }

    @discardableResult
    func requestShortcut(_ action: ProjectBoardShortcutAction) -> Bool {
        guard let activeSceneID else { return false }
        NotificationCenter.default.post(
            name: .suisuiProjectBoardShortcutRequested,
            object: ProjectBoardShortcutRequest(sceneID: activeSceneID, action: action)
        )
        return true
    }

    func openInActiveSceneOrRequestNew(route: BoardRoute, openWindow: () -> Void) {
        guard !requestShortcut(.route(route)) else { return }
        _ = requestOpen(route: route)
        openWindow()
    }

    @discardableResult
    func requestOpen(
        id: UUID = UUID(),
        targetSceneID: UUID? = nil,
        route: BoardRoute
    ) -> ProjectBoardOpenRequest? {
        let request = ProjectBoardOpenRequest(
            id: id,
            targetSceneID: targetSceneID,
            route: route
        )
        guard state.submit(request) else {
            return nil
        }
        if ProjectBoardScenePersistence.shouldUpdateInitialRoute(for: request) {
            // Broadcast navigation also defines where a newly opened window
            // starts; exact-target requests must never leak into other scenes.
            defaults.set(
                ProjectBoardRouteCodec.rawValue(for: route),
                forKey: ProjectBoardSelectionPersistence.storageKey
            )
        }
        publishDeliveryOpportunity()
        return request
    }

    func consumeNext(for sceneID: UUID) -> ProjectBoardOpenRequest? {
        state.consumeNext(for: sceneID)
    }

    func consume(requestID: UUID, for sceneID: UUID) -> ProjectBoardOpenRequest? {
        state.consume(requestID: requestID, for: sceneID)
    }

    func acknowledgeApplied(requestID: UUID) {
        guard applicationAcknowledgements.acknowledge(requestID) else {
            return
        }
        lastAppliedRequestID = requestID
    }

    func hasApplied(requestID: UUID) -> Bool {
        applicationAcknowledgements.contains(requestID)
    }

    private func publishDeliveryOpportunity() {
        deliveryRevision &+= 1
    }

    private func setActive(sceneID: UUID) {
        registeredSceneIDs.removeAll { $0 == sceneID }
        registeredSceneIDs.append(sceneID)
        activeSceneID = sceneID
    }
}
