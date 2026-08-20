import Foundation
import XCTest

final class SuisuiLiquidGlassContractTests: XCTestCase {
    func testLiquidGlassModuleUsesAvailabilityFallbackAndSemanticTokens() throws {
        let source = try readSource("Sources/SuisuiApp/Views/SuisuiLiquidGlass.swift")

        XCTAssertTrue(source.contains("enum SuisuiLiquidGlass"))
        XCTAssertTrue(source.contains("#available(macOS 26.0, *)"))
        XCTAssertTrue(source.contains(".glassEffect("))
        XCTAssertTrue(source.contains("GlassEffectContainer(spacing:"))
        XCTAssertTrue(source.contains(".regularMaterial"))
        XCTAssertTrue(source.contains("SuisuiBorder.subtle"))
        XCTAssertTrue(source.contains("func suisuiLiquidGlassControlSurface("))
        XCTAssertTrue(source.contains("func suisuiLiquidGlassCapturePanel()"))
        XCTAssertTrue(source.contains("func suisuiLiquidGlassControlGroup("))
        XCTAssertFalse(source.contains("NavigationSplitView"))
        XCTAssertFalse(source.contains(".toolbar"))
    }

    func testSidebarControlLayerUsesLiquidGlassSurfaces() throws {
        let source = try readSource("Sources/SuisuiApp/Views/ProjectBoardSidebarView.swift")

        XCTAssertTrue(source.contains(".suisuiLiquidGlassControlSurface(cornerRadius: 12)"))
        XCTAssertTrue(source.contains(".suisuiLiquidGlassControlSurface("))
        XCTAssertTrue(source.contains(".suisuiLiquidGlassControlGroup(spacing: SuisuiSpacing.md)"))
        XCTAssertFalse(source.contains(".background(.background, in: RoundedRectangle(cornerRadius: 12"))
    }

    func testVoiceCaptureControlPanelUsesLiquidGlassCaptureSurface() throws {
        let source = try readSource("Sources/SuisuiApp/Views/VoiceCaptureView.swift")

        XCTAssertTrue(source.contains(".suisuiLiquidGlassCapturePanel()"))
        XCTAssertTrue(source.contains("voice-command-understood-rail"))
        XCTAssertTrue(source.contains("voice-command-context-rail"))
        XCTAssertTrue(source.contains("struct VoiceListeningOrb"))
    }

    func testSettingsAppearanceControlsUseLiquidGlassSurfaces() throws {
        let source = try readSource("Sources/SuisuiApp/Views/SettingsAppearanceSection.swift")

        XCTAssertTrue(source.contains(".suisuiLiquidGlassControlSurface(cornerRadius: 12, interactive: true)"))
        XCTAssertTrue(source.contains("settings-theme-picker"))
        XCTAssertTrue(source.contains("settings-language-picker"))
    }

    private func readSource(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
