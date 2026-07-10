import Foundation

struct Manifest: Decodable {
    let schemaVersion: Int
    let baselineContext: CaptureContext
    let screens: [Screen]
}

struct CaptureContext: Decodable {
    let sourceCommit: String
    let normalRoute: String
    let locale: String
    let timeZoneIdentifier: String
    let referenceInstant: String
}

struct Screen: Decodable {
    let id: String
    let themes: [String]
    let viewport: Viewport
    let axTargetIdentifier: String
    let artifacts: [String: String]
}

struct Viewport: Codable {
    let width: Int
    let height: Int
}

struct ReceiptScreen: Codable {
    let id: String
    let appearance: String
    let viewport: Viewport
    let status: String
    let artifact: String
    let sha256: String
    let actualWindowFrame: WindowFrame
    let targetFrameAudit: TargetFrameAudit
}

struct WindowFrame: Codable {
    let width: Int
    let height: Int
}

struct TargetFrameAudit: Codable {
    let identifier: String
    let width: Double
    let height: Double
    let visibleWidth: Double
    let visibleHeight: Double
}

struct Receipt: Codable {
    let result: String
    let sourceCommit: String
    let normalRoute: String
    let locale: String
    let timeZoneIdentifier: String
    let referenceInstant: String
    let createdAt: String
    let screens: [ReceiptScreen]
}

struct CaptureRow {
    let artifact: String
    let label: String
    let width: Int
    let height: Int
    let sha256: String
    let targetFrameAudit: TargetFrameAudit
}

enum ReceiptError: LocalizedError {
    case invalidArguments
    case invalidManifest(String)
    case invalidCaptureRow(String)
    case contract(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments: return "usage: writer manifest captures.tsv output sourceCommit normalRoute locale timeZoneIdentifier referenceInstant"
        case let .invalidManifest(message), let .invalidCaptureRow(message), let .contract(message): return message
        }
    }
}

func readManifest(at path: String) throws -> Manifest {
    do {
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        guard manifest.schemaVersion == 2 else { throw ReceiptError.invalidManifest("manifest schemaVersion must be 2") }
        return manifest
    } catch let error as ReceiptError {
        throw error
    } catch {
        throw ReceiptError.invalidManifest("could not decode manifest: \(error.localizedDescription)")
    }
}

func readRows(at path: String) throws -> [CaptureRow] {
    let contents: String
    do { contents = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8) }
    catch { throw ReceiptError.invalidCaptureRow("could not read captures TSV: \(error.localizedDescription)") }

    return try contents.split(whereSeparator: \.isNewline).map { line in
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 10, !fields[0].isEmpty, !fields[1].isEmpty, !fields[4].isEmpty,
              let width = Int(fields[2]), let height = Int(fields[3]),
              let targetWidth = Double(fields[5]), let targetHeight = Double(fields[6]),
              let visibleWidth = Double(fields[7]), let visibleHeight = Double(fields[8]) else {
            throw ReceiptError.invalidCaptureRow(
                "capture row must be artifact, label, window width/height, target identifier/frame/visible frame, and SHA-256 TSV: \(line)"
            )
        }
        guard width > 0, height > 0 else {
            throw ReceiptError.invalidCaptureRow("capture row has non-positive window frame: \(line)")
        }
        let geometry = [targetWidth, targetHeight, visibleWidth, visibleHeight]
        guard geometry.allSatisfy({ $0.isFinite && $0 > 0 }),
              visibleWidth <= targetWidth + 0.001,
              visibleHeight <= targetHeight + 0.001,
              visibleWidth >= min(44, targetWidth),
              visibleHeight >= min(44, targetHeight) else {
            throw ReceiptError.invalidCaptureRow("capture row has invalid or non-meaningful target frame audit: \(line)")
        }
        let sha256 = fields[9]
        guard sha256.count == 64,
              sha256 == sha256.lowercased(),
              sha256.allSatisfy({ $0.isHexDigit }) else {
            throw ReceiptError.invalidCaptureRow("capture row has invalid SHA-256: \(line)")
        }
        return CaptureRow(
            artifact: fields[0],
            label: fields[1],
            width: width,
            height: height,
            sha256: sha256,
            targetFrameAudit: TargetFrameAudit(
                identifier: fields[4],
                width: targetWidth,
                height: targetHeight,
                visibleWidth: visibleWidth,
                visibleHeight: visibleHeight
            )
        )
    }
}

