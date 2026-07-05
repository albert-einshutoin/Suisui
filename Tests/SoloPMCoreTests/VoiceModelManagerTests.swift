import XCTest
@testable import SoloPMCore

final class VoiceModelManagerTests: XCTestCase {
    func testPhase1CatalogDefinesJapaneseEnglishSTTAndTTSCandidatesWithoutBundledBinaries() {
        let catalog = VoiceModelCatalog.phase1Default

        XCTAssertEqual(catalog.validationIssues, [])
        XCTAssertEqual(catalog.modelIDs, [.whisperCppTinyMultilingual, .kokoro82M])

        let sttModel = catalog.model(for: .whisperCppTinyMultilingual)
        XCTAssertEqual(sttModel?.engine, .whisperCpp)
        XCTAssertEqual(sttModel?.purpose, .speechToText)
        XCTAssertEqual(sttModel?.languages.map(\.code), ["ja", "en"])
        XCTAssertEqual(sttModel?.licenseName, "MIT")
        XCTAssertFalse(sttModel?.isBundledInApp ?? true)

        let ttsModel = catalog.model(for: .kokoro82M)
        XCTAssertEqual(ttsModel?.engine, .kokoro)
        XCTAssertEqual(ttsModel?.purpose, .textToSpeech)
        XCTAssertEqual(ttsModel?.languages.map(\.code), ["ja", "en"])
        XCTAssertEqual(ttsModel?.licenseName, "Apache-2.0")
        XCTAssertFalse(ttsModel?.isBundledInApp ?? true)
    }

    func testCatalogValidationRejectsInsecureURLsMissingChecksumsAndUnsafeCacheNames() {
        let invalidModel = VoiceModelDescriptor(
            id: .custom("bad-model"),
            displayName: "Bad model",
            purpose: .speechToText,
            engine: .whisperCpp,
            languages: [VoiceModelLanguage(code: "ja", displayName: "Japanese")],
            sourceURL: URL(string: "http://example.com/bad.bin")!,
            licenseName: "MIT",
            licenseURL: URL(string: "https://example.com/license")!,
            estimatedSizeBytes: 1,
            checksum: VoiceModelChecksum(algorithm: .sha256, value: ""),
            cacheFileName: "../bad.bin",
            isBundledInApp: false
        )

        let issues = VoiceModelCatalog(models: [invalidModel]).validationIssues.map(\.message)

        XCTAssertTrue(issues.contains("Model source URL must use HTTPS."))
        XCTAssertTrue(issues.contains("Model checksum is required."))
        XCTAssertTrue(issues.contains("Model cache file name is unsafe."))
    }

    func testInstallDownloadsVerifiesChecksumAndStoresUnderCacheRoot() async throws {
        let modelData = Data("tiny local model".utf8)
        let model = testModel(
            checksum: VoiceModelChecksum(
                algorithm: .sha256,
                value: VoiceModelChecksum.sha256Hex(for: modelData)
            )
        )
        let cacheRoot = makeTemporaryDirectory()
        let httpClient = RecordingVoiceModelHTTPDataClient(data: modelData, statusCode: 200)
        let manager = VoiceModelManager(cache: VoiceModelCache(rootDirectory: cacheRoot), httpClient: httpClient)

        let install = try await manager.install(model)

        XCTAssertEqual(install.status, .installed)
        XCTAssertEqual(httpClient.requestedURLs, [model.sourceURL])
        XCTAssertEqual(try Data(contentsOf: install.localURL), modelData)
        XCTAssertTrue(install.localURL.path.hasPrefix(cacheRoot.path))
        XCTAssertEqual(manager.status(for: model), .installed)
    }

