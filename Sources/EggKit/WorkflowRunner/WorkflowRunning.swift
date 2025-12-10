import Path

/// Protocol for workflow runners that execute the hatch lifecycle.
///
/// WorkflowRunning defines the common interface for executing the entire hatch lifecycle
/// (pre_hatch → hatch → post_hatch). This allows different implementations:
/// - `LifecycleWorkflowRunner`: Legacy runner that operates directly on the working directory
/// - `SandboxedWorkflowRunner`: Atomic runner that executes in a sandbox with partial apply
///
/// Example:
/// ```swift
/// let runner: any WorkflowRunning = SandboxedWorkflowRunner(...)
/// let outputPath = try await runner.run(
///     config: config,
///     macros: resolvedMacros,
///     templateDirectory: templateDir
/// )
/// ```
protocol WorkflowRunning {
    /// Executes the complete lifecycle workflow.
    ///
    /// - Parameters:
    ///   - config: Template configuration containing lifecycle steps and hatch configuration
    ///   - macros: Resolved macros to substitute throughout the workflow
    ///   - templateDirectory: Source directory containing the template files
    /// - Returns: The resolved absolute path of the output directory
    /// - Throws: Errors if any phase fails or file system operations fail
    func run(
        config: Config,
        macros: [ResolvedMacro],
        templateDirectory: AbsolutePath
    ) async throws -> AbsolutePath
}
