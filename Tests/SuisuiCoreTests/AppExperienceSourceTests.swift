import Foundation
import SuisuiCore
import XCTest

final class AppExperienceSourceTests: XCTestCase {
    func testOnboardingLessonCatalogUsesJapaneseSourceKeys() throws {
        let english = try readPackageFile("Sources/SuisuiApp/Resources/en.lproj/Localizable.strings")
        let japanese = try readPackageFile("Sources/SuisuiApp/Resources/ja.lproj/Localizable.strings")
        let englishKeys = try localizableKeys(in: "Sources/SuisuiApp/Resources/en.lproj/Localizable.strings")
        let japaneseKeys = try localizableKeys(in: "Sources/SuisuiApp/Resources/ja.lproj/Localizable.strings")

        let lessonKeys = [OnboardingSampleProjectDefinition.projectTitle]
            + OnboardingSampleProjectDefinition.tasks.flatMap { [$0.title, $0.detail] }

        for key in lessonKeys {
            // `.strings` stores escaped newlines, while the runtime detail
            // uses an actual newline for the two-layer Lesson presentation.
            let serializedKey = key.replacingOccurrences(of: "\n", with: "\\n")
            XCTAssertTrue(englishKeys.contains(serializedKey), "Missing English key: \(serializedKey)")
            XCTAssertTrue(japaneseKeys.contains(serializedKey), "Missing Japanese key: \(serializedKey)")
        }

        XCTAssertTrue(english.contains("\"Suisuiを学ぶ\" = \"Learn Suisui\";"))
        XCTAssertTrue(japanese.contains("\"Suisuiを学ぶ\" = \"Suisuiを学ぶ\";"))
    }

    func testSettingsWindowSupportsHostedCompactHeight() throws {
        let source = try readPackageFile("Sources/SuisuiApp/Views/SettingsView.swift")

        XCTAssertTrue(source.contains(".frame(width: presentation == .window ? 680 : nil, height: presentation == .window ? 584 : nil)"))
        XCTAssertTrue(source.contains("case board"))
    }

    func testProjectBoardSidebarMatchesApprovedTodaySampleStructure() throws {
        let sidebarSource = try readPackageFile(
            "Sources/SuisuiApp/Views/ProjectBoardSidebarView.swift"
        )
        let requiredMarkers = [
            "sidebar-destination-inbox",
            "sidebar-destination-today",
            "sidebar-destination-projects",
            "sidebar-destination-schedule",
            "sidebar-destination-completed",
            "sidebar-action-voice-command",
            "sidebar-action-settings",
        ]

        for marker in requiredMarkers {
            XCTAssertEqual(
                sidebarSource.components(separatedBy: marker).count - 1,
                1,
                "Expected exactly one top-level marker for \(marker)"
            )
        }
        let markerRanges = try requiredMarkers.map { marker in
            try XCTUnwrap(sidebarSource.range(of: marker))
        }
        for (leading, trailing) in zip(markerRanges, markerRanges.dropFirst()) {
            XCTAssertLessThan(leading.lowerBound, trailing.lowerBound)
        }

        let searchStart = try XCTUnwrap(sidebarSource.range(of: "Button(action: onOpenSearch)"))
        let searchEnd = try XCTUnwrap(
            sidebarSource.range(
                of: "VStack(alignment: .leading, spacing: 1) {",
                range: searchStart.lowerBound..<sidebarSource.endIndex
            )
        )
        let searchButton = String(sidebarSource[searchStart.lowerBound..<searchEnd.lowerBound])
        XCTAssertTrue(searchButton.contains(".padding(.horizontal, 10)"))
        XCTAssertTrue(
            searchButton.contains(
                ".frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32, alignment: .leading)"
            )
        )
        XCTAssertTrue(
            searchButton.contains(
                ".suisuiLiquidGlassControlSurface(cornerRadius: 12)"
            )
        )
        XCTAssertTrue(searchButton.contains(".contentShape(Rectangle())"))
        XCTAssertFalse(sidebarSource.contains("ScrollView {"))
        XCTAssertTrue(sidebarSource.contains("sidebar-destination-completed"))
        XCTAssertTrue(sidebarSource.contains("sidebar-action-voice-command"))
        XCTAssertTrue(sidebarSource.contains("sidebar-action-settings"))
        XCTAssertTrue(sidebarSource.contains(".layoutPriority(1)"))

        let quickActionStart = try XCTUnwrap(sidebarSource.range(of: "private func quickAction("))
        let quickActionEnd = try XCTUnwrap(
            sidebarSource.range(
                of: "private func perform",
                range: quickActionStart.lowerBound..<sidebarSource.endIndex
            )
        )
        let quickAction = String(sidebarSource[quickActionStart.lowerBound..<quickActionEnd.lowerBound])
        XCTAssertTrue(quickAction.contains(".contentShape(Rectangle())"))

        XCTAssertTrue(sidebarSource.contains("NSApplication.shared.applicationIconImage"))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: packageRoot()
                    .appendingPathComponent("packaging/Suisui-AppIcon-1024.png")
                    .path
            )
        )
        XCTAssertTrue(sidebarSource.contains("sidebar-open-search"))
        XCTAssertTrue(sidebarSource.contains("sidebar-quick-add-task"))
        XCTAssertTrue(sidebarSource.contains("sidebar-quick-add-by-voice"))
        XCTAssertTrue(sidebarSource.contains("sidebar-quick-block-time"))
        XCTAssertTrue(sidebarSource.contains("sidebar-quick-import-tasks"))
        XCTAssertTrue(sidebarSource.contains("sidebar-profile"))
        XCTAssertFalse(sidebarSource.contains("sidebar-destination-review"))
    }

    func testProjectBoardSidebarButtonsPreserveNativeAccessibilityActions() throws {
        let sidebarSource = try readPackageFile(
            "Sources/SuisuiApp/Views/ProjectBoardSidebarView.swift"
        )

        let searchStart = try XCTUnwrap(sidebarSource.range(of: "Button(action: onOpenSearch)"))
        let searchEnd = try XCTUnwrap(
            sidebarSource.range(
                of: "VStack(alignment: .leading, spacing: 1) {",
                range: searchStart.lowerBound..<sidebarSource.endIndex
            )
        )
        let sidebarRowStart = try XCTUnwrap(
            sidebarSource.range(of: "private func sidebarRowButton(")
        )
        let sidebarRowEnd = try XCTUnwrap(
            sidebarSource.range(
                of: "private func quickAction(",
                range: sidebarRowStart.lowerBound..<sidebarSource.endIndex
            )
        )
        let quickActionStart = sidebarRowEnd
        let quickActionEnd = try XCTUnwrap(
            sidebarSource.range(
                of: "private func perform",
                range: quickActionStart.lowerBound..<sidebarSource.endIndex
            )
        )

        let buttonBlocks = [
            String(sidebarSource[searchStart.lowerBound..<searchEnd.lowerBound]),
            String(sidebarSource[sidebarRowStart.lowerBound..<sidebarRowEnd.lowerBound]),
            String(sidebarSource[quickActionStart.lowerBound..<quickActionEnd.lowerBound]),
        ]
        for block in buttonBlocks {
            XCTAssertTrue(block.contains("Button"))
            XCTAssertTrue(block.contains(".accessibilityHidden(true)"))
            XCTAssertTrue(block.contains(".accessibilityLabel("))
            XCTAssertTrue(block.contains(".contentShape(Rectangle())"))
            XCTAssertFalse(
                block.contains(".accessibilityElement(children: .ignore)"),
                "Replacing a native Button AX element removes its AXPress action"
            )
        }
        XCTAssertFalse(sidebarSource.contains(".accessibilityAddTraits(.isButton)"))
    }

    func testProjectBoardConnectsSidebarCountsAndActionsToProductBehavior() throws {
        let boardSource = try readPackageFile(
            "Sources/SuisuiApp/Views/ProjectBoardView.swift"
        )
        let sidebarSource = try readPackageFile(
            "Sources/SuisuiApp/Views/ProjectBoardSidebarView.swift"
        )

        XCTAssertTrue(boardSource.contains("today: sidebarMetrics.todayCount"))
        XCTAssertTrue(boardSource.contains("inbox: sidebarMetrics.inboxCount"))
        XCTAssertTrue(boardSource.contains("projects: sidebarMetrics.projectsCount"))
        XCTAssertTrue(boardSource.contains("schedule: sidebarMetrics.scheduleCount"))
        XCTAssertTrue(boardSource.contains("completed: sidebarMetrics.doneCount"))
        XCTAssertTrue(boardSource.contains("onOpenSearch: { isCommandPaletteVisible = true }"))
        XCTAssertTrue(boardSource.contains("onAddTask: beginInboxQuickAddFromSidebar"))
        XCTAssertTrue(boardSource.contains("onBlockTime: prepareScheduleDraftFromSidebar"))
        XCTAssertTrue(boardSource.contains("onImportTasks: { isImportingTaskInterop = true }"))
        XCTAssertTrue(boardSource.contains("private func prepareScheduleDraftFromSidebar()"))
        XCTAssertFalse(sidebarSource.contains("review: Int?"))
        XCTAssertFalse(
            boardSource.contains("review: viewModel.assistantQueueSnapshot.needsAttentionCount")
        )
        XCTAssertFalse(sidebarSource.contains("@escaping () -> Void = {}"))
    }

    func testTodaySidebarLabelsAreLocalizedAndAccessible() throws {
        let english = try readPackageFile(
            "Sources/SuisuiApp/Resources/en.lproj/Localizable.strings"
        )
        let japanese = try readPackageFile(
            "Sources/SuisuiApp/Resources/ja.lproj/Localizable.strings"
        )
        let expectedEnglish = [
            "Suisui": "Suisui",
            "Welcome to Suisui": "Welcome to Suisui",
            "Inbox": "Inbox",
            "Schedule": "Schedule",
            "Add Task": "Add Task",
            "Quick Actions": "Quick Actions",
            "Search": "Search",
            "Completed": "Completed",
            "Add by Voice": "Add by Voice",
            "Block Time": "Block Time",
            "Navigate work or open a quick action.": "Navigate work or open a quick action.",
            "Opens the command palette.": "Opens the command palette.",
            "Creates a local schedule draft without writing Calendar.":
                "Creates a local schedule draft without writing Calendar.",
            "No items today": "No items today",
            "No projects": "No projects",
            "No scheduled items": "No scheduled items",
            "No completed items": "No completed items",
            "Opens this section.": "Opens this section.",
        ]
        let expectedJapanese = [
            "Suisui": "Suisui",
            "Welcome to Suisui": "Suisuiへようこそ",
            "Inbox": "受信箱",
            "Schedule": "スケジュール",
            "Add Task": "タスクを追加",
            "Quick Actions": "クイックアクション",
            "Search": "検索",
            "Completed": "完了",
            "Add by Voice": "音声で追加",
            "Block Time": "時間をブロック",
            "Navigate work or open a quick action.":
                "作業画面へ移動するか、クイックアクションを開きます。",
            "Opens the command palette.": "コマンドパレットを開きます。",
            "Creates a local schedule draft without writing Calendar.":
                "カレンダーへ書き込まず、ローカルのスケジュール下書きを作成します。",
            "No items today": "今日の項目はありません",
            "No projects": "プロジェクトはありません",
            "No scheduled items": "予定項目はありません",
            "No completed items": "完了済みの項目はありません",
            "Opens this section.": "このセクションを開きます。",
        ]

        for (key, value) in expectedEnglish {
            let entry = "\"\(key)\" = \"\(value)\";"
            XCTAssertEqual(
                english.components(separatedBy: "\"\(key)\" =").count - 1,
                1,
                "Expected one English localization key for \(key)"
            )
            XCTAssertTrue(english.contains(entry), "Unexpected English localization for \(key)")
        }
        for (key, value) in expectedJapanese {
            let entry = "\"\(key)\" = \"\(value)\";"
            XCTAssertEqual(
                japanese.components(separatedBy: "\"\(key)\" =").count - 1,
                1,
                "Expected one Japanese localization key for \(key)"
            )
            XCTAssertTrue(japanese.contains(entry), "Unexpected Japanese localization for \(key)")
        }

        let sidebar = try readPackageFile(
            "Sources/SuisuiApp/Views/ProjectBoardSidebarView.swift"
        )
        let brand = try sourceBlock(
            in: sidebar,
            from: "HStack(spacing: 8) {\n                Image(nsImage:",
            to: "Button(action: onOpenSearch)"
        )
        let search = try sourceBlock(
            in: sidebar,
            from: "Button(action: onOpenSearch)",
            to: "VStack(alignment: .leading, spacing: 1) {"
        )
        let root = try sourceBlock(
            in: sidebar,
            from: ".accessibilityIdentifier(\"project-board-sidebar\")",
            to: "private func sidebarRow("
        )
        let destinationRow = try sourceBlock(
            in: sidebar,
            from: "private func destinationSidebarRow(",
            to: "private func sidebarRowButton("
        )
        let sidebarRow = try sourceBlock(
            in: sidebar,
            from: "private func sidebarRowButton(",
            to: "private func quickAction("
        )
        let quickAction = try sourceBlock(
            in: sidebar,
            from: "private func quickAction(",
            to: "private func perform"
        )
        let countValue = try sourceBlock(
            in: sidebar,
            from: "private func countAccessibilityValue(",
            to: "private func accessibilityHintKey("
        )
        let brandText = try sourceBlock(
            in: brand,
            from: "Text(LocalizedStringKey(\"Suisui\"))",
            to: ".accessibilityElement(children: .ignore)"
        )
        let searchText = try sourceBlock(
            in: search,
            from: "Text(LocalizedStringKey(\"Search\"))",
            to: "Spacer()"
        )
        let sidebarRowText = try sourceBlock(
            in: sidebarRow,
            from: "Text(LocalizedStringKey(item.title))",
            to: "Spacer(minLength: 8)"
        )
        let quickActionText = try sourceBlock(
            in: quickAction,
            from: "Text(LocalizedStringKey(action.title))",
            to: "Spacer(minLength: 8)"
        )

        XCTAssertTrue(brand.contains("NSApplication.shared.applicationIconImage"))
        XCTAssertTrue(brand.contains(".accessibilityHidden(true)"))
        XCTAssertFalse(brandText.contains(".accessibilityHidden(true)"))
        XCTAssertTrue(brandText.contains(".foregroundStyle(Color.accentColor)"))

        XCTAssertTrue(search.contains("Image(systemName: \"magnifyingglass\")"))
        XCTAssertTrue(search.contains(".accessibilityHidden(true)"))
        XCTAssertFalse(searchText.contains(".accessibilityHidden(true)"))
        XCTAssertTrue(search.contains(".accessibilityLabel(Text(LocalizedStringKey(\"Search\")))"))
        XCTAssertTrue(
            search.contains(
                ".accessibilityHint(Text(LocalizedStringKey(\"Opens the command palette.\")))"
            )
        )
        XCTAssertTrue(search.contains(".help(LocalizedStringKey(\"Opens the command palette.\"))"))

        XCTAssertTrue(root.contains(".accessibilityLabel(Text(LocalizedStringKey(\"Project navigation\")))"))
        XCTAssertTrue(
            root.contains(
                ".accessibilityHint(Text(LocalizedStringKey(\"Navigate work or open a quick action.\")))"
            )
        )

        XCTAssertTrue(destinationRow.contains(".accessibilityAddTraits(isSelected ? .isSelected : [])"))
        XCTAssertTrue(
            destinationRow.contains(
                "hintKey: \"Opens this section.\""
            )
        )
        XCTAssertEqual(sidebar.components(separatedBy: "\"Opens this section.\"").count - 1, 1)
        XCTAssertFalse(destinationRow.contains("Navigate work or open a quick action."))
        XCTAssertTrue(sidebar.contains("case .route(let destination):"))
        XCTAssertTrue(sidebar.contains("route = destination"))
        XCTAssertFalse(sidebar.contains("preconditionFailure"))
        XCTAssertFalse(sidebarRow.contains(".accessibilityAddTraits"))
        XCTAssertEqual(sidebar.components(separatedBy: ".accessibilityAddTraits").count - 1, 1)

        XCTAssertTrue(sidebarRow.contains("Image(systemName: item.systemImage)"))
        XCTAssertTrue(sidebarRow.contains(".accessibilityHidden(true)"))
        XCTAssertFalse(sidebarRowText.contains(".accessibilityHidden(true)"))
        XCTAssertTrue(sidebarRow.contains(".accessibilityLabel(Text(LocalizedStringKey(item.title)))"))
        XCTAssertTrue(sidebarRow.contains(".accessibilityValue(countAccessibilityValue(for: item.id))"))
        XCTAssertTrue(sidebarRow.contains(".accessibilityIdentifier(accessibilityIdentifier(for: item.id))"))
        XCTAssertTrue(sidebarRow.contains(".accessibilityHint(Text(LocalizedStringKey(hintKey)))"))
        XCTAssertTrue(sidebarRow.contains(".help(LocalizedStringKey(hintKey))"))
        XCTAssertTrue(sidebarRow.contains(".foregroundStyle(isSelected ? Color.white : Color.primary)"))
        XCTAssertTrue(sidebarRow.contains(".fill(isSelected ? Color.accentColor : .clear)"))

        XCTAssertTrue(quickAction.contains("Image(systemName: action.systemImage)"))
        XCTAssertTrue(quickAction.contains("Image(systemName: \"plus\")"))
        XCTAssertTrue(quickAction.contains(".accessibilityHidden(true)"))
        XCTAssertFalse(quickActionText.contains(".accessibilityHidden(true)"))
        XCTAssertFalse(quickAction.contains(".accessibilityElement(children: .ignore)"))
        XCTAssertTrue(quickAction.contains(".accessibilityLabel(Text(LocalizedStringKey(action.title)))"))
        XCTAssertTrue(
            quickAction.contains(
                ".accessibilityHint(Text(LocalizedStringKey(accessibilityHintKey(for: action))))"
            )
        )
        XCTAssertTrue(quickAction.contains(".help(LocalizedStringKey(accessibilityHintKey(for: action)))"))
        XCTAssertFalse(quickAction.contains(".accessibilityAddTraits"))
        XCTAssertTrue(sidebar.contains("Text(LocalizedStringKey(\"Quick Actions\"))"))
        XCTAssertTrue(sidebar.contains(".suisuiLiquidGlassControlSurface(cornerRadius: 12)"))

        XCTAssertTrue(
            sidebar.contains(
                "case .blockTime:\n            \"Creates a local schedule draft without writing Calendar.\""
            )
        )
        XCTAssertTrue(
            sidebar.contains(
                "case .importTasks:\n            \"Imports tasks from a local JSON file.\""
            )
        )
        for mapping in [
            "case .inbox: localizedDisplay(\"No pending items\")",
            "case .today: localizedDisplay(\"No items today\")",
            "case .projects: localizedDisplay(\"No projects\")",
            "case .schedule: localizedDisplay(\"No scheduled items\")",
            "case .completed: localizedDisplay(\"No completed items\")",
        ] {
            XCTAssertTrue(countValue.contains(mapping), "Missing zero-count mapping: \(mapping)")
        }
        XCTAssertTrue(
            countValue.contains("localizedCount(count, one: \"%d item\", other: \"%d items\")")
        )
    }

    func testAppLocalizationsContainNoDuplicateKeys() throws {
        for path in [
            "Sources/SuisuiApp/Resources/en.lproj/Localizable.strings",
            "Sources/SuisuiApp/Resources/ja.lproj/Localizable.strings",
        ] {
            let occurrences = try localizableKeyOccurrences(in: path)
            let duplicateKeys = occurrences
                .filter { $0.value > 1 }
                .map(\.key)
                .sorted()

            XCTAssertEqual(duplicateKeys, [], "Duplicate localization keys in \(path)")
        }
    }

    func testSidebarVoiceEntrypointsShareSelectedBoardConversationContext() throws {
        let boardSource = try readPackageFile(
            "Sources/SuisuiApp/Views/ProjectBoardView.swift"
        )
        let sidebarCallStart = try XCTUnwrap(
            boardSource.range(of: "ProjectBoardSidebarView(")
        )
        let sidebarCallEnd = try XCTUnwrap(
            boardSource.range(
                of: ".id(toolbarLayoutRefreshToken)",
                range: sidebarCallStart.upperBound..<boardSource.endIndex
            )
        )
        let sidebarCall = String(
            boardSource[sidebarCallStart.lowerBound..<sidebarCallEnd.lowerBound]
        )
        let helperStart = try XCTUnwrap(
            boardSource.range(of: "private func openVoiceCommandFromBoardContext()")
        )
        let helperEnd = try XCTUnwrap(
            boardSource.range(
                of: "private func ",
                range: helperStart.upperBound..<boardSource.endIndex
            )
        )
        let helper = String(boardSource[helperStart.lowerBound..<helperEnd.lowerBound])

        XCTAssertTrue(helper.contains("let task = viewModel.selectedTask"))
        XCTAssertTrue(
            helper.contains("let projectID = task?.projectID ?? viewModel.selectedProject?.id")
        )
        XCTAssertTrue(
            helper.contains("viewModel.snapshot.projects.first { $0.id == projectID }")
        )
        XCTAssertTrue(helper.contains("projectID: projectID"))
        XCTAssertTrue(helper.contains("projectName: project?.title"))
        XCTAssertTrue(helper.contains("taskID: task?.id"))
        XCTAssertTrue(helper.contains("taskName: task?.title"))
        let store = try XCTUnwrap(
            helper.range(of: "SuisuiVoiceConversationScopeBridge.store(")
        )
        let navigate = try XCTUnwrap(
            helper.range(of: "navigateWithinScene(to: .voiceCommand)")
        )
        XCTAssertLessThan(store.lowerBound, navigate.lowerBound)
        XCTAssertTrue(
            helper.contains("name: .suisuiVoiceConversationScopeRequested")
        )
        XCTAssertTrue(helper.contains("NotificationCenter.default.post("))
        XCTAssertFalse(
            sidebarCall.contains("onOpenVoiceCommand: openVoiceCommandFromBoardContext")
        )
        XCTAssertTrue(
            sidebarCall.contains("onAddByVoice: openVoiceCommandFromBoardContext")
        )
        XCTAssertEqual(
            boardSource.components(
                separatedBy: "onOpenVoiceCommand: openVoiceCommandFromBoardContext"
            ).count - 1,
            0
        )
        XCTAssertEqual(
            boardSource.components(
                separatedBy: "onAddByVoice: openVoiceCommandFromBoardContext"
            ).count - 1,
            1
        )
    }

    func testSidebarAddTaskRequestsFocusBeforeNavigatingToInbox() throws {
        let boardSource = try readPackageFile(
            "Sources/SuisuiApp/Views/ProjectBoardView.swift"
        )
        let helperStart = try XCTUnwrap(
            boardSource.range(of: "private func beginInboxQuickAddFromSidebar()")
        )
        let helperEnd = try XCTUnwrap(
            boardSource.range(
                of: "private func ",
                range: helperStart.upperBound..<boardSource.endIndex
            )
        )
        let helper = String(boardSource[helperStart.lowerBound..<helperEnd.lowerBound])
        let focusRequest = try XCTUnwrap(
            helper.range(of: "requestsInboxQuickAddFocus = true")
        )
        let navigation = try XCTUnwrap(
            helper.range(of: "navigateWithinScene(to: .primary(.inbox))")
        )

        XCTAssertLessThan(focusRequest.lowerBound, navigation.lowerBound)
    }

    func testSidebarBlockTimeOnlyPreparesALocalScheduleDraft() throws {
        let boardSource = try readPackageFile(
            "Sources/SuisuiApp/Views/ProjectBoardView.swift"
        )
        let start = try XCTUnwrap(
            boardSource.range(of: "private func prepareScheduleDraftFromSidebar()")
        )
        let end = try XCTUnwrap(
            boardSource.range(
                of: "private func ",
                range: start.upperBound..<boardSource.endIndex
            )
        )
        let helper = String(boardSource[start.lowerBound..<end.lowerBound])

        XCTAssertTrue(helper.contains("navigateWithinScene(to: .review(.schedule))"))
        XCTAssertTrue(
            helper.contains(
                "viewModel.prepareScheduleDraft(on: VisualEvidenceRuntimeContext.referenceDate())"
            )
        )
        XCTAssertEqual(
            helper.components(separatedBy: "viewModel.prepareScheduleDraft(").count - 1,
            1
        )
        XCTAssertEqual(helper.components(separatedBy: "viewModel.").count - 1, 1)
        XCTAssertFalse(helper.contains("enqueueScheduleDraftCalendarApply"))
        XCTAssertFalse(helper.contains("applyScheduleDraftToCalendar"))
    }

    func testInboxQuickAddFocusRequestIsConsumedExactlyOnce() throws {
        let boardSource = try readPackageFile(
            "Sources/SuisuiApp/Views/ProjectBoardView.swift"
        )
        let inboxSource = try readPackageFile(
            "Sources/SuisuiApp/Views/ProjectWorkflowInboxView.swift"
        )

        XCTAssertTrue(boardSource.contains("@State private var requestsInboxQuickAddFocus = false"))
        XCTAssertTrue(boardSource.contains("requestsQuickAddFocus: requestsInboxQuickAddFocus"))
        XCTAssertTrue(boardSource.contains("requestsInboxQuickAddFocus = true"))
        XCTAssertTrue(boardSource.contains("requestsInboxQuickAddFocus = false"))

        XCTAssertTrue(inboxSource.contains("let requestsQuickAddFocus: Bool"))
        XCTAssertTrue(inboxSource.contains("let onQuickAddFocusConsumed: () -> Void"))
        XCTAssertTrue(inboxSource.contains("@FocusState private var isQuickAddFocused: Bool"))
        XCTAssertTrue(inboxSource.contains("isFocused: $isQuickAddFocused"))
        XCTAssertTrue(inboxSource.contains(".focused($isFocused)"))

        let helperStart = try XCTUnwrap(
            inboxSource.range(of: "private func consumeQuickAddFocusRequestIfNeeded()")
        )
        let helperEnd = try XCTUnwrap(
            inboxSource.range(
                of: "\n}\n\nprivate enum InboxSortOrder",
                range: helperStart.upperBound..<inboxSource.endIndex
            )
        )
        let helper = String(inboxSource[helperStart.lowerBound..<helperEnd.lowerBound])
        XCTAssertTrue(helper.contains("guard requestsQuickAddFocus else"))
        let focus = try XCTUnwrap(helper.range(of: "isQuickAddFocused = true"))
        let consume = try XCTUnwrap(helper.range(of: "onQuickAddFocusConsumed()"))
        XCTAssertLessThan(focus.lowerBound, consume.lowerBound)
        XCTAssertEqual(
            helper.components(separatedBy: "onQuickAddFocusConsumed()").count - 1,
            1
        )
        XCTAssertFalse(helper.contains("private enum InboxSortOrder"))

        let onAppearStart = try XCTUnwrap(inboxSource.range(of: ".onAppear {"))
        let onAppearEnd = try XCTUnwrap(
            inboxSource.range(
                of: ".onChange(of: requestsQuickAddFocus)",
                range: onAppearStart.upperBound..<inboxSource.endIndex
            )
        )
        let onAppear = String(inboxSource[onAppearStart.lowerBound..<onAppearEnd.lowerBound])
        XCTAssertEqual(
            onAppear.components(separatedBy: "consumeQuickAddFocusRequestIfNeeded()").count - 1,
            1
        )

        let onChangeStart = onAppearEnd
        let onChangeEnd = try XCTUnwrap(
            inboxSource.range(
                of: ".onChange(of: tasks.map(\\.id))",
                range: onChangeStart.upperBound..<inboxSource.endIndex
            )
        )
        let onChange = String(inboxSource[onChangeStart.lowerBound..<onChangeEnd.lowerBound])
        XCTAssertEqual(
            onChange.components(separatedBy: "consumeQuickAddFocusRequestIfNeeded()").count - 1,
            1
        )
    }

    func testTodayCatchUpDisplayExpansionAndAccessibilityFocusContract() throws {
        let todaySource = try readPackageFile(
            "Sources/SuisuiApp/Views/ProjectWorkflowTodayView.swift"
        )

        XCTAssertTrue(todaySource.contains("viewModel.catchUpCount > 0"))
        XCTAssertTrue(todaySource.contains("today-catch-up-section"))
        XCTAssertTrue(todaySource.contains("@AccessibilityFocusState private var isCatchUpFocused"))
        XCTAssertTrue(todaySource.contains("catchUpFocusRevision"))
        XCTAssertTrue(todaySource.contains("_isCatchUpExpanded = State(initialValue: initiallyExpandsCatchUp)"))
        XCTAssertTrue(todaySource.contains("isCatchUpExpanded = true"))
        XCTAssertTrue(todaySource.contains(".accessibilityFocused($isCatchUpFocused)"))
        XCTAssertTrue(todaySource.contains(".onChange(of: viewModel.catchUpCount)"))
    }

    func testTodayCatchUpRecommendationLeavesFocusToCatchUpSection() throws {
        let dashboardSource = try readPackageFile(
            "Sources/SuisuiApp/Views/TodayDashboardView.swift"
        )
        let actionStart = try XCTUnwrap(dashboardSource.range(of: "case .openCatchUp:"))
        let actionEnd = try XCTUnwrap(
            dashboardSource.range(of: "case .suggestBreak:", range: actionStart.upperBound..<dashboardSource.endIndex)
        )
        let action = dashboardSource[actionStart.lowerBound..<actionEnd.lowerBound]

        XCTAssertTrue(action.contains("openCatchUp()"))
        XCTAssertFalse(action.contains("isReviewFocused = true"))
    }

    func testLegacyCatchUpFocusIsResolvedAndConsumedWithinOneBoardScene() throws {
        let boardSource = try readPackageFile(
            "Sources/SuisuiApp/Views/ProjectBoardView.swift"
        )

        XCTAssertTrue(boardSource.contains("@State private var catchUpFocusRevision = 0"))
        XCTAssertTrue(boardSource.contains("@State private var activeBoardRouteFocus: BoardRouteFocus?"))
        XCTAssertTrue(boardSource.contains("ProjectBoardRouteCodec.resolution("))
        XCTAssertTrue(boardSource.contains("ProjectBoardScenePersistence.restoredResolution("))
        XCTAssertTrue(boardSource.contains("applyRouteFocus(resolution.focus)"))
        XCTAssertTrue(boardSource.contains("catchUpFocusRevision += 1"))
        XCTAssertTrue(boardSource.contains("catchUpFocusRevision: catchUpFocusRevision"))
        XCTAssertTrue(boardSource.contains("initiallyExpandsCatchUp: activeBoardRouteFocus == .catchUp"))
        XCTAssertTrue(boardSource.contains("|| currentBoardRouteResolution.focus == .catchUp"))
    }

    func testCommandPaletteUsesTypedSceneNavigationAndPreservesCatchUpFocus() throws {
        let boardSource = try readPackageFile(
            "Sources/SuisuiApp/Views/ProjectBoardView.swift"
        )
        let start = try XCTUnwrap(
            boardSource.range(of: "private func executeCommandPaletteAction")
        )
        let end = try XCTUnwrap(
            boardSource.range(
                of: "private func revealTaskFromCommandPalette",
                range: start.lowerBound..<boardSource.endIndex
            )
        )
        let block = String(boardSource[start.lowerBound..<end.lowerBound])

        XCTAssertTrue(
            block.contains(
                "navigateWithinScene(to: .primary(.today), focus: .catchUp)"
            )
        )
        XCTAssertTrue(block.contains("navigateWithinScene(to: typedRoute(for: destination))"))
        XCTAssertTrue(block.contains("navigateWithinScene(to: .project(projectID))"))
        XCTAssertFalse(block.contains("selectedDestination = destination"))
        XCTAssertFalse(block.contains("selectedDestination = .project(projectID)"))
    }

    func testBoardRoutePriorityAndFocusCancellationAreDeterministic() throws {
        let source = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardView.swift")
        let transient = try XCTUnwrap(source.range(of: "if let transientBoardRoute"))
        let environment = try XCTUnwrap(
            source.range(
                of: "ProjectBoardSelectionPersistence.environmentOverrideRawValue",
                range: transient.lowerBound..<source.endIndex
            )
        )
        let scene = try XCTUnwrap(
            source.range(
                of: "if !currentSceneRouteRawValue.isEmpty",
                range: transient.lowerBound..<source.endIndex
            )
        )
        XCTAssertLessThan(transient.lowerBound, environment.lowerBound)
        XCTAssertLessThan(environment.lowerBound, scene.lowerBound)
        XCTAssertTrue(source.contains("cancelRouteFocus()"))
        XCTAssertTrue(source.contains("activeBoardRouteFocus == .catchUp"))
        XCTAssertTrue(source.contains("catchUpFocusRevision == revision"))
    }

    func testVoiceDailyPlanningUsesTypedRouteForCatchUpAndQueueOutcomes() throws {
        let source = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardView.swift")
        let start = try XCTUnwrap(source.range(of: "private func handleVoiceDailyPlanningReviewRequest(\n        sourceTranscript:"))
        let end = try XCTUnwrap(source.range(of: "private func playDailyPlanningReadoutFromSettings", range: start.lowerBound..<source.endIndex))
        let block = String(source[start.lowerBound..<end.lowerBound])

        XCTAssertTrue(block.contains("to: .review(.assistantQueue),"))
        XCTAssertTrue(block.contains("navigateToTodayForDailyPlanning(summary: summary)"))
        XCTAssertTrue(block.contains("focus: summary.newlyMissedCount > 0 ? .catchUp : nil"))
        XCTAssertFalse(block.contains("applyLegacyDestinationWithinScene"))
    }

    func testNestedHubsUseCompactPresentationPolicyAtNarrowWidths() throws {
        let projects = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardProjectsHubView.swift")
        let review = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardReviewHubView.swift")

        for source in [projects, review] {
            XCTAssertTrue(source.contains("GeometryReader"))
            XCTAssertTrue(source.contains("ProjectBoardHubPresentationPolicy.presentation"))
            XCTAssertTrue(source.contains("case .compact:"))
            XCTAssertTrue(source.contains("case .wide:"))
        }
        XCTAssertTrue(projects.contains("projects-hub-compact-navigation"))
        XCTAssertTrue(review.contains("review-hub-compact-navigation"))
        XCTAssertTrue(review.contains("review-hub-compact-destination-assistant-queue"))
    }

    func testCompactProjectsHubPreservesWideNavigationAndActionParity() throws {
        let source = try readPackageFile(
            "Sources/SuisuiApp/Views/ProjectBoardProjectsHubView.swift"
        )
        let start = try XCTUnwrap(source.range(of: "private var compactNavigation: some View"))
        let end = try XCTUnwrap(
            source.range(
                of: "private var selectedCustomSmartList:",
                range: start.lowerBound..<source.endIndex
            )
        )
        let block = String(source[start.lowerBound..<end.lowerBound])

        XCTAssertTrue(block.contains("route = .primary(.projects)"))
        XCTAssertTrue(block.contains("ForEach(smartLists)"))
        XCTAssertTrue(block.contains("route = .smartList(smartList.id)"))
        XCTAssertTrue(block.contains("ForEach(activeProjects)"))
        XCTAssertTrue(block.contains("ForEach(completedProjects)"))
        XCTAssertTrue(block.contains("if showsArchivedProjects,"))
        XCTAssertTrue(block.contains("ForEach(archivedProjects)"))
        XCTAssertTrue(block.contains("onCreateSmartList"))
        XCTAssertTrue(block.contains("onToggleArchivedProjects"))
        XCTAssertTrue(block.contains("\"Hide Archived\" : \"Show Archived\""))
        XCTAssertTrue(block.contains("onCreateProject"))
        XCTAssertTrue(block.contains("if let selectedCustomSmartList"))
        XCTAssertTrue(block.contains("onDeleteSmartList(selectedCustomSmartList)"))
        XCTAssertTrue(block.contains("role: .destructive"))
        XCTAssertTrue(block.contains("Delete Selected Smart List"))
        XCTAssertTrue(block.contains("projects-hub-compact-new-smart-list"))
        XCTAssertTrue(block.contains("projects-hub-compact-toggle-archived"))
        XCTAssertTrue(block.contains("projects-hub-compact-delete-smart-list"))
        XCTAssertTrue(block.contains("projects-hub-compact-add-project"))
    }

    func testCompactHubLabelsUseTypedPresentationAndPreserveDestinationParity() throws {
        let review = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardReviewHubView.swift")
        let projects = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardProjectsHubView.swift")

        let reviewCompactStart = try XCTUnwrap(
            review.range(of: "private var compactNavigation")
        )
        let reviewCompactEnd = try XCTUnwrap(
            review.range(
                of: "private func compactDestination",
                range: reviewCompactStart.upperBound..<review.endIndex
            )
        )
        let reviewCompact = String(
            review[reviewCompactStart.lowerBound..<reviewCompactEnd.lowerBound]
        )
        let projectsCompactStart = try XCTUnwrap(
            projects.range(of: "private var compactNavigation")
        )
        let projectsCompactEnd = try XCTUnwrap(
            projects.range(
                of: "private var selectedCustomSmartList",
                range: projectsCompactStart.upperBound..<projects.endIndex
            )
        )
        let projectsCompact = String(
            projects[projectsCompactStart.lowerBound..<projectsCompactEnd.lowerBound]
        )

        XCTAssertTrue(
            reviewCompact.contains("ProjectBoardCompactNavigationPresentation.review(")
        )
        XCTAssertTrue(
            projectsCompact.contains("ProjectBoardCompactNavigationPresentation.projects(")
        )
        XCTAssertTrue(reviewCompact.contains("compactLabel(presentation)"))
        XCTAssertTrue(projectsCompact.contains("compactLabel(presentation)"))
        XCTAssertTrue(reviewCompact.contains("case .localized"))
        XCTAssertTrue(reviewCompact.contains("case .verbatim"))
        XCTAssertTrue(projectsCompact.contains("case .localized"))
        XCTAssertTrue(projectsCompact.contains("case .verbatim"))
        XCTAssertTrue(reviewCompact.contains(".help(\"Choose Review destination.\")"))
        XCTAssertTrue(projectsCompact.contains(".help(\"Choose Project destination.\")"))
        XCTAssertTrue(reviewCompact.contains("\"%d item needs attention\""))
        XCTAssertTrue(reviewCompact.contains("\"%d items need attention\""))
        XCTAssertFalse(reviewCompact.contains("Label(\"Choose Review View\""))
        XCTAssertFalse(projectsCompact.contains("Label(\"Choose Project View\""))

        for identifier in [
            "review-hub-compact-destination-schedule",
            "review-hub-compact-destination-completed",
            "review-hub-compact-destination-automation-activity",
            "review-hub-compact-destination-assistant-queue"
        ] {
            XCTAssertTrue(review.contains(identifier))
        }
    }

    func testProjectsAndReviewHubsExposeRelocatedDestinations() throws {
        let projectsSource = try readPackageFile(
            "Sources/SuisuiApp/Views/ProjectBoardProjectsHubView.swift"
        )
        let reviewSource = try readPackageFile(
            "Sources/SuisuiApp/Views/ProjectBoardReviewHubView.swift"
        )

        XCTAssertTrue(projectsSource.contains("projects-hub-portfolio"))
        XCTAssertTrue(projectsSource.contains("projects-hub-smart-lists"))
        XCTAssertTrue(projectsSource.contains("projects-hub-active"))
        XCTAssertTrue(projectsSource.contains("projects-hub-completed"))
        XCTAssertTrue(projectsSource.contains("projects-hub-archived"))

        XCTAssertTrue(reviewSource.contains("review-hub"))
        XCTAssertTrue(reviewSource.contains("review-destination-schedule"))
        XCTAssertTrue(reviewSource.contains("review-destination-completed"))
        XCTAssertTrue(reviewSource.contains("review-destination-automation-activity"))
        XCTAssertTrue(reviewSource.contains("review-destination-assistant-queue"))
        XCTAssertTrue(reviewSource.contains("review-hub-compact-destination-assistant-queue"))
    }

    func testEvidenceRouteOverrideRemainsProcessLocalWhileNavigationStaysTyped() throws {
        let boardSource = try readPackageFile(
            "Sources/SuisuiApp/Views/ProjectBoardView.swift"
        )

        XCTAssertTrue(boardSource.contains("@State private var transientBoardRoute: BoardRoute?"))
        XCTAssertTrue(boardSource.contains("private var boardRouteBinding: Binding<BoardRoute>"))
        XCTAssertTrue(boardSource.contains("guard ProjectBoardSelectionPersistence.environmentOverrideRawValue == nil else"))
        XCTAssertTrue(boardSource.contains("transientBoardRoute = route"))
        XCTAssertTrue(boardSource.contains("never rewrite SceneStorage"))
    }

    func testProjectBoardSurfaceReaderFindsAnchorsAcrossOwnedFiles() throws {
        let source = try readProjectBoardSurfaceSources()

        XCTAssertTrue(source.contains("project-board-sidebar"))
        XCTAssertTrue(source.contains("today-workflow"))
        XCTAssertTrue(source.contains("task-inspector-save"))
    }

    func testProjectBoardPhysicalOwnerReaderExcludesRelocatedSurfaceFiles() throws {
        let source = try readProjectBoardOwnerSource()

        XCTAssertFalse(source.contains(".accessibilityIdentifier(\"project-inspector\")"))
        XCTAssertTrue(source.contains("@SceneStorage(\"projectBoard.userRequestedInspector\") private var userRequestedInspector"))
        XCTAssertTrue(source.contains("private var wideInspectorBinding: Binding<Bool>"))
        XCTAssertFalse(source.contains("today-workflow"))
    }

    func testAppLaunchesProjectBoardBeforeVoiceCaptureWindow() throws {
        let source = try readAppShellSource()

        XCTAssertTrue(source.contains("WindowGroup(\"Suisui\", id: \"project-board\")"))
        XCTAssertTrue(source.contains("VoiceCaptureWorkspaceHost()"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"voice-capture-loading\")"))
        XCTAssertTrue(source.contains("SuisuiSettingsWorkspace("))
        XCTAssertFalse(source.contains("SettingsWindowRootView("))
        XCTAssertFalse(source.contains("VoiceCaptureWindowRootView("))
        XCTAssertFalse(source.contains("Window(\"Voice Command\", id: \"voice-capture\")"))
    }

    func testRecordFlowDoesNotInjectCannedPhaseOneTranscript() throws {
        let source = try readAppShellSource()

        XCTAssertFalse(source.contains("Create a task to review the Suisui Phase 1 UI"))
    }

    func testAVFoundationAudioRecorderRedactsSystemErrorMessages() throws {
        let source = try readPackageFile("Sources/SuisuiApp/Adapters/AVFoundationAudioRecorder.swift")

        XCTAssertEqual(source.components(separatedBy: "UserFacingErrorMessageSanitizer.message(").count - 1, 2)
        XCTAssertEqual(source.components(separatedBy: "from: error").count - 1, 2)
        XCTAssertFalse(source.contains("state = .failed(error.localizedDescription)"))
        XCTAssertFalse(source.contains("throw AudioRecorderError.failed(error.localizedDescription)"))
    }

    func testAVFoundationAudioRecorderRequestsFirstRunMicrophoneAccess() throws {
        let source = try readPackageFile("Sources/SuisuiApp/Adapters/AVFoundationAudioRecorder.swift")
        let notDeterminedRange = try XCTUnwrap(source.range(of: "case .notDetermined:"))
        let unknownRange = try XCTUnwrap(source.range(of: "@unknown default:", range: notDeterminedRange.upperBound..<source.endIndex))
        let notDeterminedBlock = source[notDeterminedRange.lowerBound..<unknownRange.lowerBound]

        XCTAssertTrue(notDeterminedBlock.contains("state = .requestingPermission"))
        XCTAssertTrue(notDeterminedBlock.contains("await requestMicrophoneAccess()"))
        XCTAssertTrue(source.contains("AVCaptureDevice.requestAccess(for: .audio)"))
    }

    func testProjectBoardSurfaceUsesKanbanLayout() throws {
        let source = try readProjectBoardSurfaceSources()
        let modelSource = try readPackageFile("Sources/SuisuiCore/WorkManagement/WorkManagementModels.swift")

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
        let source = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardView.swift")

        XCTAssertTrue(source.contains("Project Board Unavailable"))
        XCTAssertTrue(source.contains("case .fatal(let message, let canRetry) = viewModel.errorPresentation"))
        XCTAssertFalse(source.contains("if let errorMessage = viewModel.errorMessage {\n                        ContentUnavailableView"))
        XCTAssertTrue(source.contains("isEmptyProjectStateVisible"))
        let unavailableRange = try XCTUnwrap(source.range(of: "Project Board Unavailable"))
        let noProjectsRange = try XCTUnwrap(source.range(of: "No Projects"))
        XCTAssertLessThan(unavailableRange.lowerBound, noProjectsRange.lowerBound)
    }

    func testTaskInspectorUsesNativeOptionalDateEditingAndRecoverableSaveFeedback() throws {
        let source = try readProjectBoardSurfaceSources()
        let modelSource = try readPackageFile("Sources/SuisuiCore/App/ProjectBoard.swift")
        let taskInspector = try sourceBlock(
            in: source,
            from: "struct TaskInspectorView: View",
            to: "private struct TaskInspectorSuggestionSection"
        )

        XCTAssertTrue(taskInspector.contains("TaskDueDateFieldState"))
        XCTAssertTrue(taskInspector.contains("DatePicker("))
        XCTAssertTrue(taskInspector.contains("task-inspector-due-clear"))
        XCTAssertTrue(taskInspector.contains("task-inspector-save-error"))
        XCTAssertTrue(taskInspector.contains("task-inspector-save-retry"))
        XCTAssertFalse(taskInspector.contains("TextField(\"Due\""))
        XCTAssertFalse(taskInspector.contains("QuickAddDueDateParser"))
        XCTAssertTrue(taskInspector.contains("TaskDueDateFieldState.parsePersisted"))
        XCTAssertFalse(taskInspector.contains("ISO8601DateFormatter"))
        XCTAssertTrue(taskInspector.contains("dueDate: dueDate.persistedDate"))
        XCTAssertTrue(modelSource.contains("UserFacingErrorMessageSanitizer.message("))
        XCTAssertTrue(modelSource.contains("failure = .saveFailed(redactedMessage)"))
        XCTAssertTrue(source.contains("project-board-inline-error-retry"))
        XCTAssertTrue(source.contains("viewModel.rootErrorPresentation"))
        XCTAssertTrue(source.contains("viewModel.failureActionLabel"))
        XCTAssertTrue(taskInspector.contains("VStack(spacing: 0)"))
        XCTAssertTrue(taskInspector.contains(".accessibilityIdentifier(\"task-inspector-save-error\")"))
        XCTAssertFalse(taskInspector.contains(".accessibilityElement(children: .contain)\n                .accessibilityIdentifier(\"task-inspector-save-error\")"))
        XCTAssertFalse(taskInspector.contains(".safeAreaInset(edge: .top"))
    }

    func testProjectBoardRetryContextsMapBackToTheirOriginalOperations() throws {
        let source = try readPackageFile("Sources/SuisuiCore/App/ProjectBoard.swift")

        let expectedMappings = [
            "case .createTask(let draft):": "_ = createTask(",
            "case .createProject(let title):": "_ = createProject(title: title)",
            "case .updateProject(let id, let title):": "updateSelectedProject(title: title)",
            "case .completeProject(let id):": "completeSelectedProject()",
            "case .archiveProject(let id):": "archiveSelectedProject()",
            "case .restoreProject(let id):": "restoreSelectedProject()",
            "case .deleteProject(let id):": "deleteSelectedProject()",
            "case .deleteTask(let id):": "deleteSelectedTask()",
            "case .moveTask(let id, let status):": "moveTask(id: id, to: status)",
            "case .syncGoogleCalendar(let approvalToken):": "syncDueTasksToGoogleCalendar(approvalToken: approvalToken)"
        ]

        for (retryCase, originalOperation) in expectedMappings {
            let caseRange = try XCTUnwrap(source.range(of: retryCase))
            let operationRange = try XCTUnwrap(source.range(of: originalOperation, range: caseRange.lowerBound..<source.endIndex))
            XCTAssertLessThan(source.distance(from: caseRange.lowerBound, to: operationRange.lowerBound), 500)
        }
        XCTAssertFalse(source.contains("undoLastInboxClassification") && source.contains("retryAction: .deleteTask(id: selectedTaskID)\n            )\n        }\n    }\n\n    public var canUndoBoardOperation"))
    }

    func testProjectBoardRecoverableMessagesHaveEnglishAndJapaneseLocalizations() throws {
        let coreSource = try readPackageFile("Sources/SuisuiCore/App/ProjectBoard.swift")
        let english = try readPackageFile("Sources/SuisuiApp/Resources/en.lproj/Localizable.strings")
        let japanese = try readPackageFile("Sources/SuisuiApp/Resources/ja.lproj/Localizable.strings")
        let messages = [
            "Restore the project before adding tasks.",
            "Restore the project before editing tasks.",
            "Restore the project before moving tasks.",
            "Task title is required.",
            "Project title is required.",
            "Google Calendar sync requires approval before writing events.",
            "Google Calendar sync status is unavailable.",
            "Google Calendar sync failed."
        ]

        for message in messages {
            XCTAssertTrue(coreSource.contains("String(localized: \"\(message)\")"), "Core must localize \(message)")
            XCTAssertTrue(english.contains("\"\(message)\" = "), "English is missing \(message)")
            XCTAssertTrue(japanese.contains("\"\(message)\" = "), "Japanese is missing \(message)")
        }
    }

    func testProjectBoardUsesResponsiveLongContentGuards() throws {
        let source = try readProjectBoardSurfaceSources()

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
        let surfaceSource = try readProjectBoardSurfaceSources()
        let source = try taskInspectorRefreshContract(in: surfaceSource)

        XCTAssertTrue(source.contains(".onChange(of: task)"))
        XCTAssertTrue(source.contains("refreshFields(from: task)"))
        XCTAssertFalse(source.contains(".onChange(of: task.id)"))
    }

    func testTaskInspectorRefreshContractExtractionSurvivesOwnedFileRelocationOrder() throws {
        let relocatedSurfaceSource = """
        private struct InspectorDestructiveConfirmation: View {}

        struct TaskInspectorView: View {
            var body: some View {
                Text("Task")
                    .onAppear {
                        refreshFields(from: task)
                    }
                    .onChange(of: task) { _, newTask in
                        refreshFields(from: newTask)
                    }
            }

            private func refreshFields(from task: ProjectBoardTask) {}
            private func deleteSelectedTaskAfterConfirmationDismissal() {}
        }
        """

        let source = try taskInspectorRefreshContract(in: relocatedSurfaceSource)

        XCTAssertTrue(source.contains(".onChange(of: task)"))
        XCTAssertTrue(source.contains("refreshFields(from: task)"))
        XCTAssertFalse(source.contains("InspectorDestructiveConfirmation"))
    }

    func testProjectBoardUsesPersistentViewModelInsteadOfStaticSnapshot() throws {
        let appSource = try readAppShellSource()
        let boardSource = try readProjectBoardSurfaceSources()

        XCTAssertTrue(appSource.contains("prepareProjectBoardRuntimeBundle()"))
        XCTAssertTrue(appSource.contains("makeProjectBoardViewModel(runtime: runtime)"))
        XCTAssertFalse(appSource.contains("makeProjectBoardSnapshot()"))
        XCTAssertTrue(boardSource.contains("@StateObject private var viewModel: ProjectBoardViewModel"))
        XCTAssertTrue(boardSource.contains("createTask("))
    }

    func testTodayProductionRouteSmokeCoversNormalBoardDestinationMatrix() throws {
        let script = try readPackageFile("script/check_runtime_today_production_route_smoke.sh")
        let appSource = try readPackageFile("Sources/SuisuiApp/SuisuiApp.swift")
        let normalRoutesStart = try XCTUnwrap(script.range(of: "run_normal_routes() {"))
        let normalRoutesEnd = try XCTUnwrap(
            script.range(
                of: "\n}\n\ncpu_percent_for_app()",
                range: normalRoutesStart.upperBound..<script.endIndex
            )
        )
        let normalRoutesSource = String(script[normalRoutesStart.lowerBound..<normalRoutesEnd.upperBound])
        let routesStart = try XCTUnwrap(normalRoutesSource.range(of: "local routes=("))
        let routesEnd = try XCTUnwrap(
            normalRoutesSource.range(
                of: "\n  )",
                range: routesStart.upperBound..<normalRoutesSource.endIndex
            )
        )
        let routesSource = String(normalRoutesSource[routesStart.upperBound..<routesEnd.lowerBound])
        let routeRows = try bashArrayStringPayloads(in: routesSource)

        XCTAssertTrue(script.contains("run_route()"))
        XCTAssertEqual(
            routeRows,
            [
                "inbox|inbox|sidebar-destination-inbox|inbox-workflow",
                "today|today|sidebar-destination-today|today-workflow",
                "review|primary:review|sidebar-destination-schedule|review-hub",
                "review-schedule|review:schedule|sidebar-destination-schedule|schedule-workflow",
                "review-completed|review:completed|sidebar-destination-completed|done-workflow",
                "review-automation|review:automation|sidebar-destination-schedule|automation-activity-workflow",
                "review-assistant-queue|review:assistant-queue|sidebar-destination-schedule|assistant-queue-workflow",
                "projects|projects|sidebar-destination-projects|projects-portfolio-overview",
            ]
        )
        XCTAssertEqual(routeRows.count, 8)
        XCTAssertThrowsError(try bashArrayStringPayloads(in: routesSource + "\n  unquoted-extra"))
        XCTAssertEqual(
            try bashArrayStringPayloads(in: #"  "route-with-\"escaped-quote\"""#),
            [#"route-with-\"escaped-quote\""#]
        )
        XCTAssertTrue(script.contains(#"review-automation:en) printf '%s' "Automation Activity""#))
        XCTAssertTrue(script.contains(#"review-automation:ja) printf '%s' "自動化アクティビティ""#))
        XCTAssertFalse(routeRows.contains { $0.contains("sidebar-destination-review") })
        XCTAssertTrue(script.contains("navigate_to_seed_project()"))
        XCTAssertTrue(script.contains("\"project:$seed_project_id\""))
        XCTAssertTrue(script.contains("\"sidebar-destination-projects\""))
        XCTAssertTrue(script.contains("project-sidebar-row-$seed_project_id"))
        XCTAssertTrue(script.contains("route_content_marker=\"project-board-detail\""))
        XCTAssertTrue(script.contains("route_content_marker=\"project-inspector\""))
        XCTAssertTrue(script.contains("IFS='|' read -r route_id route_destination_value route_sidebar_marker_value route_content_marker_value"))
        XCTAssertTrue(script.contains("wait_for_marker_until \"$route_sidebar_marker\" \"\""))
        XCTAssertTrue(script.contains("wait_for_marker_until \"$route_content_marker\" \"$route_text\""))
        XCTAssertTrue(script.contains("seed_project_id="))
        XCTAssertTrue(script.contains("fixture-catch-up-1"))
        XCTAssertTrue(script.contains("route-evidence.tsv"))
        XCTAssertTrue(script.contains("failure_category="))
        XCTAssertTrue(script.contains("ax_wait_for_ax_identifier \"$APP_NAME\" \"$marker\" 1 \"$ROOT_DIR\" \"$probe_file\" \"$required_text\" \"$app_pid\""))
        XCTAssertTrue(script.contains("/usr/bin/env -i"))
        XCTAssertTrue(script.contains("HOME=\"$case_home\""))
        XCTAssertTrue(script.contains("CFFIXED_USER_HOME=\"$case_cf_user_home\""))
        XCTAssertTrue(script.contains("SUISUI_DATABASE_PATH=\"$database_path\""))
        XCTAssertTrue(script.contains("SUISUI_DISABLE_KEYCHAIN_SECRET_STORE=1"))
        XCTAssertTrue(script.contains("ax_wait_for_owned_app_pid \"$app_launch_pid\" \"$APP_BINARY\""))
        XCTAssertFalse(script.contains("SUISUI_LAUNCH_RECOVERY_MODE="))
        XCTAssertFalse(script.contains("ProjectBoardLaunchRecoveryView"))
        XCTAssertTrue(appSource.contains("else {\n            ProjectBoardView("))
    }

    func testProjectBoardRefreshesTodayFromProductionDateAndLifecycleNotifications() throws {
        let source = try readProjectBoardSurfaceSources()

        XCTAssertTrue(source.contains("@Environment(\\.scenePhase) private var scenePhase"))
        XCTAssertTrue(source.contains(".onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged))"))
        XCTAssertTrue(source.contains(".onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange))"))
        XCTAssertTrue(source.contains(".onReceive(NotificationCenter.default.publisher(for: .NSSystemClockDidChange))"))
        XCTAssertTrue(source.contains(".onChange(of: scenePhase)"))
        XCTAssertTrue(source.contains("@State private var boundaryRefreshTask: Task<Void, Never>?"))
        XCTAssertTrue(source.contains("DailyPlanningReviewRefreshSchedule.nextStrictBoundary"))
        XCTAssertTrue(source.contains("try await Task.sleep(nanoseconds:"))
        XCTAssertTrue(source.contains(".onDisappear"))
        XCTAssertTrue(source.contains("boundaryRefreshTask?.cancel()"))
        XCTAssertFalse(source.contains("Timer.publish"))
        XCTAssertTrue(source.contains("viewModel.refreshDerivedReadModels()"))
    }

    func testSelectionOnlyTodayRefreshReusesPlanPreviewAndRecommendationChips() throws {
        let source = try readPackageFile("Sources/SuisuiCore/App/ProjectBoard.swift")
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
        let source = try readPackageFile("Sources/SuisuiApp/Views/TodayDashboardView.swift")

        XCTAssertTrue(source.contains("viewModel.dailyPlanningReview ?? snapshot.dailyPlanningReviewPreview"))
    }

    func testProjectBoardRuntimeLoadsAssistantQueueReadModel() throws {
        let appSource = try readAppShellSource()
        let coreSource = try readPackageFile("Sources/SuisuiCore/App/ProjectBoard.swift")
        let reviewSessionSource = try readPackageFile("Sources/SuisuiCore/Review/ReviewSessionViewModel.swift")

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
        let boardSource = try readProjectBoardSurfaceSources()
        let workflowSource = try readProjectWorkflowSources()
        let persistenceSource = try readPackageFile("Sources/SuisuiCore/App/ProjectBoardSelectionPersistence.swift")
        let coreSource = try readPackageFile("Sources/SuisuiCore/App/ProjectBoard.swift")

        XCTAssertTrue(persistenceSource.contains("case assistantQueue"))
        XCTAssertTrue(persistenceSource.contains("return \"assistant-queue\""))
        XCTAssertTrue(boardSource.contains("review-destination-assistant-queue"))
        XCTAssertTrue(boardSource.contains("case .review(.assistantQueue):"))
        XCTAssertTrue(boardSource.contains("AssistantQueueWorkflowView(viewModel: viewModel)"))
        XCTAssertTrue(workflowSource.contains("struct AssistantQueueWorkflowView"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"assistant-queue-workflow\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"assistant-queue-row-\\(row.id)\")"))
        XCTAssertTrue(workflowSource.contains("viewModel.runAssistantQueueItem(\n                id: row.id,\n                expectedMutationRevision: mutationRevision"))
        XCTAssertTrue(workflowSource.contains("expectedMutationRevision: mutationRevision"))
        XCTAssertTrue(workflowSource.contains("viewModel.deferAssistantQueueItem("))
        XCTAssertTrue(workflowSource.contains("viewModel.editAssistantQueueItem("))
        XCTAssertTrue(workflowSource.contains("expectedMutationRevision: expectedMutationRevision"))
        XCTAssertTrue(workflowSource.contains("viewModel.retryAssistantQueueItem("))
        XCTAssertTrue(workflowSource.contains("viewModel.rejectAssistantQueueItem("))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"assistant-queue-run-\\(row.id)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"assistant-queue-edit-\\(row.id)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"assistant-queue-edit-reason-\\(row.id)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"assistant-queue-edit-summary-\\(row.id)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"assistant-queue-edit-save-\\(row.id)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"assistant-queue-edit-cancel-\\(row.id)\")"))
        XCTAssertTrue(workflowSource.contains("draftRedactedSummary = row.redactedSummary"))
        XCTAssertTrue(workflowSource.contains(".onChange(of: row.mutationRevision)"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"assistant-queue-retry-\\(row.id)\")"))
        XCTAssertTrue(workflowSource.contains("AssistantQueueTriageControls("))
        XCTAssertTrue(workflowSource.contains("AssistantQueueBatchToolbar("))
        XCTAssertTrue(workflowSource.contains("viewModel.setAssistantQueueViewFilter"))
        XCTAssertTrue(workflowSource.contains("viewModel.setAssistantQueueSort"))
        XCTAssertTrue(workflowSource.contains("viewModel.setAssistantQueueSelection(id: row.id, selected: selected)"))
        XCTAssertTrue(workflowSource.contains("viewModel.deferSelectedAssistantQueueItems()"))
        XCTAssertTrue(workflowSource.contains("viewModel.rejectSelectedAssistantQueueItems()"))
        XCTAssertTrue(workflowSource.contains(".disabled(!isBatchSelectable)"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"assistant-queue-filter\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"assistant-queue-sort\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"assistant-queue-batch-toolbar\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"assistant-queue-select-\\(row.id)\")"))
        XCTAssertTrue(workflowSource.contains("if snapshot.totalCount > 0 {"))
        XCTAssertFalse(workflowSource.contains("if !snapshot.rows.isEmpty {\n                AssistantQueueTriageControls"))
        XCTAssertFalse(workflowSource.contains("approveSelectedAssistantQueueItems"))
        XCTAssertFalse(workflowSource.contains("runSelectedAssistantQueueItems"))
        XCTAssertTrue(workflowSource.contains("if let receipt = row.latestReceipt"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"assistant-queue-receipt-\\(row.id)\")"))
        XCTAssertTrue(workflowSource.contains("localizedDisplay(\"Receipt: %@\", localizedDisplay(receipt.statusLabel))"))
        XCTAssertTrue(coreSource.contains("public func runAssistantQueueItem(id: String) -> Bool"))
        XCTAssertTrue(coreSource.contains("public func runAssistantQueueItem(\n        id: String,\n        expectedMutationRevision: String"))
        XCTAssertTrue(coreSource.contains("public func approveAssistantQueueItem(id: String) -> Bool"))
        XCTAssertTrue(coreSource.contains("public func deferAssistantQueueItem(id: String) -> Bool"))
        XCTAssertTrue(coreSource.contains("public func deferAssistantQueueItem(\n        id: String,\n        expectedMutationRevision: String"))
        XCTAssertTrue(coreSource.contains("public func editAssistantQueueItem("))
        XCTAssertTrue(coreSource.contains("public func retryAssistantQueueItem(id: String) -> Bool"))
        XCTAssertTrue(coreSource.contains("public func retryAssistantQueueItem(\n        id: String,\n        expectedMutationRevision: String"))
        XCTAssertTrue(coreSource.contains("public func rejectAssistantQueueItem(id: String) -> Bool"))
        XCTAssertTrue(coreSource.contains("public func rejectAssistantQueueItem(\n        id: String,\n        expectedMutationRevision: String"))
        XCTAssertTrue(coreSource.contains("public func setAssistantQueueViewFilter(_ filter: AssistantQueueViewFilter)"))
        XCTAssertTrue(coreSource.contains("public func setAssistantQueueSort(_ sort: AssistantQueueSort)"))
        XCTAssertTrue(coreSource.contains("public func setAssistantQueueSelection(id: String, selected: Bool) -> Bool"))
        XCTAssertTrue(coreSource.contains("public func deferSelectedAssistantQueueItems() -> Bool"))
        XCTAssertTrue(coreSource.contains("public func rejectSelectedAssistantQueueItems() -> Bool"))
        XCTAssertTrue(coreSource.contains("row.canDefer || row.canReject"))
        XCTAssertTrue(coreSource.contains("failClosedUnversionedAssistantQueueMutation()"))
        let queueSource = try readPackageFile("Sources/SuisuiCore/App/AssistantQueue.swift")
        XCTAssertTrue(queueSource.contains("public var mutationRevision: String?"))
        XCTAssertTrue(queueSource.contains("Treat this value as opaque"))
    }

    func testAssistantQueueRowUsesStageSpecificPrimaryActionAndSecondaryMenu() throws {
        let source = try readPackageFile(
            "Sources/SuisuiApp/Views/ProjectWorkflowAssistantQueueView.swift"
        )

        let rowStart = try XCTUnwrap(source.range(of: "private struct AssistantQueueRow"))
        let rowEnd = try XCTUnwrap(
            source.range(
                of: "private struct AssistantQueueReceiptSummaryView",
                range: rowStart.upperBound..<source.endIndex
            )
        )
        let rowSource = String(source[rowStart.lowerBound..<rowEnd.lowerBound])
        let bodyStart = try XCTUnwrap(rowSource.range(of: "var body: some View"))
        let presentationStart = try XCTUnwrap(
            rowSource.range(
                of: "private var actionPresentation",
                range: bodyStart.upperBound..<rowSource.endIndex
            )
        )
        let bodySource = String(
            rowSource[bodyStart.lowerBound..<presentationStart.lowerBound]
        )
        let primaryStart = try XCTUnwrap(
            rowSource.range(
                of: "private func primaryAction(",
                range: presentationStart.upperBound..<rowSource.endIndex
            )
        )
        let secondaryStart = try XCTUnwrap(
            rowSource.range(
                of: "private func secondaryAction(",
                range: primaryStart.upperBound..<rowSource.endIndex
            )
        )
        let primarySource = String(
            rowSource[primaryStart.lowerBound..<secondaryStart.lowerBound]
        )
        let secondaryEnd = try XCTUnwrap(
            rowSource.range(
                of: "private var approveButton",
                range: secondaryStart.upperBound..<rowSource.endIndex
            )
        )
        let secondarySource = String(
            rowSource[secondaryStart.lowerBound..<secondaryEnd.lowerBound]
        )

        XCTAssertTrue(
            rowSource.contains("AssistantQueueRowActionPresentation.make(for: row)")
        )
        XCTAssertTrue(bodySource.contains("actionPresentation.primaryAction"))
        XCTAssertTrue(bodySource.contains("actionPresentation.secondaryActions"))
        XCTAssertTrue(bodySource.contains("Menu {"))
        XCTAssertTrue(
            bodySource.contains(
                "ForEach(actionPresentation.secondaryActions, id: \\.self)"
            )
        )
        XCTAssertTrue(bodySource.contains("secondaryAction(action)"))
        XCTAssertTrue(bodySource.contains("assistant-queue-more-\\(row.id)"))
        XCTAssertTrue(bodySource.contains(".onChange(of: row.state)"))
        XCTAssertTrue(bodySource.contains(".onChange(of: actionPresentation)"))
        XCTAssertFalse(bodySource.contains("closeStaleEditIfNeeded()"))
        XCTAssertTrue(rowSource.contains("case primary"))
        XCTAssertFalse(rowSource.contains("case rowHeading"))
        XCTAssertTrue(rowSource.contains("focusAfterEditing()"))
        XCTAssertTrue(rowSource.contains("focusWorkflowControls()"))
        XCTAssertTrue(rowSource.contains("hasEditConflict = true"))
        XCTAssertTrue(rowSource.contains("assistant-queue-edit-reload-\\(row.id)"))
        let revisionChangeStart = try XCTUnwrap(
            bodySource.range(of: ".onChange(of: row.mutationRevision)")
        )
        let revisionChangeSource = String(bodySource[revisionChangeStart.lowerBound...])
        XCTAssertTrue(revisionChangeSource.contains("markEditConflictIfNeeded()"))
        XCTAssertFalse(revisionChangeSource.contains("closeStaleEditIfNeeded()"))
        let approveCase = try XCTUnwrap(primarySource.range(of: "case .approve:"))
        let runCase = try XCTUnwrap(
            primarySource.range(
                of: "case .run:",
                range: approveCase.upperBound..<primarySource.endIndex
            )
        )
        let reopenCase = try XCTUnwrap(
            primarySource.range(
                of: "case .reopen:",
                range: runCase.upperBound..<primarySource.endIndex
            )
        )
        XCTAssertTrue(
            primarySource[approveCase.upperBound..<runCase.lowerBound]
                .contains("approveButton")
        )
        XCTAssertTrue(
            primarySource[runCase.upperBound..<reopenCase.lowerBound]
                .contains("runButton")
        )
        XCTAssertTrue(primarySource[reopenCase.upperBound...].contains("reopenButton"))
        XCTAssertFalse(primarySource.contains("case .reject:"))
        XCTAssertTrue(secondarySource.contains("case .edit:"))
        XCTAssertTrue(secondarySource.contains("case .defer:"))
        let rejectCase = try XCTUnwrap(secondarySource.range(of: "case .reject:"))
        let destructiveButton = try XCTUnwrap(
            secondarySource.range(
                of: "Button(role: .destructive)",
                range: rejectCase.upperBound..<secondarySource.endIndex
            )
        )
        let rejectHandler = try XCTUnwrap(
            secondarySource.range(
                of: "viewModel.rejectAssistantQueueItem(",
                range: destructiveButton.upperBound..<secondarySource.endIndex
            )
        )
        XCTAssertLessThan(
            secondarySource.distance(
                from: rejectCase.lowerBound,
                to: rejectHandler.lowerBound
            ),
            500
        )
        XCTAssertFalse(
            secondarySource[rejectHandler.upperBound...].contains("case .")
        )
        for identifier in [
            "assistant-queue-run-\\(row.id)",
            "assistant-queue-approve-\\(row.id)",
            "assistant-queue-defer-\\(row.id)",
            "assistant-queue-edit-\\(row.id)",
            "assistant-queue-retry-\\(row.id)",
            "assistant-queue-reject-\\(row.id)"
        ] {
            XCTAssertTrue(rowSource.contains(identifier))
        }
        XCTAssertFalse(rowSource.contains(".disabled(!row.canRun)"))
        XCTAssertFalse(rowSource.contains(".disabled(!row.canApprove)"))
        XCTAssertFalse(rowSource.contains(".disabled(!row.canRetry)"))
    }

    func testAssistantQueueFilterOptionsExposeStableAXIdentifiers() throws {
        let source = try readPackageFile(
            "Sources/SuisuiApp/Views/ProjectWorkflowAssistantQueueView.swift"
        )

        XCTAssertTrue(
            source.contains(
                "assistant-queue-filter-option-\\(filter.rawValue)"
            )
        )
    }

    func testAssistantQueueTriageLocalizationsDoNotDuplicateSharedKeys() throws {
        let english = try readPackageFile("Sources/SuisuiApp/Resources/en.lproj/Localizable.strings")
        let japanese = try readPackageFile("Sources/SuisuiApp/Resources/ja.lproj/Localizable.strings")
        for source in [english, japanese] {
            XCTAssertEqual(source.components(separatedBy: "\"All\" =").count - 1, 1)
            XCTAssertEqual(source.components(separatedBy: "\"Sort\" =").count - 1, 1)
            XCTAssertEqual(source.components(separatedBy: "\"Needs attention\" =").count - 1, 1)
            XCTAssertEqual(source.components(separatedBy: "\"Needs action first\" =").count - 1, 1)
            XCTAssertEqual(source.components(separatedBy: "\"Risk high first\" =").count - 1, 1)
            XCTAssertEqual(source.components(separatedBy: "\"Title A-Z\" =").count - 1, 1)
        }
    }

    func testApprovalFlowPolishLocalizationsHaveEnglishJapaneseParity() throws {
        let english = try readPackageFile(
            "Sources/SuisuiApp/Resources/en.lproj/Localizable.strings"
        )
        let japanese = try readPackageFile(
            "Sources/SuisuiApp/Resources/ja.lproj/Localizable.strings"
        )
        let keys = [
            "Selected Item",
            "Select an Inbox item to classify.",
            "Smart List Not Found",
            "Transcript failed",
            "Transcript pending",
            "AI interpreted",
            "More Assistant Queue actions",
            "Choose Review destination.",
            "Choose Project destination."
        ]

        for key in keys {
            XCTAssertEqual(
                localizableDefinitionCount(for: key, in: english),
                1,
                "English must define \(key) exactly once"
            )
            XCTAssertEqual(
                localizableDefinitionCount(for: key, in: japanese),
                1,
                "Japanese must define \(key) exactly once"
            )
        }
    }

    func testProjectBoardExposesPortableTaskImportExportFileActions() throws {
        let appSource = try readAppShellSource()
        let boardSource = try readProjectBoardSurfaceSources()

        XCTAssertTrue(appSource.contains("SQLiteExternalTaskLinkStore(connection: connection)"))
        XCTAssertTrue(boardSource.contains("TaskInteropFileDocument"))
        XCTAssertTrue(boardSource.contains(".fileExporter("))
        XCTAssertTrue(boardSource.contains(".fileImporter("))
        XCTAssertFalse(boardSource.contains("Label(\"Integrations\", systemImage: \"arrow.left.arrow.right\")"))
        XCTAssertTrue(boardSource.contains("Label(\"Export Tasks\", systemImage: \"square.and.arrow.up\")"))
        XCTAssertTrue(boardSource.contains("Label(\"Import Tasks\", systemImage: \"square.and.arrow.down\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"project-board-export-tasks\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"project-board-import-tasks\")"))
        XCTAssertTrue(boardSource.contains("viewModel.importTaskInteropJSON(data)"))
        XCTAssertTrue(boardSource.contains("viewModel.exportTaskInteropJSON()"))
    }

    func testNativeToolbarInspectorHelpIsLocalizedInEnglishAndJapanese() throws {
        let toolbarSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardToolbarContent.swift")
        let english = try readPackageFile("Sources/SuisuiApp/Resources/en.lproj/Localizable.strings")
        let japanese = try readPackageFile("Sources/SuisuiApp/Resources/ja.lproj/Localizable.strings")

        XCTAssertTrue(toolbarSource.contains(".help(isInspectorPresented ? \"Hide Details\" : \"Show Details\")"))
        XCTAssertTrue(english.contains("\"Show Details\" = \"Show Details\";"))
        XCTAssertTrue(english.contains("\"Hide Details\" = \"Hide Details\";"))
        XCTAssertTrue(japanese.contains("\"Show Details\" = \"詳細を表示\";"))
        XCTAssertTrue(japanese.contains("\"Hide Details\" = \"詳細を非表示\";"))
    }

    func testProjectAddTaskFromOverviewOpensVisibleBoardComposer() throws {
        let source = try readProjectBoardDetailSource()
        let detailStart = try XCTUnwrap(source.range(of: "struct ProjectBoardDetail"))
        let archivedStart = try XCTUnwrap(source.range(of: "private struct ArchivedProjectReadOnlyState"))
        let detailSource = String(source[detailStart.lowerBound..<archivedStart.lowerBound])

        XCTAssertTrue(detailSource.contains("private func startComposingTask(status: ProjectTaskStatus = .backlog)"))
        XCTAssertTrue(detailSource.contains("displayMode = .board"))
        XCTAssertTrue(detailSource.contains("composingStatus = status"))
        XCTAssertGreaterThanOrEqual(detailSource.components(separatedBy: "onAddTask: { startComposingTask() }").count - 1, 3)
        XCTAssertFalse(detailSource.contains("onAddTask: { composingStatus = .backlog }"))
    }

    func testProjectsOverviewKeepsSidebarProjectSelectionAndDetailModesSeparate() throws {
        let boardSource = try readProjectBoardSurfaceSources()
        let persistenceSource = try readPackageFile("Sources/SuisuiCore/App/ProjectBoardSelectionPersistence.swift")

        XCTAssertTrue(persistenceSource.contains("case projects"))
        XCTAssertTrue(persistenceSource.contains("case .projects:"))
        XCTAssertTrue(persistenceSource.contains("return \"projects\""))
        XCTAssertTrue(boardSource.contains("sidebar-destination-projects"))
        XCTAssertTrue(boardSource.contains(".tag(BoardRoute.primary(.projects))"))
        XCTAssertTrue(boardSource.contains("ProjectsPortfolioOverview("))
        XCTAssertTrue(boardSource.contains(".tag(BoardRoute.project(project.id))"))
        XCTAssertTrue(boardSource.contains("case .project(let projectID):"))
        XCTAssertTrue(boardSource.contains("ProjectBoardDetail("))
        XCTAssertTrue(boardSource.contains("case .overview:"))
        XCTAssertTrue(boardSource.contains("case .board:"))
        XCTAssertTrue(boardSource.contains("case .list:"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"project-display-mode-\\(mode.rawValue)\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityLabel(LocalizedStringKey(mode.label))"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"project-task-list\")"))
    }

    func testProjectsPortfolioDensifiesCardsAndSummaryRailWithoutFakeProposals() throws {
        let boardDetailSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardDetailViews.swift")

        XCTAssertTrue(boardDetailSource.contains("projects-portfolio-card-milestone"))
        XCTAssertTrue(boardDetailSource.contains("nextMilestoneTitle"))
        XCTAssertTrue(boardDetailSource.contains("projects-portfolio-summary-priority-tasks"))
        XCTAssertTrue(boardDetailSource.contains("projects-portfolio-summary-proposal"))
        XCTAssertTrue(boardDetailSource.contains("projects-portfolio-summary-artifacts"))
        XCTAssertTrue(boardDetailSource.contains("No linked artifacts yet."))
        XCTAssertTrue(boardDetailSource.contains("priorityTaskTitles"))
        XCTAssertTrue(boardDetailSource.contains("proposalTitle"))
        XCTAssertTrue(boardDetailSource.contains("projects-portfolio-global-proposal"))
        XCTAssertTrue(boardDetailSource.contains("if let globalProposalTitle"))
        XCTAssertTrue(boardDetailSource.contains("String(localized: String.LocalizationValue(filter.title))"))
        XCTAssertFalse(boardDetailSource.contains("Proプラン"))
        XCTAssertFalse(boardDetailSource.contains("Pro Plan"))
        // Artifacts stay framed even when empty; do not hide the whole section.
        XCTAssertFalse(
            boardDetailSource.contains("if !artifactTitles.isEmpty {\n                summarySection(\n                    titleKey: \"Artifacts\"")
        )
    }

    func testAppearanceSelectionIsConfiguredOnlyFromSettings() throws {
        let appSource = try readAppShellSource()
        let boardSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardView.swift")
        let appearanceSectionSource = try readPackageFile("Sources/SuisuiApp/Views/SettingsAppearanceSection.swift")

        XCTAssertTrue(appSource.contains("SettingsAppearanceSection(appearancePreference: context.$appearancePreference, languagePreference: context.$languagePreference)"))
        XCTAssertEqual(appSource.components(separatedBy: "SettingsAppearanceSection(appearancePreference: context.$appearancePreference, languagePreference: context.$languagePreference)").count - 1, 1)
        XCTAssertTrue(appearanceSectionSource.contains("Section(\"Appearance\")"))
        XCTAssertTrue(appearanceSectionSource.contains("Picker(\"Theme\", selection: $appearancePreference)"))
        XCTAssertTrue(appearanceSectionSource.contains(".accessibilityIdentifier(\"settings-theme-picker\")"))
        XCTAssertEqual(appearanceSectionSource.components(separatedBy: "settings-theme-picker").count - 1, 1)
        XCTAssertEqual(appearanceSectionSource.components(separatedBy: "Section(\"Appearance\")").count - 1, 1)
        XCTAssertEqual(appearanceSectionSource.components(separatedBy: "Picker(\"Theme\"").count - 1, 1)
        let settingsRange = try XCTUnwrap(appSource.range(of: "struct SettingsView: View"))
        let appearanceTabRange = try XCTUnwrap(appSource.range(of: "struct SettingsAppearanceFeatureView: View"))
        let appearanceRange = try XCTUnwrap(appSource.range(of: "SettingsAppearanceSection(appearancePreference: context.$appearancePreference, languagePreference: context.$languagePreference)"))
        XCTAssertLessThan(settingsRange.lowerBound, appearanceRange.lowerBound)
        XCTAssertLessThan(appearanceTabRange.lowerBound, appearanceRange.lowerBound)
        XCTAssertTrue(appSource.contains("Label(\"Appearance\", systemImage: \"circle.lefthalf.filled\")"))
        XCTAssertTrue(appSource.contains("appearancePreference: $appearancePreference"))
        XCTAssertTrue(appSource.contains("@Binding private var appearancePreference: SuisuiAppearancePreference"))
        XCTAssertEqual(appSource.components(separatedBy: "@AppStorage(SuisuiAppearancePreference.storageKey)").count - 1, 2)
        XCTAssertFalse(appSource.contains(".accessibilityIdentifier(\"settings-theme-picker\")"))
        XCTAssertFalse(appSource.contains("Picker(\"Theme\", selection: $appearancePreference)"))
        XCTAssertFalse(boardSource.contains("AppearancePicker"))
        XCTAssertFalse(boardSource.contains("SidebarAppearanceSection"))
        XCTAssertFalse(boardSource.contains("SettingsAppearanceSection"))
        XCTAssertFalse(boardSource.contains("settings-theme-picker"))
        XCTAssertFalse(boardSource.contains("Section(\"Appearance\")"))
        XCTAssertFalse(boardSource.contains("Picker(\"Theme\""))
        XCTAssertFalse(boardSource.contains("Picker(\"Appearance\""))
        XCTAssertTrue(boardSource.contains("SuisuiSettingsWorkspace("))
        XCTAssertTrue(boardSource.contains("appearancePreference: $appearancePreference"))
        XCTAssertTrue(boardSource.contains("@AppStorage(SuisuiAppearancePreference.storageKey)"))
        let settingsWorkspaceSource = try readPackageFile("Sources/SuisuiApp/Views/SettingsView.swift")
        XCTAssertTrue(settingsWorkspaceSource.contains("presentation: .board"))
    }

    func testLanguageSelectionSupportsJapaneseAndEnglishFromSettings() throws {
        let appSource = try readAppShellSource()
        let boardSource = try readProjectBoardSurfaceSources()
        let appearanceSectionSource = try readPackageFile("Sources/SuisuiApp/Views/SettingsAppearanceSection.swift")
        let languagePreferenceSource = try readPackageFile("Sources/SuisuiApp/Views/AppLanguagePreference.swift")
        let localizedDisplaySource = try readPackageFile("Sources/SuisuiApp/LocalizedDisplay.swift")
        let settingsSource = try readPackageFile("Sources/SuisuiApp/Views/SettingsFeatureViews.swift")
        let doneSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectWorkflowDoneView.swift")
        let buildScript = try readPackageFile("script/build_and_run.sh")
        let englishStrings = try readPackageFile("Sources/SuisuiApp/Resources/en.lproj/Localizable.strings")
        let japaneseStrings = try readPackageFile("Sources/SuisuiApp/Resources/ja.lproj/Localizable.strings")

        XCTAssertTrue(languagePreferenceSource.contains("enum AppLanguagePreference"))
        XCTAssertTrue(languagePreferenceSource.contains("case system"))
        XCTAssertTrue(languagePreferenceSource.contains("case english"))
        XCTAssertTrue(languagePreferenceSource.contains("case japanese"))
        XCTAssertTrue(languagePreferenceSource.contains("static let storageKey = \"suisui.languagePreference\""))
        XCTAssertTrue(languagePreferenceSource.contains("static let environmentOverrideKey = \"SUISUI_LANGUAGE_PREFERENCE\""))
        XCTAssertTrue(languagePreferenceSource.contains("Locale(identifier: localeIdentifier)"))
        XCTAssertTrue(localizedDisplaySource.contains("AppLanguagePreference.environmentOverride"))
        XCTAssertTrue(localizedDisplaySource.contains("AppLanguagePreference.storageKey"))
        XCTAssertTrue(localizedDisplaySource.contains("return localizationBundle(for: preference, in: Bundle.module)"))
        XCTAssertTrue(localizedDisplaySource.contains("localizedString(forKey: key, value: key, table: nil)"))
        XCTAssertTrue(localizedDisplaySource.contains("func localizedDisplayLocale() -> Locale"))
        XCTAssertTrue(localizedDisplaySource.contains("return preference.locale"))
        XCTAssertTrue(localizedDisplaySource.contains("locale: localizedDisplayLocale()"))
        XCTAssertTrue(settingsSource.contains(".currency(code: \"USD\").locale(localizedDisplayLocale())"))
        XCTAssertTrue(doneSource.contains("return localizedDisplay("))
        XCTAssertTrue(doneSource.contains("\"%@ completed at %@\""))
        XCTAssertTrue(doneSource.contains("localizedDisplay(\"%@ completed\""))

        XCTAssertTrue(appSource.contains("@AppStorage(AppLanguagePreference.storageKey) private var languagePreference: AppLanguagePreference = .system"))
        XCTAssertTrue(appSource.contains("private var effectiveLanguagePreference: AppLanguagePreference"))
        XCTAssertTrue(appSource.contains("AppLanguagePreference.environmentOverride ?? languagePreference"))
        XCTAssertTrue(appSource.contains(".environment(\\.locale, effectiveLanguagePreference.locale)"))
        XCTAssertGreaterThanOrEqual(appSource.components(separatedBy: ".environment(\\.locale, effectiveLanguagePreference.locale)").count - 1, 2)

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
        XCTAssertTrue(boardSource.contains("@AppStorage(AppLanguagePreference.storageKey)"))
        XCTAssertTrue(boardSource.contains("languagePreference: $languagePreference"))

        XCTAssertTrue(buildScript.contains("copy_app_localizations"))
        XCTAssertTrue(buildScript.contains("Sources/SuisuiApp/Resources"))
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

    func testLocalizedDisplayUsesPackagedAppResourcesBeforeSwiftPMFallback() throws {
        let localizedDisplaySource = try readPackageFile("Sources/SuisuiApp/LocalizedDisplay.swift")
        let buildScript = try readPackageFile("script/build_and_run.sh")
        let mainBundleParameter = try XCTUnwrap(
            localizedDisplaySource.range(of: "appBundle: Bundle = .main")
        )
        let mainLookup = try XCTUnwrap(
            localizedDisplaySource.range(of: "localizationBundle(for: preference, in: appBundle)")
        )
        let moduleFallback = try XCTUnwrap(
            localizedDisplaySource.range(of: "localizationBundle(for: preference, in: Bundle.module)")
        )

        XCTAssertLessThan(mainBundleParameter.lowerBound, mainLookup.lowerBound)
        XCTAssertLessThan(mainLookup.lowerBound, moduleFallback.lowerBound)
        XCTAssertTrue(buildScript.contains("copy_app_localizations"))
        XCTAssertTrue(buildScript.contains("$APP_RESOURCES/$(basename \"$localization_dir\")"))
    }

    func testAppLocalizationsCoverStaticSwiftUILiterals() throws {
        let englishKeys = try localizableKeys(in: "Sources/SuisuiApp/Resources/en.lproj/Localizable.strings")
        let japaneseKeys = try localizableKeys(in: "Sources/SuisuiApp/Resources/ja.lproj/Localizable.strings")

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
        let boardSource = try readProjectBoardSurfaceSources()
        let workflowSource = try readProjectWorkflowSources()
        let appSource = try readAppShellSource()
        let coreBoardSource = try readPackageFile("Sources/SuisuiCore/App/ProjectBoard.swift")
        let japaneseKeys = try localizableKeys(in: "Sources/SuisuiApp/Resources/ja.lproj/Localizable.strings")

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

    func testInboxVoiceMetadataAndActionPlanEnumsDoNotExposeRawValues() throws {
        let workflowSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectWorkflowInboxView.swift")
        let reviewSource = try readPackageFile("Sources/SuisuiApp/Views/ActionReviewPanel.swift")
        let voiceSource = try readPackageFile("Sources/SuisuiApp/Views/VoiceCaptureView.swift")
        let localizedDisplaySource = try readPackageFile("Sources/SuisuiApp/LocalizedDisplay.swift")

        XCTAssertFalse(workflowSource.contains("Text(capture.sourceKind.rawValue)"))
        XCTAssertFalse(workflowSource.contains("value: capture.sourceKind.rawValue"))
        XCTAssertFalse(workflowSource.contains("value: capture.classificationStatus.rawValue"))
        XCTAssertFalse(workflowSource.contains("value: capture.transcriptionStatus.rawValue"))
        XCTAssertFalse(reviewSource.contains("Text(riskLevel.rawValue.capitalized)"))
        XCTAssertFalse(reviewSource.contains("Text(item.editedAction.tool.rawValue)"))
        XCTAssertFalse(voiceSource.contains("Text(plan.riskLevel.rawValue.capitalized)"))
        XCTAssertFalse(voiceSource.contains("Text(action.tool.rawValue)"))
        XCTAssertTrue(localizedDisplaySource.contains("func localizedInboxCaptureSource"))
        XCTAssertTrue(localizedDisplaySource.contains("func localizedActionTool"))
        XCTAssertTrue(localizedDisplaySource.contains("func localizedRiskLevel"))
    }

    func testThemePickerIsOwnedOnlyBySettingsAppearanceSectionAcrossAppSources() throws {
        let expectedOwner = "Sources/SuisuiApp/Views/SettingsAppearanceSection.swift"
        let markers = [
            "Picker(\"Theme\", selection: $appearancePreference)",
            ".accessibilityIdentifier(\"settings-theme-picker\")"
        ]
        let root = packageRoot()
        var ownersByMarker: [String: Set<String>] = [:]

        for fileURL in try allSwiftFiles(under: "Sources/SuisuiApp") {
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

    func testCalmSignalDeskTokensStayOutOfNativeContainerRoots() throws {
        let designSource = try readPackageFile("Sources/SuisuiApp/Views/SuisuiDesignSystem.swift")
        let boardSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardView.swift")
        let settingsSource = try readSettingsSurfaceSources()

        XCTAssertTrue(designSource.contains("func soloAssistantSignal() -> some View"))
        XCTAssertFalse(designSource.contains("NavigationSplitView"))
        XCTAssertFalse(designSource.contains("Form {"))
        XCTAssertFalse(designSource.contains(".inspector"))
        XCTAssertEqual(
            SwiftUISourceStyleContractAnalyzer.nativeRootStyleViolations(
                in: boardSource,
                rootType: "NavigationSplitView",
                // These backgrounds inject non-rendering AppKit layout and
                // keyboard-command bridges; neither paints a ShapeStyle.
                allowedNonvisualBackgroundMarkers: [
                    "ProjectBoardToolbarLayoutBridge(",
                    ".background(Button("
                ]
            ),
            []
        )
        XCTAssertEqual(
            SwiftUISourceStyleContractAnalyzer.nativeRootStyleViolations(
                in: settingsSource,
                rootType: "TabView"
            ),
            []
        )
    }

    func testCalmSignalDeskOwnedSurfacesUseSemanticStyleContracts() throws {
        let ownedSurfaces = [
            "Sources/SuisuiApp/Views/ProjectWorkflowTodayView.swift",
            "Sources/SuisuiApp/Views/ProjectWorkflowScheduleView.swift",
            "Sources/SuisuiApp/Views/ProjectWorkflowDoneView.swift",
            "Sources/SuisuiApp/Views/ProjectBoardReviewHubView.swift",
            "Sources/SuisuiApp/Views/SettingsStatusOverviewView.swift",
            "Sources/SuisuiApp/Views/VoiceCaptureView.swift"
        ]
        // Computed styles are allowed only where their defining property is
        // already constrained to semantic tokens in the same owned source.
        let allowedSemanticExpressions = [
            "SuisuiSurface.",
            "SuisuiTone.",
            "SuisuiBrand.",
            "suisuiLiquidGlassCapturePanel(",
            ".background(tint.opacity(",
            ".background(background,",
            ".background(dayBackground,",
            ".background(\n                blockAccent.opacity(",
            ".fill(heatmapColor(",
            ".fill(blockAccent)",
            "AnyShapeStyle(.tint)"
        ]

        for path in ownedSurfaces {
            let source = try readPackageFile(path)
            XCTAssertEqual(
                SwiftUISourceStyleContractAnalyzer.disallowedSurfaceModifiers(
                    in: source,
                    allowedExpressionMarkers: allowedSemanticExpressions
                ),
                [],
                "\(path) must use an explicitly allowed semantic surface expression."
            )
            XCTAssertEqual(
                SwiftUISourceStyleContractAnalyzer.rawStyleViolations(in: source),
                [],
                "\(path) must route status colors and radii through semantic tokens."
            )
        }
    }

    func testSwiftUIStyleContractAnalyzerRejectsMultilineAndNativeRootFixtures() {
        let multilineSecondaryOpacity = """
        Text("Example")
            .background(
                Color.secondary
                    .opacity(0.08),
                in: RoundedRectangle(cornerRadius: SuisuiRadius.card)
            )
        """
        let thinMaterial = """
        Text("Example")
            .fill(
                .thinMaterial
            )
        """
        let regularMaterialBackgroundStyle = """
        Text("Example")
            .backgroundStyle(
                .regularMaterial
            )
        """
        let thinContainerBackground = """
        Text("Example")
            .containerBackground(
                .thinMaterial,
                for: .window
            )
        """
        let presentationGradient = """
        Text("Example")
            .presentationBackground(
                LinearGradient(
                    colors: [SuisuiSurface.canvas, .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        """
        let gradient = """
        Text("Example")
            .background(
                LinearGradient(
                    colors: [SuisuiSurface.canvas, .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        """
        let nativeRootBackground = """
        struct Fixture: View {
          var body: some View {
            TabView {
              Text("Overview")
            }
            .frame(width: 400)
            .background(
              SuisuiSurface.canvas
            )
          }
        }
        """
        let similarlyNamedTypeBeforeNativeRoot = """
        struct Fixture: View {
          let visibility: NavigationSplitViewVisibility
          var body: some View {
            NavigationSplitView {
              Text("Sidebar")
            } detail: {
              Text("Detail")
            }
            .background(.thinMaterial)
          }
        }
        """

        for fixture in [
            multilineSecondaryOpacity,
            thinMaterial,
            regularMaterialBackgroundStyle,
            thinContainerBackground,
            presentationGradient,
            gradient
        ] {
            XCTAssertFalse(
                SwiftUISourceStyleContractAnalyzer.disallowedSurfaceModifiers(
                    in: fixture,
                    allowedExpressionMarkers: ["SuisuiSurface."]
                ).isEmpty
            )
        }
        XCTAssertFalse(
            SwiftUISourceStyleContractAnalyzer.nativeRootStyleViolations(
                in: nativeRootBackground,
                rootType: "TabView"
            ).isEmpty
        )
        XCTAssertFalse(
            SwiftUISourceStyleContractAnalyzer.nativeRootStyleViolations(
                in: similarlyNamedTypeBeforeNativeRoot,
                rootType: "NavigationSplitView"
            ).isEmpty
        )
    }

    func testCalmSignalDeskStatusAndMotionKeepNonColorAccessibilityCues() throws {
        let settingsSource = try readPackageFile("Sources/SuisuiApp/Views/SettingsStatusOverviewView.swift")
        let todaySource = try readPackageFile("Sources/SuisuiApp/Views/ProjectWorkflowTodayView.swift")
        let scheduleSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectWorkflowScheduleView.swift")
        let doneSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectWorkflowDoneView.swift")
        let voiceSource = try readPackageFile("Sources/SuisuiApp/Views/VoiceCaptureView.swift")
        let commandPaletteSource = try readPackageFile("Sources/SuisuiApp/Views/CommandPaletteView.swift")
        let projectsHubSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardProjectsHubView.swift")
        let boardDetailSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardDetailViews.swift")

        XCTAssertTrue(settingsSource.contains("Image(systemName: row.state.systemImage)"))
        XCTAssertTrue(settingsSource.contains("Text(localizedSettingsDisplay(row.title))"))
        XCTAssertTrue(todaySource.contains("Label(LocalizedStringKey(label), systemImage: systemImage)"))
        XCTAssertTrue(scheduleSource.contains("Image(systemName: \"clock.badge.exclamationmark\")"))
        XCTAssertTrue(scheduleSource.contains("Text(day.loadLabel)"))
        XCTAssertTrue(scheduleSource.contains("Label(label, systemImage: systemImage)"))
        XCTAssertTrue(doneSource.contains("Label(row.statusLabel, systemImage: statusSystemImage)"))
        XCTAssertTrue(voiceSource.contains("@Environment(\\.accessibilityReduceMotion)"))
        XCTAssertTrue(voiceSource.contains("SuisuiMotion.animation"))
        XCTAssertTrue(voiceSource.contains("Image(systemName: stateSystemImage)"))
        XCTAssertTrue(commandPaletteSource.contains(".accessibilityAddTraits(isSelected ? .isSelected : [])"))
        XCTAssertTrue(projectsHubSource.contains(".accessibilityAddTraits(isSelected ? .isSelected : [])"))
        XCTAssertTrue(boardDetailSource.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion"))
        XCTAssertTrue(boardDetailSource.contains("reduceMotion ? nil : .snappy(duration: 0.16)"))
        XCTAssertTrue(boardDetailSource.contains("GridItem(.adaptive(minimum: 220, maximum: 340), spacing: 12)"))
        XCTAssertTrue(boardDetailSource.contains("projects-portfolio-summary-milestones"))
        XCTAssertTrue(boardDetailSource.contains("projects-portfolio-summary-artifacts"))
        XCTAssertTrue(doneSource.contains("heatmapMarkerDiameter"))
        XCTAssertTrue(doneSource.contains("done-heatmap-legend"))

        for nonAssistantSource in [settingsSource, todaySource, scheduleSource, doneSource] {
            XCTAssertFalse(
                nonAssistantSource.contains("SuisuiBrand.signalAmber"),
                "Signal Amber is reserved for assistant attention, not selection or decoration."
            )
            XCTAssertFalse(
                nonAssistantSource.contains("SuisuiTone.attention"),
                "Signal Amber is reserved for assistant attention, not general status."
            )
        }
    }

    func testProjectBoardSidebarHostsSettingsWithoutDuplicatingToolbarControls() throws {
        let toolbarSource = try readPackageFile(
            "Sources/SuisuiApp/Views/ProjectBoardToolbarContent.swift"
        )
        let sidebarSource = try readPackageFile(
            "Sources/SuisuiApp/Views/ProjectBoardSidebarView.swift"
        )

        XCTAssertTrue(sidebarSource.contains("case .settings: \"sidebar-action-settings\""))
        XCTAssertFalse(sidebarSource.contains("onOpenSettings()"))
        XCTAssertTrue(sidebarSource.contains("\"sidebar-action-settings\""))
        XCTAssertFalse(sidebarSource.contains("SettingsLink"))
        XCTAssertFalse(sidebarSource.contains("Theme"))
        XCTAssertFalse(sidebarSource.contains("Appearance"))
        XCTAssertFalse(sidebarSource.contains("SuisuiAppearancePreference"))
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

        XCTAssertFalse(toolbarSource.contains("SettingsLink"))
        XCTAssertFalse(toolbarSource.contains("Label(\"Settings\", systemImage: \"gearshape\")"))
        XCTAssertFalse(toolbarSource.contains(".help(\"Open Settings\")"))
        XCTAssertFalse(toolbarSource.contains(".accessibilityIdentifier(\"project-board-settings-link\")"))
        XCTAssertFalse(toolbarSource.contains(".keyboardShortcut(\",\", modifiers: [.command])"))
        XCTAssertFalse(toolbarSource.contains("Theme"))
        XCTAssertFalse(toolbarSource.contains("Appearance"))
        XCTAssertFalse(toolbarSource.contains("SuisuiAppearancePreference"))
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

    func testProjectBoardInspectorUsesAdaptiveNativePresentation() throws {
        let boardSource = try readProjectBoardSurfaceSources()

        XCTAssertTrue(boardSource.contains(".inspector(isPresented: wideInspectorBinding)"))
        XCTAssertTrue(boardSource.contains("@State private var isCompactInspectorSheetPresented = false"))
        XCTAssertTrue(boardSource.contains(".sheet(isPresented: $isCompactInspectorSheetPresented"))
        XCTAssertTrue(boardSource.contains(".onChange(of: inspectorSelectionContext)"))
        XCTAssertTrue(boardSource.contains("previousSelection == .task && selection != .task"))
        XCTAssertTrue(boardSource.contains("private var usesCompactInspectorPresentation: Bool"))
        XCTAssertTrue(boardSource.contains("static let detailColumnMinWidth: CGFloat = 440"))
        XCTAssertTrue(boardSource.contains(".inspectorColumnWidth(min: 240, ideal: 280, max: 420)"))
        XCTAssertFalse(boardSource.contains("inspectorOverlayContent"))
        XCTAssertFalse(boardSource.contains(".overlay(alignment: .trailing)"))
    }

    func testProjectBoardInspectorUsesSceneLocalIntentAndStableWidthPolicy() throws {
        let boardSource = try readProjectBoardSurfaceSources()

        XCTAssertTrue(boardSource.contains("@SceneStorage(\"projectBoard.userRequestedInspector\")"))
        XCTAssertTrue(boardSource.contains("InspectorPresentationPolicy.shouldPresent("))
        XCTAssertTrue(boardSource.contains("onWindowWidthChanged: updateProjectBoardWindowWidth"))
        XCTAssertTrue(boardSource.contains("private func reportWindowWidthIfChanged()"))
        XCTAssertTrue(boardSource.contains("requestInspectorPresentation()"))
        XCTAssertTrue(boardSource.contains("private func openProjectInspector()"))
        XCTAssertTrue(boardSource.contains("@State private var projectInspectorDevelopmentContext = ProjectInspectorDevelopmentContext()"))
        XCTAssertTrue(boardSource.contains(".openProject(taskID: viewModel.selectedTaskID)"))
        XCTAssertTrue(boardSource.contains("developmentTaskID: projectInspectorDevelopmentContext.taskID"))
        XCTAssertTrue(boardSource.contains("projectInspectorDevelopmentContext.handle(.dismissInspector)"))
        XCTAssertTrue(boardSource.contains("if previousDestination != destination"))
        XCTAssertTrue(boardSource.contains("projectInspectorDevelopmentContext.handle(.destinationChanged)"))
        XCTAssertTrue(boardSource.contains("projectInspectorDevelopmentContext.handle(.openTaskInspector)"))
        XCTAssertTrue(boardSource.contains("viewModel.selectedTaskID = nil"))
        XCTAssertTrue(boardSource.contains("InspectorPresentationPolicy.intentAfterResize("))
        XCTAssertTrue(boardSource.contains("dismissInspector()"))
        XCTAssertFalse(boardSource.contains("@State private var isInspectorPresented = true"))
        XCTAssertFalse(boardSource.contains("if selectedTaskID != nil && selectedDestination != .today && selectedDestination != .inbox"))
    }

    func testProjectBoardSameDestinationRestorePreservesInspectorDevelopmentContext() throws {
        let boardSource = try readPackageFile(
            "Sources/SuisuiApp/Views/ProjectBoardView.swift"
        )
        let applyLegacyStart = try XCTUnwrap(
            boardSource.range(of: "private func applyLegacyDestinationWithinScene")
        )
        let applyLegacyEnd = try XCTUnwrap(
            boardSource.range(
                of: "private func consumePendingSceneOpenRequests",
                range: applyLegacyStart.upperBound..<boardSource.endIndex
            )
        )
        let applyLegacySource = String(
            boardSource[applyLegacyStart.lowerBound..<applyLegacyEnd.lowerBound]
        )

        XCTAssertTrue(applyLegacySource.contains("let previousDestination = selectedDestination"))
        XCTAssertTrue(applyLegacySource.contains("if previousDestination != destination"))
        XCTAssertTrue(applyLegacySource.contains("previousDestination: previousDestination"))
    }

    func testLayoutStabilitySmokeCoversAdaptiveInspectorWidthsAndIntentMarkers() throws {
        let script = try readPackageFile("script/check_layout_stability_smoke.sh")

        XCTAssertTrue(script.contains("LAYOUT_STABILITY_WINDOW_COMPACT_WIDTH"))
        XCTAssertTrue(script.contains("960"))
        XCTAssertTrue(script.contains("LAYOUT_STABILITY_WINDOW_BELOW_MIN_WIDTH"))
        XCTAssertTrue(script.contains("900"))
        XCTAssertTrue(script.contains("LAYOUT_STABILITY_WINDOW_CANONICAL_WIDTH"))
        XCTAssertTrue(script.contains("1024"))
        XCTAssertTrue(script.contains("LAYOUT_STABILITY_WINDOW_STANDARD_WIDTH"))
        XCTAssertTrue(script.contains("1180"))
        XCTAssertTrue(script.contains("inspector-compact-closed"))
        XCTAssertTrue(script.contains("window-minimum-closed"))
        XCTAssertTrue(script.contains("window-minimum-open"))
        XCTAssertTrue(script.contains("LAYOUT_STABILITY_WINDOW_BELOW_MIN_HEIGHT"))
        XCTAssertTrue(script.contains("580"))
        XCTAssertTrue(script.contains("content-minimum-closed"))
        XCTAssertTrue(script.contains("content-minimum-open"))
        XCTAssertTrue(script.contains("assert_window_content_minimum"))
        XCTAssertTrue(script.contains("inspector-explicit-open"))
        XCTAssertTrue(script.contains("task-inspector-explicit-open"))
        XCTAssertTrue(script.contains("inspector-explicit-close"))
        XCTAssertTrue(script.contains("inspector-wide-stays-closed"))
        XCTAssertFalse(script.contains("inspector-wide-restored"))
        XCTAssertTrue(script.contains("\"sidebar-destination-schedule\" \"Schedule\" \"schedule-workflow\""))
        XCTAssertTrue(script.contains("\"sidebar-destination-completed\" \"Completed\" \"done-workflow\""))
        XCTAssertFalse(script.contains("sidebar-destination-review"))
        XCTAssertTrue(script.contains("\"review-destination-assistant-queue\" \"assistant-queue-workflow\""))
        XCTAssertTrue(script.contains("LAYOUT_STABILITY_FRAME_DELTA_THRESHOLD_PX:-0"))
    }

    func testProjectBoardUsesOneNativeContextualToolbarLayer() throws {
        let appSource = try readAppShellSource()
        let boardSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardView.swift")
        let toolbarSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardToolbarContent.swift")

        XCTAssertTrue(appSource.contains(".windowStyle(.hiddenTitleBar)"))
        XCTAssertFalse(boardSource.contains("projectBoardHeaderBar"))
        XCTAssertFalse(boardSource.contains(".frame(height: 44)"))
        XCTAssertFalse(boardSource.contains(".background(.bar)"))
        XCTAssertTrue(boardSource.contains("ProjectBoardToolbarContent("))
        XCTAssertTrue(toolbarSource.contains("struct ProjectBoardToolbarContent: ToolbarContent"))
        XCTAssertTrue(toolbarSource.contains("ToolbarItem(placement: .primaryAction)"))
        XCTAssertFalse(toolbarSource.contains("ToolbarItemGroup(placement: .primaryAction)"))
        XCTAssertFalse(toolbarSource.contains("Label(\"Search\", systemImage: \"magnifyingglass\")"))
        XCTAssertFalse(toolbarSource.contains("Label(\"Voice Command\", systemImage: \"mic\")"))
        XCTAssertTrue(toolbarSource.contains("Label(\"Utilities\", systemImage: \"ellipsis.circle\")"))
        XCTAssertTrue(toolbarSource.contains("Label(\"Export Tasks\", systemImage: \"square.and.arrow.up\")"))
        XCTAssertTrue(toolbarSource.contains("Label(\"Import Tasks\", systemImage: \"square.and.arrow.down\")"))
        XCTAssertTrue(toolbarSource.contains("Label(\"Google Calendar Sync\", systemImage: \"calendar.badge.plus\")"))
        XCTAssertTrue(toolbarSource.contains("Label(\"Review Task Automation\", systemImage: \"sparkles\")"))
        XCTAssertFalse(toolbarSource.contains("Label(\"Settings\", systemImage: \"gearshape\")"))
        XCTAssertTrue(toolbarSource.contains("Label(\"Terminal\", systemImage: \"terminal\")"))
        XCTAssertTrue(toolbarSource.contains("Label(\"Details\", systemImage: \"sidebar.trailing\")"))
        let utilitiesStart = try XCTUnwrap(toolbarSource.range(of: "Menu {\n                if context.showsIntegrations"))
        let utilitiesEnd = try XCTUnwrap(toolbarSource.range(of: "} label: {\n                Label(\"Utilities\"", range: utilitiesStart.lowerBound..<toolbarSource.endIndex))
        let utilitiesSource = String(toolbarSource[utilitiesStart.lowerBound..<utilitiesEnd.lowerBound])
        XCTAssertTrue(utilitiesSource.contains("Button(action: onExportTasks)"))
        XCTAssertTrue(utilitiesSource.contains("Button(action: onImportTasks)"))
        XCTAssertTrue(utilitiesSource.contains("Button(action: onRequestGoogleCalendarSync)"))
        XCTAssertFalse(utilitiesSource.contains("Menu {\n                        Button(action: onExportTasks)"))
        XCTAssertFalse(utilitiesSource.contains("Label(\"Integrations\", systemImage: \"arrow.left.arrow.right\")"))
        XCTAssertTrue(boardSource.contains("reconcileProjectBoardToolbarLayout(allowRetryIfToolbarMissing:"))
        XCTAssertTrue(toolbarSource.contains(".accessibilityIdentifier(\"project-board-integrations-menu\")"))
        XCTAssertTrue(toolbarSource.contains(".accessibilityIdentifier(\"project-board-task-auto-execution-review\")"))
        XCTAssertFalse(toolbarSource.contains(".accessibilityIdentifier(\"project-board-command-palette\")"))
        XCTAssertFalse(toolbarSource.contains(".accessibilityIdentifier(\"project-board-voice-command\")"))
        XCTAssertFalse(toolbarSource.contains(".accessibilityIdentifier(\"project-board-settings-link\")"))
        XCTAssertTrue(toolbarSource.contains(".accessibilityIdentifier(\"project-board-terminal-toggle\")"))
        XCTAssertTrue(toolbarSource.contains(".accessibilityIdentifier(\"project-board-inspector-toggle\")"))
        XCTAssertTrue(boardSource.contains("private extension NSToolbar"))
        XCTAssertTrue(boardSource.contains("var projectBoardLayoutItems: [ProjectBoardToolbarLayoutPolicy.Item]"))
        XCTAssertTrue(boardSource.contains("accessibilityIdentifier: view?.accessibilityIdentifier()"))
        XCTAssertFalse(boardSource.contains("private struct ProjectBoardToolbarIcon: View"))
        XCTAssertFalse(boardSource.contains("toolbar.displayMode = .iconOnly"))
        XCTAssertFalse(boardSource.contains("toolbar.allowsUserCustomization = false"))
    }

    func testProjectBoardHeaderPreparesConfiguredTaskAutomationReview() throws {
        let boardSource = try readProjectBoardSurfaceSources()
        let appSource = try readAppShellSource()

        XCTAssertTrue(boardSource.contains("let taskAutomationSettings: () -> TaskAutoExecutionSettings"))
        XCTAssertTrue(boardSource.contains("let appSettings: () -> AppSettings"))
        XCTAssertTrue(boardSource.contains("taskAutomationSettings: @escaping () -> TaskAutoExecutionSettings"))
        XCTAssertTrue(boardSource.contains("appSettings: @escaping () -> AppSettings"))
        XCTAssertTrue(boardSource.contains("viewModel.prepareTaskAutomationReview(settings: taskAutomationSettings())"))
        XCTAssertTrue(boardSource.contains("// consume LLM budget; reveal the selected task inspector"))
        XCTAssertTrue(boardSource.contains("decision.status == .readyForReview"))
        XCTAssertTrue(boardSource.contains("openTaskInspector(taskID)"))
        XCTAssertEqual(
            boardSource.components(
                separatedBy: "dateProvider: ProjectBoardMissedTaskFollowUpDateProvider()"
            ).count - 1,
            2
        )
        XCTAssertTrue(boardSource.contains("visualEvidenceReferenceDate ?? SystemDateProvider().now"))
        XCTAssertTrue(boardSource.contains(".help(\"Review Task Automation: prepares review-only task automation from the configured priority, due-date, cadence, and daily budget settings\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityHint(\"Prepares review-only task automation from the configured priority, due-date, cadence, and daily budget settings.\")"))
        XCTAssertTrue(appSource.contains("@StateObject private var settingsViewModel: AppSettingsViewModel"))
        XCTAssertTrue(appSource.contains("AppRuntimeFactory.makeAppSettingsViewModel(refreshProviderSecretStatusesOnInit: false)"))
        XCTAssertTrue(appSource.contains("taskAutomationSettings: { settingsViewModel.settings.taskAutoExecution }"))
        XCTAssertTrue(appSource.contains("appSettings: { settingsViewModel.settings }"))
    }

    func testTaskInspectorApprovedExecutionReceiptIsAccessibleAndRedacted() throws {
        let boardSource = try readProjectBoardSurfaceSources()

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
        let automationSource = try readPackageFile(
            "Sources/SuisuiApp/Views/ProjectWorkflowAutomationActivityView.swift"
        )
        let doneSource = try readPackageFile(
            "Sources/SuisuiApp/Views/ProjectWorkflowDoneView.swift"
        )
        let workflowSource = automationSource + doneSource
        let historySource = try readPackageFile("Sources/SuisuiCore/App/ExecutionReceiptHistory.swift")

        // Done surfaces a compact, redacted receipt strip. Search/export stay on
        // Automation Activity so the desk never becomes a full audit console.
        XCTAssertTrue(doneSource.contains("viewModel.executionReceiptHistorySnapshot"))
        XCTAssertTrue(doneSource.contains("viewModel.refreshExecutionReceiptAuditSnapshotsIfNeeded()"))
        XCTAssertTrue(doneSource.contains(".accessibilityIdentifier(\"done-execution-receipts\")"))
        XCTAssertTrue(doneSource.contains("Execution Receipts"))
        XCTAssertFalse(doneSource.contains("Recent AI Activity"))
        XCTAssertFalse(doneSource.contains("execution-receipt-search-field"))
        XCTAssertFalse(doneSource.contains("execution-receipt-export-button"))
        XCTAssertFalse(doneSource.contains("prepareExecutionReceiptHistoryExport"))
        XCTAssertTrue(automationSource.contains(".accessibilityIdentifier(\"automation-activity-workflow\")"))
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
        XCTAssertTrue(workflowSource.contains("Recent AI Activity"))
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

    func testDoneWorkflowPresentsListPrimaryDeskWithStatsAndReceiptsInRail() throws {
        let source = try readPackageFile("Sources/SuisuiApp/Views/ProjectWorkflowDoneView.swift")
        let seeder = try readPackageFile("Sources/SuisuiVisualFixtureSeeder/main.swift")

        XCTAssertTrue(source.contains("private enum DoneHistoryFilter"))
        XCTAssertTrue(source.contains("case .all: \"All\""))
        XCTAssertTrue(source.contains("case .today: \"Today\""))
        XCTAssertTrue(source.contains("case .thisWeek: \"This Week\""))
        XCTAssertTrue(source.contains("case .thisMonth: \"This Month\""))
        XCTAssertFalse(source.contains("return historyFilter == .thisMonth"))
        XCTAssertTrue(source.contains("donePrimaryColumn"))
        XCTAssertTrue(source.contains("doneSummaryRail"))
        XCTAssertTrue(source.contains("historyContent"))
        XCTAssertTrue(source.contains("done-execution-receipts"))
        // Wide desk keeps the completed list as the primary column, not a
        // chart-first analytics dashboard stacked above history.
        let wideStart = try XCTUnwrap(source.range(of: "if isWide"))
        let wideEnd = try XCTUnwrap(source.range(of: "} else {", range: wideStart.upperBound..<source.endIndex))
        let wideBody = source[wideStart.lowerBound..<wideEnd.lowerBound]
        XCTAssertTrue(wideBody.contains("donePrimaryColumn"))
        XCTAssertTrue(wideBody.contains("doneSummaryRail"))
        let primaryIndex = try XCTUnwrap(wideBody.range(of: "donePrimaryColumn"))
        let railIndex = try XCTUnwrap(wideBody.range(of: "doneSummaryRail"))
        XCTAssertLessThan(primaryIndex.lowerBound, railIndex.lowerBound)

        XCTAssertTrue(seeder.contains("Done desk sample: today"))
        XCTAssertTrue(seeder.contains("Done desk sample: last week"))
        XCTAssertTrue(seeder.contains("seedDoneExecutionReceipts"))
        XCTAssertTrue(seeder.contains("Registered schedule to calendar"))
        XCTAssertTrue(seeder.contains("Created Markdown note"))
    }

    func testInspectorsShowScopedAIReceiptsWithoutRawReceiptFields() throws {
        let boardSource = try readProjectBoardSurfaceSources()
        let workflowSource = try readProjectWorkflowSources()

        XCTAssertTrue(boardSource.contains("Section(\"Project AI Activity\")"))
        XCTAssertTrue(boardSource.contains("Section(\"Task AI Activity\")"))
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
        let boardSource = try readProjectBoardSurfaceSources()

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
        let source = try readProjectBoardSurfaceSources()
        let boardSource = try readProjectBoardOwnerSource()

        XCTAssertTrue(source.contains("enum ProjectBoardLayoutMetrics"))
        XCTAssertFalse(source.contains("static let headerHeight: CGFloat = 44"))
        XCTAssertTrue(source.contains("static let terminalPanelMinHeight: CGFloat = 220"))
        XCTAssertTrue(source.contains("static let terminalPanelIdealHeight: CGFloat = 280"))
        XCTAssertTrue(source.contains("static let terminalPanelMaxHeight: CGFloat = 360"))
        XCTAssertTrue(source.contains("static let portfolioCardMinHeight: CGFloat = 230"))
        XCTAssertTrue(source.contains("static let overviewPanelMinHeight: CGFloat = 170"))
        XCTAssertTrue(source.contains("static let displayModePickerWidth: CGFloat = 252"))
        XCTAssertTrue(source.contains("static let sidebarColumnMinWidth: CGFloat = 220"))
        XCTAssertTrue(source.contains("static let sidebarColumnIdealWidth: CGFloat = 240"))
        XCTAssertTrue(source.contains("static let sidebarColumnMaxWidth: CGFloat = 240"))
        XCTAssertTrue(source.contains("static let boardColumnWidth: CGFloat = 204"))
        XCTAssertTrue(source.contains("static let emptyColumnMinHeight: CGFloat = 82"))
        XCTAssertTrue(source.contains("static let inlinePriorityPickerWidth: CGFloat = 112"))
        XCTAssertTrue(source.contains("static let taskMetadataChipMinWidth: CGFloat = 64"))
        XCTAssertTrue(source.contains("static let taskMetadataChipMinHeight: CGFloat = 24"))
        XCTAssertTrue(source.contains("static let taskStatusRailWidth: CGFloat = 4"))
        XCTAssertTrue(source.contains("static let taskStatusRailHeight: CGFloat = 44"))
        XCTAssertTrue(source.contains("Project Board keeps these metrics local"))

        XCTAssertFalse(source.contains("ProjectBoardLayoutMetrics.headerHeight"))
        XCTAssertFalse(boardSource.contains(".background(.bar)"))
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
        XCTAssertTrue(source.contains("Text(verbatim: value)"))
        XCTAssertTrue(source.contains(".minimumScaleFactor(0.82)"))
        XCTAssertTrue(source.contains("minHeight: ProjectBoardLayoutMetrics.taskMetadataChipMinHeight"))
        XCTAssertTrue(source.contains(".help(task.title)"))
        XCTAssertTrue(source.contains(".help(task.detail)"))
    }

    func testCommandPaletteClearsStaleContentBeforeStartingAnotherDebouncedSearch() throws {
        let source = try readPackageFile("Sources/SuisuiApp/Views/CommandPaletteView.swift")
        let searchFunction = try sourceBlock(
            in: source,
            from: "private func scheduleContentSearch(for newQuery: String)",
            to: "private func moveSelection("
        )
        let clearRange = try XCTUnwrap(searchFunction.range(of: "contentItems = []"))
        let providerGuardRange = try XCTUnwrap(searchFunction.range(of: "guard let contentSearch"))
        let taskRange = try XCTUnwrap(searchFunction.range(of: "contentSearchTask = Task"))

        XCTAssertLessThan(clearRange.lowerBound, providerGuardRange.lowerBound)
        XCTAssertLessThan(clearRange.lowerBound, taskRange.lowerBound)
    }

    func testFullVisualCaptureFinishesBoardAndSettingsRoutesBeforeVoiceWindows() throws {
        let script = try readPackageFile("script/capture_ui_evidence.sh")
        let fullCaptureStart = try XCTUnwrap(
            script.range(of: "capture_project_board_destination light \"$PROJECT_BOARD_SELECTION_OVERRIDE\"")
        )
        let fullCapture = String(script[fullCaptureStart.lowerBound...])
        let lastBoardRoute = try XCTUnwrap(
            fullCapture.range(of: "capture_mcp_settings_appearance system")
        )
        let firstVoiceRoute = try XCTUnwrap(
            fullCapture.range(of: "capture_voice_command_appearance light")
        )

        XCTAssertLessThan(lastBoardRoute.lowerBound, firstVoiceRoute.lowerBound)
    }

    func testProjectBoardLongContentFixtureMapsToResponsiveGuards() throws {
        let fixture = try readPackageFile("Tests/SuisuiCoreTests/Fixtures/ProjectBoard/long-content-layout.json")
        let source = try readProjectBoardSurfaceSources()

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
        XCTAssertTrue(source.contains("ContentUnavailableView("))
        XCTAssertTrue(source.contains("\"Project Board Unavailable\""))
        XCTAssertTrue(source.contains("ContentUnavailableView(\"No Projects\""))
        XCTAssertTrue(source.contains("Text(\"No tasks\")"))
        XCTAssertTrue(source.contains("ProjectBoardLayoutMetrics.emptyColumnMinHeight"))
    }

    func testProjectBoardStateRestorationFixtureCoversLaunchMatrix() throws {
        let fixture = try readPackageFile("Tests/SuisuiCoreTests/Fixtures/ProjectBoard/state-restoration-matrix.json")
        let boardSource = try readProjectBoardSurfaceSources()
        let persistenceSource = try readPackageFile("Sources/SuisuiCore/App/ProjectBoardSelectionPersistence.swift")
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
        XCTAssertTrue(fixture.contains("SUISUI_DATABASE_PATH"))
        XCTAssertTrue(fixture.contains("SUISUI_PROJECT_BOARD_SELECTED_DESTINATION"))
        XCTAssertTrue(fixture.contains("SUISUI_LAYOUT_STABILITY_WINDOW_MIN_WIDTH"))
        XCTAssertTrue(fixture.contains("SUISUI_LAYOUT_STABILITY_WINDOW_STANDARD_WIDTH"))
        XCTAssertTrue(fixture.contains("SUISUI_LAYOUT_STABILITY_WINDOW_WIDE_WIDTH"))

        XCTAssertTrue(boardSource.contains("restoreSelectedDestinationIfNeeded()"))
        XCTAssertTrue(boardSource.contains("ProjectBoardScenePersistence.restoredResolution("))
        XCTAssertTrue(boardSource.contains("ProjectBoardRouteCodec.resolution("))
        XCTAssertTrue(boardSource.contains("persistSelectedDestination(destination)"))
        XCTAssertTrue(boardSource.contains("applySelectedDestination("))
        XCTAssertTrue(persistenceSource.contains("Saved app state can outlive a project row"))
        XCTAssertTrue(persistenceSource.contains("availableProjects.contains(where: { $0.id == projectID }) else"))
        XCTAssertTrue(layoutSmoke.contains("SUISUI_PROJECT_BOARD_SELECTED_DESTINATION=\"project:$layout_project_id\""))
        XCTAssertTrue(crudSmoke.contains("SUISUI_PROJECT_BOARD_SELECTED_DESTINATION=\"project:$seed_project_id\""))
        XCTAssertTrue(crudSmoke.contains("SUISUI_PROJECT_BOARD_SELECTED_DESTINATION=\"projects\""))
        XCTAssertTrue(layoutSmoke.contains("AX_HELPERS=\"${AX_HELPERS:-$ROOT_DIR/script/ui_accessibility_smoke_helpers.sh}\""))
        XCTAssertTrue(layoutSmoke.contains("source \"$AX_HELPERS\""))
        XCTAssertTrue(crudSmoke.contains("AX_HELPERS=\"${AX_HELPERS:-$ROOT_DIR/script/ui_accessibility_smoke_helpers.sh}\""))
        XCTAssertTrue(crudSmoke.contains("source \"$AX_HELPERS\""))
    }

    func testProjectBoardWindowRestorationUsesNarrowPresentationOnlyBridge() throws {
        let appSource = try readAppShellSource()
        let boardSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardView.swift")
        let bridgeSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardWindowStateBridge.swift")
        let coreSource = try readPackageFile("Sources/SuisuiCore/App/ProjectBoardWindowPresentationState.swift")

        XCTAssertTrue(appSource.contains("ProjectBoardWindowStateBridge("))
        XCTAssertTrue(appSource.contains("restoresPrimaryWindow: isPrimaryOnboardingWindow"))
        XCTAssertTrue(boardSource.contains("@SceneStorage(\"projectBoard.sidebarHidden\")"))
        XCTAssertTrue(boardSource.contains("@SceneStorage(\"projectBoard.userRequestedInspector\")"))
        XCTAssertTrue(boardSource.contains("@AppStorage(\"projectBoard.primary.sidebarHidden\")"))
        XCTAssertTrue(boardSource.contains("@AppStorage(\"projectBoard.primary.userRequestedInspector\")"))
        XCTAssertTrue(bridgeSource.contains("NSViewRepresentable"))
        XCTAssertTrue(bridgeSource.contains("NSWindow.didMoveNotification"))
        XCTAssertTrue(bridgeSource.contains("NSWindow.didResizeNotification"))
        XCTAssertTrue(bridgeSource.contains("ProjectBoardWindowPresentationState"))
        XCTAssertTrue(bridgeSource.contains("suisui.projectBoard.primaryWindowFrame"))
        XCTAssertTrue(bridgeSource.contains("SUISUI_DISABLE_PROJECT_BOARD_PRESENTATION_PERSISTENCE"))
        XCTAssertTrue(boardSource.contains("SUISUI_DISABLE_PROJECT_BOARD_PRESENTATION_PERSISTENCE"))
        XCTAssertTrue(coreSource.contains("public struct ProjectBoardWindowFrame"))
        XCTAssertTrue(coreSource.contains("public static let currentVersion = 1"))
        XCTAssertFalse(coreSource.contains("public var taskTitle"))
        XCTAssertFalse(coreSource.contains("public var transcript"))
        XCTAssertFalse(coreSource.contains("public var approvalToken"))
    }

    func testProjectBoardToolbarDisplayModeOnlyAllowsIconAndTextOrIconOnly() throws {
        let boardSource = try readProjectBoardSurfaceSources()

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
        let boardSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardView.swift")
        let appSource = try readPackageFile("Sources/SuisuiApp/SuisuiApp.swift")
        let detailStart = try XCTUnwrap(boardSource.range(of: "} detail: {"))
        let inspectorStart = try XCTUnwrap(boardSource.range(of: ".inspector(isPresented: wideInspectorBinding)"))
        let toolbarStart = try XCTUnwrap(boardSource.range(of: ".toolbar {"))

        XCTAssertGreaterThan(toolbarStart.lowerBound, inspectorStart.lowerBound)
        XCTAssertTrue(boardSource.contains("enum ProjectBoardWindowMetrics"))
        XCTAssertTrue(
            boardSource.contains("static let defaultWidth: CGFloat = 1_180")
                || boardSource.contains("static let defaultWidth = CGFloat(CockpitLayoutPolicy.defaultLaunchWindowWidth)")
        )
        XCTAssertTrue(
            boardSource.contains("static let minWidth: CGFloat = 960")
                || boardSource.contains("static let minWidth = CGFloat(CockpitLayoutPolicy.minimumWindowWidth)")
        )
        XCTAssertTrue(boardSource.contains(".frame(\n            minHeight: ProjectBoardWindowMetrics.minHeight"))
        XCTAssertTrue(
            boardSource.contains("static let minHeight: CGFloat = 572")
                || boardSource.contains("static let minHeight: CGFloat = 676")
                || boardSource.contains("static let minHeight = CGFloat(")
        )
        XCTAssertTrue(boardSource.contains("private func enforceProjectBoardWindowMinimumSize()"))
        XCTAssertTrue(boardSource.contains("window.contentMinSize = minimumContentSize"))
        XCTAssertTrue(boardSource.contains("window.frameRect("))
        XCTAssertTrue(boardSource.contains("forContentRect: NSRect(origin: .zero, size: minimumContentSize)"))
        XCTAssertTrue(boardSource.contains("window.contentRect(forFrameRect: window.frame)"))
        XCTAssertTrue(boardSource.contains("window.minSize = minimumFrameSize"))
        XCTAssertTrue(boardSource.contains("window.setFrame(constrainedFrame, display: true)"))
        XCTAssertTrue(boardSource.contains("window.contentLayoutRect.size"))
        XCTAssertTrue(boardSource.contains("SUISUI_LAYOUT_STABILITY_WINDOW_CONTENT_SIZE_PATH"))
        XCTAssertFalse(boardSource.contains("max(constrainedFrame.height, minimumSize.height)"))
        XCTAssertTrue(appSource.contains(".defaultSize(width: ProjectBoardWindowMetrics.defaultWidth, height: ProjectBoardWindowMetrics.defaultHeight)"))
        XCTAssertTrue(appSource.contains(".windowResizability(.automatic)"))
        XCTAssertFalse(appSource.contains(".windowResizability(.contentMinSize)"))
        XCTAssertEqual(boardSource.components(separatedBy: ".navigationTitle(\"Suisui\")").count - 1, 1)
        XCTAssertEqual(boardSource.components(separatedBy: ".projectBoardSynchronizedColumnBounds()").count - 1, 2)
        // The sidebar pins bounded (min/ideal/max) column widths so fixed
        // destination labels render untruncated at the 1024pt canonical
        // width; a hard-coded fixed width remains forbidden.
        XCTAssertTrue(boardSource.contains("max: ProjectBoardLayoutMetrics.sidebarColumnMaxWidth"))
        XCTAssertTrue(boardSource.contains("min: ProjectBoardLayoutMetrics.detailColumnMinWidth"))
        XCTAssertTrue(boardSource.contains("ideal: ProjectBoardLayoutMetrics.detailColumnIdealWidth"))
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
        let boardSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardView.swift")
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

    func testRuntimeDiagnosticsExposeOnlyStablePublicDiagnosticValues() throws {
        let coreSource = try readPackageFile("Sources/SuisuiCore/App/ProjectBoard.swift")
        let dailyPlanningSource = try readPackageFile("Sources/SuisuiCore/App/DailyPlanningReview.swift")
        let boardSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardView.swift")
        let bridgeStart = try XCTUnwrap(boardSource.range(of: "private final class ProjectBoardToolbarLayoutBridgeView"))
        let appKitEnd = try XCTUnwrap(boardSource.range(of: "#else", range: bridgeStart.upperBound..<boardSource.endIndex))
        let bridgeSource = String(boardSource[bridgeStart.lowerBound..<appKitEnd.lowerBound])

        XCTAssertTrue(coreSource.contains("Logger(subsystem: \"dev.suisui.app\""))
        XCTAssertTrue(coreSource.contains("suisui.dailyPlanningPreview.buildCount="))
        XCTAssertTrue(coreSource.contains("temporalKey=\\(cacheKey.runtimeDiagnosticTemporalKey, privacy: .public)"))
        XCTAssertTrue(dailyPlanningSource.contains("hasher.combine(planningDayKey)"))
        XCTAssertTrue(dailyPlanningSource.contains("hasher.combine(phase.rawValue)"))
        XCTAssertTrue(dailyPlanningSource.contains("hasher.combine(timeBlock)"))
        XCTAssertFalse(dailyPlanningSource.contains("hasher.combine(sourceRevision)"))
        XCTAssertTrue(coreSource.contains("privacy: .public"))
        XCTAssertTrue(coreSource.contains("projectBoardRuntimeDiagnosticLogger.notice"))
        XCTAssertTrue(coreSource.contains("dailyPlanningReviewPreviewBuildCount += 1"))
        XCTAssertTrue(coreSource.contains("dailyPlanningReviewPreviewCache.review(for: cacheKey) {"))

        XCTAssertTrue(bridgeSource.contains("Logger(subsystem: \"dev.suisui.app\""))
        XCTAssertTrue(bridgeSource.contains("suisui.toolbar.layout.maxDepth="))
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
        let viewFiles = try allSwiftFiles(under: "Sources/SuisuiApp/Views")
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
            delayedCorrections.allSatisfy { $0.hasPrefix("Sources/SuisuiApp/Views/ProjectBoardView.swift:") },
            delayedCorrections.joined(separator: "\n")
        )

        let boardSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardView.swift")
        let bridgeStart = try XCTUnwrap(boardSource.range(of: "private final class ProjectBoardToolbarLayoutBridgeView"))
        let appKitEnd = try XCTUnwrap(boardSource.range(of: "#else", range: bridgeStart.upperBound..<boardSource.endIndex))
        let bridgeSource = String(boardSource[bridgeStart.lowerBound..<appKitEnd.lowerBound])

        XCTAssertEqual(bridgeSource.components(separatedBy: "DispatchQueue.main.asyncAfter").count - 1, 2)
        XCTAssertEqual(bridgeSource.components(separatedBy: "layout-attachment-delay:").count - 1, 2)
        XCTAssertTrue(bridgeSource.contains("initial AppKit toolbar attachment gap"))
        XCTAssertTrue(bridgeSource.contains("mutate the toolbar synchronously without forcing a full view-tree layout"))
    }

    func testLayoutSensitiveStateMutationsUseSynchronousTransactionPolicy() throws {
        let boardSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardView.swift")
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
        let boardSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardView.swift")
        let toolbarSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardToolbarContent.swift")
        let toggleStart = try XCTUnwrap(boardSource.range(of: "private func toggleSidebarVisibility()"))
        let toolbarBridgeStart = try XCTUnwrap(boardSource.range(of: "private func refreshProjectBoardColumnsAfterToolbarDisplayModeChange()"))
        let toggleSource = String(boardSource[toggleStart.lowerBound..<toolbarBridgeStart.lowerBound])

        XCTAssertTrue(boardSource.contains("@State private var columnVisibility: NavigationSplitViewVisibility = .all"))
        XCTAssertTrue(boardSource.contains("NavigationSplitView(columnVisibility: $columnVisibility)"))
        XCTAssertTrue(toolbarSource.contains("ToolbarItem(placement: .navigation)"))
        XCTAssertTrue(toolbarSource.contains("ToolbarItem(placement: .primaryAction)"))
        XCTAssertTrue(toolbarSource.contains("Label(\"Sidebar\", systemImage: \"sidebar.left\")"))
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

    func testProjectBoardHeaderLayoutRuntimeSmokeCoversNativeChromeMinimumWidthAndUtilities() throws {
        let script = try readPackageFile("script/check_project_board_header_layout_smoke.sh")

        XCTAssertTrue(script.contains("./script/build_and_run.sh --build-only"))
        XCTAssertTrue(script.contains("Project Board schema was not initialized for native toolbar smoke"))
        XCTAssertTrue(script.contains("header-layout-native-toolbar-seed"))
        XCTAssertTrue(script.contains("SUISUI_PROJECT_BOARD_SELECTED_DESTINATION=\"project:$header_layout_project_id\""))
        XCTAssertTrue(script.contains("SUISUI_HEADER_LAYOUT_DATABASE_PATH"))
        XCTAssertTrue(script.contains("SUISUI_DISABLE_PROJECT_BOARD_FALLBACK=1"))
        XCTAssertTrue(script.contains("project-board-sidebar-toggle"))
        XCTAssertTrue(script.contains("project-board-integrations-menu"))
        XCTAssertTrue(script.contains("sidebar-action-settings"))
        XCTAssertTrue(script.contains("project-board-inspector-toggle"))
        XCTAssertTrue(script.contains("ensure_project_detail_visible"))
        XCTAssertTrue(script.contains("wait_for_project_detail_visible"))
        let ensureDetailStart = try XCTUnwrap(script.range(of: "ensure_project_detail_visible() {"))
        let ensureDetailEnd = try XCTUnwrap(
            script.range(of: "\n}\n\nclose_hydrated_loading_window()", range: ensureDetailStart.upperBound..<script.endIndex)
        )
        let ensureDetailSource = String(script[ensureDetailStart.lowerBound..<ensureDetailEnd.lowerBound])
        XCTAssertTrue(ensureDetailSource.contains("/usr/bin/osascript - \"$app_pid\""))
        XCTAssertTrue(ensureDetailSource.contains("repeat with candidateWindow in windows"))
        XCTAssertFalse(ensureDetailSource.contains("window 1"))
        XCTAssertTrue(script.contains("assert_single_native_toolbar"))
        XCTAssertTrue(script.contains("assert_action_buttons_are_trailing"))
        XCTAssertTrue(script.contains("assert_utility_menu_items_reachable"))
        XCTAssertTrue(script.contains("exercise_toolbar_utilities"))
        XCTAssertTrue(script.contains("exercise_sidebar_entrypoints"))
        XCTAssertTrue(script.contains("press_ax_button \"sidebar-open-search\""))
        XCTAssertTrue(script.contains("wait_for_process_ax_identifier \"command-palette-input\" \"present\""))
        XCTAssertTrue(script.contains("press_ax_button \"sidebar-action-voice-command\""))
        XCTAssertTrue(script.contains("wait_for_process_ax_identifier \"voice-command-quick-command-tab\" \"present\""))
        XCTAssertTrue(script.contains("wait_for_process_ax_identifier \"settings-status-overview\" \"present\""))
        XCTAssertTrue(script.contains("ensure_sidebar_visible"))
        XCTAssertTrue(script.contains("close_window_containing_identifier"))
        XCTAssertTrue(script.contains("exercise_runtime_crud_recovery_entrypoints"))
        XCTAssertTrue(script.contains("SUISUI_HEADER_LAYOUT_ENTRYPOINTS_ONLY"))
        XCTAssertTrue(script.contains("Project Board relocated entrypoint smoke passed"))
        XCTAssertTrue(script.contains("SUISUI_RUNTIME_CRUD_RECOVERY_MODE=1"))
        XCTAssertTrue(script.contains("SUISUI_RUNTIME_CRUD_RECOVERY_MODE=1 \\\n    SUISUI_DISABLE_PROJECT_BOARD_FALLBACK=1"))
        XCTAssertTrue(script.contains("press_ax_button \"project-board-settings-link\""))
        XCTAssertTrue(script.contains("press_ax_button \"project-board-voice-command\""))
        XCTAssertTrue(script.contains("PID-owned AX button was not pressable"))
        XCTAssertTrue(script.contains("click_sidebar_toggle() {\n  press_ax_button \"project-board-sidebar-toggle\"\n}"))
        XCTAssertTrue(script.contains("exercise_keyboard_entrypoints() {\n  launch_header_layout_candidate\n  wait_for_project_detail_visible"))
        let keyboardShortcutStart = try XCTUnwrap(script.range(of: "press_keyboard_shortcut() {"))
        let keyboardShortcutEnd = try XCTUnwrap(
            script.range(of: "\n}\n\n# Utility windows", range: keyboardShortcutStart.upperBound..<script.endIndex)
        )
        let keyboardShortcutSource = String(script[keyboardShortcutStart.lowerBound..<keyboardShortcutEnd.lowerBound])
        XCTAssertTrue(keyboardShortcutSource.contains("restore_project_board_window"))
        XCTAssertTrue(keyboardShortcutSource.contains("click_ax_identifier_center \"project-board-detail\""))
        XCTAssertTrue(keyboardShortcutSource.contains("focus_board=\"${3:-focus-board}\""))
        XCTAssertTrue(keyboardShortcutSource.contains("if [[ \"$focus_board\" == \"focus-board\" ]]"))
        XCTAssertTrue(keyboardShortcutSource.contains("AXMenuItemCmdChar"))
        XCTAssertTrue(keyboardShortcutSource.contains("PID-owned command menu item did not become enabled"))
        let clickCenterStart = try XCTUnwrap(script.range(of: "click_ax_identifier_center() {"))
        let clickCenterEnd = try XCTUnwrap(
            script.range(of: "\n}\n\nwait_for_ax_identifier_present()", range: clickCenterStart.upperBound..<script.endIndex)
        )
        let clickCenterSource = String(script[clickCenterStart.lowerBound..<clickCenterEnd.lowerBound])
        XCTAssertTrue(clickCenterSource.contains("/usr/bin/osascript - \"$app_pid\""))
        XCTAssertTrue(clickCenterSource.contains("repeat with candidateWindow in windows"))
        XCTAssertFalse(clickCenterSource.contains("window 1"))
        XCTAssertTrue(script.contains("press_keyboard_shortcut 40 \"command\""))
        XCTAssertFalse(script.contains("exercise_primary_destination_shortcut()"))
        XCTAssertTrue(
            script.contains(
                "press_keyboard_shortcut 18 \"command\" \"skip-board-focus\"\n  wait_for_process_ax_identifier \"today-workflow\" \"present\"\n  wait_for_process_ax_identifier \"projects-portfolio-overview\" \"absent\"\n  press_keyboard_shortcut 20 \"command\" \"skip-board-focus\"\n  wait_for_process_ax_identifier \"projects-portfolio-overview\" \"present\"\n  wait_for_process_ax_identifier \"today-workflow\" \"absent\"\n  press_keyboard_shortcut 19 \"command\" \"skip-board-focus\"\n  wait_for_process_ax_identifier \"inbox-workflow\" \"present\"\n  wait_for_process_ax_identifier \"projects-portfolio-overview\" \"absent\"\n  press_keyboard_shortcut 21 \"command\" \"skip-board-focus\"\n  wait_for_process_ax_identifier \"review-hub\" \"present\"\n  wait_for_process_ax_identifier \"inbox-workflow\" \"absent\"\n  press_keyboard_shortcut 43 \"command\" \"skip-board-focus\"\n  wait_for_process_ax_identifier \"settings-status-overview\" \"present\""
            )
        )
        XCTAssertTrue(
            script.contains(
                "press_keyboard_shortcut 40 \"command\"\n  wait_for_process_ax_identifier \"command-palette-input\" \"present\"\n  press_keyboard_shortcut 9 \"command-shift\"\n  wait_for_process_ax_identifier \"voice-command-quick-command-tab\" \"present\"\n  press_keyboard_shortcut 18 \"command\" \"skip-board-focus\""
            )
        )
        XCTAssertTrue(script.contains("press_keyboard_shortcut 9 \"command-shift\""))
        XCTAssertTrue(script.contains("press_keyboard_shortcut 43 \"command\""))
        XCTAssertTrue(script.contains("project-board-export-tasks"))
        XCTAssertTrue(script.contains("project-board-import-tasks"))
        XCTAssertTrue(script.contains("task-inspector"))
        XCTAssertTrue(script.contains("embedded-terminal-close"))
        XCTAssertTrue(script.contains("assert_screenshot_has_visible_pixels"))
        XCTAssertTrue(script.contains("close_hydrated_loading_window"))
        XCTAssertTrue(script.contains("project-board-fallback-loading"))
        XCTAssertTrue(script.contains("index($1, wanted \"-\") == 1"))
        XCTAssertTrue(script.contains("wait_for_ax_identifier_absent \"open-panel\""))
        XCTAssertTrue(script.contains("script/ui_evidence_ax_resize_window.swift"))
        XCTAssertTrue(script.contains("700 500 120 160"))
        XCTAssertTrue(script.contains("PID-owned Project Board window frame was not stable enough to resize"))
        XCTAssertTrue(script.contains("restore_project_board_window"))
        XCTAssertTrue(script.contains("every process whose unix id is targetPID"))
        XCTAssertTrue(script.contains("assert_primary_ax_frames_are_nonzero"))
        XCTAssertTrue(script.contains("assert_capture_dimensions"))
        XCTAssertTrue(script.contains("assert_semantic_regions_have_visible_variance"))
        XCTAssertTrue(script.contains("scale_x="))
        XCTAssertTrue(script.contains("scaled_region_component"))
        XCTAssertTrue(script.contains("assert_scaled_region_component_contract"))
        XCTAssertTrue(script.contains("1x AX point-to-image pixel conversion regressed"))
        XCTAssertTrue(script.contains("2x AX point-to-image pixel conversion regressed"))
        XCTAssertTrue(script.contains("SUISUI_WINDOW_OWNER_PID=\"$app_pid\""))
        XCTAssertTrue(script.contains("project-header-add-task"))
        XCTAssertTrue(script.contains("task-card-open-details"))
        XCTAssertTrue(script.contains("resize_window_below_minimum"))
        XCTAssertTrue(script.contains("assert_window_respects_minimum"))
        XCTAssertTrue(script.contains("window_width < 960 || window_height < 620"))
        XCTAssertTrue(script.contains("SUISUI_LANGUAGE_PREFERENCE=\"$language\""))
        XCTAssertTrue(script.contains("launch_header_layout_candidate \"japanese\""))
        XCTAssertTrue(script.contains("Review Task Automation"))
        XCTAssertTrue(script.contains("タスク自動化を確認"))
        XCTAssertTrue(script.contains("sidebar-action-settings"))
        XCTAssertTrue(script.contains("capture_window \"sidebar-visible\""))
        XCTAssertTrue(script.contains("capture_window \"minimum-window\""))
        XCTAssertTrue(script.contains("capture_window \"minimum-window-japanese\""))
        XCTAssertTrue(script.contains("SUISUI_HEADER_LAYOUT_SMOKE_TIMEOUT_SECONDS"))
        XCTAssertTrue(script.contains("script/ui_evidence_window_metadata.swift"))
        XCTAssertTrue(script.contains("BLOCKER: native toolbar controls overlap or clip"))
        XCTAssertTrue(script.contains("BLOCKER: expected one native Project Board toolbar"))
    }

    func testMenuBarPanelHostsSettingsLinkWithoutThemeControls() throws {
        let panelSource = try readPackageFile("Sources/SuisuiApp/Views/MenuBarPanel.swift")

        XCTAssertTrue(panelSource.contains("sceneCoordinator.openInActiveSceneOrRequestNew(route: .settings)"))
        XCTAssertTrue(panelSource.contains("Label(\"Settings\", systemImage: \"gearshape\")"))
        XCTAssertTrue(panelSource.contains(".help(\"Open Settings\")"))
        XCTAssertTrue(panelSource.contains(".accessibilityIdentifier(\"menu-bar-settings-link\")"))
        XCTAssertFalse(panelSource.contains("SettingsLink"))
        XCTAssertFalse(panelSource.contains("Theme"))
        XCTAssertFalse(panelSource.contains("Appearance"))
        XCTAssertFalse(panelSource.contains("SuisuiAppearancePreference"))
        XCTAssertFalse(panelSource.contains("Picker(\"Theme\""))
        XCTAssertFalse(panelSource.contains("Picker(\"Appearance\""))
        XCTAssertFalse(panelSource.contains("settings-theme-picker"))
        XCTAssertFalse(panelSource.contains("appearancePreference"))
        XCTAssertFalse(panelSource.contains(".pickerStyle(.segmented)"))
    }

    func testProjectBoardDropPayloadsAreValidatedByViewModel() throws {
        let boardSource = try readProjectBoardSurfaceSources()
        let coreSource = try readPackageFile("Sources/SuisuiCore/App/ProjectBoard.swift")
        let storeSource = try readPackageFile("Sources/SuisuiCore/WorkManagement/WorkManagementStore.swift")

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
        let boardSource = try readProjectBoardSurfaceSources()
        let workflowSource = try readProjectWorkflowSources()
        let persistenceSource = try readPackageFile("Sources/SuisuiCore/App/ProjectBoardSelectionPersistence.swift")
        let coreSource = try readPackageFile("Sources/SuisuiCore/App/ProjectBoard.swift")
        let modelSource = try readPackageFile("Sources/SuisuiCore/WorkManagement/WorkManagementModels.swift")

        XCTAssertTrue(persistenceSource.contains("case done"))
        XCTAssertTrue(boardSource.contains("review-destination-completed"))
        XCTAssertTrue(boardSource.contains("case .review(.completed):"))
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
        let boardSource = try readProjectBoardSurfaceSources()
        let todayWorkflowSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectWorkflowTodayView.swift")
        let catchUpWorkflowSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectWorkflowCatchUpView.swift")
        let todayFeatureSource = try readPackageFile("Sources/SuisuiCore/App/TodayFeatureViewModel.swift")
        let scheduleWorkflowSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectWorkflowScheduleView.swift")
        let doneWorkflowSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectWorkflowDoneView.swift")
        let coreSource = try readPackageFile("Sources/SuisuiCore/App/ProjectBoard.swift")
        let sqliteStoreSource = try readPackageFile("Sources/SuisuiCore/WorkManagement/WorkManagementSQLiteStore.swift")

        XCTAssertTrue(coreSource.contains("public struct ProjectBoardDerivedReadModels"))
        XCTAssertTrue(coreSource.contains("@Published public private(set) var derivedReadModels"))
        XCTAssertTrue(coreSource.contains("private func rebuildDerivedReadModels("))
        XCTAssertTrue(coreSource.contains("public func refreshScheduleReadModel("))
        XCTAssertTrue(boardSource.contains("let sidebarMetrics = viewModel.derivedReadModels.sidebarMetrics"))
        XCTAssertTrue(boardSource.contains("today: sidebarMetrics.todayCount"))
        XCTAssertTrue(boardSource.contains("schedule: sidebarMetrics.scheduleCount"))
        XCTAssertTrue(boardSource.contains("completed: sidebarMetrics.doneCount"))
        XCTAssertTrue(boardSource.contains("viewModel.derivedReadModels.projectPortfolioSummaries"))
        XCTAssertFalse(boardSource.contains("count: viewModel.todayTasks().count"))
        XCTAssertFalse(boardSource.contains("count: viewModel.missedTaskReview().newlyMissedCount"))
        XCTAssertFalse(boardSource.contains("count: viewModel.unscheduledScheduleTasks().count"))
        XCTAssertFalse(boardSource.contains("count: viewModel.doneAnalytics().completedTaskCount"))
        XCTAssertFalse(boardSource.contains("count: viewModel.projectPortfolioSummaries().count"))

        XCTAssertTrue(todayWorkflowSource.contains("let snapshot = viewModel.snapshot"))
        XCTAssertFalse(todayWorkflowSource.contains("viewModel.todayWorkflowSnapshot(on: referenceDate, calendar: calendar)"))
        XCTAssertTrue(todayFeatureSource.contains("projectTitlesByTaskID"))
        XCTAssertTrue(todayFeatureSource.contains("projectTitlesByTaskID[task.id]"))
        XCTAssertFalse(todayFeatureSource.contains("board.projectTitle(for: task)"))
        XCTAssertTrue(catchUpWorkflowSource.contains("viewModel.missedTaskReview"))
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
        let boardSource = try readProjectBoardSurfaceSources()
        let appearanceSource = try readPackageFile("Sources/SuisuiApp/Views/SuisuiAppearancePreference.swift")

        XCTAssertTrue(appearanceSource.contains("enum SuisuiAppearancePreference"))
        XCTAssertTrue(appearanceSource.contains("case system"))
        XCTAssertTrue(appearanceSource.contains("case light"))
        XCTAssertTrue(appearanceSource.contains("case dark"))
        XCTAssertTrue(appearanceSource.contains("static let storageKey = \"suisui.appearancePreference\""))
        XCTAssertTrue(appearanceSource.contains("static let environmentOverrideKey = \"SUISUI_APPEARANCE_PREFERENCE\""))
        XCTAssertTrue(appearanceSource.contains("static var environmentOverride: SuisuiAppearancePreference?"))
        XCTAssertTrue(appearanceSource.contains("var colorScheme: ColorScheme?"))
        XCTAssertTrue(appSource.contains("@AppStorage(SuisuiAppearancePreference.storageKey)"))
        XCTAssertEqual(appSource.components(separatedBy: "@AppStorage(SuisuiAppearancePreference.storageKey)").count - 1, 2)
        XCTAssertTrue(appSource.contains("private var effectiveAppearancePreference: SuisuiAppearancePreference"))
        XCTAssertTrue(appSource.contains("SuisuiAppearancePreference.environmentOverride ?? appearancePreference"))
        XCTAssertTrue(appSource.contains(".preferredColorScheme(effectiveAppearancePreference.colorScheme)"))
        XCTAssertTrue(appSource.contains("private static var effectiveAppearancePreference: SuisuiAppearancePreference"))
        XCTAssertTrue(appSource.contains("SuisuiAppearancePreference.environmentOverride ?? persistedAppearancePreference"))
        XCTAssertTrue(appSource.contains(".preferredColorScheme(Self.effectiveAppearancePreference.colorScheme)"))
        XCTAssertTrue(appSource.contains("SettingsView("))
        XCTAssertTrue(appSource.contains("appearancePreference: $appearancePreference,"))
        XCTAssertTrue(appSource.contains("@Binding private var appearancePreference: SuisuiAppearancePreference"))
        XCTAssertTrue(appSource.contains("SettingsAppearanceSection(appearancePreference: context.$appearancePreference, languagePreference: context.$languagePreference)"))
        XCTAssertTrue(boardSource.contains("@AppStorage(SuisuiAppearancePreference.storageKey)"))
        XCTAssertFalse(boardSource.contains(".preferredColorScheme(appearancePreference.colorScheme)"))
    }

    func testKanbanTaskCardsExposeMouseDrivenStatusMoveControls() throws {
        let source = try readProjectBoardSurfaceSources()

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
        let source = try readProjectBoardSurfaceSources()
        let cardStart = try XCTUnwrap(source.range(of: "private struct BoardTaskCard"))
        let cardEnd = try XCTUnwrap(source.range(of: "private struct TaskCardSelectableSummary"))
        let cardSource = String(source[cardStart.lowerBound..<cardEnd.lowerBound])

        XCTAssertTrue(source.contains("TaskCardSelectableSummary"))
        XCTAssertTrue(source.contains("TaskDragAffordance"))
        XCTAssertTrue(cardSource.contains("Button(action: onOpenDetails)"))
        XCTAssertTrue(cardSource.contains("TaskCardSelectableSummary("))
        XCTAssertTrue(cardSource.contains("showsSupplementaryContent: showsSupplementaryContent"))
        XCTAssertTrue(cardSource.contains(".accessibilityElement(children: .combine)"))
        XCTAssertTrue(cardSource.contains(".buttonStyle(.plain)"))
        XCTAssertTrue(cardSource.contains(".accessibilityIdentifier(\"task-card-open-details-\\(task.id)\")"))
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
        let source = try readProjectBoardSurfaceSources()

        XCTAssertTrue(source.contains("Drag to another status column"))
        XCTAssertTrue(source.contains("arrow.up.and.down.and.arrow.left.and.right"))
        XCTAssertTrue(source.contains("Drop to move to"))
        XCTAssertTrue(source.contains("isDropTargeted"))
        XCTAssertTrue(source.contains(".dropDestination(for: String.self)"))
        XCTAssertTrue(source.contains(".contentShape(Rectangle())"))
    }

    func testKanbanCardsUseTaskComponentDragPreview() throws {
        let source = try readProjectBoardSurfaceSources()

        XCTAssertTrue(source.contains("BoardTaskDragPreview"))
        XCTAssertTrue(source.contains(".draggable(String(task.id)) {"))
        XCTAssertTrue(source.contains("BoardTaskDragPreview(task: task)"))
    }

    func testKanbanBoardUsesAdaptiveSampleInspiredCardStyling() throws {
        let source = try readProjectBoardSurfaceSources()

        XCTAssertTrue(source.contains("StatusCountBadge"))
        XCTAssertTrue(source.contains("column.status.tint"))
        XCTAssertTrue(source.contains("task.status.tint"))
        XCTAssertTrue(source.contains(".frame(width: ProjectBoardLayoutMetrics.boardColumnWidth"))
        XCTAssertTrue(source.contains(".background(.regularMaterial, in: RoundedRectangle"))
        XCTAssertTrue(source.contains(".shadow(color: Color.black.opacity(0.04)"))
    }

    func testKanbanCardsExposePointerHoverAndStatusRailAffordance() throws {
        let source = try readProjectBoardSurfaceSources()

        XCTAssertTrue(source.contains("@State private var isPointerHovered = false"))
        XCTAssertTrue(source.contains("TaskStatusAccentRail(tint: task.status.tint)"))
        XCTAssertTrue(source.contains("struct TaskStatusAccentRail"))
        XCTAssertTrue(source.contains(".onHover { isPointerHovered = $0 }"))
        XCTAssertTrue(source.contains(".shadow(color: Color.black.opacity(isPointerHovered ? 0.10 : 0.04)"))
        XCTAssertTrue(source.contains(".animation(reduceMotion ? nil : .snappy(duration: 0.16), value: isPointerHovered)"))
    }

    func testTaskCardsUseSampleInspiredNonOverlappingMetadataStrip() throws {
        let source = try readProjectBoardSurfaceSources()
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")
        let audit = try readPackageFile("docs/ux/click-path-audit.md")

        XCTAssertTrue(source.contains("TaskCardMetadataStrip(task: task)"))
        XCTAssertTrue(source.contains("private struct TaskCardMetadataStrip"))
        XCTAssertTrue(source.contains("private struct TaskMetadataLine"))
        XCTAssertTrue(source.contains("private var identityLineValue: String"))
        XCTAssertTrue(source.contains("private var scheduleLineValue: String?"))
        XCTAssertTrue(source.contains("Text(verbatim: value)"))
        XCTAssertTrue(source.contains("components.joined(separator: \" · \")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"task-card-metadata-strip-\\(task.id)\")"))
        XCTAssertTrue(source.contains("recurrenceValue.map"))
        XCTAssertTrue(source.contains("No due date"))
        XCTAssertTrue(source.contains(".minimumScaleFactor(0.82)"))
        XCTAssertTrue(phase.contains("[x] `ui-samples/01.png`、`03.png`、`04.png` を基準に、左サイドバー、中央ボード/リスト、右インスペクタの情報密度を見直す。"))
        XCTAssertTrue(phase.contains("status / priorityとdue / recurrenceを最大2行の意味的なTextへ統合"))
        XCTAssertTrue(audit.contains("Task card metadata strip"))
        XCTAssertTrue(audit.contains("status / priorityとdue / recurrenceを最大2行の意味的なText"))
    }

    func testProjectBoardExposesPrimaryCRUDKeyboardShortcuts() throws {
        let source = try readProjectBoardSurfaceSources()
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
        let boardSource = try readProjectBoardSurfaceSources()
        let toolbarSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardToolbarContent.swift")
        let policySource = try readPackageFile("Sources/SuisuiCore/App/ProjectBoardToolbarLayoutPolicy.swift")
        let terminalSource = try readPackageFile("Sources/SuisuiApp/Views/TerminalPanelView.swift")

        XCTAssertTrue(packageSource.contains(#".package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.13.0")"#))
        XCTAssertTrue(packageSource.contains(#".product(name: "SwiftTerm", package: "SwiftTerm")"#))
        XCTAssertTrue(boardSource.contains("@State private var isTerminalPanelPresented = false"))
        XCTAssertTrue(boardSource.contains("private var isDeveloperModeEnabled: Bool"))
        XCTAssertTrue(boardSource.contains("appSettings().isDeveloperModeEnabled"))
        XCTAssertTrue(boardSource.contains("EmbeddedTerminalPanel("))
        XCTAssertTrue(boardSource.contains("if isTerminalPanelPresented && projectBoardToolbarContext.showsDeveloperTerminal"))
        XCTAssertTrue(boardSource.contains("workingDirectory: terminalWorkingDirectory"))
        XCTAssertTrue(toolbarSource.contains(".accessibilityIdentifier(\"project-board-terminal-toggle\")"))
        XCTAssertTrue(toolbarSource.contains("if context.showsDeveloperTerminal"))
        XCTAssertTrue(toolbarSource.contains(".keyboardShortcut(\"`\", modifiers: [.control])"))
        XCTAssertTrue(policySource.contains("isDeveloperModeEnabled && routeKind == .project"))
        XCTAssertTrue(boardSource.contains("appSettings().defaultWorkspacePath?.trimmingCharacters(in: .whitespacesAndNewlines)"))
        let terminalButtonStart = try XCTUnwrap(toolbarSource.range(of: "if context.showsDeveloperTerminal"))
        let terminalIdentifierEnd = try XCTUnwrap(toolbarSource[terminalButtonStart.lowerBound...].range(of: ".accessibilityIdentifier(\"project-board-terminal-toggle\")"))
        let terminalButtonSource = toolbarSource[terminalButtonStart.lowerBound...terminalIdentifierEnd.upperBound]
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
        let source = try readProjectBoardSurfaceSources()
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
        XCTAssertTrue(composerSource.contains(".accessibilityHint(\"Creates the task in the local Suisui database.\")"))
        XCTAssertTrue(composerSource.contains(".accessibilityHint(\"Cancels task creation and returns focus to the board column.\")"))
        XCTAssertTrue(phase.contains("[x] Inline Task Composerにtitle/detail/priority/due/create/cancelのaccessibility identifier / hintとCommand+Return/Escapeを付ける。"))
        XCTAssertTrue(audit.contains("Inline Task Composerはtitle/detail/priority/due/create/cancelにaccessibility anchorsを持ち"))
    }

    func testInspectorsExposeKeyboardOnlyCrudShortcuts() throws {
        let source = try readProjectBoardInspectorSource()
        let projectInspectorStart = try XCTUnwrap(source.range(of: "struct ProjectInspectorView"))
        let taskInspectorStart = try XCTUnwrap(source.range(of: "struct TaskInspectorView"))
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
        let boardSource = try readProjectBoardSurfaceSources()
        let workflowSource = try readProjectWorkflowSources()
        let appSource = try readAppShellSource()
        let phase = try readPackageFile("tasks/Phase14-QualityRegressionHardening.md")

        let settingsCommand = try sourceBlock(
            in: appSource,
            from: "private struct OpenBoardSettingsCommand: Commands",
            to: "private struct SuisuiWindowCommands: Commands"
        )
        XCTAssertTrue(settingsCommand.contains("requestOpen(route: .settings)"))
        XCTAssertTrue(settingsCommand.contains(".keyboardShortcut(\",\", modifiers: [.command])"))

        let addProjectButton = try sourceBlock(
            in: boardSource,
            from: "Button(action: onCreateProject)",
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
            in: try readProjectBoardInspectorSource(),
            from: "struct ProjectInspectorView",
            to: "private struct ProjectInspectorSuggestionSection"
        )
        XCTAssertTrue(projectInspector.contains(".accessibilityIdentifier(\"project-inspector-save\")"))
        XCTAssertTrue(projectInspector.contains(".keyboardShortcut(\"s\", modifiers: [.command])"))
        XCTAssertTrue(projectInspector.contains(".accessibilityIdentifier(\"project-inspector-delete\")"))
        XCTAssertTrue(projectInspector.contains(".keyboardShortcut(.delete, modifiers: [.command])"))

        let taskInspector = try sourceBlock(
            in: try readProjectBoardInspectorSource(),
            from: "struct TaskInspectorView",
            to: "private struct TaskInspectorSuggestionSection"
        )
        XCTAssertTrue(taskInspector.contains(".accessibilityIdentifier(\"task-inspector-save\")"))
        XCTAssertTrue(taskInspector.contains(".keyboardShortcut(\"s\", modifiers: [.command])"))
        XCTAssertTrue(taskInspector.contains(".accessibilityIdentifier(\"task-inspector-delete\")"))
        XCTAssertTrue(taskInspector.contains(".keyboardShortcut(.delete, modifiers: [.command])"))

        let inboxActions = try sourceBlock(
            in: workflowSource,
            from: "private struct InboxProposedActions",
            to: "private struct InboxRelatedMaterialsSheet"
        )
        XCTAssertTrue(inboxActions.contains("accessibilityIdentifier: \"inbox-action-make-task\""))
        XCTAssertTrue(inboxActions.contains("keyboardShortcut: \"1\""))
        XCTAssertTrue(inboxActions.contains("accessibilityIdentifier: \"inbox-action-make-project\""))
        XCTAssertTrue(inboxActions.contains("keyboardShortcut: \"2\""))
        XCTAssertTrue(inboxActions.contains("accessibilityIdentifier: \"inbox-action-search-related\""))
        XCTAssertTrue(inboxActions.contains(".accessibilityElement(children: .contain)"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-voice-seek\")"))
        XCTAssertTrue(workflowSource.contains("playback.seek(to: $0)"))
        XCTAssertTrue(phase.contains("- [x] Keyboard shortcutがmenu commandまたはfocused actionに接続されていることをsource testで固定する。"))
    }

    func testInspectorSaveControlsStayAdjacentToEditableFieldsBeforeLongSuggestionSections() throws {
        let boardSource = try readProjectBoardInspectorSource()

        let projectInspector = try sourceBlock(
            in: boardSource,
            from: "struct ProjectInspectorView",
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
            from: "struct TaskInspectorView",
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
        let source = try readProjectBoardSurfaceSources()

        XCTAssertTrue(source.contains("TaskInspectorView("))
        XCTAssertTrue(source.contains("onClose: dismissInspector"))
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
        let source = try readProjectBoardInspectorSource()
        let projectInspectorStart = try XCTUnwrap(source.range(of: "struct ProjectInspectorView"))
        let taskInspectorStart = try XCTUnwrap(source.range(of: "struct TaskInspectorView"))
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
        let source = try readProjectBoardSurfaceSources()
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")
        let audit = try readPackageFile("docs/ux/click-path-audit.md")

        XCTAssertTrue(source.contains("TaskInspectorMetadataSummary("))
        XCTAssertTrue(source.contains("task: task, projectTitle: viewModel.projectTitle(for: task)"))
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
        let source = try readProjectBoardSurfaceSources()
        let workflowSource = try readProjectWorkflowSources()
        let coreSource = try readPackageFile("Sources/SuisuiCore/App/ProjectBoard.swift")

        XCTAssertTrue(source.contains("ProjectBoardSidebarView("))
        XCTAssertTrue(source.contains("sidebar-destination-inbox"))
        XCTAssertTrue(source.contains("sidebar-destination-today"))
        XCTAssertTrue(source.contains("sidebar-destination-projects"))
        XCTAssertTrue(source.contains("sidebar-destination-schedule"))
        XCTAssertTrue(source.contains("sidebar-destination-completed"))
        XCTAssertFalse(source.contains("sidebar-destination-review"))
        XCTAssertFalse(
            try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardSidebarView.swift")
                .contains("sidebar-destination-catch-up")
        )
        XCTAssertTrue(source.contains("InboxWorkflowView("))
        XCTAssertTrue(source.contains("TodayWorkflowView("))
        XCTAssertTrue(source.contains("ProjectBoardReviewHubView("))
        XCTAssertTrue(workflowSource.contains("InboxActionPanel("))
        XCTAssertTrue(workflowSource.contains("viewModel.convertSelectedTaskToProject()"))
        XCTAssertTrue(workflowSource.contains("viewModel.scheduleSelectedTaskForToday()"))
        XCTAssertTrue(workflowSource.contains("viewModel.deferSelectedTaskForLater()"))
        XCTAssertTrue(coreSource.contains("public var inboxTasks"))
        XCTAssertTrue(coreSource.contains("public func todayTasks("))
    }

    func testCockpitReviewFixesKeepTodayCalendarAndDoneContractsHonest() throws {
        let dashboardSource = try readPackageFile("Sources/SuisuiApp/Views/TodayDashboardView.swift")
        let calendarFactorySource = try readPackageFile("Sources/SuisuiApp/Composition/GoogleCalendarRuntimeCompositionFactory.swift")
        let doneWorkflowSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectWorkflowDoneView.swift")
        let boardSource = try readPackageFile("Sources/SuisuiCore/App/ProjectBoard.swift")

        XCTAssertTrue(dashboardSource.contains("today-briefing-panel"))
        XCTAssertTrue(dashboardSource.contains("@State private var isWideReviewActionsExpanded = true"))
        XCTAssertFalse(calendarFactorySource.contains("guard (try? credentialStore.loadMetadata()) != nil else { return nil }"))
        XCTAssertTrue(doneWorkflowSource.contains("DoneStatTile(\n                        title: \"Projects\""))
        XCTAssertTrue(doneWorkflowSource.contains("accessibilityTitle: \"Completed Projects\""))
        XCTAssertTrue(doneWorkflowSource.contains("DoneCompletionHeatmapView(buckets: analytics.completionHeatmapBuckets)"))
        // Heatmap stays above receipts so the first viewport shows the recap band.
        let heatmapIndex = try XCTUnwrap(doneWorkflowSource.range(of: "DoneCompletionHeatmapView(buckets: analytics.completionHeatmapBuckets)"))
        let receiptsIndex = try XCTUnwrap(doneWorkflowSource.range(of: "doneExecutionReceiptsPanel"))
        XCTAssertLessThan(heatmapIndex.lowerBound, receiptsIndex.lowerBound)
        XCTAssertFalse(doneWorkflowSource.contains("DoneStatTile(title: \"Total Work\""))
        XCTAssertFalse(boardSource.contains("doneFocusHours"))
    }

    func testPhase12SidebarDestinationRawValuesStayBackwardCompatible() throws {
        let persistenceSource = try readPackageFile("Sources/SuisuiCore/App/ProjectBoardSelectionPersistence.swift")

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

    func testSidebarShowsApprovedDestinationsInSampleOrder() throws {
        let sidebarSource = try readPackageFile(
            "Sources/SuisuiApp/Views/ProjectBoardSidebarView.swift"
        )

        let inboxRow = try XCTUnwrap(sidebarSource.range(of: "sidebar-destination-inbox"))
        let todayRow = try XCTUnwrap(sidebarSource.range(of: "sidebar-destination-today"))
        let projectsRow = try XCTUnwrap(sidebarSource.range(of: "sidebar-destination-projects"))
        let scheduleRow = try XCTUnwrap(sidebarSource.range(of: "sidebar-destination-schedule"))
        let completedRow = try XCTUnwrap(sidebarSource.range(of: "sidebar-destination-completed"))

        XCTAssertLessThan(inboxRow.lowerBound, todayRow.lowerBound)
        XCTAssertLessThan(todayRow.lowerBound, projectsRow.lowerBound)
        XCTAssertLessThan(projectsRow.lowerBound, scheduleRow.lowerBound)
        XCTAssertLessThan(scheduleRow.lowerBound, completedRow.lowerBound)
        XCTAssertFalse(sidebarSource.contains("project-sidebar-row-"))
        XCTAssertFalse(sidebarSource.contains("sidebar-destination-catch-up"))
        XCTAssertFalse(sidebarSource.contains("sidebar-destination-assistant-queue"))
        let projectsSource = try readPackageFile(
            "Sources/SuisuiApp/Views/ProjectBoardProjectsHubView.swift"
        )
        XCTAssertTrue(projectsSource.contains(".tag(BoardRoute.primary(.projects))"))
        XCTAssertTrue(projectsSource.contains(".tag(BoardRoute.project(project.id))"))
        XCTAssertTrue(projectsSource.contains("Label(\"Add Project\", systemImage: \"folder.badge.plus\")"))
        XCTAssertTrue(projectsSource.contains("\"Show Archived\""))
    }

    func testPrimaryDestinationsOwnCommandNumberShortcutsAndInboxUsesControlCommand() throws {
        let boardSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardView.swift")
        let appSource = try readPackageFile("Sources/SuisuiApp/SuisuiApp.swift")
        let coordinatorSource = try readPackageFile("Sources/SuisuiApp/Composition/ProjectBoardSceneCoordinator.swift")
        let windowBridgeSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardWindowStateBridge.swift")
        let workflowSource = try readProjectWorkflowSources()

        XCTAssertFalse(boardSource.contains("ProjectBoardKeyboardShortcutBridge"))
        XCTAssertTrue(boardSource.contains(".suisuiProjectBoardShortcutRequested"))
        XCTAssertTrue(appSource.contains("@ObservedObject private var projectBoardSceneCoordinator"))
        XCTAssertTrue(appSource.contains("projectBoardSceneCoordinator.requestShortcut(.commandPalette)"))
        XCTAssertTrue(appSource.contains("CommandMenu(localizedDisplay(\"Project navigation\"))"))
        XCTAssertFalse(appSource.contains("CommandMenu(\"Navigate\")"))
        for title in ["Search", "Today", "Inbox", "Projects", "Review"] {
            XCTAssertTrue(appSource.contains("Button(localizedDisplay(\"\(title)\"))"))
        }
        XCTAssertTrue(coordinatorSource.contains("func requestShortcut(_ action: ProjectBoardShortcutAction)"))
        XCTAssertTrue(coordinatorSource.contains("if activeSceneID == nil"))
        XCTAssertTrue(windowBridgeSource.contains("NSWindow.didBecomeKeyNotification"))
        XCTAssertTrue(windowBridgeSource.contains("markActive(sceneID: sceneID)"))
        XCTAssertTrue(windowBridgeSource.contains(".suisuiProjectBoardShortcutRequested"))
        XCTAssertTrue(windowBridgeSource.contains("window.deminiaturize(nil)"))
        XCTAssertTrue(windowBridgeSource.contains("window.makeKeyAndOrderFront(nil)"))
        let fallbackStart = try XCTUnwrap(appSource.range(of: "private struct ProjectBoardFallbackRootView"))
        let fallbackEnd = try XCTUnwrap(
            appSource.range(of: "private struct ProjectBoardFallbackLoadingView", range: fallbackStart.upperBound..<appSource.endIndex)
        )
        let fallbackSource = String(appSource[fallbackStart.lowerBound..<fallbackEnd.lowerBound])
        XCTAssertTrue(fallbackSource.contains("ProjectBoardWindowStateBridge("))
        XCTAssertTrue(appSource.contains(".keyboardShortcut(\"k\", modifiers: [.command])"))
        XCTAssertTrue(appSource.contains(".keyboardShortcut(\"1\", modifiers: [.command])"))
        XCTAssertTrue(appSource.contains(".keyboardShortcut(\"2\", modifiers: [.command])"))
        XCTAssertTrue(appSource.contains(".keyboardShortcut(\"3\", modifiers: [.command])"))
        XCTAssertTrue(appSource.contains(".keyboardShortcut(\"4\", modifiers: [.command])"))
        XCTAssertFalse(appSource.contains(".keyboardShortcut(\"5\", modifiers: [.command])"))
        XCTAssertTrue(workflowSource.contains("keyboardShortcut: \"1\""))
        XCTAssertTrue(workflowSource.contains("keyboardShortcut: \"2\""))
        XCTAssertTrue(workflowSource.contains(".keyboardShortcut(\"3\", modifiers: [.command, .control])"))
        XCTAssertTrue(workflowSource.contains(".keyboardShortcut(\"4\", modifiers: [.command, .control])"))
        XCTAssertFalse(workflowSource.contains(".keyboardShortcut(\"5\", modifiers: [.command])"))
    }

    func testInboxActionPanelSurfacesClassificationFeedbackAndUndo() throws {
        let workflowSource = try readProjectWorkflowSources()
        let coreSource = try readPackageFile("Sources/SuisuiCore/App/ProjectBoard.swift")
        let modelSource = try readPackageFile("Sources/SuisuiCore/WorkManagement/WorkManagementModels.swift")

        XCTAssertTrue(modelSource.contains("public struct InboxClassificationFeedback"))
        XCTAssertTrue(coreSource.contains("@Published public private(set) var inboxClassificationFeedback"))
        XCTAssertTrue(coreSource.contains("public func undoLastInboxClassification()"))
        XCTAssertTrue(workflowSource.contains("if let feedback = viewModel.inboxClassificationFeedback"))
        XCTAssertTrue(workflowSource.contains("Label(feedback.message, systemImage: feedback.systemImage)"))
        XCTAssertTrue(workflowSource.contains("viewModel.undoLastInboxClassification()"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-classification-feedback\")"))

        let feedbackStart = try XCTUnwrap(workflowSource.range(of: "if let feedback = viewModel.inboxClassificationFeedback"))
        let feedbackEnd = try XCTUnwrap(workflowSource[feedbackStart.lowerBound...].range(of: "InboxProposedActions("))
        let feedbackBlock = String(workflowSource[feedbackStart.lowerBound..<feedbackEnd.lowerBound])
        XCTAssertTrue(feedbackBlock.contains(".accessibilityElement(children: .contain)"))
        XCTAssertFalse(feedbackBlock.contains(".accessibilityElement(children: .combine)"))
    }

    func testInboxRowsKeepDispositionAccessibleAndUseStableDisplayOrdering() throws {
        let source = try readPackageFile("Sources/SuisuiApp/Views/ProjectWorkflowInboxView.swift")

        XCTAssertTrue(source.contains("private func sortByTitle("))
        XCTAssertTrue(source.contains("localizedStandardCompare"))
        XCTAssertTrue(source.contains("lhs.id < rhs.id"))
        XCTAssertTrue(source.contains("task?.createdAt ?? task?.updatedAt"))
        XCTAssertTrue(source.contains("triageAccessibilityValue"))
        XCTAssertTrue(source.contains("summary.accessibilityValue"))
    }

    func testInboxActionPanelShowsSelectedContextWithoutDuplicatingVoiceMetadata() throws {
        let source = try readPackageFile(
            "Sources/SuisuiApp/Views/ProjectWorkflowInboxView.swift"
        )

        let context = try XCTUnwrap(source.range(of: "InboxSelectedItemContext("))
        let voice = try XCTUnwrap(source.range(of: "InboxVoiceIntakeDetail("))
        let actions = try XCTUnwrap(source.range(of: "InboxProposedActions("))
        XCTAssertLessThan(context.lowerBound, voice.lowerBound)
        XCTAssertLessThan(voice.lowerBound, actions.lowerBound)
        let contextCall = String(source[context.lowerBound..<voice.lowerBound])
        let manualSummaryCondition =
            "manualSummary: task != nil && viewModel.selectedInboxCaptureRecords.isEmpty"

        let contextDefinitionStart = try XCTUnwrap(
            source.range(of: "private struct InboxSelectedItemContext")
        )
        let contextDefinitionEnd = try XCTUnwrap(
            source.range(
                of: "private struct InboxVoiceIntakeDetail",
                range: contextDefinitionStart.upperBound..<source.endIndex
            )
        )
        let contextDefinition = String(
            source[contextDefinitionStart.lowerBound..<contextDefinitionEnd.lowerBound]
        )
        let actionPanelStart = try XCTUnwrap(
            source.range(of: "private struct InboxActionPanel")
        )
        let actionPanelEnd = try XCTUnwrap(
            source.range(
                of: "private struct InboxProposedActions",
                range: actionPanelStart.upperBound..<source.endIndex
            )
        )
        let actionPanel = String(
            source[actionPanelStart.lowerBound..<actionPanelEnd.lowerBound]
        )
        let selectionChangeStart = try XCTUnwrap(
            source.range(of: ".onChange(of: viewModel.selectedTaskID)")
        )
        let selectionChangeEnd = try XCTUnwrap(
            source.range(
                of: "private func mainSurface",
                range: selectionChangeStart.upperBound..<source.endIndex
            )
        )
        let selectionChange = String(
            source[selectionChangeStart.lowerBound..<selectionChangeEnd.lowerBound]
        )

        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"inbox-selected-context\")"))
        XCTAssertTrue(source.contains("Select an Inbox item to classify."))
        XCTAssertTrue(contextDefinition.contains("lineLimit(2)"))
        XCTAssertTrue(contextDefinition.contains("lineLimit(3)"))
        XCTAssertTrue(contextDefinition.contains(".accessibilityElement(children: .contain)"))
        XCTAssertTrue(contextDefinition.contains(".accessibilityIdentifier(\"inbox-selected-item-more\")"))
        XCTAssertTrue(contextCall.contains(manualSummaryCondition))
        XCTAssertTrue(
            actionPanel.contains(".accessibilityLabel(\"Inbox classification actions\")")
        )
        XCTAssertTrue(
            actionPanel.contains(
                ".accessibilityHint(\"Choose how to classify the selected Inbox item.\")"
            )
        )
        XCTAssertFalse(actionPanel.contains(".accessibilityValue("))
        XCTAssertFalse(actionPanel.contains("Selected Inbox item:"))
        XCTAssertFalse(actionPanel.contains("Voice capture metadata available"))
        XCTAssertFalse(actionPanel.contains("Transcript:"))
        XCTAssertFalse(actionPanel.contains("Interpretation:"))
        XCTAssertTrue(
            selectionChange.contains(
                "let capture = viewModel.selectedInboxCaptureRecords.first"
            )
        )
        XCTAssertTrue(selectionChange.contains("voiceMemoCaptureID = capture?.id"))
        XCTAssertTrue(selectionChange.contains("voiceMemoDraft = capture?.memo ?? \"\""))
    }

    func testInboxWorkflowSurfacesVoiceCaptureMetadataWithoutReplacingVoiceCommand() throws {
        let workflowSource = try readProjectWorkflowSources()
        let inboxWorkflowSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectWorkflowInboxView.swift")
        let appSource = try readAppShellSource()
        let coreSource = try readPackageFile("Sources/SuisuiCore/App/ProjectBoard.swift")
        let modelSource = try readPackageFile("Sources/SuisuiCore/WorkManagement/WorkManagementModels.swift")
        let voiceSource = try readPackageFile("Sources/SuisuiCore/Voice/InboxCapture.swift")

        XCTAssertTrue(coreSource.contains("public var selectedInboxCaptureRecords"))
        XCTAssertTrue(voiceSource.contains("func updateMemo(id: Int64, memo: String?) throws -> InboxCaptureRecord"))
        XCTAssertTrue(coreSource.contains("public func updateSelectedInboxCaptureMemo(_ memo: String) -> InboxCaptureRecord?"))
        XCTAssertTrue(modelSource.contains("public struct InboxTriageSummary"))
        XCTAssertTrue(coreSource.contains("public func inboxTriageSummary(for task: ProjectBoardTask) -> InboxTriageSummary"))
        XCTAssertTrue(modelSource.contains("public enum InboxTriageFilter"))
        XCTAssertTrue(coreSource.contains("public var filteredInboxTasks"))
        XCTAssertTrue(coreSource.contains("public func setInboxTriageFilter"))
        XCTAssertTrue(workflowSource.contains("viewModel.inboxReferenceTasks("))
        XCTAssertTrue(workflowSource.contains("viewModel.inboxTriageSummary(for: task)"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-row-triage-summary-\\(task.id)\")"))
        XCTAssertTrue(workflowSource.contains("InboxReferenceHeader("))
        XCTAssertTrue(workflowSource.contains("ForEach(InboxReferenceFilter.allCases)"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-triage-filter\")"))
        XCTAssertTrue(
            workflowSource.contains(
                "private func mainSurface(referenceContentTopPadding: CGFloat) -> some View"
            )
        )
        XCTAssertTrue(workflowSource.contains("InboxTriageRail("))
        XCTAssertTrue(inboxWorkflowSource.contains(".accessibilityIdentifier(\"inbox-compact-workflow-scroll\")"))
        XCTAssertTrue(inboxWorkflowSource.contains(".scrollIndicators(.visible)"))
        XCTAssertTrue(inboxWorkflowSource.contains(".id(\"inbox-wide-workflow\")"))
        XCTAssertTrue(inboxWorkflowSource.contains(".id(\"inbox-compact-workflow\")"))
        let compactScrollStart = try XCTUnwrap(inboxWorkflowSource.range(of: "ScrollView(.vertical) {"))
        let compactScrollEnd = try XCTUnwrap(
            inboxWorkflowSource[compactScrollStart.lowerBound...]
                .range(of: ".accessibilityIdentifier(\"inbox-compact-workflow-scroll\")")
        )
        let compactScrollScope = String(inboxWorkflowSource[compactScrollStart.lowerBound..<compactScrollEnd.upperBound])
        XCTAssertTrue(compactScrollScope.contains("mainSurface"))
        XCTAssertTrue(compactScrollScope.contains("InboxTriageRail("))
        XCTAssertTrue(inboxWorkflowSource.contains("voiceDetailAccessibilityIdentifier: \"inbox-voice-intake-detail\""))
        XCTAssertFalse(inboxWorkflowSource.contains("inbox-voice-intake-detail-compact"))
        XCTAssertTrue(inboxWorkflowSource.contains("task.sourceCommand == \"ui-evidence\""))
        XCTAssertTrue(inboxWorkflowSource.contains("InboxAudioPlaybackController.live()"))
        XCTAssertTrue(inboxWorkflowSource.contains("fileURL: URL(fileURLWithPath: capture.audioFilePath)"))
        XCTAssertFalse(inboxWorkflowSource.contains("private var waveformBars"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-workflow\")"))
        XCTAssertTrue(workflowSource.contains("fillsAvailableHeight ? \"inbox-triage-rail\" : \"inbox-action-panel\""))
        XCTAssertTrue(
            workflowSource.contains(
                ".accessibilityLabel(fillsAvailableHeight ? \"Inbox triage station\" : \"Inbox classification actions\")"
            )
        )
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
        XCTAssertTrue(
            inboxWorkflowSource.contains(
                ".accessibilityLabel(\"Inbox classification actions\")"
            )
        )
        XCTAssertTrue(
            inboxWorkflowSource.contains(
                ".accessibilityHint(\"Choose how to classify the selected Inbox item.\")"
            )
        )
        XCTAssertFalse(inboxWorkflowSource.contains(".accessibilityValue(panelAccessibilityValue)"))
        XCTAssertFalse(inboxWorkflowSource.contains("Voice capture metadata available for \\(task.title)"))
        XCTAssertTrue(inboxWorkflowSource.contains("InboxSelectedItemContext("))
        XCTAssertTrue(workflowSource.contains("taskTitle: task?.title ?? \"Selected Inbox item\""))
        XCTAssertTrue(workflowSource.contains("InboxProposedActions("))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-proposed-actions\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(accessibilityIdentifier)"))
        let voiceDetailStart = try XCTUnwrap(workflowSource.range(of: "private struct InboxVoiceIntakeDetail"))
        let voiceDetailSource = String(workflowSource[voiceDetailStart.lowerBound...])
        XCTAssertEqual(
            voiceDetailSource.components(separatedBy: ".accessibilityIdentifier(accessibilityIdentifier)").count - 1,
            1
        )
        let voiceDetailTarget = try XCTUnwrap(voiceDetailSource.range(
            of: ".accessibilityIdentifier(accessibilityIdentifier)"
        ))
        let containedChildren = try XCTUnwrap(voiceDetailSource.range(of: ".accessibilityElement(children: .contain)"))
        XCTAssertLessThan(containedChildren.lowerBound, voiceDetailTarget.lowerBound)
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-voice-transcript-preview\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-voice-waveform\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-voice-transcript\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-voice-interpretation\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-voice-memo\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-voice-memo-editor\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-voice-memo-save\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-voice-source-metadata\")"))
        XCTAssertFalse(workflowSource.contains(".accessibilityIdentifier(\"inbox-voice-review-status\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityElement(children: .contain)"))
        XCTAssertTrue(workflowSource.contains("Voice memo playback"))
        XCTAssertTrue(workflowSource.contains("Playable voice memo, duration %@"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-voice-playback-toggle\")"))
        XCTAssertTrue(workflowSource.contains("playbackAccessibilityValue"))
        XCTAssertTrue(workflowSource.contains(".disabled(!playback.isPlayable)"))
        XCTAssertTrue(workflowSource.contains(".disabled(!playback.isSeekable)"))
        XCTAssertTrue(workflowSource.contains("playback.isRetryAvailable"))
        XCTAssertTrue(workflowSource.contains(".opacity(0.01)"))
        XCTAssertTrue(workflowSource.contains(".frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32)"))
        XCTAssertTrue(workflowSource.contains("playback.errorMessage ?? playbackAccessibilityValue"))
        XCTAssertTrue(workflowSource.contains("inbox-voice-playback-error"))
        XCTAssertFalse(workflowSource.contains("Transcript-only voice capture, duration %@, waveform preview"))
        XCTAssertFalse(workflowSource.contains("Playback unavailable in this MVP"))
        XCTAssertFalse(workflowSource.contains("Button {} label:"))
        XCTAssertTrue(workflowSource.contains(".accessibilityLabel(title)"))
        XCTAssertTrue(workflowSource.contains(".accessibilityValue(value)"))
        XCTAssertTrue(workflowSource.contains(".accessibilityLabel(\"Voice intake detail for \\(taskTitle)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityValue(captureAccessibilityValue(capture))"))
        XCTAssertTrue(workflowSource.contains("localizedInboxCaptureDuration(capture.durationSeconds)"))
        XCTAssertTrue(workflowSource.contains("capture.transcript"))
        XCTAssertTrue(workflowSource.contains("localizedInboxCaptureClassification(capture.classificationStatus)"))
        XCTAssertTrue(workflowSource.contains("localizedInboxCaptureTranscription(capture.transcriptionStatus)"))
        XCTAssertTrue(workflowSource.contains("localizedInboxCaptureSource(capture.sourceKind)"))
        XCTAssertTrue(workflowSource.contains("Transcript failed. Review the original voice memo before converting."))
        XCTAssertTrue(workflowSource.contains("AI interpretation unavailable because transcription failed."))
        XCTAssertTrue(workflowSource.contains("No AI interpretation yet."))
        XCTAssertTrue(coreSource.contains("private var inboxCaptureRecordsByTaskID: [Int64: [InboxCaptureRecord]]"))
        XCTAssertTrue(coreSource.contains("$0.transcriptionStatus == .succeeded"))
        XCTAssertTrue(appSource.contains("let inboxCaptureStore = SQLiteInboxCaptureStore(connection: connection)"))
        XCTAssertTrue(appSource.contains("inboxCaptureStore: inboxCaptureStore"))
        XCTAssertTrue(appSource.contains("VoiceCaptureWorkspaceHost("))
    }

    func testInboxWorkflowMatchesReferenceListAndDetailComposition() throws {
        let source = try readPackageFile("Sources/SuisuiApp/Views/ProjectWorkflowInboxView.swift")

        XCTAssertTrue(source.contains("private struct InboxReferenceHeader"))
        XCTAssertTrue(source.contains("private struct InboxReferenceTaskList"))
        XCTAssertTrue(source.contains("private struct InboxReferenceTaskRow"))
        XCTAssertTrue(source.contains("private struct InboxTriageRail"))
        XCTAssertTrue(source.contains("Menu(\"Sort\", systemImage: \"arrow.up.arrow.down\")"))
        XCTAssertTrue(source.contains("Menu(\"Filter\", systemImage: \"line.3.horizontal.decrease\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"inbox-reference-header\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"inbox-reference-task-list\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"inbox-reference-detail\")"))
        XCTAssertTrue(source.contains("Text(\"Proposed Actions\")"))
        XCTAssertTrue(source.contains("Text(\"Details Information\")"))
        XCTAssertTrue(source.contains("confirmationDialog("))
        XCTAssertFalse(source.contains("WorkflowTaskSurface("))
    }

    func testInboxDetailUsesReferenceMatchedVerticalMetrics() throws {
        let source = try readPackageFile("Sources/SuisuiApp/Views/ProjectWorkflowInboxView.swift")
        let seederSource = try readPackageFile("Sources/SuisuiVisualFixtureSeeder/main.swift")
        let english = try readPackageFile("Sources/SuisuiApp/Resources/en.lproj/Localizable.strings")
        let japanese = try readPackageFile("Sources/SuisuiApp/Resources/ja.lproj/Localizable.strings")
        let actionStyleStart = try XCTUnwrap(
            source.range(of: "private struct InboxTriageActionButtonStyle")
        )
        let proposedActionsStart = try XCTUnwrap(source.range(of: "private struct InboxProposedActions"))
        let proposedActionsEnd = try XCTUnwrap(
            source.range(
                of: "private struct InboxRelatedMaterialsSheet",
                range: proposedActionsStart.upperBound..<source.endIndex
            )
        )
        let detailsStart = try XCTUnwrap(source.range(of: "private struct InboxReferenceDetails"))
        let detailsEnd = try XCTUnwrap(
            source.range(of: "private func normalizedInboxDetail", range: detailsStart.upperBound..<source.endIndex)
        )
        let voiceStart = try XCTUnwrap(source.range(of: "private struct InboxVoiceIntakeDetail"))
        let copyTranscriptStart = try XCTUnwrap(
            source.range(of: "private func copyTranscript", range: voiceStart.upperBound..<source.endIndex)
        )

        let actionStyle = String(source[actionStyleStart.lowerBound..<proposedActionsStart.lowerBound])
        let proposedActions = String(source[proposedActionsStart.lowerBound..<proposedActionsEnd.lowerBound])
        let details = String(source[detailsStart.lowerBound..<detailsEnd.lowerBound])
        let transcript = String(source[voiceStart.lowerBound..<copyTranscriptStart.lowerBound])

        XCTAssertTrue(actionStyle.contains(".frame(height: 36)"))
        XCTAssertTrue(actionStyle.contains("RoundedRectangle(cornerRadius: 10)"))
        XCTAssertFalse(actionStyle.contains("Capsule()"))
        XCTAssertTrue(
            actionStyle.contains("isProminent ? Color.accentColor : Color.clear")
        )
        XCTAssertTrue(
            actionStyle.contains("isProminent ? Color.clear : Color.secondary.opacity(0.20)")
        )
        XCTAssertTrue(transcript.contains(".lineSpacing(4)"))
        XCTAssertTrue(
            transcript.contains(".frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)")
        )
        // Context already owns the Voice Memo chrome; intake detail starts at playback.
        XCTAssertFalse(transcript.contains("Text(\"Voice Memo\")"))
        XCTAssertTrue(transcript.contains(".accessibilityIdentifier(\"inbox-voice-interpretation\")"))
        XCTAssertFalse(
            transcript.contains("DisclosureGroup(\"AI Interpretation\", isExpanded: .constant(true))")
        )
        XCTAssertTrue(proposedActions.contains(".frame(height: 36)"))
        XCTAssertFalse(proposedActions.contains(".padding(.vertical, 13)"))
        XCTAssertTrue(details.contains(".frame(minHeight: 38)"))
        XCTAssertFalse(details.contains(".padding(.vertical, 14)"))
        XCTAssertFalse(
            source.contains(
                ".accessibilityIdentifier(\"inbox-proposed-actions\")\n            .padding(.bottom, 8)"
            )
        )
        XCTAssertTrue(
            source.contains(".frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32)")
        )
        XCTAssertTrue(source.contains(".padding(.top, 8)"))
        let actionPanelStart = try XCTUnwrap(source.range(of: "private struct InboxActionPanel"))
        let actionPanelEnd = try XCTUnwrap(
            source.range(
                of: "private struct InboxTriageActionButtonStyle",
                range: actionPanelStart.upperBound..<source.endIndex
            )
        )
        let actionPanel = String(source[actionPanelStart.lowerBound..<actionPanelEnd.lowerBound])
        XCTAssertTrue(actionPanel.contains("VStack(alignment: .leading, spacing: 12)"))
        XCTAssertTrue(actionPanel.contains(".padding(.horizontal, 14)"))
        XCTAssertTrue(actionPanel.contains(".padding(.top, 14)"))
        XCTAssertTrue(source.contains("Button(\"Show Note\""))
        XCTAssertFalse(source.contains("Show AI Interpretation and Note"))
        XCTAssertTrue(seederSource.contains("var envelopeSeed: UInt64 = 0x5A17_C9E3"))
        XCTAssertTrue(seederSource.contains("let speechEnvelope = (0...64).map"))
        XCTAssertTrue(seederSource.contains("envelopeSeed &*= 6_364_136_223_846_793_005"))
        XCTAssertTrue(seederSource.contains("let targetPeak = 0.65 + unitPeak * 0.35"))
        XCTAssertTrue(seederSource.contains("smoothedPeak += (targetPeak - smoothedPeak) * 0.35"))
        XCTAssertTrue(seederSource.contains("let easedBlend = blend * blend * (3 - 2 * blend)"))
        XCTAssertFalse(seederSource.contains("sin(progress *"))
        XCTAssertTrue(source.contains("inboxHeader(referenceContentTopPadding: 10)"))
        XCTAssertTrue(source.contains("mainSurface(referenceContentTopPadding: 0)"))
        XCTAssertTrue(source.contains(".padding(.bottom, referenceContentTopPadding)"))
        XCTAssertTrue(source.contains("return \"waveform\""))
        XCTAssertTrue(source.contains("return \"sparkle\""))
        XCTAssertFalse(source.contains("return \"arrow.uturn.left\""))
        XCTAssertTrue(japanese.contains("\"Inbox reference presentation metadata\" = \"山田さんからの音声メモ · 今日 10:15\";"))
        XCTAssertTrue(japanese.contains("\"Today %@ · Taro Yamada (you)\" = \"今日 %@ · 山田太郎（あなた）\";"))
        XCTAssertTrue(english.contains("\"Today %@ · Taro Yamada (you)\" = \"Today %@ · Taro Yamada (you)\";"))
        XCTAssertTrue(english.contains("\"Convert to Task\" = \"Convert\";"))
        XCTAssertTrue(japanese.contains("\"Convert to Task\" = \"タスクに変換\";"))
        XCTAssertTrue(english.contains("\"Show Note\" = \"Show Note\";"))
        XCTAssertTrue(japanese.contains("\"Show Note\" = \"メモを表示\";"))
    }

    func testInboxReferenceUIUsesPersistedTriageLifecycle() throws {
        let source = try readPackageFile("Sources/SuisuiApp/Views/ProjectWorkflowInboxView.swift")

        XCTAssertTrue(source.contains("viewModel.createInboxTask(title: title)"))
        XCTAssertTrue(source.contains("task.createdAt"))
        XCTAssertTrue(source.contains("viewModel.inboxTriageRecord(for:"))
        XCTAssertTrue(source.contains("viewModel.refreshInboxReviewAvailability(at:"))
    }

    func testInboxSelectionKeepsTriageInWorkflowInsteadOfInspector() throws {
        let boardSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardView.swift")
        let workflowSource = try readProjectWorkflowSources()

        XCTAssertTrue(boardSource.contains("InboxWorkflowView("))
        XCTAssertTrue(boardSource.contains("selectInboxTask: selectInboxTask"))
        XCTAssertTrue(boardSource.contains("route: currentBoardRoute"))
        XCTAssertTrue(boardSource.contains("private func selectInboxTask(_ task: ProjectBoardTask)"))
        XCTAssertTrue(boardSource.contains("allowsCompactInspectorPresentation = false"))
        XCTAssertTrue(boardSource.contains("InspectorPresentationPolicy.shouldPresent("))
        XCTAssertTrue(workflowSource.contains("var selectInboxTask: (ProjectBoardTask) -> Void = { _ in }"))
        XCTAssertTrue(workflowSource.contains("onSelectTask: selectInboxTask"))
        XCTAssertTrue(workflowSource.contains("memoDraft: $voiceMemoDraft"))
        XCTAssertTrue(workflowSource.contains("memoCaptureID: $voiceMemoCaptureID"))
        XCTAssertTrue(workflowSource.contains(".cockpitSplitSecondaryRail(width: railWidth)"))
        XCTAssertTrue(workflowSource.contains("CockpitSplitLayout.railWidth(for: .inbox"))
        XCTAssertTrue(workflowSource.contains(".padding(.trailing, 18)"))
        XCTAssertTrue(workflowSource.contains(".frame(maxWidth: .infinity, minHeight: 84"))

        let overrideStart = try XCTUnwrap(boardSource.range(of: "private func applySelectedTaskOverrideIfNeeded()"))
        let overrideEnd = try XCTUnwrap(boardSource[overrideStart.lowerBound...].range(of: "private func selectTodayTask"))
        let overrideBlock = String(boardSource[overrideStart.lowerBound..<overrideEnd.lowerBound])
        XCTAssertTrue(overrideBlock.contains("allowsCompactInspectorPresentation = false"))
        XCTAssertFalse(overrideBlock.contains("requestInspectorPresentation()"))
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
        XCTAssertTrue(workflowSource.contains(".accessibilityHint(\"Updates the task status in the local Suisui database without opening the inspector.\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-quick-add-title\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-quick-add-button\")"))
        XCTAssertTrue(workflowSource.contains(".keyboardShortcut(.return, modifiers: [.command])"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"workflow-task-row-\\(task.id)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityLabel(\"Open task \\(task.title)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityValue(workflowAccessibilityValue)"))
        XCTAssertTrue(
            workflowSource.contains(
                "accessibilityIdentifier: fillsAvailableHeight ? \"inbox-action-panel\" : \"inbox-action-panel-content\""
            )
        )
        XCTAssertTrue(workflowSource.contains("accessibilityIdentifier: \"inbox-action-make-task\""))
        XCTAssertTrue(workflowSource.contains("accessibilityIdentifier: \"inbox-action-make-project\""))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-action-schedule-today\")"))
        XCTAssertTrue(
            workflowSource.contains(
                ".accessibilityElement(children: .contain)\n        .accessibilityIdentifier(\"inbox-selected-context\")"
            )
        )
        // The voice seek control deliberately uses a nearly transparent native
        // slider over the visible waveform so AX and keyboard actions remain real.
        let permittedTransparentSliderCount = workflowSource.components(
            separatedBy: ".opacity(0.01)"
        ).count - 1
        XCTAssertEqual(permittedTransparentSliderCount, 1)
        XCTAssertFalse(workflowSource.contains(".frame(width: 1, height: 1)"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"inbox-action-review-later\")"))
        XCTAssertTrue(workflowSource.contains("keyboardShortcut: \"1\""))
        XCTAssertTrue(workflowSource.contains("keyboardShortcut: \"2\""))
        XCTAssertTrue(workflowSource.contains(".keyboardShortcut(\"3\", modifiers: [.command, .control])"))
        XCTAssertTrue(workflowSource.contains(".keyboardShortcut(\"4\", modifiers: [.command, .control])"))
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

    func testWorkflowTaskRowKeepsCompletionAndSelectionAsSeparateAccessibilityButtons() throws {
        let workflowSource = try readProjectWorkflowSources()
        let surfaceStart = try XCTUnwrap(workflowSource.range(of: "struct WorkflowTaskSurface"))
        let surfaceEnd = try XCTUnwrap(workflowSource[surfaceStart.lowerBound...].range(of: "struct WorkflowDoneToggle"))
        let surfaceSource = String(workflowSource[surfaceStart.lowerBound..<surfaceEnd.lowerBound])
        let rowStart = try XCTUnwrap(workflowSource.range(of: "private struct WorkflowTaskRow: View"))
        let rowEnd = try XCTUnwrap(workflowSource[rowStart.lowerBound...].range(of: "private var workflowAccessibilityValue"))
        let rowSource = String(workflowSource[rowStart.lowerBound..<rowEnd.lowerBound])

        XCTAssertFalse(
            rowSource.contains(".accessibilityElement(children: .ignore)"),
            "Ignoring a native Button's children changes its macOS accessibility role from AXButton to AXUnknown."
        )
        XCTAssertEqual(
            rowSource.components(separatedBy: ".accessibilityElement(children: .combine)").count - 1,
            1,
            "Combine only the selection button's visible text while preserving the native button role."
        )
        XCTAssertTrue(rowSource.contains(".accessibilityIdentifier(\"workflow-task-completion-\\(task.id)\")"))
        XCTAssertTrue(rowSource.contains(".accessibilityIdentifier(\"workflow-task-row-\\(task.id)\")"))
        XCTAssertFalse(
            surfaceSource.contains(".draggable(String(task.id))"),
            "Do not wrap both sibling controls in a single drag source."
        )
        XCTAssertTrue(
            rowSource.contains(".draggable(String(task.id))"),
            "Keep drag-and-drop on the selection control so the sibling completion button remains accessible."
        )
    }

    func testProjectDetailOrganizesTasksArtifactsTimelineAndSuggestions() throws {
        let source = try readProjectBoardSurfaceSources()
        let coreSource = try readPackageFile("Sources/SuisuiCore/App/ProjectBoard.swift")
        let modelSource = try readPackageFile("Sources/SuisuiCore/WorkManagement/WorkManagementModels.swift")
        let storeSource = try readPackageFile("Sources/SuisuiCore/WorkManagement/WorkManagementStore.swift")
        let sqliteStoreSource = try readPackageFile("Sources/SuisuiCore/WorkManagement/WorkManagementSQLiteStore.swift")

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
        XCTAssertTrue(source.contains("applyProjectDirectory(url:"))
        XCTAssertTrue(source.contains("viewModel.assignProjectWorkspacePath"))
        XCTAssertTrue(source.contains("viewModel.clearProjectWorkspacePath"))
        XCTAssertTrue(source.contains("viewModel.reportProjectWorkspaceSelectionFailure"))
        XCTAssertFalse(source.contains("let bookmarkData = try? url.bookmarkData"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-workspace-current\")"))
        XCTAssertTrue(source.contains("browseAccessibilityIdentifier: \"project-workspace-choose\""))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-workspace-clear\")"))
        XCTAssertTrue(source.contains("LocalPathSelectionField("))
        XCTAssertTrue(source.contains("accessibilityIdentifier: \"project-workspace-path-input\""))
        XCTAssertTrue(source.contains("applyProjectDirectory(url:"))
        XCTAssertTrue(modelSource.contains("public var workspacePath: String?"))
        XCTAssertTrue(source.contains("Section(\"Development Automation\")"))
        XCTAssertTrue(source.contains("ProjectDevelopmentAutomationPanel("))
        XCTAssertTrue(source.contains("developmentTaskID: developmentTaskID"))
        XCTAssertTrue(source.contains("let developmentTaskID: Int64?"))
        XCTAssertTrue(source.contains("private var developmentTask: ProjectBoardTask?"))
        XCTAssertTrue(source.contains("project.tasks.first { $0.id == developmentTaskID }"))
        XCTAssertTrue(source.contains("onReviewDevelopmentAutomation: onReviewDevelopmentAutomation"))
        XCTAssertTrue(source.contains("viewModel.developmentAutomationReadiness(for: project, task: developmentTask)"))
        XCTAssertTrue(source.contains("viewModel.prepareDevelopmentAutomationReview(for: project, task: developmentTask)"))
        XCTAssertTrue(source.contains("developmentAutomationReviewSession(plan)"))
        XCTAssertTrue(source.contains("ActionReviewPanel(viewModel: sheet.viewModel)"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-status\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-branch-preview\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-review\")"))
        XCTAssertTrue(source.contains("viewModel.enqueueDevelopmentAutomationReview(for: project, task: developmentTask)"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-queue\")"))
        XCTAssertTrue(source.contains("viewModel.enqueueDevelopmentVerificationReview(for: project, task: developmentTask)"))
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
        XCTAssertTrue(source.contains("viewModel.enqueueDevelopmentPushReview(for: project, task: developmentTask)"))
        XCTAssertTrue(source.contains("Queue branch push review"))
        XCTAssertTrue(source.contains("execution rechecks the current branch, clean workspace, and GitHub origin before running"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-push-queue\")"))
        XCTAssertTrue(source.contains("viewModel.developmentPullRequestCreationDraft(for: project, task: developmentTask)"))
        XCTAssertTrue(source.contains("viewModel.enqueueDevelopmentPullRequestCreationReview("))
        XCTAssertTrue(source.contains("Queue pull request creation review"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-pr-base\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-pr-title\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-pr-body\")"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Pull request body\")"))
        XCTAssertTrue(source.contains("developmentProgress.canQueuePullRequestCreationReview"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-pr-create-queue\")"))
        XCTAssertTrue(source.contains("viewModel.developmentAutomationProgress(for: project, task: developmentTask)"))
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

    func testPathInputsSupportTypingAndNativeFinderSelection() throws {
        let componentPath = packageRoot().appendingPathComponent("Sources/SuisuiApp/Views/LocalPathSelectionField.swift")
        guard FileManager.default.fileExists(atPath: componentPath.path) else {
            XCTFail("LocalPathSelectionField.swift must provide the shared typed path and Finder picker control.")
            return
        }
        let componentSource = try readPackageFile("Sources/SuisuiApp/Views/LocalPathSelectionField.swift")
        let settingsSource = try readPackageFile("Sources/SuisuiApp/Views/SettingsFeatureViews.swift")
        let projectSource = try readProjectBoardInspectorSource()

        XCTAssertTrue(componentSource.contains("TextField("))
        XCTAssertTrue(componentSource.contains("NSOpenPanel()"))
        XCTAssertTrue(componentSource.contains("panel.canChooseFiles = selectionKind.canChooseFiles"))
        XCTAssertTrue(componentSource.contains("panel.canChooseDirectories = selectionKind.canChooseDirectories"))
        XCTAssertTrue(componentSource.contains("panel.directoryURL = initialDirectoryURL"))
        XCTAssertTrue(componentSource.contains(".accessibilityIdentifier(accessibilityIdentifier)"))
        XCTAssertTrue(componentSource.contains(#"browseAccessibilityIdentifier ?? "\(accessibilityIdentifier)-browse""#))

        XCTAssertTrue(settingsSource.contains("accessibilityIdentifier: \"settings-whisper-cpp-executable-path\""))
        XCTAssertTrue(settingsSource.contains("accessibilityIdentifier: \"settings-kokoro-executable-path\""))
        XCTAssertTrue(settingsSource.contains("accessibilityIdentifier: \"settings-default-workspace-path\""))
        XCTAssertTrue(settingsSource.contains("accessibilityIdentifier: \"settings-mcp-working-directory\""))
        XCTAssertTrue(projectSource.contains("accessibilityIdentifier: \"project-development-automation-edit-path\""))
    }

    func testProjectDetailSurfacesMilestonesTimelineAndAssistantWithoutDroppingExistingSections() throws {
        let source = try readProjectBoardSurfaceSources()
        let coreSource = try readPackageFile("Sources/SuisuiCore/App/ProjectBoard.swift")
        let modelSource = try readPackageFile("Sources/SuisuiCore/WorkManagement/WorkManagementModels.swift")

        XCTAssertTrue(source.contains("ProjectMilestoneSection(project: project, viewModel: viewModel)"))
        XCTAssertTrue(source.contains("ProjectAssistantPanel(project: project, viewModel: viewModel)"))
        XCTAssertTrue(source.contains("ProjectArtifactSection(project: project, viewModel: viewModel)"))
        XCTAssertTrue(source.contains("ProjectLocalSuggestionPanel("))
        XCTAssertTrue(source.contains("onOpenTaskInspector: onOpenTaskInspector"))
        XCTAssertTrue(source.contains("project.milestones"))
        XCTAssertTrue(source.contains("case .milestone"))
        XCTAssertTrue(source.contains("viewModel.createProjectMilestone"))
        XCTAssertTrue(source.contains("viewModel.answerProjectAssistantQuestion"))
        XCTAssertTrue(source.contains("viewModel.prepareProjectAssistantSuggestedActionForReview"))
        XCTAssertTrue(source.contains("CockpitSplitLayout.presentsSplitRail("))
        XCTAssertTrue(source.contains("cockpitSplitSecondaryRail(width: railWidth)"))
        XCTAssertTrue(source.contains("project-timeline-week"))
        XCTAssertTrue(source.contains("ProjectTimelineWeekStrip"))
        XCTAssertTrue(source.contains("orderedMilestones"))
        XCTAssertFalse(source.contains("moveTask(id: suggestedTask.id, to: .inProgress)"))

        XCTAssertTrue(modelSource.contains("public struct ProjectBoardMilestone"))
        XCTAssertTrue(modelSource.contains("public var milestones: [ProjectBoardMilestone]"))
        XCTAssertTrue(coreSource.contains("ProjectAssistantReviewDraft"))
    }

    func testTaskInspectorGroupsEditingDeletionAndSuggestionApplication() throws {
        let source = try readProjectBoardSurfaceSources()

        XCTAssertTrue(source.contains("TaskInspectorSuggestionSection"))
        XCTAssertTrue(source.contains("Apply Suggestion"))
        XCTAssertTrue(source.contains("viewModel.moveSelectedTask(to:"))
        XCTAssertTrue(source.contains("Section(\"Edit\")"))
        XCTAssertTrue(source.contains("Section(\"Suggestion\")"))
        XCTAssertTrue(source.contains("Section(\"Danger Zone\")"))
    }

    func testProjectInspectorGroupsEditingDeletionAndSuggestionApplication() throws {
        let source = try readProjectBoardSurfaceSources()
        let detailSource = try readProjectBoardDetailSource()
        let headerStart = try XCTUnwrap(detailSource.range(of: "private struct ProjectHeaderActions"))
        let boardStart = try XCTUnwrap(detailSource.range(of: "private struct ProjectKanbanBoard"))
        let headerSource = String(detailSource[headerStart.lowerBound..<boardStart.lowerBound])

        XCTAssertTrue(source.contains("ProjectInspectorView("))
        XCTAssertTrue(source.contains("project: project,"))
        XCTAssertTrue(source.contains("viewModel: viewModel,"))
        XCTAssertTrue(source.contains("onClose: dismissInspector"))
        XCTAssertTrue(source.contains("ProjectInspectorSuggestionSection"))
        XCTAssertTrue(source.contains("@SceneStorage(\"projectBoard.userRequestedInspector\")"))
        XCTAssertTrue(source.contains("selectedProjectForInspector"))
        XCTAssertTrue(source.contains("private func dismissInspector()"))
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
        let source = try readProjectBoardSurfaceSources()

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
        XCTAssertTrue(source.contains(".accessibilityValue(showsArchivedProjects ? \"On\" : \"Off\")"))
        XCTAssertTrue(source.contains(".accessibilityHint(\"Shows archived projects in the sidebar without deleting local data.\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-board-add-project\")"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Add Project\")"))
        XCTAssertTrue(source.contains(".accessibilityHint(\"Creates a new local project and selects it.\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-header-add-task\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(targetStatus.map { \"task-status-move-\\($0.rawValue)-\\(task.id)\" } ?? \"task-status-move-disabled-\\(task.id)\")"))
        XCTAssertTrue(source.contains(".help(\"Creates the task in the local Suisui database\")"))
        XCTAssertTrue(source.contains(".help(\"Cancels task creation and returns focus to the board column\")"))
        XCTAssertTrue(source.contains(".help(\"Applies the local next-step suggestion to the selected task\")"))
        XCTAssertTrue(source.contains(".help(\"Saves edits to the selected task in the local Suisui database\")"))
        XCTAssertTrue(source.contains(".help(\"Deletes the selected task after confirmation\")"))
        XCTAssertTrue(source.contains(".help(\"Applies the local next-step suggestion to the selected project\")"))
        XCTAssertTrue(source.contains(".help(\"Saves edits to the selected project in the local Suisui database\")"))
        XCTAssertTrue(source.contains(".help(\"Restores the selected project to active views in the local Suisui database\")"))
        XCTAssertTrue(source.contains(".help(\"Completes the selected project in the local Suisui database\")"))
        XCTAssertTrue(source.contains(".help(\"Archives the selected project after confirmation\")"))
        XCTAssertTrue(source.contains(".help(\"Deletes the selected project after confirmation\")"))
        XCTAssertTrue(source.contains("\"Archive this project?\""))
        XCTAssertTrue(source.contains("\"Delete this project?\""))
        XCTAssertTrue(source.contains("\"Delete this task?\""))
    }

    func testProjectBoardVoiceOverFocusPathIsSourceAnchored() throws {
        let boardSource = try readProjectBoardSurfaceSources()
        let audit = try readPackageFile("docs/ux/click-path-audit.md")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")

        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"project-board-sidebar\")"))
        XCTAssertTrue(
            boardSource.contains(
                ".accessibilityLabel(Text(LocalizedStringKey(\"Project navigation\")))"
            )
        )
        XCTAssertTrue(boardSource.contains("LocalizedStringKey(\"Navigate work or open a quick action.\")"))
        XCTAssertTrue(boardSource.contains("sidebar-destination-today"))
        XCTAssertTrue(boardSource.contains("sidebar-destination-schedule"))
        XCTAssertTrue(boardSource.contains("sidebar-destination-completed"))
        XCTAssertFalse(boardSource.contains("sidebar-destination-review"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"project-sidebar-row-\\(project.id)\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityLabel(project.accessibilityProjectsHubLabel)"))
        XCTAssertTrue(boardSource.contains(".tag(BoardRoute.project(project.id))"))

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
        XCTAssertTrue(boardSource.contains(".accessibilityHint(\"Saves edits to the selected task in the local Suisui database.\")"))
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
        XCTAssertTrue(boardSource.contains(".accessibilityHint(\"Completes the selected project in the local Suisui database.\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityHint(\"Archives the selected project after confirmation.\")"))
        XCTAssertTrue(audit.contains("source-level VoiceOver focus anchors are fixed"))
        XCTAssertTrue(audit.contains("Task / Project inspectorのfield、提案適用、保存、complete、restore、archive、deleteはaccessibility identifier / hintを持ち"))
        XCTAssertTrue(phase.contains("[x] Sidebar -> board detail -> task card -> inspector edit/save/delete のsource-level focus anchorsを固定する。"))
        XCTAssertTrue(phase.contains("[x] Task / Project inspector のfield、提案適用、save、complete、restore、archive、deleteにaccessibility identifier / hintを付け"))
        XCTAssertTrue(phase.contains("[ ] 実機VoiceOverでProject board -> card -> Inline Task Composer -> inspectorのfocus orderを確認する。"))
    }

    func testProjectOverviewActionsAreAccessibleCrudEntryPoints() throws {
        let boardSource = try readProjectBoardSurfaceSources()
        let audit = try readPackageFile("docs/ux/click-path-audit.md")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")

        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"project-overview-task-open-\\(task.id)\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityLabel(\"Open task \\(task.title)\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityHint(\"Opens the task inspector from the project overview.\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"project-overview-add-task\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"project-local-suggestion-open-task\")"))
        XCTAssertTrue(boardSource.contains(".accessibilityHint(\"Opens the suggested task in the inspector.\")"))
        XCTAssertTrue(boardSource.contains("onOpenTaskInspector(task.id)"))
        XCTAssertTrue(boardSource.contains("onOpenTaskInspector(suggestedTask.id)"))
        XCTAssertTrue(boardSource.contains(".accessibilityIdentifier(\"task-list-open-details-\\(task.id)\")"))
        XCTAssertTrue(boardSource.contains("private func openTaskInspector(_ taskID: Int64)"))
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
        XCTAssertTrue(evidence.contains("- Bundle identifier: `dev.suisui.app`"))
        XCTAssertTrue(evidence.contains("- Source commit: `"))
        XCTAssertTrue(evidence.contains("- Checked by: Codex local AX and VoiceOver review"))
        XCTAssertTrue(evidence.contains("- Check date:"))
        XCTAssertTrue(evidence.contains("- Evidence source: `dist/Suisui.app manual VoiceOver pass using isolated .tmp voiceover review database project:119`"))
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
        let coreSource = try readPackageFile("Sources/SuisuiCore/App/ProjectBoard.swift")
        let modelSource = try readPackageFile("Sources/SuisuiCore/WorkManagement/WorkManagementModels.swift")
        let dailyPlanningSource = try readPackageFile("Sources/SuisuiCore/App/DailyPlanningReview.swift")
        let dailyPlanningDraftSource = try readPackageFile("Sources/SuisuiCore/App/DailyPlanningActionDraft.swift")
        let missedReviewSource = try readPackageFile("Sources/SuisuiCore/App/MissedTaskReview.swift")

        XCTAssertTrue(workflowSource.contains("TodayCommandPanel"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-command-capture-field\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-primary-action\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-secondary-actions-menu\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-suggestion-chip-"))
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
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-daily-planning-actions-menu\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-daily-planning-readout\")"))
        XCTAssertTrue(workflowSource.contains("playDailyPlanningReadout()"))
        XCTAssertTrue(workflowSource.contains("viewModel.enqueueDailyPlanningActionDraft(kind: .startRecommended)"))
        XCTAssertTrue(workflowSource.contains("viewModel.enqueueDailyPlanningActionDraft(kind: .deferRecommendedToTomorrow)"))
        XCTAssertTrue(workflowSource.contains("viewModel.enqueueDailyPlanningActionDraft(kind: .moveRecommendedDueDateToToday)"))
        XCTAssertTrue(workflowSource.contains("viewModel.enqueueDailyPlanningActionDraft(kind: .splitRecommendedTask)"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-assistant-rail\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-rail-next-action\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-rail-task-detail\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-rail-actions-menu\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-rail-schedule-block\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-rail-edit-task\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-rail-add-subtask\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-rail-reminder-draft\")"))
        XCTAssertTrue(workflowSource.contains("viewModel.enqueueTodayReminderDraft(for: task.id)"))
        XCTAssertTrue(workflowSource.contains("plan.overdueCount"))
        XCTAssertTrue(workflowSource.contains("plan.dueTodayCount"))
        XCTAssertTrue(workflowSource.contains("viewModel.missedTaskReview"))
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
        let commandPanelStart = try XCTUnwrap(workflowSource.range(of: "struct TodayCommandPanel"))
        let reviewPanelSource = String(workflowSource[reviewPanelStart.lowerBound..<commandPanelStart.lowerBound])
        XCTAssertFalse(reviewPanelSource.contains("applyScheduleDraftToCalendar"))
        XCTAssertFalse(reviewPanelSource.contains("startFocus("))
        XCTAssertFalse(reviewPanelSource.contains("AVSpeechSynthesizer"))
    }

    func testVoiceDailyPlanningReviewBridgeUsesLocalProjectBoardReview() throws {
        let voiceSource = try readPackageFile("Sources/SuisuiCore/Voice/VoiceCaptureViewModel.swift")
        let appSource = try readAppShellSource()
        let boardSource = try readProjectBoardSurfaceSources()

        XCTAssertTrue(voiceSource.contains("public struct VoiceDailyPlanningReviewRequest"))
        XCTAssertTrue(voiceSource.contains("requestedActionDraftKind: DailyPlanningActionDraftKind?"))
        XCTAssertTrue(voiceSource.contains("DailyPlanningActionDraftKind.splitRecommendedTask"))
        XCTAssertTrue(voiceSource.contains("@Published public private(set) var dailyPlanningReviewRequest"))
        XCTAssertTrue(voiceSource.contains("routedCommand.intent != .dailyPlanningReview"))
        XCTAssertTrue(voiceSource.contains("beginDailyPlanningReviewRequest"))
        XCTAssertTrue(appSource.contains("viewModel.dailyPlanningReviewRequest"))
        XCTAssertTrue(appSource.contains("Queue a move-to-today draft for approval"))
        XCTAssertTrue(appSource.contains("Queue a split-task draft for approval"))
        XCTAssertTrue(appSource.contains("guard let bridgeRequest = SuisuiVoiceDailyPlanningReviewBridge.storePendingRequest(request)"))
        XCTAssertTrue(appSource.contains("name: .suisuiVoiceDailyPlanningReviewRequested"))
        XCTAssertTrue(appSource.contains("userInfo: [SuisuiVoiceDailyPlanningReviewBridge.requestUserInfoKey: bridgeRequest]"))
        XCTAssertFalse(appSource.contains("sourceTranscriptUserInfoKey"))
        XCTAssertTrue(boardSource.contains(".onReceive(NotificationCenter.default.publisher(for: .suisuiVoiceDailyPlanningReviewRequested))"))
        XCTAssertTrue(boardSource.contains("consumePendingVoiceDailyPlanningReviewRequestIfNeeded"))
        XCTAssertTrue(boardSource.contains("SuisuiVoiceDailyPlanningReviewBridge.consumePendingRequest(id: id)"))
        XCTAssertTrue(appSource.contains("ProjectBoardSceneCoordinator.shared.requestOpen(id: request.id, route: route)"))
        XCTAssertTrue(boardSource.contains("sceneCoordinator.consume(requestID: request.id, for: sceneID)"))
        XCTAssertFalse(boardSource.contains("consumedRequestIDs"))
        XCTAssertTrue(boardSource.contains("actionDraftKind: request.actionDraftKind"))
        XCTAssertTrue(boardSource.contains("handleVoiceDailyPlanningReviewRequest"))
        XCTAssertTrue(boardSource.contains("viewModel.prepareDailyPlanningReview(transcript:"))
        XCTAssertTrue(boardSource.contains("viewModel.enqueueDailyPlanningActionDraft("))
        XCTAssertTrue(boardSource.contains("kind: actionDraftKind"))
        XCTAssertTrue(boardSource.contains("playDailyPlanningReadoutFromSettings()"))
        XCTAssertTrue(boardSource.contains("viewModel.playDailyPlanningReviewReadout("))
        XCTAssertTrue(boardSource.contains("AppTextToSpeechRuntimeFactory.makePreviewer("))
        XCTAssertTrue(boardSource.contains("temporaryDirectoryPrefix: \"suisui-daily-planning-readout\""))
        XCTAssertTrue(boardSource.contains("outputFilename: \"readout.wav\""))
        XCTAssertTrue(boardSource.contains("to: .review(.assistantQueue),"))
        XCTAssertTrue(boardSource.contains("navigateToTodayForDailyPlanning(summary: summary)"))
        XCTAssertTrue(
            boardSource.contains(
                "focus: summary.newlyMissedCount > 0 ? .catchUp : nil"
            )
        )
        XCTAssertTrue(boardSource.contains("updateInitialRoute: false"))
        XCTAssertTrue(boardSource.contains("static let suisuiVoiceDailyPlanningReviewRequested"))
        XCTAssertTrue(boardSource.contains("guard let request = SuisuiVoiceDailyPlanningReviewBridge.consumePendingRequest(id: id)"))
        XCTAssertFalse(boardSource.contains("sourceTranscript(from: notification)"))
        XCTAssertFalse(appSource.contains("calendarClient.create"))
        XCTAssertFalse(appSource.contains("reminderClient.create"))
        XCTAssertFalse(boardSource.contains("AVSpeechSynthesizer"))
    }

    func testSceneRequestPayloadIsStoredBeforePublicationAndCannotRewriteInitialRoute() throws {
        let voiceSource = try readPackageFile("Sources/SuisuiApp/Views/VoiceCaptureView.swift")
        let boardSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardView.swift")

        for (functionName, storeMarker, requestMarker, discardMarker, endMarker) in [
            (
                "postDailyPlanningReviewRequest",
                "SuisuiVoiceDailyPlanningReviewBridge.storePendingRequest(request)",
                "ProjectBoardSceneCoordinator.shared.requestOpen(id: request.id, route: route)",
                "SuisuiVoiceDailyPlanningReviewBridge.discardPendingRequest(id: bridgeRequest.id)",
                "private func postInboxTriageRequest"
            ),
            (
                "postInboxTriageRequest",
                "SuisuiVoiceInboxTriageBridge.storePendingRequest(request)",
                "ProjectBoardSceneCoordinator.shared.requestOpen(",
                "SuisuiVoiceInboxTriageBridge.discardPendingRequest(id: bridgeRequest.id)",
                "private func postAssistantQueueOpenRequest"
            ),
            (
                "postAssistantQueueOpenRequest",
                "SuisuiAssistantQueueBridge.storePendingOpen",
                "ProjectBoardSceneCoordinator.shared.requestOpen(",
                "SuisuiAssistantQueueBridge.discardPendingOpen(id: bridgeRequest.id)",
                "extension Notification.Name"
            )
        ] {
            let start = try XCTUnwrap(voiceSource.range(of: "private func \(functionName)"))
            let end = try XCTUnwrap(voiceSource.range(
                of: endMarker,
                range: start.lowerBound..<voiceSource.endIndex
            ))
            let block = String(voiceSource[start.lowerBound..<end.lowerBound])
            let store = try XCTUnwrap(block.range(of: storeMarker))
            let request = try XCTUnwrap(block.range(of: requestMarker))
            let notification = try XCTUnwrap(block.range(of: "NotificationCenter.default.post"))
            XCTAssertLessThan(store.lowerBound, request.lowerBound)
            XCTAssertLessThan(request.lowerBound, notification.lowerBound)
            XCTAssertTrue(block.contains(discardMarker))
        }

        XCTAssertTrue(boardSource.contains("static func discardPendingRequest(id: UUID)"))
        XCTAssertTrue(boardSource.contains("static func discardPendingOpen(id: UUID)"))
        XCTAssertTrue(boardSource.contains("ProjectBoardRequestPayloadStore<Request>"))
        XCTAssertTrue(boardSource.contains("consumePendingVoiceDailyPlanningReviewRequestIfNeeded(id: request.id)"))
        XCTAssertTrue(boardSource.contains("consumePendingVoiceInboxTriageRequestIfNeeded(id: request.id)"))
        XCTAssertTrue(boardSource.contains("consumePendingAssistantQueueRequestIfNeeded(id: request.id)"))
        XCTAssertTrue(boardSource.contains("consumePendingRequest(id: id)"))
        XCTAssertTrue(boardSource.contains("consumePendingOpen(id: id)"))
        XCTAssertFalse(boardSource.contains("private static var pendingRequest: Request?"))
        XCTAssertTrue(boardSource.contains("ProjectBoardScenePersistence.shouldUpdateInitialRoute(for: request)"))
        XCTAssertTrue(boardSource.contains("private func applyLegacyDestinationWithinScene("))

        let dailyStart = try XCTUnwrap(boardSource.range(of: "private func handleVoiceDailyPlanningReviewRequest(\n        sourceTranscript:"))
        let dailyEnd = try XCTUnwrap(boardSource.range(of: "private func playDailyPlanningReadoutFromSettings", range: dailyStart.lowerBound..<boardSource.endIndex))
        let inboxStart = try XCTUnwrap(boardSource.range(of: "private func openInboxForVoiceTriage()"))
        let inboxEnd = try XCTUnwrap(boardSource.range(of: "private func handleAssistantQueueOpenRequest(_ notification:", range: inboxStart.lowerBound..<boardSource.endIndex))
        let assistantStart = try XCTUnwrap(boardSource.range(of: "private func handleAssistantQueueOpenRequest(request:"))
        let assistantEnd = try XCTUnwrap(boardSource.range(of: "private func applySelectedTaskOverrideIfNeeded", range: assistantStart.lowerBound..<boardSource.endIndex))

        let dailyBlock = String(boardSource[dailyStart.lowerBound..<dailyEnd.lowerBound])
        let compatibilityBlocks = [
            String(boardSource[inboxStart.lowerBound..<inboxEnd.lowerBound]),
            String(boardSource[assistantStart.lowerBound..<assistantEnd.lowerBound])
        ]
        for block in [dailyBlock] + compatibilityBlocks {
            XCTAssertFalse(block.contains("persistSelectedDestination"))
        }
        XCTAssertTrue(dailyBlock.contains("navigateWithinScene("))
        XCTAssertTrue(dailyBlock.contains("updateInitialRoute: false"))
        XCTAssertFalse(dailyBlock.contains("applyLegacyDestinationWithinScene"))
        for block in compatibilityBlocks {
            XCTAssertTrue(block.contains("applyLegacyDestinationWithinScene"))
        }
        XCTAssertTrue(
            boardSource.contains("persistRoute(route, updateInitialRoute: updateInitialRoute)")
        )

        // The compatibility callback consumes suppression exactly once; the
        // ordinary user path still persists after that callback is cleared.
        XCTAssertTrue(boardSource.contains("if let suppression = pendingDestinationPersistenceSuppression"))
        XCTAssertTrue(boardSource.contains("suppression.destination == destination"))
        XCTAssertTrue(boardSource.contains("pendingDestinationPersistenceSuppression = nil"))
        XCTAssertTrue(boardSource.contains("persistSelectedDestination(destination)"))
    }

    func testTodayViewReadsPrecomputedDailyPlanningReviewWithoutRenderPathFallback() throws {
        let workflowSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectWorkflowTodayView.swift")
        let dashboardSource = try readPackageFile("Sources/SuisuiApp/Views/TodayDashboardView.swift")
        let panelStart = try XCTUnwrap(workflowSource.range(of: "private struct TodayDailyPlanningReviewPanel"))
        let panelEnd = try XCTUnwrap(workflowSource.range(of: "struct TodayCommandPanel"))
        let panelSource = String(workflowSource[panelStart.lowerBound..<panelEnd.lowerBound])

        XCTAssertFalse(panelSource.contains("makeDailyPlanningReview"))
        XCTAssertFalse(panelSource.contains("dailyWorkloadOverview"))
        XCTAssertTrue(dashboardSource.contains("viewModel.dailyPlanningReview ?? snapshot.dailyPlanningReviewPreview"))
    }

    func testVoiceInboxTriageBridgeUsesLocalProjectBoardInboxCommands() throws {
        let voiceSource = try readPackageFile("Sources/SuisuiCore/Voice/VoiceCaptureViewModel.swift")
        let appSource = try readAppShellSource()
        let boardSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardView.swift")

        XCTAssertTrue(voiceSource.contains("public struct VoiceInboxTriageRequest"))
        XCTAssertTrue(voiceSource.contains("@Published public private(set) var inboxTriageRequest"))
        XCTAssertTrue(voiceSource.contains("InboxVoiceTriageCommandParser"))
        XCTAssertTrue(appSource.contains("viewModel.inboxTriageRequest"))
        XCTAssertTrue(appSource.contains("SuisuiVoiceInboxTriageBridge.storePendingRequest"))
        XCTAssertTrue(appSource.contains("name: .suisuiVoiceInboxTriageRequested"))
        XCTAssertTrue(boardSource.contains(".onReceive(NotificationCenter.default.publisher(for: .suisuiVoiceInboxTriageRequested))"))
        XCTAssertTrue(boardSource.contains("consumePendingVoiceInboxTriageRequestIfNeeded"))
        XCTAssertTrue(boardSource.contains("SuisuiVoiceInboxTriageBridge.consumePendingRequest(id: id)"))
        XCTAssertTrue(appSource.contains("ProjectBoardSceneCoordinator.shared.requestOpen("))
        XCTAssertTrue(boardSource.contains("sceneCoordinator.consume(requestID: request.id, for: sceneID)"))
        XCTAssertFalse(boardSource.contains("consumedRequestIDs"))
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
        let voiceSource = try readPackageFile("Sources/SuisuiCore/Voice/VoiceCaptureViewModel.swift")
        let appSource = try readAppShellSource()
        let boardSource = try readProjectBoardSurfaceSources()
        let englishStrings = try readPackageFile("Sources/SuisuiApp/Resources/en.lproj/Localizable.strings")
        let japaneseStrings = try readPackageFile("Sources/SuisuiApp/Resources/ja.lproj/Localizable.strings")

        XCTAssertTrue(voiceSource.contains("assistantQueueExecutionHandoffItemID"))
        XCTAssertTrue(appSource.contains("executionHandoffItemID: viewModel.assistantQueueExecutionHandoffItemID"))
        XCTAssertTrue(appSource.contains("onOpenQueue: { postAssistantQueueOpenRequest() }"))
        XCTAssertTrue(appSource.contains("SuisuiAssistantQueueBridge.storePendingOpen("))
        XCTAssertTrue(appSource.contains("itemID: itemID"))
        XCTAssertTrue(appSource.contains("?? viewModel.assistantQueueExecutionHandoffItemID"))
        XCTAssertTrue(appSource.contains("userInfo: [SuisuiAssistantQueueBridge.requestUserInfoKey: bridgeRequest]"))
        XCTAssertTrue(appSource.contains("name: .suisuiAssistantQueueRequested"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"voice-assistant-queue-open-board\")"))
        XCTAssertTrue(appSource.contains(".accessibilityHint(localizedSettingsDisplay(\"Opens the Assistant Queue without running the item.\"))"))
        XCTAssertTrue(boardSource.contains(".onReceive(NotificationCenter.default.publisher(for: .suisuiAssistantQueueRequested))"))
        XCTAssertTrue(boardSource.contains("consumePendingAssistantQueueRequestIfNeeded"))
        XCTAssertTrue(boardSource.contains("SuisuiAssistantQueueBridge.consumePendingOpen(id: id)"))
        XCTAssertTrue(appSource.contains("id: bridgeRequest.id"))
        XCTAssertTrue(boardSource.contains("sceneCoordinator.consume(requestID: request.id, for: sceneID)"))
        XCTAssertTrue(boardSource.contains("applyLegacyDestinationWithinScene(.assistantQueue)"))
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
        let todayWorkflowSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectWorkflowTodayView.swift")
        let dashboardSource = try readPackageFile("Sources/SuisuiApp/Views/TodayDashboardView.swift")

        XCTAssertTrue(workflowSource.contains("TodayBriefingPanel"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-briefing-panel\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-command-capture-field\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-secondary-actions-menu\")"))
        XCTAssertTrue(workflowSource.contains("startFocus(taskID: chip.taskID)"))
        XCTAssertTrue(workflowSource.contains("viewModel.startFocusSession(taskID: taskID)"))
        XCTAssertTrue(workflowSource.contains("TodayFlowStrip(plan: plan)"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-flow-strip\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-flow-chip-\\(block.id)\")"))
        XCTAssertFalse(workflowSource.contains(".accessibilityIdentifier(\"today-flow-optimize\")"))
        // Today must keep exactly one focal "next action" surface. The old
        // AI suggestion card was a fourth pointer at the same task whose body
        // only said that more options live in the More menu, so it is gone and
        // must not come back.
        XCTAssertFalse(workflowSource.contains("TodayAISuggestionCard"))
        XCTAssertFalse(workflowSource.contains(".accessibilityIdentifier(\"today-ai-suggestion-card\")"))
        XCTAssertTrue(workflowSource.contains("TodayAssistantRail"))
        XCTAssertTrue(todayWorkflowSource.contains("let snapshot = viewModel.snapshot"))
        XCTAssertTrue(todayWorkflowSource.contains("TodayDashboardView("))
        XCTAssertTrue(todayWorkflowSource.contains("commandTitle: $commandTitle"))
        XCTAssertTrue(todayWorkflowSource.contains("snapshot: snapshot"))
        XCTAssertTrue(dashboardSource.contains("assistantContext: snapshot.assistantContext"))
        XCTAssertFalse(todayWorkflowSource.contains("viewModel.todayPlan()"))
        XCTAssertFalse(todayWorkflowSource.contains("viewModel.todayAssistantRailContext()"))
    }

    func testTodayDashboardUsesReferenceHierarchyAndStableAccessibilityIdentifiers() throws {
        let dashboard = try readPackageFile("Sources/SuisuiApp/Views/TodayDashboardView.swift")
        let header = try readPackageFile("Sources/SuisuiApp/Views/TodayDashboardHeaderView.swift")
        let cards = try readPackageFile("Sources/SuisuiApp/Views/TodayDashboardCards.swift")
        let taskList = try readPackageFile("Sources/SuisuiApp/Views/TodayDashboardTaskListView.swift")
        let rail = try readPackageFile("Sources/SuisuiApp/Views/TodayDashboardRailView.swift")
        let focusCard = try readPackageFile("Sources/SuisuiApp/Views/TodayFocusCard.swift")
        let workload = try readPackageFile("Sources/SuisuiCore/App/TodayWorkloadSnapshot.swift")
        let focusSession = try readPackageFile("Sources/SuisuiCore/App/FocusSession.swift")
        let settings = try readPackageFile("Sources/SuisuiCore/App/AppSettings.swift")
        let settingsView = try readPackageFile("Sources/SuisuiApp/Views/SettingsFeatureViews.swift")
        let snapshotBuilder = try readPackageFile("Sources/SuisuiCore/App/TodayDashboardSnapshot.swift")
        let featureViewModel = try readPackageFile("Sources/SuisuiCore/App/TodayFeatureViewModel.swift")
        let todayWorkflow = try readPackageFile("Sources/SuisuiApp/Views/ProjectWorkflowTodayView.swift")
        let board = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardView.swift")

        XCTAssertTrue(dashboard.contains("TodayDashboardSnapshotBuilder.make("))
        XCTAssertTrue(dashboard.contains("VisualEvidenceRuntimeContext.referenceDate()"))
        XCTAssertTrue(dashboard.contains("VisualEvidenceRuntimeContext.runtimeCalendar()"))
        XCTAssertTrue(dashboard.contains("localizedDisplayLocale()"))
        XCTAssertFalse(dashboard.contains("now: Date()"))
        XCTAssertTrue(
            dashboard.contains("mainContent(dashboard: dashboard, isWide: true, openReview: openReview)")
                || dashboard.contains("mainContent(\n                                        dashboard: dashboard,\n                                        isWide: true,\n                                        stacksRecommendations: stacksRecommendations,\n                                        openReview: openReview\n                                    )")
        )
        XCTAssertTrue(
            dashboard.contains("mainContent(dashboard: dashboard, isWide: false, openReview: openReview)")
                || dashboard.contains("mainContent(dashboard: dashboard, isWide: false, stacksRecommendations: true, openReview: openReview)")
        )
        XCTAssertTrue(dashboard.contains("presentsCardsHorizontally: presentsCompactRailCardsHorizontally"))
        XCTAssertTrue(dashboard.contains("showsSecondaryIntegrations: false"))
        XCTAssertTrue(dashboard.contains("displayName: displayName"))
        XCTAssertTrue(dashboard.contains("dailyCapacityMinutes: dailyCapacityMinutes"))
        XCTAssertTrue(todayWorkflow.contains("dashboardDisplayName: String = \"\""))
        XCTAssertTrue(todayWorkflow.contains("dashboardDailyCapacityMinutes: Int = AppSettings.default.dailyWorkCapacityMinutes"))
        XCTAssertTrue(board.contains("dashboardDisplayName: todaySettings.profileDisplayName ?? \"\""))
        XCTAssertTrue(board.contains("dashboardDailyCapacityMinutes: todaySettings.dailyWorkCapacityMinutes"))
        XCTAssertTrue(dashboard.contains("GeometryReader"))
        XCTAssertFalse(dashboard.contains("TodayDashboardAlignedRow"))
        XCTAssertFalse(dashboard.contains("wideBoard(dashboard: dashboard, openReview: openReview)"))
        XCTAssertTrue(dashboard.contains("accessibilityIdentifier(\"today-wide-board\")"))
        XCTAssertTrue(dashboard.contains("presentsCardsHorizontally: false"))
        XCTAssertTrue(dashboard.contains("showsSecondaryIntegrations: false"))
        XCTAssertTrue(dashboard.contains("compactRailCardsMinimumWidth"))
        XCTAssertTrue(dashboard.contains("presentsCompactRailCardsHorizontally"))
        XCTAssertTrue(dashboard.contains("static let twoColumnMinimumWidth = primaryMinimumWidth + railMinimumWidth + columnSpacing"))
        XCTAssertTrue(dashboard.contains("let proposedWidth = max(proxy.size.width, 1)"))
        XCTAssertTrue(dashboard.contains("let boardWidth = min(layoutWidth, proposedWidth)"))
        XCTAssertTrue(dashboard.contains("static func isWide(availableWidth: CGFloat) -> Bool"))
        XCTAssertTrue(dashboard.contains("prefersContinuousRail(boardWidth:"))
        XCTAssertFalse(dashboard.contains("prefersContinuousRail ?? measuredWide"))
        XCTAssertTrue(dashboard.contains("resolvedPrefersContinuousRail(boardWidth:"))
        XCTAssertTrue(dashboard.contains("cockpitSplitSecondaryRail(width:"))
        XCTAssertTrue(dashboard.contains("let primaryWidth = max("))
        XCTAssertTrue(dashboard.contains(".clipped()"))
        XCTAssertTrue(board.contains("prefersContinuousRail: todayPrefersContinuousRail"))
        XCTAssertTrue(board.contains("private var todayPrefersContinuousRail: Bool?"))
        XCTAssertTrue(board.contains("VisualEvidenceRuntimeContext() != nil"))
        XCTAssertTrue(todayWorkflow.contains("prefersContinuousRail: Bool? = nil"))
        XCTAssertTrue(todayWorkflow.contains("prefersContinuousRail: prefersContinuousRail"))
        XCTAssertTrue(dashboard.contains("TodayDashboardHeaderView"))
        XCTAssertTrue(dashboard.contains("TodayDashboardRecommendationCards"))
        XCTAssertTrue(dashboard.contains("TodayDashboardTaskListView"))
        XCTAssertTrue(dashboard.contains("TodayDashboardRailView"))
        // Wide rail stays outside the primary vertical ScrollView so it cannot clip.
        XCTAssertTrue(dashboard.contains("Keep the rail outside the primary ScrollView"))
        XCTAssertTrue(header.contains("today-dashboard-header"))
        XCTAssertTrue(header.contains("Suisui Today: %@. %@. %@. %@. %@"))
        XCTAssertTrue(header.contains("localizedTaskCount(header.taskCount)"))
        XCTAssertTrue(header.contains("scheduledTodayLabel"))
        XCTAssertTrue(cards.contains("today-recommendations"))
        XCTAssertTrue(cards.contains("let recommendations: [TodayRecommendation]"))
        XCTAssertTrue(cards.contains("Recommendation: %@. %@"))
        XCTAssertTrue(cards.contains("let onAction: (TodayRecommendation) -> Void"))
        XCTAssertTrue(cards.contains("var stacksVertically: Bool = false"))
        XCTAssertTrue(cards.contains("onAction(recommendation)"))
        XCTAssertTrue(cards.contains("accessibilityHint(accessibilityHint(for: recommendation))"))
        XCTAssertTrue(cards.contains("case .startFocus:"))
        XCTAssertTrue(cards.contains("case .openReview:"))
        XCTAssertTrue(cards.contains("case .prepareScheduleDraft:"))
        XCTAssertTrue(cards.contains("case .selectTask:"))
        XCTAssertTrue(cards.contains("Starts local focus without changing task status or Calendar."))
        XCTAssertTrue(cards.contains("moves to the Daily Planning Review"))
        XCTAssertTrue(cards.contains("Adds this task to the local schedule draft without writing Calendar."))
        XCTAssertTrue(cards.contains("today-review-card"))
        XCTAssertTrue(cards.contains("Text(\"Needs Review\")"))
        XCTAssertTrue(cards.contains("Text(\"External changes\")"))
        XCTAssertTrue(cards.contains("ForEach(review.items)"))
        XCTAssertTrue(cards.contains("today-review-item-"))
        XCTAssertTrue(cards.contains("View all review items"))
        XCTAssertTrue(dashboard.contains("review: dashboard.review"))
        XCTAssertTrue(dashboard.contains("scrollProxy.scrollTo(\"today-review-actions\", anchor: .top)"))
        XCTAssertTrue(dashboard.contains(".accessibilityFocused($isReviewActionsFocused)"))
        XCTAssertFalse(todayWorkflow.contains("var openReview: () -> Void"))
        XCTAssertFalse(board.contains("openReview: { boardRouteBinding.wrappedValue = .primary(.review) }"))
        XCTAssertTrue(cards.contains("today-weekly-schedule-card"))
        XCTAssertTrue(cards.contains("localizedCount(schedule.scheduledTaskCount"))
        XCTAssertTrue(cards.contains("localizedCount(schedule.unscheduledTaskCount"))
        XCTAssertTrue(cards.contains("ForEach(schedule.rows)"))
        XCTAssertTrue(cards.contains("today-weekly-schedule-row-"))
        XCTAssertTrue(taskList.contains("today-task-list"))
        XCTAssertTrue(rail.contains("today-workload-card"))
        XCTAssertTrue(rail.contains("TodayWorkloadCard(workload: dashboard.workload)"))
        XCTAssertTrue(rail.contains("min(workload.ratio, 1)"))
        XCTAssertTrue(rail.contains("Over capacity by %@."))
        XCTAssertTrue(rail.contains("TodayFocusCard("))
        XCTAssertTrue(focusCard.contains("today-focus-card"))
        XCTAssertTrue(rail.contains("today-assistant-card"))
        XCTAssertTrue(rail.contains("Suisui Assistant"))
        XCTAssertTrue(rail.contains("let presentsCardsHorizontally: Bool"))
        XCTAssertTrue(rail.contains("AnyLayout"))
        XCTAssertTrue(rail.contains("HStackLayout"))
        XCTAssertTrue(rail.contains("VStackLayout"))
        XCTAssertTrue(snapshotBuilder.contains("public enum TodayRecommendationAction"))
        XCTAssertTrue(snapshotBuilder.contains("case startFocus"))
        XCTAssertTrue(snapshotBuilder.contains("case openReview"))
        XCTAssertTrue(snapshotBuilder.contains("case prepareScheduleDraft"))
        XCTAssertTrue(snapshotBuilder.contains("isUnscheduledRecommendationCandidate"))
        XCTAssertTrue(snapshotBuilder.contains("task.priority == .high"))
        XCTAssertTrue(snapshotBuilder.contains("lhs.id < rhs.id"))
        XCTAssertTrue(snapshotBuilder.contains("Needs scheduling"))
        XCTAssertTrue(snapshotBuilder.contains("public struct TodayWeeklyScheduleRow"))
        XCTAssertTrue(snapshotBuilder.contains("todayScheduledTaskCount"))
        XCTAssertTrue(snapshotBuilder.contains("weeklyScheduleRows"))
        XCTAssertTrue(dashboard.contains("private func performRecommendationAction"))
        XCTAssertTrue(dashboard.contains("viewModel.startFocusSession(taskID: taskID)"))
        XCTAssertTrue(dashboard.contains("focusTaskPendingReplacement"))
        XCTAssertTrue(dashboard.contains("case .openReview:"))
        XCTAssertTrue(dashboard.contains(".accessibilityFocused($isReviewFocused)"))
        XCTAssertFalse(dashboard.contains("viewModel.prepareTodayScheduleDraft(prioritizing: taskID)"))
        XCTAssertTrue(dashboard.contains("viewModel.addUnscheduledTaskToScheduleDraft(taskID: taskID)"))
        XCTAssertTrue(featureViewModel.contains("public func addUnscheduledTaskToScheduleDraft(taskID: Int64) -> Bool"))
        XCTAssertTrue(featureViewModel.contains("VisualEvidenceRuntimeContext.referenceDate()"))
        XCTAssertTrue(featureViewModel.contains("VisualEvidenceRuntimeContext.runtimeCalendar()"))
        XCTAssertTrue(featureViewModel.contains("board.addUnscheduledTaskToScheduleDraft(taskID: taskID, on: referenceDate, calendar: calendar)"))
        XCTAssertTrue(featureViewModel.contains("public let focusSession: TodayFocusSessionStore"))
        XCTAssertTrue(featureViewModel.contains("public func startFocusSession("))
        XCTAssertTrue(featureViewModel.contains("focusSessionRegistry: TodayFocusSessionStoreRegistry = .shared"))
        XCTAssertTrue(featureViewModel.contains("self.focusSession = focusSessionRegistry.focusSession"))
        XCTAssertTrue(workload.contains("public struct TodayWorkloadSnapshot"))
        XCTAssertTrue(workload.contains("public enum TodayWorkloadDiagnostic"))
        XCTAssertTrue(workload.contains("TodayWorkloadSnapshotBuilder"))
        XCTAssertTrue(focusSession.contains("public final class TodayFocusSessionStore"))
        XCTAssertTrue(focusSession.contains("public final class TodayFocusSessionStoreRegistry"))
        XCTAssertTrue(focusSession.contains("public static let shared = TodayFocusSessionStoreRegistry()"))
        XCTAssertTrue(focusSession.contains("case requiresReplacement"))
        XCTAssertFalse(focusSession.contains("ProjectBoard"))
        XCTAssertFalse(focusSession.contains("Calendar"))
        XCTAssertTrue(focusCard.contains("today-focus-start"))
        XCTAssertTrue(focusCard.contains("today-focus-pause"))
        XCTAssertTrue(focusCard.contains("today-focus-resume"))
        XCTAssertTrue(focusCard.contains("today-focus-end"))
        XCTAssertTrue(focusCard.contains(".task"))
        XCTAssertTrue(focusCard.contains("let startFocusSession:"))
        XCTAssertTrue(focusCard.contains("startFocusSession(taskID, durationMinutes * 60, true)"))
        XCTAssertFalse(focusCard.contains("session.start(taskID:"))
        XCTAssertTrue(todayWorkflow.contains("private func startFocus(taskID: Int64)"))
        XCTAssertTrue(todayWorkflow.contains("startFocus(taskID: chip.taskID)"))
        XCTAssertFalse(todayWorkflow.contains("viewModel.startFocus(taskID:"))
        XCTAssertTrue(rail.contains("startFocusSession: viewModel.startFocusSession"))
        XCTAssertTrue(settings.contains("dailyWorkCapacityMinutes"))
        XCTAssertTrue(settingsView.contains("settings-daily-work-capacity"))
        XCTAssertTrue(settingsView.contains("private func dailyWorkCapacityLabel"))
        XCTAssertTrue(settingsView.contains("localizedCount(minutes / 60, one: \"%d hour\", other: \"%d hours\")"))
        XCTAssertTrue(header.contains("Suisui"))
    }

    func testTodayDashboardUsesReferenceVisualHierarchy() throws {
        let dashboard = try readPackageFile("Sources/SuisuiApp/Views/TodayDashboardView.swift")
        let header = try readPackageFile("Sources/SuisuiApp/Views/TodayDashboardHeaderView.swift")
        let cards = try readPackageFile("Sources/SuisuiApp/Views/TodayDashboardCards.swift")
        let taskList = try readPackageFile("Sources/SuisuiApp/Views/TodayDashboardTaskListView.swift")
        let rail = try readPackageFile("Sources/SuisuiApp/Views/TodayDashboardRailView.swift")
        let focusCard = try readPackageFile("Sources/SuisuiApp/Views/TodayFocusCard.swift")
        let cardModifierStart = try XCTUnwrap(dashboard.range(of: "func todayDashboardCard()")?.lowerBound)
        let dashboardViewStart = try XCTUnwrap(dashboard.range(of: "struct TodayDashboardView")?.lowerBound)
        let cardModifierScope = String(dashboard[cardModifierStart..<dashboardViewStart])

        XCTAssertTrue(dashboard.contains("func todayDashboardCard()"))
        XCTAssertTrue(
            cardModifierScope.contains(".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)")
                || cardModifierScope.contains(".frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)")
        )
        XCTAssertTrue(header.contains("Divider()"))
        XCTAssertTrue(header.contains("HStack(alignment: .firstTextBaseline"))
        XCTAssertTrue(header.contains("TodayDashboardWeatherView(weather: weather)"))
        XCTAssertTrue(cards.contains("recommendationIcon(for:"))
        XCTAssertTrue(cards.contains("actionTitle(for:"))
        XCTAssertTrue(cards.contains(".todayDashboardCard()"))
        XCTAssertTrue(taskList.contains("taskCountBadge"))
        XCTAssertTrue(taskList.contains("Divider()"))
        XCTAssertTrue(rail.contains("frame(width: 86, height: 86)"))
        XCTAssertTrue(rail.contains(".todayDashboardCard()"))
        XCTAssertTrue(focusCard.contains("@State private var durationMinutes = 90"))
        XCTAssertTrue(focusCard.contains(".pickerStyle(.menu)"))
        XCTAssertTrue(focusCard.contains(".buttonStyle(.borderedProminent)"))
        XCTAssertTrue(focusCard.contains("case .idle: durationMinutes * 60"))
        XCTAssertFalse(dashboard.contains(".padding(.top, isWide ? 124 : 0)"))
        XCTAssertTrue(taskList.contains(".frame(width: 280, alignment: .leading)"))
        XCTAssertTrue(taskList.contains("today-task-list-add"))
        XCTAssertTrue(dashboard.contains("VStack(alignment: .leading, spacing: TodayDashboardLayoutMetrics.sectionSpacing)"))
        XCTAssertTrue(dashboard.contains("width: TodayDashboardLayoutMetrics.railMinimumWidth + 18")
            || dashboard.contains("let railSpan = TodayDashboardLayoutMetrics.railMinimumWidth + 18"))
        XCTAssertTrue(
            dashboard.contains("cockpitSplitPrimaryColumn()")
                || dashboard.contains("frame(width: primaryWidth")
        )
        XCTAssertTrue(dashboard.contains("CockpitSplitLayout.layoutWidth("))
        XCTAssertTrue(rail.contains("minHeight: TodayDashboardLayoutMetrics.railWidgetMinHeight"))
        XCTAssertTrue(focusCard.contains("minHeight: TodayDashboardLayoutMetrics.railWidgetMinHeight"))
        XCTAssertTrue(rail.contains("assistantCard\n                .frame"))
        XCTAssertTrue(rail.contains("let cardWidth = presentsCardsHorizontally"))
        XCTAssertTrue(dashboard.contains("availableWidth: max(boardWidth - (TodayDashboardLayoutMetrics.horizontalInsets * 2), 1)"))
        XCTAssertTrue(dashboard.contains("availableWidth: TodayDashboardLayoutMetrics.railMinimumWidth"))
        XCTAssertFalse(dashboard.contains("TodayWorkloadCard(workload: dashboard.workload)"))
        XCTAssertFalse(dashboard.contains("TodayAssistantCard("))
        XCTAssertTrue(rail.contains("TodayWorkloadCard(workload: dashboard.workload)"))
        XCTAssertTrue(rail.contains("TodayAssistantCard("))
        XCTAssertTrue(dashboard.contains("today-wide-board"))
        XCTAssertTrue(dashboard.contains(".frame(maxWidth: .infinity, alignment: .topLeading)"))
        XCTAssertTrue(dashboard.contains("width: boardWidth"))
        XCTAssertTrue(dashboard.contains("resolvedPrefersContinuousRail(boardWidth:"))
        XCTAssertTrue(cards.contains("actionColor(for: recommendation)"))
        XCTAssertTrue(cards.contains(".foregroundStyle(.white)"))
        XCTAssertFalse(
            cards.contains(
                ".stroke(SuisuiBrand.soloBlue.opacity(0.28), lineWidth: 1)"
            )
        )
    }

    func testTodayWorkflowProvidesCommonQuickActionChipsAndLocalRailActions() throws {
        let workflowSource = try readProjectWorkflowSources()
        let boardSource = try readProjectBoardSurfaceSources()

        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-secondary-actions-menu\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-secondary-add-task\")"))
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
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-rail-actions-menu\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-rail-schedule-block\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"today-rail-schedule-draft-status\")"))
        XCTAssertTrue(workflowSource.contains("!trimmedCommandTitle.hasSuffix(\":\")"))
        XCTAssertTrue(workflowSource.contains("selectTask: selectTodayTask"))
        XCTAssertTrue(workflowSource.contains("openInspector(task.id)"))
        XCTAssertTrue(workflowSource.contains("commandTitle = String(format: String(localized: \"Subtask for %@: \"), task.title)"))
        XCTAssertTrue(boardSource.contains("isInspectorPresented = false"))
        XCTAssertTrue(boardSource.contains("selectTodayTask"))
        XCTAssertTrue(boardSource.contains("openInspectorForTodayRailTask: openInspectorForTodayRailTask"))
        XCTAssertTrue(boardSource.contains("openInspectorForTodayRailTask"))
        XCTAssertTrue(boardSource.contains("isInspectorPresented = true"))
    }

    func testTodayWorkflowUsesStableLayoutsForSizeFittingSensitiveScopes() throws {
        let todaySource = try readPackageFile("Sources/SuisuiApp/Views/ProjectWorkflowTodayView.swift")
        let dashboardSource = try readPackageFile("Sources/SuisuiApp/Views/TodayDashboardView.swift")
        let sharedSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectWorkflowSharedViews.swift")

        let todayWorkflowScope = dashboardSource

        let todayBriefingStart = try XCTUnwrap(todaySource.range(of: "private struct TodayBriefingPanel"))
        let todayBriefingEnd = try XCTUnwrap(todaySource.range(of: "struct TodaySuggestionPanel"))
        let todayBriefingScope = String(todaySource[todayBriefingStart.lowerBound..<todayBriefingEnd.lowerBound])

        let primaryActionStart = try XCTUnwrap(todaySource.range(of: "private var primaryAction: some View"))
        let primaryPresentationStart = try XCTUnwrap(todaySource.range(of: "private var primaryActionPresentation", range: primaryActionStart.upperBound..<todaySource.endIndex))
        let primaryActionScope = String(todaySource[primaryActionStart.lowerBound..<primaryPresentationStart.lowerBound])
        let secondaryMenuStart = try XCTUnwrap(todaySource.range(of: "private var secondaryActionsMenu", range: primaryPresentationStart.upperBound..<todaySource.endIndex))
        let addInboxItemStart = try XCTUnwrap(todaySource.range(of: "private func addInboxItem", range: secondaryMenuStart.upperBound..<todaySource.endIndex))
        let secondaryMenuScope = String(todaySource[secondaryMenuStart.lowerBound..<addInboxItemStart.lowerBound])

        let planSummaryStart = try XCTUnwrap(todaySource.range(of: "private struct TodayPlanSummary"))
        let countBadgeStart = try XCTUnwrap(todaySource.range(of: "private struct TodayCountBadge", range: planSummaryStart.upperBound..<todaySource.endIndex))
        let planSummaryScope = String(todaySource[planSummaryStart.lowerBound..<countBadgeStart.lowerBound])

        let taskSurfaceStart = try XCTUnwrap(sharedSource.range(of: "struct WorkflowTaskSurface"))
        let taskSurfaceBodyStart = try XCTUnwrap(sharedSource.range(of: "\n    var body: some View {", range: taskSurfaceStart.upperBound..<sharedSource.endIndex))
        let taskSurfaceContentStart = try XCTUnwrap(sharedSource.range(of: "\n            if tasks.isEmpty {", range: taskSurfaceBodyStart.upperBound..<sharedSource.endIndex))
        let sharedHeaderScope = String(sharedSource[taskSurfaceBodyStart.upperBound..<taskSurfaceContentStart.lowerBound])

        XCTAssertFalse(todayWorkflowScope.contains("ViewThatFits(in:"))
        XCTAssertFalse(todayBriefingScope.contains("ViewThatFits(in:"))
        XCTAssertFalse(primaryActionScope.contains("ViewThatFits(in:"))
        XCTAssertFalse(planSummaryScope.contains("ViewThatFits(in:"))
        XCTAssertFalse(sharedHeaderScope.contains("ViewThatFits(in:"))

        XCTAssertFalse(todayWorkflowScope.contains("LazyVGrid"))
        XCTAssertFalse(todayWorkflowScope.contains("GridItem(.adaptive"))
        XCTAssertTrue(todayWorkflowScope.contains("GeometryReader"))
        XCTAssertTrue(todayWorkflowScope.contains("prefersContinuousRail(boardWidth:"))
        XCTAssertTrue(todayWorkflowScope.contains("resolvedPrefersContinuousRail(boardWidth:"))
        XCTAssertTrue(todayWorkflowScope.contains("let boardWidth = min(layoutWidth, proposedWidth)"))
        XCTAssertFalse(todayWorkflowScope.contains("TodayDashboardAlignedRow"))
        XCTAssertTrue(todayWorkflowScope.contains("today-wide-board"))
        XCTAssertTrue(todayWorkflowScope.contains("HStack(alignment: .top, spacing: TodayDashboardLayoutMetrics.columnSpacing)"))
        XCTAssertTrue(todayWorkflowScope.contains("VStack(alignment: .leading, spacing: TodayDashboardLayoutMetrics.sectionSpacing)"))
        XCTAssertTrue(todayWorkflowScope.contains("ScrollView(.vertical)"))
        XCTAssertTrue(sharedSource.contains("else if fillsAvailableHeight {\n                ScrollView {\n                    taskRows"))
        XCTAssertTrue(sharedSource.contains("} else {\n                taskRows"))
        XCTAssertTrue(sharedSource.contains("private var taskRows: some View"))
        XCTAssertFalse(primaryActionScope.contains("LazyVGrid"))
        XCTAssertFalse(primaryActionScope.contains("GridItem(.adaptive"))
        XCTAssertFalse(todayBriefingScope.contains("LazyVGrid"))
        XCTAssertTrue(planSummaryScope.contains("VStack(alignment: .leading"))
        XCTAssertTrue(sharedHeaderScope.contains("VStack(alignment: .leading"))

        XCTAssertLessThan(
            try XCTUnwrap(sharedHeaderScope.range(of: "WorkflowHeader(")).lowerBound,
            try XCTUnwrap(sharedHeaderScope.range(of: "headerAccessory()")).lowerBound
        )

        // The first viewport follows heading/recommendation, reason, primary,
        // then capture and secondary actions. This is both the visible and AX
        // order at the 1024pt runtime viewport.
        let briefingOrderNeedles = [
            "TodayPlanSummary(plan: plan, viewModel: viewModel)",
            "primaryAction",
            "TextField(\"What should move next?\"",
            "secondaryActionsMenu"
        ]
        let briefingOffsets = try briefingOrderNeedles.map { needle in
            try XCTUnwrap(todayBriefingScope.range(of: needle)?.lowerBound)
        }
        for pair in zip(briefingOffsets, briefingOffsets.dropFirst()) {
            XCTAssertLessThan(pair.0, pair.1)
        }

        XCTAssertEqual(todaySource.components(separatedBy: ".buttonStyle(.borderedProminent)").count - 1, 1)
        XCTAssertTrue(primaryActionScope.contains(".accessibilityIdentifier(\"today-primary-action\")"))
        XCTAssertTrue(secondaryMenuScope.contains(".accessibilityIdentifier(\"today-secondary-actions-menu\")"))
        let planMenuIdentifiers = [
            "today-common-chip-plan-tomorrow",
            "today-common-chip-prepare-meeting",
            "today-common-chip-draft-reply"
        ]
        let planMenuOffsets = try planMenuIdentifiers.map { identifier in
            try XCTUnwrap(secondaryMenuScope.range(of: identifier)?.lowerBound)
        }
        for pair in zip(planMenuOffsets, planMenuOffsets.dropFirst()) {
            XCTAssertLessThan(pair.0, pair.1)
        }
    }

    func testTodayWorkflowKeepsTheRailReachableWithFiniteNarrowHeight() throws {
        let todaySource = try readPackageFile("Sources/SuisuiApp/Views/TodayDashboardView.swift")
        let railSource = try readPackageFile("Sources/SuisuiApp/Views/TodayDashboardRailView.swift")
        let sharedSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectWorkflowSharedViews.swift")
        let workflowScope = todaySource

        XCTAssertTrue(todaySource.contains("enum TodayDashboardLayoutMetrics"))
        XCTAssertTrue(todaySource.contains("static let twoColumnMinimumWidth = primaryMinimumWidth + railMinimumWidth + columnSpacing"))
        XCTAssertTrue(workflowScope.contains(".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)"))
        XCTAssertTrue(workflowScope.contains(".padding(.horizontal, 18)"))
        XCTAssertTrue(workflowScope.contains(".padding(.vertical, 18)"))
        XCTAssertTrue(workflowScope.contains("TodayDashboardRailView("))
        XCTAssertTrue(railSource.contains("TodayAssistantRail("))
        XCTAssertTrue(sharedSource.contains("let fillsAvailableHeight: Bool"))
        XCTAssertTrue(sharedSource.contains("maxHeight: fillsAvailableHeight ? .infinity : nil"))

        let compactMainContentRange =
            workflowScope.range(of: "mainContent(dashboard: dashboard, isWide: false, openReview: openReview)")
            ?? workflowScope.range(of: "mainContent(dashboard: dashboard, isWide: false, stacksRecommendations: true, openReview: openReview)")
        XCTAssertLessThan(
            try XCTUnwrap(compactMainContentRange).lowerBound,
            try XCTUnwrap(workflowScope.range(of: "presentsCardsHorizontally: presentsCompactRailCardsHorizontally")).lowerBound
        )
    }

    func testScheduleWorkflowIsReachableAndApprovalFirst() throws {
        let boardSource = try readProjectBoardSurfaceSources()
        let workflowSource = try readProjectWorkflowSources()
        let persistenceSource = try readPackageFile("Sources/SuisuiCore/App/ProjectBoardSelectionPersistence.swift")
        let coreSource = try readPackageFile("Sources/SuisuiCore/App/ProjectBoard.swift")
        let modelSource = try readPackageFile("Sources/SuisuiCore/WorkManagement/WorkManagementModels.swift")

        XCTAssertTrue(boardSource.contains("review-destination-schedule"))
        XCTAssertTrue(boardSource.contains("case .review(.schedule):"))
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
            try XCTUnwrap(scheduleWorkflowSource.range(of: "scheduleWorkflowArea")).lowerBound,
            try XCTUnwrap(scheduleWorkflowSource.range(of: "ScheduleMiniCalendarPanel(")).lowerBound
        )
        let workflowAreaStart = try XCTUnwrap(scheduleWorkflowSource.range(of: "private var scheduleWorkflowArea"))
        let generateButtonStart = try XCTUnwrap(scheduleWorkflowSource.range(of: "private var generateDraftButton"))
        let workflowAreaSource = String(scheduleWorkflowSource[workflowAreaStart.lowerBound..<generateButtonStart.lowerBound])
        XCTAssertTrue(workflowAreaSource.contains("ScheduleDraftApprovalControls("))
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
        let coreSource = try readPackageFile("Sources/SuisuiCore/App/ProjectBoard.swift")
        let workloadSource = try readPackageFile("Sources/SuisuiCore/App/DailyWorkloadDashboard.swift")
        let weeklySource = try readPackageFile("Sources/SuisuiCore/App/WeeklyScheduleCockpit.swift")
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

        XCTAssertTrue(workflowSource.contains("WeeklyScheduleTimelinePanel("))
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
        XCTAssertTrue(workflowSource.contains("\"schedule-mini-calendar-selected-day\""))
        XCTAssertTrue(workflowSource.contains(".accessibilityAddTraits(isSelected ? .isSelected : [])"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-week-grid\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-week-time-axis-grid\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-week-time-axis-slot-\\(day.dateKey)-\\(hour)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-week-time-axis-all-day-slot-\\(day.dateKey)\")"))
        XCTAssertTrue(workflowSource.contains("WeeklyScheduleTimeAxisGrid("))
        XCTAssertTrue(workflowSource.contains("WeeklyScheduleTimeAxisSlot("))
        XCTAssertTrue(workflowSource.contains("let startMinute = calendar.dateComponents([.minute], from: dayStart, to: item.startAt).minute ?? 0"))
        XCTAssertTrue(workflowSource.contains("ScheduleTimelineGeometry.blockFrame("))
        XCTAssertTrue(workflowSource.contains("viewModel.externalScheduleEvents"))
        XCTAssertTrue(workflowSource.contains("ExternalSchedulePositionedEvent"))
        XCTAssertTrue(workflowSource.contains("event.blocksAvailability"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-week-day-column-\\(day.dateKey)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-week-block-\\(block.id)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-week-completion-history-\\(day.dateKey)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-focus-forecast\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-smart-reminders\")"))
        XCTAssertTrue(workflowSource.contains("DailyWorkloadPanel("))
        XCTAssertTrue(workflowSource.contains("let workloadOverview = scheduleReadModel.workloadOverview"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-workload-dashboard\")"))
        XCTAssertFalse(workflowSource.contains(".accessibilityIdentifier(\"schedule-workload-previous-week\")"))
        XCTAssertFalse(workflowSource.contains(".accessibilityIdentifier(\"schedule-workload-next-week\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-workload-day-cell-\\(day.dateKey)\")"))
        XCTAssertTrue(workflowSource.contains(".accessibilityIdentifier(\"schedule-workload-count-badge-\\(day.dateKey)-total\")"))
        XCTAssertTrue(workflowSource.contains("day.totalTaskCount != day.openTaskCount"))
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
        XCTAssertTrue(captureScript.contains("schedule-workflow=>$SCHEDULE_ROUTE_LABEL"))
        XCTAssertTrue(captureScript.contains("schedule-workload-attention-banner=>"))
        XCTAssertTrue(captureScript.contains("schedule-workload-day-detail=>"))
        XCTAssertTrue(captureScript.contains("docs/release/evidence/schedule-workload-screenshots.md"))
        XCTAssertTrue(visualManifest.contains(#""id": "schedule-workload""#))
        XCTAssertTrue(visualManifest.contains("schedule-workload-light.png"))
        XCTAssertTrue(visualManifest.contains("schedule-workload-dark.png"))

        let dashboardStart = try XCTUnwrap(workflowSource.range(of: "private struct DailyWorkloadPanel"))
        let dashboardSource = String(workflowSource[dashboardStart.lowerBound...])
        XCTAssertFalse(dashboardSource.contains("applyScheduleDraftToCalendar"))
        let weeklyStart = try XCTUnwrap(workflowSource.range(of: "private struct WeeklyScheduleTimelinePanel"))
        let weeklyWorkflowSource = String(workflowSource[weeklyStart.lowerBound...])
        XCTAssertFalse(weeklyWorkflowSource.contains("applyScheduleDraftToCalendar"))
    }

    func testScheduleUsesProgressiveModesWithOneSharedWeekNavigation() throws {
        let source = try readPackageFile("Sources/SuisuiApp/Views/ProjectWorkflowScheduleView.swift")

        XCTAssertTrue(source.contains("private enum ScheduleSurfaceMode"))
        XCTAssertTrue(source.contains("case overview"))
        XCTAssertTrue(source.contains("case timeline"))
        XCTAssertTrue(source.contains("case agenda"))
        XCTAssertTrue(source.contains("case workload"))
        XCTAssertTrue(source.contains("ScheduleSurfaceMode.visualEvidenceInitialMode()"))
        XCTAssertTrue(source.contains("SUISUI_VISUAL_EVIDENCE_SCHEDULE_MODE"))
        XCTAssertTrue(source.contains("SUISUI_VISUAL_EVIDENCE_REFERENCE_INSTANT"))
        XCTAssertTrue(source.contains("Button { selectedMode = mode }"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"schedule-mode-picker\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"schedule-mode-option-\\(mode.rawValue)\")"))
        XCTAssertTrue(source.contains(".accessibilityAddTraits(selectedMode == mode ? .isSelected : [])"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"schedule-mode-\\(selectedMode.rawValue)\")"))
        XCTAssertTrue(source.contains("WeeklyScheduleTimelinePanel("))
        XCTAssertTrue(source.contains("ScheduleAgendaPanel("))
        XCTAssertTrue(source.contains("selectedDayCockpit(from:"))
        XCTAssertTrue(source.contains("ScheduleAdjustmentPanel(cockpit: cockpit, itemLimit: itemLimit ?? 2, selectDay: selectDay)"))
        XCTAssertTrue(source.contains("ScheduleAvailabilityPanel("))
        XCTAssertTrue(source.contains("ScheduleSuggestionsPanel("))
        XCTAssertTrue(source.contains("WeeklyScheduleReminderPanel("))
        XCTAssertEqual(source.components(separatedBy: "ScheduleMiniCalendarPanel(").count - 1, 1)
        XCTAssertFalse(source.contains("schedule-workload-previous-week"))
        XCTAssertFalse(source.contains("schedule-workload-next-week"))
    }

    func testScheduleOverviewUsesGoogleStyleWeekGridWithoutHorizontalScrolling() throws {
        let source = try readPackageFile("Sources/SuisuiApp/Views/ProjectWorkflowScheduleView.swift")

        XCTAssertTrue(source.contains("private enum ScheduleLayoutMetrics"))
        XCTAssertTrue(source.contains("static let hourRowHeight: CGFloat = 52"))
        XCTAssertTrue(source.contains("static let dayHeaderHeight: CGFloat = 44"))
        XCTAssertTrue(source.contains("static let allDayRowHeight: CGFloat = 30"))
        XCTAssertTrue(source.contains("ScheduleOverviewCalendar("))
        XCTAssertTrue(source.contains("static let calendarMinimumWidth: CGFloat = 360"))
        XCTAssertTrue(
            source.contains(".frame(minWidth: ScheduleLayoutMetrics.calendarMinimumWidth, maxWidth: .infinity)")
                || source.contains(".frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)")
        )
        XCTAssertTrue(source.contains("private var dayHeaderRow: some View"))
        XCTAssertTrue(source.contains("private func hourRow(_ hour: Int) -> some View"))
        XCTAssertTrue(source.contains("private var initialScrollHour: Int"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"schedule-week-grid\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"schedule-week-time-axis-grid\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"schedule-current-time-line\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"schedule-adjustments\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"schedule-availability\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"schedule-suggestions\")"))
        XCTAssertTrue(source.contains("viewModel.placeTaskInScheduleDraft("))
        XCTAssertTrue(source.contains(".keyboardShortcut(.leftArrow, modifiers: [.command, .option])"))
        XCTAssertTrue(source.contains(".keyboardShortcut(.rightArrow, modifiers: [.command, .option])"))
        XCTAssertTrue(source.contains("selectDay(day)\n        } label"))

        let gridStart = try XCTUnwrap(source.range(of: "private struct WeeklyScheduleTimeAxisGrid"))
        let gridEnd = try XCTUnwrap(source.range(of: "private struct WeeklyScheduleTimeAxisSlot"))
        let gridSource = source[gridStart.lowerBound..<gridEnd.lowerBound]
        XCTAssertFalse(gridSource.contains("ScrollView(.horizontal"))
    }

    func testScheduleEvidenceDensifiesTimedBlocksAndKeepsProductModeVocabulary() throws {
        let scheduleSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectWorkflowScheduleView.swift")
        let seederSource = try readPackageFile("Sources/SuisuiVisualFixtureSeeder/main.swift")

        XCTAssertTrue(scheduleSource.contains("case .overview: \"Week\""))
        XCTAssertTrue(scheduleSource.contains("case .timeline: \"Day\""))
        XCTAssertTrue(scheduleSource.contains("case .agenda: \"Schedule\""))
        XCTAssertTrue(scheduleSource.contains("case .workload: \"Workload\""))
        XCTAssertFalse(scheduleSource.contains("すべて"))
        XCTAssertFalse(scheduleSource.contains("同期済み"))
        XCTAssertTrue(scheduleSource.contains("prepareScheduleDraftForVisualEvidenceIfNeeded"))
        XCTAssertTrue(scheduleSource.contains("VisualEvidenceRuntimeContext() != nil"))
        XCTAssertTrue(scheduleSource.contains("private var blockAccent: Color"))
        XCTAssertTrue(scheduleSource.contains("SuisuiBrand.soloBlue.opacity(0.72)"))
        XCTAssertTrue(seederSource.contains("T10:00:00Z"))
        XCTAssertTrue(seederSource.contains("T14:00:00Z"))
        XCTAssertTrue(seederSource.contains("T16:00:00Z"))
        XCTAssertTrue(seederSource.contains("T09:00:00Z"))
        XCTAssertTrue(seederSource.contains("Stakeholder sync"))
        XCTAssertTrue(seederSource.contains("Focus polish: AX paths"))
        XCTAssertTrue(seederSource.contains("Design workshop"))
        XCTAssertTrue(seederSource.contains("Submit weekly status"))
        // Overdue/blocked work keeps Needs Adjustment populated without Calendar sync badges.
        XCTAssertTrue(seederSource.contains("\"Document remaining release blockers\""))
        XCTAssertTrue(seederSource.contains(".text(yesterdayDay)"))
        XCTAssertTrue(seederSource.contains(".text(today)"))
    }

    func testScheduleKeepsDaySeparatorsVisibleAndAdaptsAroundThirteenInchViewport() throws {
        let source = try readPackageFile("Sources/SuisuiApp/Views/ProjectWorkflowScheduleView.swift")

        XCTAssertTrue(source.contains("static let standardViewportWidth = CGFloat(CockpitLayoutPolicy.splitMinimumContentWidth)"))
        XCTAssertTrue(source.contains("static func visibleHourRowCount(for viewportHeight: CGFloat) -> Int"))
        XCTAssertTrue(source.contains("GeometryReader { viewport in"))
        XCTAssertTrue(source.contains("CockpitSplitLayout.presentsSplitRail("))
        XCTAssertTrue(source.contains("CockpitLayoutPolicy.scheduleRailWidth(contentWidth:"))
        XCTAssertTrue(source.contains("rail(itemLimit: 1)"))
        XCTAssertTrue(source.contains("@Environment(\\.displayScale) private var displayScale"))
        XCTAssertTrue(source.contains("private var dayColumnSeparators: some View"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"schedule-day-column-separators\")"))

        let slotStart = try XCTUnwrap(source.range(of: "private struct WeeklyScheduleTimeAxisSlot"))
        let slotSource = source[slotStart.lowerBound...]
        XCTAssertFalse(slotSource.contains(".overlay(alignment: .trailing)"))
    }

    func testScheduleSupportsDirectCalendarManipulationWithoutBypassingReview() throws {
        let source = try readPackageFile("Sources/SuisuiApp/Views/ProjectWorkflowScheduleView.swift")

        XCTAssertTrue(source.contains("private struct ScheduleQuickDraftSelection"))
        XCTAssertTrue(source.contains("private struct ScheduleQuickDraftComposer"))
        XCTAssertTrue(source.contains("DragGesture(minimumDistance: 4)"))
        XCTAssertTrue(source.contains("dragSelectionPreview"))
        XCTAssertTrue(source.contains("ScheduleTimelineGeometry.blockFrame("))
        XCTAssertTrue(source.contains("ScheduleTimelineGeometry.snappedDelta("))
        XCTAssertTrue(source.contains(".draggable(String(block.task.id))"))
        XCTAssertTrue(source.contains(".dropDestination(for: String.self)"))
        XCTAssertTrue(source.contains("moveBy: nil"))
        XCTAssertTrue(source.contains("resizeBy: nil"))
        XCTAssertTrue(source.contains("let moveBy: ((Int) -> Void)?"))
        XCTAssertTrue(source.contains("let resizeBy: ((Int) -> Void)?"))
        XCTAssertTrue(source.contains(".accessibilityActions"))
        XCTAssertTrue(source.contains("viewModel.placeTaskInScheduleDraft("))
        XCTAssertTrue(source.contains("viewModel.removeTaskFromScheduleDraft("))
        XCTAssertTrue(source.contains("DatePicker("))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"schedule-quick-create\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"schedule-quick-draft-composer\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"schedule-availability-slot-\\(slot.id.timeIntervalSince1970)\")"))
        XCTAssertFalse(source.contains("applyScheduleDraftToCalendar"))
    }

    func testScheduleSupportsSearchRefreshAndReadOnlyExternalEventDetails() throws {
        let source = try readPackageFile("Sources/SuisuiApp/Views/ProjectWorkflowScheduleView.swift")

        XCTAssertTrue(source.contains("@State private var scheduleSearchText"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"schedule-search\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"schedule-refresh-external-events\")"))
        XCTAssertTrue(source.contains("ExternalScheduleEventDetails"))
        XCTAssertTrue(source.contains("viewModel.refreshExternalScheduleEvents(around: workloadReferenceDate, force: true)"))
        XCTAssertTrue(source.contains(".keyboardShortcut(mode.keyboardShortcut, modifiers: [.command, .option])"))
        XCTAssertTrue(source.contains("private var currentTimeLine: some View"))
        XCTAssertFalse(source.contains(".keyboardShortcut(mode.keyboardShortcut, modifiers: [])"))
        XCTAssertTrue(source.contains("private enum ScheduleContentFilter"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"schedule-content-filter\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"schedule-search-clear\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"schedule-search-empty\")"))
        XCTAssertTrue(source.contains("formatter.setLocalizedDateFormatFromTemplate(\"j\")"))
        XCTAssertTrue(source.contains("@FocusState private var isScheduleSearchFocused: Bool"))
        XCTAssertTrue(source.contains(".focused($isScheduleSearchFocused)"))
        XCTAssertTrue(source.contains(".keyboardShortcut(\"f\", modifiers: .command)"))
        XCTAssertTrue(source.contains(".onKeyPress(.escape)"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"schedule-search-focus\")"))
        XCTAssertTrue(source.contains("private enum ScheduleAgendaItem"))
        XCTAssertTrue(source.contains("ScheduleTimelineGeometry.eventOccurs("))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"schedule-agenda-external-event-\\(event.id)\")"))
    }

    func testScheduleUsesFullWidthReviewHubAtWideWindowSizes() throws {
        let source = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardReviewHubView.swift")

        XCTAssertTrue(source.contains("if case .review(.schedule) = route"))
        XCTAssertTrue(source.contains("return .compact"))
        XCTAssertTrue(source.contains("presentation(for: proxy.size.width)"))
    }

    func testAppAndCLIShareDefaultDatabaseLocation() throws {
        let appSource = try readAppShellSource()
        let cliSource = try readPackageFile("Sources/SuisuiCLI/SuisuiCLIEntrypoint.swift")

        XCTAssertTrue(appSource.contains("SuisuiAppDatabaseLocation.defaultDatabaseURL(createDirectory: true)"))
        XCTAssertTrue(cliSource.contains("SuisuiAppDatabaseLocation.defaultDatabaseURL(createDirectory: false)"))
        XCTAssertFalse(appSource.contains("appendingPathComponent(\"Suisui.sqlite\")"))
    }

    func testCLIEntrypointUsesSanitizedRuntimeErrors() throws {
        let cliSource = try readPackageFile("Sources/SuisuiCLI/SuisuiCLIEntrypoint.swift")

        XCTAssertTrue(cliSource.contains("Unexpected error: Suisui CLI failed unexpectedly."))
        XCTAssertTrue(cliSource.contains("local read failed: Suisui local data could not be read."))
        XCTAssertTrue(cliSource.contains("plan validate failed: Action plan file could not be read or validated."))
        XCTAssertFalse(cliSource.contains("error.localizedDescription"))
    }

    func testMenuBarSummaryRefreshesFromRuntimeController() throws {
        let appSource = try readAppShellSource()

        XCTAssertTrue(appSource.contains("@StateObject private var menuBarController: MenuBarSummaryController"))
        XCTAssertTrue(appSource.contains("quickCaptureController: menuBarQuickCaptureController,"))
        XCTAssertTrue(appSource.contains("sceneCoordinator: projectBoardSceneCoordinator"))
        XCTAssertTrue(appSource.contains("makeMenuBarSummaryController()"))
        XCTAssertTrue(appSource.contains("MenuBarSummaryController {"))
        XCTAssertTrue(appSource.contains(".onReceive(NotificationCenter.default.publisher(for: .suisuiProjectBoardDidChange))"))
        XCTAssertTrue(appSource.contains("controller.emptyStateLabel"))
        XCTAssertFalse(appSource.contains("private let menuBarViewModel = AppRuntimeFactory.makeMenuBarSummaryViewModel()"))
        XCTAssertFalse(appSource.contains("StaticMenuBarSummaryProvider(summary: .empty)"))
        XCTAssertFalse(appSource.contains("controller.refresh()\n            return controller"))
        XCTAssertTrue(appSource.contains("UnavailableMenuBarSummaryProvider(error: error)"))
    }

    func testMenuBarAttentionLabelRefreshesBeforePanelOpens() throws {
        let source = try readPackageFile("Sources/SuisuiApp/SuisuiApp.swift")
        let labelStart = try XCTUnwrap(source.range(of: "private struct MenuBarExtraLabel: View"))
        let labelEnd = try XCTUnwrap(source.range(of: "/// App-menu window commands", range: labelStart.lowerBound..<source.endIndex))
        let labelSource = String(source[labelStart.lowerBound..<labelEnd.lowerBound])

        XCTAssertTrue(labelSource.contains("@ObservedObject var controller: MenuBarSummaryController"))
        XCTAssertTrue(labelSource.contains(".suisuiProjectBoardCommandReady"))
        XCTAssertTrue(labelSource.contains(".onReceive(NotificationCenter.default.publisher(for: .suisuiProjectBoardDidChange))"))
        XCTAssertEqual(labelSource.components(separatedBy: "controller.refresh()").count - 1, 2)
    }

    func testMenuBarPanelProvidesFastInboxCaptureWithLightweightController() throws {
        let appSource = try readAppShellSource()
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")
        let audit = try readPackageFile("docs/ux/click-path-audit.md")

        XCTAssertTrue(appSource.contains("@StateObject private var menuBarQuickCaptureController: MenuBarQuickCaptureController"))
        XCTAssertTrue(appSource.contains("_menuBarQuickCaptureController = StateObject(wrappedValue: AppRuntimeFactory.makeMenuBarQuickCaptureController())"))
        XCTAssertTrue(appSource.contains("quickCaptureController: menuBarQuickCaptureController,"))
        XCTAssertTrue(appSource.contains("sceneCoordinator: projectBoardSceneCoordinator"))
        XCTAssertTrue(appSource.contains("@ObservedObject var quickCaptureController: MenuBarQuickCaptureController"))
        XCTAssertTrue(appSource.contains("@State private var quickCaptureTitle = \"\""))
        XCTAssertTrue(appSource.contains("TextField(\"Quick add to Inbox\", text: $quickCaptureTitle)"))
        XCTAssertTrue(appSource.contains("quickCaptureController.createInboxTask(title: title)"))
        XCTAssertTrue(appSource.contains("MenuBarQuickCaptureController(\n            storeFactory: {"))
        XCTAssertTrue(appSource.contains(".keyboardShortcut(.return, modifiers: [.command])"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"menu-bar-quick-capture-title\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"menu-bar-quick-capture-button\")"))
        XCTAssertTrue(appSource.contains("NotificationCenter.default.post(name: .suisuiProjectBoardDidChange, object: nil)"))
        XCTAssertFalse(appSource.contains("_menuBarQuickCaptureViewModel = StateObject(wrappedValue: AppRuntimeFactory.makeProjectBoardViewModel())"))
        XCTAssertFalse(appSource.contains("quickCaptureViewModel.load()"))
        XCTAssertTrue(audit.contains("menu bar Quick AddからInboxへ0画面遷移で実タスクを作れる"))
        XCTAssertTrue(phase.contains("[x] MenuBarExtraにQuick Addを追加し、Project Boardを開かずにInboxへローカルTaskを作れる。"))
    }

    func testReviewPanelUsesResponsiveLongContentGuards() throws {
        let appSource = try readAppShellSource()
        let voiceSource = try readPackageFile("Sources/SuisuiApp/Views/VoiceCaptureView.swift")

        XCTAssertTrue(appSource.contains("ScrollView"))
        XCTAssertTrue(voiceSource.contains(".frame(minHeight: 150, idealHeight: 180, maxHeight: 220, alignment: .topLeading)"))
        XCTAssertFalse(voiceSource.contains(".frame(minHeight: 150, idealHeight: 180, maxHeight: .infinity, alignment: .topLeading)"))
        XCTAssertTrue(appSource.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        XCTAssertTrue(appSource.contains("ActionReviewHeader"))
        XCTAssertTrue(appSource.contains("ReviewActionTitleRow"))
        XCTAssertTrue(appSource.contains("ViewThatFits(in: .horizontal)"))
        XCTAssertFalse(appSource.contains("argumentDisplaySummary(maxFields: 4, maxValueLength: 96)"))
        XCTAssertTrue(appSource.contains(".help(summary)"))
        XCTAssertTrue(appSource.contains(".help(localizedFullText)"))

        // Arguments render as labelled fields, never as a raw `key: value`
        // dump, and the full text is reachable without a mouse hover.
        XCTAssertTrue(appSource.contains("ReviewActionFieldList("))
        XCTAssertTrue(appSource.contains("item.argumentDisplayFields()"))
        XCTAssertTrue(appSource.contains("localizedReviewFieldLabel(field)"))
        XCTAssertTrue(appSource.contains("localizedReviewFieldValue(field)"))
        XCTAssertTrue(appSource.contains("private var localizedFullText: String"))
        XCTAssertTrue(appSource.contains(".accessibilityValue(localizedFullText)"))
        XCTAssertFalse(appSource.contains(".accessibilityValue(argumentSummary.fullText)"))
        // Anything writing outside Suisui is shown in full; consent cannot be
        // asked for behind a "+2 more".
        XCTAssertTrue(appSource.contains("viewModel.session.originalPlan.riskLevel >= .write"))
        XCTAssertTrue(appSource.contains("showsEveryFieldInFull ? nil : 2"))
        // The streaming voice preview shares the same vocabulary instead of
        // dumping sorted JSON keys.
        XCTAssertFalse(voiceSource.contains("\\($0.key): \\($0.value.displayValue)"))
        XCTAssertTrue(voiceSource.contains("action.argumentDisplayFields()"))
        XCTAssertTrue(appSource.contains(".help(currentStringArgument(\"title\"))"))
        XCTAssertTrue(appSource.contains(".fixedSize(horizontal: false, vertical: true)"))
    }

    func testVoiceCommandUsesScrollableFiniteViewportForProductAndEvidenceWindows() throws {
        let appSource = try readPackageFile("Sources/SuisuiApp/SuisuiApp.swift")
        let voiceSource = try readPackageFile("Sources/SuisuiApp/Views/VoiceCaptureView.swift")

        let body = try XCTUnwrap(voiceSource.range(of: "var body: some View"))
        let scrollView = try XCTUnwrap(voiceSource.range(of: "ScrollView", range: body.lowerBound..<voiceSource.endIndex))
        let captureZone = try XCTUnwrap(voiceSource.range(of: "captureZone", range: scrollView.upperBound..<voiceSource.endIndex))
        XCTAssertLessThan(scrollView.lowerBound, captureZone.lowerBound)
        XCTAssertTrue(appSource.contains("openInAppVoiceCommandForEvidenceIfRequested()"))
        XCTAssertTrue(appSource.contains("SuisuiInAppVoiceNavigation.requestOpen()"))
        XCTAssertFalse(appSource.contains("voiceCommandEvidenceWindow"))
    }

    func testSettingsEvidenceOpensTheInBoardWorkspace() throws {
        let appSource = try readPackageFile("Sources/SuisuiApp/SuisuiApp.swift")
        let boardSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardView.swift")
        let settingsSource = try readPackageFile("Sources/SuisuiApp/Views/SettingsView.swift")
        let functionStart = try XCTUnwrap(
            appSource.range(of: "private func openInAppSettingsForEvidenceIfRequested()")
        )
        let functionEnd = try XCTUnwrap(
            appSource.range(
                of: "private func openInAppVoiceCommandForEvidenceIfRequested()",
                range: functionStart.upperBound..<appSource.endIndex
            )
        )
        let evidenceSource = String(appSource[functionStart.lowerBound..<functionEnd.lowerBound])

        XCTAssertTrue(evidenceSource.contains("SuisuiInAppSettingsNavigation.requestOpen()"))
        XCTAssertTrue(evidenceSource.contains("ensureProjectBoardWindowIsVisible()"))
        XCTAssertFalse(evidenceSource.contains("NSWindow("))
        XCTAssertFalse(appSource.contains("settingsEvidenceWindow"))
        XCTAssertTrue(boardSource.contains("SettingsEvidenceLaunch.shouldOpenOnLaunch"))
        XCTAssertTrue(settingsSource.contains("SettingsEvidenceLaunch.requestedTab"))
        XCTAssertTrue(settingsSource.contains("presentation: .board"))
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
        let source = try readPackageFile("Sources/SuisuiApp/Adapters/UserNotificationsNotificationClient.swift")

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
        let source = try readPackageFile("Sources/SuisuiCore/Voice/VoiceCaptureViewModel.swift")

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
        let source = try readPackageFile("Sources/SuisuiApp/Adapters/FSEventsFileMonitorClient.swift")

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
        let clientSource = try readPackageFile("Sources/SuisuiCore/Tools/SystemToolClients.swift")

        XCTAssertFalse(appSource.contains("mailDraftClient: UnavailableMailDraftClient()"))
        XCTAssertTrue(appSource.contains("mailDraftClient: try makeMailDraftClient()"))
        XCTAssertTrue(clientSource.contains("public final class LocalFileMailDraftClient"))
        XCTAssertTrue(appSource.contains("appendingPathComponent(\"MailDrafts\", isDirectory: true)"))
        XCTAssertFalse(clientSource.contains("func listDrafts() throws -> [MailDraftRecord]"))
        XCTAssertFalse(clientSource.contains("func send"))
        XCTAssertFalse(try readPackageFile("Sources/SuisuiCore/Planning/ActionPlan.swift").contains("maildraft.send"))
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
        let source = try readPackageFile("Sources/SuisuiCore/DeveloperMode/DraftGeneration.swift")

        XCTAssertTrue(source.contains("CompiledPattern"))
        XCTAssertFalse(source.contains("try? NSRegularExpression(pattern: pattern.expression)"))
        XCTAssertFalse(source.contains("try! NSRegularExpression(pattern: expression)"))
        XCTAssertTrue(source.contains("compileDefaultPatterns()"))
        XCTAssertTrue(source.contains("redactor_initialization_failed"))
    }

    func testLocalStoresDoNotDefaultArrayEncodingToEmptyJSON() throws {
        let source = try readPackageFile("Sources/SuisuiCore/Tools/LocalStores.swift")

        XCTAssertTrue(source.contains("static func jsonArray(_ values: [String], column: String) throws -> String"))
        XCTAssertFalse(source.contains(#"(try? JSONEncoder().encode(values)) ?? Data("[]".utf8)"#))
        XCTAssertFalse(source.contains(#"String(data: data, encoding: .utf8) ?? "[]""#))
    }

    func testKnowledgeVectorEncodingDoesNotDefaultToEmptyVectorJSON() throws {
        let source = try readPackageFile("Sources/SuisuiCore/Knowledge/KnowledgeAdvanced.swift")

        XCTAssertFalse(source.contains(#"String(data: data, encoding: .utf8) ?? "[]""#))
        XCTAssertTrue(source.contains("Could not encode knowledge_frame_vectors.vector_json as UTF-8 JSON."))
    }

    func testAuditLoggerDoesNotDefaultMetadataEncodingToEmptyJSON() throws {
        let source = try readPackageFile("Sources/SuisuiCore/Audit/AuditLogger.swift")

        XCTAssertFalse(source.contains(#"String(data: metadataData, encoding: .utf8) ?? "{}""#))
        XCTAssertTrue(source.contains("Could not encode audit_logs.metadata_json as UTF-8 JSON."))
    }

    func testActionPlanSchemaDoesNotFallBackToSourceTreeAtRuntime() throws {
        let source = try readPackageFile("Sources/SuisuiCore/Planning/ActionPlanSchema.swift")

        XCTAssertFalse(source.contains("loadDataFromSourceTree"))
        XCTAssertFalse(source.contains("#filePath"))
        XCTAssertFalse(source.contains("Sources/SuisuiCore/Resources"))
        XCTAssertFalse(source.contains("try? loadData(bundle: .main)"))
        XCTAssertFalse(source.contains("try? loadData(bundle: .module)"))
        XCTAssertTrue(source.contains("catch ActionPlanSchemaError.resourceNotFound"))
    }

    func testExternalMCPLauncherDoesNotDefaultToInMemorySecretStore() throws {
        let source = try readPackageFile("Sources/SuisuiCore/ExternalMCP/MCPRegistration.swift")

        XCTAssertFalse(source.contains("SecretStoreMCPEnvironmentResolver(secretStore: InMemorySecretStore())"))
    }

    func testRuntimeExternalMCPSettingsUseSQLiteRegistrationStore() throws {
        let appSource = try readAppShellSource()
        let mcpRegistrationSource = try readPackageFile("Sources/SuisuiCore/ExternalMCP/MCPRegistration.swift")

        XCTAssertTrue(appSource.contains("SQLiteMCPServerRegistrationStore(connection:"))
        XCTAssertFalse(appSource.contains("Picker(\"Server\""))
        XCTAssertTrue(appSource.contains("final class LazyObservableObjectLoader<Value: ObservableObject>: ObservableObject"))
        XCTAssertTrue(appSource.contains("loadedValue.objectWillChange.sink"))
        XCTAssertTrue(appSource.contains("MCPServerSettingsRow("))
        XCTAssertTrue(appSource.contains("@StateObject private var externalMCPSettingsViewModelLoader: LazyObservableObjectLoader<ExternalMCPSettingsViewModel>"))
        XCTAssertTrue(appSource.contains("loadState = .loaded(viewModel)"))
        XCTAssertTrue(appSource.contains("if case .loaded(let loadedExternalMCPViewModel) = context.loadState"))
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
        let mcpRegistrationSource = try readPackageFile("Sources/SuisuiCore/ExternalMCP/MCPRegistration.swift")

        XCTAssertTrue(appSource.contains("externalMCPAuditLoadResult()"))
        XCTAssertTrue(appSource.contains("auditErrorMessage: auditLoadResult.errorMessage"))
        XCTAssertTrue(appSource.contains("loadedExternalMCPViewModel.auditErrorMessage"))
        XCTAssertTrue(appSource.contains("MCP audit history is unavailable because audit logging could not be opened."))
        XCTAssertFalse(appSource.contains("private static func externalMCPAuditRows() -> [ExternalMCPAuditHistoryRow]"))
        XCTAssertTrue(mcpRegistrationSource.contains("@Published public private(set) var auditErrorMessage: String?"))
    }

    func testExternalMCPArgumentsUseQuotedRoundTripTextInsteadOfSpaceSplitDisplay() throws {
        let appSource = try readAppShellSource()
        let mcpRegistrationSource = try readPackageFile("Sources/SuisuiCore/ExternalMCP/MCPRegistration.swift")

        XCTAssertTrue(appSource.contains("loadedExternalMCPViewModel.argumentsText"))
        XCTAssertFalse(appSource.contains("registration.arguments.joined(separator: \" \")"))
        XCTAssertTrue(mcpRegistrationSource.contains("MCPArgumentTextCodec.parse"))
        XCTAssertTrue(mcpRegistrationSource.contains("MCPArgumentTextCodec.format"))
    }

    func testExternalMCPExecutorDoesNotDefaultToInMemoryAuditLogger() throws {
        let source = try readPackageFile("Sources/SuisuiCore/ExternalMCP/MCPExecution.swift")

        XCTAssertFalse(source.contains("auditLogger: any AuditLogger = InMemoryAuditLogger()"))
        XCTAssertFalse(source.contains("processController: any MCPProcessController = NoopMCPProcessController()"))
        XCTAssertFalse(source.contains("struct NoopMCPProcessController"))
        XCTAssertFalse(source.contains("RecordingMCPProcessController"))
        XCTAssertFalse(source.contains("MCPProcessKillRequest"))
        XCTAssertFalse(source.contains("let descriptor = try? registry.descriptor(named: toolName)"))
        XCTAssertTrue(source.contains("descriptor: ExternalMCPToolDescriptor"))
    }

    func testToolExecutionContextRequiresExplicitSource() throws {
        let source = try readPackageFile("Sources/SuisuiCore/Tools/Tooling.swift")

        XCTAssertFalse(source.contains("source: ToolExecutionSource = .developerHarness"))
        XCTAssertFalse(source.contains("case developerHarness"))
        XCTAssertFalse(source.contains("case test"))
        XCTAssertTrue(source.contains("case developerTool"))
        XCTAssertTrue(source.contains("source: ToolExecutionSource"))
    }

    func testAIProvidersDoNotDefaultToInMemorySecretStore() throws {
        let chatSource = try readPackageFile("Sources/SuisuiCore/Planning/ChatCompletionsCompatibleProvider.swift")
        let sttSource = try readPackageFile("Sources/SuisuiCore/Voice/STTProviders.swift")

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
        let source = try readPackageFile("Sources/SuisuiCore/Shortcuts/ShortcutRegistration.swift")

        XCTAssertFalse(source.contains("client: any ShortcutClient = InMemoryShortcutClient()"))
    }

    func testRuntimeSourcesDoNotShipShortcutInMemoryClient() throws {
        let sourceFiles = try allSwiftFiles(under: "Sources")

        for sourceFile in sourceFiles {
            let source = try String(contentsOf: sourceFile, encoding: .utf8)
            XCTAssertFalse(source.contains("class InMemoryShortcutClient"), "\(sourceFile.path) ships test-only shortcut client.")
        }
    }

    func testGlobalVoiceShortcutUsesTypedCarbonLifecycleAndTruthfulFallback() throws {
        let appSource = try readPackageFile("Sources/SuisuiApp/SuisuiApp.swift")
        let adapterSource = try readPackageFile("Sources/SuisuiApp/Adapters/SystemShortcutClient.swift")
        let coreSource = try readPackageFile("Sources/SuisuiCore/Shortcuts/ShortcutRegistration.swift")
        let settingsSource = try readSettingsSurfaceSources()
        let menuBarSource = try readPackageFile("Sources/SuisuiApp/Views/MenuBarPanel.swift")
        let entitlements = try readPackageFile("packaging/Suisui.entitlements")

        for status in ["registered", "notRegistered", "conflict", "unavailable"] {
            XCTAssertTrue(coreSource.contains("case \(status)"))
        }
        XCTAssertTrue(adapterSource.contains("RegisterEventHotKey"))
        XCTAssertTrue(adapterSource.contains("UnregisterEventHotKey"))
        XCTAssertTrue(adapterSource.contains("kVK_Space"))
        XCTAssertTrue(adapterSource.contains("optionKey"))
        XCTAssertTrue(appSource.contains("GlobalShortcutRuntime.shared.settingsViewModel"))
        XCTAssertTrue(settingsSource.contains("Global Shortcut"))
        XCTAssertTrue(settingsSource.contains("fallbackShortcutLabel"))
        XCTAssertTrue(settingsSource.contains("Register Global Shortcut"))
        XCTAssertTrue(settingsSource.contains("Disable Global Shortcut"))
        XCTAssertFalse(menuBarSource.contains(".keyboardShortcut(.space, modifiers: [.option])"))
        XCTAssertFalse(entitlements.contains("listen-event"))
        XCTAssertFalse(entitlements.contains("input-monitoring"))
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
        let appTarget = try XCTUnwrap(packageSource.range(of: ".executableTarget(\n            name: \"Suisui\","))
        let cliTarget = try XCTUnwrap(packageSource.range(of: ".executableTarget(\n            name: \"SuisuiCLI\","))
        let testsTarget = try XCTUnwrap(packageSource.range(of: ".testTarget(\n            name: \"SuisuiCoreTests\","))
        let appTargetBlock = String(packageSource[appTarget.lowerBound..<cliTarget.lowerBound])
        let cliTargetBlock = String(packageSource[cliTarget.lowerBound..<testsTarget.lowerBound])

        XCTAssertTrue(packageSource.contains("name: \"SuisuiGoogleCalendarRuntime\""))
        XCTAssertTrue(packageSource.contains("name: \"SuisuiExternalConnectors\""))
        XCTAssertTrue(packageSource.contains("dependencies: [\"SuisuiCore\"]"))
        XCTAssertTrue(appTargetBlock.contains("SuisuiGoogleCalendarRuntime"))
        XCTAssertFalse(appTargetBlock.contains("SuisuiExternalConnectors"))
        XCTAssertFalse(cliTargetBlock.contains("SuisuiExternalConnectors"))
    }

    func testExternalConnectorPlanningDocsKeepTestDoublesOutOfProductionTarget() throws {
        let phase = try readPackageFile("tasks/Phase8-SaaSConnectors.md")
        let adr = try readPackageFile("docs/adr/0006-optional-connectors-and-knowledge-boundaries.md")

        XCTAssertTrue(phase.contains("Production connector protocols live in `Sources/SuisuiExternalConnectors/SaaSConnectors.swift`."))
        XCTAssertTrue(phase.contains("Test doubles live under `Tests/SuisuiCoreTests/SaaSConnectorTests.swift`"))
        XCTAssertTrue(phase.contains("Public alpha の `Suisui` app / `suisui-cli` は `SuisuiExternalConnectors` に依存せず"))
        XCTAssertFalse(phase.contains("`SuisuiExternalConnectors` target の protocol + test-only fake client"))
        XCTAssertFalse(phase.contains("fake Google client"))
        XCTAssertFalse(phase.contains("connector ごとに fake client test がある"))

        XCTAssertTrue(adr.contains("production connector protocols, metadata stores, and approval gates"))
        XCTAssertTrue(adr.contains("test doubles isolated under `Tests/`"))
        XCTAssertTrue(adr.contains("`Suisui` app and `suisui-cli` do not link the optional connector target"))
        XCTAssertFalse(adr.contains("Core protocols, fake clients, local stores"))
        XCTAssertFalse(adr.contains("as Core protocols, fake clients, local stores"))
    }

    func testSuisuiCoreDoesNotShipExternalSaaSConnectorImplementations() throws {
        let coreSourceFiles = try allSwiftFiles(under: "Sources/SuisuiCore")
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
                XCTAssertFalse(source.contains(symbol), "\(sourceFile.path) keeps optional external SaaS connector symbol \(symbol) in SuisuiCore.")
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
        let projectRuntimeSource = try readPackageFile("Sources/SuisuiApp/Composition/ProjectBoardRuntimeFactory.swift")
        let coordinatorFactoryStart = try XCTUnwrap(projectRuntimeSource.range(of: "private static func makeAssistantQueueExecutionCoordinator("))
        let coordinatorFactoryEnd = try XCTUnwrap(projectRuntimeSource.range(of: "\n}\n\nprivate struct UnavailableProjectBoardStore", range: coordinatorFactoryStart.upperBound..<projectRuntimeSource.endIndex))
        let coordinatorFactory = String(projectRuntimeSource[coordinatorFactoryStart.lowerBound..<coordinatorFactoryEnd.lowerBound])
        let registryFactoryStart = try XCTUnwrap(appSource.range(of: "static func makeRuntimeToolRegistry("))
        let registryFactory = String(appSource[registryFactoryStart.lowerBound...])

        XCTAssertTrue(appSource.contains("static func makeRuntimeToolRegistry("))
        XCTAssertTrue(coordinatorFactory.contains("makeRuntimeToolRegistry(connection: connection, auditLogger: auditLogger)"))
        XCTAssertTrue(coordinatorFactory.contains("RedactingAuditLogger(base: SQLiteAuditLogger(connection: connection))"))
        XCTAssertFalse(coordinatorFactory.contains("let auditLogger = try makeAuditLogger()"))
        XCTAssertTrue(registryFactory.contains("DevelopmentPullRequestCreationTool(\n                projectStore: projectStore,\n                bookmarkResolver: developmentBookmarkResolver"))
        XCTAssertTrue(registryFactory.contains("DevelopmentPullRequestReviewGateTool(\n                projectStore: projectStore,\n                bookmarkResolver: developmentBookmarkResolver"))
        XCTAssertTrue(registryFactory.contains("DevelopmentPullRequestMergeTool(\n                projectStore: projectStore,\n                bookmarkResolver: developmentBookmarkResolver"))
        XCTAssertTrue(registryFactory.contains(".developmentReviewPullRequestGate"))
        XCTAssertTrue(registryFactory.contains(".developmentMergePullRequest"))
        XCTAssertFalse(registryFactory.contains("ToolRegistryFactory.developerMode("))
        XCTAssertTrue(registryFactory.contains("let artifactStore = SQLiteArtifactStore(connection: connection)"))
        XCTAssertTrue(appSource.contains("#if DEBUG\nprivate struct RuntimeDevelopmentPRSmokeBookmarkResolver"))
        XCTAssertTrue(appSource.contains("SUISUI_RUNTIME_DEVELOPMENT_PR_SMOKE_BOOKMARK"))
        XCTAssertFalse(appSource.contains("SUISUI_RUNTIME_DEVELOPMENT_PR_FIXTURE_BOOKMARK"))
        XCTAssertTrue(appSource.contains("suisui-runtime-development-pr-smoke:"))
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
        XCTAssertTrue(reviewFactory.contains("SQLiteApprovalReplayStore(connection: connection)"))
        XCTAssertTrue(reviewFactory.contains("replayStore: runtime.replayStore"))
        XCTAssertTrue(reviewFactory.contains("executionReceiptStore: runtime.receiptStore"))
        XCTAssertTrue(reviewFactory.contains("Review execution tools are unavailable because audit logging or local data stores could not be opened."))
    }

    func testReviewRuntimePersistsExecutionReceiptsUnderApplicationSupport() throws {
        let appSource = try readAppShellSource()

        XCTAssertTrue(appSource.contains("static func makeExecutionReceiptStore() throws -> any ExecutionReceiptStore"))
        XCTAssertTrue(appSource.contains("FileExecutionReceiptStore("))
        XCTAssertTrue(appSource.contains("appendingPathComponent(\"ExecutionReceipts\", isDirectory: true)"))
    }

    func testExternalSideEffectRecoveryRunsAtDatabaseStartupNotRegistryConstruction() throws {
        let appRuntime = try readPackageFile("Sources/SuisuiApp/Composition/AppRuntimeFactory.swift")
        let registryRuntime = try readPackageFile("Sources/SuisuiApp/Composition/RuntimeToolCompositionFactory.swift")

        XCTAssertTrue(appRuntime.contains("externalSideEffectStartupRecovery.recoverOnce("))
        XCTAssertTrue(appRuntime.contains("SQLiteMigrationRunner.migrate("))
        XCTAssertFalse(registryRuntime.contains("recoverStartedAsUnknown("))
        XCTAssertFalse(registryRuntime.contains("recoverOnce("))
    }

    func testProductionLaunchRunsAutomaticConversationRetentionOffMainActorAndAuditsOutcome()
        throws
    {
        let appSource = try readPackageFile(
            "Sources/SuisuiApp/SuisuiApp.swift"
        )
        let runtimeSource = try readPackageFile(
            "Sources/SuisuiApp/Composition/ConversationRetentionRuntime.swift"
        )

        XCTAssertTrue(
            appSource.contains(
                "ConversationRetentionRuntime.shared.start()"
            )
        )
        XCTAssertTrue(
            runtimeSource.contains(
                "Task.detached(priority: .utility)"
            )
        )
        XCTAssertTrue(
            runtimeSource.contains(
                "VoiceTaskConversationAutomaticRetentionRunner().run("
            )
        )
        XCTAssertTrue(runtimeSource.contains("RedactingAuditLogger("))
        XCTAssertTrue(runtimeSource.contains("AuditEvent("))
        XCTAssertFalse(runtimeSource.contains("try?"))
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

    func testVoiceRuntimePersistsConversationOrchestrationWithoutMemoryFallback() throws {
        let appSource = try readAppShellSource()
        let voiceFactoryStart = try XCTUnwrap(
            appSource.range(of: "static func makeVoiceCaptureViewModel()")
        )
        let nextFactoryStart = try XCTUnwrap(
            appSource.range(
                of: "static func loadRuntimeSettings()",
                range: voiceFactoryStart.upperBound..<appSource.endIndex
            )
        )
        let voiceFactory = String(
            appSource[
                voiceFactoryStart.lowerBound..<nextFactoryStart.lowerBound
            ]
        )

        XCTAssertTrue(
            voiceFactory.contains(
                "SQLiteVoiceTaskConversationOrchestrationStateStore("
            )
        )
        XCTAssertTrue(
            voiceFactory.contains("connection: connection")
        )
        XCTAssertTrue(
            voiceFactory.contains(
                "conversationOrchestrator: conversationOrchestrator"
            )
        )
        XCTAssertFalse(
            voiceFactory.contains("InMemoryVoiceTaskConversation")
        )
        XCTAssertTrue(
            voiceFactory.contains(
                "let sqliteConversationStore = SQLiteVoiceTaskConversationStore("
            )
        )
        XCTAssertTrue(
            voiceFactory.contains(
                "conversationStore: sqliteConversationStore"
            )
        )
    }

    func testAssistantQueueRuntimeValidatesConversationLinksAgainstCurrentTaskSnapshot() throws {
        let appSource = try readAppShellSource()
        let coordinatorStart = try XCTUnwrap(
            appSource.range(
                of: "private static func makeAssistantQueueExecutionCoordinator("
            )
        )
        let coordinatorEnd = try XCTUnwrap(
            appSource.range(
                of: "\n    }\n}",
                range: coordinatorStart.upperBound..<appSource.endIndex
            )
        )
        let coordinator = String(
            appSource[
                coordinatorStart.lowerBound..<coordinatorEnd.upperBound
            ]
        )

        XCTAssertTrue(
            coordinator.contains(
                "let conversationStore = SQLiteVoiceTaskConversationStore("
            )
        )
        XCTAssertTrue(
            coordinator.contains(
                "conversationActionLinkStore: conversationStore"
            )
        )
        XCTAssertTrue(
            coordinator.contains(
                "taskSnapshotFingerprintProvider:"
            )
        )
        XCTAssertTrue(
            coordinator.contains(
                "ConversationTaskSnapshotFingerprint.make("
            )
        )
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

    func testProjectBoardRuntimeReconcilesManagedInboxAudioWithoutHidingTranscriptOnFailure() throws {
        let projectRuntimeSource = try readPackageFile(
            "Sources/SuisuiApp/Composition/ProjectBoardRuntimeFactory.swift"
        )
        let voiceRuntimeSource = try readPackageFile(
            "Sources/SuisuiApp/Composition/VoiceRuntimeFactory.swift"
        )
        let viewModelRuntimeStart = try XCTUnwrap(
            projectRuntimeSource.range(
                of: "static func makeProjectBoardViewModel(runtime: ProjectBoardRuntimeBundle)"
            )
        )
        let availableStart = try XCTUnwrap(
            projectRuntimeSource.range(
                of: "case let .available(",
                range: viewModelRuntimeStart.upperBound..<projectRuntimeSource.endIndex
            )
        )
        let unavailableStart = try XCTUnwrap(
            projectRuntimeSource.range(
                of: "case let .unavailable(error):",
                range: availableStart.upperBound..<projectRuntimeSource.endIndex
            )
        )
        let availableRuntime = String(
            projectRuntimeSource[
                availableStart.lowerBound..<unavailableStart.lowerBound
            ]
        )
        let prepareStart = try XCTUnwrap(
            projectRuntimeSource.range(of: "static func prepareProjectBoardRuntimeBundle()")
        )
        let bundleStart = try XCTUnwrap(
            projectRuntimeSource.range(
                of: "static func makeProjectBoardRuntimeBundle()",
                range: prepareStart.upperBound..<projectRuntimeSource.endIndex
            )
        )
        let prepareRuntime = String(
            projectRuntimeSource[prepareStart.lowerBound..<bundleStart.lowerBound]
        )
        let synchronousViewModelStart = try XCTUnwrap(
            projectRuntimeSource.range(
                of: "static func makeProjectBoardViewModel()",
                range: bundleStart.upperBound..<projectRuntimeSource.endIndex
            )
        )
        let synchronousBundleRuntime = String(
            projectRuntimeSource[bundleStart.lowerBound..<synchronousViewModelStart.lowerBound]
        )
        let onceStart = try XCTUnwrap(
            projectRuntimeSource.range(of: "static func reconcileManagedInboxAudioOnce(")
        )
        let reconciliationStart = try XCTUnwrap(
            projectRuntimeSource.range(
                of: "static func reconcileManagedInboxAudio(",
                range: onceStart.upperBound..<projectRuntimeSource.endIndex
            )
        )
        let onceRuntime = String(
            projectRuntimeSource[onceStart.lowerBound..<reconciliationStart.lowerBound]
        )

        XCTAssertTrue(
            projectRuntimeSource.contains(
                "static func reconcileManagedInboxAudio("
            )
        )
        XCTAssertFalse(
            voiceRuntimeSource.contains(
                "private static func reconcileManagedInboxAudio("
            )
        )
        XCTAssertFalse(voiceRuntimeSource.contains("reconcileManagedInboxAudio("))
        XCTAssertFalse(voiceRuntimeSource.contains("reconcileManagedInboxAudioOnce("))
        XCTAssertTrue(
            voiceRuntimeSource.contains(
                "let inboxAudioFileStore = try? ManagedInboxAudioFileStore()"
            )
        )
        XCTAssertTrue(
            projectRuntimeSource.contains(
                "private enum InboxAudioReconciliationGate"
            )
        )
        XCTAssertTrue(
            projectRuntimeSource.contains(
                "nonisolated(unsafe) static var hasAttempted = false"
            )
        )
        XCTAssertTrue(
            prepareRuntime.contains(
                "reconcileManagedInboxAudioOnce(connection: connection)"
            )
        )
        XCTAssertTrue(prepareRuntime.contains("Task.detached(priority: .userInitiated)"))
        XCTAssertFalse(synchronousBundleRuntime.contains("reconcileManagedInboxAudioOnce("))
        XCTAssertTrue(onceRuntime.contains("InboxAudioReconciliationGate.lock.lock()"))
        XCTAssertTrue(onceRuntime.contains("defer { InboxAudioReconciliationGate.lock.unlock() }"))
        XCTAssertTrue(onceRuntime.contains("guard InboxAudioReconciliationGate.hasAttempted == false"))
        XCTAssertTrue(onceRuntime.contains("InboxAudioReconciliationGate.hasAttempted = true"))
        XCTAssertFalse(
            availableRuntime.contains(
                "reconcileManagedInboxAudioOnce(connection: connection)"
            )
        )
        XCTAssertTrue(
            availableRuntime.contains(
                "let inboxCaptureStore = SQLiteInboxCaptureStore(connection: connection)"
            )
        )
        XCTAssertTrue(
            availableRuntime.contains(
                "inboxCaptureStore: inboxCaptureStore"
            )
        )
        XCTAssertTrue(
            projectRuntimeSource.contains(
                "Inbox audio reconciliation failed category=audio_reconciliation_failed"
            )
        )
        XCTAssertFalse(availableRuntime.contains("return .unavailable(error)"))
        XCTAssertFalse(availableRuntime.contains("error.localizedDescription"))
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

        XCTAssertTrue(appSource.contains("SUISUI_OPEN_VOICE_COMMAND_ON_LAUNCH"))
        XCTAssertTrue(appSource.contains("openInAppVoiceCommandForEvidenceIfRequested()"))
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

    func testVoiceFailureSurfaceOffersTypedNextStepAffordances() throws {
        let voiceViewSource = try readPackageFile("Sources/SuisuiApp/Views/VoiceCaptureView.swift")
        let voiceModelSource = try readPackageFile("Sources/SuisuiCore/Voice/VoiceCaptureViewModel.swift")

        // T-10: provider-readiness failures must surface an Open Settings
        // affordance; transient network/rate-limit failures must surface a
        // retry that reruns plan generation with the current transcript.
        XCTAssertTrue(voiceViewSource.contains(".accessibilityIdentifier(\"voice-error-open-settings\")"))
        XCTAssertTrue(voiceViewSource.contains(".accessibilityIdentifier(\"voice-error-retry\")"))
        XCTAssertTrue(voiceViewSource.contains(".accessibilityIdentifier(\"voice-answer-retry\")"))
        XCTAssertTrue(voiceViewSource.contains("case .openSettings:"))
        XCTAssertTrue(voiceViewSource.contains("case .retryPlanGeneration:"))
        XCTAssertTrue(voiceViewSource.contains("openInActiveSceneOrRequestNew(route: .settings)"))
        XCTAssertFalse(voiceViewSource.contains("SettingsLink"))
        XCTAssertTrue(voiceViewSource.contains("await viewModel.generatePlan()"))

        // Classification is on the typed provider error, never on message text.
        XCTAssertTrue(voiceModelSource.contains("public enum VoiceCaptureFailureRecovery"))
        XCTAssertTrue(voiceModelSource.contains("case .authenticationFailed, .executionNotApproved:"))
        XCTAssertTrue(voiceModelSource.contains("return .openSettings"))
        XCTAssertTrue(voiceModelSource.contains("case .network, .rateLimited:"))
        XCTAssertTrue(voiceModelSource.contains("return .retryPlanGeneration"))
    }

    func testVoiceCaptureMakesReadinessAndCaptureModesTruthful() throws {
        let voiceSource = try readPackageFile("Sources/SuisuiApp/Views/VoiceCaptureView.swift")
        let english = try readPackageFile("Sources/SuisuiApp/Resources/en.lproj/Localizable.strings")
        let japanese = try readPackageFile("Sources/SuisuiApp/Resources/ja.lproj/Localizable.strings")
        let runtimeSmoke = try readPackageFile("script/check_runtime_voice_review_smoke.sh")

        XCTAssertTrue(voiceSource.contains(".disabled(!viewModel.canGeneratePlan ||"))
        XCTAssertTrue(voiceSource.contains("Label(\"Record once\", systemImage:"))
        XCTAssertTrue(voiceSource.contains("Label(\"Hands-free mode\", systemImage:"))
        XCTAssertTrue(voiceSource.contains(".accessibilityIdentifier(\"voice-hands-free-provider-privacy\")"))
        XCTAssertTrue(voiceSource.contains("localizedDisplay(\"Speech provider: %@\", viewModel.handsFreeModeProviderName)"))
        XCTAssertFalse(voiceSource.contains("String(format: String(localized: \"Speech provider: %@\")"))
        XCTAssertTrue(voiceSource.contains("Audio is processed by the selected speech-to-text provider only while Hands-free mode is listening."))
        XCTAssertTrue(voiceSource.contains(".help(localizedSettingsDisplay(actionReadinessMessage))"))
        XCTAssertTrue(voiceSource.contains(".accessibilityLabel(\"Start Hands-free mode\")"))
        XCTAssertTrue(voiceSource.contains(".accessibilityLabel(\"Stop Hands-free mode\")"))
        XCTAssertTrue(
            voiceSource.contains(
                "Label(\"Voice Command\", systemImage: \"mic\")\n                        .font(.headline)\n                        .accessibilityIdentifier(\"voice-command-root\")"
            )
        )
        XCTAssertEqual(
            voiceSource.components(separatedBy: ".accessibilityIdentifier(\"voice-command-root\")").count - 1,
            1
        )
        XCTAssertTrue(
            voiceSource.contains(
                ".accessibilityIdentifier(\"voice-command-quick-command-tab\")"
            )
        )
        XCTAssertTrue(voiceSource.contains("voice-command-understood-rail"))
        XCTAssertTrue(voiceSource.contains("voice-command-context-rail"))
        XCTAssertTrue(voiceSource.contains("struct VoiceListeningOrb"))
        XCTAssertTrue(voiceSource.contains("VoiceVisualEvidenceSurface"))
        XCTAssertTrue(voiceSource.contains("SUISUI_VISUAL_EVIDENCE_VOICE_SURFACE"))
        XCTAssertTrue(voiceSource.contains("voice-command-listening-hero"))
        XCTAssertTrue(voiceSource.contains("voice-command-listening-timer"))
        XCTAssertTrue(voiceSource.contains("case conversation"))
        XCTAssertTrue(voiceSource.contains("voice-conversation-tab"))
        XCTAssertTrue(voiceSource.contains("voice-command-understood-action-"))
        XCTAssertTrue(voiceSource.contains("Create preparation task"))
        XCTAssertTrue(voiceSource.contains("voice-command-conversation-log"))
        XCTAssertTrue(voiceSource.contains("voice-command-confirmation-chips"))
        XCTAssertTrue(
            voiceSource.contains(
                "Label(\"Record once\", systemImage: \"waveform.badge.mic\")\n                .font(.subheadline.weight(.semibold))\n                .accessibilityIdentifier(\"voice-command-capture-zone\")"
            )
        )
        XCTAssertTrue(
            voiceSource.contains(
                "Label(\"Hands-free mode\", systemImage: \"waveform\")\n                    .font(.caption.weight(.semibold))\n                    .foregroundStyle(.secondary)\n                    .accessibilityIdentifier(\"voice-agent-panel\")"
            )
        )
        XCTAssertEqual(
            voiceSource.components(separatedBy: ".accessibilityIdentifier(\"voice-command-capture-zone\")").count - 1,
            1
        )
        XCTAssertEqual(
            voiceSource.components(separatedBy: ".accessibilityIdentifier(\"voice-agent-panel\")").count - 1,
            1
        )

        let examplesStart = try XCTUnwrap(voiceSource.range(of: "private struct VoiceCommandExampleChips"))
        let readinessStart = try XCTUnwrap(
            voiceSource.range(of: "private struct VoiceCommandActionReadinessRow", range: examplesStart.upperBound..<voiceSource.endIndex)
        )
        let examplesSource = String(voiceSource[examplesStart.lowerBound..<readinessStart.lowerBound])
        XCTAssertTrue(examplesSource.contains("onInsert(text)"))
        XCTAssertFalse(examplesSource.contains("generatePlan"))
        XCTAssertFalse(examplesSource.contains("saveDraftToInbox"))
        XCTAssertFalse(examplesSource.contains("Task {"))

        for localization in [english, japanese] {
            XCTAssertTrue(localization.contains("\"Record once\" = "))
            XCTAssertTrue(localization.contains("\"Hands-free mode\" = "))
            XCTAssertTrue(localization.contains("\"Speech provider: %@\" = "))
            XCTAssertTrue(localization.contains("\"Audio is processed by the selected speech-to-text provider only while Hands-free mode is listening.\" = "))
        }

        XCTAssertTrue(runtimeSmoke.contains("setTextAreaContaining \"voice-command-input\" \"   \""))
        XCTAssertTrue(runtimeSmoke.contains("waitForControlEnabledState \"voice-command-generate-plan\" \"false\""))
        XCTAssertTrue(runtimeSmoke.contains("waitForControlEnabledState \"voice-command-generate-plan\" \"true\""))
        XCTAssertTrue(runtimeSmoke.contains("OK: Generate Plan stayed disabled for whitespace and enabled for a valid draft"))
        XCTAssertTrue(runtimeSmoke.contains("AX_HELPERS=\"${AX_HELPERS:-$ROOT_DIR/script/ui_accessibility_smoke_helpers.sh}\""))
        XCTAssertTrue(runtimeSmoke.contains("ax_wait_for_owned_app_pid"))
        XCTAssertTrue(runtimeSmoke.contains("ax_wait_for_owned_process_identity"))
        XCTAssertTrue(runtimeSmoke.contains("ax_process_matches_identity"))
        XCTAssertTrue(runtimeSmoke.contains("ax_terminate_owned_process"))
        XCTAssertTrue(runtimeSmoke.contains("application processes whose unix id is appPID"))
        XCTAssertTrue(runtimeSmoke.contains("SUISUI_LANGUAGE_PREFERENCE=\"$locale\""))
        XCTAssertTrue(runtimeSmoke.contains("run_voice_readiness_matrix english 1024"))
        XCTAssertTrue(runtimeSmoke.contains("run_voice_readiness_matrix japanese 1024"))
        XCTAssertTrue(runtimeSmoke.contains("local osascript_pid=$!"))
        XCTAssertTrue(runtimeSmoke.contains("kill \"$osascript_pid\""))
        XCTAssertTrue(runtimeSmoke.contains("wait \"$osascript_pid\""))
        XCTAssertFalse(runtimeSmoke.contains("pkill -x"))
        XCTAssertFalse(runtimeSmoke.contains("pgrep -x"))
        XCTAssertFalse(runtimeSmoke.contains("tell process appName"))
        XCTAssertFalse(runtimeSmoke.contains("window 1"))
        XCTAssertGreaterThanOrEqual(
            runtimeSmoke.components(
                separatedBy: "SELECT count(*) FROM assistant_queue_items WHERE id LIKE 'action-plan:daily-planning:%';"
            ).count - 1,
            4
        )
    }

    func testSettingsPrivacyDiagnosticsExportIsMetadataOnlyWithInlineError() throws {
        let appSource = try readAppShellSource()
        let coreSource = try readPackageFile("Sources/SuisuiCore/App/DiagnosticsReport.swift")

        // T-18: the export button lives in Settings > Privacy, writes through
        // NSSavePanel, states inclusions/exclusions, and reports errors inline.
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"settings-export-diagnostics\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"settings-export-diagnostics-caption\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"settings-export-diagnostics-error\")"))
        XCTAssertTrue(appSource.contains("suisui-diagnostics-"))
        XCTAssertTrue(appSource.contains("AppRuntimeFactory.makeDiagnosticsReportText()"))
        XCTAssertTrue(coreSource.contains("static let privacyHeader"))
        XCTAssertTrue(coreSource.contains("Audit log entries (the audit log stores plan content, so it is excluded entirely)"))
    }

    func testSettingsSurfaceStartsWithStatusOverviewForCoreOperationalAreas() throws {
        let appSource = try readAppShellSource()
        let overviewSource = try readPackageFile("Sources/SuisuiApp/Views/SettingsStatusOverviewView.swift")

        let overviewRange = try XCTUnwrap(appSource.range(of: "SettingsStatusOverviewView("))
        let overviewTabRange = try XCTUnwrap(appSource.range(of: "struct SettingsOverviewFeatureView: View"))
        let appearanceTabRange = try XCTUnwrap(appSource.range(of: "struct SettingsAppearanceFeatureView: View"))

        XCTAssertLessThan(overviewTabRange.lowerBound, overviewRange.lowerBound)
        XCTAssertLessThan(overviewRange.lowerBound, appearanceTabRange.lowerBound)
        XCTAssertTrue(appSource.contains("Section(\"Status Overview\")"))
        XCTAssertTrue(appSource.contains("title: \"AI Provider\""))
        XCTAssertTrue(appSource.contains("title: \"MCP\""))
        XCTAssertTrue(appSource.contains("title: \"Sync\""))
        XCTAssertTrue(appSource.contains("title: \"Privacy\""))
        XCTAssertTrue(appSource.contains("settingsViewModel.settings.aiProvider.displayName"))
        XCTAssertTrue(appSource.contains("let syncStatusLabel = builder.syncViewModel?.statusLabel ?? \"Set up when needed\""))
        XCTAssertTrue(appSource.contains("let mcpStatusLabel = builder.externalMCPViewModel?.connectionCheckResultLabel ?? \"Set up when needed\""))
        XCTAssertTrue(appSource.contains("SettingsReadinessPresentation.grouped("))
        XCTAssertTrue(appSource.contains("showsAdvanced: showAdvancedSettings"))
        XCTAssertTrue(appSource.contains("SettingsReadinessPresentation.aiProviderCapability("))
        XCTAssertTrue(appSource.contains("readiness: activeAIProviderReadinessRow.readiness"))
        XCTAssertTrue(appSource.contains("SettingsReadinessPresentation.voiceProviderCapability("))
        XCTAssertTrue(appSource.contains("action: .retry(featureID: \"google-calendar\")"))
        XCTAssertTrue(appSource.contains("settingsViewModel.settings.notificationsEnabled"))
        XCTAssertTrue(overviewSource.contains("case .readyNow: \"Ready\""))
        XCTAssertTrue(overviewSource.contains("case .setUpWhenUsed: \"Set Up When Used\""))
        XCTAssertTrue(overviewSource.contains("case .needsAttention: \"Needs Attention\""))
        XCTAssertTrue(overviewSource.contains(".accessibilityLabel(localizedSettingsDisplay(group.group.title))"))
        XCTAssertTrue(overviewSource.contains("settings-readiness-row-"))
        XCTAssertTrue(overviewSource.contains("settings-readiness-action-"))
        XCTAssertTrue(appSource.contains("settings-overview-detail-rail"))
        XCTAssertTrue(appSource.contains("settings-ai-readiness-rail"))
        XCTAssertTrue(appSource.contains("settings-privacy-root"))
        XCTAssertFalse(overviewSource.contains("LazyVGrid"))
    }

    func testSettingsOverviewSurfacesIntegrationStatusTilesForPhase12() throws {
        let appSource = try readAppShellSource()
        let overviewSource = try readPackageFile("Sources/SuisuiApp/Views/SettingsStatusOverviewView.swift")

        XCTAssertTrue(appSource.contains("integrationPermissionSnapshot: AppRuntimeFactory.makeIntegrationPermissionSnapshot()"))
        XCTAssertTrue(appSource.contains("title: \"STT\""))
        XCTAssertTrue(appSource.contains("title: \"TTS\""))
        XCTAssertTrue(appSource.contains("title: \"Calendar\""))
        XCTAssertTrue(appSource.contains("title: \"Reminder\""))
        XCTAssertTrue(appSource.contains("title: \"Notifications\""))
        XCTAssertTrue(appSource.contains("title: \"Google Calendar\""))
        XCTAssertTrue(appSource.contains("title: \"Data Location\""))
        XCTAssertTrue(appSource.contains("Local whisper.cpp: %@"))
        XCTAssertTrue(appSource.contains("settingsViewModel.localSTTProviderReadinessRow.statusLabel"))
        XCTAssertTrue(appSource.contains("settingsViewModel.ttsProviderReadinessRow.statusLabel"))
        XCTAssertTrue(appSource.contains("integrationPermissionSnapshot.status(for: .calendar)"))
        XCTAssertTrue(appSource.contains("integrationPermissionSnapshot.status(for: .reminders)"))
        XCTAssertTrue(appSource.contains("dataLocationOverviewDetailLabel"))
        XCTAssertTrue(appSource.contains("The app container is already a valid local-first data location."))
        XCTAssertTrue(appSource.contains("notification permission has its own row"))
        XCTAssertTrue(overviewSource.contains(".accessibilityIdentifier(\"settings-status-overview\")"))
    }

    func testSettingsExposesReadyGatedKokoroTTSProviderControls() throws {
        let appSource = try readAppShellSource()
        let aiTabStart = try XCTUnwrap(appSource.range(of: "struct SettingsAIFeatureView: View"))
        let syncTabStart = try XCTUnwrap(appSource.range(of: "struct SettingsSyncFeatureView: View"))
        let aiTabSource = String(appSource[aiTabStart.lowerBound..<syncTabStart.lowerBound])

        XCTAssertTrue(aiTabSource.contains("Picker(\n                    \"Text to Speech\""))
        XCTAssertTrue(aiTabSource.contains("settingsViewModel.selectableTTSProviders"))
        XCTAssertTrue(aiTabSource.contains("SelectedTTSProviderStatusRow(row: settingsViewModel.ttsProviderReadinessRow)"))
        XCTAssertTrue(aiTabSource.contains(".accessibilityIdentifier(\"settings-tts-provider-picker\")"))
        XCTAssertTrue(aiTabSource.contains("accessibilityIdentifier: \"settings-kokoro-executable-path\""))
        XCTAssertTrue(aiTabSource.contains(".accessibilityIdentifier(\"settings-tts-language-picker\")"))
        XCTAssertTrue(aiTabSource.contains(".accessibilityIdentifier(\"settings-tts-voice-id\")"))
        XCTAssertTrue(aiTabSource.contains(".accessibilityIdentifier(\"settings-tts-test-play\")"))
        XCTAssertTrue(aiTabSource.contains("Task {\n                        await settingsViewModel.testTTSPlayback("))
        XCTAssertTrue(aiTabSource.contains("context.makeTextToSpeechPreviewer()"))
        XCTAssertTrue(appSource.contains("textToSpeechPreviewerFactory: AppRuntimeFactory.makeTextToSpeechPreviewer"))
        XCTAssertFalse(aiTabSource.contains("TTS playback adapter is not connected in this slice."))
        XCTAssertFalse(aiTabSource.contains("TTSProvider.systemSpeech.unavailableReason"))
        XCTAssertFalse(aiTabSource.contains(".accessibilityIdentifier(\"settings-tts-unavailable\")"))
    }

    func testSettingsExposesSelectedSTTReadinessBeforeRuntimeSelection() throws {
        let appSource = try readAppShellSource()
        let coreSource = try readPackageFile("Sources/SuisuiCore/App/AppSettings.swift")
        let aiTabStart = try XCTUnwrap(appSource.range(of: "struct SettingsAIFeatureView: View"))
        let syncTabStart = try XCTUnwrap(appSource.range(of: "struct SettingsSyncFeatureView: View"))
        let aiTabSource = String(appSource[aiTabStart.lowerBound..<syncTabStart.lowerBound])

        XCTAssertTrue(aiTabSource.contains("LocalSTTProviderStatusRow(row: settingsViewModel.selectedSTTProviderReadinessRow)"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"settings-local-stt-readiness-row\")"))
        XCTAssertTrue(appSource.contains("Text(localizedSettingsDisplay(row.statusLabel))"))
        XCTAssertTrue(appSource.contains("struct LocalSTTProviderStatusRow"))
        XCTAssertTrue(appSource.contains("STT provider readiness"))
        XCTAssertTrue(coreSource.contains("Uses on-device Apple Speech without an API key"))
        XCTAssertTrue(coreSource.contains("run the local voice runtime smoke"))
    }

    func testSettingsOverviewSurfacesProValueWithoutOpeningSyncOrMCPTabs() throws {
        let appSource = try readAppShellSource()
        let audit = try readPackageFile("docs/ux/click-path-audit.md")
        let investorReview = try readPackageFile("docs/product/investor-review.md")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")
        let overviewStart = try XCTUnwrap(appSource.range(of: "struct SettingsOverviewFeatureView: View"))
        let appearanceStart = try XCTUnwrap(appSource.range(of: "struct SettingsAppearanceFeatureView: View"))
        let overviewSource = String(appSource[overviewStart.lowerBound..<appearanceStart.lowerBound])

        XCTAssertTrue(overviewSource.contains("if dependencies.showAdvanced"))
        XCTAssertTrue(overviewSource.contains("Section(\"Pro Value\")"))
        XCTAssertTrue(overviewSource.contains("ProValueOverviewRow("))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"settings-pro-value-overview-row\")"))
        XCTAssertTrue(overviewSource.contains("syncValueLabel: dependencies.syncValueLabel"))
        XCTAssertTrue(overviewSource.contains("syncBoundaryLabel: dependencies.syncBoundaryLabel"))
        XCTAssertTrue(overviewSource.contains("mcpValueLabel: dependencies.mcpValueLabel"))
        XCTAssertTrue(overviewSource.contains("mcpBoundaryLabel: dependencies.mcpBoundaryLabel"))
        XCTAssertLessThan(
            try XCTUnwrap(overviewSource.range(of: "SettingsStatusOverviewView(")).lowerBound,
            try XCTUnwrap(overviewSource.range(of: "ProValueOverviewRow(")).lowerBound
        )
        XCTAssertTrue(audit.contains("Settings Overview Pro Value row"))
        XCTAssertTrue(investorReview.contains("Settings Overview now surfaces Pro value and fail-closed boundaries before opening Sync or MCP tabs"))
        XCTAssertTrue(phase.contains("[x] Overview tabにPro Value rowを追加し、Sync/MCPタブを開く前に有料価値とFree/local-only/fail-closed境界が分かる。"))
    }

    func testSettingsSurfaceUsesTabbedCategoriesInsteadOfOneLongForm() throws {
        let appSource = try readAppShellSource()
        let appearanceSectionSource = try readPackageFile("Sources/SuisuiApp/Views/SettingsAppearanceSection.swift")
        let audit = try readPackageFile("docs/ux/click-path-audit.md")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")

        XCTAssertTrue(appSource.contains("TabView(selection: $selectedTab) {"))
        XCTAssertTrue(appSource.contains("enum SettingsTab: String"))
        XCTAssertTrue(appSource.contains("@State private var selectedTab: SettingsTab"))
        XCTAssertTrue(appSource.contains("struct SettingsOverviewFeatureView: View"))
        XCTAssertTrue(appSource.contains("struct SettingsAppearanceFeatureView: View"))
        XCTAssertTrue(appSource.contains("struct SettingsAIFeatureView: View"))
        XCTAssertTrue(appSource.contains("struct SettingsMCPFeatureView: View"))
        XCTAssertTrue(appSource.contains("struct SettingsSyncFeatureView: View"))
        XCTAssertTrue(appSource.contains("struct SettingsPrivacyFeatureView: View"))
        XCTAssertTrue(appSource.contains("Label(\"Overview\", systemImage: \"gauge.with.dots.needle.bottom.50percent\")"))
        XCTAssertTrue(appSource.contains("Label(\"Appearance\", systemImage: \"circle.lefthalf.filled\")"))
        XCTAssertTrue(appSource.contains("Label(\"AI\", systemImage: \"brain.head.profile\")"))
        XCTAssertTrue(appSource.contains("Label(\"MCP\", systemImage: \"externaldrive.connected.to.line.below\")"))
        XCTAssertTrue(appSource.contains("Label(\"Sync\", systemImage: \"arrow.triangle.2.circlepath\")"))
        XCTAssertTrue(appSource.contains("Label(\"Privacy\", systemImage: \"lock.shield\")"))

        let overviewStart = try XCTUnwrap(appSource.range(of: "struct SettingsOverviewFeatureView"))
        let appearanceStart = try XCTUnwrap(appSource.range(of: "struct SettingsAppearanceFeatureView"))
        let aiStart = try XCTUnwrap(appSource.range(of: "struct SettingsAIFeatureView"))
        let syncStart = try XCTUnwrap(appSource.range(of: "struct SettingsSyncFeatureView"))
        let privacyStart = try XCTUnwrap(appSource.range(of: "struct SettingsPrivacyFeatureView"))
        let mcpStart = try XCTUnwrap(appSource.range(of: "struct SettingsMCPFeatureView"))

        let overviewSource = String(appSource[overviewStart.lowerBound..<appearanceStart.lowerBound])
        let appearanceSource = String(appSource[appearanceStart.lowerBound..<aiStart.lowerBound])
        let aiSource = String(appSource[aiStart.lowerBound..<syncStart.lowerBound])
        let syncSource = String(appSource[syncStart.lowerBound..<privacyStart.lowerBound])
        let privacySource = String(appSource[privacyStart.lowerBound..<mcpStart.lowerBound])
        let mcpSource = String(appSource[mcpStart.lowerBound..<appSource.endIndex])

        XCTAssertTrue(overviewSource.contains("Section(\"Status Overview\")"))
        XCTAssertFalse(overviewSource.contains("SettingsAppearanceSection(appearancePreference: $appearancePreference, languagePreference: $languagePreference)"))
        XCTAssertTrue(overviewSource.contains("settings-overview-detail-rail"))
        XCTAssertTrue(overviewSource.contains("CockpitSplitLayout.presentsSplitRail("))
        XCTAssertTrue(overviewSource.contains("overviewDetailRail"))
        // Narrow Settings keep the readiness rail reachable by stacking under the form.
        XCTAssertTrue(overviewSource.contains("ScrollView"))
        XCTAssertTrue(aiSource.contains("settings-ai-readiness-rail"))
        XCTAssertTrue(aiSource.contains("CockpitSplitLayout.presentsSplitRail("))
        XCTAssertTrue(aiSource.contains("aiReadinessRail"))
        XCTAssertFalse(appearanceSectionSource.contains("Save Changes"))
        XCTAssertFalse(appearanceSource.contains("Save Changes"))
        XCTAssertFalse(appearanceSectionSource.contains("Proプラン"))
        XCTAssertTrue(appearanceSource.contains("SettingsAppearanceSection(appearancePreference: context.$appearancePreference, languagePreference: context.$languagePreference)"))
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
        let selectedFieldsStart = try XCTUnwrap(appSource.range(of: "var selectedProviderConfigurationFields: some View"))
        let nextFieldStart = try XCTUnwrap(appSource.range(of: "var openAIProviderSettingsFields: some View"))
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
        XCTAssertTrue(appSource.contains("var openAIProviderSettingsFields: some View"))
        XCTAssertTrue(appSource.contains("var claudeProviderSettingsFields: some View"))
        XCTAssertTrue(appSource.contains("var geminiProviderSettingsFields: some View"))
        XCTAssertTrue(appSource.contains("var groqProviderSettingsFields: some View"))
        XCTAssertTrue(appSource.contains("var openCodeProviderSettingsFields: some View"))
        XCTAssertTrue(appSource.contains("var openRouterProviderSettingsFields: some View"))
        XCTAssertTrue(appSource.contains("var ollamaProviderSettingsFields: some View"))

        let aiStart = try XCTUnwrap(appSource.range(of: "struct SettingsAIFeatureView"))
        let syncStart = try XCTUnwrap(appSource.range(of: "struct SettingsSyncFeatureView"))
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
        let aiStart = try XCTUnwrap(appSource.range(of: "struct SettingsAIFeatureView: View"))
        let syncStart = try XCTUnwrap(appSource.range(of: "struct SettingsSyncFeatureView: View"))
        let aiSource = String(appSource[aiStart.lowerBound..<syncStart.lowerBound])

        XCTAssertTrue(appSource.contains("SelectedAIProviderStatusRow("))
        XCTAssertTrue(appSource.contains("AIProviderReadinessSummaryRow("))
        XCTAssertTrue(appSource.contains("settingsViewModel.providerReadinessRows"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"ai-provider-readiness-row\")"))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"ai-provider-readiness-summary\")"))
        XCTAssertTrue(appSource.contains("var providerReadinessDetailLabel: String"))
        XCTAssertTrue(appSource.contains("var activeAIProviderNextActionLabel: String"))
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
        XCTAssertTrue(factorySource.contains("settings.whisperCppExecutablePath ?? \"\""))
        XCTAssertTrue(factorySource.contains("WhisperCppLocalSTTProvider(configuration: configuration)"))
        XCTAssertFalse(factorySource.contains(".openAITranscribe, .appleSpeechAnalyzer, .localWhisperKit, .localWhisperCpp"))
    }

    func testRuntimeSTTFactoryUsesAppleSpeechProviderWithoutOpenAIFallback() throws {
        let appSource = try readAppShellSource()
        let factoryStart = try XCTUnwrap(appSource.range(of: "private static func makeSpeechToTextProvider"))
        let factorySource = String(appSource[factoryStart.lowerBound..<appSource.endIndex])
        let providerSource = try readPackageFile("Sources/SuisuiApp/Adapters/AppleSpeechRecognitionProvider.swift")

        XCTAssertTrue(factorySource.contains("case .appleSpeechAnalyzer:"))
        XCTAssertTrue(factorySource.contains("AppleSpeechRecognitionProvider()"))
        XCTAssertFalse(factorySource.contains("case .openAITranscribe, .appleSpeechAnalyzer"))
        XCTAssertTrue(providerSource.contains("import Speech"))
        XCTAssertTrue(providerSource.contains("SFSpeechRecognizer.requestAuthorization"))
        XCTAssertTrue(providerSource.contains("SFSpeechURLRecognitionRequest"))
        XCTAssertTrue(providerSource.contains("requiresOnDeviceRecognition = true"))
        XCTAssertTrue(providerSource.contains("suisuiAppleSpeechAuthorizationDidChange"))
        let buildScript = try readPackageFile("script/build_and_run.sh")
        XCTAssertTrue(buildScript.contains("NSSpeechRecognitionUsageDescription"))
    }

    func testRuntimeTTSFactoryUsesAppleSystemSpeechWithoutKokoroFallback() throws {
        let appSource = try readAppShellSource()
        let runtimeFactoryStart = try XCTUnwrap(appSource.range(of: "enum AppTextToSpeechRuntimeFactory"))
        let runtimeFactorySource = String(appSource[runtimeFactoryStart.lowerBound..<appSource.endIndex])
        let providerSource = try readPackageFile("Sources/SuisuiApp/Adapters/AppleSystemSpeechProvider.swift")

        XCTAssertTrue(appSource.contains("static func makeTextToSpeechPreviewer(settings: AppSettings) -> any TextToSpeechPreviewing"))
        XCTAssertTrue(appSource.contains("AppTextToSpeechRuntimeFactory.makePreviewer(settings: settings)"))
        XCTAssertTrue(appSource.contains("settings.selectedTTSVoiceID"))
        XCTAssertTrue(runtimeFactorySource.contains("case .systemSpeech:"))
        XCTAssertTrue(runtimeFactorySource.contains("AppleSystemSpeechProvider("))
        XCTAssertTrue(runtimeFactorySource.contains("case .localKokoro:"))
        XCTAssertTrue(runtimeFactorySource.contains("KokoroLocalTTSConfiguration("))
        XCTAssertTrue(runtimeFactorySource.contains("normalizedSettings.kokoroExecutablePath ?? \"\""))
        XCTAssertTrue(runtimeFactorySource.contains("normalizedSettings.ttsLanguageCode"))
        XCTAssertTrue(runtimeFactorySource.contains("normalizedSettings.ttsVoiceID"))
        XCTAssertTrue(runtimeFactorySource.contains("KokoroLocalTTSProvider(configuration: configuration)"))
        XCTAssertTrue(runtimeFactorySource.contains("TemporaryDirectoryTextToSpeechPreviewer("))
        XCTAssertTrue(runtimeFactorySource.contains("TextToSpeechPreviewService("))
        XCTAssertTrue(runtimeFactorySource.contains("AVFoundationSpeechAudioPlayer()"))
        XCTAssertTrue(runtimeFactorySource.contains("temporaryDirectory: temporaryDirectory"))
        XCTAssertTrue(providerSource.contains("AVSpeechSynthesizer"))
        XCTAssertTrue(providerSource.contains("AVSpeechSynthesisVoice"))
        XCTAssertTrue(providerSource.contains("baseLanguageCode(selected.language) == baseLanguageCode(languageCode)"))
        XCTAssertTrue(providerSource.contains("AVAudioFile"))
    }

    func testAVFoundationSpeechAudioPlayerUsesAudioPlayerInsteadOfSystemSpeech() throws {
        let source = try readPackageFile("Sources/SuisuiApp/Adapters/AVFoundationSpeechAudioPlayer.swift")

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
        let syncSource = try readPackageFile("Sources/SuisuiCore/App/SyncService.swift")
        let entitlementSource = try readPackageFile("Sources/SuisuiCore/App/Entitlements.swift")

        XCTAssertTrue(appSource.contains("@StateObject private var syncSettingsViewModelLoader: LazyObservableObjectLoader<SyncSettingsViewModel>"))
        XCTAssertTrue(appSource.contains("loadedValue.objectWillChange.sink"))
        XCTAssertTrue(appSource.contains("loadState = .loaded(viewModel)"))
        XCTAssertTrue(appSource.contains("if case .loaded(let loadedSyncViewModel) = context.loadState"))
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
        let syncStart = try XCTUnwrap(appSource.range(of: "struct SettingsSyncFeatureView: View"))
        let privacyStart = try XCTUnwrap(appSource.range(of: "struct SettingsPrivacyFeatureView: View"))
        let syncSource = String(appSource[syncStart.lowerBound..<privacyStart.lowerBound])
        let controlsStart = try XCTUnwrap(appSource.range(of: "struct GoogleCalendarSettingsSaveControls: View"))
        let controlsEnd = try XCTUnwrap(appSource.range(of: "func settingsLazyLoadUnavailableHint", range: controlsStart.lowerBound..<appSource.endIndex))
        let controlsSource = String(appSource[controlsStart.lowerBound..<controlsEnd.lowerBound])

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
        XCTAssertTrue(appSource.contains("var googleCalendarSettingsReadinessRow: GoogleCalendarSettingsReadinessRow"))
        XCTAssertTrue(appSource.contains("GoogleCalendarSettingsReadinessRow(status: googleCalendarSyncStatus)"))
        XCTAssertTrue(syncSource.contains("status: context.googleCalendarSettingsReadinessRow.statusLabel"))
        XCTAssertTrue(syncSource.contains("detail: context.googleCalendarSettingsReadinessRow.detailLabel"))
        XCTAssertTrue(syncSource.contains("nextAction: context.googleCalendarSettingsReadinessRow.nextActionLabel"))
        XCTAssertTrue(syncSource.contains("privacyBoundary: context.googleCalendarSettingsReadinessRow.privacyBoundaryLabel"))
        XCTAssertTrue(syncSource.contains("statusActionLabel: context.googleCalendarSettingsReadinessRow.statusCheckActionLabel"))
        XCTAssertTrue(syncSource.contains("onStatusAction: context.refreshGoogleCalendarSettingsStatus"))
        XCTAssertTrue(appSource.contains("settings-google-calendar-readiness-check"))
        XCTAssertTrue(appSource.contains("settings-google-calendar-readiness-status"))
        XCTAssertTrue(appSource.contains("settings-google-calendar-readiness-detail"))
        XCTAssertTrue(controlsSource.contains("\"Google Calendar ID\""))
        XCTAssertTrue(syncSource.contains("settingsViewModel.settings.googleCalendarID"))
        XCTAssertTrue(syncSource.contains("settingsViewModel.setGoogleCalendarID($0)"))
        XCTAssertTrue(syncSource.contains("GoogleCalendarSettingsSaveControls("))
        XCTAssertTrue(controlsSource.contains("settings-google-calendar-id-save-flow"))
        XCTAssertTrue(controlsSource.contains("settings-google-calendar-id"))
        XCTAssertTrue(syncSource.contains("saveCalendarID: context.saveGoogleCalendarIDSetting"))
        XCTAssertTrue(appSource.contains("func saveGoogleCalendarIDSetting()"))
        XCTAssertTrue(controlsSource.contains("Picker(\"Available Calendar\""))
        XCTAssertTrue(controlsSource.contains("ForEach(calendarListOptions)"))
        XCTAssertTrue(controlsSource.contains("settings-google-calendar-picker"))
        XCTAssertTrue(syncSource.contains("loadCalendarList: context.loadGoogleCalendarList"))
        XCTAssertTrue(controlsSource.contains("settings-google-calendar-list-load"))
        XCTAssertTrue(syncSource.contains("isCalendarListLoadDisabled: !context.canLoadGoogleCalendarList"))
        XCTAssertTrue(appSource.contains("func loadGoogleCalendarList()"))
        XCTAssertTrue(appSource.contains("guard !isGoogleCalendarOAuthAuthorizationInProgress else"))
        XCTAssertTrue(appSource.contains("func invalidateGoogleCalendarListOptions()"))
        XCTAssertTrue(appSource.contains("generation == googleCalendarListLoadGeneration"))
        XCTAssertTrue(appSource.contains("invalidateGoogleCalendarListOptions()"))
        XCTAssertTrue(appSource.contains("googleCalendarListProvider.listWritableCalendars()"))
        XCTAssertTrue(appSource.contains("Google Calendar list loaded. Choose a calendar, then save."))
        XCTAssertTrue(appSource.contains("Google Calendar list is not available in this build."))
        XCTAssertTrue(appSource.contains("Reconnect Google Calendar with OAuth before loading calendars."))
        XCTAssertTrue(appSource.contains("Wait for Google Calendar OAuth authorization to finish before loading calendars."))
        XCTAssertTrue(appSource.contains("Connect with OAuth authorization"))
        XCTAssertTrue(syncSource.contains("Button(localizedSettingsDisplay(context.googleCalendarOAuthActionLabel))"))
        XCTAssertTrue(syncSource.contains("context.startGoogleCalendarOAuthAuthorization()"))
        XCTAssertTrue(appSource.contains("context.isConfirmingGoogleCalendarOAuthDisconnect = true"))
        XCTAssertTrue(appSource.contains("disconnectGoogleCalendarOAuthAuthorization()"))
        XCTAssertTrue(appSource.contains("settings-google-calendar-oauth-disconnect-confirm"))
        XCTAssertTrue(appSource.contains("This removes local Google Calendar OAuth tokens from Keychain. Tasks and saved calendar ID stay unchanged."))
        XCTAssertTrue(syncSource.contains("settings-google-calendar-oauth-disconnect"))
        XCTAssertTrue(syncSource.contains("role: .destructive"))
        XCTAssertLessThan(
            try XCTUnwrap(controlsSource.range(of: "settings-google-calendar-id-save")).lowerBound,
            try XCTUnwrap(controlsSource.range(of: "settings-google-calendar-list-load")).lowerBound
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
        XCTAssertTrue(appSource.contains("SUISUI_GOOGLE_CALENDAR_OAUTH_CLIENT_ID"))
        XCTAssertTrue(appSource.contains("SuisuiGoogleCalendarOAuthClientID"))
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
        let syncStart = try XCTUnwrap(appSource.range(of: "struct SettingsSyncFeatureView: View"))
        let privacyStart = try XCTUnwrap(appSource.range(of: "struct SettingsPrivacyFeatureView: View"))
        let syncSource = String(appSource[syncStart.lowerBound..<privacyStart.lowerBound])

        XCTAssertTrue(appSource.contains("SyncValueStatusRow("))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"sync-paid-value-row\")"))
        XCTAssertTrue(appSource.contains("var syncPaidValueLabel: String"))
        XCTAssertTrue(appSource.contains("var syncSafetyBoundaryLabel: String"))
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
        let syncStart = try XCTUnwrap(appSource.range(of: "struct SettingsSyncFeatureView: View"))
        let privacyStart = try XCTUnwrap(appSource.range(of: "struct SettingsPrivacyFeatureView: View"))
        let syncSource = String(appSource[syncStart.lowerBound..<privacyStart.lowerBound])

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
        XCTAssertFalse(appSource.contains("import SuisuiExternalConnectors"))
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

        XCTAssertTrue(appSource.contains("import SuisuiGoogleCalendarRuntime"))
        XCTAssertTrue(appSource.contains("static func makeEntitlementStore(secretStore: any SecretStore) -> KeychainEntitlementStore"))
        XCTAssertTrue(appSource.contains("static func makeLocalLicenseVerifier() -> any LocalLicenseVerifier"))
        XCTAssertTrue(appSource.contains("SuisuiLocalLicensePublicKey"))
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

    func testPublicAlphaGoogleCalendarCompositionFailsClosedAcrossEveryRuntimeEntryPoint() throws {
        let appSource = try readAppShellSource()
        let composition = try readPackageFile(
            "Sources/SuisuiApp/Composition/GoogleCalendarRuntimeCompositionFactory.swift"
        )
        let boardComposition = try readPackageFile(
            "Sources/SuisuiApp/Composition/ProjectBoardRuntimeFactory.swift"
        )

        XCTAssertTrue(composition.contains("SuisuiRuntimePolicy"))
        XCTAssertTrue(composition.contains("GoogleCalendarRuntimeBuildPolicy"))
        XCTAssertTrue(composition.contains("SUISUI_ENABLE_EXPERIMENTAL_GOOGLE_CALENDAR_RUNTIME"))
        XCTAssertTrue(composition.contains("?? .publicAlpha"))
        XCTAssertGreaterThanOrEqual(
            composition.components(separatedBy: "guard isGoogleCalendarRuntimeEnabled() else").count - 1,
            6
        )
        XCTAssertTrue(composition.contains("DisabledGoogleCalendarRuntimeSync"))
        XCTAssertTrue(composition.contains("throw GoogleCalendarRuntimeSyncError.notReady(.runtimeNotConfigured)"))
        XCTAssertTrue(boardComposition.contains("guard isGoogleCalendarRuntimeEnabled() else"))
        XCTAssertTrue(appSource.contains("isGoogleCalendarRuntimeEnabled: AppRuntimeFactory.isGoogleCalendarRuntimeEnabled()"))
        XCTAssertTrue(appSource.contains("if context.isGoogleCalendarRuntimeEnabled"))
    }

    func testProjectBoardGoogleCalendarSyncMenuUsesRuntimeReadinessInsteadOfHardcodedDisabled() throws {
        let boardSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardView.swift")
        let toolbarSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardToolbarContent.swift")
        let menuStart = try XCTUnwrap(toolbarSource.range(of: "Button(action: onRequestGoogleCalendarSync)"))
        let menuEnd = try XCTUnwrap(toolbarSource.range(of: "if context.showsAutomation", range: menuStart.lowerBound..<toolbarSource.endIndex))
        let googleCalendarMenuSource = String(toolbarSource[menuStart.lowerBound..<menuEnd.lowerBound])

        XCTAssertTrue(boardSource.contains("@State private var isGoogleCalendarSyncApprovalPresented = false"))
        XCTAssertTrue(boardSource.contains("onRequestGoogleCalendarSync: { isGoogleCalendarSyncApprovalPresented = true }"))
        XCTAssertTrue(googleCalendarMenuSource.contains(".disabled(!canSyncGoogleCalendar)"))
        XCTAssertTrue(googleCalendarMenuSource.contains(".help(googleCalendarSyncHelp)"))
        XCTAssertFalse(googleCalendarMenuSource.contains(".disabled(true)"))
        XCTAssertFalse(boardSource.contains("syncDueTasksToGoogleCalendar(approvalToken: nil)"))
        XCTAssertFalse(boardSource.contains("ProjectBoardIntegrationUnavailableError.googleCalendarOAuthNotConfigured"))
    }

    func testProjectBoardGoogleCalendarSyncRequiresDialogApprovalToken() throws {
        let boardSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardView.swift")
        let dialogStart = try XCTUnwrap(boardSource.range(of: ".confirmationDialog(\n                \"Sync due tasks to Google Calendar?\""))
        let dialogEnd = try XCTUnwrap(boardSource.range(of: "private var projectBoardLifecycleChrome", range: dialogStart.lowerBound..<boardSource.endIndex))
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
        let mcpSource = try readPackageFile("Sources/SuisuiCore/ExternalMCP/MCPRegistration.swift")
        let audit = try readPackageFile("docs/ux/click-path-audit.md")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")

        XCTAssertTrue(appSource.contains("MCPServerSettingsRow("))
        XCTAssertTrue(appSource.contains("if case .loaded(let loadedExternalMCPViewModel) = context.loadState"))
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
        let executionSource = try readPackageFile("Sources/SuisuiCore/ExternalMCP/MCPExecution.swift")
        let audit = try readPackageFile("docs/ux/click-path-audit.md")
        let investorReview = try readPackageFile("docs/product/investor-review.md")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")
        let mcpStart = try XCTUnwrap(appSource.range(of: "struct SettingsMCPFeatureView: View"))
        let dependenciesStart = try XCTUnwrap(appSource.range(of: "struct SettingsOverviewDependencies"))
        let mcpTabSource = String(appSource[mcpStart.lowerBound..<dependenciesStart.lowerBound])

        XCTAssertTrue(appSource.contains("MCPPaidExecutionBoundaryRow("))
        XCTAssertTrue(appSource.contains(".accessibilityIdentifier(\"mcp-paid-execution-boundary-row\")"))
        XCTAssertTrue(appSource.contains("let mcpExecutionValueLabel: String"))
        XCTAssertTrue(appSource.contains("let mcpExecutionSafetyBoundaryLabel: String"))
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
        XCTAssertTrue(audit.contains("Hosted Light/Dark/Systemスクリーンショットで、選択カードを含めtitle、状態、優先度、期限、drag affordanceが欠落・重複しないことを確認する"))
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
        XCTAssertTrue(audit.contains("Sources/SuisuiApp/Views/ProjectBoardView.swift"))
        XCTAssertTrue(audit.contains("Sources/SuisuiApp/Views/ProjectWorkflowInboxView.swift"))
        XCTAssertTrue(audit.contains("Sources/SuisuiApp/Views/ProjectWorkflowTodayView.swift"))
        XCTAssertTrue(audit.contains("Sources/SuisuiApp/SuisuiApp.swift"))
        XCTAssertTrue(audit.contains("Tests/SuisuiCoreTests/ProjectBoardStoreTests.swift"))
        XCTAssertTrue(audit.contains("Tests/SuisuiCoreTests/ExternalMCPTests.swift"))
        XCTAssertTrue(audit.contains("Tests/SuisuiCoreTests/SyncEntitlementTests.swift"))
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
        let seederSource = try readPackageFile("Sources/SuisuiVisualFixtureSeeder/main.swift")
        let windowMetadataScript = try readPackageFile("script/ui_evidence_window_metadata.swift")
        let contentCheckScript = try readPackageFile("script/ui_evidence_content_check.swift")
        let boardSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardView.swift")
        let persistenceSource = try readPackageFile("Sources/SuisuiCore/App/ProjectBoardSelectionPersistence.swift")
        let evidence = try readPackageFile("docs/release/evidence/ui-screenshots.md")
        let audit = try readPackageFile("docs/ux/click-path-audit.md")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")

        XCTAssertTrue(script.contains("script/build_and_run.sh\" --build-only"))
        XCTAssertTrue(script.contains("CFFIXED_USER_HOME"))
        XCTAssertTrue(script.contains("SUISUI_UI_EVIDENCE_HOME"))
        XCTAssertTrue(script.contains("SUISUI_UI_EVIDENCE_TMPDIR"))
        XCTAssertTrue(script.contains("SUISUI_DATABASE_PATH=$DATABASE_PATH"))
        XCTAssertTrue(script.contains("SUISUI_DISABLE_KEYCHAIN_SECRET_STORE=1"))
        XCTAssertFalse(script.contains("SUISUI_FORCE_PROJECT_BOARD_FALLBACK"))
        XCTAssertFalse(script.contains("SUISUI_LAUNCH_RECOVERY_MODE"))
        XCTAssertTrue(script.contains("normal `ProjectBoardView` route"))
        XCTAssertTrue(script.contains("suisui.appearancePreference"))
        XCTAssertTrue(script.contains("ui_evidence_window_metadata.swift"))
        XCTAssertTrue(windowMetadataScript.contains("CGWindowListCopyWindowInfo"))
        XCTAssertTrue(script.contains("wait_for_window_capture_metadata"))
        XCTAssertTrue(script.contains("position_window_for_capture"))
        XCTAssertTrue(script.contains("AX_RESIZE_WINDOW_HELPER_BINARY"))
        XCTAssertTrue(script.contains("read -r _ _ observed_width observed_height <<<\"$ax_window_size\""))
        XCTAssertTrue(script.contains("POSITIONED_WINDOW_WIDTH=\"$observed_width\""))
        XCTAssertTrue(script.contains("successful_window_width=\"$POSITIONED_WINDOW_WIDTH\""))
        XCTAssertTrue(script.contains("Avoid LaunchServices activation"))
        XCTAssertTrue(script.contains("tell application \"System Events\""))
        XCTAssertFalse(script.contains(#"tell application \"$APP_NAME\" to activate"#))
        XCTAssertTrue(script.contains("screencapture -x -o -l"))
        XCTAssertFalse(script.contains("screencapture -x -l"))
        let captureStart = try XCTUnwrap(script.range(of: "capture_visible_window() {"))
        let captureEnd = try XCTUnwrap(
            script.range(of: "\nopen_mcp_settings_tab() {", range: captureStart.upperBound..<script.endIndex)
        )
        let captureFunction = script[captureStart.lowerBound..<captureEnd.lowerBound]
        XCTAssertFalse(captureFunction.contains("screencapture -x -R"))
        XCTAssertTrue(script.contains("if [[ \"$bytes\" -lt 30000 ]]"))
        XCTAssertFalse(script.contains("if [[ \"$bytes\" -lt 50000 ]]"))
        XCTAssertTrue(script.contains("local capture_attempts=3"))
        XCTAssertTrue(script.contains("for ((capture_attempt = 1; capture_attempt <= capture_attempts; capture_attempt++))"))
        XCTAssertTrue(script.contains("local deadline=$((SECONDS + TARGET_TIMEOUT_SECONDS))"))
        XCTAssertTrue(script.contains("while true; do"))
        XCTAssertTrue(script.contains("\"$window_x\" \"$window_y\" \"$window_width\" \"$window_height\""))
        XCTAssertFalse(script.contains("if ! wait_for_owned_evidence_window \"$window_name\" \"$diagnostic_file\"; then"))
        XCTAssertTrue(script.contains("wait_for_window_capture_metadata \"$window_name\""))
        XCTAssertTrue(script.contains("if [[ \"$SECONDS\" -ge \"$deadline\" ]]; then"))
        XCTAssertTrue(script.contains("INFO: waiting for recreated owned evidence window before positioning"))
        XCTAssertTrue(script.contains("SUISUI_VISUAL_EVIDENCE_SYSTEM_APPEARANCE=dark"))
        XCTAssertTrue(script.contains("ui_evidence_appearance_check.swift"))
        XCTAssertTrue(script.contains("VISUAL_APPEARANCE_CHECKER"))
        XCTAssertFalse(script.contains("-AppleInterfaceStyle"))
        XCTAssertTrue(script.contains(#""-AppleShowScrollBars" "Always""#))
        XCTAssertTrue(script.contains("most constrained persistent-scrollbar setting"))
        XCTAssertTrue(script.contains("assert_screenshot_has_visible_content"))
        XCTAssertTrue(script.contains("ui_evidence_content_check.swift"))
        XCTAssertTrue(script.contains("ui_evidence_source_commit()"))
        XCTAssertTrue(script.contains("SUISUI_VISUAL_SOURCE_REF"))
        XCTAssertTrue(script.contains("git -C \"$ROOT_DIR\" log -1 --format=%H \"$source_ref\""))
        XCTAssertTrue(script.contains("- Source commit: `%s`"))
        XCTAssertTrue(contentCheckScript.contains("CGImageSourceCreateWithURL"))
        XCTAssertTrue(contentCheckScript.contains("Screenshot appears blank or too low contrast"))
        XCTAssertTrue(contentCheckScript.contains("opaqueBlackPixelCount"))
        XCTAssertTrue(contentCheckScript.contains("transparentPixelCount"))
        XCTAssertTrue(contentCheckScript.contains("luminanceVariance"))
        XCTAssertTrue(contentCheckScript.contains("uniformly composed without visible UI variance"))
        XCTAssertTrue(contentCheckScript.contains("sourceImage.cropping(to: boundedRegion)"))
        XCTAssertTrue(contentCheckScript.contains("Screenshot contains large opaque-black regions"))
        XCTAssertTrue(contentCheckScript.contains("Screenshot contains large transparent regions"))
        XCTAssertFalse(script.contains("sqlite3"))
        XCTAssertTrue(script.contains("seed_capture_database"))
        XCTAssertTrue(script.contains("--capture-reference-instant"))
        XCTAssertTrue(seederSource.contains("Launch Readiness"))
        XCTAssertTrue(seederSource.contains("Local Filesystem MCP"))
        XCTAssertTrue(seederSource.contains("Issue Tracker MCP"))
        XCTAssertTrue(seederSource.contains("mcp_server_registrations"))
        XCTAssertTrue(script.contains("persist_project_board_selection"))
        XCTAssertTrue(script.contains("write_app_preference"))
        XCTAssertTrue(script.contains("HOME=\"$EVIDENCE_HOME\""))
        XCTAssertTrue(script.contains("/usr/bin/env -i PATH=\"$PATH\" TMPDIR=\"$EVIDENCE_TMPDIR\" \"${env_args[@]}\""))
        XCTAssertTrue(script.contains("Direct launch preserves the isolated database"))
        XCTAssertFalse(script.contains("open_args+=(--env \"$env_arg\")"))
        XCTAssertFalse(script.contains("/usr/bin/open \"${open_args[@]}\""))
        XCTAssertTrue(script.contains("/usr/bin/defaults write \"$BUNDLE_IDENTIFIER\""))
        XCTAssertTrue(script.contains("suisui.projectBoard.selectedDestination"))
        XCTAssertTrue(script.contains("SUISUI_PROJECT_BOARD_SELECTED_DESTINATION=$PROJECT_BOARD_SELECTION_OVERRIDE"))
        XCTAssertTrue(script.contains("SUISUI_PROJECT_BOARD_SELECTED_TASK_ID=$PROJECT_BOARD_SELECTED_TASK_OVERRIDE"))
        XCTAssertTrue(script.contains("SUISUI_APPEARANCE_PREFERENCE=$APPEARANCE_OVERRIDE"))
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
        XCTAssertTrue(script.contains("schedule-mode-overview=>"))
        XCTAssertTrue(script.contains("SCHEDULE_COCKPIT_TARGET_MARKERS=\"schedule-workflow=>$SCHEDULE_ROUTE_LABEL|schedule-mode-overview=>|schedule-mini-calendar=>\""))
        XCTAssertTrue(script.contains("SCHEDULE_MODE_OVERRIDE=\"$schedule_mode_override\""))
        XCTAssertTrue(script.contains("SUISUI_VISUAL_EVIDENCE_SCHEDULE_MODE=$SCHEDULE_MODE_OVERRIDE"))
        XCTAssertTrue(script.contains("SCHEDULE_WORKLOAD_TARGET_MARKERS=\"schedule-workflow=>$SCHEDULE_ROUTE_LABEL|schedule-mode-workload=>|schedule-mini-calendar=>\""))
        XCTAssertTrue(script.contains("SCHEDULE_WORKLOAD_DETAIL_MARKERS=\"schedule-workload-attention-banner=>|schedule-workload-day-detail=>\""))
        XCTAssertTrue(script.contains("\"\" \"schedule-workload-attention-banner\" \"$SCHEDULE_WORKLOAD_DETAIL_MARKERS\" workload"))
        XCTAssertFalse(script.contains("\"schedule-workload-day-detail\" \"schedule-workload-attention-banner\""))
        XCTAssertTrue(script.contains("fi\n  if [[ -n \"$scroll_target_identifier\" ]]"))
        XCTAssertTrue(script.contains("ui_evidence_ax_scroll_container.swift"))
        XCTAssertTrue(script.contains("capture_project_board_destination light schedule \"$SCHEDULE_LIGHT_SCREENSHOT\" \"Schedule cockpit\" \"$SCHEDULE_COCKPIT_TARGET_MARKERS\""))
        XCTAssertTrue(script.contains("capture_project_board_destination dark schedule \"$SCHEDULE_DARK_SCREENSHOT\" \"Schedule cockpit\" \"$SCHEDULE_COCKPIT_TARGET_MARKERS\""))
        XCTAssertTrue(script.contains("if [[ \"$SCHEDULE_COCKPIT\" == \"1\" ]]"))
        XCTAssertTrue(script.contains(#""-ApplePersistenceIgnoreState" "YES""#))
        XCTAssertTrue(script.contains(#""-AppleLanguages" "$APPLE_LANGUAGES""#))
        XCTAssertTrue(script.contains(#""-AppleLocale" "$APPLE_LOCALE""#))
        XCTAssertFalse(script.contains("if [[ \"$SCHEDULE_COCKPIT\" != \"1\" ]]"))
        XCTAssertTrue(script.contains("open_settings_overview_tab"))
        XCTAssertTrue(script.contains("capture_settings_overview"))
        XCTAssertTrue(script.contains("open_settings_appearance_tab"))
        XCTAssertTrue(script.contains("capture_settings_appearance"))
        XCTAssertTrue(script.contains("capture_settings_ai light \"$SETTINGS_AI_LIGHT_SCREENSHOT\""))
        XCTAssertTrue(script.contains("settings-ai-readiness-rail"))
        XCTAssertTrue(script.contains("settings-overview-detail-rail=>"))
        XCTAssertTrue(script.contains("SETTINGS_TAB_OVERRIDE=\"AI\""))
        XCTAssertTrue(script.contains("capture_settings_privacy"))
        XCTAssertTrue(script.contains("SETTINGS_TAB_OVERRIDE=\"Privacy\""))
        XCTAssertTrue(script.contains("settings-privacy-root"))
        XCTAssertTrue(script.contains("capture_voice_conversation_appearance"))
        XCTAssertTrue(script.contains("VOICE_SURFACE_OVERRIDE=\"conversation\""))
        XCTAssertTrue(script.contains("voice-conversation-workspace"))
        XCTAssertTrue(script.contains("open_mcp_settings_tab"))
        XCTAssertTrue(script.contains("capture_mcp_settings_appearance"))
        XCTAssertTrue(script.contains("SUISUI_SETTINGS_EVIDENCE_TAB=$SETTINGS_TAB_OVERRIDE"))
        XCTAssertTrue(script.contains("docs/release/evidence/ui-screenshots"))
        XCTAssertTrue(script.contains("Screen Recording permission"))
        XCTAssertFalse(script.contains("OpenAI API Key"))
        XCTAssertFalse(script.contains("sk-proj-"))
        XCTAssertFalse(script.contains("sk-live-"))

        XCTAssertTrue(boardSource.contains("@AppStorage(ProjectBoardSelectionPersistence.storageKey)"))
        XCTAssertTrue(boardSource.contains("restoreSelectedDestinationIfNeeded()"))
        XCTAssertTrue(boardSource.contains("persistSelectedDestination(_ destination: ProjectBoardSidebarDestination?)"))
        XCTAssertTrue(persistenceSource.contains("public enum ProjectBoardSelectionPersistence"))
        XCTAssertTrue(persistenceSource.contains("static let storageKey = \"suisui.projectBoard.selectedDestination\""))
        XCTAssertTrue(persistenceSource.contains("static let environmentOverrideKey = \"SUISUI_PROJECT_BOARD_SELECTED_DESTINATION\""))
        XCTAssertTrue(persistenceSource.contains("public enum ProjectBoardTaskSelectionPersistence"))
        XCTAssertTrue(persistenceSource.contains("static let environmentOverrideKey = \"SUISUI_PROJECT_BOARD_SELECTED_TASK_ID\""))
        XCTAssertTrue(boardSource.contains("ProjectBoardSelectionPersistence.environmentOverrideRawValue"))
        XCTAssertTrue(boardSource.contains("applySelectedTaskOverrideIfNeeded()"))
        let destinationChangeStart = try XCTUnwrap(boardSource.range(of: ".onChange(of: selectedDestination)"))
        let destinationChangeEnd = try XCTUnwrap(boardSource.range(
            of: "private var projectBoardToolbarChrome",
            range: destinationChangeStart.upperBound..<boardSource.endIndex
        ))
        let destinationChangeSource = String(boardSource[destinationChangeStart.lowerBound..<destinationChangeEnd.lowerBound])
        let destinationApply = try XCTUnwrap(destinationChangeSource.range(of: "applySelectedDestination("))
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
        XCTAssertTrue(script.contains("SUISUI_UI_EVIDENCE_TARGET_TIMEOUT_SECONDS"))
        XCTAssertTrue(script.contains("ui_evidence_ax_marker_check.swift"))
        XCTAssertTrue(script.contains("AX_MARKER_CHECKER="))
        XCTAssertTrue(script.contains("/usr/bin/swiftc \"$ROOT_DIR/script/ui_evidence_ax_marker_check.swift\" -o \"$AX_MARKER_CHECKER\""))
        XCTAssertTrue(script.contains("\"$AX_MARKER_CHECKER\" \"$APP_NAME\" \"$identifier\" \"$text\" \"$EVIDENCE_APP_PID\""))
        XCTAssertTrue(script.contains("kill -9 \"$checker_pid\""))
        XCTAssertFalse(script.contains("/usr/bin/swift \"$ROOT_DIR/script/ui_evidence_ax_marker_check.swift\""))
        XCTAssertFalse(script.contains("watchdog_pid"))
        XCTAssertTrue(script.contains("SUISUI_UI_EVIDENCE_AX_MAX_NODES"))
        XCTAssertTrue(script.contains("AX marker scans use a bounded Swift AX traversal"))
        XCTAssertTrue(axMarkerScript.contains("AXUIElementCreateApplication"))
        XCTAssertTrue(axMarkerScript.contains("AXUIElementSetMessagingTimeout"))
        XCTAssertTrue(axMarkerScript.contains("SUISUI_UI_EVIDENCE_AX_MAX_NODES"))
        XCTAssertTrue(axMarkerScript.contains(#""AXIdentifier""#))
        XCTAssertTrue(axMarkerScript.contains(#""AXVisibleChildren""#))
        XCTAssertTrue(axMarkerScript.contains(#""AXContents""#))
        XCTAssertTrue(axMarkerScript.contains("missing AX identifier marker"))
        XCTAssertTrue(script.contains("project-board-detail=>Launch Readiness"))
        XCTAssertTrue(script.contains("today-workflow=>$TODAY_ROUTE_LABEL"))
        XCTAssertTrue(script.contains("today-assistant-rail=>$TODAY_ROUTE_LABEL"))
        XCTAssertTrue(script.contains("schedule-workflow=>$SCHEDULE_ROUTE_LABEL"))
        XCTAssertTrue(script.contains("SCHEDULE_COCKPIT_TARGET_MARKERS"))
        XCTAssertTrue(script.contains("done-workflow=>$DONE_ROUTE_LABEL"))
        XCTAssertTrue(script.contains("VOICE_COMMAND_TARGET_MARKERS"))
        XCTAssertTrue(script.contains("voice-command-root=>$VOICE_COMMAND_LABEL"))
        XCTAssertTrue(script.contains("capture_project_board_destination light \"$PROJECT_BOARD_SELECTION_OVERRIDE\" \"$LIGHT_SCREENSHOT\" \"Project Board\" \"$PROJECT_BOARD_TARGET_MARKERS\""))
        XCTAssertTrue(script.contains("capture_project_board_destination light today \"$TODAY_LIGHT_SCREENSHOT\" \"Today\" \"$TODAY_TARGET_MARKERS\""))
        XCTAssertTrue(script.contains("capture_project_board_destination light schedule \"$SCHEDULE_LIGHT_SCREENSHOT\" \"Schedule cockpit\" \"$SCHEDULE_COCKPIT_TARGET_MARKERS\""))
        XCTAssertTrue(script.contains("capture_project_board_destination light schedule \"$SCHEDULE_LIGHT_SCREENSHOT\" \"Schedule cockpit\" \"$SCHEDULE_TARGET_MARKERS\""))
        XCTAssertTrue(script.contains("capture_project_board_destination light done \"$DONE_LIGHT_SCREENSHOT\" \"Done analytics\" \"$DONE_TARGET_MARKERS\""))
        XCTAssertTrue(script.contains("--done-analytics"))
        XCTAssertTrue(script.contains("DONE_ANALYTICS_TARGET_MARKERS"))
        XCTAssertFalse(script.contains("SUISUI_UI_EVIDENCE_RECOVERY_MODE"))
        XCTAssertFalse(script.contains("SUISUI_LAUNCH_RECOVERY_MODE"))
        XCTAssertTrue(script.contains("write_done_analytics_evidence_file"))
        XCTAssertTrue(script.contains("docs/release/evidence/done-analytics-screenshots.md"))
        XCTAssertTrue(script.contains("INBOX_VOICE_TITLE=\"Create tomorrow's presentation materials\""))
        XCTAssertTrue(script.contains("INBOX_VOICE_TITLE=\"明日のプレゼン資料を作成する\""))
        XCTAssertTrue(script.contains("HOME=\"$EVIDENCE_HOME\" CFFIXED_USER_HOME=\"$EVIDENCE_HOME\""))
        XCTAssertTrue(script.contains("inbox-voice-intake-detail=>Voice intake detail for $INBOX_VOICE_TITLE"))
        XCTAssertTrue(script.contains("capture_project_board_destination light inbox \"$INBOX_VOICE_LIGHT_SCREENSHOT\" \"Inbox voice detail\" \"$INBOX_VOICE_ROUTE_MARKERS\" \"$INBOX_VOICE_TASK_OVERRIDE\" \"inbox-voice-intake-detail\" \"inbox-voice-intake-detail\" \"$INBOX_VOICE_TARGET_MARKERS\""))
        XCTAssertTrue(script.contains("capture_voice_command_appearance light \"$VOICE_COMMAND_LIGHT_SCREENSHOT\""))
        XCTAssertTrue(script.contains("capture_voice_command_listening_appearance light \"$VOICE_COMMAND_LISTENING_LIGHT_SCREENSHOT\""))
        XCTAssertTrue(script.contains("SUISUI_VISUAL_EVIDENCE_VOICE_SURFACE=$VOICE_SURFACE_OVERRIDE"))
        XCTAssertTrue(script.contains("voice-command-listening-hero"))
        let captureDestinationStart = try XCTUnwrap(script.range(of: "capture_project_board_destination()"))
        let captureDestinationEnd = try XCTUnwrap(script.range(
            of: "capture_voice_command_appearance()",
            range: captureDestinationStart.upperBound..<script.endIndex
        ))
        let captureDestinationSource = String(script[captureDestinationStart.lowerBound..<captureDestinationEnd.lowerBound])
        XCTAssertTrue(captureDestinationSource.contains("launch_destination=\"$selected_destination\""))
        XCTAssertFalse(script.contains("press_project_sidebar_row"))
        XCTAssertFalse(script.contains("project-sidebar-row-$project_id"))
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

    func testUIScreenshotCaptureTerminatesOnlyTheOwnedSuisuiProcessBeforeRelaunching() throws {
        let script = try readPackageFile("script/capture_ui_evidence.sh")

        XCTAssertTrue(script.contains("PROJECT_BOARD_SELECTED_TASK_OVERRIDE=\"\""))
        XCTAssertTrue(script.contains("wait_for_app_process_exit"))
        XCTAssertTrue(script.contains("stop_evidence_app"))
        XCTAssertTrue(script.contains("EVIDENCE_APP_IDENTITY"))
        XCTAssertTrue(script.contains("EVIDENCE_APP_LAUNCH_IDENTITY"))
        XCTAssertTrue(script.contains("EVIDENCE_APP_LOG"))
        XCTAssertTrue(script.contains("emit_evidence_app_diagnostic"))
        XCTAssertTrue(script.contains("visual-launch-identity-unavailable"))
        XCTAssertTrue(script.contains("ax_wait_for_owned_process_identity \"$EVIDENCE_APP_LAUNCH_PID\" \"$APP_BINARY\" \"$TARGET_TIMEOUT_SECONDS\""))
        XCTAssertTrue(script.contains("ax_terminate_owned_process \"$owned_pid\" \"$APP_BINARY\" \"${EVIDENCE_APP_IDENTITY:-}\""))
        XCTAssertTrue(script.contains("ax_terminate_owned_process \"$launch_pid\" \"$APP_BINARY\" \"${EVIDENCE_APP_LAUNCH_IDENTITY:-}\""))
        XCTAssertFalse(script.contains("kill \"$EVIDENCE_APP_PID\""))
        XCTAssertTrue(script.contains("ax_wait_for_owned_app_pid \"$EVIDENCE_APP_PID\" \"$APP_BINARY\""))
        XCTAssertTrue(script.contains("visual-owned-pid-unavailable"))
    }

    func testUIScreenshotCaptureRetriesNamedWindowReadinessAfterMarkerValidation() throws {
        let script = try readPackageFile("script/capture_ui_evidence.sh")
        let helperStart = try XCTUnwrap(script.range(of: "prepare_named_evidence_window()"))
        let helperEnd = try XCTUnwrap(
            script.range(
                of: "\ncapture_settings_overview()",
                range: helperStart.upperBound..<script.endIndex
            )
        )
        let helper = String(script[helperStart.lowerBound..<helperEnd.lowerBound])

        XCTAssertTrue(helper.contains("for ((window_attempt = 1; window_attempt <= EVIDENCE_ROUTE_ATTEMPTS; window_attempt++))"))
        XCTAssertTrue(helper.contains("wait_for_window_capture_metadata \"$window_name\""))
        XCTAssertTrue(helper.contains("wait_for_project_board_destination \"$label\" \"$marker_spec\""))
        XCTAssertEqual(
            helper.components(separatedBy: "position_window_for_capture \"$window_name\"").count - 1,
            2,
            "named evidence windows must be reacquired after marker traversal before capture"
        )
        XCTAssertTrue(helper.contains("retrying named evidence window after readiness failure"))
        XCTAssertTrue(script.contains(
            "prepare_named_evidence_window \"\" \"Voice Command\" \"$VOICE_COMMAND_TARGET_MARKERS\""
        ))
        XCTAssertTrue(script.contains(
            "prepare_named_evidence_window \"\" \"Settings appearance\" \"settings-theme-picker=>\""
        ))
    }

    func testPhase12UIScreenshotEvidenceCoversNewCockpitScreens() throws {
        let script = try readPackageFile("script/capture_ui_evidence.sh")
        let seederSource = try readPackageFile("Sources/SuisuiVisualFixtureSeeder/main.swift")
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
        XCTAssertTrue(script.contains("EVIDENCE_REFERENCE_INSTANT"))
        XCTAssertTrue(seederSource.contains("\"Review VoiceOver focus path\""))
        XCTAssertTrue(seederSource.contains("\"in_progress\""))
        XCTAssertTrue(seederSource.contains("Confirm project board to task card to inspector path before public alpha."))
        XCTAssertTrue(seederSource.contains("'Inbox', 'active'"))
        XCTAssertTrue(seederSource.contains("title: \"Inbox\""))
        XCTAssertTrue(workflowSource.contains("synchronizeSelection(with: tasks.map(\\.id))"))
        XCTAssertTrue(workflowSource.contains(
            ".onChange(of: tasks.map(\\.id)) { _, visibleTaskIDs in"
        ))
        XCTAssertTrue(workflowSource.contains("synchronizeSelection(with: visibleTaskIDs)"))

        XCTAssertTrue(script.contains("capture_project_board_destination"))
        XCTAssertTrue(script.contains("SUISUI_OPEN_SETTINGS_ON_LAUNCH=1"))
        XCTAssertTrue(script.contains("SETTINGS_TAB_OVERRIDE=\"Overview\""))
        XCTAssertTrue(script.contains("SETTINGS_TAB_OVERRIDE=\"Appearance\""))
        XCTAssertTrue(script.contains("SETTINGS_TAB_OVERRIDE=\"MCP\""))
        XCTAssertTrue(appSource.contains("SUISUI_OPEN_SETTINGS_ON_LAUNCH"))
        XCTAssertTrue(appSource.contains("SUISUI_SETTINGS_EVIDENCE_TAB"))
        XCTAssertFalse(appSource.contains("settingsEvidenceWindow"))
        XCTAssertTrue(appSource.contains("openInAppSettingsForEvidenceIfRequested"))
        XCTAssertTrue(appSource.contains("SettingsView("))
        XCTAssertTrue(script.contains("seed_capture_database"))
        XCTAssertTrue(seederSource.contains("明日のプレゼン資料を作成する"))
        XCTAssertTrue(seederSource.contains("Done analytics sample"))
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

    func testPhase12UICaptureSeederFailsWhenSeedDataIsMissing() throws {
        let script = try readPackageFile("script/capture_ui_evidence.sh")
        let seederSource = try readPackageFile("Sources/SuisuiVisualFixtureSeeder/main.swift")

        XCTAssertTrue(script.contains("seed_capture_database \"$DATABASE_PATH\""))
        XCTAssertTrue(seederSource.contains("missing Phase 12 UI evidence seed"))
        XCTAssertTrue(seederSource.contains("\"明日のプレゼン資料を作成する\""))
        XCTAssertTrue(seederSource.contains("\"Done analytics sample\""))
        XCTAssertTrue(seederSource.contains("\"Completed Evidence Project\""))
        XCTAssertTrue(seederSource.contains("\"Inbox\""))
        XCTAssertTrue(seederSource.contains("SELECT COUNT(*) FROM tasks"))
        XCTAssertTrue(seederSource.contains("SELECT COUNT(*) FROM projects"))
    }

    func testPhase12UICaptureSeedUsesPersistedTaskStatusContract() throws {
        let script = try readPackageFile("script/capture_ui_evidence.sh")
        let seederSource = try readPackageFile("Sources/SuisuiVisualFixtureSeeder/main.swift")

        XCTAssertTrue(script.contains("seed_capture_database \"$DATABASE_PATH\""))
        XCTAssertTrue(seederSource.contains("unsupported Phase 12 UI evidence task status"))
        XCTAssertTrue(seederSource.contains("status NOT IN ('open', 'backlog', 'planned', 'in_progress', 'blocked', 'completed')"))
        XCTAssertTrue(seederSource.contains("\"Done analytics sample\""))
        XCTAssertTrue(seederSource.contains("\"completed\""))
        XCTAssertFalse(seederSource.contains("\"Done analytics sample\",\n                \"done\""))
    }

    func testUIScreenshotCaptureFailureExplainsScreenRecordingAndWindowDiagnostics() throws {
        let script = try readPackageFile("script/capture_ui_evidence.sh")
        let evidence = try readPackageFile("docs/release/evidence/ui-screenshots.md")
        let phase = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")

        XCTAssertTrue(script.contains("print_capture_failure_guidance"))
        XCTAssertTrue(script.contains("selected Suisui window"))
        XCTAssertTrue(script.contains("System Settings > Privacy & Security > Screen Recording / Screen & System Audio Recording"))
        XCTAssertTrue(script.contains("Quit and reopen the terminal or Codex app after granting permission"))
        XCTAssertTrue(script.contains("SUISUI_UI_EVIDENCE_KEEP_HOME=1"))
        XCTAssertTrue(script.contains("--doctor"))
        XCTAssertTrue(script.contains("run_doctor"))
        XCTAssertTrue(script.contains("screen capture preflight"))
        XCTAssertTrue(script.contains("does not write release evidence"))
        XCTAssertTrue(script.contains("EVIDENCE_WINDOW_ATTEMPTS=2"))
        XCTAssertTrue(script.contains("EVIDENCE_ROUTE_ATTEMPTS=2"))
        XCTAssertTrue(script.contains("resolve_evidence_process_and_window"))
        XCTAssertTrue(script.contains("$EVIDENCE_WAIT_FAILURE_CATEGORY\" == \"window"))
        XCTAssertTrue(script.contains("retrying normal UI capture after owned window publication timeout"))
        XCTAssertTrue(script.contains("retrying exact production destination after required marker timeout"))
        XCTAssertTrue(script.contains("EVIDENCE_WAIT_FAILURE_REASON=\"visual-window-unavailable\""))
        XCTAssertTrue(
            script.contains(
                "[[ \"$DRY_RUN\" != \"1\" && \"$DOCTOR\" != \"1\" && \"$SEED_ONLY\" != \"1\" ]]"
            )
        )
        XCTAssertTrue(evidence.contains("System Settings > Privacy & Security > Screen Recording / Screen & System Audio Recording"))
        XCTAssertTrue(evidence.contains("SUISUI_UI_EVIDENCE_KEEP_HOME=1"))
        XCTAssertTrue(evidence.contains("script/capture_ui_evidence.sh --doctor"))
        XCTAssertTrue(phase.contains("[x] `capture_ui_evidence.sh` はScreen Recording権限やwindow capture失敗時に、選択window情報と再実行手順を出す。"))
        XCTAssertTrue(phase.contains("[x] `capture_ui_evidence.sh --doctor` はrelease evidenceを書かずにScreen Recordingの可視ピクセル取得を事前診断する。"))
    }

    func testLLMHTTPErrorMappingDoesNotDropMalformedErrorBodies() throws {
        let llmProviderSource = try readPackageFile("Sources/SuisuiCore/Planning/LLMProvider.swift")
        let responsesSource = try readPackageFile("Sources/SuisuiCore/Planning/OpenAIResponsesProvider.swift")
        let chatSource = try readPackageFile("Sources/SuisuiCore/Planning/ChatCompletionsCompatibleProvider.swift")
        let claudeSource = try readPackageFile("Sources/SuisuiCore/Planning/ClaudeMessagesProvider.swift")
        let geminiSource = try readPackageFile("Sources/SuisuiCore/Planning/GeminiDirectProvider.swift")
        let sttSource = try readPackageFile("Sources/SuisuiCore/Voice/STTProviders.swift")

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
        XCTAssertTrue(phase.contains("[x] 完了条件: Notion的な柔軟さ、Linear的な速度、Todoist的な即時入力のうち、Suisuiに必要な部分だけが実装される。"))
        XCTAssertTrue(phase.contains("[x] 実操作2-4時間で見るべき競合別クリックパス、測定項目、Suisui採用/非採用判断基準を `docs/product/competitor-benchmark.md` に記録する。"))
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

        for region in ["toolbar", "sidebar", "detail", "inspector"] {
            XCTAssertTrue(
                riskMap.contains(region),
                "Risk map must cover Project Board layout stability for \(region)"
            )
        }

        let invariants = [
            "Native toolbar keeps selection details and semantic utility overflow reachable",
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
            riskMap.contains("project-board-integrations-menu"),
            "Risk map must reference the canonical AX identifier for native toolbar"
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
        let boardSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardInspectors.swift")
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

    func testExtractedBoardAndSettingsLeafViewsKeepAccessibilityAndActionClosures() throws {
        let inspectorSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardInspectors.swift")
        let detailSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardDetailViews.swift")
        let settingsSource = try readPackageFile("Sources/SuisuiApp/Views/SettingsFeatureViews.swift")

        XCTAssertTrue(inspectorSource.contains("accessibilityIdentifier(\"project-inspector\")"))
        XCTAssertTrue(inspectorSource.contains("let onClose: () -> Void"))
        XCTAssertTrue(detailSource.contains("@Binding var displayMode: ProjectBoardDisplayMode"))
        XCTAssertTrue(detailSource.contains("var onOpenTaskInspector: (Int64) -> Void"))
        XCTAssertTrue(detailSource.contains("let onOpenProject: (Int64) -> Void"))
        XCTAssertTrue(settingsSource.contains("let onSelect: () -> Void"))
        XCTAssertTrue(settingsSource.contains("let onCheck: () -> Void"))
        XCTAssertFalse(inspectorSource.contains("SQLiteConnection("))
        XCTAssertFalse(detailSource.contains("SQLiteConnection("))
        XCTAssertFalse(settingsSource.contains("SQLiteConnection("))
    }

    func testOnboardingRerunCoordinatorOwnsSingleWindowPresentation() throws {
        let appSource = try readAppShellSource()
        let coreSource = try readPackageFile("Sources/SuisuiCore/App/FirstRunOnboarding.swift")
        let settingsSource = try readSettingsSurfaceSources()

        XCTAssertTrue(
            coreSource.contains("public final class OnboardingRerunCoordinator"),
            "OnboardingRerunCoordinator must live in Core so it can be unit-tested"
        )
        XCTAssertTrue(
            coreSource.contains("func register(windowID:") && coreSource.contains("func unregister(windowID:"),
            "OnboardingRerunCoordinator must track registered Project Board windows"
        )
        XCTAssertTrue(
            coreSource.contains("func requestRerun()"),
            "OnboardingRerunCoordinator must expose a single request entry point"
        )
        XCTAssertTrue(
            appSource.contains("OnboardingRerunCoordinator.shared"),
            "SuisuiApp must adopt the shared OnboardingRerunCoordinator"
        )
        XCTAssertTrue(
            appSource.contains("onboardingRerunCoordinator.register(windowID:"),
            "ProjectBoardWindowRootView must register itself with the coordinator"
        )
        XCTAssertTrue(
            appSource.contains("onboardingRerunCoordinator.unregister(windowID:"),
            "ProjectBoardWindowRootView must unregister so a closed window frees the primary slot"
        )
        XCTAssertTrue(
            appSource.contains("isPrimaryOnboardingWindow"),
            "ProjectBoardWindowRootView must track the primary slot to deduplicate sheets"
        )
        XCTAssertFalse(
            appSource.contains("NotificationCenter.default.publisher(for: FirstRunOnboardingGate.rerunNotificationName)"),
            "SuisuiApp must stop broadcasting onboarding rerun through NotificationCenter"
        )
        XCTAssertFalse(
            settingsSource.contains("NotificationCenter.default.post(\n                        name: FirstRunOnboardingGate.rerunNotificationName"),
            "SettingsView must not post the legacy rerun notification"
        )
        XCTAssertTrue(
            settingsSource.contains("dependencies.rerunOnboarding()"),
            "SettingsView must call the injected rerun closure"
        )
        XCTAssertTrue(
            settingsSource.contains("OnboardingRerunCoordinator.shared.requestRerun()"),
            "The in-board Settings workspace must wire the rerun request to the coordinator"
        )
        XCTAssertFalse(
            appSource.contains("SettingsWindowRootView"),
            "Settings must not keep a detached Settings scene root"
        )
    }

    func testOnboardingPermissionSnapshotIncludesMicrophone() throws {
        let factorySource = try readPackageFile("Sources/SuisuiApp/Composition/SettingsRuntimeFactory.swift")
        let adapterSource = try readPackageFile("Sources/SuisuiApp/Adapters/AVFoundationMicrophonePermissionSnapshotReader.swift")
        let welcomeSource = try readPackageFile("Sources/SuisuiApp/Views/OnboardingWelcomeView.swift")
        let appSource = try readAppShellSource()

        XCTAssertTrue(
            adapterSource.contains("AVCaptureDevice.authorizationStatus(for: .audio)"),
            "Microphone adapter must read AVAuthorizationStatus from AVCaptureDevice"
        )
        XCTAssertTrue(
            factorySource.contains("AVFoundationMicrophonePermissionSnapshotReader.snapshot"),
            "Permission snapshot factory must compose the microphone reader"
        )
        XCTAssertTrue(
            welcomeSource.contains("@Sendable () -> PermissionSnapshot"),
            "OnboardingWelcomeView must type the snapshot provider as @Sendable for off-Main reads"
        )
        XCTAssertTrue(
            appSource.contains("permissionSnapshotProvider: AppRuntimeFactory.makeIntegrationPermissionSnapshotSendable"),
            "SuisuiApp must inject the Sendable snapshot factory so off-Main reads are safe"
        )
    }

    func testTodayWeatherAndOnboardingPreferencesRemainLocalAndAccessible() throws {
        let weatherSource = try readPackageFile("Sources/SuisuiCore/App/TodayWeatherSnapshot.swift")
        let weatherModelSource = try readPackageFile("Sources/SuisuiApp/Weather/TodayWeatherModel.swift")
        let weatherPreferenceSource = try readPackageFile("Sources/SuisuiCore/App/WeatherLocationPreference.swift")
        let dashboardSource = try readPackageFile("Sources/SuisuiCore/App/TodayDashboardSnapshot.swift")
        let dashboardViewSource = try readPackageFile("Sources/SuisuiApp/Views/TodayDashboardView.swift")
        let todayWorkflowSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectWorkflowTodayView.swift")
        let localizedDisplaySource = try readPackageFile("Sources/SuisuiApp/LocalizedDisplay.swift")
        let headerSource = try readPackageFile("Sources/SuisuiApp/Views/TodayDashboardHeaderView.swift")
        let onboardingSource = try readPackageFile("Sources/SuisuiApp/Views/OnboardingWelcomeView.swift")
        let settingsSource = try readPackageFile("Sources/SuisuiCore/App/AppSettings.swift")

        XCTAssertTrue(weatherSource.contains("case notConfigured"))
        XCTAssertTrue(weatherSource.contains("case permissionPending"))
        XCTAssertTrue(weatherSource.contains("case permissionDenied"))
        XCTAssertTrue(weatherSource.contains("case loading"))
        XCTAssertTrue(weatherSource.contains("case available"))
        XCTAssertTrue(weatherSource.contains("case availableDetails"))
        XCTAssertTrue(weatherSource.contains("case failed"))
        XCTAssertFalse(weatherSource.contains("URLSession"))
        XCTAssertFalse(weatherSource.contains("weather provider in Settings"))
        XCTAssertTrue(weatherModelSource.contains("WeatherKitTodayProvider"))
        XCTAssertTrue(weatherModelSource.contains("CoreLocationTodayProvider"))
        XCTAssertTrue(weatherModelSource.contains("requestAuthorization()"))
        XCTAssertTrue(weatherModelSource.contains("locations.last"))
        XCTAssertTrue(weatherPreferenceSource.contains("case currentLocation"))
        XCTAssertTrue(dashboardSource.contains("public let weather: TodayWeatherSnapshot"))
        XCTAssertTrue(dashboardViewSource.contains("let weatherState: TodayWeatherState"))
        XCTAssertTrue(dashboardViewSource.contains("weatherState: weatherState"))
        XCTAssertTrue(todayWorkflowSource.contains("dashboardWeatherState: TodayWeatherState? = nil"))
        XCTAssertTrue(todayWorkflowSource.contains("AppRuntimeFactory.makeTodayWeatherModel"))
        XCTAssertTrue(headerSource.contains("today-weather"))
        XCTAssertTrue(headerSource.contains("weather.accessibilityLabel"))
        XCTAssertTrue(headerSource.contains(".accessibilityElement(children: .contain)"))
        let taskListSource = try readPackageFile("Sources/SuisuiApp/Views/TodayDashboardTaskListView.swift")
        let weeklySource = try readPackageFile("Sources/SuisuiApp/Views/TodayDashboardCards.swift")
        XCTAssertTrue(taskListSource.contains("Grid("))
        XCTAssertTrue(taskListSource.contains("let isWide: Bool"))
        XCTAssertTrue(weeklySource.contains(".accessibilityElement(children: .contain)"))
        XCTAssertTrue(localizedDisplaySource.contains("func localizedDurationMinutes"))
        XCTAssertTrue(onboardingSource.contains("onboarding-profile-display-name"))
        XCTAssertTrue(onboardingSource.contains("onboarding-daily-work-capacity"))
        XCTAssertTrue(onboardingSource.contains("saveTodayPreferencesThen"))
        XCTAssertTrue(onboardingSource.contains("guard settingsViewModel.saveOnboardingTodayPreferences(todayPreferences) else"))
        XCTAssertTrue(onboardingSource.contains("todayPreferencesSaveError = localizedDisplay(\"Could not save your Today preferences.\")"))
        XCTAssertFalse(onboardingSource.contains("String(localized: \"Could not save your Today preferences.\")"))
        XCTAssertTrue(settingsSource.contains("saveOnboardingTodayPreferences"))
        XCTAssertTrue(settingsSource.contains("let previousSettings = settings"))
        XCTAssertTrue(settingsSource.contains("settings = previousSettings"))
    }

    func testTodayIntegrationRailUsesInjectedReadOnlyConnectionSnapshots() throws {
        let integrationSource = try readPackageFile("Sources/SuisuiCore/App/TodayIntegrationSnapshot.swift")
        let dashboardSource = try readPackageFile("Sources/SuisuiCore/App/TodayDashboardSnapshot.swift")
        let workflowSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectWorkflowTodayView.swift")
        let dashboardViewSource = try readPackageFile("Sources/SuisuiApp/Views/TodayDashboardView.swift")
        let railSource = try readPackageFile("Sources/SuisuiApp/Views/TodayDashboardRailView.swift")
        let featureViewModelSource = try readPackageFile("Sources/SuisuiCore/App/TodayFeatureViewModel.swift")
        let boardSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardView.swift")
        let projectBoardCoreSource = try readPackageFile("Sources/SuisuiCore/App/ProjectBoard.swift")
        let appSettingsSource = try readPackageFile("Sources/SuisuiCore/App/AppSettings.swift")
        let settingsSource = try readPackageFile("Sources/SuisuiApp/Views/SettingsView.swift")
        let runtimeBundleSource = try readPackageFile("Sources/SuisuiApp/Composition/ProjectBoardRuntimeFactory.swift")

        XCTAssertTrue(integrationSource.contains("public enum TodayIntegrationState"))
        XCTAssertTrue(integrationSource.contains("case notConnected"))
        XCTAssertTrue(integrationSource.contains("case permissionPending"))
        XCTAssertTrue(integrationSource.contains("case connected"))
        XCTAssertTrue(integrationSource.contains("case syncing"))
        XCTAssertTrue(integrationSource.contains("case synced"))
        XCTAssertTrue(integrationSource.contains("case failed"))
        XCTAssertTrue(integrationSource.contains("public enum TodayIntegrationPresentationState"))
        XCTAssertTrue(integrationSource.contains("category: TodayIntegrationFailureCategory"))
        XCTAssertTrue(integrationSource.contains("private static func presentationState"))
        XCTAssertFalse(integrationSource.contains("public let state: TodayIntegrationState"))
        XCTAssertTrue(integrationSource.contains("private static func failureDetail"))
        XCTAssertFalse(integrationSource.contains("localized(\"Sync failed. %@\""))
        XCTAssertFalse(integrationSource.contains("URLSession"))
        XCTAssertTrue(dashboardSource.contains("public let integrations: TodayIntegrationsSnapshot"))
        XCTAssertTrue(dashboardSource.contains("integrationsState: TodayIntegrationStates"))
        XCTAssertTrue(featureViewModelSource.contains("public var integrationStates: TodayIntegrationStates"))
        XCTAssertTrue(featureViewModelSource.contains("board.$googleCalendarSyncStatus"))
        XCTAssertTrue(runtimeBundleSource.contains("googleCalendarSyncStatus: makeGoogleCalendarRuntimeSyncStatus(connection: connection)"))
        XCTAssertTrue(workflowSource.contains("integrationsState: resolvedIntegrationsState"))
        XCTAssertTrue(workflowSource.contains("viewModel.integrationStates"))
        XCTAssertTrue(workflowSource.contains("SUISUI_VISUAL_EVIDENCE_REFERENCE_INSTANT"))
        XCTAssertTrue(appSettingsSource.contains("suisuiGoogleCalendarReadinessDidChange"))
        XCTAssertTrue(settingsSource.contains("NotificationCenter.default.post(name: .suisuiGoogleCalendarReadinessDidChange"))
        XCTAssertTrue(projectBoardCoreSource.contains("refreshGoogleCalendarSyncStatusOffMain"))
        XCTAssertTrue(projectBoardCoreSource.contains("Task.detached(priority: .utility)"))
        XCTAssertTrue(projectBoardCoreSource.contains("A synchronous user/approval refresh is newer"))
        XCTAssertTrue(projectBoardCoreSource.contains("if hasLoadedBoardSnapshot"))
        XCTAssertTrue(projectBoardCoreSource.contains("hasPreloadedGoogleCalendarSyncStatus"))
        XCTAssertTrue(projectBoardCoreSource.contains("initialGoogleCalendarSyncStatus != nil"))
        XCTAssertFalse(dashboardViewSource.contains("makeTodayIntegrationStates"))
        XCTAssertFalse(dashboardViewSource.contains("migratedConnection"))
        XCTAssertFalse(workflowSource.contains("migratedConnection"))
        XCTAssertFalse(boardSource.contains("makeTodayIntegrationStates"))
        XCTAssertTrue(railSource.contains("today-calendar-card"))
        XCTAssertTrue(railSource.contains("today-slack-card"))
        XCTAssertTrue(railSource.contains("suisuiOpenBoardSettings"))
        XCTAssertTrue(railSource.contains("It does not start sync or send messages."))
        XCTAssertFalse(railSource.contains("URLSession"))
    }

    func testProductionSettingsFactoryWiresURLSessionOllamaHealthChecker() throws {
        let factorySource = try readPackageFile("Sources/SuisuiApp/Composition/SettingsRuntimeFactory.swift")
        let coreSource = try readPackageFile("Sources/SuisuiCore/App/AppSettings.swift")

        XCTAssertTrue(
            factorySource.contains("ollamaHealthChecker: URLSessionOllamaEndpointHealthChecker()"),
            "Production composition must inject URLSessionOllamaEndpointHealthChecker so Ollama can become ready"
        )
        XCTAssertFalse(
            factorySource.contains("ollamaHealthChecker: UncheckedOllamaEndpointHealthChecker"),
            "Production composition must not fall back to the Unchecked default"
        )
        XCTAssertTrue(
            coreSource.contains("public struct URLSessionOllamaEndpointHealthChecker: OllamaEndpointHealthChecking"),
            "Core must own the URLSession-backed checker so production can use it"
        )
    }

    func testOnboardingRerunConsumesPendingTokenOnWindowRegistration() throws {
        let coreSource = try readPackageFile("Sources/SuisuiCore/App/FirstRunOnboarding.swift")
        let appSource = try readAppShellSource()

        XCTAssertTrue(
            coreSource.contains("public func consumePendingRerun(for windowID: UUID) -> UUID?"),
            "Coordinator must expose an atomic consumePendingRerun API for window registration"
        )
        XCTAssertTrue(
            appSource.contains("onboardingRerunCoordinator.consumePendingRerun(for: sceneID)"),
            "ProjectBoardWindowRootView must consume pending rerun on appear"
        )
        XCTAssertTrue(
            appSource.contains("openWindow(id: \"project-board\")"),
            "Settings entry points must still be able to reopen the Project Board window"
        )
    }

    func testProductionRefreshProviderReadinessRunsKeychainReadsOffMainActor() throws {
        let coreSource = try readPackageFile("Sources/SuisuiCore/App/AppSettings.swift")

        XCTAssertTrue(
            coreSource.contains("public struct ProviderSecretReadinessSnapshot: Equatable, Sendable"),
            "Core must define a Sendable ProviderSecretReadinessSnapshot for off-Main reads"
        )
        XCTAssertTrue(
            coreSource.contains("public protocol ProviderSecretReadinessReading: Sendable"),
            "Core must define a ProviderSecretReadinessReading port"
        )
        XCTAssertTrue(
            coreSource.contains("Task.detached(priority: .userInitiated) { [secretReadinessReader] in"),
            "refreshProviderReadiness must run Keychain reads on a detached background task"
        )
        XCTAssertFalse(
            coreSource.contains("private func apiKeyReadinessState(forStatusLabel label: String)"),
            "Typed readiness must not be derived from a display label"
        )
    }

    func testKeychainBackedReaderClassifiesReadErrorsAsUnavailable() throws {
        let coreSource = try readPackageFile("Sources/SuisuiCore/App/AppSettings.swift")

        XCTAssertTrue(
            coreSource.contains("try secretStore.read(key)"),
            "Reader must call SecretStore.read with try inside do/catch so a throw becomes `.unavailable`"
        )
        XCTAssertFalse(
            coreSource.contains("classifyAPIKeyValue(try? secretStore.read"),
            "Reader must not use try? — that collapses Keychain failures into `.missing`"
        )
        XCTAssertTrue(
            coreSource.contains("public var failedProviders: Set<AIProvider>"),
            "ProviderSecretReadinessReadResult must expose failedProviders so multiple read failures are preserved"
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

    private func localizableDefinitionCount(for key: String, in source: String) -> Int {
        source.components(separatedBy: .newlines).reduce(into: 0) { count, rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.first == "\"",
                  let closingQuote = line.dropFirst().firstIndex(of: "\"")
            else {
                return
            }
            let parsedKey = String(line[line.index(after: line.startIndex)..<closingQuote])
            let suffix = line[line.index(after: closingQuote)...]
                .trimmingCharacters(in: .whitespaces)
            if parsedKey == key, suffix.first == "=" {
                count += 1
            }
        }
    }

    private func readAppShellSource() throws -> String {
        let appSource = try readPackageFile("Sources/SuisuiApp/SuisuiApp.swift")
        let viewSources = try [
            "Sources/SuisuiApp/Views/ProjectBoardLaunchRecoveryViews.swift",
            "Sources/SuisuiApp/Views/MenuBarPanel.swift",
            "Sources/SuisuiApp/Views/VoiceCaptureView.swift",
            "Sources/SuisuiApp/Views/ActionReviewPanel.swift",
            "Sources/SuisuiApp/Views/SettingsView.swift",
            "Sources/SuisuiApp/Views/SettingsFeatureViews.swift"
        ].map(readPackageFile).joined(separator: "\n\n")
        let runtimeCompositionSources = try [
            "Sources/SuisuiApp/Composition/AppRuntimeFactory.swift",
            "Sources/SuisuiApp/Composition/ProjectBoardRuntimeFactory.swift",
            "Sources/SuisuiApp/Composition/RuntimeToolCompositionFactory.swift",
            "Sources/SuisuiApp/Composition/SettingsRuntimeFactory.swift",
            "Sources/SuisuiApp/Composition/GoogleCalendarRuntimeCompositionFactory.swift",
            "Sources/SuisuiApp/Composition/VoiceRuntimeFactory.swift",
            "Sources/SuisuiApp/Composition/MenuBarRuntimeFactory.swift"
        ].map(readPackageFile).joined(separator: "\n\n")

        return [
            appSource,
            viewSources,
            runtimeCompositionSources
        ].joined(separator: "\n\n")
    }

    private func readProjectBoardSurfaceSources() throws -> String {
        let ownedBasenamePrefixes = ["ProjectBoard", "ProjectWorkflow", "TaskInspector"]
        let sourceFiles = try allSwiftFiles(under: "Sources/SuisuiApp/Views")
            .filter { url in
                ownedBasenamePrefixes.contains { url.lastPathComponent.hasPrefix($0) }
            }
            .sorted { relativePackagePath(for: $0) < relativePackagePath(for: $1) }

        return try sourceFiles
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n\n")
    }

    private func readProjectBoardOwnerSource() throws -> String {
        try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardView.swift")
    }

    private func readProjectBoardDetailSource() throws -> String {
        try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardDetailViews.swift")
    }

    private func readProjectBoardInspectorSource() throws -> String {
        try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardInspectors.swift")
    }

    private func readSettingsSurfaceSources() throws -> String {
        try [
            "Sources/SuisuiApp/Views/SettingsView.swift",
            "Sources/SuisuiApp/Views/SettingsFeatureViews.swift"
        ].map(readPackageFile).joined(separator: "\n\n")
    }

    private func taskInspectorRefreshContract(in surfaceSource: String) throws -> String {
        let taskInspectorSource = try sourceBlock(
            in: surfaceSource,
            from: "struct TaskInspectorView: View",
            to: "private func deleteSelectedTaskAfterConfirmationDismissal()"
        )
        return try sourceBlock(
            in: taskInspectorSource,
            from: ".onAppear {",
            to: "private func deleteSelectedTaskAfterConfirmationDismissal()"
        )
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

    private func localizableKeyOccurrences(in relativePath: String) throws -> [String: Int] {
        let source = try readPackageFile(relativePath)
        let pattern = #""((?:[^"\\]|\\.)*)"\s*="#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(source.startIndex..<source.endIndex, in: source)

        return regex.matches(in: source, range: range).reduce(into: [:]) { occurrences, match in
            guard let keyRange = Range(match.range(at: 1), in: source) else {
                return
            }
            occurrences[String(source[keyRange]), default: 0] += 1
        }
    }

    private func readProjectWorkflowSources() throws -> String {
        try [
            "Sources/SuisuiApp/Views/ProjectWorkflowSharedViews.swift",
            "Sources/SuisuiApp/Views/ProjectWorkflowTodayView.swift",
            "Sources/SuisuiApp/Views/TodayDashboardView.swift",
            "Sources/SuisuiApp/Views/TodayDashboardHeaderView.swift",
            "Sources/SuisuiApp/Views/TodayDashboardCards.swift",
            "Sources/SuisuiApp/Views/TodayDashboardTaskListView.swift",
            "Sources/SuisuiApp/Views/TodayDashboardRailView.swift",
            "Sources/SuisuiApp/Views/ProjectWorkflowCatchUpView.swift",
            "Sources/SuisuiApp/Views/ProjectWorkflowScheduleView.swift",
            "Sources/SuisuiApp/Views/ProjectWorkflowDoneView.swift",
            "Sources/SuisuiApp/Views/ProjectWorkflowInboxView.swift",
            "Sources/SuisuiApp/Views/ProjectWorkflowAssistantQueueView.swift"
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
            #"\bLabeledContent\("((?:[^"\\]|\\.)*)""#,
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

        for fileURL in try allSwiftFiles(under: "Sources/SuisuiApp") {
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

    private func bashArrayStringPayloads(in source: String) throws -> [String] {
        var payloads: [String] = []

        for (lineIndex, rawLine) in source.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else {
                continue
            }
            guard line.count >= 2, line.first == "\"", line.last == "\"" else {
                throw BashArrayStringParseError.invalidElement(line: lineIndex + 1, value: line)
            }

            let payload = line.dropFirst().dropLast()
            var backslashEscaped = false
            for character in payload {
                if character == "\"", !backslashEscaped {
                    throw BashArrayStringParseError.invalidElement(line: lineIndex + 1, value: line)
                }
                if character == "\\" {
                    backslashEscaped.toggle()
                } else {
                    backslashEscaped = false
                }
            }
            guard !backslashEscaped else {
                throw BashArrayStringParseError.invalidElement(line: lineIndex + 1, value: line)
            }

            // Removing only the boundary quotes preserves Bash escapes verbatim;
            // replacing quote text here could silently change a route payload.
            payloads.append(String(payload))
        }

        return payloads
    }

    private enum BashArrayStringParseError: Error {
        case invalidElement(line: Int, value: String)
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }
}
