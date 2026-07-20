import CryptoKit
import Foundation

public enum VoiceModelID: Hashable, Sendable {
    case whisperCppTinyMultilingual
    case kokoro82M
    case custom(String)

    public var rawValue: String {
        switch self {
        case .whisperCppTinyMultilingual:
            "whisper-cpp-tiny-multilingual"
        case .kokoro82M:
            "kokoro-82m"
        case .custom(let value):
            value
        }
    }
}

public enum VoiceModelPurpose: String, Equatable, Sendable {
    case speechToText
    case textToSpeech
}

public enum VoiceModelEngine: String, Equatable, Sendable {
    case whisperCpp = "whisper.cpp"
    case whisperKit = "WhisperKit"
    case sherpaOnnx = "sherpa-onnx"
    case kokoro = "Kokoro"
}

public struct VoiceModelLanguage: Equatable, Sendable {
    public var code: String
    public var displayName: String

    public init(code: String, displayName: String) {
        self.code = code
        self.displayName = displayName
    }
}

public struct VoiceModelChecksum: Equatable, Sendable {
    public enum Algorithm: String, Equatable, Sendable {
        case sha1
        case sha256
    }

    public var algorithm: Algorithm
    public var value: String

    public init(algorithm: Algorithm, value: String) {
        self.algorithm = algorithm
        self.value = value.lowercased()
    }

    public func hexDigest(for data: Data) -> String {
        switch algorithm {
        case .sha1:
            Insecure.SHA1.hash(data: data).hexString
        case .sha256:
            SHA256.hash(data: data).hexString
        }
    }

    public func hexDigest(forFileAt url: URL) throws -> String {
        switch algorithm {
        case .sha1:
            try Insecure.SHA1.hashFile(at: url).hexString
        case .sha256:
            try SHA256.hashFile(at: url).hexString
        }
    }

    public static func sha256Hex(for data: Data) -> String {
        SHA256.hash(data: data).hexString
    }
}

public struct VoiceModelDescriptor: Equatable, Sendable {
    public var id: VoiceModelID
    public var displayName: String
    public var purpose: VoiceModelPurpose
    public var engine: VoiceModelEngine
    public var languages: [VoiceModelLanguage]
    public var sourceURL: URL
    public var licenseName: String
    public var licenseURL: URL
    public var estimatedSizeBytes: Int64
    public var checksum: VoiceModelChecksum
    public var cacheFileName: String
    public var isBundledInApp: Bool

    public init(
        id: VoiceModelID,
        displayName: String,
        purpose: VoiceModelPurpose,
        engine: VoiceModelEngine,
        languages: [VoiceModelLanguage],
        sourceURL: URL,
        licenseName: String,
        licenseURL: URL,
        estimatedSizeBytes: Int64,
        checksum: VoiceModelChecksum,
        cacheFileName: String,
        isBundledInApp: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.purpose = purpose
        self.engine = engine
        self.languages = languages
        self.sourceURL = sourceURL
        self.licenseName = licenseName
        self.licenseURL = licenseURL
        self.estimatedSizeBytes = estimatedSizeBytes
        self.checksum = checksum
        self.cacheFileName = cacheFileName
        self.isBundledInApp = isBundledInApp
    }
}

public struct VoiceModelCatalog: Equatable, Sendable {
    public var models: [VoiceModelDescriptor]

    public init(models: [VoiceModelDescriptor]) {
        self.models = models
    }

    public var modelIDs: [VoiceModelID] {
        models.map(\.id)
    }

    public var validationIssues: [ValidationIssue] {
        models.flatMap(Self.validationIssues(for:))
    }

    public func model(for id: VoiceModelID) -> VoiceModelDescriptor? {
        models.first { $0.id == id }
    }

    public func readinessRows(using manager: any VoiceModelManaging) -> [VoiceModelReadinessRow] {
        models.map { model in
            VoiceModelReadinessRow(model: model, status: manager.status(for: model))
        }
    }

