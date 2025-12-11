import Noora
import Path

/// Resolves macro definitions into concrete values.
///
/// MacroResolver handles the resolution of `Config.Macro` definitions into `ResolvedMacro` values.
/// For interactive mode, it prompts the user for values. For direct mode, macros should already
/// be resolved and passed through.
///
/// ## Important
/// The `workingDirectory` parameter should be the actual execution directory:
/// - For transactional workspace runners: the workspace root directory
/// - For non-sandboxed runners: the real working directory
///
/// This ensures path-type macros resolve correctly relative to the execution context.
package struct MacroResolver {
    private let config: Config
    private let workingDirectory: AbsolutePath
    private let homeDirectory: AbsolutePath
    private let noora: any Noorable

    package init(
        config: Config,
        workingDirectory: AbsolutePath,
        homeDirectory: AbsolutePath,
        noora: some Noorable
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
            return promptForString(macro)
        case .boolean:
            return promptForBoolean(macro)
        case .choice:
            return promptForChoice(macro)
        case .array:
            return promptForArray(macro)
        case .path:
            return promptForPath(macro)
        }
    }

    private func promptForString(_ macro: Config.Macro) -> ResolvedMacro {
        var validationRules: [any ValidatableRule] = [
            NonEmptyValidationRule(error: "\(macro.name) cannot be empty."),
        ]

        if let validatePattern = macro.validate {
            validationRules.append(
                RegexPatternValidationRule(
                    pattern: validatePattern,
                    error: "Value does not match the required pattern: '\(validatePattern)'"
                )
            )
        }

        let value = noora.textPrompt(
            title: "\(macro.name)",
            prompt: "\(macro.description)",
            collapseOnAnswer: true,
            validationRules: validationRules
        )

        return ResolvedMacro(
            name: macro.name,
            description: macro.description,
            value: .string(value)
        )
    }

    private func promptForBoolean(_ macro: Config.Macro) -> ResolvedMacro {
        let value = noora.yesOrNoChoicePrompt(
            title: "\(macro.name)",
            question: "\(macro.description)"
        )

        return ResolvedMacro(
            name: macro.name,
            description: macro.description,
            value: .boolean(value)
        )
    }

    private func promptForChoice(_ macro: Config.Macro) -> ResolvedMacro {
        guard let choices = macro.choices, !choices.isEmpty else {
            fatalError("Macro '\(macro.name)' is of type 'choice' but no choices are defined.")
        }

        let value = noora.singleChoicePrompt(
            title: "\(macro.name)",
            question: "\(macro.description)",
            options: choices
        )

        return ResolvedMacro(
            name: macro.name,
            description: macro.description,
            value: .choice(value)
        )
    }

    private func promptForArray(_ macro: Config.Macro) -> ResolvedMacro {
        guard let choices = macro.choices, !choices.isEmpty else {
            fatalError("Macro '\(macro.name)' is of type 'array' but no choices are defined.")
        }

        let values = noora.multipleChoicePrompt(
            title: "\(macro.name)",
            question: "\(macro.description)",
            options: choices
        )

        return ResolvedMacro(
            name: macro.name,
            description: macro.description,
            value: .array(values)
        )
    }

    private func promptForPath(_ macro: Config.Macro) -> ResolvedMacro {
        let pathValidationRule = PathValidationRule(
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
            error: "Invalid path for \(macro.name)"
        )

        let validationRules: [any ValidatableRule] = [
            NonEmptyValidationRule(error: "\(macro.name) cannot be empty."),
            pathValidationRule,
        ]

        let pathString = noora.textPrompt(
            title: "\(macro.name)",
            prompt: "\(macro.description)",
            collapseOnAnswer: true,
            validationRules: validationRules
        )

        // Resolve path using the standalone function
        let absolutePath = try! resolveToAbsolutePath(
            pathString,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory
        )

        return ResolvedMacro(
            name: macro.name,
            description: macro.description,
            value: .path(absolutePath)
        )
    }
}
