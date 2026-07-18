import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import Vision

// This checker deliberately keeps image health, raster comparison, and runtime AX
// evidence separate: a valid PNG alone is never evidence that the UI is usable.
struct Manifest: Decodable {
    let schemaVersion: Int
    let artifactRoot: String
    let semanticTolerances: SemanticTolerances
    let rasterComparison: RasterComparison
    let baselineContext: CaptureContext
    let overrides: [RasterOverride]?
    let screens: [Screen]
}

struct SemanticTolerances: Decodable {
    let minimumBytes: Int; let minimumWidth: Int; let minimumHeight: Int
    let minimumLuminanceRange: Int; let minimumColorBuckets: Int
    let blackScreenMaximumLuminance: Int; let requiresAXFrameAudit: Bool?
}

struct RasterComparison: Codable {
    var perChannelDeltaThreshold: Double
    var maximumChangedPixelRatio: Double
    var maximumMeanAbsoluteError: Double
    var reason: String?
}

struct RasterPatch: Decodable {
    let perChannelDeltaThreshold: Double?
    let maximumChangedPixelRatio: Double?
    let maximumMeanAbsoluteError: Double?
    let reason: String?
}

struct RasterOverride: Decodable {
    let screen: String?; let theme: String?
    let perChannelDeltaThreshold: Double?
    let maximumChangedPixelRatio: Double?
    let maximumMeanAbsoluteError: Double?
    let reason: String?
}

struct Viewport: Codable, Equatable { let width: Int; let height: Int }
struct CaptureContext: Codable {
    let sourceCommit: String
    let normalRoute: String
    let locale: String
    let timeZoneIdentifier: String
    let referenceInstant: String
}
struct Screen: Decodable {
    let id: String; let title: String; let themes: [String]; let viewport: Viewport
    let axFrameAudit: Bool?; let axTargetIdentifier: String; let rasterComparison: RasterPatch?
    let themeOverrides: [String: RasterPatch]?; let artifacts: [String: String]
    let requiredVisibleTextLines: [String]?
}
struct BaselineMetadata: Codable {
    let sourceCommit: String; let normalRoute: String; let locale: String
    let timeZoneIdentifier: String; let referenceInstant: String
    let appearance: String; let viewport: Viewport
    let rasterWidth: Int; let rasterHeight: Int; let generatedAt: String
}
struct WindowFrame: Decodable { let width: Int; let height: Int }
struct TargetFrameAudit: Decodable {
    let identifier: String
    let width: Double; let height: Double
    let visibleWidth: Double; let visibleHeight: Double
}
struct AXScreen: Decodable {
    let id: String; let viewport: Viewport; let appearance: String; let status: String
    let artifact: String; let sha256: String
    let actualWindowFrame: WindowFrame; let targetFrameAudit: TargetFrameAudit
}
struct AXAudit: Decodable {
    let result: String; let sourceCommit: String; let normalRoute: String; let locale: String
    let timeZoneIdentifier: String; let referenceInstant: String
    let createdAt: String; let screens: [AXScreen]
}
struct Options {
    let manifestPath: String; let screenshotDirectory: String; let baselineDirectory: String
    let artifactDirectory: String; let axAuditResult: String?; let currentSourceCommit: String
    let updateBaselines: Bool; let allowUpdate: Bool
}
struct RGBAImage { let width: Int; let height: Int; let pixels: [UInt8] }
struct Inspection { let width: Int; let height: Int; let luminanceRange: Int; let maximumLuminance: Int; let colorBucketCount: Int; let visiblePixelCount: Int }
struct ScreenThemeKey: Hashable { let screen: String; let theme: String }
struct RasterBucketKey: Hashable { let width: Int; let height: Int; let pixelHash: Int }

func blocker(_ message: String) { print("BLOCKER: \(message)") }
func usage(_ message: String) -> Never { fputs("BLOCKER: usage error: \(message)\n", stderr); exit(2) }

func parseOptions() -> Options {
    var values = [String: String](); var update = false; var allowUpdate = false; var index = 1
    while index < CommandLine.arguments.count {
        let argument = CommandLine.arguments[index]
        if argument == "--update-baselines" { update = true; index += 1; continue }
        if argument == "--allow-update" { allowUpdate = true; index += 1; continue }
        guard ["--manifest", "--screenshot-dir", "--baseline-dir", "--artifact-dir", "--ax-audit-result", "--current-source-commit"].contains(argument) else { usage("unknown argument: \(argument)") }
        index += 1; guard index < CommandLine.arguments.count else { usage("\(argument) requires a path") }
        values[argument] = CommandLine.arguments[index]; index += 1
    }
    guard let manifest = values["--manifest"], let screenshots = values["--screenshot-dir"], let baselines = values["--baseline-dir"] else { usage("manifest, screenshot directory, and baseline directory are required") }
    guard let currentSourceCommit = values["--current-source-commit"], !currentSourceCommit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { usage("--current-source-commit is required and must be nonblank") }
    return Options(manifestPath: manifest, screenshotDirectory: screenshots, baselineDirectory: baselines, artifactDirectory: values["--artifact-dir"] ?? ".visual-regression-artifacts", axAuditResult: values["--ax-audit-result"], currentSourceCommit: currentSourceCommit, updateBaselines: update, allowUpdate: allowUpdate)
}

