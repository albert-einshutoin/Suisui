import CoreGraphics
import Foundation
import ImageIO

guard CommandLine.arguments.count == 3 else {
    fputs("appearance check requires an image path and light or dark expectation.\n", stderr)
    exit(2)
}

let imagePath = CommandLine.arguments[1]
let expectedAppearance = CommandLine.arguments[2]
guard expectedAppearance == "light" || expectedAppearance == "dark" else {
    fputs("appearance check expectation must be light or dark.\n", stderr)
    exit(2)
}

let imageURL = URL(fileURLWithPath: imagePath)
guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fputs("appearance check could not read image: \(imagePath)\n", stderr)
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
    fputs("appearance check could not create sampling context.\n", stderr)
    exit(2)
}

context.interpolationQuality = .low
context.draw(image, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))

var luminanceSum = 0.0
var visiblePixelCount = 0
for offset in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
    guard pixels[offset + 3] > 16 else { continue }
    let red = Double(pixels[offset])
    let green = Double(pixels[offset + 1])
    let blue = Double(pixels[offset + 2])
    luminanceSum += red * 0.2126 + green * 0.7152 + blue * 0.0722
    visiblePixelCount += 1
}

guard visiblePixelCount > 0 else {
    fputs("appearance check found no visible pixels: \(imagePath)\n", stderr)
    exit(2)
}

let meanLuminance = luminanceSum / Double(visiblePixelCount)
let actualAppearance = meanLuminance >= 127.5 ? "light" : "dark"
let formattedMeanLuminance = String(format: "%.2f", meanLuminance)
guard actualAppearance == expectedAppearance else {
    fputs(
        "appearance mismatch: expected \(expectedAppearance), observed \(actualAppearance), mean luminance \(formattedMeanLuminance): \(imagePath)\n",
        stderr
    )
    exit(1)
}

print("OK: \(expectedAppearance) appearance (mean luminance \(formattedMeanLuminance))")
