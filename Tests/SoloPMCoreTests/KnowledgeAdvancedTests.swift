import XCTest
@testable import SoloPMCore

final class KnowledgeAdvancedTests: XCTestCase {
    func testRetrievalRequirementsReviewDefinesFTSGapsAndConstraints() {
        let review = RetrievalRequirementsReview(
            fixtures: [
                RetrievalFixture(
                    id: "semantic-1",
                    query: "請求の催促",
                    expectedFrameIDs: [42],
                    allowedAlternativeFrameIDs: [43],
                    requiresSemanticRetrieval: true
                ),
                RetrievalFixture(
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
        XCTAssertEqual(review.semanticFixtures.map(\.id), ["semantic-1"])
        XCTAssertEqual(review.sqliteVecJustification, "1 semantic fixtures exceed FTS5 exact matching.")
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

        XCTAssertEqual(vector.values.count, 4)
        XCTAssertFalse(vector.redactedPreview.contains("sk-secret"))

        let byok = BYOKOpenAIEmbeddingProvider(
            secretStore: InMemorySecretStore(values: [.openAIAPIKey: "sk-test"]),
            fallback: local
        )
        XCTAssertEqual(try byok.embed(EmbeddingRequest(frameID: 2, text: "fallback", userApproved: true)).values.count, 4)

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

    func testHybridRetrieverExplainsExactSemanticNoMatchAndLowConfidence() throws {
        let exact = KnowledgeFrameRecord(id: 1, name: "QZT", body: "QZT launch checklist", triggers: ["qzt"])
        let semantic = KnowledgeFrameRecord(id: 2, name: "Billing", body: "Invoice follow-up", triggers: ["invoice"])
        let fts = StaticKnowledgeTextSearch(resultsByQuery: ["QZT": [exact]])
        let vectorIndex = InMemoryKnowledgeVectorIndex(expectedDimensions: 2)
        try vectorIndex.upsert(KnowledgeEmbeddingVector(frameID: 2, values: [1, 0], providerID: "static", redactedPreview: "Billing"))
        let provider = StaticEmbeddingProvider(vectorsByText: [
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
            try connector.send(preview, context: ToolExecutionContext(source: .test))
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
    }

    private func migratedPhase9Connection() throws -> SQLiteConnection {
        let connection = try SQLiteConnection(path: ":memory:")
        try TestMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.phase9)
        return connection
    }

    private func approvedContext() -> ToolExecutionContext {
        ToolExecutionContext(
            approvalToken: ApprovalToken(id: "approval", sessionID: "session"),
            source: .test
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
