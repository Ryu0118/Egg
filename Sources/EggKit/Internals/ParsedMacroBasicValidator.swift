import Foundation
import Path

/// Performs basic validation of parsed macro definitions without path resolution.
///
/// This validator checks:
/// - All provided macros are defined in the config
/// - Required macros (without defaults) are provided
/// - Value counts match the macro type
/// - Choice values are valid
/// - Regex patterns match
///
/// Path resolution is NOT performed here. Use `ParsedMacroDefinitionValidator` for
/// full validation and resolution when the working directory is known.
struct ParsedMacroBasicValidator {
    let config: Config

    /// Validates parsed macro definitions without resolving paths.
    ///
    /// - Parameter parsedMacroDefinitions: The parsed macro definitions to validate
    /// - Throws: `CombinedError` containing all validation errors
    func validate(_ parsedMacroDefinitions: [ParsedMacroDefinition]) throws {
        let providedMacroNames = Set(parsedMacroDefinitions.map(\.macro))

        var errors: [Error] = []

        // Validate provided macros
        for parsed in parsedMacroDefinitions {
            if let error = validateBasic(parsed) {
                errors.append(error)
            }
        }

        // Check for missing required macros (those without defaults)
        for configMacro in config.macros ?? [] where configMacro.default == nil && !providedMacroNames.contains(configMacro.name) {
            errors.append(.requiredMacroNotProvided(macro: configMacro.name))
        }

        if !errors.isEmpty {
            throw CombinedError(
                errors: errors,
                errorMessageModifier: { "⛔️ \($0)" }
            )
        }
    }

    private func validateBasic(_ parsed: ParsedMacroDefinition) -> Error? {
        // Check if macro exists in config
        guard let configMacro = config.macros?.first(where: { $0.name == parsed.macro }) else {
            return .unknownMacro(macro: parsed.macro)
        }

        // Validate value count
        if let error = validateValueCount(parsed.values, configMacro: configMacro, macroName: parsed.macro) {
            return error
        }

        // Validate choice type
        if let error = validateChoice(parsed.values, configMacro: configMacro, macroName: parsed.macro) {
            return error
        }

        // Validate regex pattern (for non-path types)
        if configMacro.type != .path, let error = validateRegex(parsed.values, configMacro: configMacro, macroName: parsed.macro) {
            return error
        }

        // Validate boolean format
        if configMacro.type == .boolean, let error = validateBooleanFormat(parsed.values, macroName: parsed.macro) {
            return error
        }

        return nil
    }

    private func validateValueCount(_ values: [String], configMacro: Config.Macro, macroName: String) -> Error? {
        switch configMacro.type {
        case .array:
            if values.isEmpty {
                return .arrayRequiresAtLeastOneValue(macro: macroName)
            }
        case .string, .boolean, .choice, .path:
            if values.count != 1 {
                return .nonArrayRequiresSingleValue(
                    macro: macroName,
                    type: configMacro.type,
                    actualCount: values.count
                )
            }
        }
        return nil
    }

    private func validateChoice(_ values: [String], configMacro: Config.Macro, macroName: String) -> Error? {
        guard configMacro.type == .choice else { return nil }

        guard let choices = configMacro.choices, !choices.isEmpty else {
            return .choiceTypeRequiresChoices(macro: macroName)
        }

        let validationRule = ChoiceValidationRule(choices: choices, error: "Value not in choices")

        for value in values {
            if !validationRule.validate(input: value) {
                return .valueNotInChoices(macro: macroName, value: value, choices: choices)
            }
        }

        return nil
    }

    private func validateRegex(_ values: [String], configMacro: Config.Macro, macroName: String) -> Error? {
        guard let regexPattern = configMacro.validate else { return nil }

        guard (try? NSRegularExpression(pattern: regexPattern)) != nil else {
            return .invalidRegexPattern(macro: macroName, pattern: regexPattern)
        }

        let validationRule = RegexPatternValidationRule(pattern: regexPattern, error: "Value does not match pattern")

        for value in values {
            if !validationRule.validate(input: value) {
                return .valueDoesNotMatchRegex(macro: macroName, value: value, pattern: regexPattern)
            }
        }

        return nil
    }

    private func validateBooleanFormat(_ values: [String], macroName: String) -> Error? {
        guard let value = values.first else { return nil }

        let lowercased = value.lowercased()
        if lowercased != "true", lowercased != "false" {
            return .invalidBooleanValue(macro: macroName, value: value)
        }

        return nil
    }

    enum Error: LocalizedError, Equatable {
        case unknownMacro(macro: String)
        case arrayRequiresAtLeastOneValue(macro: String)
        case nonArrayRequiresSingleValue(macro: String, type: Config.MacroType, actualCount: Int)
        case choiceTypeRequiresChoices(macro: String)
        case valueNotInChoices(macro: String, value: String, choices: [String])
        case invalidRegexPattern(macro: String, pattern: String)
        case valueDoesNotMatchRegex(macro: String, value: String, pattern: String)
        case invalidBooleanValue(macro: String, value: String)
        case requiredMacroNotProvided(macro: String)

        var errorDescription: String? {
            switch self {
            case let .unknownMacro(macro):
                "Unknown macro: '\(macro)'. This macro is not defined in the template configuration."
            case let .arrayRequiresAtLeastOneValue(macro):
                "Macro '\(macro)' is of type 'array' and requires at least one value."
            case let .nonArrayRequiresSingleValue(macro, type, actualCount):
                "Macro '\(macro)' is of type '\(type.rawValue)' and requires exactly one value, but \(actualCount) values were provided."
            case let .choiceTypeRequiresChoices(macro):
                "Macro '\(macro)' is of type 'choice' but no choices are defined in the configuration."
            case let .valueNotInChoices(macro, value, choices):
                "Value '\(value)' for macro '\(macro)' is not in the allowed choices: \(choices.joined(separator: ", "))"
            case let .invalidRegexPattern(macro, pattern):
                "Macro '\(macro)' has an invalid regex pattern: '\(pattern)'"
            case let .valueDoesNotMatchRegex(macro, value, pattern):
                "Value '\(value)' for macro '\(macro)' does not match the required pattern: '\(pattern)'"
            case let .invalidBooleanValue(macro, value):
                "Value '\(value)' for macro '\(macro)' is not a valid boolean. Use 'true' or 'false'."
            case let .requiredMacroNotProvided(macro):
                "Required macro '\(macro)' was not provided. This macro has no default value and must be specified."
            }
        }
    }
}
