import XCTest
@testable import SuisuiCore

final class KnowledgeAdvancedTests: XCTestCase {
    func testRetrievalRequirementsReviewDefinesFTSGapsAndConstraints() {
        let review = RetrievalRequirementsReview(
            requirementCases: [
                RetrievalRequirementCase(
                    id: "semantic-1",
                    query: "請求の催促",
                    expectedFrameIDs: [42],
                    allowedAlternativeFrameIDs: [43],
                    requiresSemanticRetrieval: true
                ),
                RetrievalRequirementCase(
                    id: "exact-1",
                    query: "QZT",
                    expectedFrameIDs: [1],
                    requiresSemanticRetrieval: false
                )
            ],
            constraints: RetrievalConstraints(
                maxLatencyMilliseconds: 150,
                maxStorageMegabytes: 64,
                privacyBoundary: .localOnly,
                maxEmbeddingDimensions: 384
            )
        )

        XCTAssertTrue(review.hasConcreteFTSGap)
        XCTAssertEqual(review.semanticRequirementCases.map(\.id), ["semantic-1"])
        XCTAssertEqual(review.sqliteVecJustification, "1 semantic retrieval requirement cases exceed FTS5 exact matching.")
        XCTAssertEqual(review.constraints.privacyBoundary, .localOnly)
    }

    func testEmbeddingProvidersRejectUnavailableDimensionMismatchAndRedactPreview() throws {
        let disabled = DisabledEmbeddingProvider()
        XCTAssertThrowsError(
            try disabled.embed(EmbeddingRequest(frameID: 1, text: "secret", userApproved: true))
        ) { error in
            XCTAssertEqual(error as? EmbeddingError, .providerUnavailable("disabled"))
        }

        let local = LocalHashEmbeddingProvider(dimensions: 4)
        let vector = try local.embed(EmbeddingRequest(frameID: 1, text: "api_key=sk-secret value", userApproved: true))

        XCTAssertEqual(vector.providerID, "local_hash")
        XCTAssertEqual(vector.values.count, 4)
        XCTAssertFalse(vector.redactedPreview.contains("sk-secret"))

        let index = InMemoryKnowledgeVectorIndex(expectedDimensions: 4)
        try index.upsert(vector)
        XCTAssertThrowsError(
            try index.upsert(KnowledgeEmbeddingVector(frameID: 2, values: [0.1, 0.2], providerID: "bad", redactedPreview: "bad"))
        ) { error in
            XCTAssertEqual(error as? KnowledgeVectorIndexError, .dimensionMismatch(expected: 4, actual: 2))
        }
    }

    func testSQLiteVectorStorageMigrationAndFrameIndexSyncCreateUpdateDelete() throws {
        let connection = try migratedPhase9Connection()
        XCTAssertTrue(try connection.tableExists("knowledge_frame_vectors"))
        XCTAssertTrue(try connection.tableExists("knowledge_retrieval_eval_runs"))

        let frameStore = SQLiteKnowledgeFrameStore(connection: connection)
        let vectorIndex = SQLiteKnowledgeVectorIndex(connection: connection, expectedDimensions: 4)
        let synchronizer = KnowledgeVectorSynchronizer(
            frameStore: frameStore,
            vectorIndex: vectorIndex,
            embeddingProvider: LocalHashEmbeddingProvider(dimensions: 4)
        )

        let created = try frameStore.create(name: "Billing", body: "Invoice follow-up", triggers: [])
        try synchronizer.syncFrame(id: created.id, userApproved: true)
        let firstVector = try XCTUnwrap(vectorIndex.vector(frameID: created.id))

        _ = try frameStore.update(id: created.id, body: "Invoice follow-up and payment reminder")
        try synchronizer.syncFrame(id: created.id, userApproved: true)
        let updatedVector = try XCTUnwrap(vectorIndex.vector(frameID: created.id))

        XCTAssertEqual(updatedVector.values.count, 4)
        XCTAssertNotEqual(firstVector.redactedPreview, updatedVector.redactedPreview)

        try frameStore.delete(id: created.id)
        try synchronizer.deleteFrame(id: created.id)

        XCTAssertNil(try vectorIndex.vector(frameID: created.id))
    }

