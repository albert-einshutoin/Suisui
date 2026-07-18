import CoreGraphics
import Foundation
import ImageIO

private struct Manifest: Decodable {
    let rasterComparison: RasterComparison
}

private struct RasterComparison: Decodable {
    let perChannelDeltaThreshold: Double
    let maximumChangedPixelRatio: Double
    let maximumMeanAbsoluteError: Double
}

private struct RGBAImage {
    let width: Int
    let height: Int
    let pixels: [UInt8]
}

private struct Options {
    let manifest: URL
    let first: URL
    let second: URL
}

private func failUsage(_ message: String) -> Never {
    fputs("BLOCKER: raster stability usage error: \(message)\n", stderr)
    exit(2)
}

private func parseOptions() -> Options {
    var values: [String: String] = [:]
    var index = 1
    while index < CommandLine.arguments.count {
        let key = CommandLine.arguments[index]
        guard ["--manifest", "--first", "--second"].contains(key) else {
            failUsage("unknown argument: \(key)")
        }
        index += 1
        guard index < CommandLine.arguments.count else {
            failUsage("\(key) requires a path")
        }
        values[key] = CommandLine.arguments[index]
        index += 1
    }
    guard let manifest = values["--manifest"],
          let first = values["--first"],
          let second = values["--second"] else {
        failUsage("--manifest, --first, and --second are required")
    }
    return Options(
        manifest: URL(fileURLWithPath: manifest),
        first: URL(fileURLWithPath: first),
        second: URL(fileURLWithPath: second)
    )
}

private func canonicalRGBA(_ url: URL) throws -> RGBAImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw NSError(domain: "VisualRasterStability", code: 1, userInfo: [NSLocalizedDescriptionKey: "could not decode \(url.lastPathComponent)"])
    }
    let width = image.width
    let height = image.height
    guard width > 0, height > 0,
          let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
        throw NSError(domain: "VisualRasterStability", code: 2, userInfo: [NSLocalizedDescriptionKey: "invalid raster dimensions or color space"])
    }
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "VisualRasterStability", code: 3, userInfo: [NSLocalizedDescriptionKey: "could not create canonical RGBA context"])
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return RGBAImage(width: width, height: height, pixels: pixels)
}

private func validate(_ thresholds: RasterComparison) throws {
    for (name, value) in [
        ("perChannelDeltaThreshold", thresholds.perChannelDeltaThreshold),
        ("maximumChangedPixelRatio", thresholds.maximumChangedPixelRatio),
        ("maximumMeanAbsoluteError", thresholds.maximumMeanAbsoluteError)
    ] where !value.isFinite || !(0...1).contains(value) {
        throw NSError(domain: "VisualRasterStability", code: 4, userInfo: [NSLocalizedDescriptionKey: "\(name) must be finite and within 0...1"])
    }
}

private func run() throws -> Bool {
    let options = parseOptions()
    let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: options.manifest))
    try validate(manifest.rasterComparison)
    let first = try canonicalRGBA(options.first)
    let second = try canonicalRGBA(options.second)
    guard first.width == second.width, first.height == second.height else {
        print("BLOCKER: raster did not converge: dimensions differ \(first.width)x\(first.height) vs \(second.width)x\(second.height)")
        return false
    }

    var changedPixels = 0
    var absoluteDeltaSum = 0
    for offset in stride(from: 0, to: first.pixels.count, by: 4) {
        let deltas = (0..<3).map { channel in
            abs(Int(first.pixels[offset + channel]) - Int(second.pixels[offset + channel]))
        }
        absoluteDeltaSum += deltas.reduce(0, +)
        if Double(deltas.max() ?? 0) / 255.0 > manifest.rasterComparison.perChannelDeltaThreshold {
            changedPixels += 1
        }
    }
    let pixelCount = first.width * first.height
    let changedRatio = Double(changedPixels) / Double(pixelCount)
    let meanAbsoluteError = Double(absoluteDeltaSum) / Double(pixelCount * 3 * 255)
    let converged = changedRatio <= manifest.rasterComparison.maximumChangedPixelRatio
        && meanAbsoluteError <= manifest.rasterComparison.maximumMeanAbsoluteError
    let metrics = "changed ratio \(changedRatio), MAE \(meanAbsoluteError)"
    if converged {
        print("OK: raster converged (\(metrics))")
    } else {
        print("BLOCKER: raster did not converge (\(metrics))")
    }
    return converged
}

do {
    exit(try run() ? 0 : 1)
} catch {
    fputs("BLOCKER: raster stability check failed: \(error.localizedDescription)\n", stderr)
    exit(2)
}
