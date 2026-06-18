import XCTest
@testable import SoloPMCore

final class LLMProviderCatalogTests: XCTestCase {
    func testCatalogDefinesEntryForEveryProviderID() {
        let ids = LLMProviderCatalog.allEntries.map(\.id)

        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertEqual(Set(ids), Set(LLMProviderID.allCases))

        for id in LLMProviderID.allCases {
            XCTAssertEqual(LLMProviderCatalog.entry(for: id).id, id)
        }
    }

    func testCatalogDefinesContractForEachTargetProvider() {
        let entries = LLMProviderCatalog.allEntries

        XCTAssertEqual(
            entries.map(\.id),
            [
                .openaiResponses,
                .claudeMessages,
                .geminiDirect,
                .geminiOpenAICompatible,
                .groqOpenAICompatible,
                .opencodeLocal,
                .openRouterCompatible,
                .ollamaCompatible
            ]
        )

        let openAI = LLMProviderCatalog.entry(for: .openaiResponses)
        XCTAssertEqual(openAI.apiKeySecretKey, .openAIAPIKey)
        XCTAssertEqual(openAI.baseURL?.absoluteString, "https://api.openai.com/v1")
        XCTAssertEqual(openAI.defaultModelID, "gpt-5.2")
        XCTAssertEqual(openAI.requestFamily, .openAIResponses)
        XCTAssertTrue(openAI.supportsStructuredOutput)

        let geminiDirect = LLMProviderCatalog.entry(for: .geminiDirect)
        let geminiCompatible = LLMProviderCatalog.entry(for: .geminiOpenAICompatible)
        XCTAssertEqual(geminiDirect.apiKeySecretKey, .geminiAPIKey)
        XCTAssertEqual(geminiCompatible.apiKeySecretKey, .geminiAPIKey)
        XCTAssertEqual(geminiDirect.defaultModelID, "gemini-3.5-flash")
        XCTAssertTrue(geminiDirect.isAvailableInCurrentBuild)
        XCTAssertFalse(geminiCompatible.isAvailableInCurrentBuild)
        XCTAssertEqual(geminiDirect.requestFamily, .geminiGenerateContent)
        XCTAssertEqual(geminiCompatible.requestFamily, .openAIChatCompletions)
        XCTAssertNotEqual(geminiDirect.baseURL, geminiCompatible.baseURL)

        let groq = LLMProviderCatalog.entry(for: .groqOpenAICompatible)
        XCTAssertEqual(groq.apiKeySecretKey, .groqAPIKey)
        XCTAssertEqual(groq.baseURL?.absoluteString, "https://api.groq.com/openai/v1")
        XCTAssertEqual(groq.defaultModelID, "llama-3.3-70b-versatile")
        XCTAssertTrue(groq.isAvailableInCurrentBuild)
        XCTAssertEqual(groq.requestFamily, .openAIChatCompletions)

        let claude = LLMProviderCatalog.entry(for: .claudeMessages)
        XCTAssertEqual(claude.apiKeySecretKey, .anthropicAPIKey)
        XCTAssertEqual(claude.baseURL?.absoluteString, "https://api.anthropic.com/v1")
        XCTAssertEqual(claude.defaultModelID, "claude-opus-4-6")
        XCTAssertEqual(claude.requestFamily, .anthropicMessages)

        let openCode = LLMProviderCatalog.entry(for: .opencodeLocal)
        XCTAssertNil(openCode.apiKeySecretKey)
        XCTAssertNil(openCode.baseURL)
        XCTAssertTrue(openCode.isAvailableInCurrentBuild)
        XCTAssertEqual(openCode.requestFamily, .opencodeLocalCLI)
    }

    func testSettingsSelectableProvidersOnlyIncludeImplementedRuntimeAdapters() {
        XCTAssertEqual(
            LLMProviderCatalog.settingsSelectableIDs,
            [
                .openaiResponses,
                .claudeMessages,
                .geminiDirect,
                .groqOpenAICompatible,
                .opencodeLocal,
                .openRouterCompatible,
                .ollamaCompatible
            ]
        )

        for entry in LLMProviderCatalog.allEntries where !entry.isAvailableInCurrentBuild {
            XCTAssertEqual(entry.unavailableReason, "Not available in this build")
            XCTAssertFalse(LLMProviderCatalog.settingsSelectableIDs.contains(entry.id))
        }
    }

    func testProviderSecretsAreSeparatedByProvider() {
        XCTAssertEqual(LLMProviderCatalog.entry(for: .openaiResponses).apiKeySecretKey, .openAIAPIKey)
        XCTAssertEqual(LLMProviderCatalog.entry(for: .openRouterCompatible).apiKeySecretKey, .openRouterAPIKey)
        XCTAssertEqual(LLMProviderCatalog.entry(for: .claudeMessages).apiKeySecretKey, .anthropicAPIKey)
        XCTAssertEqual(LLMProviderCatalog.entry(for: .geminiDirect).apiKeySecretKey, .geminiAPIKey)
        XCTAssertEqual(LLMProviderCatalog.entry(for: .geminiOpenAICompatible).apiKeySecretKey, .geminiAPIKey)
        XCTAssertEqual(LLMProviderCatalog.entry(for: .groqOpenAICompatible).apiKeySecretKey, .groqAPIKey)
        XCTAssertNil(LLMProviderCatalog.entry(for: .opencodeLocal).apiKeySecretKey)
        XCTAssertNil(LLMProviderCatalog.entry(for: .ollamaCompatible).apiKeySecretKey)
    }
}
