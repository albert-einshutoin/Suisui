import Combine
import Foundation
import SuisuiCore

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

    private var state = ProjectBoardSceneNavigationState()
    private var applicationAcknowledgements = ProjectBoardSceneApplicationAcknowledgements()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func register(sceneID: UUID) {
        state.register(sceneID: sceneID)
        publishDeliveryOpportunity()
    }

    func unregister(sceneID: UUID) {
        state.unregister(sceneID: sceneID)
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
}
