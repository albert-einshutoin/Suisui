import XCTest
@testable import SuisuiCore

final class VisualEvidenceRuntimeContextTests: XCTestCase {
    func testJapaneseVisualManifestUsesJaContextAndSeparateRoots() throws {
        let manifest = try visualManifest(named: "visual-baseline-manifest-ja.json")
        let context = try XCTUnwrap(manifest["baselineContext"] as? [String: Any])
        let screens = try XCTUnwrap(manifest["screens"] as? [[String: Any]])
        let projectBoard = try XCTUnwrap(screens.first { $0["id"] as? String == "project-board" })
        let requiredVisibleTextLines = try XCTUnwrap(projectBoard["requiredVisibleTextLines"] as? [String])

        XCTAssertEqual(context["locale"] as? String, "ja-JP")
        XCTAssertEqual(manifest["artifactRoot"] as? String, "docs/release/evidence/ui-screenshots-ja")
        XCTAssertEqual(manifest["baselineRoot"] as? String, "docs/quality/visual-baselines-ja")
        XCTAssertEqual(requiredVisibleTextLines, [
            "project board to task card to",
            "進行中 高",
            "7月10日"
        ])
        XCTAssertFalse(requiredVisibleTextLines.contains("In Progress High"))
        XCTAssertFalse(requiredVisibleTextLines.contains("Jul 10"))
    }

    func testApprovalFlowScreensExistInBothLocaleManifests() throws {
        let expectedApprovalScreens: [String: (target: String, themes: Set<String>)] = [
            "assistant-queue-waiting-review": ("assistant-queue-row-visual-waiting", ["light", "dark"]),
            "assistant-queue-approved": ("assistant-queue-row-visual-approved", ["light", "dark"]),
            "assistant-queue-failed": ("assistant-queue-row-visual-failed", ["light", "dark"])
        ]
        let requiredWorkflowScreens: Set<String> = [
            "inbox",
            "inbox-voice",
            "projects-overview"
        ]

        for manifestName in [
            "visual-baseline-manifest.json",
            "visual-baseline-manifest-ja.json"
        ] {
            let manifest = try visualManifest(named: manifestName)
            let screens = try XCTUnwrap(manifest["screens"] as? [[String: Any]])
            let screensByID = Dictionary(
                uniqueKeysWithValues: try screens.map {
                    (try XCTUnwrap($0["id"] as? String), $0)
                }
            )

            XCTAssertTrue(
                requiredWorkflowScreens.isSubset(of: Set(screensByID.keys)),
                "\(manifestName) must keep the complete workflow contract"
            )
            for (screenID, expected) in expectedApprovalScreens {
                let screen = try XCTUnwrap(screensByID[screenID], "\(manifestName) missing \(screenID)")
                XCTAssertEqual(screen["axTargetIdentifier"] as? String, expected.target)
                XCTAssertEqual(Set(try XCTUnwrap(screen["themes"] as? [String])), expected.themes)
                XCTAssertEqual(
                    Set(try XCTUnwrap((screen["artifacts"] as? [String: String])?.keys)),
                    expected.themes
                )
            }
            let artifactCount = try screens.reduce(into: 0) { count, screen in
                count += try XCTUnwrap(screen["artifacts"] as? [String: String]).count
            }
            XCTAssertEqual(artifactCount, 39, "\(manifestName) must describe all 39 locale-specific captures")
        }
    }

    func testCompleteCaptureContextPinsReferenceInstantLocaleAndTimeZone() throws {
        let context = try XCTUnwrap(VisualEvidenceRuntimeContext(environment: [
            VisualEvidenceRuntimeContext.referenceInstantEnvironmentKey: "2026-07-10T12:00:00Z",
            VisualEvidenceRuntimeContext.timeZoneEnvironmentKey: "UTC",
            VisualEvidenceRuntimeContext.localeEnvironmentKey: "en-US"
        ]))

        XCTAssertEqual(ISO8601DateFormatter().string(from: context.referenceInstant), "2026-07-10T12:00:00Z")
        XCTAssertEqual(context.timeZoneIdentifier, "UTC")
        XCTAssertEqual(context.localeIdentifier, "en-US")
        XCTAssertEqual(context.calendar.timeZone.identifier, "GMT")
        XCTAssertEqual(context.calendar.locale?.identifier, "en-US")
    }

    func testPartialOrInvalidCaptureContextFallsBackToSystemClockAndCalendar() {
        let systemNow = Date(timeIntervalSince1970: 123)
        var systemCalendar = Calendar(identifier: .iso8601)
        systemCalendar.timeZone = TimeZone(secondsFromGMT: 3_600)!
        let partialEnvironment = [
            VisualEvidenceRuntimeContext.referenceInstantEnvironmentKey: "2026-07-10T12:00:00Z"
        ]

        XCTAssertNil(VisualEvidenceRuntimeContext(environment: partialEnvironment))
        XCTAssertEqual(
            VisualEvidenceRuntimeContext.referenceDate(
                environment: partialEnvironment,
                systemNow: { systemNow }
            ),
            systemNow
        )
        XCTAssertEqual(
            VisualEvidenceRuntimeContext.runtimeCalendar(
                environment: partialEnvironment,
                systemCalendar: { systemCalendar }
            ).timeZone,
            systemCalendar.timeZone
        )
    }

    private func visualManifest(named fileName: String) throws -> [String: Any] {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(
            contentsOf: packageRoot.appendingPathComponent("docs/quality/\(fileName)")
        )
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
