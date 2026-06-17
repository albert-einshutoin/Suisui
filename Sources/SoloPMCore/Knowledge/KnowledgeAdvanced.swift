import Foundation

public enum RetrievalPrivacyBoundary: String, Codable, Equatable, Sendable {
    case localOnly
    case byokCloudFallback
}

public struct RetrievalConstraints: Equatable, Sendable {
    public var maxLatencyMilliseconds: Int
    public var maxStorageMegabytes: Int
    public var privacyBoundary: RetrievalPrivacyBoundary
    public var maxEmbeddingDimensions: Int

    public init(
        maxLatencyMilliseconds: Int,
        maxStorageMegabytes: Int,
        privacyBoundary: RetrievalPrivacyBoundary,
        maxEmbeddingDimensions: Int
    ) {
        self.maxLatencyMilliseconds = maxLatencyMilliseconds
        self.maxStorageMegabytes = maxStorageMegabytes
        self.privacyBoundary = privacyBoundary
        self.maxEmbeddingDimensions = maxEmbeddingDimensions
    }
}

public struct RetrievalFixture: Equatable, Sendable {
    public var id: String
    public var query: String
    public var expectedFrameIDs: [Int64]
    public var allowedAlternativeFrameIDs: [Int64]
    public var requiresSemanticRetrieval: Bool

    public init(
        id: String,
        query: String,
        expectedFrameIDs: [Int64],
        allowedAlternativeFrameIDs: [Int64] = [],
        requiresSemanticRetrieval: Bool
    ) {
        self.id = id
        self.query = query
        self.expectedFrameIDs = expectedFrameIDs
        self.allowedAlternativeFrameIDs = allowedAlternativeFrameIDs
        self.requiresSemanticRetrieval = requiresSemanticRetrieval
    }
}

public struct RetrievalRequirementsReview: Equatable, Sendable {
    public var fixtures: [RetrievalFixture]
    public var constraints: RetrievalConstraints

    public init(fixtures: [RetrievalFixture], constraints: RetrievalConstraints) {
        self.fixtures = fixtures
        self.constraints = constraints
    }

    public var semanticFixtures: [RetrievalFixture] {
        fixtures.filter(\.requiresSemanticRetrieval)
    }

    public var hasConcreteFTSGap: Bool {
        !semanticFixtures.isEmpty
    }

    public var sqliteVecJustification: String {
        "\(semanticFixtures.count) semantic fixtures exceed FTS5 exact matching."
    }
}

public struct EmbeddingRequest: Equatable, Sendable {
    public var frameID: Int64
    public var text: String
    public var userApproved: Bool

    public init(frameID: Int64, text: String, userApproved: Bool) {
        self.frameID = frameID
        self.text = text
        self.userApproved = userApproved
    }
}

public struct KnowledgeEmbeddingVector: Equatable, Sendable {
    public var frameID: Int64
    public var values: [Double]
    public var providerID: String
    public var redactedPreview: String

    public init(frameID: Int64, values: [Double], providerID: String, redactedPreview: String) {
        self.frameID = frameID
        self.values = values
        self.providerID = providerID
        self.redactedPreview = redactedPreview
    }
}

public enum EmbeddingError: Error, Equatable, Sendable {
    case providerUnavailable(String)
    case userApprovalRequired
    case invalidDimensions(Int)
}

public protocol EmbeddingProvider: Sendable {
    var providerID: String { get }
    var dimensions: Int { get }
    func embed(_ request: EmbeddingRequest) throws -> KnowledgeEmbeddingVector
}

public struct DisabledEmbeddingProvider: EmbeddingProvider {
    public let providerID = "disabled"
    public let dimensions = 0

    public init() {}

    public func embed(_ request: EmbeddingRequest) throws -> KnowledgeEmbeddingVector {
        throw EmbeddingError.providerUnavailable(providerID)
    }
}

public struct LocalHashEmbeddingProvider: EmbeddingProvider {
    public let providerID = "local_hash"
    public let dimensions: Int

    public init(dimensions: Int) {
        self.dimensions = dimensions
    }

