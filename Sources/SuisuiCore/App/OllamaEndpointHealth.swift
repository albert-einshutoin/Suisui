import Foundation

/// Snapshot of the Ollama-compatible endpoint, derived from the injected health
/// checker. The status is the only source of truth for Ollama planning
/// readiness; display text is derived from it.
public enum OllamaEndpointHealth: Equatable, Sendable {
    case unknown
    case checking
    case ready
    case failure(reason: String)
}

/// Port for probing the local Ollama-compatible endpoint. Production
/// implementations issue an HTTP probe, tests substitute deterministic
/// results so the readiness gate can be exercised without a live server.
public protocol OllamaEndpointHealthChecking: Sendable {
    func currentStatus() async -> OllamaEndpointHealth
}

/// Default `OllamaEndpointHealthChecking` that reports `.unknown` until the
/// app or tests inject a real probe. Keeping the default explicit prevents the
/// onboarding sheet from accidentally treating an unprobed endpoint as ready.
public struct UncheckedOllamaEndpointHealthChecker: OllamaEndpointHealthChecking, Sendable {
    public init() {}

    public func currentStatus() async -> OllamaEndpointHealth {
        .unknown
    }
}

/// Production `OllamaEndpointHealthChecking` that issues a HEAD-style probe to
/// the Ollama root URL. The probe times out quickly so onboarding readiness
/// never blocks the MainActor behind a slow local server.
public struct URLSessionOllamaEndpointHealthChecker: OllamaEndpointHealthChecking, Sendable {
    public let baseURL: URL?
    public let session: any OllamaHealthProbing
    public let timeout: TimeInterval

    public init(
        baseURL: URL? = LLMProviderCatalog.entry(for: .ollamaCompatible).baseURL,
        session: any OllamaHealthProbing = URLSessionOllamaHealthProbe(),
        timeout: TimeInterval = 1.5
    ) {
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
    }

    public func currentStatus() async -> OllamaEndpointHealth {
        guard let baseURL else {
            return .unknown
        }
        do {
            let success = try await session.probe(
                url: baseURL,
                timeout: timeout
            )
            return success ? .ready : .failure(reason: "Local Ollama-compatible server did not respond.")
        } catch {
            return .failure(reason: "Local Ollama-compatible server is unreachable.")
        }
    }
}

/// Sendable HTTP probe abstraction so tests can drive the health checker
/// without standing up a real local server.
public protocol OllamaHealthProbing: Sendable {
    func probe(url: URL, timeout: TimeInterval) async throws -> Bool
}

public struct URLSessionOllamaHealthProbe: OllamaHealthProbing, Sendable {
    public init() {}

    public func probe(url: URL, timeout: TimeInterval) async throws -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            return false
        }
        return (200..<500).contains(http.statusCode)
    }
}
