import Foundation

struct ParsedMacroDefinitionValidator {
    let config: Config
    let workingDirectory: URL
    let homeDirectory: URL

    func validate(_ parsedMacroDefinitions: [ParsedMacroDefinition]) throws -> [ResolvedMacro] {
        let providedMacroNames = Set(parsedMacroDefinitions.map { $0.macro })

        let allResults = validateProvidedMacros(parsedMacroDefinitions)
            + validateMissingMacrosWithDefaults(providedMacroNames: providedMacroNames)
            + validateMissingRequiredMacros(providedMacroNames: providedMacroNames)

        try throwIfErrors(allResults)

        return extractResolvedMacros(from: allResults)
    }

    private func validateProvidedMacros(_ parsedMacroDefinitions: [ParsedMacroDefinition]) -> [Result<ResolvedMacro, Error>] {
        parsedMacroDefinitions.map { validate($0, isFromDefault: false) }
    }

    private func validateMissingMacrosWithDefaults(providedMacroNames: Set<String>) -> [Result<ResolvedMacro, Error>] {
        (config.macros ?? [])
            .filter { configMacro in
                configMacro.default != nil && !providedMacroNames.contains(configMacro.name)
            }
            .map { configMacro in
                validateMacroWithDefault(configMacro)
            }
    }

    private func validateMissingRequiredMacros(providedMacroNames: Set<String>) -> [Result<ResolvedMacro, Error>] {
        (config.macros ?? [])
            .filter { configMacro in
                configMacro.default == nil && !providedMacroNames.contains(configMacro.name)
            }
            .map { configMacro in
                Result<ResolvedMacro, Error>.failure(.requiredMacroNotProvided(macro: configMacro.name))
            }
    }

    private func throwIfErrors(_ results: [Result<ResolvedMacro, Error>]) throws {
        let errors = results.compactMap { result -> Error? in
            if case let .failure(error) = result {
                return error
            }
            return nil
        }

        if !errors.isEmpty {
            throw CombinedError(
                errors: errors,
                errorMessageModifier: { "⛔️ \($0)" }
            )
        }
    }

    private func extractResolvedMacros(from results: [Result<ResolvedMacro, Error>]) -> [ResolvedMacro] {
        results.compactMap { result -> ResolvedMacro? in
            if case let .success(resolved) = result {
                return resolved
            }
            return nil
        }
    }

    private func validate(
        _ parsedMacroDefinition: ParsedMacroDefinition,
        isFromDefault _: Bool
    ) -> Result<ResolvedMacro, Error> {
        // Find the macro definition in config
        guard let configMacro = findConfigMacro(for: parsedMacroDefinition) else {
            return .failure(.unknownMacro(macro: parsedMacroDefinition.macro))
        }

        // Use provided values (no default resolution here since defaults are handled separately)
        let resolvedValues = parsedMacroDefinition.values

        return validateAndResolve(
            values: resolvedValues,
            configMacro: configMacro,
            macroName: parsedMacroDefinition.macro
        )
    }

    private func validateMacroWithDefault(_ configMacro: Config.Macro) -> Result<ResolvedMacro, Error> {
        guard let defaultValue = configMacro.default else {
            return .failure(.missingDefaultValue(macro: configMacro.name))
        }

        let resolvedValues = [defaultValue]

        return validateAndResolve(
            values: resolvedValues,
            configMacro: configMacro,
            macroName: configMacro.name
        )
    }

    private func validateAndResolve(
        values: [String],
        configMacro: Config.Macro,
        macroName: String
    ) -> Result<ResolvedMacro, Error> {
        // Validate value count
        if let error = validateValueCount(values, configMacro: configMacro, macroName: macroName) {
            return .failure(error)
        }

        // Validate choice type
        if let error = validateChoice(values, configMacro: configMacro, macroName: macroName) {
            return .failure(error)
        }

        // Validate regex pattern
        if let error = validateRegex(values, configMacro: configMacro, macroName: macroName) {
            return .failure(error)
        }

        // Convert to ResolvedMacro.Value
        guard let resolvedValue = convertToResolvedValue(values, configMacro: configMacro, macroName: macroName) else {
            return .failure(.conversionFailed(macro: macroName, type: configMacro.type))
        }

        let resolvedMacro = ResolvedMacro(
            name: macroName,
            description: configMacro.description,
            value: resolvedValue
        )

        return .success(resolvedMacro)
    }

