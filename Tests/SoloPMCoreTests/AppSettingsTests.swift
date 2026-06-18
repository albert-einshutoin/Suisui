import XCTest
@testable import SoloPMCore

final class AppSettingsTests: XCTestCase {
    func testDefaultSettingsAreValid() {
        XCTAssertTrue(AppSettings.default.validate().isEmpty)
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

    func testReleaseReadySTTProvidersOnlyExposeImplementedRuntimeProvider() {
        XCTAssertEqual(STTProvider.releaseReadyCases, [.openAITranscribe])
        XCTAssertTrue(STTProvider.openAITranscribe.isReleaseReady)
        XCTAssertFalse(STTProvider.localWhisperKit.isReleaseReady)
    }

    func testUserDefaultsAppSettingsStorePersistsSettings() throws {
        let suiteName = "SoloPM.AppSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        let settings = AppSettings(
            aiProvider: .openAIResponses,
            sttProvider: .openAITranscribe,
            notificationsEnabled: true,
            defaultWorkspacePath: "/tmp/SoloPM",
            timeZoneIdentifier: "Asia/Tokyo"
        )

        try store.save(settings)

        XCTAssertEqual(try store.load(), settings)
    }

    @MainActor
    func testAppSettingsViewModelReportsCorruptedStoredSettingsInsteadOfSilentDefault() throws {
        let suiteName = "SoloPM.AppSettingsCorrupted.\(UUID().uuidString)"
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
        let suiteName = "SoloPM.AppSettingsKeychainReadFailure.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: ThrowingReadSecretStore()
        )

