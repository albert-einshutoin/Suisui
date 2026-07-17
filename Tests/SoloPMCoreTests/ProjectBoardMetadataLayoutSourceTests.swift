import Foundation
import XCTest

final class ProjectBoardMetadataLayoutSourceTests: XCTestCase {
    func testMetadataChipReservesTextWidthWhenPersistentScrollbarsNarrowTheCard() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardDetailViews.swift")
        let chipStart = try XCTUnwrap(source.range(of: "private struct TaskMetadataChip: View"))
        let chipEnd = try XCTUnwrap(
            source.range(of: "private struct ProjectTaskList: View", range: chipStart.upperBound..<source.endIndex)
        )
        let chipSource = String(source[chipStart.lowerBound..<chipEnd.lowerBound])

        XCTAssertTrue(chipSource.contains("private static let minimumTextWidth: CGFloat = 24"))
        XCTAssertTrue(chipSource.contains("HStack(spacing: 4)"))
        XCTAssertTrue(chipSource.contains(".layoutPriority(1)"))
        XCTAssertTrue(chipSource.contains("minWidth: Self.minimumTextWidth"))
        XCTAssertTrue(chipSource.contains(".fixedSize(horizontal: true, vertical: false)"))
        XCTAssertTrue(chipSource.contains(".lineLimit(1)"))
        XCTAssertTrue(chipSource.contains(".truncationMode(.tail)"))
        XCTAssertTrue(chipSource.contains(".minimumScaleFactor(0.82)"))
        XCTAssertTrue(chipSource.contains("minWidth: ProjectBoardLayoutMetrics.taskMetadataChipMinWidth"))
    }

    func testMetadataStripKeepsCompleteAccessibilityValueIndependentOfVisualTruncation() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardDetailViews.swift")

        XCTAssertTrue(
            source.contains(".accessibilityValue(\"\\(localizedStatusValue), \\(localizedPriorityValue), \\(localizedDueValue)\")")
        )
        XCTAssertTrue(source.contains("private var localizedStatusValue: String"))
        XCTAssertTrue(source.contains("localizedDisplay(task.status.title)"))
        XCTAssertTrue(source.contains("private var localizedPriorityValue: String"))
        XCTAssertTrue(source.contains("localizedDisplay(task.priority.label)"))
        XCTAssertTrue(source.contains("private var localizedDueValue: String"))
        XCTAssertTrue(source.contains("task.dueLabel.map(localizedDisplay) ?? localizedDisplay(\"No due date\")"))
        XCTAssertTrue(source.contains("Text(localizedDisplay(value))"))
        XCTAssertTrue(
            source.contains(".accessibilityIdentifier(\"task-card-metadata-strip-\\(task.id)\")")
        )
        XCTAssertFalse(source.contains(".accessibilityIdentifier(\"task-card-metadata-strip\")"))
    }

    func testMetadataLocalizationCatalogCoversStatusPriorityAndDatelessValues() throws {
        let english = try readPackageFile("Sources/SoloPMApp/Resources/en.lproj/Localizable.strings")
        let japanese = try readPackageFile("Sources/SoloPMApp/Resources/ja.lproj/Localizable.strings")

        for (key, englishValue, japaneseValue) in [
            ("Planned", "Planned", "予定"),
            ("Low", "Low", "低"),
            ("Medium", "Medium", "中"),
            ("High", "High", "高"),
            ("No due date", "No due date", "期限なし")
        ] {
            XCTAssertEqual(localizationValue(for: key, in: english), englishValue)
            XCTAssertEqual(localizationValue(for: key, in: japanese), japaneseValue)
            XCTAssertEqual(localizationKeyCount(key, in: english), 1)
            XCTAssertEqual(localizationKeyCount(key, in: japanese), 1)
        }
    }

    private func localizationValue(for key: String, in catalog: String) -> String? {
        let prefix = "\"\(key)\" = \""
        guard let start = catalog.range(of: prefix) else { return nil }
        let suffix = catalog[start.upperBound...]
        guard let end = suffix.range(of: "\";") else { return nil }
        return String(suffix[..<end.lowerBound])
    }

    private func localizationKeyCount(_ key: String, in catalog: String) -> Int {
        catalog.components(separatedBy: "\"\(key)\" = ").count - 1
    }

    private func readPackageFile(_ relativePath: String) throws -> String {
        try String(
            contentsOf: packageRoot().appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func packageRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}
