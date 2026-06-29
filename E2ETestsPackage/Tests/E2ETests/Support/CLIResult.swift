import Foundation

/// Result of a CLI execution
struct CLIResult {
    /// The exit code of the process
    let exitCode: Int32

    /// The standard output of the process
    let stdout: String

    /// The standard error of the process
    let stderr: String

    /// Whether the command succeeded (exit code 0)
    var succeeded: Bool {
        exitCode == 0
    }
}
