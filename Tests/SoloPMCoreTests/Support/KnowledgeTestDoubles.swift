import Foundation
@testable import SoloPMCore

struct StaticEmbeddingProvider: EmbeddingProvider {
    let providerID = "static"
    var dimensions: Int {
        vectorsByText.values.first?.count ?? 0
    }
    private let vectorsByText: [String: [Double]]

    init(vectorsByText: [String: [Double]]) {
        self.vectorsByText = vectorsByText
    }

    func embed(_ request: EmbeddingRequest) throws -> KnowledgeEmbeddingVector {
        guard request.userApproved else {
            throw EmbeddingError.userApprovalRequired
        }
        let values = vectorsByText[request.text] ?? []
        return KnowledgeEmbeddingVector(
            frameID: request.frameID,
            values: testNormalize(values),
            providerID: providerID,
            redactedPreview: testRedactedPreview(request.text)
        )
    }
}

final class InMemoryKnowledgeVectorIndex: KnowledgeVectorIndex, @unchecked Sendable {
    let expectedDimensions: Int
    private let lock = NSLock()
    private var vectors: [Int64: KnowledgeEmbeddingVector]

    init(expectedDimensions: Int, vectors: [Int64: KnowledgeEmbeddingVector] = [:]) {
        self.expectedDimensions = expectedDimensions
        self.vectors = vectors
    }

    func upsert(_ vector: KnowledgeEmbeddingVector) throws {
        try validate(vector.values)
        try KnowledgeVectorValidator.validateProviderID(vector.providerID)
        lock.lock()
        defer { lock.unlock() }
        vectors[vector.frameID] = vector
    }

    func delete(frameID: Int64) throws {
        lock.lock()
        defer { lock.unlock() }
        vectors.removeValue(forKey: frameID)
    }

    func vector(frameID: Int64) throws -> KnowledgeEmbeddingVector? {
        lock.lock()
        defer { lock.unlock() }
        return vectors[frameID]
    }

    func search(queryVector: [Double], topK: Int, threshold: Double) throws -> [KnowledgeVectorSearchResult] {
        try validate(queryVector)
        lock.lock()
        defer { lock.unlock() }
        return vectors.values
            .map {
                KnowledgeVectorSearchResult(
                    frameID: $0.frameID,
                    score: testCosineSimilarity(queryVector, $0.values),
                    providerID: $0.providerID
                )
            }
            .filter { $0.score >= threshold }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.frameID < rhs.frameID
                }
                return lhs.score > rhs.score
            }
            .prefix(topK)
            .map { $0 }
    }

    private func validate(_ values: [Double]) throws {
        guard values.count == expectedDimensions else {
            throw KnowledgeVectorIndexError.dimensionMismatch(expected: expectedDimensions, actual: values.count)
        }
    }
}

struct StaticKnowledgeTextSearch: KnowledgeTextSearch {
    private let resultsByQuery: [String: [KnowledgeFrameRecord]]

    init(resultsByQuery: [String: [KnowledgeFrameRecord]]) {
        self.resultsByQuery = resultsByQuery
    }

    func search(query: String) throws -> [KnowledgeFrameRecord] {
        resultsByQuery[query] ?? []
    }
}

final class InMemoryWeKnoraClient: WeKnoraClient, @unchecked Sendable {
    var nextError: WeKnoraConnectorError?

    init(nextError: WeKnoraConnectorError? = nil) {
        self.nextError = nextError
    }

    func send(_ preview: WeKnoraPreview) throws -> WeKnoraResponse {
        if let nextError {
            self.nextError = nil
            throw nextError
        }
        return WeKnoraResponse(summary: "ok")
    }
}

private func testNormalize(_ values: [Double]) -> [Double] {
    let magnitude = sqrt(values.reduce(0) { $0 + $1 * $1 })
    guard magnitude > 0 else {
        return values
    }
    return values.map { $0 / magnitude }
}

private func testCosineSimilarity(_ lhs: [Double], _ rhs: [Double]) -> Double {
    guard lhs.count == rhs.count, !lhs.isEmpty else {
        return 0
    }
    let dot = zip(lhs, rhs).reduce(0) { $0 + $1.0 * $1.1 }
    let lhsMagnitude = sqrt(lhs.reduce(0) { $0 + $1 * $1 })
    let rhsMagnitude = sqrt(rhs.reduce(0) { $0 + $1 * $1 })
    guard lhsMagnitude > 0, rhsMagnitude > 0 else {
        return 0
    }
    return dot / (lhsMagnitude * rhsMagnitude)
}

private func testRedactedPreview(_ text: String) -> String {
    DeveloperSecretRedactor().redact(text).text
}
