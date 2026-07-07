import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Line-oriented streaming HTTP transport for server-sent-events providers.
/// Implementations must yield response body lines as they arrive so callers
/// can surface incremental output while the request is still running.
public protocol HTTPByteStreamClient: Sendable {
    func lines(for request: URLRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse)
}

public struct URLSessionHTTPByteStreamClient: HTTPByteStreamClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func lines(for request: URLRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        let stream = AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }

        return (stream, httpResponse)
    }
}
