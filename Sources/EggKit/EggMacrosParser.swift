import Foundation

struct EggMacrosParser {
    func parse(_ macros: [String]) throws -> [EggMacro] {
        var result: [EggMacro] = []
        var i = 0

        while i < macros.count {
            let current = macros[i]

            // Check if it has only one dash (invalid)
            if current.hasPrefix("-") && !current.hasPrefix("--") {
                throw MacrosParseError.singleDashNotAllowed(macro: current)
            }

            // Check if current element starts with --
            guard current.hasPrefix("--") else {
                throw MacrosParseError.missingDoubleDash(macro: current)
            }

            // Extract macro name (remove --)
            let macroName = String(current.dropFirst(2))
            guard !macroName.isEmpty else {
                throw MacrosParseError.emptyMacroName
            }

            // Check if next element exists
            guard i + 1 < macros.count else {
                throw MacrosParseError.missingContent(macro: current)
            }

            i += 1
            let content = macros[i]

            // Content must not start with --
            guard !content.hasPrefix("--") else {
                throw MacrosParseError.contentStartsWithDoubleDash(macro: current, content: content)
            }

            // Check if next element is also not starting with -- (consecutive content)
            if i + 1 < macros.count && !macros[i + 1].hasPrefix("--") {
                throw MacrosParseError.consecutiveContentValues(first: content, second: macros[i + 1])
            }

            // Convert macro name to uppercase with underscores
            let normalizedMacro = normalize(macroName: macroName)

            result.append(EggMacro(macro: normalizedMacro, content: content))
            i += 1
        }

        return result
    }

    private func normalize(macroName: String) -> String {
        macroName
            .replacingOccurrences(of: "-", with: "_")
            .uppercased()
    }
}

enum MacrosParseError: Error, LocalizedError, Equatable {
    case missingDoubleDash(macro: String)
    case singleDashNotAllowed(macro: String)
    case emptyMacroName
    case missingContent(macro: String)
    case contentStartsWithDoubleDash(macro: String, content: String)
    case consecutiveContentValues(first: String, second: String)

    var errorDescription: String? {
        switch self {
        case .missingDoubleDash(let macro):
            return "Macro must start with '--': \(macro)"
        case .singleDashNotAllowed(let macro):
            return "Macro must start with '--', not '-': \(macro)"
        case .emptyMacroName:
            return "Macro name cannot be empty"
        case .missingContent(let macro):
            return "Macro '\(macro)' requires a content value"
        case .contentStartsWithDoubleDash(let macro, let content):
            return "Content for macro '\(macro)' cannot start with '--': \(content)"
        case .consecutiveContentValues(let first, let second):
            return "Consecutive content values are not allowed: '\(first)' followed by '\(second)'"
        }
    }
}

package struct EggMacro: Equatable {
    let macro: String
    let content: String
}