    public func embed(_ request: EmbeddingRequest) throws -> KnowledgeEmbeddingVector {
        guard request.userApproved else {
            throw EmbeddingError.userApprovalRequired
        }
        guard dimensions > 0 else {
            throw EmbeddingError.invalidDimensions(dimensions)
        }

        var values = Array(repeating: 0.0, count: dimensions)
        let tokens = request.text
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
        for token in tokens where !token.isEmpty {
            let bucket = stableBucket(String(token), dimensions: dimensions)
            values[bucket] += 1
        }
        values = normalize(values)

        return KnowledgeEmbeddingVector(
            frameID: request.frameID,
            values: values,
            providerID: providerID,
            redactedPreview: redactedPreview(request.text)
        )
    }

    private func stableBucket(_ value: String, dimensions: Int) -> Int {
        let hash = value.unicodeScalars.reduce(0) { partial, scalar in
            ((partial * 31) + Int(scalar.value)) & 0x7fffffff
        }
        return hash % dimensions
    }
}

public struct BYOKOpenAIEmbeddingProvider: EmbeddingProvider {
    public let providerID = "openai_byok_fallback"
    public var dimensions: Int { fallback.dimensions }
    private let secretStore: any SecretStore
    private let fallback: any EmbeddingProvider

    public init(secretStore: any SecretStore, fallback: any EmbeddingProvider) {
        self.secretStore = secretStore
        self.fallback = fallback
    }

    public func embed(_ request: EmbeddingRequest) throws -> KnowledgeEmbeddingVector {
        guard let apiKey = try secretStore.read(.openAIAPIKey), !apiKey.isEmpty else {
            throw EmbeddingError.providerUnavailable(providerID)
        }
        return try fallback.embed(request)
    }
}

public struct StaticEmbeddingProvider: EmbeddingProvider {
    public let providerID = "static"
    public var dimensions: Int {
        vectorsByText.values.first?.count ?? 0
    }
    private let vectorsByText: [String: [Double]]

    public init(vectorsByText: [String: [Double]]) {
        self.vectorsByText = vectorsByText
    }

    public func embed(_ request: EmbeddingRequest) throws -> KnowledgeEmbeddingVector {
        guard request.userApproved else {
            throw EmbeddingError.userApprovalRequired
        }
        guard let values = vectorsByText[request.text] else {
            return KnowledgeEmbeddingVector(frameID: request.frameID, values: [], providerID: providerID, redactedPreview: redactedPreview(request.text))
        }
        return KnowledgeEmbeddingVector(frameID: request.frameID, values: normalize(values), providerID: providerID, redactedPreview: redactedPreview(request.text))
    }
}

public struct KnowledgeVectorSearchResult: Equatable, Sendable {
    public var frameID: Int64
    public var score: Double
    public var providerID: String
}

public enum KnowledgeVectorIndexError: Error, Equatable, Sendable {
    case dimensionMismatch(expected: Int, actual: Int)
}

public protocol KnowledgeVectorIndex: Sendable {
    var expectedDimensions: Int { get }
    func upsert(_ vector: KnowledgeEmbeddingVector) throws
    func delete(frameID: Int64) throws
    func vector(frameID: Int64) throws -> KnowledgeEmbeddingVector?
    func search(queryVector: [Double], topK: Int, threshold: Double) throws -> [KnowledgeVectorSearchResult]
}

public final class InMemoryKnowledgeVectorIndex: KnowledgeVectorIndex, @unchecked Sendable {
    public let expectedDimensions: Int
    private let lock = NSLock()
    private var vectors: [Int64: KnowledgeEmbeddingVector]

    public init(expectedDimensions: Int, vectors: [Int64: KnowledgeEmbeddingVector] = [:]) {
        self.expectedDimensions = expectedDimensions
        self.vectors = vectors
    }

    public func upsert(_ vector: KnowledgeEmbeddingVector) throws {
        try validate(vector.values)
        lock.withLock {
            vectors[vector.frameID] = vector
        }
    }