    func testSQLiteVectorIndexRejectsCorruptedVectorJSONInsteadOfUsingEmptyVector() throws {
        let connection = try migratedPhase9Connection()
        let frameStore = SQLiteKnowledgeFrameStore(connection: connection)
        let vectorIndex = SQLiteKnowledgeVectorIndex(connection: connection, expectedDimensions: 4)
        let frame = try frameStore.create(name: "Billing", body: "Invoice follow-up", triggers: [])
        try vectorIndex.upsert(KnowledgeEmbeddingVector(frameID: frame.id, values: [1, 0, 0, 0], providerID: "local", redactedPreview: "Billing"))

        try connection.execute("UPDATE knowledge_frame_vectors SET vector_json = 'not-json' WHERE frame_id = \(frame.id);")

        XCTAssertThrowsError(try vectorIndex.vector(frameID: frame.id)) { error in
            XCTAssertEqual(error as? LocalStoreDecodingError, .invalidDoubleArray(column: "knowledge_frame_vectors.vector_json"))
        }
    }

    func testSQLiteVectorIndexRejectsBlankProviderIDInsteadOfReturningAnonymousVector() throws {
        let connection = try migratedPhase9Connection()
        let frameStore = SQLiteKnowledgeFrameStore(connection: connection)
        let vectorIndex = SQLiteKnowledgeVectorIndex(connection: connection, expectedDimensions: 4)
        let frame = try frameStore.create(name: "Billing", body: "Invoice follow-up", triggers: [])
        try vectorIndex.upsert(KnowledgeEmbeddingVector(frameID: frame.id, values: [1, 0, 0, 0], providerID: "local", redactedPreview: "Billing"))

        try connection.execute("UPDATE knowledge_frame_vectors SET provider_id = '' WHERE frame_id = \(frame.id);")

        XCTAssertThrowsError(try vectorIndex.search(queryVector: [1, 0, 0, 0], topK: 1, threshold: 0.10)) { error in
            XCTAssertEqual(error as? LocalStoreDecodingError, .missingRequiredColumn(column: "knowledge_frame_vectors.provider_id"))
        }
    }

    func testSQLiteVectorIndexSearchWithTopKBoundedRankingAndTiebreak() throws {
        let connection = try migratedPhase9Connection()
        let frameStore = SQLiteKnowledgeFrameStore(connection: connection)
        let vectorIndex = SQLiteKnowledgeVectorIndex(connection: connection, expectedDimensions: 3)

        let first = try frameStore.create(name: "First", body: "one", triggers: [])
        let second = try frameStore.create(name: "Second", body: "two", triggers: [])
        let third = try frameStore.create(name: "Third", body: "three", triggers: [])
        let fourth = try frameStore.create(name: "Fourth", body: "four", triggers: [])

        try vectorIndex.upsert(KnowledgeEmbeddingVector(frameID: first.id, values: [1, 0, 0], providerID: "local", redactedPreview: "one"))
        try vectorIndex.upsert(KnowledgeEmbeddingVector(frameID: second.id, values: [1, 0, 0], providerID: "local", redactedPreview: "two"))
        try vectorIndex.upsert(KnowledgeEmbeddingVector(frameID: third.id, values: [1, 1, 0], providerID: "local", redactedPreview: "three"))
        try vectorIndex.upsert(KnowledgeEmbeddingVector(frameID: fourth.id, values: [0, 1, 0], providerID: "local", redactedPreview: "four"))

        let topOne = try vectorIndex.search(queryVector: [1, 0, 0], topK: 1, threshold: 0.10)
        XCTAssertEqual(topOne.map(\.frameID), [first.id])

        let topTwo = try vectorIndex.search(queryVector: [1, 0, 0], topK: 2, threshold: 0.10)
        XCTAssertEqual(topTwo.map(\.frameID), [first.id, second.id])
        XCTAssertEqual(topTwo.map(\.score), [1.0, 1.0])

        let topThree = try vectorIndex.search(queryVector: [1, 0, 0], topK: 3, threshold: 0.10)
        XCTAssertEqual(topThree.map(\.frameID), [first.id, second.id, third.id])
        XCTAssertEqual(topThree.count, 3)
        XCTAssertEqual(topThree[2].score, 0.7071067811865475, accuracy: 1e-12)
    }

