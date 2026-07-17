import Foundation
import XCTest

final class ProjectBoardMetadataLayoutSourceTests: XCTestCase {
    func testTaskCardButtonPublishesTaskSpecificLocalizedMetadataForRuntimeAX() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardDetailViews.swift")
        let cardStart = try XCTUnwrap(source.range(of: "private struct BoardTaskCard: View"))
        let cardEnd = try XCTUnwrap(
            source.range(of: "private struct TaskCardSelectableSummary: View", range: cardStart.upperBound..<source.endIndex)
        )
        let cardSource = String(source[cardStart.lowerBound..<cardEnd.lowerBound])

        XCTAssertTrue(cardSource.contains(".accessibilityIdentifier(\"task-card-open-details-\\(task.id)\")"))
        XCTAssertFalse(cardSource.contains(".accessibilityIdentifier(\"task-card-open-details\")"))
        XCTAssertTrue(cardSource.contains("accessibilityMetadataValue"))
        XCTAssertTrue(cardSource.contains("recurrenceValue.map"))
        XCTAssertTrue(cardSource.contains("localizedDisplay(task.status.title)"))
        XCTAssertTrue(cardSource.contains("localizedDisplay(task.priority.label)"))
        XCTAssertTrue(cardSource.contains("task.dueLabel.map(localizedDisplay) ?? localizedDisplay(\"No due date\")"))
        XCTAssertTrue(cardSource.contains("Button(action: onOpenDetails) {\n                TaskCardSelectableSummary(task: task, isPointerHovered: isPointerHovered)"))
        XCTAssertTrue(cardSource.contains(".accessibilityElement(children: .combine)"))
        XCTAssertTrue(cardSource.contains(".accessibilityLabel(\"Open task \\(task.title)\")"))
    }

    func testMetadataLineUsesOneVerbatimTextNodeSoHostedRenderingCannotDropChildLabels() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardDetailViews.swift")
        let lineStart = try XCTUnwrap(source.range(of: "private struct TaskMetadataLine: View"))
        let lineEnd = try XCTUnwrap(
            source.range(of: "private struct ProjectTaskList: View", range: lineStart.upperBound..<source.endIndex)
        )
        let lineSource = String(source[lineStart.lowerBound..<lineEnd.lowerBound])

        XCTAssertTrue(lineSource.contains("Text(verbatim: value)"))
        XCTAssertFalse(lineSource.contains("Image(systemName:"))
        XCTAssertFalse(lineSource.contains("HStack"))
        XCTAssertTrue(lineSource.contains(".lineLimit(1)"))
        XCTAssertTrue(lineSource.contains(".minimumScaleFactor(0.82)"))
        XCTAssertTrue(lineSource.contains("maxWidth: .infinity"))
        XCTAssertFalse(lineSource.contains(".foregroundStyle(tint)"))
    }

    func testSelectedMaterialTaskCardUsesConcreteTextColorsOnHostedRunner() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardDetailViews.swift")
        let cardStart = try XCTUnwrap(source.range(of: "private struct BoardTaskCard: View"))
        let cardEnd = try XCTUnwrap(
            source.range(of: "private struct TaskCardSelectableSummary: View", range: cardStart.upperBound..<source.endIndex)
        )
        let cardSource = String(source[cardStart.lowerBound..<cardEnd.lowerBound])
        let summaryStart = try XCTUnwrap(source.range(of: "private struct TaskCardSelectableSummary: View"))
        let summaryEnd = try XCTUnwrap(
            source.range(of: "private struct TaskDragAffordance: View", range: summaryStart.upperBound..<source.endIndex)
        )
        let summarySource = String(source[summaryStart.lowerBound..<summaryEnd.lowerBound])
        let controlsStart = try XCTUnwrap(source.range(of: "private struct TaskStatusMoveControls: View"))
        let controlsEnd = try XCTUnwrap(
            source.range(of: "private struct TaskCardMetadataStrip: View", range: controlsStart.upperBound..<source.endIndex)
        )
        let controlsSource = String(source[controlsStart.lowerBound..<controlsEnd.lowerBound])

        XCTAssertTrue(summarySource.contains("Text(task.detail)"))
        XCTAssertTrue(summarySource.contains(".foregroundColor(.secondary)"))
        XCTAssertFalse(summarySource.contains(".foregroundStyle(.secondary)"))
        XCTAssertTrue(controlsSource.contains("Text(LocalizedStringKey(task.status.title))"))
        XCTAssertTrue(controlsSource.contains(".foregroundColor(.secondary)"))
        XCTAssertFalse(controlsSource.contains(".foregroundStyle(.secondary)"))
        XCTAssertTrue(cardSource.contains(".background(task.status.tint.opacity(0.05)"))
        XCTAssertFalse(cardSource.contains(".background(task.status.tint.opacity(isSelected"))
        XCTAssertTrue(cardSource.contains(".stroke(isSelected || isPointerHovered"))
    }

    func testMetadataStripComposesStatusPriorityDueAndRecurrenceIntoOneReadableValue() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardDetailViews.swift")
        let stripStart = try XCTUnwrap(source.range(of: "private struct TaskCardMetadataStrip: View"))
        let stripEnd = try XCTUnwrap(
            source.range(of: "private struct ProjectTaskList: View", range: stripStart.upperBound..<source.endIndex)
        )
        let stripSource = String(source[stripStart.lowerBound..<stripEnd.lowerBound])

        XCTAssertTrue(stripSource.contains("TaskMetadataLine(value: identityLineValue"))
        XCTAssertTrue(stripSource.contains("if let scheduleLineValue"))
        XCTAssertTrue(stripSource.contains("TaskMetadataLine(value: scheduleLineValue"))
        XCTAssertTrue(stripSource.contains("private var identityLineValue: String"))
        XCTAssertTrue(stripSource.contains("private var scheduleLineValue: String?"))
        XCTAssertTrue(stripSource.contains("components.joined(separator: \" · \")"))
        XCTAssertTrue(stripSource.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        XCTAssertFalse(stripSource.contains("TaskMetadataChip"))
        XCTAssertFalse(stripSource.contains("ViewThatFits"))
    }

    func testMetadataStripKeepsCompleteAccessibilityValueIndependentOfVisualTruncation() throws {
        let source = try readPackageFile("Sources/SoloPMApp/Views/ProjectBoardDetailViews.swift")

        XCTAssertEqual(source.components(separatedBy: ".accessibilityValue(accessibilityValueText)").count - 1, 1)
        XCTAssertTrue(source.contains("private var accessibilityMetadataValue: String"))
        XCTAssertTrue(source.contains("recurrenceValue.map"))
        XCTAssertTrue(source.contains("private var localizedStatusValue: String"))
        XCTAssertTrue(source.contains("localizedDisplay(task.status.title)"))
        XCTAssertTrue(source.contains("private var localizedPriorityValue: String"))
        XCTAssertTrue(source.contains("localizedDisplay(task.priority.label)"))
        XCTAssertTrue(source.contains("private var localizedDueValue: String"))
        XCTAssertTrue(source.contains("task.dueLabel.map(localizedDisplay) ?? localizedDisplay(\"No due date\")"))
        XCTAssertTrue(source.contains("Text(verbatim: value)"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"task-card-metadata-strip-\\(task.id)\")"))
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
