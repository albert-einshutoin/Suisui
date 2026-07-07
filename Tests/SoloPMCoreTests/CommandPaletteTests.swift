import XCTest
@testable import SoloPMCore

final class CommandPaletteTests: XCTestCase {
    private func makeProjects(_ titles: [(String, Bool)]) -> [(id: Int64, title: String, isArchived: Bool)] {
        titles.enumerated().map { index, entry in
            (id: Int64(index + 1), title: entry.0, isArchived: entry.1)
        }
    }

    func testEmptyQueryListsDestinationsWindowActionsThenProjects() {
        let items = CommandPaletteComposer.items(
            query: "  ",
            projects: makeProjects([
                ("Release prep", false),
                ("Website refresh", false),
                ("Old archive", true)
            ])
        )

        XCTAssertEqual(
            items.map(\.id),
            [
                "destination-today",
                "destination-inbox",
                "destination-assistant-queue",
                "destination-schedule",
                "destination-done",
                "destination-catch-up",
                "window-voice-command",
                "window-settings",
                "project-1",
                "project-2"
            ]
        )
        XCTAssertFalse(items.contains { item in
            if case .createInboxTask = item.kind {
                return true
            }
            return false
        })
        XCTAssertEqual(items[0].kind, .openDestination(.today))
        XCTAssertEqual(items[6].kind, .openVoiceCommandWindow)
        XCTAssertEqual(items[7].kind, .openSettingsWindow)
        XCTAssertEqual(items[8].kind, .openProject(id: 1, title: "Release prep"))
    }

    func testEmptyQueryCapsProjectsAtFiveNonArchived() {
        let projects = makeProjects((1...9).map { ("Project \($0)", false) })
        let items = CommandPaletteComposer.items(query: "", projects: projects)

        let projectItems = items.filter { $0.id.hasPrefix("project-") }
        XCTAssertEqual(projectItems.count, 4, "cap of 12 leaves room for 4 of the 5 eligible projects")
        XCTAssertEqual(items.count, CommandPaletteComposer.maxItemCount)
    }

    func testFuzzyScoreMatchesCaseInsensitiveSubsequence() throws {
        XCTAssertNotNil(CommandPaletteComposer.fuzzyScore(query: "tdy", candidate: "Today"))
        XCTAssertNotNil(CommandPaletteComposer.fuzzyScore(query: "TDY", candidate: "today"))
        XCTAssertNil(CommandPaletteComposer.fuzzyScore(query: "tdz", candidate: "Today"))
        XCTAssertNil(CommandPaletteComposer.fuzzyScore(query: "todayy", candidate: "Today"))

        let prefixScore = try XCTUnwrap(CommandPaletteComposer.fuzzyScore(query: "to", candidate: "Today"))
        let scatteredScore = try XCTUnwrap(CommandPaletteComposer.fuzzyScore(query: "ty", candidate: "Today"))
        XCTAssertGreaterThan(prefixScore, scatteredScore, "contiguous prefixes outrank scattered matches")

        let boundaryScore = try XCTUnwrap(CommandPaletteComposer.fuzzyScore(query: "q", candidate: "Assistant Queue"))
        let interiorScore = try XCTUnwrap(CommandPaletteComposer.fuzzyScore(query: "s", candidate: "Assistant Queue"))
        XCTAssertGreaterThan(boundaryScore, interiorScore, "word boundaries outrank interior matches")
    }

    func testQueryPutsCreateInboxTaskFirstThenFuzzyMatches() {
        let items = CommandPaletteComposer.items(query: "tdy", projects: [])

        XCTAssertEqual(items.first?.id, "create-inbox-task")
        XCTAssertEqual(items.first?.kind, .createInboxTask(title: "tdy"))
        XCTAssertEqual(items.first?.title, "tdy")
        XCTAssertEqual(items.first?.subtitle, "Add to Inbox")
        XCTAssertTrue(items.contains { $0.id == "destination-today" })
        XCTAssertFalse(items.contains { $0.id == "destination-done" })
    }

    func testQueryMatchesProjectsAndExcludesArchivedOnes() {
        let items = CommandPaletteComposer.items(
            query: "rel",
            projects: makeProjects([
                ("Release prep", false),
                ("Relay archive", true)
            ])
        )

        XCTAssertTrue(items.contains { $0.kind == .openProject(id: 1, title: "Release prep") })
        XCTAssertFalse(items.contains { $0.id == "project-2" })
        XCTAssertEqual(items.first?.kind, .createInboxTask(title: "rel"))
    }

    func testQueryTrimsWhitespaceBeforeComposingCreateAction() {
        let items = CommandPaletteComposer.items(query: "  buy milk tomorrow  ", projects: [])

        XCTAssertEqual(items.first?.kind, .createInboxTask(title: "buy milk tomorrow"))
    }

    func testQueryResultsAreCappedAtTwelveItems() {
        let projects = makeProjects((1...30).map { ("Project \($0)", false) })
        let items = CommandPaletteComposer.items(query: "project", projects: projects)

        XCTAssertEqual(items.count, CommandPaletteComposer.maxItemCount)
        XCTAssertEqual(items.first?.id, "create-inbox-task")
    }

    func testQueryOrdersMatchesByScoreThenTitle() {
        let items = CommandPaletteComposer.items(
            query: "pre",
            projects: makeProjects([
                ("Press kit", false),
                ("Prep work", false)
            ])
        )

        let matchIDs = items.dropFirst().map(\.id)
        XCTAssertEqual(matchIDs, ["project-2", "project-1"], "equal scores fall back to title ordering")
    }
}
