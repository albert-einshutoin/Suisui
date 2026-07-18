import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Window content size requires a diagnostic file path.\n", stderr)
    exit(2)
}

let path = CommandLine.arguments[1]
guard let payload = try? String(contentsOfFile: path, encoding: .utf8) else {
    fputs("Window content size diagnostic is unavailable.\n", stderr)
    exit(1)
}

let components = payload.split(whereSeparator: \.isWhitespace)
guard components.count == 2,
      Int(components[0]) != nil,
      Int(components[1]) != nil else {
    fputs("Window content size diagnostic is malformed.\n", stderr)
    exit(1)
}

print("\(components[0]) \(components[1])")
