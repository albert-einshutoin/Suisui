import Foundation
import XCTest

final class AppExperienceSourceTests: XCTestCase {
    func testAppLaunchesProjectBoardBeforeVoiceCaptureWindow() throws {
        let source = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

        XCTAssertTrue(source.contains("WindowGroup(\"SoloPM\", id: \"project-board\")"))
        let boardWindow = try XCTUnwrap(source.range(of: "WindowGroup(\"SoloPM\", id: \"project-board\")"))
        let voiceWindow = try XCTUnwrap(source.range(of: "Window(\"Voice Command\", id: \"voice-capture\")"))
        XCTAssertLessThan(boardWindow.lowerBound, voiceWindow.lowerBound)
    }

    func testRecordFlowDoesNotInjectCannedPhaseOneTranscript() throws {
        let source = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

        XCTAssertFalse(source.contains("Create a task to review the SoloPM Phase 1 UI"))
    }

    func testProjectBoardSurfaceUsesKanbanLayout() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let coreSource = try readPackageFile("Sources/SoloPMCore/App/ProjectBoard.swift")

        XCTAssertTrue(source.contains("NavigationSplitView"))
        XCTAssertTrue(source.contains("BoardColumnView"))
        XCTAssertTrue(source.contains("InlineTaskComposer"))
        XCTAssertTrue(source.contains("TaskInspectorView"))
        XCTAssertTrue(coreSource.contains("Backlog"))
        XCTAssertTrue(coreSource.contains("In Progress"))
        XCTAssertTrue(coreSource.contains("Done"))
    }

    func testProjectBoardUsesPersistentViewModelInsteadOfStaticSnapshot() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")

        XCTAssertTrue(appSource.contains("makeProjectBoardViewModel()"))
        XCTAssertFalse(appSource.contains("makeProjectBoardSnapshot()"))
        XCTAssertTrue(boardSource.contains("@StateObject private var viewModel: ProjectBoardViewModel"))
        XCTAssertTrue(boardSource.contains("createTask("))
    }

    func testMenuBarSummaryRefreshesFromRuntimeController() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

        XCTAssertTrue(appSource.contains("@StateObject private var menuBarController: MenuBarSummaryController"))
        XCTAssertTrue(appSource.contains("MenuBarPanel(controller: menuBarController)"))
        XCTAssertTrue(appSource.contains("makeMenuBarSummaryController()"))
        XCTAssertTrue(appSource.contains(".onReceive(NotificationCenter.default.publisher(for: .soloPMProjectBoardDidChange))"))
        XCTAssertFalse(appSource.contains("private let menuBarViewModel = AppRuntimeFactory.makeMenuBarSummaryViewModel()"))
        XCTAssertFalse(appSource.contains("StaticMenuBarSummaryProvider(summary: .empty)"))
        XCTAssertTrue(appSource.contains("UnavailableMenuBarSummaryProvider(error: error)"))
    }

    func testReviewPanelUsesResponsiveLongContentGuards() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

        XCTAssertTrue(appSource.contains("ViewThatFits(in: .horizontal)"))
        XCTAssertTrue(appSource.contains("argumentDisplaySummary(maxFields: 4, maxValueLength: 96)"))
        XCTAssertTrue(appSource.contains(".help(argumentSummary.fullText)"))
        XCTAssertTrue(appSource.contains(".fixedSize(horizontal: false, vertical: true)"))
    }

    func testReviewRuntimeDoesNotFallBackToEmptyToolRegistry() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

        XCTAssertFalse(appSource.contains("registry = ToolRegistry()"))
        XCTAssertTrue(appSource.contains("runtimeValidationMessage: reviewRuntimeValidationMessage"))
        XCTAssertTrue(appSource.contains("Review execution tools are unavailable because local data stores could not be opened."))
    }

    func testWatcherDiagnosticsUsesRuntimeStateStoreAndNotificationPermissions() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

        XCTAssertTrue(appSource.contains("WatcherDiagnosticsProvider("))
        XCTAssertTrue(appSource.contains("SQLiteDailyCheckStateStore(connection: connection)"))
        XCTAssertTrue(appSource.contains("UserNotificationsPermissionSnapshotReader.snapshot()"))
        XCTAssertFalse(appSource.contains("lastCheckAt: nil"))
        XCTAssertFalse(appSource.contains("nextCheckAt: Date()"))
        XCTAssertFalse(appSource.contains("notificationPermissionStatus: .notDetermined"))
    }

    func testExternalMCPFakeServerKitIsNotShippedInRuntimeSources() throws {
        let sourceFiles = try allSwiftFiles(under: "Sources")

        for sourceFile in sourceFiles {
            let source = try String(contentsOf: sourceFile, encoding: .utf8)
            XCTAssertFalse(source.contains("ExternalMCPTestKit"), "\(sourceFile.path) ships the fake MCP server test kit.")
            XCTAssertFalse(source.contains("makeFakeServerTransport"), "\(sourceFile.path) ships fake MCP transport helpers.")
        }
    }

    func testRuntimeAppCompositionDoesNotUseDemoOrInMemorySuccessPath() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

        XCTAssertFalse(appSource.contains("AppPreviewFactory"))
        XCTAssertFalse(appSource.contains("DemoPlanningProvider"))
        XCTAssertFalse(appSource.contains("DemoTranscriptionUnavailableProvider"))
        XCTAssertFalse(appSource.contains("InMemoryProjectBoardStore()"))
        XCTAssertFalse(appSource.contains("ToolRegistryFactory.inMemoryPhase2MVP"))
        XCTAssertTrue(appSource.contains("AppRuntimeFactory"))
        XCTAssertTrue(appSource.contains("KeychainSecretStore"))
        XCTAssertTrue(appSource.contains("OpenAIResponsesProvider(secretStore:"))
        XCTAssertTrue(appSource.contains("ToolRegistry.phase2MVP("))
    }

    func testSettingsSurfaceCanPersistOpenAIKeyThroughViewModel() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

        XCTAssertTrue(appSource.contains("AppSettingsViewModel"))
        XCTAssertTrue(appSource.contains("settingsViewModel.saveOpenAIAPIKey()"))
        XCTAssertTrue(appSource.contains("settingsViewModel.deleteOpenAIAPIKey()"))
        XCTAssertFalse(appSource.contains("SecureField(\"API Key\", text: .constant(\"\"))"))
    }

    private func readPackageFile(_ relativePath: String) throws -> String {
        let url = packageRoot().appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func allSwiftFiles(under relativePath: String) throws -> [URL] {
        let root = packageRoot().appendingPathComponent(relativePath, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return try enumerator.compactMap { item -> URL? in
            guard let url = item as? URL, url.pathExtension == "swift" else {
                return nil
            }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            return values.isRegularFile == true ? url : nil
        }
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }
}
