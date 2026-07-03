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

    func testKeychainSecretStoreCachesSuccessfulReadForCurrentProcess() throws {
        let client = RecordingKeychainClient(
            copyMatchingStatuses: [errSecSuccess],
            copyMatchingValues: ["gemini-live-secret"]
        )
        let store = KeychainSecretStore(service: "test.solopm", keychain: client)

        XCTAssertEqual(try store.read(.geminiAPIKey), "gemini-live-secret")
        XCTAssertEqual(try store.read(.geminiAPIKey), "gemini-live-secret")

        XCTAssertEqual(client.operations, [.copyMatching])
    }

    func testKeychainSecretStoreSaveEvictsProcessCacheSoNextReadVerifiesKeychain() throws {
        let client = RecordingKeychainClient(
            updateStatuses: [errSecSuccess],
            copyMatchingStatuses: [errSecSuccess, errSecSuccess],
            copyMatchingValues: ["old-secret", "replacement-secret"]
        )
        let store = KeychainSecretStore(service: "test.solopm", keychain: client)

        XCTAssertEqual(try store.read(.openAIAPIKey), "old-secret")
        try store.save("replacement-secret", for: .openAIAPIKey)

        XCTAssertEqual(try store.read(.openAIAPIKey), "replacement-secret")
        XCTAssertEqual(client.operations, [.copyMatching, .update, .copyMatching])
    }

    func testKeychainSecretStoreSaveDoesNotMaskFollowingKeychainReadFailure() throws {
        let client = RecordingKeychainClient(
            updateStatuses: [errSecSuccess],
            copyMatchingStatuses: [-25308]
        )
        let store = KeychainSecretStore(service: "test.solopm", keychain: client)

        try store.save("replacement-secret", for: .openAIAPIKey)

        XCTAssertThrowsError(try store.read(.openAIAPIKey)) { error in
            XCTAssertEqual(error as? SecretStoreError, .unexpectedStatus(-25308))
        }
        XCTAssertEqual(client.operations, [.update, .copyMatching])
    }

    func testKeychainSecretStoreDeleteClearsProcessCache() throws {
        let client = RecordingKeychainClient(
            copyMatchingStatuses: [errSecSuccess, errSecItemNotFound],
            copyMatchingValues: ["old-secret", nil],
            deleteStatuses: [errSecSuccess]
        )
        let store = KeychainSecretStore(service: "test.solopm", keychain: client)

        XCTAssertEqual(try store.read(.openRouterAPIKey), "old-secret")
        try store.delete(.openRouterAPIKey)
        XCTAssertNil(try store.read(.openRouterAPIKey))

        XCTAssertEqual(client.operations, [.copyMatching, .delete, .copyMatching])
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
    private var copyMatchingValues: [String?]
    private var deleteStatuses: [OSStatus]

    private(set) var operations: [Operation] = []
    private(set) var addedValue: String?
    private(set) var updatedValue: String?

    init(
        updateStatuses: [OSStatus] = [],
        addStatuses: [OSStatus] = [],
        copyMatchingStatuses: [OSStatus] = [],
        copyMatchingValues: [String?] = [],
        deleteStatuses: [OSStatus] = []
    ) {
        self.updateStatuses = updateStatuses
        self.addStatuses = addStatuses
        self.copyMatchingStatuses = copyMatchingStatuses
        self.copyMatchingValues = copyMatchingValues
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
        let status = copyMatchingStatuses.isEmpty ? errSecItemNotFound : copyMatchingStatuses.removeFirst()
        let value = copyMatchingValues.isEmpty ? nil : copyMatchingValues.removeFirst()
        if status == errSecSuccess {
            if let value, let data = value.data(using: .utf8) {
                item?.pointee = data as NSData
            }
        }
        return status
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