func isSafePathComponent(_ value: String) -> Bool {
    guard isNonblank(value), !value.contains("\\"), !value.contains("\0") else { return false }
    let components = (value as NSString).pathComponents
    return components.count == 1 && components[0] == value && value != "." && value != ".."
}

func isSafeRelativePath(_ path: String) -> Bool {
    guard isNonblank(path), !(path as NSString).isAbsolutePath, !path.contains("\\"), !path.contains("\0") else { return false }
    let components = (path as NSString).pathComponents
    guard !components.isEmpty, !components.contains("."), !components.contains("..") else { return false }
    return (path as NSString).standardizingPath == path
}

func containedURL(_ root: URL, _ relativePath: String) -> URL? {
    guard isSafeRelativePath(relativePath) else { return nil }
    // Resolve both the authority root and the candidate. Checking only lexical
    // components lets an artifact symlink redirect reads or updates outside the
    // caller-provided directory even when the manifest path itself is clean.
    let standardizedRoot = root.standardizedFileURL
    let resolvedRoot = standardizedRoot.resolvingSymlinksInPath()
    let rootPrefix = resolvedRoot.path.hasSuffix("/") ? resolvedRoot.path : resolvedRoot.path + "/"
    var resolvedCandidate = resolvedRoot
    // Resolve at every component so an existing intermediate symlink is still
    // detected when the final evidence file or subdirectory does not exist yet.
    for component in (relativePath as NSString).pathComponents {
        resolvedCandidate = resolvedCandidate.appendingPathComponent(component).standardizedFileURL.resolvingSymlinksInPath()
        guard resolvedCandidate.path.hasPrefix(rootPrefix) else { return nil }
    }
    return resolvedCandidate
}

func metadataURL(for baselineURL: URL) -> URL {
    baselineURL.deletingPathExtension().appendingPathExtension("metadata.json")
}

func metadataRelativePath(for artifact: String) -> String {
    (artifact as NSString).deletingPathExtension + ".metadata.json"
}

func canonicalColorSpace() throws -> CGColorSpace {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
        throw NSError(domain: "VisualRegression", code: 6, userInfo: [NSLocalizedDescriptionKey: "could not create canonical sRGB color space"])
    }
    return colorSpace
}

func canonicalRGBA(_ url: URL) throws -> RGBAImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw NSError(domain: "VisualRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: "could not decode image"]) }
    let width = image.width, height = image.height
    guard width > 0, height > 0 else { throw NSError(domain: "VisualRegression", code: 2, userInfo: [NSLocalizedDescriptionKey: "image has empty dimensions"]) }
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: try canonicalColorSpace(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw NSError(domain: "VisualRegression", code: 3, userInfo: [NSLocalizedDescriptionKey: "could not create canonical RGBA context"]) }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return RGBAImage(width: width, height: height, pixels: pixels)
}

func sha256Hex(_ url: URL) throws -> String {
    SHA256.hash(data: try Data(contentsOf: url))
        .map { String(format: "%02x", $0) }
        .joined()
}

func inspect(_ image: RGBAImage) -> Inspection {
    let sx = min(image.width, 160), sy = min(image.height, 100)
    var minLum = 255, maxLum = 0, visible = 0; var buckets = Set<Int>()
    for y in 0..<sy { for x in 0..<sx {
        let sourceX = x * image.width / sx, sourceY = y * image.height / sy, offset = (sourceY * image.width + sourceX) * 4
        let a = Int(image.pixels[offset + 3]); guard a > 16 else { continue }
        let r = Int(image.pixels[offset]), g = Int(image.pixels[offset + 1]), b = Int(image.pixels[offset + 2])
        let lum = (r * 2126 + g * 7152 + b * 722) / 10000
        minLum = min(minLum, lum); maxLum = max(maxLum, lum); visible += 1; buckets.insert((r / 32) << 10 | (g / 32) << 5 | b / 32)
    }}
    return Inspection(width: image.width, height: image.height, luminanceRange: maxLum - minLum, maximumLuminance: maxLum, colorBucketCount: buckets.count, visiblePixelCount: visible)
}

func healthBlocker(_ image: RGBAImage, bytes: Int, label: String, tolerances: SemanticTolerances) -> String? {
    if bytes < tolerances.minimumBytes { return "visual screenshot is too small: \(label) (\(bytes) bytes)" }
    let info = inspect(image)
    if info.width < tolerances.minimumWidth || info.height < tolerances.minimumHeight { return "visual screenshot dimensions are too small: \(label) (\(info.width)x\(info.height))" }
    if info.maximumLuminance <= tolerances.blackScreenMaximumLuminance { return "visual screenshot appears black: \(label)" }
    let minimumVisible = max(1, min(info.width, 160) * min(info.height, 100) / 20)
    if info.visiblePixelCount < minimumVisible || info.luminanceRange < tolerances.minimumLuminanceRange || info.colorBucketCount < tolerances.minimumColorBuckets { return "visual screenshot is low information: \(label)" }
    return nil
}