    func testSQLiteVectorIndexLargeCorpusKeepsTopKAndTiebreakStable() throws {
        let connection = try migratedPhase9Connection()
        let frameStore = SQLiteKnowledgeFrameStore(connection: connection)
        let vectorIndex = SQLiteKnowledgeVectorIndex(connection: connection, expectedDimensions: 3)
        var exactMatchIDs: [Int64] = []

        for index in 0..<1_000 {
            let frame = try frameStore.create(name: "Frame \(index)", body: "knowledge \(index)", triggers: [])
            let values: [Double]
            if index < 3 {
                exactMatchIDs.append(frame.id)
                values = [1, 0, 0]
            } else if index.isMultiple(of: 2) {
                values = [0, 1, 0]
            } else {
                values = [0, 0, 1]
            }
            try vectorIndex.upsert(KnowledgeEmbeddingVector(
                frameID: frame.id,
                values: values,
                providerID: "local",
                redactedPreview: "large-corpus"
            ))
        }

        let results = try vectorIndex.search(queryVector: [1, 0, 0], topK: 3, threshold: 0.10)

        XCTAssertEqual(results.map(\.frameID), exactMatchIDs)
        XCTAssertEqual(results.map(\.score), [1.0, 1.0, 1.0])
    }

    func testSQLiteVecFastPathWhenRuntimeExtensionAvailable() throws {
        let connection = try migratedPhase9Connection()
        guard SQLiteVecCapabilityProbe().capability(connection: connection) == .available else {
            throw XCTSkip("sqlite-vec extension is not available in this SQLite runtime.")
        }

        let frameStore = SQLiteKnowledgeFrameStore(connection: connection)
        let vectorIndex = SQLiteKnowledgeVectorIndex(connection: connection, expectedDimensions: 3)
        let first = try frameStore.create(name: "First", body: "one", triggers: [])
        let second = try frameStore.create(name: "Second", body: "two", triggers: [])
        let third = try frameStore.create(name: "Third", body: "three", triggers: [])
        try vectorIndex.upsert(KnowledgeEmbeddingVector(frameID: first.id, values: [1, 0, 0], providerID: "local", redactedPreview: "first"))
        try vectorIndex.upsert(KnowledgeEmbeddingVector(frameID: second.id, values: [1, 0, 0], providerID: "local", redactedPreview: "second"))
        try vectorIndex.upsert(KnowledgeEmbeddingVector(frameID: third.id, values: [0, 1, 0], providerID: "local", redactedPreview: "third"))

        let results = try vectorIndex.search(queryVector: [1, 0, 0], topK: 2, threshold: 0.10)

        XCTAssertEqual(results.map(\.frameID), [first.id, second.id])
        XCTAssertEqual(results[0].score, 1.0, accuracy: 1e-12)
        XCTAssertEqual(results[1].score, 1.0, accuracy: 1e-12)

        try connection.execute("UPDATE knowledge_frame_vectors SET vector_json = 'not-json' WHERE frame_id = \(first.id);")
        XCTAssertThrowsError(try vectorIndex.search(queryVector: [1, 0, 0], topK: 1, threshold: 0.10)) { error in
            XCTAssertEqual(error as? LocalStoreDecodingError, .invalidDoubleArray(column: "knowledge_frame_vectors.vector_json"))
        }
    }

