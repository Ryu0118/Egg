import FileManagerProtocol
import Foundation
import Interaction
import Noora
import ProcessRunning

package struct HatchRunner {
    private let mode: HatchRunnerMode
    private let noora: any Noorable
    private let interaction: any InteractionProviding
    private let workingDirectory: URL
    private let homeDirectory: URL
    private let fileManager: any FileManagerProtocol
    private let projectDirectory: URL
    private let templateFinder: TemplatesFinder
    private let processRunner: any ProcessRunning
    private let useStaging: Bool
    private let overrideConflicts: Bool
    private let sandboxDisabled: Bool
    private let applyChanges: Bool
    private let stagingRoot: URL?
    private let pickerStyle: TemplatePickerStyle

    package init(
        mode: HatchRunnerMode,
        workingDirectory: URL,
        homeDirectory: URL,
        projectDirectory: URL,
        additionalSearchPaths: [URL] = [],
        fileManager: some FileManagerProtocol,
        processRunner: some ProcessRunning = ProcessRunner(),
        noora: some Noorable = Noora(),
        interaction: some InteractionProviding = Terminal(),
        useStaging: Bool = true,
        overrideConflicts: Bool = false,
        sandboxDisabled: Bool = false,
        applyChanges: Bool = false,
        stagingRoot: URL? = nil,
        pickerStyle: TemplatePickerStyle = .list,
    ) {
        self.mode = mode
        self.workingDirectory = workingDirectory
        self.homeDirectory = homeDirectory
        self.projectDirectory = projectDirectory
        self.fileManager = fileManager
        self.processRunner = processRunner
        self.noora = noora
        self.interaction = interaction
        self.useStaging = useStaging
        self.overrideConflicts = overrideConflicts
        self.sandboxDisabled = sandboxDisabled
        self.applyChanges = applyChanges
        self.stagingRoot = stagingRoot
        self.pickerStyle = pickerStyle
        templateFinder = TemplatesFinder(
            fileManager: fileManager,
            projectDirectory: projectDirectory,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
            additionalSearchPaths: additionalSearchPaths,
        )
    }

    package func run() async throws {
        switch mode {
        case .interactive:
            // Get all available templates from global and project directories
            let options = try await templateFinder.listWithLocations()

            guard !options.isEmpty else {
                throw Error.noTemplatesFound
            }

            // Select template based on picker style
            let selectedOption = try selectTemplate(from: options)

            let workflowRunner = makeWorkflowRunner()

            // Run workflow with interactive macro resolution
            // Macros will be resolved inside the workflow runner at the appropriate time
            // (after staging area creation for staging execution)
            _ = try await workflowRunner.run(
                config: selectedOption.template.config,
                macroInputs: .interactive,
                templateDirectory: selectedOption.template.path,
            )

        case let .direct(template, parsedMacros):
            let workflowRunner = makeWorkflowRunner()

            // Run workflow with parsed macros (path resolution deferred to runner)
            // This ensures path-type macros are resolved relative to the correct
            // working directory (staging area root for staging execution)
            _ = try await workflowRunner.run(
                config: template.config,
                macroInputs: .parsed(parsedMacros),
                templateDirectory: template.path,
            )

        case .mcp:
            // MCP mode returns result, use runMcp() instead
            break
        }
    }

    /// Run in MCP mode and return structured result
    package func runMcp(
        template: Template,
        parsedMacros: [ParsedMacroDefinition],
    ) async throws -> HatchResult {
        let workflowRunner = makeWorkflowRunner()

        do {
            let outputPath = try await workflowRunner.run(
                config: template.config,
                macroInputs: .parsed(parsedMacros),
                templateDirectory: template.path,
            )

            return HatchResult(
                templateName: template.config.name,
                outputDirectory: outputPath.path(percentEncoded: false),
                success: true,
                message: "Template '\(template.config.name)' hatched successfully",
            )
        } catch {
            return HatchResult(
                templateName: template.config.name,
                outputDirectory: workingDirectory.path(percentEncoded: false),
                success: false,
                message: error.localizedDescription,
            )
        }
    }

    /// Selects a template based on the configured picker style.
    ///
    /// - Parameter options: Available templates with their locations
    /// - Returns: The selected template with location
    /// - Throws: ``Error/templateNotFound(_:)`` if text input doesn't match any template
    private func selectTemplate(from options: [TemplateWithLocation]) throws -> TemplateWithLocation {
        switch pickerStyle {
        case .list:
            return noora.singleChoicePrompt(
                title: "Select Template",
                question: "Which template would you like to use?",
                options: options,
                description: "Select a template to hatch.",
            )
        case .text:
            let availableNames = options.map(\.template.config.name).joined(separator: ", ")
            let templateName = noora.textPrompt(
                title: "Template Name (\(availableNames))",
                prompt: "Enter the template name:",
                collapseOnAnswer: true,
            )
            guard let selected = options.first(where: { $0.template.config.name == templateName }) else {
                throw Error.templateNotFound(templateName)
            }
            return selected
        }
    }

    /// Creates the appropriate workflow runner based on staging settings.
    ///
    /// - Returns: A workflow runner (staging or direct)
    private func makeWorkflowRunner() -> any WorkflowRunning {
        if useStaging {
            return StagingWorkflowRunner(
                processRunner: processRunner,
                fileManager: fileManager,
                workingDirectory: workingDirectory,
                homeDirectory: homeDirectory,
                noora: noora,
                interaction: interaction,
                isInteractive: mode.isInteractive,
                overrideConflicts: overrideConflicts,
                sandboxDisabled: sandboxDisabled,
                applyChanges: applyChanges,
                stagingRoot: stagingRoot,
            )
        } else {
            interaction.writeWarning("Running in direct mode. filesystem changes are permanent")
            return LifecycleWorkflowRunner(
                processRunner: processRunner,
                fileManager: fileManager,
                workingDirectory: workingDirectory,
                homeDirectory: homeDirectory,
                noora: noora,
                interaction: interaction,
                isInteractive: mode.isInteractive,
                overrideConflicts: overrideConflicts,
                sandboxDisabled: sandboxDisabled,
                applyChanges: applyChanges,
            )
        }
    }
}

extension HatchRunnerMode {
    var isInteractive: Bool {
        switch self {
        case .interactive:
            true
        case .direct, .mcp:
            false
        }
    }
}

extension HatchRunner {
    enum Error: LocalizedError {
        case noTemplatesFound
        case templateNotFound(String)

        var errorDescription: String? {
            switch self {
            case .noTemplatesFound:
                "No templates found. Create a template first using 'egg create'."
            case let .templateNotFound(name):
                "Template '\(name)' not found."
            }
        }
    }
}