    private func findConfigMacro(for parsedMacroDefinition: ParsedMacroDefinition) -> Config.Macro? {
        config.macros?.first(where: { $0.name == parsedMacroDefinition.macro })
    }

    private func validateValueCount(_ resolvedValues: [String], configMacro: Config.Macro, macroName: String) -> Error? {
        switch configMacro.type {
        case .array:
            // Array type can have one or more values
            if resolvedValues.isEmpty {
                return .arrayRequiresAtLeastOneValue(macro: macroName)
            }
        case .string, .boolean, .choice, .path:
            // Non-array types must have exactly one value
            if resolvedValues.count != 1 {
                return .nonArrayRequiresSingleValue(
                    macro: macroName,
                    type: configMacro.type,
                    actualCount: resolvedValues.count
                )
            }
        }
        return nil
    }

    private func validateChoice(_ resolvedValues: [String], configMacro: Config.Macro, macroName: String) -> Error? {
        guard configMacro.type == .choice else {
            return nil
        }

        guard let choices = configMacro.choices, !choices.isEmpty else {
            return .choiceTypeRequiresChoices(macro: macroName)
        }

        // Use ChoiceValidationRule for validation
        let validationRule = ChoiceValidationRule(
            choices: choices,
            error: "Value not in choices"
        )

        for value in resolvedValues {
            if !validationRule.validate(input: value) {
                return .valueNotInChoices(
                    macro: macroName,
                    value: value,
                    choices: choices
                )
            }
        }

        return nil
    }

    private func validateRegex(_ resolvedValues: [String], configMacro: Config.Macro, macroName: String) -> Error? {
        guard let regexPattern = configMacro.validate else {
            return nil
        }

        // Use RegexPatternValidationRule for validation
        let validationRule = RegexPatternValidationRule(
            pattern: regexPattern,
            error: "Value does not match pattern"
        )

        // Check if the pattern itself is valid
        guard (try? NSRegularExpression(pattern: regexPattern)) != nil else {
            return .invalidRegexPattern(macro: macroName, pattern: regexPattern)
        }

        for value in resolvedValues {
            if !validationRule.validate(input: value) {
                return .valueDoesNotMatchRegex(
                    macro: macroName,
                    value: value,
                    pattern: regexPattern
                )
            }
        }

        return nil
    }

    private func convertToResolvedValue(_ resolvedValues: [String], configMacro: Config.Macro, macroName _: String) -> ResolvedMacro.Value? {
        switch configMacro.type {
        case .string:
            guard let value = resolvedValues.first else { return nil }
            return .string(value)

        case .boolean:
            guard let value = resolvedValues.first else { return nil }
            if value.lowercased() == "true" {
                return .boolean(true)
            } else if value.lowercased() == "false" {
                return .boolean(false)
            }
            return nil

        case .choice:
            guard let value = resolvedValues.first else { return nil }
            return .choice(value)

        case .array:
            return .array(resolvedValues)

        case .path:
            guard let value = resolvedValues.first, !value.isEmpty else { return nil }

            guard let absolutePath = try? resolveToAbsoluteURL(
                value,
                workingDirectory: workingDirectory,
                homeDirectory: homeDirectory
            ) else {
                return nil
            }

            return .path(absolutePath)
        }
    }

    enum Error: LocalizedError, Equatable {
        case unknownMacro(macro: String)
        case arrayRequiresAtLeastOneValue(macro: String)
        case nonArrayRequiresSingleValue(macro: String, type: Config.MacroType, actualCount: Int)
        case choiceTypeRequiresChoices(macro: String)
        case valueNotInChoices(macro: String, value: String, choices: [String])
        case invalidRegexPattern(macro: String, pattern: String)
        case valueDoesNotMatchRegex(macro: String, value: String, pattern: String)
        case conversionFailed(macro: String, type: Config.MacroType)
        case missingDefaultValue(macro: String)
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
            case let .conversionFailed(macro, type):
                "Failed to convert value for macro '\(macro)' to type '\(type.rawValue)'"
            case let .missingDefaultValue(macro):
                "Macro '\(macro)' is expected to have a default value but none is defined."
            case let .requiredMacroNotProvided(macro):
                "Required macro '\(macro)' was not provided. This macro has no default value and must be specified."
            }
        }
    }
}