    func testSQLiteVectorIndexCandidateSearchSkipsUnrelatedCorruptedVectors() throws {
        let connection = try migratedPhase9Connection()
        let frameStore = SQLiteKnowledgeFrameStore(connection: connection)
        let vectorIndex = SQLiteKnowledgeVectorIndex(connection: connection, expectedDimensions: 3)
        let candidate = try frameStore.create(name: "Candidate", body: "invoice", triggers: [])

        try vectorIndex.upsert(KnowledgeEmbeddingVector(frameID: candidate.id, values: [1, 0, 0], providerID: "local", redactedPreview: "candidate"))
        var unrelatedIDs: [Int64] = []
        for index in 0..<1_000 {
            let frame = try frameStore.create(name: "Unrelated \(index)", body: "secret \(index)", triggers: [])
            unrelatedIDs.append(frame.id)
            let values: [Double] = index.isMultiple(of: 2) ? [0, 1, 0] : [0, 0, 1]
            try vectorIndex.upsert(KnowledgeEmbeddingVector(
                frameID: frame.id,
                values: values,
                providerID: "local",
                redactedPreview: "unrelated"
            ))
        }
        let corruptedID = try XCTUnwrap(unrelatedIDs.last)
        try connection.execute("UPDATE knowledge_frame_vectors SET vector_json = 'not-json' WHERE frame_id = \(corruptedID);")

        let results = try vectorIndex.search(
            queryVector: [1, 0, 0],
            topK: 2,
            threshold: 0.10,
            candidateFrameIDs: [candidate.id]
        )

        XCTAssertEqual(results.map(\.frameID), [candidate.id])
        XCTAssertTrue(try vectorIndex.search(queryVector: [1, 0, 0], topK: 2, threshold: 0.10, candidateFrameIDs: []).isEmpty)
        XCTAssertThrowsError(try vectorIndex.search(queryVector: [1, 0, 0], topK: 2, threshold: 0.10)) { error in
            XCTAssertEqual(error as? LocalStoreDecodingError, .invalidDoubleArray(column: "knowledge_frame_vectors.vector_json"))
        }
    }

    func testSQLiteVectorIndexSearchReturnsEmptyForNonPositiveTopK() throws {
        let connection = try migratedPhase9Connection()
        let frameStore = SQLiteKnowledgeFrameStore(connection: connection)
        let vectorIndex = SQLiteKnowledgeVectorIndex(connection: connection, expectedDimensions: 3)
        let frame = try frameStore.create(name: "Billing", body: "Invoice follow-up", triggers: [])

        try vectorIndex.upsert(KnowledgeEmbeddingVector(frameID: frame.id, values: [1, 0, 0], providerID: "local", redactedPreview: "Billing"))

        XCTAssertTrue(try vectorIndex.search(queryVector: [1, 0, 0], topK: 0, threshold: 0.10).isEmpty)
        XCTAssertTrue(try vectorIndex.search(queryVector: [1, 0, 0], topK: -1, threshold: 0.10).isEmpty)
    }

    func testSQLiteVectorIndexRejectsBlankProviderIDBeforePersistingVector() throws {
        let connection = try migratedPhase9Connection()
        let frameStore = SQLiteKnowledgeFrameStore(connection: connection)
        let vectorIndex = SQLiteKnowledgeVectorIndex(connection: connection, expectedDimensions: 4)
        let frame = try frameStore.create(name: "Billing", body: "Invoice follow-up", triggers: [])

        XCTAssertThrowsError(
            try vectorIndex.upsert(KnowledgeEmbeddingVector(
                frameID: frame.id,
                values: [1, 0, 0, 0],
                providerID: "   ",
                redactedPreview: "Billing"
            ))
        ) { error in
            XCTAssertEqual(error as? KnowledgeVectorIndexError, .invalidProviderID)
        }

        XCTAssertNil(try vectorIndex.vector(frameID: frame.id))
    }