func normalizedVisibleText(_ value: String) -> String {
    let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    let scalars = folded.unicodeScalars.map { scalar in
        CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : " "
    }.joined()
    return scalars.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

func recognizedVisibleTextLines(in url: URL, recognitionLanguage: String) throws -> [String] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    request.recognitionLanguages = [recognitionLanguage]
    try VNImageRequestHandler(url: url, options: [:]).perform([request])
    return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
}

func visibleTextBlockers(for screen: Screen, theme: String, screenshotURL: URL, locale: String) -> [String] {
    guard let requiredLines = screen.requiredVisibleTextLines, !requiredLines.isEmpty else { return [] }
    do {
        let recognized = try recognizedVisibleTextLines(in: screenshotURL, recognitionLanguage: locale).map(normalizedVisibleText)
        return requiredLines.compactMap { requiredLine in
            let expected = normalizedVisibleText(requiredLine)
            guard recognized.contains(where: { $0.contains(expected) }) else {
                return "BLOCKER: required visible text line is missing for \(screen.id) \(theme): \(requiredLine)"
            }
            return nil
        }
    } catch {
        return ["BLOCKER: visible text recognition failed for \(screen.id) \(theme): \(error.localizedDescription)"]
    }
}

func context(for manifest: Manifest) -> CaptureContext {
    return manifest.baselineContext
}
func isNonblank(_ value: String?) -> Bool { !(value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }
func comparison(for screen: Screen, theme: String, manifest: Manifest, blockers: inout [String]) -> RasterComparison {
    var resolved = manifest.rasterComparison
    func apply(_ override: RasterPatch?, scope: String) {
        guard let override else { return }
        guard isNonblank(override.reason) else { blockers.append("BLOCKER: raster comparison override for \(scope) requires a nonblank reason"); return }
        if let value = override.perChannelDeltaThreshold { resolved.perChannelDeltaThreshold = value }
        if let value = override.maximumChangedPixelRatio { resolved.maximumChangedPixelRatio = value }
        if let value = override.maximumMeanAbsoluteError { resolved.maximumMeanAbsoluteError = value }
    }
    apply(screen.rasterComparison, scope: screen.id); apply(screen.themeOverrides?[theme], scope: "\(screen.id) \(theme)")
    for override in manifest.overrides ?? [] where (override.screen == nil || override.screen == screen.id) && (override.theme == nil || override.theme == theme) {
        guard isNonblank(override.reason) else { blockers.append("BLOCKER: raster comparison override for \(screen.id) \(theme) requires a nonblank reason"); continue }
        if let value = override.perChannelDeltaThreshold { resolved.perChannelDeltaThreshold = value }; if let value = override.maximumChangedPixelRatio { resolved.maximumChangedPixelRatio = value }; if let value = override.maximumMeanAbsoluteError { resolved.maximumMeanAbsoluteError = value }
    }
    return resolved
}

func validateThreshold(_ name: String, value: Double, scope: String, blockers: inout [String]) {
    guard value.isFinite, (0.0...1.0).contains(value) else {
        blockers.append("BLOCKER: \(name) for \(scope) must be finite and within 0...1")
        return
    }
}

func validatePatch(_ patch: RasterPatch?, scope: String, blockers: inout [String]) {
    guard let patch else { return }
    if !isNonblank(patch.reason) {
        blockers.append("BLOCKER: raster comparison override for \(scope) requires a nonblank reason")
    }
    if let value = patch.perChannelDeltaThreshold { validateThreshold("perChannelDeltaThreshold", value: value, scope: scope, blockers: &blockers) }
    if let value = patch.maximumChangedPixelRatio { validateThreshold("maximumChangedPixelRatio", value: value, scope: scope, blockers: &blockers) }
    if let value = patch.maximumMeanAbsoluteError { validateThreshold("maximumMeanAbsoluteError", value: value, scope: scope, blockers: &blockers) }
}

func validateManifest(_ manifest: Manifest) -> [String] {
    var blockers = [String]()
    validateThreshold("perChannelDeltaThreshold", value: manifest.rasterComparison.perChannelDeltaThreshold, scope: "manifest rasterComparison", blockers: &blockers)
    validateThreshold("maximumChangedPixelRatio", value: manifest.rasterComparison.maximumChangedPixelRatio, scope: "manifest rasterComparison", blockers: &blockers)
    validateThreshold("maximumMeanAbsoluteError", value: manifest.rasterComparison.maximumMeanAbsoluteError, scope: "manifest rasterComparison", blockers: &blockers)
    if !isSafeRelativePath(manifest.artifactRoot) {
        blockers.append("BLOCKER: visual manifest artifactRoot must be a safe relative path")
    }
    if TimeZone(identifier: manifest.baselineContext.timeZoneIdentifier) == nil {
        blockers.append("BLOCKER: visual manifest baselineContext timeZoneIdentifier is invalid")
    }
    if ISO8601DateFormatter().date(from: manifest.baselineContext.referenceInstant) == nil {
        blockers.append("BLOCKER: visual manifest baselineContext referenceInstant is invalid")
    }

    var screenIDs = Set<String>()
    var artifactPaths = Set<String>()
    for screen in manifest.screens {
        if !isSafePathComponent(screen.id) {
            blockers.append("BLOCKER: visual manifest screen id must be a safe path component: \(screen.id)")
        }
        if !screenIDs.insert(screen.id).inserted {
            blockers.append("BLOCKER: visual manifest has duplicate screen id: \(screen.id)")
        }
        if screen.viewport.width <= 0 || screen.viewport.height <= 0 {
            blockers.append("BLOCKER: visual manifest viewport must be positive for \(screen.id)")
        }
        if !isSafePathComponent(screen.axTargetIdentifier) {
            blockers.append("BLOCKER: visual manifest axTargetIdentifier must be a safe nonblank component for \(screen.id)")
        }
        if let requiredLines = screen.requiredVisibleTextLines {
            if requiredLines.isEmpty {
                blockers.append("BLOCKER: visual manifest requiredVisibleTextLines must not be empty when present for \(screen.id)")
            }
            if requiredLines.count > 16 {
                blockers.append("BLOCKER: visual manifest requiredVisibleTextLines exceeds 16 entries for \(screen.id)")
            }
            var normalizedLines = Set<String>()
            for requiredLine in requiredLines {
                let normalized = normalizedVisibleText(requiredLine)
                if normalized.isEmpty || requiredLine.count > 256 {
                    blockers.append("BLOCKER: visual manifest requiredVisibleTextLines contains an invalid line for \(screen.id)")
                } else if !normalizedLines.insert(normalized).inserted {
                    blockers.append("BLOCKER: visual manifest requiredVisibleTextLines contains a duplicate line for \(screen.id): \(requiredLine)")
                }
            }
        }
        validatePatch(screen.rasterComparison, scope: screen.id, blockers: &blockers)

        let themeSet = Set(screen.themes)
        if themeSet.count != screen.themes.count {
            blockers.append("BLOCKER: visual manifest has duplicate themes for \(screen.id)")
        }
        if Set(screen.artifacts.keys) != themeSet {
            blockers.append("BLOCKER: visual manifest artifact keys must exactly match themes for \(screen.id)")
        }
        if let themeOverrides = screen.themeOverrides {
            for (theme, patch) in themeOverrides {
                if !themeSet.contains(theme) {
                    blockers.append("BLOCKER: visual manifest has an override for unknown theme \(screen.id) \(theme)")
                }
                validatePatch(patch, scope: "\(screen.id) \(theme)", blockers: &blockers)
            }
        }

        for theme in screen.themes {
            if !isSafePathComponent(theme) {
                blockers.append("BLOCKER: visual manifest theme must be a safe path component: \(screen.id) \(theme)")
            }
            guard let artifact = screen.artifacts[theme] else { continue }
            if !isSafeRelativePath(artifact) {
                blockers.append("BLOCKER: visual manifest artifact must be a safe relative path: \(screen.id) \(theme) (\(artifact))")
            }
            if (artifact as NSString).pathExtension.lowercased() != "png" {
                blockers.append("BLOCKER: visual manifest artifact must be a PNG: \(screen.id) \(theme) (\(artifact))")
            }
            if !artifactPaths.insert(artifact).inserted {
                blockers.append("BLOCKER: visual manifest has duplicate artifact path: \(artifact)")
            }
            var comparisonBlockers = [String]()
            let resolved = comparison(for: screen, theme: theme, manifest: manifest, blockers: &comparisonBlockers)
            blockers.append(contentsOf: comparisonBlockers)
            validateThreshold("perChannelDeltaThreshold", value: resolved.perChannelDeltaThreshold, scope: "\(screen.id) \(theme)", blockers: &blockers)
            validateThreshold("maximumChangedPixelRatio", value: resolved.maximumChangedPixelRatio, scope: "\(screen.id) \(theme)", blockers: &blockers)
            validateThreshold("maximumMeanAbsoluteError", value: resolved.maximumMeanAbsoluteError, scope: "\(screen.id) \(theme)", blockers: &blockers)
        }
    }

    for override in manifest.overrides ?? [] {
        let scope = [override.screen, override.theme].compactMap { $0 }.joined(separator: " ")
        if !isNonblank(override.reason) {
            blockers.append("BLOCKER: raster comparison override for \(scope.isEmpty ? "manifest" : scope) requires a nonblank reason")
        }
        if let screen = override.screen, !screenIDs.contains(screen) {
            blockers.append("BLOCKER: raster comparison override references unknown screen: \(screen)")
        }
        if let theme = override.theme, !isSafePathComponent(theme) {
            blockers.append("BLOCKER: raster comparison override theme must be a safe component: \(theme)")
        }
        if let value = override.perChannelDeltaThreshold { validateThreshold("perChannelDeltaThreshold", value: value, scope: scope, blockers: &blockers) }
        if let value = override.maximumChangedPixelRatio { validateThreshold("maximumChangedPixelRatio", value: value, scope: scope, blockers: &blockers) }
        if let value = override.maximumMeanAbsoluteError { validateThreshold("maximumMeanAbsoluteError", value: value, scope: scope, blockers: &blockers) }
    }
    return blockers
}

func validateAX(_ auditPath: String?, manifest: Manifest, screenshotDirectory: String, currentSourceCommit: String, updateBaselines: Bool) -> [String] {
    let required = manifest.screens.flatMap { screen in screen.themes.filter { _ in (screen.axFrameAudit ?? manifest.semanticTolerances.requiresAXFrameAudit ?? false) }.map { (screen, $0) } }
    guard !required.isEmpty else { return [] }
    guard let auditPath, FileManager.default.fileExists(atPath: auditPath) else { return ["BLOCKER: AX frame audit result is required for this manifest"] }
    let audit: AXAudit
    do { audit = try JSONDecoder().decode(AXAudit.self, from: Data(contentsOf: URL(fileURLWithPath: auditPath))) } catch { return ["BLOCKER: AX frame audit result is invalid: \(error.localizedDescription)"] }
    var blockers = [String](); if audit.result.lowercased() != "passed" { blockers.append("BLOCKER: AX frame audit result is not passed") }
    if audit.sourceCommit != currentSourceCommit {
        blockers.append("BLOCKER: AX audit sourceCommit does not match --current-source-commit")
    }
    if updateBaselines {
        let baselineSourceCommit = manifest.baselineContext.sourceCommit
        if audit.sourceCommit != baselineSourceCommit {
            blockers.append("BLOCKER: baseline update requires AX audit sourceCommit to match manifest baselineContext sourceCommit")
        }
    }
    let formatter = ISO8601DateFormatter(); guard let created = formatter.date(from: audit.createdAt) else { return blockers + ["BLOCKER: AX frame audit createdAt is invalid"] }
    let age = Date().timeIntervalSince(created); if age > 15 * 60 { blockers.append("BLOCKER: AX frame audit is stale; capture a fresh runtime audit") }; if age < -60 { blockers.append("BLOCKER: AX frame audit createdAt is more than 60 seconds in the future") }

    let expectedKeys = Set(required.map { ScreenThemeKey(screen: $0.0.id, theme: $0.1) })
    var entries = [ScreenThemeKey: AXScreen]()
    for entry in audit.screens {
        let key = ScreenThemeKey(screen: entry.id, theme: entry.appearance)
        if entries[key] != nil {
            blockers.append("BLOCKER: AX frame audit has duplicate entry for \(entry.id) \(entry.appearance)")
        } else {
            entries[key] = entry
        }
    }
    for key in Set(entries.keys).subtracting(expectedKeys).sorted(by: { ($0.screen, $0.theme) < ($1.screen, $1.theme) }) {
        blockers.append("BLOCKER: AX frame audit has unexpected entry for \(key.screen) \(key.theme); exact coverage is required")
    }
    for (screen, theme) in required {
        let expected = context(for: manifest)
        if audit.normalRoute != expected.normalRoute { blockers.append("BLOCKER: AX audit normalRoute does not match manifest for \(screen.id)") }
        if audit.locale != expected.locale { blockers.append("BLOCKER: AX audit locale does not match manifest for \(screen.id)") }
        if audit.timeZoneIdentifier != expected.timeZoneIdentifier { blockers.append("BLOCKER: AX audit timeZoneIdentifier does not match manifest for \(screen.id)") }
        if audit.referenceInstant != expected.referenceInstant { blockers.append("BLOCKER: AX audit referenceInstant does not match manifest for \(screen.id)") }
        let key = ScreenThemeKey(screen: screen.id, theme: theme)
        guard let entry = entries[key] else { blockers.append("BLOCKER: AX frame audit is missing \(screen.id) \(theme); exact coverage is required"); continue }
        if entry.status.lowercased() != "passed" { blockers.append("BLOCKER: AX frame audit status is not passed for \(screen.id) \(theme)") }
        if entry.viewport != screen.viewport { blockers.append("BLOCKER: AX frame audit viewport does not match manifest for \(screen.id) \(theme)") }
        if entry.artifact != screen.artifacts[theme] { blockers.append("BLOCKER: AX frame audit artifact does not match manifest for \(screen.id) \(theme)") }
        if entry.sha256.count != 64 || entry.sha256 != entry.sha256.lowercased() || !entry.sha256.allSatisfy({ $0.isHexDigit }) {
            blockers.append("BLOCKER: AX frame audit SHA-256 is invalid for \(screen.id) \(theme)")
        } else if let artifact = screen.artifacts[theme], let screenshotURL = containedURL(URL(fileURLWithPath: screenshotDirectory), artifact) {
            do {
                if try sha256Hex(screenshotURL) != entry.sha256 {
                    blockers.append("BLOCKER: current screenshot SHA-256 digest does not match AX audit receipt for \(screen.id) \(theme)")
                }
            } catch {
                blockers.append("BLOCKER: current screenshot SHA-256 could not be read for \(screen.id) \(theme): \(error.localizedDescription)")
            }
        } else {
            blockers.append("BLOCKER: current screenshot path escapes screenshot root for SHA-256 validation: \(screen.id) \(theme)")
        }
        if entry.actualWindowFrame.width != screen.viewport.width || entry.actualWindowFrame.height != screen.viewport.height {
            blockers.append("BLOCKER: AX frame audit actualWindowFrame must exactly match manifest viewport for \(screen.id) \(theme)")
        }
        let target = entry.targetFrameAudit
        if !isSafePathComponent(target.identifier) {
            blockers.append("BLOCKER: AX frame audit targetFrameAudit identifier must be a safe nonblank component for \(screen.id) \(theme)")
        } else if target.identifier != screen.axTargetIdentifier {
            blockers.append("BLOCKER: AX frame audit targetFrameAudit identifier does not match manifest axTargetIdentifier for \(screen.id) \(theme)")
        }
        let geometry = [target.width, target.height, target.visibleWidth, target.visibleHeight]
        if !geometry.allSatisfy({ $0.isFinite && $0 > 0 }) {
            blockers.append("BLOCKER: AX frame audit targetFrameAudit dimensions must all be finite and positive for \(screen.id) \(theme)")
        } else {
            if target.visibleWidth > target.width + 0.001 || target.visibleHeight > target.height + 0.001 {
                blockers.append("BLOCKER: AX frame audit targetFrameAudit visible dimensions must not exceed the target frame for \(screen.id) \(theme)")
            }
            if target.visibleWidth < min(44, target.width) || target.visibleHeight < min(44, target.height) {
                blockers.append("BLOCKER: AX frame audit targetFrameAudit visible dimensions are not meaningful for \(screen.id) \(theme)")
            }
        }
    }
    return blockers
}

func pngData(_ image: RGBAImage) throws -> Data {
    var pixels = image.pixels
    let data = NSMutableData()
    guard let context = CGContext(data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: try canonicalColorSpace(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let cgImage = context.makeImage(), let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { throw NSError(domain: "VisualRegression", code: 4, userInfo: [NSLocalizedDescriptionKey: "could not encode PNG"]) }
    CGImageDestinationAddImage(destination, cgImage, nil); guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "VisualRegression", code: 5, userInfo: [NSLocalizedDescriptionKey: "could not finalize PNG"]) }; return data as Data
}

func writeEvidence(root: URL, screen: Screen, theme: String, baseline: RGBAImage, current: RGBAImage, comparison: RasterComparison, reason: String, changed: Int = 0, mae: Double = 0, maxDelta: Int = 0) -> String? {
    do {
        let relativeDirectory = "\(screen.id)/\(theme)"
        guard let directory = containedURL(root, relativeDirectory),
              let baselineOutput = containedURL(root, "\(relativeDirectory)/baseline.png"),
              let currentOutput = containedURL(root, "\(relativeDirectory)/current.png"),
              let diffOutput = containedURL(root, "\(relativeDirectory)/diff.png"),
              let metricsOutput = containedURL(root, "\(relativeDirectory)/metrics.json") else {
            return "failure evidence symlink escapes artifact root for \(screen.id) \(theme)"
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try pngData(baseline).write(to: baselineOutput); try pngData(current).write(to: currentOutput)
        var diff = [UInt8](repeating: 0, count: current.pixels.count)
        if baseline.width == current.width && baseline.height == current.height { for offset in stride(from: 0, to: diff.count, by: 4) { let delta = max(abs(Int(current.pixels[offset]) - Int(baseline.pixels[offset])), abs(Int(current.pixels[offset + 1]) - Int(baseline.pixels[offset + 1])), abs(Int(current.pixels[offset + 2]) - Int(baseline.pixels[offset + 2]))); if Double(delta) / 255.0 > comparison.perChannelDeltaThreshold { diff[offset] = 255; diff[offset + 3] = 255 } } }
        try pngData(RGBAImage(width: current.width, height: current.height, pixels: diff)).write(to: diffOutput)
        let metrics: [String: Any] = ["screen": screen.id, "theme": theme, "viewport": ["width": screen.viewport.width, "height": screen.viewport.height], "dimensions": ["baseline": ["width": baseline.width, "height": baseline.height], "current": ["width": current.width, "height": current.height]], "thresholds": ["perChannelDeltaThreshold": comparison.perChannelDeltaThreshold, "maximumChangedPixelRatio": comparison.maximumChangedPixelRatio, "maximumMeanAbsoluteError": comparison.maximumMeanAbsoluteError], "changedPixelCount": changed, "changedPixelRatio": Double(changed) / Double(max(1, current.width * current.height)), "meanAbsoluteError": mae, "observedMaximumChannelDelta": maxDelta, "reasons": [reason]]
        try JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted, .sortedKeys]).write(to: metricsOutput)
        return nil
    } catch { return "could not write visual comparison evidence: \(error.localizedDescription)" }
}

