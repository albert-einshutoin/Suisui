import Foundation
import XCTest

final class LaunchExperienceTests: XCTestCase {
    func testRunScriptActivatesAppAfterOpeningBundle() throws {
        let script = try readPackageFile("script/build_and_run.sh")

        XCTAssertTrue(script.contains("local open_args=(-n -F \"$APP_BUNDLE\")"))
        XCTAssertTrue(script.contains("activate_app()"))
        XCTAssertTrue(script.contains("local osascript_pid=$!"))
        XCTAssertTrue(script.contains("kill \"$osascript_pid\""))
        XCTAssertTrue(script.contains("tell application \\\"$APP_NAME\\\" to activate"))
        XCTAssertTrue(script.contains("SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1"))
        XCTAssertTrue(script.contains("SOLOPM_LAUNCH_RECOVERY_MODE=1"))
        XCTAssertFalse(script.contains("/usr/bin/osascript -e \"tell application \\\"$APP_NAME\\\" to activate\" >/dev/null 2>&1 || true"))
    }

    func testVerifyModeRequiresVisibleProjectBoardWindow() throws {
        let script = try readPackageFile("script/build_and_run.sh")

        XCTAssertTrue(script.contains("SOLOPM_VERIFY_TIMEOUT_SECONDS"))
        XCTAssertTrue(script.contains("PROJECT_BOARD_WINDOW_NAME=\"${SOLOPM_PROJECT_BOARD_WINDOW_NAME:-SoloPM}\""))
        XCTAssertTrue(script.contains("wait_for_project_board_window"))
        XCTAssertTrue(script.contains("SOLOPM_WINDOW_OWNER=\"$APP_NAME\""))
        XCTAssertTrue(script.contains("SOLOPM_WINDOW_NAME=\"$PROJECT_BOARD_WINDOW_NAME\""))
        XCTAssertTrue(script.contains("script/ui_evidence_window_metadata.swift"))
        XCTAssertTrue(script.contains("BLOCKER: Project Board window was not visible within"))
        XCTAssertFalse(script.contains("sleep 1\n    pgrep -x \"$APP_NAME\" >/dev/null\n    ;;"))
    }

    func testWindowlessSavedStateStillShowsProjectBoardOnLaunch() throws {
        let script = try readPackageFile("script/build_and_run.sh")
        let source = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

        XCTAssertTrue(script.contains("<key>NSQuitAlwaysKeepsWindows</key>"))
        XCTAssertTrue(script.contains("<false/>"))
        XCTAssertTrue(script.contains("wait_for_project_board_window"))
        XCTAssertTrue(script.contains("BLOCKER: Project Board window was not visible within"))
        XCTAssertTrue(source.contains("SoloPMProjectBoardWindowFallback.shared.showIfNeeded()"))
        XCTAssertTrue(source.contains("createFallbackProjectBoardWindow()"))
        XCTAssertTrue(source.contains("guard SoloPMWindowlessFallbackEnvironment.shouldForceProjectBoardFallback || visibleProjectBoardWindows.isEmpty else"))
        XCTAssertTrue(source.contains("window.makeKeyAndOrderFront(nil)"))
        XCTAssertTrue(source.contains("window.orderFrontRegardless()"))
    }

    func testBundleDisablesWindowRestorationForPrimaryBoardLaunch() throws {
        let script = try readPackageFile("script/build_and_run.sh")

        XCTAssertTrue(script.contains("<key>NSQuitAlwaysKeepsWindows</key>"))
        XCTAssertTrue(script.contains("<false/>"))
    }

    func testBundleCarriesSignedLocalLicensePublicKeyMetadata() throws {
        let script = try readPackageFile("script/build_and_run.sh")

        XCTAssertTrue(script.contains("LOCAL_LICENSE_PUBLIC_KEY_BASE64=\"${SOLOPM_LOCAL_LICENSE_PUBLIC_KEY_BASE64:-${SOLOPM_LOCAL_LICENSE_PUBLIC_KEY:-}}\""))
        XCTAssertTrue(script.contains("xml_escape()"))
        XCTAssertTrue(script.contains("<key>SoloPMLocalLicensePublicKey</key>"))
        XCTAssertTrue(script.contains("$(xml_escape \"$LOCAL_LICENSE_PUBLIC_KEY_BASE64\")"))
    }

    func testAppDelegateActivatesRegularAppOnLaunch() throws {
        let source = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

        XCTAssertTrue(source.contains("NSApplication.shared.setActivationPolicy(.regular)"))
        XCTAssertTrue(source.contains("NSApplication.shared.activate(ignoringOtherApps: true)"))
    }

