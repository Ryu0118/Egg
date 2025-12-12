import Foundation

/// Defines the execution environment for shell commands.
///
/// This enum clearly separates staging workspace execution (with OS-level restrictions)
/// from normal execution, making the code intent explicit and preventing
/// confusion about which parameters are required in each mode.
enum ExecutionEnvironment {
    /// Normal execution without staging workspace restrictions.
    case normal

    /// Staging workspace execution with OS-level restrictions (macOS sandbox-exec).
    ///
    /// - Parameters:
    ///   - root: The staging workspace root directory where write access is allowed
    ///   - originalWorkingDirectory: The original working directory to block writes to
    case staging(root: URL, originalWorkingDirectory: URL)
}