func makeReceipt(
    manifest: Manifest,
    rows: [CaptureRow],
    sourceCommit: String,
    normalRoute: String,
    locale: String,
    timeZoneIdentifier: String,
    referenceInstant: String
) throws -> Receipt {
    guard !sourceCommit.isEmpty,
          sourceCommit.count == 40 || sourceCommit.count == 64,
          sourceCommit.allSatisfy({ $0.isHexDigit }) else {
        throw ReceiptError.contract("sourceCommit must be a full hexadecimal product-source commit hash")
    }
    guard TimeZone(identifier: timeZoneIdentifier) != nil,
          ISO8601DateFormatter().date(from: referenceInstant) != nil else {
        throw ReceiptError.contract("capture timezone or reference instant is invalid")
    }
    guard manifest.baselineContext.normalRoute == normalRoute,
          manifest.baselineContext.locale == locale,
          manifest.baselineContext.timeZoneIdentifier == timeZoneIdentifier,
          manifest.baselineContext.referenceInstant == referenceInstant else {
        throw ReceiptError.contract("capture route, locale, timezone, or reference instant does not match manifest baselineContext")
    }

    var expected = [String: (screen: String, theme: String, viewport: Viewport, targetIdentifier: String)]()
    for screen in manifest.screens {
        guard !screen.axTargetIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReceiptError.contract("manifest has blank axTargetIdentifier for \(screen.id)")
        }
        for theme in screen.themes {
            guard let artifact = screen.artifacts[theme] else {
                throw ReceiptError.contract("manifest is missing artifact for \(screen.id) \(theme)")
            }
            guard expected[artifact] == nil else { throw ReceiptError.contract("manifest has duplicate artifact: \(artifact)") }
            expected[artifact] = (screen.id, theme, screen.viewport, screen.axTargetIdentifier)
        }
    }

    guard !expected.isEmpty else { throw ReceiptError.contract("manifest has no screen/theme artifacts") }
    var seen = Set<String>()
    var receiptScreens = [ReceiptScreen]()
    for row in rows {
        guard seen.insert(row.artifact).inserted else { throw ReceiptError.contract("duplicate capture row: \(row.artifact)") }
        guard let target = expected[row.artifact] else { throw ReceiptError.contract("unexpected capture artifact: \(row.artifact)") }
        guard row.width == target.viewport.width, row.height == target.viewport.height else {
            throw ReceiptError.contract(
                "actual window frame \(row.width)x\(row.height) does not equal manifest viewport \(target.viewport.width)x\(target.viewport.height) for \(row.artifact)"
            )
        }
        guard row.targetFrameAudit.identifier == target.targetIdentifier else {
            throw ReceiptError.contract(
                "AX target identifier \(row.targetFrameAudit.identifier) does not match manifest \(target.targetIdentifier) for \(row.artifact)"
            )
        }
        receiptScreens.append(ReceiptScreen(
            id: target.screen,
            appearance: target.theme,
            viewport: target.viewport,
            status: "passed",
            artifact: row.artifact,
            sha256: row.sha256,
            actualWindowFrame: WindowFrame(width: row.width, height: row.height),
            targetFrameAudit: row.targetFrameAudit
        ))
    }
    guard seen == Set(expected.keys) else {
        let missing = Set(expected.keys).subtracting(seen).sorted().joined(separator: ", ")
        throw ReceiptError.contract("incomplete capture coverage; missing: \(missing)")
    }

    receiptScreens.sort { ($0.id, $0.appearance) < ($1.id, $1.appearance) }
    return Receipt(
        result: "passed",
        sourceCommit: sourceCommit,
        normalRoute: normalRoute,
        locale: locale,
        timeZoneIdentifier: timeZoneIdentifier,
        referenceInstant: referenceInstant,
        createdAt: ISO8601DateFormatter().string(from: Date()),
        screens: receiptScreens
    )
}

func main() throws {
    guard CommandLine.arguments.count == 9 else { throw ReceiptError.invalidArguments }
    let manifest = try readManifest(at: CommandLine.arguments[1])
    let rows = try readRows(at: CommandLine.arguments[2])
    let receipt = try makeReceipt(
        manifest: manifest,
        rows: rows,
        sourceCommit: CommandLine.arguments[4],
        normalRoute: CommandLine.arguments[5],
        locale: CommandLine.arguments[6],
        timeZoneIdentifier: CommandLine.arguments[7],
        referenceInstant: CommandLine.arguments[8]
    )
    let outputURL = URL(fileURLWithPath: CommandLine.arguments[3])
    let temporaryURL = outputURL.deletingLastPathComponent().appendingPathComponent(".\(outputURL.lastPathComponent).tmp-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: temporaryURL) }
    let data = try JSONEncoder().encode(receipt)
    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: temporaryURL, options: .atomic)
    try? FileManager.default.removeItem(at: outputURL)
    try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
    print(outputURL.path)
}

do {
    try main()
} catch {
    if CommandLine.arguments.count > 3 {
        try? FileManager.default.removeItem(atPath: CommandLine.arguments[3])
    }
   fputs("BLOCKER: \(error.localizedDescription)\n", stderr)
   exit(1)
}
