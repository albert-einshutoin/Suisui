import Foundation
import XCTest

final class AppBundleMetadataTests: XCTestCase {
    func testPackagingMetadataDefinesPublicAlphaIdentity() throws {
        let metadata = try loadMetadata()

        XCTAssertEqual(metadata["APP_NAME"], "Suisui")
        XCTAssertEqual(metadata["SWIFT_PRODUCT_NAME"], "Suisui")
        XCTAssertEqual(metadata["BUNDLE_IDENTIFIER"], "dev.suisui.app")
        XCTAssertEqual(metadata["APP_CATEGORY"], "public.app-category.productivity")
        XCTAssertEqual(metadata["MIN_SYSTEM_VERSION"], "14.0")
        XCTAssertEqual(metadata["SUPPORTED_ARCHITECTURES"], "arm64")
        XCTAssertEqual(metadata["MARKETING_VERSION"], "0.1.0")
        XCTAssertEqual(metadata["CURRENT_PROJECT_VERSION"], "1")
        XCTAssertEqual(metadata["COPYRIGHT"], "Copyright (c) 2026 Suisui contributors.")
        XCTAssertGreaterThan(try XCTUnwrap(Int(metadata["CURRENT_PROJECT_VERSION"] ?? "")), 0)
    }

    func testMarketingVersionUsesSemVerShape() throws {
        let metadata = try loadMetadata()
        let version = try XCTUnwrap(metadata["MARKETING_VERSION"])
        let components = version.split(separator: ".")

        XCTAssertEqual(components.count, 3)
        XCTAssertTrue(components.allSatisfy { Int($0) != nil })
    }

    // Keep the production entitlement surface explicit so future capabilities cannot
    // silently broaden the app sandbox boundary during release packaging.
    func testEntitlementsGrantAudioInputAndWeatherKitOnly() throws {
        let entitlementsURL = packageRoot().appendingPathComponent("packaging/Suisui.entitlements")
        let data = try Data(contentsOf: entitlementsURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        )

        XCTAssertEqual(Set(plist.keys), ["com.apple.security.device.audio-input", "com.apple.developer.weatherkit"])
        XCTAssertEqual(plist["com.apple.security.device.audio-input"] as? Bool, true)
        XCTAssertEqual(plist["com.apple.developer.weatherkit"] as? Bool, true)
    }

    func testPackagedLocationPermissionHasEnglishAndJapaneseInfoPlistStrings() throws {
        let root = packageRoot()
        let english = try String(
            contentsOf: root.appendingPathComponent("Sources/SuisuiApp/Resources/en.lproj/InfoPlist.strings"),
            encoding: .utf8
        )
        let japanese = try String(
            contentsOf: root.appendingPathComponent("Sources/SuisuiApp/Resources/ja.lproj/InfoPlist.strings"),
            encoding: .utf8
        )
        let buildScript = try String(
            contentsOf: root.appendingPathComponent("script/build_and_run.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(english.contains("NSLocationUsageDescription"))
        XCTAssertTrue(english.contains("only while Today weather is being shown"))
        XCTAssertTrue(japanese.contains("NSLocationUsageDescription"))
        XCTAssertTrue(japanese.contains("Todayの天気を表示している間だけ現在地を使用します"))
        XCTAssertTrue(buildScript.contains("InfoPlist.strings"))
    }

    private func loadMetadata() throws -> [String: String] {
        let url = packageRoot().appendingPathComponent("packaging/app_metadata.env")
        let contents = try String(contentsOf: url, encoding: .utf8)
        return contents
            .split(separator: "\n")
            .reduce(into: [String: String]()) { result, line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                      let separator = trimmed.firstIndex(of: "=") else {
                    return
                }
                let key = String(trimmed[..<separator])
                let value = String(trimmed[trimmed.index(after: separator)...]).trimmingMetadataQuotes()
                result[key] = value
            }
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }
}

private extension String {
    func trimmingMetadataQuotes() -> String {
        if hasPrefix("\""), hasSuffix("\""), count >= 2 {
            return String(dropFirst().dropLast())
        }
        return self
    }
}
