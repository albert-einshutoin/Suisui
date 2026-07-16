import Foundation
import XCTest

final class SoloPMDesignTokenContractTests: XCTestCase {
    func testDesignSystemDefinesEveryApprovedSemanticLayer() throws {
        let source = try readSource("Sources/SoloPMApp/Views/SoloPMDesignSystem.swift")

        for symbol in [
            "SoloPMBrand",
            "SoloPMTypography",
            "SoloPMSurface",
            "SoloPMBorder",
            "SoloPMMotion",
            "SoloPMIconMetrics",
            "SoloPMControlDensity"
        ] {
            XCTAssertTrue(source.contains("enum \(symbol)"), "Missing \(symbol)")
        }
    }

    func testTokensExposeConcreteAdaptiveSwiftUIValues() throws {
        let source = try readSource("Sources/SoloPMApp/Views/SoloPMDesignSystem.swift")

        XCTAssertTrue(source.contains("Color(nsColor:"))
        XCTAssertTrue(source.contains("NSColor.Name(name)"))
        XCTAssertTrue(source.contains("dynamicProvider"))
        XCTAssertTrue(source.contains("static let pageTitle: Font"))
        XCTAssertTrue(source.contains("static let groupedContent: AnyShapeStyle"))
        XCTAssertTrue(source.contains("static let subtle: Color"))
        XCTAssertTrue(source.contains("static let compact: CGFloat"))
        XCTAssertTrue(source.contains("static let prominent: ControlSize"))
        XCTAssertTrue(source.contains("accessibilityReduceMotion"))
        XCTAssertTrue(source.contains("reduceMotion ? nil"))
    }

    func testAssistantSignalAndCardUseSemanticSolidAdaptiveSurfaces() throws {
        let source = try readSource("Sources/SoloPMApp/Views/SoloPMDesignSystem.swift")

        XCTAssertTrue(source.contains("func soloAssistantSignal() -> some View"))
        XCTAssertTrue(source.contains("SoloPMSurface.assistantSignal"))
        XCTAssertTrue(source.contains("SoloPMBorder.attention"))
        XCTAssertTrue(source.contains("func soloCard() -> some View"))
        XCTAssertTrue(source.contains("SoloPMSurface.groupedContent"))
        XCTAssertFalse(source.contains("Material"))
        XCTAssertFalse(source.contains("LinearGradient"))
        XCTAssertFalse(source.contains("RadialGradient"))
    }

    func testSemanticTokenSourceRejectsRawStatusColorsAndAnonymousRadii() throws {
        let source = try readSource("Sources/SoloPMApp/Views/SoloPMDesignSystem.swift")

        for forbidden in [".red", ".orange", ".green", "cornerRadius: 8", "cornerRadius: 10"] {
            XCTAssertFalse(source.contains(forbidden), "Design tokens reintroduced raw styling: \(forbidden)")
        }
        XCTAssertTrue(source.contains("SoloPMRadius.card"))
        XCTAssertTrue(source.contains("static let control: CGFloat"))
    }

    func testDesignSystemDoesNotCustomSkinNativeContainers() throws {
        let source = try readSource("Sources/SoloPMApp/Views/SoloPMDesignSystem.swift")

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
