import Foundation

public enum CodexAccountReadiness: Equatable, Sendable {
    case notInstalled
    case unsupportedVersion(installed: String, minimum: String)
    case signedOut
    case authenticating
    case ready(plan: CodexPlanType)
    case usageLimited(resetAt: Date?)
    case workspaceDisabled
    case unavailable(redactedReason: String)
}

public struct CodexAccountSnapshot: Equatable, Sendable {
    public let account: CodexAccount?
    public let readiness: CodexAccountReadiness
}

public struct CodexLoginAttempt: Equatable, Sendable {
    public let id: String
    public let authorizationURL: URL
    public let userCode: String?
}

public struct CodexRateLimitSnapshot: Equatable, Sendable {
    public let usedPercent: Double?
    public let resetsAt: Date?
}

public struct CodexModel: Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let isDefault: Bool
}

public enum CodexAccountClientError: Error, Equatable, Sendable {
    case invalidResponse
    case unsafeAuthenticationURL
    case loginFailed(redactedReason: String)
    case loginTimedOut
    case staleLoginID
}

public protocol CodexAccountServicing: Sendable {
    func initialize(clientVersion: String) async throws
    func readAccount(refresh: Bool) async throws -> CodexAccountSnapshot
    func startLogin(_ kind: CodexLoginKind) async throws -> CodexLoginAttempt
    func awaitLogin(id: String, timeout: TimeInterval) async throws -> CodexAccountReadiness
    func cancelLogin(id: String) async throws
    func logout() async throws
    func readRateLimits() async throws -> CodexRateLimitSnapshot
    func listModels() async throws -> [CodexModel]
}

