import FileSystem
import Foundation
import Noora
import Path
import ProcessRunning

/// Orchestrates the complete lifecycle workflow: pre_hatch → hatch → post_hatch.
///
/// LifecycleWorkflowRunner coordinates the three main phases of template generation:
/// 1. **pre_hatch**: Prepare environment, validate inputs, generate metadata
/// 2. **hatch**: Expand template with macro and step output substitution
/// 3. **post_hatch**: Format code, initialize git, install dependencies
///
/// The workflow runner ensures that outputs from earlier phases are available to later phases,
/// enabling complex multi-step template generation workflows.
///
/// Example:
/// ```swift
/// let runner = LifecycleWorkflowRunner(
///     processRunner: ProcessRunner(),
///     fileSystem: FileSystem(),
///     workingDirectory: try AbsolutePath(validating: "/tmp/work"),
///     outputDirectory: try AbsolutePath(validating: "/tmp/output")
/// )
///
/// try await runner.run(
///     config: config,
///     macros: resolvedMacros,
///     templateDirectory: templateDir
/// )
/// ```
struct LifecycleWorkflowRunner {
    private let processRunner: any ProcessRunning
    private let fileSystem: any FileSysteming
    private let workingDirectory: AbsolutePath
    private let homeDirectory: AbsolutePath
    private let noora: any Noorable

    init(
        processRunner: any ProcessRunning,
        fileSystem: any FileSysteming,
        workingDirectory: AbsolutePath,
        homeDirectory: AbsolutePath,
        noora: some Noorable = Noora()
    ) {
        self.processRunner = processRunner
        self.fileSystem = fileSystem
        self.workingDirectory = workingDirectory
        self.homeDirectory = homeDirectory
        self.noora = noora
    }

    /// Executes the complete lifecycle workflow.
    ///
    /// - Parameters:
    ///   - config: Template configuration containing lifecycle steps and hatch configuration
    ///   - macros: Resolved macros to substitute throughout the workflow
    ///   - templateDirectory: Source directory containing the template files
    /// - Returns: The resolved absolute path of the output directory
    /// - Throws: `LifecycleStepError` if any step fails, or file system errors
    func run(
        config: Config,
        macros: [ResolvedMacro],
        templateDirectory: AbsolutePath
    ) async throws -> AbsolutePath {
        let outputs = StepOutputsStorage()

        // Phase 1: Execute pre_hatch
        if let preHatchSteps = config.preHatch {
            try await executePreHatchPhase(steps: preHatchSteps, macros: macros, outputs: outputs)
        }

        // Phase 2: Execute hatch (template expansion)
        let outputDirectory = try await executeHatchPhase(config: config, macros: macros, outputs: outputs, templateDirectory: templateDirectory)

        // Phase 3: Execute post_hatch
        if let postHatchSteps = config.postHatch {
            try await executePostHatchPhase(
                steps: postHatchSteps,
                macros: macros,
                outputs: outputs
            )
        }

        return outputDirectory
    }

    /// Executes the pre_hatch lifecycle phase.
    ///
    /// Pre-hatch steps typically prepare the environment, validate inputs,
    /// or generate metadata that will be used during template expansion.
    ///
    /// - Parameters:
    ///   - steps: Pre-hatch lifecycle steps to execute
    ///   - macros: Resolved macros for variable substitution
    ///   - outputs: Storage for step outputs
    private func executePreHatchPhase(
        steps: [Config.LifecycleStep],
        macros: [ResolvedMacro],
        outputs: StepOutputsStorage
    ) async throws {
        noora.passthrough("🥚 Pre-hatch script executing...\n")

        let stepRunner = LifecycleStepRunner(
            processRunner: processRunner,
            workingDirectory: workingDirectory
        )

        _ = try await stepRunner.execute(
            .preHatch,
            steps: steps,
            substituting: macros,
            merging: outputs
        )
    }

    /// Executes the hatch phase (template expansion).
    ///
    /// Hatch phase expands the template directory to the output directory,
    /// performing macro substitution, step output substitution, and applying exclusion rules.
    ///
    /// - Parameters:
    ///   - config: Template configuration
    ///   - macros: Resolved macros for substitution
    ///   - outputs: Step outputs from pre_hatch phase
    ///   - templateDirectory: Source directory containing template files
    /// - Returns: The resolved absolute path of the output directory
    private func executeHatchPhase(
        config: Config,
        macros: [ResolvedMacro],
        outputs: StepOutputsStorage,
        templateDirectory: AbsolutePath
    ) async throws -> AbsolutePath {
        noora.passthrough("🐣 Hatching \(config.name)...\n")

        // Resolve macros in the output path first
        let resolver = VariableResolver(macros: macros, outputs: outputs)
        let resolvedOutput = try await resolver.resolve(config.hatch.output)

        let outputDirectory = try resolveToAbsolutePath(
            resolvedOutput,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory
        )

        // Safety check: prevent data loss by ensuring outputDirectory is not the same as or contains templateDirectory
        // This prevents accidentally wiping out the template or working directory
        if outputDirectory == templateDirectory {
            throw LifecycleStepError.invalidOutputDirectory(
                "Output directory cannot be the same as template directory: \(outputDirectory.pathString)"
            )
        }

        if templateDirectory.pathString.hasPrefix(outputDirectory.pathString + "/") {
            throw LifecycleStepError.invalidOutputDirectory(
                "Output directory cannot contain template directory. Output: \(outputDirectory.pathString), Template: \(templateDirectory.pathString)"
            )
        }

        let expander = TemplateExpander(
            fileSystem: fileSystem,
            templateDirectory: templateDirectory,
            outputDirectory: outputDirectory
        )

        try await expander.expand(
            substituting: macros,
            with: outputs,
            excluding: config.hatch.exclude
        )

        noora.success("Template hatched successfully at \(outputDirectory.pathString)")

        return outputDirectory
    }

    /// Executes the post_hatch lifecycle phase.
    ///
    /// Post-hatch steps typically perform finalization tasks such as code formatting,
    /// git initialization, dependency installation, or running initial builds.
    ///
    /// - Parameters:
    ///   - steps: Post-hatch lifecycle steps to execute
    ///   - macros: Resolved macros for variable substitution
    ///   - outputs: Step outputs from pre_hatch and hatch phases
    private func executePostHatchPhase(
        steps: [Config.LifecycleStep],
        macros: [ResolvedMacro],
        outputs: StepOutputsStorage
    ) async throws {
        noora.passthrough("🐥 Post-hatch script executing...\n")

        let stepRunner = LifecycleStepRunner(
            processRunner: processRunner,
            workingDirectory: workingDirectory
        )

        _ = try await stepRunner.execute(
            .postHatch,
            steps: steps,
            substituting: macros,
            merging: outputs
        )
    }
}
