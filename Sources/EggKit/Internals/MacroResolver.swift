import Foundation
import Interaction

/// Resolves macro definitions into concrete values.
///
/// MacroResolver handles the resolution of `Config.Macro` definitions into `ResolvedMacro` values.
/// For interactive mode, it prompts the user for values. For direct mode, macros should already
/// be resolved and passed through.
///
/// ## Important
/// The `workingDirectory` parameter should be the actual execution directory:
/// - For staging runners: the workspace root directory
/// - For non-staging runners: the real working directory
///
/// This ensures path-type macros resolve correctly relative to the execution context.
package struct MacroResolver {
    private let config: Config
    private let workingDirectory: URL
    private let homeDirectory: URL
    private let interaction: any InteractionProviding

    package init(
        config: Config,
        workingDirectory: URL,
        homeDirectory: URL,
        interaction: some InteractionProviding,
    ) {
        self.config = config
        self.workingDirectory = workingDirectory
        self.homeDirectory = homeDirectory
        self.interaction = interaction
    }

    /// Resolves all macros defined in the config.
    ///
    /// - Returns: Array of resolved macros with concrete values
    package func resolve() async throws -> [ResolvedMacro] {
        guard let macros = config.macros else { return [] }

        var resolvedMacros: [ResolvedMacro] = []

        for macro in macros {
            let resolvedMacro = try await promptForMacro(macro)
            resolvedMacros.append(resolvedMacro)
        }

        return resolvedMacros
    }

    private func promptForMacro(_ macro: Config.Macro) async throws -> ResolvedMacro {
        switch macro.type {
        case .string:
            await promptForString(macro)
        case .boolean:
            promptForBoolean(macro)
        case .choice:
            try promptForChoice(macro)
        case .choices:
            try promptForChoices(macro)
        case .array:
            await promptForArray(macro)
        case .path:
            await promptForPath(macro)
        }
    }

    private func promptForString(_ macro: Config.Macro) async -> ResolvedMacro {
        var validationRules: [ValidationRule] = []

        // Only require non-empty if there's no default value
        if macro.default == nil {
            validationRules.append(
                .nonEmpty(message: "\(macro.name) cannot be empty."),
            )
        }

        if let validatePattern = macro.validate {
            validationRules.append(
                .regexPattern(
                    validatePattern,
                    error: "Value does not match the required pattern: '\(validatePattern)'",
                ),
            )
        }

        // Build prompt message with default value hint
        let promptMessage: String = if let defaultValue = macro.default?.stringValue {
            "\(macro.description) [default: '\(defaultValue)'] (Type '\"\"' for empty string)"
        } else {
            macro.description
        }

        let value = await interaction.textPrompt(
            title: "\(macro.name)",
            prompt: StyledText(promptMessage),
            collapsesOnAnswer: true,
            validationRules: validationRules,
        )

        // Resolve final value
        let finalValue: String = if value == "\"\"" {
            // User explicitly wants empty string
            ""
        } else if value.isEmpty, let defaultValue = macro.default?.stringValue {
            // User pressed Enter with default available
            defaultValue
        } else {
            // User provided a value
            value
        }

        return ResolvedMacro(
            name: macro.name,
            description: macro.description,
            value: .string(finalValue),
        )
    }

    private func promptForBoolean(_ macro: Config.Macro) -> ResolvedMacro {
        let value = interaction.yesOrNoChoicePrompt(
            title: "\(macro.name)",
            question: "\(macro.description)",
        )

        return ResolvedMacro(
            name: macro.name,
            description: macro.description,
            value: .boolean(value),
        )
    }

    private func promptForChoice(_ macro: Config.Macro) throws -> ResolvedMacro {
        guard let choices = macro.choices, !choices.isEmpty else {
            throw Error.choiceTypeRequiresChoices(macro: macro.name)
        }

        let value = interaction.singleChoicePrompt(
            title: "\(macro.name)",
            question: "\(macro.description)",
            options: choices,
        )

        return ResolvedMacro(
            name: macro.name,
            description: macro.description,
            value: .choice(value),
        )
    }

    private func promptForChoices(_ macro: Config.Macro) throws -> ResolvedMacro {
        guard let choices = macro.choices, !choices.isEmpty else {
            throw Error.choiceTypeRequiresChoices(macro: macro.name)
        }

        let values = interaction.multipleChoicePrompt(
            title: "\(macro.name)",
            question: "\(macro.description)",
            options: choices,
        )

        return ResolvedMacro(
            name: macro.name,
            description: macro.description,
            value: .choices(values),
        )
    }

    private func promptForArray(_ macro: Config.Macro) async -> ResolvedMacro {
        // Build validation rules for array elements
        var validationRules: [ValidationRule] = []

        if let validatePattern = macro.validate {
            // Create a custom validation rule that validates each comma-separated element
            validationRules.append(
                .arrayElement(
                    elementPattern: validatePattern,
                    error: "One or more values do not match the required pattern: '\(validatePattern)'",
                ),
            )
        }

        // Build prompt message with default value hint
        let promptMessage = if let defaultValue = macro.default {
            "\(macro.description) (comma-separated) [default: '\(defaultValue.stringValue)'] (Type '\"\"' for empty array)"
        } else {
            "\(macro.description) (comma-separated)"
        }

        let input = await interaction.textPrompt(
            title: "\(macro.name)",
            prompt: StyledText(promptMessage),
            collapsesOnAnswer: true,
            validationRules: validationRules,
        )

        // Resolve final values
        let values: [String] = if input == "\"\"" {
            // User explicitly wants empty array
            []
        } else if input.isEmpty, let defaultValue = macro.default {
            // User pressed Enter with default available - use arrayValue directly
            defaultValue.arrayValue
        } else {
            // User provided values
            ArrayInputParser().parseFromInteractive(input)
        }

        return ResolvedMacro(
            name: macro.name,
            description: macro.description,
            value: .array(values),
        )
    }

    private func promptForPath(_ macro: Config.Macro) async -> ResolvedMacro {
        let pathValidationRule = ValidationRule.path(
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
            allowsEmpty: macro.default != nil,
            error: "Invalid path for \(macro.name)",
        )

        var validationRules: [ValidationRule] = []

        // Only require non-empty if there's no default value
        if macro.default == nil {
            validationRules.append(
                .nonEmpty(message: "\(macro.name) cannot be empty."),
            )
        }

        validationRules.append(pathValidationRule)

        // Build prompt message with default value hint
        let promptMessage: String = if let defaultValue = macro.default?.stringValue {
            "\(macro.description) [default: '\(defaultValue)']"
        } else {
            macro.description
        }

        let pathString = await interaction.textPrompt(
            title: "\(macro.name)",
            prompt: StyledText(promptMessage),
            collapsesOnAnswer: true,
            validationRules: validationRules,
        )

        // Resolve final path
        let finalPathString = pathString.isEmpty && macro.default != nil ? macro.default!.stringValue : pathString

        // Resolve path using the standalone function
        let absolutePath = try! PathResolver.resolveToAbsoluteURL(
            finalPathString,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
        )

        return ResolvedMacro(
            name: macro.name,
            description: macro.description,
            value: .path(absolutePath),
        )
    }
}

extension MacroResolver {
    enum Error: LocalizedError, Equatable {
        case choiceTypeRequiresChoices(macro: String)

        var errorDescription: String? {
            switch self {
            case let .choiceTypeRequiresChoices(macro):
                "Macro '\(macro)' is of type 'choice' but no choices are defined in the configuration."
            }
        }
    }
}
