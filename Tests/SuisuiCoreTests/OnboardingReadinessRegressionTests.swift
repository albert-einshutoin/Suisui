import Foundation
import os
import XCTest
@testable import SuisuiCore

final class OnboardingReadinessRegressionTests: XCTestCase {
    // MARK: - Typed readiness state (P2: display strings must not gate planning)

    @MainActor
    func testProviderReadinessUsesTypedStateForOpenAIKeyInsteadOfStatusLabel() throws {
        let suite = "Suisui.TypedReadiness.\(UUID().uuidString)"
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
        let suite = "Suisui.TypedReadinessMissing.\(UUID().uuidString)"
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
        let suite = "Suisui.TypedReadinessInvalid.\(UUID().uuidString)"
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
        let suite = "Suisui.OpenCodeModelID.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)

        // Missing model id.
        try store.save(
            AppSettings(
                aiProvider: .opencodeLocal,
                openCodeExecutablePath: "/opt/homebrew/bin/opencode",
                openCodeWorkspacePath: "/tmp/Suisui",
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
                openCodeWorkspacePath: "/tmp/Suisui",
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
                openCodeWorkspacePath: "/tmp/Suisui",
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
                openCodeWorkspacePath: "/tmp/Suisui",
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
        let suite = "Suisui.OllamaReady.\(UUID().uuidString)"
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
        let suite = "Suisui.OllamaFailure.\(UUID().uuidString)"
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
        let suite = "Suisui.OllamaChecking.\(UUID().uuidString)"
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
        let suite = "Suisui.AsyncCheck.\(UUID().uuidString)"
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

    // MARK: - Window-consume API (P2-New1: pending rerun must drain on registration)

    @MainActor
    func testConsumePendingRerunReturnsNilWhenNotPrimary() {
        let coordinator = OnboardingRerunCoordinator()
        let first = UUID()
        let second = UUID()
        _ = coordinator.register(windowID: first)
        XCTAssertFalse(coordinator.register(windowID: second))
        coordinator.requestRerun()

        // Second window is not primary, so consume must refuse the token.
        XCTAssertNil(coordinator.consumePendingRerun(for: second))
        XCTAssertNil(coordinator.lastHandledToken)
    }

    @MainActor
    func testConsumePendingRerunDrainsTokenOnPrimaryRegistration() {
        let coordinator = OnboardingRerunCoordinator()
        // 0-window case: Settings fires the rerun before any window exists.
        coordinator.requestRerun()
        let firstToken = coordinator.rerunRequestToken
        XCTAssertNotNil(firstToken)

        let first = UUID()
        _ = coordinator.register(windowID: first)

        // The newly registered primary must drain the pending token atomically
        // so the onboarding sheet opens in this window.
        XCTAssertEqual(coordinator.consumePendingRerun(for: first), firstToken)
        XCTAssertEqual(coordinator.lastHandledToken, firstToken)
        // A second consume call must not re-open the sheet.
        XCTAssertNil(coordinator.consumePendingRerun(for: first))
    }

    @MainActor
    func testConsumePendingRerunDrainsAcrossPrimaryPromotion() {
        let coordinator = OnboardingRerunCoordinator()
        let first = UUID()
        let second = UUID()
        _ = coordinator.register(windowID: first)
        XCTAssertFalse(coordinator.register(windowID: second))

        // Primary window goes away; the second window is promoted.
        coordinator.unregister(windowID: first)
        XCTAssertEqual(coordinator.snapshotForTests().primary, second)

        // A new rerun must be consumable by the promoted primary.
        coordinator.requestRerun()
        let newToken = coordinator.rerunRequestToken
        XCTAssertEqual(coordinator.consumePendingRerun(for: second), newToken)
    }

    @MainActor
    func testConsumePendingRerunIgnoresStaleTokensAfterHandle() {
        let coordinator = OnboardingRerunCoordinator()
        let first = UUID()
        _ = coordinator.register(windowID: first)

        coordinator.requestRerun()
        _ = coordinator.consumePendingRerun(for: first)

        // A second window registers after the first primary already drained
        // the token. It must not be allowed to re-open the sheet.
        let second = UUID()
        _ = coordinator.register(windowID: second)
        XCTAssertNil(coordinator.consumePendingRerun(for: second))
    }

    // MARK: - Typed readiness direct from SecretStore (P2-New4)

    @MainActor
    func testClassifyAPIKeyValueMapsSecretStoreResultsDirectlyToTypedState() throws {
        XCTAssertEqual(
            AppSettingsViewModel.classifyAPIKeyValue("sk-valid-secret"),
            .configured
        )
        XCTAssertEqual(AppSettingsViewModel.classifyAPIKeyValue(""), .missing)
        XCTAssertEqual(AppSettingsViewModel.classifyAPIKeyValue(nil), .missing)
        XCTAssertEqual(
            AppSettingsViewModel.classifyAPIKeyValue("sk- has internal whitespace"),
            .invalid
        )
    }

    @MainActor
    func testReadinessDecisionSurvivesLabelFormatterSwap() throws {
        // The decision path must not depend on the display label. We verify
        // the typed state for the SecretStore value, then the resulting
        // `AIProviderReadiness` for that typed state. A different label
        // formatter would not change either, because the formatter only runs
        // on the existing typed state.
        let suite = "Suisui.ReadinessFormatterSwap.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        func expectedReadiness(for state: ProviderAPIKeyReadinessState) -> AIProviderReadiness {
            switch state {
            case .configured:
                return .ready
            case .invalid:
                return .needsAction(reason: "Re-enter the provider API key in Keychain.")
            case .missing:
                return .needsAction(reason: "Save the provider API key in Keychain.")
            case .unavailable:
                return .unavailable(reason: "Keychain access is unavailable.")
            }
        }

        for (secret, expectedState) in [
            ("sk-valid", ProviderAPIKeyReadinessState.configured),
            ("", ProviderAPIKeyReadinessState.missing),
            ("sk- has whitespace", ProviderAPIKeyReadinessState.invalid)
        ] {
            let viewModel = AppSettingsViewModel(
                settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
                secretStore: InMemorySecretStore(values: [.openAIAPIKey: secret])
            )
            XCTAssertEqual(
                viewModel.openAIAPIKeyReadinessState,
                expectedState,
                "Readiness must classify the SecretStore value directly."
            )
            XCTAssertEqual(
                viewModel.providerReadinessRow(for: .openaiResponses).readiness,
                expectedReadiness(for: expectedState),
                "Planning readiness must follow the typed state, not the display label."
            )
        }
    }

    @MainActor
    func testReadinessDecisionMatchesTypedStateAcrossAllAPIKeyProviders() throws {
        let suite = "Suisui.AllProvidersTyped.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let secretStore = InMemorySecretStore(values: [
            .openAIAPIKey: "sk-openai",
            .openRouterAPIKey: "sk-or",
            .anthropicAPIKey: "sk-ant",
            .geminiAPIKey: "gemini-key",
            .groqAPIKey: "gsk"
        ])
        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: secretStore
        )
        XCTAssertEqual(viewModel.openAIAPIKeyReadinessState, .configured)
        XCTAssertEqual(viewModel.openRouterAPIKeyReadinessState, .configured)
        XCTAssertEqual(viewModel.anthropicAPIKeyReadinessState, .configured)
        XCTAssertEqual(viewModel.geminiAPIKeyReadinessState, .configured)
        XCTAssertEqual(viewModel.groqAPIKeyReadinessState, .configured)
    }

    // MARK: - Keychain off MainActor (P2-New2)

    @MainActor
    func testRefreshProviderReadinessKeepsMainActorResponsiveDuringBlockingKeychainRead() async throws {
        let suite = "Suisui.BlockingKeychain.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let secretStore = BlockingSecretStore(
            blockedKeys: Set(SecretKey.allProviderKeys)
        )
        // Use a fast Ollama checker so the test isolates the Keychain-read
        // block rather than the probe block. The Keychain read is the part
        // that the P2 review required to leave MainActor. Defer the init
        // refresh so the BlockingSecretStore does not hang the constructor.
        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: secretStore,
            ollamaHealthChecker: StaticOllamaEndpointHealthChecker(result: .ready),
            refreshProviderSecretStatusesOnInit: false
        )

        let refreshTask = Task<Void, Never> { @MainActor in
            await viewModel.refreshProviderReadiness()
        }

        // Spin until `.checking` is published.
        for _ in 0..<500 where !viewModel.isRefreshingProviderReadiness {
            await Task.yield()
        }
        XCTAssertTrue(viewModel.isRefreshingProviderReadiness, "refresh must publish `.checking` before reading")

        // While the Keychain read is blocked, the MainActor must remain
        // responsive. The heartbeat ticks the MainActor until the refresh
        // completes; if the Keychain read were running on MainActor the
        // heartbeat would never advance.
        let heartbeat = await Self.awaitHeartbeat(viewModel: viewModel)
        XCTAssertGreaterThan(
            heartbeat,
            0,
            "MainActor must process a heartbeat while Keychain reads are blocked on a background thread"
        )
        XCTAssertTrue(
            viewModel.isRefreshingProviderReadiness,
            "The aggregate refresh must remain in flight while Keychain reads are blocked"
        )

        // Unblock the Keychain reads; refresh must complete and the typed
        // state must become `.configured` for every provider.
        secretStore.release()
        await refreshTask.value
        XCTAssertEqual(viewModel.openAIAPIKeyReadinessState, .configured)
        XCTAssertEqual(viewModel.openRouterAPIKeyReadinessState, .configured)
        XCTAssertEqual(viewModel.anthropicAPIKeyReadinessState, .configured)
        XCTAssertEqual(viewModel.geminiAPIKeyReadinessState, .configured)
        XCTAssertEqual(viewModel.groqAPIKeyReadinessState, .configured)
        XCTAssertFalse(viewModel.isRefreshingProviderReadiness)
    }

    @MainActor
    private static func awaitHeartbeat(viewModel: AppSettingsViewModel) async -> Int {
        var ticks = 0
        for _ in 0..<200 where viewModel.isRefreshingProviderReadiness {
            ticks += 1
            await Task.yield()
        }
        return ticks
    }

    @MainActor
    func testProviderSecretReadinessSnapshotIsSendableAndRoundTrips() throws {
        let snapshot = ProviderSecretReadinessSnapshot(
            openAI: .configured,
            openRouter: .missing,
            anthropic: .invalid,
            gemini: .unavailable,
            groq: .configured
        )
        // Compile-time check: snapshot is Sendable, so a detached task can
        // populate and the MainActor can apply it.
        let sendable: any Sendable = snapshot
        XCTAssertNotNil(sendable as? ProviderSecretReadinessSnapshot)
        XCTAssertEqual(snapshot.openAI, .configured)
        XCTAssertEqual(snapshot.openRouter, .missing)
        XCTAssertEqual(snapshot.anthropic, .invalid)
        XCTAssertEqual(snapshot.gemini, .unavailable)
        XCTAssertEqual(snapshot.groq, .configured)
    }

    // MARK: - Keychain read errors must surface as .unavailable (P2-Keychain)

    @MainActor
    func testKeychainBackedReaderClassifiesSecretStoreThrowingAsUnavailable() async {
        let reader = KeychainBackedProviderSecretReadinessReader(
            secretStore: AlwaysThrowingSecretStore()
        )
        let result = await reader.readSnapshot()
        XCTAssertEqual(result.snapshot.openAI, .unavailable)
        XCTAssertEqual(result.snapshot.openRouter, .unavailable)
        XCTAssertEqual(result.snapshot.anthropic, .unavailable)
        XCTAssertEqual(result.snapshot.gemini, .unavailable)
        XCTAssertEqual(result.snapshot.groq, .unavailable)
        XCTAssertEqual(
            result.failedProviders,
            Set<AIProvider>([
                .openaiResponses,
                .openRouterCompatible,
                .claudeMessages,
                .geminiDirect,
                .groqOpenAICompatible
            ])
        )
        XCTAssertTrue(result.hasReadFailure)
    }

    @MainActor
    func testKeychainBackedReaderKeepsOtherProvidersValidWhenOneFails() async {
        let secretStore = SelectiveThrowingSecretStore(
            throwing: .openAIAPIKey,
            values: [
                .openRouterAPIKey: "sk-or-valid",
                .anthropicAPIKey: "sk-ant-valid",
                .geminiAPIKey: "gemini-valid",
                .groqAPIKey: "gsk-valid"
            ]
        )
        let reader = KeychainBackedProviderSecretReadinessReader(secretStore: secretStore)
        let result = await reader.readSnapshot()

        XCTAssertEqual(result.snapshot.openAI, .unavailable)
        XCTAssertEqual(result.snapshot.openRouter, .configured)
        XCTAssertEqual(result.snapshot.anthropic, .configured)
        XCTAssertEqual(result.snapshot.gemini, .configured)
        XCTAssertEqual(result.snapshot.groq, .configured)
        XCTAssertEqual(result.failedProviders, [.openaiResponses])
        XCTAssertTrue(result.hasReadFailure)
    }

    @MainActor
    func testKeychainBackedReaderDoesNotLeakMissingWhenStoreThrows() async {
        // Regression for the previous `try?` implementation: a throwing
        // SecretStore must never collapse into `.missing` and silently look
        // like "user just hasn't entered a key yet".
        let reader = KeychainBackedProviderSecretReadinessReader(
            secretStore: AlwaysThrowingSecretStore()
        )
        let result = await reader.readSnapshot()
        for (provider, state) in result.snapshot.allProviders {
            XCTAssertNotEqual(
                state,
                ProviderAPIKeyReadinessState.missing,
                "\(provider) must be `.unavailable` (not `.missing`) when SecretStore.read throws."
            )
            XCTAssertEqual(
                state,
                ProviderAPIKeyReadinessState.unavailable
            )
        }
    }

    @MainActor
    func testAsyncRefreshProviderReadinessMarksEveryProviderUnavailableOnKeychainFailure() async throws {
        let suite = "Suisui.KeychainAsyncUnavailable.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: AlwaysThrowingSecretStore(),
            ollamaHealthChecker: StaticOllamaEndpointHealthChecker(result: .ready),
            refreshProviderSecretStatusesOnInit: false
        )

        await viewModel.refreshProviderReadiness()

        XCTAssertEqual(viewModel.openAIAPIKeyReadinessState, .unavailable)
        XCTAssertEqual(viewModel.openRouterAPIKeyReadinessState, .unavailable)
        XCTAssertEqual(viewModel.anthropicAPIKeyReadinessState, .unavailable)
        XCTAssertEqual(viewModel.geminiAPIKeyReadinessState, .unavailable)
        XCTAssertEqual(viewModel.groqAPIKeyReadinessState, .unavailable)
        XCTAssertEqual(viewModel.openAIAPIKeyStatusLabel, "Unavailable")
        XCTAssertEqual(viewModel.anthropicAPIKeyStatusLabel, "Unavailable")
        XCTAssertEqual(viewModel.openRouterAPIKeyStatusLabel, "Unavailable")
        XCTAssertEqual(viewModel.geminiAPIKeyStatusLabel, "Unavailable")
        XCTAssertEqual(viewModel.groqAPIKeyStatusLabel, "Unavailable")
        XCTAssertEqual(viewModel.errorMessage, "API key status could not be read from Keychain.")
        XCTAssertNil(viewModel.successMessage)

        // Planning readiness must follow the typed state, not the previous
        // "missing" misclassification.
        XCTAssertEqual(
            viewModel.providerReadinessRow(for: .openaiResponses).readiness,
            .unavailable(reason: "Keychain access is unavailable.")
        )
    }

    @MainActor
    func testAsyncAndSyncRefreshAgreeOnUnavailableForThrowingSecretStore() async throws {
        let suite = "Suisui.AsyncSyncParity.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let secretStore = AlwaysThrowingSecretStore()

        let syncViewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: secretStore,
            ollamaHealthChecker: StaticOllamaEndpointHealthChecker(result: .ready)
        )
        let asyncViewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: secretStore,
            ollamaHealthChecker: StaticOllamaEndpointHealthChecker(result: .ready),
            refreshProviderSecretStatusesOnInit: false
        )

        await asyncViewModel.refreshProviderReadiness()

        // Both code paths must produce `.unavailable` for every provider.
        for provider in AIProvider.allCases {
            if let key = AppSettingsViewModel.secretKey(for: provider) {
                let expected: ProviderAPIKeyReadinessState = .unavailable
                XCTAssertEqual(
                    syncViewModel.readinessStateForAPIKeyReadinessTest(key: key),
                    expected,
                    "sync path for \(key) must be `.unavailable`"
                )
                XCTAssertEqual(
                    asyncViewModel.readinessStateForAPIKeyReadinessTest(key: key),
                    expected,
                    "async path for \(key) must be `.unavailable`"
                )
            }
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

/// `SecretStore` that parks every `read` on a per-key semaphore so the test
/// can deterministically observe the MainActor while a Keychain read is in
/// flight. Releasing the semaphore unblocks all parked reads at once.
private final class BlockingSecretStore: SecretStore, @unchecked Sendable {
    private let blockedKeys: Set<SecretKey>
    private let semaphore = DispatchSemaphore(value: 0)
    private let releasedLock = OSAllocatedUnfairLock()
    private var released: Bool = false
    private let storage: [SecretKey: String] = [
        .openAIAPIKey: "sk-openai",
        .openRouterAPIKey: "sk-or",
        .anthropicAPIKey: "sk-ant",
        .geminiAPIKey: "gemini-key",
        .groqAPIKey: "gsk"
    ]

    init(blockedKeys: Set<SecretKey>) {
        self.blockedKeys = blockedKeys
    }

    func save(_ value: String, for key: SecretKey) throws {}
    func delete(_ key: SecretKey) throws {}

    func read(_ key: SecretKey) throws -> String? {
        guard blockedKeys.contains(key) else {
            return storage[key]
        }
        let alreadyReleased = releasedLock.withLock { self.released }
        if alreadyReleased {
            return storage[key]
        }
        semaphore.wait()
        return storage[key]
    }

    func release() {
        releasedLock.withLock { released = true }
        semaphore.signal()
    }
}

private extension SecretKey {
    static var allProviderKeys: Set<SecretKey> {
        [
            .openAIAPIKey,
            .openRouterAPIKey,
            .anthropicAPIKey,
            .geminiAPIKey,
            .groqAPIKey
        ]
    }
}

/// `SecretStore` that throws on every read. Used to verify the async reader
/// reports `.unavailable` for every provider rather than collapsing the
/// failure into `.missing` via `try?`.
private final class AlwaysThrowingSecretStore: SecretStore, @unchecked Sendable {
    func save(_ value: String, for key: SecretKey) throws {}
    func delete(_ key: SecretKey) throws {}
    func read(_ key: SecretKey) throws -> String? {
        throw SecretStoreError.unexpectedStatus(-25300)
    }
}

/// `SecretStore` that throws for one configured key and returns the others
/// from the in-memory map. Used to verify the async reader records the
/// failure in `failedProviders` while still reading the other keys.
private final class SelectiveThrowingSecretStore: SecretStore, @unchecked Sendable {
    private let throwing: Set<SecretKey>
    private let values: [SecretKey: String]
    private let lock = NSLock()

    init(throwing: SecretKey..., values: [SecretKey: String] = [:]) {
        self.throwing = Set(throwing)
        self.values = values
    }

    func save(_ value: String, for key: SecretKey) throws {}
    func delete(_ key: SecretKey) throws {}

    func read(_ key: SecretKey) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        if throwing.contains(key) {
            throw SecretStoreError.unexpectedStatus(-25300)
        }
        return values[key]
    }
}
