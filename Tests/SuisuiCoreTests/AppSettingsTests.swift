import Darwin
import XCTest
@testable import SuisuiCore

final class AppSettingsTests: XCTestCase {
    func testDefaultSettingsAreValid() {
        XCTAssertTrue(AppSettings.default.validate().isEmpty)
    }

    func testDefaultVoiceRoutingPreferencesAreAppleFirst() {
        XCTAssertEqual(AppSettings.default.sttRoutingPreference, .appleFirst)
        XCTAssertEqual(AppSettings.default.ttsRoutingPreference, .appleFirst)
    }

    func testLowLatencyVoiceAgentDefaultsOffAndCloudFallbackDisabled() throws {
        XCTAssertFalse(AppSettings.default.isLowLatencyVoiceAgentModeEnabled)
        XCTAssertFalse(AppSettings.default.isLowLatencyVoiceAgentAlwaysOnRecordingEnabled)
        XCTAssertFalse(AppSettings.default.isLowLatencyVoiceAgentCloudFallbackEnabled)
        XCTAssertFalse(AppSettings.default.isLowLatencyVoiceAgentCloudFallbackCostVisible)

        let legacyData = Data("""
        {
          "aiProvider": "openAIResponses",
          "sttProvider": "openAITranscribe",
          "notificationsEnabled": false,
          "defaultWorkspacePath": null,
          "timeZoneIdentifier": "UTC"
        }
        """.utf8)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacyData)
        XCTAssertFalse(decoded.isLowLatencyVoiceAgentModeEnabled)
        XCTAssertFalse(decoded.isLowLatencyVoiceAgentAlwaysOnRecordingEnabled)
        XCTAssertFalse(decoded.isLowLatencyVoiceAgentCloudFallbackEnabled)
        XCTAssertFalse(decoded.isLowLatencyVoiceAgentCloudFallbackCostVisible)

        let hiddenCostFallback = AppSettings(
            isLowLatencyVoiceAgentModeEnabled: true,
            isLowLatencyVoiceAgentAlwaysOnRecordingEnabled: true,
            isLowLatencyVoiceAgentCloudFallbackEnabled: true,
            isLowLatencyVoiceAgentCloudFallbackCostVisible: false
        ).normalizedForRuntime
        XCTAssertTrue(hiddenCostFallback.isLowLatencyVoiceAgentModeEnabled)
        XCTAssertFalse(hiddenCostFallback.isLowLatencyVoiceAgentAlwaysOnRecordingEnabled)
        XCTAssertFalse(hiddenCostFallback.isLowLatencyVoiceAgentCloudFallbackEnabled)

        let explicitCostVisibleFallback = AppSettings(
            isLowLatencyVoiceAgentModeEnabled: true,
            isLowLatencyVoiceAgentCloudFallbackEnabled: true,
            isLowLatencyVoiceAgentCloudFallbackCostVisible: true
        ).normalizedForRuntime
        XCTAssertTrue(explicitCostVisibleFallback.isLowLatencyVoiceAgentCloudFallbackEnabled)

