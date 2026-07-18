import Foundation

/// Shared capacity for request metadata and ID-keyed bridge payloads.
///
/// Keeping one default avoids configuration drift, while each store remains
/// independently bounded because route-only requests intentionally have no
/// corresponding payload.
public enum ProjectBoardSceneRequestLimits {
    public static let pending = 64
}

/// Storage keys and pure restore policy for one Project Board window.
public enum ProjectBoardScenePersistence {
    public static let sceneIDStorageKey = "solopm.projectBoard.sceneID"
    public static let routeStorageKey = "solopm.projectBoard.sceneRoute"

    public static func restoredRoute(
        sceneRawValue: String,
        initialRawValue: String,
        availableProjectIDs: Set<Int64>
    ) -> BoardRoute {
        restoredResolution(
            sceneRawValue: sceneRawValue,
            initialRawValue: initialRawValue,
            availableProjectIDs: availableProjectIDs
        ).route
    }

    public static func restoredResolution(
        sceneRawValue: String,
        initialRawValue: String,
        availableProjectIDs: Set<Int64>
    ) -> ProjectBoardRouteResolution {
        // Scene storage is authoritative after a window has navigated. The
        // app preference is intentionally consulted only for a new window.
        let rawValue = sceneRawValue.isEmpty ? initialRawValue : sceneRawValue
        return ProjectBoardRouteCodec.resolution(
            from: rawValue,
            availableProjectIDs: availableProjectIDs
        )
    }

    /// Only a broadcast expresses the default intent for future windows. An
    /// exact request belongs exclusively to its target scene's stored route.
    public static func shouldUpdateInitialRoute(
        for request: ProjectBoardOpenRequest
    ) -> Bool {
        request.targetSceneID == nil
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

/// Small ID-keyed payload buffer used by app bridges while a scene request is
/// waiting to be claimed. Keeping it in Core makes consecutive/deduplicated
/// payload lifetime testable without importing SwiftUI app types.
public struct ProjectBoardRequestPayloadStore<Payload> {
    private var payloads: [UUID: Payload] = [:]
    private let limit: Int

    public init(limit: Int = ProjectBoardSceneRequestLimits.pending) {
        precondition(limit > 0, "Pending request payload limit must be above zero")
        self.limit = limit
    }

    /// Returns false without replacing the first payload for a duplicate ID.
    @discardableResult
    public mutating func store(_ payload: Payload, id: UUID) -> Bool {
        guard payloads[id] == nil, payloads.count < limit else {
            return false
        }
        payloads[id] = payload
        return true
    }

    public mutating func consume(id: UUID) -> Payload? {
        payloads.removeValue(forKey: id)
    }

    public mutating func discard(id: UUID) {
        payloads.removeValue(forKey: id)
    }
}

/// Bounded acknowledgement history for app-level scene coordinators. A route
/// consumer records only after applying the request, letting follow-up UI work
/// wait for the exact navigation instead of guessing with render delays.
public struct ProjectBoardSceneApplicationAcknowledgements: Sendable {
    private var appliedRequestIDs: Set<UUID> = []
    private var appliedRequestOrder: [UUID] = []
    private let limit: Int

    public init(limit: Int = ProjectBoardSceneRequestLimits.pending) {
        precondition(limit > 0, "Applied request history limit must be above zero")
        self.limit = limit
    }

    @discardableResult
    public mutating func acknowledge(_ requestID: UUID) -> Bool {
        guard appliedRequestIDs.insert(requestID).inserted else {
            return false
        }
        appliedRequestOrder.append(requestID)
        if appliedRequestOrder.count > limit {
            appliedRequestIDs.remove(appliedRequestOrder.removeFirst())
        }
        return true
    }

    public func contains(_ requestID: UUID) -> Bool {
        appliedRequestIDs.contains(requestID)
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
    private var terminalRequestOrder: [UUID] = []
    private let pendingRequestLimit: Int
    private let terminalHistoryLimit: Int

    public init(
        pendingRequestLimit: Int = ProjectBoardSceneRequestLimits.pending,
        terminalHistoryLimit: Int = 512
    ) {
        precondition(pendingRequestLimit > 0, "Pending request limit must be above zero")
        precondition(terminalHistoryLimit > 0, "Terminal request history must be bounded above zero")
        self.pendingRequestLimit = pendingRequestLimit
        self.terminalHistoryLimit = terminalHistoryLimit
    }

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
        for requestID in expiredIDs {
            markTerminal(requestID)
        }
        pendingRequests.removeAll { $0.targetSceneID == sceneID }
    }

    /// Returns false for a duplicate ID already pending, consumed, or expired.
    @discardableResult
    public mutating func submit(_ request: ProjectBoardOpenRequest) -> Bool {
        guard !terminalRequestIDs.contains(request.id),
              !pendingRequests.contains(where: { $0.id == request.id }) else {
            return false
        }
        if let targetSceneID = request.targetSceneID,
           !registeredSceneIDs.contains(targetSceneID) {
            // Unknown exact targets are not terminal: registration followed by
            // retry is valid, while silently retaining a stale target is not.
            return false
        }
        guard pendingRequests.count < pendingRequestLimit else {
            // Preserve already accepted user intent instead of silently
            // evicting it. Callers can discard a same-ID bridge payload and
            // retry this non-terminal request after capacity becomes free.
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
        markTerminal(request.id)
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
        markTerminal(request.id)
        return request
    }

    private mutating func markTerminal(_ requestID: UUID) {
        guard terminalRequestIDs.insert(requestID).inserted else {
            return
        }
        terminalRequestOrder.append(requestID)
        guard terminalRequestOrder.count > terminalHistoryLimit else {
            return
        }
        // Terminal IDs only protect this process from recent duplicate
        // deliveries. Bounding the FIFO avoids turning a long-running app into
        // an ever-growing request log while retaining deterministic eviction.
        let prunedRequestID = terminalRequestOrder.removeFirst()
        terminalRequestIDs.remove(prunedRequestID)
    }
}
