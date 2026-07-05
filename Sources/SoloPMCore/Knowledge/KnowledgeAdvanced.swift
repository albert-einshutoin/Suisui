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

public struct RetrievalRequirementCase: Equatable, Sendable {
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
    public var requirementCases: [RetrievalRequirementCase]
    public var constraints: RetrievalConstraints

    public init(requirementCases: [RetrievalRequirementCase], constraints: RetrievalConstraints) {
        self.requirementCases = requirementCases
        self.constraints = constraints
    }

    public var semanticRequirementCases: [RetrievalRequirementCase] {
        requirementCases.filter(\.requiresSemanticRetrieval)
    }

    public var hasConcreteFTSGap: Bool {
        !semanticRequirementCases.isEmpty
    }

    public var sqliteVecJustification: String {
        "\(semanticRequirementCases.count) semantic retrieval requirement cases exceed FTS5 exact matching."
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

public struct KnowledgeVectorSearchResult: Equatable, Sendable {
    public var frameID: Int64
    public var score: Double
    public var providerID: String
}

public enum KnowledgeVectorIndexError: Error, Equatable, Sendable {
    case dimensionMismatch(expected: Int, actual: Int)
    case invalidProviderID
}

public protocol KnowledgeVectorIndex: Sendable {
    var expectedDimensions: Int { get }
    func upsert(_ vector: KnowledgeEmbeddingVector) throws
    func delete(frameID: Int64) throws
    func vector(frameID: Int64) throws -> KnowledgeEmbeddingVector?
    func search(queryVector: [Double], topK: Int, threshold: Double) throws -> [KnowledgeVectorSearchResult]
}

/// Candidate-scoped search is an opt-in refinement so existing OSS vector index
/// implementations keep the stable `KnowledgeVectorIndex` contract.
public protocol CandidateKnowledgeVectorIndex: KnowledgeVectorIndex {
    func search(
        queryVector: [Double],
        topK: Int,
        threshold: Double,
        candidateFrameIDs: Set<Int64>?
    ) throws -> [KnowledgeVectorSearchResult]
}

public extension CandidateKnowledgeVectorIndex {
    func search(queryVector: [Double], topK: Int, threshold: Double) throws -> [KnowledgeVectorSearchResult] {
        try search(queryVector: queryVector, topK: topK, threshold: threshold, candidateFrameIDs: nil)
    }
}

public final class SQLiteKnowledgeVectorIndex: CandidateKnowledgeVectorIndex, @unchecked Sendable {
    public let expectedDimensions: Int
    private let connection: SQLiteConnection
    private let lock = NSLock()
    private var sqliteVecState: SQLiteVecIndexState = .unknown

    public init(connection: SQLiteConnection, expectedDimensions: Int) {
        self.connection = connection
        self.expectedDimensions = expectedDimensions
    }

    public func upsert(_ vector: KnowledgeEmbeddingVector) throws {
        try validate(vector)
        let valuesJSON = try jsonString(vector.values)
        try lock.withLock {
            try connection.transaction {
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
                if try ensureSQLiteVecIndexLocked() {
                    try upsertSQLiteVecVectorLocked(vector)
                }
            }
        }
    }

    public func delete(frameID: Int64) throws {
        try lock.withLock {
            try connection.transaction {
                if try ensureSQLiteVecIndexLocked() {
                    try connection.execute("DELETE FROM \(sqliteVecTableName) WHERE frame_id = \(frameID);")
                    try connection.execute("DELETE FROM \(sqliteVecMetaTableName) WHERE frame_id = \(frameID);")
                }
                try connection.execute("DELETE FROM knowledge_frame_vectors WHERE frame_id = \(frameID);")
            }
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

    public func search(
        queryVector: [Double],
        topK: Int,
        threshold: Double,
        candidateFrameIDs: Set<Int64>?
    ) throws -> [KnowledgeVectorSearchResult] {
        try validate(queryVector)
        let maxResults = max(topK, 0)
        guard maxResults > 0 else {
            return []
        }
        if let candidateFrameIDs, candidateFrameIDs.isEmpty {
            return []
        }
        return try lock.withLock {
            if candidateFrameIDs == nil,
               shouldUseSQLiteVecSearch(queryVector: queryVector, threshold: threshold),
               try ensureSQLiteVecIndexLocked(),
               try isSQLiteVecIndexFreshLocked() {
                return try searchSQLiteVecLocked(queryVector: queryVector, maxResults: maxResults, threshold: threshold)
            }

            var results: [KnowledgeVectorSearchResult] = []
            let rows = try connection.queryRows(searchSQL(candidateFrameIDs: candidateFrameIDs))

            // SQL-side candidate filtering keeps direct candidate searches from
            // decoding unrelated vector_json rows after a caller narrows scope.
            for row in rows {
                let vector = try vector(row: row)
                let score = cosineSimilarity(queryVector, vector.values)
                guard score >= threshold else {
                    continue
                }

                insert(
                    KnowledgeVectorSearchResult(
                        frameID: vector.frameID,
                        score: score,
                        providerID: vector.providerID
                    ),
                    into: &results,
                    maxCount: maxResults
                )
            }
            return results
        }
    }

    private func searchSQL(candidateFrameIDs: Set<Int64>?) -> String {
        let filter = candidateFrameIDs.map { "WHERE frame_id IN (\($0.sorted().map(String.init).joined(separator: ", ")))" } ?? ""
        return """
        SELECT *
        FROM knowledge_frame_vectors
        \(filter)
        ORDER BY frame_id ASC;
        """
    }

    private enum SQLiteVecIndexState {
        case unknown
        case available
        case unavailableFallback
    }

    private var sqliteVecTableName: String {
        "knowledge_frame_vector_index_\(max(expectedDimensions, 0))"
    }

    private var sqliteVecMetaTableName: String {
        "knowledge_frame_vector_index_meta_\(max(expectedDimensions, 0))"
    }

    private func ensureSQLiteVecIndexLocked() throws -> Bool {
        guard expectedDimensions > 0 else {
            sqliteVecState = .unavailableFallback
            return false
        }
        switch sqliteVecState {
        case .available:
            return true
        case .unavailableFallback:
            return false
        case .unknown:
            do {
                try connection.execute(
                    """
                    CREATE VIRTUAL TABLE IF NOT EXISTS \(sqliteVecTableName) USING vec0(
                        frame_id integer primary key,
                        embedding float[\(expectedDimensions)]
                    );
                    """
                )
                try connection.execute(
                    """
                    CREATE TABLE IF NOT EXISTS \(sqliteVecMetaTableName) (
                        frame_id INTEGER PRIMARY KEY NOT NULL,
                        source_updated_at TEXT NOT NULL,
                        provider_id TEXT NOT NULL,
                        dimensions INTEGER NOT NULL,
                        is_indexed INTEGER NOT NULL CHECK(is_indexed IN (0, 1))
                    );
                    """
                )
                sqliteVecState = .available
                return true
            } catch {
                sqliteVecState = .unavailableFallback
                return false
            }
        }
    }

    private func upsertSQLiteVecVectorLocked(_ vector: KnowledgeEmbeddingVector) throws {
        let sourceRow = try connection.queryRows(
            """
            SELECT updated_at
            FROM knowledge_frame_vectors
            WHERE frame_id = \(vector.frameID)
            LIMIT 1;
            """
        ).first
        let sourceUpdatedAt = try KnowledgeSQL.requiredString(
            sourceRow?["updated_at"],
            column: "knowledge_frame_vectors.updated_at"
        )
        let isIndexed = vectorMagnitude(vector.values) > 0
        try connection.execute("DELETE FROM \(sqliteVecTableName) WHERE frame_id = \(vector.frameID);")
        if isIndexed {
            let normalizedValuesJSON = try jsonString(normalize(vector.values))
            try connection.execute(
                """
                INSERT INTO \(sqliteVecTableName) (frame_id, embedding)
                VALUES (\(vector.frameID), '\(KnowledgeSQL.escape(normalizedValuesJSON))');
                """
            )
        }
        try connection.execute(
            """
            INSERT INTO \(sqliteVecMetaTableName) (frame_id, source_updated_at, provider_id, dimensions, is_indexed)
            VALUES (
                \(vector.frameID),
                '\(KnowledgeSQL.escape(sourceUpdatedAt))',
                '\(KnowledgeSQL.escape(vector.providerID))',
                \(vector.values.count),
                \(isIndexed ? 1 : 0)
            )
            ON CONFLICT(frame_id) DO UPDATE SET
                source_updated_at = excluded.source_updated_at,
                provider_id = excluded.provider_id,
                dimensions = excluded.dimensions,
                is_indexed = excluded.is_indexed;
            """
        )
    }

    private func isSQLiteVecIndexFreshLocked() throws -> Bool {
        let baseCount = try KnowledgeSQL.requiredInt(
            connection.queryRows(
                """
                SELECT COUNT(*) AS count
                FROM knowledge_frame_vectors;
                """
            ).first?["count"],
            column: "knowledge_frame_vectors.count"
        )
        let freshMetaCount = try KnowledgeSQL.requiredInt(
            connection.queryRows(
                """
                SELECT COUNT(*) AS count
                FROM knowledge_frame_vectors AS base
                JOIN \(sqliteVecMetaTableName) AS meta ON meta.frame_id = base.frame_id
                WHERE meta.source_updated_at = base.updated_at
                  AND meta.provider_id = base.provider_id
                  AND meta.dimensions = base.dimensions;
                """
            ).first?["count"],
            column: "\(sqliteVecMetaTableName).count"
        )
        return baseCount == freshMetaCount
    }

    private func searchSQLiteVecLocked(queryVector: [Double], maxResults: Int, threshold: Double) throws -> [KnowledgeVectorSearchResult] {
        let normalizedQueryJSON = try jsonString(normalize(queryVector))
        let requestedK = sqliteVecK(maxResults: maxResults)
        let rows = try connection.queryRows(
            """
            SELECT
                base.frame_id AS frame_id,
                base.provider_id AS provider_id,
                base.dimensions AS dimensions,
                base.vector_json AS vector_json,
                base.redacted_preview AS redacted_preview,
                indexed.frame_id AS indexed_frame_id,
                indexed.distance AS vector_distance
            FROM \(sqliteVecTableName) AS indexed
            JOIN \(sqliteVecMetaTableName) AS meta ON meta.frame_id = indexed.frame_id
            JOIN knowledge_frame_vectors AS base ON base.frame_id = indexed.frame_id
            WHERE indexed.embedding MATCH '\(KnowledgeSQL.escape(normalizedQueryJSON))'
              AND k = \(requestedK)
              AND meta.is_indexed = 1
              AND meta.source_updated_at = base.updated_at
              AND meta.provider_id = base.provider_id
              AND meta.dimensions = base.dimensions
            ORDER BY indexed.distance ASC, indexed.frame_id ASC;
            """
        )

        var results: [KnowledgeVectorSearchResult] = []
        for row in rows {
            let baseVector = try vector(row: row)
            _ = try KnowledgeSQL.requiredDouble(
                row["vector_distance"],
                column: "\(sqliteVecTableName).distance"
            )
            // sqlite-vec is only the candidate generator; the persisted base row
            // remains the source of truth for score/threshold semantics.
            let score = cosineSimilarity(queryVector, baseVector.values)
            guard score >= threshold else {
                continue
            }
            insert(
                KnowledgeVectorSearchResult(
                    frameID: baseVector.frameID,
                    score: score,
                    providerID: baseVector.providerID
                ),
                into: &results,
                maxCount: maxResults
            )
        }
        return results
    }

    private func shouldUseSQLiteVecSearch(queryVector: [Double], threshold: Double) -> Bool {
        // Zero-vector and non-positive-threshold searches rely on fallback cosine
        // semantics, where zero similarity can still be a valid returned score.
        threshold > 0 && vectorMagnitude(queryVector) > 0
    }

    private func sqliteVecK(maxResults: Int) -> Int {
        // Over-fetch a bounded amount so Swift can keep the existing score/id
        // tie-break semantics after sqlite-vec does the expensive distance pass.
        max(maxResults, min(maxResults * 8, maxResults + 128))
    }

    private func shouldRankBefore(_ lhs: KnowledgeVectorSearchResult, _ rhs: KnowledgeVectorSearchResult) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }
        return lhs.frameID < rhs.frameID
    }

    private func insert(
        _ candidate: KnowledgeVectorSearchResult,
        into results: inout [KnowledgeVectorSearchResult],
        maxCount: Int
    ) {
        let insertIndex = results.firstIndex(where: { shouldRankBefore(candidate, $0) }) ?? results.count
        guard insertIndex < maxCount else {
            return
        }
        results.insert(candidate, at: insertIndex)
        if results.count > maxCount {
            results.removeLast()
        }
    }

    private func validate(_ values: [Double]) throws {
        guard values.count == expectedDimensions else {
            throw KnowledgeVectorIndexError.dimensionMismatch(expected: expectedDimensions, actual: values.count)
        }
    }

    private func validate(_ vector: KnowledgeEmbeddingVector) throws {
        try validate(vector.values)
        try KnowledgeVectorValidator.validateProviderID(vector.providerID)
    }

    private func vector(row: [String: String]) throws -> KnowledgeEmbeddingVector {
        let dimensions = try KnowledgeSQL.requiredInt(
            row["dimensions"],
            column: "knowledge_frame_vectors.dimensions"
        )
        let values = try values(
            from: try KnowledgeSQL.requiredString(row["vector_json"], column: "knowledge_frame_vectors.vector_json"),
            column: "knowledge_frame_vectors.vector_json"
        )
        guard dimensions == values.count else {
            throw LocalStoreDecodingError.inconsistentDimensions(
                column: "knowledge_frame_vectors.dimensions",
                expected: dimensions,
                actual: values.count
            )
        }
        try validate(values)
        return KnowledgeEmbeddingVector(
            frameID: try KnowledgeSQL.requiredInt64(row["frame_id"], column: "knowledge_frame_vectors.frame_id"),
            values: values,
            providerID: try KnowledgeSQL.requiredString(row["provider_id"], column: "knowledge_frame_vectors.provider_id"),
            redactedPreview: try KnowledgeSQL.presentString(row["redacted_preview"], column: "knowledge_frame_vectors.redacted_preview")
        )
    }
}

enum KnowledgeVectorValidator {
    static func validateProviderID(_ providerID: String) throws {
        guard !providerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw KnowledgeVectorIndexError.invalidProviderID
        }
    }
}

public enum SQLiteVecCapability: Equatable, Sendable {
    case available
    case unavailableFallback
}

public struct SQLiteVecCapabilityProbe: Sendable {
    public init() {}

