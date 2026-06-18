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
            aiProvider: .openaiResponses,
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
        let suiteName = "SoloPM.AppSettingsInvalidStoredOpenAIKey.\(UUID().uuidString)"
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
        let suiteName = "SoloPM.AppSettingsInvalidStoredOpenRouterKey.\(UUID().uuidString)"
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
        XCTAssertEqual(viewModel.openAIProviderSmokeStatusLabel, "unavailable")
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
    func testAppSettingsViewModelDoesNotReportAnthropicKeySaveSuccessWhenStatusRefreshFails() throws {
        let suiteName = "SoloPM.AppSettingsAnthropicSaveRefreshFailure.\(UUID().uuidString)"
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
        let suiteName = "SoloPM.AppSettingsGeminiSaveRefreshFailure.\(UUID().uuidString)"
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
        let suiteName = "SoloPM.AppSettingsGroqSaveRefreshFailure.\(UUID().uuidString)"
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
        XCTAssertEqual(viewModel.openAIProviderSmokeStatusLabel, "readyForManualSmoke")
        XCTAssertNil(defaults.data(forKey: "app.settings"))

        viewModel.deleteOpenAIAPIKey()

        XCTAssertNil(try secretStore.read(.openAIAPIKey))
        XCTAssertEqual(viewModel.openAIAPIKeyStatusLabel, "Not configured")
        XCTAssertEqual(viewModel.openAIProviderSmokeStatusLabel, "notConfigured")
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
        XCTAssertEqual(viewModel.openAIProviderSmokeStatusLabel, "notConfigured")
        XCTAssertEqual(viewModel.errorMessage, "API key cannot contain whitespace.")
        XCTAssertFalse(viewModel.errorMessage?.contains(keyPrefix) ?? true)
    }

    @MainActor
    func testAppSettingsViewModelShowsOpenAIProviderSmokeNotConfiguredWithoutAPIKey() throws {
        let suiteName = "SoloPM.AppSettingsOpenAISmokeNotConfigured.\(UUID().uuidString)"
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
    func testAppSettingsViewModelSavesAndDeletesAnthropicKeyInSecretStoreOnly() throws {
        let suiteName = "SoloPM.AppSettingsViewModelAnthropicTests.\(UUID().uuidString)"
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
        let suiteName = "SoloPM.AppSettingsViewModelGeminiTests.\(UUID().uuidString)"
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
        let suiteName = "SoloPM.AppSettingsViewModelGroqTests.\(UUID().uuidString)"
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
    func testAppSettingsViewModelRejectsAnthropicKeyWithInternalWhitespace() throws {
        let suiteName = "SoloPM.AppSettingsViewModelInvalidAnthropicKey.\(UUID().uuidString)"
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
        let suiteName = "SoloPM.AppSettingsViewModelInvalidGeminiKey.\(UUID().uuidString)"
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
        let suiteName = "SoloPM.AppSettingsViewModelInvalidGroqKey.\(UUID().uuidString)"
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
        let suiteName = "SoloPM.AppSettingsViewModelSettings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        let viewModel = AppSettingsViewModel(settingsStore: store, secretStore: InMemorySecretStore())

        viewModel.setNotificationsEnabled(true)
        viewModel.setDefaultWorkspacePath("/tmp/SoloPM")
        viewModel.setGeminiModelID(" gemini-3.5-flash ")
        viewModel.setGroqBaseURLString(" https://api.groq.com/openai/v1 ")
        viewModel.saveSettings()

        let loaded = try store.load()

        XCTAssertTrue(loaded.notificationsEnabled)
        XCTAssertEqual(loaded.defaultWorkspacePath, "/tmp/SoloPM")
        XCTAssertEqual(loaded.geminiModelID, "gemini-3.5-flash")
        XCTAssertEqual(loaded.groqBaseURLString, "https://api.groq.com/openai/v1")
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

    @MainActor
    func testAppSettingsViewModelPersistsProviderSelection() throws {
        let suiteName = "SoloPM.AppSettingsViewModelProviders.\(UUID().uuidString)"
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
    func testAppSettingsViewModelRejectsUnavailableAIProviderSelection() throws {
        let suiteName = "SoloPM.AppSettingsUnavailableAIProvider.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        let viewModel = AppSettingsViewModel(settingsStore: store, secretStore: InMemorySecretStore())

        XCTAssertEqual(
            viewModel.selectableAIProviders,
            [.openaiResponses, .claudeMessages, .geminiDirect, .groqOpenAICompatible, .openRouterCompatible, .ollamaCompatible]
        )

        viewModel.setAIProvider(.geminiOpenAICompatible)
        viewModel.saveSettings()

        XCTAssertEqual(viewModel.settings.aiProvider, .openaiResponses)
        XCTAssertEqual(viewModel.errorMessage, "Gemini OpenAI-compatible is not available in this build.")
        XCTAssertNil(defaults.data(forKey: "app.settings"))
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

        XCTAssertEqual(try decoder.decode(AppSettings.self, from: openRouterData).aiProvider, .openRouterCompatible)
        XCTAssertEqual(try decoder.decode(AppSettings.self, from: ollamaData).aiProvider, .ollamaCompatible)
        XCTAssertEqual(try decoder.decode(AppSettings.self, from: openAICompatibleData).aiProvider, .openaiResponses)
        XCTAssertEqual(try decoder.decode(AppSettings.self, from: openAIResponsesData).aiProvider, .openaiResponses)
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
