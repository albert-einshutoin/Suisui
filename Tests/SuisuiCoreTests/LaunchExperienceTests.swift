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
        XCTAssertFalse(script.contains("\"$APP_BINARY\" -ApplePersistenceIgnoreState YES >/dev/null 2>&1 &"))
        XCTAssertFalse(script.contains("/usr/bin/osascript -e \"tell application \\\"$APP_NAME\\\" to activate\" >/dev/null 2>&1 || true"))
    }

    func testVerifyModeLaunchesBundleThroughNSWorkspaceAndCapturesExactPID() throws {
        let script = try readPackageFile("script/build_and_run.sh")
        let launcher = try readPackageFile("script/launch_macos_app.swift")

        XCTAssertTrue(script.contains("VERIFY_APP_LAUNCHER_SOURCE=\"$ROOT_DIR/script/launch_macos_app.swift\""))
        XCTAssertTrue(script.contains("/usr/bin/swiftc -parse-as-library \"$VERIFY_APP_LAUNCHER_SOURCE\" -o \"$VERIFY_APP_LAUNCHER_EXECUTABLE\""))
        XCTAssertTrue(script.contains("getconf DARWIN_USER_TEMP_DIR"))
        XCTAssertTrue(script.contains("mktemp -d \"${VERIFY_SYSTEM_TMP_ROOT%/}/suisui-verify.XXXXXX\""))
        XCTAssertTrue(script.contains("cleanup_verify_root()"))
        XCTAssertTrue(script.contains("VERIFY_LAUNCH_PID=\"$(/usr/bin/env -i"))
        XCTAssertTrue(script.contains("PATH=\"$PATH\""))
        XCTAssertTrue(script.contains("\"$APP_BUNDLE\""))
        XCTAssertTrue(script.contains("\"$selected_destination\""))
        XCTAssertFalse(try functionSource(named: "launch_verify_process", in: script).contains("\"$APP_BINARY\" -ApplePersistenceIgnoreState YES"))

        XCTAssertTrue(launcher.contains("NSWorkspace.OpenConfiguration()"))
        XCTAssertTrue(launcher.contains("configuration.createsNewApplicationInstance = true"))
        XCTAssertTrue(launcher.contains("configuration.activates = true"))
        XCTAssertTrue(launcher.contains("configuration.environment"))
        XCTAssertTrue(launcher.contains("SUISUI_DATABASE_PATH"))
        XCTAssertTrue(launcher.contains("SUISUI_PROJECT_BOARD_SELECTED_DESTINATION"))
        XCTAssertTrue(launcher.contains("runningApplication.processIdentifier"))
    }

    func testVerifyModeUsesNormalProjectBoardWithoutRecoveryFlags() throws {
        let script = try readPackageFile("script/build_and_run.sh")
        let launcher = try readPackageFile("script/launch_macos_app.swift")

        XCTAssertTrue(script.contains("SUISUI_VERIFY_TIMEOUT_SECONDS"))
        XCTAssertTrue(script.contains("PROJECT_BOARD_WINDOW_NAME=\"${SUISUI_PROJECT_BOARD_WINDOW_NAME:-}\""))
        XCTAssertTrue(script.contains("Product markers identify the Project Board independently of its localized window title"))
        XCTAssertTrue(script.contains("AX_HELPERS=\"${AX_HELPERS:-$ROOT_DIR/script/ui_accessibility_smoke_helpers.sh}\""))
        XCTAssertTrue(launcher.contains("\"HOME\": CommandLine.arguments[3]"))
        XCTAssertTrue(launcher.contains("\"CFFIXED_USER_HOME\": CommandLine.arguments[4]"))
        XCTAssertTrue(launcher.contains("\"SUISUI_DATABASE_PATH\": CommandLine.arguments[6]"))
        XCTAssertTrue(launcher.contains("\"SUISUI_DISABLE_KEYCHAIN_SECRET_STORE\": \"1\""))
        XCTAssertTrue(script.contains("launch_verify_process \"today\"\n    BOOTSTRAP_LAUNCH_PID=\"$VERIFY_LAUNCH_PID\""))
        XCTAssertTrue(script.contains("terminate_owned_verify_process \"bootstrap\" \"$BOOTSTRAP_LAUNCH_PID\" \"$BOOTSTRAP_APP_PID\""))
        XCTAssertTrue(script.contains("VERIFY_PROJECT_ID=\"$(fetch_verify_project_id)\""))
        XCTAssertTrue(script.contains("launch_verify_process \"project:$VERIFY_PROJECT_ID\"\n    APP_LAUNCH_PID=\"$VERIFY_LAUNCH_PID\""))
        XCTAssertTrue(launcher.contains("\"SUISUI_PROJECT_BOARD_SELECTED_DESTINATION\": CommandLine.arguments[7]"))
        XCTAssertTrue(script.contains("VERIFY_LAUNCH_PID=\"$(/usr/bin/env -i"))
        XCTAssertTrue(script.contains("ax_wait_for_owned_app_pid \"$launch_pid\" \"$APP_BINARY\""))
        XCTAssertTrue(script.contains("source_command = 'build-and-run-verify'"))
        XCTAssertTrue(script.contains("JOIN tasks AS t ON t.project_id = p.id"))
        XCTAssertTrue(script.contains("INSERT INTO projects"))
        XCTAssertTrue(script.contains("INSERT INTO tasks"))
        XCTAssertTrue(script.contains("due_at=\"2026-01-01T12:00:00+00:00\""))
        XCTAssertTrue(launcher.contains("\"-ApplePersistenceIgnoreState\", \"YES\""))
        XCTAssertTrue(script.contains("wait_for_project_board_window"))
        XCTAssertTrue(script.contains("wait_for_project_board_marker"))
        XCTAssertTrue(script.contains("project-board-command-palette"))
        XCTAssertTrue(script.contains("project-board-sidebar"))
        XCTAssertTrue(script.contains("project-board-detail"))
        XCTAssertTrue(script.contains("BLOCKER: Project Board window was not visible within"))
        XCTAssertFalse(script.contains("SUISUI_LAUNCH_RECOVERY_MODE"))
        XCTAssertFalse(script.contains("SUISUI_FORCE_PROJECT_BOARD_FALLBACK"))
        XCTAssertFalse(script.contains("SUISUI_PROJECT_BOARD_SELECTED_DESTINATION=\"today\""))
        XCTAssertFalse(script.contains("sleep 1\n    pgrep -x \"$APP_NAME\" >/dev/null\n    ;;"))

        let bootstrapStart = try XCTUnwrap(script.range(of: "launch_verify_process \"today\"\n    BOOTSTRAP_LAUNCH_PID=\"$VERIFY_LAUNCH_PID\""))
        let bootstrapStop = try XCTUnwrap(script.range(of: "terminate_owned_verify_process \"bootstrap\" \"$BOOTSTRAP_LAUNCH_PID\" \"$BOOTSTRAP_APP_PID\""))
        let seedStart = try XCTUnwrap(script.range(of: "    seed_verify_fixture\n    VERIFY_PROJECT_ID"))
        let projectIDFetch = try XCTUnwrap(script.range(of: "VERIFY_PROJECT_ID=\"$(fetch_verify_project_id)\""))
        let finalLaunch = try XCTUnwrap(script.range(of: "launch_verify_process \"project:$VERIFY_PROJECT_ID\"\n    APP_LAUNCH_PID=\"$VERIFY_LAUNCH_PID\""))
        XCTAssertLessThan(bootstrapStart.lowerBound, bootstrapStop.lowerBound)
        XCTAssertLessThan(bootstrapStop.lowerBound, seedStart.lowerBound)
        XCTAssertLessThan(seedStart.lowerBound, projectIDFetch.lowerBound)
        XCTAssertLessThan(projectIDFetch.lowerBound, finalLaunch.lowerBound)
    }

    func testVerifyModeUsesFixedMachineReadableFailureCategoriesAndPidOwnedChecks() throws {
        let script = try readPackageFile("script/build_and_run.sh")
        let helpers = try readPackageFile("script/ui_accessibility_smoke_helpers.sh")
        let markerChecker = try readPackageFile("script/ui_evidence_ax_marker_check.swift")

        XCTAssertTrue(helpers.contains("failure_category=%s"))
        XCTAssertTrue(helpers.contains("launch|window|accessibility|product-marker"))
        XCTAssertTrue(helpers.contains("failure_category=launch"))
        XCTAssertTrue(helpers.contains("ax_wait_for_pid_owned_process()"))
        XCTAssertTrue(helpers.contains("ax_process_matches_binary()"))
        XCTAssertTrue(helpers.contains("ax_wait_for_owned_app_pid()"))
        XCTAssertTrue(helpers.contains("ps -p \"$app_pid\" -o command="))
        XCTAssertTrue(helpers.contains("pgrep -P \"$launch_pid\""))
        XCTAssertFalse(helpers.contains("ps -p \"$app_pid\" -o comm="))
        XCTAssertTrue(helpers.contains("ax_wait_for_pid_owned_window()"))
        XCTAssertTrue(helpers.contains("ax_classify_marker_failure()"))
        XCTAssertTrue(helpers.contains("ax_classify_ax_marker_failure()"))
        XCTAssertTrue(helpers.contains("ax_classify_window_failure()"))
        XCTAssertTrue(helpers.contains("no visible AX windows|has no visible windows|window missing|pid-owned window missing"))
        XCTAssertTrue(helpers.contains("local app_pid=\"${2:-}\""))
        XCTAssertTrue(helpers.contains("if [[ -n \"$app_pid\" ]] && ! kill -0 \"$app_pid\""))
        XCTAssertTrue(helpers.contains("local marker_checker=\"${AX_MARKER_HELPER_EXECUTABLE:-}\""))
        XCTAssertTrue(helpers.contains("if [[ -n \"$marker_checker\" && -x \"$marker_checker\" ]]"))
        XCTAssertTrue(script.contains("ax_wait_for_pid_owned_process \"$APP_NAME\" \"$APP_PID\" \"$VERIFY_TIMEOUT_SECONDS\" \"$APP_BINARY\""))
        XCTAssertTrue(script.contains("ax_wait_for_pid_owned_window \"$APP_NAME\" \"$APP_PID\" \"$PROJECT_BOARD_WINDOW_NAME\" \"$VERIFY_TIMEOUT_SECONDS\" \"$window_diagnostic_file\" \"$APP_BINARY\""))
        XCTAssertTrue(script.contains("ax_classify_window_failure \"$window_diagnostic_file\" \"$APP_PID\""))
        XCTAssertTrue(script.contains("APP_PID=\"$(resolve_verify_app_pid \"$APP_LAUNCH_PID\")\""))
        XCTAssertTrue(script.contains("ax_wait_for_ax_identifier \"$APP_NAME\" \"$marker\""))
        XCTAssertTrue(script.contains("ax_classify_marker_failure \"$probe_file\""))
        XCTAssertTrue(markerChecker.contains("var foundText = textNeedle.isEmpty"))
        XCTAssertTrue(markerChecker.contains("if textNeedle.isEmpty || signalParts(for: element).signal.contains(textNeedle)"))
        XCTAssertTrue(markerChecker.contains("if !textNeedle.isEmpty && !foundText"))
    }

    func testRecoveryDiagnosticsAreExplicitlySeparateFromProductProof() throws {
        let readme = try readPackageFile("README.md")
        let contributing = try readPackageFile("CONTRIBUTING.md")
        let documentation = readme + "\n" + contributing

        XCTAssertTrue(documentation.contains("SUISUI_LAUNCH_RECOVERY_MODE=1"))
        XCTAssertTrue(documentation.contains("diagnostic"))
        XCTAssertTrue(documentation.contains("release proof"))
        XCTAssertTrue(documentation.contains("build_and_run.sh --verify"))
        XCTAssertTrue(documentation.contains("product-marker"))
    }

    func testNonVerifyRunAndBuildOnlyModesRemainSeparate() throws {
        let script = try readPackageFile("script/build_and_run.sh")

        XCTAssertTrue(script.contains("--build-only|build)"))
        XCTAssertTrue(script.contains("--build-only|build)\n    release_build_and_run_lock"))
        XCTAssertTrue(script.contains("run)\n    open_app\n    release_build_and_run_lock"))
        XCTAssertTrue(script.contains("local open_args=(-n -F \"$APP_BUNDLE\")"))
    }

    func testVerifyModeDefaultTimeoutAllowsColdSwiftUILaunchWindow() throws {
        let script = try readPackageFile("script/build_and_run.sh")

        XCTAssertTrue(script.contains("VERIFY_TIMEOUT_SECONDS=\"${SUISUI_VERIFY_TIMEOUT_SECONDS:-30}\""))
        XCTAssertFalse(script.contains("VERIFY_TIMEOUT_SECONDS=\"${SUISUI_VERIFY_TIMEOUT_SECONDS:-12}\""))
    }

    func testWindowlessSavedStateStillShowsProjectBoardOnLaunch() throws {
        let script = try readPackageFile("script/build_and_run.sh")
        let source = try readPackageFile("Sources/SuisuiApp/SuisuiApp.swift")

        XCTAssertTrue(script.contains("<key>NSQuitAlwaysKeepsWindows</key>"))
        XCTAssertTrue(script.contains("<false/>"))
        XCTAssertTrue(script.contains("wait_for_project_board_window"))
        XCTAssertTrue(script.contains("BLOCKER: Project Board window was not visible within"))
        XCTAssertTrue(source.contains("SuisuiProjectBoardWindowFallback.shared.showIfNeeded()"))
        XCTAssertTrue(source.contains("createFallbackProjectBoardWindow()"))
        XCTAssertTrue(source.contains("guard SuisuiWindowlessFallbackEnvironment.shouldForceProjectBoardFallback || visibleProjectBoardWindows.isEmpty else"))
        XCTAssertEqual(
            source.components(separatedBy: "window.title == String(localized: \"Suisui\")").count - 1,
            2,
            "both fallback and delegate window discovery must recognize the localized product title"
        )
        XCTAssertTrue(source.contains("window.makeKeyAndOrderFront(nil)"))
        XCTAssertTrue(source.contains("window.orderFrontRegardless()"))
    }

    func testBundleDisablesWindowRestorationForPrimaryBoardLaunch() throws {
        let script = try readPackageFile("script/build_and_run.sh")
        let launcher = try readPackageFile("script/launch_macos_app.swift")
        let source = try readPackageFile("Sources/SuisuiApp/SuisuiApp.swift")

        XCTAssertTrue(script.contains("<key>NSQuitAlwaysKeepsWindows</key>"))
        XCTAssertTrue(script.contains("<false/>"))
        XCTAssertTrue(launcher.contains("\"-ApplePersistenceIgnoreState\", \"YES\""))
        XCTAssertTrue(source.contains("shouldSaveApplicationState"))
        XCTAssertTrue(source.contains("shouldRestoreApplicationState"))
        XCTAssertTrue(source.contains("return false"))
    }

    func testBundleCarriesSignedLocalLicensePublicKeyMetadata() throws {
        let script = try readPackageFile("script/build_and_run.sh")

        XCTAssertTrue(script.contains("LOCAL_LICENSE_PUBLIC_KEY_BASE64=\"${SUISUI_LOCAL_LICENSE_PUBLIC_KEY_BASE64:-${SUISUI_LOCAL_LICENSE_PUBLIC_KEY:-}}\""))
        XCTAssertTrue(script.contains("xml_escape()"))
        XCTAssertTrue(script.contains("<key>SuisuiLocalLicensePublicKey</key>"))
        XCTAssertTrue(script.contains("$(xml_escape \"$LOCAL_LICENSE_PUBLIC_KEY_BASE64\")"))
    }

    func testAppDelegateActivatesRegularAppOnLaunch() throws {
        let source = try readPackageFile("Sources/SuisuiApp/SuisuiApp.swift")

        XCTAssertTrue(source.contains("NSApplication.shared.setActivationPolicy(.regular)"))
        XCTAssertTrue(source.contains("NSApplication.shared.activate(ignoringOtherApps: true)"))
    }

    func testGlobalVoiceShortcutIsProcessOwnedAndReusesExistingVoiceWindow() throws {
        let appSource = try readPackageFile("Sources/SuisuiApp/SuisuiApp.swift")
        let adapterSource = try readPackageFile("Sources/SuisuiApp/Adapters/SystemShortcutClient.swift")

        XCTAssertTrue(appSource.contains("@StateObject private var shortcutSettingsViewModel"))
        XCTAssertTrue(adapterSource.contains("SystemShortcutClient"))
        XCTAssertTrue(adapterSource.contains("registerDefaultVoiceCaptureShortcut()"))
        XCTAssertTrue(appSource.contains("VoiceWindowActivationCoordinator.shared"))
        XCTAssertTrue(adapterSource.contains("activateExistingWindowOrRequestOpen"))
        XCTAssertTrue(appSource.contains(".background(GlobalVoiceShortcutBridge())"))
        XCTAssertTrue(appSource.contains("installOpenRequest"))
        XCTAssertTrue(appSource.contains("openWindow(id: \"voice-capture\")"))
        XCTAssertTrue(appSource.contains("private struct MenuBarExtraLabel: View"))
        XCTAssertTrue(adapterSource.contains("performVoiceCommandShortcutMenuItem"))
        XCTAssertTrue(adapterSource.contains("item.keyEquivalent == \"V\""))
        XCTAssertTrue(adapterSource.contains("modifiers.contains(.shift)"))
        XCTAssertFalse(adapterSource.contains("item.title == \"Voice Command\""))
        XCTAssertTrue(appSource.contains("openWindow(id: \"voice-capture\")"))
        XCTAssertTrue(appSource.contains("markVoiceWindowVisible"))
        XCTAssertTrue(appSource.contains("markVoiceWindowClosed"))
        XCTAssertTrue(appSource.contains("VoiceWindowIdentifierInstaller()"))
        XCTAssertTrue(adapterSource.contains("NSUserInterfaceItemIdentifier(VoiceWindowIdentity.identifierRawValue)"))
        XCTAssertTrue(adapterSource.contains("VoiceWindowIdentity.matches("))
        XCTAssertFalse(adapterSource.contains("window.title == \"Voice Command\""))
        XCTAssertTrue(adapterSource.contains("RegisterEventHotKey"))
        XCTAssertTrue(adapterSource.contains("UnregisterEventHotKey"))
        XCTAssertTrue(adapterSource.contains("InstallEventHandler"))
        XCTAssertTrue(adapterSource.contains("kVK_Space"))
        XCTAssertTrue(adapterSource.contains("optionKey"))
        XCTAssertTrue(adapterSource.contains("Task { @MainActor"))
        XCTAssertFalse(adapterSource.contains("NSEvent.addGlobalMonitorForEvents"))
        XCTAssertFalse(adapterSource.contains("CGEvent.tapCreate"))
    }

    func testGlobalShortcutDoesNotRequireInputMonitoringEntitlement() throws {
        let entitlements = try readPackageFile("packaging/Suisui.entitlements")
        let adapterSource = try readPackageFile("Sources/SuisuiApp/Adapters/SystemShortcutClient.swift")

        XCTAssertFalse(entitlements.contains("listen-event"))
        XCTAssertFalse(entitlements.contains("input-monitoring"))
        XCTAssertFalse(adapterSource.contains("AXIsProcessTrusted"))
    }

    func testAppInitActivatesButDefersFallbackWindowCreationToDelegate() throws {
        let source = try readPackageFile("Sources/SuisuiApp/SuisuiApp.swift")

        let initStart = try XCTUnwrap(source.range(of: "@MainActor\n    init() {"))
        let bodyStart = try XCTUnwrap(source.range(of: "\n    var body: some Scene {"))
        let initBlock = source[initStart.lowerBound..<bodyStart.lowerBound]
        XCTAssertTrue(initBlock.contains("NSApplication.shared.setActivationPolicy(.regular)"))
        XCTAssertFalse(initBlock.contains("SuisuiProjectBoardWindowFallback.shared.showIfNeeded()"))
        XCTAssertFalse(initBlock.contains("NSApp.windows"))

        let delegateStart = try XCTUnwrap(source.range(of: "func applicationDidFinishLaunching"))
        let delegateEnd = try XCTUnwrap(source.range(of: "#if canImport(Sparkle)", range: delegateStart.lowerBound..<source.endIndex))
        let delegateBlock = source[delegateStart.lowerBound..<delegateEnd.lowerBound]
        XCTAssertTrue(delegateBlock.contains("ensureProjectBoardWindowIsVisible()"))
        XCTAssertFalse(delegateBlock.contains("createFallbackProjectBoardWindow()"))
    }

    func testVerifyModeCanLaunchWithoutPromptingForKeychainSecrets() throws {
        let source = try readRuntimeCompositionSources()

        XCTAssertTrue(source.contains("SUISUI_DISABLE_KEYCHAIN_SECRET_STORE"))
        XCTAssertTrue(source.contains("LaunchVerificationSecretStore"))
        XCTAssertTrue(source.contains("return nil"))
    }

    func testRuntimeFactorySharesSecretStoreAcrossProviderSurfaces() throws {
        let source = try readRuntimeCompositionSources()

        XCTAssertTrue(source.contains("private static let sharedSecretStore: any SecretStore"))
        XCTAssertTrue(source.contains("return sharedSecretStore"))
        XCTAssertFalse(source.contains("private static func makeSecretStore() -> any SecretStore {\n        if ProcessInfo.processInfo.environment[\"SUISUI_DISABLE_KEYCHAIN_SECRET_STORE\"] == \"1\""))
    }

    func testAppDelegateReopensProjectBoardWhenNoWindowIsVisible() throws {
        let source = try readPackageFile("Sources/SuisuiApp/SuisuiApp.swift")
        let projectBoardSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardView.swift")

        XCTAssertTrue(source.contains("applicationShouldHandleReopen"))
        XCTAssertTrue(source.contains("ensureProjectBoardWindowIsVisible()"))
        XCTAssertTrue(source.contains("projectBoardWindowRestoreAttempts"))
        XCTAssertTrue(source.contains("attemptEnsureProjectBoardWindowIsVisible(after: 0.25)"))
        XCTAssertTrue(source.contains("static let maxWindowGroupRestoreAttempts = 3"))
        XCTAssertTrue(source.contains("projectBoardWindowRestoreAttempts < SuisuiWindowlessFallbackEnvironment.maxWindowGroupRestoreAttempts"))
        XCTAssertTrue(source.contains("didRequestWindow ? 0.75 : 0.25"))
        XCTAssertTrue(source.contains("performNewProjectBoardWindowMenuItem()"))
        XCTAssertTrue(source.contains("New Suisui Window"))
        XCTAssertTrue(source.contains("performActionForItem(at: itemIndex)"))
        XCTAssertTrue(source.contains("visibleProjectBoardWindows"))
        XCTAssertTrue(source.contains("fallbackProjectBoardWindow"))
        XCTAssertTrue(source.contains("rootView: ProjectBoardFallbackRootView("))
        XCTAssertTrue(source.contains("ProjectBoardWindowRootView(\n                settingsViewModel: settingsViewModel,"))
        XCTAssertTrue(source.contains("makeAppSettingsViewModel(refreshProviderSecretStatusesOnInit: false)"))
        XCTAssertTrue(source.contains("await settingsViewModel.refreshProviderReadiness()"))
        XCTAssertTrue(source.contains("@State private var viewModel: ProjectBoardViewModel?"))
        XCTAssertTrue(source.contains("@State private var isProjectBoardReady = false"))
        XCTAssertTrue(source.contains("ProjectBoardFallbackLoadingView()"))
        XCTAssertTrue(source.contains("let runtime = await AppRuntimeFactory.prepareProjectBoardRuntimeBundle()"))
        XCTAssertTrue(source.contains("AppRuntimeFactory.makeProjectBoardViewModel(runtime: runtime)"))
        XCTAssertTrue(source.contains("await MainActor.run"))
        XCTAssertTrue(projectBoardSource.contains("LaunchPerformanceMilestones.record(\"command-ready\")"))
        XCTAssertTrue(projectBoardSource.contains("LaunchPerformanceMilestones.record(\"today-ready\")"))
        XCTAssertTrue(source.contains("LaunchPerformanceMilestones.record(\"window-visible\")"))
        XCTAssertFalse(source.contains("ProjectBoardLaunchHydrationDelay.nanoseconds"))
        XCTAssertFalse(source.contains("static let nanoseconds: UInt64 = 150_000_000"))
        XCTAssertTrue(source.contains("if SuisuiWindowlessFallbackEnvironment.shouldCreateDirectFallbackWindow"))
        XCTAssertTrue(source.contains("createFallbackProjectBoardWindow()"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-board-fallback-loading\")"))
        XCTAssertTrue(source.contains(".frame(minWidth: 960, minHeight: 572)"))
        XCTAssertFalse(source.contains(".frame(minWidth: 960, idealWidth: 1_180, minHeight: 572, idealHeight: 760)"))
        XCTAssertTrue(source.contains("window.contentMinSize = NSSize(width: 960, height: 572)"))
        XCTAssertTrue(source.contains("makeKeyAndOrderFront(nil)"))
        XCTAssertTrue(source.contains("#selector(NSWindow.newWindowForTab(_:))"))
        XCTAssertTrue(source.contains("return false"))
    }

    func testDigestNotificationOpenForcesTodayDestinationThroughSharedRouting() throws {
        let appSource = try readPackageFile("Sources/SuisuiApp/SuisuiApp.swift")
        let boardSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardView.swift")
        let menuBarSource = try readPackageFile("Sources/SuisuiApp/Views/MenuBarPanel.swift")

        // Digest taps must land on Today through the one app-level coordinator
        // before reopening a window if necessary.
        let observerStart = try XCTUnwrap(appSource.range(of: "forName: .suisuiDigestNotificationOpened"))
        let observerEnd = try XCTUnwrap(appSource.range(
            of: "openSettingsWindowForEvidenceIfRequested()",
            range: observerStart.lowerBound..<appSource.endIndex
        ))
        let observerBlock = appSource[observerStart.lowerBound..<observerEnd.lowerBound]
        XCTAssertTrue(observerBlock.contains("ProjectBoardSceneCoordinator.shared.requestOpen(route: .primary(.today))"))
        XCTAssertTrue(observerBlock.contains("ensureProjectBoardWindowIsVisible()"))

        // Every board observes publication, but the coordinator atomically
        // returns the request to only one registered scene.
        XCTAssertTrue(boardSource.contains("sceneCoordinator.consumeNext(for: sceneID)"))
        XCTAssertTrue(boardSource.contains("applySceneOpenRequest(request)"))

        // The menu bar summary shares the coordinator instead of creating a
        // second notification-driven routing implementation.
        XCTAssertTrue(menuBarSource.contains("sceneCoordinator.requestOpen(route: .primary(.today))"))
        XCTAssertTrue(menuBarSource.contains("openWindow(id: \"project-board\")"))
        XCTAssertTrue(menuBarSource.contains(".accessibilityIdentifier(\"menu-bar-open-today\")"))
        XCTAssertTrue(menuBarSource.contains("Label(\"Open Today\", systemImage: \"chevron.right.circle\")"))
    }

    func testFallbackProjectBoardWindowUsesTodayLaunchRecoveryView() throws {
        let source = try readLaunchRecoveryAppShellSource()

        XCTAssertTrue(source.contains("private struct ProjectBoardFallbackRootView: View"))
        XCTAssertTrue(source.contains("if SuisuiLaunchRecoveryEnvironment.isEnabled"))
        XCTAssertTrue(source.contains("ProjectBoardView("))
        XCTAssertTrue(source.contains("struct ProjectBoardLaunchRecoveryView: View"))
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
        XCTAssertTrue(source.contains("SUISUI_PROJECT_BOARD_SELECTED_DESTINATION"))
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
        let source = try readPackageFile("Sources/SuisuiApp/SuisuiApp.swift")
        let recoveryStart = try XCTUnwrap(source.range(of: "private enum SuisuiLaunchRecoveryEnvironment"))
        let recoveryEnd = try XCTUnwrap(source.range(of: "private enum SuisuiWindowlessFallbackEnvironment"))
        let recoveryBlock = String(source[recoveryStart.lowerBound..<recoveryEnd.lowerBound])

        XCTAssertTrue(recoveryBlock.contains("private enum SuisuiLaunchRecoveryEnvironment"))
        XCTAssertTrue(recoveryBlock.contains("private static let flagName = \"SUISUI_LAUNCH_RECOVERY_MODE\""))
        XCTAssertTrue(recoveryBlock.contains("return environment[flagName] == \"1\""))
        XCTAssertFalse(recoveryBlock.contains("environment[\"SUISUI_DISABLE_KEYCHAIN_SECRET_STORE\"] == \"1\""))
        XCTAssertFalse(recoveryBlock.contains("environment[\"SUISUI_DATABASE_PATH\"] != nil"))
        XCTAssertTrue(source.contains("if SuisuiLaunchRecoveryEnvironment.isEnabled"))
        XCTAssertTrue(source.contains("self.createFallbackProjectBoardWindow()"))
    }

    func testIsolatedDatabaseLaunchesUseFullBoardFallbackWithoutRecoveryMode() throws {
        let source = try readPackageFile("Sources/SuisuiApp/SuisuiApp.swift")

        XCTAssertTrue(source.contains("private enum SuisuiWindowlessFallbackEnvironment"))
        XCTAssertTrue(source.contains("static var shouldCreateDirectFallbackWindow: Bool"))
        XCTAssertTrue(source.contains("static var shouldForceProjectBoardFallback: Bool"))
        XCTAssertTrue(source.contains("private static let forceFallbackFlagName = \"SUISUI_FORCE_PROJECT_BOARD_FALLBACK\""))
        XCTAssertTrue(source.contains("private static let disableFallbackFlagName = \"SUISUI_DISABLE_PROJECT_BOARD_FALLBACK\""))
        XCTAssertTrue(source.contains("guard environment[disableFallbackFlagName] != \"1\" else"))
        XCTAssertTrue(source.contains("return SuisuiLaunchRecoveryEnvironment.isEnabled\n            || environment[\"SUISUI_DATABASE_PATH\"] != nil"))
        XCTAssertTrue(source.contains("|| shouldForceProjectBoardFallback"))
        XCTAssertTrue(source.contains("guard SuisuiWindowlessFallbackEnvironment.shouldForceProjectBoardFallback || visibleProjectBoardWindows.isEmpty else"))
        XCTAssertTrue(source.contains("if SuisuiWindowlessFallbackEnvironment.shouldCreateDirectFallbackWindow"))
        XCTAssertTrue(source.contains("taskAutomationSettings: AppRuntimeFactory.loadTaskAutoExecutionSettings"))
        XCTAssertTrue(source.contains("window.occlusionState.contains(.visible)"))
    }

    func testRuntimeWorkflowSmokesUseNormalProjectBoardRoute() throws {
        let todaySmoke = try readPackageFile("script/check_runtime_today_complete_smoke.sh")
        let inboxSmoke = try readPackageFile("script/check_runtime_inbox_triage_smoke.sh")
        let runtimeCRUDSmoke = try readPackageFile("script/check_runtime_accessible_crud_smoke.sh")
        let screenshotCapture = try readPackageFile("script/capture_ui_evidence.sh")

        XCTAssertFalse(todaySmoke.contains("SUISUI_LAUNCH_RECOVERY_MODE"))
        XCTAssertFalse(inboxSmoke.contains("SUISUI_LAUNCH_RECOVERY_MODE"))
        XCTAssertFalse(runtimeCRUDSmoke.contains("SUISUI_LAUNCH_RECOVERY_MODE"))
        XCTAssertFalse(runtimeCRUDSmoke.contains("SUISUI_RUNTIME_CRUD_RECOVERY_MODE"))
        XCTAssertFalse(screenshotCapture.contains("SUISUI_LAUNCH_RECOVERY_MODE"))
        XCTAssertFalse(screenshotCapture.contains("SUISUI_FORCE_PROJECT_BOARD_FALLBACK"))
        XCTAssertFalse(screenshotCapture.contains("SUISUI_UI_EVIDENCE_RECOVERY_MODE"))
        XCTAssertTrue(todaySmoke.contains("HOME=\"$runtime_home\""))
        XCTAssertTrue(inboxSmoke.contains("HOME=\"$runtime_home\""))
        XCTAssertTrue(runtimeCRUDSmoke.contains("HOME=\"$runtime_home\""))
        XCTAssertTrue(todaySmoke.contains("/usr/bin/env -i"))
        XCTAssertTrue(inboxSmoke.contains("/usr/bin/env -i"))
        XCTAssertTrue(runtimeCRUDSmoke.contains("/usr/bin/env -i"))
        XCTAssertTrue(screenshotCapture.contains("/usr/bin/env -i"))
        XCTAssertTrue(screenshotCapture.contains("HOME=$EVIDENCE_HOME"))
        XCTAssertTrue(screenshotCapture.contains("CFFIXED_USER_HOME=$EVIDENCE_HOME"))
        XCTAssertTrue(todaySmoke.contains("ax_wait_for_owned_app_pid"))
        XCTAssertTrue(inboxSmoke.contains("ax_wait_for_owned_app_pid"))
        XCTAssertTrue(runtimeCRUDSmoke.contains("ax_wait_for_owned_app_pid"))
        XCTAssertTrue(screenshotCapture.contains("ax_wait_for_owned_app_pid"))
        XCTAssertTrue(screenshotCapture.contains("--p0-workflows"))
        XCTAssertTrue(screenshotCapture.contains("--schedule-cockpit"))
        XCTAssertTrue(screenshotCapture.contains("--done-analytics"))
        XCTAssertTrue(screenshotCapture.contains("if [[ \"$P0_WORKFLOWS\" == \"1\" ]]"))
        XCTAssertTrue(screenshotCapture.contains("EVIDENCE_LOCALES=(\"english\" \"japanese\")"))
        XCTAssertTrue(screenshotCapture.contains("SUISUI_LANGUAGE_PREFERENCE=$EVIDENCE_LOCALE"))
        XCTAssertTrue(screenshotCapture.contains("SUISUI_PROJECT_BOARD_SELECTED_DESTINATION"))
        XCTAssertTrue(screenshotCapture.contains("\"$AX_MARKER_CHECKER\" \"$APP_NAME\" \"$identifier\" \"$text\" \"$EVIDENCE_APP_PID\""))
    }

    func testTodayProductionRouteSmokeDoesNotUseLaunchRecoveryAndChecksRealBoardMarkers() throws {
        let source = try readPackageFile("script/check_runtime_today_production_route_smoke.sh")

        XCTAssertFalse(source.contains("SUISUI_LAUNCH_RECOVERY_MODE="))
        XCTAssertTrue(source.contains("SUISUI_PROJECT_BOARD_SELECTED_DESTINATION=\"today\""))
        // The marker waiter is deliberately generic: the production smoke must
        // exercise both concrete markers through that helper, not duplicate it.
        XCTAssertTrue(source.contains("wait_for_marker_until()"))
        XCTAssertTrue(source.contains("wait_for_marker_until \"project-board-command-palette\" \"\" \"$case_deadline\""))
        XCTAssertTrue(source.contains("wait_for_marker_until \"today-workflow\" \"$expected_today_label\" \"$case_deadline\""))
        XCTAssertTrue(source.contains("RUNTIME_TIMEOUT_SECONDS=\"${SUISUI_RUNTIME_TODAY_PRODUCTION_ROUTE_TIMEOUT_SECONDS:-30}\""))
        XCTAssertFalse(source.contains("RUNTIME_TIMEOUT_SECONDS=\"${SUISUI_RUNTIME_TODAY_PRODUCTION_ROUTE_TIMEOUT_SECONDS:-10}\""))
        XCTAssertTrue(source.contains("SUISUI_LANGUAGE_PREFERENCE=\"$locale\""))
        XCTAssertTrue(source.contains("LOCALES=(\"english\" \"japanese\")"))
        XCTAssertTrue(source.contains("locale_label_for"))
        XCTAssertTrue(source.contains("expected_today_label_for"))
        XCTAssertTrue(source.contains("ax_wait_for_ax_identifier \"$APP_NAME\" \"$marker\" 1 \"$ROOT_DIR\" \"$probe_file\" \"$required_text\" \"$app_pid\""))
    }

    func testDeadlineWatcherStaysOutOfEvidenceHarnessLaunches() throws {
        let source = try readPackageFile("Sources/SuisuiApp/Composition/DeadlineWatcherRuntime.swift")

        XCTAssertTrue(source.contains("bundleIdentifier: String? = Bundle.main.bundleIdentifier"))
        XCTAssertTrue(source.contains("SUISUI_DATABASE_PATH"))
        XCTAssertTrue(source.contains("SUISUI_LAUNCH_RECOVERY_MODE"))
        XCTAssertTrue(source.contains("SUISUI_FORCE_PROJECT_BOARD_FALLBACK"))
        XCTAssertTrue(source.contains("SUISUI_UI_EVIDENCE_RECOVERY_MODE"))
        XCTAssertTrue(source.contains("SUISUI_RUNTIME_CRUD_RECOVERY_MODE"))
        XCTAssertTrue(source.contains("SUISUI_LAYOUT_STABILITY_RECOVERY_MODE"))
        XCTAssertTrue(source.contains("SUISUI_OPEN_SETTINGS_ON_LAUNCH"))
        XCTAssertTrue(source.contains("SUISUI_OPEN_VOICE_COMMAND_ON_LAUNCH"))
        XCTAssertTrue(source.contains("SUISUI_RUNTIME_DEVELOPMENT_PR_SMOKE_BOOKMARK"))
        XCTAssertTrue(source.contains("key == \"SUISUI_DATABASE_PATH\" || value == \"1\""))
    }

    func testLaunchVerificationWindowGroupUsesLaunchRecoveryView() throws {
        let source = try readLaunchRecoveryAppShellSource()

        XCTAssertTrue(source.contains("if SuisuiLaunchRecoveryEnvironment.isEnabled {"))
        XCTAssertTrue(source.contains("ProjectBoardLaunchRecoveryView("))
        XCTAssertTrue(source.contains("ProjectBoardView("))
        XCTAssertTrue(source.contains("case .schedule:\n            ScheduleWorkflowView(viewModel: viewModel)"))
        XCTAssertTrue(source.contains("ProjectBoardRuntimeCRUDRecoveryView("))
        XCTAssertTrue(source.contains("ProjectBoardRuntimeCRUDRecoveryEnvironment.isEnabled"))
        XCTAssertTrue(source.contains("ProjectBoardUIEvidenceRecoveryEnvironment.isEnabled"))
        XCTAssertTrue(source.contains("private static let flagName = \"SUISUI_UI_EVIDENCE_RECOVERY_MODE\""))
        XCTAssertTrue(source.contains("ProjectBoardUIEvidenceProjectsOverviewRecoveryView("))
        XCTAssertTrue(source.contains("private static let flagName = \"SUISUI_RUNTIME_CRUD_RECOVERY_MODE\""))
        XCTAssertTrue(source.contains("ProjectBoardLayoutStabilityRecoveryView("))
        XCTAssertTrue(source.contains("ProjectBoardLayoutStabilityRecoveryEnvironment.isEnabled"))
        XCTAssertTrue(source.contains("private static let flagName = \"SUISUI_LAYOUT_STABILITY_RECOVERY_MODE\""))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-board-header-bar\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-board-detail\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-board-sidebar\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-board-sidebar-toggle\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"sidebar-destination-inbox\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"sidebar-destination-today\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-board-settings-link\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-board-voice-command\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"task-status-move-controls\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"task-inspector-apply-suggestion\")"))
        XCTAssertTrue(source.contains("case .projects"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"projects-portfolio-overview\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"sidebar-destination-projects\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-board-add-project\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-header-add-task\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"inline-task-title\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"approved-execution-receipt\")"))
        XCTAssertTrue(source.contains("case schedule"))
        XCTAssertTrue(source.contains("case done"))
        XCTAssertTrue(source.contains("case .project(let projectID):"))
    }

    func testWorkflowRootAccessibilityKeepsNestedLaunchRecoveryIdentifiers() throws {
        let source = try readProjectWorkflowSources()

        XCTAssertTrue(source.contains(".accessibilityElement(children: .contain)\n        .accessibilityIdentifier(\"today-workflow\")"))
        XCTAssertTrue(source.contains(".accessibilityElement(children: .contain)\n        .accessibilityIdentifier(\"inbox-workflow\")"))
        XCTAssertTrue(source.contains(".accessibilityElement(children: .contain)\n        .accessibilityIdentifier(\"schedule-workflow\")"))
        XCTAssertTrue(source.contains(".accessibilityElement(children: .contain)\n        .accessibilityIdentifier(\"catch-up-workflow\")"))
        XCTAssertTrue(source.contains(".accessibilityElement(children: .contain)\n        .accessibilityIdentifier(\"done-workflow\")"))
        XCTAssertTrue(source.contains(".accessibilityElement(children: .contain)\n        .accessibilityIdentifier(\"assistant-queue-workflow\")"))
    }

    func testProjectBoardOpensOnLaunch() throws {
        let source = try readPackageFile("Sources/SuisuiApp/SuisuiApp.swift")

        XCTAssertTrue(source.contains("WindowGroup(\"Suisui\", id: \"project-board\")"))

        let boardWindow = try XCTUnwrap(source.range(of: "WindowGroup(\"Suisui\", id: \"project-board\")"))
        let menuBar = try XCTUnwrap(source.range(of: "MenuBarExtraLabel(controller: menuBarController)"))
        XCTAssertLessThan(boardWindow.lowerBound, menuBar.lowerBound)
    }

    func testProjectBoardMultiWindowBoundaryUsesIndependentViewModelsAndSceneRoutePersistence() throws {
        let appSource = try readPackageFile("Sources/SuisuiApp/SuisuiApp.swift")
        let boardSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardView.swift")
        let coordinatorSource = try readPackageFile("Sources/SuisuiApp/Composition/ProjectBoardSceneCoordinator.swift")

        XCTAssertTrue(appSource.contains("WindowGroup(\"Suisui\", id: \"project-board\")"))
        XCTAssertTrue(appSource.contains("taskAutomationSettings: { settingsViewModel.settings.taskAutoExecution }"))
        XCTAssertTrue(appSource.contains("appSettings: { settingsViewModel.settings }"))
        XCTAssertTrue(appSource.contains("#selector(NSWindow.newWindowForTab(_:))"))
        XCTAssertTrue(appSource.contains("New Suisui Window"))
        XCTAssertTrue(boardSource.contains("@StateObject private var viewModel: ProjectBoardViewModel"))
        XCTAssertTrue(boardSource.contains("let taskAutomationSettings: () -> TaskAutoExecutionSettings"))
        XCTAssertTrue(boardSource.contains("let appSettings: () -> AppSettings"))
        XCTAssertTrue(appSource.contains("@SceneStorage(ProjectBoardScenePersistence.sceneIDStorageKey)"))
        XCTAssertTrue(boardSource.contains("@SceneStorage(ProjectBoardScenePersistence.routeStorageKey)"))
        XCTAssertTrue(boardSource.contains("@AppStorage(ProjectBoardSelectionPersistence.storageKey)"))
        XCTAssertTrue(boardSource.contains("ProjectBoardRouteCodec.resolution("))
        XCTAssertTrue(boardSource.contains("ProjectBoardRouteCodec.rawValue(for:"))
        XCTAssertTrue(boardSource.contains("@State private var selectedDestination: ProjectBoardSidebarDestination? = .today"))
        XCTAssertTrue(coordinatorSource.contains("@MainActor"))
        XCTAssertTrue(coordinatorSource.contains("ProjectBoardSceneNavigationState"))
        XCTAssertTrue(coordinatorSource.contains("consumeNext(for: sceneID)"))
    }

    private func readPackageFile(_ relativePath: String) throws -> String {
        let url = packageRoot().appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func functionSource(named name: String, in script: String) throws -> String {
        let start = try XCTUnwrap(script.range(of: "\(name)() {"))
        let tail = script[start.upperBound...]
        let end = try XCTUnwrap(tail.range(of: "\n}"))
        return String(script[start.lowerBound..<end.upperBound])
    }

    private func readLaunchRecoveryAppShellSource() throws -> String {
        try [
            readPackageFile("Sources/SuisuiApp/SuisuiApp.swift"),
            readPackageFile("Sources/SuisuiApp/Views/ProjectBoardLaunchRecoveryViews.swift")
        ].joined(separator: "\n\n")
    }

    private func readProjectWorkflowSources() throws -> String {
        try [
            "Sources/SuisuiApp/Views/ProjectWorkflowViews.swift",
            "Sources/SuisuiApp/Views/ProjectWorkflowSharedViews.swift",
            "Sources/SuisuiApp/Views/ProjectWorkflowTodayView.swift",
            "Sources/SuisuiApp/Views/ProjectWorkflowCatchUpView.swift",
            "Sources/SuisuiApp/Views/ProjectWorkflowScheduleView.swift",
            "Sources/SuisuiApp/Views/ProjectWorkflowDoneView.swift",
            "Sources/SuisuiApp/Views/ProjectWorkflowInboxView.swift",
            "Sources/SuisuiApp/Views/ProjectWorkflowAssistantQueueView.swift"
        ]
        .map { try readPackageFile($0) }
        .joined(separator: "\n")
    }

    private func readRuntimeCompositionSources() throws -> String {
        try [
            "Sources/SuisuiApp/SuisuiApp.swift",
            "Sources/SuisuiApp/Composition/AppRuntimeFactory.swift",
            "Sources/SuisuiApp/Composition/ProjectBoardRuntimeFactory.swift",
            "Sources/SuisuiApp/Composition/RuntimeToolCompositionFactory.swift",
            "Sources/SuisuiApp/Composition/SettingsRuntimeFactory.swift",
            "Sources/SuisuiApp/Composition/GoogleCalendarRuntimeCompositionFactory.swift",
            "Sources/SuisuiApp/Composition/VoiceRuntimeFactory.swift",
            "Sources/SuisuiApp/Composition/MenuBarRuntimeFactory.swift"
        ]
        .map { try readPackageFile($0) }
        .joined(separator: "\n")
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }
}
