import Foundation
import XCTest

final class SuisuiDesignTokenContractTests: XCTestCase {
    func testDesignSystemDefinesEveryApprovedSemanticLayer() throws {
        let source = try readSource("Sources/SuisuiApp/Views/SuisuiDesignSystem.swift")

        for symbol in [
            "SuisuiBrand",
            "SuisuiTypography",
            "SuisuiSurface",
            "SuisuiBorder",
            "SuisuiMotion"
        ] {
            XCTAssertTrue(source.contains("enum \(symbol)"), "Missing \(symbol)")
        }
    }

    func testTokensExposeConcreteAdaptiveSwiftUIValues() throws {
        let source = try readSource("Sources/SuisuiApp/Views/SuisuiDesignSystem.swift")

        XCTAssertTrue(source.contains("Color(nsColor:"))
        XCTAssertTrue(source.contains("NSColor.Name(name)"))
        XCTAssertTrue(source.contains("dynamicProvider"))
        XCTAssertTrue(source.contains("static let sectionTitle: Font"))
        XCTAssertTrue(source.contains("static let groupedContent: AnyShapeStyle"))
        XCTAssertTrue(source.contains("static let subtle: Color"))
        XCTAssertTrue(source.contains("accessibilityReduceMotion"))
        XCTAssertTrue(source.contains("reduceMotion ? nil"))
    }

    func testAssistantSignalAndCardUseSemanticSolidAdaptiveSurfaces() throws {
        let source = try readSource("Sources/SuisuiApp/Views/SuisuiDesignSystem.swift")

        XCTAssertTrue(source.contains("func soloAssistantSignal() -> some View"))
        XCTAssertTrue(source.contains("SuisuiSurface.assistantSignal"))
        XCTAssertTrue(source.contains("SuisuiBorder.attention"))
        XCTAssertTrue(source.contains("func soloCard() -> some View"))
        XCTAssertTrue(source.contains("SuisuiSurface.groupedContent"))
        XCTAssertFalse(source.contains("Material"))
        XCTAssertFalse(source.contains("LinearGradient"))
        XCTAssertFalse(source.contains("RadialGradient"))
    }

    func testSemanticTokenSourceRejectsRawStatusColorsAndAnonymousRadii() throws {
        let source = try readSource("Sources/SuisuiApp/Views/SuisuiDesignSystem.swift")

        for forbidden in [".red", ".orange", ".green", "cornerRadius: 8", "cornerRadius: 10"] {
            XCTAssertFalse(source.contains(forbidden), "Design tokens reintroduced raw styling: \(forbidden)")
        }
        XCTAssertTrue(source.contains("SuisuiRadius.card"))
        XCTAssertTrue(source.contains("static let control: CGFloat"))
    }

    func testDesignSystemDoesNotCustomSkinNativeContainers() throws {
        let source = try readSource("Sources/SuisuiApp/Views/SuisuiDesignSystem.swift")

        for nativeRoot in ["NavigationSplitView", ".toolbar", "Form {", ".inspector"] {
            XCTAssertFalse(source.contains(nativeRoot), "Design tokens must not skin native root: \(nativeRoot)")
        }
    }

    func testDesignSystemDocumentationDefinesCalmSignalDeskBoundaries() throws {
        let documentation = try readSource("docs/ux/design-system.md")

        XCTAssertTrue(documentation.contains("Calm Signal Desk"))
        XCTAssertTrue(documentation.contains("Signal Amber"))
        XCTAssertTrue(documentation.contains("Reduce Motion"))
        XCTAssertTrue(documentation.contains("native sidebar"))
        XCTAssertTrue(documentation.contains("raw status"))
        XCTAssertTrue(documentation.contains("`.soloAssistantSignal()`"))
    }

    private func readSource(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
