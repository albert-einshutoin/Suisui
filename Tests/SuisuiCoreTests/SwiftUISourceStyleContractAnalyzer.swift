import Foundation

/// Lightweight Swift source scanner used only by source-contract tests.
/// It balances delimiters and skips comments/string literals so formatting or
/// multiline modifier arguments cannot bypass Calm Signal Desk guardrails.
enum SwiftUISourceStyleContractAnalyzer {
    private static let surfaceModifierNames: Set<String> = [
        "background",
        "fill",
        "backgroundStyle",
        "containerBackground",
        "presentationBackground"
    ]

    static func disallowedSurfaceModifiers(
        in source: String,
        allowedExpressionMarkers: [String]
    ) -> [String] {
        let allowed = allowedExpressionMarkers.map(normalize)

        return modifierCalls(in: source, names: surfaceModifierNames)
            .map(\.expression)
            .filter { expression in
                let normalized = normalize(expression)
                return containsForbiddenSurfaceConstruct(normalized)
                    || !allowed.contains { normalized.contains($0) }
            }
    }

    static func rawStyleViolations(in source: String) -> [String] {
        let code = codeWithoutCommentsOrStrings(source)
        let patterns = [
            #"\.(red|orange|green)\b"#,
            #"cornerRadius\s*:\s*(?:\d|\.\d)"#
        ]

        return patterns.flatMap { pattern -> [String] in
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return []
            }
            let range = NSRange(code.startIndex..<code.endIndex, in: code)
            return regex.matches(in: code, range: range).compactMap { match in
                guard let matchRange = Range(match.range, in: code) else {
                    return nil
                }
                return String(code[matchRange])
            }
        }
    }

    static func nativeRootStyleViolations(
        in source: String,
        rootType: String,
        allowedNonvisualBackgroundMarkers: [String] = []
    ) -> [String] {
        let characters = Array(source)
        guard let rootStart = firstCodeOccurrence(of: rootType, in: characters),
              let openingBrace = firstCodeCharacter("{", after: rootStart + rootType.count, in: characters),
              var rootEnd = balancedEnd(startingAt: openingBrace, in: characters) else {
            return ["Missing native root \(rootType)"]
        }

        // NavigationSplitView and similar native containers may have labeled
        // trailing closures. Consume each closure before inspecting the root's
        // own modifier chain.
        while let trailingClosure = trailingClosureStart(after: rootEnd, in: characters),
              let trailingEnd = balancedEnd(startingAt: trailingClosure, in: characters) {
            rootEnd = trailingEnd
        }

        let rootIndent = indentationBefore(index: rootStart, in: characters)
        let bodyEnd = enclosingBodyEnd(after: rootEnd, rootIndent: rootIndent, in: characters)
        let suffix = String(characters[rootEnd..<bodyEnd])
        let suffixCharacters = Array(suffix)
        let calls = modifierCalls(in: suffix, names: surfaceModifierNames)
        let allowedBackgrounds = allowedNonvisualBackgroundMarkers.map(normalize)

        return calls.compactMap { call in
            guard indentationBefore(index: call.offset, in: suffixCharacters) == rootIndent else {
                return nil
            }
            let normalized = normalize(call.expression)
            let explicitlyNonvisual = call.name == "background"
                && allowedBackgrounds.contains { normalized.contains($0) }
            return explicitlyNonvisual ? nil : call.expression
        }
    }

    private struct ModifierCall {
        let offset: Int
        let name: String
        let expression: String
    }

    private static func modifierCalls(in source: String, names: Set<String>?) -> [ModifierCall] {
        let characters = Array(source)
        var calls: [ModifierCall] = []
        var index = 0

        while index < characters.count {
            if let skipped = triviaOrLiteralEnd(startingAt: index, in: characters) {
                index = skipped
                continue
            }
            guard characters[index] == "." else {
                index += 1
                continue
            }

            let nameStart = index + 1
            var cursor = nameStart
            while cursor < characters.count, isIdentifierCharacter(characters[cursor]) {
                cursor += 1
            }
            let name = String(characters[nameStart..<cursor])
            guard !name.isEmpty, names == nil || names?.contains(name) == true else {
                index += 1
                continue
            }

            cursor = skipWhitespace(from: cursor, in: characters)
            guard cursor < characters.count,
                  characters[cursor] == "(" || characters[cursor] == "{",
                  let end = balancedEnd(startingAt: cursor, in: characters) else {
                index += 1
                continue
            }

            calls.append(
                ModifierCall(
                    offset: index,
                    name: name,
                    expression: String(characters[index..<end])
                )
            )
            index = end
        }
        return calls
    }

    private static func normalize(_ source: String) -> String {
        codeWithoutCommentsOrStrings(source)
            .filter { !$0.isWhitespace }
    }

    private static func containsForbiddenSurfaceConstruct(_ normalized: String) -> Bool {
        let alwaysForbidden = [
            "Material",
            ".thinMaterial",
            ".regularMaterial",
            ".thickMaterial",
            ".ultraThinMaterial",
            "Gradient(",
            ".quaternary"
        ]
        if alwaysForbidden.contains(where: normalized.contains) {
            return true
        }
        return normalized.contains("Color.") && normalized.contains(".opacity(")
    }

    private static func codeWithoutCommentsOrStrings(_ source: String) -> String {
        let characters = Array(source)
        var output: [Character] = []
        var index = 0

        while index < characters.count {
            if let end = commentEnd(startingAt: index, in: characters) {
                output.append(contentsOf: repeatElement(" ", count: end - index))
                index = end
                continue
            }
            if let end = stringLiteralEnd(startingAt: index, in: characters) {
                output.append(contentsOf: repeatElement(" ", count: end - index))
                index = end
                continue
            }
            output.append(characters[index])
            index += 1
        }
        return String(output)
    }

    private static func balancedEnd(startingAt start: Int, in characters: [Character]) -> Int? {
        let pairs: [Character: Character] = ["(": ")", "[": "]", "{": "}"]
        guard let expectedClose = pairs[characters[start]] else {
            return nil
        }
        var stack = [expectedClose]
        var index = start + 1

        while index < characters.count {
            if let skipped = triviaOrLiteralEnd(startingAt: index, in: characters) {
                index = skipped
                continue
            }
            if let close = pairs[characters[index]] {
                stack.append(close)
            } else if characters[index] == stack.last {
                stack.removeLast()
                if stack.isEmpty {
                    return index + 1
                }
            }
            index += 1
        }
        return nil
    }

    private static func firstCodeOccurrence(of needle: String, in characters: [Character]) -> Int? {
        let target = Array(needle)
        var index = 0
        while index + target.count <= characters.count {
            if let skipped = triviaOrLiteralEnd(startingAt: index, in: characters) {
                index = skipped
                continue
            }
            let hasIdentifierBoundaryBefore = index == 0 || !isIdentifierCharacter(characters[index - 1])
            let end = index + target.count
            let hasIdentifierBoundaryAfter = end == characters.count || !isIdentifierCharacter(characters[end])
            if hasIdentifierBoundaryBefore,
               hasIdentifierBoundaryAfter,
               Array(characters[index..<end]) == target {
                return index
            }
            index += 1
        }
        return nil
    }

    private static func firstCodeCharacter(
        _ character: Character,
        after start: Int,
        in characters: [Character]
    ) -> Int? {
        var index = start
        var parenthesisDepth = 0
        while index < characters.count {
            if let skipped = triviaOrLiteralEnd(startingAt: index, in: characters) {
                index = skipped
                continue
            }
            if characters[index] == "(" {
                parenthesisDepth += 1
            } else if characters[index] == ")" {
                parenthesisDepth = max(0, parenthesisDepth - 1)
            } else if characters[index] == character, parenthesisDepth == 0 {
                return index
            }
            index += 1
        }
        return nil
    }

    private static func trailingClosureStart(after end: Int, in characters: [Character]) -> Int? {
        var index = skipWhitespace(from: end, in: characters)
        if index < characters.count, characters[index] == "{" {
            return index
        }

        let labelStart = index
        while index < characters.count, isIdentifierCharacter(characters[index]) {
            index += 1
        }
        guard index > labelStart else {
            return nil
        }
        index = skipWhitespace(from: index, in: characters)
        guard index < characters.count, characters[index] == ":" else {
            return nil
        }
        index = skipWhitespace(from: index + 1, in: characters)
        return index < characters.count && characters[index] == "{" ? index : nil
    }

    private static func enclosingBodyEnd(
        after start: Int,
        rootIndent: Int,
        in characters: [Character]
    ) -> Int {
        var lineStart = start
        while lineStart < characters.count {
            while lineStart < characters.count, characters[lineStart] != "\n" {
                lineStart += 1
            }
            lineStart += lineStart < characters.count ? 1 : 0
            let contentStart = skipHorizontalWhitespace(from: lineStart, in: characters)
            let indent = contentStart - lineStart
            if indent < rootIndent, contentStart < characters.count, characters[contentStart] == "}" {
                return lineStart
            }
        }
        return characters.count
    }

    private static func indentationBefore(index: Int, in characters: [Character]) -> Int {
        var lineStart = index
        while lineStart > 0, characters[lineStart - 1] != "\n" {
            lineStart -= 1
        }
        return skipHorizontalWhitespace(from: lineStart, in: characters) - lineStart
    }

    private static func triviaOrLiteralEnd(startingAt index: Int, in characters: [Character]) -> Int? {
        commentEnd(startingAt: index, in: characters)
            ?? stringLiteralEnd(startingAt: index, in: characters)
    }

    private static func commentEnd(startingAt index: Int, in characters: [Character]) -> Int? {
        guard index + 1 < characters.count, characters[index] == "/" else {
            return nil
        }
        if characters[index + 1] == "/" {
            var cursor = index + 2
            while cursor < characters.count, characters[cursor] != "\n" {
                cursor += 1
            }
            return cursor
        }
        guard characters[index + 1] == "*" else {
            return nil
        }
        var depth = 1
        var cursor = index + 2
        while cursor + 1 < characters.count {
            if characters[cursor] == "/", characters[cursor + 1] == "*" {
                depth += 1
                cursor += 2
            } else if characters[cursor] == "*", characters[cursor + 1] == "/" {
                depth -= 1
                cursor += 2
                if depth == 0 {
                    return cursor
                }
            } else {
                cursor += 1
            }
        }
        return characters.count
    }

    private static func stringLiteralEnd(startingAt index: Int, in characters: [Character]) -> Int? {
        guard characters[index] == "\"" else {
            return nil
        }
        let isMultiline = index + 2 < characters.count
            && characters[index + 1] == "\""
            && characters[index + 2] == "\""
        var cursor = index + (isMultiline ? 3 : 1)

        while cursor < characters.count {
            if isMultiline,
               cursor + 2 < characters.count,
               characters[cursor] == "\"",
               characters[cursor + 1] == "\"",
               characters[cursor + 2] == "\"" {
                return cursor + 3
            }
            if !isMultiline, characters[cursor] == "\"", !isEscaped(cursor, in: characters) {
                return cursor + 1
            }
            cursor += 1
        }
        return characters.count
    }

    private static func isEscaped(_ index: Int, in characters: [Character]) -> Bool {
        var slashCount = 0
        var cursor = index
        while cursor > 0, characters[cursor - 1] == "\\" {
            slashCount += 1
            cursor -= 1
        }
        return slashCount.isMultiple(of: 2) == false
    }

    private static func skipWhitespace(from start: Int, in characters: [Character]) -> Int {
        var index = start
        while index < characters.count, characters[index].isWhitespace {
            index += 1
        }
        return index
    }

    private static func skipHorizontalWhitespace(from start: Int, in characters: [Character]) -> Int {
        var index = start
        while index < characters.count, characters[index] == " " || characters[index] == "\t" {
            index += 1
        }
        return index
    }

    private static func isIdentifierCharacter(_ character: Character) -> Bool {
        character == "_" || character.isLetter || character.isNumber
    }
}