    func testSQLiteVectorIndexRejectsMissingFrameIDInsteadOfPersistingOrphanVector() throws {
        let connection = try migratedPhase9Connection()
        let vectorIndex = SQLiteKnowledgeVectorIndex(connection: connection, expectedDimensions: 4)

        XCTAssertThrowsError(
            try vectorIndex.upsert(KnowledgeEmbeddingVector(
                frameID: 404,
                values: [1, 0, 0, 0],
                providerID: "local",
                redactedPreview: "Missing frame"
            ))
        ) { error in
            // Parameterized statements surface constraint violations as
            // stepFailed while multi-statement scripts surface executeFailed;
            // both prove SQLite enforced the foreign key.
            switch error {
            case let DatabaseError.executeFailed(message),
                 let DatabaseError.stepFailed(message):
                XCTAssertTrue(message.localizedCaseInsensitiveContains("foreign key"))
            default:
                XCTFail("Expected SQLite foreign key enforcement, got \(error).")
            }
        }

        XCTAssertNil(try vectorIndex.vector(frameID: 404))
    }

    func testSQLiteVectorIndexRejectsStoredDimensionMismatchInsteadOfIgnoringColumn() throws {
        let connection = try migratedPhase9Connection()
        let frameStore = SQLiteKnowledgeFrameStore(connection: connection)
        let vectorIndex = SQLiteKnowledgeVectorIndex(connection: connection, expectedDimensions: 4)
        let frame = try frameStore.create(name: "Billing", body: "Invoice follow-up", triggers: [])
        try vectorIndex.upsert(KnowledgeEmbeddingVector(frameID: frame.id, values: [1, 0, 0, 0], providerID: "local", redactedPreview: "Billing"))

        try connection.execute("UPDATE knowledge_frame_vectors SET dimensions = 2 WHERE frame_id = \(frame.id);")

        XCTAssertThrowsError(try vectorIndex.vector(frameID: frame.id)) { error in
            XCTAssertEqual(
                error as? LocalStoreDecodingError,
                .inconsistentDimensions(column: "knowledge_frame_vectors.dimensions", expected: 2, actual: 4)
            )
        }
        XCTAssertThrowsError(try vectorIndex.search(queryVector: [1, 0, 0, 0], topK: 1, threshold: 0.10)) { error in
            XCTAssertEqual(
                error as? LocalStoreDecodingError,
                .inconsistentDimensions(column: "knowledge_frame_vectors.dimensions", expected: 2, actual: 4)
            )
        }
    }

    func testHybridRetrieverExplainsExactSemanticNoMatchAndLowConfidence() throws {
        let exact = KnowledgeFrameRecord(id: 1, name: "QZT", body: "QZT launch checklist", triggers: ["qzt"])
        let semantic = KnowledgeFrameRecord(id: 2, name: "Billing", body: "Invoice follow-up", triggers: ["invoice"])
        let fts = StaticKnowledgeTextSearch(resultsByQuery: ["QZT": [exact]])
        let vectorIndex = InMemoryKnowledgeVectorIndex(expectedDimensions: 2)
        try vectorIndex.upsert(KnowledgeEmbeddingVector(frameID: 2, values: [1, 0], providerID: "static", redactedPreview: "Billing"))
        let provider = StaticEmbeddingProvider(vectorsByText: [
            "QZT": [0, 1],
            "invoice payment": [1, 0],
            "unrelated": [0, 1]
        ])
        let retriever = HybridKnowledgeRetriever(
            textSearch: fts,
            vectorIndex: vectorIndex,
            embeddingProvider: provider,
            framesByID: [1: exact, 2: semantic],
            configuration: HybridRetrievalConfiguration(topK: 3, threshold: 0.60)
        )

        let exactResults = try retriever.search(query: "QZT", mode: .hybrid, userApprovedForEmbedding: true)
        XCTAssertEqual(exactResults.first?.frame.id, 1)
        XCTAssertTrue(exactResults.first?.explanation.contains("fts") ?? false)

        let semanticResults = try retriever.search(query: "invoice payment", mode: .hybrid, userApprovedForEmbedding: true)
        XCTAssertEqual(semanticResults.first?.frame.id, 2)
        XCTAssertTrue(semanticResults.first?.explanation.contains("vector") ?? false)

        XCTAssertTrue(try retriever.search(query: "", mode: .hybrid, userApprovedForEmbedding: true).isEmpty)
        XCTAssertTrue(try retriever.search(query: "unrelated", mode: .hybrid, userApprovedForEmbedding: true).isEmpty)
    }