    public func capability(connection: SQLiteConnection) -> SQLiteVecCapability {
        do {
            try connection.execute(
                """
                CREATE VIRTUAL TABLE temp.solopm_vec_probe USING vec0(embedding float[2]);
                DROP TABLE temp.solopm_vec_probe;
                """
            )
            return .available
        } catch {
            return .unavailableFallback
        }
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

    public init(
        query: String,
        mode: RetrievalMode,
        topFrameID: Int64?,
        isMatch: Bool,
        latencyMilliseconds: Double
    ) {
        self.query = query
        self.mode = mode
        self.topFrameID = topFrameID
        self.isMatch = isMatch
        self.latencyMilliseconds = latencyMilliseconds
    }
}

public struct RetrievalEvaluationReport: Equatable, Sendable {
    public var results: [RetrievalEvaluationResult]

    public init(results: [RetrievalEvaluationResult]) {
        self.results = results
    }
}

public struct RetrievalEvaluationLatencyViolation: Equatable, Sendable {
    public var query: String
    public var mode: RetrievalMode
    public var latencyMilliseconds: Double
    public var maxLatencyMilliseconds: Double

    public init(
        query: String,
        mode: RetrievalMode,
        latencyMilliseconds: Double,
        maxLatencyMilliseconds: Double
    ) {
        self.query = query
        self.mode = mode
        self.latencyMilliseconds = latencyMilliseconds
        self.maxLatencyMilliseconds = maxLatencyMilliseconds
    }
}

public extension RetrievalEvaluationReport {
    func latencyViolations(maxLatencyMilliseconds: Double) -> [RetrievalEvaluationLatencyViolation] {
        results.compactMap { result in
            guard result.latencyMilliseconds > maxLatencyMilliseconds else {
                return nil
            }
            return RetrievalEvaluationLatencyViolation(
                query: result.query,
                mode: result.mode,
                latencyMilliseconds: result.latencyMilliseconds,
                maxLatencyMilliseconds: maxLatencyMilliseconds
            )
        }
    }
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
    let magnitude = vectorMagnitude(values)
    guard magnitude > 0 else {
        return values
    }
    return values.map { $0 / magnitude }
}

private func vectorMagnitude(_ values: [Double]) -> Double {
    sqrt(values.reduce(0) { $0 + $1 * $1 })
}

private func cosineSimilarity(_ lhs: [Double], _ rhs: [Double]) -> Double {
    guard lhs.count == rhs.count, !lhs.isEmpty else {
        return 0
    }
    let dot = zip(lhs, rhs).reduce(0) { $0 + $1.0 * $1.1 }
    let lhsMagnitude = vectorMagnitude(lhs)
    let rhsMagnitude = vectorMagnitude(rhs)
    guard lhsMagnitude > 0, rhsMagnitude > 0 else {
        return 0
    }
    return dot / (lhsMagnitude * rhsMagnitude)
}

private func redactedPreview(_ text: String) -> String {
    DeveloperSecretRedactor().redact(text).text
}

private func jsonString(_ values: [Double]) throws -> String {
    let data = try JSONEncoder().encode(values)
    guard let json = String(data: data, encoding: .utf8) else {
        throw DatabaseError.executeFailed("Could not encode knowledge_frame_vectors.vector_json as UTF-8 JSON.")
    }
    return json
}

private func values(from json: String, column: String) throws -> [Double] {
    let data = Data(json.utf8)
    do {
        return try JSONDecoder().decode([Double].self, from: data)
    } catch {
        throw LocalStoreDecodingError.invalidDoubleArray(column: column)
    }
}

private enum KnowledgeSQL {
    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    static func requiredString(_ value: String?, column: String) throws -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LocalStoreDecodingError.missingRequiredColumn(column: column)
        }
        return value
    }

    static func presentString(_ value: String?, column: String) throws -> String {
        guard let value else {
            throw LocalStoreDecodingError.missingRequiredColumn(column: column)
        }
        return value
    }

    static func requiredInt64(_ value: String?, column: String) throws -> Int64 {
        let rawValue = try requiredString(value, column: column)
        guard let intValue = Int64(rawValue) else {
            throw LocalStoreDecodingError.invalidInt64(column: column, value: rawValue)
        }
        return intValue
    }

    static func requiredInt(_ value: String?, column: String) throws -> Int {
        let rawValue = try requiredString(value, column: column)
        guard let intValue = Int(rawValue) else {
            throw LocalStoreDecodingError.invalidInt64(column: column, value: rawValue)
        }
        return intValue
    }

    static func requiredDouble(_ value: String?, column: String) throws -> Double {
        let rawValue = try requiredString(value, column: column)
        guard let doubleValue = Double(rawValue) else {
            throw DatabaseError.invalidColumnValue(column: column, value: rawValue)
        }
        return doubleValue
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