    public func delete(frameID: Int64) throws {
        _ = lock.withLock {
            vectors.removeValue(forKey: frameID)
        }
    }

    public func vector(frameID: Int64) throws -> KnowledgeEmbeddingVector? {
        lock.withLock {
            vectors[frameID]
        }
    }

    public func search(queryVector: [Double], topK: Int, threshold: Double) throws -> [KnowledgeVectorSearchResult] {
        try validate(queryVector)
        return lock.withLock {
            vectors.values
                .map {
                    KnowledgeVectorSearchResult(
                        frameID: $0.frameID,
                        score: cosineSimilarity(queryVector, $0.values),
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
    }

    private func validate(_ values: [Double]) throws {
        guard values.count == expectedDimensions else {
            throw KnowledgeVectorIndexError.dimensionMismatch(expected: expectedDimensions, actual: values.count)
        }
    }
}

public final class SQLiteKnowledgeVectorIndex: KnowledgeVectorIndex, @unchecked Sendable {
    public let expectedDimensions: Int
    private let connection: SQLiteConnection
    private let lock = NSLock()

    public init(connection: SQLiteConnection, expectedDimensions: Int) {
        self.connection = connection
        self.expectedDimensions = expectedDimensions
    }

    public func upsert(_ vector: KnowledgeEmbeddingVector) throws {
        try validate(vector.values)
        let valuesJSON = try jsonString(vector.values)
        try lock.withLock {
            try connection.execute(
                """
                INSERT INTO knowledge_frame_vectors (frame_id, provider_id, dimensions, vector_json, redacted_preview, updated_at)
                VALUES (
                  \(vector.frameID),
                  '\(KnowledgeSQL.escape(vector.providerID))',
                  \(vector.values.count),
                  '\(KnowledgeSQL.escape(valuesJSON))',
                  '\(KnowledgeSQL.escape(vector.redactedPreview))',
                  CURRENT_TIMESTAMP
                )
                ON CONFLICT(frame_id) DO UPDATE SET
                  provider_id = excluded.provider_id,
                  dimensions = excluded.dimensions,
                  vector_json = excluded.vector_json,
                  redacted_preview = excluded.redacted_preview,
                  updated_at = CURRENT_TIMESTAMP;
                """
            )
        }
    }

    public func delete(frameID: Int64) throws {
        try lock.withLock {
            try connection.execute("DELETE FROM knowledge_frame_vectors WHERE frame_id = \(frameID);")
        }
    }

    public func vector(frameID: Int64) throws -> KnowledgeEmbeddingVector? {
        try lock.withLock {
            guard let row = try connection.queryRows("SELECT * FROM knowledge_frame_vectors WHERE frame_id = \(frameID) LIMIT 1;").first else {
                return nil
            }
            return try vector(row: row)
        }
    }

    public func search(queryVector: [Double], topK: Int, threshold: Double) throws -> [KnowledgeVectorSearchResult] {
        try validate(queryVector)
        return try lock.withLock {
            try connection.queryRows("SELECT * FROM knowledge_frame_vectors;")
                .map { try vector(row: $0) }
                .map {
                    KnowledgeVectorSearchResult(
                        frameID: $0.frameID,
                        score: cosineSimilarity(queryVector, $0.values),
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
    }

    private func validate(_ values: [Double]) throws {
        guard values.count == expectedDimensions else {
            throw KnowledgeVectorIndexError.dimensionMismatch(expected: expectedDimensions, actual: values.count)
        }
    }

    private func vector(row: [String: String]) throws -> KnowledgeEmbeddingVector {
        let values = try values(from: row["vector_json"] ?? "[]")
        try validate(values)
        return KnowledgeEmbeddingVector(
            frameID: Int64(row["frame_id"] ?? "") ?? 0,
            values: values,
            providerID: row["provider_id"] ?? "",
            redactedPreview: row["redacted_preview"] ?? ""
        )
    }
}

public enum SQLiteVecCapability: Equatable, Sendable {
    case available
    case unavailableFallback
}

public struct SQLiteVecCapabilityProbe: Sendable {
    public init() {}

    public func capability(connection: SQLiteConnection) -> SQLiteVecCapability {
        (try? connection.tableExists("vec0")) == true ? .available : .unavailableFallback
    }
}

public struct KnowledgeVectorSynchronizer: Sendable {
    private let frameStore: SQLiteKnowledgeFrameStore
    private let vectorIndex: any KnowledgeVectorIndex
    private let embeddingProvider: any EmbeddingProvider

    public init(
        frameStore: SQLiteKnowledgeFrameStore,
        vectorIndex: any KnowledgeVectorIndex,
        embeddingProvider: any EmbeddingProvider
    ) {
        self.frameStore = frameStore
        self.vectorIndex = vectorIndex
        self.embeddingProvider = embeddingProvider
    }

    public func syncFrame(id: Int64, userApproved: Bool) throws {
        let frame = try frameStore.get(id: id)
        let vector = try embeddingProvider.embed(EmbeddingRequest(
            frameID: id,
            text: "\(frame.name)\n\(frame.body)\n\(frame.triggers.joined(separator: " "))",
            userApproved: userApproved
        ))
        try vectorIndex.upsert(vector)
    }

    public func deleteFrame(id: Int64) throws {
        try vectorIndex.delete(frameID: id)
    }
}

public protocol KnowledgeTextSearch: Sendable {
    func search(query: String) throws -> [KnowledgeFrameRecord]
}

extension SQLiteKnowledgeFrameStore: KnowledgeTextSearch {}

public struct StaticKnowledgeTextSearch: KnowledgeTextSearch {
    private let resultsByQuery: [String: [KnowledgeFrameRecord]]

    public init(resultsByQuery: [String: [KnowledgeFrameRecord]]) {
        self.resultsByQuery = resultsByQuery
    }

    public func search(query: String) throws -> [KnowledgeFrameRecord] {
        resultsByQuery[query] ?? []
    }
}

public enum RetrievalMode: String, CaseIterable, Equatable, Sendable {
    case ftsOnly
    case vectorOnly
    case hybrid
}

public struct HybridRetrievalConfiguration: Equatable, Sendable {
    public var topK: Int
    public var threshold: Double
    public var ftsWeight: Double
    public var vectorWeight: Double

    public init(topK: Int, threshold: Double, ftsWeight: Double = 1.0, vectorWeight: Double = 1.0) {
        self.topK = topK
        self.threshold = threshold
        self.ftsWeight = ftsWeight
        self.vectorWeight = vectorWeight
    }
}

public struct HybridRetrievalResult: Equatable, Sendable {
    public var frame: KnowledgeFrameRecord
    public var score: Double
    public var explanation: String
}

public struct HybridKnowledgeRetriever: Sendable {
    private let textSearch: any KnowledgeTextSearch
    private let vectorIndex: any KnowledgeVectorIndex
    private let embeddingProvider: any EmbeddingProvider
    private let framesByID: [Int64: KnowledgeFrameRecord]
    private let configuration: HybridRetrievalConfiguration

    public init(
        textSearch: any KnowledgeTextSearch,
        vectorIndex: any KnowledgeVectorIndex,
        embeddingProvider: any EmbeddingProvider,
        framesByID: [Int64: KnowledgeFrameRecord],
        configuration: HybridRetrievalConfiguration
    ) {
        self.textSearch = textSearch
        self.vectorIndex = vectorIndex
        self.embeddingProvider = embeddingProvider
        self.framesByID = framesByID
        self.configuration = configuration
    }

    public func search(query: String, mode: RetrievalMode, userApprovedForEmbedding: Bool) throws -> [HybridRetrievalResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        var ranked: [Int64: (frame: KnowledgeFrameRecord, score: Double, explanations: [String])] = [:]

        if mode == .ftsOnly || mode == .hybrid {
            for frame in try textSearch.search(query: trimmed) {
                let existing = ranked[frame.id]
                ranked[frame.id] = (
                    frame: frame,
                    score: (existing?.score ?? 0) + configuration.ftsWeight,
                    explanations: (existing?.explanations ?? []) + ["fts"]
                )
            }
        }

        if mode == .vectorOnly || mode == .hybrid {
            let queryVector = try embeddingProvider.embed(EmbeddingRequest(frameID: 0, text: trimmed, userApproved: userApprovedForEmbedding))
            if queryVector.values.count == vectorIndex.expectedDimensions {
                let vectorResults = try vectorIndex.search(
                    queryVector: queryVector.values,
                    topK: configuration.topK,
                    threshold: configuration.threshold
                )
                for result in vectorResults {
                    guard let frame = framesByID[result.frameID] else {
                        continue
                    }
                    let existing = ranked[result.frameID]
                    ranked[result.frameID] = (
                        frame: frame,
                        score: (existing?.score ?? 0) + result.score * configuration.vectorWeight,
                        explanations: (existing?.explanations ?? []) + ["vector"]
                    )
                }
            }
        }

        return ranked.values
            .filter { $0.score >= configuration.threshold }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.frame.id < rhs.frame.id
                }
                return lhs.score > rhs.score
            }
            .prefix(configuration.topK)
            .map {
                HybridRetrievalResult(
                    frame: $0.frame,
                    score: $0.score,
                    explanation: $0.explanations.joined(separator: "+")
                )
            }
    }
}

public struct ProjectMemoryCandidate: Equatable, Sendable {
    public var name: String
    public var body: String
    public var triggers: [String]
}

public struct ProjectMemoryCandidateExtractor: Sendable {
    public init() {}

    public func extractCandidates(
        completedProject: ProjectRecord,
        tasks: [TaskRecord],
        artifactTemplates: [String]
    ) -> [ProjectMemoryCandidate] {
        guard completedProject.status == "completed" else {
            return []
        }

        let completedTasks = tasks
            .filter { $0.status == "completed" }
            .map(\.title)
            .joined(separator: ", ")
        let body = """
        Project: \(completedProject.title)
        Priority: \(completedProject.priority ?? "none")
        Tags: \(completedProject.tags.joined(separator: ", "))
        Completed tasks: \(completedTasks)
        Artifact templates: \(artifactTemplates.joined(separator: ", "))
        Source command: \(completedProject.sourceCommand ?? "none")
        """
        return [
            ProjectMemoryCandidate(
                name: "Project memory: \(completedProject.title)",
                body: redactedPreview(body),
                triggers: completedProject.tags + artifactTemplates
            )
        ]
    }
}

public struct ProjectMemoryApproval: Equatable, Sendable {
    public var candidate: ProjectMemoryCandidate
    public var isApproved: Bool

    public init(candidate: ProjectMemoryCandidate, isApproved: Bool) {
        self.candidate = candidate
        self.isApproved = isApproved
    }
}

public struct ProjectMemoryService: Sendable {
    private let frameStore: SQLiteKnowledgeFrameStore

    public init(frameStore: SQLiteKnowledgeFrameStore) {
        self.frameStore = frameStore
    }

    public func save(candidates: [ProjectMemoryApproval]) throws {
        for approval in candidates where approval.isApproved {
            _ = try frameStore.create(
                name: approval.candidate.name,
                body: approval.candidate.body,
                triggers: approval.candidate.triggers
            )
        }
    }
}

public struct WeKnoraPreview: Equatable, Sendable {
    public var redactedContext: String
    public var query: String

    public init(redactedContext: String, query: String) {
        self.redactedContext = redactedContext
        self.query = query
    }
}

public struct WeKnoraResponse: Equatable, Sendable {
    public var summary: String
}

public enum WeKnoraConnectorError: Error, Equatable, Sendable {
    case disabled
    case approvalRequired
    case networkFailure(String)
    case permissionDenied
}

public protocol WeKnoraClient: Sendable {
    func send(_ preview: WeKnoraPreview) throws -> WeKnoraResponse
}

public struct WeKnoraConnector: Sendable {
    private let isEnabled: Bool
    private let client: any WeKnoraClient

    public init(isEnabled: Bool, client: any WeKnoraClient) {
        self.isEnabled = isEnabled
        self.client = client
    }

    public func preview(context: String, query: String) throws -> WeKnoraPreview {
        guard isEnabled else {
            throw WeKnoraConnectorError.disabled
        }
        return WeKnoraPreview(redactedContext: redactedPreview(context), query: query)
    }

    public func send(_ preview: WeKnoraPreview, context: ToolExecutionContext) throws -> WeKnoraResponse {
        guard context.approvalToken != nil else {
            throw WeKnoraConnectorError.approvalRequired
        }
        return try client.send(preview)
    }
}

public final class InMemoryWeKnoraClient: WeKnoraClient, @unchecked Sendable {
    public var nextError: WeKnoraConnectorError?

    public init(nextError: WeKnoraConnectorError? = nil) {
        self.nextError = nextError
    }

    public func send(_ preview: WeKnoraPreview) throws -> WeKnoraResponse {
        if let nextError {
            self.nextError = nil
            throw nextError
        }
        return WeKnoraResponse(summary: "ok")
    }
}

public struct RetrievalEvaluationCase: Equatable, Sendable {
    public var query: String
    public var expectedFrameID: Int64
    public var allowedAlternativeFrameIDs: [Int64]

    public init(query: String, expectedFrameID: Int64, allowedAlternativeFrameIDs: [Int64]) {
        self.query = query
        self.expectedFrameID = expectedFrameID
        self.allowedAlternativeFrameIDs = allowedAlternativeFrameIDs
    }
}

public struct RetrievalEvaluationDataset: Equatable, Sendable {
    public var cases: [RetrievalEvaluationCase]

    public init(cases: [RetrievalEvaluationCase]) {
        self.cases = cases
    }
}

public struct RetrievalEvaluationResult: Equatable, Sendable {
    public var query: String
    public var mode: RetrievalMode
    public var topFrameID: Int64?
    public var isMatch: Bool
    public var latencyMilliseconds: Double
}

public struct RetrievalEvaluationReport: Equatable, Sendable {
    public var results: [RetrievalEvaluationResult]
}

public struct RetrievalEvaluationHarness: Sendable {
    private let retriever: HybridKnowledgeRetriever

    public init(retriever: HybridKnowledgeRetriever) {
        self.retriever = retriever
    }

    public func run(dataset: RetrievalEvaluationDataset) throws -> RetrievalEvaluationReport {
        var results: [RetrievalEvaluationResult] = []

        for testCase in dataset.cases {
            for mode in RetrievalMode.allCases {
                let start = Date()
                let matches = try retriever.search(query: testCase.query, mode: mode, userApprovedForEmbedding: true)
                let latency = Date().timeIntervalSince(start) * 1_000
                let topFrameID = matches.first?.frame.id
                let expected = [testCase.expectedFrameID] + testCase.allowedAlternativeFrameIDs
                results.append(RetrievalEvaluationResult(
                    query: testCase.query,
                    mode: mode,
                    topFrameID: topFrameID,
                    isMatch: topFrameID.map { expected.contains($0) } ?? false,
                    latencyMilliseconds: max(0, latency)
                ))
            }
        }

        return RetrievalEvaluationReport(results: results)
    }
}

private func normalize(_ values: [Double]) -> [Double] {
    let magnitude = sqrt(values.reduce(0) { $0 + $1 * $1 })
    guard magnitude > 0 else {
        return values
    }
    return values.map { $0 / magnitude }
}

private func cosineSimilarity(_ lhs: [Double], _ rhs: [Double]) -> Double {
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

private func redactedPreview(_ text: String) -> String {
    SecretRedactor.redact(metadata: ["text": text])["text"] ?? "[REDACTED]"
}

private func jsonString(_ values: [Double]) throws -> String {
    let data = try JSONEncoder().encode(values)
    return String(data: data, encoding: .utf8) ?? "[]"
}

private func values(from json: String) throws -> [Double] {
    let data = Data(json.utf8)
    return try JSONDecoder().decode([Double].self, from: data)
}

private enum KnowledgeSQL {
    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