    func testHybridRetrieverPreservesGlobalVectorRecallWhenTextAlsoMatches() throws {
        let exact = KnowledgeFrameRecord(id: 1, name: "QZT", body: "QZT launch checklist", triggers: ["qzt"])
        let unrelatedSemantic = KnowledgeFrameRecord(id: 2, name: "Billing", body: "Invoice follow-up", triggers: ["invoice"])
        let vectorIndex = InMemoryKnowledgeVectorIndex(expectedDimensions: 2)
        try vectorIndex.upsert(KnowledgeEmbeddingVector(frameID: 1, values: [0, 1], providerID: "static", redactedPreview: "QZT"))
        try vectorIndex.upsert(KnowledgeEmbeddingVector(frameID: 2, values: [1, 0], providerID: "static", redactedPreview: "Billing"))
        for id in Int64(3)...Int64(1_000) {
            try vectorIndex.upsert(KnowledgeEmbeddingVector(
                frameID: id,
                values: [1, 0],
                providerID: "static",
                redactedPreview: "Noise"
            ))
        }
        let retriever = HybridKnowledgeRetriever(
            textSearch: StaticKnowledgeTextSearch(resultsByQuery: ["QZT": [exact]]),
            vectorIndex: vectorIndex,
            embeddingProvider: StaticEmbeddingProvider(vectorsByText: ["QZT": [1, 0]]),
            framesByID: [1: exact, 2: unrelatedSemantic],
            configuration: HybridRetrievalConfiguration(topK: 3, threshold: 0.10)
        )

        let results = try retriever.search(query: "QZT", mode: .hybrid, userApprovedForEmbedding: true)

        XCTAssertEqual(results.map(\.frame.id), [1, 2])
        let recordedCandidates = vectorIndex.searchCandidateFrameIDs
        XCTAssertEqual(recordedCandidates.count, 1)
        XCTAssertNil(recordedCandidates[0])
        XCTAssertEqual(vectorIndex.searchFrameIDs.first?.count, 1_000)
        XCTAssertTrue(results.first?.explanation.contains("fts") ?? false)
        XCTAssertTrue(results[1].explanation.contains("vector"))
    }

    func testHybridRetrieverFallsBackToGlobalVectorSearchWhenFTSHasNoCandidates() throws {
        let semantic = KnowledgeFrameRecord(id: 2, name: "Billing", body: "Invoice follow-up", triggers: ["invoice"])
        let vectorIndex = InMemoryKnowledgeVectorIndex(expectedDimensions: 2)
        try vectorIndex.upsert(KnowledgeEmbeddingVector(frameID: 2, values: [1, 0], providerID: "static", redactedPreview: "Billing"))
        let retriever = HybridKnowledgeRetriever(
            textSearch: StaticKnowledgeTextSearch(resultsByQuery: [:]),
            vectorIndex: vectorIndex,
            embeddingProvider: StaticEmbeddingProvider(vectorsByText: ["invoice payment": [1, 0]]),
            framesByID: [2: semantic],
            configuration: HybridRetrievalConfiguration(topK: 3, threshold: 0.10)
        )

        let results = try retriever.search(query: "invoice payment", mode: .hybrid, userApprovedForEmbedding: true)

        XCTAssertEqual(results.map(\.frame.id), [2])
        let recordedCandidates = vectorIndex.searchCandidateFrameIDs
        XCTAssertEqual(recordedCandidates.count, 1)
        XCTAssertNil(recordedCandidates[0])
        XCTAssertTrue(results.first?.explanation.contains("vector") ?? false)
    }

