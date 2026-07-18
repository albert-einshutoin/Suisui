import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 3,
      let x = Double(CommandLine.arguments[1]),
      let y = Double(CommandLine.arguments[2]) else {
    FileHandle.standardError.write(Data("usage: ui_evidence_pointer_park <x> <y>\n".utf8))
    exit(2)
}

// Screenshot windows are deliberately repositioned to canonical bounds. Park
// the pointer outside those bounds so an unrelated host cursor position cannot
// turn a baseline into a hover-state capture or rebuild a repeated SwiftUI row.
CGWarpMouseCursorPosition(CGPoint(x: x, y: y))
CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