        XCTAssertEqual(
            AppSettings(
                isLowLatencyVoiceAgentCloudFallbackEnabled: true,
                isLowLatencyVoiceAgentCloudFallbackCostVisible: false
            ).validate().filter { $0.field == "isLowLatencyVoiceAgentCloudFallbackEnabled" },
            [
                ValidationIssue(
                    field: "isLowLatencyVoiceAgentCloudFallbackEnabled",
                    message: "Low-latency cloud fallback requires visible cost disclosure.",
                    severity: .error
                )
            ]
        )
    }

    func testCodexLocalSettingsDefaultOffAndRoundTripWithoutCredentials() throws {
        XCTAssertNil(AppSettings.default.codexExecutablePath)
        XCTAssertNil(AppSettings.default.codexModelID)
        XCTAssertFalse(AppSettings.default.isCodexLocalExecutionApproved)
        XCTAssertNil(AppSettings.default.approvedCodexExecutable)

        let approved = try CodexAppServerRuntimeConfiguration.approve(
            executablePath: "/usr/bin/true",
            trustPolicy: .developerUnsignedAllowed
        )
        let settings = AppSettings(
            isDeveloperModeEnabled: true,
            codexExecutablePath: "/usr/bin/true",
            codexModelID: " gpt-5.4 ",
            isCodexLocalExecutionApproved: true,
            approvedCodexExecutable: approved
        ).normalizedForRuntime
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.codexExecutablePath, "/usr/bin/true")
        XCTAssertEqual(decoded.codexModelID, "gpt-5.4")
        XCTAssertTrue(decoded.isCodexLocalExecutionApproved)
        XCTAssertEqual(decoded.approvedCodexExecutable, approved)
        let encoded = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(encoded.contains("accessToken"))
        XCTAssertFalse(encoded.contains("refreshToken"))
    }

    func testCodexLocalSelectionRequiresAbsoluteExecutableAndApproval() throws {
        let missing = AppSettings(aiProvider: .codexLocal)
        XCTAssertEqual(
            Set(missing.validate().map(\.field)),
            Set(["codexExecutablePath", "isCodexLocalExecutionApproved"])
        )

        let approved = try CodexAppServerRuntimeConfiguration.approve(
            executablePath: "/usr/bin/true",
            trustPolicy: .developerUnsignedAllowed
        )
        let ready = AppSettings(
            aiProvider: .codexLocal,
            isDeveloperModeEnabled: true,
            codexExecutablePath: "/usr/bin/true",
            isCodexLocalExecutionApproved: true,
            approvedCodexExecutable: approved
        )
        XCTAssertTrue(ready.validate().isEmpty)

        let credentialPath = AppSettings(
            aiProvider: .codexLocal,
            codexExecutablePath: "/Users/example/.codex/auth.json",
            isCodexLocalExecutionApproved: true
        )
        XCTAssertEqual(credentialPath.validate().first?.field, "codexExecutablePath")
    }

    @MainActor
    func testChangingCodexExecutableInvalidatesBoundApproval() throws {
        let suiteName = "Suisui.CodexApprovalBinding.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: InMemorySecretStore(),
            refreshProviderSecretStatusesOnInit: false
        )

        viewModel.setCodexExecutablePath("/usr/bin/true")
        viewModel.setDeveloperModeEnabled(true)
        viewModel.setCodexLocalExecutionApproved(true)
        XCTAssertTrue(viewModel.settings.isCodexLocalExecutionApproved)
        XCTAssertNotNil(viewModel.settings.approvedCodexExecutable)

        viewModel.setCodexExecutablePath("/usr/bin/false")

        XCTAssertFalse(viewModel.settings.isCodexLocalExecutionApproved)
        XCTAssertNil(viewModel.settings.approvedCodexExecutable)
    }

    @MainActor
    func testUnsignedCodexApprovalRequiresDeveloperModeAndIsRevokedWhenDeveloperModeEnds() throws {
        let suiteName = "Suisui.CodexUnsignedDeveloperApproval.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-codex-settings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("codex")
        try Data("#!/bin/sh\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: InMemorySecretStore(),
            refreshProviderSecretStatusesOnInit: false
        )
        viewModel.setCodexExecutablePath(executable.path)

        viewModel.setCodexLocalExecutionApproved(true)
        XCTAssertFalse(viewModel.settings.isCodexLocalExecutionApproved)

        viewModel.setDeveloperModeEnabled(true)
        viewModel.setCodexLocalExecutionApproved(true)
        XCTAssertTrue(viewModel.settings.isCodexLocalExecutionApproved)
        XCTAssertEqual(
            viewModel.settings.approvedCodexExecutable?.trustPolicy,
            .developerUnsignedAllowed
        )

        viewModel.setDeveloperModeEnabled(false)
        XCTAssertFalse(viewModel.settings.isCodexLocalExecutionApproved)
        XCTAssertNil(viewModel.settings.approvedCodexExecutable)
    }

    @MainActor
    func testDisconnectCodexPersistsRevocationImmediately() throws {
        let suiteName = "Suisui.CodexDisconnect.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        let approved = try CodexAppServerRuntimeConfiguration.approve(
            executablePath: "/usr/bin/true",
            trustPolicy: .developerUnsignedAllowed
        )
        try store.save(AppSettings(
            aiProvider: .codexLocal,
            isDeveloperModeEnabled: true,
            codexExecutablePath: "/usr/bin/true",
            isCodexLocalExecutionApproved: true,
            approvedCodexExecutable: approved
        ))
        let viewModel = AppSettingsViewModel(
            settingsStore: store,
            secretStore: InMemorySecretStore(),
            refreshProviderSecretStatusesOnInit: false
        )

        try viewModel.disconnectCodexAndSave()

        XCTAssertFalse(viewModel.settings.isCodexLocalExecutionApproved)
        XCTAssertNil(viewModel.settings.approvedCodexExecutable)
        let persisted = try store.load()
        XCTAssertFalse(persisted.isCodexLocalExecutionApproved)
        XCTAssertNil(persisted.approvedCodexExecutable)
    }

    func testInvalidTimeZoneProducesValidationIssue() {
        let settings = AppSettings(timeZoneIdentifier: "Invalid/Timezone")

        XCTAssertEqual(
            settings.validate(),
            [
                ValidationIssue(
                    field: "timeZoneIdentifier",
                    message: "Unknown time zone identifier.",
                    severity: .error
                )
            ]
        )
    }

    func testBlankWorkspacePathProducesValidationIssue() {
        let settings = AppSettings(defaultWorkspacePath: "   ")

        XCTAssertEqual(settings.validate().first?.field, "defaultWorkspacePath")
    }

    func testReleaseReadySTTProvidersExposeImplementedRuntimeProviders() {
        XCTAssertEqual(STTProvider.releaseReadyCases, [.appleSpeechAnalyzer, .openAITranscribe, .localWhisperCpp])
        XCTAssertTrue(STTProvider.appleSpeechAnalyzer.isReleaseReady)
        XCTAssertTrue(STTProvider.openAITranscribe.isReleaseReady)
        XCTAssertTrue(STTProvider.localWhisperCpp.isReleaseReady)
        XCTAssertFalse(STTProvider.localWhisperKit.isReleaseReady)
    }

    func testUserDefaultsAppSettingsStorePersistsSettings() throws {
        let suiteName = "Suisui.AppSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        let settings = AppSettings(
            aiProvider: .openaiResponses,
            sttProvider: .openAITranscribe,
            notificationsEnabled: true,
            defaultWorkspacePath: "/tmp/Suisui",
            timeZoneIdentifier: "Asia/Tokyo",
            googleCalendarID: "team@example.com"
        )

        try store.save(settings)

        XCTAssertEqual(try store.load(), settings)
    }

    func testManagedAIBillingSettingsPersistAndExposePerRunPreviewCap() throws {
        let suiteName = "Suisui.AppSettingsBillingCaps.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        let settings = AppSettings(
            managedAIBilling: ManagedAIBillingSettings(
                isEnabled: true,
                perRunCapCents: 50,
                dailyCapCents: 150,
                monthlyCapCents: 900,
                workspaceCapCents: 75
            )
        )

        try store.save(settings)

        let loaded = try store.load()
        XCTAssertEqual(loaded.managedAIBilling, settings.managedAIBilling)
        XCTAssertEqual(loaded.normalizedForRuntime.managedAIBilling.hardCapCentsForPreview, 50)
    }

    func testManagedAIBillingSettingsRejectInvalidCaps() {
        let settings = AppSettings(
            managedAIBilling: ManagedAIBillingSettings(
                isEnabled: true,
                perRunCapCents: -1,
                dailyCapCents: 0,
                monthlyCapCents: -10,
                workspaceCapCents: 25
            )
        )

        XCTAssertEqual(
            settings.validate().filter { $0.field.hasPrefix("managedAIBilling") },
            [
                ValidationIssue(
                    field: "managedAIBilling.perRunCapCents",
                    message: "Managed AI per-run cap must be greater than 0 cents.",
                    severity: .error
                ),
                ValidationIssue(
                    field: "managedAIBilling.dailyCapCents",
                    message: "Managed AI daily cap must be greater than 0 cents.",
                    severity: .error
                ),
                ValidationIssue(
                    field: "managedAIBilling.monthlyCapCents",
                    message: "Managed AI monthly cap must be greater than 0 cents.",
                    severity: .error
                )
            ]
        )
    }

    func testManagedAICostRateCardResolverReadsConfiguredEnvironment() {
        let environment = [
            ManagedAICostRateCardConfiguration.providerIDEnvironmentKey: " suisui.managed ",
            ManagedAICostRateCardConfiguration.modelNameEnvironmentKey: " managed-small ",
            ManagedAICostRateCardConfiguration.currencyCodeEnvironmentKey: " usd ",
            ManagedAICostRateCardConfiguration.inputTokenCentsPerMillionEnvironmentKey: "10000",
            ManagedAICostRateCardConfiguration.outputTokenCentsPerMillionEnvironmentKey: "20000"
        ]
        let resolver = ManagedAICostRateCardResolver(environment: environment)
        let response = PlanningResponse(
            providerID: "suisui.managed",
            rawContent: "{}",
            actionPlan: nil,
            validationResult: ActionPlanValidationResult(issues: []),
            model: ExecutionReceiptModel(provider: "suisui.managed", name: "managed-small")
        )

        let rateCard = resolver.rateCard(for: response)

        XCTAssertEqual(rateCard?.provider, "suisui.managed")
        XCTAssertEqual(rateCard?.modelName, "managed-small")
        XCTAssertEqual(rateCard?.currencyCode, "USD")
        XCTAssertEqual(rateCard?.inputTokenCentsPerMillion, 10_000)
        XCTAssertEqual(rateCard?.outputTokenCentsPerMillion, 20_000)
    }

    func testManagedAICostRateCardResolverIgnoresMissingOrInvalidRates() {
        let invalidResolver = ManagedAICostRateCardResolver(environment: [
            ManagedAICostRateCardConfiguration.providerIDEnvironmentKey: "suisui.managed",
            ManagedAICostRateCardConfiguration.modelNameEnvironmentKey: "managed-small",
            ManagedAICostRateCardConfiguration.inputTokenCentsPerMillionEnvironmentKey: "0",
            ManagedAICostRateCardConfiguration.outputTokenCentsPerMillionEnvironmentKey: "invalid"
        ])
        let response = PlanningResponse(
            providerID: "suisui.managed",
            rawContent: "{}",
            actionPlan: nil,
            validationResult: ActionPlanValidationResult(issues: [])
        )

        XCTAssertNil(invalidResolver.rateCard(for: response))
        XCTAssertNil(ManagedAICostRateCardResolver(environment: [:]).rateCard(for: response))
    }

    func testManagedAICostRateCardResolverRequiresMatchingModelName() {
        let resolver = ManagedAICostRateCardResolver(configuration: ManagedAICostRateCardConfiguration(
            providerID: "suisui.managed",
            modelName: "managed-small",
            inputTokenCentsPerMillion: 10_000,
            outputTokenCentsPerMillion: 20_000
        ))
        let response = PlanningResponse(
            providerID: "suisui.managed",
            rawContent: "{}",
            actionPlan: nil,
            validationResult: ActionPlanValidationResult(issues: []),
            model: ExecutionReceiptModel(provider: "suisui.managed", name: "managed-large")
        )

        XCTAssertNil(resolver.rateCard(for: response))
    }

    @MainActor
    func testAppSettingsViewModelSavesManagedAIBillingCaps() throws {
        let suiteName = "Suisui.AppSettingsBillingCapViewModel.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        let viewModel = AppSettingsViewModel(
            settingsStore: store,
            secretStore: InMemorySecretStore()
        )

        viewModel.setManagedAIBillingEnabled(true)
        viewModel.setManagedAIPerRunCapCents(125)
        viewModel.setManagedAIDailyCapCents(200)
        viewModel.setManagedAIMonthlyCapCents(1_000)
        viewModel.setManagedAIWorkspaceCapCents(nil)
        viewModel.saveSettings()

        XCTAssertEqual(viewModel.successMessage, "Settings saved.")
        let saved = try store.load().managedAIBilling
        XCTAssertTrue(saved.isEnabled)
        XCTAssertEqual(saved.perRunCapCents, 125)
        XCTAssertEqual(saved.dailyCapCents, 200)
        XCTAssertEqual(saved.monthlyCapCents, 1_000)
        XCTAssertNil(saved.workspaceCapCents)
    }

    @MainActor
    func testSuccessfulSettingsSavePostsCalendarReadinessInvalidation() async throws {
        let suiteName = "Suisui.AppSettingsCalendarReadiness.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: InMemorySecretStore()
        )
        let notification = expectation(description: "Calendar readiness is invalidated after Settings save")
        let observer = NotificationCenter.default.addObserver(
            forName: .suisuiGoogleCalendarReadinessDidChange,
            object: nil,
            queue: nil
        ) { _ in
            notification.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        viewModel.setGoogleCalendarID("team@example.com")
        viewModel.saveSettings()

        XCTAssertEqual(viewModel.successMessage, "Settings saved.")
        await fulfillment(of: [notification], timeout: 1)
    }

    func testGoogleCalendarIDDefaultsAndNormalizesForRuntime() throws {
        let legacyData = Data("""
        {
          "aiProvider": "openAIResponses",
          "sttProvider": "openAITranscribe",
          "notificationsEnabled": false,
          "defaultWorkspacePath": null,
          "timeZoneIdentifier": "UTC"
        }
        """.utf8)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacyData)
        let trimmed = AppSettings(googleCalendarID: " team@example.com ").normalizedForRuntime
        let blank = AppSettings(googleCalendarID: " \n ").normalizedForRuntime

        XCTAssertEqual(AppSettings.default.googleCalendarID, "primary")
        XCTAssertEqual(decoded.googleCalendarID, "primary")
        XCTAssertEqual(trimmed.googleCalendarID, "team@example.com")
        XCTAssertEqual(blank.googleCalendarID, "")
    }

    func testDailyWorkCapacityDefaultsDecodesLegacyAndValidatesBounds() throws {
        let legacyData = Data("""
        {
          "aiProvider": "openAIResponses",
          "sttProvider": "openAITranscribe",
          "notificationsEnabled": false,
          "defaultWorkspacePath": null,
          "timeZoneIdentifier": "UTC"
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacyData)

        XCTAssertEqual(AppSettings.default.dailyWorkCapacityMinutes, 480)
        XCTAssertEqual(decoded.dailyWorkCapacityMinutes, 480)
        XCTAssertEqual(AppSettings(dailyWorkCapacityMinutes: 390).normalizedForRuntime.dailyWorkCapacityMinutes, 390)
        XCTAssertEqual(AppSettings(dailyWorkCapacityMinutes: 0).normalizedForRuntime.dailyWorkCapacityMinutes, 60)
        XCTAssertEqual(AppSettings(dailyWorkCapacityMinutes: 24 * 60).normalizedForRuntime.dailyWorkCapacityMinutes, 16 * 60)
        XCTAssertTrue(AppSettings(dailyWorkCapacityMinutes: 45).validate().contains {
            $0.field == "dailyWorkCapacityMinutes" && $0.severity == .error
        })
    }

    func testProfileDisplayNameDefaultsToNilWhenDecodingLegacySettings() throws {
        let legacyData = Data("""
        {
          "aiProvider": "openAIResponses",
          "sttProvider": "openAITranscribe",
          "notificationsEnabled": false,
          "defaultWorkspacePath": null,
          "timeZoneIdentifier": "UTC"
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacyData)

        XCTAssertNil(decoded.profileDisplayName)
    }

    func testProfileDisplayNameTrimsWhitespaceAndTreatsEmptyValueAsNil() {
        XCTAssertEqual(
            AppSettings(profileDisplayName: "  Ada Lovelace \n").normalizedForRuntime.profileDisplayName,
            "Ada Lovelace"
        )
        XCTAssertNil(AppSettings(profileDisplayName: " \n\t ").normalizedForRuntime.profileDisplayName)
    }

    func testProfileDisplayNameLimitsToEightyUserPerceivedCharacters() {
        let name = String(repeating: "👩🏽‍💻", count: 81)

        let normalized = AppSettings(profileDisplayName: name).normalizedForRuntime.profileDisplayName

        XCTAssertEqual(normalized?.count, 80)
        XCTAssertEqual(normalized, String(name.prefix(80)))
    }

    func testProfileDisplayNameRoundTripsThroughSettingsEncoding() throws {
        let settings = AppSettings(profileDisplayName: "Ada Lovelace")

        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))

        XCTAssertEqual(decoded.profileDisplayName, "Ada Lovelace")
    }

    @MainActor
    func testAppSettingsViewModelKeepsProfileDisplayNameInMemoryUntilSettingsSave() throws {
        let suiteName = "Suisui.AppSettingsProfileDisplayName.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        let viewModel = AppSettingsViewModel(settingsStore: store, secretStore: InMemorySecretStore())

        viewModel.setProfileDisplayName(" Ada Lovelace ")

        XCTAssertEqual(viewModel.settings.profileDisplayName, " Ada Lovelace ")
        XCTAssertNil(try store.load().profileDisplayName)

        viewModel.saveSettings()

        XCTAssertEqual(try store.load().profileDisplayName, "Ada Lovelace")
    }

    @MainActor
    func testProfileDisplayNameKeepsTypingDraftUntilSaveNormalizesIt() throws {
        let suiteName = "Suisui.AppSettingsProfileDisplayNameDraft.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        let viewModel = AppSettingsViewModel(settingsStore: store, secretStore: InMemorySecretStore())

        viewModel.setProfileDisplayName("Ada ")
        XCTAssertEqual(viewModel.settings.profileDisplayName, "Ada ")
        viewModel.setProfileDisplayName("Ada  ")
        XCTAssertEqual(viewModel.settings.profileDisplayName, "Ada  ")

        viewModel.saveSettings()
        XCTAssertEqual(viewModel.settings.profileDisplayName, "Ada")
        XCTAssertEqual(try store.load().profileDisplayName, "Ada")
    }

    @MainActor
    func testOnboardingTodayPreferencesSaveOnlyWhenApplied() throws {
        let suiteName = "Suisui.OnboardingTodayPreferences.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        let viewModel = AppSettingsViewModel(settingsStore: store, secretStore: InMemorySecretStore())
        let preferences = OnboardingTodayPreferences(
            displayName: "  Grace Hopper  ",
            dailyWorkCapacityMinutes: 75
        )

        XCTAssertNil(try store.load().profileDisplayName)
        XCTAssertTrue(viewModel.saveOnboardingTodayPreferences(preferences))
        XCTAssertEqual(viewModel.settings.profileDisplayName, "Grace Hopper")
        XCTAssertEqual(viewModel.settings.dailyWorkCapacityMinutes, 60)
        XCTAssertEqual(try store.load().profileDisplayName, "Grace Hopper")
        XCTAssertEqual(try store.load().dailyWorkCapacityMinutes, 60)
    }

    @MainActor
    func testOnboardingTodayPreferencesRollBackRuntimeAndPersistedSettingsWhenSaveFails() throws {
        let saved = AppSettings(profileDisplayName: "Ada", dailyWorkCapacityMinutes: 390)
        let store = FailingSaveAppSettingsStore(initial: saved)
        let viewModel = AppSettingsViewModel(settingsStore: store, secretStore: InMemorySecretStore())

        XCTAssertFalse(viewModel.saveOnboardingTodayPreferences(
            OnboardingTodayPreferences(displayName: "Grace", dailyWorkCapacityMinutes: 480)
        ))

        XCTAssertEqual(viewModel.settings.profileDisplayName, "Ada")
        XCTAssertEqual(viewModel.settings.dailyWorkCapacityMinutes, 390)
        XCTAssertEqual(try store.load().profileDisplayName, "Ada")
        XCTAssertEqual(try store.load().dailyWorkCapacityMinutes, 390)
    }

    func testUserDefaultsAppSettingsStoreCanUseRuntimeSuiteOverride() throws {
        let suiteName = "Suisui.AppSettingsRuntimeSuite.\(UUID().uuidString)"
        let defaults = UserDefaultsAppSettingsStore.defaultUserDefaults(environment: [
            UserDefaultsAppSettingsStore.suiteNameEnvironmentKey: suiteName
        ])
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        let settings = AppSettings(notificationsEnabled: true)

        try store.save(settings)

        XCTAssertEqual(try store.load().notificationsEnabled, true)
    }

    @MainActor
    func testAppSettingsViewModelSavesGoogleCalendarIDSetting() throws {
        let suiteName = "Suisui.AppSettingsGoogleCalendarID.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        let viewModel = AppSettingsViewModel(
            settingsStore: store,
            secretStore: InMemorySecretStore()
        )

        viewModel.setGoogleCalendarID(" team-calendar@example.com ")
        viewModel.saveSettings()

        XCTAssertEqual(viewModel.successMessage, "Settings saved.")
        XCTAssertEqual(try store.load().googleCalendarID, "team-calendar@example.com")
    }

    @MainActor
    func testAppSettingsViewModelReportsCorruptedStoredSettingsInsteadOfSilentDefault() throws {
        let suiteName = "Suisui.AppSettingsCorrupted.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("not-json".utf8), forKey: "app.settings")

        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: InMemorySecretStore()
        )

        XCTAssertEqual(viewModel.settings, .default)
        XCTAssertEqual(viewModel.errorMessage, "App settings could not be loaded. Defaults are shown until settings are saved again.")
        XCTAssertNil(viewModel.successMessage)
    }

    @MainActor
    func testAppSettingsViewModelReportsKeychainReadFailureInsteadOfNotConfigured() throws {
        let suiteName = "Suisui.AppSettingsKeychainReadFailure.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: ThrowingReadSecretStore()
        )

        XCTAssertEqual(viewModel.openAIAPIKeyStatusLabel, "Unavailable")
        XCTAssertEqual(viewModel.anthropicAPIKeyStatusLabel, "Unavailable")
        XCTAssertEqual(viewModel.geminiAPIKeyStatusLabel, "Unavailable")
        XCTAssertEqual(viewModel.geminiProviderSmokeStatusLabel, "unavailable")
        XCTAssertEqual(viewModel.groqAPIKeyStatusLabel, "Unavailable")
        XCTAssertEqual(viewModel.groqProviderSmokeStatusLabel, "unavailable")
        XCTAssertEqual(viewModel.openRouterAPIKeyStatusLabel, "Unavailable")
        XCTAssertEqual(viewModel.openAIProviderSmokeStatusLabel, "unavailable")
        XCTAssertEqual(viewModel.errorMessage, "API key status could not be read from Keychain.")
    }

    @MainActor
    func testAppSettingsViewModelReportsInvalidStoredOpenAIKeyInsteadOfConfigured() throws {
        let suiteName = "Suisui.AppSettingsInvalidStoredOpenAIKey.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: InMemorySecretStore(values: [.openAIAPIKey: "sk-live invalid"])
        )

        XCTAssertEqual(viewModel.openAIAPIKeyStatusLabel, "Invalid")
        XCTAssertEqual(viewModel.openAIProviderSmokeStatusLabel, "invalidConfiguration")
        XCTAssertEqual(viewModel.anthropicAPIKeyStatusLabel, "Not configured")
        XCTAssertEqual(viewModel.geminiAPIKeyStatusLabel, "Not configured")
        XCTAssertEqual(viewModel.groqAPIKeyStatusLabel, "Not configured")
        XCTAssertEqual(viewModel.openRouterAPIKeyStatusLabel, "Not configured")
        XCTAssertEqual(viewModel.errorMessage, "Stored API key is invalid. Re-enter it in Settings.")
        XCTAssertFalse(viewModel.errorMessage?.contains("sk-live") ?? true)
    }

    @MainActor
    func testAppSettingsViewModelReportsInvalidStoredOpenRouterKeyInsteadOfConfigured() throws {
        let suiteName = "Suisui.AppSettingsInvalidStoredOpenRouterKey.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: InMemorySecretStore(values: [.openRouterAPIKey: "sk-or-live\ninvalid"])
        )

        XCTAssertEqual(viewModel.openAIAPIKeyStatusLabel, "Not configured")
        XCTAssertEqual(viewModel.openAIProviderSmokeStatusLabel, "notConfigured")
        XCTAssertEqual(viewModel.anthropicAPIKeyStatusLabel, "Not configured")
        XCTAssertEqual(viewModel.geminiAPIKeyStatusLabel, "Not configured")
        XCTAssertEqual(viewModel.groqAPIKeyStatusLabel, "Not configured")
        XCTAssertEqual(viewModel.openRouterAPIKeyStatusLabel, "Invalid")
        XCTAssertEqual(viewModel.errorMessage, "Stored API key is invalid. Re-enter it in Settings.")
        XCTAssertFalse(viewModel.errorMessage?.contains("sk-or-live") ?? true)
    }

    @MainActor
    func testAppSettingsViewModelDoesNotReportOpenAIKeySaveSuccessWhenStatusRefreshFails() throws {
        let suiteName = "Suisui.AppSettingsOpenAISaveRefreshFailure.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: ThrowingReadSecretStore()
        )

        viewModel.updateOpenAIAPIKeyInput("sk-test")
        viewModel.saveOpenAIAPIKey()

        XCTAssertEqual(viewModel.openAIAPIKeyStatusLabel, "Unavailable")
        XCTAssertEqual(viewModel.openAIProviderSmokeStatusLabel, "unavailable")
        XCTAssertEqual(viewModel.errorMessage, "API key status could not be read from Keychain.")
        XCTAssertNil(viewModel.successMessage)
    }

    @MainActor
    func testAppSettingsViewModelDoesNotReportOpenRouterKeySaveSuccessWhenStatusRefreshFails() throws {
        let suiteName = "Suisui.AppSettingsOpenRouterSaveRefreshFailure.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: ThrowingReadSecretStore()
        )

        viewModel.updateOpenRouterAPIKeyInput("sk-or-test")
        viewModel.saveOpenRouterAPIKey()

        XCTAssertEqual(viewModel.openRouterAPIKeyStatusLabel, "Unavailable")
        XCTAssertEqual(viewModel.errorMessage, "API key status could not be read from Keychain.")
        XCTAssertNil(viewModel.successMessage)
    }

    @MainActor
    func testAppSettingsViewModelDoesNotReportAnthropicKeySaveSuccessWhenStatusRefreshFails() throws {
        let suiteName = "Suisui.AppSettingsAnthropicSaveRefreshFailure.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: ThrowingReadSecretStore()
        )

        viewModel.updateAnthropicAPIKeyInput("sk-ant-test")
        viewModel.saveAnthropicAPIKey()

        XCTAssertEqual(viewModel.anthropicAPIKeyStatusLabel, "Unavailable")
        XCTAssertEqual(viewModel.errorMessage, "API key status could not be read from Keychain.")
        XCTAssertNil(viewModel.successMessage)
    }

    @MainActor
    func testAppSettingsViewModelDoesNotReportGeminiKeySaveSuccessWhenStatusRefreshFails() throws {
        let suiteName = "Suisui.AppSettingsGeminiSaveRefreshFailure.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: ThrowingReadSecretStore()
        )

        viewModel.updateGeminiAPIKeyInput("gemini-test-key")
        viewModel.saveGeminiAPIKey()

        XCTAssertEqual(viewModel.geminiAPIKeyStatusLabel, "Unavailable")
        XCTAssertEqual(viewModel.geminiProviderSmokeStatusLabel, "unavailable")
        XCTAssertEqual(viewModel.errorMessage, "API key status could not be read from Keychain.")
        XCTAssertNil(viewModel.successMessage)
    }

    @MainActor
    func testAppSettingsViewModelDoesNotReportGroqKeySaveSuccessWhenStatusRefreshFails() throws {
        let suiteName = "Suisui.AppSettingsGroqSaveRefreshFailure.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: ThrowingReadSecretStore()
        )

        viewModel.updateGroqAPIKeyInput("gsk-test")
        viewModel.saveGroqAPIKey()

        XCTAssertEqual(viewModel.groqAPIKeyStatusLabel, "Unavailable")
        XCTAssertEqual(viewModel.groqProviderSmokeStatusLabel, "unavailable")
        XCTAssertEqual(viewModel.errorMessage, "API key status could not be read from Keychain.")
        XCTAssertNil(viewModel.successMessage)
    }

    @MainActor
    func testAppSettingsViewModelSavesAndDeletesOpenAIKeyInSecretStoreOnly() throws {
        let suiteName = "Suisui.AppSettingsViewModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settingsStore = UserDefaultsAppSettingsStore(defaults: defaults)
        let secretStore = InMemorySecretStore()
        let viewModel = AppSettingsViewModel(settingsStore: settingsStore, secretStore: secretStore)

        viewModel.updateOpenAIAPIKeyInput(" sk-test-secret ")
        viewModel.saveOpenAIAPIKey()

        XCTAssertEqual(try secretStore.read(.openAIAPIKey), "sk-test-secret")
        XCTAssertEqual(viewModel.openAIAPIKeyStatusLabel, "Configured")
        XCTAssertEqual(viewModel.openAIProviderSmokeStatusLabel, "readyForManualSmoke")
        XCTAssertNil(defaults.data(forKey: "app.settings"))

        viewModel.deleteOpenAIAPIKey()

        XCTAssertNil(try secretStore.read(.openAIAPIKey))
        XCTAssertEqual(viewModel.openAIAPIKeyStatusLabel, "Not configured")
        XCTAssertEqual(viewModel.openAIProviderSmokeStatusLabel, "notConfigured")
    }

    @MainActor
    func testAppSettingsViewModelRejectsOpenAIKeyWithInternalWhitespace() throws {
        let suiteName = "Suisui.AppSettingsViewModelInvalidOpenAIKey.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settingsStore = UserDefaultsAppSettingsStore(defaults: defaults)
        let secretStore = InMemorySecretStore()
        let viewModel = AppSettingsViewModel(settingsStore: settingsStore, secretStore: secretStore)

        let keyPrefix = "sk" + "-live"
        viewModel.updateOpenAIAPIKeyInput("\(keyPrefix) invalid")
        viewModel.saveOpenAIAPIKey()

        XCTAssertNil(try secretStore.read(.openAIAPIKey))
        XCTAssertEqual(viewModel.openAIAPIKeyStatusLabel, "Not configured")
        XCTAssertEqual(viewModel.openAIProviderSmokeStatusLabel, "notConfigured")
        XCTAssertEqual(viewModel.errorMessage, "API key cannot contain whitespace.")
        XCTAssertFalse(viewModel.errorMessage?.contains(keyPrefix) ?? true)
    }

    @MainActor
    func testAppSettingsViewModelShowsOpenAIProviderSmokeNotConfiguredWithoutAPIKey() throws {
        let suiteName = "Suisui.AppSettingsOpenAISmokeNotConfigured.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: InMemorySecretStore()
        )

        XCTAssertEqual(viewModel.openAIProviderSmokeStatusLabel, "notConfigured")
        XCTAssertEqual(viewModel.openAIAPIKeyStatusLabel, "Not configured")
    }

    @MainActor
    func testAppSettingsViewModelSavesAndDeletesOpenRouterKeyInSecretStoreOnly() throws {
        let suiteName = "Suisui.AppSettingsViewModelOpenRouterTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settingsStore = UserDefaultsAppSettingsStore(defaults: defaults)
        let secretStore = InMemorySecretStore()
        let viewModel = AppSettingsViewModel(settingsStore: settingsStore, secretStore: secretStore)

        viewModel.updateOpenRouterAPIKeyInput(" sk-or-test-secret ")
        viewModel.saveOpenRouterAPIKey()

        XCTAssertEqual(try secretStore.read(.openRouterAPIKey), "sk-or-test-secret")
        XCTAssertEqual(viewModel.openRouterAPIKeyStatusLabel, "Configured")
        XCTAssertNil(defaults.data(forKey: "app.settings"))

        viewModel.deleteOpenRouterAPIKey()

        XCTAssertNil(try secretStore.read(.openRouterAPIKey))
        XCTAssertEqual(viewModel.openRouterAPIKeyStatusLabel, "Not configured")
    }

    @MainActor
    func testAppSettingsViewModelSavesAndDeletesAnthropicKeyInSecretStoreOnly() throws {
        let suiteName = "Suisui.AppSettingsViewModelAnthropicTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settingsStore = UserDefaultsAppSettingsStore(defaults: defaults)
        let secretStore = InMemorySecretStore()
        let viewModel = AppSettingsViewModel(settingsStore: settingsStore, secretStore: secretStore)

        viewModel.updateAnthropicAPIKeyInput(" sk-ant-test-secret ")
        viewModel.saveAnthropicAPIKey()

        XCTAssertEqual(try secretStore.read(.anthropicAPIKey), "sk-ant-test-secret")
        XCTAssertEqual(viewModel.anthropicAPIKeyStatusLabel, "Configured")
        XCTAssertNil(defaults.data(forKey: "app.settings"))

        viewModel.deleteAnthropicAPIKey()

        XCTAssertNil(try secretStore.read(.anthropicAPIKey))
        XCTAssertEqual(viewModel.anthropicAPIKeyStatusLabel, "Not configured")
    }

    @MainActor
    func testAppSettingsViewModelSavesAndDeletesGeminiKeyInSecretStoreOnly() throws {
        let suiteName = "Suisui.AppSettingsViewModelGeminiTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settingsStore = UserDefaultsAppSettingsStore(defaults: defaults)
        let secretStore = InMemorySecretStore()
        let viewModel = AppSettingsViewModel(settingsStore: settingsStore, secretStore: secretStore)

        viewModel.updateGeminiAPIKeyInput(" gemini-test-secret ")
        viewModel.saveGeminiAPIKey()

        XCTAssertEqual(try secretStore.read(.geminiAPIKey), "gemini-test-secret")
        XCTAssertEqual(viewModel.geminiAPIKeyStatusLabel, "Configured")
        XCTAssertEqual(viewModel.geminiProviderSmokeStatusLabel, "readyForManualSmoke")
        XCTAssertNil(defaults.data(forKey: "app.settings"))

        viewModel.deleteGeminiAPIKey()

        XCTAssertNil(try secretStore.read(.geminiAPIKey))
        XCTAssertEqual(viewModel.geminiAPIKeyStatusLabel, "Not configured")
        XCTAssertEqual(viewModel.geminiProviderSmokeStatusLabel, "notConfigured")
    }

    @MainActor
    func testAppSettingsViewModelSavesAndDeletesGroqKeyInSecretStoreOnly() throws {
        let suiteName = "Suisui.AppSettingsViewModelGroqTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settingsStore = UserDefaultsAppSettingsStore(defaults: defaults)
        let secretStore = InMemorySecretStore()
        let viewModel = AppSettingsViewModel(settingsStore: settingsStore, secretStore: secretStore)

        viewModel.updateGroqAPIKeyInput(" gsk-test-secret ")
        viewModel.saveGroqAPIKey()

        XCTAssertEqual(try secretStore.read(.groqAPIKey), "gsk-test-secret")
        XCTAssertEqual(viewModel.groqAPIKeyStatusLabel, "Configured")
        XCTAssertEqual(viewModel.groqProviderSmokeStatusLabel, "readyForManualSmoke")
        XCTAssertNil(defaults.data(forKey: "app.settings"))

        viewModel.deleteGroqAPIKey()

        XCTAssertNil(try secretStore.read(.groqAPIKey))
        XCTAssertEqual(viewModel.groqAPIKeyStatusLabel, "Not configured")
        XCTAssertEqual(viewModel.groqProviderSmokeStatusLabel, "notConfigured")
    }

    @MainActor
    func testAppSettingsViewModelSavesAndDeletesCustomKeychainSecretForMCPReferences() throws {
        let suiteName = "Suisui.AppSettingsViewModelCustomSecretTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settingsStore = UserDefaultsAppSettingsStore(defaults: defaults)
        let secretStore = InMemorySecretStore()
        let viewModel = AppSettingsViewModel(settingsStore: settingsStore, secretStore: secretStore)

        viewModel.updateKeychainSecretKeyInput(" github_token ")
        viewModel.updateKeychainSecretValueInput(" mcp-custom-secret ")
        viewModel.saveKeychainSecret()

        XCTAssertEqual(try secretStore.read(.githubToken), "mcp-custom-secret")
        XCTAssertEqual(viewModel.keychainSecretKeyInput, "github_token")
        XCTAssertEqual(viewModel.keychainSecretValueInput, "")
        XCTAssertEqual(viewModel.keychainSecretStatusLabel, "Configured")
        XCTAssertEqual(viewModel.successMessage, "Secret saved to Keychain.")
        XCTAssertNil(defaults.data(forKey: "app.settings"))
        XCTAssertFalse(viewModel.successMessage?.contains("mcp-custom-secret") ?? true)

        viewModel.deleteKeychainSecret()

        XCTAssertNil(try secretStore.read(.githubToken))
        XCTAssertEqual(viewModel.keychainSecretStatusLabel, "Not configured")
        XCTAssertEqual(viewModel.successMessage, "Secret removed.")
    }

    @MainActor
    func testAppSettingsViewModelRejectsInvalidCustomSecretKeyWithoutSavingRawValue() throws {
        let suiteName = "Suisui.AppSettingsViewModelInvalidCustomSecret.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let secretStore = InMemorySecretStore()
        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: secretStore
        )

        viewModel.updateKeychainSecretKeyInput("github token")
        viewModel.updateKeychainSecretValueInput("mcp-should-not-save")
        viewModel.saveKeychainSecret()

        XCTAssertNil(try secretStore.read(SecretKey("github token")))
        XCTAssertEqual(viewModel.keychainSecretStatusLabel, "Invalid key")
        XCTAssertEqual(
            viewModel.errorMessage,
            "Secret key can contain letters, numbers, underscore, hyphen, or dot only."
        )
        XCTAssertFalse(viewModel.errorMessage?.contains("mcp-should-not-save") ?? true)
    }

    @MainActor
    func testAppSettingsViewModelReportsCustomSecretStatusWithoutRevealingValue() throws {
        let suiteName = "Suisui.AppSettingsViewModelCustomSecretStatus.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let secretStore = InMemorySecretStore(values: [SecretKey("github_token"): "mcp-existing-secret"])
        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: secretStore
        )

        viewModel.updateKeychainSecretKeyInput("github_token")

        XCTAssertEqual(viewModel.keychainSecretStatusLabel, "Configured")
        XCTAssertEqual(viewModel.keychainSecretValueInput, "")
        XCTAssertFalse(viewModel.errorMessage?.contains("mcp-existing-secret") ?? false)
        XCTAssertFalse(viewModel.successMessage?.contains("mcp-existing-secret") ?? false)
    }

    @MainActor
    func testAppSettingsViewModelRejectsOpenRouterKeyWithInternalWhitespace() throws {
        let suiteName = "Suisui.AppSettingsViewModelInvalidOpenRouterKey.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settingsStore = UserDefaultsAppSettingsStore(defaults: defaults)
        let secretStore = InMemorySecretStore()
        let viewModel = AppSettingsViewModel(settingsStore: settingsStore, secretStore: secretStore)

        let keyPrefix = "sk" + "-or-live"
        viewModel.updateOpenRouterAPIKeyInput("\(keyPrefix)\ninvalid")
        viewModel.saveOpenRouterAPIKey()

        XCTAssertNil(try secretStore.read(.openRouterAPIKey))
        XCTAssertEqual(viewModel.openRouterAPIKeyStatusLabel, "Not configured")
        XCTAssertEqual(viewModel.errorMessage, "API key cannot contain whitespace.")
        XCTAssertFalse(viewModel.errorMessage?.contains(keyPrefix) ?? true)
    }

    @MainActor
    func testAppSettingsViewModelRejectsAnthropicKeyWithInternalWhitespace() throws {
        let suiteName = "Suisui.AppSettingsViewModelInvalidAnthropicKey.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settingsStore = UserDefaultsAppSettingsStore(defaults: defaults)
        let secretStore = InMemorySecretStore()
        let viewModel = AppSettingsViewModel(settingsStore: settingsStore, secretStore: secretStore)

        let keyPrefix = "sk-ant" + "-live"
        viewModel.updateAnthropicAPIKeyInput("\(keyPrefix)\ninvalid")
        viewModel.saveAnthropicAPIKey()

        XCTAssertNil(try secretStore.read(.anthropicAPIKey))
        XCTAssertEqual(viewModel.anthropicAPIKeyStatusLabel, "Not configured")
        XCTAssertEqual(viewModel.errorMessage, "API key cannot contain whitespace.")
        XCTAssertFalse(viewModel.errorMessage?.contains(keyPrefix) ?? true)
    }

    @MainActor
    func testAppSettingsViewModelRejectsGeminiKeyWithInternalWhitespace() throws {
        let suiteName = "Suisui.AppSettingsViewModelInvalidGeminiKey.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settingsStore = UserDefaultsAppSettingsStore(defaults: defaults)
        let secretStore = InMemorySecretStore()
        let viewModel = AppSettingsViewModel(settingsStore: settingsStore, secretStore: secretStore)

        let keyPrefix = "gemini-live"
        viewModel.updateGeminiAPIKeyInput("\(keyPrefix)\ninvalid")
        viewModel.saveGeminiAPIKey()

        XCTAssertNil(try secretStore.read(.geminiAPIKey))
        XCTAssertEqual(viewModel.geminiAPIKeyStatusLabel, "Not configured")
        XCTAssertEqual(viewModel.geminiProviderSmokeStatusLabel, "notConfigured")
        XCTAssertEqual(viewModel.errorMessage, "API key cannot contain whitespace.")
        XCTAssertFalse(viewModel.errorMessage?.contains(keyPrefix) ?? true)
    }

    @MainActor
    func testAppSettingsViewModelRejectsGroqKeyWithInternalWhitespace() throws {
        let suiteName = "Suisui.AppSettingsViewModelInvalidGroqKey.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settingsStore = UserDefaultsAppSettingsStore(defaults: defaults)
        let secretStore = InMemorySecretStore()
        let viewModel = AppSettingsViewModel(settingsStore: settingsStore, secretStore: secretStore)

        let keyPrefix = "gsk-live"
        viewModel.updateGroqAPIKeyInput("\(keyPrefix)\ninvalid")
        viewModel.saveGroqAPIKey()

        XCTAssertNil(try secretStore.read(.groqAPIKey))
        XCTAssertEqual(viewModel.groqAPIKeyStatusLabel, "Not configured")
        XCTAssertEqual(viewModel.groqProviderSmokeStatusLabel, "notConfigured")
        XCTAssertEqual(viewModel.errorMessage, "API key cannot contain whitespace.")
        XCTAssertFalse(viewModel.errorMessage?.contains(keyPrefix) ?? true)
    }

    @MainActor
    func testAppSettingsViewModelPersistsNonSecretSettings() throws {
        let suiteName = "Suisui.AppSettingsViewModelSettings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        let viewModel = AppSettingsViewModel(settingsStore: store, secretStore: InMemorySecretStore())

        viewModel.setNotificationsEnabled(true)
        viewModel.setDefaultWorkspacePath("/tmp/Suisui")
        viewModel.setGeminiModelID(" gemini-3.5-flash ")
        viewModel.setGroqBaseURLString(" https://api.groq.com/openai/v1 ")
        viewModel.setOpenCodeExecutablePath(" opencode ")
        viewModel.setOpenCodeWorkspacePath(" /tmp ")
        viewModel.setOpenCodeModelID(" opencode-go/kimi-k2.7-code ")
        viewModel.setOpenCodeLocalExecutionApproved(true)
        viewModel.setWhisperCppExecutablePath(" /opt/homebrew/bin/whisper-cli ")
        viewModel.setLowLatencyVoiceAgentModeEnabled(true)
        viewModel.setLowLatencyVoiceAgentCloudFallbackCostVisible(true)
        viewModel.setLowLatencyVoiceAgentCloudFallbackEnabled(true)
        viewModel.saveSettings()

        let loaded = try store.load()

        XCTAssertTrue(loaded.notificationsEnabled)
        XCTAssertEqual(loaded.defaultWorkspacePath, "/tmp/Suisui")
        XCTAssertEqual(loaded.geminiModelID, "gemini-3.5-flash")
        XCTAssertEqual(loaded.groqBaseURLString, "https://api.groq.com/openai/v1")
        XCTAssertEqual(loaded.openCodeExecutablePath, "opencode")
        XCTAssertEqual(loaded.openCodeWorkspacePath, "/tmp")
        XCTAssertEqual(loaded.openCodeModelID, "opencode-go/kimi-k2.7-code")
        XCTAssertTrue(loaded.isOpenCodeLocalExecutionApproved)
        XCTAssertEqual(loaded.whisperCppExecutablePath, "/opt/homebrew/bin/whisper-cli")
        XCTAssertTrue(loaded.isLowLatencyVoiceAgentModeEnabled)
        XCTAssertTrue(loaded.isLowLatencyVoiceAgentCloudFallbackCostVisible)
        XCTAssertTrue(loaded.isLowLatencyVoiceAgentCloudFallbackEnabled)
    }

    @MainActor
    func testAppSettingsViewModelPersistsVoiceRoutingPreferences() throws {
        let suiteName = "Suisui.AppSettingsViewModelVoiceRouting.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        let viewModel = AppSettingsViewModel(settingsStore: store, secretStore: InMemorySecretStore())

        viewModel.setSTTRoutingPreference(.localFirst)
        viewModel.setTTSRoutingPreference(.localFirst)
        viewModel.saveSettings()

        let loaded = try store.load()

        XCTAssertEqual(loaded.sttRoutingPreference, .localFirst)
        XCTAssertEqual(loaded.ttsRoutingPreference, .localFirst)
    }

    @MainActor
    func testAppSettingsViewModelReportsSettingsSaveFailureWithoutInternalErrorName() throws {
        let viewModel = AppSettingsViewModel(
            settingsStore: FailingSaveAppSettingsStore(),
            secretStore: InMemorySecretStore()
        )

        viewModel.setNotificationsEnabled(true)
        viewModel.saveSettings()

        XCTAssertEqual(viewModel.errorMessage, "App settings could not be saved.")
        XCTAssertFalse(viewModel.errorMessage?.contains("unexpectedStatus") ?? true)
        XCTAssertNil(viewModel.successMessage)
    }

    @MainActor
    func testAppSettingsViewModelReportsAPIKeySaveFailureWithoutInternalStatusOrRawKey() throws {
        let rawKey = "sk-live-secret-value"
        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: try makeUserDefaults("APIKeySaveFailure")),
            secretStore: FailingWriteSecretStore(saveError: SecretStoreError.unexpectedStatus(-34018))
        )

        viewModel.updateOpenAIAPIKeyInput(rawKey)
        viewModel.saveOpenAIAPIKey()

        XCTAssertEqual(viewModel.errorMessage, "API key could not be saved to Keychain.")
        XCTAssertFalse(viewModel.errorMessage?.contains(rawKey) ?? true)
        XCTAssertFalse(viewModel.errorMessage?.contains("unexpectedStatus") ?? true)
        XCTAssertNil(viewModel.successMessage)
    }

    @MainActor
    func testAppSettingsViewModelReportsAPIKeyDeleteFailureWithoutInternalStatus() throws {
        let secretStore = FailingWriteSecretStore(
            values: [.openRouterAPIKey: "sk-or-live-secret"],
            deleteError: SecretStoreError.unexpectedStatus(-25300)
        )
        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: try makeUserDefaults("APIKeyDeleteFailure")),
            secretStore: secretStore
        )

        viewModel.deleteOpenRouterAPIKey()

        XCTAssertEqual(viewModel.errorMessage, "API key could not be removed from Keychain.")
        XCTAssertFalse(viewModel.errorMessage?.contains("unexpectedStatus") ?? true)
        XCTAssertNil(viewModel.successMessage)
        XCTAssertEqual(try secretStore.read(.openRouterAPIKey), "sk-or-live-secret")
    }

    func testAppSettingsValidatesGroqBaseURLBeforeSaving() {
        let blank = AppSettings(groqBaseURLString: "   ")
        let insecure = AppSettings(groqBaseURLString: "http://api.groq.com/openai/v1")
        let missingHost = AppSettings(groqBaseURLString: "https:///openai/v1")
        let valid = AppSettings(groqBaseURLString: "https://api.groq.com/openai/v1")

        XCTAssertEqual(blank.validate().first?.field, "groqBaseURLString")
        XCTAssertEqual(insecure.validate().first?.message, "Groq base URL must be an HTTPS URL with a host.")
        XCTAssertEqual(missingHost.validate().first?.message, "Groq base URL must be an HTTPS URL with a host.")
        XCTAssertTrue(valid.validate().isEmpty)
    }

    func testAppSettingsValidatesOpenCodeLocalSettingsOnlyWhenSelected() {
        let inactive = AppSettings(
            aiProvider: .openaiResponses,
            openCodeExecutablePath: nil,
            openCodeWorkspacePath: nil,
            openCodeModelID: nil,
            isOpenCodeLocalExecutionApproved: false
        )
        let missingConfig = AppSettings(
            aiProvider: .opencodeLocal,
            openCodeExecutablePath: nil,
            openCodeWorkspacePath: nil,
            openCodeModelID: nil,
            isOpenCodeLocalExecutionApproved: false
        )
        let authJSONExecutable = AppSettings(
            aiProvider: .opencodeLocal,
            openCodeExecutablePath: "~/.local/share/opencode/auth.json",
            openCodeWorkspacePath: "/tmp",
            openCodeModelID: "opencode-go/kimi-k2.7-code",
            isOpenCodeLocalExecutionApproved: true
        )
        let whitespaceModel = AppSettings(
            aiProvider: .opencodeLocal,
            openCodeExecutablePath: "opencode",
            openCodeWorkspacePath: "/tmp",
            openCodeModelID: "provider/model bad",
            isOpenCodeLocalExecutionApproved: true
        )

        XCTAssertTrue(inactive.validate().isEmpty)
        XCTAssertEqual(
            missingConfig.validate().map(\.field),
            [
                "openCodeExecutablePath",
                "openCodeWorkspacePath",
                "openCodeModelID",
                "isOpenCodeLocalExecutionApproved"
            ]
        )
        XCTAssertEqual(authJSONExecutable.validate().first?.message, "OpenCode executable path must not point to auth.json.")
        XCTAssertEqual(whitespaceModel.validate().first?.message, "OpenCode model id cannot contain whitespace.")
    }

    func testAppSettingsValidatesWhisperCppExecutablePathOnlyWhenSelected() {
        let inactive = AppSettings(sttProvider: .openAITranscribe, whisperCppExecutablePath: nil)
        let missingConfig = AppSettings(sttProvider: .localWhisperCpp, whisperCppExecutablePath: nil)
        let relativeExecutable = AppSettings(sttProvider: .localWhisperCpp, whisperCppExecutablePath: "whisper-cli")
        let credentialPath = AppSettings(sttProvider: .localWhisperCpp, whisperCppExecutablePath: "/tmp/token.json")
        let valid = AppSettings(sttProvider: .localWhisperCpp, whisperCppExecutablePath: "/opt/homebrew/bin/whisper-cli")

        XCTAssertTrue(inactive.validate().isEmpty)
        XCTAssertEqual(missingConfig.validate().first?.field, "whisperCppExecutablePath")
        XCTAssertEqual(relativeExecutable.validate().first?.message, "whisper.cpp executable path must be absolute.")
        XCTAssertEqual(credentialPath.validate().first?.message, "whisper.cpp executable path must not point to a credential or token file.")
        XCTAssertFalse(valid.validate().contains { $0.field == "whisperCppExecutablePath" })
    }

    func testRuntimeNormalizationPreservesUnavailableProviderForFailClosedRuntime() {
        let settings = AppSettings(aiProvider: .geminiOpenAICompatible)

        let normalized = settings.normalizedForRuntime

        XCTAssertEqual(normalized.aiProvider, .geminiOpenAICompatible)
        XCTAssertEqual(normalized.validate().map(\.field), ["aiProvider"])
    }

    func testAppSettingsDefaultsDeveloperModeOffForLocalShellSafety() {
        XCTAssertFalse(AppSettings.default.isDeveloperModeEnabled)
        XCTAssertFalse(AppSettings().isDeveloperModeEnabled)
    }

    @MainActor
    func testAppSettingsViewModelPersistsProviderSelection() throws {
        let suiteName = "Suisui.AppSettingsViewModelProviders.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        let viewModel = AppSettingsViewModel(settingsStore: store, secretStore: InMemorySecretStore())

        viewModel.setAIProvider(.groqOpenAICompatible)
        viewModel.setSTTProvider(.openAITranscribe)
        viewModel.saveSettings()

        let loaded = try store.load()

        XCTAssertEqual(loaded.aiProvider, .groqOpenAICompatible)
        XCTAssertEqual(loaded.sttProvider, .openAITranscribe)
    }

    @MainActor
    func testAppSettingsViewModelPersistsDeveloperModeOptIn() throws {
        let suiteName = "Suisui.AppSettingsViewModelDeveloperMode.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        let viewModel = AppSettingsViewModel(settingsStore: store, secretStore: InMemorySecretStore())

        viewModel.setDeveloperModeEnabled(true)
        viewModel.saveSettings()

        let loaded = try store.load()

        XCTAssertTrue(loaded.isDeveloperModeEnabled)
    }

    @MainActor
    func testAppSettingsViewModelCanDeferProviderSecretReadsUntilSettingsOpen() throws {
        let defaults = try makeUserDefaults("DeferredProviderSecretReads")
        let secretStore = CountingSecretStore(values: [
            .openAIAPIKey: "sk-test-deferred-key",
            .anthropicAPIKey: "sk-ant-test",
            .geminiAPIKey: "gemini-test",
            .groqAPIKey: "gsk_test",
            .openRouterAPIKey: "sk-or-test"
        ])
        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: secretStore,
            refreshProviderSecretStatusesOnInit: false
        )

        XCTAssertEqual(secretStore.readCount, 0)
        XCTAssertEqual(viewModel.openAIAPIKeyStatusLabel, "Not configured")

        XCTAssertTrue(viewModel.refreshProviderSecretStatuses())
        XCTAssertEqual(secretStore.readCount, 5)
        XCTAssertEqual(viewModel.openAIAPIKeyStatusLabel, "Configured")
        XCTAssertEqual(viewModel.anthropicAPIKeyStatusLabel, "Configured")
        XCTAssertEqual(viewModel.geminiAPIKeyStatusLabel, "Configured")
        XCTAssertEqual(viewModel.groqAPIKeyStatusLabel, "Configured")
        XCTAssertEqual(viewModel.openRouterAPIKeyStatusLabel, "Configured")
    }

    @MainActor
    func testAppSettingsViewModelSelectsWhisperCppOnlyWhenExecutableAndModelAreReady() throws {
        let suiteName = "Suisui.AppSettingsViewModelWhisperCppReady.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        let executableURL = try writeExecutable(named: "whisper-cli")
        let viewModel = AppSettingsViewModel(
            settingsStore: store,
            secretStore: InMemorySecretStore(),
            voiceModelManager: StaticAppSettingsVoiceModelManager(statuses: [.whisperCppTinyMultilingual: .installed])
        )

        viewModel.setWhisperCppExecutablePath(executableURL.path)

        XCTAssertEqual(viewModel.selectableSTTProviders, [.appleSpeechAnalyzer, .openAITranscribe, .localWhisperCpp])

        viewModel.setSTTProvider(.localWhisperCpp)
        viewModel.saveSettings()

        XCTAssertEqual(viewModel.settings.sttProvider, .localWhisperCpp)
        XCTAssertEqual(try store.load().sttProvider, .localWhisperCpp)
        XCTAssertEqual(try store.load().whisperCppExecutablePath, executableURL.path)
    }

    @MainActor
    func testAppSettingsViewModelRejectsWhisperCppSelectionUntilModelAndExecutableAreReady() throws {
        let suiteName = "Suisui.AppSettingsViewModelWhisperCppUnavailable.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        let executableURL = try writeExecutable(named: "whisper-cli")
        let viewModel = AppSettingsViewModel(
            settingsStore: store,
            secretStore: InMemorySecretStore(),
            voiceModelManager: StaticAppSettingsVoiceModelManager(statuses: [.whisperCppTinyMultilingual: .notInstalled])
        )

        viewModel.setWhisperCppExecutablePath(executableURL.path)
        viewModel.setSTTProvider(.localWhisperCpp)

        XCTAssertEqual(viewModel.selectableSTTProviders, [.appleSpeechAnalyzer, .openAITranscribe])
        XCTAssertEqual(viewModel.settings.sttProvider, .openAITranscribe)
        XCTAssertEqual(viewModel.errorMessage, "Install the whisper.cpp model and configure the executable before selecting offline speech to text.")
    }

    @MainActor
    func testAppSettingsViewModelReportsWhisperCppSTTReadinessStages() throws {
        let suiteName = "Suisui.AppSettingsViewModelWhisperCppReadiness.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let executableURL = try writeExecutable(named: "whisper-cli")
        let missingModelViewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: InMemorySecretStore(),
            voiceModelManager: StaticAppSettingsVoiceModelManager(statuses: [
                .whisperCppTinyMultilingual: .notInstalled
            ])
        )

        XCTAssertEqual(missingModelViewModel.localSTTProviderReadinessRow.statusLabel, "Model not installed")
        XCTAssertEqual(missingModelViewModel.localSTTProviderReadinessRow.nextActionLabel, "Download whisper.cpp model")
        XCTAssertFalse(missingModelViewModel.localSTTProviderReadinessRow.isReady)

        let runtimePendingViewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: InMemorySecretStore(),
            voiceModelManager: StaticAppSettingsVoiceModelManager(statuses: [
                .whisperCppTinyMultilingual: .installed
            ])
        )

        XCTAssertEqual(runtimePendingViewModel.localSTTProviderReadinessRow.statusLabel, "Runtime pending")
        XCTAssertEqual(runtimePendingViewModel.localSTTProviderReadinessRow.nextActionLabel, "Configure whisper.cpp executable")
        XCTAssertFalse(runtimePendingViewModel.localSTTProviderReadinessRow.isReady)

        runtimePendingViewModel.setWhisperCppExecutablePath(executableURL.path)

        XCTAssertEqual(runtimePendingViewModel.localSTTProviderReadinessRow.statusLabel, "Smoke pending")
        XCTAssertEqual(
            runtimePendingViewModel.localSTTProviderReadinessRow.detailLabel,
            "Model and executable are ready; run the local voice runtime smoke before release closeout."
        )
        XCTAssertEqual(runtimePendingViewModel.localSTTProviderReadinessRow.nextActionLabel, "Run local voice smoke")
        XCTAssertFalse(runtimePendingViewModel.localSTTProviderReadinessRow.isReady)
    }

    @MainActor
    func testAppSettingsViewModelPersistsProviderSelectionWhenSelected() throws {
        let suiteName = "Suisui.AppSettingsViewModelProviderAutoSave.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        let viewModel = AppSettingsViewModel(settingsStore: store, secretStore: InMemorySecretStore())

        viewModel.selectAIProviderAndSave(.claudeMessages)

        XCTAssertEqual(viewModel.settings.aiProvider, .claudeMessages)
        XCTAssertEqual(try store.load().aiProvider, .claudeMessages)
        XCTAssertEqual(viewModel.successMessage, "Settings saved.")
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testAppSettingsViewModelBuildsProviderReadinessRowsWithoutSecrets() throws {
        let suiteName = "Suisui.AppSettingsProviderReadinessRows.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        try store.save(
            AppSettings(
                aiProvider: .opencodeLocal,
                openCodeExecutablePath: "/opt/homebrew/bin/opencode",
                openCodeWorkspacePath: "/tmp/Suisui",
                openCodeModelID: "anthropic/claude-sonnet-4-5",
                isOpenCodeLocalExecutionApproved: true
            )
        )
        let openAISecret = "sk-secret-openai"
        let geminiSecret = "gemini-secret"
        let secretStore = InMemorySecretStore(values: [
            .openAIAPIKey: openAISecret,
            .geminiAPIKey: geminiSecret
        ])
        let viewModel = AppSettingsViewModel(settingsStore: store, secretStore: secretStore)

        XCTAssertEqual(viewModel.providerReadinessRows.map(\.provider), viewModel.selectableAIProviders)
        XCTAssertFalse(viewModel.providerReadinessRows.contains { $0.provider == .geminiOpenAICompatible })

        let openAIRow = try XCTUnwrap(viewModel.providerReadinessRows.first { $0.provider == .openaiResponses })
        XCTAssertEqual(openAIRow.statusLabel, "Configured")
        XCTAssertEqual(openAIRow.detailLabel, "Smoke: Ready for manual smoke")
        XCTAssertEqual(openAIRow.nextActionLabel, "Generate a reviewed plan or run a manual smoke check.")
        XCTAssertFalse(openAIRow.isSelected)
        XCTAssertEqual(openAIRow.readiness, .ready)

        let claudeRow = try XCTUnwrap(viewModel.providerReadinessRows.first { $0.provider == .claudeMessages })
        XCTAssertEqual(claudeRow.statusLabel, "Not configured")
        XCTAssertEqual(claudeRow.nextActionLabel, "Save the provider API key in Keychain.")
        XCTAssertEqual(claudeRow.readiness, .needsAction(reason: "Save the provider API key in Keychain."))

        let openCodeRow = try XCTUnwrap(viewModel.providerReadinessRows.first { $0.provider == .opencodeLocal })
        XCTAssertEqual(openCodeRow.statusLabel, "Approved")
        XCTAssertEqual(openCodeRow.detailLabel, "Local execution is approved for the selected workspace.")
        XCTAssertTrue(openCodeRow.isSelected)
        XCTAssertEqual(openCodeRow.readiness, .ready)

        let ollamaRow = try XCTUnwrap(viewModel.providerReadinessRows.first { $0.provider == .ollamaCompatible })
        XCTAssertEqual(ollamaRow.statusLabel, "Local")
        XCTAssertEqual(ollamaRow.detailLabel, "Local endpoint; API key is not required.")
        XCTAssertEqual(ollamaRow.readiness, .needsAction(reason: "Start the local Ollama-compatible server before planning."))

        let onboarding = viewModel.onboardingReadinessSnapshot(permissionSnapshot: .empty)
        XCTAssertEqual(onboarding.selectedProvider, .opencodeLocal)
        XCTAssertEqual(onboarding.planningState, .ready)
        XCTAssertEqual(onboarding.items.count, 5)

        let renderedLabels = viewModel.providerReadinessRows
            .flatMap { [$0.provider.displayName, $0.statusLabel, $0.detailLabel, $0.nextActionLabel] }
            .joined(separator: "\n")
        XCTAssertFalse(renderedLabels.contains(openAISecret))
        XCTAssertFalse(renderedLabels.contains(geminiSecret))
    }

    @MainActor
    func testAppSettingsViewModelRejectsUnavailableAIProviderSelection() throws {
        let suiteName = "Suisui.AppSettingsUnavailableAIProvider.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        let viewModel = AppSettingsViewModel(settingsStore: store, secretStore: InMemorySecretStore())

        XCTAssertEqual(
            viewModel.selectableAIProviders,
            [.openaiResponses, .claudeMessages, .geminiDirect, .groqOpenAICompatible, .codexLocal, .opencodeLocal, .openRouterCompatible, .ollamaCompatible]
        )

        viewModel.setAIProvider(.geminiOpenAICompatible)
        viewModel.saveSettings()

        XCTAssertEqual(viewModel.settings.aiProvider, .openaiResponses)
        XCTAssertEqual(viewModel.errorMessage, "Gemini OpenAI-compatible is not available in this build.")
        XCTAssertNil(defaults.data(forKey: "app.settings"))
    }

    @MainActor
    func testAppSettingsViewModelPreservesStoredUnavailableProviderForRepair() throws {
        let suiteName = "Suisui.AppSettingsStoredUnavailableAIProvider.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        try store.save(AppSettings(aiProvider: .geminiOpenAICompatible))

        let viewModel = AppSettingsViewModel(settingsStore: store, secretStore: InMemorySecretStore())

        XCTAssertEqual(viewModel.settings.aiProvider, .geminiOpenAICompatible)
        XCTAssertFalse(viewModel.selectableAIProviders.contains(.geminiOpenAICompatible))

        viewModel.saveSettings()

        XCTAssertEqual(viewModel.settings.aiProvider, .geminiOpenAICompatible)
        XCTAssertEqual(viewModel.errorMessage, "Gemini OpenAI-compatible is not available in this build.")
    }

    func testLegacyAIProviderRawValuesAreMigratedWhenSettingsLoad() throws {
        let decoder = JSONDecoder()
        let template = """
        {
          "aiProvider": "%@",
          "sttProvider": "openAITranscribe",
          "notificationsEnabled": false,
          "defaultWorkspacePath": null,
          "timeZoneIdentifier": "UTC"
        }
        """

        let openRouterData = Data(String(format: template, "openRouter").utf8)
        let ollamaData = Data(String(format: template, "ollama").utf8)
        let openAICompatibleData = Data(String(format: template, "openAICompatible").utf8)
        let openAIResponsesData = Data(String(format: template, "openAIResponses").utf8)

        let openRouterSettings = try decoder.decode(AppSettings.self, from: openRouterData)
        let ollamaSettings = try decoder.decode(AppSettings.self, from: ollamaData)
        let openAICompatibleSettings = try decoder.decode(AppSettings.self, from: openAICompatibleData)
        let openAIResponsesSettings = try decoder.decode(AppSettings.self, from: openAIResponsesData)

        XCTAssertEqual(openRouterSettings.aiProvider, .openRouterCompatible)
        XCTAssertEqual(ollamaSettings.aiProvider, .ollamaCompatible)
        XCTAssertEqual(openAICompatibleSettings.aiProvider, .openaiResponses)
        XCTAssertEqual(openAIResponsesSettings.aiProvider, .openaiResponses)
        XCTAssertFalse(openRouterSettings.isOpenCodeLocalExecutionApproved)
        XCTAssertNil(openRouterSettings.openCodeExecutablePath)
        XCTAssertNil(openRouterSettings.openCodeWorkspacePath)
        XCTAssertNil(openRouterSettings.openCodeModelID)
        XCTAssertEqual(openRouterSettings.googleCalendarID, "primary")
    }

    func testDefaultWorkspacePathMustBeAnAbsoluteDirectoryLocation() {
        let relativeSettings = AppSettings(defaultWorkspacePath: "relative/project")
        let fileSettings = AppSettings(defaultWorkspacePath: "/tmp/suisui-token.json")
        let absoluteSettings = AppSettings(defaultWorkspacePath: "/tmp/Suisui")

        XCTAssertEqual(
            relativeSettings.validate().first { $0.field == "defaultWorkspacePath" }?.message,
            "Default workspace path must be an absolute directory path."
        )
        XCTAssertEqual(
            fileSettings.validate().first { $0.field == "defaultWorkspacePath" }?.message,
            "Default workspace path must not point to a credential or token file."
        )
        XCTAssertFalse(absoluteSettings.validate().contains { $0.field == "defaultWorkspacePath" })
    }

    func testTTSProvidersExposeAppleSystemSpeechAndLocalKokoro() {
        XCTAssertEqual(TTSProvider.releaseReadyCases, [.systemSpeech, .localKokoro])
        XCTAssertTrue(TTSProvider.systemSpeech.isReleaseReady)
        XCTAssertTrue(TTSProvider.localKokoro.isReleaseReady)
        XCTAssertEqual(TTSProvider.systemSpeech.displayName, "System Speech")
        XCTAssertEqual(TTSProvider.localKokoro.displayName, "Local Kokoro")
        XCTAssertEqual(TTSProvider.systemSpeech.unavailableReason, "Uses voices installed in macOS.")
        XCTAssertEqual(TTSProvider.localKokoro.unavailableReason, "Install the Kokoro model and configure the executable in Settings.")
    }

    func testSystemSpeechPreservesInstalledMacOSVoiceIdentifier() {
        var settings = AppSettings(
            ttsProvider: .systemSpeech,
            ttsLanguageCode: "en",
            ttsVoiceID: "af_heart"
        )
        settings.systemSpeechVoiceID = "com.apple.voice.compact.en-US.Samantha"

        XCTAssertEqual(
            settings.normalizedForRuntime.selectedTTSVoiceID,
            "com.apple.voice.compact.en-US.Samantha"
        )
        XCTAssertFalse(settings.validate().contains { $0.field == "ttsVoiceID" })
    }

    @MainActor
    func testSystemSpeechReadinessRejectsMissingAndWrongLanguageVoiceIdentifiers() throws {
        let suiteName = "Suisui.SystemSpeechReadiness.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var settings = AppSettings(
            ttsProvider: .systemSpeech,
            ttsLanguageCode: "en",
            ttsVoiceID: "af_heart"
        )
        settings.systemSpeechVoiceID = "com.apple.voice.compact.ja-JP.Kyoko"
        try UserDefaultsAppSettingsStore(defaults: defaults).save(settings)
        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: InMemorySecretStore(),
            appleSpeechReadinessProvider: { .permissionNotDetermined },
            systemSpeechReadinessProvider: {
                SystemSpeechReadinessSnapshot(
                    isAvailable: true,
                    isInventoryAuthoritative: true,
                    voices: [
                        SystemSpeechVoiceOption(
                            identifier: "com.apple.voice.compact.en-US.Samantha",
                            name: "Samantha",
                            languageCode: "en-US"
                        ),
                        SystemSpeechVoiceOption(
                            identifier: "com.apple.voice.compact.ja-JP.Kyoko",
                            name: "Kyoko",
                            languageCode: "ja-JP"
                        )
                    ]
                )
            }
        )

        XCTAssertEqual(viewModel.ttsProviderReadinessRow.statusLabel, "Checking")
        XCTAssertFalse(viewModel.ttsProviderReadinessRow.isReady)

        viewModel.refreshSystemSpeechReadiness()

        XCTAssertEqual(viewModel.ttsProviderReadinessRow.statusLabel, "Voice unavailable")
        XCTAssertFalse(viewModel.ttsProviderReadinessRow.isReady)
        XCTAssertEqual(
            viewModel.selectableSystemSpeechVoices.map(\.identifier),
            ["com.apple.voice.compact.en-US.Samantha"]
        )

        viewModel.setSystemSpeechVoiceID("com.apple.voice.compact.en-US.Samantha")

        XCTAssertEqual(viewModel.ttsProviderReadinessRow.statusLabel, "Ready")
        XCTAssertTrue(viewModel.ttsProviderReadinessRow.isReady)
    }

    @MainActor
    func testSystemSpeechReadinessAllowsSystemDefaultWhenLanguageVoiceExists() throws {
        let suiteName = "Suisui.SystemSpeechDefaultVoice.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: InMemorySecretStore(),
            appleSpeechReadinessProvider: { .permissionNotDetermined },
            systemSpeechReadinessProvider: {
                SystemSpeechReadinessSnapshot(
                    isAvailable: true,
                    isInventoryAuthoritative: true,
                    voices: [
                        SystemSpeechVoiceOption(
                            identifier: "com.apple.voice.compact.en-US.Samantha",
                            name: "Samantha",
                            languageCode: "en-US"
                        )
                    ]
                )
            }
        )
        viewModel.setTTSProvider(.systemSpeech)
        viewModel.refreshSystemSpeechReadiness()

        XCTAssertNil(viewModel.settings.systemSpeechVoiceID)
        XCTAssertEqual(viewModel.ttsProviderReadinessRow.statusLabel, "Ready")
        XCTAssertTrue(viewModel.ttsProviderReadinessRow.isReady)
    }

    @MainActor
    func testVoiceFrameworkReadinessIsLoadedOnDemandInsteadOfDuringSettingsInitialization() throws {
        let suiteName = "Suisui.LazyVoiceFrameworkReadiness.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appleSpeechProvider = CountingAppleSpeechReadinessProvider()
        let systemSpeechProvider = CountingSystemSpeechReadinessProvider()

        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: InMemorySecretStore(),
            appleSpeechReadinessProvider: appleSpeechProvider.read,
            systemSpeechReadinessProvider: systemSpeechProvider.read
        )

        XCTAssertEqual(appleSpeechProvider.readCount, 0)
        XCTAssertEqual(systemSpeechProvider.readCount, 0)

        viewModel.refreshAppleSpeechReadiness()
        viewModel.refreshSystemSpeechReadiness()

        XCTAssertEqual(appleSpeechProvider.readCount, 1)
        XCTAssertEqual(systemSpeechProvider.readCount, 1)
    }

    func testKokoroStillRejectsVoiceIdentifierForWrongLanguage() {
        let settings = AppSettings(
            ttsProvider: .localKokoro,
            ttsLanguageCode: "ja",
            ttsVoiceID: "com.apple.voice.compact.ja-JP.Kyoko"
        )

        XCTAssertEqual(settings.normalizedForRuntime.ttsVoiceID, "jf_alpha")
        XCTAssertTrue(settings.validate().contains { $0.field == "ttsVoiceID" })
    }

    @MainActor
    func testAppSettingsViewModelAllowsAppleVoiceProviderSelectionWithoutExternalRuntime() throws {
        let suiteName = "Suisui.AppSettingsViewModelAppleVoiceProviders.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        let viewModel = AppSettingsViewModel(
            settingsStore: store,
            secretStore: InMemorySecretStore(),
            appleSpeechReadinessProvider: {
                AppleSpeechReadinessSnapshot(
                    authorization: .authorized,
                    isRecognizerAvailable: true,
                    supportsOnDeviceRecognition: true
                )
            }
        )

        XCTAssertTrue(viewModel.selectableSTTProviders.contains(.appleSpeechAnalyzer))
        XCTAssertTrue(viewModel.selectableTTSProviders.contains(.systemSpeech))

        viewModel.setSTTProvider(.appleSpeechAnalyzer)
        viewModel.setTTSProvider(.systemSpeech)
        viewModel.saveSettings()

        XCTAssertEqual(viewModel.settings.sttProvider, .appleSpeechAnalyzer)
        XCTAssertEqual(viewModel.settings.ttsProvider, .systemSpeech)
        XCTAssertEqual(viewModel.selectedSTTProviderReadinessRow.statusLabel, "Ready")
        XCTAssertTrue(viewModel.selectedSTTProviderReadinessRow.isReady)
        XCTAssertEqual(viewModel.ttsProviderReadinessRow.statusLabel, "Ready")
        XCTAssertTrue(viewModel.ttsProviderReadinessRow.isReady)
        XCTAssertEqual(try store.load().sttProvider, .appleSpeechAnalyzer)
        XCTAssertEqual(try store.load().ttsProvider, .systemSpeech)
    }

    @MainActor
    func testAppleSpeechReadinessReflectsPermissionAndOnDeviceSupport() throws {
        let suiteName = "Suisui.AppSettingsViewModelAppleSpeechReadiness.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let denied = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: InMemorySecretStore(),
            appleSpeechReadinessProvider: {
                AppleSpeechReadinessSnapshot(
                    authorization: .denied,
                    isRecognizerAvailable: true,
                    supportsOnDeviceRecognition: true
                )
            }
        )
        denied.setSTTProvider(.appleSpeechAnalyzer)
        XCTAssertEqual(denied.selectedSTTProviderReadinessRow.statusLabel, "Permission denied")
        XCTAssertEqual(denied.selectedSTTProviderReadinessRow.nextActionLabel, "Open System Settings")
        XCTAssertFalse(denied.selectedSTTProviderReadinessRow.isReady)

        let restricted = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: InMemorySecretStore(),
            appleSpeechReadinessProvider: {
                AppleSpeechReadinessSnapshot(
                    authorization: .restricted,
                    isRecognizerAvailable: true,
                    supportsOnDeviceRecognition: true
                )
            }
        )
        restricted.setSTTProvider(.appleSpeechAnalyzer)
        XCTAssertEqual(restricted.selectedSTTProviderReadinessRow.statusLabel, "Restricted")
        XCTAssertEqual(restricted.selectedSTTProviderReadinessRow.nextActionLabel, "Select another provider")
        XCTAssertFalse(restricted.selectedSTTProviderReadinessRow.isReady)

        let unsupported = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: InMemorySecretStore(),
            appleSpeechReadinessProvider: {
                AppleSpeechReadinessSnapshot(
                    authorization: .authorized,
                    isRecognizerAvailable: true,
                    supportsOnDeviceRecognition: false
                )
            }
        )
        unsupported.setSTTProvider(.appleSpeechAnalyzer)
        XCTAssertEqual(unsupported.selectedSTTProviderReadinessRow.statusLabel, "Unsupported")
        XCTAssertFalse(unsupported.selectedSTTProviderReadinessRow.isReady)

        let unavailable = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: InMemorySecretStore(),
            appleSpeechReadinessProvider: {
                AppleSpeechReadinessSnapshot(
                    authorization: .authorized,
                    isRecognizerAvailable: false,
                    supportsOnDeviceRecognition: true
                )
            }
        )
        unavailable.setSTTProvider(.appleSpeechAnalyzer)
        XCTAssertEqual(unavailable.selectedSTTProviderReadinessRow.statusLabel, "Unavailable")
        XCTAssertEqual(unavailable.selectedSTTProviderReadinessRow.nextActionLabel, "Try again later")
        XCTAssertFalse(unavailable.selectedSTTProviderReadinessRow.isReady)
    }

    @MainActor
    func testAppleSpeechReadinessDistinguishesPermissionRequestFromReady() throws {
        let suiteName = "Suisui.AppSettingsViewModelAppleSpeechPermission.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let permissionRequired = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: InMemorySecretStore(),
            appleSpeechReadinessProvider: {
                AppleSpeechReadinessSnapshot(
                    authorization: .notDetermined,
                    isRecognizerAvailable: true,
                    supportsOnDeviceRecognition: true
                )
            }
        )
        permissionRequired.setSTTProvider(.appleSpeechAnalyzer)
        XCTAssertEqual(permissionRequired.selectedSTTProviderReadinessRow.statusLabel, "Permission required")
        XCTAssertFalse(permissionRequired.selectedSTTProviderReadinessRow.isReady)

        let ready = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: InMemorySecretStore(),
            appleSpeechReadinessProvider: {
                AppleSpeechReadinessSnapshot(
                    authorization: .authorized,
                    isRecognizerAvailable: true,
                    supportsOnDeviceRecognition: true
                )
            }
        )
        ready.setSTTProvider(.appleSpeechAnalyzer)
        XCTAssertEqual(ready.selectedSTTProviderReadinessRow.statusLabel, "Ready")
        XCTAssertTrue(ready.selectedSTTProviderReadinessRow.isReady)
    }

    @MainActor
    func testAppleSpeechReadinessRefreshPublishesAuthorizationTransition() throws {
        let suiteName = "Suisui.AppSettingsViewModelAppleSpeechRefresh.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let readiness = LockedAppleSpeechReadinessProvider(snapshot: .permissionNotDetermined)
        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: InMemorySecretStore(),
            appleSpeechReadinessProvider: { readiness.read() }
        )
        viewModel.setSTTProvider(.appleSpeechAnalyzer)
        XCTAssertEqual(viewModel.selectedSTTProviderReadinessRow.statusLabel, "Permission required")

        readiness.write(
            AppleSpeechReadinessSnapshot(
                authorization: .authorized,
                isRecognizerAvailable: true,
                supportsOnDeviceRecognition: true
            )
        )
        viewModel.refreshAppleSpeechReadiness()

        XCTAssertEqual(viewModel.selectedSTTProviderReadinessRow.statusLabel, "Ready")
        XCTAssertTrue(viewModel.selectedSTTProviderReadinessRow.isReady)
    }

    @MainActor
    func testTTSProviderRoundTripPreservesProviderSpecificVoiceIDs() throws {
        let suiteName = "Suisui.AppSettingsViewModelProviderVoiceRoundTrip.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: InMemorySecretStore()
        )

        viewModel.setTTSProvider(.systemSpeech)
        viewModel.setTTSVoiceID("com.apple.voice.compact.en-US.Samantha")
        viewModel.setTTSProvider(.localKokoro)
        viewModel.setTTSVoiceID("af_heart")
        viewModel.setTTSProvider(.systemSpeech)
        viewModel.saveSettings()

        XCTAssertEqual(
            viewModel.settings.selectedTTSVoiceID,
            "com.apple.voice.compact.en-US.Samantha"
        )
        XCTAssertEqual(viewModel.settings.ttsVoiceID, "af_heart")
        let loaded = try UserDefaultsAppSettingsStore(defaults: defaults).load()
        XCTAssertEqual(loaded.systemSpeechVoiceID, "com.apple.voice.compact.en-US.Samantha")
        XCTAssertEqual(loaded.ttsVoiceID, "af_heart")
    }

    @MainActor
    func testChangingTTSLanguageClearsStaleSystemSpeechVoice() throws {
        let suiteName = "Suisui.AppSettingsViewModelSystemVoiceLanguage.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: InMemorySecretStore()
        )
        viewModel.setTTSProvider(.systemSpeech)
        viewModel.setTTSVoiceID("com.apple.voice.compact.en-US.Samantha")

        viewModel.setTTSLanguageCode("ja")

        XCTAssertEqual(viewModel.settings.ttsLanguageCode, "ja")
        XCTAssertEqual(viewModel.settings.selectedTTSVoiceID, "")
    }

    @MainActor
    func testAppSettingsViewModelReportsKokoroTTSReadinessWithoutRequiringModelToSaveSettings() throws {
        let suiteName = "Suisui.AppSettingsViewModelTTSReadiness.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        let executableURL = try writeExecutable(named: "kokoro-tts")
        let viewModel = AppSettingsViewModel(
            settingsStore: store,
            secretStore: InMemorySecretStore(),
            voiceModelManager: StaticAppSettingsVoiceModelManager(statuses: [
                .kokoro82M: .notInstalled
            ])
        )

        XCTAssertEqual(viewModel.settings.ttsProvider, .localKokoro)
        XCTAssertEqual(viewModel.selectableTTSProviders, [.systemSpeech, .localKokoro])
        XCTAssertEqual(viewModel.ttsProviderReadinessRow.statusLabel, "Model not installed")

        viewModel.setKokoroExecutablePath(executableURL.path)
        viewModel.saveSettings()

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.successMessage, "Settings saved.")
    }

    @MainActor
    func testAppSettingsViewModelPreservesKokoroDownloadFailureForActionableReadiness() throws {
        let suiteName = "Suisui.AppSettingsViewModelTTSFailure.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: InMemorySecretStore(),
            voiceModelManager: StaticAppSettingsVoiceModelManager(statuses: [
                .kokoro82M: .failed("Network request failed.")
            ])
        )

        XCTAssertEqual(viewModel.ttsProviderReadinessRow.statusLabel, "Download failed")
        XCTAssertEqual(viewModel.ttsProviderReadinessRow.nextActionLabel, "Retry Kokoro model")
        XCTAssertFalse(viewModel.ttsProviderReadinessRow.isReady)
    }

    @MainActor
    func testAppSettingsViewModelMarksKokoroTTSReadyWithInstalledModelAndExecutable() throws {
        let suiteName = "Suisui.AppSettingsViewModelTTSReady.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let executableURL = try writeExecutable(named: "kokoro-tts")
        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: InMemorySecretStore(),
            voiceModelManager: StaticAppSettingsVoiceModelManager(statuses: [
                .kokoro82M: .installed
            ])
        )

        XCTAssertEqual(viewModel.ttsProviderReadinessRow.statusLabel, "Runtime pending")

        viewModel.setKokoroExecutablePath(executableURL.path)
        viewModel.setTTSLanguageCode("ja")
        viewModel.setTTSVoiceID("jf_alpha")

        XCTAssertEqual(viewModel.ttsProviderReadinessRow.statusLabel, "Ready")
        XCTAssertEqual(viewModel.ttsProviderReadinessRow.nextActionLabel, "Test play")
        XCTAssertEqual(viewModel.ttsProviderReadinessRow.detailLabel, "JA / jf_alpha short prompts")
    }

    @MainActor
    func testAppSettingsViewModelRunsReadyKokoroTTSPreview() async throws {
        let suiteName = "Suisui.AppSettingsViewModelTTSPreview.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let executableURL = try writeExecutable(named: "kokoro-tts")
        let previewer = RecordingTTSPreviewClient()
        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: InMemorySecretStore(),
            voiceModelManager: StaticAppSettingsVoiceModelManager(statuses: [
                .kokoro82M: .installed
            ])
        )
        viewModel.setKokoroExecutablePath(executableURL.path)
        viewModel.setTTSLanguageCode("ja")
        viewModel.setTTSVoiceID("jf_alpha")

        await viewModel.testTTSPlayback(using: previewer)

        XCTAssertEqual(
            previewer.requests,
            [
                TextToSpeechRequest(
                    text: "Suisuiのローカル音声テストです。",
                    languageCode: "ja",
                    voiceID: "jf_alpha"
                )
            ]
        )
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.successMessage, "TTS test play completed.")
    }

    @MainActor
    func testAppSettingsViewModelBlocksTTSPreviewUntilReady() async throws {
        let suiteName = "Suisui.AppSettingsViewModelTTSPreviewBlocked.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let previewer = RecordingTTSPreviewClient()
        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: InMemorySecretStore(),
            voiceModelManager: StaticAppSettingsVoiceModelManager(statuses: [
                .kokoro82M: .notInstalled
            ])
        )

        await viewModel.testTTSPlayback(using: previewer)

        XCTAssertTrue(previewer.requests.isEmpty)
        XCTAssertEqual(viewModel.errorMessage, "Download Kokoro model before test play.")
        XCTAssertNil(viewModel.successMessage)
    }

    @MainActor
    func testAppSettingsViewModelRedactsTTSPreviewFailureDetails() async throws {
        let suiteName = "Suisui.AppSettingsViewModelTTSPreviewFailure.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let executableURL = try writeExecutable(named: "kokoro-tts")
        let secret = "sk-localPreviewSecret123"
        let localPath = "/Users/example/Library/Application Support/Suisui/Voice/speech.wav"
        let previewer = RecordingTTSPreviewClient(
            error: SpeechAudioPlaybackError.playbackFailed("Playback failed at \(localPath) token=\(secret)")
        )
        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: InMemorySecretStore(),
            voiceModelManager: StaticAppSettingsVoiceModelManager(statuses: [
                .kokoro82M: .installed
            ])
        )
        viewModel.setKokoroExecutablePath(executableURL.path)

        await viewModel.testTTSPlayback(using: previewer)

        XCTAssertEqual(previewer.requests.count, 1)
        let message = try XCTUnwrap(viewModel.errorMessage)
        XCTAssertTrue(message.contains("TTS test play failed."))
        XCTAssertTrue(message.contains("[REDACTED_PATH]"))
        XCTAssertTrue(message.contains("[REDACTED_SECRET]"))
        XCTAssertFalse(message.contains(localPath))
        XCTAssertFalse(message.contains("Application Support"))
        XCTAssertFalse(message.contains("speech.wav"))
        XCTAssertFalse(message.contains(secret))
        XCTAssertNil(viewModel.successMessage)
    }

    @MainActor
    func testAppSettingsViewModelNormalizesUnsupportedSTTProvider() throws {
        let suiteName = "Suisui.AppSettingsViewModelUnsupportedSTT.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        try store.save(AppSettings(sttProvider: .localWhisperKit))

        let viewModel = AppSettingsViewModel(settingsStore: store, secretStore: InMemorySecretStore())

        XCTAssertEqual(viewModel.settings.sttProvider, .openAITranscribe)

        viewModel.setSTTProvider(.localWhisperCpp)

        XCTAssertEqual(viewModel.settings.sttProvider, .openAITranscribe)
    }

    private func makeUserDefaults(_ label: String) throws -> UserDefaults {
        let suiteName = "Suisui.AppSettingsTests.\(label).\(UUID().uuidString)"
        return try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    private func writeExecutable(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-settings-executable-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data("#!/bin/sh\n".utf8).write(to: url)
        chmod(url.path, 0o755)
        return url
    }
}

private final class LockedAppleSpeechReadinessProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: AppleSpeechReadinessSnapshot

    init(snapshot: AppleSpeechReadinessSnapshot) {
        self.snapshot = snapshot
    }

    func read() -> AppleSpeechReadinessSnapshot {
        lock.withLock { snapshot }
    }

    func write(_ snapshot: AppleSpeechReadinessSnapshot) {
        lock.withLock {
            self.snapshot = snapshot
        }
    }
}

private final class CountingAppleSpeechReadinessProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var readCount: Int {
        lock.withLock { count }
    }

    func read() -> AppleSpeechReadinessSnapshot {
        lock.withLock {
            count += 1
        }
        return .permissionNotDetermined
    }
}

private final class CountingSystemSpeechReadinessProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var readCount: Int {
        lock.withLock { count }
    }

    func read() -> SystemSpeechReadinessSnapshot {
        lock.withLock {
            count += 1
        }
        return .assumedAvailable
    }
}

private struct StaticAppSettingsVoiceModelManager: VoiceModelManaging {
    var statuses: [VoiceModelID: VoiceModelInstallStatus]

    func status(for model: VoiceModelDescriptor) -> VoiceModelInstallStatus {
        statuses[model.id] ?? .notInstalled
    }

    func install(_ model: VoiceModelDescriptor) async throws -> VoiceModelInstall {
        VoiceModelInstall(
            modelID: model.id,
            status: status(for: model),
            localURL: URL(filePath: "/tmp/\(model.cacheFileName)")
        )
    }