    func testInstallRemovesPartialFileAndSanitizesChecksumMismatch() async throws {
        let modelData = Data("tampered local model".utf8)
        let model = testModel(
            checksum: VoiceModelChecksum(
                algorithm: .sha256,
                value: String(repeating: "0", count: 64)
            )
        )
        let cacheRoot = makeTemporaryDirectory()
        let manager = VoiceModelManager(
            cache: VoiceModelCache(rootDirectory: cacheRoot),
            httpClient: RecordingVoiceModelHTTPDataClient(data: modelData, statusCode: 200)
        )

        do {
            _ = try await manager.install(model)
            XCTFail("Expected checksum mismatch.")
        } catch let error as VoiceModelManagerError {
            XCTAssertEqual(
                error,
                .checksumMismatch(
                    modelID: model.id.rawValue,
                    expected: String(repeating: "0", count: 64),
                    actual: VoiceModelChecksum.sha256Hex(for: modelData)
                )
            )
            XCTAssertFalse(error.userMessage.contains(cacheRoot.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: VoiceModelCache(rootDirectory: cacheRoot).localURL(for: model).path))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRemoveFromCacheDeletesOnlyTheSelectedModelFile() async throws {
        let firstModel = testModel(id: .custom("first"), cacheFileName: "first.bin")
        let secondModel = testModel(id: .custom("second"), cacheFileName: "second.bin")
        let cacheRoot = makeTemporaryDirectory()
        let cache = VoiceModelCache(rootDirectory: cacheRoot)
        let validModelData = Data("tiny local model".utf8)
        try cache.write(validModelData, for: firstModel)
        try cache.write(validModelData, for: secondModel)
        let manager = VoiceModelManager(cache: cache, httpClient: RecordingVoiceModelHTTPDataClient())

        try manager.removeFromCache(firstModel)

        XCTAssertEqual(manager.status(for: firstModel), .notInstalled)
        XCTAssertEqual(manager.status(for: secondModel), .installed)
    }

    func testStatusMarksCorruptCachedModelAsNeedsReinstall() throws {
        let model = testModel()
        let cacheRoot = makeTemporaryDirectory()
        let cache = VoiceModelCache(rootDirectory: cacheRoot)
        try cache.write(Data("corrupt model".utf8), for: model)
        let manager = VoiceModelManager(cache: cache, httpClient: RecordingVoiceModelHTTPDataClient())

        XCTAssertEqual(manager.status(for: model), .corrupted("Voice model checksum verification failed."))

        let row = VoiceModelReadinessRow(model: model, status: manager.status(for: model))
        XCTAssertEqual(row.statusLabel, "Needs reinstall")
        XCTAssertEqual(row.action, .retry)
    }

    func testStatusInvalidatesCacheWhenExpectedChecksumChanges() throws {
        let modelData = Data("tiny local model".utf8)
        let model = testModel(
            checksum: VoiceModelChecksum(
                algorithm: .sha256,
                value: VoiceModelChecksum.sha256Hex(for: modelData)
            )
        )
        let cacheRoot = makeTemporaryDirectory()
        let cache = VoiceModelCache(rootDirectory: cacheRoot)
        try cache.write(modelData, for: model)
        let manager = VoiceModelManager(cache: cache, httpClient: RecordingVoiceModelHTTPDataClient())

        XCTAssertEqual(manager.status(for: model), .installed)

        let changedExpectedModel = testModel(
            checksum: VoiceModelChecksum(
                algorithm: .sha256,
                value: String(repeating: "0", count: 64)
            )
        )

        XCTAssertEqual(
            manager.status(for: changedExpectedModel),
            .corrupted("Voice model checksum verification failed.")
        )
    }

    func testStatusInvalidatesCacheWhenModelFileContentsChange() throws {
        let model = testModel()
        let originalData = Data("tiny local model".utf8)
        let cacheRoot = makeTemporaryDirectory()
        let cache = VoiceModelCache(rootDirectory: cacheRoot)
        try cache.write(originalData, for: model)
        let manager = VoiceModelManager(cache: cache, httpClient: RecordingVoiceModelHTTPDataClient())

        XCTAssertEqual(manager.status(for: model), .installed)

        try Data("model-version-two-changed".utf8).write(to: cache.localURL(for: model), options: [.atomic])

        XCTAssertEqual(
            manager.status(for: model),
            .corrupted("Voice model checksum verification failed.")
        )
    }

    func testCommitStagedFileKeepsExistingFinalWhenPartialIsMissing() throws {
        let model = testModel()
        let cacheRoot = makeTemporaryDirectory()
        let cache = VoiceModelCache(rootDirectory: cacheRoot)
        let existingData = Data("previous verified model".utf8)
        try cache.write(existingData, for: model)

        XCTAssertThrowsError(try cache.commitStagedFile(for: model))
        XCTAssertEqual(try Data(contentsOf: cache.localURL(for: model)), existingData)
    }

    func testInstallReplacesStalePartialFileDuringRetry() async throws {
        let modelData = Data("tiny local model".utf8)
        let model = testModel()
        let cacheRoot = makeTemporaryDirectory()
        let cache = VoiceModelCache(rootDirectory: cacheRoot)
        try FileManager.default.createDirectory(
            at: cache.partialURL(for: model).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("stale partial".utf8).write(to: cache.partialURL(for: model))
        let manager = VoiceModelManager(
            cache: cache,
            httpClient: RecordingVoiceModelHTTPDataClient(data: modelData, statusCode: 200)
        )

        let install = try await manager.install(model)

        XCTAssertEqual(install.status, .installed)
        XCTAssertEqual(try Data(contentsOf: cache.localURL(for: model)), modelData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.partialURL(for: model).path))
    }

    func testInstallRemovesPartialFileWhenChecksumCannotReadStagedDownload() async throws {
        let model = testModel()
        let cacheRoot = makeTemporaryDirectory()
        let cache = VoiceModelCache(rootDirectory: cacheRoot)
        let downloadedDirectory = cacheRoot.appendingPathComponent("downloaded-directory", isDirectory: true)
        try FileManager.default.createDirectory(at: downloadedDirectory, withIntermediateDirectories: true)
        let manager = VoiceModelManager(
            cache: cache,
            downloadClient: DirectoryVoiceModelDownloadClient(temporaryURL: downloadedDirectory)
        )

        do {
            _ = try await manager.install(model)
            XCTFail("Expected unreadable staged download to fail.")
        } catch let error as VoiceModelManagerError {
            XCTAssertEqual(
                error,
                .verificationFailed("Voice model checksum verification could not read the staged download.")
            )
            XCTAssertFalse(error.userMessage.contains(cacheRoot.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: cache.partialURL(for: model).path))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testSettingsReadinessRowsExposeInstallStateWhileGatingLocalProviderSelection() throws {
        let installedModel = VoiceModelCatalog.phase1Default.model(for: .whisperCppTinyMultilingual)!
        let suiteName = "SoloPM.VoiceModelSettings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: InMemorySecretStore(),
            voiceModelManager: StaticVoiceModelManager(statuses: [
                installedModel.id: .installed,
                .kokoro82M: .notInstalled
            ])
        )

        XCTAssertEqual(viewModel.voiceModelReadinessRows.map(\.modelID), [.whisperCppTinyMultilingual, .kokoro82M])
        XCTAssertEqual(viewModel.voiceModelReadinessRows[0].statusLabel, "Installed")
        XCTAssertEqual(viewModel.voiceModelReadinessRows[1].statusLabel, "Not installed")
        XCTAssertEqual(STTProvider.releaseReadyCases, [.openAITranscribe, .localWhisperCpp])
        XCTAssertEqual(viewModel.selectableSTTProviders, [.openAITranscribe])
        XCTAssertEqual(TTSProvider.releaseReadyCases, [.localKokoro])
        XCTAssertEqual(viewModel.selectableTTSProviders, [.localKokoro])
        XCTAssertEqual(viewModel.ttsProviderReadinessRow.statusLabel, "Model not installed")
    }

    @MainActor
    func testSettingsInstallAndRemoveActionsUpdateVoiceModelReadinessRows() async throws {
        let manager = RecordingVoiceModelManager()
        let suiteName = "SoloPM.VoiceModelSettingsActions.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: InMemorySecretStore(),
            voiceModelManager: manager
        )

        await viewModel.installVoiceModel(.whisperCppTinyMultilingual)

        XCTAssertEqual(manager.installedModelIDs, [.whisperCppTinyMultilingual])
        XCTAssertEqual(viewModel.voiceModelReadinessRows[0].statusLabel, "Installed")
        XCTAssertEqual(viewModel.successMessage, "Voice model is installed.")

        viewModel.removeVoiceModelFromCache(.whisperCppTinyMultilingual)

        XCTAssertEqual(manager.removedModelIDs, [.whisperCppTinyMultilingual])
        XCTAssertEqual(viewModel.voiceModelReadinessRows[0].statusLabel, "Not installed")
        XCTAssertEqual(viewModel.successMessage, "Voice model cache entry was removed.")
    }

    @MainActor
    func testSettingsShowsCorruptCachedModelAsNeedsReinstall() throws {
        let model = testModel(id: .custom("settings-corrupt-model"), cacheFileName: "settings-corrupt-model.bin")
        let cacheRoot = makeTemporaryDirectory()
        let cache = VoiceModelCache(rootDirectory: cacheRoot)
        try cache.write(Data("corrupt settings model".utf8), for: model)
        let suiteName = "SoloPM.VoiceModelSettingsCorrupt.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let viewModel = AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(defaults: defaults),
            secretStore: InMemorySecretStore(),
            voiceModelCatalog: VoiceModelCatalog(models: [model]),
            voiceModelManager: VoiceModelManager(cache: cache, httpClient: RecordingVoiceModelHTTPDataClient())
        )

        XCTAssertEqual(viewModel.voiceModelReadinessRows[0].statusLabel, "Needs reinstall")
        XCTAssertEqual(viewModel.voiceModelReadinessRows[0].action, .retry)
    }



    private func testModel(
        id: VoiceModelID = .custom("test-model"),
        checksum: VoiceModelChecksum = VoiceModelChecksum(
            algorithm: .sha256,
            value: VoiceModelChecksum.sha256Hex(for: Data("tiny local model".utf8))
        ),
        cacheFileName: String = "test-model.bin"
    ) -> VoiceModelDescriptor {
        VoiceModelDescriptor(
            id: id,
            displayName: "Test model",
            purpose: .speechToText,
            engine: .whisperCpp,
            languages: [VoiceModelLanguage(code: "en", displayName: "English")],
            sourceURL: URL(string: "https://models.example.com/test-model.bin")!,
            licenseName: "MIT",
            licenseURL: URL(string: "https://models.example.com/license")!,
            estimatedSizeBytes: 16,
            checksum: checksum,
            cacheFileName: cacheFileName,
            isBundledInApp: false
        )
    }

    private func makeTemporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("solopm-voice-model-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}

private final class RecordingVoiceModelHTTPDataClient: HTTPDataClient, @unchecked Sendable {
    private let data: Data
    private let statusCode: Int
    private let lock = NSLock()
    private var urls: [URL] = []

    init(data: Data = Data(), statusCode: Int = 200) {
        self.data = data
        self.statusCode = statusCode
    }

    var requestedURLs: [URL] {
        lock.withLock { urls }
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock {
            if let url = request.url {
                urls.append(url)
            }
        }
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://models.example.com")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

private struct StaticVoiceModelManager: VoiceModelManaging {
    var statuses: [VoiceModelID: VoiceModelInstallStatus]

    func status(for model: VoiceModelDescriptor) -> VoiceModelInstallStatus {
        statuses[model.id] ?? .notInstalled
    }

    func install(_ model: VoiceModelDescriptor) async throws -> VoiceModelInstall {
        VoiceModelInstall(modelID: model.id, status: status(for: model), localURL: URL(filePath: "/tmp/\(model.cacheFileName)"))
    }

    func removeFromCache(_ model: VoiceModelDescriptor) throws {}
}

private struct DirectoryVoiceModelDownloadClient: VoiceModelDownloadClient {
    var temporaryURL: URL

    func download(_ model: VoiceModelDescriptor) async throws -> VoiceModelDownloadedFile {
        VoiceModelDownloadedFile(
            temporaryURL: temporaryURL,
            response: HTTPURLResponse(
                url: model.sourceURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }
}

private final class RecordingVoiceModelManager: VoiceModelManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [VoiceModelID: VoiceModelInstallStatus] = [:]
    private var installedIDs: [VoiceModelID] = []
    private var removedIDs: [VoiceModelID] = []

    var installedModelIDs: [VoiceModelID] {
        lock.withLock { installedIDs }
    }

    var removedModelIDs: [VoiceModelID] {
        lock.withLock { removedIDs }
    }

    func status(for model: VoiceModelDescriptor) -> VoiceModelInstallStatus {
        lock.withLock { statuses[model.id] ?? .notInstalled }
    }

    func install(_ model: VoiceModelDescriptor) async throws -> VoiceModelInstall {
        lock.withLock {
            statuses[model.id] = .installed
            installedIDs.append(model.id)
        }
        return VoiceModelInstall(modelID: model.id, status: .installed, localURL: URL(filePath: "/tmp/\(model.cacheFileName)"))
    }

    func removeFromCache(_ model: VoiceModelDescriptor) throws {
        lock.withLock {
            statuses[model.id] = .notInstalled
            removedIDs.append(model.id)
        }
    }
}