    func testAppInitActivatesButDefersFallbackWindowCreationToDelegate() throws {
        let source = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

        let initStart = try XCTUnwrap(source.range(of: "@MainActor\n    init() {"))
        let bodyStart = try XCTUnwrap(source.range(of: "\n    var body: some Scene {"))
        let initBlock = source[initStart.lowerBound..<bodyStart.lowerBound]
        XCTAssertTrue(initBlock.contains("NSApplication.shared.setActivationPolicy(.regular)"))
        XCTAssertFalse(initBlock.contains("SoloPMProjectBoardWindowFallback.shared.showIfNeeded()"))
        XCTAssertFalse(initBlock.contains("NSApp.windows"))

        let delegateStart = try XCTUnwrap(source.range(of: "func applicationDidFinishLaunching"))
        let delegateEnd = try XCTUnwrap(source.range(of: "#if canImport(Sparkle)", range: delegateStart.lowerBound..<source.endIndex))
        let delegateBlock = source[delegateStart.lowerBound..<delegateEnd.lowerBound]
        XCTAssertTrue(delegateBlock.contains("ensureProjectBoardWindowIsVisible()"))
        XCTAssertFalse(delegateBlock.contains("createFallbackProjectBoardWindow()"))
    }

    func testVerifyModeCanLaunchWithoutPromptingForKeychainSecrets() throws {
        let source = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

        XCTAssertTrue(source.contains("SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE"))
        XCTAssertTrue(source.contains("LaunchVerificationSecretStore"))
        XCTAssertTrue(source.contains("return nil"))
    }

    func testRuntimeFactorySharesSecretStoreAcrossProviderSurfaces() throws {
        let source = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

        XCTAssertTrue(source.contains("private static let sharedSecretStore: any SecretStore"))
        XCTAssertTrue(source.contains("return sharedSecretStore"))
        XCTAssertFalse(source.contains("private static func makeSecretStore() -> any SecretStore {\n        if ProcessInfo.processInfo.environment[\"SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE\"] == \"1\""))
    }

    func testAppDelegateReopensProjectBoardWhenNoWindowIsVisible() throws {
        let source = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

        XCTAssertTrue(source.contains("applicationShouldHandleReopen"))
        XCTAssertTrue(source.contains("ensureProjectBoardWindowIsVisible()"))
        XCTAssertTrue(source.contains("projectBoardWindowRestoreAttempts"))
        XCTAssertTrue(source.contains("attemptEnsureProjectBoardWindowIsVisible(after: 0.25)"))
        XCTAssertTrue(source.contains("projectBoardWindowRestoreAttempts < 12"))
        XCTAssertTrue(source.contains("didRequestWindow ? 0.75 : 0.25"))
        XCTAssertTrue(source.contains("performNewProjectBoardWindowMenuItem()"))
        XCTAssertTrue(source.contains("New SoloPM Window"))
        XCTAssertTrue(source.contains("performActionForItem(at: itemIndex)"))
        XCTAssertTrue(source.contains("visibleProjectBoardWindows"))
        XCTAssertTrue(source.contains("fallbackProjectBoardWindow"))
        XCTAssertTrue(source.contains("rootView: ProjectBoardFallbackRootView("))
        XCTAssertTrue(source.contains("viewModel: AppRuntimeFactory.makeProjectBoardViewModel()"))
        XCTAssertTrue(source.contains("makeKeyAndOrderFront(nil)"))
        XCTAssertTrue(source.contains("#selector(NSWindow.newWindowForTab(_:))"))
        XCTAssertTrue(source.contains("return false"))
    }

