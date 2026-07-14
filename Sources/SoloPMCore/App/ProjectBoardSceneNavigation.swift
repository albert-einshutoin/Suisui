import Foundation

/// Storage keys and pure restore policy for one Project Board window.
public enum ProjectBoardScenePersistence {
    public static let sceneIDStorageKey = "solopm.projectBoard.sceneID"
    public static let routeStorageKey = "solopm.projectBoard.sceneRoute"

    public static func restoredRoute(
        sceneRawValue: String,
        initialRawValue: String,
        availableProjectIDs: Set<Int64>
    ) -> BoardRoute {
        // Scene storage is authoritative after a window has navigated. The
        // app preference is intentionally consulted only for a new window.
        let rawValue = sceneRawValue.isEmpty ? initialRawValue : sceneRawValue
        return ProjectBoardRouteCodec.route(
            from: rawValue,
            availableProjectIDs: availableProjectIDs
        )
    }
}

/// Immutable intent to route one Project Board scene to a typed destination.
public struct ProjectBoardOpenRequest: Equatable, Sendable {
    public let id: UUID
    public let targetSceneID: UUID?
    public let route: BoardRoute

    public init(
        id: UUID = UUID(),
        targetSceneID: UUID? = nil,
        route: BoardRoute
    ) {
        self.id = id
        self.targetSceneID = targetSceneID
        self.route = route
    }
}

/// Pure matching boundary shared by app composition and reducer tests.
public enum ProjectBoardSceneNavigation {
    public static func route(
        for request: ProjectBoardOpenRequest,
        sceneID: UUID
    ) -> BoardRoute? {
        guard request.targetSceneID == nil || request.targetSceneID == sceneID else {
            return nil
        }
        return request.route
    }
}

/// Pure request-lifetime state. App composition serializes mutations on the
/// MainActor, while keeping registration, expiration, and one-consumer rules
/// independently testable without SwiftUI or window-server timing.
public struct ProjectBoardSceneNavigationState: Sendable {
    private var registeredSceneIDs: Set<UUID> = []
    private var pendingRequests: [ProjectBoardOpenRequest] = []
    private var terminalRequestIDs: Set<UUID> = []

    public init() {}

    public mutating func register(sceneID: UUID) {
        registeredSceneIDs.insert(sceneID)
    }

    public mutating func unregister(sceneID: UUID) {
        guard registeredSceneIDs.remove(sceneID) != nil else {
            return
        }

        // An exact request belongs to one concrete window lifetime. Dropping
        // it when that scene closes prevents a later scene reusing restored
        // storage from replaying a stale navigation side effect.
        let expiredIDs = pendingRequests.compactMap { request in
            request.targetSceneID == sceneID ? request.id : nil
        }
        terminalRequestIDs.formUnion(expiredIDs)
        pendingRequests.removeAll { $0.targetSceneID == sceneID }
    }

    /// Returns false for a duplicate ID already pending, consumed, or expired.
    @discardableResult
    public mutating func submit(_ request: ProjectBoardOpenRequest) -> Bool {
        guard !terminalRequestIDs.contains(request.id),
              !pendingRequests.contains(where: { $0.id == request.id }) else {
            return false
        }
        pendingRequests.append(request)
        return true
    }

    /// Atomically claims the oldest request eligible for this registered scene.
    /// Removing before returning is why an untargeted request still has exactly
    /// one consumer even when multiple windows observe the same publication.
    public mutating func consumeNext(for sceneID: UUID) -> ProjectBoardOpenRequest? {
        guard registeredSceneIDs.contains(sceneID),
              let index = pendingRequests.firstIndex(where: {
                  ProjectBoardSceneNavigation.route(for: $0, sceneID: sceneID) != nil
              }) else {
            return nil
        }

        let request = pendingRequests.remove(at: index)
        terminalRequestIDs.insert(request.id)
        return request
    }

    /// Atomically claims one known request from a notification carrying its ID.
    public mutating func consume(
        requestID: UUID,
        for sceneID: UUID
    ) -> ProjectBoardOpenRequest? {
        guard registeredSceneIDs.contains(sceneID),
              let index = pendingRequests.firstIndex(where: {
                  $0.id == requestID
                      && ProjectBoardSceneNavigation.route(for: $0, sceneID: sceneID) != nil
              }) else {
            return nil
        }

        let request = pendingRequests.remove(at: index)
        terminalRequestIDs.insert(request.id)
        return request
    }
}
