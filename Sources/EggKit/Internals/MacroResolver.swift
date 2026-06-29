import Foundation
import Noora

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
    private let noora: any Noorable

    package init(
        config: Config,
        workingDirectory: URL,
        homeDirectory: URL,
        noora: some Noorable,
    ) {
        self.config = config
        self.workingDirectory = workingDirectory
        self.homeDirectory = homeDirectory
        self.noora = noora
    }

    /// Resolves all macros defined in the config.
    ///
    /// - Returns: Array of resolved macros with concrete values
    package func resolve() -> [ResolvedMacro] {
        guard let macros = config.macros else { return [] }

        var resolvedMacros: [ResolvedMacro] = []

        for macro in macros {
            let resolvedMacro = promptForMacro(macro)
            resolvedMacros.append(resolvedMacro)
        }

        return resolvedMacros
    }

    private func promptForMacro(_ macro: Config.Macro) -> ResolvedMacro {
        switch macro.type {
        case .string:
            promptForString(macro)
        case .boolean:
            promptForBoolean(macro)
        case .choice:
            promptForChoice(macro)
        case .choices:
            promptForChoices(macro)
        case .array:
            promptForArray(macro)
        case .path:
            promptForPath(macro)
        }
    }

    private func promptForString(_ macro: Config.Macro) -> ResolvedMacro {
        var validationRules: [any ValidatableRule] = []

        // Only require non-empty if there's no default value
        if macro.default == nil {
            validationRules.append(
                NonEmptyValidationRule(error: "\(macro.name) cannot be empty."),
            )
        }

        if let validatePattern = macro.validate {
            validationRules.append(
                RegexPatternValidationRule(
                    pattern: validatePattern,
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

        let value = noora.textPrompt(
            title: "\(macro.name)",
            prompt: TerminalText(stringLiteral: promptMessage),
            collapseOnAnswer: true,
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
        let value = noora.yesOrNoChoicePrompt(
            title: "\(macro.name)",
            question: "\(macro.description)",
        )

        return ResolvedMacro(
            name: macro.name,
            description: macro.description,
            value: .boolean(value),
        )
    }

    private func promptForChoice(_ macro: Config.Macro) -> ResolvedMacro {
        guard let choices = macro.choices, !choices.isEmpty else {
            fatalError("Macro '\(macro.name)' is of type 'choice' but no choices are defined.")
        }

        let value = noora.singleChoicePrompt(
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

    private func promptForChoices(_ macro: Config.Macro) -> ResolvedMacro {
        guard let choices = macro.choices, !choices.isEmpty else {
            fatalError("Macro '\(macro.name)' is of type 'choices' but no choices are defined.")
        }

        let values = noora.multipleChoicePrompt(
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

    private func promptForArray(_ macro: Config.Macro) -> ResolvedMacro {
        // Build validation rules for array elements
        var validationRules: [any ValidatableRule] = []

        if let validatePattern = macro.validate {
            // Create a custom validation rule that validates each comma-separated element
            validationRules.append(
                ArrayElementValidationRule(
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

        let input = noora.textPrompt(
            title: "\(macro.name)",
            prompt: TerminalText(stringLiteral: promptMessage),
            collapseOnAnswer: true,
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

    private func promptForPath(_ macro: Config.Macro) -> ResolvedMacro {
        let pathValidationRule = PathValidationRule(
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
            error: "Invalid path for \(macro.name)",
        )

        var validationRules: [any ValidatableRule] = []

        // Only require non-empty if there's no default value
        if macro.default == nil {
            validationRules.append(
                NonEmptyValidationRule(error: "\(macro.name) cannot be empty."),
            )
        }

        validationRules.append(pathValidationRule)

        // Build prompt message with default value hint
        let promptMessage: String = if let defaultValue = macro.default?.stringValue {
            "\(macro.description) [default: '\(defaultValue)']"
        } else {
            macro.description
        }

        let pathString = noora.textPrompt(
            title: "\(macro.name)",
            prompt: TerminalText(stringLiteral: promptMessage),
            collapseOnAnswer: true,
            validationRules: validationRules,
        )

        // Resolve final path
        let finalPathString = pathString.isEmpty && macro.default != nil ? macro.default!.stringValue : pathString

        // Resolve path using the standalone function
        let absolutePath = try! resolveToAbsoluteURL(
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
