import Foundation

struct MacrosParser {
    /// Macro definitions from config for type-aware parsing
    private let macroDefinitions: [Config.Macro]

    init(macroDefinitions: [Config.Macro] = []) {
        self.macroDefinitions = macroDefinitions
    }

    /// Parses command line arguments into macro definitions.
    ///
    /// Converts CLI arguments in the format `["--name", "value", "--age", "25"]`
    /// into normalized macro definitions with `___UPPER_CASE___` format.
    ///
    /// Boolean macros support special syntax:
    /// - `--flag` sets the value to "true"
    /// - `--no-flag` sets the value to "false"
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

            // Convert macro name to normalized format
            let normalizedMacro = MacroNameConverter.flagToMacro(macroName)

            // Check if this is a boolean macro (direct match)
            let isBooleanMacro = macroDefinitions.contains {
                $0.name == normalizedMacro && $0.type == .boolean
            }

            if isBooleanMacro {
                // Boolean macro without negation: value is true
                result.append(ParsedMacroDefinition(macro: normalizedMacro, values: ["true"]))
                i += 1
                continue
            }

            // Check for --no- prefix (boolean negation)
            // e.g., --no-create-tests → ___CREATE_TESTS___ = false
            // Only if --no-xxx doesn't match a macro named ___NO_XXX___
            if macroName.hasPrefix("no-") {
                let negatedName = String(macroName.dropFirst(3))
                let negatedNormalizedMacro = MacroNameConverter.flagToMacro(negatedName)

                let isNegatedBooleanMacro = macroDefinitions.contains {
                    $0.name == negatedNormalizedMacro && $0.type == .boolean
                }

                if isNegatedBooleanMacro {
                    // Boolean macro with negation: value is false
                    result.append(ParsedMacroDefinition(macro: negatedNormalizedMacro, values: ["false"]))
                    i += 1
                    continue
                }
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

            result.append(ParsedMacroDefinition(macro: normalizedMacro, values: values))
        }

        return result
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
