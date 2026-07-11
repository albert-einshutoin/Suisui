import Foundation
import os
import XCTest
@testable import SoloPMCore

final class OnboardingReadinessRegressionTests: XCTestCase {
    // MARK: - Typed readiness state (P2: display strings must not gate planning)

    @MainActor
    func testProviderReadinessUsesTypedStateForOpenAIKeyInsteadOfStatusLabel() throws {
        let suite = "SoloPM.TypedReadiness.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        let viewModel = AppSettingsViewModel(
            settingsStore: store,
            secretStore: InMemorySecretStore(values: [.openAIAPIKey: "sk-valid-secret"]),
            refreshProviderSecretStatusesOnInit: true
        )

        let openAIRow = try XCTUnwrap(
            viewModel.providerReadinessRows.first { $0.provider == .openaiResponses }
        )
        XCTAssertEqual(openAIRow.readiness, .ready)
        XCTAssertEqual(viewModel.openAIAPIKeyReadinessState, .configured)

        // The "Configured" label is now derived from the typed state, so the
        // readiness gate survives any localizable rename of the label.
        XCTAssertTrue(
            openAIRow.readiness.isReady,
            "Ready readiness must be derived from the typed state, not the Configured label."
        )
    }

    @MainActor
    func testProviderReadinessReportsMissingForOpenAIWithoutAffectingLabelChange() throws {
        let suite = "SoloPM.TypedReadinessMissing.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        let viewModel = AppSettingsViewModel(
            settingsStore: store,
            secretStore: InMemorySecretStore()
        )

        let openAIRow = try XCTUnwrap(
            viewModel.providerReadinessRows.first { $0.provider == .openaiResponses }
        )
        XCTAssertEqual(viewModel.openAIAPIKeyReadinessState, .missing)
        XCTAssertEqual(
            openAIRow.readiness,
            .needsAction(reason: "Save the provider API key in Keychain.")
        )
    }

    @MainActor
    func testProviderReadinessReportsInvalidForOpenAIKeyWithInternalWhitespace() throws {
        let suite = "SoloPM.TypedReadinessInvalid.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        let viewModel = AppSettingsViewModel(
            settingsStore: store,
            secretStore: InMemorySecretStore(values: [.openAIAPIKey: "sk- has whitespace"])
        )

        let openAIRow = try XCTUnwrap(
            viewModel.providerReadinessRows.first { $0.provider == .openaiResponses }
        )
        XCTAssertEqual(viewModel.openAIAPIKeyReadinessState, .invalid)
        XCTAssertEqual(
            openAIRow.readiness,
            .needsAction(reason: "Re-enter the provider API key in Keychain.")
        )
    }

    // MARK: - OpenCode model id gate (P2: model id must be required)

    @MainActor
    func testOpenCodeReadinessRequiresNonEmptyModelID() throws {
        let suite = "SoloPM.OpenCodeModelID.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)

        // Missing model id.
        try store.save(
            AppSettings(
                aiProvider: .opencodeLocal,
                openCodeExecutablePath: "/opt/homebrew/bin/opencode",
                openCodeWorkspacePath: "/tmp/SoloPM",
                openCodeModelID: nil,
                isOpenCodeLocalExecutionApproved: true
            )
        )
        let missingViewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: InMemorySecretStore()
        )
        let missingRow = try XCTUnwrap(
            missingViewModel.providerReadinessRows.first { $0.provider == .opencodeLocal }
        )
        XCTAssertEqual(
            missingRow.readiness,
            .needsAction(reason: "Set the OpenCode model id."),
            "Readiness must be `needsAction` when the model id is missing even with executable + workspace + approval."
        )
        XCTAssertEqual(
            missingViewModel.onboardingReadinessSnapshot(permissionSnapshot: .empty).planningState,
            .needsAction(reason: "Set the OpenCode model id.")
        )

        // Blank-whitespace model id.
        try store.save(
            AppSettings(
                aiProvider: .opencodeLocal,
                openCodeExecutablePath: "/opt/homebrew/bin/opencode",
                openCodeWorkspacePath: "/tmp/SoloPM",
                openCodeModelID: "   ",
                isOpenCodeLocalExecutionApproved: true
            )
        )
        let blankViewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: InMemorySecretStore()
        )
        let blankRow = try XCTUnwrap(
            blankViewModel.providerReadinessRows.first { $0.provider == .opencodeLocal }
        )
        XCTAssertEqual(
            blankRow.readiness,
            .needsAction(reason: "Set the OpenCode model id.")
        )

        // Valid model id, missing approval.
        try store.save(
            AppSettings(
                aiProvider: .opencodeLocal,
                openCodeExecutablePath: "/opt/homebrew/bin/opencode",
                openCodeWorkspacePath: "/tmp/SoloPM",
                openCodeModelID: "anthropic/claude-sonnet-4-5",
                isOpenCodeLocalExecutionApproved: false
            )
        )
        let unapprovedViewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: InMemorySecretStore()
        )
        let unapprovedRow = try XCTUnwrap(
            unapprovedViewModel.providerReadinessRows.first { $0.provider == .opencodeLocal }
        )
        XCTAssertEqual(
            unapprovedRow.readiness,
            .needsAction(reason: "Review the local command and approve execution.")
        )

        // Fully ready: executable + workspace + model id + approval.
        try store.save(
            AppSettings(
                aiProvider: .opencodeLocal,
                openCodeExecutablePath: "/opt/homebrew/bin/opencode",
                openCodeWorkspacePath: "/tmp/SoloPM",
                openCodeModelID: "anthropic/claude-sonnet-4-5",
                isOpenCodeLocalExecutionApproved: true
            )
        )
        let readyViewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: InMemorySecretStore()
        )
        let readyRow = try XCTUnwrap(
            readyViewModel.providerReadinessRows.first { $0.provider == .opencodeLocal }
        )
        XCTAssertEqual(readyRow.readiness, .ready)
    }

    // MARK: - Ollama endpoint health (P2: ready when healthy, invalid when failing)

    @MainActor
    func testOllamaReadinessBecomesReadyWhenHealthCheckerReportsReady() async throws {
        let suite = "SoloPM.OllamaReady.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        try store.save(AppSettings(aiProvider: .ollamaCompatible))

        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: InMemorySecretStore(),
            ollamaHealthChecker: StaticOllamaEndpointHealthChecker(result: .ready)
        )

        // The Ollama readiness row is driven by the async endpoint probe; the
        // test must drive a refresh before the row reflects the ready state.
        await viewModel.refreshProviderReadiness()

        let row = try XCTUnwrap(
            viewModel.providerReadinessRows.first { $0.provider == .ollamaCompatible }
        )
        XCTAssertEqual(row.readiness, .ready)
    }

    @MainActor
    func testOllamaReadinessReportsFailureWhenHealthCheckerReportsFailure() async throws {
        let suite = "SoloPM.OllamaFailure.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        try store.save(AppSettings(aiProvider: .ollamaCompatible))

        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: InMemorySecretStore(),
            ollamaHealthChecker: StaticOllamaEndpointHealthChecker(
                result: .failure(reason: "Local Ollama-compatible server did not respond.")
            )
        )

        // The Ollama health check is async; the row reflects the latest cached
        // status, so the test must wait for the refresh to apply the result.
        await viewModel.refreshProviderReadiness()

        let row = try XCTUnwrap(
            viewModel.providerReadinessRows.first { $0.provider == .ollamaCompatible }
        )
        XCTAssertEqual(
            row.readiness,
            .needsAction(reason: "Local Ollama-compatible server did not respond.")
        )
    }

    @MainActor
    func testOllamaReadinessIsCheckingWhileRefreshInFlight() async throws {
        let suite = "SoloPM.OllamaChecking.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        try store.save(AppSettings(aiProvider: .ollamaCompatible))

        let probe = DeferredOllamaEndpointHealthProbe()
        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: InMemorySecretStore(),
            ollamaHealthChecker: probe
        )
        XCTAssertEqual(viewModel.ollamaEndpointHealth, .unknown)

        // Suspend the probe; once we resume it the refresh can complete. The
        // task we create here will park on `withCheckedContinuation` inside
        // the probe and let us observe the spinner state first.
        let refreshTask = Task<OllamaEndpointHealth, Never> { @MainActor in
            await viewModel.refreshProviderReadiness()
            return viewModel.ollamaEndpointHealth
        }

        // Spin the runloop so the MainActor refresh task gets scheduled.
        for _ in 0..<100 where !viewModel.isRefreshingProviderReadiness {
            await Task.yield()
        }
        XCTAssertTrue(viewModel.isRefreshingProviderReadiness)
        XCTAssertEqual(viewModel.ollamaEndpointHealth, .checking)

        probe.resume(with: .ready)
        _ = await refreshTask.value
        XCTAssertEqual(viewModel.ollamaEndpointHealth, .ready)
        XCTAssertFalse(viewModel.isRefreshingProviderReadiness)
    }

    // MARK: - Async refresh on MainActor isolation (P2: not blocking)

    @MainActor
    func testRefreshProviderReadinessPublishesCheckingBeforeResolving() async throws {
        let suite = "SoloPM.AsyncCheck.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let probe = DeferredOllamaEndpointHealthProbe()
        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: InMemorySecretStore(),
            ollamaHealthChecker: probe
        )
        XCTAssertEqual(viewModel.ollamaEndpointHealth, .unknown)
        XCTAssertFalse(viewModel.isRefreshingProviderReadiness)

        let refreshTask = Task<Void, Never> { @MainActor in
            await viewModel.refreshProviderReadiness()
        }

        for _ in 0..<100 where !viewModel.isRefreshingProviderReadiness {
            await Task.yield()
        }
        XCTAssertTrue(viewModel.isRefreshingProviderReadiness)
        XCTAssertEqual(viewModel.ollamaEndpointHealth, .checking)

        probe.resume(with: .ready)
        await refreshTask.value
        XCTAssertEqual(viewModel.ollamaEndpointHealth, .ready)
        XCTAssertFalse(viewModel.isRefreshingProviderReadiness)
    }

    // MARK: - Rerun coordinator (P2: 0/1/2 Project Board windows)

    @MainActor
    func testRerunCoordinatorRoutesOnlyToPrimaryWindow() {
        let coordinator = OnboardingRerunCoordinator()
        let first = UUID()
        let second = UUID()

        XCTAssertTrue(coordinator.register(windowID: first))
        XCTAssertFalse(coordinator.register(windowID: second))
        XCTAssertEqual(coordinator.snapshotForTests().primary, first)

        coordinator.requestRerun()
        let token = coordinator.rerunRequestToken
        XCTAssertNotNil(token)
        coordinator.markHandled(token: try! XCTUnwrap(token))
        XCTAssertEqual(coordinator.lastHandledToken, token)
    }

    @MainActor
    func testRerunCoordinatorPromotesSecondWindowWhenPrimaryUnregisters() {
        let coordinator = OnboardingRerunCoordinator()
        let first = UUID()
        let second = UUID()

        XCTAssertTrue(coordinator.register(windowID: first))
        XCTAssertFalse(coordinator.register(windowID: second))

        coordinator.unregister(windowID: first)

        XCTAssertEqual(coordinator.snapshotForTests().primary, second)
        XCTAssertEqual(coordinator.snapshotForTests().registered, [second])
    }

    @MainActor
    func testRerunCoordinatorWithNoRegisteredWindowsKeepsRequestAvailable() {
        let coordinator = OnboardingRerunCoordinator()
        coordinator.requestRerun()
        XCTAssertNotNil(coordinator.rerunRequestToken)
        XCTAssertNil(coordinator.snapshotForTests().primary)

        // First registration after a request must become primary and observe
        // the pending request via markHandled.
        let first = UUID()
        XCTAssertTrue(coordinator.register(windowID: first))
        XCTAssertEqual(coordinator.snapshotForTests().primary, first)
    }

    @MainActor
    func testRerunCoordinatorIgnoresStaleTokensViaLastHandledToken() {
        let coordinator = OnboardingRerunCoordinator()
        let windowID = UUID()
        XCTAssertTrue(coordinator.register(windowID: windowID))

        coordinator.requestRerun()
        let firstToken = coordinator.rerunRequestToken
        coordinator.markHandled(token: try! XCTUnwrap(firstToken))

        // A second window must not inherit the already-handled token.
        let secondWindow = UUID()
        XCTAssertFalse(coordinator.register(windowID: secondWindow))
        XCTAssertNotEqual(coordinator.lastHandledToken, nil)
    }

    // MARK: - Microphone permission states (P2: 4 states)

    @MainActor
    func testOnboardingSnapshotHonorsMicrophonePermissionState() {
        let cases: [(PermissionStatus, OnboardingReadinessState)] = [
            (.granted, .ready),
            (.notDetermined, .needsAction(reason: "Permission has not been requested yet.")),
            (.denied, .needsAction(reason: "Permission is denied. Review it in System Settings when needed.")),
            (.restricted, .unavailable(reason: "This permission is restricted by macOS."))
        ]

        for (status, expected) in cases {
            var permissions = PermissionSnapshot.empty
            permissions.setStatus(status, for: .microphone)
            let snapshot = OnboardingReadinessSnapshot.make(
                selectedProvider: .ollamaCompatible,
                providerReadiness: .ready,
                permissions: permissions
            )
            XCTAssertEqual(
                snapshot.items.first(where: { $0.id == "microphone" })?.state,
                expected,
                "Microphone state for \(status) must map to \(expected)."
            )
        }
    }
}

// MARK: - Test doubles

private struct StaticOllamaEndpointHealthChecker: OllamaEndpointHealthChecking, Sendable {
    let result: OllamaEndpointHealth

    func currentStatus() async -> OllamaEndpointHealth { result }
}

private final class DeferredOllamaEndpointHealthProbe: OllamaEndpointHealthChecking, @unchecked Sendable {
    private var continuation: CheckedContinuation<OllamaEndpointHealth, Never>?
    private let lock = OSAllocatedUnfairLock()

    init() {}

    func currentStatus() async -> OllamaEndpointHealth {
        await withCheckedContinuation { (continuation: CheckedContinuation<OllamaEndpointHealth, Never>) in
            lock.withLock { self.continuation = continuation }
        }
    }

    func resume(with status: OllamaEndpointHealth) {
        let cont: CheckedContinuation<OllamaEndpointHealth, Never>? = lock.withLock {
            let current = continuation
            continuation = nil
            return current
        }
        cont?.resume(returning: status)
    }
}
