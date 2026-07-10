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
        XCTAssertTrue(script.contains("\"$APP_BINARY\" -ApplePersistenceIgnoreState YES >/dev/null 2>&1 &"))
        XCTAssertFalse(script.contains("/usr/bin/osascript -e \"tell application \\\"$APP_NAME\\\" to activate\" >/dev/null 2>&1 || true"))
    }

    func testVerifyModeUsesNormalProjectBoardWithoutRecoveryFlags() throws {
        let script = try readPackageFile("script/build_and_run.sh")

        XCTAssertTrue(script.contains("SOLOPM_VERIFY_TIMEOUT_SECONDS"))
        XCTAssertTrue(script.contains("PROJECT_BOARD_WINDOW_NAME=\"${SOLOPM_PROJECT_BOARD_WINDOW_NAME:-SoloPM}\""))
        XCTAssertTrue(script.contains("AX_HELPERS=\"${AX_HELPERS:-$ROOT_DIR/script/ui_accessibility_smoke_helpers.sh}\""))
        XCTAssertTrue(script.contains("/usr/bin/env -i"))
        XCTAssertTrue(script.contains("HOME=\"$VERIFY_HOME\""))
        XCTAssertTrue(script.contains("CFFIXED_USER_HOME=\"$VERIFY_CFFIXED_USER_HOME\""))
        XCTAssertTrue(script.contains("SOLOPM_DATABASE_PATH=\"$VERIFY_DATABASE_PATH\""))
        XCTAssertTrue(script.contains("SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1"))
        XCTAssertTrue(script.contains("launch_verify_process \"today\"\n    BOOTSTRAP_LAUNCH_PID=\"$VERIFY_LAUNCH_PID\""))
        XCTAssertTrue(script.contains("terminate_owned_verify_process \"bootstrap\" \"$BOOTSTRAP_LAUNCH_PID\" \"$BOOTSTRAP_APP_PID\""))
        XCTAssertTrue(script.contains("VERIFY_PROJECT_ID=\"$(fetch_verify_project_id)\""))
        XCTAssertTrue(script.contains("launch_verify_process \"project:$VERIFY_PROJECT_ID\"\n    APP_LAUNCH_PID=\"$VERIFY_LAUNCH_PID\""))
        XCTAssertTrue(script.contains("SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION=\"$selected_destination\""))
        XCTAssertTrue(script.contains("VERIFY_LAUNCH_PID=\"$!\""))
        XCTAssertTrue(script.contains("ax_wait_for_owned_app_pid \"$launch_pid\" \"$APP_BINARY\""))
        XCTAssertTrue(script.contains("source_command = 'build-and-run-verify'"))
        XCTAssertTrue(script.contains("JOIN tasks AS t ON t.project_id = p.id"))
        XCTAssertTrue(script.contains("INSERT INTO projects"))
        XCTAssertTrue(script.contains("INSERT INTO tasks"))
        XCTAssertTrue(script.contains("due_at=\"2026-01-01T12:00:00+00:00\""))
        XCTAssertTrue(script.contains("-ApplePersistenceIgnoreState YES"))
        XCTAssertTrue(script.contains("wait_for_project_board_window"))
        XCTAssertTrue(script.contains("wait_for_project_board_marker"))
        XCTAssertTrue(script.contains("project-board-header-bar"))
        XCTAssertTrue(script.contains("project-board-sidebar"))
        XCTAssertTrue(script.contains("project-board-detail"))
        XCTAssertTrue(script.contains("BLOCKER: Project Board window was not visible within"))
        XCTAssertFalse(script.contains("SOLOPM_LAUNCH_RECOVERY_MODE"))
        XCTAssertFalse(script.contains("SOLOPM_FORCE_PROJECT_BOARD_FALLBACK"))
        XCTAssertFalse(script.contains("SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION=\"today\""))
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
        XCTAssertTrue(helpers.contains("local marker_checker=\"${AX_MARKER_HELPER_EXECUTABLE:-}\""))
        XCTAssertTrue(helpers.contains("if [[ -n \"$marker_checker\" && -x \"$marker_checker\" ]]"))
        XCTAssertTrue(script.contains("ax_wait_for_pid_owned_process \"$APP_NAME\" \"$APP_PID\" \"$VERIFY_TIMEOUT_SECONDS\" \"$APP_BINARY\""))
        XCTAssertTrue(script.contains("ax_wait_for_pid_owned_window \"$APP_NAME\" \"$APP_PID\" \"$PROJECT_BOARD_WINDOW_NAME\" \"$VERIFY_TIMEOUT_SECONDS\" \"$window_diagnostic_file\" \"$APP_BINARY\""))
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

        XCTAssertTrue(documentation.contains("SOLOPM_LAUNCH_RECOVERY_MODE=1"))
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

        XCTAssertTrue(script.contains("VERIFY_TIMEOUT_SECONDS=\"${SOLOPM_VERIFY_TIMEOUT_SECONDS:-30}\""))
        XCTAssertFalse(script.contains("VERIFY_TIMEOUT_SECONDS=\"${SOLOPM_VERIFY_TIMEOUT_SECONDS:-12}\""))
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
        let source = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

        XCTAssertTrue(script.contains("<key>NSQuitAlwaysKeepsWindows</key>"))
        XCTAssertTrue(script.contains("<false/>"))
        XCTAssertTrue(script.contains("-ApplePersistenceIgnoreState YES"))
        XCTAssertTrue(source.contains("shouldSaveApplicationState"))
        XCTAssertTrue(source.contains("shouldRestoreApplicationState"))
        XCTAssertTrue(source.contains("return false"))
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
        let source = try readRuntimeCompositionSources()

        XCTAssertTrue(source.contains("SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE"))
        XCTAssertTrue(source.contains("LaunchVerificationSecretStore"))
        XCTAssertTrue(source.contains("return nil"))
    }

    func testRuntimeFactorySharesSecretStoreAcrossProviderSurfaces() throws {
        let source = try readRuntimeCompositionSources()

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
        XCTAssertTrue(source.contains("static let maxWindowGroupRestoreAttempts = 3"))
        XCTAssertTrue(source.contains("projectBoardWindowRestoreAttempts < SoloPMWindowlessFallbackEnvironment.maxWindowGroupRestoreAttempts"))
        XCTAssertTrue(source.contains("didRequestWindow ? 0.75 : 0.25"))
        XCTAssertTrue(source.contains("performNewProjectBoardWindowMenuItem()"))
        XCTAssertTrue(source.contains("New SoloPM Window"))
        XCTAssertTrue(source.contains("performActionForItem(at: itemIndex)"))
        XCTAssertTrue(source.contains("visibleProjectBoardWindows"))
        XCTAssertTrue(source.contains("fallbackProjectBoardWindow"))
        XCTAssertTrue(source.contains("rootView: ProjectBoardFallbackRootView("))
        XCTAssertTrue(source.contains("ProjectBoardWindowRootView(settingsViewModel: settingsViewModel)"))
        XCTAssertTrue(source.contains("makeAppSettingsViewModel(refreshProviderSecretStatusesOnInit: false)"))
        XCTAssertTrue(source.contains("settingsViewModel.refreshProviderSecretStatuses()"))
        XCTAssertTrue(source.contains("@State private var viewModel: ProjectBoardViewModel?"))
        XCTAssertTrue(source.contains("@State private var isProjectBoardReady = false"))
        XCTAssertTrue(source.contains("ProjectBoardFallbackLoadingView()"))
        XCTAssertTrue(source.contains("let runtime = await AppRuntimeFactory.prepareProjectBoardRuntimeBundle()"))
        XCTAssertTrue(source.contains("AppRuntimeFactory.makeProjectBoardViewModel(runtime: runtime)"))
        XCTAssertTrue(source.contains("await MainActor.run"))
        XCTAssertTrue(source.contains("ProjectBoardLaunchHydrationDelay.nanoseconds"))
        XCTAssertTrue(source.contains("static let nanoseconds: UInt64 = 150_000_000"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"project-board-fallback-loading\")"))
        XCTAssertTrue(source.contains("makeKeyAndOrderFront(nil)"))
        XCTAssertTrue(source.contains("#selector(NSWindow.newWindowForTab(_:))"))
        XCTAssertTrue(source.contains("return false"))
    }

    func testFallbackProjectBoardWindowUsesTodayLaunchRecoveryView() throws {
        let source = try readLaunchRecoveryAppShellSource()

        XCTAssertTrue(source.contains("private struct ProjectBoardFallbackRootView: View"))
        XCTAssertTrue(source.contains("if SoloPMLaunchRecoveryEnvironment.isEnabled"))
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

    func testRuntimeWorkflowSmokesUseNormalProjectBoardRoute() throws {
        let todaySmoke = try readPackageFile("script/check_runtime_today_complete_smoke.sh")
        let inboxSmoke = try readPackageFile("script/check_runtime_inbox_triage_smoke.sh")
        let runtimeCRUDSmoke = try readPackageFile("script/check_runtime_accessible_crud_smoke.sh")
        let screenshotCapture = try readPackageFile("script/capture_ui_evidence.sh")

        XCTAssertFalse(todaySmoke.contains("SOLOPM_LAUNCH_RECOVERY_MODE"))
        XCTAssertFalse(inboxSmoke.contains("SOLOPM_LAUNCH_RECOVERY_MODE"))
        XCTAssertFalse(runtimeCRUDSmoke.contains("SOLOPM_LAUNCH_RECOVERY_MODE"))
        XCTAssertFalse(runtimeCRUDSmoke.contains("SOLOPM_RUNTIME_CRUD_RECOVERY_MODE"))
        XCTAssertFalse(screenshotCapture.contains("SOLOPM_LAUNCH_RECOVERY_MODE"))
        XCTAssertFalse(screenshotCapture.contains("SOLOPM_FORCE_PROJECT_BOARD_FALLBACK"))
        XCTAssertFalse(screenshotCapture.contains("SOLOPM_UI_EVIDENCE_RECOVERY_MODE"))
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
        XCTAssertTrue(screenshotCapture.contains("SOLOPM_LANGUAGE_PREFERENCE=$EVIDENCE_LOCALE"))
        XCTAssertTrue(screenshotCapture.contains("SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION"))
        XCTAssertTrue(screenshotCapture.contains("\"$AX_MARKER_CHECKER\" \"$APP_NAME\" \"$identifier\" \"$text\" \"$EVIDENCE_APP_PID\""))
    }

    func testTodayProductionRouteSmokeDoesNotUseLaunchRecoveryAndChecksRealBoardMarkers() throws {
        let source = try readPackageFile("script/check_runtime_today_production_route_smoke.sh")

        XCTAssertFalse(source.contains("SOLOPM_LAUNCH_RECOVERY_MODE="))
        XCTAssertTrue(source.contains("SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION=\"today\""))
        // The marker waiter is deliberately generic: the production smoke must
        // exercise both concrete markers through that helper, not duplicate it.
        XCTAssertTrue(source.contains("wait_for_marker_until()"))
        XCTAssertTrue(source.contains("wait_for_marker_until \"project-board-header-bar\" \"\" \"$case_deadline\""))
        XCTAssertTrue(source.contains("wait_for_marker_until \"today-workflow\" \"$expected_today_label\" \"$case_deadline\""))
        XCTAssertTrue(source.contains("RUNTIME_TIMEOUT_SECONDS=\"${SOLOPM_RUNTIME_TODAY_PRODUCTION_ROUTE_TIMEOUT_SECONDS:-10}\""))
        XCTAssertTrue(source.contains("SOLOPM_LANGUAGE_PREFERENCE=\"$locale\""))
        XCTAssertTrue(source.contains("LOCALES=(\"english\" \"japanese\")"))
        XCTAssertTrue(source.contains("locale_label_for"))
        XCTAssertTrue(source.contains("expected_today_label_for"))
        XCTAssertTrue(source.contains("ax_wait_for_ax_identifier \"$APP_NAME\" \"$marker\" 1 \"$ROOT_DIR\" \"$probe_file\" \"$required_text\" \"$app_pid\""))
    }

    func testDeadlineWatcherStaysOutOfEvidenceHarnessLaunches() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Composition/DeadlineWatcherRuntime.swift")

        XCTAssertTrue(source.contains("bundleIdentifier: String? = Bundle.main.bundleIdentifier"))
        XCTAssertTrue(source.contains("SOLOPM_DATABASE_PATH"))
        XCTAssertTrue(source.contains("SOLOPM_LAUNCH_RECOVERY_MODE"))
        XCTAssertTrue(source.contains("SOLOPM_FORCE_PROJECT_BOARD_FALLBACK"))
        XCTAssertTrue(source.contains("SOLOPM_UI_EVIDENCE_RECOVERY_MODE"))
        XCTAssertTrue(source.contains("SOLOPM_RUNTIME_CRUD_RECOVERY_MODE"))
        XCTAssertTrue(source.contains("SOLOPM_LAYOUT_STABILITY_RECOVERY_MODE"))
        XCTAssertTrue(source.contains("SOLOPM_OPEN_SETTINGS_ON_LAUNCH"))
        XCTAssertTrue(source.contains("SOLOPM_OPEN_VOICE_COMMAND_ON_LAUNCH"))
        XCTAssertTrue(source.contains("SOLOPM_RUNTIME_DEVELOPMENT_PR_SMOKE_BOOKMARK"))
        XCTAssertTrue(source.contains("key == \"SOLOPM_DATABASE_PATH\" || value == \"1\""))
    }

    func testLaunchVerificationWindowGroupUsesLaunchRecoveryView() throws {
        let source = try readLaunchRecoveryAppShellSource()

        XCTAssertTrue(source.contains("if SoloPMLaunchRecoveryEnvironment.isEnabled {"))
        XCTAssertTrue(source.contains("ProjectBoardLaunchRecoveryView("))
        XCTAssertTrue(source.contains("ProjectBoardView("))
        XCTAssertTrue(source.contains("case .schedule:\n            ScheduleWorkflowView(viewModel: viewModel)"))
        XCTAssertTrue(source.contains("ProjectBoardRuntimeCRUDRecoveryView("))
        XCTAssertTrue(source.contains("ProjectBoardRuntimeCRUDRecoveryEnvironment.isEnabled"))
        XCTAssertTrue(source.contains("ProjectBoardUIEvidenceRecoveryEnvironment.isEnabled"))
        XCTAssertTrue(source.contains("private static let flagName = \"SOLOPM_UI_EVIDENCE_RECOVERY_MODE\""))
        XCTAssertTrue(source.contains("ProjectBoardUIEvidenceProjectsOverviewRecoveryView("))
        XCTAssertTrue(source.contains("private static let flagName = \"SOLOPM_RUNTIME_CRUD_RECOVERY_MODE\""))
        XCTAssertTrue(source.contains("ProjectBoardLayoutStabilityRecoveryView("))
        XCTAssertTrue(source.contains("ProjectBoardLayoutStabilityRecoveryEnvironment.isEnabled"))
        XCTAssertTrue(source.contains("private static let flagName = \"SOLOPM_LAYOUT_STABILITY_RECOVERY_MODE\""))
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
        let source = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

        XCTAssertTrue(source.contains("WindowGroup(\"SoloPM\", id: \"project-board\")"))

        let boardWindow = try XCTUnwrap(source.range(of: "WindowGroup(\"SoloPM\", id: \"project-board\")"))
        let menuBar = try XCTUnwrap(source.range(of: "MenuBarExtraLabel(controller: menuBarController)"))
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

    private func readLaunchRecoveryAppShellSource() throws -> String {
        try [
            readPackageFile("Sources/SoloPMApp/SoloPMApp.swift"),
            readPackageFile("Sources/SoloPMApp/Views/ProjectBoardLaunchRecoveryViews.swift")
        ].joined(separator: "\n\n")
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

    private func readRuntimeCompositionSources() throws -> String {
        try [
            "Sources/SoloPMApp/SoloPMApp.swift",
            "Sources/SoloPMApp/Composition/AppRuntimeFactory.swift",
            "Sources/SoloPMApp/Composition/ProjectBoardRuntimeFactory.swift",
            "Sources/SoloPMApp/Composition/RuntimeToolCompositionFactory.swift",
            "Sources/SoloPMApp/Composition/SettingsRuntimeFactory.swift",
            "Sources/SoloPMApp/Composition/GoogleCalendarRuntimeCompositionFactory.swift",
            "Sources/SoloPMApp/Composition/VoiceRuntimeFactory.swift",
            "Sources/SoloPMApp/Composition/MenuBarRuntimeFactory.swift"
        ]
        .map { try readPackageFile($0) }
        .joined(separator: "\n")
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }
}
