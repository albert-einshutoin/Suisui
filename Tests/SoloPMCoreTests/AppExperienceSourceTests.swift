import Foundation
import XCTest

final class AppExperienceSourceTests: XCTestCase {
    func testAppLaunchesProjectBoardBeforeVoiceCaptureWindow() throws {
        let source = try readAppShellSource()

        XCTAssertTrue(source.contains("WindowGroup(\"SoloPM\", id: \"project-board\")"))
        XCTAssertTrue(source.contains("VoiceCaptureWindowRootView()"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"voice-capture-loading\")"))
        XCTAssertTrue(source.contains("SettingsWindowRootView("))
        XCTAssertFalse(source.contains("Window(\"Voice Command\", id: \"voice-capture\") {\n            VoiceCaptureView(viewModel: AppRuntimeFactory.makeVoiceCaptureViewModel())"))
        let boardWindow = try XCTUnwrap(source.range(of: "WindowGroup(\"SoloPM\", id: \"project-board\")"))
        let voiceWindow = try XCTUnwrap(source.range(of: "Window(\"Voice Command\", id: \"voice-capture\")"))
        XCTAssertLessThan(boardWindow.lowerBound, voiceWindow.lowerBound)
    }

    func testRecordFlowDoesNotInjectCannedPhaseOneTranscript() throws {
        let source = try readAppShellSource()

        XCTAssertFalse(source.contains("Create a task to review the SoloPM Phase 1 UI"))
    }

    func testAVFoundationAudioRecorderRedactsSystemErrorMessages() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Adapters/AVFoundationAudioRecorder.swift")

        XCTAssertEqual(source.components(separatedBy: "UserFacingErrorMessageSanitizer.message(").count - 1, 2)
        XCTAssertEqual(source.components(separatedBy: "from: error").count - 1, 2)
        XCTAssertFalse(source.contains("state = .failed(error.localizedDescription)"))
        XCTAssertFalse(source.contains("throw AudioRecorderError.failed(error.localizedDescription)"))
    }

    func testAVFoundationAudioRecorderRequestsFirstRunMicrophoneAccess() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Adapters/AVFoundationAudioRecorder.swift")
        let notDeterminedRange = try XCTUnwrap(source.range(of: "case .notDetermined:"))
        let unknownRange = try XCTUnwrap(source.range(of: "@unknown default:", range: notDeterminedRange.upperBound..<source.endIndex))
        let notDeterminedBlock = source[notDeterminedRange.lowerBound..<unknownRange.lowerBound]

        XCTAssertTrue(notDeterminedBlock.contains("state = .requestingPermission"))
        XCTAssertTrue(notDeterminedBlock.contains("await requestMicrophoneAccess()"))
        XCTAssertTrue(source.contains("AVCaptureDevice.requestAccess(for: .audio)"))
    }

    func testProjectBoardSurfaceUsesKanbanLayout() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let modelSource = try readPackageFile("Sources/SoloPMCore/WorkManagement/WorkManagementModels.swift")

        XCTAssertTrue(source.contains("NavigationSplitView"))
        XCTAssertTrue(source.contains("BoardColumnView"))
        XCTAssertTrue(source.contains("InlineTaskComposer"))
        XCTAssertTrue(source.contains("TaskInspectorView"))
        XCTAssertTrue(source.contains("Archive Project"))
        XCTAssertTrue(source.contains("Show Archived"))
        XCTAssertTrue(source.contains("Restore Project"))
        XCTAssertTrue(source.contains("InspectorDestructiveConfirmation"))
        XCTAssertTrue(modelSource.contains("Backlog"))
        XCTAssertTrue(modelSource.contains("In Progress"))
        XCTAssertTrue(modelSource.contains("Done"))
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
        XCTAssertTrue(source.contains("ProjectHeaderSummary"))
        XCTAssertTrue(source.contains("ProjectHeaderActions"))
        XCTAssertTrue(source.contains("TaskCardMetadataStrip"))
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
        let appSource = try readAppShellSource()
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")

        XCTAssertTrue(appSource.contains("prepareProjectBoardRuntimeBundle()"))
        XCTAssertTrue(appSource.contains("makeProjectBoardViewModel(runtime: runtime)"))
        XCTAssertFalse(appSource.contains("makeProjectBoardSnapshot()"))
        XCTAssertTrue(boardSource.contains("@StateObject private var viewModel: ProjectBoardViewModel"))
        XCTAssertTrue(boardSource.contains("createTask("))
    }

    func testProjectBoardRefreshesTodayFromProductionDateAndLifecycleNotifications() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")

        XCTAssertTrue(source.contains("@Environment(\\.scenePhase) private var scenePhase"))
        XCTAssertTrue(source.contains(".onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged))"))
        XCTAssertTrue(source.contains(".onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange))"))
        XCTAssertTrue(source.contains(".onChange(of: scenePhase)"))
        XCTAssertTrue(source.contains("viewModel.refreshDerivedReadModels()"))
    }

    func testSelectionOnlyTodayRefreshReusesPlanPreviewAndRecommendationChips() throws {
        let source = try readPackageFile("Sources/SoloPMCore/App/ProjectBoard.swift")
        let start = try XCTUnwrap(source.range(of: "private func refreshTodayDerivedReadModelForSelectionChange()"))
        let end = try XCTUnwrap(source.range(of: "private func makeCachedDailyPlanningReviewPreview(", range: start.upperBound..<source.endIndex))
        let selectionRefresh = String(source[start.lowerBound..<end.lowerBound])

        XCTAssertTrue(selectionRefresh.contains("nextReadModels.todayWorkflowSnapshot.plan"))
        XCTAssertTrue(selectionRefresh.contains("assistantContext"))
        XCTAssertFalse(selectionRefresh.contains("todayPlan("))
        XCTAssertFalse(selectionRefresh.contains("dailyWorkloadOverview("))
        XCTAssertFalse(selectionRefresh.contains("makeCachedDailyPlanningReviewPreview("))
    }

    func testTodayWorkflowViewUsesExplicitReviewBeforeSnapshotPreview() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectWorkflowTodayView.swift")

        XCTAssertTrue(source.contains("viewModel.dailyPlanningReview ?? snapshot.dailyPlanningReviewPreview"))
    }

    func testProjectBoardRuntimeLoadsAssistantQueueReadModel() throws {
        let appSource = try readAppShellSource()
        let coreSource = try readPackageFile("Sources/SoloPMCore/App/ProjectBoard.swift")
        let reviewSessionSource = try readPackageFile("Sources/SoloPMCore/Review/ReviewSessionViewModel.swift")

        XCTAssertTrue(appSource.contains("assistantQueueStore: SQLiteAssistantQueueStore(connection: connection)"))
        XCTAssertTrue(appSource.contains("assistantQueueStore: assistantQueueStore"))
        XCTAssertTrue(appSource.contains("assistantQueueExecutionCoordinatorFactory: {"))
        XCTAssertTrue(appSource.contains("executionReceiptStore: try? makeExecutionReceiptStore()"))
        XCTAssertTrue(appSource.contains("executionReceiptStore: executionReceiptStore"))
        XCTAssertTrue(appSource.contains("managedAIUsageLedgerStore: SQLiteManagedAIUsageLedgerStore(connection: connection)"))
        XCTAssertTrue(appSource.contains("managedAIBillingSettingsProvider: { loadRuntimeAppSettings().managedAIBilling }"))
        XCTAssertTrue(appSource.contains("return AssistantQueueExecutionCoordinator("))
        XCTAssertTrue(coreSource.contains("@Published public private(set) var assistantQueueSnapshot: AssistantQueueSnapshot"))
        XCTAssertTrue(coreSource.contains("AssistantQueueReadModel.snapshot("))
        XCTAssertTrue(reviewSessionSource.contains("executionReceiptStore?.list(limit: 100)"))
    }

    func testAssistantQueueWorkflowIsReachableFromProjectBoardSidebar() throws {
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let workflowSource = try readProjectWorkflowSources()
        let persistenceSource = try readPackageFile("Sources/SoloPMCore/App/ProjectBoardSelectionPersistence.swift")
        let coreSource = try readPackageFile("Sources/SoloPMCore/App/ProjectBoard.swift")

        XCTAssertTrue(persistenceSource.contains("case assistantQueue"))
        XCTAssertTrue(persistenceSource.contains("return \"assistant-queue\""))
        XCTAssertTrue(boardSource.contains("ProjectBoardSidebarDestinationRow(destination: .assistantQueue, count: viewModel.assistantQueueSnapshot.needsAttentionCount)"))
        XCTAssertTrue(boardSource.contains("AssistantQueueWorkflowView(viewModel: viewModel)"))
        XCTAssertTrue(workflowSource.contains("struct AssistantQueueWorkflowView"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"assistant-queue-workflow\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"assistant-queue-row-\\(row.id)\")"))
        XCTAssertTrue(workflowSource.contains("viewModel.runAssistantQueueItem(id: row.id)"))
        XCTAssertTrue(workflowSource.contains("viewModel.approveAssistantQueueItem(id: row.id)"))
        XCTAssertTrue(workflowSource.contains("viewModel.deferAssistantQueueItem(id: row.id)"))
        XCTAssertTrue(workflowSource.contains("viewModel.editAssistantQueueItem("))
        XCTAssertTrue(workflowSource.contains("viewModel.retryAssistantQueueItem(id: row.id)"))
        XCTAssertTrue(workflowSource.contains("viewModel.rejectAssistantQueueItem(id: row.id)"))
        XCTAssertTrue(workflowSource.contains(".disabled(!row.canRun)"))
        XCTAssertTrue(workflowSource.contains(".disabled(!row.canApprove)"))
        XCTAssertTrue(workflowSource.contains(".disabled(!row.canDefer)"))
        XCTAssertTrue(workflowSource.contains(".disabled(!row.canEdit)"))
        XCTAssertTrue(workflowSource.contains(".disabled(!row.canRetry)"))
        XCTAssertTrue(workflowSource.contains(".disabled(!row.canReject)"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"assistant-queue-run-\\(row.id)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"assistant-queue-edit-\\(row.id)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"assistant-queue-edit-reason-\\(row.id)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"assistant-queue-edit-summary-\\(row.id)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"assistant-queue-edit-save-\\(row.id)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"assistant-queue-edit-cancel-\\(row.id)\")"))
        XCTAssertTrue(workflowSource.contains("draftRedactedSummary = row.redactedSummary"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"assistant-queue-retry-\\(row.id)\")"))
        XCTAssertTrue(workflowSource.contains("AssistantQueueTriageControls("))
        XCTAssertTrue(workflowSource.contains("AssistantQueueBatchToolbar("))
        XCTAssertTrue(workflowSource.contains("viewModel.setAssistantQueueViewFilter"))
        XCTAssertTrue(workflowSource.contains("viewModel.setAssistantQueueSort"))
        XCTAssertTrue(workflowSource.contains("viewModel.setAssistantQueueSelection(id: row.id, selected: selected)"))
        XCTAssertTrue(workflowSource.contains("viewModel.deferSelectedAssistantQueueItems()"))
        XCTAssertTrue(workflowSource.contains("viewModel.rejectSelectedAssistantQueueItems()"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"assistant-queue-filter\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"assistant-queue-sort\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"assistant-queue-batch-toolbar\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"assistant-queue-select-\\(row.id)\")"))
        XCTAssertFalse(workflowSource.contains("approveSelectedAssistantQueueItems"))
        XCTAssertFalse(workflowSource.contains("runSelectedAssistantQueueItems"))
        XCTAssertTrue(workflowSource.contains("if let receipt = row.latestReceipt"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"assistant-queue-receipt-\\(row.id)\")"))
        XCTAssertTrue(workflowSource.contains("localizedDisplay(\"Receipt: %@\", localizedDisplay(receipt.statusLabel))"))
        XCTAssertTrue(coreSource.contains("public func runAssistantQueueItem(id: String) -> Bool"))
        XCTAssertTrue(coreSource.contains("public func approveAssistantQueueItem(id: String) -> Bool"))
        XCTAssertTrue(coreSource.contains("public func deferAssistantQueueItem(id: String) -> Bool"))
        XCTAssertTrue(coreSource.contains("public func editAssistantQueueItem("))
        XCTAssertTrue(coreSource.contains("public func retryAssistantQueueItem(id: String) -> Bool"))
        XCTAssertTrue(coreSource.contains("public func rejectAssistantQueueItem(id: String) -> Bool"))
        XCTAssertTrue(coreSource.contains("public func setAssistantQueueViewFilter(_ filter: AssistantQueueViewFilter)"))
        XCTAssertTrue(coreSource.contains("public func setAssistantQueueSort(_ sort: AssistantQueueSort)"))
        XCTAssertTrue(coreSource.contains("public func setAssistantQueueSelection(id: String, selected: Bool) -> Bool"))
        XCTAssertTrue(coreSource.contains("public func deferSelectedAssistantQueueItems() -> Bool"))
        XCTAssertTrue(coreSource.contains("public func rejectSelectedAssistantQueueItems() -> Bool"))
    }

    func testAssistantQueueTriageLocalizationsDoNotDuplicateSharedKeys() throws {
        let english = try readPackageFile("Sources/SoloPMApp/Resources/en.lproj/Localizable.strings")
        let japanese = try readPackageFile("Sources/SoloPMApp/Resources/ja.lproj/Localizable.strings")
        for source in [english, japanese] {
            XCTAssertEqual(source.components(separatedBy: "\"All\" =").count - 1, 1)
            XCTAssertEqual(source.components(separatedBy: "\"Sort\" =").count - 1, 1)
            XCTAssertEqual(source.components(separatedBy: "\"Needs attention\" =").count - 1, 1)
            XCTAssertEqual(source.components(separatedBy: "\"Needs action first\" =").count - 1, 1)
            XCTAssertEqual(source.components(separatedBy: "\"Risk high first\" =").count - 1, 1)
            XCTAssertEqual(source.components(separatedBy: "\"Title A-Z\" =").count - 1, 1)
        }
    }

    func testProjectBoardExposesPortableTaskImportExportFileActions() throws {
        let appSource = try readAppShellSource()
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")

        XCTAssertTrue(appSource.contains("SQLiteExternalTaskLinkStore(connection: connection)"))
        XCTAssertTrue(boardSource.contains("TaskInteropFileDocument"))
        XCTAssertTrue(boardSource.contains(".fileExporter("))
        XCTAssertTrue(boardSource.contains(".fileImporter("))
        XCTAssertTrue(boardSource.contains("Label(\"Integrations\", systemImage: \"arrow.left.arrow.right\")"))
        XCTAssertTrue(boardSource.contains("Label(\"Export Tasks\", systemImage: \"square.and.arrow.up\")"))
        XCTAssertTrue(boardSource.contains("Label(\"Import Tasks\", systemImage: \"square.and.arrow.down\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"project-board-export-tasks\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"project-board-import-tasks\")"))
        XCTAssertTrue(boardSource.contains("viewModel.importTaskInteropJSON(data)"))
        XCTAssertTrue(boardSource.contains("viewModel.exportTaskInteropJSON()"))
    }

    func testProjectAddTaskFromOverviewOpensVisibleBoardComposer() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let detailStart = try XCTUnwrap(source.range(of: "private struct ProjectBoardDetail"))
        let archivedStart = try XCTUnwrap(source.range(of: "private struct ArchivedProjectReadOnlyState"))
        let detailSource = String(source[detailStart.lowerBound..<archivedStart.lowerBound])

        XCTAssertTrue(detailSource.contains("private func startComposingTask(status: ProjectTaskStatus = .backlog)"))
        XCTAssertTrue(detailSource.contains("displayMode = .board"))
        XCTAssertTrue(detailSource.contains("composingStatus = status"))
        XCTAssertGreaterThanOrEqual(detailSource.components(separatedBy: "onAddTask: { startComposingTask() }").count - 1, 3)
        XCTAssertFalse(detailSource.contains("onAddTask: { composingStatus = .backlog }"))
    }

    func testProjectsOverviewKeepsSidebarProjectSelectionAndDetailModesSeparate() throws {
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let persistenceSource = try readPackageFile("Sources/SoloPMCore/App/ProjectBoardSelectionPersistence.swift")

        XCTAssertTrue(persistenceSource.contains("case projects"))
        XCTAssertTrue(persistenceSource.contains("case .projects:"))
        XCTAssertTrue(persistenceSource.contains("return \"projects\""))
        XCTAssertTrue(boardSource.contains("destination: .projects"))
        XCTAssertTrue(boardSource.contains(".tag(ProjectBoardSidebarDestination.projects)"))
        XCTAssertTrue(boardSource.contains("ProjectsPortfolioOverview("))
        XCTAssertTrue(boardSource.contains(".tag(ProjectBoardSidebarDestination.project(project.id))"))
        XCTAssertTrue(boardSource.contains("case .project(let projectID):"))
        XCTAssertTrue(boardSource.contains("ProjectBoardDetail("))
        XCTAssertTrue(boardSource.contains("case .overview:"))
        XCTAssertTrue(boardSource.contains("case .board:"))
        XCTAssertTrue(boardSource.contains("case .list:"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"project-display-mode-\\(mode.rawValue)\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityLabel(LocalizedStringKey(mode.label))"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"project-task-list\")"))
    }

    func testAppearanceSelectionIsConfiguredOnlyFromSettings() throws {
        let appSource = try readAppShellSource()
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let appearanceSectionSource = try readPackageFile("Sources/SoloPMApp/Views/SettingsAppearanceSection.swift")

        XCTAssertTrue(appSource.contains("SettingsAppearanceSection(appearancePreference: $appearancePreference, languagePreference: $languagePreference)"))
        XCTAssertEqual(appSource.components(separatedBy: "SettingsAppearanceSection(appearancePreference: $appearancePreference, languagePreference: $languagePreference)").count - 1, 1)
        XCTAssertTrue(appearanceSectionSource.contains("Section(\"Appearance\")"))
        XCTAssertTrue(appearanceSectionSource.contains("Picker(\"Theme\", selection: $appearancePreference)"))
        XCTAssertTrue(appearanceSectionSource.contains(".accessibilityIdentifier(\"settings-theme-picker\")"))
        XCTAssertEqual(appearanceSectionSource.components(separatedBy: "settings-theme-picker").count - 1, 1)
        XCTAssertEqual(appearanceSectionSource.components(separatedBy: "Section(\"Appearance\")").count - 1, 1)
        XCTAssertEqual(appearanceSectionSource.components(separatedBy: "Picker(\"Theme\"").count - 1, 1)
        let settingsRange = try XCTUnwrap(appSource.range(of: "Settings {"))
        let appearanceTabRange = try XCTUnwrap(appSource.range(of: "private var appearanceSettingsTab: some View"))
        let appearanceRange = try XCTUnwrap(appSource.range(of: "SettingsAppearanceSection(appearancePreference: $appearancePreference, languagePreference: $languagePreference)"))
        XCTAssertLessThan(settingsRange.lowerBound, appearanceRange.lowerBound)
        XCTAssertLessThan(appearanceTabRange.lowerBound, appearanceRange.lowerBound)
        XCTAssertTrue(appSource.contains("Label(\"Appearance\", systemImage: \"circle.lefthalf.filled\")"))
        XCTAssertTrue(appSource.contains("appearancePreference: $appearancePreference"))
        XCTAssertTrue(appSource.contains("@Binding private var appearancePreference: SoloPMAppearancePreference"))
        XCTAssertEqual(appSource.components(separatedBy: "@AppStorage(SoloPMAppearancePreference.storageKey)").count - 1, 1)
        XCTAssertFalse(appSource.contains(".accessibilityIdentifier(\"settings-theme-picker\")"))
        XCTAssertFalse(appSource.contains("Picker(\"Theme\", selection: $appearancePreference)"))
        XCTAssertFalse(boardSource.contains("AppearancePicker"))
        XCTAssertFalse(boardSource.contains("SidebarAppearanceSection"))
        XCTAssertFalse(boardSource.contains("SettingsAppearanceSection"))
        XCTAssertFalse(boardSource.contains("settings-theme-picker"))
        XCTAssertFalse(boardSource.contains("Section(\"Appearance\")"))
        XCTAssertFalse(boardSource.contains("Picker(\"Theme\""))
        XCTAssertFalse(boardSource.contains("Picker(\"Appearance\""))
        XCTAssertFalse(boardSource.contains("@AppStorage(SoloPMAppearancePreference.storageKey)"))
        XCTAssertFalse(boardSource.contains("SoloPMAppearancePreference"))
        XCTAssertFalse(boardSource.contains("Theme"))
        XCTAssertFalse(boardSource.contains("appearancePreference: $appearancePreference"))
    }

    func testLanguageSelectionSupportsJapaneseAndEnglishFromSettings() throws {
        let appSource = try readAppShellSource()
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let appearanceSectionSource = try readPackageFile("Sources/SoloPMApp/Views/SettingsAppearanceSection.swift")
        let languagePreferenceSource = try readPackageFile("Sources/SoloPMApp/Views/AppLanguagePreference.swift")
        let buildScript = try readPackageFile("script/build_and_run.sh")
        let englishStrings = try readPackageFile("Sources/SoloPMApp/Resources/en.lproj/Localizable.strings")
        let japaneseStrings = try readPackageFile("Sources/SoloPMApp/Resources/ja.lproj/Localizable.strings")

        XCTAssertTrue(languagePreferenceSource.contains("enum AppLanguagePreference"))
        XCTAssertTrue(languagePreferenceSource.contains("case system"))
        XCTAssertTrue(languagePreferenceSource.contains("case english"))
        XCTAssertTrue(languagePreferenceSource.contains("case japanese"))
        XCTAssertTrue(languagePreferenceSource.contains("static let storageKey = \"solopm.languagePreference\""))
        XCTAssertTrue(languagePreferenceSource.contains("static let environmentOverrideKey = \"SOLOPM_LANGUAGE_PREFERENCE\""))
        XCTAssertTrue(languagePreferenceSource.contains("Locale(identifier: localeIdentifier)"))

        XCTAssertTrue(appSource.contains("@AppStorage(AppLanguagePreference.storageKey) private var languagePreference: AppLanguagePreference = .system"))
        XCTAssertTrue(appSource.contains("private var effectiveLanguagePreference: AppLanguagePreference"))
        XCTAssertTrue(appSource.contains("AppLanguagePreference.environmentOverride ?? languagePreference"))
        XCTAssertTrue(appSource.contains(".environment(\\.locale, effectiveLanguagePreference.locale)"))
        XCTAssertGreaterThanOrEqual(appSource.components(separatedBy: ".environment(\\.locale, effectiveLanguagePreference.locale)").count - 1, 4)

        XCTAssertTrue(appSource.contains("languagePreference: $languagePreference"))
        XCTAssertTrue(appSource.contains("@Binding private var languagePreference: AppLanguagePreference"))
        XCTAssertTrue(appearanceSectionSource.contains("@Binding var languagePreference: AppLanguagePreference"))
        XCTAssertTrue(appearanceSectionSource.contains("Section(\"Language\")"))
        XCTAssertTrue(appearanceSectionSource.contains("Picker(\"Language\", selection: $languagePreference)"))
        XCTAssertTrue(appearanceSectionSource.contains("ForEach(AppLanguagePreference.allCases)"))
        XCTAssertTrue(appearanceSectionSource.contains(".accessibilityIdentifier(\"settings-language-picker\")"))
        XCTAssertEqual(appearanceSectionSource.components(separatedBy: "settings-language-picker").count - 1, 1)

        XCTAssertFalse(boardSource.contains("settings-language-picker"))
        XCTAssertFalse(boardSource.contains("Picker(\"Language\""))
        XCTAssertFalse(boardSource.contains("AppLanguagePreference"))
        XCTAssertFalse(boardSource.contains("@AppStorage(AppLanguagePreference.storageKey)"))

        XCTAssertTrue(buildScript.contains("copy_app_localizations"))
        XCTAssertTrue(buildScript.contains("Sources/SoloPMApp/Resources"))
        XCTAssertTrue(buildScript.contains("CFBundleDevelopmentRegion"))
        XCTAssertTrue(buildScript.contains("CFBundleLocalizations"))
        XCTAssertTrue(buildScript.contains("ja"))
        XCTAssertTrue(buildScript.contains("en"))

        XCTAssertTrue(englishStrings.contains("\"Language\" = \"Language\";"))
        XCTAssertTrue(englishStrings.contains("\"Japanese\" = \"Japanese\";"))
        XCTAssertTrue(englishStrings.contains("\"Project Board\" = \"Project Board\";"))
        XCTAssertTrue(japaneseStrings.contains("\"Language\" = \"言語\";"))
        XCTAssertTrue(japaneseStrings.contains("\"Japanese\" = \"日本語\";"))
        XCTAssertTrue(japaneseStrings.contains("\"Project Board\" = \"プロジェクトボード\";"))
    }

    func testAppLocalizationsCoverStaticSwiftUILiterals() throws {
        let englishKeys = try localizableKeys(in: "Sources/SoloPMApp/Resources/en.lproj/Localizable.strings")
        let japaneseKeys = try localizableKeys(in: "Sources/SoloPMApp/Resources/ja.lproj/Localizable.strings")

        XCTAssertEqual(englishKeys, japaneseKeys)

        var missingKeys: [String] = []
        for key in try staticSwiftUILiteralKeys() where !englishKeys.contains(key) || !japaneseKeys.contains(key) {
            missingKeys.append(key)
        }

        XCTAssertTrue(
            missingKeys.isEmpty,
            "Missing Localizable.strings keys: \(missingKeys.sorted().joined(separator: ", "))"
        )
        XCTAssertEqual(englishKeys.count, japaneseKeys.count)
        XCTAssertTrue(japaneseKeys.contains("Settings"))
        XCTAssertTrue(japaneseKeys.contains("Open Settings"))
        XCTAssertTrue(japaneseKeys.contains("Classify Selected Item"))
        XCTAssertTrue(japaneseKeys.contains("Track Artifact"))
        XCTAssertTrue(japaneseKeys.contains("MCP paid execution boundary"))
    }

    func testDynamicAppStatusStringsUseLocalizationRouting() throws {
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let workflowSource = try readProjectWorkflowSources()
        let appSource = try readAppShellSource()
        let coreBoardSource = try readPackageFile("Sources/SoloPMCore/App/ProjectBoard.swift")
        let japaneseKeys = try localizableKeys(in: "Sources/SoloPMApp/Resources/ja.lproj/Localizable.strings")

        XCTAssertTrue(boardSource.contains("localizedTaskCount(project.taskCount)"))
        XCTAssertTrue(boardSource.contains("localizedDisplay(\"%@ is blocked. Resolve it before adding more work.\", task.title)"))
        XCTAssertTrue(workflowSource.contains("Text(LocalizedStringKey(plan.recommendationReason))"))
        XCTAssertTrue(appSource.contains("localizedSettingsDisplay(statusLabel)"))
        XCTAssertTrue(coreBoardSource.contains("String(localized: \"Kept \\\"%@\\\" as a task.\")"))
        XCTAssertTrue(coreBoardSource.contains("String(localized: \"Review unblock plan\")"))
        XCTAssertTrue(coreBoardSource.contains("String(localized: \"Review next action\")"))
        XCTAssertTrue(coreBoardSource.contains("String(localized: \"Start with %@, then check milestone %@.\")"))
        XCTAssertTrue(coreBoardSource.contains("String(localized: \"No open tasks or milestones need attention.\")"))

        XCTAssertFalse(boardSource.contains("Text(project.isArchived ? \"Archived\" : \"\\(project.taskCount) tasks\")"))
        XCTAssertFalse(boardSource.contains("return \"\\(task.title) is blocked. Resolve it before adding more work.\""))
        XCTAssertFalse(workflowSource.contains("Text(plan.recommendationReason)"))
        XCTAssertFalse(appSource.contains("Label(syncUnavailableLabel, systemImage: \"lock\")"))
        XCTAssertFalse(coreBoardSource.contains("return \"Start with \\(task.title).\""))
        XCTAssertFalse(coreBoardSource.contains("return \"No open tasks or milestones need attention.\""))

        XCTAssertTrue(japaneseKeys.contains("%@ is blocked. Resolve it before adding more work."))
        XCTAssertTrue(japaneseKeys.contains(#"Kept \"%@\" as a task."#))
        XCTAssertTrue(japaneseKeys.contains("Plan: %@"))
        XCTAssertTrue(japaneseKeys.contains("Smoke: %@"))
        XCTAssertTrue(japaneseKeys.contains("Review unblock plan"))
        XCTAssertTrue(japaneseKeys.contains("Start with %@, then check milestone %@."))
    }

    func testThemePickerIsOwnedOnlyBySettingsAppearanceSectionAcrossAppSources() throws {
        let expectedOwner = "Sources/SoloPMApp/Views/SettingsAppearanceSection.swift"
        let markers = [
            "Picker(\"Theme\", selection: $appearancePreference)",
            ".accessibilityIdentifier(\"settings-theme-picker\")"
        ]
        let root = packageRoot()
        var ownersByMarker: [String: Set<String>] = [:]

        for fileURL in try allSwiftFiles(under: "Sources/SoloPMApp") {
            let relativePath = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
            let source = try String(contentsOf: fileURL, encoding: .utf8)

            for marker in markers where source.contains(marker) {
                ownersByMarker[marker, default: []].insert(relativePath)
            }
        }

        for marker in markers {
            XCTAssertEqual(ownersByMarker[marker], [expectedOwner], "\(marker) should only live in Settings.")
        }
    }

    func testProjectBoardHeaderHostsSettingsLinkWithoutThemeControls() throws {
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let sidebarStart = try XCTUnwrap(boardSource.range(of: "NavigationSplitView(columnVisibility: $columnVisibility) {"))
        let detailStart = try XCTUnwrap(boardSource.range(of: "} detail: {"))
        let sidebarSource = String(boardSource[sidebarStart.upperBound..<detailStart.lowerBound])

        XCTAssertTrue(sidebarSource.contains("Show Archived"))
        XCTAssertTrue(sidebarSource.contains("Add Project"))
        XCTAssertFalse(sidebarSource.contains("SettingsLink"))
        XCTAssertFalse(sidebarSource.contains("gearshape"))
        XCTAssertFalse(sidebarSource.contains("Theme"))
        XCTAssertFalse(sidebarSource.contains("Appearance"))
        XCTAssertFalse(sidebarSource.contains("SoloPMAppearancePreference"))
        XCTAssertFalse(sidebarSource.contains("Picker(\"Theme\""))
        XCTAssertFalse(sidebarSource.contains("Picker(\"Appearance\""))
        XCTAssertFalse(sidebarSource.contains("Light"))
        XCTAssertFalse(sidebarSource.contains("Dark"))
        XCTAssertFalse(sidebarSource.contains("System"))
        XCTAssertFalse(sidebarSource.contains("sun.max"))
        XCTAssertFalse(sidebarSource.contains("moon"))
        XCTAssertFalse(sidebarSource.contains("circle.lefthalf.filled"))
        XCTAssertFalse(sidebarSource.contains("settings-theme-picker"))
        XCTAssertFalse(sidebarSource.contains("appearancePreference"))
        XCTAssertFalse(sidebarSource.contains(".pickerStyle(.segmented)"))

        let headerStart = try XCTUnwrap(boardSource.range(of: "private var projectBoardHeaderBar: some View"))
        let toggleStart = try XCTUnwrap(boardSource.range(of: "private func toggleSidebarVisibility()"))
        let headerSource = String(boardSource[headerStart.lowerBound..<toggleStart.lowerBound])

        XCTAssertTrue(headerSource.contains("SettingsLink"))
        XCTAssertTrue(headerSource.contains("Label(\"Settings\", systemImage: \"gearshape\")"))
        XCTAssertTrue(headerSource.contains(".help(\"Open Settings\")"))
        XCTAssertTrue(headerSource.contains(".accessibilityIdentifier(\"project-board-settings-link\")"))
        XCTAssertFalse(headerSource.contains(".keyboardShortcut(\",\", modifiers: [.command])"))
        XCTAssertFalse(headerSource.contains("Theme"))
        XCTAssertFalse(headerSource.contains("Appearance"))
        XCTAssertFalse(headerSource.contains("SoloPMAppearancePreference"))
        XCTAssertFalse(headerSource.contains("Picker(\"Theme\""))
        XCTAssertFalse(headerSource.contains("Picker(\"Appearance\""))
        XCTAssertFalse(headerSource.contains("Light"))
        XCTAssertFalse(headerSource.contains("Dark"))
        XCTAssertFalse(headerSource.contains("System"))
        XCTAssertFalse(headerSource.contains("sun.max"))
        XCTAssertFalse(headerSource.contains("moon"))
        XCTAssertFalse(headerSource.contains("circle.lefthalf.filled"))
        XCTAssertFalse(headerSource.contains("settings-theme-picker"))
        XCTAssertFalse(headerSource.contains("appearancePreference"))
        XCTAssertFalse(headerSource.contains(".pickerStyle(.segmented)"))
    }

    func testProjectBoardHeaderKeepsActionsInSynchronousSwiftUILayout() throws {
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let headerStart = try XCTUnwrap(boardSource.range(of: "private var projectBoardHeaderBar: some View"))
        let toggleStart = try XCTUnwrap(boardSource.range(of: "private func toggleSidebarVisibility()"))
        let headerSource = String(boardSource[headerStart.lowerBound..<toggleStart.lowerBound])
        let toolbarStart = try XCTUnwrap(boardSource.range(of: ".toolbar {"))
        let toolbarRemovalStart = try XCTUnwrap(boardSource.range(of: ".toolbar(removing: .sidebarToggle)"))
        let toolbarSource = String(boardSource[toolbarStart.lowerBound..<toolbarRemovalStart.lowerBound])

        XCTAssertTrue(boardSource.contains("projectBoardHeaderBar"))
        XCTAssertTrue(headerSource.contains("HStack(spacing: 8)"))
        XCTAssertTrue(headerSource.contains("Spacer(minLength: 16)"))
        XCTAssertTrue(headerSource.contains("Label(\"Integrations\", systemImage: \"arrow.left.arrow.right\")"))
        XCTAssertTrue(headerSource.contains("Label(\"Review Task Automation\", systemImage: \"sparkles\")"))
        XCTAssertTrue(headerSource.contains("Label(\"Voice Command\", systemImage: \"mic\")"))
        XCTAssertTrue(headerSource.contains("Label(\"Settings\", systemImage: \"gearshape\")"))
        XCTAssertTrue(headerSource.contains("Label(\"Terminal\", systemImage: \"terminal\")"))
        XCTAssertTrue(headerSource.contains(".accessibilityIdentifier(\"project-board-header-bar\")"))
        XCTAssertTrue(headerSource.contains(".buttonStyle(.bordered)"))
        XCTAssertTrue(headerSource.contains(".controlSize(.small)"))
        XCTAssertTrue(headerSource.contains("minHeight: ProjectBoardLayoutMetrics.headerHeight"))
        XCTAssertTrue(headerSource.contains("maxHeight: ProjectBoardLayoutMetrics.headerHeight"))
        XCTAssertEqual(toolbarSource.components(separatedBy: "ToolbarItem(placement: .primaryAction)").count - 1, 0)
        XCTAssertFalse(toolbarSource.contains("ToolbarItemGroup(placement:"))
        XCTAssertFalse(toolbarSource.contains("project-board-integrations-menu"))
        XCTAssertFalse(toolbarSource.contains("project-board-voice-command"))
        XCTAssertFalse(toolbarSource.contains("project-board-settings-link"))
        XCTAssertFalse(toolbarSource.contains("project-board-terminal-toggle"))
        XCTAssertTrue(boardSource.contains("reconcileProjectBoardToolbarLayout(allowRetryIfToolbarMissing:"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"project-board-integrations-menu\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"project-board-task-auto-execution-review\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"project-board-voice-command\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"project-board-settings-link\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"project-board-terminal-toggle\")"))
        XCTAssertTrue(boardSource.contains("private extension NSToolbar"))
        XCTAssertTrue(boardSource.contains("var projectBoardLayoutItems: [ProjectBoardToolbarLayoutPolicy.Item]"))
        XCTAssertTrue(boardSource.contains("accessibilityIdentifier: view?.accessibilityIdentifier()"))
        XCTAssertFalse(boardSource.contains("private struct ProjectBoardToolbarIcon: View"))
        XCTAssertFalse(boardSource.contains("toolbar.displayMode = .iconOnly"))
        XCTAssertFalse(boardSource.contains("toolbar.allowsUserCustomization = false"))
    }

    func testProjectBoardHeaderPreparesConfiguredTaskAutomationReview() throws {
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let appSource = try readAppShellSource()

        XCTAssertTrue(boardSource.contains("let taskAutomationSettings: () -> TaskAutoExecutionSettings"))
        XCTAssertTrue(boardSource.contains("let appSettings: () -> AppSettings"))
        XCTAssertTrue(boardSource.contains("taskAutomationSettings: @escaping () -> TaskAutoExecutionSettings"))
        XCTAssertTrue(boardSource.contains("appSettings: @escaping () -> AppSettings"))
        XCTAssertTrue(boardSource.contains("viewModel.prepareTaskAutomationReview(settings: taskAutomationSettings())"))
        XCTAssertTrue(boardSource.contains("viewModel.scheduleMissedTaskDailyFollowUp(settings: appSettings())"))
        XCTAssertTrue(boardSource.contains(".help(\"Prepares review-only task automation from the configured priority, due-date, cadence, and daily budget settings\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityHint(\"Prepares review-only task automation from the configured priority, due-date, cadence, and daily budget settings.\")"))
        XCTAssertTrue(appSource.contains("@StateObject private var settingsViewModel: AppSettingsViewModel"))
        XCTAssertTrue(appSource.contains("AppRuntimeFactory.makeAppSettingsViewModel(refreshProviderSecretStatusesOnInit: false)"))
        XCTAssertTrue(appSource.contains("taskAutomationSettings: { settingsViewModel.settings.taskAutoExecution }"))
        XCTAssertTrue(appSource.contains("appSettings: { settingsViewModel.settings }"))
    }

    func testTaskInspectorApprovedExecutionReceiptIsAccessibleAndRedacted() throws {
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")

        XCTAssertTrue(boardSource.contains("private var latestApprovedExecutionReceipt: ApprovedAutomationExecutionReceipt?"))
        XCTAssertTrue(boardSource.contains("viewModel.approvedAutomationExecutionReceipts.last { $0.taskID == task.id }"))
        XCTAssertTrue(boardSource.contains("approvedExecutionReceiptView(receipt)"))
        XCTAssertTrue(boardSource.contains("Text(\"Task: \\(receipt.redactedTaskTitle)\")"))
        XCTAssertTrue(boardSource.contains("Text(\"Reviewed detail: \\(receipt.redactedTaskDetail)\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"approved-execution-receipt\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityLabel(\"Approved execution receipt\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityValue(approvedExecutionReceiptAccessibilityValue(receipt))"))
        XCTAssertTrue(boardSource.contains(".accessibilityHint(\"Shows the redacted task title and detail that were approved and executed.\")"))
        XCTAssertTrue(boardSource.contains("\"Task \\(receipt.redactedTaskTitle)\""))
        XCTAssertTrue(boardSource.contains("\"Reviewed detail \\(receipt.redactedTaskDetail)\""))
    }

    func testDoneWorkflowShowsRecentAIReceiptsWithoutRawReceiptFields() throws {
        let workflowSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectWorkflowDoneView.swift")
        let historySource = try readPackageFile("Sources/SoloPMCore/App/ExecutionReceiptHistory.swift")

        XCTAssertTrue(workflowSource.contains("viewModel.executionReceiptHistorySnapshot"))
        XCTAssertTrue(workflowSource.contains("viewModel.executionUsageMeterSnapshot"))
        XCTAssertTrue(workflowSource.contains("AI Usage Meter"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"ai-usage-meter-summary\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"ai-usage-meter-scope\")"))
        XCTAssertTrue(workflowSource.contains("appSettings.managedAIBilling"))
        XCTAssertTrue(workflowSource.contains("usageThresholdRows(for: snapshot)"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"ai-usage-threshold-row-\\(row.scope.rawValue)\")"))
        XCTAssertTrue(workflowSource.contains("Latest Month"))
        XCTAssertTrue(workflowSource.contains("row.summary.costLabel"))
        XCTAssertTrue(workflowSource.contains("Recent AI Receipts"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"recent-ai-receipts\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"execution-receipt-search-field\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"execution-receipt-export-button\")"))
        XCTAssertTrue(workflowSource.contains(".fileExporter("))
        XCTAssertTrue(workflowSource.contains("isExportingExecutionReceipts"))
        XCTAssertTrue(workflowSource.contains("ExecutionReceiptHistoryFileDocument"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"execution-receipt-row-\\(row.id)\")"))
        XCTAssertTrue(workflowSource.contains("ExecutionReceiptHistoryRowView"))
        XCTAssertTrue(workflowSource.contains("viewModel.prepareExecutionReceiptHistoryExport()"))
        let receiptHistoryViewTail = try XCTUnwrap(
            workflowSource.components(separatedBy: "struct ExecutionReceiptHistoryRowView").last
        )
        XCTAssertTrue(historySource.contains("displayDigest(for: receipt)"))
        XCTAssertTrue(historySource.contains("Receipt Digest: %@"))
        XCTAssertFalse(receiptHistoryViewTail.contains(".inputPreview"))
        XCTAssertFalse(receiptHistoryViewTail.contains(".sourceLinks"))
        XCTAssertFalse(receiptHistoryViewTail.contains(".actions"))
        XCTAssertFalse(receiptHistoryViewTail.contains("receipt.id"))
        XCTAssertFalse(receiptHistoryViewTail.contains("receipt.runID"))
    }

    func testInspectorsShowScopedAIReceiptsWithoutRawReceiptFields() throws {
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let workflowSource = try readProjectWorkflowSources()

        XCTAssertTrue(boardSource.contains("Section(\"Project AI Receipts\")"))
        XCTAssertTrue(boardSource.contains("Section(\"Task AI Receipts\")"))
        XCTAssertTrue(boardSource.contains("viewModel.executionReceiptHistorySnapshot(forProjectID: project.id)"))
        XCTAssertTrue(boardSource.contains("viewModel.executionReceiptHistorySnapshot(forTaskID: task.id)"))
        XCTAssertTrue(boardSource.contains("accessibilityIdentifier: \"project-execution-receipts\""))
        XCTAssertTrue(boardSource.contains("accessibilityIdentifier: \"task-execution-receipts\""))
        XCTAssertTrue(boardSource.contains("ExecutionReceiptHistoryInspectorSection"))
        XCTAssertTrue(boardSource.contains("ExecutionReceiptHistoryRowView(row: row)"))
        XCTAssertTrue(workflowSource.contains("struct ExecutionReceiptHistoryRowView: View"))

        let inspectorReceiptSection = try sourceBlock(
            in: boardSource,
            from: "private struct ExecutionReceiptHistoryInspectorSection",
            to: "private struct InspectorMetadataPill"
        )
        XCTAssertFalse(inspectorReceiptSection.contains(".inputPreview"))
        XCTAssertFalse(inspectorReceiptSection.contains(".sourceLinks"))
        XCTAssertFalse(inspectorReceiptSection.contains(".actions"))
        XCTAssertFalse(inspectorReceiptSection.contains("receipt.id"))
    }

    func testTaskInspectorShowsDocumentSourceReviewForAutomationDrafts() throws {
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")

        XCTAssertTrue(boardSource.contains("viewModel.taskAutomationDocumentDeliverableReviews"))
        XCTAssertTrue(boardSource.contains("documentDeliverableReviewView"))
        XCTAssertTrue(boardSource.contains("Document deliverables"))
        XCTAssertTrue(boardSource.contains("Source documents"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"task-auto-execution-document-deliverables\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"task-auto-execution-document-source-\\(source.id)\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityLabel(\"Automation document source\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityValue(documentSourceAccessibilityValue(source))"))
    }

    func testProjectBoardLayoutMetricsGuardPrimaryDimensionsAndLongLabels() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")

        XCTAssertTrue(source.contains("private enum ProjectBoardLayoutMetrics"))
        XCTAssertTrue(source.contains("static let headerHeight: CGFloat = 44"))
        XCTAssertTrue(source.contains("static let terminalPanelMinHeight: CGFloat = 220"))
        XCTAssertTrue(source.contains("static let terminalPanelIdealHeight: CGFloat = 280"))
        XCTAssertTrue(source.contains("static let terminalPanelMaxHeight: CGFloat = 360"))
        XCTAssertTrue(source.contains("static let portfolioCardMinHeight: CGFloat = 230"))
        XCTAssertTrue(source.contains("static let overviewPanelMinHeight: CGFloat = 170"))
        XCTAssertTrue(source.contains("static let displayModePickerWidth: CGFloat = 252"))
        XCTAssertTrue(source.contains("static let boardColumnWidth: CGFloat = 244"))
        XCTAssertTrue(source.contains("static let emptyColumnMinHeight: CGFloat = 82"))
        XCTAssertTrue(source.contains("static let inlinePriorityPickerWidth: CGFloat = 112"))
        XCTAssertTrue(source.contains("static let taskMetadataChipMinWidth: CGFloat = 64"))
        XCTAssertTrue(source.contains("static let taskMetadataChipMinHeight: CGFloat = 24"))
        XCTAssertTrue(source.contains("static let taskStatusRailWidth: CGFloat = 4"))
        XCTAssertTrue(source.contains("static let taskStatusRailHeight: CGFloat = 44"))
        XCTAssertTrue(source.contains("Project Board keeps these metrics local"))

        XCTAssertTrue(source.contains("minHeight: ProjectBoardLayoutMetrics.headerHeight"))
        XCTAssertTrue(source.contains("maxHeight: ProjectBoardLayoutMetrics.headerHeight"))
        XCTAssertTrue(source.contains("minHeight: ProjectBoardLayoutMetrics.terminalPanelMinHeight"))
        XCTAssertTrue(source.contains("idealHeight: ProjectBoardLayoutMetrics.terminalPanelIdealHeight"))
        XCTAssertTrue(source.contains("maxHeight: ProjectBoardLayoutMetrics.terminalPanelMaxHeight"))
        XCTAssertTrue(source.contains(".frame(minHeight: ProjectBoardLayoutMetrics.portfolioCardMinHeight, alignment: .topLeading)"))
        XCTAssertTrue(source.contains(".frame(maxWidth: .infinity, minHeight: ProjectBoardLayoutMetrics.overviewPanelMinHeight, alignment: .topLeading)"))
        XCTAssertTrue(source.contains(".frame(width: ProjectBoardLayoutMetrics.displayModePickerWidth)"))
        XCTAssertTrue(source.contains(".frame(width: ProjectBoardLayoutMetrics.boardColumnWidth, alignment: .topLeading)"))
        XCTAssertTrue(source.contains(".frame(maxWidth: .infinity, minHeight: ProjectBoardLayoutMetrics.emptyColumnMinHeight, alignment: .topLeading)"))
        XCTAssertTrue(source.contains(".frame(width: ProjectBoardLayoutMetrics.inlinePriorityPickerWidth)"))
        XCTAssertTrue(source.contains(".frame(width: ProjectBoardLayoutMetrics.taskStatusRailWidth)"))
        XCTAssertTrue(source.contains(".frame(height: ProjectBoardLayoutMetrics.taskStatusRailHeight)"))
        XCTAssertTrue(source.contains("minWidth: ProjectBoardLayoutMetrics.taskMetadataChipMinWidth"))
        XCTAssertTrue(source.contains("minHeight: ProjectBoardLayoutMetrics.taskMetadataChipMinHeight"))
        XCTAssertTrue(source.contains(".minimumScaleFactor(0.82)"))
        XCTAssertTrue(source.contains(".help(task.title)"))
        XCTAssertTrue(source.contains(".help(task.detail)"))
    }

    func testProjectBoardLongContentFixtureMapsToResponsiveGuards() throws {
        let fixture = try readPackageFile("Tests/SoloPMCoreTests/Fixtures/ProjectBoard/long-content-layout.json")
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")

        XCTAssertTrue(fixture.contains("\"longJapaneseProjectTitle\""))
        XCTAssertTrue(fixture.contains("長い日本語のプロジェクト名"))
        XCTAssertTrue(fixture.contains("\"longEnglishTaskTitle\""))
        XCTAssertTrue(fixture.contains("Coordinate multi-window Project Board release readiness"))
        XCTAssertTrue(fixture.contains("\"emptyState\""))
        XCTAssertTrue(fixture.contains("\"No tasks\""))
        XCTAssertTrue(fixture.contains("\"errorState\""))
        XCTAssertTrue(fixture.contains("\"Project Board Unavailable\""))

        XCTAssertTrue(source.contains("Text(project.title)"))
        XCTAssertTrue(source.contains(".lineLimit(1)"))
        XCTAssertTrue(source.contains(".truncationMode(.tail)"))
        XCTAssertTrue(source.contains(".help(project.title)"))
        XCTAssertTrue(source.contains("Text(task.title)"))
        XCTAssertTrue(source.contains(".help(task.title)"))
        XCTAssertTrue(source.contains("Text(task.detail)"))
        XCTAssertTrue(source.contains(".help(task.detail)"))
        XCTAssertTrue(source.contains("ContentUnavailableView(\n                            \"Project Board Unavailable\""))
        XCTAssertTrue(source.contains("ContentUnavailableView(\"No Projects\""))
        XCTAssertTrue(source.contains("Text(\"No tasks\")"))
        XCTAssertTrue(source.contains("ProjectBoardLayoutMetrics.emptyColumnMinHeight"))
    }

    func testProjectBoardStateRestorationFixtureCoversLaunchMatrix() throws {
        let fixture = try readPackageFile("Tests/SoloPMCoreTests/Fixtures/ProjectBoard/state-restoration-matrix.json")
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let persistenceSource = try readPackageFile("Sources/SoloPMCore/App/ProjectBoardSelectionPersistence.swift")
        let layoutSmoke = try readPackageFile("script/check_layout_stability_smoke.sh")
        let crudSmoke = try readPackageFile("script/check_runtime_accessible_crud_smoke.sh")

        XCTAssertTrue(fixture.contains("\"emptyDatabase\""))
        XCTAssertTrue(fixture.contains("\"normalSeededDatabase\""))
        XCTAssertTrue(fixture.contains("\"deletedSavedProject\""))
        XCTAssertTrue(fixture.contains("\"manyProjectsAndTasks\""))
        XCTAssertTrue(fixture.contains("\"savedSelection\": \"project:42\""))
        XCTAssertTrue(fixture.contains("\"expectedDestination\": \"today\""))
        XCTAssertTrue(fixture.contains("\"envOverride\": \"project:42\""))
        XCTAssertTrue(fixture.contains("\"projectCount\": 24"))
        XCTAssertTrue(fixture.contains("\"tasksPerProject\": 12"))
        XCTAssertTrue(fixture.contains("SOLOPM_DATABASE_PATH"))
        XCTAssertTrue(fixture.contains("SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION"))
        XCTAssertTrue(fixture.contains("SOLOPM_LAYOUT_STABILITY_WINDOW_MIN_WIDTH"))
        XCTAssertTrue(fixture.contains("SOLOPM_LAYOUT_STABILITY_WINDOW_STANDARD_WIDTH"))
        XCTAssertTrue(fixture.contains("SOLOPM_LAYOUT_STABILITY_WINDOW_WIDE_WIDTH"))

        XCTAssertTrue(boardSource.contains("restoreSelectedDestinationIfNeeded()"))
        XCTAssertTrue(boardSource.contains("ProjectBoardSelectionPersistence.destination("))
        XCTAssertTrue(boardSource.contains("persistSelectedDestination(destination)"))
        XCTAssertTrue(boardSource.contains("applySelectedDestination(destination)"))
        XCTAssertTrue(persistenceSource.contains("Saved app state can outlive a project row"))
        XCTAssertTrue(persistenceSource.contains("availableProjects.contains(where: { $0.id == projectID }) else"))
        XCTAssertTrue(layoutSmoke.contains("SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION=\"project:$layout_project_id\""))
        XCTAssertTrue(crudSmoke.contains("SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION=\"project:$seed_project_id\""))
        XCTAssertTrue(crudSmoke.contains("SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION=\"projects\""))
        XCTAssertTrue(layoutSmoke.contains("AX_HELPERS=\"${AX_HELPERS:-$ROOT_DIR/script/ui_accessibility_smoke_helpers.sh}\""))
        XCTAssertTrue(layoutSmoke.contains("source \"$AX_HELPERS\""))
        XCTAssertTrue(crudSmoke.contains("AX_HELPERS=\"${AX_HELPERS:-$ROOT_DIR/script/ui_accessibility_smoke_helpers.sh}\""))
        XCTAssertTrue(crudSmoke.contains("source \"$AX_HELPERS\""))
    }

    func testProjectBoardToolbarDisplayModeOnlyAllowsIconAndTextOrIconOnly() throws {
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")

        XCTAssertTrue(boardSource.contains("projectBoardSupportedToolbarDisplayMode(for:"))
        XCTAssertTrue(boardSource.contains("enforceProjectBoardSupportedToolbarDisplayMode("))
        XCTAssertTrue(boardSource.contains("case .iconAndLabel:"))
        XCTAssertTrue(boardSource.contains("case .iconOnly:"))
        XCTAssertTrue(boardSource.contains("case .labelOnly, .default:"))
        XCTAssertTrue(boardSource.contains("return .iconAndLabel"))
        XCTAssertTrue(boardSource.contains("toolbar.displayMode = supportedDisplayMode"))
        XCTAssertTrue(boardSource.contains("enforceProjectBoardSupportedToolbarDisplayMode(toolbar)"))
        XCTAssertTrue(boardSource.contains("installToolbarDisplayModeMenuPruningIfNeeded()"))
        XCTAssertTrue(boardSource.contains("NSMenu.didBeginTrackingNotification"))
        XCTAssertTrue(boardSource.contains("pruneUnsupportedProjectBoardToolbarDisplayModeItems(from:"))
        XCTAssertTrue(boardSource.contains("isProjectBoardToolbarDisplayModeMenu("))
        XCTAssertTrue(boardSource.contains("\"Icon and Text\""))
        XCTAssertTrue(boardSource.contains("\"Icon Only\""))
        XCTAssertTrue(boardSource.contains("\"アイコンとテキスト\""))
        XCTAssertTrue(boardSource.contains("\"アイコンのみ\""))
        XCTAssertTrue(boardSource.contains("\"Text Only\""))
        XCTAssertTrue(boardSource.contains("\"テキストのみ\""))
        XCTAssertFalse(boardSource.contains("toolbar.displayMode = .labelOnly"))
    }

    func testProjectBoardHeaderIsSharedAndColumnsUseSynchronizedBounds() throws {
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
        let detailStart = try XCTUnwrap(boardSource.range(of: "} detail: {"))
        let inspectorStart = try XCTUnwrap(boardSource.range(of: ".inspector(isPresented: inspectorBinding)"))
        let toolbarStart = try XCTUnwrap(boardSource.range(of: ".toolbar {"))

        XCTAssertGreaterThan(toolbarStart.lowerBound, inspectorStart.lowerBound)
        XCTAssertTrue(boardSource.contains("enum ProjectBoardWindowMetrics"))
        XCTAssertTrue(boardSource.contains("static let defaultWidth: CGFloat = 1_180"))
        XCTAssertTrue(boardSource.contains("static let minWidth: CGFloat = 960"))
        XCTAssertTrue(boardSource.contains(".frame(\n            minWidth: ProjectBoardWindowMetrics.minWidth,\n            minHeight: ProjectBoardWindowMetrics.minHeight"))
        XCTAssertTrue(appSource.contains(".defaultSize(width: ProjectBoardWindowMetrics.defaultWidth, height: ProjectBoardWindowMetrics.defaultHeight)"))
        XCTAssertEqual(boardSource.components(separatedBy: ".navigationTitle(\"SoloPM\")").count - 1, 1)
        XCTAssertEqual(boardSource.components(separatedBy: ".projectBoardSynchronizedColumnBounds()").count - 1, 2)
        XCTAssertFalse(boardSource.contains(".navigationSplitViewColumnWidth("))
        XCTAssertFalse(boardSource.contains("ProjectBoardLayout.sidebarColumnWidth"))
        XCTAssertEqual(boardSource.components(separatedBy: ".id(toolbarLayoutRefreshToken)").count - 1, 2)
        XCTAssertTrue(boardSource.contains("@State private var toolbarLayoutRefreshToken = 0"))
        XCTAssertTrue(boardSource.contains("private struct ProjectBoardSynchronizedColumnBounds: ViewModifier"))
        XCTAssertTrue(boardSource.contains("ProjectBoardToolbarLayoutPolicy.nativeSidebarRemovalIndexes("))
        XCTAssertTrue(boardSource.contains("sidebar item and tracking separator"))
        XCTAssertTrue(boardSource.contains(".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)"))
        XCTAssertTrue(boardSource.contains("refreshProjectBoardColumnsAfterToolbarDisplayModeChange()"))
        XCTAssertTrue(boardSource.contains("toolbarLayoutRefreshToken += 1"))
        XCTAssertTrue(boardSource.contains("toolbar.observe(\\.displayMode, options: [.new])"))
        XCTAssertTrue(boardSource.contains("reconcileProjectBoardToolbarLayout("))
        XCTAssertTrue(boardSource.contains("reconcileToolbarDisplayModeChange()"))
        XCTAssertTrue(boardSource.contains("MainActor.assumeIsolated"))
        XCTAssertTrue(boardSource.contains("observedToolbarDisplayMode != toolbar.displayMode"))
        XCTAssertTrue(boardSource.contains("NSAnimationContext.runAnimationGroup"))
        XCTAssertTrue(boardSource.contains("context.duration = 0"))
        XCTAssertTrue(boardSource.contains("context.allowsImplicitAnimation = false"))
        XCTAssertTrue(boardSource.contains("window?.contentView?.needsLayout = true"))
        XCTAssertTrue(boardSource.contains("window?.contentView?.needsDisplay = true"))
        XCTAssertTrue(boardSource.contains("notifyColumnsWhenToolbarAlreadyStable"))
        XCTAssertFalse(boardSource.contains("window?.contentView?.layoutSubtreeIfNeeded()"))
        XCTAssertFalse(boardSource.contains("window?.displayIfNeeded()"))
        XCTAssertTrue(boardSource.contains("withTransaction(transaction)"))
        XCTAssertTrue(boardSource.contains("transaction.disablesAnimations = true"))

        let detailColumnSource = String(boardSource[detailStart.lowerBound..<inspectorStart.lowerBound])
        XCTAssertTrue(detailColumnSource.contains(".projectBoardSynchronizedColumnBounds()"))
    }

    func testProjectBoardHeaderLayoutBridgeAvoidsDelayedCorrectionDuringStateChanges() throws {
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let bridgeStart = try XCTUnwrap(boardSource.range(of: "private final class ProjectBoardToolbarLayoutBridgeView"))
        let appKitEnd = try XCTUnwrap(boardSource.range(of: "#else", range: bridgeStart.upperBound..<boardSource.endIndex))
        let bridgeSource = String(boardSource[bridgeStart.lowerBound..<appKitEnd.lowerBound])

        XCTAssertTrue(bridgeSource.contains("reconcileProjectBoardToolbarLayout(allowRetryIfToolbarMissing: true)"))
        XCTAssertTrue(bridgeSource.contains("reconcileProjectBoardToolbarLayout(allowRetryIfToolbarMissing: false)"))
        XCTAssertTrue(bridgeSource.contains("override func layout()"))
        XCTAssertTrue(bridgeSource.contains("isPerformingToolbarLayoutPass"))
        XCTAssertTrue(bridgeSource.contains("scheduleInitialProjectBoardToolbarLayoutStabilizationIfNeeded()"))
        XCTAssertTrue(bridgeSource.contains("didScheduleInitialToolbarLayoutStabilization"))
        XCTAssertTrue(bridgeSource.contains("retrySynchronousProjectBoardToolbarLayoutPass(remainingAttempts:"))
        XCTAssertFalse(bridgeSource.contains("scheduleToolbarTrailingAlignment()"))
        XCTAssertFalse(bridgeSource.contains("scheduleToolbarLayoutRefreshIfDisplayModeChanged()"))
    }

    func testRuntimeDiagnosticsExposeOnlyStablePublicIntegerCounters() throws {
        let coreSource = try readPackageFile("Sources/SoloPMCore/App/ProjectBoard.swift")
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let bridgeStart = try XCTUnwrap(boardSource.range(of: "private final class ProjectBoardToolbarLayoutBridgeView"))
        let appKitEnd = try XCTUnwrap(boardSource.range(of: "#else", range: bridgeStart.upperBound..<boardSource.endIndex))
        let bridgeSource = String(boardSource[bridgeStart.lowerBound..<appKitEnd.lowerBound])

        XCTAssertTrue(coreSource.contains("Logger(subsystem: \"dev.solopm.app\""))
        XCTAssertTrue(coreSource.contains("solopm.dailyPlanningPreview.buildCount="))
        XCTAssertTrue(coreSource.contains("privacy: .public"))
        XCTAssertTrue(coreSource.contains("projectBoardRuntimeDiagnosticLogger.notice"))
        XCTAssertTrue(coreSource.contains("dailyPlanningReviewPreviewBuildCount += 1"))
        XCTAssertTrue(coreSource.contains("dailyPlanningReviewPreviewCache.review(for: cacheKey) {"))

        XCTAssertTrue(bridgeSource.contains("Logger(subsystem: \"dev.solopm.app\""))
        XCTAssertTrue(bridgeSource.contains("solopm.toolbar.layout.maxDepth="))
        XCTAssertTrue(bridgeSource.contains("privacy: .public"))
        XCTAssertTrue(bridgeSource.contains("runtimeDiagnosticLogger.notice"))
        XCTAssertTrue(bridgeSource.contains("private var toolbarLayoutReconcileDepth = 0"))
        XCTAssertTrue(bridgeSource.contains("private var toolbarLayoutMaxDepth = 0"))
        XCTAssertTrue(bridgeSource.contains("toolbarLayoutReconcileDepth += 1"))
        XCTAssertTrue(bridgeSource.contains("toolbarLayoutMaxDepth = max(toolbarLayoutMaxDepth, toolbarLayoutReconcileDepth)"))
        XCTAssertTrue(bridgeSource.contains("defer { toolbarLayoutReconcileDepth -= 1 }"))
        XCTAssertTrue(bridgeSource.contains("guard isPerformingToolbarLayoutPass == false else"))
        XCTAssertTrue(bridgeSource.contains("guard toolbarLayoutReconcileDepth == 1 else"))
    }

    func testSynchronousUIMutationPolicyADRDefinesLayoutSensitiveBoundaries() throws {
        let adr = try readPackageFile("docs/adr/0009-synchronous-ui-mutation-policy.md")

        XCTAssertTrue(adr.contains("Status: Accepted"))
        XCTAssertTrue(adr.contains("Sidebar toggle"))
        XCTAssertTrue(adr.contains("toolbar display mode"))
        XCTAssertTrue(adr.contains("split view visibility"))
        XCTAssertTrue(adr.contains("theme switching"))
        XCTAssertTrue(adr.contains("inspector open/close"))
        XCTAssertTrue(adr.contains("project selection"))
        XCTAssertTrue(adr.contains("DispatchQueue.main.asyncAfter"))
        XCTAssertTrue(adr.contains("Timer"))
        XCTAssertTrue(adr.contains("Transaction.disablesAnimations = true"))
        XCTAssertTrue(adr.contains("does not call `layoutSubtreeIfNeeded` or `displayIfNeeded`"))
        XCTAssertTrue(adr.contains("layout-attachment-delay:"))
        XCTAssertTrue(adr.contains("script/check_layout_stability_smoke.sh"))
        XCTAssertTrue(adr.contains("script/check_project_board_header_layout_smoke.sh"))
        XCTAssertTrue(adr.contains("AppExperienceSourceTests"))
    }

    func testViewLayoutDelaysRemainLimitedToInitialToolbarAttachmentPolicyException() throws {
        let viewFiles = try allSwiftFiles(under: "Sources/SoloPMApp/Views")
        var delayedCorrections: [String] = []
        var timerCorrections: [String] = []

        for fileURL in viewFiles {
            let relativePath = relativePackagePath(for: fileURL)
            let lines = try String(contentsOf: fileURL, encoding: .utf8)
                .components(separatedBy: .newlines)

            for (index, line) in lines.enumerated() {
                let location = "\(relativePath):\(index + 1)"
                if line.contains("DispatchQueue.main.asyncAfter") {
                    delayedCorrections.append(location)
                }
                if line.contains("Timer.") || line.contains("Timer(") {
                    timerCorrections.append(location)
                }
            }
        }

        XCTAssertTrue(timerCorrections.isEmpty, timerCorrections.joined(separator: "\n"))
        XCTAssertEqual(delayedCorrections.count, 2, delayedCorrections.joined(separator: "\n"))
        XCTAssertTrue(
            delayedCorrections.allSatisfy { $0.hasPrefix("Sources/SoloPMApp/Views/ProjectBoardView.swift:") },
            delayedCorrections.joined(separator: "\n")
        )

        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let bridgeStart = try XCTUnwrap(boardSource.range(of: "private final class ProjectBoardToolbarLayoutBridgeView"))
        let appKitEnd = try XCTUnwrap(boardSource.range(of: "#else", range: bridgeStart.upperBound..<boardSource.endIndex))
        let bridgeSource = String(boardSource[bridgeStart.lowerBound..<appKitEnd.lowerBound])

        XCTAssertEqual(bridgeSource.components(separatedBy: "DispatchQueue.main.asyncAfter").count - 1, 2)
        XCTAssertEqual(bridgeSource.components(separatedBy: "layout-attachment-delay:").count - 1, 2)
        XCTAssertTrue(bridgeSource.contains("initial AppKit toolbar attachment gap"))
        XCTAssertTrue(bridgeSource.contains("mutate the toolbar synchronously without forcing a full view-tree layout"))
    }

    func testLayoutSensitiveStateMutationsUseSynchronousTransactionPolicy() throws {
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let toggleStart = try XCTUnwrap(boardSource.range(of: "private func toggleSidebarVisibility()"))
        let toolbarBridgeStart = try XCTUnwrap(boardSource.range(of: "private func refreshProjectBoardColumnsAfterToolbarDisplayModeChange()"))
        let toggleSource = String(boardSource[toggleStart.lowerBound..<toolbarBridgeStart.lowerBound])

        XCTAssertTrue(toggleSource.contains("var transaction = Transaction()"))
        XCTAssertTrue(toggleSource.contains("transaction.disablesAnimations = true"))
        XCTAssertTrue(toggleSource.contains("withTransaction(transaction)"))
        XCTAssertTrue(toggleSource.contains("columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly"))
        XCTAssertFalse(toggleSource.contains("DispatchQueue.main.async"))
        XCTAssertFalse(toggleSource.contains("withAnimation"))

        let adr = try readPackageFile("docs/adr/0009-synchronous-ui-mutation-policy.md")
        XCTAssertTrue(adr.contains("SwiftUI state mutationは最小scopeのtransaction"))
        XCTAssertTrue(adr.contains("AppKit interopはProjectBoardToolbarLayoutBridgeView"))
    }

    func testProjectBoardReplacesDefaultSidebarToggleWithShortAdaptiveToolbarItem() throws {
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let toggleStart = try XCTUnwrap(boardSource.range(of: "private func toggleSidebarVisibility()"))
        let toolbarBridgeStart = try XCTUnwrap(boardSource.range(of: "private func refreshProjectBoardColumnsAfterToolbarDisplayModeChange()"))
        let toggleSource = String(boardSource[toggleStart.lowerBound..<toolbarBridgeStart.lowerBound])

        XCTAssertTrue(boardSource.contains("@State private var columnVisibility: NavigationSplitViewVisibility = .all"))
        XCTAssertTrue(boardSource.contains("NavigationSplitView(columnVisibility: $columnVisibility)"))
        XCTAssertTrue(boardSource.contains("ToolbarItem(placement: .navigation)"))
        XCTAssertFalse(boardSource.contains("ToolbarItem(placement: .primaryAction)"))
        XCTAssertTrue(boardSource.contains("Label(\"Sidebar\", systemImage: \"sidebar.left\")"))
        XCTAssertTrue(boardSource.contains(".toolbar(removing: .sidebarToggle)"))
        XCTAssertTrue(boardSource.contains("ProjectBoardToolbarLayoutBridge("))
        XCTAssertTrue(boardSource.contains("columnVisibility: columnVisibility"))
        XCTAssertTrue(boardSource.contains("onToolbarLayoutChanged: refreshProjectBoardColumnsAfterToolbarDisplayModeChange"))
        XCTAssertTrue(boardSource.contains("let columnVisibility: NavigationSplitViewVisibility"))
        XCTAssertTrue(boardSource.contains("let onToolbarLayoutChanged: () -> Void"))
        XCTAssertTrue(boardSource.contains("#selector(NSSplitViewController.toggleSidebar(_:))"))
        XCTAssertTrue(boardSource.contains("identifierRawValue: itemIdentifier.rawValue"))
        XCTAssertTrue(boardSource.contains("retrySynchronousProjectBoardToolbarLayoutPass(remainingAttempts:"))
        XCTAssertTrue(toggleSource.contains("var transaction = Transaction()"))
        XCTAssertTrue(toggleSource.contains("transaction.disablesAnimations = true"))
        XCTAssertTrue(toggleSource.contains("withTransaction(transaction)"))
        XCTAssertTrue(toggleSource.contains("columnVisibility == .detailOnly ? .all : .detailOnly"))
        XCTAssertFalse(toggleSource.contains("withAnimation"))
        XCTAssertFalse(toggleSource.contains("animation:"))
        XCTAssertFalse(boardSource.contains("toolbar.displayMode = .iconOnly"))
        XCTAssertFalse(boardSource.contains("toolbar.allowsUserCustomization = false"))
    }

    func testProjectBoardHeaderLayoutRuntimeSmokeCoversSidebarToggleAndActionPositions() throws {
        let script = try readPackageFile("script/check_project_board_header_layout_smoke.sh")

        XCTAssertTrue(script.contains("./script/build_and_run.sh --build-only"))
        XCTAssertTrue(script.contains("./script/prepare_voiceover_review_candidate.sh --database \"$HEADER_LAYOUT_DATABASE_PATH\" --no-launch --skip-build"))
        XCTAssertTrue(script.contains("SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION=\"project:$header_layout_project_id\""))
        XCTAssertTrue(script.contains("SOLOPM_HEADER_LAYOUT_DATABASE_PATH"))
        XCTAssertTrue(script.contains("project-board-sidebar-toggle"))
        XCTAssertTrue(script.contains("project-board-integrations-menu"))
        XCTAssertTrue(script.contains("project-board-voice-command"))
        XCTAssertTrue(script.contains("project-board-settings-link"))
        XCTAssertTrue(script.contains("project-board-terminal-toggle"))
        XCTAssertTrue(script.contains("project-display-mode-overview"))
        XCTAssertTrue(script.contains("project-display-mode-board"))
        XCTAssertTrue(script.contains("project-display-mode-list"))
        XCTAssertTrue(script.contains("ensure_project_detail_visible"))
        XCTAssertTrue(script.contains("wait_for_project_detail_visible"))
        XCTAssertTrue(script.contains("assert_action_buttons_are_trailing"))
        XCTAssertTrue(script.contains("click_sidebar_toggle"))
        XCTAssertTrue(script.contains("set_toolbar_display_mode"))
        XCTAssertTrue(script.contains("click_project_display_mode"))
        XCTAssertTrue(script.contains("click_inspector_close"))
        XCTAssertTrue(script.contains("click_task_card_open_details"))
        XCTAssertTrue(script.contains("click_terminal_toggle"))
        XCTAssertTrue(script.contains("click_terminal_close"))
        XCTAssertTrue(script.contains("seed_header_layout_selection_project"))
        XCTAssertTrue(script.contains("click_project_sidebar_row"))
        XCTAssertTrue(script.contains("click_ax_identifier_center \"project-sidebar-row-$project_id\""))
        XCTAssertTrue(script.contains("Header Layout Selection Project"))
        XCTAssertTrue(script.contains("wait_for_ax_identifier_present \"task-inspector\""))
        XCTAssertTrue(script.contains("wait_for_ax_identifier_absent \"project-inspector\""))
        XCTAssertTrue(script.contains("wait_for_ax_identifier_present \"embedded-terminal-close\""))
        XCTAssertTrue(script.contains("wait_for_ax_identifier_absent \"embedded-terminal-close\""))
        XCTAssertTrue(script.contains("wait_for_ax_identifier_present \"task-status-move-in_progress-$header_layout_alternate_task_id\""))
        XCTAssertTrue(script.contains("wait_for_ax_identifier_present \"task-status-move-in_progress-$header_layout_project_task_id\""))
        XCTAssertTrue(script.contains("capture_window \"sidebar-visible\""))
        XCTAssertTrue(script.contains("capture_window \"sidebar-hidden\""))
        XCTAssertTrue(script.contains("capture_window \"sidebar-restored\""))
        XCTAssertTrue(script.contains("capture_window \"toolbar-icon-only\""))
        XCTAssertTrue(script.contains("capture_window \"toolbar-icon-and-label\""))
        XCTAssertTrue(script.contains("capture_window \"display-mode-list\""))
        XCTAssertTrue(script.contains("capture_window \"display-mode-overview\""))
        XCTAssertTrue(script.contains("capture_window \"display-mode-board\""))
        XCTAssertTrue(script.contains("capture_window \"inspector-closed\""))
        XCTAssertTrue(script.contains("capture_window \"inspector-reopened\""))
        XCTAssertTrue(script.contains("capture_window \"terminal-open\""))
        XCTAssertTrue(script.contains("capture_window \"terminal-closed\""))
        XCTAssertTrue(script.contains("capture_window \"project-selection-alternate\""))
        XCTAssertTrue(script.contains("capture_window \"project-selection-original\""))
        XCTAssertTrue(script.contains("assert_toolbar_layout_is_stable"))
        XCTAssertTrue(script.contains("toolbar_items_deduplicated >\"$baseline_file\""))
        XCTAssertTrue(script.contains("perform action \"AXPress\" of uiElement\n        return true"))
        XCTAssertTrue(script.contains("sidebar-hidden-immediate"))
        XCTAssertTrue(script.contains("sidebar-restored-immediate"))
        XCTAssertTrue(script.contains("toolbar-icon-only-immediate"))
        XCTAssertTrue(script.contains("toolbar-icon-and-label-immediate"))
        XCTAssertTrue(script.contains("display-mode-list-immediate"))
        XCTAssertTrue(script.contains("display-mode-overview-immediate"))
        XCTAssertTrue(script.contains("display-mode-board-immediate"))
        XCTAssertTrue(script.contains("inspector-closed-immediate"))
        XCTAssertTrue(script.contains("inspector-reopened-immediate"))
        XCTAssertTrue(script.contains("terminal-open-immediate"))
        XCTAssertTrue(script.contains("terminal-closed-immediate"))
        XCTAssertTrue(script.contains("project-selection-alternate-immediate"))
        XCTAssertTrue(script.contains("project-selection-original-immediate"))
        XCTAssertTrue(script.contains("Icon Only"))
        XCTAssertTrue(script.contains("Icon and Text"))
        XCTAssertTrue(script.contains("アイコンのみ"))
        XCTAssertTrue(script.contains("アイコンとテキスト"))
        XCTAssertTrue(script.contains("BLOCKER: header layout shifted after"))
        XCTAssertTrue(script.contains("SOLOPM_HEADER_LAYOUT_SMOKE_TIMEOUT_SECONDS"))
        XCTAssertTrue(script.contains("script/ui_evidence_window_metadata.swift"))
        XCTAssertTrue(script.contains("BLOCKER: header action controls are not trailing"))
        XCTAssertTrue(script.contains("BLOCKER: toolbar display mode menu item was not available"))
        XCTAssertTrue(script.contains("BLOCKER: Project display mode control was not available"))
        XCTAssertTrue(script.contains("BLOCKER: AX identifier stayed visible"))
        XCTAssertTrue(script.contains("BLOCKER: AX identifier was not visible"))
    }

    func testMenuBarPanelHostsSettingsLinkWithoutThemeControls() throws {
        let appSource = try readAppShellSource()
        let panelStart = try XCTUnwrap(appSource.range(of: "struct MenuBarPanel"))
        let panelEnd = try XCTUnwrap(appSource.range(of: "private struct SummaryRow"))
        let panelSource = String(appSource[panelStart.lowerBound..<panelEnd.lowerBound])

        XCTAssertTrue(panelSource.contains("SettingsLink"))
        XCTAssertTrue(panelSource.contains("Label(\"Settings\", systemImage: \"gearshape\")"))
        XCTAssertTrue(panelSource.contains(".help(\"Open Settings\")"))
        XCTAssertTrue(panelSource.contains(".accessibilityIdentifier(\"menu-bar-settings-link\")"))
        XCTAssertFalse(panelSource.contains("Theme"))
        XCTAssertFalse(panelSource.contains("Appearance"))
        XCTAssertFalse(panelSource.contains("SoloPMAppearancePreference"))
        XCTAssertFalse(panelSource.contains("Picker(\"Theme\""))
        XCTAssertFalse(panelSource.contains("Picker(\"Appearance\""))
        XCTAssertFalse(panelSource.contains("settings-theme-picker"))
        XCTAssertFalse(panelSource.contains("appearancePreference"))
        XCTAssertFalse(panelSource.contains(".pickerStyle(.segmented)"))
    }

    func testProjectBoardDropPayloadsAreValidatedByViewModel() throws {
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let coreSource = try readPackageFile("Sources/SoloPMCore/App/ProjectBoard.swift")
        let storeSource = try readPackageFile("Sources/SoloPMCore/WorkManagement/WorkManagementStore.swift")

        XCTAssertTrue(boardSource.contains(".draggable(String(task.id))"))
        XCTAssertTrue(boardSource.contains(".dropDestination(for: String.self)"))
        XCTAssertTrue(boardSource.contains("onMoveDroppedTasks(rawIDs, column.status)"))
        XCTAssertTrue(boardSource.contains(".contentShape(Rectangle())"))
        XCTAssertFalse(boardSource.contains("ProjectTaskDragPayload"))
        XCTAssertTrue(coreSource.contains("moveDroppedTasks(ids taskIDs: [Int64], to status: ProjectTaskStatus)"))
        XCTAssertTrue(coreSource.contains("moveDroppedTasks(ids rawIDs: [String], to status: ProjectTaskStatus)"))
        XCTAssertTrue(storeSource.contains("func moveTasks(ids: [Int64], to status: ProjectTaskStatus) throws -> [ProjectBoardTask]"))
        XCTAssertTrue(coreSource.contains("store.moveTasks(ids: taskIDs, to: status)"))
        XCTAssertTrue(coreSource.contains("Could not move task: invalid drag payload."))
    }

    func testDoneWorkflowIsReachableFromSidebarAndExposesReviewActions() throws {
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let workflowSource = try readProjectWorkflowSources()
        let persistenceSource = try readPackageFile("Sources/SoloPMCore/App/ProjectBoardSelectionPersistence.swift")
        let coreSource = try readPackageFile("Sources/SoloPMCore/App/ProjectBoard.swift")
        let modelSource = try readPackageFile("Sources/SoloPMCore/WorkManagement/WorkManagementModels.swift")

        XCTAssertTrue(persistenceSource.contains("case done"))
        XCTAssertTrue(boardSource.contains("ProjectBoardSidebarDestinationRow(destination: .done"))
        XCTAssertTrue(boardSource.contains("DoneWorkflowView(viewModel: viewModel, appSettings: appSettings())"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"done-workflow\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"done-reopen-task-\\(task.id)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"done-completion-heatmap\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"done-heatmap-day-\\(bucket.dayKey)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"done-productivity-insight\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"done-best-weekday-summary\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"done-best-hour-summary\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"done-follow-up-task-\\(task.id)\")"))
        XCTAssertTrue(workflowSource.contains("viewModel.enqueueDoneFollowUpDraft(for: task.id)"))
        XCTAssertTrue(workflowSource.contains("private struct DoneTaskHistoryActions"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"done-history-row-actions-\\(task.id)\")"))
        XCTAssertTrue(workflowSource.contains("analytics.completionHeatmapBuckets"))
        XCTAssertTrue(workflowSource.contains("analytics.bestWeekdaySummary"))
        XCTAssertTrue(workflowSource.contains("analytics.bestHourSummary"))
        XCTAssertTrue(coreSource.contains("public func doneAnalytics("))
        XCTAssertTrue(modelSource.contains("public struct DoneAnalyticsDayBucket"))
        XCTAssertTrue(modelSource.contains("DoneAnalyticsBestWeekdaySummary"))
        XCTAssertTrue(modelSource.contains("DoneAnalyticsBestHourSummary"))
        XCTAssertTrue(coreSource.contains("public func reopenCompletedTask(id: Int64)"))
        XCTAssertTrue(coreSource.contains("public func enqueueDoneFollowUpDraft(\n        for taskID: Int64"))
        XCTAssertTrue(coreSource.contains("DoneFollowUpActionDraftBuilder"))

        let doneRowStart = try XCTUnwrap(workflowSource.range(of: "private struct DoneTaskHistoryRow"))
        let doneRowEnd = try XCTUnwrap(workflowSource.range(of: "struct ExecutionReceiptHistoryRowView"))
        let doneRowSource = String(workflowSource[doneRowStart.lowerBound..<doneRowEnd.lowerBound])
        XCTAssertTrue(doneRowSource.contains("DoneTaskHistoryActions(task: task, viewModel: viewModel)"))
        XCTAssertFalse(doneRowSource.contains("Spacer()"))
    }

    func testProjectBoardPerformanceReadModelsStayOutOfRenderPath() throws {
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let todayWorkflowSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectWorkflowTodayView.swift")
        let catchUpWorkflowSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectWorkflowCatchUpView.swift")
        let scheduleWorkflowSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectWorkflowScheduleView.swift")
        let doneWorkflowSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectWorkflowDoneView.swift")
        let coreSource = try readPackageFile("Sources/SoloPMCore/App/ProjectBoard.swift")
        let sqliteStoreSource = try readPackageFile("Sources/SoloPMCore/WorkManagement/WorkManagementSQLiteStore.swift")

        XCTAssertTrue(coreSource.contains("public struct ProjectBoardDerivedReadModels"))
        XCTAssertTrue(coreSource.contains("@Published public private(set) var derivedReadModels"))
        XCTAssertTrue(coreSource.contains("private func rebuildDerivedReadModels("))
        XCTAssertTrue(coreSource.contains("public func refreshScheduleReadModel("))
        XCTAssertTrue(boardSource.contains("let sidebarMetrics = viewModel.derivedReadModels.sidebarMetrics"))
        XCTAssertTrue(boardSource.contains("count: sidebarMetrics.todayCount"))
        XCTAssertTrue(boardSource.contains("count: sidebarMetrics.catchUpCount"))
        XCTAssertTrue(boardSource.contains("count: sidebarMetrics.scheduleCount"))
        XCTAssertTrue(boardSource.contains("count: sidebarMetrics.doneCount"))
        XCTAssertTrue(boardSource.contains("viewModel.derivedReadModels.projectPortfolioSummaries"))
        XCTAssertFalse(boardSource.contains("count: viewModel.todayTasks().count"))
        XCTAssertFalse(boardSource.contains("count: viewModel.missedTaskReview().newlyMissedCount"))
        XCTAssertFalse(boardSource.contains("count: viewModel.unscheduledScheduleTasks().count"))
        XCTAssertFalse(boardSource.contains("count: viewModel.doneAnalytics().completedTaskCount"))
        XCTAssertFalse(boardSource.contains("count: viewModel.projectPortfolioSummaries().count"))

        XCTAssertTrue(todayWorkflowSource.contains("let snapshot = viewModel.derivedReadModels.todayWorkflowSnapshot"))
        XCTAssertFalse(todayWorkflowSource.contains("viewModel.todayWorkflowSnapshot(on: referenceDate, calendar: calendar)"))
        XCTAssertTrue(catchUpWorkflowSource.contains("viewModel.derivedReadModels.missedTaskReview"))
        XCTAssertFalse(catchUpWorkflowSource.contains("viewModel.missedTaskReview()"))
        XCTAssertTrue(scheduleWorkflowSource.contains("let scheduleReadModel = viewModel.derivedReadModels.schedule"))
        XCTAssertTrue(scheduleWorkflowSource.contains("viewModel.refreshScheduleReadModel(around: nextDate)"))
        XCTAssertTrue(scheduleWorkflowSource.contains("viewModel.refreshScheduleReadModel(around: day.date)"))
        XCTAssertFalse(scheduleWorkflowSource.contains("viewModel.refreshDerivedReadModels(on: nextDate)"))
        XCTAssertFalse(scheduleWorkflowSource.contains("viewModel.refreshDerivedReadModels(on: day.date)"))
        XCTAssertFalse(scheduleWorkflowSource.contains("viewModel.dailyWorkloadOverview(around: workloadReferenceDate)"))
        XCTAssertFalse(scheduleWorkflowSource.contains("viewModel.weeklyScheduleCockpit(around: workloadReferenceDate)"))
        XCTAssertTrue(doneWorkflowSource.contains("viewModel.derivedReadModels.doneAnalytics"))
        XCTAssertFalse(doneWorkflowSource.contains("viewModel.doneAnalytics()"))

        XCTAssertTrue(sqliteStoreSource.contains("private struct ProjectBoardStoreIndexes"))
        XCTAssertTrue(sqliteStoreSource.contains("Dictionary(grouping: boardData.tasks"))
        XCTAssertTrue(sqliteStoreSource.contains("Dictionary(grouping: boardData.artifacts"))
        XCTAssertTrue(sqliteStoreSource.contains("Dictionary(grouping: boardData.milestones"))
    }

    func testProjectBoardSupportsPersistentLightDarkAppearanceSelection() throws {
        let appSource = try readAppShellSource()
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let appearanceSource = try readPackageFile("Sources/SoloPMApp/Views/SoloPMAppearancePreference.swift")

        XCTAssertTrue(appearanceSource.contains("enum SoloPMAppearancePreference"))
        XCTAssertTrue(appearanceSource.contains("case system"))
        XCTAssertTrue(appearanceSource.contains("case light"))
        XCTAssertTrue(appearanceSource.contains("case dark"))
        XCTAssertTrue(appearanceSource.contains("static let storageKey = \"solopm.appearancePreference\""))
        XCTAssertTrue(appearanceSource.contains("static let environmentOverrideKey = \"SOLOPM_APPEARANCE_PREFERENCE\""))
        XCTAssertTrue(appearanceSource.contains("static var environmentOverride: SoloPMAppearancePreference?"))
        XCTAssertTrue(appearanceSource.contains("var colorScheme: ColorScheme?"))
        XCTAssertTrue(appSource.contains("@AppStorage(SoloPMAppearancePreference.storageKey)"))
        XCTAssertEqual(appSource.components(separatedBy: "@AppStorage(SoloPMAppearancePreference.storageKey)").count - 1, 1)
        XCTAssertTrue(appSource.contains("private var effectiveAppearancePreference: SoloPMAppearancePreference"))
        XCTAssertTrue(appSource.contains("SoloPMAppearancePreference.environmentOverride ?? appearancePreference"))
        XCTAssertTrue(appSource.contains(".preferredColorScheme(effectiveAppearancePreference.colorScheme)"))
        XCTAssertTrue(appSource.contains("private static var effectiveAppearancePreference: SoloPMAppearancePreference"))
        XCTAssertTrue(appSource.contains("SoloPMAppearancePreference.environmentOverride ?? persistedAppearancePreference"))
        XCTAssertTrue(appSource.contains(".preferredColorScheme(Self.effectiveAppearancePreference.colorScheme)"))
        XCTAssertTrue(appSource.contains("SettingsView("))
        XCTAssertTrue(appSource.contains("appearancePreference: $appearancePreference, languagePreference: $languagePreference"))
        XCTAssertTrue(appSource.contains("@Binding private var appearancePreference: SoloPMAppearancePreference"))
        XCTAssertTrue(appSource.contains("SettingsAppearanceSection(appearancePreference: $appearancePreference, languagePreference: $languagePreference)"))
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
        XCTAssertTrue(source.contains(".draggable(String(task.id))"))
        XCTAssertFalse(source.contains("Button {\n                        onSelectTask(task.id)\n                    } label: {\n                        BoardTaskCard"))
    }

    func testKanbanTaskCardsSeparateOpenDetailsFocusFromStatusMoveControls() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let cardStart = try XCTUnwrap(source.range(of: "private struct BoardTaskCard"))
        let cardEnd = try XCTUnwrap(source.range(of: "private struct TaskCardSelectableSummary"))
        let cardSource = String(source[cardStart.lowerBound..<cardEnd.lowerBound])

        XCTAssertTrue(source.contains("TaskCardSelectableSummary"))
        XCTAssertTrue(source.contains("TaskDragAffordance"))
        XCTAssertTrue(cardSource.contains("Button(action: onSelect)"))
        XCTAssertTrue(cardSource.contains(".buttonStyle(.plain)"))
        XCTAssertTrue(cardSource.contains(".accessibilityIdentifier(\"task-card-open-details\")"))
        XCTAssertTrue(cardSource.contains(".accessibilityIdentifier(\"task-status-move-controls\")"))
        XCTAssertTrue(cardSource.contains(".accessibilityElement(children: .contain)"))
        XCTAssertTrue(cardSource.contains(".accessibilitySortPriority(2)"))
        XCTAssertTrue(cardSource.contains(".accessibilitySortPriority(1)"))
        XCTAssertLessThan(
            try XCTUnwrap(cardSource.range(of: "TaskCardSelectableSummary")).lowerBound,
            try XCTUnwrap(cardSource.range(of: "TaskStatusMoveControls")).lowerBound
        )
        XCTAssertFalse(cardSource.contains(".onTapGesture(perform: onSelect)"))
    }

    func testKanbanDragAndDropHasVisibleDesktopAffordances() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")

        XCTAssertTrue(source.contains("Drag to another status column"))
        XCTAssertTrue(source.contains("arrow.up.and.down.and.arrow.left.and.right"))
        XCTAssertTrue(source.contains("Drop to move to"))
        XCTAssertTrue(source.contains("isDropTargeted"))
        XCTAssertTrue(source.contains(".dropDestination(for: String.self)"))
        XCTAssertTrue(source.contains(".contentShape(Rectangle())"))
    }

    func testKanbanCardsUseTaskComponentDragPreview() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")

        XCTAssertTrue(source.contains("BoardTaskDragPreview"))
        XCTAssertTrue(source.contains(".draggable(String(task.id)) {"))
        XCTAssertTrue(source.contains("BoardTaskDragPreview(task: task)"))
    }

    func testKanbanBoardUsesAdaptiveSampleInspiredCardStyling() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")

        XCTAssertTrue(source.contains("StatusCountBadge"))
        XCTAssertTrue(source.contains("column.status.tint"))
        XCTAssertTrue(source.contains("task.status.tint"))
        XCTAssertTrue(source.contains(".frame(width: ProjectBoardLayoutMetrics.boardColumnWidth"))
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

    func testTaskCardsUseSampleInspiredNonOverlappingMetadataStrip() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")
        let audit = try readPackageFile("docs/ux/click-path-audit.md")

        XCTAssertTrue(source.contains("TaskCardMetadataStrip(task: task)"))
        XCTAssertTrue(source.contains("private struct TaskCardMetadataStrip"))
        XCTAssertTrue(source.contains("private struct TaskMetadataChip"))
        XCTAssertTrue(source.contains("GridItem(.adaptive(minimum: 72), spacing: 6)"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"task-card-metadata-strip\")"))
        XCTAssertTrue(source.contains(".accessibilityValue(\"\\(task.status.title), \\(task.priority.label), \\(dueValue)\")"))
        XCTAssertTrue(source.contains("No due date"))
        XCTAssertTrue(source.contains(".minimumScaleFactor(0.82)"))
        XCTAssertTrue(source.contains("minWidth: ProjectBoardLayoutMetrics.taskMetadataChipMinWidth"))
        XCTAssertTrue(source.contains("minHeight: ProjectBoardLayoutMetrics.taskMetadataChipMinHeight"))
        XCTAssertTrue(phase.contains("[x] `ui-samples/01.png`、`03.png`、`04.png` を基準に、左サイドバー、中央ボード/リスト、右インスペクタの情報密度を見直す。"))
        XCTAssertTrue(phase.contains("[x] Task card metadata strip はstatus / priority / dueを固定寸法chipに分離し、狭いKanban列ではadaptive gridへ逃がす。"))
        XCTAssertTrue(audit.contains("Task card metadata strip"))
        XCTAssertTrue(audit.contains("status / priority / dueを固定寸法chip"))
    }

    func testProjectBoardExposesPrimaryCRUDKeyboardShortcuts() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let appSource = try readAppShellSource()

        XCTAssertTrue(source.contains(".keyboardShortcut(\"n\", modifiers: [.command])"))
        XCTAssertTrue(source.contains(".keyboardShortcut(\"n\", modifiers: [.command, .shift])"))
        XCTAssertTrue(source.contains(".help(\"Add a project\")"))
        XCTAssertFalse(source.contains(".keyboardShortcut(\",\", modifiers: [.command])"))
        XCTAssertTrue(source.contains(".help(\"Open Settings\")"))
        XCTAssertTrue(appSource.contains("CommandGroup(replacing: .appSettings)"))
        XCTAssertTrue(appSource.contains(".keyboardShortcut(\",\", modifiers: [.command])"))
    }

    func testProjectBoardHostsEmbeddedTerminalAsApprovalGatedBottomPanel() throws {
        let packageSource = try readPackageFile("Package.swift")
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let terminalSource = try readPackageFile("Sources/SoloPMApp/Views/TerminalPanelView.swift")

        XCTAssertTrue(packageSource.contains(#".package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.13.0")"#))
        XCTAssertTrue(packageSource.contains(#".product(name: "SwiftTerm", package: "SwiftTerm")"#))
        XCTAssertTrue(boardSource.contains("@State private var isTerminalPanelPresented = false"))
        XCTAssertTrue(boardSource.contains("private var isDeveloperModeEnabled: Bool"))
        XCTAssertTrue(boardSource.contains("appSettings().isDeveloperModeEnabled"))
        XCTAssertTrue(boardSource.contains("EmbeddedTerminalPanel("))
        XCTAssertTrue(boardSource.contains("if isTerminalPanelPresented && isDeveloperModeEnabled"))
        XCTAssertTrue(boardSource.contains("workingDirectory: terminalWorkingDirectory"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"project-board-terminal-toggle\")"))
        XCTAssertTrue(boardSource.contains("if isDeveloperModeEnabled {\n                Button {"))
        XCTAssertTrue(boardSource.contains(".keyboardShortcut(\"`\", modifiers: [.control])"))
        XCTAssertTrue(boardSource.contains("appSettings().defaultWorkspacePath?.trimmingCharacters(in: .whitespacesAndNewlines)"))
        let terminalButtonStart = try XCTUnwrap(boardSource.range(of: "if isDeveloperModeEnabled {\n                Button {"))
        let terminalIdentifierEnd = try XCTUnwrap(boardSource[terminalButtonStart.lowerBound...].range(of: ".accessibilityIdentifier(\"project-board-terminal-toggle\")"))
        let terminalButtonSource = boardSource[terminalButtonStart.lowerBound...terminalIdentifierEnd.upperBound]
        XCTAssertFalse(terminalButtonSource.contains(".accessibilityElement(children: .ignore)"))
        XCTAssertTrue(terminalSource.contains("struct EmbeddedTerminalPanel"))
        XCTAssertTrue(terminalSource.contains("@State private var isExecutionApproved = false"))
        XCTAssertTrue(terminalSource.contains("if isExecutionApproved {"))
        XCTAssertTrue(terminalSource.contains("LocalShellTerminalRepresentable("))
        XCTAssertTrue(terminalSource.contains("Button { isExecutionApproved = true }"))
        XCTAssertTrue(terminalSource.contains("Developer Mode is enabled. Local shell execution requires explicit approval and starts in \\(displayDirectory)."))
        XCTAssertFalse(terminalSource.contains(".accessibilityIdentifier(\"embedded-terminal-panel\")"))
        XCTAssertTrue(terminalSource.contains(".accessibilityIdentifier(\"embedded-terminal-approve\")"))
        XCTAssertTrue(terminalSource.contains(".accessibilityIdentifier(\"embedded-terminal-view\")"))
        XCTAssertTrue(terminalSource.contains(".accessibilityIdentifier(\"embedded-terminal-close\")"))
        XCTAssertTrue(terminalSource.contains("static func dismantleNSView"))
        XCTAssertTrue(terminalSource.contains("nsView.terminate()"))
        XCTAssertFalse(terminalSource.contains("setHostLogging"))
    }

    func testInlineTaskComposerExposesKeyboardAndVoiceOverCreateAnchors() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")
        let audit = try readPackageFile("docs/ux/click-path-audit.md")
        let composerStart = try XCTUnwrap(source.range(of: "private struct InlineTaskComposer"))
        let cardStart = try XCTUnwrap(source.range(of: "private struct BoardTaskCard"))
        let composerSource = String(source[composerStart.lowerBound..<cardStart.lowerBound])

        XCTAssertTrue(composerSource.contains(".accessibilityIdentifier(\"inline-task-composer-\\(status.rawValue)\")"))
        XCTAssertTrue(composerSource.contains(".accessibilityLabel(\"New task in \\(status.title)\")"))
        XCTAssertTrue(composerSource.contains(".accessibilityHint(\"Create a local task in the \\(status.title) column without leaving the board.\")"))
        XCTAssertTrue(composerSource.contains(".accessibilityIdentifier(\"inline-task-title\")"))
        XCTAssertTrue(composerSource.contains(".accessibilityIdentifier(\"inline-task-detail\")"))
        XCTAssertTrue(composerSource.contains(".accessibilityIdentifier(\"inline-task-priority\")"))
        XCTAssertTrue(composerSource.contains(".accessibilityIdentifier(\"inline-task-due\")"))
        XCTAssertTrue(composerSource.contains(".accessibilityIdentifier(\"inline-task-create\")"))
        XCTAssertTrue(composerSource.contains(".accessibilityIdentifier(\"inline-task-cancel\")"))
        XCTAssertTrue(composerSource.contains(".keyboardShortcut(.return, modifiers: [.command])"))
        XCTAssertTrue(composerSource.contains(".keyboardShortcut(.escape, modifiers: [])"))
        XCTAssertTrue(composerSource.contains(".accessibilityHint(\"Creates the task in the local SoloPM database.\")"))
        XCTAssertTrue(composerSource.contains(".accessibilityHint(\"Cancels task creation and returns focus to the board column.\")"))
        XCTAssertTrue(phase.contains("[x] Inline Task Composerにtitle/detail/priority/due/create/cancelのaccessibility identifier / hintとCommand+Return/Escapeを付ける。"))
        XCTAssertTrue(audit.contains("Inline Task Composerはtitle/detail/priority/due/create/cancelにaccessibility anchorsを持ち"))
    }

    func testInspectorsExposeKeyboardOnlyCrudShortcuts() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let projectInspectorStart = try XCTUnwrap(source.range(of: "private struct ProjectInspectorView"))
        let taskInspectorStart = try XCTUnwrap(source.range(of: "private struct TaskInspectorView"))
        let projectSuggestionStart = try XCTUnwrap(source.range(of: "private struct ProjectInspectorSuggestionSection"))
        let taskSuggestionStart = try XCTUnwrap(source.range(of: "private struct TaskInspectorSuggestionSection"))
        let projectInspectorSource = String(source[projectInspectorStart.lowerBound..<projectSuggestionStart.lowerBound])
        let taskInspectorSource = String(source[taskInspectorStart.lowerBound..<taskSuggestionStart.lowerBound])
        let suggestionSource = String(source[projectSuggestionStart.lowerBound..<source.endIndex])

        XCTAssertTrue(projectInspectorSource.contains(".keyboardShortcut(\"s\", modifiers: [.command])"))
        XCTAssertTrue(taskInspectorSource.contains(".keyboardShortcut(\"s\", modifiers: [.command])"))
        XCTAssertTrue(projectInspectorSource.contains(".keyboardShortcut(.delete, modifiers: [.command])"))
        XCTAssertTrue(taskInspectorSource.contains(".keyboardShortcut(.delete, modifiers: [.command])"))
        XCTAssertGreaterThanOrEqual(suggestionSource.components(separatedBy: ".keyboardShortcut(.return, modifiers: [.command])").count - 1, 2)
    }

    func testPrimaryKeyboardShortcutsAreAttachedToConcreteCommandsAndFocusedActions() throws {
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let workflowSource = try readProjectWorkflowSources()
        let appSource = try readAppShellSource()
        let phase = try readPackageFile("tasks/Phase14-QualityRegressionHardening.md")

        let settingsCommand = try sourceBlock(
            in: appSource,
            from: "CommandGroup(replacing: .appSettings)",
            to: "Window(\"Voice Command\", id: \"voice-capture\")"
        )
        XCTAssertTrue(settingsCommand.contains("SettingsLink"))
        XCTAssertTrue(settingsCommand.contains(".keyboardShortcut(\",\", modifiers: [.command])"))

        let addProjectButton = try sourceBlock(
            in: boardSource,
            from: "if let project = viewModel.createProject()",
            to: ".accessibilityIdentifier(\"project-board-add-project\")"
        )
        XCTAssertTrue(addProjectButton.contains(".keyboardShortcut(\"n\", modifiers: [.command, .shift])"))

        let addTaskButton = try sourceBlock(
            in: boardSource,
            from: "private var addTaskButton: some View",
            to: ".accessibilityIdentifier(\"project-header-add-task\")"
        )
        XCTAssertTrue(addTaskButton.contains("Button(action: onAddTask)"))
        XCTAssertTrue(addTaskButton.contains(".keyboardShortcut(\"n\", modifiers: [.command])"))

        let inlineComposer = try sourceBlock(
            in: boardSource,
            from: "private struct InlineTaskComposer",
            to: "private struct BoardTaskCard"
        )
        XCTAssertTrue(inlineComposer.contains(".accessibilityIdentifier(\"inline-task-create\")"))
        XCTAssertTrue(inlineComposer.contains(".keyboardShortcut(.return, modifiers: [.command])"))
        XCTAssertTrue(inlineComposer.contains(".accessibilityIdentifier(\"inline-task-cancel\")"))
        XCTAssertTrue(inlineComposer.contains(".keyboardShortcut(.escape, modifiers: [])"))

        let projectInspector = try sourceBlock(
            in: boardSource,
            from: "private struct ProjectInspectorView",
            to: "private struct ProjectInspectorSuggestionSection"
        )
        XCTAssertTrue(projectInspector.contains(".accessibilityIdentifier(\"project-inspector-save\")"))
        XCTAssertTrue(projectInspector.contains(".keyboardShortcut(\"s\", modifiers: [.command])"))
        XCTAssertTrue(projectInspector.contains(".accessibilityIdentifier(\"project-inspector-delete\")"))
        XCTAssertTrue(projectInspector.contains(".keyboardShortcut(.delete, modifiers: [.command])"))

        let taskInspector = try sourceBlock(
            in: boardSource,
            from: "private struct TaskInspectorView",
            to: "private struct TaskInspectorSuggestionSection"
        )
        XCTAssertTrue(taskInspector.contains(".accessibilityIdentifier(\"task-inspector-save\")"))
        XCTAssertTrue(taskInspector.contains(".keyboardShortcut(\"s\", modifiers: [.command])"))
        XCTAssertTrue(taskInspector.contains(".accessibilityIdentifier(\"task-inspector-delete\")"))
        XCTAssertTrue(taskInspector.contains(".keyboardShortcut(.delete, modifiers: [.command])"))

        let inboxActions = try sourceBlock(
            in: workflowSource,
            from: "private var actionButtons: some View",
            to: "private struct InboxVoiceIntakeDetail"
        )
        XCTAssertTrue(inboxActions.contains(".accessibilityIdentifier(\"inbox-action-make-task\")"))
        XCTAssertTrue(inboxActions.contains(".keyboardShortcut(\"1\", modifiers: [.command])"))
        XCTAssertTrue(inboxActions.contains(".accessibilityIdentifier(\"inbox-action-make-project\")"))
        XCTAssertTrue(inboxActions.contains(".keyboardShortcut(\"2\", modifiers: [.command])"))
        XCTAssertTrue(inboxActions.contains(".accessibilityIdentifier(\"inbox-action-schedule-today\")"))
        XCTAssertTrue(inboxActions.contains(".keyboardShortcut(\"3\", modifiers: [.command])"))
        XCTAssertTrue(inboxActions.contains(".accessibilityIdentifier(\"inbox-action-review-later\")"))
        XCTAssertTrue(inboxActions.contains(".keyboardShortcut(\"4\", modifiers: [.command])"))
        XCTAssertTrue(phase.contains("- [x] Keyboard shortcutがmenu commandまたはfocused actionに接続されていることをsource testで固定する。"))
    }

    func testInspectorSaveControlsStayAdjacentToEditableFieldsBeforeLongSuggestionSections() throws {
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")

        let projectInspector = try sourceBlock(
            in: boardSource,
            from: "private struct ProjectInspectorView",
            to: "private struct ProjectInspectorSuggestionSection"
        )
        let projectEdit = try XCTUnwrap(projectInspector.range(of: "Section(\"Edit\")"))
        let projectSave = try XCTUnwrap(projectInspector.range(of: ".accessibilityIdentifier(\"project-inspector-save\")"))
        let projectSuggestion = try XCTUnwrap(projectInspector.range(of: "Section(\"Suggestion\")"))
        XCTAssertLessThan(projectEdit.lowerBound, projectSave.lowerBound)
        XCTAssertLessThan(
            projectSave.lowerBound,
            projectSuggestion.lowerBound,
            "Project save must stay before long suggestion content so compact-window AX and VoiceOver paths can save immediately after editing."
        )

        let taskInspector = try sourceBlock(
            in: boardSource,
            from: "private struct TaskInspectorView",
            to: "private struct TaskInspectorSuggestionSection"
        )
        let taskFields = try XCTUnwrap(taskInspector.range(of: "Section(\"Fields\")"))
        let taskSave = try XCTUnwrap(taskInspector.range(of: ".accessibilityIdentifier(\"task-inspector-save\")"))
        let taskSuggestion = try XCTUnwrap(taskInspector.range(of: "Section(\"Suggestion\")"))
        let taskAutomation = try XCTUnwrap(taskInspector.range(of: "Section(\"Automation\")"))
        XCTAssertLessThan(taskFields.lowerBound, taskSave.lowerBound)
        XCTAssertLessThan(
            taskSave.lowerBound,
            taskSuggestion.lowerBound,
            "Task save must stay before suggestion and automation content so edit/save remains reachable without scrolling."
        )
        XCTAssertLessThan(taskSave.lowerBound, taskAutomation.lowerBound)
    }

    func testInspectorsExposeVisibleCloseButtonsThatDismissTheSidebar() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")

        XCTAssertTrue(source.contains("TaskInspectorView("))
        XCTAssertTrue(source.contains("onClose: { inspectorBinding.wrappedValue = false }"))
        XCTAssertTrue(source.contains("ProjectInspectorView("))
        XCTAssertTrue(source.contains("private struct InspectorCloseHeader"))
        XCTAssertTrue(source.contains("private struct InspectorCloseButton"))
        XCTAssertTrue(source.contains("InspectorCloseHeader("))
        XCTAssertTrue(source.contains("title: \"Task Details\""))
        XCTAssertTrue(source.contains("title: \"Project Details\""))
        XCTAssertTrue(source.contains("closeTitle: \"Close Task Details\""))
        XCTAssertTrue(source.contains("closeTitle: \"Close Project Details\""))
        XCTAssertTrue(source.contains("Label(title, systemImage: systemImage)"))
        XCTAssertTrue(source.contains("Label(closeTitle, systemImage: \"xmark\")"))
        XCTAssertTrue(source.contains(".labelStyle(.iconOnly)"))
        XCTAssertTrue(source.contains(".keyboardShortcut(.escape, modifiers: [])"))
        XCTAssertTrue(source.contains("closeAccessibilityIdentifier: \"task-inspector-close\""))
        XCTAssertTrue(source.contains("closeAccessibilityIdentifier: \"project-inspector-close\""))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(accessibilityIdentifier)"))
    }

    func testInspectorDestructiveConfirmationActionsDeferSelectionMutations() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let projectInspectorStart = try XCTUnwrap(source.range(of: "private struct ProjectInspectorView"))
        let taskInspectorStart = try XCTUnwrap(source.range(of: "private struct TaskInspectorView"))
        let projectSuggestionStart = try XCTUnwrap(source.range(of: "private struct ProjectInspectorSuggestionSection"))
        let taskSummaryStart = try XCTUnwrap(source.range(of: "private struct TaskInspectorMetadataSummary"))
        let projectInspectorSource = String(source[projectInspectorStart.lowerBound..<projectSuggestionStart.lowerBound])
        let taskInspectorSource = String(source[taskInspectorStart.lowerBound..<taskSummaryStart.lowerBound])

        XCTAssertTrue(projectInspectorSource.contains("archiveSelectedProjectAfterConfirmationDismissal()"))
        XCTAssertTrue(projectInspectorSource.contains("deleteSelectedProjectAfterConfirmationDismissal()"))
        XCTAssertTrue(taskInspectorSource.contains("deleteSelectedTaskAfterConfirmationDismissal()"))
        XCTAssertTrue(projectInspectorSource.contains("InspectorDestructiveConfirmation("))
        XCTAssertTrue(taskInspectorSource.contains("InspectorDestructiveConfirmation("))
        XCTAssertTrue(projectInspectorSource.contains("DispatchQueue.main.async"))
        XCTAssertTrue(taskInspectorSource.contains("DispatchQueue.main.async"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"\\(accessibilityIdentifier)-cancel\")"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Cancel \\(confirmTitle)\")"))
        XCTAssertTrue(source.contains(".accessibilityHint(\"Cancels \\(confirmTitle) and returns to the inspector.\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"\\(accessibilityIdentifier)-confirm\")"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Confirm \\(confirmTitle)\")"))
        XCTAssertTrue(source.contains(".accessibilityHint(\"Confirms \\(confirmTitle).\")"))
        XCTAssertFalse(projectInspectorSource.contains(".confirmationDialog("))
        XCTAssertFalse(taskInspectorSource.contains(".confirmationDialog("))
        XCTAssertFalse(projectInspectorSource.contains("Button(\"Archive Project\", role: .destructive) {\n                viewModel.archiveSelectedProject()\n            }"))
        XCTAssertFalse(projectInspectorSource.contains("Button(\"Delete Project\", role: .destructive) {\n                viewModel.deleteSelectedProject()\n            }"))
        XCTAssertFalse(taskInspectorSource.contains("Button(\"Delete Task\", role: .destructive) {\n                viewModel.deleteSelectedTask()\n            }"))
    }

    func testInspectorsExposeCompactMetadataSummaries() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")
        let audit = try readPackageFile("docs/ux/click-path-audit.md")

        XCTAssertTrue(source.contains("TaskInspectorMetadataSummary(task: task, projectTitle: viewModel.projectTitle(for: task))"))
        XCTAssertTrue(source.contains("ProjectInspectorMetadataSummary(project: project)"))
        XCTAssertTrue(source.contains("private struct InspectorMetadataPill"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"task-inspector-metadata-summary\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-inspector-metadata-summary\")"))
        let projectSummaryStart = try XCTUnwrap(source.range(of: "private struct ProjectInspectorMetadataSummary"))
        let projectSuggestionStart = try XCTUnwrap(source.range(of: "private struct ProjectInspectorSuggestionSection"))
        let taskSummaryStart = try XCTUnwrap(source.range(of: "private struct TaskInspectorMetadataSummary"))
        let inspectorPillStart = try XCTUnwrap(source.range(of: "private struct InspectorMetadataPill"))
        let projectSummarySource = String(source[projectSummaryStart.lowerBound..<projectSuggestionStart.lowerBound])
        let taskSummarySource = String(source[taskSummaryStart.lowerBound..<inspectorPillStart.lowerBound])

        XCTAssertTrue(projectSummarySource.contains("LazyVGrid(columns: compactColumns, alignment: .leading, spacing: 8)"))
        XCTAssertTrue(taskSummarySource.contains("LazyVGrid(columns: compactColumns, alignment: .leading, spacing: 8)"))
        XCTAssertFalse(projectSummarySource.contains("ViewThatFits(in: .horizontal)"))
        XCTAssertFalse(projectSummarySource.contains("HStack(spacing: 8)"))
        XCTAssertFalse(taskSummarySource.contains("ViewThatFits(in: .horizontal)"))
        XCTAssertFalse(taskSummarySource.contains("HStack(spacing: 8)"))
        XCTAssertTrue(source.contains("GridItem(.adaptive(minimum: 96), spacing: 8)"))
        XCTAssertTrue(phase.contains("[x] Task / Project inspector はcompact summaryで状態、優先度、期限、件数を先頭表示し、詳細Formの前に文脈が分かる。"))
        XCTAssertTrue(audit.contains("Task / Project inspector はcompact summaryを先頭に追加済み"))
    }

    func testProjectBoardPromotesInboxAndTodayAsFirstClassDestinations() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let workflowSource = try readProjectWorkflowSources()
        let coreSource = try readPackageFile("Sources/SoloPMCore/App/ProjectBoard.swift")

        XCTAssertTrue(source.contains("ProjectBoardSidebarDestination"))
        XCTAssertTrue(source.contains("ProjectBoardSidebarDestinationRow(destination: .inbox"))
        XCTAssertTrue(source.contains("ProjectBoardSidebarDestinationRow(destination: .today"))
        XCTAssertTrue(source.contains("ProjectBoardSidebarDestinationRow(destination: .catchUp"))
        XCTAssertTrue(source.contains("InboxWorkflowView("))
        XCTAssertTrue(source.contains("TodayWorkflowView("))
        XCTAssertTrue(source.contains("CatchUpWorkflowView("))
        XCTAssertTrue(workflowSource.contains("InboxActionPanel("))
        XCTAssertTrue(workflowSource.contains("viewModel.convertSelectedTaskToProject()"))
        XCTAssertTrue(workflowSource.contains("viewModel.scheduleSelectedTaskForToday()"))
        XCTAssertTrue(workflowSource.contains("viewModel.deferSelectedTaskForLater()"))
        XCTAssertTrue(coreSource.contains("public var inboxTasks"))
        XCTAssertTrue(coreSource.contains("public func todayTasks("))
    }

    func testPhase12SidebarDestinationRawValuesStayBackwardCompatible() throws {
        let persistenceSource = try readPackageFile("Sources/SoloPMCore/App/ProjectBoardSelectionPersistence.swift")

        XCTAssertTrue(persistenceSource.contains("public enum ProjectBoardSidebarDestination"))
        XCTAssertTrue(persistenceSource.contains("public enum ProjectBoardSelectionPersistence"))
        XCTAssertTrue(persistenceSource.contains("static let defaultRawValue = \"today\""))
        XCTAssertTrue(persistenceSource.contains("case .inbox:\n            return \"inbox\""))
        XCTAssertTrue(persistenceSource.contains("case .today:\n            return \"today\""))
        XCTAssertTrue(persistenceSource.contains("case .catchUp:\n            return \"catch-up\""))
        XCTAssertTrue(persistenceSource.contains("case .projects:\n            return \"projects\""))
        XCTAssertTrue(persistenceSource.contains("case .schedule:\n            return \"schedule\""))
        XCTAssertTrue(persistenceSource.contains("case .done:\n            return \"done\""))
        XCTAssertTrue(persistenceSource.contains("case .project(let projectID):\n            return \"project:\\(projectID)\""))
        XCTAssertTrue(persistenceSource.contains("case \"inbox\":\n            return .inbox"))
        XCTAssertTrue(persistenceSource.contains("case \"today\":\n            return .today"))
        XCTAssertTrue(persistenceSource.contains("case \"catch-up\":\n            return .catchUp"))
        XCTAssertTrue(persistenceSource.contains("case \"projects\":\n            return .projects"))
        XCTAssertTrue(persistenceSource.contains("case \"schedule\":\n            return .schedule"))
        XCTAssertTrue(persistenceSource.contains("case \"done\":\n            return .done"))
        XCTAssertTrue(persistenceSource.contains("guard parts.count == 2 else {\n                return .today"))
        XCTAssertTrue(persistenceSource.contains("availableProjects.contains(where: { $0.id == projectID }) else {\n                    return .today"))
    }

    func testPhase12SidebarShowsWorkflowDestinationsBeforeProjectRows() throws {
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")

        let inboxRow = try XCTUnwrap(boardSource.range(of: "ProjectBoardSidebarDestinationRow(destination: .inbox"))
        let todayRow = try XCTUnwrap(boardSource.range(of: "ProjectBoardSidebarDestinationRow(destination: .today"))
        let catchUpRow = try XCTUnwrap(boardSource.range(of: "ProjectBoardSidebarDestinationRow(destination: .catchUp"))
        let scheduleRow = try XCTUnwrap(boardSource.range(of: "ProjectBoardSidebarDestinationRow(destination: .schedule"))
        let doneRow = try XCTUnwrap(boardSource.range(of: "ProjectBoardSidebarDestinationRow(destination: .done"))
        let projectsSection = try XCTUnwrap(boardSource.range(of: "Section(\"Projects\")"))

        XCTAssertLessThan(inboxRow.lowerBound, projectsSection.lowerBound)
        XCTAssertLessThan(todayRow.lowerBound, projectsSection.lowerBound)
        XCTAssertLessThan(todayRow.lowerBound, catchUpRow.lowerBound)
        XCTAssertLessThan(catchUpRow.lowerBound, scheduleRow.lowerBound)
        XCTAssertLessThan(catchUpRow.lowerBound, projectsSection.lowerBound)
        XCTAssertLessThan(scheduleRow.lowerBound, projectsSection.lowerBound)
        XCTAssertLessThan(doneRow.lowerBound, projectsSection.lowerBound)
        XCTAssertTrue(boardSource.contains("ProjectBoardSidebarDestinationRow(\n                            destination: .projects"))
        XCTAssertTrue(boardSource.contains(".tag(ProjectBoardSidebarDestination.projects)"))
        XCTAssertTrue(boardSource.contains(".tag(ProjectBoardSidebarDestination.project(project.id))"))
        XCTAssertTrue(boardSource.contains("Label(\"Add Project\", systemImage: \"folder.badge.plus\")"))
        XCTAssertTrue(boardSource.contains("Label(\n                        \"Show Archived\""))
    }

    func testPhase12SidebarDoesNotStealInboxCommandNumberShortcuts() throws {
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let workflowSource = try readProjectWorkflowSources()

        XCTAssertFalse(boardSource.contains(".keyboardShortcut(\"1\", modifiers: [.command])"))
        XCTAssertFalse(boardSource.contains(".keyboardShortcut(\"2\", modifiers: [.command])"))
        XCTAssertFalse(boardSource.contains(".keyboardShortcut(\"3\", modifiers: [.command])"))
        XCTAssertFalse(boardSource.contains(".keyboardShortcut(\"4\", modifiers: [.command])"))
        XCTAssertFalse(boardSource.contains(".keyboardShortcut(\"5\", modifiers: [.command])"))
        XCTAssertTrue(workflowSource.contains(".keyboardShortcut(\"1\", modifiers: [.command])"))
        XCTAssertTrue(workflowSource.contains(".keyboardShortcut(\"2\", modifiers: [.command])"))
        XCTAssertTrue(workflowSource.contains(".keyboardShortcut(\"3\", modifiers: [.command])"))
        XCTAssertTrue(workflowSource.contains(".keyboardShortcut(\"4\", modifiers: [.command])"))
        XCTAssertFalse(workflowSource.contains(".keyboardShortcut(\"5\", modifiers: [.command])"))
    }

    func testInboxActionPanelSurfacesClassificationFeedbackAndUndo() throws {
        let workflowSource = try readProjectWorkflowSources()
        let coreSource = try readPackageFile("Sources/SoloPMCore/App/ProjectBoard.swift")
        let modelSource = try readPackageFile("Sources/SoloPMCore/WorkManagement/WorkManagementModels.swift")

        XCTAssertTrue(modelSource.contains("public struct InboxClassificationFeedback"))
        XCTAssertTrue(coreSource.contains("@Published public private(set) var inboxClassificationFeedback"))
        XCTAssertTrue(coreSource.contains("public func undoLastInboxClassification()"))
        XCTAssertTrue(workflowSource.contains("if let feedback = viewModel.inboxClassificationFeedback"))
        XCTAssertTrue(workflowSource.contains("Label(feedback.message, systemImage: feedback.systemImage)"))
        XCTAssertTrue(workflowSource.contains("viewModel.undoLastInboxClassification()"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-classification-feedback\")"))

        let feedbackStart = try XCTUnwrap(workflowSource.range(of: "if let feedback = viewModel.inboxClassificationFeedback"))
        let feedbackEnd = try XCTUnwrap(workflowSource[feedbackStart.lowerBound...].range(of: "LazyVGrid(columns: actionGridColumns"))
        let feedbackBlock = String(workflowSource[feedbackStart.lowerBound..<feedbackEnd.lowerBound])
        XCTAssertTrue(feedbackBlock.contains(".accessibilityElement(children: .contain)"))
        XCTAssertFalse(feedbackBlock.contains(".accessibilityElement(children: .combine)"))
    }

    func testInboxWorkflowSurfacesVoiceCaptureMetadataWithoutReplacingVoiceCommand() throws {
        let workflowSource = try readProjectWorkflowSources()
        let appSource = try readAppShellSource()
        let coreSource = try readPackageFile("Sources/SoloPMCore/App/ProjectBoard.swift")
        let modelSource = try readPackageFile("Sources/SoloPMCore/WorkManagement/WorkManagementModels.swift")
        let voiceSource = try readPackageFile("Sources/SoloPMCore/Voice/InboxCapture.swift")

        XCTAssertTrue(coreSource.contains("public var selectedInboxCaptureRecords"))
        XCTAssertTrue(voiceSource.contains("func updateMemo(id: Int64, memo: String?) throws -> InboxCaptureRecord"))
        XCTAssertTrue(coreSource.contains("public func updateSelectedInboxCaptureMemo(_ memo: String) -> InboxCaptureRecord?"))
        XCTAssertTrue(modelSource.contains("public struct InboxTriageSummary"))
        XCTAssertTrue(coreSource.contains("public func inboxTriageSummary(for task: ProjectBoardTask) -> InboxTriageSummary"))
        XCTAssertTrue(modelSource.contains("public enum InboxTriageFilter"))
        XCTAssertTrue(coreSource.contains("public var filteredInboxTasks"))
        XCTAssertTrue(coreSource.contains("public func setInboxTriageFilter"))
        XCTAssertTrue(workflowSource.contains("viewModel.filteredInboxTasks"))
        XCTAssertTrue(workflowSource.contains("viewModel.inboxTriageSummary(for: task)"))
        XCTAssertTrue(workflowSource.contains("InboxTriagePill(summary: triageSummary)"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-row-triage-summary-\\(task.id)\")"))
        XCTAssertTrue(workflowSource.contains("InboxHeaderControls("))
        XCTAssertTrue(workflowSource.contains("Picker(\"Inbox Filter\""))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-triage-filter\")"))
        XCTAssertTrue(workflowSource.contains("private var mainSurface: some View"))
        XCTAssertTrue(workflowSource.contains("InboxTriageRail("))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-workflow\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-triage-rail\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityLabel(\"Inbox triage station\")"))
        XCTAssertTrue(workflowSource.contains("without opening the task inspector"))
        XCTAssertTrue(workflowSource.contains("onSelectTask: selectInboxTask"))
        XCTAssertTrue(workflowSource.contains("@State private var voiceMemoDraft"))
        XCTAssertTrue(workflowSource.contains("@State private var voiceMemoCaptureID"))
        XCTAssertTrue(workflowSource.contains("memoDraft: $voiceMemoDraft"))
        XCTAssertTrue(workflowSource.contains("memoCaptureID: $voiceMemoCaptureID"))
        XCTAssertTrue(workflowSource.contains("@Binding var memoDraft: String"))
        XCTAssertTrue(workflowSource.contains("@Binding var memoCaptureID: Int64?"))
        XCTAssertTrue(workflowSource.contains("InboxVoiceIntakeDetail("))
        XCTAssertTrue(workflowSource.contains("onSaveMemo: { memo in"))
        XCTAssertTrue(workflowSource.contains("viewModel.updateSelectedInboxCaptureMemo(memo)"))
        XCTAssertTrue(workflowSource.contains("viewModel.selectedInboxCaptureRecords"))
        XCTAssertTrue(workflowSource.contains(".accessibilityLabel(panelAccessibilityLabel)"))
        XCTAssertTrue(workflowSource.contains(".accessibilityValue(panelAccessibilityValue)"))
        XCTAssertTrue(workflowSource.contains(".accessibilityHint(panelAccessibilityHint)"))
        XCTAssertTrue(workflowSource.contains("Voice capture metadata available for \\(task.title)"))
        XCTAssertTrue(workflowSource.contains("taskTitle: task?.title ?? \"Selected Inbox item\""))
        XCTAssertTrue(workflowSource.contains("LazyVGrid(columns: actionGridColumns"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-action-grid\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-voice-intake-detail\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-voice-transcript-preview\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-voice-waveform\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-voice-transcript\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-voice-interpretation\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-voice-memo\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-voice-memo-editor\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-voice-memo-save\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-voice-source-metadata\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-voice-review-status\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityElement(children: .contain)"))
        XCTAssertTrue(workflowSource.contains("Transcript only"))
        XCTAssertTrue(workflowSource.contains("Transcript-only voice capture, duration \\(capture.durationLabel), waveform preview"))
        XCTAssertFalse(workflowSource.contains("Playback unavailable in this MVP"))
        XCTAssertFalse(workflowSource.contains("Button {} label:"))
        XCTAssertTrue(workflowSource.contains(".accessibilityLabel(title)"))
        XCTAssertTrue(workflowSource.contains(".accessibilityValue(value)"))
        XCTAssertTrue(workflowSource.contains(".accessibilityLabel(\"Voice intake detail for \\(taskTitle)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityValue(captureAccessibilityValue(capture))"))
        XCTAssertTrue(workflowSource.contains("capture.durationLabel"))
        XCTAssertTrue(workflowSource.contains("capture.transcript"))
        XCTAssertTrue(workflowSource.contains("capture.classificationStatus.rawValue"))
        XCTAssertTrue(workflowSource.contains("Transcript failed. Review the original voice memo before converting."))
        XCTAssertTrue(workflowSource.contains("AI interpretation unavailable because transcription failed."))
        XCTAssertTrue(workflowSource.contains("No AI interpretation yet."))
        XCTAssertTrue(coreSource.contains("private var inboxCaptureRecordsByTaskID: [Int64: [InboxCaptureRecord]]"))
        XCTAssertTrue(coreSource.contains("$0.transcriptionStatus == .succeeded"))
        XCTAssertTrue(appSource.contains("inboxCaptureStore: SQLiteInboxCaptureStore(connection: connection)"))
        XCTAssertTrue(appSource.contains("Window(\"Voice Command\", id: \"voice-capture\")"))
    }

    func testInboxSelectionKeepsTriageInWorkflowInsteadOfInspector() throws {
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let workflowSource = try readProjectWorkflowSources()

        XCTAssertTrue(boardSource.contains("InboxWorkflowView(viewModel: viewModel, selectInboxTask: selectInboxTask)"))
        XCTAssertTrue(boardSource.contains("selectedDestination != .today && selectedDestination != .inbox"))
        XCTAssertTrue(boardSource.contains("private func selectInboxTask(_ task: ProjectBoardTask)"))
        XCTAssertTrue(boardSource.contains("isInspectorPresented = false"))
        XCTAssertTrue(boardSource.contains("isInspectorPresented = selectedDestination != .today && selectedDestination != .inbox"))
        XCTAssertTrue(workflowSource.contains("var selectInboxTask: (ProjectBoardTask) -> Void = { _ in }"))
        XCTAssertTrue(workflowSource.contains("onSelectTask: selectInboxTask"))
        XCTAssertTrue(workflowSource.contains("memoDraft: $voiceMemoDraft"))
        XCTAssertTrue(workflowSource.contains("memoCaptureID: $voiceMemoCaptureID"))
        XCTAssertTrue(workflowSource.contains(".frame(minWidth: 300, idealWidth: 320, maxWidth: 360"))

        let overrideStart = try XCTUnwrap(boardSource.range(of: "private func applySelectedTaskOverrideIfNeeded()"))
        let overrideEnd = try XCTUnwrap(boardSource[overrideStart.lowerBound...].range(of: "private func selectTodayTask"))
        let overrideBlock = String(boardSource[overrideStart.lowerBound..<overrideEnd.lowerBound])
        XCTAssertTrue(overrideBlock.contains("isInspectorPresented = selectedDestination != .today && selectedDestination != .inbox"))
        XCTAssertFalse(overrideBlock.contains("isInspectorPresented = true"))
    }

    func testInboxAndTodayWorkflowsExposeKeyboardAndVoiceOverAnchors() throws {
        let workflowSource = try readProjectWorkflowSources()
        let audit = try readPackageFile("docs/ux/click-path-audit.md")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")

        XCTAssertTrue(workflowSource.contains("viewModel.toggleTaskCompletion(id: task.id)"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"workflow-task-completion-\\(task.id)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityLabel(toggleCompletionAccessibilityLabel)"))
        XCTAssertTrue(workflowSource.contains("localizedDisplay(\"Reopen task %@\", task.title)"))
        XCTAssertTrue(workflowSource.contains("localizedDisplay(\"Complete task %@\", task.title)"))
        XCTAssertTrue(workflowSource.contains(".accessibilityHint(\"Updates the task status in the local SoloPM database without opening the inspector.\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-quick-add-title\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-quick-add-button\")"))
        XCTAssertTrue(workflowSource.contains(".keyboardShortcut(.return, modifiers: [.command])"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"workflow-task-row-\\(task.id)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityLabel(\"Open task \\(task.title)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityValue(workflowAccessibilityValue)"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-action-panel\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-action-make-task\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-action-make-project\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-action-schedule-today\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-action-review-later\")"))
        XCTAssertTrue(workflowSource.contains(".keyboardShortcut(\"1\", modifiers: [.command])"))
        XCTAssertTrue(workflowSource.contains(".keyboardShortcut(\"2\", modifiers: [.command])"))
        XCTAssertTrue(workflowSource.contains(".keyboardShortcut(\"3\", modifiers: [.command])"))
        XCTAssertTrue(workflowSource.contains(".keyboardShortcut(\"4\", modifiers: [.command])"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-classification-undo\")"))

        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-suggestion-panel\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-plan-summary\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-focus-recommendation\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-count-badge-\\(label.lowercased())\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-time-block-list\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-time-block-row-\\(block.id)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"catch-up-missed-review-panel\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"catch-up-state-error\")"))
        XCTAssertTrue(workflowSource.contains("CatchUpCountBadge(label: \"Due Today\", value: summary.dueTodayCount"))
        XCTAssertTrue(workflowSource.contains("CatchUpCountBadge(label: \"Stale\", value: summary.staleCount"))
        XCTAssertTrue(workflowSource.contains("label.lowercased().replacingOccurrences(of: \" \", with: \"-\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"catch-up-missed-count-badge-\\(identifierSuffix)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"catch-up-missed-review-row-\\(item.task.id)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"catch-up-missed-complete-\\(item.task.id)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"catch-up-missed-reschedule-\\(item.task.id)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"catch-up-missed-defer-\\(item.task.id)\")"))

        XCTAssertTrue(audit.contains("Inbox / Todayのrow完了toggle"))
        XCTAssertTrue(audit.contains("Inbox / Todayのrow、Quick Add、分類action、Today summary、time blockにsource-level accessibility identifiers / hints / keyboard anchorsを追加済み"))
        XCTAssertTrue(phase.contains("[x] Inbox / Today workflowのrow完了toggleを追加し、選択済みinspectorを開かずにlocal SQLite task statusをDoneへ移せる。"))
        XCTAssertTrue(phase.contains("[x] Inbox / Today workflowのrow、Quick Add、分類action、Today summary、time blockにsource-level accessibility identifiers / hints / keyboard anchorsを付ける。"))
    }

    func testProjectDetailOrganizesTasksArtifactsTimelineAndSuggestions() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let coreSource = try readPackageFile("Sources/SoloPMCore/App/ProjectBoard.swift")
        let modelSource = try readPackageFile("Sources/SoloPMCore/WorkManagement/WorkManagementModels.swift")
        let storeSource = try readPackageFile("Sources/SoloPMCore/WorkManagement/WorkManagementStore.swift")
        let sqliteStoreSource = try readPackageFile("Sources/SoloPMCore/WorkManagement/WorkManagementSQLiteStore.swift")

        XCTAssertTrue(source.contains("case overview"))
        XCTAssertTrue(source.contains("ProjectDetailOverview("))
        XCTAssertTrue(source.contains("ProjectProgressOverview"))
        XCTAssertTrue(source.contains("ProjectTaskSnapshotSection"))
        XCTAssertTrue(source.contains("ProjectArtifactSection"))
        XCTAssertTrue(source.contains("ProjectArtifactSection(project: project, viewModel: viewModel)"))
        XCTAssertTrue(source.contains("Track Artifact"))
        XCTAssertTrue(source.contains("viewModel.createProjectArtifact"))
        XCTAssertTrue(source.contains("Remove artifact link"))
        XCTAssertTrue(source.contains("viewModel.deleteProjectArtifact"))
        XCTAssertTrue(source.contains("Section(\"Project Directory\")"))
        XCTAssertTrue(source.contains("chooseProjectDirectory()"))
        XCTAssertTrue(source.contains("viewModel.assignProjectWorkspacePath"))
        XCTAssertTrue(source.contains("viewModel.clearProjectWorkspacePath"))
        XCTAssertTrue(source.contains("viewModel.reportProjectWorkspaceSelectionFailure"))
        XCTAssertFalse(source.contains("let bookmarkData = try? url.bookmarkData"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-workspace-current\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-workspace-choose\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-workspace-clear\")"))
        XCTAssertTrue(source.contains("Section(\"Development Automation\")"))
        XCTAssertTrue(source.contains("ProjectDevelopmentAutomationPanel("))
        XCTAssertTrue(source.contains("onReviewDevelopmentAutomation: onReviewDevelopmentAutomation"))
        XCTAssertTrue(source.contains("viewModel.developmentAutomationReadiness(for: project, task: viewModel.selectedTask)"))
        XCTAssertTrue(source.contains("viewModel.prepareDevelopmentAutomationReview(for: project, task: viewModel.selectedTask)"))
        XCTAssertTrue(source.contains("developmentAutomationReviewSession(plan)"))
        XCTAssertTrue(source.contains("ActionReviewPanel(viewModel: sheet.viewModel)"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-status\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-branch-preview\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-review\")"))
        XCTAssertTrue(source.contains("viewModel.enqueueDevelopmentAutomationReview(for: project, task: viewModel.selectedTask)"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-queue\")"))
        XCTAssertTrue(source.contains("viewModel.enqueueDevelopmentVerificationReview(for: project, task: viewModel.selectedTask)"))
        XCTAssertTrue(source.contains("Queue verification review"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-verification-queue\")"))
        XCTAssertTrue(source.contains("Repository edit review"))
        XCTAssertTrue(source.contains("viewModel.enqueueDevelopmentRepositoryEditReview("))
        XCTAssertTrue(source.contains("developmentProgress.canQueueRepositoryEditReview"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-edit-operation\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-edit-path\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-edit-expected-sha\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-edit-contents\")"))
        XCTAssertTrue(source.contains("viewModel.developmentRepositoryEditPreview("))
        XCTAssertTrue(coreSource.contains("Reviewed Change Scope"))
        XCTAssertTrue(coreSource.contains("Reviewed Replacement"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-edit-preview\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-edit-preview-row-\\(row.id)\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-edit-queue\")"))
        XCTAssertTrue(source.contains("viewModel.enqueueDevelopmentCommitReview("))
        XCTAssertTrue(source.contains("Queue commit review"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-commit-paths\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-commit-message\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-commit-queue\")"))
        XCTAssertTrue(source.contains("viewModel.enqueueDevelopmentPushReview(for: project, task: viewModel.selectedTask)"))
        XCTAssertTrue(source.contains("Queue branch push review"))
        XCTAssertTrue(source.contains("execution rechecks the current branch, clean workspace, and GitHub origin before running"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-push-queue\")"))
        XCTAssertTrue(source.contains("viewModel.developmentPullRequestCreationDraft(for: project, task: viewModel.selectedTask)"))
        XCTAssertTrue(source.contains("viewModel.enqueueDevelopmentPullRequestCreationReview("))
        XCTAssertTrue(source.contains("Queue pull request creation review"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-pr-base\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-pr-title\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-pr-body\")"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Pull request body\")"))
        XCTAssertTrue(source.contains("developmentProgress.canQueuePullRequestCreationReview"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-pr-create-queue\")"))
        XCTAssertTrue(source.contains("viewModel.developmentAutomationProgress(for: project, task: viewModel.selectedTask)"))
        XCTAssertTrue(source.contains("Pull request progress"))
        XCTAssertTrue(source.contains("developmentProgress.nextApproval"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-next-approval\")"))
        XCTAssertTrue(source.contains("developmentProgress.approvalPreview"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-approval-preview\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-approval-preview-row-\\(row.id)\")"))
        XCTAssertTrue(source.contains("developmentProgress.queueHandoff"))
        XCTAssertTrue(source.contains("Assistant Queue handoff"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-queue-handoff\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-queue-handoff-capability-\\(index)\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-progress\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-progress-stage-\\(stage.id)\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-progress-pr-url\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-progress-base\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-progress-commit\")"))
        XCTAssertTrue(source.contains("developmentProgress.canQueuePullRequestReviewGate"))
        XCTAssertTrue(source.contains("developmentProgress.canQueuePullRequestMergeGate"))
        XCTAssertTrue(source.contains("viewModel.enqueueDevelopmentPullRequestLifecycleReview("))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-pr-review-queue\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-pr-merge-queue\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-review-sheet\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-step-\\(index)\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-lifecycle-tool-\\(index)\")"))
        XCTAssertTrue(source.contains("readiness.lifecycleToolNames"))
        XCTAssertTrue(source.contains("readiness.approvalBoundaryLabel"))
        XCTAssertTrue(coreSource.contains("development.pr_workflow.prepare"))
        XCTAssertTrue(coreSource.contains("ActionTool.developmentMergePullRequest.rawValue"))
        XCTAssertTrue(coreSource.contains("public var lifecycleToolNames: [String]"))
        XCTAssertTrue(coreSource.contains("public var approvalBoundaryLabel: String"))
        XCTAssertTrue(coreSource.contains("public struct ProjectDevelopmentAutomationProgress"))
        XCTAssertTrue(coreSource.contains("public struct ProjectDevelopmentAutomationNextApproval"))
        XCTAssertTrue(coreSource.contains("public func prepareDevelopmentVerificationReview("))
        XCTAssertTrue(coreSource.contains("public func prepareDevelopmentCommitReview("))
        XCTAssertTrue(coreSource.contains("public func developmentAutomationProgress("))
        XCTAssertTrue(coreSource.contains("ExecutionReceiptSearchFilter("))
        XCTAssertTrue(coreSource.contains(".developmentBaseBranch"))
        XCTAssertFalse(source.contains("project-development-automation-delete"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-artifact-path\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-artifact-track\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-artifact-remove-\\(artifact.id)\")"))
        XCTAssertTrue(source.contains("ProjectTimelineSection"))
        XCTAssertTrue(source.contains("ProjectLocalSuggestionPanel"))
        XCTAssertTrue(source.contains("project.artifacts"))
        XCTAssertTrue(modelSource.contains("public struct ProjectBoardArtifact"))
        XCTAssertTrue(modelSource.contains("public var hasWorkspaceDirectory: Bool"))
        XCTAssertTrue(modelSource.contains("public var hasWorkspaceBookmark: Bool"))
        XCTAssertTrue(modelSource.contains("public var workspaceDisplayName: String?"))
        XCTAssertTrue(coreSource.contains("public struct ProjectDevelopmentAutomationReadiness"))
        XCTAssertTrue(coreSource.contains("public func developmentAutomationReadiness("))
        XCTAssertTrue(coreSource.contains("public func prepareDevelopmentAutomationReview("))
        XCTAssertTrue(coreSource.contains("ActionPlan("))
        XCTAssertTrue(coreSource.contains(".developmentPreparePullRequestWorkflow"))
        XCTAssertTrue(modelSource.contains("public var artifacts: [ProjectBoardArtifact]"))
        XCTAssertTrue(storeSource.contains("func setProjectWorkspacePath(id: Int64, path: String?, bookmarkData: Data?) throws -> ProjectBoardProject"))
        XCTAssertFalse(coreSource.contains("ProjectBoardProject: Identifiable, Equatable, Sendable {\n    public var id: Int64\n    public var title: String\n    public var status: String\n    public var subtitle: String\n    public var workspacePath: String?"))
        XCTAssertTrue(storeSource.contains("func createProjectArtifact(projectID: Int64, expectedPath: String) throws -> ProjectBoardArtifact"))
        XCTAssertTrue(storeSource.contains("func deleteProjectArtifact(id: Int64) throws"))
        XCTAssertTrue(sqliteStoreSource.contains("SQLiteArtifactStore(connection: connection)"))
    }

    func testProjectDetailSurfacesMilestonesTimelineAndAssistantWithoutDroppingExistingSections() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let coreSource = try readPackageFile("Sources/SoloPMCore/App/ProjectBoard.swift")
        let modelSource = try readPackageFile("Sources/SoloPMCore/WorkManagement/WorkManagementModels.swift")

        XCTAssertTrue(source.contains("ProjectMilestoneSection(project: project, viewModel: viewModel)"))
        XCTAssertTrue(source.contains("ProjectAssistantPanel(project: project, viewModel: viewModel)"))
        XCTAssertTrue(source.contains("ProjectArtifactSection(project: project, viewModel: viewModel)"))
        XCTAssertTrue(source.contains("ProjectLocalSuggestionPanel(project: project, viewModel: viewModel)"))
        XCTAssertTrue(source.contains("project.milestones"))
        XCTAssertTrue(source.contains("case .milestone"))
        XCTAssertTrue(source.contains("viewModel.createProjectMilestone"))
        XCTAssertTrue(source.contains("viewModel.answerProjectAssistantQuestion"))
        XCTAssertTrue(source.contains("viewModel.prepareProjectAssistantSuggestedActionForReview"))
        XCTAssertFalse(source.contains("moveTask(id: suggestedTask.id, to: .inProgress)"))

        XCTAssertTrue(modelSource.contains("public struct ProjectBoardMilestone"))
        XCTAssertTrue(modelSource.contains("public var milestones: [ProjectBoardMilestone]"))
        XCTAssertTrue(coreSource.contains("ProjectAssistantReviewDraft"))
    }

    func testTaskInspectorGroupsEditingDeletionAndSuggestionApplication() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")

        XCTAssertTrue(source.contains("TaskInspectorSuggestionSection"))
        XCTAssertTrue(source.contains("Apply Suggestion"))
        XCTAssertTrue(source.contains("viewModel.moveSelectedTask(to:"))
        XCTAssertTrue(source.contains("Section(\"Edit\")"))
        XCTAssertTrue(source.contains("Section(\"Suggestion\")"))
        XCTAssertTrue(source.contains("Section(\"Danger Zone\")"))
    }

    func testProjectInspectorGroupsEditingDeletionAndSuggestionApplication() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let headerStart = try XCTUnwrap(source.range(of: "private struct ProjectHeaderActions"))
        let boardStart = try XCTUnwrap(source.range(of: "private struct ProjectKanbanBoard"))
        let headerSource = String(source[headerStart.lowerBound..<boardStart.lowerBound])

        XCTAssertTrue(source.contains("ProjectInspectorView("))
        XCTAssertTrue(source.contains("project: project,"))
        XCTAssertTrue(source.contains("viewModel: viewModel,"))
        XCTAssertTrue(source.contains("onClose: { inspectorBinding.wrappedValue = false }"))
        XCTAssertTrue(source.contains("ProjectInspectorSuggestionSection"))
        XCTAssertTrue(source.contains("@State private var isInspectorPresented = true"))
        XCTAssertTrue(source.contains("selectedProjectForInspector"))
        XCTAssertTrue(source.contains("isInspectorPresented = false"))
        XCTAssertTrue(source.contains("viewModel.updateSelectedProject(title: title)"))
        XCTAssertTrue(source.contains("viewModel.deleteSelectedProject()"))
        XCTAssertTrue(source.contains("viewModel.archiveSelectedProject()"))
        XCTAssertTrue(source.contains("viewModel.restoreSelectedProject()"))
        XCTAssertTrue(source.contains("viewModel.completeSelectedProject()"))
        XCTAssertTrue(source.contains("viewModel.createTask(title: localizedDisplay(\"Define next action\")"))
        XCTAssertTrue(source.contains("viewModel.selectedTaskID = taskID"))
        XCTAssertTrue(source.contains("Section(\"Edit\")"))
        XCTAssertTrue(source.contains("Section(\"Suggestion\")"))
        XCTAssertTrue(source.contains("Section(\"Actions\")"))
        XCTAssertTrue(source.contains("Section(\"Danger Zone\")"))
        XCTAssertFalse(source.contains("ProjectHeaderTitleEditor"))
        XCTAssertFalse(headerSource.contains("Delete Project"))
        XCTAssertFalse(headerSource.contains("Archive Project"))
        XCTAssertFalse(headerSource.contains("Complete Project"))
    }

    func testBoardAccessibilityLabelsHelpAndDestructiveConfirmations() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")

        XCTAssertTrue(source.contains(".accessibilityElement(children: .combine)"))
        XCTAssertTrue(source.contains(".accessibilityElement(children: .contain)"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Open task \\(task.title)\")"))
        XCTAssertTrue(source.contains(".accessibilityValue(accessibilityValueText)"))
        XCTAssertTrue(source.contains(".accessibilityHint(\"Opens task details in the inspector. Task inspector fields can then be edited without dragging.\")"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Status controls for \\(task.title)\")"))
        XCTAssertTrue(source.contains(".accessibilityHint(\"Moves the task between board columns.\")"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Add task to \\(column.title)\")"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Add task to empty \\(column.title) column\")"))
        XCTAssertGreaterThanOrEqual(source.components(separatedBy: ".accessibilityLabel(\"Add task to \\(project.title)\")").count - 1, 2)
        XCTAssertGreaterThanOrEqual(source.components(separatedBy: ".accessibilityHint(\"Opens the inline composer for a new local task.\")").count - 1, 2)
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Current status: \\(task.status.title)\")"))
        XCTAssertTrue(source.contains(".accessibilityHint(\"Changes \\(task.title) status.\")"))
        XCTAssertTrue(source.contains(".help(\"Show archived projects\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-board-show-archived\")"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Show archived projects\")"))
        XCTAssertTrue(source.contains(".accessibilityValue(viewModel.showsArchivedProjects ? \"On\" : \"Off\")"))
        XCTAssertTrue(source.contains(".accessibilityHint(\"Shows archived projects in the sidebar without deleting local data.\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-board-add-project\")"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Add Project\")"))
        XCTAssertTrue(source.contains(".accessibilityHint(\"Creates a new local project and selects it.\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-header-add-task\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(targetStatus.map { \"task-status-move-\\($0.rawValue)-\\(task.id)\" } ?? \"task-status-move-disabled-\\(task.id)\")"))
        XCTAssertTrue(source.contains(".help(\"Creates the task in the local SoloPM database\")"))
        XCTAssertTrue(source.contains(".help(\"Cancels task creation and returns focus to the board column\")"))
        XCTAssertTrue(source.contains(".help(\"Applies the local next-step suggestion to the selected task\")"))
        XCTAssertTrue(source.contains(".help(\"Saves edits to the selected task in the local SoloPM database\")"))
        XCTAssertTrue(source.contains(".help(\"Deletes the selected task after confirmation\")"))
        XCTAssertTrue(source.contains(".help(\"Applies the local next-step suggestion to the selected project\")"))
        XCTAssertTrue(source.contains(".help(\"Saves edits to the selected project in the local SoloPM database\")"))
        XCTAssertTrue(source.contains(".help(\"Restores the selected project to active views in the local SoloPM database\")"))
        XCTAssertTrue(source.contains(".help(\"Completes the selected project in the local SoloPM database\")"))
        XCTAssertTrue(source.contains(".help(\"Archives the selected project after confirmation\")"))
        XCTAssertTrue(source.contains(".help(\"Deletes the selected project after confirmation\")"))
        XCTAssertTrue(source.contains("\"Archive this project?\""))
        XCTAssertTrue(source.contains("\"Delete this project?\""))
        XCTAssertTrue(source.contains("\"Delete this task?\""))
    }

    func testProjectBoardVoiceOverFocusPathIsSourceAnchored() throws {
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let workflowSource = try readProjectWorkflowSources()
        let audit = try readPackageFile("docs/ux/click-path-audit.md")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")

        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"project-board-sidebar\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityLabel(\"Project navigation\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityHint(\"Select Inbox, Today, or a project before moving to the board detail.\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"sidebar-destination-\\(destination.accessibilityIdentifierSuffix)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityLabel(destination.accessibilityLabel(count: count))"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"project-sidebar-row-\\(project.id)\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityLabel(project.accessibilitySidebarLabel)"))
        XCTAssertTrue(boardSource.contains("let onSelect: () -> Void"))
        XCTAssertTrue(boardSource.contains("onSelect: { selectedDestination = .project(project.id) }"))
        XCTAssertTrue(boardSource.contains(".contentShape(Rectangle())"))
        XCTAssertTrue(boardSource.contains(".onTapGesture(perform: onSelect)"))
        XCTAssertTrue(boardSource.contains(".accessibilityAction(.default, onSelect)"))

        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"project-board-detail\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityLabel(\"Project board for \\(project.title)\")"))
        XCTAssertTrue(boardSource.contains(".accessibilitySortPriority(3)"))
        XCTAssertTrue(boardSource.contains(".accessibilitySortPriority(2)"))
        XCTAssertTrue(boardSource.contains(".accessibilitySortPriority(1)"))

        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"task-inspector\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityLabel(\"Task inspector for \\(task.title)\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"task-inspector-title\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"task-inspector-detail\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"task-inspector-status\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"task-inspector-priority\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"task-inspector-due\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"task-inspector-apply-suggestion\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"task-inspector-save\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"task-inspector-delete\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityHint(\"Applies the local next-step suggestion to the selected task.\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityHint(\"Saves edits to the selected task in the local SoloPM database.\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityHint(\"Deletes the selected task after confirmation.\")"))

        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"project-inspector\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityLabel(\"Project inspector for \\(project.title)\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"project-inspector-title\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"project-inspector-apply-suggestion\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"project-inspector-save\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"project-inspector-complete\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"project-inspector-restore\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"project-inspector-archive\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"project-inspector-delete\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityHint(\"Applies the local next-step suggestion to the selected project.\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityHint(\"Completes the selected project in the local SoloPM database.\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityHint(\"Archives the selected project after confirmation.\")"))
        XCTAssertTrue(audit.contains("source-level VoiceOver focus anchors are fixed"))
        XCTAssertTrue(audit.contains("Task / Project inspectorのfield、提案適用、保存、complete、restore、archive、deleteはaccessibility identifier / hintを持ち"))
        XCTAssertTrue(phase.contains("[x] Sidebar -> board detail -> task card -> inspector edit/save/delete のsource-level focus anchorsを固定する。"))
        XCTAssertTrue(phase.contains("[x] Task / Project inspector のfield、提案適用、save、complete、restore、archive、deleteにaccessibility identifier / hintを付け"))
        XCTAssertTrue(phase.contains("[ ] 実機VoiceOverでProject board -> card -> Inline Task Composer -> inspectorのfocus orderを確認する。"))
    }

    func testProjectOverviewActionsAreAccessibleCrudEntryPoints() throws {
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let audit = try readPackageFile("docs/ux/click-path-audit.md")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")

        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"project-overview-task-open-\\(task.id)\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityLabel(\"Open task \\(task.title)\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityHint(\"Opens the task inspector from the project overview.\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"project-overview-add-task\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"project-local-suggestion-open-task\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityHint(\"Opens the suggested task in the inspector.\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"project-local-suggestion-review-action\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityHint(\"Prepares the suggested blocked task action for review without writing task status.\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityLabel(\"Project timeline item \\(item.title)\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityLabel(\"Track artifact path\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityLabel(\"Track artifact link\")"))
        XCTAssertTrue(audit.contains("Project OverviewのTask snapshot、Local Suggestions、Artifactsはaccessibility identifier / label / hint付きのCRUD入口になっている"))
        XCTAssertTrue(phase.contains("[x] Project OverviewのTask snapshot、Local Suggestions、Artifactsにaccessibility identifier / label / hintを付け、Overviewからも支援技術で主要CRUDへ入れる。"))
    }

    func testVoiceOverEvidenceCapturesPassedReleaseCandidateContextAndFailureNotes() throws {
        let evidence = try readPackageFile("docs/release/evidence/accessibility-voiceover.md")
        let generator = try readPackageFile("script/create_voiceover_evidence.sh")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")

        XCTAssertTrue(evidence.contains("Status: passed"))
        XCTAssertTrue(evidence.contains("Generated by: script/create_voiceover_evidence.sh"))
        XCTAssertTrue(evidence.contains("## Release Candidate Context"))
        XCTAssertTrue(evidence.contains("- macOS version: macOS "))
        XCTAssertTrue(evidence.contains("- App build: `0.1.0 (1)`"))
        XCTAssertTrue(evidence.contains("- Bundle identifier: `dev.solopm.app`"))
        XCTAssertTrue(evidence.contains("- Source commit: `"))
        XCTAssertTrue(evidence.contains("- Checked by: Codex local AX and VoiceOver review"))
        XCTAssertTrue(evidence.contains("- Check date:"))
        XCTAssertTrue(evidence.contains("- Evidence source: `dist/SoloPM.app manual VoiceOver pass using isolated .tmp voiceover review database project:119`"))
        XCTAssertFalse(evidence.contains("/Users/"))
        XCTAssertFalse(evidence.contains("/Volumes/"))
        XCTAssertFalse(evidence.contains("file://"))
        XCTAssertTrue(evidence.contains("- Runtime AX smoke: OK: runtime AX smoke visible"))
        XCTAssertTrue(evidence.contains("unlabeledButtons=0"))
        XCTAssertTrue(evidence.contains("genericButtons=0"))
        XCTAssertTrue(evidence.contains("crudSignals=8/8"))
        XCTAssertTrue(evidence.contains("focusPathSignals=6/6"))
        XCTAssertTrue(evidence.contains("## Verified Focus Path"))
        XCTAssertTrue(evidence.contains("Project navigation: passed"))
        XCTAssertTrue(evidence.contains("Project board detail: passed"))
        XCTAssertTrue(evidence.contains("Open task: passed"))
        XCTAssertTrue(evidence.contains("Inline Task Composer: passed"))
        XCTAssertTrue(evidence.contains("Status controls: passed"))
        XCTAssertTrue(evidence.contains("Task inspector: passed"))
        XCTAssertTrue(evidence.contains("Delete Task confirmation: passed"))
        XCTAssertTrue(evidence.contains("inline confirmation text Delete this task?"))
        XCTAssertFalse(evidence.contains("confirmation dialogs"))
        XCTAssertTrue(evidence.contains("## Failure Notes"))
        XCTAssertTrue(evidence.contains("- Blocker observed: none during the manual VoiceOver pass."))
        XCTAssertTrue(evidence.contains("- Follow-up source/test link:"))
        XCTAssertFalse(evidence.contains("Status: pending"))
        XCTAssertFalse(evidence.contains("[ ]"))
        XCTAssertFalse(evidence.contains("Do not set `Status: passed`"))
        XCTAssertFalse(evidence.contains("## Completion Instructions"))
        XCTAssertTrue(generator.contains("usage:"))
        XCTAssertTrue(generator.contains("VOICEOVER_STATUS=\"pending\""))
        XCTAssertTrue(generator.contains("--confirm-manual-voiceover-pass"))
        XCTAssertTrue(generator.contains("Project navigation: passed"))
        XCTAssertTrue(generator.contains("Inline Task Composer: passed"))
        XCTAssertTrue(generator.contains("inline inspector confirmation panel"))
        XCTAssertFalse(generator.contains("confirmation dialogs"))
        XCTAssertTrue(generator.contains("No unlabeled primary CRUD controls: passed"))
        XCTAssertTrue(generator.contains("Status: passed"))
        XCTAssertTrue(generator.contains("Status: pending"))
        XCTAssertTrue(generator.contains("BUNDLE_IDENTIFIER"))
        XCTAssertTrue(generator.contains("CURRENT_PROJECT_VERSION"))
        XCTAssertTrue(generator.contains("MARKETING_VERSION"))
        XCTAssertTrue(phase.contains("[x] `release_readiness_report.sh` はVoiceOver証跡のrelease-candidate context空欄/テンプレート値をblockerにする。"))
        XCTAssertTrue(phase.contains("[x] `release_readiness_report.sh` とVoiceOver証跡generatorはInline Task Composerの作成/cancel導線を必須focus pathに含める。"))
        XCTAssertTrue(phase.contains("[x] `docs/release/evidence/accessibility-voiceover.md` は実機確認者がmacOS/build/checked-by/failure notesを埋められる形にする。"))
    }

    func testTodayWorkflowShowsRecommendationDueCountsAndTimeBlocks() throws {
        let workflowSource = try readProjectWorkflowSources()
        let coreSource = try readPackageFile("Sources/SoloPMCore/App/ProjectBoard.swift")
        let modelSource = try readPackageFile("Sources/SoloPMCore/WorkManagement/WorkManagementModels.swift")
        let dailyPlanningSource = try readPackageFile("Sources/SoloPMCore/App/DailyPlanningReview.swift")
        let dailyPlanningDraftSource = try readPackageFile("Sources/SoloPMCore/App/DailyPlanningActionDraft.swift")
        let missedReviewSource = try readPackageFile("Sources/SoloPMCore/App/MissedTaskReview.swift")

        XCTAssertTrue(workflowSource.contains("TodayCommandPanel"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-command-capture-field\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-command-add\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-suggestion-chip-"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-start-focus\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-schedule-draft-button\")"))
        XCTAssertTrue(workflowSource.contains("TodayPlanSummary"))
        XCTAssertTrue(workflowSource.contains("TodayTimeBlockList"))
        XCTAssertTrue(workflowSource.contains("TodayAssistantRail"))
        XCTAssertTrue(workflowSource.contains("TodayDailyPlanningReviewPanel"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-daily-planning-review\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-daily-planning-focus-"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-daily-planning-draft-start\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-daily-planning-draft-defer\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-daily-planning-draft-move-today\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-daily-planning-draft-split\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-daily-planning-readout\")"))
        XCTAssertTrue(workflowSource.contains("playDailyPlanningReadout()"))
        XCTAssertTrue(workflowSource.contains("viewModel.enqueueDailyPlanningActionDraft(kind: .startRecommended)"))
        XCTAssertTrue(workflowSource.contains("viewModel.enqueueDailyPlanningActionDraft(kind: .deferRecommendedToTomorrow)"))
        XCTAssertTrue(workflowSource.contains("viewModel.enqueueDailyPlanningActionDraft(kind: .moveRecommendedDueDateToToday)"))
        XCTAssertTrue(workflowSource.contains("viewModel.enqueueDailyPlanningActionDraft(kind: .splitRecommendedTask)"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-assistant-rail\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-rail-next-action\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-rail-task-detail\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-rail-focus\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-rail-schedule-block\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-rail-edit-task\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-rail-add-subtask\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-rail-reminder-draft\")"))
        XCTAssertTrue(workflowSource.contains("viewModel.enqueueTodayReminderDraft(for: task.id)"))
        XCTAssertTrue(workflowSource.contains("plan.overdueCount"))
        XCTAssertTrue(workflowSource.contains("plan.dueTodayCount"))
        XCTAssertTrue(workflowSource.contains("viewModel.derivedReadModels.missedTaskReview"))
        XCTAssertTrue(workflowSource.contains("CatchUpWorkflowView"))
        XCTAssertTrue(workflowSource.contains("CatchUpMissedTaskReviewPanel"))
        XCTAssertTrue(workflowSource.contains("summary.immediateQueue"))
        XCTAssertTrue(workflowSource.contains("viewModel.completeMissedTask(id: item.task.id)"))
        XCTAssertTrue(workflowSource.contains("viewModel.rescheduleMissedTaskForToday(id: item.task.id)"))
        XCTAssertTrue(workflowSource.contains("viewModel.deferMissedTaskForLater(id: item.task.id)"))
        XCTAssertTrue(workflowSource.contains("plan.recommendationReason"))
        XCTAssertTrue(workflowSource.contains("ForEach(plan.timeBlocks)"))
        XCTAssertTrue(modelSource.contains("public struct TodayWorkflowPlan"))
        XCTAssertTrue(modelSource.contains("public struct TodayTimeBlock"))
        XCTAssertTrue(dailyPlanningSource.contains("public struct DailyPlanningReview"))
        XCTAssertTrue(dailyPlanningSource.contains("public enum DailyPlanningReviewBoundary"))
        XCTAssertTrue(coreSource.contains("DailyPlanningReviewReadoutBuilder.makeRequest"))
        XCTAssertTrue(dailyPlanningDraftSource.contains("public enum DailyPlanningActionDraftKind"))
        XCTAssertTrue(dailyPlanningDraftSource.contains("case moveRecommendedDueDateToToday"))
        XCTAssertTrue(dailyPlanningDraftSource.contains("case splitRecommendedTask"))
        XCTAssertTrue(dailyPlanningDraftSource.contains("DailyPlanningActionDraftBuilder"))
        XCTAssertTrue(dailyPlanningDraftSource.contains("tool: .taskUpdate"))
        XCTAssertTrue(dailyPlanningDraftSource.contains("tool: .taskCreate"))
        XCTAssertFalse(dailyPlanningDraftSource.contains("calendarCreate"))
        XCTAssertTrue(modelSource.contains("public struct TodayAssistantRailContext"))
        XCTAssertTrue(modelSource.contains("public enum TodayAssistantRailSource"))
        XCTAssertTrue(missedReviewSource.contains("public struct MissedTaskReviewSummary"))
        XCTAssertTrue(missedReviewSource.contains("public struct MissedTaskReviewItem"))
        XCTAssertTrue(missedReviewSource.contains("public enum MissedTaskReviewReason"))
        XCTAssertTrue(missedReviewSource.contains("public protocol MissedTaskReviewStateStore"))
        XCTAssertTrue(coreSource.contains("public func missedTaskReview("))
        XCTAssertTrue(coreSource.contains("public func completeMissedTask"))
        XCTAssertTrue(coreSource.contains("public func rescheduleMissedTaskForToday"))
        XCTAssertTrue(coreSource.contains("public func deferMissedTaskForLater"))
        XCTAssertTrue(modelSource.contains("public struct TodayRecommendationChip"))
        XCTAssertTrue(modelSource.contains("public struct TodayScheduleDraft"))
        XCTAssertTrue(coreSource.contains("public func submitTodayCommand"))
        XCTAssertTrue(coreSource.contains("public func todayRecommendationChips"))
        XCTAssertTrue(coreSource.contains("public func todayAssistantRailContext"))
        XCTAssertTrue(coreSource.contains("public func prepareDailyPlanningReview"))
        XCTAssertTrue(coreSource.contains("public func enqueueDailyPlanningActionDraft"))
        XCTAssertTrue(coreSource.contains("public func enqueueTodayReminderDraft"))
        XCTAssertTrue(coreSource.contains("ActionPlanValidator().validate(draft.actionPlan)"))
        XCTAssertTrue(coreSource.contains("public func startFocus"))
        XCTAssertTrue(coreSource.contains("public func prepareTodayScheduleDraft"))
        XCTAssertTrue(coreSource.contains("public func todayPlan("))
        let reviewPanelStart = try XCTUnwrap(workflowSource.range(of: "private struct TodayDailyPlanningReviewPanel"))
        let commandPanelStart = try XCTUnwrap(workflowSource.range(of: "private struct TodayCommandPanel"))
        let reviewPanelSource = String(workflowSource[reviewPanelStart.lowerBound..<commandPanelStart.lowerBound])
        XCTAssertFalse(reviewPanelSource.contains("applyScheduleDraftToCalendar"))
        XCTAssertFalse(reviewPanelSource.contains("startFocus("))
        XCTAssertFalse(reviewPanelSource.contains("AVSpeechSynthesizer"))
    }

    func testVoiceDailyPlanningReviewBridgeUsesLocalProjectBoardReview() throws {
        let voiceSource = try readPackageFile("Sources/SoloPMCore/Voice/VoiceCaptureViewModel.swift")
        let appSource = try readAppShellSource()
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")

        XCTAssertTrue(voiceSource.contains("public struct VoiceDailyPlanningReviewRequest"))
        XCTAssertTrue(voiceSource.contains("requestedActionDraftKind: DailyPlanningActionDraftKind?"))
        XCTAssertTrue(voiceSource.contains("DailyPlanningActionDraftKind.splitRecommendedTask"))
        XCTAssertTrue(voiceSource.contains("@Published public private(set) var dailyPlanningReviewRequest"))
        XCTAssertTrue(voiceSource.contains("routedCommand.intent != .dailyPlanningReview"))
        XCTAssertTrue(voiceSource.contains("beginDailyPlanningReviewRequest"))
        XCTAssertTrue(appSource.contains("viewModel.dailyPlanningReviewRequest"))
        XCTAssertTrue(appSource.contains("Queue a move-to-today draft for approval"))
        XCTAssertTrue(appSource.contains("Queue a split-task draft for approval"))
        XCTAssertTrue(appSource.contains("guard let bridgeRequest = SoloPMVoiceDailyPlanningReviewBridge.storePendingRequest(request)"))
        XCTAssertTrue(appSource.contains("name: .soloPMVoiceDailyPlanningReviewRequested"))
        XCTAssertTrue(appSource.contains("userInfo: [SoloPMVoiceDailyPlanningReviewBridge.requestUserInfoKey: bridgeRequest]"))
        XCTAssertFalse(appSource.contains("sourceTranscriptUserInfoKey"))
        XCTAssertTrue(boardSource.contains(".onReceive(NotificationCenter.default.publisher(for: .soloPMVoiceDailyPlanningReviewRequested))"))
        XCTAssertTrue(boardSource.contains("consumePendingVoiceDailyPlanningReviewRequestIfNeeded"))
        XCTAssertTrue(boardSource.contains("SoloPMVoiceDailyPlanningReviewBridge.consumePendingRequest()"))
        XCTAssertTrue(boardSource.contains("SoloPMVoiceDailyPlanningReviewBridge.hasRequestPayload(notification)"))
        XCTAssertTrue(boardSource.contains("SoloPMVoiceDailyPlanningReviewBridge.consumeRequest(from: notification)"))
        XCTAssertTrue(boardSource.contains("actionDraftKind: request.actionDraftKind"))
        XCTAssertTrue(boardSource.contains("handleVoiceDailyPlanningReviewRequest"))
        XCTAssertTrue(boardSource.contains("viewModel.prepareDailyPlanningReview(transcript:"))
        XCTAssertTrue(boardSource.contains("viewModel.enqueueDailyPlanningActionDraft("))
        XCTAssertTrue(boardSource.contains("kind: actionDraftKind"))
        XCTAssertTrue(boardSource.contains("playDailyPlanningReadoutFromSettings()"))
        XCTAssertTrue(boardSource.contains("viewModel.playDailyPlanningReviewReadout("))
        XCTAssertTrue(boardSource.contains("AppTextToSpeechRuntimeFactory.makePreviewer("))
        XCTAssertTrue(boardSource.contains("temporaryDirectoryPrefix: \"solopm-daily-planning-readout\""))
        XCTAssertTrue(boardSource.contains("outputFilename: \"readout.wav\""))
        XCTAssertTrue(boardSource.contains("selectedDestination = summary.newlyMissedCount > 0 ? .catchUp : .today"))
        XCTAssertTrue(boardSource.contains("static let soloPMVoiceDailyPlanningReviewRequested"))
        XCTAssertTrue(boardSource.contains("guard let request = SoloPMVoiceDailyPlanningReviewBridge.consumePendingRequest()"))
        XCTAssertFalse(boardSource.contains("sourceTranscript(from: notification)"))
        XCTAssertFalse(appSource.contains("calendarClient.create"))
        XCTAssertFalse(appSource.contains("reminderClient.create"))
        XCTAssertFalse(boardSource.contains("AVSpeechSynthesizer"))
    }

    func testTodayViewReadsPrecomputedDailyPlanningReviewWithoutRenderPathFallback() throws {
        let workflowSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectWorkflowTodayView.swift")
        let panelStart = try XCTUnwrap(workflowSource.range(of: "private struct TodayDailyPlanningReviewPanel"))
        let panelEnd = try XCTUnwrap(workflowSource.range(of: "private struct TodayCommandPanel"))
        let panelSource = String(workflowSource[panelStart.lowerBound..<panelEnd.lowerBound])

        XCTAssertFalse(panelSource.contains("makeDailyPlanningReview"))
        XCTAssertFalse(panelSource.contains("dailyWorkloadOverview"))
        XCTAssertTrue(workflowSource.contains("viewModel.dailyPlanningReview ?? snapshot.dailyPlanningReviewPreview"))
    }

    func testVoiceInboxTriageBridgeUsesLocalProjectBoardInboxCommands() throws {
        let voiceSource = try readPackageFile("Sources/SoloPMCore/Voice/VoiceCaptureViewModel.swift")
        let appSource = try readAppShellSource()
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")

        XCTAssertTrue(voiceSource.contains("public struct VoiceInboxTriageRequest"))
        XCTAssertTrue(voiceSource.contains("@Published public private(set) var inboxTriageRequest"))
        XCTAssertTrue(voiceSource.contains("InboxVoiceTriageCommandParser"))
        XCTAssertTrue(appSource.contains("viewModel.inboxTriageRequest"))
        XCTAssertTrue(appSource.contains("SoloPMVoiceInboxTriageBridge.storePendingRequest"))
        XCTAssertTrue(appSource.contains("name: .soloPMVoiceInboxTriageRequested"))
        XCTAssertTrue(boardSource.contains(".onReceive(NotificationCenter.default.publisher(for: .soloPMVoiceInboxTriageRequested))"))
        XCTAssertTrue(boardSource.contains("consumePendingVoiceInboxTriageRequestIfNeeded"))
        XCTAssertTrue(boardSource.contains("SoloPMVoiceInboxTriageBridge.consumePendingRequest()"))
        XCTAssertTrue(boardSource.contains("consumedRequestIDs"))
        XCTAssertTrue(boardSource.contains("handleVoiceInboxTriageRequest"))
        XCTAssertTrue(boardSource.contains("viewModel.applyInboxVoiceTriageCommand(request.command)"))
        let openStart = try XCTUnwrap(boardSource.range(of: "private func openInboxForVoiceTriage()"))
        let overrideStart = try XCTUnwrap(boardSource.range(of: "private func applySelectedTaskOverrideIfNeeded()"))
        let openSource = String(boardSource[openStart.lowerBound..<overrideStart.lowerBound])
        XCTAssertFalse(openSource.contains("ensureSelectedInboxTaskIsVisible"))
        XCTAssertFalse(appSource.contains("calendarClient.create"))
        XCTAssertFalse(appSource.contains("reminderClient.create"))
    }

    func testVoiceAssistantQueueApprovalHandoffsExecutionToProjectBoardQueue() throws {
        let voiceSource = try readPackageFile("Sources/SoloPMCore/Voice/VoiceCaptureViewModel.swift")
        let appSource = try readAppShellSource()
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let englishStrings = try readPackageFile("Sources/SoloPMApp/Resources/en.lproj/Localizable.strings")
        let japaneseStrings = try readPackageFile("Sources/SoloPMApp/Resources/ja.lproj/Localizable.strings")

        XCTAssertTrue(voiceSource.contains("assistantQueueExecutionHandoffItemID"))
        XCTAssertTrue(appSource.contains("executionHandoffItemID: viewModel.assistantQueueExecutionHandoffItemID"))
        XCTAssertTrue(appSource.contains("onOpenQueue: { postAssistantQueueOpenRequest() }"))
        XCTAssertTrue(appSource.contains("SoloPMAssistantQueueBridge.storePendingOpen(itemID: viewModel.assistantQueueExecutionHandoffItemID)"))
        XCTAssertTrue(appSource.contains("userInfo: [SoloPMAssistantQueueBridge.requestUserInfoKey: bridgeRequest]"))
        XCTAssertTrue(appSource.contains("name: .soloPMAssistantQueueRequested"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"voice-assistant-queue-open-board\")"))
        XCTAssertTrue(appSource.contains(".accessibilityHint(localizedSettingsDisplay(\"Opens the Assistant Queue without running the item.\"))"))
        XCTAssertTrue(boardSource.contains(".onReceive(NotificationCenter.default.publisher(for: .soloPMAssistantQueueRequested))"))
        XCTAssertTrue(boardSource.contains("consumePendingAssistantQueueRequestIfNeeded"))
        XCTAssertTrue(boardSource.contains("SoloPMAssistantQueueBridge.consumePendingOpen()"))
        XCTAssertTrue(boardSource.contains("SoloPMAssistantQueueBridge.consumeRequest(from: notification)"))
        XCTAssertTrue(boardSource.contains("selectedDestination = .assistantQueue"))
        XCTAssertTrue(boardSource.contains("viewModel.focusAssistantQueueExecutionHandoff(id: request.itemID)"))
        XCTAssertTrue(englishStrings.contains("\"Open Assistant Queue\""))
        XCTAssertTrue(englishStrings.contains("\"Opens the Assistant Queue without running the item.\""))
        XCTAssertTrue(englishStrings.contains("\"Assistant Queue item is no longer available.\""))
        XCTAssertTrue(japaneseStrings.contains("\"Open Assistant Queue\""))
        XCTAssertTrue(japaneseStrings.contains("\"Opens the Assistant Queue without running the item.\""))
        XCTAssertTrue(japaneseStrings.contains("\"Assistant Queue item is no longer available.\""))
        XCTAssertFalse(appSource.contains("ActionReviewPanel(viewModel: AppRuntimeFactory.makeReviewSessionViewModel(plan: plan))"))
    }

    func testTodayWorkflowUsesSampleInspiredBriefingAndFlowRail() throws {
        let workflowSource = try readProjectWorkflowSources()
        let todayWorkflowStart = try XCTUnwrap(workflowSource.range(of: "struct TodayWorkflowView"))
        let todayWorkflowEnd = try XCTUnwrap(workflowSource.range(of: "struct CatchUpWorkflowView"))
        let todayWorkflowSource = String(workflowSource[todayWorkflowStart.lowerBound..<todayWorkflowEnd.lowerBound])

        XCTAssertTrue(workflowSource.contains("TodayBriefingPanel"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-briefing-panel\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-command-capture-field\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-suggestion-rail\")"))
        XCTAssertTrue(workflowSource.contains("viewModel.startFocus(taskID: chip.taskID)"))
        XCTAssertTrue(workflowSource.contains("TodayFlowStrip(plan: plan, viewModel: viewModel)"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-flow-strip\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-flow-chip-\\(block.id)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-flow-optimize\")"))
        XCTAssertTrue(workflowSource.contains("TodayAISuggestionCard(plan: plan, viewModel: viewModel)"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-ai-suggestion-card\")"))
        XCTAssertTrue(todayWorkflowSource.contains("let snapshot = viewModel.derivedReadModels.todayWorkflowSnapshot"))
        XCTAssertTrue(todayWorkflowSource.contains("mainSurface(snapshot: snapshot)"))
        XCTAssertTrue(todayWorkflowSource.contains("TodayAssistantRail(\n                    commandTitle: $commandTitle,\n                    context: snapshot.assistantContext"))
        XCTAssertFalse(todayWorkflowSource.contains("viewModel.todayPlan()"))
        XCTAssertFalse(todayWorkflowSource.contains("viewModel.todayAssistantRailContext()"))
    }

    func testTodayWorkflowProvidesCommonQuickActionChipsAndLocalRailActions() throws {
        let workflowSource = try readProjectWorkflowSources()
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")

        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-common-action-rail\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-common-chip-add-task\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-common-chip-plan-tomorrow\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-common-chip-prepare-meeting\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-common-chip-draft-reply\")"))
        XCTAssertTrue(workflowSource.contains("commandTitle = String(localized: \"New task: \")"))
        XCTAssertTrue(workflowSource.contains("commandTitle = String(localized: \"Plan tomorrow: \")"))
        XCTAssertTrue(workflowSource.contains("commandTitle = String(localized: \"Prepare meeting: \")"))
        XCTAssertTrue(workflowSource.contains("commandTitle = String(localized: \"Draft reply: \")"))
        XCTAssertTrue(workflowSource.contains("recommendationChips: snapshot.recommendationChips"))
        XCTAssertTrue(workflowSource.contains("let recommendationChips: [TodayRecommendationChip]"))
        XCTAssertTrue(workflowSource.contains("ForEach(recommendationChips) { chip in"))
        XCTAssertTrue(workflowSource.contains("TodayAssistantRail("))
        XCTAssertTrue(workflowSource.contains("commandTitle: $commandTitle"))
        XCTAssertTrue(workflowSource.contains("viewModel.prepareTodayScheduleDraft(prioritizing: task.id)"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-rail-schedule-block\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-rail-schedule-draft-status\")"))
        XCTAssertTrue(workflowSource.contains("!trimmedCommandTitle.hasSuffix(\":\")"))
        XCTAssertTrue(workflowSource.contains("onSelectTask: selectTodayTask"))
        XCTAssertTrue(workflowSource.contains("openInspector(task.id)"))
        XCTAssertTrue(workflowSource.contains("commandTitle = String(format: String(localized: \"Subtask for %@: \"), task.title)"))
        XCTAssertTrue(boardSource.contains("isInspectorPresented = false"))
        XCTAssertTrue(boardSource.contains("selectTodayTask"))
        XCTAssertTrue(boardSource.contains("openInspectorForTodayRailTask: openInspectorForTodayRailTask"))
        XCTAssertTrue(boardSource.contains("openInspectorForTodayRailTask"))
        XCTAssertTrue(boardSource.contains("isInspectorPresented = true"))
    }

    func testTodayWorkflowUsesStableLayoutsForSizeFittingSensitiveScopes() throws {
        let todaySource = try readPackageFile("Sources/SoloPMApp/Views/ProjectWorkflowTodayView.swift")
        let sharedSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectWorkflowSharedViews.swift")

        let todayWorkflowStart = try XCTUnwrap(todaySource.range(of: "struct TodayWorkflowView"))
        let todayWorkflowEnd = try XCTUnwrap(todaySource.range(of: "private struct TodayDailyPlanningReviewPanel"))
        let todayWorkflowScope = String(todaySource[todayWorkflowStart.lowerBound..<todayWorkflowEnd.lowerBound])

        let todayBriefingStart = try XCTUnwrap(todaySource.range(of: "private struct TodayBriefingPanel"))
        let todayBriefingEnd = try XCTUnwrap(todaySource.range(of: "private struct TodaySuggestionPanel"))
        let todayBriefingScope = String(todaySource[todayBriefingStart.lowerBound..<todayBriefingEnd.lowerBound])

        let commonRailStart = try XCTUnwrap(todaySource.range(of: "private var commonActionRail"))
        let commonButtonsStart = try XCTUnwrap(todaySource.range(of: "@ViewBuilder\n    private var commonActionButtons", range: commonRailStart.upperBound..<todaySource.endIndex))
        let commonRailScope = String(todaySource[commonRailStart.lowerBound..<commonButtonsStart.lowerBound])
        let suggestionRailStart = try XCTUnwrap(todaySource.range(of: "private var suggestionRail", range: commonButtonsStart.upperBound..<todaySource.endIndex))
        let commonButtonsScope = String(todaySource[commonButtonsStart.lowerBound..<suggestionRailStart.lowerBound])

        let planSummaryStart = try XCTUnwrap(todaySource.range(of: "private struct TodayPlanSummary"))
        let countBadgeStart = try XCTUnwrap(todaySource.range(of: "private struct TodayCountBadge", range: planSummaryStart.upperBound..<todaySource.endIndex))
        let planSummaryScope = String(todaySource[planSummaryStart.lowerBound..<countBadgeStart.lowerBound])

        let taskSurfaceStart = try XCTUnwrap(sharedSource.range(of: "struct WorkflowTaskSurface"))
        let taskSurfaceBodyStart = try XCTUnwrap(sharedSource.range(of: "\n    var body: some View {", range: taskSurfaceStart.upperBound..<sharedSource.endIndex))
        let taskSurfaceContentStart = try XCTUnwrap(sharedSource.range(of: "\n            if tasks.isEmpty {", range: taskSurfaceBodyStart.upperBound..<sharedSource.endIndex))
        let sharedHeaderScope = String(sharedSource[taskSurfaceBodyStart.upperBound..<taskSurfaceContentStart.lowerBound])

        XCTAssertFalse(todayWorkflowScope.contains("ViewThatFits(in:"))
        XCTAssertFalse(todayBriefingScope.contains("ViewThatFits(in:"))
        XCTAssertFalse(commonRailScope.contains("ViewThatFits(in:"))
        XCTAssertFalse(planSummaryScope.contains("ViewThatFits(in:"))
        XCTAssertFalse(sharedHeaderScope.contains("ViewThatFits(in:"))

        XCTAssertTrue(todayWorkflowScope.contains("LazyVGrid"))
        XCTAssertTrue(todayBriefingScope.contains("LazyVGrid"))
        XCTAssertTrue(commonRailScope.contains("GridItem(.adaptive"))
        XCTAssertTrue(planSummaryScope.contains("VStack(alignment: .leading"))
        XCTAssertTrue(sharedHeaderScope.contains("VStack(alignment: .leading"))

        XCTAssertLessThan(
            try XCTUnwrap(sharedHeaderScope.range(of: "WorkflowHeader(")).lowerBound,
            try XCTUnwrap(sharedHeaderScope.range(of: "headerAccessory()")).lowerBound
        )
        XCTAssertLessThan(
            try XCTUnwrap(todayBriefingScope.range(of: "WorkflowDoneToggle(viewModel: viewModel)")).lowerBound,
            try XCTUnwrap(todayBriefingScope.range(of: "suggestionRail")).lowerBound
        )
        XCTAssertLessThan(
            try XCTUnwrap(todayBriefingScope.range(of: "suggestionRail")).lowerBound,
            try XCTUnwrap(todayBriefingScope.range(of: "startFocusButton")).lowerBound
        )

        let commonActionIdentifiers = [
            "today-common-chip-add-task",
            "today-common-chip-plan-tomorrow",
            "today-common-chip-prepare-meeting",
            "today-common-chip-draft-reply"
        ]
        let commonActionOffsets = try commonActionIdentifiers.map { identifier in
            try XCTUnwrap(commonButtonsScope.range(of: identifier)?.lowerBound)
        }
        for pair in zip(commonActionOffsets, commonActionOffsets.dropFirst()) {
            XCTAssertLessThan(pair.0, pair.1)
        }
    }

    func testScheduleWorkflowIsReachableAndApprovalFirst() throws {
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let workflowSource = try readProjectWorkflowSources()
        let persistenceSource = try readPackageFile("Sources/SoloPMCore/App/ProjectBoardSelectionPersistence.swift")
        let coreSource = try readPackageFile("Sources/SoloPMCore/App/ProjectBoard.swift")
        let modelSource = try readPackageFile("Sources/SoloPMCore/WorkManagement/WorkManagementModels.swift")

        XCTAssertTrue(boardSource.contains("ProjectBoardSidebarDestinationRow(destination: .schedule"))
        XCTAssertTrue(boardSource.contains("case .schedule:"))
        XCTAssertTrue(boardSource.contains("ScheduleWorkflowView(viewModel: viewModel)"))
        XCTAssertTrue(persistenceSource.contains("case schedule"))
        XCTAssertTrue(workflowSource.contains("ScheduleWorkflowView"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-workflow\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-generate-draft\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-apply-calendar\")"))
        XCTAssertTrue(workflowSource.contains("ScheduleDraftApprovalControls("))
        XCTAssertTrue(workflowSource.contains("viewModel.enqueueScheduleDraftCalendarApply(on: workloadReferenceDate)"))
        XCTAssertTrue(workflowSource.contains("viewModel.addUnscheduledTaskToScheduleDraft("))
        XCTAssertTrue(workflowSource.contains("scheduleReadModel.unscheduledTasks"))
        XCTAssertTrue(workflowSource.contains("viewModel.enqueueScheduleReminderDraft("))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-unscheduled-add-draft-\\(task.id)\")"))
        XCTAssertTrue(workflowSource.contains("ForEach(reminderProposalTasks(for: day), id: \\.id)"))
        XCTAssertTrue(workflowSource.contains("private func reminderProposalTasks(for day: WeeklyScheduleDay) -> [ProjectBoardTask]"))
        XCTAssertFalse(workflowSource.contains("private func reminderProposalTask(for day: WeeklyScheduleDay) -> ProjectBoardTask?"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-smart-reminder-draft-\\(task.id)\")"))
        XCTAssertTrue(workflowSource.contains("Queue Reminder Draft"))
        XCTAssertTrue(workflowSource.contains("Queue reminder draft for %@"))
        XCTAssertTrue(workflowSource.contains(".accessibilityLabel(String(format: String(localized: \"Add %@ to Draft\"), task.title))"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-queue-approval-note\")"))
        let scheduleWorkflowStart = try XCTUnwrap(workflowSource.range(of: "struct ScheduleWorkflowView"))
        let scheduleWorkflowEnd = try XCTUnwrap(workflowSource.range(of: "struct DoneWorkflowView"))
        let scheduleWorkflowSource = String(workflowSource[scheduleWorkflowStart.lowerBound..<scheduleWorkflowEnd.lowerBound])
        XCTAssertTrue(scheduleWorkflowSource.contains("viewModel.prepareScheduleDraft(on: workloadReferenceDate)"))
        XCTAssertLessThan(
            try XCTUnwrap(scheduleWorkflowSource.range(of: "ScheduleDraftApprovalControls(")).lowerBound,
            try XCTUnwrap(scheduleWorkflowSource.range(of: "ScheduleMiniCalendarPanel(")).lowerBound
        )
        XCTAssertLessThan(
            try XCTUnwrap(scheduleWorkflowSource.range(of: "ScheduleDraftApprovalControls(")).lowerBound,
            try XCTUnwrap(scheduleWorkflowSource.range(of: "ScheduleDraftPanel(viewModel: viewModel)")).lowerBound
        )
        XCTAssertFalse(scheduleWorkflowSource.contains("applyScheduleDraftToCalendar"))
        XCTAssertTrue(modelSource.contains("public struct ScheduleDraft"))
        XCTAssertTrue(coreSource.contains("public func unscheduledScheduleTasks"))
        XCTAssertTrue(coreSource.contains("public func prepareScheduleDraft"))
        XCTAssertTrue(coreSource.contains("public func addUnscheduledTaskToScheduleDraft"))
        XCTAssertTrue(coreSource.contains("public func enqueueScheduleReminderDraft"))
        XCTAssertTrue(coreSource.contains("public func enqueueScheduleDraftCalendarApply"))
        XCTAssertTrue(coreSource.contains("public func applyScheduleDraftToCalendar"))
        XCTAssertFalse(workflowSource.contains("SecureField(\"Approval token\""))
        XCTAssertFalse(coreSource.contains("return .applied(eventCount: 0)"))
    }

    func testScheduleWorkflowShowsLocalDailyWorkloadDashboardWithoutCalendarWrites() throws {
        let workflowSource = try readProjectWorkflowSources()
        let coreSource = try readPackageFile("Sources/SoloPMCore/App/ProjectBoard.swift")
        let workloadSource = try readPackageFile("Sources/SoloPMCore/App/DailyWorkloadDashboard.swift")
        let weeklySource = try readPackageFile("Sources/SoloPMCore/App/WeeklyScheduleCockpit.swift")
        let captureScript = try readPackageFile("script/capture_ui_evidence.sh")
        let visualManifest = try readPackageFile("docs/quality/visual-baseline-manifest.json")

        XCTAssertTrue(workloadSource.contains("public struct DailyWorkloadOverview"))
        XCTAssertTrue(workloadSource.contains("public struct DailyWorkloadDay"))
        XCTAssertTrue(workloadSource.contains("public struct DailyWorkloadProjectContribution"))
        XCTAssertTrue(coreSource.contains("public func dailyWorkloadOverview("))
        XCTAssertTrue(weeklySource.contains("public struct WeeklyScheduleCockpit"))
        XCTAssertTrue(weeklySource.contains("public struct WeeklyScheduleBlock"))
        XCTAssertTrue(weeklySource.contains("public var startHour: Int?"))
        XCTAssertTrue(weeklySource.contains("startHour: calendar.component(.hour, from: start)"))
        XCTAssertTrue(weeklySource.contains("public struct WeeklyScheduleFocusForecast"))
        XCTAssertTrue(weeklySource.contains("completionHistoryCount"))
        XCTAssertTrue(weeklySource.contains("completedDayKeys"))
        XCTAssertTrue(coreSource.contains("public func weeklyScheduleCockpit("))
        XCTAssertTrue(workloadSource.contains("inboxUntriagedCount"))
        XCTAssertTrue(workloadSource.contains("private static func isInboxProject"))

        XCTAssertTrue(workflowSource.contains("WeeklyScheduleCockpitPanel("))
        XCTAssertTrue(workflowSource.contains("let scheduleReadModel = viewModel.derivedReadModels.schedule"))
        XCTAssertTrue(workflowSource.contains("cockpit: scheduleReadModel.weeklyCockpit"))
        XCTAssertTrue(workflowSource.contains("ScheduleMiniCalendarPanel("))
        XCTAssertTrue(workflowSource.contains("selectMiniCalendarDay"))
        XCTAssertTrue(workflowSource.contains("selectDay: selectMiniCalendarDay"))
        XCTAssertTrue(workflowSource.contains("let selectDay: (DailyWorkloadDay) -> Void"))
        XCTAssertTrue(workflowSource.contains("selectDay(day)"))
        XCTAssertTrue(workflowSource.contains("moveWorkloadToToday"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-mini-calendar\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-mini-calendar-previous-week\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-mini-calendar-next-week\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-mini-calendar-today\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-mini-calendar-day-\\(day.dateKey)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-mini-calendar-selected-day\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityAddTraits(day.dateKey == selectedDay?.dateKey ? .isSelected : [])"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-week-grid\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-week-time-axis-grid\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-week-time-axis-slot-\\(day.dateKey)-\\(hour)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-week-time-axis-all-day-slot-\\(day.dateKey)\")"))
        XCTAssertTrue(workflowSource.contains("WeeklyScheduleTimeAxisGrid(cockpit: cockpit)"))
        XCTAssertTrue(workflowSource.contains("WeeklyScheduleTimeAxisSlot("))
        XCTAssertTrue(workflowSource.contains("block.startHour"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-week-day-column-\\(day.dateKey)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-week-block-\\(block.id)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-week-completion-history-\\(day.dateKey)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-focus-forecast\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-smart-reminders\")"))
        XCTAssertTrue(workflowSource.contains("DailyWorkloadPanel("))
        XCTAssertTrue(workflowSource.contains("let workloadOverview = scheduleReadModel.workloadOverview"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-workload-dashboard\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-workload-previous-week\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-workload-next-week\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-workload-day-cell-\\(day.dateKey)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-workload-count-badge-\\(day.dateKey)-total\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-workload-count-badge-\\(day.dateKey)-in-progress\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-workload-count-badge-\\(day.dateKey)-blocked\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-workload-count-badge-\\(day.dateKey)-missed\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-workload-progress-\\(day.dateKey)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-workload-attention-banner\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-workload-day-detail\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-workload-detail-task-\\(task.id)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-workload-unscheduled-bucket\")"))
        XCTAssertTrue(workflowSource.contains("External Calendar writes require review approval."))
        XCTAssertTrue(captureScript.contains("--schedule-workload"))
        XCTAssertTrue(captureScript.contains("schedule-workload-light.png"))
        XCTAssertTrue(captureScript.contains("schedule-workload-dark.png"))
        XCTAssertTrue(captureScript.contains("schedule-workload-dashboard=>schedule-workload-dashboard"))
        XCTAssertTrue(captureScript.contains("schedule-workload-attention-banner=>schedule-workload-attention-banner"))
        XCTAssertTrue(captureScript.contains("schedule-workload-day-detail=>schedule-workload-day-detail"))
        XCTAssertTrue(captureScript.contains("docs/release/evidence/schedule-workload-screenshots.md"))
        XCTAssertTrue(visualManifest.contains(#""id": "schedule-workload""#))
        XCTAssertTrue(visualManifest.contains("schedule-workload-light.png"))
        XCTAssertTrue(visualManifest.contains("schedule-workload-dark.png"))

        let dashboardStart = try XCTUnwrap(workflowSource.range(of: "private struct DailyWorkloadPanel"))
        let dashboardSource = String(workflowSource[dashboardStart.lowerBound...])
        XCTAssertFalse(dashboardSource.contains("applyScheduleDraftToCalendar"))
        let weeklyStart = try XCTUnwrap(workflowSource.range(of: "private struct WeeklyScheduleCockpitPanel"))
        let weeklyWorkflowSource = String(workflowSource[weeklyStart.lowerBound...])
        XCTAssertFalse(weeklyWorkflowSource.contains("applyScheduleDraftToCalendar"))
    }

    func testAppAndCLIShareDefaultDatabaseLocation() throws {
        let appSource = try readAppShellSource()
        let cliSource = try readPackageFile("Sources/SoloPMCLI/SoloPMCLIEntrypoint.swift")

        XCTAssertTrue(appSource.contains("SoloPMAppDatabaseLocation.defaultDatabaseURL(createDirectory: true)"))
        XCTAssertTrue(cliSource.contains("SoloPMAppDatabaseLocation.defaultDatabaseURL(createDirectory: false)"))
        XCTAssertFalse(appSource.contains("appendingPathComponent(\"SoloPM.sqlite\")"))
    }

    func testCLIEntrypointUsesSanitizedRuntimeErrors() throws {
        let cliSource = try readPackageFile("Sources/SoloPMCLI/SoloPMCLIEntrypoint.swift")

        XCTAssertTrue(cliSource.contains("Unexpected error: SoloPM CLI failed unexpectedly."))
        XCTAssertTrue(cliSource.contains("local read failed: SoloPM local data could not be read."))
        XCTAssertTrue(cliSource.contains("plan validate failed: Action plan file could not be read or validated."))
        XCTAssertFalse(cliSource.contains("error.localizedDescription"))
    }

    func testMenuBarSummaryRefreshesFromRuntimeController() throws {
        let appSource = try readAppShellSource()

        XCTAssertTrue(appSource.contains("@StateObject private var menuBarController: MenuBarSummaryController"))
        XCTAssertTrue(appSource.contains("MenuBarPanel(controller: menuBarController, quickCaptureController: menuBarQuickCaptureController)"))
        XCTAssertTrue(appSource.contains("makeMenuBarSummaryController()"))
        XCTAssertTrue(appSource.contains("MenuBarSummaryController {"))
        XCTAssertTrue(appSource.contains(".onReceive(NotificationCenter.default.publisher(for: .soloPMProjectBoardDidChange))"))
        XCTAssertTrue(appSource.contains("controller.emptyStateLabel"))
        XCTAssertFalse(appSource.contains("private let menuBarViewModel = AppRuntimeFactory.makeMenuBarSummaryViewModel()"))
        XCTAssertFalse(appSource.contains("StaticMenuBarSummaryProvider(summary: .empty)"))
        XCTAssertFalse(appSource.contains("controller.refresh()\n            return controller"))
        XCTAssertTrue(appSource.contains("UnavailableMenuBarSummaryProvider(error: error)"))
    }

    func testMenuBarAttentionLabelRefreshesBeforePanelOpens() throws {
        let source = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
        let labelStart = try XCTUnwrap(source.range(of: "private struct MenuBarExtraLabel: View"))
        let labelEnd = try XCTUnwrap(source.range(of: "/// App-menu window commands", range: labelStart.lowerBound..<source.endIndex))
        let labelSource = String(source[labelStart.lowerBound..<labelEnd.lowerBound])

        XCTAssertTrue(labelSource.contains("@ObservedObject var controller: MenuBarSummaryController"))
        XCTAssertTrue(labelSource.contains(".task {"))
        XCTAssertTrue(labelSource.contains(".onReceive(NotificationCenter.default.publisher(for: .soloPMProjectBoardDidChange))"))
        XCTAssertEqual(labelSource.components(separatedBy: "controller.refresh()").count - 1, 2)
    }

    func testMenuBarPanelProvidesFastInboxCaptureWithLightweightController() throws {
        let appSource = try readAppShellSource()
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")
        let audit = try readPackageFile("docs/ux/click-path-audit.md")

        XCTAssertTrue(appSource.contains("@StateObject private var menuBarQuickCaptureController: MenuBarQuickCaptureController"))
        XCTAssertTrue(appSource.contains("_menuBarQuickCaptureController = StateObject(wrappedValue: AppRuntimeFactory.makeMenuBarQuickCaptureController())"))
        XCTAssertTrue(appSource.contains("MenuBarPanel(controller: menuBarController, quickCaptureController: menuBarQuickCaptureController)"))
        XCTAssertTrue(appSource.contains("@ObservedObject var quickCaptureController: MenuBarQuickCaptureController"))
        XCTAssertTrue(appSource.contains("@State private var quickCaptureTitle = \"\""))
        XCTAssertTrue(appSource.contains("TextField(\"Quick add to Inbox\", text: $quickCaptureTitle)"))
        XCTAssertTrue(appSource.contains("quickCaptureController.createInboxTask(title: title)"))
        XCTAssertTrue(appSource.contains("MenuBarQuickCaptureController(\n            storeFactory: {"))
        XCTAssertTrue(appSource.contains(".keyboardShortcut(.return, modifiers: [.command])"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"menu-bar-quick-capture-title\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"menu-bar-quick-capture-button\")"))
        XCTAssertTrue(appSource.contains("NotificationCenter.default.post(name: .soloPMProjectBoardDidChange, object: nil)"))
        XCTAssertFalse(appSource.contains("_menuBarQuickCaptureViewModel = StateObject(wrappedValue: AppRuntimeFactory.makeProjectBoardViewModel())"))
        XCTAssertFalse(appSource.contains("quickCaptureViewModel.load()"))
        XCTAssertTrue(audit.contains("menu bar Quick AddからInboxへ0画面遷移で実タスクを作れる"))
        XCTAssertTrue(phase.contains("[x] MenuBarExtraにQuick Addを追加し、Project Boardを開かずにInboxへローカルTaskを作れる。"))
    }

    func testReviewPanelUsesResponsiveLongContentGuards() throws {
        let appSource = try readAppShellSource()

        XCTAssertTrue(appSource.contains("ScrollView"))
        XCTAssertTrue(appSource.contains(".frame(minHeight: 150, idealHeight: 180, maxHeight: 180)"))
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
        let appSource = try readAppShellSource()

        XCTAssertFalse(appSource.contains("registry = ToolRegistry()"))
        XCTAssertTrue(appSource.contains("runtimeValidationMessage: runtime.reviewRuntimeValidationMessage"))
        XCTAssertTrue(appSource.contains("Review execution tools are unavailable because audit logging or local data stores could not be opened."))
    }

    func testWatcherDiagnosticsUsesRuntimeStateStoreAndNotificationPermissions() throws {
        let appSource = try readAppShellSource()

        XCTAssertTrue(appSource.contains("WatcherDiagnosticsProvider("))
        XCTAssertTrue(appSource.contains("SQLiteDailyCheckStateStore(connection: connection)"))
        XCTAssertTrue(appSource.contains("UserNotificationsPermissionSnapshotReader.snapshot()"))
        XCTAssertTrue(appSource.contains("diagnosticsSnapshot.errorMessage"))
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

    func testRuntimeMailDraftClientStoresLocalDraftsWithoutListOrSendSurface() throws {
        let appSource = try readAppShellSource()
        let clientSource = try readPackageFile("Sources/SoloPMCore/Tools/SystemToolClients.swift")

        XCTAssertFalse(appSource.contains("mailDraftClient: UnavailableMailDraftClient()"))
        XCTAssertTrue(appSource.contains("mailDraftClient: try makeMailDraftClient()"))
        XCTAssertTrue(clientSource.contains("public final class LocalFileMailDraftClient"))
        XCTAssertTrue(appSource.contains("appendingPathComponent(\"MailDrafts\", isDirectory: true)"))
        XCTAssertFalse(clientSource.contains("func listDrafts() throws -> [MailDraftRecord]"))
        XCTAssertFalse(clientSource.contains("func send"))
        XCTAssertFalse(try readPackageFile("Sources/SoloPMCore/Planning/ActionPlan.swift").contains("maildraft.send"))
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
        let appSource = try readAppShellSource()
        let mcpRegistrationSource = try readPackageFile("Sources/SoloPMCore/ExternalMCP/MCPRegistration.swift")

        XCTAssertTrue(appSource.contains("SQLiteMCPServerRegistrationStore(connection:"))
        XCTAssertFalse(appSource.contains("Picker(\"Server\""))
        XCTAssertTrue(appSource.contains("private final class LazyObservableObjectLoader<Value: ObservableObject>: ObservableObject"))
        XCTAssertTrue(appSource.contains("loadedValue.objectWillChange.sink"))
        XCTAssertTrue(appSource.contains("MCPServerSettingsRow("))
        XCTAssertTrue(appSource.contains("@StateObject private var externalMCPSettingsViewModelLoader: LazyObservableObjectLoader<ExternalMCPSettingsViewModel>"))
        XCTAssertTrue(appSource.contains("let loadedExternalMCPViewModel = externalMCPSettingsViewModelLoader.value"))
        XCTAssertTrue(appSource.contains("if let loadedExternalMCPViewModel"))
        XCTAssertTrue(appSource.contains("loadedExternalMCPViewModel.registrationRows"))
        XCTAssertTrue(appSource.contains("loadedExternalMCPViewModel.selectRegistration(id: row.id)"))
        XCTAssertTrue(appSource.contains("await loadedExternalMCPViewModel.checkConnection(id: row.id)"))
        XCTAssertTrue(appSource.contains("loadedExternalMCPViewModel.createRegistration()"))
        XCTAssertTrue(appSource.contains("Add Server"))
        XCTAssertTrue(appSource.contains("Environment References"))
        XCTAssertTrue(appSource.contains("loadedExternalMCPViewModel.environmentText"))
        XCTAssertTrue(appSource.contains("loadedExternalMCPViewModel.updateEnvironmentText($0)"))
        XCTAssertTrue(appSource.contains("Protocol Version"))
        XCTAssertTrue(appSource.contains("loadedExternalMCPViewModel.protocolVersionLabel"))
        XCTAssertTrue(appSource.contains("Check Result"))
        XCTAssertTrue(appSource.contains("loadedExternalMCPViewModel.connectionCheckResultLabel"))
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
        XCTAssertTrue(appSource.contains("externalMCPViewModel?.deleteRegistration()"))
        XCTAssertTrue(appSource.contains("externalMCPSettingsViewModelFactory: AppRuntimeFactory.makeExternalMCPSettingsViewModel"))
        XCTAssertTrue(mcpRegistrationSource.contains("MCPServerRegistrationRow"))
        XCTAssertTrue(mcpRegistrationSource.contains("selectedRegistrationID"))
        XCTAssertTrue(mcpRegistrationSource.contains("MCPEnvironmentTextCodec"))
        XCTAssertTrue(mcpRegistrationSource.contains("rawValueNotAllowed"))
        XCTAssertFalse(appSource.contains("store: UserDefaultsMCPServerRegistrationStore()"))
        XCTAssertFalse(mcpRegistrationSource.contains("UserDefaultsMCPServerRegistrationStore"))
    }

    func testRuntimeExternalMCPAuditLoadFailureIsNotRenderedAsEmptyHistory() throws {
        let appSource = try readAppShellSource()
        let mcpRegistrationSource = try readPackageFile("Sources/SoloPMCore/ExternalMCP/MCPRegistration.swift")

        XCTAssertTrue(appSource.contains("externalMCPAuditLoadResult()"))
        XCTAssertTrue(appSource.contains("auditErrorMessage: auditLoadResult.errorMessage"))
        XCTAssertTrue(appSource.contains("loadedExternalMCPViewModel.auditErrorMessage"))
        XCTAssertTrue(appSource.contains("MCP audit history is unavailable because audit logging could not be opened."))
        XCTAssertFalse(appSource.contains("private static func externalMCPAuditRows() -> [ExternalMCPAuditHistoryRow]"))
        XCTAssertTrue(mcpRegistrationSource.contains("@Published public private(set) var auditErrorMessage: String?"))
    }

    func testExternalMCPArgumentsUseQuotedRoundTripTextInsteadOfSpaceSplitDisplay() throws {
        let appSource = try readAppShellSource()
        let mcpRegistrationSource = try readPackageFile("Sources/SoloPMCore/ExternalMCP/MCPRegistration.swift")

        XCTAssertTrue(appSource.contains("loadedExternalMCPViewModel.argumentsText"))
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
        let appSource = try readAppShellSource()

        XCTAssertTrue(appSource.contains("settingsViewModel.selectableAIProviders"))
        XCTAssertTrue(appSource.contains("settingsViewModel.selectAIProviderAndSave($0)"))
        XCTAssertFalse(appSource.contains("ForEach(AIProvider.allCases"))
        XCTAssertFalse(appSource.contains("Save Provider Selection"))
    }

    func testSettingsShowsOpenAIProviderSmokeReadiness() throws {
        let appSource = try readAppShellSource()

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

    func testPublicAlphaAppLinksOnlyNarrowGoogleCalendarRuntimeTarget() throws {
        let packageSource = try readPackageFile("Package.swift")
        let appTarget = try XCTUnwrap(packageSource.range(of: ".executableTarget(\n            name: \"SoloPM\","))
        let cliTarget = try XCTUnwrap(packageSource.range(of: ".executableTarget(\n            name: \"SoloPMCLI\","))
        let testsTarget = try XCTUnwrap(packageSource.range(of: ".testTarget(\n            name: \"SoloPMCoreTests\","))
        let appTargetBlock = String(packageSource[appTarget.lowerBound..<cliTarget.lowerBound])
        let cliTargetBlock = String(packageSource[cliTarget.lowerBound..<testsTarget.lowerBound])

        XCTAssertTrue(packageSource.contains("name: \"SoloPMGoogleCalendarRuntime\""))
        XCTAssertTrue(packageSource.contains("name: \"SoloPMExternalConnectors\""))
        XCTAssertTrue(packageSource.contains("dependencies: [\"SoloPMCore\"]"))
        XCTAssertTrue(appTargetBlock.contains("SoloPMGoogleCalendarRuntime"))
        XCTAssertFalse(appTargetBlock.contains("SoloPMExternalConnectors"))
        XCTAssertFalse(cliTargetBlock.contains("SoloPMExternalConnectors"))
    }

    func testExternalConnectorPlanningDocsKeepTestDoublesOutOfProductionTarget() throws {
        let phase = try readPackageFile("tasks/Phase8-SaaSConnectors.md")
        let adr = try readPackageFile("docs/adr/0006-optional-connectors-and-knowledge-boundaries.md")

        XCTAssertTrue(phase.contains("Production connector protocols live in `Sources/SoloPMExternalConnectors/SaaSConnectors.swift`."))
        XCTAssertTrue(phase.contains("Test doubles live under `Tests/SoloPMCoreTests/SaaSConnectorTests.swift`"))
        XCTAssertTrue(phase.contains("Public alpha の `SoloPM` app / `solopm-cli` は `SoloPMExternalConnectors` に依存せず"))
        XCTAssertFalse(phase.contains("`SoloPMExternalConnectors` target の protocol + test-only fake client"))
        XCTAssertFalse(phase.contains("fake Google client"))
        XCTAssertFalse(phase.contains("connector ごとに fake client test がある"))

        XCTAssertTrue(adr.contains("production connector protocols, metadata stores, and approval gates"))
        XCTAssertTrue(adr.contains("test doubles isolated under `Tests/`"))
        XCTAssertTrue(adr.contains("`SoloPM` app and `solopm-cli` do not link the optional connector target"))
        XCTAssertFalse(adr.contains("Core protocols, fake clients, local stores"))
        XCTAssertFalse(adr.contains("as Core protocols, fake clients, local stores"))
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
        let appSource = try readAppShellSource()

        XCTAssertFalse(appSource.contains("AppPreviewFactory"))
        XCTAssertFalse(appSource.contains("DemoPlanningProvider"))
        XCTAssertFalse(appSource.contains("DemoTranscriptionUnavailableProvider"))
        XCTAssertFalse(appSource.contains("InMemoryProjectBoardStore()"))
        XCTAssertFalse(appSource.contains("ToolRegistryFactory.inMemoryPhase2MVP"))
        XCTAssertTrue(appSource.contains("AppRuntimeFactory"))
        XCTAssertTrue(appSource.contains("KeychainSecretStore"))
        XCTAssertTrue(appSource.contains("OpenAIResponsesProvider(secretStore:"))
        XCTAssertTrue(appSource.contains("ToolRegistry.phase2MVP("))
        XCTAssertTrue(appSource.contains("let artifactStore = SQLiteArtifactStore(connection: connection)"))
        XCTAssertTrue(appSource.contains("artifactStore: artifactStore"))
    }

    func testRuntimeExecutionRegistryIncludesDeveloperWorkflowToolsForAssistantQueue() throws {
        let appSource = try readAppShellSource()
        let coordinatorFactoryStart = try XCTUnwrap(appSource.range(of: "private static func makeAssistantQueueExecutionCoordinator("))
        let coordinatorFactoryEnd = try XCTUnwrap(appSource.range(of: "@MainActor\n    static func makeMenuBarSummaryController()", range: coordinatorFactoryStart.upperBound..<appSource.endIndex))
        let coordinatorFactory = String(appSource[coordinatorFactoryStart.lowerBound..<coordinatorFactoryEnd.lowerBound])
        let registryFactoryStart = try XCTUnwrap(appSource.range(of: "static func makeRuntimeToolRegistry("))
        let registryFactory = String(appSource[registryFactoryStart.lowerBound..<coordinatorFactoryEnd.lowerBound])

        XCTAssertTrue(appSource.contains("static func makeRuntimeToolRegistry("))
        XCTAssertTrue(coordinatorFactory.contains("makeRuntimeToolRegistry(connection: connection, auditLogger: auditLogger)"))
        XCTAssertTrue(registryFactory.contains("DevelopmentPullRequestCreationTool(\n                projectStore: projectStore,\n                bookmarkResolver: developmentBookmarkResolver"))
        XCTAssertTrue(registryFactory.contains("DevelopmentPullRequestReviewGateTool(\n                projectStore: projectStore,\n                bookmarkResolver: developmentBookmarkResolver"))
        XCTAssertTrue(registryFactory.contains("DevelopmentPullRequestMergeTool(\n                projectStore: projectStore,\n                bookmarkResolver: developmentBookmarkResolver"))
        XCTAssertTrue(registryFactory.contains(".developmentReviewPullRequestGate"))
        XCTAssertTrue(registryFactory.contains(".developmentMergePullRequest"))
        XCTAssertFalse(registryFactory.contains("ToolRegistryFactory.developerMode("))
        XCTAssertTrue(registryFactory.contains("let artifactStore = SQLiteArtifactStore(connection: connection)"))
        XCTAssertTrue(appSource.contains("#if DEBUG\nprivate struct RuntimeDevelopmentPRSmokeBookmarkResolver"))
        XCTAssertTrue(appSource.contains("SOLOPM_RUNTIME_DEVELOPMENT_PR_SMOKE_BOOKMARK"))
        XCTAssertFalse(appSource.contains("SOLOPM_RUNTIME_DEVELOPMENT_PR_FIXTURE_BOOKMARK"))
        XCTAssertTrue(appSource.contains("solopm-runtime-development-pr-smoke:"))
        XCTAssertTrue(appSource.contains("return try SecurityScopedProjectWorkspaceBookmarkResolver().resolve(bookmarkData: bookmarkData)"))
        XCTAssertTrue(appSource.contains("return SecurityScopedProjectWorkspaceBookmarkResolver()"))
        XCTAssertTrue(registryFactory.contains("let developmentBookmarkResolver = makeDevelopmentWorkspaceBookmarkResolver()"))
        XCTAssertTrue(registryFactory.contains("bookmarkResolver: developmentBookmarkResolver"))
        XCTAssertTrue(registryFactory.contains("DevelopmentPRWorkflowTool("))
        XCTAssertTrue(registryFactory.contains("DevelopmentCommitWorkflowTool("))
        XCTAssertTrue(registryFactory.contains("DevelopmentRepositoryFileTool("))
        XCTAssertTrue(registryFactory.contains("name: .developmentRepositoryListFiles"))
        XCTAssertTrue(registryFactory.contains("name: .developmentRepositoryReadFile"))
        XCTAssertTrue(registryFactory.contains("name: .developmentRepositoryCreateFile"))
        XCTAssertTrue(registryFactory.contains("name: .developmentRepositoryUpdateFile"))
        XCTAssertTrue(registryFactory.contains("DevelopmentVerificationCommandTool("))
        XCTAssertTrue(registryFactory.contains("DevelopmentPushWorkflowTool("))
        XCTAssertTrue(registryFactory.contains("DevelopmentPullRequestCreationTool("))
        XCTAssertTrue(registryFactory.contains("taskStore: taskStore"))
        XCTAssertTrue(registryFactory.contains("requireBookmark: true"))
        XCTAssertFalse(registryFactory.contains("for prohibitedTool in ["))
        XCTAssertTrue(registryFactory.contains(".developmentCreatePullRequest"))
        XCTAssertFalse(registryFactory.contains(".gitReadOnly"))

        func auditedRegistrationBlock(containing needle: String) throws -> String {
            let start = try XCTUnwrap(registryFactory.range(of: "try registry.register(AuditedTool(", range: registryFactory.startIndex..<registryFactory.endIndex))
            let toolStart = try XCTUnwrap(registryFactory.range(of: needle, range: start.lowerBound..<registryFactory.endIndex))
            let blockStart = try XCTUnwrap(
                registryFactory.range(
                    of: "try registry.register(AuditedTool(",
                    options: .backwards,
                    range: start.lowerBound..<toolStart.lowerBound
                )
            )
            let blockEnd = try XCTUnwrap(registryFactory.range(of: "logger: auditLogger", range: toolStart.upperBound..<registryFactory.endIndex))
            return String(registryFactory[blockStart.lowerBound..<blockEnd.upperBound])
        }

        for block in try [
            auditedRegistrationBlock(containing: "DevelopmentPRWorkflowTool("),
            auditedRegistrationBlock(containing: "name: .developmentRepositoryListFiles"),
            auditedRegistrationBlock(containing: "name: .developmentRepositoryReadFile"),
            auditedRegistrationBlock(containing: "name: .developmentRepositoryCreateFile"),
            auditedRegistrationBlock(containing: "name: .developmentRepositoryUpdateFile"),
            auditedRegistrationBlock(containing: "DevelopmentVerificationCommandTool("),
            auditedRegistrationBlock(containing: "DevelopmentCommitWorkflowTool(")
        ] {
            XCTAssertTrue(block.contains("AuditedTool("))
            XCTAssertTrue(block.contains("requireBookmark: true"))
        }
        let pushBlock = try auditedRegistrationBlock(containing: "DevelopmentPushWorkflowTool(")
        XCTAssertTrue(pushBlock.contains("AuditedTool("))
        XCTAssertTrue(pushBlock.contains("bookmarkResolver: developmentBookmarkResolver"))
        XCTAssertTrue(pushBlock.contains("logger: auditLogger"))
        let createPullRequestBlock = try auditedRegistrationBlock(containing: "DevelopmentPullRequestCreationTool(")
        XCTAssertTrue(createPullRequestBlock.contains("AuditedTool("))
        XCTAssertTrue(createPullRequestBlock.contains("logger: auditLogger"))
    }

    func testReviewRuntimeRequiresAuditLoggerBeforeWriteExecution() throws {
        let appSource = try readAppShellSource()
        let reviewFactoryStart = try XCTUnwrap(appSource.range(of: "static func makeReviewSessionViewModel(plan: ActionPlan)"))
        let nextFactoryStart = try XCTUnwrap(appSource.range(of: "static func workspaceRootURL()", range: reviewFactoryStart.upperBound..<appSource.endIndex))
        let reviewFactory = String(appSource[reviewFactoryStart.lowerBound..<nextFactoryStart.lowerBound])

        XCTAssertFalse(reviewFactory.contains("try? makeAuditLogger()"))
        XCTAssertTrue(reviewFactory.contains("let auditLogger = try makeAuditLogger()"))
        XCTAssertTrue(reviewFactory.contains("let receiptStore = try makeExecutionReceiptStore()"))
        XCTAssertTrue(reviewFactory.contains("let projectStore = SQLiteProjectStore(connection: connection)"))
        XCTAssertTrue(reviewFactory.contains("let taskStore = SQLiteTaskStore(connection: connection)"))
        XCTAssertTrue(reviewFactory.contains("let artifactStore = SQLiteArtifactStore(connection: connection)"))
        XCTAssertTrue(reviewFactory.contains("DevelopmentPRWorkflowTool("))
        XCTAssertTrue(reviewFactory.contains("DevelopmentCommitWorkflowTool("))
        XCTAssertTrue(reviewFactory.contains("DevelopmentRepositoryFileTool("))
        XCTAssertTrue(reviewFactory.contains("name: .developmentRepositoryListFiles"))
        XCTAssertTrue(reviewFactory.contains("name: .developmentRepositoryReadFile"))
        XCTAssertTrue(reviewFactory.contains("name: .developmentRepositoryCreateFile"))
        XCTAssertTrue(reviewFactory.contains("name: .developmentRepositoryUpdateFile"))
        XCTAssertTrue(reviewFactory.contains("DevelopmentVerificationCommandTool("))
        XCTAssertTrue(reviewFactory.contains("taskStore: taskStore"))
        XCTAssertTrue(reviewFactory.contains("requireBookmark: true"))
        XCTAssertTrue(reviewFactory.contains("registry.register(AuditedTool("))
        XCTAssertFalse(reviewFactory.contains("DevelopmentPushWorkflowTool("))
        XCTAssertFalse(reviewFactory.contains("DevelopmentPullRequestCreationTool("))
        XCTAssertFalse(reviewFactory.contains("ToolRegistryFactory.developerMode("))
        XCTAssertTrue(reviewFactory.contains("return (auditLogger, receiptStore, registry, nil)"))
        XCTAssertTrue(reviewFactory.contains("executionReceiptStore: runtime.receiptStore"))
        XCTAssertTrue(reviewFactory.contains("Review execution tools are unavailable because audit logging or local data stores could not be opened."))
    }

    func testReviewRuntimePersistsExecutionReceiptsUnderApplicationSupport() throws {
        let appSource = try readAppShellSource()

        XCTAssertTrue(appSource.contains("static func makeExecutionReceiptStore() throws -> any ExecutionReceiptStore"))
        XCTAssertTrue(appSource.contains("FileExecutionReceiptStore("))
        XCTAssertTrue(appSource.contains("appendingPathComponent(\"ExecutionReceipts\", isDirectory: true)"))
    }

    func testUnavailableReviewRegistryDoesNotSilentlyDropRegistrationFailures() throws {
        let appSource = try readAppShellSource()

        XCTAssertFalse(appSource.contains("try? target.register(UnavailableReviewTool"))
        XCTAssertFalse(appSource.contains("try! target.register(UnavailableReviewTool"))
        XCTAssertTrue(appSource.contains("registrationFailures.append(action.tool.rawValue)"))
        XCTAssertTrue(appSource.contains("Fallback unavailable tools could not be registered"))
        XCTAssertTrue(appSource.contains("UnavailableReviewRegistryResult"))
    }

    func testVoicePlanningRequiresAuditLoggerBeforeGeneration() throws {
        let appSource = try readAppShellSource()
        let voiceFactoryStart = try XCTUnwrap(appSource.range(of: "static func makeVoiceCaptureViewModel()"))
        let nextFactoryStart = try XCTUnwrap(appSource.range(of: "static func loadRuntimeSettings()", range: voiceFactoryStart.upperBound..<appSource.endIndex))
        let voiceFactory = String(appSource[voiceFactoryStart.lowerBound..<nextFactoryStart.lowerBound])

        XCTAssertFalse(voiceFactory.contains("try? makeAuditLogger()"))
        XCTAssertTrue(voiceFactory.contains("auditLogger = try makeAuditLogger()"))
        XCTAssertTrue(voiceFactory.contains("runtimeValidationMessage: runtimeValidationMessage"))
        XCTAssertTrue(voiceFactory.contains("Voice planning is unavailable because audit logging or local data stores could not be opened."))
    }

    func testVoiceRuntimePersistsAssistantQueueToSQLite() throws {
        let appSource = try readAppShellSource()
        let voiceFactoryStart = try XCTUnwrap(appSource.range(of: "static func makeVoiceCaptureViewModel()"))
        let nextFactoryStart = try XCTUnwrap(appSource.range(of: "static func loadRuntimeSettings()", range: voiceFactoryStart.upperBound..<appSource.endIndex))
        let voiceFactory = String(appSource[voiceFactoryStart.lowerBound..<nextFactoryStart.lowerBound])

        XCTAssertTrue(voiceFactory.contains("let connection = try migratedConnection()"))
        XCTAssertTrue(voiceFactory.contains("assistantQueueStore = SQLiteAssistantQueueStore(connection: connection)"))
        XCTAssertTrue(voiceFactory.contains("assistantQueueStore: assistantQueueStore"))
        XCTAssertTrue(voiceFactory.contains("let managedCostRateCardResolver = ManagedAICostRateCardResolver()"))
        XCTAssertTrue(voiceFactory.contains("managedCostRateCardProvider: { managedCostRateCardResolver.rateCard(for: $0) }"))
        XCTAssertFalse(voiceFactory.contains("assistantQueueStore: nil"))
    }

    func testVoiceRuntimeInjectsFailClosedDevelopmentProjectProvider() throws {
        let appSource = try readAppShellSource()
        let voiceFactoryStart = try XCTUnwrap(appSource.range(of: "static func makeVoiceCaptureViewModel()"))
        let nextFactoryStart = try XCTUnwrap(appSource.range(of: "static func loadRuntimeSettings()", range: voiceFactoryStart.upperBound..<appSource.endIndex))
        let voiceFactory = String(appSource[voiceFactoryStart.lowerBound..<nextFactoryStart.lowerBound])

        XCTAssertTrue(voiceFactory.contains("let projectStore = SQLiteProjectStore(connection: connection)"))
        XCTAssertTrue(voiceFactory.contains("developmentProjectProvider = {"))
        XCTAssertTrue(voiceFactory.contains("approvedDevelopmentProject(from: projectStore)"))
        XCTAssertTrue(voiceFactory.contains("developmentProjectProvider: developmentProjectProvider"))
        XCTAssertTrue(appSource.contains("VoiceDevelopmentProjectSelection.uniqueApprovedActiveProject(from: projects)"))
    }

    func testVoiceCommandCanPersistRecordedTranscriptToInboxRuntimeStores() throws {
        let appSource = try readAppShellSource()
        let voiceFactoryStart = try XCTUnwrap(appSource.range(of: "static func makeVoiceCaptureViewModel()"))
        let nextFactoryStart = try XCTUnwrap(appSource.range(of: "static func loadRuntimeSettings()", range: voiceFactoryStart.upperBound..<appSource.endIndex))
        let voiceFactory = String(appSource[voiceFactoryStart.lowerBound..<nextFactoryStart.lowerBound])

        XCTAssertTrue(appSource.contains("viewModel.saveDraftToInbox()"))
        XCTAssertTrue(appSource.contains("Save to Inbox"))
        XCTAssertTrue(appSource.contains(".disabled(!viewModel.canSaveDraftToInbox || viewModel.isLowLatencyVoiceAgentListening)"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"voice-command-save-to-inbox\")"))
        XCTAssertTrue(appSource.contains("VoiceInboxCaptureSavedPanel("))
        XCTAssertTrue(voiceFactory.contains("let projectBoardStore = SQLiteProjectBoardStore(connection: connection)"))
        XCTAssertTrue(voiceFactory.contains("let inboxCaptureStore = SQLiteInboxCaptureStore(connection: connection)"))
        XCTAssertTrue(voiceFactory.contains("inboxCaptureService = InboxVoiceCaptureService("))
        XCTAssertTrue(voiceFactory.contains("inboxCaptureSaver: inboxCaptureService"))
    }

    func testVoiceAssistantQueuePanelRendersWithoutPlanningResponse() throws {
        let appSource = try readAppShellSource()
        let queuePanelStart = try XCTUnwrap(appSource.range(of: "if let item = viewModel.assistantQueueItem"))
        let responsePanelStart = try XCTUnwrap(appSource.range(of: "if let response = viewModel.planningResponse", range: queuePanelStart.upperBound..<appSource.endIndex))
        let queuePanelSource = String(appSource[queuePanelStart.lowerBound..<responsePanelStart.lowerBound])
        let responsePanelEnd = appSource.index(
            responsePanelStart.lowerBound,
            offsetBy: 160,
            limitedBy: appSource.endIndex
        ) ?? appSource.endIndex
        let responsePanelSource = String(appSource[responsePanelStart.lowerBound..<responsePanelEnd])

        XCTAssertTrue(queuePanelSource.contains("AssistantQueuePanel("))
        XCTAssertFalse(responsePanelSource.contains("AssistantQueuePanel("))
        XCTAssertTrue(responsePanelSource.contains("ActionPlanPreview(response: response)"))
    }

    func testReviewActionButtonsDoNotDropViewModelErrors() throws {
        let appSource = try readAppShellSource()

        XCTAssertFalse(appSource.contains("try? viewModel.approve()"))
        XCTAssertFalse(appSource.contains("try? viewModel.execute()"))
        XCTAssertTrue(appSource.contains("viewModel.approveOrReportError()"))
        XCTAssertTrue(appSource.contains("viewModel.executeOrReportError()"))
    }

    func testRuntimeSettingsLoadDoesNotSilentlyDefaultOnDecodeFailure() throws {
        let appSource = try readAppShellSource()
        let runtimeFactoryStart = try XCTUnwrap(appSource.range(of: "enum AppRuntimeFactory"))
        let runtimeFactory = String(appSource[runtimeFactoryStart.lowerBound..<appSource.endIndex])

        XCTAssertFalse(runtimeFactory.contains("(try? UserDefaultsAppSettingsStore().load()) ?? .default"))
        XCTAssertFalse(runtimeFactory.contains("((try? UserDefaultsAppSettingsStore().load()) ?? .default).normalizedForRuntime"))
        XCTAssertTrue(runtimeFactory.contains("loadRuntimeSettings()"))
        XCTAssertTrue(runtimeFactory.contains("Runtime app settings could not be loaded. Defaults are shown until settings are saved again."))
    }

    func testSettingsSurfaceCanPersistProviderKeysThroughViewModel() throws {
        let appSource = try readAppShellSource()

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

    func testSettingsSurfaceExposesTaskAutomationSaveAnchors() throws {
        let appSource = try readAppShellSource()

        XCTAssertTrue(appSource.contains("Section(\"Task Automation\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"settings-task-auto-execution-toggle\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"settings-task-auto-execution-frequency\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"settings-task-auto-execution-max-tasks\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"settings-task-auto-execution-daily-limit\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"settings-task-auto-execution-lookahead\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"settings-task-auto-execution-urgent-cooldown\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"settings-task-auto-execution-boundary\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"settings-task-auto-execution-save\")"))
        XCTAssertTrue(appSource.contains("Section(\"Billing\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"settings-managed-ai-billing-toggle\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"settings-managed-ai-per-run-cap\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"settings-managed-ai-daily-cap\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"settings-managed-ai-monthly-cap\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"settings-managed-ai-workspace-cap\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"settings-save-button\")"))
        XCTAssertTrue(appSource.contains(".accessibilityHint(\"Persists non-secret settings to local UserDefaults.\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"settings-low-latency-voice-agent-toggle\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"settings-low-latency-voice-agent-cost-visible\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"settings-low-latency-voice-agent-cloud-fallback\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"settings-low-latency-voice-agent-boundary\")"))

        let taskAutomationStart = try XCTUnwrap(appSource.range(of: "Section(\"Task Automation\")"))
        let billingStart = try XCTUnwrap(appSource.range(of: "Section(\"Billing\")"))
        let taskAutomationSource = String(appSource[taskAutomationStart.lowerBound..<billingStart.lowerBound])
        XCTAssertLessThan(
            try XCTUnwrap(taskAutomationSource.range(of: "taskAutomationSaveButton")).lowerBound,
            try XCTUnwrap(taskAutomationSource.range(of: "settings-task-auto-execution-frequency")).lowerBound
        )
    }

    func testVoiceCommandRuntimeEvidenceLaunchAndReviewAnchors() throws {
        let appSource = try readAppShellSource()

        XCTAssertTrue(appSource.contains("SOLOPM_OPEN_VOICE_COMMAND_ON_LAUNCH"))
        XCTAssertTrue(appSource.contains("openVoiceCommandWindowForEvidenceIfRequested()"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"voice-command-root\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"voice-command-input\")"))
        XCTAssertTrue(appSource.contains("VoiceCommandInputPrompt()"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"voice-command-input-prompt\")"))
        XCTAssertTrue(appSource.contains("VoiceCommandActionReadinessRow("))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"voice-command-action-readiness\")"))
        XCTAssertTrue(appSource.contains("LowLatencyVoiceAgentPanel(viewModel: viewModel)"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"voice-agent-panel\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"voice-agent-start\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"voice-agent-stop\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"voice-agent-live-transcript\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"voice-agent-live-intent\")"))
        XCTAssertTrue(appSource.contains("viewModel.phase == .generatingPlan || viewModel.phase == .transcribing || viewModel.isLowLatencyVoiceAgentListening"))
        XCTAssertTrue(appSource.contains("!viewModel.canSaveDraftToInbox || viewModel.isLowLatencyVoiceAgentListening"))
        XCTAssertTrue(appSource.contains("viewModel.phase == .generatingPlan || viewModel.phase == .recording || viewModel.phase == .transcribing || viewModel.isLowLatencyVoiceAgentListening"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"voice-command-intent-preview\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"voice-command-clarification-panel\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"voice-command-clarification-answer\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"voice-command-clarification-submit\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"voice-command-clarification-cancel\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"voice-assistant-queue-panel\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"voice-assistant-queue-state\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"voice-assistant-queue-risk\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"voice-assistant-queue-capabilities\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"voice-assistant-queue-approve\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"voice-assistant-queue-defer\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"voice-assistant-queue-reject\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"voice-command-generate-plan\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"voice-command-status\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"voice-action-review-panel\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"voice-action-review-approve\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"voice-action-review-execute\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"voice-action-review-cancel\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"voice-execution-receipt\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"voice-execution-receipt-status\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"voice-execution-receipt-output\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"voice-execution-receipt-cost\")"))
    }

    func testSettingsSurfaceStartsWithStatusOverviewForCoreOperationalAreas() throws {
        let appSource = try readAppShellSource()

        let overviewRange = try XCTUnwrap(appSource.range(of: "SettingsStatusOverview("))
        let overviewTabRange = try XCTUnwrap(appSource.range(of: "private var overviewSettingsTab: some View"))
        let appearanceTabRange = try XCTUnwrap(appSource.range(of: "private var appearanceSettingsTab: some View"))

        XCTAssertLessThan(overviewTabRange.lowerBound, overviewRange.lowerBound)
        XCTAssertLessThan(overviewRange.lowerBound, appearanceTabRange.lowerBound)
        XCTAssertTrue(appSource.contains("Section(\"Status Overview\")"))
        XCTAssertTrue(appSource.contains("title: \"AI Provider\""))
        XCTAssertTrue(appSource.contains("title: \"MCP\""))
        XCTAssertTrue(appSource.contains("title: \"Sync\""))
        XCTAssertTrue(appSource.contains("title: \"Privacy\""))
        XCTAssertTrue(appSource.contains("settingsViewModel.settings.aiProvider.displayName"))
        XCTAssertTrue(appSource.contains("let currentSyncStatusLabel = syncViewModel?.statusLabel ?? \"Unavailable\""))
        XCTAssertTrue(appSource.contains("let currentMcpStatusLabel = externalMCPViewModel?.connectionCheckResultLabel ?? \"Unavailable\""))
        XCTAssertTrue(appSource.contains("mcpStatusLabel: currentMcpStatusLabel"))
        XCTAssertTrue(appSource.contains("syncStatusLabel: currentSyncStatusLabel"))
        XCTAssertTrue(appSource.contains("settingsViewModel.settings.notificationsEnabled"))
    }

    func testSettingsOverviewSurfacesIntegrationStatusTilesForPhase12() throws {
        let appSource = try readAppShellSource()

        XCTAssertTrue(appSource.contains("integrationPermissionSnapshot: AppRuntimeFactory.makeIntegrationPermissionSnapshot()"))
        XCTAssertTrue(appSource.contains("title: \"STT\""))
        XCTAssertTrue(appSource.contains("title: \"TTS\""))
        XCTAssertTrue(appSource.contains("title: \"Calendar\""))
        XCTAssertTrue(appSource.contains("title: \"Reminder\""))
        XCTAssertTrue(appSource.contains("title: \"Data Location\""))
        XCTAssertTrue(appSource.contains("settingsViewModel.settings.sttProvider.displayName"))
        XCTAssertTrue(appSource.contains("Local whisper.cpp: %@"))
        XCTAssertTrue(appSource.contains("settingsViewModel.localSTTProviderReadinessRow.statusLabel"))
        XCTAssertTrue(appSource.contains("settingsViewModel.settings.ttsProvider.displayName"))
        XCTAssertTrue(appSource.contains("settingsViewModel.ttsProviderReadinessRow.statusLabel"))
        XCTAssertTrue(appSource.contains("integrationPermissionSnapshot.status(for: .calendar)"))
        XCTAssertTrue(appSource.contains("integrationPermissionSnapshot.status(for: .reminders)"))
        XCTAssertTrue(appSource.contains("dataLocationOverviewStatusLabel"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"settings-status-overview\")"))
    }

    func testSettingsExposesReadyGatedKokoroTTSProviderControls() throws {
        let appSource = try readAppShellSource()
        let aiTabStart = try XCTUnwrap(appSource.range(of: "private var aiSettingsTab: some View"))
        let syncTabStart = try XCTUnwrap(appSource.range(of: "private var syncSettingsTab: some View"))
        let aiTabSource = String(appSource[aiTabStart.lowerBound..<syncTabStart.lowerBound])

        XCTAssertTrue(aiTabSource.contains("Picker(\n                    \"Text to Speech\""))
        XCTAssertTrue(aiTabSource.contains("settingsViewModel.selectableTTSProviders"))
        XCTAssertTrue(aiTabSource.contains("SelectedTTSProviderStatusRow(row: settingsViewModel.ttsProviderReadinessRow)"))
        XCTAssertTrue(aiTabSource.contains(".accessibilityIdentifier(\"settings-tts-provider-picker\")"))
        XCTAssertTrue(aiTabSource.contains(".accessibilityIdentifier(\"settings-kokoro-executable-path\")"))
        XCTAssertTrue(aiTabSource.contains(".accessibilityIdentifier(\"settings-tts-language-picker\")"))
        XCTAssertTrue(aiTabSource.contains(".accessibilityIdentifier(\"settings-tts-voice-id\")"))
        XCTAssertTrue(aiTabSource.contains(".accessibilityIdentifier(\"settings-tts-test-play\")"))
        XCTAssertTrue(aiTabSource.contains("Task {\n                        await settingsViewModel.testTTSPlayback("))
        XCTAssertTrue(aiTabSource.contains("textToSpeechPreviewerFactory(settingsViewModel.settings)"))
        XCTAssertTrue(appSource.contains("textToSpeechPreviewerFactory: AppRuntimeFactory.makeTextToSpeechPreviewer"))
        XCTAssertFalse(aiTabSource.contains("TTS playback adapter is not connected in this slice."))
        XCTAssertFalse(aiTabSource.contains("TTSProvider.systemSpeech.unavailableReason"))
        XCTAssertFalse(aiTabSource.contains(".accessibilityIdentifier(\"settings-tts-unavailable\")"))
    }

    func testSettingsExposesLocalSTTReadinessBeforeRuntimeSelection() throws {
        let appSource = try readAppShellSource()
        let coreSource = try readPackageFile("Sources/SoloPMCore/App/AppSettings.swift")
        let aiTabStart = try XCTUnwrap(appSource.range(of: "private var aiSettingsTab: some View"))
        let syncTabStart = try XCTUnwrap(appSource.range(of: "private var syncSettingsTab: some View"))
        let aiTabSource = String(appSource[aiTabStart.lowerBound..<syncTabStart.lowerBound])

        XCTAssertTrue(aiTabSource.contains("LocalSTTProviderStatusRow(row: settingsViewModel.localSTTProviderReadinessRow)"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"settings-local-stt-readiness-row\")"))
        XCTAssertTrue(appSource.contains("Text(localizedSettingsDisplay(row.statusLabel))"))
        XCTAssertTrue(appSource.contains("private struct LocalSTTProviderStatusRow"))
        XCTAssertTrue(appSource.contains("STT provider readiness"))
        XCTAssertTrue(coreSource.contains("run the local voice runtime smoke"))
    }

    func testSettingsOverviewSurfacesProValueWithoutOpeningSyncOrMCPTabs() throws {
        let appSource = try readAppShellSource()
        let audit = try readPackageFile("docs/ux/click-path-audit.md")
        let investorReview = try readPackageFile("docs/product/investor-review.md")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")
        let overviewStart = try XCTUnwrap(appSource.range(of: "private var overviewSettingsTab: some View"))
        let appearanceStart = try XCTUnwrap(appSource.range(of: "private var appearanceSettingsTab: some View"))
        let overviewSource = String(appSource[overviewStart.lowerBound..<appearanceStart.lowerBound])

        XCTAssertTrue(overviewSource.contains("Section(\"Pro Value\")"))
        XCTAssertTrue(overviewSource.contains("ProValueOverviewRow("))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"settings-pro-value-overview-row\")"))
        XCTAssertTrue(overviewSource.contains("syncValueLabel: syncPaidValueLabel"))
        XCTAssertTrue(overviewSource.contains("syncBoundaryLabel: syncSafetyBoundaryLabel"))
        XCTAssertTrue(overviewSource.contains("mcpValueLabel: mcpExecutionValueLabel"))
        XCTAssertTrue(overviewSource.contains("mcpBoundaryLabel: mcpExecutionSafetyBoundaryLabel"))
        XCTAssertLessThan(
            try XCTUnwrap(overviewSource.range(of: "SettingsStatusOverview(")).lowerBound,
            try XCTUnwrap(overviewSource.range(of: "ProValueOverviewRow(")).lowerBound
        )
        XCTAssertTrue(audit.contains("Settings Overview Pro Value row"))
        XCTAssertTrue(investorReview.contains("Settings Overview now surfaces Pro value and fail-closed boundaries before opening Sync or MCP tabs"))
        XCTAssertTrue(phase.contains("[x] Overview tabにPro Value rowを追加し、Sync/MCPタブを開く前に有料価値とFree/local-only/fail-closed境界が分かる。"))
    }

    func testSettingsSurfaceUsesTabbedCategoriesInsteadOfOneLongForm() throws {
        let appSource = try readAppShellSource()
        let appearanceSectionSource = try readPackageFile("Sources/SoloPMApp/Views/SettingsAppearanceSection.swift")
        let audit = try readPackageFile("docs/ux/click-path-audit.md")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")

        XCTAssertTrue(appSource.contains("TabView(selection: $selectedTab) {"))
        XCTAssertTrue(appSource.contains("enum SettingsTab: String"))
        XCTAssertTrue(appSource.contains("@State private var selectedTab: SettingsTab"))
        XCTAssertTrue(appSource.contains("private var overviewSettingsTab: some View"))
        XCTAssertTrue(appSource.contains("private var appearanceSettingsTab: some View"))
        XCTAssertTrue(appSource.contains("private var aiSettingsTab: some View"))
        XCTAssertTrue(appSource.contains("private var mcpSettingsTab: some View"))
        XCTAssertTrue(appSource.contains("private var syncSettingsTab: some View"))
        XCTAssertTrue(appSource.contains("private var privacySettingsTab: some View"))
        XCTAssertTrue(appSource.contains("Label(\"Overview\", systemImage: \"gauge.with.dots.needle.bottom.50percent\")"))
        XCTAssertTrue(appSource.contains("Label(\"Appearance\", systemImage: \"circle.lefthalf.filled\")"))
        XCTAssertTrue(appSource.contains("Label(\"AI\", systemImage: \"brain.head.profile\")"))
        XCTAssertTrue(appSource.contains("Label(\"MCP\", systemImage: \"externaldrive.connected.to.line.below\")"))
        XCTAssertTrue(appSource.contains("Label(\"Sync\", systemImage: \"arrow.triangle.2.circlepath\")"))
        XCTAssertTrue(appSource.contains("Label(\"Privacy\", systemImage: \"lock.shield\")"))

        let overviewStart = try XCTUnwrap(appSource.range(of: "private var overviewSettingsTab"))
        let appearanceStart = try XCTUnwrap(appSource.range(of: "private var appearanceSettingsTab"))
        let aiStart = try XCTUnwrap(appSource.range(of: "private var aiSettingsTab"))
        let syncStart = try XCTUnwrap(appSource.range(of: "private var syncSettingsTab"))
        let privacyStart = try XCTUnwrap(appSource.range(of: "private var privacySettingsTab"))
        let mcpStart = try XCTUnwrap(appSource.range(of: "private var mcpSettingsTab"))

        let overviewSource = String(appSource[overviewStart.lowerBound..<appearanceStart.lowerBound])
        let appearanceSource = String(appSource[appearanceStart.lowerBound..<aiStart.lowerBound])
        let aiSource = String(appSource[aiStart.lowerBound..<syncStart.lowerBound])
        let syncSource = String(appSource[syncStart.lowerBound..<privacyStart.lowerBound])
        let privacySource = String(appSource[privacyStart.lowerBound..<mcpStart.lowerBound])
        let mcpSource = String(appSource[mcpStart.lowerBound..<appSource.endIndex])

        XCTAssertTrue(overviewSource.contains("Section(\"Status Overview\")"))
        XCTAssertFalse(overviewSource.contains("SettingsAppearanceSection(appearancePreference: $appearancePreference, languagePreference: $languagePreference)"))
        XCTAssertTrue(appearanceSource.contains("SettingsAppearanceSection(appearancePreference: $appearancePreference, languagePreference: $languagePreference)"))
        XCTAssertTrue(appearanceSectionSource.contains("Section(\"Appearance\")"))
        XCTAssertTrue(appearanceSectionSource.contains("Section(\"Language\")"))
        XCTAssertTrue(aiSource.contains("Section(\"AI\")"))
        XCTAssertTrue(aiSource.contains("Section(\"Voice\")"))
        XCTAssertTrue(mcpSource.contains("Section(\"External MCP\")"))
        XCTAssertTrue(mcpSource.contains("Section(\"MCP Tool Permissions\")"))
        XCTAssertTrue(mcpSource.contains("Section(\"MCP Audit\")"))
        XCTAssertTrue(syncSource.contains("Section(\"Sync\")"))
        XCTAssertTrue(privacySource.contains("Section(\"Privacy\")"))
        XCTAssertTrue(privacySource.contains("settingsViewModel.settings.isDeveloperModeEnabled"))
        XCTAssertTrue(privacySource.contains("settingsViewModel.setDeveloperModeEnabled($0)"))
        XCTAssertTrue(privacySource.contains("Label(\"Developer Mode\", systemImage: \"hammer\")"))
        XCTAssertTrue(privacySource.contains(".accessibilityIdentifier(\"settings-developer-mode-toggle\")"))
        XCTAssertTrue(privacySource.contains(".accessibilityIdentifier(\"settings-developer-mode-boundary\")"))
        XCTAssertTrue(privacySource.contains("Section(\"Watcher\")"))
        XCTAssertTrue(audit.contains("Settings詳細FormはOverview / Appearance / AI / MCP / Sync / Privacyのtabへ分割済み"))
        XCTAssertTrue(phase.contains("[x] Settings詳細FormをOverview / Appearance / AI / MCP / Sync / Privacyのtabへ分割し"))
    }

    func testAISettingsTabShowsOnlySelectedProviderFields() throws {
        let appSource = try readAppShellSource()
        let audit = try readPackageFile("docs/ux/click-path-audit.md")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")
        let selectedFieldsStart = try XCTUnwrap(appSource.range(of: "private var selectedProviderConfigurationFields: some View"))
        let nextFieldStart = try XCTUnwrap(appSource.range(of: "private var openAIProviderSettingsFields: some View"))
        let selectedFieldsSource = String(appSource[selectedFieldsStart.lowerBound..<nextFieldStart.lowerBound])

        XCTAssertTrue(appSource.contains("selectedProviderConfigurationFields"))
        XCTAssertTrue(selectedFieldsSource.contains("switch settingsViewModel.settings.aiProvider"))
        XCTAssertTrue(selectedFieldsSource.contains("case .openaiResponses:"))
        XCTAssertTrue(selectedFieldsSource.contains("case .geminiOpenAICompatible:"))
        XCTAssertTrue(selectedFieldsSource.contains("unavailableProviderSettingsFields"))
        XCTAssertFalse(selectedFieldsSource.contains("case .openaiResponses, .geminiOpenAICompatible:"))
        XCTAssertFalse(selectedFieldsSource.contains("case .openaiResponses,\n             .geminiOpenAICompatible:"))
        XCTAssertTrue(selectedFieldsSource.contains("case .claudeMessages:"))
        XCTAssertTrue(selectedFieldsSource.contains("case .geminiDirect:"))
        XCTAssertTrue(selectedFieldsSource.contains("case .groqOpenAICompatible:"))
        XCTAssertTrue(selectedFieldsSource.contains("case .opencodeLocal:"))
        XCTAssertTrue(selectedFieldsSource.contains("case .openRouterCompatible:"))
        XCTAssertTrue(selectedFieldsSource.contains("case .ollamaCompatible:"))
        XCTAssertTrue(appSource.contains("private var openAIProviderSettingsFields: some View"))
        XCTAssertTrue(appSource.contains("private var claudeProviderSettingsFields: some View"))
        XCTAssertTrue(appSource.contains("private var geminiProviderSettingsFields: some View"))
        XCTAssertTrue(appSource.contains("private var groqProviderSettingsFields: some View"))
        XCTAssertTrue(appSource.contains("private var openCodeProviderSettingsFields: some View"))
        XCTAssertTrue(appSource.contains("private var openRouterProviderSettingsFields: some View"))
        XCTAssertTrue(appSource.contains("private var ollamaProviderSettingsFields: some View"))

        let aiStart = try XCTUnwrap(appSource.range(of: "private var aiSettingsTab"))
        let syncStart = try XCTUnwrap(appSource.range(of: "private var syncSettingsTab"))
        let aiSource = String(appSource[aiStart.lowerBound..<syncStart.lowerBound])

        XCTAssertTrue(aiSource.contains("selectedProviderConfigurationFields"))
        XCTAssertFalse(aiSource.contains("LabeledContent(\"Anthropic API Key\""))
        XCTAssertFalse(aiSource.contains("TextField(\n                    \"OpenCode Executable\""))
        XCTAssertTrue(audit.contains("Provider詳細設定は選択中providerだけを表示するcompact panelへ分離済み"))
        XCTAssertTrue(phase.contains("[x] AI tabのprovider詳細fieldは選択中providerだけを表示し"))
    }

    func testAISettingsTabShowsSelectedProviderReadinessBeforeProviderFields() throws {
        let appSource = try readAppShellSource()
        let audit = try readPackageFile("docs/ux/click-path-audit.md")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")
        let aiStart = try XCTUnwrap(appSource.range(of: "private var aiSettingsTab: some View"))
        let syncStart = try XCTUnwrap(appSource.range(of: "private var syncSettingsTab: some View"))
        let aiSource = String(appSource[aiStart.lowerBound..<syncStart.lowerBound])

        XCTAssertTrue(appSource.contains("SelectedAIProviderStatusRow("))
        XCTAssertTrue(appSource.contains("AIProviderReadinessSummaryRow("))
        XCTAssertTrue(appSource.contains("settingsViewModel.providerReadinessRows"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"ai-provider-readiness-row\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"ai-provider-readiness-summary\")"))
        XCTAssertTrue(appSource.contains("private var providerReadinessDetailLabel: String"))
        XCTAssertTrue(appSource.contains("private var activeAIProviderNextActionLabel: String"))
        XCTAssertLessThan(
            try XCTUnwrap(aiSource.range(of: "Picker(")).lowerBound,
            try XCTUnwrap(aiSource.range(of: "SelectedAIProviderStatusRow(")).lowerBound
        )
        XCTAssertLessThan(
            try XCTUnwrap(aiSource.range(of: "SelectedAIProviderStatusRow(")).lowerBound,
            try XCTUnwrap(aiSource.range(of: "AIProviderReadinessSummaryRow(")).lowerBound
        )
        XCTAssertLessThan(
            try XCTUnwrap(aiSource.range(of: "AIProviderReadinessSummaryRow(")).lowerBound,
            try XCTUnwrap(aiSource.range(of: "selectedProviderConfigurationFields")).lowerBound
        )
        XCTAssertLessThan(
            try XCTUnwrap(aiSource.range(of: "SelectedAIProviderStatusRow(")).lowerBound,
            try XCTUnwrap(aiSource.range(of: "selectedProviderConfigurationFields")).lowerBound
        )
        XCTAssertTrue(audit.contains("AI Provider readiness row"))
        XCTAssertTrue(audit.contains("AI Provider readiness summary"))
        XCTAssertTrue(phase.contains("[x] AI tabはprovider picker直下に選択中providerの状態、smoke readiness、次の操作を表示し、詳細fieldを読む前に未設定理由が分かる。"))
        XCTAssertTrue(phase.contains("[x] AI tabはProvider Readiness summaryで全providerの設定状態をprovider切替なしに確認できる。"))
    }

    func testRuntimeLLMFactoryUsesClaudeMessagesProviderWithoutOpenAIFallback() throws {
        let appSource = try readAppShellSource()
        let factoryStart = try XCTUnwrap(appSource.range(of: "private static func makeLLMProvider"))
        let factorySource = String(appSource[factoryStart.lowerBound..<appSource.endIndex])

        XCTAssertTrue(factorySource.contains("case .claudeMessages:"))
        XCTAssertTrue(factorySource.contains("ClaudeMessagesConfiguration(model: entry.defaultModelID)"))
        XCTAssertTrue(factorySource.contains("ClaudeMessagesProvider(secretStore: secretStore, configuration: configuration)"))
        XCTAssertFalse(factorySource.contains(".openaiResponses,\n             .claudeMessages"))
    }

    func testRuntimeLLMFactoryUsesGeminiDirectProviderWithoutOpenAICompatibleFallback() throws {
        let appSource = try readAppShellSource()
        let factoryStart = try XCTUnwrap(appSource.range(of: "private static func makeLLMProvider"))
        let factorySource = String(appSource[factoryStart.lowerBound..<appSource.endIndex])

        XCTAssertTrue(factorySource.contains("case .geminiDirect:"))
        XCTAssertTrue(factorySource.contains("GeminiDirectConfiguration(model: settings.normalizedForRuntime.geminiModelID ?? entry.defaultModelID)"))
        XCTAssertTrue(factorySource.contains("GeminiDirectProvider(secretStore: secretStore, configuration: configuration)"))
        XCTAssertTrue(factorySource.contains("case .geminiOpenAICompatible:"))
        XCTAssertTrue(factorySource.contains("UnavailableLLMProvider("))
        XCTAssertFalse(factorySource.contains(".openaiResponses,\n             .geminiOpenAICompatible:"))
        XCTAssertFalse(factorySource.contains(".claudeMessages,\n             .geminiDirect"))
        XCTAssertFalse(factorySource.contains(".geminiDirect,\n             .geminiOpenAICompatible"))
    }

    func testRuntimeLLMFactoryUsesOpenCodeLocalProviderWithoutOpenAIFallbackOrAuthFileRead() throws {
        let appSource = try readAppShellSource()
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

    func testRuntimeSTTFactoryUsesWhisperCppProviderWithoutOpenAIFallback() throws {
        let appSource = try readAppShellSource()
        let factoryStart = try XCTUnwrap(appSource.range(of: "private static func makeSpeechToTextProvider"))
        let factorySource = String(appSource[factoryStart.lowerBound..<appSource.endIndex])

        XCTAssertTrue(factorySource.contains("case .localWhisperCpp:"))
        XCTAssertTrue(factorySource.contains("WhisperCppLocalSTTConfiguration("))
        XCTAssertTrue(factorySource.contains("normalizedSettings.whisperCppExecutablePath ?? \"\""))
        XCTAssertTrue(factorySource.contains("WhisperCppLocalSTTProvider(configuration: configuration)"))
        XCTAssertFalse(factorySource.contains(".openAITranscribe, .appleSpeechAnalyzer, .localWhisperKit, .localWhisperCpp"))
    }

    func testRuntimeTTSFactoryUsesKokoroProviderWithoutSystemSpeechFallback() throws {
        let appSource = try readAppShellSource()
        let runtimeFactoryStart = try XCTUnwrap(appSource.range(of: "enum AppTextToSpeechRuntimeFactory"))
        let runtimeFactorySource = String(appSource[runtimeFactoryStart.lowerBound..<appSource.endIndex])

        XCTAssertTrue(appSource.contains("static func makeTextToSpeechPreviewer(settings: AppSettings) -> any TextToSpeechPreviewing"))
        XCTAssertTrue(appSource.contains("AppTextToSpeechRuntimeFactory.makePreviewer(settings: settings)"))
        XCTAssertTrue(runtimeFactorySource.contains("case .systemSpeech, .localKokoro:"))
        XCTAssertTrue(runtimeFactorySource.contains("KokoroLocalTTSConfiguration("))
        XCTAssertTrue(runtimeFactorySource.contains("normalizedSettings.kokoroExecutablePath ?? \"\""))
        XCTAssertTrue(runtimeFactorySource.contains("normalizedSettings.ttsLanguageCode"))
        XCTAssertTrue(runtimeFactorySource.contains("normalizedSettings.ttsVoiceID"))
        XCTAssertTrue(runtimeFactorySource.contains("KokoroLocalTTSProvider(configuration: configuration)"))
        XCTAssertTrue(runtimeFactorySource.contains("TemporaryDirectoryTextToSpeechPreviewer("))
        XCTAssertTrue(runtimeFactorySource.contains("TextToSpeechPreviewService("))
        XCTAssertTrue(runtimeFactorySource.contains("AVFoundationSpeechAudioPlayer()"))
        XCTAssertTrue(runtimeFactorySource.contains("temporaryDirectory: temporaryDirectory"))
        XCTAssertFalse(runtimeFactorySource.contains("AVSpeechSynthesizer"))
    }

    func testAVFoundationSpeechAudioPlayerUsesAudioPlayerInsteadOfSystemSpeech() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Adapters/AVFoundationSpeechAudioPlayer.swift")

        XCTAssertTrue(source.contains("AVAudioPlayer"))
        XCTAssertTrue(source.contains("SpeechAudioPlaying"))
        XCTAssertTrue(source.contains("TemporaryDirectoryTextToSpeechPreviewer"))
        XCTAssertTrue(source.contains("try? FileManager.default.removeItem(at: temporaryDirectory)"))
        XCTAssertTrue(source.contains("UserFacingErrorMessageSanitizer.message("))
        XCTAssertFalse(source.contains("AVSpeechSynthesizer"))
    }

    func testRuntimeLLMFactoryUsesGroqCompatibleProviderWithoutOpenAIFallback() throws {
        let appSource = try readAppShellSource()
        let factoryStart = try XCTUnwrap(appSource.range(of: "private static func makeLLMProvider"))
        let factorySource = String(appSource[factoryStart.lowerBound..<appSource.endIndex])

        XCTAssertTrue(factorySource.contains("case .groqOpenAICompatible:"))
        XCTAssertTrue(factorySource.contains("let defaultBaseURL = entry.baseURL"))
        XCTAssertTrue(factorySource.contains("configuration: .groq("))
        XCTAssertTrue(factorySource.contains("settings.normalizedForRuntime.resolvedGroqBaseURL(defaultBaseURL: defaultBaseURL)"))
        XCTAssertTrue(factorySource.contains("secretStore: secretStore"))
        XCTAssertFalse(factorySource.contains(".openaiResponses,\n             .groqOpenAICompatible"))
    }

    func testSettingsSurfaceUsesRuntimeReadySTTProviderPicker() throws {
        let appSource = try readAppShellSource()

        XCTAssertTrue(appSource.contains("settingsViewModel.selectableSTTProviders"))
        XCTAssertTrue(appSource.contains("settingsViewModel.setWhisperCppExecutablePath($0)"))
        XCTAssertTrue(appSource.contains("settingsViewModel.settings.whisperCppExecutablePath ?? \"\""))
        XCTAssertFalse(appSource.contains("ForEach(STTProvider.releaseReadyCases"))
        XCTAssertFalse(appSource.contains("ForEach(STTProvider.allCases"))
        XCTAssertFalse(appSource.contains("AppleSpeechAnalyzerProvider()"))
        XCTAssertFalse(appSource.contains("WhisperKitProvider()"))
        XCTAssertFalse(appSource.contains("WhisperCppProvider()"))
    }

    func testSettingsSurfaceShowsSyncGateWithoutMockSuccessPath() throws {
        let appSource = try readAppShellSource()
        let syncSource = try readPackageFile("Sources/SoloPMCore/App/SyncService.swift")
        let entitlementSource = try readPackageFile("Sources/SoloPMCore/App/Entitlements.swift")

        XCTAssertTrue(appSource.contains("@StateObject private var syncSettingsViewModelLoader: LazyObservableObjectLoader<SyncSettingsViewModel>"))
        XCTAssertTrue(appSource.contains("loadedValue.objectWillChange.sink"))
        XCTAssertTrue(appSource.contains("let loadedSyncViewModel = syncSettingsViewModelLoader.value"))
        XCTAssertTrue(appSource.contains("if let loadedSyncViewModel"))
        XCTAssertTrue(appSource.contains("Section(\"Sync\")"))
        XCTAssertTrue(appSource.contains("loadedSyncViewModel.startSync()"))
        XCTAssertTrue(appSource.contains("makeEntitlementStore(secretStore: secretStore)"))
        XCTAssertTrue(appSource.contains("if let syncUnavailableLabel = loadedSyncViewModel.syncUnavailableLabel"))
        XCTAssertTrue(appSource.contains("Label(localizedSettingsDisplay(syncUnavailableLabel), systemImage: \"lock\")"))
        XCTAssertTrue(syncSource.contains("public var syncUnavailableLabel: String?"))
        XCTAssertTrue(syncSource.contains("status.state == .idle"))
        XCTAssertTrue(syncSource.contains("throw SyncServiceError.syncBackendNotConfigured"))
        XCTAssertTrue(entitlementSource.contains("case sync"))
        XCTAssertTrue(entitlementSource.contains("case externalSync"))
        XCTAssertTrue(entitlementSource.contains("case cloudRelay"))
        XCTAssertTrue(entitlementSource.contains("case hostedMCPEndpoint"))
        XCTAssertTrue(entitlementSource.contains("case documentScopedAutomation"))
        XCTAssertTrue(entitlementSource.contains("case harnessHistory"))
        XCTAssertTrue(entitlementSource.contains("case externalConnectorWrite"))
        XCTAssertFalse(syncSource.contains("return SyncStartResult(startedAt: Date())"))
    }

    func testSettingsGoogleCalendarRowUsesRuntimeReadinessAndOAuthActions() throws {
        let appSource = try readAppShellSource()
        let syncStart = try XCTUnwrap(appSource.range(of: "private var syncSettingsTab: some View"))
        let providerStart = try XCTUnwrap(appSource.range(of: "private var selectedProviderConfigurationFields: some View"))
        let syncSource = String(appSource[syncStart.lowerBound..<providerStart.lowerBound])

        XCTAssertTrue(appSource.contains("let googleCalendarStatusProvider: () -> GoogleCalendarRuntimeSyncStatus"))
        XCTAssertTrue(appSource.contains("let googleCalendarOAuthConnector: (any GoogleCalendarOAuthConnecting)?"))
        XCTAssertTrue(appSource.contains("let googleCalendarOAuthDisconnecter: (any GoogleCalendarOAuthDisconnecting)?"))
        XCTAssertTrue(appSource.contains("let googleCalendarListProviderFactory: () -> (any GoogleCalendarListProviding)?"))
        XCTAssertTrue(appSource.contains("@State private var googleCalendarSyncStatus: GoogleCalendarRuntimeSyncStatus?"))
        XCTAssertTrue(appSource.contains("@State private var googleCalendarSetupMessage: String?"))
        XCTAssertTrue(appSource.contains("@State private var isGoogleCalendarOAuthAuthorizationInProgress = false"))
        XCTAssertTrue(appSource.contains("@State private var isConfirmingGoogleCalendarOAuthDisconnect = false"))
        XCTAssertTrue(appSource.contains("@State private var isLoadingGoogleCalendarList = false"))
        XCTAssertTrue(appSource.contains("@State private var googleCalendarListOptions: [GoogleCalendarRuntimeCalendarListEntry] = []"))
        XCTAssertTrue(appSource.contains("@State private var googleCalendarListLoadGeneration = 0"))
        XCTAssertTrue(appSource.contains("_googleCalendarSyncStatus = State(initialValue: nil)"))
        XCTAssertTrue(appSource.contains("private var googleCalendarSettingsReadinessRow: GoogleCalendarSettingsReadinessRow"))
        XCTAssertTrue(appSource.contains("GoogleCalendarSettingsReadinessRow(status: googleCalendarSyncStatus)"))
        XCTAssertTrue(syncSource.contains("status: googleCalendarSettingsReadinessRow.statusLabel"))
        XCTAssertTrue(syncSource.contains("detail: googleCalendarSettingsReadinessRow.detailLabel"))
        XCTAssertTrue(syncSource.contains("nextAction: googleCalendarSettingsReadinessRow.nextActionLabel"))
        XCTAssertTrue(syncSource.contains("privacyBoundary: googleCalendarSettingsReadinessRow.privacyBoundaryLabel"))
        XCTAssertTrue(syncSource.contains("statusActionLabel: googleCalendarSettingsReadinessRow.statusCheckActionLabel"))
        XCTAssertTrue(syncSource.contains("onStatusAction: refreshGoogleCalendarSettingsStatus"))
        XCTAssertTrue(appSource.contains("settings-google-calendar-readiness-check"))
        XCTAssertTrue(appSource.contains("settings-google-calendar-readiness-status"))
        XCTAssertTrue(appSource.contains("settings-google-calendar-readiness-detail"))
        XCTAssertTrue(syncSource.contains("\"Google Calendar ID\""))
        XCTAssertTrue(syncSource.contains("settingsViewModel.settings.googleCalendarID"))
        XCTAssertTrue(syncSource.contains("settingsViewModel.setGoogleCalendarID($0)"))
        XCTAssertTrue(syncSource.contains("GoogleCalendarSettingsSaveControls("))
        XCTAssertTrue(syncSource.contains("settings-google-calendar-id-save-flow"))
        XCTAssertTrue(syncSource.contains("settings-google-calendar-id"))
        XCTAssertTrue(syncSource.contains("saveCalendarID: saveGoogleCalendarIDSetting"))
        XCTAssertTrue(appSource.contains("private func saveGoogleCalendarIDSetting()"))
        XCTAssertTrue(syncSource.contains("Picker(\"Available Calendar\""))
        XCTAssertTrue(syncSource.contains("ForEach(calendarListOptions)"))
        XCTAssertTrue(syncSource.contains("settings-google-calendar-picker"))
        XCTAssertTrue(syncSource.contains("loadCalendarList: loadGoogleCalendarList"))
        XCTAssertTrue(syncSource.contains("settings-google-calendar-list-load"))
        XCTAssertTrue(syncSource.contains("isCalendarListLoadDisabled: isLoadingGoogleCalendarList || isGoogleCalendarOAuthAuthorizationInProgress || googleCalendarListProvider == nil"))
        XCTAssertTrue(appSource.contains("private func loadGoogleCalendarList()"))
        XCTAssertTrue(appSource.contains("guard !isGoogleCalendarOAuthAuthorizationInProgress else"))
        XCTAssertTrue(appSource.contains("private func invalidateGoogleCalendarListOptions()"))
        XCTAssertTrue(appSource.contains("generation == googleCalendarListLoadGeneration"))
        XCTAssertTrue(appSource.contains("invalidateGoogleCalendarListOptions()"))
        XCTAssertTrue(appSource.contains("googleCalendarListProvider.listWritableCalendars()"))
        XCTAssertTrue(appSource.contains("Google Calendar list loaded. Choose a calendar, then save."))
        XCTAssertTrue(appSource.contains("Google Calendar list is not available in this build."))
        XCTAssertTrue(appSource.contains("Reconnect Google Calendar with OAuth before loading calendars."))
        XCTAssertTrue(appSource.contains("Wait for Google Calendar OAuth authorization to finish before loading calendars."))
        XCTAssertTrue(appSource.contains("Connect with OAuth authorization"))
        XCTAssertTrue(syncSource.contains("Button(localizedSettingsDisplay(googleCalendarOAuthActionLabel))"))
        XCTAssertTrue(syncSource.contains("startGoogleCalendarOAuthAuthorization()"))
        XCTAssertTrue(appSource.contains("isConfirmingGoogleCalendarOAuthDisconnect = true"))
        XCTAssertTrue(appSource.contains("disconnectGoogleCalendarOAuthAuthorization()"))
        XCTAssertTrue(appSource.contains("settings-google-calendar-oauth-disconnect-confirm"))
        XCTAssertTrue(appSource.contains("This removes local Google Calendar OAuth tokens from Keychain. Tasks and saved calendar ID stay unchanged."))
        XCTAssertTrue(syncSource.contains("settings-google-calendar-oauth-disconnect"))
        XCTAssertTrue(syncSource.contains("role: .destructive"))
        XCTAssertLessThan(
            try XCTUnwrap(syncSource.range(of: "settings-google-calendar-id-save")).lowerBound,
            try XCTUnwrap(syncSource.range(of: "settings-google-calendar-list-load")).lowerBound
        )
        XCTAssertLessThan(
            try XCTUnwrap(syncSource.range(of: "GoogleCalendarSettingsSaveControls(")).lowerBound,
            try XCTUnwrap(syncSource.range(of: "ExternalConnectorScopeRow(")).lowerBound
        )
        XCTAssertTrue(appSource.contains("googleCalendarOAuthConnector.startAuthorization"))
        XCTAssertTrue(appSource.contains("googleCalendarOAuthDisconnecter.disconnect()"))
        XCTAssertTrue(appSource.contains("GoogleCalendarAppRuntimeFactory.disconnectOAuthCredential"))
        XCTAssertTrue(appSource.contains("OAuth authorization opens in the system browser with PKCE. Tokens stay in Keychain before calendar writes are enabled."))
        XCTAssertTrue(appSource.contains("Google Calendar OAuth disconnected. Tokens were removed from Keychain."))
        XCTAssertTrue(syncSource.contains("settings-google-calendar-oauth-setup-message"))
        XCTAssertTrue(appSource.contains("GoogleCalendarOAuthAuthenticationSessionController"))
        XCTAssertTrue(appSource.contains("ASWebAuthenticationSession("))
        XCTAssertTrue(appSource.contains("SOLOPM_GOOGLE_CALENDAR_OAUTH_CLIENT_ID"))
        XCTAssertTrue(appSource.contains("SoloPMGoogleCalendarOAuthClientID"))
        XCTAssertTrue(appSource.contains("GoogleCalendarAppRuntimeFactory.makeCalendarListClient"))
        XCTAssertTrue(appSource.contains("oauthClientID: googleCalendarOAuthClientID()"))
        XCTAssertTrue(appSource.contains("let runtimeSettings = loadRuntimeAppSettings()"))
        XCTAssertTrue(appSource.contains("calendarID: runtimeSettings.googleCalendarID"))
        XCTAssertTrue(appSource.contains("timeZoneIdentifier: runtimeSettings.timeZoneIdentifier"))
        XCTAssertFalse(syncSource.contains("The connect flow is not available in this build yet."))
        XCTAssertFalse(syncSource.contains("settingsViewModel.setTransientErrorMessage"))
        XCTAssertFalse(syncSource.contains("Google Calendar API Key"))
        XCTAssertFalse(syncSource.contains("geminiAPIKeyInput"))
    }

    func testSyncSettingsTabSurfacesPaidValueAndLocalBoundaryBeforeToggle() throws {
        let appSource = try readAppShellSource()
        let audit = try readPackageFile("docs/ux/click-path-audit.md")
        let investorReview = try readPackageFile("docs/product/investor-review.md")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")
        let syncStart = try XCTUnwrap(appSource.range(of: "private var syncSettingsTab: some View"))
        let providerStart = try XCTUnwrap(appSource.range(of: "@ViewBuilder\n    private var selectedProviderConfigurationFields"))
        let syncSource = String(appSource[syncStart.lowerBound..<providerStart.lowerBound])

        XCTAssertTrue(appSource.contains("SyncValueStatusRow("))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"sync-paid-value-row\")"))
        XCTAssertTrue(appSource.contains("private var syncPaidValueLabel: String"))
        XCTAssertTrue(appSource.contains("private var syncSafetyBoundaryLabel: String"))
        XCTAssertLessThan(
            try XCTUnwrap(syncSource.range(of: "SyncValueStatusRow(")).lowerBound,
            try XCTUnwrap(syncSource.range(of: "Toggle(")).lowerBound
        )
        XCTAssertTrue(audit.contains("Sync paid value row"))
        XCTAssertTrue(investorReview.contains("Settings/Sync now surfaces the Pro value and local-only safety boundary before the toggle"))
        XCTAssertTrue(phase.contains("[x] Sync tabはtoggle前にPro価値、Freeのlocal-only境界、backend未構成時の次状態を表示し、課金価値がdisabled toggleだけに埋もれない。"))
    }

    func testSyncSettingsTabNamesExternalConnectorScopeWithoutLinkingConnectorTarget() throws {
        let appSource = try readAppShellSource()
        let syncStart = try XCTUnwrap(appSource.range(of: "private var syncSettingsTab: some View"))
        let providerStart = try XCTUnwrap(appSource.range(of: "@ViewBuilder\n    private var selectedProviderConfigurationFields"))
        let syncSource = String(appSource[syncStart.lowerBound..<providerStart.lowerBound])

        XCTAssertTrue(syncSource.contains("Section(\"External Task Tools\")"))
        XCTAssertTrue(syncSource.contains("name: \"Google Calendar\""))
        XCTAssertTrue(syncSource.contains("ExternalConnectorExposurePolicy.exposure(for: .googleCalendar).systemImage"))
        XCTAssertTrue(syncSource.contains("hiddenConnectorPolicySummary"))
        XCTAssertTrue(syncSource.contains(".accessibilityIdentifier(\"settings-external-connector-policy-boundary\")"))
        XCTAssertFalse(syncSource.contains("Connector planned"))
        XCTAssertFalse(syncSource.contains("name: \"Todoist\""))
        XCTAssertFalse(syncSource.contains("name: \"Notion\""))
        XCTAssertFalse(syncSource.contains("name: \"Linear\""))
        XCTAssertFalse(syncSource.contains("name: \"GitHub Issues\""))
        XCTAssertTrue(syncSource.contains("Pro unlocks external sync; import/export JSON stays local."))
        XCTAssertFalse(appSource.contains("import SoloPMExternalConnectors"))
    }

    func testAppRuntimeWiresGoogleCalendarSyncWithoutFakeUnavailableStore() throws {
        let appSource = try readAppShellSource()
        let factoryStart = try XCTUnwrap(appSource.range(of: "googleCalendarSyncFactory: {"))
        let factoryEnd = try XCTUnwrap(appSource.range(of: "return ProjectBoardViewModel(", range: factoryStart.lowerBound..<appSource.endIndex))
        let factorySource = String(appSource[factoryStart.lowerBound..<factoryEnd.lowerBound])
        let settingsBackedStart = try XCTUnwrap(appSource.range(of: "static func makeSettingsBackedGoogleCalendarSyncController("))
        let settingsBackedEnd = try XCTUnwrap(appSource.range(of: "private static func makeGoogleCalendarSyncController(", range: settingsBackedStart.lowerBound..<appSource.endIndex))
        let settingsBackedSource = String(appSource[settingsBackedStart.lowerBound..<settingsBackedEnd.lowerBound])
        let helperStart = try XCTUnwrap(appSource.range(of: "private static func makeGoogleCalendarSyncController("))
        let helperEnd = try XCTUnwrap(appSource.range(of: "private static func makeGoogleCalendarOAuthAuthorizationService()", range: helperStart.lowerBound..<appSource.endIndex))
        let helperSource = String(appSource[helperStart.lowerBound..<helperEnd.lowerBound])

        XCTAssertTrue(appSource.contains("import SoloPMGoogleCalendarRuntime"))
        XCTAssertTrue(appSource.contains("static func makeEntitlementStore(secretStore: any SecretStore) -> KeychainEntitlementStore"))
        XCTAssertTrue(appSource.contains("static func makeLocalLicenseVerifier() -> any LocalLicenseVerifier"))
        XCTAssertTrue(appSource.contains("SoloPMLocalLicensePublicKey"))
        XCTAssertTrue(appSource.contains("SignedLocalLicenseVerifier(publicKeyBase64: publicKeyBase64)"))
        XCTAssertTrue(factorySource.contains("let secretStore = makeSecretStore()"))
        XCTAssertTrue(factorySource.contains("entitlementStore: makeEntitlementStore(secretStore: secretStore)"))
        XCTAssertTrue(factorySource.contains("makeSettingsBackedGoogleCalendarSyncController("))
        XCTAssertTrue(factorySource.contains("googleCalendarSyncFactory: {"))
        XCTAssertTrue(settingsBackedSource.contains("SettingsBackedGoogleCalendarRuntimeSync("))
        XCTAssertTrue(settingsBackedSource.contains("settingsStore: UserDefaultsAppSettingsStore()"))
        XCTAssertTrue(settingsBackedSource.contains("GoogleCalendarAppRuntimeFactory.syncStatus("))
        XCTAssertTrue(settingsBackedSource.contains("calendarID: settings.googleCalendarID"))
        XCTAssertTrue(settingsBackedSource.contains("timeZoneIdentifier: settings.timeZoneIdentifier"))
        XCTAssertTrue(settingsBackedSource.contains("oauthClientID: googleCalendarOAuthClientID()"))
        XCTAssertTrue(settingsBackedSource.contains("syncFactory:"))
        XCTAssertFalse(factorySource.contains("let runtimeSettings = loadRuntimeAppSettings()"))
        XCTAssertTrue(helperSource.contains("GoogleCalendarAppRuntimeFactory.makeSyncController("))
        XCTAssertTrue(helperSource.contains("idempotencyNamespaceStore:"))
        XCTAssertTrue(helperSource.contains("calendarID: calendarID"))
        XCTAssertTrue(helperSource.contains("oauthClientID: googleCalendarOAuthClientID()"))
        XCTAssertFalse(helperSource.contains("calendarID: \"primary\""))
        XCTAssertFalse(factorySource.contains("UnavailableGoogleCalendarRuntimeCredentialStatusStore()"))
        XCTAssertFalse(factorySource.contains("taskSyncService: nil"))
        XCTAssertFalse(helperSource.contains("UnavailableGoogleCalendarRuntimeCredentialStatusStore()"))
        XCTAssertFalse(helperSource.contains("taskSyncService: nil"))
    }

    func testProjectBoardGoogleCalendarSyncMenuUsesRuntimeReadinessInsteadOfHardcodedDisabled() throws {
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let menuStart = try XCTUnwrap(boardSource.range(of: "Button {\n                    isGoogleCalendarSyncApprovalPresented = true"))
        let menuEnd = try XCTUnwrap(boardSource.range(of: "} label: {\n                Label(\"Integrations\"", range: menuStart.lowerBound..<boardSource.endIndex))
        let googleCalendarMenuSource = String(boardSource[menuStart.lowerBound..<menuEnd.lowerBound])

        XCTAssertTrue(boardSource.contains("@State private var isGoogleCalendarSyncApprovalPresented = false"))
        XCTAssertTrue(googleCalendarMenuSource.contains("isGoogleCalendarSyncApprovalPresented = true"))
        XCTAssertTrue(googleCalendarMenuSource.contains(".disabled(!viewModel.canSyncGoogleCalendar)"))
        XCTAssertTrue(googleCalendarMenuSource.contains(".help(viewModel.googleCalendarSyncHelp)"))
        XCTAssertFalse(googleCalendarMenuSource.contains(".disabled(true)"))
        XCTAssertFalse(boardSource.contains("syncDueTasksToGoogleCalendar(approvalToken: nil)"))
        XCTAssertFalse(boardSource.contains("ProjectBoardIntegrationUnavailableError.googleCalendarOAuthNotConfigured"))
    }

    func testProjectBoardGoogleCalendarSyncRequiresDialogApprovalToken() throws {
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let dialogStart = try XCTUnwrap(boardSource.range(of: ".confirmationDialog(\n            \"Sync due tasks to Google Calendar?\""))
        let dialogEnd = try XCTUnwrap(boardSource.range(of: "private var inspectorBinding", range: dialogStart.lowerBound..<boardSource.endIndex))
        let dialogSource = String(boardSource[dialogStart.lowerBound..<dialogEnd.lowerBound])

        XCTAssertTrue(dialogSource.contains("isPresented: $isGoogleCalendarSyncApprovalPresented"))
        XCTAssertTrue(dialogSource.contains("Button(\"Approve Google Calendar Sync\")"))
        XCTAssertTrue(dialogSource.contains("approveGoogleCalendarSync()"))
        XCTAssertTrue(dialogSource.contains("Button(\"Cancel\", role: .cancel)"))
        XCTAssertTrue(dialogSource.contains("project-board-google-calendar-sync-approval-confirm"))
        XCTAssertTrue(dialogSource.contains("project-board-google-calendar-sync-approval-cancel"))
        XCTAssertTrue(boardSource.contains("viewModel.syncDueTasksToGoogleCalendar(approvalToken: UUID().uuidString)"))
    }

    func testSettingsSurfaceShowsInlineMCPServerRowsWithCheckActions() throws {
        let appSource = try readAppShellSource()
        let mcpSource = try readPackageFile("Sources/SoloPMCore/ExternalMCP/MCPRegistration.swift")
        let audit = try readPackageFile("docs/ux/click-path-audit.md")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")

        XCTAssertTrue(appSource.contains("MCPServerSettingsRow("))
        XCTAssertTrue(appSource.contains("if let loadedExternalMCPViewModel"))
        XCTAssertTrue(appSource.contains("ForEach(loadedExternalMCPViewModel.registrationRows) { row in"))
        XCTAssertTrue(appSource.contains("await loadedExternalMCPViewModel.checkConnection(id: row.id)"))
        XCTAssertTrue(appSource.contains("row.connectionCheckResultLabel"))
        XCTAssertTrue(appSource.contains("row.statusLabel"))
        XCTAssertTrue(appSource.contains("row.isCheckingConnection"))
        XCTAssertTrue(mcpSource.contains("connectionCheckResultLabel"))
        XCTAssertTrue(mcpSource.contains("isSelected"))
        XCTAssertTrue(mcpSource.contains("public func checkConnection(id registrationID: String) async"))
        XCTAssertFalse(appSource.contains("Picker(\"Server\""))
        XCTAssertTrue(audit.contains("対象server rowの `Check`"))
        XCTAssertTrue(audit.contains("Picker切替を不要にし"))
        XCTAssertTrue(phase.contains("[x] 複数MCP serverの接続確認をPicker切替ではなくserver row上の `Check`"))
    }

    func testMCPSettingsTabSurfacesPaidExecutionBoundaryBeforeRegistrationEditing() throws {
        let appSource = try readAppShellSource()
        let executionSource = try readPackageFile("Sources/SoloPMCore/ExternalMCP/MCPExecution.swift")
        let audit = try readPackageFile("docs/ux/click-path-audit.md")
        let investorReview = try readPackageFile("docs/product/investor-review.md")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")
        let mcpStart = try XCTUnwrap(appSource.range(of: "private var mcpSettingsTab: some View"))
        let statusStart = try XCTUnwrap(appSource.range(of: "private var activeAIProviderStatusLabel"))
        let mcpTabSource = String(appSource[mcpStart.lowerBound..<statusStart.lowerBound])

        XCTAssertTrue(appSource.contains("MCPPaidExecutionBoundaryRow("))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"mcp-paid-execution-boundary-row\")"))
        XCTAssertTrue(appSource.contains("private var mcpExecutionValueLabel: String"))
        XCTAssertTrue(appSource.contains("private var mcpExecutionSafetyBoundaryLabel: String"))
        XCTAssertTrue(appSource.contains("FeatureGate.advancedMCPExecution.requiredPlan.displayName"))
        XCTAssertTrue(executionSource.contains("entitlementChecker.require(.advancedMCPExecution)"))
        XCTAssertLessThan(
            try XCTUnwrap(mcpTabSource.range(of: "MCPPaidExecutionBoundaryRow(")).lowerBound,
            try XCTUnwrap(mcpTabSource.range(of: "Toggle(")).lowerBound
        )
        XCTAssertTrue(audit.contains("MCP paid execution boundary row"))
        XCTAssertTrue(investorReview.contains("MCP now surfaces Pro execution value and approval safety before registration editing"))
        XCTAssertTrue(phase.contains("[x] MCP tabは登録編集前にPro実行価値、Freeで可能な登録/接続確認、tools/call前のentitlement/approval/policy境界を表示する。"))
    }

    func testClickPathAuditTracksTaskCardFocusUpgradeAndRemainingManualEvidence() throws {
        let audit = try readPackageFile("docs/ux/click-path-audit.md")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")

        XCTAssertTrue(audit.contains("cardの `Open task` 領域 -> inspector編集 -> `Save Changes`"))
        XCTAssertTrue(audit.contains("キーボードフォーカス可能なButton"))
        XCTAssertTrue(audit.contains("Open Detailsとstatus move controlsも別フォーカス対象に分離"))
        XCTAssertTrue(audit.contains("Task card screenshot証跡は生成・目視確認済み"))
        XCTAssertTrue(audit.contains("Light/Dark/Systemスクリーンショットでtitle、状態、優先度、期限、drag affordanceが重ならないことを確認済み"))
        XCTAssertTrue(audit.contains("実機VoiceOver focus order確認は残る"))
        XCTAssertTrue(phase.contains("[x] Task card本体のOpen Detailsとstatus move controlsを別フォーカス対象に分け"))
        XCTAssertTrue(phase.contains("[x] Task cardはタイトル、状態、優先度、期限、ドラッグ affordance が重ならず表示されることをスクリーンショットで確認する。"))
        XCTAssertTrue(phase.contains("[ ] 実機VoiceOverでProject board -> card -> Inline Task Composer -> inspectorのfocus orderを確認する。"))
        XCTAssertTrue(phase.contains("[x] `script/capture_ui_evidence.sh` は一時HOME、seed済みProject board、Light/Dark/System切替、window captureを使う。"))
        XCTAssertTrue(phase.contains("[x] Light/Dark/System切替後にカード、サイドバー、インスペクタのコントラストが破綻しないことをスクリーンショットで確認する。"))
    }

    func testClickPathAuditLinksPrimaryOperationsToImplementationEvidence() throws {
        let audit = try readPackageFile("docs/ux/click-path-audit.md")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")

        XCTAssertTrue(audit.contains("## 改善紐づけ"))
        XCTAssertTrue(audit.contains("PR未作成のため、現時点ではcurrent branchの改善commitとsource testに紐づける"))
        XCTAssertTrue(audit.contains("PR作成時はこの表をPR descriptionに転記する"))
        XCTAssertTrue(audit.contains("Sources/SoloPMApp/Views/ProjectBoardView.swift"))
        XCTAssertTrue(audit.contains("Sources/SoloPMApp/Views/ProjectWorkflowInboxView.swift"))
        XCTAssertTrue(audit.contains("Sources/SoloPMApp/Views/ProjectWorkflowTodayView.swift"))
        XCTAssertTrue(audit.contains("Sources/SoloPMApp/SoloPMApp.swift"))
        XCTAssertTrue(audit.contains("Tests/SoloPMCoreTests/ProjectBoardStoreTests.swift"))
        XCTAssertTrue(audit.contains("Tests/SoloPMCoreTests/ExternalMCPTests.swift"))
        XCTAssertTrue(audit.contains("Tests/SoloPMCoreTests/SyncEntitlementTests.swift"))
        XCTAssertTrue(audit.contains("AppExperienceSourceTests.testTaskCardsUseSampleInspiredNonOverlappingMetadataStrip"))
        XCTAssertTrue(audit.contains("ProjectBoardStoreTests.testCreateTaskPersistsRequestedColumnMetadataAndDetail"))
        XCTAssertTrue(audit.contains("ProjectBoardStoreTests.testProjectBoardViewModelInboxClassificationShowsFeedbackAdvancesSelectionAndUndo"))
        XCTAssertTrue(audit.contains("ExternalMCPTests.testExternalMCPSettingsViewModelChecksSpecificRegistrationFromInlineRow"))
        XCTAssertTrue(audit.contains("SyncEntitlementTests.testSyncServiceFreeStartFailsBeforeNetworkClientIsReached"))
        XCTAssertTrue(audit.contains("SyncEntitlementTests.testSyncServiceConfiguredBackendRecordsNetworkFailureInsteadOfReturningReady"))
        XCTAssertTrue(audit.contains("SyncEntitlementTests.testSyncSettingsViewModelShowsFailedStateAfterNetworkFailure"))
        XCTAssertTrue(phase.contains("[x] UX click-path auditで主要操作のクリック数が記録され、改善PRと紐づいている。"))
    }

    func testUIScreenshotEvidenceUsesIsolatedSeededProjectBoard() throws {
        let script = try readPackageFile("script/capture_ui_evidence.sh")
        let windowMetadataScript = try readPackageFile("script/ui_evidence_window_metadata.swift")
        let contentCheckScript = try readPackageFile("script/ui_evidence_content_check.swift")
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let persistenceSource = try readPackageFile("Sources/SoloPMCore/App/ProjectBoardSelectionPersistence.swift")
        let evidence = try readPackageFile("docs/release/evidence/ui-screenshots.md")
        let audit = try readPackageFile("docs/ux/click-path-audit.md")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")

        XCTAssertTrue(script.contains("script/build_and_run.sh\" --build-only"))
        XCTAssertTrue(script.contains("CFFIXED_USER_HOME"))
        XCTAssertTrue(script.contains("SOLOPM_UI_EVIDENCE_HOME"))
        XCTAssertTrue(script.contains("SOLOPM_UI_EVIDENCE_TMPDIR"))
        XCTAssertTrue(script.contains("SOLOPM_DATABASE_PATH=$DATABASE_PATH"))
        XCTAssertTrue(script.contains("SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1"))
        XCTAssertTrue(script.contains("SOLOPM_FORCE_PROJECT_BOARD_FALLBACK=1"))
        XCTAssertTrue(script.contains("solopm.appearancePreference"))
        XCTAssertTrue(script.contains("ui_evidence_window_metadata.swift"))
        XCTAssertTrue(windowMetadataScript.contains("CGWindowListCopyWindowInfo"))
        XCTAssertTrue(script.contains("wait_for_window_capture_metadata"))
        XCTAssertTrue(script.contains("position_window_for_capture"))
        XCTAssertTrue(script.contains("Avoid LaunchServices activation"))
        XCTAssertTrue(script.contains("tell application \"System Events\""))
        XCTAssertFalse(script.contains(#"tell application \"$APP_NAME\" to activate"#))
        XCTAssertTrue(script.contains("screencapture -x -l"))
        XCTAssertTrue(script.contains("screencapture -x -R"))
        XCTAssertTrue(script.contains("assert_screenshot_has_visible_content"))
        XCTAssertTrue(script.contains("ui_evidence_content_check.swift"))
        XCTAssertTrue(script.contains("ui_evidence_source_commit()"))
        XCTAssertTrue(script.contains("- Source commit: `%s`"))
        XCTAssertTrue(contentCheckScript.contains("CGImageSourceCreateWithURL"))
        XCTAssertTrue(contentCheckScript.contains("Screenshot appears blank or too low contrast"))
        XCTAssertTrue(script.contains("sqlite3"))
        XCTAssertTrue(script.contains("Launch Readiness"))
        XCTAssertTrue(script.contains("seed_mcp_registrations"))
        XCTAssertTrue(script.contains("Local Filesystem MCP"))
        XCTAssertTrue(script.contains("Issue Tracker MCP"))
        XCTAssertTrue(script.contains("mcp_server_registrations"))
        XCTAssertTrue(script.contains("persist_project_board_selection"))
        XCTAssertTrue(script.contains("write_app_preference"))
        XCTAssertTrue(script.contains("HOME=\"$EVIDENCE_HOME\""))
        XCTAssertTrue(script.contains("/usr/bin/env \"${env_args[@]}\" \"$APP_BINARY\" -ApplePersistenceIgnoreState YES"))
        XCTAssertTrue(script.contains("Direct launch preserves the isolated database"))
        XCTAssertFalse(script.contains("open_args+=(--env \"$env_arg\")"))
        XCTAssertFalse(script.contains("/usr/bin/open \"${open_args[@]}\""))
        XCTAssertTrue(script.contains("/usr/bin/defaults write \"$BUNDLE_IDENTIFIER\""))
        XCTAssertTrue(script.contains("solopm.projectBoard.selectedDestination"))
        XCTAssertTrue(script.contains("SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION=$PROJECT_BOARD_SELECTION_OVERRIDE"))
        XCTAssertTrue(script.contains("SOLOPM_PROJECT_BOARD_SELECTED_TASK_ID=$PROJECT_BOARD_SELECTED_TASK_OVERRIDE"))
        XCTAssertTrue(script.contains("SOLOPM_APPEARANCE_PREFERENCE=$APPEARANCE_OVERRIDE"))
        XCTAssertTrue(script.contains("project:$project_id"))
        XCTAssertTrue(script.contains("INBOX_VOICE_TASK_OVERRIDE=\"$inbox_voice_task_id\""))
        XCTAssertTrue(script.contains("project-board-light.png"))
        XCTAssertTrue(script.contains("project-board-dark.png"))
        XCTAssertTrue(script.contains("project-board-system.png"))
        XCTAssertTrue(script.contains("capture_project_board_destination light \"$PROJECT_BOARD_SELECTION_OVERRIDE\" \"$LIGHT_SCREENSHOT\" \"Project Board\""))
        XCTAssertTrue(script.contains("capture_project_board_destination dark \"$PROJECT_BOARD_SELECTION_OVERRIDE\" \"$DARK_SCREENSHOT\" \"Project Board\""))
        XCTAssertTrue(script.contains("capture_project_board_destination system \"$PROJECT_BOARD_SELECTION_OVERRIDE\" \"$SYSTEM_SCREENSHOT\" \"Project Board\""))
        XCTAssertTrue(script.contains("settings-appearance-light.png"))
        XCTAssertTrue(script.contains("settings-appearance-dark.png"))
        XCTAssertTrue(script.contains("settings-overview-light.png"))
        XCTAssertTrue(script.contains("settings-overview-dark.png"))
        XCTAssertTrue(script.contains("settings-mcp-light.png"))
        XCTAssertTrue(script.contains("settings-mcp-dark.png"))
        XCTAssertTrue(script.contains("SCHEDULE_COCKPIT=1"))
        XCTAssertTrue(script.contains("write_schedule_cockpit_evidence_file"))
        XCTAssertTrue(script.contains("script/capture_ui_evidence.sh --schedule-cockpit"))
        XCTAssertTrue(script.contains("schedule-week-time-axis-grid=>Schedule time axis grid"))
        XCTAssertTrue(script.contains("SCHEDULE_COCKPIT_TARGET_MARKERS=\"schedule-workflow=>Schedule|schedule-week-grid=>schedule-week-grid|schedule-week-time-axis-grid=>schedule-week-time-axis-grid\""))
        XCTAssertTrue(script.contains("capture_project_board_destination light schedule \"$SCHEDULE_LIGHT_SCREENSHOT\" \"Schedule cockpit\" \"$SCHEDULE_COCKPIT_TARGET_MARKERS\""))
        XCTAssertTrue(script.contains("capture_project_board_destination dark schedule \"$SCHEDULE_DARK_SCREENSHOT\" \"Schedule cockpit\" \"$SCHEDULE_COCKPIT_TARGET_MARKERS\""))
        XCTAssertTrue(script.contains("if [[ \"$SCHEDULE_COCKPIT\" == \"1\" ]]"))
        XCTAssertTrue(script.contains("/usr/bin/env \"${env_args[@]}\" \"$APP_BINARY\" -ApplePersistenceIgnoreState YES >/dev/null 2>&1 &"))
        XCTAssertTrue(script.contains("if [[ \"$SCHEDULE_COCKPIT\" != \"1\" ]]"))
        XCTAssertTrue(script.contains("open_settings_overview_tab"))
        XCTAssertTrue(script.contains("capture_settings_overview"))
        XCTAssertTrue(script.contains("open_settings_appearance_tab"))
        XCTAssertTrue(script.contains("capture_settings_appearance"))
        XCTAssertTrue(script.contains("open_mcp_settings_tab"))
        XCTAssertTrue(script.contains("capture_mcp_settings_appearance"))
        XCTAssertTrue(script.contains("SOLOPM_SETTINGS_EVIDENCE_TAB=$SETTINGS_TAB_OVERRIDE"))
        XCTAssertTrue(script.contains("docs/release/evidence/ui-screenshots"))
        XCTAssertTrue(script.contains("Screen Recording permission"))
        XCTAssertFalse(script.contains("OpenAI API Key"))
        XCTAssertFalse(script.contains("sk-proj-"))
        XCTAssertFalse(script.contains("sk-live-"))

        XCTAssertTrue(boardSource.contains("@AppStorage(ProjectBoardSelectionPersistence.storageKey)"))
        XCTAssertTrue(boardSource.contains("restoreSelectedDestinationIfNeeded()"))
        XCTAssertTrue(boardSource.contains("persistSelectedDestination(_ destination: ProjectBoardSidebarDestination?)"))
        XCTAssertTrue(persistenceSource.contains("public enum ProjectBoardSelectionPersistence"))
        XCTAssertTrue(persistenceSource.contains("static let storageKey = \"solopm.projectBoard.selectedDestination\""))
        XCTAssertTrue(persistenceSource.contains("static let environmentOverrideKey = \"SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION\""))
        XCTAssertTrue(persistenceSource.contains("public enum ProjectBoardTaskSelectionPersistence"))
        XCTAssertTrue(persistenceSource.contains("static let environmentOverrideKey = \"SOLOPM_PROJECT_BOARD_SELECTED_TASK_ID\""))
        XCTAssertTrue(boardSource.contains("ProjectBoardSelectionPersistence.environmentOverrideRawValue"))
        XCTAssertTrue(boardSource.contains("applySelectedTaskOverrideIfNeeded()"))
        let destinationChangeStart = try XCTUnwrap(boardSource.range(of: ".onChange(of: selectedDestination)"))
        let destinationChangeEnd = try XCTUnwrap(boardSource.range(
            of: ".fileExporter",
            range: destinationChangeStart.upperBound..<boardSource.endIndex
        ))
        let destinationChangeSource = String(boardSource[destinationChangeStart.lowerBound..<destinationChangeEnd.lowerBound])
        let destinationApply = try XCTUnwrap(destinationChangeSource.range(of: "applySelectedDestination(destination)"))
        let taskOverrideApply = try XCTUnwrap(destinationChangeSource.range(of: "applySelectedTaskOverrideIfNeeded()"))
        XCTAssertLessThan(destinationApply.lowerBound, taskOverrideApply.lowerBound)
        XCTAssertTrue(boardSource.contains("ProjectBoardTaskSelectionPersistence.environmentOverrideTaskID"))
        XCTAssertTrue(persistenceSource.contains("case \"project\""))

        XCTAssertTrue(evidence.contains("script/capture_ui_evidence.sh"))
        XCTAssertTrue(evidence.contains("- Source commit: `"))
        XCTAssertTrue(evidence.contains("isolated temporary HOME"))
        XCTAssertTrue(evidence.contains("project-board-light.png"))
        XCTAssertTrue(evidence.contains("project-board-dark.png"))
        XCTAssertTrue(evidence.contains("project-board-system.png"))
        XCTAssertTrue(evidence.contains("settings-appearance-light.png"))
        XCTAssertTrue(evidence.contains("settings-appearance-dark.png"))
        XCTAssertTrue(evidence.contains("settings-overview-light.png"))
        XCTAssertTrue(evidence.contains("settings-overview-dark.png"))
        XCTAssertTrue(evidence.contains("settings-mcp-light.png"))
        XCTAssertTrue(evidence.contains("settings-mcp-dark.png"))
        XCTAssertTrue(evidence.contains("Manual review: passed for Project Board sidebar/cards/inspector, Inbox voice detail, Today cockpit, Projects overview, Schedule cockpit, Schedule workload dashboard, Done analytics, Settings integrations, Settings Appearance Theme picker, Settings MCP server rows, and Light/Dark/System contrast"))
        XCTAssertTrue(audit.contains("Task card screenshot証跡は生成・目視確認済み"))
        XCTAssertTrue(audit.contains("Settings Overview Pro Value rowのスクリーンショット証跡は生成・目視確認済み"))
        XCTAssertTrue(audit.contains("MCP server別の接続状態証跡は生成・目視確認済み"))
        XCTAssertTrue(audit.contains("settings-overview-light.png"))
        XCTAssertTrue(audit.contains("settings-overview-dark.png"))
        XCTAssertTrue(audit.contains("settings-appearance-light.png"))
        XCTAssertTrue(audit.contains("settings-appearance-dark.png"))
        XCTAssertTrue(audit.contains("settings-mcp-light.png"))
        XCTAssertTrue(audit.contains("settings-mcp-dark.png"))
        XCTAssertTrue(phase.contains("[x] `script/capture_ui_evidence.sh` は一時HOME、seed済みProject board、Light/Dark/System切替、window captureを使う。"))
        XCTAssertTrue(phase.contains("[x] `release_readiness_report.sh` は `ui-screenshots.md` だけでなく Project Board Light/Dark/System、Settings Overview Light/Dark、Settings Appearance Light/Dark、MCP Settings Light/Dark PNG の存在、サイズ、寸法を検証し、欠落や小さすぎる画像をblockerにする。"))
        XCTAssertTrue(phase.contains("[x] Light/Dark/System切替後にカード、サイドバー、インスペクタのコントラストが破綻しないことをスクリーンショットで確認する。"))
        XCTAssertTrue(phase.contains("[x] `ui-samples/` を参考にした画面密度・インスペクタ・Settingsの改善がスクリーンショットで検証されている。"))
    }

    func testUIScreenshotCaptureVerifiesTargetDestinationBeforeScreenshot() throws {
        let script = try readPackageFile("script/capture_ui_evidence.sh")
        let axMarkerScript = try readPackageFile("script/ui_evidence_ax_marker_check.swift")
        let visualBaselines = try readPackageFile("docs/quality/visual-baselines.md")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")

        XCTAssertTrue(script.contains("assert_project_board_destination_ready"))
        XCTAssertTrue(script.contains("wait_for_project_board_destination"))
        XCTAssertTrue(script.contains("SOLOPM_UI_EVIDENCE_TARGET_TIMEOUT_SECONDS"))
        XCTAssertTrue(script.contains("ui_evidence_ax_marker_check.swift"))
        XCTAssertTrue(script.contains("AX_MARKER_CHECKER="))
        XCTAssertTrue(script.contains("/usr/bin/swiftc \"$ROOT_DIR/script/ui_evidence_ax_marker_check.swift\" -o \"$AX_MARKER_CHECKER\""))
        XCTAssertTrue(script.contains("\"$AX_MARKER_CHECKER\" \"$APP_NAME\" \"$identifier\" \"$text\""))
        XCTAssertTrue(script.contains("kill -9 \"$checker_pid\""))
        XCTAssertFalse(script.contains("/usr/bin/swift \"$ROOT_DIR/script/ui_evidence_ax_marker_check.swift\""))
        XCTAssertFalse(script.contains("watchdog_pid"))
        XCTAssertTrue(script.contains("SOLOPM_UI_EVIDENCE_AX_MAX_NODES"))
        XCTAssertTrue(script.contains("AX marker scans use a bounded Swift AX traversal"))
        XCTAssertTrue(axMarkerScript.contains("AXUIElementCreateApplication"))
        XCTAssertTrue(axMarkerScript.contains("AXUIElementSetMessagingTimeout"))
        XCTAssertTrue(axMarkerScript.contains("SOLOPM_UI_EVIDENCE_AX_MAX_NODES"))
        XCTAssertTrue(axMarkerScript.contains(#""AXIdentifier""#))
        XCTAssertTrue(axMarkerScript.contains(#""AXVisibleChildren""#))
        XCTAssertTrue(axMarkerScript.contains(#""AXContents""#))
        XCTAssertTrue(axMarkerScript.contains("missing AX identifier marker"))
        XCTAssertTrue(script.contains("project-board-detail=>Launch Readiness"))
        XCTAssertTrue(script.contains("today-workflow=>Today"))
        XCTAssertTrue(script.contains("today-assistant-rail=>Today"))
        XCTAssertTrue(script.contains("schedule-workflow=>Schedule"))
        XCTAssertTrue(script.contains("SCHEDULE_COCKPIT_TARGET_MARKERS"))
        XCTAssertTrue(script.contains("done-workflow=>Done"))
        XCTAssertTrue(script.contains("VOICE_COMMAND_TARGET_MARKERS"))
        XCTAssertTrue(script.contains("voice-command-root=>Voice Command"))
        XCTAssertTrue(script.contains("capture_project_board_destination light \"$PROJECT_BOARD_SELECTION_OVERRIDE\" \"$LIGHT_SCREENSHOT\" \"Project Board\" \"$PROJECT_BOARD_TARGET_MARKERS\""))
        XCTAssertTrue(script.contains("capture_project_board_destination light today \"$TODAY_LIGHT_SCREENSHOT\" \"Today\" \"$TODAY_TARGET_MARKERS\""))
        XCTAssertTrue(script.contains("capture_project_board_destination light schedule \"$SCHEDULE_LIGHT_SCREENSHOT\" \"Schedule cockpit\" \"$SCHEDULE_COCKPIT_TARGET_MARKERS\""))
        XCTAssertTrue(script.contains("capture_project_board_destination light schedule \"$SCHEDULE_LIGHT_SCREENSHOT\" \"Schedule cockpit\" \"$SCHEDULE_TARGET_MARKERS\""))
        XCTAssertTrue(script.contains("capture_project_board_destination light done \"$DONE_LIGHT_SCREENSHOT\" \"Done analytics\" \"$DONE_TARGET_MARKERS\""))
        XCTAssertTrue(script.contains("--done-analytics"))
        XCTAssertTrue(script.contains("DONE_ANALYTICS_TARGET_MARKERS"))
        XCTAssertTrue(script.contains("SOLOPM_UI_EVIDENCE_RECOVERY_MODE=1"))
        XCTAssertTrue(script.contains("args+=(\"SOLOPM_LAUNCH_RECOVERY_MODE=1\")"))
        XCTAssertTrue(script.contains("write_done_analytics_evidence_file"))
        XCTAssertTrue(script.contains("docs/release/evidence/done-analytics-screenshots.md"))
        XCTAssertTrue(script.contains("inbox-action-panel=>Voice capture metadata available for Scheduled manual capture"))
        XCTAssertTrue(script.contains("capture_project_board_destination light inbox \"$INBOX_VOICE_LIGHT_SCREENSHOT\" \"Inbox voice detail\" \"$INBOX_VOICE_TARGET_MARKERS\" \"$INBOX_VOICE_TASK_OVERRIDE\""))
        XCTAssertTrue(script.contains("capture_voice_command_appearance light \"$VOICE_COMMAND_LIGHT_SCREENSHOT\""))
        let captureDestinationStart = try XCTUnwrap(script.range(of: "capture_project_board_destination()"))
        let captureDestinationEnd = try XCTUnwrap(script.range(
            of: "capture_voice_command_appearance()",
            range: captureDestinationStart.upperBound..<script.endIndex
        ))
        let captureDestinationSource = String(script[captureDestinationStart.lowerBound..<captureDestinationEnd.lowerBound])
        let destinationPosition = try XCTUnwrap(captureDestinationSource.range(of: "position_window_for_capture"))
        let destinationMarkerWait = try XCTUnwrap(captureDestinationSource.range(of: "wait_for_project_board_destination"))
        XCTAssertLessThan(destinationPosition.lowerBound, destinationMarkerWait.lowerBound)
        let windowMetadataStart = try XCTUnwrap(script.range(of: "wait_for_window_capture_metadata()"))
        let targetMarkerStart = try XCTUnwrap(script.range(
            of: "target_marker_present()",
            range: windowMetadataStart.upperBound..<script.endIndex
        ))
        let windowMetadataSource = String(script[windowMetadataStart.lowerBound..<targetMarkerStart.lowerBound])
        XCTAssertTrue(windowMetadataSource.contains("local deadline=$((SECONDS + TARGET_TIMEOUT_SECONDS))"))
        XCTAssertTrue(windowMetadataSource.contains("[[ \"$SECONDS\" -ge \"$deadline\" ]]"))
        XCTAssertFalse(windowMetadataSource.contains("for _ in {1..40}"))
        XCTAssertTrue(visualBaselines.contains("Capture target validation"))
        XCTAssertTrue(phase.contains("[x] `capture_ui_evidence.sh` は撮影前にAX identifierとseed固有テキストで対象画面を検証し、Today等の誤画面スクショをrelease evidenceとして保存しない。"))
    }

    func testUIScreenshotCaptureWaitsForPreviousSoloPMProcessBeforeRelaunching() throws {
        let script = try readPackageFile("script/capture_ui_evidence.sh")

        XCTAssertTrue(script.contains("PROJECT_BOARD_SELECTED_TASK_OVERRIDE=\"\""))
        XCTAssertTrue(script.contains("wait_for_app_process_exit"))
        XCTAssertTrue(script.contains("$APP_NAME did not terminate before next evidence capture."))
        XCTAssertTrue(script.contains("wait_for_app_process_exit"))
        XCTAssertTrue(script.contains("kill -0 \"$EVIDENCE_APP_PID\""))
        XCTAssertTrue(script.contains("$APP_NAME did not launch as expected pid $EVIDENCE_APP_PID."))
    }

    func testPhase12UIScreenshotEvidenceCoversNewCockpitScreens() throws {
        let script = try readPackageFile("script/capture_ui_evidence.sh")
        let releaseReport = try readPackageFile("script/release_readiness_report.sh")
        let evidence = try readPackageFile("docs/release/evidence/ui-screenshots.md")
        let appSource = try readAppShellSource()
        let workflowSource = try readProjectWorkflowSources()

        let requiredScreenshots = [
            "inbox-voice-light.png",
            "inbox-voice-dark.png",
            "projects-overview-light.png",
            "projects-overview-dark.png",
            "schedule-light.png",
            "schedule-dark.png",
            "done-light.png",
            "done-dark.png",
            "settings-integrations-light.png",
            "settings-integrations-dark.png"
        ]

        for screenshot in requiredScreenshots {
            XCTAssertTrue(script.contains(screenshot), "script missing \(screenshot)")
            XCTAssertTrue(releaseReport.contains(screenshot), "release report missing \(screenshot)")
            XCTAssertTrue(evidence.contains(screenshot), "evidence missing \(screenshot)")
        }

        XCTAssertTrue(script.contains("capture_project_board_destination light today \"$TODAY_LIGHT_SCREENSHOT\" \"Today\""))
        XCTAssertTrue(script.contains("capture_project_board_destination dark today \"$TODAY_DARK_SCREENSHOT\" \"Today\""))
        XCTAssertTrue(script.contains("capture_project_board_destination system today \"$TODAY_SYSTEM_SCREENSHOT\" \"Today\""))
        XCTAssertTrue(script.contains("capture_project_board_destination light schedule \"$SCHEDULE_LIGHT_SCREENSHOT\" \"Schedule cockpit\""))
        XCTAssertFalse(script.contains("capture_project_board_destination light schedule \"$TODAY_LIGHT_SCREENSHOT\""))
        XCTAssertTrue(script.contains("today=\"$(date +%Y-%m-%d)\""))
        XCTAssertTrue(script.contains("'Review VoiceOver focus path', 'in_progress', 'Confirm project board to task card to inspector path before public alpha.', '$today'"))
        XCTAssertTrue(script.contains("VALUES ('Inbox', 'active'"))
        XCTAssertTrue(script.contains("title = 'Inbox' ORDER BY id DESC LIMIT 1"))
        XCTAssertTrue(workflowSource.contains("ensureSelectedInboxTaskIsVisible"))

        XCTAssertTrue(script.contains("capture_project_board_destination"))
        XCTAssertTrue(script.contains("SOLOPM_OPEN_SETTINGS_ON_LAUNCH=1"))
        XCTAssertTrue(script.contains("SETTINGS_TAB_OVERRIDE=\"Overview\""))
        XCTAssertTrue(script.contains("SETTINGS_TAB_OVERRIDE=\"Appearance\""))
        XCTAssertTrue(script.contains("SETTINGS_TAB_OVERRIDE=\"MCP\""))
        XCTAssertTrue(appSource.contains("SOLOPM_OPEN_SETTINGS_ON_LAUNCH"))
        XCTAssertTrue(appSource.contains("SOLOPM_SETTINGS_EVIDENCE_TAB"))
        XCTAssertTrue(appSource.contains("settingsEvidenceWindow"))
        XCTAssertTrue(appSource.contains("openSettingsWindowForEvidenceIfRequested"))
        XCTAssertTrue(appSource.contains("SettingsView("))
        XCTAssertTrue(script.contains("assert_phase12_seed_data"))
        XCTAssertTrue(script.contains("Scheduled manual capture"))
        XCTAssertTrue(script.contains("Done analytics sample"))
        XCTAssertTrue(evidence.contains("Inbox voice detail"))
        XCTAssertTrue(evidence.contains("Projects overview"))
        XCTAssertTrue(evidence.contains("Schedule cockpit"))
        XCTAssertTrue(evidence.contains("Done analytics"))
        XCTAssertTrue(evidence.contains("Settings integrations"))
    }

    func testPhase12ClickPathAuditTracksNewWorkflowScreens() throws {
        let audit = try readPackageFile("docs/ux/click-path-audit.md")

        XCTAssertTrue(audit.contains("| Inbox voice detail | sidebar `Inbox` -> item row | 2 | Pass |"))
        XCTAssertTrue(audit.contains("| Projects overview確認 | sidebar `Projects` | 1 | Pass |"))
        XCTAssertTrue(audit.contains("| Schedule確認 | sidebar `Schedule` | 1 | Pass |"))
        XCTAssertTrue(audit.contains("| Done確認 | sidebar `Done` | 1 | Pass |"))
        XCTAssertTrue(audit.contains("| Settings integrations確認 | Settings -> Status Overview | 1 | Pass |"))
        XCTAssertTrue(audit.contains("Phase 12 screenshot evidence"))
        XCTAssertTrue(audit.contains("inbox-voice-light.png"))
        XCTAssertTrue(audit.contains("projects-overview-light.png"))
        XCTAssertTrue(audit.contains("schedule-light.png"))
        XCTAssertTrue(audit.contains("done-light.png"))
        XCTAssertTrue(audit.contains("settings-integrations-light.png"))
    }

    func testPhase12UICaptureScriptFailsWhenSeedDataIsMissing() throws {
        let script = try readPackageFile("script/capture_ui_evidence.sh")

        XCTAssertTrue(script.contains("assert_phase12_seed_data"))
        XCTAssertTrue(script.contains("missing Phase 12 UI evidence seed"))
        XCTAssertTrue(script.contains("SELECT COUNT(*) FROM tasks WHERE source_command = 'ui-evidence' AND title = 'Scheduled manual capture'"))
        XCTAssertTrue(script.contains("SELECT COUNT(*) FROM tasks WHERE source_command = 'ui-evidence' AND title = 'Done analytics sample'"))
        XCTAssertTrue(script.contains("SELECT COUNT(*) FROM projects WHERE source_command = 'ui-evidence' AND title = 'Completed Evidence Project'"))
        XCTAssertTrue(script.contains("SELECT COUNT(*) FROM projects WHERE source_command = 'ui-evidence' AND title = 'Inbox'"))
        XCTAssertTrue(script.contains("assert_phase12_seed_data \"$DATABASE_PATH\""))
    }

    func testPhase12UICaptureSeedUsesPersistedTaskStatusContract() throws {
        let script = try readPackageFile("script/capture_ui_evidence.sh")

        XCTAssertTrue(script.contains("assert_valid_seed_task_statuses"))
        XCTAssertTrue(script.contains("unsupported Phase 12 UI evidence task status"))
        XCTAssertTrue(script.contains("status NOT IN ('open', 'backlog', 'planned', 'in_progress', 'blocked', 'completed')"))
        XCTAssertTrue(script.contains("'Done analytics sample', 'completed'"))
        XCTAssertFalse(script.contains("'Done analytics sample', 'done'"))
        XCTAssertTrue(script.contains("assert_valid_seed_task_statuses \"$DATABASE_PATH\""))
    }

    func testUIScreenshotCaptureFailureExplainsScreenRecordingAndWindowDiagnostics() throws {
        let script = try readPackageFile("script/capture_ui_evidence.sh")
        let evidence = try readPackageFile("docs/release/evidence/ui-screenshots.md")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")

        XCTAssertTrue(script.contains("print_capture_failure_guidance"))
        XCTAssertTrue(script.contains("selected SoloPM window"))
        XCTAssertTrue(script.contains("System Settings > Privacy & Security > Screen Recording / Screen & System Audio Recording"))
        XCTAssertTrue(script.contains("Quit and reopen the terminal or Codex app after granting permission"))
        XCTAssertTrue(script.contains("SOLOPM_UI_EVIDENCE_KEEP_HOME=1"))
        XCTAssertTrue(script.contains("--doctor"))
        XCTAssertTrue(script.contains("run_doctor"))
        XCTAssertTrue(script.contains("screen capture preflight"))
        XCTAssertTrue(script.contains("does not write release evidence"))
        XCTAssertTrue(script.contains("[[ \"$DRY_RUN\" != \"1\" && \"$DOCTOR\" != \"1\" ]]"))
        XCTAssertTrue(evidence.contains("System Settings > Privacy & Security > Screen Recording / Screen & System Audio Recording"))
        XCTAssertTrue(evidence.contains("SOLOPM_UI_EVIDENCE_KEEP_HOME=1"))
        XCTAssertTrue(evidence.contains("script/capture_ui_evidence.sh --doctor"))
        XCTAssertTrue(phase.contains("[x] `capture_ui_evidence.sh` はScreen Recording権限やwindow capture失敗時に、選択window情報と再実行手順を出す。"))
        XCTAssertTrue(phase.contains("[x] `capture_ui_evidence.sh --doctor` はrelease evidenceを書かずにScreen Recordingの可視ピクセル取得を事前診断する。"))
    }

    func testLLMHTTPErrorMappingDoesNotDropMalformedErrorBodies() throws {
        let llmProviderSource = try readPackageFile("Sources/SoloPMCore/Planning/LLMProvider.swift")
        let responsesSource = try readPackageFile("Sources/SoloPMCore/Planning/OpenAIResponsesProvider.swift")
        let chatSource = try readPackageFile("Sources/SoloPMCore/Planning/ChatCompletionsCompatibleProvider.swift")
        let claudeSource = try readPackageFile("Sources/SoloPMCore/Planning/ClaudeMessagesProvider.swift")
        let geminiSource = try readPackageFile("Sources/SoloPMCore/Planning/GeminiDirectProvider.swift")
        let sttSource = try readPackageFile("Sources/SoloPMCore/Voice/STTProviders.swift")

        XCTAssertTrue(llmProviderSource.contains("LLMHTTPErrorMessageExtractor"))
        XCTAssertTrue(llmProviderSource.contains("Unexpected error body"))
        XCTAssertTrue(llmProviderSource.contains("DeveloperSecretRedactor().redact"))
        XCTAssertTrue(responsesSource.contains("LLMHTTPErrorMessageExtractor.message(from: data)"))
        XCTAssertTrue(chatSource.contains("LLMHTTPErrorMessageExtractor.message(from: data)"))
        XCTAssertTrue(claudeSource.contains("LLMHTTPErrorMessageExtractor.message(from: data)"))
        XCTAssertTrue(geminiSource.contains("LLMHTTPErrorMessageExtractor.message(from: data)"))
        XCTAssertTrue(llmProviderSource.contains("ProviderErrorMessageSanitizer"))
        XCTAssertTrue(responsesSource.contains("ProviderErrorMessageSanitizer.message(from: error)"))
        XCTAssertTrue(chatSource.contains("ProviderErrorMessageSanitizer.message(from: error)"))
        XCTAssertTrue(claudeSource.contains("ProviderErrorMessageSanitizer.message(from: error)"))
        XCTAssertTrue(geminiSource.contains("ProviderErrorMessageSanitizer.message(from: error)"))
        XCTAssertTrue(sttSource.contains("ProviderErrorMessageSanitizer.message(from: error)"))
        XCTAssertTrue(claudeSource.contains("Claude Messages HTTP"))
        XCTAssertTrue(geminiSource.contains("Gemini Direct HTTP"))
        XCTAssertFalse(responsesSource.contains("No error message."))
        XCTAssertFalse(chatSource.contains("No error message."))
        XCTAssertFalse(claudeSource.contains("No error message."))
        XCTAssertFalse(geminiSource.contains("No error message."))
        XCTAssertFalse(responsesSource.contains("LLMProviderError.network(error.localizedDescription)"))
        XCTAssertFalse(chatSource.contains("LLMProviderError.network(error.localizedDescription)"))
        XCTAssertFalse(claudeSource.contains("LLMProviderError.network(error.localizedDescription)"))
        XCTAssertFalse(geminiSource.contains("LLMProviderError.network(error.localizedDescription)"))
        XCTAssertFalse(sttSource.contains("STTProviderError.transcriptionFailed(error.localizedDescription)"))
    }

    func testProductBenchmarkDocumentsAdoptDeferRejectDecisions() throws {
        let benchmark = try readPackageFile("docs/product/competitor-benchmark.md")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")

        XCTAssertTrue(benchmark.contains("Verified: 2026-06-19"))
        XCTAssertTrue(benchmark.contains("Notion"))
        XCTAssertTrue(benchmark.contains("Todoist"))
        XCTAssertTrue(benchmark.contains("Linear"))
        XCTAssertTrue(benchmark.contains("Motion"))
        XCTAssertTrue(benchmark.contains("Adopt / Defer / Reject Backlog"))
        XCTAssertTrue(benchmark.contains("Custom database schema builder | Reject for MVP"))
        XCTAssertTrue(benchmark.contains("Calendar layout / auto-scheduling | Defer"))
        XCTAssertTrue(benchmark.contains("Project overview with tasks/artifacts/timeline/suggestions | Adopted"))
        XCTAssertTrue(benchmark.contains("Project expected artifact links | Adopted"))
        XCTAssertTrue(benchmark.contains("Menu bar Quick Add to Inbox | Adopted"))
        XCTAssertTrue(benchmark.contains("Phase 11 Fit Closure"))
        XCTAssertTrue(benchmark.contains("Notion-like flexible project context"))
        XCTAssertTrue(benchmark.contains("Linear-like execution speed"))
        XCTAssertTrue(benchmark.contains("Todoist-like immediate input"))
        XCTAssertTrue(benchmark.contains("AppExperienceSourceTests.testProjectDetailOrganizesTasksArtifactsTimelineAndSuggestions"))
        XCTAssertTrue(benchmark.contains("ProjectBoardStoreTests.testProjectBoardViewModelQuickCapturePersistsToSQLiteInbox"))
        XCTAssertTrue(benchmark.contains("VC-Grade Feature Fit"))
        XCTAssertTrue(benchmark.contains("Official Source Snapshot"))
        XCTAssertTrue(benchmark.contains("Release Candidate Hands-On Worksheet"))
        XCTAssertTrue(benchmark.contains("30-minute hands-on path"))
        XCTAssertTrue(benchmark.contains("Setup steps before first useful board"))
        XCTAssertTrue(benchmark.contains("Keystrokes/clicks to capture"))
        XCTAssertTrue(benchmark.contains("Repeated-operation speed"))
        XCTAssertTrue(benchmark.contains("Whether recommendations are understandable"))
        XCTAssertTrue(benchmark.contains("Explicit confirmation that no external SaaS sync or team workflow was added"))
        XCTAssertTrue(phase.contains("[x] 競合benchmarkから採用/非採用判断が残っている。"))
        XCTAssertTrue(phase.contains("[x] 完了条件: Notion的な柔軟さ、Linear的な速度、Todoist的な即時入力のうち、SoloPMに必要な部分だけが実装される。"))
        XCTAssertTrue(phase.contains("[x] 実操作2-4時間で見るべき競合別クリックパス、測定項目、SoloPM採用/非採用判断基準を `docs/product/competitor-benchmark.md` に記録する。"))
    }

    func testInvestorReviewTiesFeaturesToRetentionMonetizationAndRisk() throws {
        let review = try readPackageFile("docs/product/investor-review.md")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")

        XCTAssertTrue(review.contains("Problem"))
        XCTAssertTrue(review.contains("User pull"))
        XCTAssertTrue(review.contains("Retention hook"))
        XCTAssertTrue(review.contains("Monetization"))
        XCTAssertTrue(review.contains("Risk"))
        XCTAssertTrue(review.contains("Feature Admission Rules"))
        XCTAssertTrue(review.contains("Why it can grow"))
        XCTAssertTrue(review.contains("Why users may pay"))
        XCTAssertTrue(review.contains("Why it may fail"))
        XCTAssertTrue(review.contains("Visual quality"))
        XCTAssertTrue(review.contains("Accessibility"))
        XCTAssertTrue(review.contains("Paid value"))
        XCTAssertTrue(review.contains("UI screenshot evidence is now present and release-report validated"))
        XCTAssertTrue(review.contains("Remaining release blockers are VoiceOver manual pass, competitor hands-on validation, and signing/notarization/Sparkle/Gatekeeper evidence"))
        XCTAssertTrue(review.contains("Light/Dark/System screenshots are green for Project Board and Settings"))
        XCTAssertFalse(review.contains("Visual evidence, VoiceOver focus order, and full release packaging evidence remain open"))
        XCTAssertFalse(review.contains("Without screenshot evidence, UI quality is not fully proven"))
        XCTAssertTrue(phase.contains("[x] Investor reviewはUI screenshot証跡をpassed local evidenceとして扱い、VoiceOver、競合hands-on、署名/Notarization/Sparkle/Gatekeeperを残release blockerとして分離する。"))
    }

    func testPhase12ExitAuditPinsLocalCockpitScopeAndRemainingManualGates() throws {
        let audit = try readPackageFile("docs/ux/phase12-exit-audit.md")
        let phase = try readPackageFile("tasks/Phase12-ProductCockpitUXParity.md")
        let clickPath = try readPackageFile("docs/ux/click-path-audit.md")

        XCTAssertTrue(audit.contains("Phase 12 Exit Audit"))
        XCTAssertTrue(audit.contains("Status: passed for local/source/runtime-covered scope."))
        XCTAssertTrue(audit.contains("Status: passed for implemented / deferred / non-goal classification."))
        XCTAssertTrue(audit.contains("Status: passed for source/test-covered local scope."))
        XCTAssertTrue(audit.contains("Status: passed for implemented cockpit surfaces."))
        XCTAssertTrue(audit.contains("Status: passed for Phase 12 local cockpit scope."))

        for sample in 1...7 {
            XCTAssertTrue(audit.contains(String(format: "`ui-samples/%02d.png`", sample)))
        }

        for screen in ["Inbox", "Today", "Projects", "Project Detail", "Schedule", "Done", "Settings"] {
            XCTAssertTrue(audit.contains("| \(screen) |"), "Missing Phase 12 screen role: \(screen)")
            XCTAssertTrue(clickPath.contains(screen), "Click-path audit should cover \(screen)")
        }

        XCTAssertTrue(audit.contains("API keys and provider tokens stay behind Keychain-oriented settings flows"))
        XCTAssertTrue(audit.contains("Calendar writes are not direct"))
        XCTAssertTrue(audit.contains("MCP tools/call is gated by entitlement, tool policy, and explicit approval"))
        XCTAssertTrue(audit.contains("Sync fails closed for Free/local-only and missing backend paths before upload"))
        XCTAssertTrue(audit.contains("AI/LLM output is converted to Action Plan review/validation"))
        XCTAssertTrue(audit.contains("Manual VoiceOver pass"))
        XCTAssertTrue(audit.contains("Real 2-4 hour competitor hands-on evidence"))
        XCTAssertTrue(audit.contains("Developer ID signing, notarization, Gatekeeper, stapling, Sparkle appcast signature"))

        XCTAssertTrue(phase.contains("## Exit Gate"))
        XCTAssertFalse(audit.contains("Status: passed for release-machine scope."))
    }

    func testPhase14UXAccessFlowAuditMapsHardToReachPathsToFollowUps() throws {
        let clickPath = try readPackageFile("docs/ux/click-path-audit.md")

        XCTAssertTrue(clickPath.contains("## Phase 14 access-flow map (2026-07-03)"))
        XCTAssertTrue(clickPath.contains("| User goal | Access flow | Current reachability | Follow-up / PR |"))
        XCTAssertTrue(clickPath.contains("app launch -> sidebar `Schedule` -> `Generate Draft` -> `Queue Calendar Apply` -> Assistant Queue approval"))
        XCTAssertTrue(clickPath.contains("app launch -> sidebar `Done` -> completed task row -> `Follow Up` / `Reopen`"))
        XCTAssertTrue(clickPath.contains("app launch -> `Settings...` / `Command+,` -> `Sync` -> Google Calendar save flow -> `Save Calendar` -> `Check Readiness`"))
        XCTAssertTrue(clickPath.contains("app launch -> Voice Command -> record or type -> `Save to Inbox` / `Generate Plan` -> Inbox or Assistant Queue review"))
        XCTAssertTrue(clickPath.contains("developer/release -> `./script/build_and_run.sh --verify` -> Project Board visible-window proof"))

        for token in ["#208 / PR #218", "#209 / PR #217", "#210 / PR #215", "#211 / PR #216", "#212 / PR #214"] {
            XCTAssertTrue(clickPath.contains(token), "Missing Phase 14 child issue/PR mapping: \(token)")
        }

        XCTAssertTrue(clickPath.contains("## Phase 14 hard-to-access or unproven paths"))
        XCTAssertTrue(clickPath.contains("| Settings Google Calendar save/readiness |"))
        XCTAssertTrue(clickPath.contains("| Schedule apply after draft generation |"))
        XCTAssertTrue(clickPath.contains("| Done row recovery actions |"))
        XCTAssertTrue(clickPath.contains("| Voice Command first-run path |"))
        XCTAssertTrue(clickPath.contains("| Launch visible-window verifier |"))
    }

    func testRegressionRiskMapExistsAndCoversPrimaryScreens() throws {
        let riskMap = try readPackageFile("docs/quality/regression-risk-map.md")
        let phase = try readPackageFile("tasks/Phase14-QualityRegressionHardening.md")

        XCTAssertTrue(riskMap.contains("Regression Risk Map"))
        XCTAssertTrue(riskMap.contains("## Scope"))
        XCTAssertTrue(riskMap.contains("## Verification Layers"))
        XCTAssertTrue(riskMap.contains("## Coverage Status"))

        for screen in ["Project Board", "Inbox", "Today", "Settings", "Voice Command", "Menu Bar"] {
            XCTAssertTrue(
                riskMap.contains("| \(screen) |"),
                "Risk map should list \(screen) as a primary screen row"
            )
        }

        XCTAssertTrue(
            phase.contains("### Tests First"),
            "P14-001 is the regression inventory task; risk map test must reference Phase 14"
        )
        XCTAssertTrue(
            phase.contains("docs/quality/regression-risk-map.md"),
            "Phase 14 P14-001 should pin docs/quality/regression-risk-map.md as the canonical artifact"
        )
    }

    func testRegressionRiskMapDocumentsProjectBoardLayoutStability() throws {
        let riskMap = try readPackageFile("docs/quality/regression-risk-map.md")

        for region in ["header", "sidebar", "detail", "inspector"] {
            XCTAssertTrue(
                riskMap.contains(region),
                "Risk map must cover Project Board layout stability for \(region)"
            )
        }

        let invariants = [
            "Header action group is detail-right aligned",
            "Sidebar toggle mutates synchronously",
            "Toolbar display mode preserves primary action position",
            "Light / Dark / System switch does not collapse or overlap",
            "Window resize preserves fixed dimension bounds",
            "Layout correction avoids delayed animation"
        ]
        for invariant in invariants {
            XCTAssertTrue(
                riskMap.contains(invariant),
                "Risk map must record layout stability invariant: \(invariant)"
            )
        }

        XCTAssertTrue(
            riskMap.contains("project-board-header-bar"),
            "Risk map must reference the canonical AX identifier for header"
        )
        XCTAssertTrue(
            riskMap.contains("project-board-sidebar"),
            "Risk map must reference the canonical AX identifier for sidebar"
        )
        XCTAssertTrue(
            riskMap.contains("project-board-detail"),
            "Risk map must reference the canonical AX identifier for detail"
        )
        XCTAssertTrue(
            riskMap.contains("project-inspector"),
            "Risk map must reference the canonical AX identifier for inspector (project-inspector, not project-board-inspector)"
        )
        XCTAssertFalse(
            riskMap.contains("project-board-inspector"),
            "Risk map must not invent a project-board-inspector identifier that does not exist in ProjectBoardView.swift"
        )
    }

    func testRegressionRiskMapAlignsRisksToAllFiveVerificationLayers() throws {
        let riskMap = try readPackageFile("docs/quality/regression-risk-map.md")

        for layer in ["unit", "source", "runtime", "visual", "manual"] {
            XCTAssertTrue(
                riskMap.contains(layer),
                "Risk map must list verification layer: \(layer)"
            )
        }

        XCTAssertTrue(
            riskMap.contains("AppExperienceSourceTests"),
            "Risk map must point to AppExperienceSourceTests as the source-level owner"
        )
        XCTAssertTrue(
            riskMap.contains("ReleasePipelineTests"),
            "Risk map must point to ReleasePipelineTests for release pipeline source checks"
        )
        XCTAssertTrue(
            riskMap.contains("check_project_board_header_layout_smoke.sh"),
            "Risk map must point to header layout smoke for runtime AX verification"
        )
        XCTAssertTrue(
            riskMap.contains("check_runtime_accessible_crud_smoke.sh"),
            "Risk map must point to runtime CRUD smoke for click-path verification"
        )
        XCTAssertTrue(
            riskMap.contains("capture_ui_evidence.sh"),
            "Risk map must point to visual evidence capture for screenshot verification"
        )

        let manualOnlyMarkers = ["VoiceOver", "Gatekeeper", "manual-only"]
        for marker in manualOnlyMarkers {
            XCTAssertTrue(
                riskMap.contains(marker),
                "Risk map must classify manual-only gates explicitly: \(marker)"
            )
        }

        XCTAssertTrue(
            riskMap.contains("P14-002") || riskMap.contains("P14-003") || riskMap.contains("P14-005"),
            "Risk map must forward uncovered risks to follow-up P14 tasks"
        )
    }

    func testRegressionRiskMapDataRowsDeclareVerificationLayerOwnerAndCoverage() throws {
        let riskMap = try readPackageFile("docs/quality/regression-risk-map.md")
        let tables = try parseMarkdownTables(in: riskMap)

        XCTAssertFalse(tables.isEmpty, "Risk map must contain at least one markdown table")

        let verificationLayerHeaders = ["Verification layer", "Layer", "Verification Layer"]
        let ownerTestHeaders = ["Owner test / script", "代表コマンド / owner"]
        let coverageHeaders = ["Coverage"]
        let allowedLayerTokens: Set<String> = ["unit", "source", "runtime", "visual", "manual"]
        let allowedCoverageValues: Set<String> = ["automated", "partial", "manual-only", "open", "automated+", "partial+"]

        for (sectionTitle, header, rows) in tables {
            let normalizedHeader = header.map { $0.trimmingCharacters(in: .whitespaces) }

            guard let layerColumnIndex = normalizedHeader.firstIndex(where: { verificationLayerHeaders.contains($0) }),
                  let ownerColumnIndex = normalizedHeader.firstIndex(where: { ownerTestHeaders.contains($0) }) else {
                continue
            }

            XCTAssertFalse(
                rows.isEmpty,
                "Table under '\(sectionTitle)' must contain at least one data row"
            )

            for (rowIndex, row) in rows.enumerated() {
                let rowLabel = "section='\(sectionTitle)' row=\(rowIndex + 1)"
                XCTAssertGreaterThanOrEqual(
                    row.count,
                    max(layerColumnIndex, ownerColumnIndex) + 1,
                    "\(rowLabel) must have a cell for Verification layer and Owner test"
                )

                let layerCell = row[layerColumnIndex]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                XCTAssertFalse(
                    layerCell.isEmpty,
                    "\(rowLabel) Verification layer must not be empty"
                )

                let layerTokens = layerCell
                    .lowercased()
                    .components(separatedBy: CharacterSet(charactersIn: "+,/、& "))
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                for token in layerTokens {
                    XCTAssertTrue(
                        allowedLayerTokens.contains(token),
                        "\(rowLabel) Verification layer contains unknown token '\(token)': '\(layerCell)'"
                    )
                }

                let ownerCell = row[ownerColumnIndex]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                XCTAssertFalse(
                    ownerCell.isEmpty,
                    "\(rowLabel) Owner test / script must not be empty"
                )
                XCTAssertFalse(
                    ownerCell.contains("TBD") || ownerCell.contains("TODO"),
                    "\(rowLabel) Owner test / script must not be a placeholder: '\(ownerCell)'"
                )
            }

            if let coverageColumnIndex = normalizedHeader.firstIndex(where: { coverageHeaders.contains($0) }) {
                for (rowIndex, row) in rows.enumerated() {
                    let rowLabel = "section='\(sectionTitle)' row=\(rowIndex + 1)"
                    XCTAssertGreaterThanOrEqual(
                        row.count,
                        coverageColumnIndex + 1,
                        "\(rowLabel) must have a Coverage cell"
                    )
                    let coverageCell = row[coverageColumnIndex]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    XCTAssertFalse(
                        coverageCell.isEmpty,
                        "\(rowLabel) Coverage must not be empty"
                    )
                    XCTAssertTrue(
                        allowedCoverageValues.contains(coverageCell),
                        "\(rowLabel) Coverage '\(coverageCell)' is not one of the allowed values"
                    )
                }
            }
        }
    }

    func testRegressionRiskMapReferencesBuiltVisualRegressionSmokeScript() throws {
        let root = packageRoot().appendingPathComponent("script")
        let visualScriptURL = root.appendingPathComponent("check_visual_regression_smoke.sh")
        let fileExists = FileManager.default.fileExists(atPath: visualScriptURL.path)

        XCTAssertTrue(
            fileExists,
            "check_visual_regression_smoke.sh must exist before the visual verification layer can pin it"
        )

        let riskMap = try readPackageFile("docs/quality/regression-risk-map.md")
        let visualRow = riskMap
            .components(separatedBy: "\n")
            .first(where: { $0.hasPrefix("| visual   |") || $0.hasPrefix("| visual |") })

        XCTAssertNotNil(visualRow, "Risk map must keep a visual layer row")
        XCTAssertTrue(
            visualRow?.contains("check_visual_regression_smoke.sh") ?? false,
            "Visual layer representative command must list check_visual_regression_smoke.sh once P14-004 is implemented"
        )

        XCTAssertFalse(
            riskMap.contains("リポジトリには未存在"),
            "Risk map must not keep the old unbuilt-script wording after P14-004"
        )
    }

    func testRegressionRiskMapUsesExistingInspectorAccessibilityIdentifier() throws {
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let riskMap = try readPackageFile("docs/quality/regression-risk-map.md")

        XCTAssertTrue(
            boardSource.contains(".accessibilityIdentifier(\"project-inspector\")"),
            "ProjectBoardView.swift must define project-inspector as the inspector identifier"
        )
        XCTAssertFalse(
            boardSource.contains("project-board-inspector"),
            "ProjectBoardView.swift must not invent project-board-inspector"
        )
        XCTAssertTrue(
            riskMap.contains("project-inspector"),
            "Risk map must point to the existing project-inspector identifier for the inspector region"
        )
        XCTAssertFalse(
            riskMap.contains("project-board-inspector"),
            "Risk map must not reference the non-existent project-board-inspector identifier"
        )
    }

    private func parseMarkdownTables(in source: String) throws -> [(section: String, header: [String], rows: [[String]])] {
        let lines = source.components(separatedBy: "\n")
        var tables: [(String, [String], [[String]])] = []
        var currentSection = "preamble"
        var index = 0

        while index < lines.count {
            let line = lines[index]

            if line.hasPrefix("#") {
                currentSection = String(line.drop(while: { $0 == "#" }))
                    .trimmingCharacters(in: .whitespaces)
                index += 1
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.contains("|") {
                var tableLines: [String] = [trimmed]
                var cursor = index + 1
                while cursor < lines.count {
                    let next = lines[cursor].trimmingCharacters(in: .whitespaces)
                    if next.hasPrefix("|") && next.hasSuffix("|") && next.contains("|") {
                        tableLines.append(next)
                        cursor += 1
                    } else {
                        break
                    }
                }

                if tableLines.count >= 3 {
                    let header = splitTableRow(tableLines[0])
                    let separator = splitTableRow(tableLines[1])
                    let isSeparator = separator.allSatisfy { cell in
                        let trimmedCell = cell.trimmingCharacters(in: .whitespaces)
                        if trimmedCell.isEmpty { return true }
                        let core = trimmedCell.trimmingCharacters(in: CharacterSet(charactersIn: "-:"))
                        return !core.isEmpty
                    }
                    if isSeparator {
                        let dataRows = tableLines[2...]
                            .map(splitTableRow)
                            .filter { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
                        tables.append((currentSection, header, dataRows))
                        index = cursor
                        continue
                    }
                }
            }

            index += 1
        }

        return tables
    }

    private func splitTableRow(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|"), trimmed.hasSuffix("|") else {
            return []
        }
        let inner = String(trimmed.dropFirst().dropLast())
        return inner
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func readPackageFile(_ relativePath: String) throws -> String {
        let url = packageRoot().appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func readAppShellSource() throws -> String {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
        let viewSources = try [
            "Sources/SoloPMApp/Views/ProjectBoardLaunchRecoveryViews.swift",
            "Sources/SoloPMApp/Views/MenuBarPanel.swift",
            "Sources/SoloPMApp/Views/VoiceCaptureView.swift",
            "Sources/SoloPMApp/Views/ActionReviewPanel.swift",
            "Sources/SoloPMApp/Views/SettingsView.swift"
        ].map(readPackageFile).joined(separator: "\n\n")
        let runtimeCompositionSources = try [
            "Sources/SoloPMApp/Composition/AppRuntimeFactory.swift",
            "Sources/SoloPMApp/Composition/ProjectBoardRuntimeFactory.swift",
            "Sources/SoloPMApp/Composition/RuntimeToolCompositionFactory.swift",
            "Sources/SoloPMApp/Composition/SettingsRuntimeFactory.swift",
            "Sources/SoloPMApp/Composition/GoogleCalendarRuntimeCompositionFactory.swift",
            "Sources/SoloPMApp/Composition/VoiceRuntimeFactory.swift",
            "Sources/SoloPMApp/Composition/MenuBarRuntimeFactory.swift"
        ].map(readPackageFile).joined(separator: "\n\n")

        return [
            appSource,
            viewSources,
            runtimeCompositionSources
        ].joined(separator: "\n\n")
    }

    private func sourceBlock(in source: String, from startNeedle: String, to endNeedle: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: startNeedle))
        let end = try XCTUnwrap(source.range(of: endNeedle, range: start.upperBound..<source.endIndex))
        return String(source[start.lowerBound..<end.upperBound])
    }

    private func relativePackagePath(for url: URL) -> String {
        let packageRootPath = packageRoot().standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        guard filePath.hasPrefix(packageRootPath + "/") else {
            return filePath
        }
        return String(filePath.dropFirst(packageRootPath.count + 1))
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

    private func localizableKeys(in relativePath: String) throws -> Set<String> {
        let source = try readPackageFile(relativePath)
        let pattern = #""((?:[^"\\]|\\.)*)"\s*="#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(source.startIndex..<source.endIndex, in: source)

        return Set(regex.matches(in: source, range: range).compactMap { match in
            guard let keyRange = Range(match.range(at: 1), in: source) else {
                return nil
            }
            return String(source[keyRange])
        })
    }

    private func readProjectWorkflowSources() throws -> String {
        try [
            "Sources/SoloPMApp/Views/ProjectWorkflowViews.swift",
            "Sources/SoloPMApp/Views/ProjectWorkflowSharedViews.swift",
            "Sources/SoloPMApp/Views/ProjectWorkflowTodayView.swift",
            "Sources/SoloPMApp/Views/ProjectWorkflowCatchUpView.swift",
            "Sources/SoloPMApp/Views/ProjectWorkflowScheduleView.swift",
            "Sources/SoloPMApp/Views/ProjectWorkflowDoneView.swift",
            "Sources/SoloPMApp/Views/ProjectWorkflowInboxView.swift",
            "Sources/SoloPMApp/Views/ProjectWorkflowAssistantQueueView.swift"
        ]
        .map { try readPackageFile($0) }
        .joined(separator: "\n")
    }

    private func staticSwiftUILiteralKeys() throws -> Set<String> {
        let patterns = [
            #"\bText\("((?:[^"\\]|\\.)*)"\)"#,
            #"\bLabel\("((?:[^"\\]|\\.)*)""#,
            #"\bButton\("((?:[^"\\]|\\.)*)""#,
            #"\bPicker\("((?:[^"\\]|\\.)*)""#,
            #"\bToggle\("((?:[^"\\]|\\.)*)""#,
            #"\bMenu\("((?:[^"\\]|\\.)*)""#,
            #"\bSection\("((?:[^"\\]|\\.)*)""#,
            #"\bGroupBox\("((?:[^"\\]|\\.)*)""#,
            #"\.navigationTitle\("((?:[^"\\]|\\.)*)"\)"#,
            #"\.help\("((?:[^"\\]|\\.)*)"\)"#,
            #"\.accessibilityLabel\("((?:[^"\\]|\\.)*)"\)"#,
            #"\.accessibilityHint\("((?:[^"\\]|\\.)*)"\)"#,
            #"\bTextField\("((?:[^"\\]|\\.)*)""#,
            #"\bSecureField\("((?:[^"\\]|\\.)*)""#
        ]
        let regexes = try patterns.map { pattern in
            try NSRegularExpression(pattern: pattern)
        }
        var keys: Set<String> = []

        for fileURL in try allSwiftFiles(under: "Sources/SoloPMApp") {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let range = NSRange(source.startIndex..<source.endIndex, in: source)

            for regex in regexes {
                for match in regex.matches(in: source, range: range) {
                    guard let keyRange = Range(match.range(at: 1), in: source) else {
                        continue
                    }
                    let key = String(source[keyRange])
                    guard isLocalizableStaticUILiteral(key) else {
                        continue
                    }
                    keys.insert(key)
                }
            }
        }

        return keys
    }

    private func isLocalizableStaticUILiteral(_ key: String) -> Bool {
        guard !key.isEmpty, !key.contains(#"\("#) else {
            return false
        }

        let nonLocalizedPrefixes = [
            "settings-",
            "project-",
            "inline-",
            "embedded-",
            "task-"
        ]
        return !nonLocalizedPrefixes.contains { key.hasPrefix($0) }
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }
}
