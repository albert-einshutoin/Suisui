import Foundation
import XCTest

final class PublicBrandSurfaceTests: XCTestCase {
    func testLocalizedValuesUseSuisuiWithoutRenamingCompatibilityIdentifiers() throws {
        for locale in ["en", "ja"] {
            let contents = try read("Sources/SoloPMApp/Resources/\(locale).lproj/Localizable.strings")
            let publicValues = contents
                .split(separator: "\n")
                .compactMap { line -> String? in
                    guard let separator = line.range(of: " = ") else { return nil }
                    return String(line[separator.upperBound...])
                }
                .joined(separator: "\n")
                .replacingOccurrences(of: "SOLOPM_GOOGLE_CALENDAR_OAUTH_CLIENT_ID", with: "")
                .replacingOccurrences(of: "SoloPMGoogleCalendarOAuthClientID", with: "")

            XCTAssertFalse(publicValues.contains("SoloPM"), "\(locale) still exposes the legacy brand")
        }
    }

    func testCompanionWebAndCLIExposeSuisuiBrand() throws {
        XCTAssertTrue(try read("Sources/SoloPMWeb/SoloPMWebMVP.swift").contains("<title>Suisui Web</title>"))
        XCTAssertTrue(try read("Sources/SoloPMiOS/SoloPMiOSCompanion.swift").contains("What should Suisui do?"))

        let cli = try read("Sources/SoloPMCLI/SoloPMCLIEntrypoint.swift")
        XCTAssertTrue(cli.contains("Suisui CLI failed unexpectedly"))
        XCTAssertTrue(cli.contains("Suisui local data could not be read"))
    }

    private func read(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
