import Foundation

struct MacrosParser {
    /// Parses command line arguments into macro definitions.
    ///
    /// Converts CLI arguments in the format `["--name", "value", "--age", "25"]`
    /// into normalized macro definitions with `___UPPER_CASE___` format.
    ///
    /// - Parameter commandLineArguments: Array of CLI arguments starting with `--` prefix
    /// - Returns: Array of parsed and normalized `ParsedMacroDefinition` instances
    /// - Throws: `MacrosParseError` if arguments are malformed
    func parseCommandLineArguments(_ commandLineArguments: [String]) throws -> [ParsedMacroDefinition] {
        var result: [ParsedMacroDefinition] = []
        var i = 0

        while i < commandLineArguments.count {
            let current = commandLineArguments[i]

            // Check if it has only one dash (invalid)
            if current.hasPrefix("-"), !current.hasPrefix("--") {
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
            guard i + 1 < commandLineArguments.count else {
                throw MacrosParseError.missingContent(macro: current)
            }

            // Collect all values until next -- or end of array
            var values: [String] = []
            i += 1

            while i < commandLineArguments.count {
                let value = commandLineArguments[i]

                // If it starts with --, we've reached the next macro
                if value.hasPrefix("--") {
                    break
                }

                // Single dash is invalid
                if value.hasPrefix("-"), !value.hasPrefix("--") {
                    throw MacrosParseError.singleDashNotAllowed(macro: value)
                }

                values.append(value)
                i += 1
            }

            // At least one value is required
            guard !values.isEmpty else {
                throw MacrosParseError.missingContent(macro: current)
            }

            // Convert macro name to uppercase with underscores
            let normalizedMacro = normalize(macroName: macroName)

            result.append(ParsedMacroDefinition(macro: normalizedMacro, values: values))
        }

        return result
    }

    private func normalize(macroName: String) -> String {
        let normalized = macroName
            .replacingOccurrences(of: "-", with: "_")
            .uppercased()
        return "___\(normalized)___"
    }
}

enum MacrosParseError: Error, LocalizedError, Equatable {
    case missingDoubleDash(macro: String)
    case singleDashNotAllowed(macro: String)
    case emptyMacroName
    case missingContent(macro: String)

    var errorDescription: String? {
        switch self {
        case let .missingDoubleDash(macro):
            return "Macro must start with '--': \(macro)"
        case let .singleDashNotAllowed(macro):
            return "Macro must start with '--', not '-': \(macro)"
        case .emptyMacroName:
            return "Macro name cannot be empty"
        case let .missingContent(macro):
            return "Macro '\(macro)' requires at least one value"
        }
    }
}
