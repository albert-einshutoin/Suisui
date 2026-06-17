import Foundation
import XCTest

final class LaunchExperienceTests: XCTestCase {
    func testRunScriptActivatesAppAfterOpeningBundle() throws {
        let script = try readPackageFile("script/build_and_run.sh")

        XCTAssertTrue(script.contains("/usr/bin/open -n \"$APP_BUNDLE\""))
        XCTAssertTrue(script.contains("tell application \\\"$APP_NAME\\\" to activate"))
    }

    func testAppDelegateActivatesRegularAppOnLaunch() throws {
        let source = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

        XCTAssertTrue(source.contains("NSApp.setActivationPolicy(.regular)"))
        XCTAssertTrue(source.contains("NSApp.activate(ignoringOtherApps: true)"))
    }

    func testVoiceCommandDemoWindowOpensOnLaunch() throws {
        let source = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")

        XCTAssertTrue(source.contains("WindowGroup(\"Voice Command\", id: \"voice-capture\")"))

        let voiceWindow = try XCTUnwrap(source.range(of: "WindowGroup(\"Voice Command\", id: \"voice-capture\")"))
        let menuBar = try XCTUnwrap(source.range(of: "MenuBarExtra(\"SoloPM\", systemImage: \"checklist\")"))
        XCTAssertLessThan(voiceWindow.lowerBound, menuBar.lowerBound)
    }

    private func readPackageFile(_ relativePath: String) throws -> String {
        let url = packageRoot().appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }
}
