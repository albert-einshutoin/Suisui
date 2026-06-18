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

    func testAppearanceSelectionIsConfiguredOnlyFromSettings() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")

        XCTAssertTrue(appSource.contains("Section(\"Appearance\")"))
        XCTAssertTrue(appSource.contains("Picker(\"Theme\", selection: $appearancePreference)"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"settings-theme-picker\")"))
        XCTAssertEqual(appSource.components(separatedBy: "settings-theme-picker").count - 1, 1)
        XCTAssertEqual(appSource.components(separatedBy: "Section(\"Appearance\")").count - 1, 1)
        XCTAssertEqual(appSource.components(separatedBy: "Picker(\"Theme\"").count - 1, 1)
        let settingsRange = try XCTUnwrap(appSource.range(of: "Settings {"))
        let appearanceRange = try XCTUnwrap(appSource.range(of: "Section(\"Appearance\")"))
        XCTAssertLessThan(settingsRange.lowerBound, appearanceRange.lowerBound)
        XCTAssertFalse(boardSource.contains("AppearancePicker"))
        XCTAssertFalse(boardSource.contains("SidebarAppearanceSection"))
        XCTAssertFalse(boardSource.contains("Section(\"Appearance\")"))
        XCTAssertFalse(boardSource.contains("Picker(\"Theme\""))
        XCTAssertFalse(boardSource.contains("Picker(\"Appearance\""))
        XCTAssertFalse(boardSource.contains("@AppStorage(SoloPMAppearancePreference.storageKey)"))
        XCTAssertFalse(boardSource.contains("SoloPMAppearancePreference"))
        XCTAssertFalse(boardSource.contains("Theme"))
        XCTAssertFalse(boardSource.contains("appearancePreference: $appearancePreference"))
    }

    func testProjectBoardSidebarAndToolbarDoNotHostThemeControls() throws {
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let sidebarStart = try XCTUnwrap(boardSource.range(of: "NavigationSplitView {"))
        let detailStart = try XCTUnwrap(boardSource.range(of: "} detail: {"))
        let sidebarSource = String(boardSource[sidebarStart.upperBound..<detailStart.lowerBound])

        XCTAssertTrue(sidebarSource.contains("Show Archived"))
        XCTAssertTrue(sidebarSource.contains("Add Project"))
        XCTAssertFalse(sidebarSource.contains("Theme"))
        XCTAssertFalse(sidebarSource.contains("Appearance"))
        XCTAssertFalse(sidebarSource.contains("SoloPMAppearancePreference"))
        XCTAssertFalse(sidebarSource.contains("Picker(\"Theme\""))
        XCTAssertFalse(sidebarSource.contains("Picker(\"Appearance\""))

        let toolbarStart = try XCTUnwrap(boardSource.range(of: ".toolbar {"))
        let inspectorStart = try XCTUnwrap(boardSource.range(of: ".inspector(isPresented: inspectorBinding)"))
        let toolbarSource = String(boardSource[toolbarStart.lowerBound..<inspectorStart.lowerBound])

        XCTAssertTrue(toolbarSource.contains("SettingsLink"))
        XCTAssertFalse(toolbarSource.contains("Theme"))
        XCTAssertFalse(toolbarSource.contains("Appearance"))
        XCTAssertFalse(toolbarSource.contains("SoloPMAppearancePreference"))
        XCTAssertFalse(toolbarSource.contains("Picker(\"Theme\""))
        XCTAssertFalse(toolbarSource.contains("Picker(\"Appearance\""))
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

        XCTAssertTrue(source.contains(".keyboardShortcut(\"n\", modifiers: [.command])"))
        XCTAssertTrue(source.contains(".keyboardShortcut(\"n\", modifiers: [.command, .shift])"))
        XCTAssertTrue(source.contains(".keyboardShortcut(\",\", modifiers: [.command])"))
        XCTAssertTrue(source.contains(".help(\"Add a project\")"))
        XCTAssertTrue(source.contains(".help(\"Open Settings\")"))
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

    func testInspectorsExposeCompactMetadataSummaries() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")
        let audit = try readPackageFile("docs/ux/click-path-audit.md")

        XCTAssertTrue(source.contains("TaskInspectorMetadataSummary(task: task, projectTitle: viewModel.projectTitle(for: task))"))
        XCTAssertTrue(source.contains("ProjectInspectorMetadataSummary(project: project)"))
        XCTAssertTrue(source.contains("private struct InspectorMetadataPill"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"task-inspector-metadata-summary\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-inspector-metadata-summary\")"))
        XCTAssertTrue(source.contains("ViewThatFits(in: .horizontal)"))
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

    func testInboxAndTodayWorkflowsExposeKeyboardAndVoiceOverAnchors() throws {
        let workflowSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectWorkflowViews.swift")
        let audit = try readPackageFile("docs/ux/click-path-audit.md")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")

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

        XCTAssertTrue(audit.contains("Inbox / Todayのrow、Quick Add、分類action、Today summary、time blockにsource-level accessibility identifiers / hints / keyboard anchorsを追加済み"))
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

        XCTAssertTrue(source.contains("ProjectInspectorView(project: project, viewModel: viewModel)"))
        XCTAssertTrue(source.contains("ProjectInspectorSuggestionSection"))
        XCTAssertTrue(source.contains("@State private var isInspectorPresented = true"))
        XCTAssertTrue(source.contains("selectedProjectForInspector"))
        XCTAssertTrue(source.contains("isInspectorPresented = false"))
        XCTAssertTrue(source.contains("viewModel.updateSelectedProject(title: title)"))
        XCTAssertTrue(source.contains("viewModel.deleteSelectedProject()"))
        XCTAssertTrue(source.contains("viewModel.archiveSelectedProject()"))
        XCTAssertTrue(source.contains("viewModel.restoreSelectedProject()"))
        XCTAssertTrue(source.contains("viewModel.completeSelectedProject()"))
        XCTAssertTrue(source.contains("viewModel.createTask(title: \"Define next action\""))
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
        XCTAssertTrue(source.contains(".accessibilityHint(\"Opens task details in the inspector. Use the status controls below to move without dragging.\")"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Status controls for \\(task.title)\")"))
        XCTAssertTrue(source.contains(".accessibilityHint(\"Moves the task between board columns.\")"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Add task to \\(column.title)\")"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Add task to empty \\(column.title) column\")"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Current status: \\(task.status.title)\")"))
        XCTAssertTrue(source.contains(".accessibilityHint(\"Changes \\(task.title) status.\")"))
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
        XCTAssertTrue(phase.contains("[ ] 実機VoiceOverでProject board -> card -> inspectorのfocus orderを確認する。"))
    }

    func testVoiceOverEvidenceTemplateCapturesReleaseCandidateContextAndFailureNotes() throws {
        let evidence = try readPackageFile("docs/release/evidence/accessibility-voiceover.md")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")

        XCTAssertTrue(evidence.contains("Status: pending"))
        XCTAssertTrue(evidence.contains("Do not set `Status: passed` until every item below is verified"))
        XCTAssertTrue(evidence.contains("## Release Candidate Context"))
        XCTAssertTrue(evidence.contains("- macOS version:"))
        XCTAssertTrue(evidence.contains("- App build:"))
        XCTAssertTrue(evidence.contains("- Bundle identifier:"))
        XCTAssertTrue(evidence.contains("- Checked by:"))
        XCTAssertTrue(evidence.contains("- Check date:"))
        XCTAssertTrue(evidence.contains("## Setup"))
        XCTAssertTrue(evidence.contains("Seed the Project Board with at least one active project and one task with a due date."))
        XCTAssertTrue(evidence.contains("## Required Focus Path"))
        XCTAssertTrue(evidence.contains("[ ] Project navigation"))
        XCTAssertTrue(evidence.contains("[ ] Task inspector"))
        XCTAssertTrue(evidence.contains("## Failure Notes"))
        XCTAssertTrue(evidence.contains("- Blocker observed:"))
        XCTAssertTrue(evidence.contains("- Follow-up source/test link:"))
        XCTAssertTrue(evidence.contains("## Completion Instructions"))
        XCTAssertTrue(evidence.contains("Remove all `pending` and unchecked `[ ]` markers."))
        XCTAssertTrue(phase.contains("[x] `release_readiness_report.sh` はVoiceOver証跡のrelease-candidate context空欄/テンプレート値をblockerにする。"))
        XCTAssertTrue(phase.contains("[x] `docs/release/evidence/accessibility-voiceover.md` は実機確認者がmacOS/build/checked-by/failure notesを埋められる形にする。"))
    }

    func testTodayWorkflowShowsRecommendationDueCountsAndTimeBlocks() throws {
        let workflowSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectWorkflowViews.swift")
        let coreSource = try readPackageFile("Sources/SoloPMCore/App/ProjectBoard.swift")

        XCTAssertTrue(workflowSource.contains("TodayPlanSummary"))
        XCTAssertTrue(workflowSource.contains("TodayTimeBlockList"))
        XCTAssertTrue(workflowSource.contains("plan.overdueCount"))
        XCTAssertTrue(workflowSource.contains("plan.dueTodayCount"))
        XCTAssertTrue(workflowSource.contains("plan.recommendationReason"))
        XCTAssertTrue(workflowSource.contains("ForEach(plan.timeBlocks)"))
        XCTAssertTrue(coreSource.contains("public struct TodayWorkflowPlan"))
        XCTAssertTrue(coreSource.contains("public struct TodayTimeBlock"))
        XCTAssertTrue(coreSource.contains("public func todayPlan("))
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

    func testSettingsSurfaceUsesTabbedCategoriesInsteadOfOneLongForm() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
        let audit = try readPackageFile("docs/ux/click-path-audit.md")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")

        XCTAssertTrue(appSource.contains("TabView {"))
        XCTAssertTrue(appSource.contains("private var overviewSettingsTab: some View"))
        XCTAssertTrue(appSource.contains("private var aiSettingsTab: some View"))
        XCTAssertTrue(appSource.contains("private var mcpSettingsTab: some View"))
        XCTAssertTrue(appSource.contains("private var syncSettingsTab: some View"))
        XCTAssertTrue(appSource.contains("private var privacySettingsTab: some View"))
        XCTAssertTrue(appSource.contains("Label(\"Overview\", systemImage: \"gauge.with.dots.needle.bottom.50percent\")"))
        XCTAssertTrue(appSource.contains("Label(\"AI\", systemImage: \"brain.head.profile\")"))
        XCTAssertTrue(appSource.contains("Label(\"MCP\", systemImage: \"externaldrive.connected.to.line.below\")"))
        XCTAssertTrue(appSource.contains("Label(\"Sync\", systemImage: \"arrow.triangle.2.circlepath\")"))
        XCTAssertTrue(appSource.contains("Label(\"Privacy\", systemImage: \"lock.shield\")"))

        let overviewStart = try XCTUnwrap(appSource.range(of: "private var overviewSettingsTab"))
        let aiStart = try XCTUnwrap(appSource.range(of: "private var aiSettingsTab"))
        let syncStart = try XCTUnwrap(appSource.range(of: "private var syncSettingsTab"))
        let privacyStart = try XCTUnwrap(appSource.range(of: "private var privacySettingsTab"))
        let mcpStart = try XCTUnwrap(appSource.range(of: "private var mcpSettingsTab"))

        let overviewSource = String(appSource[overviewStart.lowerBound..<aiStart.lowerBound])
        let aiSource = String(appSource[aiStart.lowerBound..<syncStart.lowerBound])
        let syncSource = String(appSource[syncStart.lowerBound..<privacyStart.lowerBound])
        let privacySource = String(appSource[privacyStart.lowerBound..<mcpStart.lowerBound])
        let mcpSource = String(appSource[mcpStart.lowerBound..<appSource.endIndex])

        XCTAssertTrue(overviewSource.contains("Section(\"Status Overview\")"))
        XCTAssertTrue(overviewSource.contains("Section(\"Appearance\")"))
        XCTAssertTrue(aiSource.contains("Section(\"AI\")"))
        XCTAssertTrue(aiSource.contains("Section(\"Voice\")"))
        XCTAssertTrue(mcpSource.contains("Section(\"External MCP\")"))
        XCTAssertTrue(mcpSource.contains("Section(\"MCP Tool Permissions\")"))
        XCTAssertTrue(mcpSource.contains("Section(\"MCP Audit\")"))
        XCTAssertTrue(syncSource.contains("Section(\"Sync\")"))
        XCTAssertTrue(privacySource.contains("Section(\"Privacy\")"))
        XCTAssertTrue(privacySource.contains("Section(\"Watcher\")"))
        XCTAssertTrue(audit.contains("Settings詳細FormはOverview / AI / MCP / Sync / Privacyのtabへ分割済み"))
        XCTAssertTrue(phase.contains("[x] Settings詳細FormをOverview / AI / MCP / Sync / Privacyのtabへ分割し"))
    }

    func testAISettingsTabShowsOnlySelectedProviderFields() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
        let audit = try readPackageFile("docs/ux/click-path-audit.md")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")

        XCTAssertTrue(appSource.contains("selectedProviderConfigurationFields"))
        XCTAssertTrue(appSource.contains("switch settingsViewModel.settings.aiProvider"))
        XCTAssertTrue(appSource.contains("case .openaiResponses, .geminiOpenAICompatible:"))
        XCTAssertTrue(appSource.contains("case .claudeMessages:"))
        XCTAssertTrue(appSource.contains("case .geminiDirect:"))
        XCTAssertTrue(appSource.contains("case .groqOpenAICompatible:"))
        XCTAssertTrue(appSource.contains("case .opencodeLocal:"))
        XCTAssertTrue(appSource.contains("case .openRouterCompatible:"))
        XCTAssertTrue(appSource.contains("case .ollamaCompatible:"))
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

    func testClickPathAuditTracksTaskCardFocusUpgradeAndRemainingManualEvidence() throws {
        let audit = try readPackageFile("docs/ux/click-path-audit.md")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")

        XCTAssertTrue(audit.contains("cardの `Open task` 領域 -> inspector編集 -> `Save Changes`"))
        XCTAssertTrue(audit.contains("キーボードフォーカス可能なButton"))
        XCTAssertTrue(audit.contains("Open Detailsとstatus move controlsも別フォーカス対象に分離"))
        XCTAssertTrue(audit.contains("Light/Dark/System screenshot evidence scriptは追加済み"))
        XCTAssertTrue(audit.contains("実機VoiceOver focus order確認は残る"))
        XCTAssertTrue(phase.contains("[x] Task card本体のOpen Detailsとstatus move controlsを別フォーカス対象に分け"))
        XCTAssertTrue(phase.contains("[ ] 実機VoiceOverでProject board -> card -> inspectorのfocus orderを確認する。"))
        XCTAssertTrue(phase.contains("[x] `script/capture_ui_evidence.sh` は一時HOME、seed済みProject board、Light/Dark/System切替、window captureを使う。"))
        XCTAssertTrue(phase.contains("[ ] Light/Dark/System切替後にカード、サイドバー、インスペクタのコントラストが破綻しないことをスクリーンショットで確認する。"))
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
        XCTAssertTrue(phase.contains("[x] UX click-path auditで主要操作のクリック数が記録され、改善PRと紐づいている。"))
    }

    func testUIScreenshotEvidenceUsesIsolatedSeededProjectBoard() throws {
        let script = try readPackageFile("script/capture_ui_evidence.sh")
        let evidence = try readPackageFile("docs/release/evidence/ui-screenshots.md")
        let audit = try readPackageFile("docs/ux/click-path-audit.md")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")

        XCTAssertTrue(script.contains("script/build_and_run.sh\" --build-only"))
        XCTAssertTrue(script.contains("CFFIXED_USER_HOME"))
        XCTAssertTrue(script.contains("SOLOPM_UI_EVIDENCE_HOME"))
        XCTAssertTrue(script.contains("solopm.appearancePreference"))
        XCTAssertTrue(script.contains("CGWindowListCopyWindowInfo"))
        XCTAssertTrue(script.contains(#"tell application \"$APP_NAME\" to activate"#))
        XCTAssertTrue(script.contains("screencapture -x -l"))
        XCTAssertTrue(script.contains("assert_screenshot_has_visible_content"))
        XCTAssertTrue(script.contains("CGImageSourceCreateWithURL"))
        XCTAssertTrue(script.contains("Screenshot appears blank or too low contrast"))
        XCTAssertTrue(script.contains("sqlite3"))
        XCTAssertTrue(script.contains("Launch Readiness"))
        XCTAssertTrue(script.contains("project-board-light.png"))
        XCTAssertTrue(script.contains("project-board-dark.png"))
        XCTAssertTrue(script.contains("project-board-system.png"))
        XCTAssertTrue(script.contains("docs/release/evidence/ui-screenshots"))
        XCTAssertTrue(script.contains("Screen Recording permission"))
        XCTAssertFalse(script.contains("OpenAI API Key"))
        XCTAssertFalse(script.contains("sk-"))

        XCTAssertTrue(evidence.contains("script/capture_ui_evidence.sh"))
        XCTAssertTrue(evidence.contains("isolated temporary HOME"))
        XCTAssertTrue(evidence.contains("project-board-light.png"))
        XCTAssertTrue(evidence.contains("project-board-dark.png"))
        XCTAssertTrue(evidence.contains("project-board-system.png"))
        XCTAssertTrue(audit.contains("Light/Dark/System screenshot evidence scriptは追加済み"))
        XCTAssertTrue(phase.contains("[x] `script/capture_ui_evidence.sh` は一時HOME、seed済みProject board、Light/Dark/System切替、window captureを使う。"))
        XCTAssertTrue(phase.contains("[ ] Light/Dark/System切替後にカード、サイドバー、インスペクタのコントラストが破綻しないことをスクリーンショットで確認する。"))
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
        XCTAssertTrue(benchmark.contains("VC-Grade Feature Fit"))
        XCTAssertTrue(phase.contains("[x] 競合benchmarkから採用/非採用判断が残っている。"))
        XCTAssertTrue(phase.contains("[ ] 完了条件: Notion的な柔軟さ、Linear的な速度、Todoist的な即時入力のうち、SoloPMに必要な部分だけが実装される。"))
    }

    func testInvestorReviewTiesFeaturesToRetentionMonetizationAndRisk() throws {
        let review = try readPackageFile("docs/product/investor-review.md")

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