    func testFallbackProjectBoardWindowUsesTodayLaunchRecoveryView() throws {
        let source = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

        XCTAssertTrue(source.contains("private struct ProjectBoardFallbackRootView: View"))
        XCTAssertTrue(source.contains("if SoloPMLaunchRecoveryEnvironment.isEnabled"))
        XCTAssertTrue(source.contains("ProjectBoardView("))
        XCTAssertTrue(source.contains("private struct ProjectBoardLaunchRecoveryView: View"))
        XCTAssertTrue(source.contains("TodayWorkflowView("))
        XCTAssertTrue(source.contains("selectTodayTask: selectWorkflowTask"))
        XCTAssertTrue(source.contains("openInspectorForTodayRailTask: openInspectorForWorkflowTask"))
        XCTAssertTrue(source.contains("private var recoveryInspector: some View"))
        XCTAssertTrue(source.contains("ProjectBoardLaunchRecoveryTaskInspector("))
        XCTAssertTrue(source.contains("private func openInspectorForWorkflowTask(_ taskID: Int64)"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"task-inspector-title\")"))
        XCTAssertTrue(source.contains("InboxWorkflowView(viewModel: viewModel"))
        XCTAssertTrue(source.contains("case .done:\n            DoneWorkflowView(viewModel: viewModel, appSettings: appSettings())"))
        XCTAssertTrue(source.contains("case .assistantQueue:\n            AssistantQueueWorkflowView(viewModel: viewModel)"))
        XCTAssertTrue(source.contains("case .project(let projectID):"))
        XCTAssertTrue(source.contains("ProjectDevelopmentAutomationRecoveryView("))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-queue\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-development-automation-queue-handoff\")"))
        XCTAssertTrue(source.contains("@State private var didLoad = false"))
        XCTAssertTrue(source.contains("private var resolvedSelectedDestination: ProjectBoardLaunchRecoveryDestination"))
        XCTAssertTrue(source.contains("selectedDestination.resolved(availableProjects: viewModel.snapshot.projects)"))
        XCTAssertTrue(source.contains("func resolved(availableProjects: [ProjectBoardProject]) -> ProjectBoardLaunchRecoveryDestination"))
        XCTAssertTrue(source.contains("availableProjects.contains(where: { $0.id == projectID }) ? self : .today"))
        XCTAssertFalse(source.contains("isProjectBoardRecovery"))
        XCTAssertTrue(source.contains("SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION"))
        XCTAssertTrue(source.contains("ProjectBoardLaunchRecoveryDestination"))
        XCTAssertTrue(source.contains("case .assistantQueue"))
        XCTAssertTrue(source.contains("case \"assistant-queue\":"))
        XCTAssertTrue(source.contains("case .project(let projectID)"))
        XCTAssertTrue(source.contains("rawValue.hasPrefix(\"project:\")"))
        XCTAssertTrue(source.contains("ProjectBoardTaskSelectionPersistence.environmentOverrideTaskID"))
        XCTAssertTrue(source.contains("viewModel.selectedTaskID = taskID"))
        XCTAssertTrue(source.contains("viewModel.load()"))
        XCTAssertTrue(source.contains("scheduleMissedTaskDailyFollowUp(settings: appSettings())"))
    }

    func testLaunchVerificationRecoveryUsesFallbackBeforeWindowGroupRetries() throws {
        let source = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
        let recoveryStart = try XCTUnwrap(source.range(of: "private enum SoloPMLaunchRecoveryEnvironment"))
        let recoveryEnd = try XCTUnwrap(source.range(of: "private enum SoloPMWindowlessFallbackEnvironment"))
        let recoveryBlock = String(source[recoveryStart.lowerBound..<recoveryEnd.lowerBound])

        XCTAssertTrue(recoveryBlock.contains("private enum SoloPMLaunchRecoveryEnvironment"))
        XCTAssertTrue(recoveryBlock.contains("private static let flagName = \"SOLOPM_LAUNCH_RECOVERY_MODE\""))
        XCTAssertTrue(recoveryBlock.contains("return environment[flagName] == \"1\""))
        XCTAssertFalse(recoveryBlock.contains("environment[\"SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE\"] == \"1\""))
        XCTAssertFalse(recoveryBlock.contains("environment[\"SOLOPM_DATABASE_PATH\"] != nil"))
        XCTAssertTrue(source.contains("if SoloPMLaunchRecoveryEnvironment.isEnabled"))
        XCTAssertTrue(source.contains("self.createFallbackProjectBoardWindow()"))
    }

    func testIsolatedDatabaseLaunchesUseFullBoardFallbackWithoutRecoveryMode() throws {
        let source = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

        XCTAssertTrue(source.contains("private enum SoloPMWindowlessFallbackEnvironment"))
        XCTAssertTrue(source.contains("static var shouldCreateDirectFallbackWindow: Bool"))
        XCTAssertTrue(source.contains("static var shouldForceProjectBoardFallback: Bool"))
        XCTAssertTrue(source.contains("private static let forceFallbackFlagName = \"SOLOPM_FORCE_PROJECT_BOARD_FALLBACK\""))
        XCTAssertTrue(source.contains("return SoloPMLaunchRecoveryEnvironment.isEnabled\n            || environment[\"SOLOPM_DATABASE_PATH\"] != nil"))
        XCTAssertTrue(source.contains("|| shouldForceProjectBoardFallback"))
        XCTAssertTrue(source.contains("guard SoloPMWindowlessFallbackEnvironment.shouldForceProjectBoardFallback || visibleProjectBoardWindows.isEmpty else"))
        XCTAssertTrue(source.contains("if SoloPMWindowlessFallbackEnvironment.shouldCreateDirectFallbackWindow"))
        XCTAssertTrue(source.contains("taskAutomationSettings: AppRuntimeFactory.loadTaskAutoExecutionSettings"))
        XCTAssertTrue(source.contains("window.occlusionState.contains(.visible)"))
    }

    func testRuntimeWorkflowSmokesOptIntoLaunchRecoveryExplicitly() throws {
        let todaySmoke = try readPackageFile("script/check_runtime_today_complete_smoke.sh")
        let inboxSmoke = try readPackageFile("script/check_runtime_inbox_triage_smoke.sh")
        let screenshotCapture = try readPackageFile("script/capture_ui_evidence.sh")

        XCTAssertTrue(todaySmoke.contains("SOLOPM_LAUNCH_RECOVERY_MODE=1"))
        XCTAssertTrue(inboxSmoke.contains("SOLOPM_LAUNCH_RECOVERY_MODE=1"))
        XCTAssertTrue(screenshotCapture.contains("--p0-workflows"))
        XCTAssertTrue(screenshotCapture.contains("--schedule-cockpit"))
        XCTAssertTrue(screenshotCapture.contains("--done-analytics"))
        XCTAssertTrue(screenshotCapture.contains("if [[ \"$P0_WORKFLOWS\" == \"1\" ]]"))
        XCTAssertTrue(screenshotCapture.contains("if [[ \"$P0_WORKFLOWS\" == \"1\" || \"$SCHEDULE_COCKPIT\" == \"1\" || \"$DONE_ANALYTICS\" == \"1\" ]]"))
        XCTAssertTrue(screenshotCapture.contains("args+=(\"SOLOPM_LAUNCH_RECOVERY_MODE=1\")"))
    }

    func testLaunchVerificationWindowGroupUsesLaunchRecoveryView() throws {
        let source = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

        XCTAssertTrue(source.contains("if SoloPMLaunchRecoveryEnvironment.isEnabled {"))
        XCTAssertTrue(source.contains("ProjectBoardLaunchRecoveryView("))
        XCTAssertTrue(source.contains("ProjectBoardView("))
        XCTAssertTrue(source.contains("case .schedule:\n            ScheduleWorkflowView(viewModel: viewModel)"))
        XCTAssertTrue(source.contains("case schedule"))
        XCTAssertTrue(source.contains("case done"))
        XCTAssertTrue(source.contains("case .project(let projectID):"))
    }

    func testWorkflowRootAccessibilityKeepsNestedLaunchRecoveryIdentifiers() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectWorkflowViews.swift")

        XCTAssertTrue(source.contains(".accessibilityElement(children: .contain)\n        .accessibilityIdentifier(\"today-workflow\")"))
        XCTAssertTrue(source.contains(".accessibilityElement(children: .contain)\n        .accessibilityIdentifier(\"inbox-workflow\")"))
    }

    func testProjectBoardOpensOnLaunch() throws {
        let source = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

        XCTAssertTrue(source.contains("WindowGroup(\"SoloPM\", id: \"project-board\")"))

        let boardWindow = try XCTUnwrap(source.range(of: "WindowGroup(\"SoloPM\", id: \"project-board\")"))
        let menuBar = try XCTUnwrap(source.range(of: "MenuBarExtra(\"SoloPM\", systemImage: \"checklist\")"))
        XCTAssertLessThan(boardWindow.lowerBound, menuBar.lowerBound)
    }

    func testProjectBoardMultiWindowBoundaryUsesIndependentViewModelsAndSharedSelectionPersistence() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
        let boardSource = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardView.swift")

        XCTAssertTrue(appSource.contains("WindowGroup(\"SoloPM\", id: \"project-board\")"))
        XCTAssertTrue(appSource.contains("taskAutomationSettings: { settingsViewModel.settings.taskAutoExecution }"))
        XCTAssertTrue(appSource.contains("appSettings: { settingsViewModel.settings }"))
        XCTAssertTrue(appSource.contains("#selector(NSWindow.newWindowForTab(_:))"))
        XCTAssertTrue(appSource.contains("New SoloPM Window"))
        XCTAssertTrue(boardSource.contains("@StateObject private var viewModel: ProjectBoardViewModel"))
        XCTAssertTrue(boardSource.contains("let taskAutomationSettings: () -> TaskAutoExecutionSettings"))
        XCTAssertTrue(boardSource.contains("let appSettings: () -> AppSettings"))
        XCTAssertTrue(boardSource.contains("@AppStorage(ProjectBoardSelectionPersistence.storageKey)"))
        XCTAssertTrue(boardSource.contains("@State private var selectedDestination: ProjectBoardSidebarDestination? = .today"))
    }

    private func readPackageFile(_ relativePath: String) throws -> String {
        let url = packageRoot().appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }
}