    func testHybridRetrieverRejectsQueryEmbeddingDimensionMismatchInsteadOfReturningFTSOnly() throws {
        let exact = KnowledgeFrameRecord(id: 1, name: "QZT", body: "QZT launch checklist", triggers: ["qzt"])
        let fts = StaticKnowledgeTextSearch(resultsByQuery: ["QZT": [exact]])
        let vectorIndex = InMemoryKnowledgeVectorIndex(expectedDimensions: 2)
        let provider = StaticEmbeddingProvider(vectorsByText: [
            "QZT": [1]
        ])
        let retriever = HybridKnowledgeRetriever(
            textSearch: fts,
            vectorIndex: vectorIndex,
            embeddingProvider: provider,
            framesByID: [1: exact],
            configuration: HybridRetrievalConfiguration(topK: 3, threshold: 0.60)
        )

        XCTAssertThrowsError(try retriever.search(query: "QZT", mode: .hybrid, userApprovedForEmbedding: true)) { error in
            XCTAssertEqual(error as? KnowledgeVectorIndexError, .dimensionMismatch(expected: 2, actual: 1))
        }
    }

    func testProjectMemoryCandidatesRequireApprovalAndRedactSecretsBeforeSaving() throws {
        let connection = try migratedPhase9Connection()
        let store = SQLiteKnowledgeFrameStore(connection: connection)
        let extractor = ProjectMemoryCandidateExtractor()
        let service = ProjectMemoryService(frameStore: store)
        let candidates = extractor.extractCandidates(
            completedProject: ProjectRecord(
                id: 1,
                title: "Launch",
                status: "completed",
                priority: "high",
                deadline: nil,
                workspacePath: nil,
                tags: ["release"],
                sourceCommand: "sk-secret-token"
            ),
            tasks: [
                TaskRecord(id: 10, projectID: 1, title: "Write release notes", status: "completed", dueAt: nil, priority: nil, sourceCommand: nil)
            ],
            artifactTemplates: ["release/checklist.md"]
        )

        XCTAssertFalse(candidates.isEmpty)
        XCTAssertFalse(candidates.first?.body.contains("sk-secret-token") ?? true)

        try service.save(candidates: candidates.map { ProjectMemoryApproval(candidate: $0, isApproved: false) })
        XCTAssertEqual(try store.list().count, 0)

        try service.save(candidates: candidates.map { ProjectMemoryApproval(candidate: $0, isApproved: true) })

        let frames = try store.list()
        XCTAssertEqual(frames.count, candidates.count)
        XCTAssertTrue(frames.first?.body.contains("[REDACTED_SECRET]") ?? false)
    }

    func testWeKnoraConnectorIsOptionalPreviewedAndApprovalBound() throws {
        let disabled = WeKnoraConnector(isEnabled: false, client: InMemoryWeKnoraClient())
        XCTAssertThrowsError(
            try disabled.preview(context: "local frame", query: "status")
        ) { error in
            XCTAssertEqual(error as? WeKnoraConnectorError, .disabled)
        }

        let client = InMemoryWeKnoraClient()
        let connector = WeKnoraConnector(isEnabled: true, client: client)
        let preview = try connector.preview(context: "local frame", query: "status")

        XCTAssertEqual(preview.redactedContext, "local frame")
        XCTAssertThrowsError(
            try connector.send(preview, context: ToolExecutionContext(source: .developerTool))
        ) { error in
            XCTAssertEqual(error as? WeKnoraConnectorError, .approvalRequired)
        }

        client.nextError = .networkFailure("offline")
        XCTAssertThrowsError(
            try connector.send(preview, context: approvedContext())
        ) { error in
            XCTAssertEqual(error as? WeKnoraConnectorError, .networkFailure("offline"))
        }

        client.nextError = .permissionDenied
        XCTAssertThrowsError(
            try connector.send(preview, context: approvedContext())
        ) { error in
            XCTAssertEqual(error as? WeKnoraConnectorError, .permissionDenied)
        }
    }

