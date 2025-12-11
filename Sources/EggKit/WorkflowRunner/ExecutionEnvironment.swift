import Path

/// Defines the execution environment for shell commands.
///
/// This enum clearly separates sandboxed execution (with OS-level restrictions)
/// from normal execution, making the code intent explicit and preventing
/// confusion about which parameters are required in each mode.
enum ExecutionEnvironment {
    /// Normal execution without sandbox restrictions.
    case normal

    /// Sandboxed execution with OS-level restrictions (macOS sandbox-exec).
    ///
    /// - Parameters:
    ///   - root: The sandbox root directory where write access is allowed
    ///   - originalWorkingDirectory: The original working directory to block writes to
    case sandboxed(root: AbsolutePath, originalWorkingDirectory: AbsolutePath)
}
