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

    func testEmptyQueryWithoutSmartListsOmitsSmartListItems() {
        let items = CommandPaletteComposer.items(query: "", projects: [])

        XCTAssertFalse(items.contains { item in
            if case .openSmartList = item.kind {
                return true
            }
            return false
        })
    }

    func testEmptyQueryPlacesSmartListsAfterWindowActionsBeforeProjects() throws {
        let items = CommandPaletteComposer.items(
            query: "",
            projects: makeProjects([("Release prep", false)]),
            smartLists: [(id: "preset-high-priority", name: "High priority")]
        )

        let settingsIndex = try XCTUnwrap(items.firstIndex { $0.id == "window-settings" })
        let smartListIndex = try XCTUnwrap(items.firstIndex { $0.id == "smart-list-preset-high-priority" })
        let projectIndex = try XCTUnwrap(items.firstIndex { $0.id == "project-1" })

        XCTAssertLessThan(settingsIndex, smartListIndex)
        XCTAssertLessThan(smartListIndex, projectIndex)
        XCTAssertEqual(
            items[smartListIndex].kind,
            .openSmartList(id: "preset-high-priority", name: "High priority")
        )
    }

    func testQueryFuzzyMatchesSmartListsAlongsideOtherCandidates() {
        let items = CommandPaletteComposer.items(
            query: "high",
            projects: makeProjects([("High seas", false)]),
            smartLists: [
                (id: "preset-high-priority", name: "High priority"),
                (id: "saved-1", name: "Blocked reviews")
            ]
        )

        XCTAssertEqual(items.first?.kind, .createInboxTask(title: "high"))
        XCTAssertTrue(items.contains { $0.kind == .openSmartList(id: "preset-high-priority", name: "High priority") })
        XCTAssertTrue(items.contains { $0.kind == .openProject(id: 1, title: "High seas") })
        XCTAssertFalse(items.contains { $0.id == "smart-list-saved-1" })
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

    // MARK: - Content matches (T-15)

    private func makeContentMatches(_ count: Int) -> [CommandPaletteContentMatch] {
        (1...count).map { index in
            CommandPaletteContentMatch(
                source: .task(id: Int64(index), projectID: 3),
                title: "Task \(index)",
                content: "shared keyword body \(index)"
            )
        }
    }

    func testContentSectionAppearsOnlyAtMinimumQueryLength() {
        let matches = makeContentMatches(2)

        XCTAssertTrue(CommandPaletteComposer.contentItems(query: "k", matches: matches).isEmpty)
        XCTAssertTrue(CommandPaletteComposer.contentItems(query: "  k  ", matches: matches).isEmpty)
        XCTAssertTrue(CommandPaletteComposer.contentItems(query: "", matches: matches).isEmpty)
        XCTAssertEqual(CommandPaletteComposer.contentItems(query: "ke", matches: matches).count, 2)
    }

    func testContentItemsAreCappedAtFive() {
        let items = CommandPaletteComposer.contentItems(query: "keyword", matches: makeContentMatches(9))

        XCTAssertEqual(CommandPaletteComposer.maxContentItemCount, 5)
        XCTAssertEqual(items.count, 5)
        XCTAssertEqual(items.map(\.id), ["fts-task-1", "fts-task-2", "fts-task-3", "fts-task-4", "fts-task-5"])
    }

    func testVisibleItemsKeepFuzzyResultsBeforeContentSection() throws {
        let primary = CommandPaletteComposer.items(
            query: "release",
            projects: makeProjects([("Release prep", false)])
        )
        let content = CommandPaletteComposer.contentItems(
            query: "release",
            matches: [
                CommandPaletteContentMatch(
                    source: .task(id: 42, projectID: 1),
                    title: "Ship it",
                    content: "Draft the release notes first."
                )
            ]
        )

        let visible = CommandPaletteComposer.visibleItems(primary: primary, content: content)

        XCTAssertEqual(visible.map(\.id).prefix(primary.count), ArraySlice(primary.map(\.id)))
        let contentIndex = try XCTUnwrap(visible.firstIndex { $0.id == "fts-task-42" })
        let lastPrimaryIndex = try XCTUnwrap(visible.firstIndex { $0.id == primary.last?.id })
        XCTAssertGreaterThan(contentIndex, lastPrimaryIndex, "content matches follow every fuzzy result")
    }

    func testContentSnippetStripsNewlinesAndTruncatesAroundMatch() {
        let content = """
        First line of a long task description that keeps going for a while.
        The keyword INVOICE hides on the second line with trailing context after it.
        """
        let snippet = CommandPaletteComposer.contentSnippet(from: content, query: "invoice")

        XCTAssertFalse(snippet.contains("\n"))
        XCTAssertTrue(snippet.localizedCaseInsensitiveContains("invoice"))
        XCTAssertLessThanOrEqual(
            snippet.count,
            CommandPaletteComposer.contentSnippetCharacterLimit + 2,
            "limit plus at most one leading and one trailing ellipsis"
        )
        XCTAssertTrue(snippet.hasPrefix("…"), "clipped leading context is marked")

        let short = CommandPaletteComposer.contentSnippet(from: "tiny\nnote", query: "note")
        XCTAssertEqual(short, "tiny note")
    }

    func testContentItemsFromFakeProviderMapToNavigationKindsAndStableIdentifiers() {
        let fakeProvider: CommandPaletteContentSearch = { _ in
            [
                CommandPaletteContentMatch(
                    source: .task(id: 7, projectID: 12),
                    title: "Write launch email",
                    content: "Mention the beta signup link."
                ),
                CommandPaletteContentMatch(
                    source: .task(id: 8, projectID: nil),
                    title: "Inbox capture",
                    content: "signup follow-up"
                ),
                CommandPaletteContentMatch(
                    source: .knowledge(id: 4),
                    title: "Signup policy",
                    content: "Signups require a verified email."
                )
            ]
        }

        let items = CommandPaletteComposer.contentItems(query: "signup", matches: fakeProvider("signup"))

        XCTAssertEqual(items.map(\.id), ["fts-task-7", "fts-task-8", "fts-knowledge-4"])
        XCTAssertEqual(items[0].kind, .revealTask(id: 7, projectID: 12, title: "Write launch email"))
        XCTAssertEqual(items[1].kind, .revealTask(id: 8, projectID: nil, title: "Inbox capture"))
        XCTAssertEqual(items[2].kind, .openKnowledgeFrame(id: 4, name: "Signup policy"))
        XCTAssertEqual(items[0].subtitle, "Mention the beta signup link.")
    }

    func testContentSnippetSanitizedQueriesNeverThrowThroughComposer() {
        // Quotes and asterisks flow through snippet building untouched; the
        // SQL-level sanitizing is covered by CommandPaletteContentSearchServiceTests.
        let matches = [
            CommandPaletteContentMatch(
                source: .knowledge(id: 1),
                title: "Quoting",
                content: "Use \"smart quotes\" sparingly and avoid asterisks** in prose."
            )
        ]
        let items = CommandPaletteComposer.contentItems(query: "\"smart* quotes\"", matches: matches)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, "fts-knowledge-1")
    }
}