public actor CodexAppServerAccountClient: CodexAccountServicing {
    private struct LoginWaiter {
        let continuation: CheckedContinuation<CodexAccountReadiness, Error>
    }

    private let transport: any CodexAppServerTransport
    private var observerTask: Task<Void, Never>?
    private var activeLoginIDs: Set<String> = []
    private var loginWaiters: [String: LoginWaiter] = [:]
    private var completedLogins: [String: Result<CodexAccountReadiness, CodexAccountClientError>] = [:]

    public init(transport: any CodexAppServerTransport) {
        self.transport = transport
    }

    deinit {
        observerTask?.cancel()
    }

    public func initialize(clientVersion: String) async throws {
        ensureNotificationObserver()
        let params: JSONValue = .object([
            "clientInfo": .object([
                "name": .string("suisui"),
                "title": .string("Suisui"),
                "version": .string(clientVersion)
            ])
        ])
        _ = try await transport.request(method: CodexAppServerMethod.initialize, params: params, timeout: 10)
        try await transport.notify(method: "initialized", params: nil)
    }

    public func readAccount(refresh _: Bool = false) async throws -> CodexAccountSnapshot {
        let response = try await transport.request(
            method: CodexAppServerMethod.accountRead,
            // Codex owns normal token refresh. Suisui intentionally avoids the
            // similarly named proactive-refresh wire field to keep credential
            // concepts out of its encoded traffic and diagnostics.
            params: .object([:]),
            timeout: 10
        )
        let decoded: CodexAccountReadResponse = try decode(response.result)
        guard let account = decoded.account else {
            return CodexAccountSnapshot(account: nil, readiness: .signedOut)
        }
        switch account {
        case let .chatGPT(_, plan):
            return CodexAccountSnapshot(account: account, readiness: .ready(plan: plan))
        case let .unsupported(type):
            return CodexAccountSnapshot(
                account: account,
                readiness: .unavailable(redactedReason: "Unsupported Codex account type: \(type).")
            )
        }
    }

    public func startLogin(_ kind: CodexLoginKind) async throws -> CodexLoginAttempt {
        ensureNotificationObserver()
        let params = try encodeValue(CodexLoginStartParams(type: kind))
        let response = try await transport.request(
            method: CodexAppServerMethod.accountLoginStart,
            params: params,
            timeout: 10
        )
        let decoded: CodexLoginStartResponse = try decode(response.result)
        let attempt: CodexLoginAttempt
        switch decoded {
        case let .chatGPTBrowser(loginID, authenticationURL):
            try validateAuthenticationURL(authenticationURL)
            attempt = CodexLoginAttempt(id: loginID, authorizationURL: authenticationURL, userCode: nil)
        case let .chatGPTDeviceCode(loginID, userCode, verificationURL):
            try validateAuthenticationURL(verificationURL)
            attempt = CodexLoginAttempt(id: loginID, authorizationURL: verificationURL, userCode: userCode)
        }
        activeLoginIDs.insert(attempt.id)
        return attempt
    }

    public func awaitLogin(id: String, timeout: TimeInterval) async throws -> CodexAccountReadiness {
        if let result = completedLogins.removeValue(forKey: id) {
            return try result.get()
        }
        guard activeLoginIDs.contains(id) else { throw CodexAccountClientError.staleLoginID }
        return try await withCheckedThrowingContinuation { continuation in
            loginWaiters[id] = LoginWaiter(continuation: continuation)
            Task { [weak self] in
                let nanoseconds = UInt64(max(0, timeout) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                await self?.timeoutLogin(id: id)
            }
        }
    }

    public func cancelLogin(id: String) async throws {
        _ = try await transport.request(
            method: CodexAppServerMethod.accountLoginCancel,
            params: .object(["loginId": .string(id)]),
            timeout: 10
        )
        activeLoginIDs.remove(id)
        loginWaiters.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError())
    }

    public func logout() async throws {
        _ = try await transport.request(method: CodexAppServerMethod.accountLogout, params: .object([:]), timeout: 10)
        for waiter in loginWaiters.values {
            waiter.continuation.resume(throwing: CancellationError())
        }
        loginWaiters.removeAll()
        activeLoginIDs.removeAll()
    }

    public func readRateLimits() async throws -> CodexRateLimitSnapshot {
        let response = try await transport.request(
            method: CodexAppServerMethod.accountRateLimitsRead,
            params: .object([:]),
            timeout: 10
        )
        guard case let .object(root) = response.result,
              case let .object(rateLimits)? = root["rateLimits"] else {
            throw CodexAccountClientError.invalidResponse
        }
        let primary = rateLimits.objectValue(for: "primary")
        let usedPercent = primary?.doubleValue(for: "usedPercent")
        let resetsAt = primary?.doubleValue(for: "resetsAt").map(Date.init(timeIntervalSince1970:))
        return CodexRateLimitSnapshot(usedPercent: usedPercent, resetsAt: resetsAt)
    }

    public func listModels() async throws -> [CodexModel] {
        let response = try await transport.request(
            method: CodexAppServerMethod.modelList,
            params: .object(["limit": .number(100)]),
            timeout: 10
        )
        guard case let .object(root) = response.result,
              case let .array(items)? = root["data"] else {
            throw CodexAccountClientError.invalidResponse
        }
        return try items.map { item in
            guard case let .object(model) = item,
                  let id = model.stringValue(for: "id"),
                  let displayName = model.stringValue(for: "displayName"),
                  let isDefault = model.boolValue(for: "isDefault") else {
                throw CodexAccountClientError.invalidResponse
            }
            return CodexModel(id: id, displayName: displayName, isDefault: isDefault)
        }
    }

    private func ensureNotificationObserver() {
        guard observerTask == nil else { return }
        observerTask = Task { [weak self, transport] in
            let stream = await transport.notifications()
            for await notification in stream {
                guard let self else { return }
                await self.handle(notification)
            }
        }
    }

    private func handle(_ notification: CodexJSONRPCNotification) async {
        guard notification.method == "account/login/completed",
              let params = notification.params?.object,
              let loginID = params.stringValue(for: "loginId"),
              activeLoginIDs.contains(loginID) else {
            return
        }
        guard params.boolValue(for: "success") == true else {
            let reason = params.stringValue(for: "error") ?? "Codex login failed."
            completeLogin(id: loginID, result: .failure(.loginFailed(redactedReason: sanitized(reason))))
            return
        }
        do {
            let snapshot = try await readAccount(refresh: true)
            completeLogin(id: loginID, result: .success(snapshot.readiness))
        } catch {
            completeLogin(id: loginID, result: .failure(.loginFailed(redactedReason: "Codex account could not be verified.")))
        }
    }

    private func completeLogin(id: String, result: Result<CodexAccountReadiness, CodexAccountClientError>) {
        activeLoginIDs.remove(id)
        guard let waiter = loginWaiters.removeValue(forKey: id) else {
            completedLogins[id] = result
            return
        }
        switch result {
        case let .success(readiness):
            waiter.continuation.resume(returning: readiness)
        case let .failure(error):
            waiter.continuation.resume(throwing: error)
        }
    }

    private func timeoutLogin(id: String) {
        guard let waiter = loginWaiters.removeValue(forKey: id) else { return }
        activeLoginIDs.remove(id)
        waiter.continuation.resume(throwing: CodexAccountClientError.loginTimedOut)
    }

    private func validateAuthenticationURL(_ url: URL) throws {
        let allowedHosts: Set<String> = ["chatgpt.com", "auth.openai.com"]
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              allowedHosts.contains(host) else {
            throw CodexAccountClientError.unsafeAuthenticationURL
        }
    }

    private func decode<T: Decodable>(_ value: JSONValue) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
        } catch {
            throw CodexAccountClientError.invalidResponse
        }
    }

    private func encodeValue<T: Encodable>(_ value: T) throws -> JSONValue {
        do {
            return try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
        } catch {
            throw CodexAccountClientError.invalidResponse
        }
    }

    private func sanitized(_ reason: String) -> String {
        let redacted = DeveloperSecretRedactor().redact(reason).text
        return String(redacted.prefix(300))
    }
}

private extension JSONValue {
    var object: [String: JSONValue]? {
        guard case let .object(value) = self else { return nil }
        return value
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    func stringValue(for key: String) -> String? {
        guard case let .string(value)? = self[key] else { return nil }
        return value
    }

    func boolValue(for key: String) -> Bool? {
        guard case let .bool(value)? = self[key] else { return nil }
        return value
    }

    func doubleValue(for key: String) -> Double? {
        guard case let .number(value)? = self[key] else { return nil }
        return value
    }

    func objectValue(for key: String) -> [String: JSONValue]? {
        guard case let .object(value)? = self[key] else { return nil }
        return value
    }
}
