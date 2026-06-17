import XCTest
@testable import SoloPMCore

final class SecretStoreTests: XCTestCase {
    func testInMemorySecretStoreSavesReplacesAndDeletesValues() throws {
        let store = InMemorySecretStore()
        let key = SecretKey.openAIAPIKey

        XCTAssertNil(try store.read(key))

        try store.save("first", for: key)
        XCTAssertEqual(try store.read(key), "first")

        try store.save("second", for: key)
        XCTAssertEqual(try store.read(key), "second")

        try store.delete(key)
        XCTAssertNil(try store.read(key))
    }
}

