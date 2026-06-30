import XCTest
@testable import SoloPMCore

final class InboxVoiceTriageCommandTests: XCTestCase {
    func testParserRecognizesMinimalJapaneseAndEnglishCommands() {
        let parser = InboxVoiceTriageCommandParser()

        XCTAssertEqual(parser.parse("次")?.action, .selectNext)
        XCTAssertEqual(parser.parse("today")?.action, .scheduleToday)
        XCTAssertEqual(parser.parse("後で")?.action, .reviewLater)
        XCTAssertEqual(parser.parse("done")?.action, .complete)
        XCTAssertEqual(parser.parse("取り消し")?.action, .undo)
        XCTAssertEqual(parser.parse("優先度 高")?.action, .setPriority(.high))
        XCTAssertEqual(parser.parse("medium priority")?.action, .setPriority(.medium))
        XCTAssertEqual(parser.parse("低")?.action, .setPriority(.low))
    }

    func testVoiceCommandParserRequiresExplicitInboxContext() {
        let parser = InboxVoiceTriageCommandParser()

        XCTAssertEqual(parser.parseVoiceCommand("inbox today")?.action, .scheduleToday)
        XCTAssertEqual(parser.parseVoiceCommand("Inbox: done")?.action, .complete)
        XCTAssertEqual(parser.parseVoiceCommand("インボックス 優先度 高")?.action, .setPriority(.high))
        XCTAssertEqual(parser.parseVoiceCommand("仕分け 次")?.action, .selectNext)
        XCTAssertNil(parser.parseVoiceCommand("today"))
        XCTAssertNil(parser.parseVoiceCommand("完了"))
    }

    func testParserFailsClosedForFreeFormOrExternalCommands() {
        let parser = InboxVoiceTriageCommandParser()

        XCTAssertNil(parser.parse(""))
        XCTAssertNil(parser.parse("今日やることを確認して"))
        XCTAssertNil(parser.parse("Slack に送って"))
        XCTAssertNil(parser.parse("delete this task"))
        XCTAssertNil(parser.parse("いい感じにして"))
    }
}
