import Foundation
import XCTest
@testable import SuisuiCore

final class LocalLicenseTests: XCTestCase {
    func testMissingLicenseReturnsMissingDisplayState() {
        let validator = LocalLicenseValidator()
        let result = validator.validate(data: nil, now: referenceDate)

        XCTAssertEqual(result.status, .missing)
        XCTAssertEqual(result.displayState, .missing)
    }

    func testFounderLicenseIsValidWithoutPersonalInformation() throws {
        let license = """
        {
          "id": "founder-local-001",
          "plan": "founder",
          "issuedAt": "2026-06-01T00:00:00Z",
          "expiresAt": null,
          "features": ["unlimitedProjects", "sparkleUpdates"],
          "signature": "local-alpha-placeholder"
        }
        """.data(using: .utf8)!

        let validator = LocalLicenseValidator()
        let result = validator.validate(data: license, now: referenceDate)

        XCTAssertEqual(result.status, .valid(plan: .founder))
        XCTAssertEqual(result.displayState, .active(planName: "Founder"))
    }

    func testExpiredLicenseReturnsExpiredDisplayState() throws {
        let license = """
        {
          "id": "personal-plus-001",
          "plan": "personalPlus",
          "issuedAt": "2026-01-01T00:00:00Z",
          "expiresAt": "2026-02-01T00:00:00Z",
          "features": ["unlimitedProjects"],
          "signature": "local-alpha-placeholder"
        }
        """.data(using: .utf8)!

        let validator = LocalLicenseValidator()
        let result = validator.validate(data: license, now: referenceDate)

        XCTAssertEqual(result.status, .expired(plan: .personalPlus))
        XCTAssertEqual(result.displayState, .expired(planName: "Personal Plus"))
    }

    func testLicenseRejectsPersonalInformationFields() throws {
        let license = """
        {
          "id": "founder-local-001",
          "plan": "founder",
          "issuedAt": "2026-06-01T00:00:00Z",
          "email": "user@example.com",
          "features": [],
          "signature": "local-alpha-placeholder"
        }
        """.data(using: .utf8)!

        let validator = LocalLicenseValidator()
        let result = validator.validate(data: license, now: referenceDate)

        XCTAssertEqual(result.status, .invalid(reason: "License file must not contain personal information fields."))
        XCTAssertEqual(result.displayState, .invalid(message: "License file must not contain personal information fields."))
    }

    func testLicenseRejectsNestedPersonalInformationFieldsCaseInsensitively() throws {
        let license = """
        {
          "id": "founder-local-001",
          "plan": "founder",
          "issuedAt": "2026-06-01T00:00:00Z",
          "metadata": {
            "FullName": "Example User"
          },
          "features": [],
          "signature": "local-alpha-placeholder"
        }
        """.data(using: .utf8)!

        let validator = LocalLicenseValidator()
        let result = validator.validate(data: license, now: referenceDate)

        XCTAssertEqual(result.status, .invalid(reason: "License file must not contain personal information fields."))
        XCTAssertEqual(result.displayState, .invalid(message: "License file must not contain personal information fields."))
    }

    private var referenceDate: Date {
        ISO8601DateFormatter().date(from: "2026-06-17T00:00:00Z")!
    }
}
