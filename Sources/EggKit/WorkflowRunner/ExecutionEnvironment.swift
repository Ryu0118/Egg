import Foundation

/// Defines whether lifecycle shell commands run inside an OS sandbox.
///
/// - `.sandboxed`: Commands run via `sandbox-exec` with the provided configuration.
/// - `.unsandboxed`: Commands run directly without sandbox restrictions.
enum ExecutionEnvironment {
    case sandboxed(SandboxConfiguration)
    case unsandboxed
}

/// Configuration describing the sandbox boundaries.
struct SandboxConfiguration {
    /// Directory where shell commands are allowed to write.
    let writableRoot: URL
    /// Paths that should be explicitly denied for read/write access.
    let deniedPaths: [URL]

    init(writableRoot: URL, deniedPaths: [URL] = []) {
        self.writableRoot = writableRoot
        self.deniedPaths = deniedPaths
    }
}

extension SandboxConfiguration {
    /// Sandbox configuration for direct (non-staging) execution.
    static func workingDirectory(_ directory: URL) -> SandboxConfiguration {
        SandboxConfiguration(writableRoot: directory)
    }

    /// Sandbox configuration for staging execution that blocks access
    /// to the original working directory.
    static func staging(root: URL, originalWorkingDirectory: URL) -> SandboxConfiguration {
        SandboxConfiguration(
            writableRoot: root,
            deniedPaths: [originalWorkingDirectory]
        )
    }
}