    func testRetrievalEvaluationHarnessComparesModesAndRecordsLatency() throws {
        let expected = KnowledgeFrameRecord(id: 1, name: "Billing", body: "Invoice follow-up", triggers: [])
        let fts = StaticKnowledgeTextSearch(resultsByQuery: ["invoice": [expected]])
        let vectorIndex = InMemoryKnowledgeVectorIndex(expectedDimensions: 2)
        try vectorIndex.upsert(KnowledgeEmbeddingVector(frameID: 1, values: [1, 0], providerID: "static", redactedPreview: "Billing"))
        let retriever = HybridKnowledgeRetriever(
            textSearch: fts,
            vectorIndex: vectorIndex,
            embeddingProvider: StaticEmbeddingProvider(vectorsByText: ["invoice": [1, 0]]),
            framesByID: [1: expected],
            configuration: HybridRetrievalConfiguration(topK: 3, threshold: 0.10)
        )
        let harness = RetrievalEvaluationHarness(retriever: retriever)

        let report = try harness.run(dataset: RetrievalEvaluationDataset(cases: [
            RetrievalEvaluationCase(query: "invoice", expectedFrameID: 1, allowedAlternativeFrameIDs: [])
        ]))

        XCTAssertEqual(Set(report.results.map(\.mode)), Set(RetrievalMode.allCases))
        XCTAssertTrue(report.results.allSatisfy { $0.latencyMilliseconds >= 0 })
        XCTAssertTrue(report.results.first { $0.mode == .hybrid }?.isMatch ?? false)
        XCTAssertTrue(report.latencyViolations(maxLatencyMilliseconds: 1_000).isEmpty)
    }

    func testRetrievalEvaluationReportFlagsLatencyBudgetViolations() {
        let report = RetrievalEvaluationReport(results: [
            RetrievalEvaluationResult(
                query: "invoice",
                mode: .vectorOnly,
                topFrameID: 1,
                isMatch: true,
                latencyMilliseconds: 25
            ),
            RetrievalEvaluationResult(
                query: "qzt",
                mode: .hybrid,
                topFrameID: 2,
                isMatch: true,
                latencyMilliseconds: 125
            )
        ])

        let violations = report.latencyViolations(maxLatencyMilliseconds: 100)

        XCTAssertEqual(violations.count, 1)
        XCTAssertEqual(violations[0].query, "qzt")
        XCTAssertEqual(violations[0].mode, .hybrid)
        XCTAssertEqual(violations[0].latencyMilliseconds, 125)
        XCTAssertEqual(violations[0].maxLatencyMilliseconds, 100)
    }

    private func migratedPhase9Connection() throws -> SQLiteConnection {
        let connection = try SQLiteConnection(path: ":memory:")
        try TestMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.phase9)
        return connection
    }

    private func approvedContext() -> ToolExecutionContext {
        ToolExecutionContext(
            approvalToken: ApprovalToken(id: "approval", sessionID: "session"),
            source: .developerTool
        )
    }
}

private enum TestMigrationRunner {
    static func migrate(connection: SQLiteConnection, migrations: [DatabaseMigration]) throws {
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS schema_migrations (
                id TEXT PRIMARY KEY NOT NULL,
                applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );
            """
        )
        let alreadyApplied = Set(try connection.queryStrings("SELECT id FROM schema_migrations ORDER BY id;"))
        for migration in migrations where !alreadyApplied.contains(migration.id) {
            try migration.apply(connection)
            try connection.execute("INSERT INTO schema_migrations (id) VALUES ('\(migration.id)');")
        }
    }
}
