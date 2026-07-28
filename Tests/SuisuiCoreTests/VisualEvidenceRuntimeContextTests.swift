import XCTest
@testable import SuisuiCore

final class VisualEvidenceRuntimeContextTests: XCTestCase {
    func testJapaneseVisualManifestUsesJaContextAndSeparateRoots() throws {
        let manifest = try visualManifest(named: "visual-baseline-manifest-ja.json")
        let context = try XCTUnwrap(manifest["baselineContext"] as? [String: Any])
        let screens = try XCTUnwrap(manifest["screens"] as? [[String: Any]])
        let projectBoard = try XCTUnwrap(screens.first { $0["id"] as? String == "project-board" })
        let requiredVisibleTextLines = try XCTUnwrap(projectBoard["requiredVisibleTextLines"] as? [String])

        XCTAssertEqual(context["locale"] as? String, "ja-JP")
        XCTAssertEqual(manifest["artifactRoot"] as? String, "docs/release/evidence/ui-screenshots-ja")
        XCTAssertEqual(manifest["baselineRoot"] as? String, "docs/quality/visual-baselines-ja")
        XCTAssertEqual(requiredVisibleTextLines, [
            "project board to task card to",
            "進行中 高",
            "7月10日"
        ])
        XCTAssertFalse(requiredVisibleTextLines.contains("In Progress High"))
        XCTAssertFalse(requiredVisibleTextLines.contains("Jul 10"))
    }

    func testApprovalFlowScreensExistInBothLocaleManifests() throws {
        let expectedApprovalScreens: [String: (target: String, themes: Set<String>)] = [
            "assistant-queue-waiting-review": ("assistant-queue-row-visual-waiting", ["light", "dark"]),
            "assistant-queue-approved": ("assistant-queue-row-visual-approved", ["light", "dark"]),
            "assistant-queue-failed": ("assistant-queue-row-visual-failed", ["light", "dark"])
        ]
        let requiredWorkflowScreens: Set<String> = [
            "inbox",
            "inbox-voice",
            "projects-overview"
        ]

        for manifestName in [
            "visual-baseline-manifest.json",
            "visual-baseline-manifest-ja.json"
        ] {
            let manifest = try visualManifest(named: manifestName)
            let screens = try XCTUnwrap(manifest["screens"] as? [[String: Any]])
            let screensByID = Dictionary(
                uniqueKeysWithValues: try screens.map {
                    (try XCTUnwrap($0["id"] as? String), $0)
                }
            )

            XCTAssertTrue(
                requiredWorkflowScreens.isSubset(of: Set(screensByID.keys)),
                "\(manifestName) must keep the complete workflow contract"
            )
            for (screenID, expected) in expectedApprovalScreens {
                let screen = try XCTUnwrap(screensByID[screenID], "\(manifestName) missing \(screenID)")
                XCTAssertEqual(screen["axTargetIdentifier"] as? String, expected.target)
                XCTAssertEqual(Set(try XCTUnwrap(screen["themes"] as? [String])), expected.themes)
                XCTAssertEqual(
                    Set(try XCTUnwrap((screen["artifacts"] as? [String: String])?.keys)),
                    expected.themes
                )
            }
            let artifactCount = try screens.reduce(into: 0) { count, screen in
                count += try XCTUnwrap(screen["artifacts"] as? [String: String]).count
            }
            XCTAssertEqual(artifactCount, 39, "\(manifestName) must describe all 39 locale-specific captures")
        }
    }

    func testCompleteCaptureContextPinsReferenceInstantLocaleAndTimeZone() throws {
        let context = try XCTUnwrap(VisualEvidenceRuntimeContext(environment: [
            VisualEvidenceRuntimeContext.referenceInstantEnvironmentKey: "2026-07-10T12:00:00Z",
            VisualEvidenceRuntimeContext.timeZoneEnvironmentKey: "UTC",
            VisualEvidenceRuntimeContext.localeEnvironmentKey: "en-US"
        ]))

        XCTAssertEqual(ISO8601DateFormatter().string(from: context.referenceInstant), "2026-07-10T12:00:00Z")
        XCTAssertEqual(context.timeZoneIdentifier, "UTC")
        XCTAssertEqual(context.localeIdentifier, "en-US")
        XCTAssertEqual(context.calendar.timeZone.identifier, "GMT")
        XCTAssertEqual(context.calendar.locale?.identifier, "en-US")
    }