func main() throws {
    let options = parseOptions(), manager = FileManager.default
    if options.updateBaselines && !options.allowUpdate { blocker("baseline update requires --allow-update"); exit(1) }
    let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: URL(fileURLWithPath: options.manifestPath)))
    guard manifest.schemaVersion == 2 else { blocker("visual manifest schemaVersion must be 2"); exit(1) }
    var blockers = validateManifest(manifest)
    if !blockers.isEmpty { blockers.forEach { print($0) }; exit(1) }
    blockers = validateAX(options.axAuditResult, manifest: manifest, screenshotDirectory: options.screenshotDirectory, currentSourceCommit: options.currentSourceCommit, updateBaselines: options.updateBaselines)
    var currentEntries: [(Screen, String, String, URL, RGBAImage)] = []
    for screen in manifest.screens { for theme in screen.themes {
        guard let artifact = screen.artifacts[theme] else { blockers.append("BLOCKER: visual manifest missing artifact for \(screen.id) \(theme)"); continue }
        guard let url = containedURL(URL(fileURLWithPath: options.screenshotDirectory), artifact) else { blockers.append("BLOCKER: visual manifest artifact escapes screenshot root for \(screen.id) \(theme)"); continue }
        let label = "\(screen.id) \(theme) (\(artifact))"
        guard manager.fileExists(atPath: url.path) else { blockers.append("BLOCKER: missing visual screenshot: \(label)"); continue }
        do {
            let image = try canonicalRGBA(url)
            let size = (try manager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
            if let fault = healthBlocker(image, bytes: size, label: label, tolerances: manifest.semanticTolerances) {
                blockers.append("BLOCKER: \(fault)")
            } else {
                blockers.append(contentsOf: visibleTextBlockers(
                    for: screen,
                    theme: theme,
                    screenshotURL: url,
                    locale: manifest.baselineContext.locale
                ))
                currentEntries.append((screen, theme, artifact, url, image))
            }
        } catch {
            blockers.append("BLOCKER: visual screenshot could not decode: \(label) (\(error.localizedDescription))")
        }
    }}
    // Hash once per raster so exact duplicate detection stays linear for normal
    // captures; byte equality remains the authority in case hashes collide.
    var rasterBuckets = [RasterBucketKey: [Int]]()
    for currentIndex in currentEntries.indices {
        let current = currentEntries[currentIndex]
        let key = RasterBucketKey(width: current.4.width, height: current.4.height, pixelHash: current.4.pixels.hashValue)
        for previousIndex in rasterBuckets[key, default: []] {
            let previous = currentEntries[previousIndex]
            guard previous.0.id != current.0.id, previous.4.pixels == current.4.pixels else { continue }
            blockers.append("BLOCKER: decoded raster is identical across different screen ids: \(previous.0.id) \(previous.1) and \(current.0.id) \(current.1)")
        }
        rasterBuckets[key, default: []].append(currentIndex)
    }
    if !blockers.isEmpty { blockers.forEach { print($0) }; exit(1) }
    if options.updateBaselines {
        let destination = URL(fileURLWithPath: options.baselineDirectory), staging = destination.deletingLastPathComponent().appendingPathComponent(".visual-baselines-staging-\(UUID().uuidString)")
        // An existing baseline tree is moved during the transaction. Reject
        // escaping symlinks before mutation so update mode is fail-closed too.
        for (screen, theme, artifact, _, _) in currentEntries {
            let nominalBaseline = destination.appendingPathComponent(artifact)
            if manager.fileExists(atPath: nominalBaseline.path), containedURL(destination, artifact) == nil {
                blocker("baseline artifact symlink escapes baseline root for \(screen.id) \(theme)")
                exit(1)
            }
            let metadataPath = metadataRelativePath(for: artifact)
            let nominalMetadata = destination.appendingPathComponent(metadataPath)
            if manager.fileExists(atPath: nominalMetadata.path), containedURL(destination, metadataPath) == nil {
                blocker("baseline metadata symlink escapes baseline root for \(screen.id) \(theme)")
                exit(1)
            }
        }
        defer { try? manager.removeItem(at: staging) }; try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        for (screen, theme, artifact, source, image) in currentEntries { let capture = context(for: manifest); guard let target = containedURL(staging, artifact) else { blocker("visual manifest artifact escapes baseline staging root for \(screen.id) \(theme)"); exit(1) }; try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true); try manager.copyItem(at: source, to: target); let metadata = BaselineMetadata(sourceCommit: capture.sourceCommit, normalRoute: capture.normalRoute, locale: capture.locale, timeZoneIdentifier: capture.timeZoneIdentifier, referenceInstant: capture.referenceInstant, appearance: theme, viewport: screen.viewport, rasterWidth: image.width, rasterHeight: image.height, generatedAt: ISO8601DateFormatter().string(from: Date())); try JSONEncoder().encode(metadata).write(to: metadataURL(for: target)) }
        let backup = destination.deletingLastPathComponent().appendingPathComponent(".visual-baselines-backup-\(UUID().uuidString)"); var moved = false
        do { if manager.fileExists(atPath: destination.path) { try manager.moveItem(at: destination, to: backup); moved = true }; try manager.moveItem(at: staging, to: destination); if moved { try? manager.removeItem(at: backup) } } catch { if moved && !manager.fileExists(atPath: destination.path) { try? manager.moveItem(at: backup, to: destination) }; throw error }
        print("OK: visual regression baselines updated transactionally (\(currentEntries.count) screenshots)"); return
    }
    for (screen, theme, artifact, _, current) in currentEntries {
        var overrideBlockers = [String](); let comparison = comparison(for: screen, theme: theme, manifest: manifest, blockers: &overrideBlockers); if !overrideBlockers.isEmpty { blockers.append(contentsOf: overrideBlockers); continue }
        let baselineRoot = URL(fileURLWithPath: options.baselineDirectory)
        guard let baselineURL = containedURL(baselineRoot, artifact) else { blockers.append("BLOCKER: visual manifest artifact or symlink escapes baseline root for \(screen.id) \(theme)"); continue }
        guard let baselineMetadataURL = containedURL(baselineRoot, metadataRelativePath(for: artifact)) else { blockers.append("BLOCKER: visual baseline metadata symlink escapes baseline root for \(screen.id) \(theme)"); continue }
        guard manager.fileExists(atPath: baselineURL.path) else { blockers.append("BLOCKER: missing baseline: \(screen.id) \(theme)"); continue }
        guard manager.fileExists(atPath: baselineMetadataURL.path) else { blockers.append("BLOCKER: missing baseline metadata: \(screen.id) \(theme)"); continue }
        let capture = context(for: manifest)
        do {
            let metadata = try JSONDecoder().decode(BaselineMetadata.self, from: Data(contentsOf: baselineMetadataURL))
            if metadata.sourceCommit != capture.sourceCommit || metadata.normalRoute != capture.normalRoute || metadata.locale != capture.locale || metadata.timeZoneIdentifier != capture.timeZoneIdentifier || metadata.referenceInstant != capture.referenceInstant || metadata.appearance != theme || metadata.viewport != screen.viewport {
                blockers.append("BLOCKER: baseline metadata does not match manifest context for \(screen.id) \(theme)")
                continue
            }
            let baseline = try canonicalRGBA(baselineURL)
            if metadata.rasterWidth != baseline.width || metadata.rasterHeight != baseline.height {
                blockers.append("BLOCKER: baseline metadata rasterWidth/rasterHeight do not match decoded baseline for \(screen.id) \(theme)")
                continue
            }
            if ISO8601DateFormatter().date(from: metadata.generatedAt) == nil {
                blockers.append("BLOCKER: baseline metadata generatedAt is invalid for \(screen.id) \(theme)")
                continue
            }
            guard baseline.width == current.width && baseline.height == current.height else {
                if let evidenceFailure = writeEvidence(root: URL(fileURLWithPath: options.artifactDirectory), screen: screen, theme: theme, baseline: baseline, current: current, comparison: comparison, reason: "raster dimensions differ") {
                    blockers.append("BLOCKER: \(evidenceFailure)")
                }
                blockers.append("BLOCKER: baseline/current raster dimension mismatch for \(screen.id) \(theme); resizing is not allowed")
                continue
            }
            var changed = 0, sum = 0, maximum = 0
            for offset in stride(from: 0, to: current.pixels.count, by: 4) {
                let deltas = [abs(Int(current.pixels[offset]) - Int(baseline.pixels[offset])), abs(Int(current.pixels[offset + 1]) - Int(baseline.pixels[offset + 1])), abs(Int(current.pixels[offset + 2]) - Int(baseline.pixels[offset + 2]))]
                maximum = max(maximum, deltas.max()!)
                sum += deltas.reduce(0, +)
                if Double(deltas.max()!) / 255.0 > comparison.perChannelDeltaThreshold { changed += 1 }
            }
            let ratio = Double(changed) / Double(current.width * current.height)
            let mae = Double(sum) / Double(current.width * current.height * 3 * 255)
            if ratio > comparison.maximumChangedPixelRatio || mae > comparison.maximumMeanAbsoluteError {
                if let evidenceFailure = writeEvidence(root: URL(fileURLWithPath: options.artifactDirectory), screen: screen, theme: theme, baseline: baseline, current: current, comparison: comparison, reason: "raster thresholds exceeded", changed: changed, mae: mae, maxDelta: maximum) {
                    blockers.append("BLOCKER: \(evidenceFailure)")
                }
                blockers.append("BLOCKER: visual raster comparison failed for \(screen.id) \(theme) (changed ratio \(ratio), MAE \(mae))")
            }
        } catch {
            blockers.append("BLOCKER: baseline could not decode or metadata could not be read for \(screen.id) \(theme): \(error.localizedDescription)")
        }
    }
    if !blockers.isEmpty { blockers.forEach { print($0) }; exit(1) }
    print("OK: visual regression smoke passed (\(currentEntries.count) screenshots, manifest: \(options.manifestPath))")
}

do { try main() } catch { blocker(error.localizedDescription); exit(1) }
