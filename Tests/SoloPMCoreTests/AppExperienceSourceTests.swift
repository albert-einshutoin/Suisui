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
        XCTAssertTrue(source.contains("Archive Project"))
        XCTAssertTrue(source.contains("Show Archived"))
        XCTAssertTrue(source.contains("Restore Project"))
        XCTAssertTrue(source.contains("confirmationDialog"))
        XCTAssertTrue(coreSource.contains("Backlog"))
        XCTAssertTrue(coreSource.contains("In Progress"))
        XCTAssertTrue(coreSource.contains("Done"))
    }

    func testProjectBoardLoadFailureIsNotRenderedAsNoProjects() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")

        XCTAssertTrue(source.contains("Project Board Unavailable"))
        XCTAssertTrue(source.contains("isEmptyProjectStateVisible"))
        let unavailableRange = try XCTUnwrap(source.range(of: "Project Board Unavailable"))
        let noProjectsRange = try XCTUnwrap(source.range(of: "No Projects"))
        XCTAssertLessThan(unavailableRange.lowerBound, noProjectsRange.lowerBound)
    }

    func testProjectBoardUsesResponsiveLongContentGuards() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")

        XCTAssertTrue(source.contains("ViewThatFits(in: .horizontal)"))
        XCTAssertTrue(source.contains("ProjectHeaderTitleEditor"))
        XCTAssertTrue(source.contains("ProjectHeaderActions"))
        XCTAssertTrue(source.contains("TaskMetadataRow"))
        XCTAssertTrue(source.contains("ScrollView([.horizontal, .vertical])"))
        XCTAssertTrue(source.contains(".defaultScrollAnchor(.topLeading)"))
        XCTAssertTrue(source.contains(".scrollIndicators(.visible)"))
        XCTAssertTrue(source.contains(".help(task.title)"))
        XCTAssertTrue(source.contains(".help(task.detail)"))
        XCTAssertTrue(source.contains(".truncationMode(.tail)"))
    }

    func testTaskInspectorRefreshesWhenSelectedTaskDataChanges() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")

        XCTAssertTrue(source.contains(".onChange(of: task)"))
        XCTAssertTrue(source.contains("refreshFields(from: task)"))
        XCTAssertFalse(source.contains(".onChange(of: task.id)"))
    }

    func testProjectBoardUsesPersistentViewModelInsteadOfStaticSnapshot() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")

        XCTAssertTrue(appSource.contains("makeProjectBoardViewModel()"))
        XCTAssertFalse(appSource.contains("makeProjectBoardSnapshot()"))
        XCTAssertTrue(boardSource.contains("@StateObject private var viewModel: ProjectBoardViewModel"))
        XCTAssertTrue(boardSource.contains("createTask("))
    }

    func testAppearanceSelectionIsConfiguredOnlyFromSettings() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")

        XCTAssertTrue(appSource.contains("Section(\"Appearance\")"))
        XCTAssertTrue(appSource.contains("Picker(\"Theme\", selection: $appearancePreference)"))
        XCTAssertEqual(appSource.components(separatedBy: "Picker(\"Theme\"").count - 1, 1)
        XCTAssertFalse(boardSource.contains("AppearancePicker"))
        XCTAssertFalse(boardSource.contains("SidebarAppearanceSection"))
        XCTAssertFalse(boardSource.contains("Picker(\"Theme\""))
        XCTAssertFalse(boardSource.contains("Picker(\"Appearance\""))
        XCTAssertFalse(boardSource.contains("SoloPMAppearancePreference"))
        XCTAssertFalse(boardSource.contains("Theme"))
        XCTAssertFalse(boardSource.contains("appearancePreference: $appearancePreference"))
    }

    func testProjectBoardDropPayloadsAreValidatedByViewModel() throws {
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let coreSource = try readPackageFile("Sources/SoloPMCore/App/ProjectBoard.swift")

        XCTAssertTrue(boardSource.contains("onMoveDroppedTasks(payloads.map(\\.taskID), column.status)"))
        XCTAssertFalse(boardSource.contains("compactMap(Int64.init)"))
        XCTAssertTrue(boardSource.contains("ProjectTaskDragPayload"))
        XCTAssertTrue(coreSource.contains("moveDroppedTasks(ids taskIDs: [Int64], to status: ProjectTaskStatus)"))
        XCTAssertTrue(coreSource.contains("moveDroppedTasks(ids rawIDs: [String], to status: ProjectTaskStatus)"))
        XCTAssertTrue(coreSource.contains("func moveTasks(ids: [Int64], to status: ProjectTaskStatus) throws -> [ProjectBoardTask]"))
        XCTAssertTrue(coreSource.contains("store.moveTasks(ids: taskIDs, to: status)"))
        XCTAssertTrue(coreSource.contains("Could not move task: invalid drag payload."))
    }

    func testProjectBoardSupportsPersistentLightDarkAppearanceSelection() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let appearanceSource = try readPackageFile("Sources/SoloPMApp/Views/SoloPMAppearancePreference.swift")

        XCTAssertTrue(appearanceSource.contains("enum SoloPMAppearancePreference"))
        XCTAssertTrue(appearanceSource.contains("case system"))
        XCTAssertTrue(appearanceSource.contains("case light"))
        XCTAssertTrue(appearanceSource.contains("case dark"))
        XCTAssertTrue(appearanceSource.contains("static let storageKey = \"solopm.appearancePreference\""))
        XCTAssertTrue(appearanceSource.contains("var colorScheme: ColorScheme?"))
        XCTAssertTrue(appSource.contains("@AppStorage(SoloPMAppearancePreference.storageKey)"))
        XCTAssertTrue(appSource.contains(".preferredColorScheme(appearancePreference.colorScheme)"))
        XCTAssertTrue(appSource.contains("Section(\"Appearance\")"))
        XCTAssertFalse(boardSource.contains("@AppStorage(SoloPMAppearancePreference.storageKey)"))
        XCTAssertFalse(boardSource.contains(".preferredColorScheme(appearancePreference.colorScheme)"))
    }

    func testKanbanTaskCardsExposeMouseDrivenStatusMoveControls() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")

        XCTAssertTrue(source.contains("TaskStatusMoveControls"))
        XCTAssertTrue(source.contains("Move to previous status"))
        XCTAssertTrue(source.contains("Move to next status"))
        XCTAssertTrue(source.contains("task.status.previousStatus"))
        XCTAssertTrue(source.contains("task.status.nextStatus"))
        XCTAssertTrue(source.contains("onMoveTask(task.id, status)"))
        XCTAssertTrue(source.contains(".draggable(ProjectTaskDragPayload(taskID: task.id))"))
        XCTAssertFalse(source.contains(".draggable(String(task.id))"))
        XCTAssertFalse(source.contains("Button {\n                        onSelectTask(task.id)\n                    } label: {\n                        BoardTaskCard"))
    }

    func testKanbanDragAndDropHasVisibleDesktopAffordances() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")

        XCTAssertTrue(source.contains("Drag to another status column"))
        XCTAssertTrue(source.contains("arrow.up.and.down.and.arrow.left.and.right"))
        XCTAssertTrue(source.contains("Drop to move to"))
        XCTAssertTrue(source.contains("isDropTargeted"))
        XCTAssertTrue(source.contains(".dropDestination(for: ProjectTaskDragPayload.self)"))
    }

    func testKanbanCardsUseTaskComponentDragPreview() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")

        XCTAssertTrue(source.contains("BoardTaskDragPreview"))
        XCTAssertTrue(source.contains(".draggable(ProjectTaskDragPayload(taskID: task.id)) {"))
        XCTAssertTrue(source.contains("BoardTaskDragPreview(task: task)"))
    }

    func testKanbanBoardUsesAdaptiveSampleInspiredCardStyling() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")

        XCTAssertTrue(source.contains("StatusCountBadge"))
        XCTAssertTrue(source.contains("column.status.tint"))
        XCTAssertTrue(source.contains("task.status.tint"))
        XCTAssertTrue(source.contains(".frame(width: 244"))
        XCTAssertTrue(source.contains(".background(.regularMaterial, in: RoundedRectangle"))
        XCTAssertTrue(source.contains(".shadow(color: Color.black.opacity(0.04)"))
    }

    func testKanbanCardsExposePointerHoverAndStatusRailAffordance() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")

        XCTAssertTrue(source.contains("@State private var isPointerHovered = false"))
        XCTAssertTrue(source.contains("TaskStatusAccentRail(tint: task.status.tint)"))
        XCTAssertTrue(source.contains("struct TaskStatusAccentRail"))
        XCTAssertTrue(source.contains(".onHover { isPointerHovered = $0 }"))
        XCTAssertTrue(source.contains(".shadow(color: Color.black.opacity(isPointerHovered ? 0.10 : 0.04)"))
        XCTAssertTrue(source.contains(".animation(.snappy(duration: 0.16), value: isPointerHovered)"))
    }

    func testProjectBoardExposesPrimaryCRUDKeyboardShortcuts() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")

        XCTAssertTrue(source.contains(".keyboardShortcut(\"n\", modifiers: [.command])"))
        XCTAssertTrue(source.contains(".keyboardShortcut(\"n\", modifiers: [.command, .shift])"))
        XCTAssertTrue(source.contains(".keyboardShortcut(\",\", modifiers: [.command])"))
        XCTAssertTrue(source.contains(".help(\"Add a project\")"))
        XCTAssertTrue(source.contains(".help(\"Open Settings\")"))
    }

    func testProjectBoardPromotesInboxAndTodayAsFirstClassDestinations() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let workflowSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectWorkflowViews.swift")
        let coreSource = try readPackageFile("Sources/SoloPMCore/App/ProjectBoard.swift")

        XCTAssertTrue(source.contains("ProjectBoardSidebarDestination"))
        XCTAssertTrue(source.contains("ProjectBoardSidebarDestinationRow(destination: .inbox"))
        XCTAssertTrue(source.contains("ProjectBoardSidebarDestinationRow(destination: .today"))
        XCTAssertTrue(source.contains("InboxWorkflowView("))
        XCTAssertTrue(source.contains("TodayWorkflowView("))
        XCTAssertTrue(workflowSource.contains("InboxActionPanel("))
        XCTAssertTrue(workflowSource.contains("viewModel.convertSelectedTaskToProject()"))
        XCTAssertTrue(workflowSource.contains("viewModel.scheduleSelectedTaskForToday()"))
        XCTAssertTrue(workflowSource.contains("viewModel.deferSelectedTaskForLater()"))
        XCTAssertTrue(coreSource.contains("public var inboxTasks"))
        XCTAssertTrue(coreSource.contains("public func todayTasks("))
    }

    func testAppAndCLIShareDefaultDatabaseLocation() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
        let cliSource = try readPackageFile("Sources/SoloPMCLI/SoloPMCLIEntrypoint.swift")

        XCTAssertTrue(appSource.contains("SoloPMAppDatabaseLocation.defaultDatabaseURL(createDirectory: true)"))
        XCTAssertTrue(cliSource.contains("SoloPMAppDatabaseLocation.defaultDatabaseURL(createDirectory: false)"))
        XCTAssertFalse(appSource.contains("appendingPathComponent(\"SoloPM.sqlite\")"))
    }

    func testMenuBarSummaryRefreshesFromRuntimeController() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

        XCTAssertTrue(appSource.contains("@StateObject private var menuBarController: MenuBarSummaryController"))
        XCTAssertTrue(appSource.contains("MenuBarPanel(controller: menuBarController)"))
        XCTAssertTrue(appSource.contains("makeMenuBarSummaryController()"))
        XCTAssertTrue(appSource.contains(".onReceive(NotificationCenter.default.publisher(for: .soloPMProjectBoardDidChange))"))
        XCTAssertTrue(appSource.contains("controller.emptyStateLabel"))
        XCTAssertFalse(appSource.contains("private let menuBarViewModel = AppRuntimeFactory.makeMenuBarSummaryViewModel()"))
        XCTAssertFalse(appSource.contains("StaticMenuBarSummaryProvider(summary: .empty)"))
        XCTAssertTrue(appSource.contains("UnavailableMenuBarSummaryProvider(error: error)"))
    }

    func testReviewPanelUsesResponsiveLongContentGuards() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

        XCTAssertTrue(appSource.contains("ScrollView"))
        XCTAssertTrue(appSource.contains(".frame(minHeight: 180, idealHeight: 220)"))
        XCTAssertTrue(appSource.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        XCTAssertTrue(appSource.contains("ActionReviewHeader"))
        XCTAssertTrue(appSource.contains("ReviewActionTitleRow"))
        XCTAssertTrue(appSource.contains("ViewThatFits(in: .horizontal)"))
        XCTAssertTrue(appSource.contains("argumentDisplaySummary(maxFields: 4, maxValueLength: 96)"))
        XCTAssertTrue(appSource.contains(".help(summary)"))
        XCTAssertTrue(appSource.contains(".help(argumentSummary.fullText)"))
        XCTAssertTrue(appSource.contains(".help(currentStringArgument(\"title\"))"))
        XCTAssertTrue(appSource.contains(".fixedSize(horizontal: false, vertical: true)"))
    }

    func testReviewRuntimeDoesNotFallBackToEmptyToolRegistry() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

        XCTAssertFalse(appSource.contains("registry = ToolRegistry()"))
        XCTAssertTrue(appSource.contains("runtimeValidationMessage: reviewRuntimeValidationMessage"))
        XCTAssertTrue(appSource.contains("Review execution tools are unavailable because audit logging or local data stores could not be opened."))
    }

    func testWatcherDiagnosticsUsesRuntimeStateStoreAndNotificationPermissions() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

        XCTAssertTrue(appSource.contains("WatcherDiagnosticsProvider("))
        XCTAssertTrue(appSource.contains("SQLiteDailyCheckStateStore(connection: connection)"))
        XCTAssertTrue(appSource.contains("UserNotificationsPermissionSnapshotReader.snapshot()"))
        XCTAssertTrue(appSource.contains("watcherDiagnosticsSnapshot.errorMessage"))
        XCTAssertTrue(appSource.contains("Watcher diagnostics are unavailable because local state could not be opened."))
        XCTAssertFalse(appSource.contains("lastCheckAt: nil"))
        XCTAssertFalse(appSource.contains("nextCheckAt: Date()"))
        XCTAssertFalse(appSource.contains("notificationPermissionStatus: .notDetermined"))
    }

    func testNotificationListingDoesNotDefaultMissingCallbackToEmptyList() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Adapters/UserNotificationsNotificationClient.swift")

        XCTAssertFalse(source.contains("requests.value ?? []"))
        XCTAssertTrue(source.contains("guard let pendingRequests = requests.value else"))
        XCTAssertTrue(source.contains("Pending notification requests could not be loaded."))
    }

    func testExternalMCPFakeServerKitIsNotShippedInRuntimeSources() throws {
        let sourceFiles = try allSwiftFiles(under: "Sources")

        for sourceFile in sourceFiles {
            let source = try String(contentsOf: sourceFile, encoding: .utf8)
            XCTAssertFalse(source.contains("ExternalMCPTestKit"), "\(sourceFile.path) ships the fake MCP server test kit.")
            XCTAssertFalse(source.contains("makeFakeServerTransport"), "\(sourceFile.path) ships fake MCP transport helpers.")
            XCTAssertFalse(source.contains("RecordingMCPServerProcess"), "\(sourceFile.path) ships a test-only MCP server process.")
        }
    }

    func testVoiceCaptureRuntimeDependenciesAreExplicitlyInjected() throws {
        let source = try readPackageFile("Sources/SoloPMCore/Voice/VoiceCaptureViewModel.swift")

        XCTAssertFalse(source.contains("audioRecorder: any AudioRecorder = FakeAudioRecorder()"))
        XCTAssertFalse(source.contains("sttProvider: any SpeechToTextProvider = FakeSTTProvider"))
    }

    func testRuntimeSourcesDoNotShipFakeVoiceAndPlanningProviders() throws {
        let sourceFiles = try allSwiftFiles(under: "Sources")

        for sourceFile in sourceFiles {
            let source = try String(contentsOf: sourceFile, encoding: .utf8)
            XCTAssertFalse(source.contains("struct FakeAudioRecorder"), "\(sourceFile.path) ships a test-only audio recorder.")
            XCTAssertFalse(source.contains("struct FakeSTTProvider"), "\(sourceFile.path) ships a test-only STT provider.")
            XCTAssertFalse(source.contains("struct FakeLLMProvider"), "\(sourceFile.path) ships a test-only planning provider.")
        }
    }

    func testRuntimeSourcesDoNotShipInfrastructureTestDoubles() throws {
        let sourceFiles = try allSwiftFiles(under: "Sources")

        for sourceFile in sourceFiles {
            let source = try String(contentsOf: sourceFile, encoding: .utf8)
            XCTAssertFalse(source.contains("class FakeFileMonitorClient"), "\(sourceFile.path) ships a test-only file monitor.")
            XCTAssertFalse(source.contains("struct StaticPermissionManager"), "\(sourceFile.path) ships a test-only permission manager.")
            XCTAssertFalse(source.contains("struct StaticMenuBarSummaryProvider"), "\(sourceFile.path) ships a test-only menu bar summary provider.")
            XCTAssertFalse(source.contains("struct StaticTool"), "\(sourceFile.path) ships a test-only tool implementation.")
        }
    }

    func testFSEventsMonitorDoesNotDropMismatchedEventPayloads() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Adapters/FSEventsFileMonitorClient.swift")

        XCTAssertFalse(source.contains("compactMap"))
        XCTAssertTrue(source.contains("eventPayloadMismatch"))
        XCTAssertTrue(source.contains("queuedErrors"))
    }

    func testRuntimeSourcesDoNotShipLocalInMemoryStoresAndSystemClients() throws {
        let sourceFiles = try allSwiftFiles(under: "Sources")
        let forbiddenTypeNames = [
            "InMemoryProjectBoardStore",
            "InMemoryDailyCheckStateStore",
            "InMemoryLaunchAtLoginClient",
            "InMemoryNotificationClient",
            "InMemoryCalendarClient",
            "InMemoryReminderClient",
            "InMemoryMailDraftClient"
        ]

        for sourceFile in sourceFiles {
            let source = try String(contentsOf: sourceFile, encoding: .utf8)
            for typeName in forbiddenTypeNames {
                XCTAssertFalse(source.contains("class \(typeName)"), "\(sourceFile.path) ships test-only \(typeName).")
            }
        }
    }

    func testUnavailableMailDraftClientDoesNotExposeEmptyListSuccessPath() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
        let clientSource = try readPackageFile("Sources/SoloPMCore/Tools/SystemToolClients.swift")
        let unavailableClientStart = try XCTUnwrap(appSource.range(of: "private struct UnavailableMailDraftClient"))
        let unavailableClientEnd = try XCTUnwrap(appSource.range(of: "private extension JSONValue", range: unavailableClientStart.upperBound..<appSource.endIndex))
        let unavailableClientSource = String(appSource[unavailableClientStart.lowerBound..<unavailableClientEnd.lowerBound])

        XCTAssertTrue(appSource.contains("mailDraftClient: UnavailableMailDraftClient()"))
        XCTAssertFalse(unavailableClientSource.contains("func listDrafts() throws -> [MailDraftRecord]"))
        XCTAssertFalse(unavailableClientSource.contains("[]"))
        XCTAssertFalse(clientSource.contains("func listDrafts() throws -> [MailDraftRecord]"))
    }

    func testRuntimeSourcesDoNotShipSecurityOrMCPInMemoryStores() throws {
        let sourceFiles = try allSwiftFiles(under: "Sources")
        let forbiddenTypeNames = [
            "InMemorySecretStore",
            "InMemoryAuditLogger",
            "InMemoryMCPServerRegistrationStore"
        ]

        for sourceFile in sourceFiles {
            let source = try String(contentsOf: sourceFile, encoding: .utf8)
            for typeName in forbiddenTypeNames {
                XCTAssertFalse(source.contains("class \(typeName)"), "\(sourceFile.path) ships test-only \(typeName).")
            }
        }
    }

    func testRuntimeSecretRedactionCompilesPatternsBeforeRedacting() throws {
        let source = try readPackageFile("Sources/SoloPMCore/DeveloperMode/DraftGeneration.swift")

        XCTAssertTrue(source.contains("CompiledPattern"))
        XCTAssertFalse(source.contains("try? NSRegularExpression(pattern: pattern.expression)"))
        XCTAssertFalse(source.contains("try! NSRegularExpression(pattern: expression)"))
        XCTAssertTrue(source.contains("compileDefaultPatterns()"))
        XCTAssertTrue(source.contains("redactor_initialization_failed"))
    }

    func testLocalStoresDoNotDefaultArrayEncodingToEmptyJSON() throws {
        let source = try readPackageFile("Sources/SoloPMCore/Tools/LocalStores.swift")

        XCTAssertTrue(source.contains("static func jsonArray(_ values: [String], column: String) throws -> String"))
        XCTAssertFalse(source.contains(#"(try? JSONEncoder().encode(values)) ?? Data("[]".utf8)"#))
        XCTAssertFalse(source.contains(#"String(data: data, encoding: .utf8) ?? "[]""#))
    }

    func testKnowledgeVectorEncodingDoesNotDefaultToEmptyVectorJSON() throws {
        let source = try readPackageFile("Sources/SoloPMCore/Knowledge/KnowledgeAdvanced.swift")

        XCTAssertFalse(source.contains(#"String(data: data, encoding: .utf8) ?? "[]""#))
        XCTAssertTrue(source.contains("Could not encode knowledge_frame_vectors.vector_json as UTF-8 JSON."))
    }

    func testAuditLoggerDoesNotDefaultMetadataEncodingToEmptyJSON() throws {
        let source = try readPackageFile("Sources/SoloPMCore/Audit/AuditLogger.swift")

        XCTAssertFalse(source.contains(#"String(data: metadataData, encoding: .utf8) ?? "{}""#))
        XCTAssertTrue(source.contains("Could not encode audit_logs.metadata_json as UTF-8 JSON."))
    }

    func testActionPlanSchemaDoesNotFallBackToSourceTreeAtRuntime() throws {
        let source = try readPackageFile("Sources/SoloPMCore/Planning/ActionPlanSchema.swift")

        XCTAssertFalse(source.contains("loadDataFromSourceTree"))
        XCTAssertFalse(source.contains("#filePath"))
        XCTAssertFalse(source.contains("Sources/SoloPMCore/Resources"))
        XCTAssertFalse(source.contains("try? loadData(bundle: .main)"))
        XCTAssertFalse(source.contains("try? loadData(bundle: .module)"))
        XCTAssertTrue(source.contains("catch ActionPlanSchemaError.resourceNotFound"))
    }

    func testExternalMCPLauncherDoesNotDefaultToInMemorySecretStore() throws {
        let source = try readPackageFile("Sources/SoloPMCore/ExternalMCP/MCPRegistration.swift")

        XCTAssertFalse(source.contains("SecretStoreMCPEnvironmentResolver(secretStore: InMemorySecretStore())"))
    }

    func testRuntimeExternalMCPSettingsUseSQLiteRegistrationStore() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
        let mcpRegistrationSource = try readPackageFile("Sources/SoloPMCore/ExternalMCP/MCPRegistration.swift")

        XCTAssertTrue(appSource.contains("SQLiteMCPServerRegistrationStore(connection:"))
        XCTAssertTrue(appSource.contains("Picker(\"Server\""))
        XCTAssertTrue(appSource.contains("externalMCPViewModel.registrationRows"))
        XCTAssertTrue(appSource.contains("externalMCPViewModel.selectRegistration(id: $0)"))
        XCTAssertTrue(appSource.contains("externalMCPViewModel.createRegistration()"))
        XCTAssertTrue(appSource.contains("Add Server"))
        XCTAssertTrue(appSource.contains("Environment References"))
        XCTAssertTrue(appSource.contains("externalMCPViewModel.environmentText"))
        XCTAssertTrue(appSource.contains("externalMCPViewModel.updateEnvironmentText($0)"))
        XCTAssertTrue(appSource.contains("Protocol Version"))
        XCTAssertTrue(appSource.contains("externalMCPViewModel.protocolVersionLabel"))
        XCTAssertTrue(appSource.contains("Check Result"))
        XCTAssertTrue(appSource.contains("externalMCPViewModel.connectionCheckResultLabel"))
        XCTAssertTrue(appSource.contains("LabeledContent(\"Resources\", value: \"Not supported in this release\")"))
        XCTAssertTrue(appSource.contains("LabeledContent(\"Prompts\", value: \"Not supported in this release\")"))
        XCTAssertTrue(appSource.contains("MCP Keychain Secret"))
        XCTAssertTrue(appSource.contains("settingsViewModel.keychainSecretKeyInput"))
        XCTAssertTrue(appSource.contains("settingsViewModel.updateKeychainSecretKeyInput($0)"))
        XCTAssertTrue(appSource.contains("SecureField(\"Secret Value\""))
        XCTAssertTrue(appSource.contains("settingsViewModel.saveKeychainSecret()"))
        XCTAssertTrue(appSource.contains("settingsViewModel.deleteKeychainSecret()"))
        XCTAssertTrue(appSource.contains("isConfirmingMCPRegistrationDeletion = true"))
        XCTAssertTrue(appSource.contains(#"confirmationDialog("#))
        XCTAssertTrue(appSource.contains("externalMCPViewModel.deleteRegistration()"))
        XCTAssertTrue(mcpRegistrationSource.contains("MCPServerRegistrationRow"))
        XCTAssertTrue(mcpRegistrationSource.contains("selectedRegistrationID"))
        XCTAssertTrue(mcpRegistrationSource.contains("MCPEnvironmentTextCodec"))
        XCTAssertTrue(mcpRegistrationSource.contains("rawValueNotAllowed"))
        XCTAssertFalse(appSource.contains("store: UserDefaultsMCPServerRegistrationStore()"))
        XCTAssertFalse(mcpRegistrationSource.contains("UserDefaultsMCPServerRegistrationStore"))
    }

    func testRuntimeExternalMCPAuditLoadFailureIsNotRenderedAsEmptyHistory() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
        let mcpRegistrationSource = try readPackageFile("Sources/SoloPMCore/ExternalMCP/MCPRegistration.swift")

        XCTAssertTrue(appSource.contains("externalMCPAuditLoadResult()"))
        XCTAssertTrue(appSource.contains("auditErrorMessage: auditLoadResult.errorMessage"))
        XCTAssertTrue(appSource.contains("externalMCPViewModel.auditErrorMessage"))
        XCTAssertTrue(appSource.contains("MCP audit history is unavailable because audit logging could not be opened."))
        XCTAssertFalse(appSource.contains("private static func externalMCPAuditRows() -> [ExternalMCPAuditHistoryRow]"))
        XCTAssertTrue(mcpRegistrationSource.contains("@Published public private(set) var auditErrorMessage: String?"))
    }

    func testExternalMCPArgumentsUseQuotedRoundTripTextInsteadOfSpaceSplitDisplay() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
        let mcpRegistrationSource = try readPackageFile("Sources/SoloPMCore/ExternalMCP/MCPRegistration.swift")

        XCTAssertTrue(appSource.contains("externalMCPViewModel.argumentsText"))
        XCTAssertFalse(appSource.contains("registration.arguments.joined(separator: \" \")"))
        XCTAssertTrue(mcpRegistrationSource.contains("MCPArgumentTextCodec.parse"))
        XCTAssertTrue(mcpRegistrationSource.contains("MCPArgumentTextCodec.format"))
    }

    func testExternalMCPExecutorDoesNotDefaultToInMemoryAuditLogger() throws {
        let source = try readPackageFile("Sources/SoloPMCore/ExternalMCP/MCPExecution.swift")

        XCTAssertFalse(source.contains("auditLogger: any AuditLogger = InMemoryAuditLogger()"))
        XCTAssertFalse(source.contains("processController: any MCPProcessController = NoopMCPProcessController()"))
        XCTAssertFalse(source.contains("struct NoopMCPProcessController"))
        XCTAssertFalse(source.contains("RecordingMCPProcessController"))
        XCTAssertFalse(source.contains("MCPProcessKillRequest"))
        XCTAssertFalse(source.contains("let descriptor = try? registry.descriptor(named: toolName)"))
        XCTAssertTrue(source.contains("descriptor: ExternalMCPToolDescriptor"))
    }

    func testToolExecutionContextRequiresExplicitSource() throws {
        let source = try readPackageFile("Sources/SoloPMCore/Tools/Tooling.swift")

        XCTAssertFalse(source.contains("source: ToolExecutionSource = .developerHarness"))
        XCTAssertFalse(source.contains("case developerHarness"))
        XCTAssertFalse(source.contains("case test"))
        XCTAssertTrue(source.contains("case developerTool"))
        XCTAssertTrue(source.contains("source: ToolExecutionSource)"))
    }

    func testAIProvidersDoNotDefaultToInMemorySecretStore() throws {
        let chatSource = try readPackageFile("Sources/SoloPMCore/Planning/ChatCompletionsCompatibleProvider.swift")
        let sttSource = try readPackageFile("Sources/SoloPMCore/Voice/STTProviders.swift")

        XCTAssertFalse(chatSource.contains("secretStore: any SecretStore = InMemorySecretStore()"))
        XCTAssertFalse(sttSource.contains("secretStore: any SecretStore = InMemorySecretStore()"))
    }

    func testSettingsAIProviderPickerUsesSelectableCatalog() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

        XCTAssertTrue(appSource.contains("settingsViewModel.selectableAIProviders"))
        XCTAssertTrue(appSource.contains("settingsViewModel.selectAIProviderAndSave($0)"))
        XCTAssertFalse(appSource.contains("ForEach(AIProvider.allCases"))
        XCTAssertFalse(appSource.contains("Save Provider Selection"))
    }

    func testSettingsShowsOpenAIProviderSmokeReadiness() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

        XCTAssertTrue(appSource.contains("OpenAI Provider Smoke"))
        XCTAssertTrue(appSource.contains("settingsViewModel.openAIProviderSmokeStatusLabel"))
    }

    func testShortcutSettingsDoesNotDefaultToInMemoryClient() throws {
        let source = try readPackageFile("Sources/SoloPMCore/Shortcuts/ShortcutRegistration.swift")

        XCTAssertFalse(source.contains("client: any ShortcutClient = InMemoryShortcutClient()"))
    }

    func testRuntimeSourcesDoNotShipShortcutInMemoryClient() throws {
        let sourceFiles = try allSwiftFiles(under: "Sources")

        for sourceFile in sourceFiles {
            let source = try String(contentsOf: sourceFile, encoding: .utf8)
            XCTAssertFalse(source.contains("class InMemoryShortcutClient"), "\(sourceFile.path) ships test-only shortcut client.")
        }
    }

    func testRuntimeSourcesDoNotShipKnowledgeTestDoubles() throws {
        let sourceFiles = try allSwiftFiles(under: "Sources")
        let forbiddenTypeDeclarations = [
            "struct StaticEmbeddingProvider",
            "class InMemoryKnowledgeVectorIndex",
            "struct StaticKnowledgeTextSearch",
            "struct BYOKOpenAIEmbeddingProvider",
            "openai_byok_fallback",
            "class InMemoryWeKnoraClient"
        ]

        for sourceFile in sourceFiles {
            let source = try String(contentsOf: sourceFile, encoding: .utf8)
            for declaration in forbiddenTypeDeclarations {
                XCTAssertFalse(source.contains(declaration), "\(sourceFile.path) ships test-only knowledge component \(declaration).")
            }
        }
    }

    func testRuntimeSourcesDoNotShipSaaSConnectorTestDoubles() throws {
        let sourceFiles = try allSwiftFiles(under: "Sources")
        let forbiddenTypeDeclarations = [
            "class InMemoryOAuthCredentialMetadataStore",
            "class InMemoryGoogleCalendarClient",
            "class InMemoryGmailDraftClient",
            "class InMemorySlackClient",
            "class InMemoryGoogleDriveClient",
            "class InMemoryNotionClient",
            "struct StaticConnectorHealthClient"
        ]

        for sourceFile in sourceFiles {
            let source = try String(contentsOf: sourceFile, encoding: .utf8)
            for declaration in forbiddenTypeDeclarations {
                XCTAssertFalse(source.contains(declaration), "\(sourceFile.path) ships test-only SaaS connector component \(declaration).")
            }
        }
    }

    func testPublicAlphaAppDoesNotLinkExternalSaaSConnectorTarget() throws {
        let packageSource = try readPackageFile("Package.swift")
        let appTarget = try XCTUnwrap(packageSource.range(of: ".executableTarget(\n            name: \"SoloPM\","))
        let cliTarget = try XCTUnwrap(packageSource.range(of: ".executableTarget(\n            name: \"SoloPMCLI\","))
        let testsTarget = try XCTUnwrap(packageSource.range(of: ".testTarget(\n            name: \"SoloPMCoreTests\","))
        let appTargetBlock = String(packageSource[appTarget.lowerBound..<cliTarget.lowerBound])
        let cliTargetBlock = String(packageSource[cliTarget.lowerBound..<testsTarget.lowerBound])

        XCTAssertTrue(packageSource.contains("name: \"SoloPMExternalConnectors\""))
        XCTAssertTrue(packageSource.contains("dependencies: [\"SoloPMCore\"]"))
        XCTAssertFalse(appTargetBlock.contains("SoloPMExternalConnectors"))
        XCTAssertFalse(cliTargetBlock.contains("SoloPMExternalConnectors"))
    }

    func testSoloPMCoreDoesNotShipExternalSaaSConnectorImplementations() throws {
        let coreSourceFiles = try allSwiftFiles(under: "Sources/SoloPMCore")
        let forbiddenRuntimeSymbols = [
            "SaaSConnectorID",
            "OAuthScope",
            "GoogleCalendarConnector",
            "GmailDraftConnector",
            "SlackConnector",
            "GoogleDriveConnector",
            "NotionConnector",
            "ConnectorHealthDashboard"
        ]

        for sourceFile in coreSourceFiles {
            let source = try String(contentsOf: sourceFile, encoding: .utf8)
            for symbol in forbiddenRuntimeSymbols {
                XCTAssertFalse(source.contains(symbol), "\(sourceFile.path) keeps optional external SaaS connector symbol \(symbol) in SoloPMCore.")
            }
        }
    }

    func testInMemoryToolRegistryFactoryIsNotShippedInRuntimeSources() throws {
        let sourceFiles = try allSwiftFiles(under: "Sources")

        for sourceFile in sourceFiles {
            let source = try String(contentsOf: sourceFile, encoding: .utf8)
            XCTAssertFalse(source.contains("ToolRegistryFactory.inMemoryPhase2MVP"), "\(sourceFile.path) references test-only in-memory registry factory.")
            XCTAssertFalse(source.contains("inMemoryPhase2MVP("), "\(sourceFile.path) ships test-only in-memory registry factory.")
            XCTAssertFalse(source.contains(#"SQLiteConnection(path: ":memory:")"#), "\(sourceFile.path) opens a test-only in-memory registry database.")
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

    func testReviewRuntimeRequiresAuditLoggerBeforeWriteExecution() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
        let reviewFactoryStart = try XCTUnwrap(appSource.range(of: "static func makeReviewSessionViewModel(plan: ActionPlan)"))
        let nextFactoryStart = try XCTUnwrap(appSource.range(of: "private static func migratedConnection()", range: reviewFactoryStart.upperBound..<appSource.endIndex))
        let reviewFactory = String(appSource[reviewFactoryStart.lowerBound..<nextFactoryStart.lowerBound])

        XCTAssertFalse(reviewFactory.contains("try? makeAuditLogger()"))
        XCTAssertTrue(reviewFactory.contains("let auditLogger = try makeAuditLogger()"))
        XCTAssertTrue(reviewFactory.contains("logger = auditLogger"))
        XCTAssertTrue(reviewFactory.contains("Review execution tools are unavailable because audit logging or local data stores could not be opened."))
    }

    func testUnavailableReviewRegistryDoesNotSilentlyDropRegistrationFailures() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

        XCTAssertFalse(appSource.contains("try? target.register(UnavailableReviewTool"))
        XCTAssertFalse(appSource.contains("try! target.register(UnavailableReviewTool"))
        XCTAssertTrue(appSource.contains("registrationFailures.append(action.tool.rawValue)"))
        XCTAssertTrue(appSource.contains("Fallback unavailable tools could not be registered"))
        XCTAssertTrue(appSource.contains("UnavailableReviewRegistryResult"))
    }

    func testVoicePlanningRequiresAuditLoggerBeforeGeneration() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
        let voiceFactoryStart = try XCTUnwrap(appSource.range(of: "static func makeVoiceCaptureViewModel()"))
        let nextFactoryStart = try XCTUnwrap(appSource.range(of: "private static func loadRuntimeSettings()", range: voiceFactoryStart.upperBound..<appSource.endIndex))
        let voiceFactory = String(appSource[voiceFactoryStart.lowerBound..<nextFactoryStart.lowerBound])

        XCTAssertFalse(voiceFactory.contains("try? makeAuditLogger()"))
        XCTAssertTrue(voiceFactory.contains("auditLogger = try makeAuditLogger()"))
        XCTAssertTrue(voiceFactory.contains("runtimeValidationMessage: runtimeValidationMessage"))
        XCTAssertTrue(voiceFactory.contains("Voice planning is unavailable because audit logging or local data stores could not be opened."))
    }

    func testReviewActionButtonsDoNotDropViewModelErrors() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

        XCTAssertFalse(appSource.contains("try? viewModel.approve()"))
        XCTAssertFalse(appSource.contains("try? viewModel.execute()"))
        XCTAssertTrue(appSource.contains("viewModel.approveOrReportError()"))
        XCTAssertTrue(appSource.contains("viewModel.executeOrReportError()"))
    }

    func testRuntimeSettingsLoadDoesNotSilentlyDefaultOnDecodeFailure() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
        let runtimeFactoryStart = try XCTUnwrap(appSource.range(of: "private enum AppRuntimeFactory"))
        let runtimeFactory = String(appSource[runtimeFactoryStart.lowerBound..<appSource.endIndex])

        XCTAssertFalse(runtimeFactory.contains("(try? UserDefaultsAppSettingsStore().load()) ?? .default"))
        XCTAssertFalse(runtimeFactory.contains("((try? UserDefaultsAppSettingsStore().load()) ?? .default).normalizedForRuntime"))
        XCTAssertTrue(runtimeFactory.contains("loadRuntimeSettings()"))
        XCTAssertTrue(runtimeFactory.contains("Runtime app settings could not be loaded. Defaults are shown until settings are saved again."))
    }

    func testSettingsSurfaceCanPersistProviderKeysThroughViewModel() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

        XCTAssertTrue(appSource.contains("AppSettingsViewModel"))
        XCTAssertTrue(appSource.contains("settingsViewModel.saveOpenAIAPIKey()"))
        XCTAssertTrue(appSource.contains("settingsViewModel.deleteOpenAIAPIKey()"))
        XCTAssertTrue(appSource.contains("settingsViewModel.saveAnthropicAPIKey()"))
        XCTAssertTrue(appSource.contains("settingsViewModel.deleteAnthropicAPIKey()"))
        XCTAssertTrue(appSource.contains("Anthropic API Key"))
        XCTAssertTrue(appSource.contains("settingsViewModel.saveGeminiAPIKey()"))
        XCTAssertTrue(appSource.contains("settingsViewModel.deleteGeminiAPIKey()"))
        XCTAssertTrue(appSource.contains("Gemini API Key"))
        XCTAssertTrue(appSource.contains("Gemini Model ID"))
        XCTAssertTrue(appSource.contains("settingsViewModel.saveGroqAPIKey()"))
        XCTAssertTrue(appSource.contains("settingsViewModel.deleteGroqAPIKey()"))
        XCTAssertTrue(appSource.contains("Groq API Key"))
        XCTAssertTrue(appSource.contains("Groq Base URL"))
        XCTAssertTrue(appSource.contains("OpenCode Executable"))
        XCTAssertTrue(appSource.contains("OpenCode Workspace"))
        XCTAssertTrue(appSource.contains("OpenCode Model ID"))
        XCTAssertTrue(appSource.contains("Approve OpenCode Local Execution"))
        XCTAssertFalse(appSource.contains("SecureField(\"API Key\", text: .constant(\"\"))"))
    }

    func testSettingsSurfaceStartsWithStatusOverviewForCoreOperationalAreas() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

        let overviewRange = try XCTUnwrap(appSource.range(of: "SettingsStatusOverview("))
        let appearanceRange = try XCTUnwrap(appSource.range(of: "Section(\"Appearance\")"))

        XCTAssertLessThan(overviewRange.lowerBound, appearanceRange.lowerBound)
        XCTAssertTrue(appSource.contains("Section(\"Status Overview\")"))
        XCTAssertTrue(appSource.contains("title: \"AI Provider\""))
        XCTAssertTrue(appSource.contains("title: \"MCP\""))
        XCTAssertTrue(appSource.contains("title: \"Sync\""))
        XCTAssertTrue(appSource.contains("title: \"Privacy\""))
        XCTAssertTrue(appSource.contains("settingsViewModel.settings.aiProvider.displayName"))
        XCTAssertTrue(appSource.contains("externalMCPViewModel.connectionCheckResultLabel"))
        XCTAssertTrue(appSource.contains("syncViewModel.statusLabel"))
        XCTAssertTrue(appSource.contains("settingsViewModel.settings.notificationsEnabled"))
    }

    func testRuntimeLLMFactoryUsesClaudeMessagesProviderWithoutOpenAIFallback() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
        let factoryStart = try XCTUnwrap(appSource.range(of: "private static func makeLLMProvider"))
        let factorySource = String(appSource[factoryStart.lowerBound..<appSource.endIndex])

        XCTAssertTrue(factorySource.contains("case .claudeMessages:"))
        XCTAssertTrue(factorySource.contains("ClaudeMessagesConfiguration(model: entry.defaultModelID)"))
        XCTAssertTrue(factorySource.contains("ClaudeMessagesProvider(secretStore: secretStore, configuration: configuration)"))
        XCTAssertFalse(factorySource.contains(".openaiResponses,\n             .claudeMessages"))
    }

    func testRuntimeLLMFactoryUsesGeminiDirectProviderWithoutOpenAICompatibleFallback() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
        let factoryStart = try XCTUnwrap(appSource.range(of: "private static func makeLLMProvider"))
        let factorySource = String(appSource[factoryStart.lowerBound..<appSource.endIndex])

        XCTAssertTrue(factorySource.contains("case .geminiDirect:"))
        XCTAssertTrue(factorySource.contains("GeminiDirectConfiguration(model: settings.normalizedForRuntime.geminiModelID ?? entry.defaultModelID)"))
        XCTAssertTrue(factorySource.contains("GeminiDirectProvider(secretStore: secretStore, configuration: configuration)"))
        XCTAssertTrue(factorySource.contains(".openaiResponses,\n             .geminiOpenAICompatible:"))
        XCTAssertFalse(factorySource.contains(".claudeMessages,\n             .geminiDirect"))
        XCTAssertFalse(factorySource.contains(".geminiDirect,\n             .geminiOpenAICompatible"))
    }

    func testRuntimeLLMFactoryUsesOpenCodeLocalProviderWithoutOpenAIFallbackOrAuthFileRead() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
        let factoryStart = try XCTUnwrap(appSource.range(of: "private static func makeLLMProvider"))
        let factorySource = String(appSource[factoryStart.lowerBound..<appSource.endIndex])

        XCTAssertTrue(factorySource.contains("case .opencodeLocal:"))
        XCTAssertTrue(factorySource.contains("OpenCodeLocalConfiguration("))
        XCTAssertTrue(factorySource.contains("OpenCodeLocalProvider(configuration: configuration)"))
        XCTAssertTrue(factorySource.contains("normalizedSettings.openCodeExecutablePath"))
        XCTAssertTrue(factorySource.contains("normalizedSettings.openCodeWorkspacePath"))
        XCTAssertFalse(factorySource.contains(".openaiResponses,\n             .opencodeLocal"))
        XCTAssertFalse(appSource.contains(".local/share/opencode/auth.json"))
    }

    func testRuntimeLLMFactoryUsesGroqCompatibleProviderWithoutOpenAIFallback() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
        let factoryStart = try XCTUnwrap(appSource.range(of: "private static func makeLLMProvider"))
        let factorySource = String(appSource[factoryStart.lowerBound..<appSource.endIndex])

        XCTAssertTrue(factorySource.contains("case .groqOpenAICompatible:"))
        XCTAssertTrue(factorySource.contains("let defaultBaseURL = entry.baseURL"))
        XCTAssertTrue(factorySource.contains("configuration: .groq("))
        XCTAssertTrue(factorySource.contains("settings.normalizedForRuntime.resolvedGroqBaseURL(defaultBaseURL: defaultBaseURL)"))
        XCTAssertTrue(factorySource.contains("secretStore: secretStore"))
        XCTAssertFalse(factorySource.contains(".openaiResponses,\n             .groqOpenAICompatible"))
    }

    func testSettingsSurfaceOnlyShowsReleaseReadySTTProviders() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

        XCTAssertTrue(appSource.contains("STTProvider.releaseReadyCases"))
        XCTAssertFalse(appSource.contains("ForEach(STTProvider.allCases"))
        XCTAssertFalse(appSource.contains("AppleSpeechAnalyzerProvider()"))
        XCTAssertFalse(appSource.contains("WhisperKitProvider()"))
        XCTAssertFalse(appSource.contains("WhisperCppProvider()"))
    }

    func testSettingsSurfaceShowsSyncGateWithoutMockSuccessPath() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
        let syncSource = try readPackageFile("Sources/SoloPMCore/App/SyncService.swift")
        let entitlementSource = try readPackageFile("Sources/SoloPMCore/App/Entitlements.swift")

        XCTAssertTrue(appSource.contains("@StateObject private var syncViewModel: SyncSettingsViewModel"))
        XCTAssertTrue(appSource.contains("Section(\"Sync\")"))
        XCTAssertTrue(appSource.contains("syncViewModel.startSync()"))
        XCTAssertTrue(appSource.contains("KeychainEntitlementStore(secretStore: makeSecretStore())"))
        XCTAssertTrue(syncSource.contains("throw SyncServiceError.syncBackendNotConfigured"))
        XCTAssertTrue(entitlementSource.contains("case externalSync"))
        XCTAssertFalse(syncSource.contains("return SyncStartResult(startedAt: Date())"))
    }

    func testLLMHTTPErrorMappingDoesNotDropMalformedErrorBodies() throws {
        let llmProviderSource = try readPackageFile("Sources/SoloPMCore/Planning/LLMProvider.swift")
        let responsesSource = try readPackageFile("Sources/SoloPMCore/Planning/OpenAIResponsesProvider.swift")
        let chatSource = try readPackageFile("Sources/SoloPMCore/Planning/ChatCompletionsCompatibleProvider.swift")
        let claudeSource = try readPackageFile("Sources/SoloPMCore/Planning/ClaudeMessagesProvider.swift")
        let geminiSource = try readPackageFile("Sources/SoloPMCore/Planning/GeminiDirectProvider.swift")

        XCTAssertTrue(llmProviderSource.contains("LLMHTTPErrorMessageExtractor"))
        XCTAssertTrue(llmProviderSource.contains("Unexpected error body"))
        XCTAssertTrue(llmProviderSource.contains("DeveloperSecretRedactor().redact"))
        XCTAssertTrue(responsesSource.contains("LLMHTTPErrorMessageExtractor.message(from: data)"))
        XCTAssertTrue(chatSource.contains("LLMHTTPErrorMessageExtractor.message(from: data)"))
        XCTAssertTrue(claudeSource.contains("LLMHTTPErrorMessageExtractor.message(from: data)"))
        XCTAssertTrue(geminiSource.contains("LLMHTTPErrorMessageExtractor.message(from: data)"))
        XCTAssertTrue(claudeSource.contains("Claude Messages HTTP"))
        XCTAssertTrue(geminiSource.contains("Gemini Direct HTTP"))
        XCTAssertFalse(responsesSource.contains("No error message."))
        XCTAssertFalse(chatSource.contains("No error message."))
        XCTAssertFalse(claudeSource.contains("No error message."))
        XCTAssertFalse(geminiSource.contains("No error message."))
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
