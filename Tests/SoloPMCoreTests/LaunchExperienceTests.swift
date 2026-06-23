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
        XCTAssertTrue(source.contains("guard visibleProjectBoardWindows.isEmpty else"))
        XCTAssertTrue(source.contains("window.makeKeyAndOrderFront(nil)"))
        XCTAssertTrue(source.contains("window.orderFrontRegardless()"))
    }

    func testBundleDisablesWindowRestorationForPrimaryBoardLaunch() throws {
        let script = try readPackageFile("script/build_and_run.sh")

        XCTAssertTrue(script.contains("<key>NSQuitAlwaysKeepsWindows</key>"))
        XCTAssertTrue(script.contains("<false/>"))
    }

    func testAppDelegateActivatesRegularAppOnLaunch() throws {
        let source = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

        XCTAssertTrue(source.contains("NSApplication.shared.setActivationPolicy(.regular)"))
        XCTAssertTrue(source.contains("NSApplication.shared.activate(ignoringOtherApps: true)"))
    }

    func testAppInitUsesSharedApplicationWhenPresentingLaunchWindow() throws {
        let source = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

        let initStart = try XCTUnwrap(source.range(of: "@MainActor\n    init() {"))
        let bodyStart = try XCTUnwrap(source.range(of: "\n    var body: some Scene {"))
        let initBlock = source[initStart.lowerBound..<bodyStart.lowerBound]
        XCTAssertTrue(initBlock.contains("NSApplication.shared.setActivationPolicy(.regular)"))
        XCTAssertTrue(initBlock.contains("SoloPMProjectBoardWindowFallback.shared.showIfNeeded()"))
        XCTAssertFalse(initBlock.contains("NSApp.windows"))
    }

    func testVerifyModeCanLaunchWithoutPromptingForKeychainSecrets() throws {
        let source = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

        XCTAssertTrue(source.contains("SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE"))
        XCTAssertTrue(source.contains("LaunchVerificationSecretStore"))
        XCTAssertTrue(source.contains("return nil"))
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
        XCTAssertTrue(source.contains("rootView: ProjectBoardView("))
        XCTAssertTrue(source.contains("taskAutomationSettings: AppRuntimeFactory.loadTaskAutoExecutionSettings"))
        XCTAssertTrue(source.contains("makeKeyAndOrderFront(nil)"))
        XCTAssertTrue(source.contains("#selector(NSWindow.newWindowForTab(_:))"))
        XCTAssertTrue(source.contains("return false"))
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
        XCTAssertTrue(appSource.contains("#selector(NSWindow.newWindowForTab(_:))"))
        XCTAssertTrue(appSource.contains("New SoloPM Window"))
        XCTAssertTrue(boardSource.contains("@StateObject private var viewModel: ProjectBoardViewModel"))
        XCTAssertTrue(boardSource.contains("let taskAutomationSettings: () -> TaskAutoExecutionSettings"))
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
