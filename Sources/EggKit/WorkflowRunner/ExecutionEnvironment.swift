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
    /// Additional paths outside the sandbox that are allowed for write access.
    /// These are absolute paths specified in config.yml's `sandbox.allowed_paths`.
    let allowedPaths: [URL]

    init(writableRoot: URL, deniedPaths: [URL] = [], allowedPaths: [URL] = []) {
        self.writableRoot = writableRoot
        self.deniedPaths = deniedPaths
        self.allowedPaths = allowedPaths
    }
}

extension SandboxConfiguration {
    /// Sandbox configuration for direct (non-staging) execution.
    static func workingDirectory(_ directory: URL, allowedPaths: [URL] = []) -> SandboxConfiguration {
        SandboxConfiguration(writableRoot: directory, allowedPaths: allowedPaths)
    }

    /// Sandbox configuration for staging execution that blocks access
    /// to the original working directory.
    static func staging(root: URL, originalWorkingDirectory: URL, allowedPaths: [URL] = []) -> SandboxConfiguration {
        SandboxConfiguration(
            writableRoot: root,
            deniedPaths: [originalWorkingDirectory],
            allowedPaths: allowedPaths
        )
    }
}
