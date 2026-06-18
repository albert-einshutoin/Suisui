import XCTest
@testable import SoloPMCore

#if canImport(Security)
import Security
#endif

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

#if canImport(Security)
    func testKeychainSecretStoreSaveUpdatesExistingItemBeforeAddingNewItem() throws {
        let client = RecordingKeychainClient(updateStatuses: [errSecSuccess])
        let store = KeychainSecretStore(service: "test.solopm", keychain: client)

        try store.save("replacement", for: .openAIAPIKey)

        XCTAssertEqual(client.operations, [.update])
        XCTAssertEqual(client.updatedValue, "replacement")
        XCTAssertNil(client.addedValue)
    }

    func testKeychainSecretStoreSaveAddsOnlyWhenUpdateReportsMissingItem() throws {
        let client = RecordingKeychainClient(updateStatuses: [errSecItemNotFound], addStatuses: [errSecSuccess])
        let store = KeychainSecretStore(service: "test.solopm", keychain: client)

        try store.save("first", for: .openRouterAPIKey)

        XCTAssertEqual(client.operations, [.update, .add])
        XCTAssertEqual(client.updatedValue, "first")
        XCTAssertEqual(client.addedValue, "first")
    }

    func testKeychainSecretStoreSaveDoesNotAddOrDeleteAfterUpdateFailure() throws {
        let client = RecordingKeychainClient(updateStatuses: [-25291])
        let store = KeychainSecretStore(service: "test.solopm", keychain: client)

        XCTAssertThrowsError(try store.save("replacement", for: .openAIAPIKey)) { error in
            XCTAssertEqual(error as? SecretStoreError, .unexpectedStatus(-25291))
        }
        XCTAssertEqual(client.operations, [.update])
    }
#endif
}

#if canImport(Security)
private final class RecordingKeychainClient: KeychainSecItemClient {
    enum Operation: Equatable {
        case add
        case update
        case copyMatching
        case delete
    }

    private var updateStatuses: [OSStatus]
    private var addStatuses: [OSStatus]
    private var copyMatchingStatuses: [OSStatus]
    private var deleteStatuses: [OSStatus]

    private(set) var operations: [Operation] = []
    private(set) var addedValue: String?
    private(set) var updatedValue: String?

    init(
        updateStatuses: [OSStatus] = [],
        addStatuses: [OSStatus] = [],
        copyMatchingStatuses: [OSStatus] = [],
        deleteStatuses: [OSStatus] = []
    ) {
        self.updateStatuses = updateStatuses
        self.addStatuses = addStatuses
        self.copyMatchingStatuses = copyMatchingStatuses
        self.deleteStatuses = deleteStatuses
    }

    func add(_ query: CFDictionary) -> OSStatus {
        operations.append(.add)
        addedValue = stringValue(in: query)
        return addStatuses.isEmpty ? errSecSuccess : addStatuses.removeFirst()
    }

    func update(_ query: CFDictionary, _ attributes: CFDictionary) -> OSStatus {
        operations.append(.update)
        updatedValue = stringValue(in: attributes)
        return updateStatuses.isEmpty ? errSecSuccess : updateStatuses.removeFirst()
    }

    func copyMatching(_ query: CFDictionary, _ item: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        operations.append(.copyMatching)
        return copyMatchingStatuses.isEmpty ? errSecItemNotFound : copyMatchingStatuses.removeFirst()
    }

    func delete(_ query: CFDictionary) -> OSStatus {
        operations.append(.delete)
        return deleteStatuses.isEmpty ? errSecSuccess : deleteStatuses.removeFirst()
    }

    private func stringValue(in dictionary: CFDictionary) -> String? {
        guard let data = (dictionary as NSDictionary)[kSecValueData as String] as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
#endif
