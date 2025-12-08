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

            // Collect all values until next -- or end of array
            var values: [String] = []
            i += 1
            
            while i < macros.count {
                let value = macros[i]
                
                // If it starts with --, we've reached the next macro
                if value.hasPrefix("--") {
                    break
                }
                
                // Single dash is invalid
                if value.hasPrefix("-") && !value.hasPrefix("--") {
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

            result.append(EggMacro(macro: normalizedMacro, values: values))
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

    var errorDescription: String? {
        switch self {
        case .missingDoubleDash(let macro):
            return "Macro must start with '--': \(macro)"
        case .singleDashNotAllowed(let macro):
            return "Macro must start with '--', not '-': \(macro)"
        case .emptyMacroName:
            return "Macro name cannot be empty"
        case .missingContent(let macro):
            return "Macro '\(macro)' requires at least one value"
        }
    }
}

package struct EggMacro: Equatable {
    let macro: String
    let values: [String]
}
