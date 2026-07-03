import CoreGraphics
import Foundation
import ImageIO

struct Manifest: Decodable {
    var artifactRoot: String
    var semanticTolerances: SemanticTolerances
    var screens: [Screen]
}

struct SemanticTolerances: Decodable {
    var minimumBytes: Int
    var minimumWidth: Int
    var minimumHeight: Int
    var minimumLuminanceRange: Int
    var minimumColorBuckets: Int
    var blackScreenMaximumLuminance: Int
}

struct Screen: Decodable {
    var id: String
    var title: String
    var themes: [String]
    var artifacts: [String: String]
}

struct ImageInspection {
    var width: Int
    var height: Int
    var luminanceRange: Int
    var maximumLuminance: Int
    var colorBucketCount: Int
    var visiblePixelCount: Int
}

struct Options {
    var manifestPath: String
    var screenshotDirectory: String
    var baselineDirectory: String
    var updateBaselines: Bool
}

func parseOptions() -> Options {
    var manifestPath = ""
    var screenshotDirectory = ""
    var baselineDirectory = ""
    var updateBaselines = false
    var index = 1
    while index < CommandLine.arguments.count {
        switch CommandLine.arguments[index] {
        case "--manifest":
            index += 1
            guard index < CommandLine.arguments.count else {
                fatalUsage("--manifest requires a path.")
            }
            manifestPath = CommandLine.arguments[index]
        case "--screenshot-dir":
            index += 1
            guard index < CommandLine.arguments.count else {
                fatalUsage("--screenshot-dir requires a path.")
            }
            screenshotDirectory = CommandLine.arguments[index]
        case "--baseline-dir":
            index += 1
            guard index < CommandLine.arguments.count else {
                fatalUsage("--baseline-dir requires a path.")
            }
            baselineDirectory = CommandLine.arguments[index]
        case "--update-baselines":
            updateBaselines = true
        default:
            fatalUsage("unknown argument: \(CommandLine.arguments[index])")
        }
        index += 1
    }

    guard !manifestPath.isEmpty, !screenshotDirectory.isEmpty, !baselineDirectory.isEmpty else {
        fatalUsage("manifest, screenshot directory, and baseline directory are required.")
    }

    return Options(
        manifestPath: manifestPath,
        screenshotDirectory: screenshotDirectory,
        baselineDirectory: baselineDirectory,
        updateBaselines: updateBaselines
    )
}

func fatalUsage(_ message: String) -> Never {
    fputs("usage error: \(message)\n", stderr)
    exit(2)
}

func inspectImage(at url: URL) throws -> ImageInspection {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw NSError(domain: "VisualRegressionSmoke", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "image could not be read"
        ])
    }

    let sampleWidth = min(max(image.width, 1), 160)
    let sampleHeight = min(max(image.height, 1), 100)
    let bytesPerPixel = 4
    let bytesPerRow = sampleWidth * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: sampleHeight * bytesPerRow)

    guard let context = CGContext(
        data: &pixels,
        width: sampleWidth,
        height: sampleHeight,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "VisualRegressionSmoke", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "sampling context could not be created"
        ])
    }

    context.interpolationQuality = .low
    context.draw(image, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))

    var minimumLuminance = 255
    var maximumLuminance = 0
    var visiblePixelCount = 0
    var colorBuckets = Set<Int>()

    for offset in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
        let alpha = Int(pixels[offset + 3])
        guard alpha > 16 else { continue }

        let red = Int(pixels[offset])
        let green = Int(pixels[offset + 1])
        let blue = Int(pixels[offset + 2])
        let luminance = (red * 2_126 + green * 7_152 + blue * 722) / 10_000
        let bucket = (red / 32) << 10 | (green / 32) << 5 | (blue / 32)

        minimumLuminance = min(minimumLuminance, luminance)
        maximumLuminance = max(maximumLuminance, luminance)
        visiblePixelCount += 1
        colorBuckets.insert(bucket)
    }

    return ImageInspection(
        width: image.width,
        height: image.height,
        luminanceRange: maximumLuminance - minimumLuminance,
        maximumLuminance: maximumLuminance,
        colorBucketCount: colorBuckets.count,
        visiblePixelCount: visiblePixelCount
    )
}

func resolvedURL(baseDirectory: URL, artifact: String) -> URL {
    if artifact.hasPrefix("/") {
        return URL(fileURLWithPath: artifact)
    }
    return baseDirectory.appendingPathComponent(artifact)
}

let options = parseOptions()
let manifestURL = URL(fileURLWithPath: options.manifestPath)
let screenshotDirectory = URL(fileURLWithPath: options.screenshotDirectory, isDirectory: true)
let baselineDirectory = URL(fileURLWithPath: options.baselineDirectory, isDirectory: true)
let manifestData = try Data(contentsOf: manifestURL)
let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
let tolerances = manifest.semanticTolerances
let fileManager = FileManager.default
var blockers: [String] = []
var checkedCount = 0

for screen in manifest.screens {
    for theme in screen.themes {
        guard let artifact = screen.artifacts[theme] else {
            blockers.append("BLOCKER: visual manifest missing artifact for \(screen.id) \(theme)")
            continue
        }

        let screenshotURL = resolvedURL(baseDirectory: screenshotDirectory, artifact: artifact)
        let relativeLabel = "\(screen.id) \(theme) (\(artifact))"
        guard fileManager.fileExists(atPath: screenshotURL.path) else {
            blockers.append("BLOCKER: missing visual screenshot: \(relativeLabel)")
            continue
        }

        let attributes = try fileManager.attributesOfItem(atPath: screenshotURL.path)
        let byteCount = attributes[.size] as? Int ?? 0
        if byteCount < tolerances.minimumBytes {
            blockers.append("BLOCKER: visual screenshot is too small: \(relativeLabel) (\(byteCount) bytes)")
            continue
        }

        let inspection: ImageInspection
        do {
            inspection = try inspectImage(at: screenshotURL)
        } catch {
            blockers.append("BLOCKER: visual screenshot is unreadable: \(relativeLabel) (\(error.localizedDescription))")
            continue
        }

        if inspection.width < tolerances.minimumWidth || inspection.height < tolerances.minimumHeight {
            blockers.append("BLOCKER: visual screenshot dimensions are too small: \(relativeLabel) (\(inspection.width)x\(inspection.height))")
            continue
        }

        if inspection.maximumLuminance <= tolerances.blackScreenMaximumLuminance {
            blockers.append("BLOCKER: visual screenshot appears black: \(relativeLabel)")
            continue
        }

        let minimumVisiblePixels = max(1, (min(inspection.width, 160) * min(inspection.height, 100)) / 20)
        if inspection.visiblePixelCount < minimumVisiblePixels
            || inspection.luminanceRange < tolerances.minimumLuminanceRange
            || inspection.colorBucketCount < tolerances.minimumColorBuckets {
            blockers.append("BLOCKER: visual screenshot is low information: \(relativeLabel)")
            continue
        }

        if options.updateBaselines {
            let baselineURL = resolvedURL(baseDirectory: baselineDirectory, artifact: artifact)
            try fileManager.createDirectory(at: baselineURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: baselineURL.path) {
                try fileManager.removeItem(at: baselineURL)
            }
            try fileManager.copyItem(at: screenshotURL, to: baselineURL)
        }

        checkedCount += 1
    }
}

if !blockers.isEmpty {
    for blocker in blockers {
        print(blocker)
    }
    exit(1)
}

// The smoke intentionally validates semantic image health instead of exact pixels to avoid macOS rendering flakes.
print("OK: visual regression smoke passed (\(checkedCount) screenshots, manifest: \(manifestURL.path))")
