import CoreGraphics
import Foundation
import ImageIO

guard CommandLine.arguments.count == 2 else {
    fputs("screenshot content check requires an image path.\n", stderr)
    exit(2)
}

let imagePath = CommandLine.arguments[1]
let imageURL = URL(fileURLWithPath: imagePath)

guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fputs("screenshot content check could not read image: \(imagePath)\n", stderr)
    exit(2)
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
    visiblePixelCount += 1
    if red <= 4, green <= 4, blue <= 4 {
        opaqueBlackPixelCount += 1
    }
}

if ProcessInfo.processInfo.environment["SOLOPM_UI_EVIDENCE_CONTENT_DIAGNOSTICS"] == "1" {
    fputs(
        "content diagnostics: visible=\(visiblePixelCount) transparent=\(transparentPixelCount) opaqueBlack=\(opaqueBlackPixelCount) total=\(sampleWidth * sampleHeight)\n",
        stderr
    )
}

let minimumVisiblePixels = max(1, (sampleWidth * sampleHeight) / 20)
guard visiblePixelCount >= minimumVisiblePixels else {
    fputs("Screenshot appears blank or too low contrast: \(imagePath)\n", stderr)
    exit(1)
}

// A shadowless window raster should be opaque across the logical viewport.
// Large transparent holes render as black in common artifact viewers and mean
// the compositor published only part of the window surface.
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

let luminanceRange = maximumLuminance - minimumLuminance
if luminanceRange < 12 {
    fputs("Screenshot appears blank or too low contrast: \(imagePath)\n", stderr)
    exit(1)
}
