import Darwin
import Foundation
import SuisuiCore

private struct SeederOptions {
    let databaseURL: URL
    let evidenceHomeURL: URL

    init(arguments: [String]) throws {
        var databasePath: String?
        var evidenceHomePath: String?
        var index = 0

        while index < arguments.count {
            let flag = arguments[index]
            guard flag == "--database" || flag == "--evidence-home" else {
                throw SeederError.invalidArguments("unknown argument: \(flag)")
            }
            guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
                throw SeederError.invalidArguments("missing value for \(flag)")
            }

            let value = arguments[index + 1]
            guard !value.isEmpty else {
                throw SeederError.invalidArguments("empty value for \(flag)")
            }
            switch flag {
            case "--database":
                guard databasePath == nil else {
                    throw SeederError.invalidArguments("duplicate --database")
                }
                databasePath = value
            case "--evidence-home":
                guard evidenceHomePath == nil else {
                    throw SeederError.invalidArguments("duplicate --evidence-home")
                }
                evidenceHomePath = value
            default:
                preconditionFailure("validated flag")
            }
            index += 2
        }

        guard let databasePath, let evidenceHomePath else {
            throw SeederError.invalidArguments(
                "usage: SuisuiVisualFixtureSeeder --database <path> --evidence-home <path>"
            )
        }

        databaseURL = Self.resolvedURL(for: databasePath)
        evidenceHomeURL = Self.resolvedURL(for: evidenceHomePath)
        try Self.validate(databaseURL: databaseURL, evidenceHomeURL: evidenceHomeURL)
    }

    private static func resolvedURL(for path: String) -> URL {
        URL(
            fileURLWithPath: path,
            relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        )
        .standardizedFileURL
        .resolvingSymlinksInPath()
        .standardizedFileURL
    }

    private static func validate(databaseURL: URL, evidenceHomeURL: URL) throws {
        var evidenceHomeIsDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: evidenceHomeURL.path,
            isDirectory: &evidenceHomeIsDirectory
        ), evidenceHomeIsDirectory.boolValue else {
            throw SeederError.invalidPath("--evidence-home must resolve to an existing directory")
        }

        var databaseIsDirectory: ObjCBool = false
        if FileManager.default.fileExists(
            atPath: databaseURL.path,
            isDirectory: &databaseIsDirectory
        ), databaseIsDirectory.boolValue {
            throw SeederError.invalidPath("--database must resolve to a file")
        }

        let homeComponents = evidenceHomeURL.pathComponents
        let databaseComponents = databaseURL.pathComponents
        guard databaseComponents.count > homeComponents.count,
              Array(databaseComponents.prefix(homeComponents.count)) == homeComponents else {
            throw SeederError.invalidPath(
                "--database must be a file below the resolved --evidence-home"
            )
        }
    }
}

private enum SeederError: Error, CustomStringConvertible {
    case invalidArguments(String)
    case invalidPath(String)
    case invalidPresentation(id: String, expected: String)

    var description: String {
        switch self {
        case .invalidArguments(let message), .invalidPath(let message):
            message
        case .invalidPresentation(let id, let expected):
            "seeded \(id) did not expose \(expected) as its primary action"
        }
    }
}

private struct FixtureDefinition {
    let id: String
    let planID: String
    let actionID: String
}

private let waitingFixture = FixtureDefinition(
    id: "visual-waiting",
    planID: "visual-plan-waiting",
    actionID: "visual-action-waiting"
)

private let approvedFixture = FixtureDefinition(
    id: "visual-approved",
    planID: "visual-plan-approved",
    actionID: "visual-action-approved"
)

private let failedFixture = FixtureDefinition(
    id: "visual-failed",
    planID: "visual-plan-failed",
    actionID: "visual-action-failed"
)

private func waitingItem(for fixture: FixtureDefinition) -> AssistantQueueItem {
    let plan = ActionPlan(
        id: fixture.planID,
        userInput: "Prepare local visual evidence",
        summary: "Prepare local visual evidence",
        actions: [
            PlanAction(
                id: fixture.actionID,
                tool: .taskCreate,
                // All visual states intentionally share one inert local action.
                // This isolates state presentation from payload wording and
                // proves that captures never exercise an external connector.
                arguments: [
                    "title": .string("Review local visual evidence"),
                    "detail": .string("Visual fixture only; no external connector is invoked.")
                ],
                riskLevel: .write
            )
        ],
        riskLevel: .write,
        requiresApproval: true
    )
    var item = AssistantQueueAdapter.makeItem(
        actionPlan: plan,
        sourceTranscript: nil,
        interpretationSummary: "Local visual evidence task draft.",
        reason: "Review this local visual fixture before approval."
    )
    // The adapter owns every approval-related field. Only the fixture identity
    // is replaced so captures can address stable rows without hand-building
    // approval JSON that could drift from the production model.
    item.id = fixture.id
    return item
}

private func run(options: SeederOptions) throws {
    try FileManager.default.createDirectory(
        at: options.databaseURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let store = try SQLiteAssistantQueueStore(path: options.databaseURL.path)

    let waiting = waitingItem(for: waitingFixture)
    let approved = try AssistantQueueStateMachine.approve(
        waitingItem(for: approvedFixture),
        reviewerID: "visual-evidence-reviewer"
    )
    let failed = try AssistantQueueStateMachine.markFailed(
        AssistantQueueStateMachine.startRunning(
            AssistantQueueStateMachine.approve(
                waitingItem(for: failedFixture),
                reviewerID: "visual-evidence-reviewer"
            )
        ),
        reason: "visual-evidence-simulated-failure"
    )

    for item in [waiting, approved, failed] {
        try store.save(item)
    }

    let snapshot = try store.readModelSnapshot(filter: .all(limit: 100))
    let rowsByID = Dictionary(uniqueKeysWithValues: snapshot.rows.map { ($0.id, $0) })
    let expectedActions: [(String, AssistantQueueRowActionPresentation.Action, String)] = [
        (waiting.id, .approve, "approve"),
        (approved.id, .run, "run"),
        (failed.id, .reopen, "reopen")
    ]
    for (id, expectedAction, expectedName) in expectedActions {
        guard let row = rowsByID[id],
              AssistantQueueRowActionPresentation.make(for: row).primaryAction == expectedAction else {
            throw SeederError.invalidPresentation(id: id, expected: expectedName)
        }
    }
}

do {
    let options = try SeederOptions(arguments: Array(CommandLine.arguments.dropFirst()))
    try run(options: options)
} catch {
    fputs("BLOCKER: \(error)\n", stderr)
    exit(2)
}