    func testPartialOrInvalidCaptureContextFallsBackToSystemClockAndCalendar() {
        let systemNow = Date(timeIntervalSince1970: 123)
        var systemCalendar = Calendar(identifier: .iso8601)
        systemCalendar.timeZone = TimeZone(secondsFromGMT: 3_600)!
        let partialEnvironment = [
            VisualEvidenceRuntimeContext.referenceInstantEnvironmentKey: "2026-07-10T12:00:00Z"
        ]

        XCTAssertNil(VisualEvidenceRuntimeContext(environment: partialEnvironment))
        XCTAssertEqual(
            VisualEvidenceRuntimeContext.referenceDate(
                environment: partialEnvironment,
                systemNow: { systemNow }
            ),
            systemNow
        )
        XCTAssertEqual(
            VisualEvidenceRuntimeContext.runtimeCalendar(
                environment: partialEnvironment,
                systemCalendar: { systemCalendar }
            ).timeZone,
            systemCalendar.timeZone
        )
    }

    func testVisualFixtureSeederPersistsExactInertApprovalStatesWithoutDuplicates() throws {
        let packageRoot = packageRoot()
        let fixtureDirectory = packageRoot
            .appendingPathComponent(".build/test-visual-fixture-seeder-\(UUID().uuidString)", isDirectory: true)
        let evidenceHome = fixtureDirectory.appendingPathComponent("home", isDirectory: true)
        let databaseURL = evidenceHome.appendingPathComponent("Library/Application Support/Suisui/suisui.sqlite")
        try FileManager.default.createDirectory(at: evidenceHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureDirectory) }

        let seederURL = packageRoot
            .appendingPathComponent(".build/debug/SuisuiVisualFixtureSeeder")
        XCTAssertTrue(
            FileManager.default.isExecutableFile(atPath: seederURL.path),
            "build SuisuiVisualFixtureSeeder before running its persistence integration test"
        )
        let seederArguments = try visualFixtureSeederArguments(
            executableURL: seederURL,
            databaseURL: databaseURL,
            evidenceHome: evidenceHome
        )

        for _ in 0..<2 {
            let seed = try runTool(seederArguments)
            XCTAssertEqual(seed.exitCode, 0, seed.output)
        }

        let store = try SQLiteAssistantQueueStore(path: databaseURL.path)
        let items = try store.list(filter: .all(limit: 100))
        let itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        XCTAssertEqual(Set(itemsByID.keys), ["visual-waiting", "visual-approved", "visual-failed"])
        XCTAssertEqual(items.count, 3, "rerunning the seeder must update stable rows, not append duplicates")
        XCTAssertEqual(itemsByID["visual-waiting"]?.state, .waitingReview)
        XCTAssertEqual(itemsByID["visual-approved"]?.state, .approved)
        XCTAssertEqual(itemsByID["visual-failed"]?.state, .failed)

        var planIDs = Set<String>()
        var actionIDs = Set<String>()
        for item in items {
            guard case .actionPlan(let plan) = item.payload else {
                XCTFail("\(item.id) must persist an action-plan payload")
                continue
            }
            let action = try XCTUnwrap(plan.actions.first)
            XCTAssertEqual(plan.actions.count, 1)
            XCTAssertEqual(plan.userInput, "Prepare local visual evidence")
            XCTAssertEqual(plan.summary, "Prepare local visual evidence")
            XCTAssertEqual(plan.riskLevel, .write)
            XCTAssertTrue(plan.requiresApproval)
            XCTAssertEqual(action.tool, .taskCreate)
            XCTAssertEqual(action.arguments, [
                "title": .string("Review local visual evidence"),
                "detail": .string("Visual fixture only; no external connector is invoked.")
            ])
            XCTAssertEqual(action.riskLevel, .write)
            XCTAssertFalse(action.requiresUserConfirmation)
            XCTAssertEqual(item.riskLevel, .write)
            XCTAssertEqual(item.reviewReason, "Review this local visual fixture before approval.")
            XCTAssertEqual(item.interpretationSummary, "Local visual evidence task draft.")
            planIDs.insert(plan.id)
            actionIDs.insert(action.id)
        }
        XCTAssertEqual(planIDs.count, 3, "only stable plan IDs may differ between fixture payloads")
        XCTAssertEqual(actionIDs.count, 3, "only stable action IDs may differ between fixture payloads")

