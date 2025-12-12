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
    private let useStaging: Bool
    private let override: Bool

    package init(
        mode: HatchRunnerMode,
        workingDirectory: AbsolutePath,
        homeDirectory: AbsolutePath,
        projectDirectory: AbsolutePath,
        fileSystem: some FileSysteming,
        processRunner: some ProcessRunning = ProcessRunner(),
        noora: some Noorable = Noora(),
        useStaging: Bool = true,
        override: Bool = false
    ) {
        self.mode = mode
        self.workingDirectory = workingDirectory
        self.homeDirectory = homeDirectory
        self.projectDirectory = projectDirectory
        self.fileSystem = fileSystem
        self.processRunner = processRunner
        self.noora = noora
        self.useStaging = useStaging
        self.override = override
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

            let workflowRunner = makeWorkflowRunner()

            // Run workflow with interactive macro resolution
            // Macros will be resolved inside the workflow runner at the appropriate time
            // (after staging area creation for staging execution)
            _ = try await workflowRunner.run(
                config: template.config,
                macroInputs: .interactive,
                templateDirectory: template.path
            )

        case let .direct(template, parsedMacros):
            let workflowRunner = makeWorkflowRunner()

            // Run workflow with parsed macros (path resolution deferred to runner)
            // This ensures path-type macros are resolved relative to the correct
            // working directory (staging area root for staging execution)
            _ = try await workflowRunner.run(
                config: template.config,
                macroInputs: .parsed(parsedMacros),
                templateDirectory: template.path
            )
        }
    }

    /// Creates the appropriate workflow runner based on staging settings.
    ///
    /// - Returns: A workflow runner (staging or direct)
    private func makeWorkflowRunner() -> any WorkflowRunning {
        if useStaging {
            return StagingWorkflowRunner(
                processRunner: processRunner,
                fileSystem: fileSystem,
                workingDirectory: workingDirectory,
                homeDirectory: homeDirectory,
                noora: noora,
                isInteractive: mode.isInteractive,
                override: override
            )
        } else {
            noora.warning("Running in direct mode. filesystem changes are permanent")
            return LifecycleWorkflowRunner(
                processRunner: processRunner,
                fileSystem: fileSystem,
                workingDirectory: workingDirectory,
                homeDirectory: homeDirectory,
                noora: noora,
                isInteractive: mode.isInteractive,
                override: override
            )
        }
    }
}

extension HatchRunnerMode {
    var isInteractive: Bool {
        switch self {
        case .interactive:
            true
        case .direct:
            false
        }
    }
}