    private static func validationIssues(for model: VoiceModelDescriptor) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if model.sourceURL.scheme?.lowercased() != "https" || model.sourceURL.host?.isEmpty != false {
            issues.append(ValidationIssue(field: model.id.rawValue, message: "Model source URL must use HTTPS.", severity: .error))
        }
        if model.checksum.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(ValidationIssue(field: model.id.rawValue, message: "Model checksum is required.", severity: .error))
        }
        if !VoiceModelCache.isSafeCacheFileName(model.cacheFileName) {
            issues.append(ValidationIssue(field: model.id.rawValue, message: "Model cache file name is unsafe.", severity: .error))
        }
        if model.languages.isEmpty || model.languages.contains(where: { $0.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            issues.append(ValidationIssue(field: model.id.rawValue, message: "Model language metadata is required.", severity: .error))
        }
        return issues
    }
}

public extension VoiceModelCatalog {
    static let phase1Default = VoiceModelCatalog(
        models: [
            VoiceModelDescriptor(
                id: .whisperCppTinyMultilingual,
                displayName: "whisper.cpp tiny multilingual",
                purpose: .speechToText,
                engine: .whisperCpp,
                languages: [
                    VoiceModelLanguage(code: "ja", displayName: "Japanese"),
                    VoiceModelLanguage(code: "en", displayName: "English")
                ],
                sourceURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin")!,
                licenseName: "MIT",
                licenseURL: URL(string: "https://github.com/openai/whisper/blob/main/LICENSE")!,
                estimatedSizeBytes: 77_691_713,
                checksum: VoiceModelChecksum(
                    algorithm: .sha256,
                    value: "be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21"
                ),
                cacheFileName: "ggml-tiny.bin",
                isBundledInApp: false
            ),
            VoiceModelDescriptor(
                id: .kokoro82M,
                displayName: "Kokoro 82M",
                purpose: .textToSpeech,
                engine: .kokoro,
                languages: [
                    VoiceModelLanguage(code: "ja", displayName: "Japanese"),
                    VoiceModelLanguage(code: "en", displayName: "English")
                ],
                sourceURL: URL(string: "https://huggingface.co/hexgrad/Kokoro-82M/resolve/main/kokoro-v1_0.pth")!,
                licenseName: "Apache-2.0",
                licenseURL: URL(string: "https://huggingface.co/hexgrad/Kokoro-82M")!,
                estimatedSizeBytes: 327_212_226,
                checksum: VoiceModelChecksum(
                    algorithm: .sha256,
                    value: "496dba118d1a58f5f3db2efc88dbdc216e0483fc89fe6e47ee1f2c53f18ad1e4"
                ),
                cacheFileName: "kokoro-v1_0.pth",
                isBundledInApp: false
            )
        ]
    )
}

public enum VoiceModelInstallStatus: Equatable, Sendable {
    case notInstalled
    case downloading
    case installed
    case failed(String)
    case corrupted(String)
}

public struct VoiceModelInstall: Equatable, Sendable {
    public var modelID: VoiceModelID
    public var status: VoiceModelInstallStatus
    public var localURL: URL

    public init(modelID: VoiceModelID, status: VoiceModelInstallStatus, localURL: URL) {
        self.modelID = modelID
        self.status = status
        self.localURL = localURL
    }
}

public enum VoiceModelManagerError: Error, Equatable, Sendable {
    case invalidModelMetadata(String)
    case downloadFailed(String)
    case verificationFailed(String)
    case checksumMismatch(modelID: String, expected: String, actual: String)
    case cacheWriteFailed(String)

    public var userMessage: String {
        switch self {
        case .invalidModelMetadata(let message):
            message
        case .downloadFailed(let message):
            message
        case .verificationFailed(let message):
            message
        case .checksumMismatch:
            "Voice model checksum verification failed. Remove the cache and try downloading the model again."
        case .cacheWriteFailed(let message):
            message
        }
    }
}

public struct VoiceModelCache: Sendable {
    public var rootDirectory: URL

    public init(rootDirectory: URL = Self.defaultRootDirectory()) {
        self.rootDirectory = rootDirectory
    }

    public func localURL(for model: VoiceModelDescriptor) -> URL {
        rootDirectory
            .appendingPathComponent(model.engine.rawValue, isDirectory: true)
            .appendingPathComponent(model.cacheFileName, isDirectory: false)
    }

    public func partialURL(for model: VoiceModelDescriptor) -> URL {
        localURL(for: model)
            .deletingLastPathComponent()
            .appendingPathComponent("\(model.cacheFileName).partial", isDirectory: false)
    }

    public func contains(_ model: VoiceModelDescriptor) -> Bool {
        FileManager.default.fileExists(atPath: localURL(for: model).path)
    }