        XCTAssertNil(itemsByID["visual-waiting"]?.approval)
        for id in ["visual-approved", "visual-failed"] {
            let item = try XCTUnwrap(itemsByID[id])
            let fingerprint = try XCTUnwrap(item.approval?.reviewedContentFingerprint)
            XCTAssertEqual(fingerprint.count, 64)
            XCTAssertTrue(fingerprint.allSatisfy(\.isHexDigit))
            XCTAssertTrue(AssistantQueueStateMachine.hasCurrentApproval(item))
        }

        let rowsByID = Dictionary(
            uniqueKeysWithValues: try store.readModelSnapshot(filter: .all(limit: 100)).rows.map { ($0.id, $0) }
        )
        XCTAssertEqual(
            AssistantQueueRowActionPresentation.make(for: try XCTUnwrap(rowsByID["visual-waiting"])).primaryAction,
            .approve
        )
        XCTAssertEqual(
            AssistantQueueRowActionPresentation.make(for: try XCTUnwrap(rowsByID["visual-approved"])).primaryAction,
            .run
        )
        XCTAssertEqual(
            AssistantQueueRowActionPresentation.make(for: try XCTUnwrap(rowsByID["visual-failed"])).primaryAction,
            .reopen
        )
    }

    func testVisualFixtureSeederAcceptsUncreatedDatabaseBelowAncestorSymlinkHome() throws {
        let fixtureDirectory = URL(
            fileURLWithPath: "/tmp/suisui-visual-seeder-\(UUID().uuidString)",
            isDirectory: true
        )
        let evidenceHome = fixtureDirectory.appendingPathComponent("home", isDirectory: true)
        let databaseURL = evidenceHome.appendingPathComponent("Library/Application Support/Suisui/suisui.sqlite")
        try FileManager.default.createDirectory(at: evidenceHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureDirectory) }

        let result = try runTool(
            visualFixtureSeederArguments(
                databaseURL: databaseURL,
                evidenceHome: evidenceHome
            )
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: databaseURL.path))
    }

    func testVisualFixtureSeederPreservesNonEvidenceMCPRegistrationsWhenRerun() throws {
        let fixtureDirectory = URL(
            fileURLWithPath: "/tmp/suisui-visual-seeder-preserve-mcp-\(UUID().uuidString)",
            isDirectory: true
        )
        let evidenceHome = fixtureDirectory.appendingPathComponent("home", isDirectory: true)
        let databaseURL = evidenceHome.appendingPathComponent("suisui.sqlite")
        try FileManager.default.createDirectory(at: evidenceHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureDirectory) }

        var arguments = try visualFixtureSeederArguments(
            databaseURL: databaseURL,
            evidenceHome: evidenceHome
        )
        arguments += [
            "--capture-reference-instant",
            "2026-07-10T12:00:00Z"
        ]
        let firstSeed = try runTool(arguments)
        XCTAssertEqual(firstSeed.exitCode, 0, firstSeed.output)

        var connection: SQLiteConnection? = try SQLiteConnection(path: databaseURL.path)
        try connection?.execute(
            """
            INSERT INTO mcp_server_registrations (
                id, sort_order, display_name, command, arguments_json,
                environment_json, working_directory, is_enabled
            ) VALUES (
                'user-owned-mcp', 99, 'User MCP', '/usr/bin/true',
                '[]', '{}', NULL, 1
            );
            """
        )
        try connection?.execute("PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode=DELETE;")
        connection = nil

        let secondSeed = try runTool(arguments)
        XCTAssertEqual(secondSeed.exitCode, 0, secondSeed.output)
        let validationConnection = try SQLiteConnection(path: databaseURL.path)
        XCTAssertEqual(
            try validationConnection.queryStrings(
                "SELECT id FROM mcp_server_registrations WHERE id = 'user-owned-mcp';"
            ),
            ["user-owned-mcp"]
        )
    }

    func testVisualFixtureSeederRejectsEvidenceHomeWithoutCaptureOwnershipMarker() throws {
        let fixtureDirectory = URL(
            fileURLWithPath: "/tmp/suisui-visual-seeder-unowned-\(UUID().uuidString)",
            isDirectory: true
        )
        let evidenceHome = fixtureDirectory.appendingPathComponent("home", isDirectory: true)
        let databaseURL = evidenceHome.appendingPathComponent("suisui.sqlite")
        let markerToken = UUID().uuidString
        try FileManager.default.createDirectory(at: evidenceHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureDirectory) }

        let result = try runTool([
            visualFixtureSeederURL().path,
            "--database",
            databaseURL.path,
            "--evidence-home",
            evidenceHome.path,
            "--evidence-home-marker-token",
            markerToken
        ])

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(result.output.localizedCaseInsensitiveContains("capture-owned isolated home"), result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path))
    }

    func testVisualFixtureSeederRejectsUncreatedDatabaseBelowEscapingParentSymlink() throws {
        let fixtureDirectory = URL(
            fileURLWithPath: "/tmp/suisui-visual-seeder-\(UUID().uuidString)",
            isDirectory: true
        )
        let evidenceHome = fixtureDirectory.appendingPathComponent("home", isDirectory: true)
        let externalDirectory = fixtureDirectory.appendingPathComponent("external", isDirectory: true)
        let escapedParent = evidenceHome.appendingPathComponent("escaped", isDirectory: true)
        let databaseURL = escapedParent.appendingPathComponent("nested/suisui.sqlite")
        try FileManager.default.createDirectory(at: evidenceHome, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: escapedParent, withDestinationURL: externalDirectory)
        defer { try? FileManager.default.removeItem(at: fixtureDirectory) }

        let result = try runTool(
            visualFixtureSeederArguments(
                databaseURL: databaseURL,
                evidenceHome: evidenceHome
            )
        )

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(result.output.contains("--database must be a file below the resolved --evidence-home"), result.output)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: externalDirectory.appendingPathComponent("nested/suisui.sqlite").path
            )
        )
    }

    func testVisualFixtureSeederRejectsDatabaseFinalSymlink() throws {
        let fixtureDirectory = URL(
            fileURLWithPath: "/tmp/suisui-visual-seeder-\(UUID().uuidString)",
            isDirectory: true
        )
        let evidenceHome = fixtureDirectory.appendingPathComponent("home", isDirectory: true)
        let databaseTarget = evidenceHome.appendingPathComponent("database-target.sqlite")
        let databaseSymlink = evidenceHome.appendingPathComponent("suisui.sqlite")
        try FileManager.default.createDirectory(at: evidenceHome, withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: databaseTarget.path, contents: Data()))
        try FileManager.default.createSymbolicLink(at: databaseSymlink, withDestinationURL: databaseTarget)
        defer { try? FileManager.default.removeItem(at: fixtureDirectory) }

        let result = try runTool(
            visualFixtureSeederArguments(
                databaseURL: databaseSymlink,
                evidenceHome: evidenceHome
            )
        )

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(result.output.localizedCaseInsensitiveContains("symbolic link"), result.output)
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: databaseTarget.path)[.size] as? NSNumber,
            0
        )
    }

    func testVisualFixtureSeederRejectsDatabaseHardLink() throws {
        let fixtureDirectory = URL(
            fileURLWithPath: "/tmp/suisui-visual-seeder-\(UUID().uuidString)",
            isDirectory: true
        )
        let evidenceHome = fixtureDirectory.appendingPathComponent("home", isDirectory: true)
        let externalDatabase = fixtureDirectory.appendingPathComponent("external.sqlite")
        let databaseURL = evidenceHome.appendingPathComponent("suisui.sqlite")
        try FileManager.default.createDirectory(at: evidenceHome, withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: externalDatabase.path, contents: Data()))
        try FileManager.default.linkItem(at: externalDatabase, to: databaseURL)
        defer { try? FileManager.default.removeItem(at: fixtureDirectory) }

        let result = try runTool(
            visualFixtureSeederArguments(
                databaseURL: databaseURL,
                evidenceHome: evidenceHome
            )
        )

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(result.output.localizedCaseInsensitiveContains("hard link"), result.output)
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: externalDatabase.path)[.size] as? NSNumber,
            0
        )
    }

    func testCaptureSeedOnlyDelegatesDatabaseWorkToSecureSeeder() throws {
        let fixtureDirectory = URL(
            fileURLWithPath: "/tmp/suisui-capture-seed-\(UUID().uuidString)",
            isDirectory: true
        )
        let evidenceHome = fixtureDirectory.appendingPathComponent("home", isDirectory: true)
        let temporaryDirectory = fixtureDirectory.appendingPathComponent("tmp", isDirectory: true)
        let databaseURL = captureDatabaseURL(in: evidenceHome)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureDirectory) }

        let result = try runTool(
            ["/bin/bash", captureScriptURL().path, "--seed-only"],
            environment: captureSeedEnvironment(
                evidenceHome: evidenceHome,
                temporaryDirectory: temporaryDirectory
            )
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("capture_seed_ready=1"), result.output)
        let connection = try SQLiteConnection(path: databaseURL.path)
        XCTAssertEqual(
            try connection.queryStrings(
                "SELECT title FROM projects WHERE source_command = 'ui-evidence' ORDER BY title;"
            ),
            ["Completed Evidence Project", "Inbox", "Launch Readiness"]
        )
        XCTAssertEqual(
            try connection.queryStrings(
                "SELECT id FROM assistant_queue_items WHERE id LIKE 'visual-%' ORDER BY id;"
            ),
            ["visual-approved", "visual-failed", "visual-waiting"]
        )
    }

    func testCaptureSeedOnlyRejectsExistingUnownedHomeBeforeSeeding() throws {
        let fixtureDirectory = URL(
            fileURLWithPath: "/tmp/suisui-capture-seed-existing-home-\(UUID().uuidString)",
            isDirectory: true
        )
        let evidenceHome = fixtureDirectory.appendingPathComponent("home", isDirectory: true)
        let temporaryDirectory = fixtureDirectory.appendingPathComponent("tmp", isDirectory: true)
        let sentinel = evidenceHome.appendingPathComponent("keep.txt")
        try FileManager.default.createDirectory(at: evidenceHome, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        try Data("must-not-change".utf8).write(to: sentinel)
        defer { try? FileManager.default.removeItem(at: fixtureDirectory) }

        let result = try runTool(
            ["/bin/bash", captureScriptURL().path, "--seed-only"],
            environment: captureSeedEnvironment(
                evidenceHome: evidenceHome,
                temporaryDirectory: temporaryDirectory
            )
        )

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(result.output.contains("BLOCKER"), result.output)
        XCTAssertTrue(result.output.localizedCaseInsensitiveContains("isolated home"), result.output)
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("must-not-change".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: captureDatabaseURL(in: evidenceHome).path))
    }

    func testCaptureSeedOnlyRejectsDatabaseSymlinkWithoutChangingExternalTarget() throws {
        let fixtureDirectory = URL(
            fileURLWithPath: "/tmp/suisui-capture-seed-symlink-\(UUID().uuidString)",
            isDirectory: true
        )
        let evidenceHome = fixtureDirectory.appendingPathComponent("home", isDirectory: true)
        let temporaryDirectory = fixtureDirectory.appendingPathComponent("tmp", isDirectory: true)
        let databaseURL = captureDatabaseURL(in: evidenceHome)
        let externalDatabase = fixtureDirectory.appendingPathComponent("external.sqlite")
        let sentinel = Data("external-symlink-target".utf8)
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        try sentinel.write(to: externalDatabase)
        try FileManager.default.createSymbolicLink(at: databaseURL, withDestinationURL: externalDatabase)
        defer { try? FileManager.default.removeItem(at: fixtureDirectory) }

        let result = try runTool(
            ["/bin/bash", captureScriptURL().path, "--seed-only"],
            environment: captureSeedEnvironment(
                evidenceHome: evidenceHome,
                temporaryDirectory: temporaryDirectory
            )
        )

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(result.output.localizedCaseInsensitiveContains("isolated home"), result.output)
        XCTAssertEqual(try Data(contentsOf: externalDatabase), sentinel)
    }

    func testCaptureSeedOnlyRejectsDatabaseHardLinkWithoutChangingExternalTarget() throws {
        let fixtureDirectory = URL(
            fileURLWithPath: "/tmp/suisui-capture-seed-hardlink-\(UUID().uuidString)",
            isDirectory: true
        )
        let evidenceHome = fixtureDirectory.appendingPathComponent("home", isDirectory: true)
        let temporaryDirectory = fixtureDirectory.appendingPathComponent("tmp", isDirectory: true)
        let databaseURL = captureDatabaseURL(in: evidenceHome)
        let externalDatabase = fixtureDirectory.appendingPathComponent("external.sqlite")
        let sentinel = Data("external-hardlink-target".utf8)
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        try sentinel.write(to: externalDatabase)
        try FileManager.default.linkItem(at: externalDatabase, to: databaseURL)
        defer { try? FileManager.default.removeItem(at: fixtureDirectory) }

        let result = try runTool(
            ["/bin/bash", captureScriptURL().path, "--seed-only"],
            environment: captureSeedEnvironment(
                evidenceHome: evidenceHome,
                temporaryDirectory: temporaryDirectory
            )
        )

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(result.output.localizedCaseInsensitiveContains("isolated home"), result.output)
        XCTAssertEqual(try Data(contentsOf: externalDatabase), sentinel)
    }

    func testCaptureDatabaseSourceContractUsesPinnedDirectoryDescriptorsOnly() throws {
        let script = try String(contentsOf: captureScriptURL(), encoding: .utf8)
        let seeder = try String(
            contentsOf: packageRoot()
                .appendingPathComponent("Sources/SuisuiVisualFixtureSeeder/main.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(script.contains("sqlite3"))
        XCTAssertTrue(script.contains("seed_capture_database"))
        XCTAssertTrue(script.contains("--capture-reference-instant"))
        XCTAssertTrue(script.contains("--evidence-home-marker-token"))
        XCTAssertTrue(script.contains("must name a new isolated home"))
        XCTAssertTrue(script.contains("capture_seed_ready=1"))
        XCTAssertFalse(seeder.contains("FileManager.default.createDirectory"))
        XCTAssertTrue(seeder.contains("mkdirat"))
        XCTAssertTrue(seeder.contains("let evidenceHomeDescriptor"))
        XCTAssertTrue(seeder.contains("validateEvidenceHomeMarker(in: evidenceHomeDescriptor)"))
        XCTAssertTrue(seeder.contains("openat("))
        XCTAssertTrue(
            seeder.contains("DELETE FROM mcp_server_registrations WHERE id LIKE 'ui-evidence-%';")
        )
        XCTAssertFalse(seeder.contains("DELETE FROM mcp_server_registrations;"))
    }

    private func visualManifest(named fileName: String) throws -> [String: Any] {
        let packageRoot = packageRoot()
        let data = try Data(
            contentsOf: packageRoot.appendingPathComponent("docs/quality/\(fileName)")
        )
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func visualFixtureSeederURL() -> URL {
        packageRoot().appendingPathComponent(".build/debug/SuisuiVisualFixtureSeeder")
    }

    private func visualFixtureSeederArguments(
        executableURL: URL? = nil,
        databaseURL: URL,
        evidenceHome: URL
    ) throws -> [String] {
        let markerToken = UUID().uuidString
        let markerURL = evidenceHome.appendingPathComponent(".suisui-ui-evidence-home-v1")
        try Data("suisui-ui-evidence-home-v1:\(markerToken)\n".utf8).write(to: markerURL)
        return [
            (executableURL ?? visualFixtureSeederURL()).path,
            "--database",
            databaseURL.path,
            "--evidence-home",
            evidenceHome.path,
            "--evidence-home-marker-token",
            markerToken
        ]
    }

    private func captureScriptURL() -> URL {
        packageRoot().appendingPathComponent("script/capture_ui_evidence.sh")
    }

    private func captureDatabaseURL(in evidenceHome: URL) -> URL {
        evidenceHome.appendingPathComponent("Library/Application Support/Suisui/Suisui.sqlite")
    }

    private func captureSeedEnvironment(
        evidenceHome: URL,
        temporaryDirectory: URL
    ) -> [String: String] {
        [
            "SUISUI_UI_EVIDENCE_HOME": evidenceHome.path,
            "SUISUI_UI_EVIDENCE_TMPDIR": temporaryDirectory.path,
            "SUISUI_VISUAL_FIXTURE_SEEDER_BIN": visualFixtureSeederURL().path
        ]
    }

    private func runTool(
        _ arguments: [String],
        environment: [String: String] = [:]
    ) throws -> (exitCode: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: arguments[0])
        process.arguments = Array(arguments.dropFirst())
        process.currentDirectoryURL = packageRoot()
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, override in
            override
        }
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (process.terminationStatus, output)
    }
}