    func removeFromCache(_ model: VoiceModelDescriptor) throws {}
}

private final class RecordingTTSPreviewClient: TextToSpeechPreviewing, @unchecked Sendable {
    private let error: Error?
    private(set) var requests: [TextToSpeechRequest] = []

    init(error: Error? = nil) {
        self.error = error
    }

    func playPreview(_ request: TextToSpeechRequest) async throws {
        requests.append(request)
        if let error {
            throw error
        }
    }
}

private struct FailingSaveAppSettingsStore: AppSettingsStore {
    let initial: AppSettings

    init(initial: AppSettings = .default) {
        self.initial = initial
    }

    func load() throws -> AppSettings {
        initial
    }

    func save(_ settings: AppSettings) throws {
        throw SecretStoreError.unexpectedStatus(-34018)
    }
}

private final class FailingWriteSecretStore: SecretStore, @unchecked Sendable {
    private var values: [SecretKey: String]
    private let saveError: Error?
    private let deleteError: Error?
    private let lock = NSLock()

    init(
        values: [SecretKey: String] = [:],
        saveError: Error? = nil,
        deleteError: Error? = nil
    ) {
        self.values = values
        self.saveError = saveError
        self.deleteError = deleteError
    }

    func save(_ value: String, for key: SecretKey) throws {
        if let saveError {
            throw saveError
        }
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
    }

    func read(_ key: SecretKey) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func delete(_ key: SecretKey) throws {
        if let deleteError {
            throw deleteError
        }
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: key)
    }
}

private final class CountingSecretStore: SecretStore, @unchecked Sendable {
    private var values: [SecretKey: String]
    private let lock = NSLock()
    private var readCountStorage = 0

    init(values: [SecretKey: String] = [:]) {
        self.values = values
    }

    var readCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return readCountStorage
    }

    func save(_ value: String, for key: SecretKey) throws {
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
    }

    func read(_ key: SecretKey) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        readCountStorage += 1
        return values[key]
    }

    func delete(_ key: SecretKey) throws {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: key)
    }
}

private struct ThrowingReadSecretStore: SecretStore {
    func save(_ value: String, for key: SecretKey) throws {}

    func read(_ key: SecretKey) throws -> String? {
        throw SecretStoreError.unexpectedStatus(-1)
    }

    func delete(_ key: SecretKey) throws {}
}