    public func write(_ data: Data, for model: VoiceModelDescriptor) throws {
        let url = localURL(for: model)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
        } catch {
            throw VoiceModelManagerError.cacheWriteFailed("Voice model could not be written to the local cache.")
        }
    }

    public func stageDownloadedFile(at temporaryURL: URL, for model: VoiceModelDescriptor) throws -> URL {
        let partialURL = partialURL(for: model)
        do {
            try FileManager.default.createDirectory(at: partialURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: partialURL)
            try FileManager.default.moveItem(at: temporaryURL, to: partialURL)
            return partialURL
        } catch {
            throw VoiceModelManagerError.cacheWriteFailed("Voice model could not be staged in the local cache.")
        }
    }

    public func commitStagedFile(for model: VoiceModelDescriptor) throws -> URL {
        let partialURL = partialURL(for: model)
        let finalURL = localURL(for: model)
        guard FileManager.default.fileExists(atPath: partialURL.path) else {
            throw VoiceModelManagerError.cacheWriteFailed("Voice model staged file was missing.")
        }
        do {
            if FileManager.default.fileExists(atPath: finalURL.path) {
                let resultingURL = try FileManager.default.replaceItemAt(
                    finalURL,
                    withItemAt: partialURL,
                    backupItemName: nil,
                    options: []
                )
                return resultingURL ?? finalURL
            }

            try FileManager.default.moveItem(at: partialURL, to: finalURL)
            return finalURL
        } catch {
            try? FileManager.default.removeItem(at: partialURL)
            throw VoiceModelManagerError.cacheWriteFailed("Voice model could not be installed in the local cache.")
        }
    }

    public func removePartial(_ model: VoiceModelDescriptor) {
        try? FileManager.default.removeItem(at: partialURL(for: model))
    }

    public func remove(_ model: VoiceModelDescriptor) throws {
        let url = localURL(for: model)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw VoiceModelManagerError.cacheWriteFailed("Voice model cache entry could not be removed.")
        }
    }

    public static func isSafeCacheFileName(_ fileName: String) -> Bool {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }
        guard trimmed == URL(fileURLWithPath: trimmed).lastPathComponent else {
            return false
        }
        return !trimmed.contains("..")
    }

    public static func defaultRootDirectory() -> URL {
        let base = (try? SuisuiAppDatabaseLocation.applicationSupportDirectoryURL(createDirectory: false))
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
                .appendingPathComponent("Suisui", isDirectory: true)
        return base
            .appendingPathComponent("VoiceModels", isDirectory: true)
    }
}

public protocol VoiceModelManaging: Sendable {
    func status(for model: VoiceModelDescriptor) -> VoiceModelInstallStatus
    func install(_ model: VoiceModelDescriptor) async throws -> VoiceModelInstall
    func removeFromCache(_ model: VoiceModelDescriptor) throws
}

public struct VoiceModelDownloadedFile: Sendable {
    public var temporaryURL: URL
    public var response: HTTPURLResponse

    public init(temporaryURL: URL, response: HTTPURLResponse) {
        self.temporaryURL = temporaryURL
        self.response = response
    }
}

public protocol VoiceModelDownloadClient: Sendable {
    func download(_ model: VoiceModelDescriptor) async throws -> VoiceModelDownloadedFile
}

public struct URLSessionVoiceModelDownloadClient: VoiceModelDownloadClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func download(_ model: VoiceModelDescriptor) async throws -> VoiceModelDownloadedFile {
        var request = URLRequest(url: model.sourceURL)
        request.httpMethod = "GET"
        let (url, response) = try await session.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VoiceModelManagerError.downloadFailed("Voice model download did not return an HTTP response.")
        }
        return VoiceModelDownloadedFile(temporaryURL: url, response: httpResponse)
    }
}

public struct HTTPDataVoiceModelDownloadClient: VoiceModelDownloadClient {
    private let httpClient: any HTTPDataClient

    public init(httpClient: any HTTPDataClient) {
        self.httpClient = httpClient
    }

    public func download(_ model: VoiceModelDescriptor) async throws -> VoiceModelDownloadedFile {
        var request = URLRequest(url: model.sourceURL)
        request.httpMethod = "GET"
        let (data, response) = try await httpClient.data(for: request)
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-voice-model-\(UUID().uuidString).download")
        try data.write(to: temporaryURL, options: [.atomic])
        return VoiceModelDownloadedFile(temporaryURL: temporaryURL, response: response)
    }
}

