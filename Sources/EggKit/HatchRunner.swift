import FileSystem
import Foundation
import Noora
import Path
import ProcessRunning

package struct HatchRunner {
    private let mode: HatchRunnerMode
    private let noora: any Noorable
    private let workingDirectory: AbsolutePath
    private let homeDirectory: AbsolutePath
    private let fileSystem: any FileSysteming
    private let projectDirectory: AbsolutePath
    private let templateFinder: TemplatesFinder
    private let processRunner: any ProcessRunning

    package init(
        mode: HatchRunnerMode,
        workingDirectory: AbsolutePath,
        homeDirectory: AbsolutePath,
        projectDirectory: AbsolutePath,
        fileSystem: some FileSysteming,
        processRunner: some ProcessRunning = ProcessRunner(),
        noora: some Noorable = Noora()
    ) {
        self.mode = mode
        self.workingDirectory = workingDirectory
        self.homeDirectory = homeDirectory
        self.projectDirectory = projectDirectory
        self.fileSystem = fileSystem
        self.processRunner = processRunner
        self.noora = noora
        templateFinder = TemplatesFinder(
            fileSystem: fileSystem,
            projectDirectory: projectDirectory,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
            noora: noora
        )
    }

    package func run() async throws {
        switch mode {
        case .interactive:
            // Prompt for template name
            let templateName = noora.textPrompt(
                title: "Template Name",
                prompt: "Enter the template name:",
                collapseOnAnswer: true
            )

            // Fetch template using TemplatesFinder
            let template = try await templateFinder.fetchTemplate(templateName)

            // Generate questions using MacroQuestionGenerator
            let generator = MacroQuestionGenerator(
                config: template.config,
                workingDirectory: workingDirectory,
                homeDirectory: homeDirectory,
                noora: noora
            )

            let resolvedMacros = generator.generateQuestions()

            let workflowRunner = LifecycleWorkflowRunner(
                processRunner: processRunner,
                fileSystem: fileSystem,
                workingDirectory: workingDirectory,
                homeDirectory: homeDirectory,
                noora: noora
            )

            _ = try await workflowRunner.run(
                config: template.config,
                macros: resolvedMacros,
                templateDirectory: template.path
            )

        case let .direct(template, macros):
            let workflowRunner = LifecycleWorkflowRunner(
                processRunner: processRunner,
                fileSystem: fileSystem,
                workingDirectory: workingDirectory,
                homeDirectory: homeDirectory,
                noora: noora
            )

            _ = try await workflowRunner.run(
                config: template.config,
                macros: macros,
                templateDirectory: template.path
            )
        }
    }
}

/// Generates Noora questions from Config macros
private struct MacroQuestionGenerator {
    private let config: Config
    private let workingDirectory: AbsolutePath
    private let homeDirectory: AbsolutePath
    private let noora: any Noorable

    init(
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

    func generateQuestions() -> [ResolvedMacro] {
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
