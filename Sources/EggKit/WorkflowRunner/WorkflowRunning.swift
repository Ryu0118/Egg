import Path

/// Protocol for workflow runners that execute the hatch lifecycle.
///
/// WorkflowRunning defines the common interface for executing the entire hatch lifecycle
/// (pre_hatch → hatch → post_hatch). This allows different implementations:
/// - `LifecycleWorkflowRunner`: Legacy runner that operates directly on the working directory
/// - `TransactionalWorkflowRunner`: Atomic runner that executes in a transactional workspace with partial apply
///
/// Example:
/// ```swift
/// let runner: any WorkflowRunning = TransactionalWorkflowRunner(...)
/// let outputPath = try await runner.run(
///     config: config,
///     macroInputs: macroInputs,
///     templateDirectory: templateDir
/// )
/// ```
protocol WorkflowRunning {
    /// Executes the complete lifecycle workflow.
    ///
    /// The runner is responsible for resolving macros at the appropriate time,
    /// which is especially important for transactional execution where paths must be
    /// resolved relative to the transactional workspace root.
    ///
    /// - Parameters:
    ///   - config: Template configuration containing lifecycle steps and hatch configuration
    ///   - macroInputs: Macro inputs to be resolved (either already resolved or pending interactive prompts)
    ///   - templateDirectory: Source directory containing the template files
    /// - Returns: The resolved absolute path of the output directory
    /// - Throws: Errors if any phase fails or file system operations fail
    func run(
        config: Config,
        macroInputs: MacroInputs,
        templateDirectory: AbsolutePath
    ) async throws -> AbsolutePath
}

/// Represents the input for macro resolution.
///
/// Macros can be provided in different ways:
/// - `parsed`: Parsed macro definitions from CLI that need path resolution
/// - `interactive`: Macros need to be prompted interactively
///
/// The workflow runner is responsible for resolving macros at the appropriate time
/// (after transactional workspace creation for transactional runners), especially for path-type macros.
enum MacroInputs: Sendable {
    /// Parsed macro definitions from CLI arguments.
    /// Path-type macros will be resolved by the workflow runner.
    case parsed([ParsedMacroDefinition])

    /// Macros need to be resolved interactively.
    /// The runner will prompt for values using the macro definitions from Config.
    case interactive
}