public struct VoiceModelManager: VoiceModelManaging {
    private let cache: VoiceModelCache
    private let downloadClient: any VoiceModelDownloadClient
    /// Cache status results by model metadata + expected checksum to avoid re-reading
    /// large model files on every readiness check.
    private let readinessCache: VoiceModelReadinessCache

    public init(cache: VoiceModelCache = VoiceModelCache(), downloadClient: any VoiceModelDownloadClient = URLSessionVoiceModelDownloadClient()) {
        self.cache = cache
        self.downloadClient = downloadClient
        self.readinessCache = VoiceModelReadinessCache()
    }

    public init(cache: VoiceModelCache = VoiceModelCache(), httpClient: any HTTPDataClient) {
        self.init(cache: cache, downloadClient: HTTPDataVoiceModelDownloadClient(httpClient: httpClient))
    }

    public func status(for model: VoiceModelDescriptor) -> VoiceModelInstallStatus {
        verifiedStatus(for: model)
    }

    public func verifiedStatus(for model: VoiceModelDescriptor) -> VoiceModelInstallStatus {
        let url = cache.localURL(for: model)
        guard FileManager.default.fileExists(atPath: url.path) else {
            readinessCache.remove(for: model)
            return .notInstalled
        }
        guard let localMetadata = modelFileMetadata(at: url) else {
            readinessCache.remove(for: model)
            return .corrupted("Voice model cache entry could not be read.")
        }

        if let cached = readinessCache.cachedStatus(for: model, checksum: model.checksum.value),
           cached.metadata == localMetadata {
            return cached.status
        }

        let digest = try? model.checksum.hexDigest(forFileAt: url)
        let computedStatus: VoiceModelInstallStatus
        if let digest {
            computedStatus = digest == model.checksum.value ? .installed : .corrupted("Voice model checksum verification failed.")
        } else {
            computedStatus = .corrupted("Voice model cache entry could not be read.")
        }
        readinessCache.storeStatus(computedStatus, for: model, checksum: model.checksum.value, metadata: localMetadata)
        return computedStatus
    }

    public func install(_ model: VoiceModelDescriptor) async throws -> VoiceModelInstall {
        try validate(model)
        readinessCache.remove(for: model)

        let downloadedFile: VoiceModelDownloadedFile
        do {
            downloadedFile = try await downloadClient.download(model)
        } catch {
            throw VoiceModelManagerError.downloadFailed(ProviderErrorMessageSanitizer.message(from: error))
        }

        guard (200..<300).contains(downloadedFile.response.statusCode) else {
            try? FileManager.default.removeItem(at: downloadedFile.temporaryURL)
            throw VoiceModelManagerError.downloadFailed("Voice model download failed with HTTP \(downloadedFile.response.statusCode).")
        }

        // A model should only look installed after checksum verification; staging
        // avoids treating interrupted downloads as usable local voice providers.
        let partialURL = try cache.stageDownloadedFile(at: downloadedFile.temporaryURL, for: model)
        readinessCache.remove(for: model)
        let actualChecksum: String
        do {
            actualChecksum = try model.checksum.hexDigest(forFileAt: partialURL)
        } catch {
            cache.removePartial(model)
            readinessCache.remove(for: model)
            throw VoiceModelManagerError.verificationFailed("Voice model checksum verification could not read the staged download.")
        }
        guard actualChecksum == model.checksum.value else {
            cache.removePartial(model)
            readinessCache.remove(for: model)
            throw VoiceModelManagerError.checksumMismatch(
                modelID: model.id.rawValue,
                expected: model.checksum.value,
                actual: actualChecksum
            )
        }

        let localURL = try cache.commitStagedFile(for: model)
        if let localMetadata = modelFileMetadata(at: localURL) {
            readinessCache.storeStatus(.installed, for: model, checksum: model.checksum.value, metadata: localMetadata)
        } else {
            readinessCache.remove(for: model)
        }
        return VoiceModelInstall(modelID: model.id, status: .installed, localURL: localURL)
    }

    public func removeFromCache(_ model: VoiceModelDescriptor) throws {
        readinessCache.remove(for: model)
        try cache.remove(model)
        cache.removePartial(model)
    }

    private func validate(_ model: VoiceModelDescriptor) throws {
        let issues = VoiceModelCatalog(models: [model]).validationIssues
        guard issues.isEmpty else {
            throw VoiceModelManagerError.invalidModelMetadata(
                issues.map(\.message).joined(separator: " ")
            )
        }
    }