        XCTAssertEqual(viewModel.openAIAPIKeyStatusLabel, "Unavailable")
        XCTAssertEqual(viewModel.openRouterAPIKeyStatusLabel, "Unavailable")
        XCTAssertEqual(viewModel.errorMessage, "API key status could not be read from Keychain.")
    }

    @MainActor
    func testAppSettingsViewModelReportsInvalidStoredOpenAIKeyInsteadOfConfigured() throws {
        let suiteName = "SoloPM.AppSettingsInvalidStoredOpenAIKey.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: InMemorySecretStore(values: [.openAIAPIKey: "sk-live invalid"])
        )

        XCTAssertEqual(viewModel.openAIAPIKeyStatusLabel, "Invalid")
        XCTAssertEqual(viewModel.openRouterAPIKeyStatusLabel, "Not configured")
        XCTAssertEqual(viewModel.errorMessage, "Stored API key is invalid. Re-enter it in Settings.")
        XCTAssertFalse(viewModel.errorMessage?.contains("sk-live") ?? true)
    }

    @MainActor
    func testAppSettingsViewModelReportsInvalidStoredOpenRouterKeyInsteadOfConfigured() throws {
        let suiteName = "SoloPM.AppSettingsInvalidStoredOpenRouterKey.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: InMemorySecretStore(values: [.openRouterAPIKey: "sk-or-live\ninvalid"])
        )

        XCTAssertEqual(viewModel.openAIAPIKeyStatusLabel, "Not configured")
        XCTAssertEqual(viewModel.openRouterAPIKeyStatusLabel, "Invalid")
        XCTAssertEqual(viewModel.errorMessage, "Stored API key is invalid. Re-enter it in Settings.")
        XCTAssertFalse(viewModel.errorMessage?.contains("sk-or-live") ?? true)
    }

    @MainActor
    func testAppSettingsViewModelDoesNotReportOpenAIKeySaveSuccessWhenStatusRefreshFails() throws {
        let suiteName = "SoloPM.AppSettingsOpenAISaveRefreshFailure.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: ThrowingReadSecretStore()
        )

        viewModel.updateOpenAIAPIKeyInput("sk-test")
        viewModel.saveOpenAIAPIKey()

        XCTAssertEqual(viewModel.openAIAPIKeyStatusLabel, "Unavailable")
        XCTAssertEqual(viewModel.errorMessage, "API key status could not be read from Keychain.")
        XCTAssertNil(viewModel.successMessage)
    }

    @MainActor
    func testAppSettingsViewModelDoesNotReportOpenRouterKeySaveSuccessWhenStatusRefreshFails() throws {
        let suiteName = "SoloPM.AppSettingsOpenRouterSaveRefreshFailure.\(UUID().uuidString)"
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
    func testAppSettingsViewModelSavesAndDeletesOpenAIKeyInSecretStoreOnly() throws {
        let suiteName = "SoloPM.AppSettingsViewModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settingsStore = UserDefaultsAppSettingsStore(defaults: defaults)
        let secretStore = InMemorySecretStore()
        let viewModel = AppSettingsViewModel(settingsStore: settingsStore, secretStore: secretStore)

        viewModel.updateOpenAIAPIKeyInput(" sk-test-secret ")
        viewModel.saveOpenAIAPIKey()

        XCTAssertEqual(try secretStore.read(.openAIAPIKey), "sk-test-secret")
        XCTAssertEqual(viewModel.openAIAPIKeyStatusLabel, "Configured")
        XCTAssertNil(defaults.data(forKey: "app.settings"))

        viewModel.deleteOpenAIAPIKey()

        XCTAssertNil(try secretStore.read(.openAIAPIKey))
        XCTAssertEqual(viewModel.openAIAPIKeyStatusLabel, "Not configured")
    }

    @MainActor
    func testAppSettingsViewModelRejectsOpenAIKeyWithInternalWhitespace() throws {
        let suiteName = "SoloPM.AppSettingsViewModelInvalidOpenAIKey.\(UUID().uuidString)"
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
        XCTAssertEqual(viewModel.errorMessage, "API key cannot contain whitespace.")
        XCTAssertFalse(viewModel.errorMessage?.contains(keyPrefix) ?? true)
    }

    @MainActor
    func testAppSettingsViewModelSavesAndDeletesOpenRouterKeyInSecretStoreOnly() throws {
        let suiteName = "SoloPM.AppSettingsViewModelOpenRouterTests.\(UUID().uuidString)"
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
    func testAppSettingsViewModelSavesAndDeletesCustomKeychainSecretForMCPReferences() throws {
        let suiteName = "SoloPM.AppSettingsViewModelCustomSecretTests.\(UUID().uuidString)"
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
        let suiteName = "SoloPM.AppSettingsViewModelInvalidCustomSecret.\(UUID().uuidString)"
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
        let suiteName = "SoloPM.AppSettingsViewModelCustomSecretStatus.\(UUID().uuidString)"
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
        let suiteName = "SoloPM.AppSettingsViewModelInvalidOpenRouterKey.\(UUID().uuidString)"
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
    func testAppSettingsViewModelPersistsNonSecretSettings() throws {
        let suiteName = "SoloPM.AppSettingsViewModelSettings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        let viewModel = AppSettingsViewModel(settingsStore: store, secretStore: InMemorySecretStore())

        viewModel.setNotificationsEnabled(true)
        viewModel.setDefaultWorkspacePath("/tmp/SoloPM")
        viewModel.saveSettings()

        let loaded = try store.load()

        XCTAssertTrue(loaded.notificationsEnabled)
        XCTAssertEqual(loaded.defaultWorkspacePath, "/tmp/SoloPM")
    }

    @MainActor
    func testAppSettingsViewModelPersistsProviderSelection() throws {
        let suiteName = "SoloPM.AppSettingsViewModelProviders.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        let viewModel = AppSettingsViewModel(settingsStore: store, secretStore: InMemorySecretStore())

        viewModel.setAIProvider(.openRouter)
        viewModel.setSTTProvider(.openAITranscribe)
        viewModel.saveSettings()

        let loaded = try store.load()

        XCTAssertEqual(loaded.aiProvider, .openRouter)
        XCTAssertEqual(loaded.sttProvider, .openAITranscribe)
    }

    @MainActor
    func testAppSettingsViewModelNormalizesUnsupportedSTTProvider() throws {
        let suiteName = "SoloPM.AppSettingsViewModelUnsupportedSTT.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        try store.save(AppSettings(sttProvider: .localWhisperKit))

        let viewModel = AppSettingsViewModel(settingsStore: store, secretStore: InMemorySecretStore())

        XCTAssertEqual(viewModel.settings.sttProvider, .openAITranscribe)

        viewModel.setSTTProvider(.localWhisperCpp)

        XCTAssertEqual(viewModel.settings.sttProvider, .openAITranscribe)
    }
}

private struct ThrowingReadSecretStore: SecretStore {
    func save(_ value: String, for key: SecretKey) throws {}

    func read(_ key: SecretKey) throws -> String? {
        throw SecretStoreError.unexpectedStatus(-1)
    }

    func delete(_ key: SecretKey) throws {}
}
