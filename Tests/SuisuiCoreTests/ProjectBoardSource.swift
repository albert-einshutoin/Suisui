import Foundation

/// Source contracts inspect the bounded board implementation, not a former
/// physical monolith. Missing owners fail the read instead of skipping checks.
func readProjectBoardImplementation() throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let featureDirectory = root.appendingPathComponent("Sources/SuisuiCore/App/ProjectBoard")
    let features = try FileManager.default.contentsOfDirectory(
        at: featureDirectory, includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "swift" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    let owners = [
        root.appendingPathComponent("Sources/SuisuiCore/App/ProjectBoard.swift"),
        root.appendingPathComponent("Sources/SuisuiCore/WorkManagement/ProjectBoardReadModels.swift"),
        root.appendingPathComponent("Sources/SuisuiCore/WorkManagement/ProjectBoardPresentationModels.swift"),
        root.appendingPathComponent("Sources/SuisuiCore/DeveloperMode/ProjectDevelopmentPresentation.swift"),
        root.appendingPathComponent("Sources/SuisuiCore/Review/TaskAutomationPresentation.swift"),
        root.appendingPathComponent("Sources/SuisuiCore/WorkManagement/LocalWorkspaceFailureMessage.swift"),
        root.appendingPathComponent("Sources/SuisuiCore/WorkManagement/LocalPlanningPolicy.swift")
    ] + features
    return try owners.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n\n")
}

func readProjectBoardShellImplementation() throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return try [
        "ProjectBoardView.swift", "ProjectBoardPlatformPresentation.swift",
        "ProjectBoardCommands.swift", "ProjectBoardTaskInteropDocument.swift", "ProjectBoardDisplay.swift"
    ].map { filename in
        try String(contentsOf: root.appendingPathComponent("Sources/SuisuiApp/Views/" + filename), encoding: .utf8)
    }.joined(separator: "\n\n")
}
