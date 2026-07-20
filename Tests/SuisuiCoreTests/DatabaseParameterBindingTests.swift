import XCTest
@testable import SuisuiCore

final class DatabaseParameterBindingTests: XCTestCase {
    private func makeConnection() throws -> SQLiteConnection {
        let connection = try SQLiteConnection(path: ":memory:")
        try connection.execute(
            """
            CREATE TABLE bound_rows (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                note TEXT,
                score REAL,
                payload BLOB
            );
            """
        )
        return connection
    }

    func testExecuteBindsAllValueKindsAndReadsThemBack() throws {
        let connection = try makeConnection()
        try connection.execute(
            "INSERT INTO bound_rows (title, note, score, payload) VALUES (?, ?, ?, ?);",
            parameters: [
                .text("Launch"),
                .null,
                .real(0.75),
                .blob(Data([0x73, 0x61, 0x66, 0x65]))
            ]
        )

        let rows = try connection.query("SELECT title, note, score, payload FROM bound_rows;") { row in
            (
                title: try row.string("title"),
                note: try row.optionalString("note"),
                payload: try row.data("payload")
            )
        }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].title, "Launch")
        XCTAssertNil(rows[0].note)
        XCTAssertEqual(rows[0].payload, Data([0x73, 0x61, 0x66, 0x65]))
    }

    func testBoundTextTreatsInjectionAttemptsAsLiteralValues() throws {
        let connection = try makeConnection()
        let hostileTitle = "task'); DROP TABLE bound_rows; --"
        let hostileNote = "Robert'); DELETE FROM bound_rows WHERE ('1'='1"

        try connection.execute(
            "INSERT INTO bound_rows (title, note) VALUES (?, ?);",
            parameters: [.text(hostileTitle), .text(hostileNote)]
        )

        XCTAssertTrue(try connection.tableExists("bound_rows"))
        let matches = try connection.queryStrings(
            "SELECT note FROM bound_rows WHERE title = ?;",
            parameters: [.text(hostileTitle)]
        )
        XCTAssertEqual(matches, [hostileNote])
    }

    func testTableExistsBindsHostileTableNames() throws {
        let connection = try makeConnection()
        XCTAssertFalse(try connection.tableExists("bound_rows' OR '1'='1"))
        XCTAssertTrue(try connection.tableExists("bound_rows"))
    }

    func testEmptyBlobRoundTripsAsEmptyDataNotNull() throws {
        let connection = try makeConnection()
        try connection.execute(
            "INSERT INTO bound_rows (title, payload) VALUES (?, ?);",
            parameters: [.text("empty"), .blob(Data())]
        )

        let payloads = try connection.query("SELECT payload FROM bound_rows;") { row in
            try row.optionalData("payload")
        }
        XCTAssertEqual(payloads, [Data()])
    }

    func testMismatchedParameterCountThrowsPrepareFailed() throws {
        let connection = try makeConnection()
        XCTAssertThrowsError(
            try connection.execute(
                "INSERT INTO bound_rows (title, note) VALUES (?, ?);",
                parameters: [.text("only one")]
            )
        ) { error in
            guard case let DatabaseError.prepareFailed(message) = error else {
                XCTFail("Expected DatabaseError.prepareFailed, got \(error).")
                return
            }
            XCTAssertTrue(message.contains("2"))
            XCTAssertTrue(message.contains("1"))
        }
    }

    func testOptionalConvenienceInitializersMapNilToNull() {
        XCTAssertEqual(SQLiteValue(String?.none), .null)
        XCTAssertEqual(SQLiteValue(Int64?.none), .null)
        XCTAssertEqual(SQLiteValue(Double?.none), .null)
        XCTAssertEqual(SQLiteValue(Data?.none), .null)
        XCTAssertEqual(SQLiteValue(Bool?.none), .null)
        XCTAssertEqual(SQLiteValue("note"), .text("note"))
        XCTAssertEqual(SQLiteValue(Int64(7)), .integer(7))
        XCTAssertEqual(SQLiteValue(3), .integer(3))
        XCTAssertEqual(SQLiteValue(true), .integer(1))
    }

    func testQueryStringsSupportsBoundLimit() throws {
        let connection = try makeConnection()
        for index in 1...5 {
            try connection.execute(
                "INSERT INTO bound_rows (title) VALUES (?);",
                parameters: [.text("task-\(index)")]
            )
        }

        let titles = try connection.queryStrings(
            "SELECT title FROM bound_rows ORDER BY id DESC LIMIT ?;",
            parameters: [.integer(2)]
        )
        XCTAssertEqual(titles, ["task-5", "task-4"])
    }
}