    private func modelFileMetadata(at url: URL) -> VoiceModelFileMetadata? {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            guard let fileSize = values.fileSize else {
                return nil
            }

            return VoiceModelFileMetadata(
                filePath: url.path,
                fileSize: Int64(fileSize),
                modifiedAt: values.contentModificationDate
            )
        } catch {
            return nil
        }
    }
}

public struct VoiceModelReadinessRow: Identifiable, Equatable, Sendable {
    public var modelID: VoiceModelID
    public var displayName: String
    public var engineLabel: String
    public var languageSummary: String
    public var sizeLabel: String
    public var statusLabel: String
    public var detailLabel: String
    public var actionLabel: String
    public var action: VoiceModelReadinessAction
    public var sourceHost: String
    public var licenseName: String

    public var id: VoiceModelID { modelID }

    public init(model: VoiceModelDescriptor, status: VoiceModelInstallStatus) {
        self.modelID = model.id
        self.displayName = model.displayName
        self.engineLabel = model.engine.rawValue
        self.languageSummary = model.languages.map(\.displayName).joined(separator: " / ")
        self.sizeLabel = ByteCountFormatter.string(fromByteCount: model.estimatedSizeBytes, countStyle: .file)
        self.statusLabel = status.statusLabel
        self.detailLabel = "\(model.engine.rawValue) - \(model.licenseName) - \(model.sourceURL.host ?? "unknown source")"
        self.action = status.action
        self.actionLabel = status.actionLabel
        self.sourceHost = model.sourceURL.host ?? ""
        self.licenseName = model.licenseName
    }
}

public enum VoiceModelReadinessAction: Equatable, Sendable {
    case download
    case wait
    case removeFromCache
    case retry
}

private extension VoiceModelInstallStatus {
    var statusLabel: String {
        switch self {
        case .notInstalled:
            "Not installed"
        case .downloading:
            "Downloading"
        case .installed:
            "Installed"
        case .failed:
            "Failed"
        case .corrupted:
            "Needs reinstall"
        }
    }

    var action: VoiceModelReadinessAction {
        switch self {
        case .notInstalled:
            .download
        case .downloading:
            .wait
        case .installed:
            .removeFromCache
        case .failed, .corrupted:
            .retry
        }
    }

    var actionLabel: String {
        switch action {
        case .download:
            "Download"
        case .wait:
            "Wait"
        case .removeFromCache:
            "Remove from cache"
        case .retry:
            "Retry"
        }
    }
}

private extension Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

private extension HashFunction {
    static func hashFile(at url: URL) throws -> Self.Digest {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        var hasher = Self()
        while true {
            let chunk = try handle.read(upToCount: 1024 * 1024)
            guard let chunk, !chunk.isEmpty else {
                break
            }
            hasher.update(data: chunk)
        }
        return hasher.finalize()
    }
}

private struct VoiceModelFileMetadata: Equatable {
    var filePath: String
    var fileSize: Int64
    var modifiedAt: Date?
}

private struct VoiceModelReadinessCacheEntry: Equatable {
    var checksum: String
    var metadata: VoiceModelFileMetadata
    var status: VoiceModelInstallStatus
}

private final class VoiceModelReadinessCache: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: VoiceModelReadinessCacheEntry] = [:]

    func cachedStatus(for model: VoiceModelDescriptor, checksum: String) -> VoiceModelReadinessCacheEntry? {
        let key = cacheKey(for: model)
        return lock.withLock {
            entries[key]
        }.flatMap { entry in
            entry.checksum == checksum ? entry : nil
        }
    }

    func storeStatus(_ status: VoiceModelInstallStatus, for model: VoiceModelDescriptor, checksum: String, metadata: VoiceModelFileMetadata) {
        let key = cacheKey(for: model)
        lock.withLock {
            entries[key] = VoiceModelReadinessCacheEntry(
                checksum: checksum,
                metadata: metadata,
                status: status
            )
        }
    }

    func remove(for model: VoiceModelDescriptor) {
        let key = cacheKey(for: model)
        lock.withLock {
            entries[key] = nil
        }
    }

    private func cacheKey(for model: VoiceModelDescriptor) -> String {
        "\(model.id.rawValue):\(model.cacheFileName)"
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
