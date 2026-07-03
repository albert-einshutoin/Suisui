import XCTest
@testable import SoloPMCore

final class ActionPlanSchemaTests: XCTestCase {
    func testSchemaResourceLoadsAsJSONObject() throws {
        let data = try ActionPlanSchema.loadData()
        let object = try schemaObject()

        XCTAssertFalse(data.isEmpty)
        XCTAssertEqual(object["$id"] as? String, "https://solopm.dev/schemas/action-plan.schema.json")
        XCTAssertEqual(object["title"] as? String, "SoloPM ActionPlan")
    }

    func testSchemaUsesStrictRootAndActionObjects() throws {
        let object = try schemaObject()
        let definitions = try XCTUnwrap(object["$defs"] as? [String: Any])
        let action = try XCTUnwrap(definitions["action"] as? [String: Any])
        let required = try XCTUnwrap(object["required"] as? [String])

        XCTAssertEqual(object["additionalProperties"] as? Bool, false)
        XCTAssertEqual(action["additionalProperties"] as? Bool, false)
        XCTAssertTrue(required.contains("id"))
        XCTAssertTrue(required.contains("userInput"))
        XCTAssertTrue(required.contains("summary"))
        XCTAssertTrue(required.contains("actions"))
        XCTAssertTrue(required.contains("riskLevel"))
        XCTAssertTrue(required.contains("requiresApproval"))
    }

    func testSchemaToolEnumMatchesActionToolCases() throws {
        let definitions = try XCTUnwrap(schemaObject()["$defs"] as? [String: Any])
        let tool = try XCTUnwrap(definitions["tool"] as? [String: Any])
        let schemaTools = try XCTUnwrap(tool["enum"] as? [String])

        XCTAssertEqual(Set(schemaTools), Set(ActionTool.allCases.map(\.rawValue)))
    }

    func testSchemaDoesNotExposeFilesystemDeleteTool() throws {
        let definitions = try XCTUnwrap(schemaObject()["$defs"] as? [String: Any])
        let tool = try XCTUnwrap(definitions["tool"] as? [String: Any])
        let schemaTools = try XCTUnwrap(tool["enum"] as? [String])

        XCTAssertTrue(schemaTools.filter { value in
            value.hasPrefix("filesystem.") && value.localizedCaseInsensitiveContains("delete")
        }.isEmpty)
    }

    func testSchemaRiskEnumMatchesRiskLevelCases() throws {
        let definitions = try XCTUnwrap(schemaObject()["$defs"] as? [String: Any])
        let riskLevel = try XCTUnwrap(definitions["riskLevel"] as? [String: Any])
        let schemaRiskLevels = try XCTUnwrap(riskLevel["enum"] as? [String])

        XCTAssertEqual(Set(schemaRiskLevels), Set(RiskLevel.allCases.map(\.rawValue)))
    }

    func testSchemaFallbackOnlyUsesModuleResourceWhenPrimaryResourceIsMissing() throws {
        let fallbackData = try ActionPlanSchema.loadData(
            primary: { throw ActionPlanSchemaError.resourceNotFound },
            module: { Data(#"{"title":"fallback"}"#.utf8) }
        )

        XCTAssertEqual(String(data: fallbackData, encoding: .utf8), #"{"title":"fallback"}"#)
    }

    func testSchemaFallbackDoesNotHidePrimaryBundleReadErrors() throws {
        enum TestReadError: Error, Equatable {
            case denied
        }

        XCTAssertThrowsError(
            try ActionPlanSchema.loadData(
                primary: { throw TestReadError.denied },
                module: { Data(#"{"title":"fallback"}"#.utf8) }
            )
        ) { error in
            XCTAssertEqual(error as? TestReadError, .denied)
        }
    }

    private func schemaObject() throws -> [String: Any] {
        let data = try ActionPlanSchema.loadData()
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
