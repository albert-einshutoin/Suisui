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
        let coreSource = try readPackageFile("Sources/SoloPMCore/App/ProjectBoard.swift")

        XCTAssertTrue(source.contains("NavigationSplitView"))
        XCTAssertTrue(source.contains("BoardColumnView"))
        XCTAssertTrue(source.contains("InlineTaskComposer"))
        XCTAssertTrue(source.contains("TaskInspectorView"))
        XCTAssertTrue(source.contains("Archive Project"))
        XCTAssertTrue(source.contains("Show Archived"))
        XCTAssertTrue(source.contains("Restore Project"))
        XCTAssertTrue(source.contains("InspectorDestructiveConfirmation"))
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
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")

        XCTAssertTrue(appSource.contains("makeProjectBoardViewModel()"))
        XCTAssertFalse(appSource.contains("makeProjectBoardSnapshot()"))
        XCTAssertTrue(boardSource.contains("@StateObject private var viewModel: ProjectBoardViewModel"))
        XCTAssertTrue(boardSource.contains("createTask("))
    }

    func testProjectBoardExposesPortableTaskImportExportFileActions() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
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
        let workflowSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectWorkflowViews.swift")

        XCTAssertTrue(workflowSource.contains("case projects"))
        XCTAssertTrue(workflowSource.contains("case .projects:"))
        XCTAssertTrue(workflowSource.contains("return \"projects\""))
        XCTAssertTrue(boardSource.contains("destination: .projects"))
        XCTAssertTrue(boardSource.contains(".tag(ProjectBoardSidebarDestination.projects)"))
        XCTAssertTrue(boardSource.contains("ProjectsPortfolioOverview("))
        XCTAssertTrue(boardSource.contains(".tag(ProjectBoardSidebarDestination.project(project.id))"))
        XCTAssertTrue(boardSource.contains("case .project(let projectID):"))
        XCTAssertTrue(boardSource.contains("ProjectBoardDetail("))
        XCTAssertTrue(boardSource.contains("case .overview:"))
        XCTAssertTrue(boardSource.contains("case .board:"))
        XCTAssertTrue(boardSource.contains("case .list:"))
    }

    func testAppearanceSelectionIsConfiguredOnlyFromSettings() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
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
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
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
        let workflowSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectWorkflowViews.swift")
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
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

    func testProjectBoardToolbarHostsSettingsLinkWithoutThemeControls() throws {
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let sidebarStart = try XCTUnwrap(boardSource.range(of: "NavigationSplitView {"))
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

        let toolbarStart = try XCTUnwrap(boardSource.range(of: ".toolbar {"))
        let inspectorStart = try XCTUnwrap(boardSource.range(of: ".inspector(isPresented: inspectorBinding)"))
        let toolbarSource = String(boardSource[toolbarStart.lowerBound..<inspectorStart.lowerBound])

        XCTAssertTrue(toolbarSource.contains("SettingsLink"))
        XCTAssertTrue(toolbarSource.contains("Label(\"Settings\", systemImage: \"gearshape\")"))
        XCTAssertTrue(toolbarSource.contains(".help(\"Open Settings\")"))
        XCTAssertTrue(toolbarSource.contains(".accessibilityIdentifier(\"project-board-settings-link\")"))
        XCTAssertFalse(toolbarSource.contains(".keyboardShortcut(\",\", modifiers: [.command])"))
        XCTAssertFalse(toolbarSource.contains("Theme"))
        XCTAssertFalse(toolbarSource.contains("Appearance"))
        XCTAssertFalse(toolbarSource.contains("SoloPMAppearancePreference"))
        XCTAssertFalse(toolbarSource.contains("Picker(\"Theme\""))
        XCTAssertFalse(toolbarSource.contains("Picker(\"Appearance\""))
        XCTAssertFalse(toolbarSource.contains("Light"))
        XCTAssertFalse(toolbarSource.contains("Dark"))
        XCTAssertFalse(toolbarSource.contains("System"))
        XCTAssertFalse(toolbarSource.contains("sun.max"))
        XCTAssertFalse(toolbarSource.contains("moon"))
        XCTAssertFalse(toolbarSource.contains("circle.lefthalf.filled"))
        XCTAssertFalse(toolbarSource.contains("settings-theme-picker"))
        XCTAssertFalse(toolbarSource.contains("appearancePreference"))
        XCTAssertFalse(toolbarSource.contains(".pickerStyle(.segmented)"))
    }

    func testMenuBarPanelHostsSettingsLinkWithoutThemeControls() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
        let panelStart = try XCTUnwrap(appSource.range(of: "private struct MenuBarPanel"))
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

        XCTAssertTrue(boardSource.contains(".draggable(String(task.id))"))
        XCTAssertTrue(boardSource.contains(".dropDestination(for: String.self)"))
        XCTAssertTrue(boardSource.contains("onMoveDroppedTasks(rawIDs, column.status)"))
        XCTAssertTrue(boardSource.contains(".contentShape(Rectangle())"))
        XCTAssertFalse(boardSource.contains("ProjectTaskDragPayload"))
        XCTAssertTrue(coreSource.contains("moveDroppedTasks(ids taskIDs: [Int64], to status: ProjectTaskStatus)"))
        XCTAssertTrue(coreSource.contains("moveDroppedTasks(ids rawIDs: [String], to status: ProjectTaskStatus)"))
        XCTAssertTrue(coreSource.contains("func moveTasks(ids: [Int64], to status: ProjectTaskStatus) throws -> [ProjectBoardTask]"))
        XCTAssertTrue(coreSource.contains("store.moveTasks(ids: taskIDs, to: status)"))
        XCTAssertTrue(coreSource.contains("Could not move task: invalid drag payload."))
    }

    func testDoneWorkflowIsReachableFromSidebarAndExposesReviewActions() throws {
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let workflowSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectWorkflowViews.swift")
        let coreSource = try readPackageFile("Sources/SoloPMCore/App/ProjectBoard.swift")

        XCTAssertTrue(workflowSource.contains("case done"))
        XCTAssertTrue(boardSource.contains("ProjectBoardSidebarDestinationRow(destination: .done"))
        XCTAssertTrue(boardSource.contains("DoneWorkflowView(viewModel: viewModel)"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"done-workflow\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"done-reopen-task-\\(task.id)\")"))
        XCTAssertTrue(coreSource.contains("public func doneAnalytics("))
        XCTAssertTrue(coreSource.contains("public func reopenCompletedTask(id: Int64)"))
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
        XCTAssertTrue(appearanceSource.contains("static let environmentOverrideKey = \"SOLOPM_APPEARANCE_PREFERENCE\""))
        XCTAssertTrue(appearanceSource.contains("static var environmentOverride: SoloPMAppearancePreference?"))
        XCTAssertTrue(appearanceSource.contains("var colorScheme: ColorScheme?"))
        XCTAssertTrue(appSource.contains("@AppStorage(SoloPMAppearancePreference.storageKey)"))
        XCTAssertEqual(appSource.components(separatedBy: "@AppStorage(SoloPMAppearancePreference.storageKey)").count - 1, 1)
        XCTAssertTrue(appSource.contains("private var effectiveAppearancePreference: SoloPMAppearancePreference"))
        XCTAssertTrue(appSource.contains("SoloPMAppearancePreference.environmentOverride ?? appearancePreference"))
        XCTAssertTrue(appSource.contains(".preferredColorScheme(effectiveAppearancePreference.colorScheme)"))
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
        XCTAssertTrue(source.contains(".frame(minWidth: 64, maxWidth: .infinity, minHeight: 24, alignment: .leading)"))
        XCTAssertTrue(phase.contains("[x] `ui-samples/01.png`、`03.png`、`04.png` を基準に、左サイドバー、中央ボード/リスト、右インスペクタの情報密度を見直す。"))
        XCTAssertTrue(phase.contains("[x] Task card metadata strip はstatus / priority / dueを固定寸法chipに分離し、狭いKanban列ではadaptive gridへ逃がす。"))
        XCTAssertTrue(audit.contains("Task card metadata strip"))
        XCTAssertTrue(audit.contains("status / priority / dueを固定寸法chip"))
    }

    func testProjectBoardExposesPrimaryCRUDKeyboardShortcuts() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

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
        XCTAssertTrue(boardSource.contains("EmbeddedTerminalPanel("))
        XCTAssertTrue(boardSource.contains("workingDirectory: terminalWorkingDirectory"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"project-board-terminal-toggle\")"))
        XCTAssertTrue(boardSource.contains(".keyboardShortcut(\"`\", modifiers: [.control])"))
        XCTAssertTrue(terminalSource.contains("struct EmbeddedTerminalPanel"))
        XCTAssertTrue(terminalSource.contains("@State private var isExecutionApproved = false"))
        XCTAssertTrue(terminalSource.contains("if isExecutionApproved {"))
        XCTAssertTrue(terminalSource.contains("LocalShellTerminalRepresentable("))
        XCTAssertTrue(terminalSource.contains("Button { isExecutionApproved = true }"))
        XCTAssertTrue(terminalSource.contains(".accessibilityIdentifier(\"embedded-terminal-approve\")"))
        XCTAssertTrue(terminalSource.contains(".accessibilityIdentifier(\"embedded-terminal-view\")"))
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
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"\\(accessibilityIdentifier)-confirm\")"))
        XCTAssertTrue(source.contains(".accessibilityLabel(confirmTitle)"))
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

    func testPhase12SidebarDestinationRawValuesStayBackwardCompatible() throws {
        let workflowSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectWorkflowViews.swift")

        XCTAssertTrue(workflowSource.contains("static let defaultRawValue = \"today\""))
        XCTAssertTrue(workflowSource.contains("case .inbox:\n            return \"inbox\""))
        XCTAssertTrue(workflowSource.contains("case .today:\n            return \"today\""))
        XCTAssertTrue(workflowSource.contains("case .projects:\n            return \"projects\""))
        XCTAssertTrue(workflowSource.contains("case .schedule:\n            return \"schedule\""))
        XCTAssertTrue(workflowSource.contains("case .done:\n            return \"done\""))
        XCTAssertTrue(workflowSource.contains("case .project(let projectID):\n            return \"project:\\(projectID)\""))
        XCTAssertTrue(workflowSource.contains("case \"inbox\":\n            return .inbox"))
        XCTAssertTrue(workflowSource.contains("case \"today\":\n            return .today"))
        XCTAssertTrue(workflowSource.contains("case \"projects\":\n            return .projects"))
        XCTAssertTrue(workflowSource.contains("case \"schedule\":\n            return .schedule"))
        XCTAssertTrue(workflowSource.contains("case \"done\":\n            return .done"))
        XCTAssertTrue(workflowSource.contains("guard parts.count == 2 else {\n                return .today"))
        XCTAssertTrue(workflowSource.contains("availableProjects.contains(where: { $0.id == projectID }) else {\n                    return .today"))
    }

    func testPhase12SidebarShowsWorkflowDestinationsBeforeProjectRows() throws {
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")

        let inboxRow = try XCTUnwrap(boardSource.range(of: "ProjectBoardSidebarDestinationRow(destination: .inbox"))
        let todayRow = try XCTUnwrap(boardSource.range(of: "ProjectBoardSidebarDestinationRow(destination: .today"))
        let scheduleRow = try XCTUnwrap(boardSource.range(of: "ProjectBoardSidebarDestinationRow(destination: .schedule"))
        let doneRow = try XCTUnwrap(boardSource.range(of: "ProjectBoardSidebarDestinationRow(destination: .done"))
        let projectsSection = try XCTUnwrap(boardSource.range(of: "Section(\"Projects\")"))

        XCTAssertLessThan(inboxRow.lowerBound, projectsSection.lowerBound)
        XCTAssertLessThan(todayRow.lowerBound, projectsSection.lowerBound)
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
        let workflowSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectWorkflowViews.swift")

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
        let workflowSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectWorkflowViews.swift")
        let coreSource = try readPackageFile("Sources/SoloPMCore/App/ProjectBoard.swift")

        XCTAssertTrue(coreSource.contains("public struct InboxClassificationFeedback"))
        XCTAssertTrue(coreSource.contains("@Published public private(set) var inboxClassificationFeedback"))
        XCTAssertTrue(coreSource.contains("public func undoLastInboxClassification()"))
        XCTAssertTrue(workflowSource.contains("if let feedback = viewModel.inboxClassificationFeedback"))
        XCTAssertTrue(workflowSource.contains("Label(feedback.message, systemImage: feedback.systemImage)"))
        XCTAssertTrue(workflowSource.contains("viewModel.undoLastInboxClassification()"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-classification-feedback\")"))
    }

    func testInboxWorkflowSurfacesVoiceCaptureMetadataWithoutReplacingVoiceCommand() throws {
        let workflowSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectWorkflowViews.swift")
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
        let coreSource = try readPackageFile("Sources/SoloPMCore/App/ProjectBoard.swift")

        XCTAssertTrue(coreSource.contains("public var selectedInboxCaptureRecords"))
        XCTAssertTrue(coreSource.contains("public enum InboxTriageFilter"))
        XCTAssertTrue(coreSource.contains("public var filteredInboxTasks"))
        XCTAssertTrue(coreSource.contains("public func setInboxTriageFilter"))
        XCTAssertTrue(workflowSource.contains("viewModel.filteredInboxTasks"))
        XCTAssertTrue(workflowSource.contains("InboxHeaderControls("))
        XCTAssertTrue(workflowSource.contains("Picker(\"Inbox Filter\""))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-triage-filter\")"))
        XCTAssertTrue(workflowSource.contains("InboxCaptureMetadataPanel("))
        XCTAssertTrue(workflowSource.contains("viewModel.selectedInboxCaptureRecords"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-capture-metadata\")"))
        XCTAssertTrue(workflowSource.contains("capture.durationLabel"))
        XCTAssertTrue(workflowSource.contains("capture.transcript"))
        XCTAssertTrue(workflowSource.contains("capture.classificationStatus.rawValue"))
        XCTAssertTrue(appSource.contains("inboxCaptureStore: SQLiteInboxCaptureStore(connection: connection)"))
        XCTAssertTrue(appSource.contains("Window(\"Voice Command\", id: \"voice-capture\")"))
    }

    func testInboxAndTodayWorkflowsExposeKeyboardAndVoiceOverAnchors() throws {
        let workflowSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectWorkflowViews.swift")
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

        XCTAssertTrue(audit.contains("Inbox / Todayのrow完了toggle"))
        XCTAssertTrue(audit.contains("Inbox / Todayのrow、Quick Add、分類action、Today summary、time blockにsource-level accessibility identifiers / hints / keyboard anchorsを追加済み"))
        XCTAssertTrue(phase.contains("[x] Inbox / Today workflowのrow完了toggleを追加し、選択済みinspectorを開かずにlocal SQLite task statusをDoneへ移せる。"))
        XCTAssertTrue(phase.contains("[x] Inbox / Today workflowのrow、Quick Add、分類action、Today summary、time blockにsource-level accessibility identifiers / hints / keyboard anchorsを付ける。"))
    }

    func testProjectDetailOrganizesTasksArtifactsTimelineAndSuggestions() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let coreSource = try readPackageFile("Sources/SoloPMCore/App/ProjectBoard.swift")

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
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-artifact-path\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-artifact-track\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-artifact-remove-\\(artifact.id)\")"))
        XCTAssertTrue(source.contains("ProjectTimelineSection"))
        XCTAssertTrue(source.contains("ProjectLocalSuggestionPanel"))
        XCTAssertTrue(source.contains("project.artifacts"))
        XCTAssertTrue(coreSource.contains("public struct ProjectBoardArtifact"))
        XCTAssertTrue(coreSource.contains("public var artifacts: [ProjectBoardArtifact]"))
        XCTAssertTrue(coreSource.contains("func createProjectArtifact(projectID: Int64, expectedPath: String) throws -> ProjectBoardArtifact"))
        XCTAssertTrue(coreSource.contains("func deleteProjectArtifact(id: Int64) throws"))
        XCTAssertTrue(coreSource.contains("SQLiteArtifactStore(connection: connection)"))
    }

    func testProjectDetailSurfacesMilestonesTimelineAndAssistantWithoutDroppingExistingSections() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let coreSource = try readPackageFile("Sources/SoloPMCore/App/ProjectBoard.swift")

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

        XCTAssertTrue(coreSource.contains("public struct ProjectBoardMilestone"))
        XCTAssertTrue(coreSource.contains("public var milestones: [ProjectBoardMilestone]"))
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
        let workflowSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectWorkflowViews.swift")
        let audit = try readPackageFile("docs/ux/click-path-audit.md")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")

        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"project-board-sidebar\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityLabel(\"Project navigation\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityHint(\"Select Inbox, Today, or a project before moving to the board detail.\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"sidebar-destination-\\(destination.accessibilityIdentifierSuffix)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityLabel(destination.accessibilityLabel(count: count))"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"project-sidebar-row-\\(project.id)\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityLabel(project.accessibilitySidebarLabel)"))

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
        let workflowSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectWorkflowViews.swift")
        let coreSource = try readPackageFile("Sources/SoloPMCore/App/ProjectBoard.swift")

        XCTAssertTrue(workflowSource.contains("TodayCommandPanel"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-command-title\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-command-add\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-suggestion-chip-"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-start-focus\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-schedule-draft-button\")"))
        XCTAssertTrue(workflowSource.contains("TodayPlanSummary"))
        XCTAssertTrue(workflowSource.contains("TodayTimeBlockList"))
        XCTAssertTrue(workflowSource.contains("plan.overdueCount"))
        XCTAssertTrue(workflowSource.contains("plan.dueTodayCount"))
        XCTAssertTrue(workflowSource.contains("plan.recommendationReason"))
        XCTAssertTrue(workflowSource.contains("ForEach(plan.timeBlocks)"))
        XCTAssertTrue(coreSource.contains("public struct TodayWorkflowPlan"))
        XCTAssertTrue(coreSource.contains("public struct TodayTimeBlock"))
        XCTAssertTrue(coreSource.contains("public struct TodayRecommendationChip"))
        XCTAssertTrue(coreSource.contains("public struct TodayScheduleDraft"))
        XCTAssertTrue(coreSource.contains("public func submitTodayCommand"))
        XCTAssertTrue(coreSource.contains("public func todayRecommendationChips"))
        XCTAssertTrue(coreSource.contains("public func startFocus"))
        XCTAssertTrue(coreSource.contains("public func prepareTodayScheduleDraft"))
        XCTAssertTrue(coreSource.contains("public func todayPlan("))
    }

    func testScheduleWorkflowIsReachableAndApprovalFirst() throws {
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let workflowSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectWorkflowViews.swift")
        let coreSource = try readPackageFile("Sources/SoloPMCore/App/ProjectBoard.swift")

        XCTAssertTrue(boardSource.contains("ProjectBoardSidebarDestinationRow(destination: .schedule"))
        XCTAssertTrue(boardSource.contains("case .schedule:"))
        XCTAssertTrue(boardSource.contains("ScheduleWorkflowView(viewModel: viewModel)"))
        XCTAssertTrue(workflowSource.contains("case schedule"))
        XCTAssertTrue(workflowSource.contains("ScheduleWorkflowView"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-workflow\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-generate-draft\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-apply-calendar\")"))
        XCTAssertTrue(coreSource.contains("public struct ScheduleDraft"))
        XCTAssertTrue(coreSource.contains("public func unscheduledScheduleTasks"))
        XCTAssertTrue(coreSource.contains("public func prepareScheduleDraft"))
        XCTAssertTrue(coreSource.contains("public func applyScheduleDraftToCalendar"))
        XCTAssertTrue(coreSource.contains("approvalToken"))
        XCTAssertFalse(coreSource.contains("return .applied(eventCount: 0)"))
    }

    func testAppAndCLIShareDefaultDatabaseLocation() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
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
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

        XCTAssertTrue(appSource.contains("@StateObject private var menuBarController: MenuBarSummaryController"))
        XCTAssertTrue(appSource.contains("MenuBarPanel(controller: menuBarController, quickCaptureViewModel: menuBarQuickCaptureViewModel)"))
        XCTAssertTrue(appSource.contains("makeMenuBarSummaryController()"))
        XCTAssertTrue(appSource.contains(".onReceive(NotificationCenter.default.publisher(for: .soloPMProjectBoardDidChange))"))
        XCTAssertTrue(appSource.contains("controller.emptyStateLabel"))
        XCTAssertFalse(appSource.contains("private let menuBarViewModel = AppRuntimeFactory.makeMenuBarSummaryViewModel()"))
        XCTAssertFalse(appSource.contains("StaticMenuBarSummaryProvider(summary: .empty)"))
        XCTAssertTrue(appSource.contains("UnavailableMenuBarSummaryProvider(error: error)"))
    }

    func testMenuBarPanelProvidesFastInboxCaptureWithRuntimeBoardViewModel() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")
        let audit = try readPackageFile("docs/ux/click-path-audit.md")

        XCTAssertTrue(appSource.contains("@StateObject private var menuBarQuickCaptureViewModel: ProjectBoardViewModel"))
        XCTAssertTrue(appSource.contains("_menuBarQuickCaptureViewModel = StateObject(wrappedValue: AppRuntimeFactory.makeProjectBoardViewModel())"))
        XCTAssertTrue(appSource.contains("MenuBarPanel(controller: menuBarController, quickCaptureViewModel: menuBarQuickCaptureViewModel)"))
        XCTAssertTrue(appSource.contains("@ObservedObject var quickCaptureViewModel: ProjectBoardViewModel"))
        XCTAssertTrue(appSource.contains("@State private var quickCaptureTitle = \"\""))
        XCTAssertTrue(appSource.contains("TextField(\"Quick add to Inbox\", text: $quickCaptureTitle)"))
        XCTAssertTrue(appSource.contains("quickCaptureViewModel.createInboxTask(title: title)"))
        XCTAssertTrue(appSource.contains(".keyboardShortcut(.return, modifiers: [.command])"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"menu-bar-quick-capture-title\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"menu-bar-quick-capture-button\")"))
        XCTAssertTrue(appSource.contains("NotificationCenter.default.post(name: .soloPMProjectBoardDidChange, object: nil)"))
        XCTAssertTrue(audit.contains("menu bar Quick AddからInboxへ0画面遷移で実タスクを作れる"))
        XCTAssertTrue(phase.contains("[x] MenuBarExtraにQuick Addを追加し、Project Boardを開かずにInboxへローカルTaskを作れる。"))
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
        XCTAssertFalse(appSource.contains("Picker(\"Server\""))
        XCTAssertTrue(appSource.contains("MCPServerSettingsRow("))
        XCTAssertTrue(appSource.contains("externalMCPViewModel.registrationRows"))
        XCTAssertTrue(appSource.contains("externalMCPViewModel.selectRegistration(id: row.id)"))
        XCTAssertTrue(appSource.contains("await externalMCPViewModel.checkConnection(id: row.id)"))
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
        XCTAssertTrue(appSource.contains("artifactStore: SQLiteArtifactStore(connection: connection)"))
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
        XCTAssertTrue(appSource.contains("externalMCPViewModel.connectionCheckResultLabel"))
        XCTAssertTrue(appSource.contains("syncViewModel.statusLabel"))
        XCTAssertTrue(appSource.contains("settingsViewModel.settings.notificationsEnabled"))
    }

    func testSettingsOverviewSurfacesIntegrationStatusTilesForPhase12() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

        XCTAssertTrue(appSource.contains("integrationPermissionSnapshot: AppRuntimeFactory.makeIntegrationPermissionSnapshot()"))
        XCTAssertTrue(appSource.contains("title: \"STT\""))
        XCTAssertTrue(appSource.contains("title: \"TTS\""))
        XCTAssertTrue(appSource.contains("title: \"Calendar\""))
        XCTAssertTrue(appSource.contains("title: \"Reminder\""))
        XCTAssertTrue(appSource.contains("title: \"Data Location\""))
        XCTAssertTrue(appSource.contains("settingsViewModel.settings.sttProvider.displayName"))
        XCTAssertTrue(appSource.contains("TTSProvider.systemSpeech.unavailableReason"))
        XCTAssertTrue(appSource.contains("integrationPermissionSnapshot.status(for: .calendar)"))
        XCTAssertTrue(appSource.contains("integrationPermissionSnapshot.status(for: .reminders)"))
        XCTAssertTrue(appSource.contains("dataLocationOverviewStatusLabel"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"settings-status-overview\")"))
    }

    func testSettingsDoesNotExposeSelectableTTSProviderWhenUnsupported() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
        let aiTabStart = try XCTUnwrap(appSource.range(of: "private var aiSettingsTab: some View"))
        let syncTabStart = try XCTUnwrap(appSource.range(of: "private var syncSettingsTab: some View"))
        let aiTabSource = String(appSource[aiTabStart.lowerBound..<syncTabStart.lowerBound])

        XCTAssertTrue(aiTabSource.contains("LabeledContent(\"Text to Speech\""))
        XCTAssertTrue(aiTabSource.contains("TTSProvider.releaseReadyCases.isEmpty"))
        XCTAssertTrue(aiTabSource.contains("TTSProvider.systemSpeech.unavailableReason"))
        XCTAssertTrue(aiTabSource.contains(".accessibilityIdentifier(\"settings-tts-unavailable\")"))
        XCTAssertFalse(aiTabSource.contains("Picker(\"Text to Speech\""))
    }

    func testSettingsOverviewSurfacesProValueWithoutOpeningSyncOrMCPTabs() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
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
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
        let appearanceSectionSource = try readPackageFile("Sources/SoloPMApp/Views/SettingsAppearanceSection.swift")
        let audit = try readPackageFile("docs/ux/click-path-audit.md")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")

        XCTAssertTrue(appSource.contains("TabView(selection: $selectedTab) {"))
        XCTAssertTrue(appSource.contains("private enum SettingsTab: String"))
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
        XCTAssertTrue(privacySource.contains("Section(\"Watcher\")"))
        XCTAssertTrue(audit.contains("Settings詳細FormはOverview / Appearance / AI / MCP / Sync / Privacyのtabへ分割済み"))
        XCTAssertTrue(phase.contains("[x] Settings詳細FormをOverview / Appearance / AI / MCP / Sync / Privacyのtabへ分割し"))
    }

    func testAISettingsTabShowsOnlySelectedProviderFields() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
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
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
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
        XCTAssertTrue(factorySource.contains("case .geminiOpenAICompatible:"))
        XCTAssertTrue(factorySource.contains("UnavailableLLMProvider("))
        XCTAssertFalse(factorySource.contains(".openaiResponses,\n             .geminiOpenAICompatible:"))
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
        XCTAssertTrue(appSource.contains("if let syncUnavailableLabel = syncViewModel.syncUnavailableLabel"))
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

    func testSyncSettingsTabSurfacesPaidValueAndLocalBoundaryBeforeToggle() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
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
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
        let syncStart = try XCTUnwrap(appSource.range(of: "private var syncSettingsTab: some View"))
        let providerStart = try XCTUnwrap(appSource.range(of: "@ViewBuilder\n    private var selectedProviderConfigurationFields"))
        let syncSource = String(appSource[syncStart.lowerBound..<providerStart.lowerBound])

        XCTAssertTrue(syncSource.contains("Section(\"External Task Tools\")"))
        XCTAssertTrue(syncSource.contains("name: \"Google Calendar\""))
        XCTAssertTrue(syncSource.contains("name: \"Todoist\""))
        XCTAssertTrue(syncSource.contains("name: \"Notion\""))
        XCTAssertTrue(syncSource.contains("name: \"Linear\""))
        XCTAssertTrue(syncSource.contains("name: \"GitHub Issues\""))
        XCTAssertTrue(syncSource.contains("Pro unlocks external sync; import/export JSON stays local."))
        XCTAssertFalse(appSource.contains("import SoloPMExternalConnectors"))
    }

    func testSettingsSurfaceShowsInlineMCPServerRowsWithCheckActions() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
        let mcpSource = try readPackageFile("Sources/SoloPMCore/ExternalMCP/MCPRegistration.swift")
        let audit = try readPackageFile("docs/ux/click-path-audit.md")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")

        XCTAssertTrue(appSource.contains("MCPServerSettingsRow("))
        XCTAssertTrue(appSource.contains("ForEach(externalMCPViewModel.registrationRows) { row in"))
        XCTAssertTrue(appSource.contains("await externalMCPViewModel.checkConnection(id: row.id)"))
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
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
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
        XCTAssertTrue(audit.contains("Sources/SoloPMApp/Views/ProjectWorkflowViews.swift"))
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
        let workflowSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectWorkflowViews.swift")
        let evidence = try readPackageFile("docs/release/evidence/ui-screenshots.md")
        let audit = try readPackageFile("docs/ux/click-path-audit.md")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")

        XCTAssertTrue(script.contains("script/build_and_run.sh\" --build-only"))
        XCTAssertTrue(script.contains("CFFIXED_USER_HOME"))
        XCTAssertTrue(script.contains("SOLOPM_UI_EVIDENCE_HOME"))
        XCTAssertTrue(script.contains("SOLOPM_UI_EVIDENCE_TMPDIR"))
        XCTAssertTrue(script.contains("solopm.appearancePreference"))
        XCTAssertTrue(script.contains("ui_evidence_window_metadata.swift"))
        XCTAssertTrue(windowMetadataScript.contains("CGWindowListCopyWindowInfo"))
        XCTAssertTrue(script.contains("wait_for_window_capture_metadata"))
        XCTAssertTrue(script.contains("position_window_for_capture"))
        XCTAssertTrue(script.contains(#"tell application \"$APP_NAME\" to activate"#))
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
        XCTAssertTrue(script.contains("/usr/bin/defaults write \"$BUNDLE_IDENTIFIER\""))
        XCTAssertTrue(script.contains("solopm.projectBoard.selectedDestination"))
        XCTAssertTrue(script.contains("SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION=$PROJECT_BOARD_SELECTION_OVERRIDE"))
        XCTAssertTrue(script.contains("SOLOPM_APPEARANCE_PREFERENCE=$APPEARANCE_OVERRIDE"))
        XCTAssertTrue(script.contains("project:$project_id"))
        XCTAssertTrue(script.contains("project-board-light.png"))
        XCTAssertTrue(script.contains("project-board-dark.png"))
        XCTAssertTrue(script.contains("project-board-system.png"))
        XCTAssertTrue(script.contains("settings-appearance-light.png"))
        XCTAssertTrue(script.contains("settings-appearance-dark.png"))
        XCTAssertTrue(script.contains("settings-overview-light.png"))
        XCTAssertTrue(script.contains("settings-overview-dark.png"))
        XCTAssertTrue(script.contains("settings-mcp-light.png"))
        XCTAssertTrue(script.contains("settings-mcp-dark.png"))
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
        XCTAssertFalse(script.contains("sk-"))

        XCTAssertTrue(boardSource.contains("@AppStorage(ProjectBoardSelectionPersistence.storageKey)"))
        XCTAssertTrue(boardSource.contains("restoreSelectedDestinationIfNeeded()"))
        XCTAssertTrue(boardSource.contains("persistSelectedDestination(_ destination: ProjectBoardSidebarDestination?)"))
        XCTAssertTrue(workflowSource.contains("enum ProjectBoardSelectionPersistence"))
        XCTAssertTrue(workflowSource.contains("static let storageKey = \"solopm.projectBoard.selectedDestination\""))
        XCTAssertTrue(workflowSource.contains("static let environmentOverrideKey = \"SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION\""))
        XCTAssertTrue(boardSource.contains("ProjectBoardSelectionPersistence.environmentOverrideRawValue"))
        XCTAssertTrue(workflowSource.contains("case \"project\""))

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
        XCTAssertTrue(evidence.contains("Manual review: passed for Project Board sidebar/cards/inspector, Inbox voice detail, Projects overview, Schedule cockpit, Done analytics, Settings integrations, Settings Appearance Theme picker, Settings MCP server rows, and Light/Dark/System contrast"))
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

    func testPhase12UIScreenshotEvidenceCoversNewCockpitScreens() throws {
        let script = try readPackageFile("script/capture_ui_evidence.sh")
        let releaseReport = try readPackageFile("script/release_readiness_report.sh")
        let evidence = try readPackageFile("docs/release/evidence/ui-screenshots.md")
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

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
        XCTAssertTrue(script.contains("assert_phase12_seed_data \"$DATABASE_PATH\""))
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
