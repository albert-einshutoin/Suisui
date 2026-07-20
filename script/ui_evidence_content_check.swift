import CoreGraphics
import Foundation
import ImageIO

guard CommandLine.arguments.count == 2 || CommandLine.arguments.count == 6 else {
    fputs("screenshot content check requires an image path and optional x y width height region.\n", stderr)
    exit(2)
}

let imagePath = CommandLine.arguments[1]
let imageURL = URL(fileURLWithPath: imagePath)

guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
      let sourceImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fputs("screenshot content check could not read image: \(imagePath)\n", stderr)
    exit(2)
}

let image: CGImage
if CommandLine.arguments.count == 6 {
    guard let x = Int(CommandLine.arguments[2]),
          let y = Int(CommandLine.arguments[3]),
          let width = Int(CommandLine.arguments[4]),
          let height = Int(CommandLine.arguments[5]),
          width > 0,
          height > 0 else {
        fputs("screenshot content check received an invalid region.\n", stderr)
        exit(2)
    }
    let boundedRegion = CGRect(x: x, y: y, width: width, height: height)
        .intersection(CGRect(x: 0, y: 0, width: sourceImage.width, height: sourceImage.height))
        .integral
    guard boundedRegion.width > 0,
          boundedRegion.height > 0,
          let croppedImage = sourceImage.cropping(to: boundedRegion) else {
        fputs("screenshot content check region falls outside the image.\n", stderr)
        exit(2)
    }
    image = croppedImage
} else {
    image = sourceImage
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
    fputs("screenshot content check could not create sampling context.\n", stderr)
    exit(2)
}

context.interpolationQuality = .low
context.draw(image, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))

var minimumLuminance = 255
var maximumLuminance = 0
var visiblePixelCount = 0
var opaqueBlackPixelCount = 0
var transparentPixelCount = 0
var luminanceSum = 0.0
var luminanceSquaredSum = 0.0
let gridColumns = 4
let gridRows = 4
var gridCounts = [Int](repeating: 0, count: gridColumns * gridRows)
var gridSums = [Double](repeating: 0, count: gridColumns * gridRows)
var gridSquaredSums = [Double](repeating: 0, count: gridColumns * gridRows)

for offset in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
    let alpha = Int(pixels[offset + 3])
    guard alpha > 16 else {
        transparentPixelCount += 1
        continue
    }

    let red = Int(pixels[offset])
    let green = Int(pixels[offset + 1])
    let blue = Int(pixels[offset + 2])
    let luminance = (red * 2_126 + green * 7_152 + blue * 722) / 10_000

    minimumLuminance = min(minimumLuminance, luminance)
    maximumLuminance = max(maximumLuminance, luminance)
    luminanceSum += Double(luminance)
    luminanceSquaredSum += Double(luminance * luminance)
    let pixelIndex = offset / bytesPerPixel
    let pixelX = pixelIndex % sampleWidth
    let pixelY = pixelIndex / sampleWidth
    let gridX = min(gridColumns - 1, pixelX * gridColumns / sampleWidth)
    let gridY = min(gridRows - 1, pixelY * gridRows / sampleHeight)
    let gridIndex = gridY * gridColumns + gridX
    gridCounts[gridIndex] += 1
    gridSums[gridIndex] += Double(luminance)
    gridSquaredSums[gridIndex] += Double(luminance * luminance)
    visiblePixelCount += 1
    if red <= 4, green <= 4, blue <= 4 {
        opaqueBlackPixelCount += 1
    }
}

if ProcessInfo.processInfo.environment["SUISUI_UI_EVIDENCE_CONTENT_DIAGNOSTICS"] == "1" {
    fputs(
        "content diagnostics: visible=\(visiblePixelCount) transparent=\(transparentPixelCount) opaqueBlack=\(opaqueBlackPixelCount) total=\(sampleWidth * sampleHeight)\n",
        stderr
    )
    for index in gridCounts.indices where gridCounts[index] > 0 {
        let mean = gridSums[index] / Double(gridCounts[index])
        let variance = max(0, gridSquaredSums[index] / Double(gridCounts[index]) - mean * mean)
        fputs("grid[\(index / gridColumns),\(index % gridColumns)]: mean=\(mean) variance=\(variance)\n", stderr)
    }
}

let minimumVisiblePixels = max(1, (sampleWidth * sampleHeight) / 20)
guard visiblePixelCount >= minimumVisiblePixels else {
    fputs("Screenshot appears blank or too low contrast: \(imagePath)\n", stderr)
    exit(1)
}

if ProcessInfo.processInfo.environment["SUISUI_UI_EVIDENCE_ALLOW_DESKTOP_BACKGROUND"] != "1" {
    // These checks apply to owned, shadowless window evidence. The runner
    // capability probe captures the whole desktop, where a black wallpaper is
    // valid and must not be mistaken for an incompletely composed app window.
    if transparentPixelCount * 100 > sampleWidth * sampleHeight * 5 {
        fputs("Screenshot contains large transparent regions: \(imagePath)\n", stderr)
        exit(1)
    }

    // A headless macOS compositor can transiently publish an otherwise valid
    // window with large, opaque-black layer holes. Dark appearance uses tinted
    // surfaces rather than pure black, so this catches incomplete composition
    // without rejecting the intentional dark theme.
    if opaqueBlackPixelCount * 100 > visiblePixelCount * 15 {
        fputs("Screenshot contains large opaque-black regions: \(imagePath)\n", stderr)
        exit(1)
    }
}

let luminanceRange = maximumLuminance - minimumLuminance
if luminanceRange < 12 {
    fputs("Screenshot appears blank or too low contrast: \(imagePath)\n", stderr)
    exit(1)
}

let meanLuminance = luminanceSum / Double(visiblePixelCount)
let luminanceVariance = max(
    0,
    (luminanceSquaredSum / Double(visiblePixelCount)) - (meanLuminance * meanLuminance)
)
guard luminanceVariance >= 4 else {
    fputs("Screenshot appears uniformly composed without visible UI variance: \(imagePath)\n", stderr)
    exit(1)
}
