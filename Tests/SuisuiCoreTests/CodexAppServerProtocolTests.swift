import Foundation
import XCTest
@testable import SuisuiCore

final class CodexAppServerProtocolTests: XCTestCase {
    func testChatGPTAccountFixtureDecodesWithoutCredentials() throws {
        let data = try fixtureData(named: "account-read-chatgpt", extension: "json")
        let response = try JSONDecoder().decode(CodexAccountReadResponse.self, from: data)

        XCTAssertEqual(response.account, .chatGPT(email: "user@example.com", plan: .plus))
        XCTAssertTrue(response.requiresOpenAIAuth)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("accessToken"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("refreshToken"))
    }

    func testOnlyUserOwnedChatGPTLoginKindsCanBeEncoded() throws {
        XCTAssertEqual(Set(CodexLoginKind.allCases), [.chatGPTBrowser, .chatGPTDeviceCode])

        let data = try JSONEncoder().encode(CodexLoginStartParams(type: .chatGPTBrowser))
        XCTAssertEqual(try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String]), ["type": "chatgpt"])
    }

    func testChatGPTLoginStartFixtureDecodesBrowserURL() throws {
        let response = try JSONDecoder().decode(
            CodexLoginStartResponse.self,
            from: fixtureData(named: "login-start-chatgpt", extension: "json")
        )

        XCTAssertEqual(
            response,
            .chatGPTBrowser(
                loginID: "login-example",
                authenticationURL: try XCTUnwrap(URL(string: "https://auth.openai.com/oauth/authorize?client_id=example"))
            )
        )
    }

    func testFuturePlanValueFailsSafeAsUnknown() throws {
        let data = Data(#"{"account":{"type":"chatgpt","email":null,"planType":"future_plan"},"requiresOpenaiAuth":true}"#.utf8)
        let response = try JSONDecoder().decode(CodexAccountReadResponse.self, from: data)

        XCTAssertEqual(response.account, .chatGPT(email: nil, plan: .unknown))
    }

    func testStableMethodNamesMatchAppServerContract() {
        XCTAssertEqual(CodexAppServerMethod.initialize, "initialize")
        XCTAssertEqual(CodexAppServerMethod.accountRead, "account/read")
        XCTAssertEqual(CodexAppServerMethod.accountLoginStart, "account/login/start")
        XCTAssertEqual(CodexAppServerMethod.modelList, "model/list")
        XCTAssertEqual(CodexAppServerMethod.threadStart, "thread/start")
        XCTAssertEqual(CodexAppServerMethod.turnStart, "turn/start")
        XCTAssertEqual(CodexAppServerMethod.turnInterrupt, "turn/interrupt")
    }

    func testApprovalFixtureIsRecognizedAsForbiddenToolRequest() throws {
        let lines = try fixtureLines(named: "turn-approval-request")
        let message = try JSONDecoder().decode(CodexInboundMessage.self, from: XCTUnwrap(lines.first))

        XCTAssertEqual(message.kind, .serverRequest)
        XCTAssertEqual(message.method, CodexAppServerMethod.commandExecutionRequestApproval)
        XCTAssertTrue(message.isForbiddenToolLifecycle)
    }

    func testProtocolFixturesContainNoCredentialFieldsOrSecretPatterns() throws {
        for name in ["account-read-chatgpt.json", "login-start-chatgpt.json", "turn-success.jsonl", "turn-approval-request.jsonl", "usage-limit.jsonl"] {
            let data = try fixtureData(filename: name)
            let text = String(decoding: data, as: UTF8.self)
            XCTAssertFalse(text.contains("accessToken"), name)
            XCTAssertFalse(text.contains("refreshToken"), name)
            XCTAssertFalse(text.contains("sk-"), name)
        }
    }

    private func fixtureLines(named name: String) throws -> [Data] {
        String(decoding: try fixtureData(named: name, extension: "jsonl"), as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map { Data($0.utf8) }
    }

    private func fixtureData(named name: String, extension fileExtension: String) throws -> Data {
        try fixtureData(filename: "\(name).\(fileExtension)")
    }

    private func fixtureData(filename: String) throws -> Data {
        let components = filename.split(separator: ".", maxSplits: 1).map(String.init)
        let name = components[0]
        let fileExtension = components.count == 2 ? components[1] : nil
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: fileExtension, subdirectory: "CodexAppServer/v0.144.1")
                ?? Bundle.module.url(forResource: name, withExtension: fileExtension, subdirectory: "v0.144.1")
                ?? Bundle.module.url(forResource: name, withExtension: fileExtension)
        )
        return try Data(contentsOf: url)
    }
}
