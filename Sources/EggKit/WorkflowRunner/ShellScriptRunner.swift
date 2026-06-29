import Foundation
import ProcessRunning
import Subprocess

#if canImport(System)
    import System
#else
    import SystemPackage
#endif

/// Executes shell commands and captures output.
///
/// When `executionEnvironment` is `.sandboxed`, commands are executed within
/// an OS-level sandbox using `sandbox-exec` that restricts file system access
/// to only the staging directory.
struct ShellScriptRunner {
    private let processRunner: any ProcessRunning
    private let workingDirectory: URL
    private let additionalEnvironment: [String: String]
    private let executionEnvironment: ExecutionEnvironment

    init(
        processRunner: any ProcessRunning,
        workingDirectory: URL,
        additionalEnvironment: [String: String] = [:],
        executionEnvironment: ExecutionEnvironment = .unsandboxed,
    ) {
        self.processRunner = processRunner
        self.workingDirectory = workingDirectory
        self.additionalEnvironment = additionalEnvironment
        self.executionEnvironment = executionEnvironment
    }

    /// Executes a shell command and streams stdout in real-time.
    /// Note: stderr is not captured in streaming mode due to API limitations.
    ///
    /// - Parameters:
    ///   - command: The shell command to execute
    ///   - onOutput: Closure called with stdout chunks as they arrive
    /// - Returns: Complete stdout string
    /// - Throws: LifecycleStepError.shellExecutionError if the command exits with non-zero status
    func executeStreaming(
        _ command: String,
        onOutput: @escaping (String) -> Void,
    ) async throws -> String {
        let (executable, arguments) = makeExecutableAndArguments(for: command)

        // Resolve symlinks in working directory for macOS sandbox-exec compatibility
        let resolvedWorkingDirectory = resolveRealPath(workingDirectory.path(percentEncoded: false))

        let result = try await processRunner.run(
            executable,
            arguments: arguments,
            environment: mergedEnvironment,
            workingDirectory: FilePath(resolvedWorkingDirectory),
            platformOptions: .init(),
            input: .none,
            error: .standardError,
            preferredBufferSize: nil,
            isolation: nil,
        ) { _, stdoutSequence in
            var stdoutBuffer = Data()

            for try await chunk in stdoutSequence {
                // Collect bytes for return value
                chunk.withUnsafeBytes { ptr in
                    stdoutBuffer.append(contentsOf: ptr)
                }
                // Stream output to caller's closure
                if let chunkString = String(data: Data(buffer: chunk), encoding: .utf8) {
                    onOutput(chunkString)
                }
            }

            return stdoutBuffer
        }

        let stdout = String(decoding: result.value, as: UTF8.self)

        guard result.terminationStatus.isSuccess else {
            let exitCode: Int32 = switch result.terminationStatus {
            case let .exited(code):
                code
            case let .unhandledException(code):
                code
            }
            throw LifecycleStepError.shellExecutionError(
                command: command,
                exitCode: exitCode,
                stderr: "",
            )
        }

        return stdout
    }

    /// Computes the merged environment by inheriting parent process environment
    /// and adding any additional environment variables.
    ///
    /// Additional environment variables take precedence over inherited values.
    private var mergedEnvironment: Subprocess.Environment {
        if additionalEnvironment.isEmpty {
            return .inherit
        }
        // Convert [String: String] to [Environment.Key: String?] for the updating() method
        // Environment.Key conforms to ExpressibleByStringLiteral, so we need to create keys via a workaround
        var envUpdates: [Subprocess.Environment.Key: String?] = [:]
        for (key, value) in additionalEnvironment {
            // Use the rawValue setter approach since the init is package-internal
            var envKey = Subprocess.Environment.Key("")
            envKey.rawValue = key
            envUpdates[envKey] = value
        }
        return Subprocess.Environment.inherit.updating(envUpdates)
    }

    /// Returns the executable and arguments for running the command.
    ///
    /// When sandboxed, wraps the command in `sandbox-exec`
    /// with a profile that restricts file system access to only the staging directory.
    private func makeExecutableAndArguments(for command: String) -> (Subprocess.Executable, Arguments) {
        switch executionEnvironment {
        case .unsandboxed:
            return (.path("/bin/sh"), ["-c", command])

        case let .sandboxed(configuration):
            let profile = generateSandboxProfile(for: configuration)
            return (
                .path("/usr/bin/sandbox-exec"),
                ["-p", profile, "/bin/sh", "-c", command],
            )
        }
    }

    /// Generates a Sandbox Profile Language (SBPL) profile that restricts file access.
    ///
    /// The profile:
    /// - Denies all operations by default
    /// - Allows process execution (required for running commands)
    /// - Allows read access to all files
    /// - Allows read/write access only to the staging root directory
    /// - Allows read/write access to additional allowed paths (from config.sandbox.allowed_paths)
    /// - Explicitly denies write access to the original working directory
    /// - Allows network access (some scripts may need it)
    ///
    /// Reference: https://reverse.put.as/wp-content/uploads/2011/09/Apple-Sandbox-Guide-v1.0.pdf
    private func generateSandboxProfile(for configuration: SandboxConfiguration) -> String {
        let writableRootPath = resolveRealPath(configuration.writableRoot.path(percentEncoded: false))
        let escapedWritableRoot = writableRootPath.replacingOccurrences(of: "\"", with: "\\\"")

        let deniedRules = configuration.deniedPaths.map { path -> String in
            let resolved = resolveRealPath(path.path(percentEncoded: false))
            let escaped = resolved.replacingOccurrences(of: "\"", with: "\\\"")
            return """
            (deny file-write* (subpath "\(escaped)"))
            (deny file-read* (subpath "\(escaped)"))
            """
        }.joined(separator: "\n")

        let allowedPathRules = configuration.allowedPaths.map { path -> String in
            let resolved = resolveRealPath(path.path(percentEncoded: false))
            let escaped = resolved.replacingOccurrences(of: "\"", with: "\\\"")
            return """
            ; Allow write access to user-specified path: \(path.path(percentEncoded: false))
            (allow file-write* (subpath "\(escaped)"))
            """
        }.joined(separator: "\n")

        return """
        (version 1)
        (deny default)
        ; Allow all process operations (exec, fork, etc.)
        (allow process*)
        ; Allow reading all files
        (allow file-read*)
        \(deniedRules)
        ; Allow full read/write access to sandbox directory only
        (allow file-write* (subpath "\(escapedWritableRoot)"))
        \(allowedPathRules)
        ; Allow read/write access to system temp directories (needed for atomic writes, locks, etc.)
        (allow file-read* (subpath "/private/var/folders"))
        (allow file-read* (subpath "/private/tmp"))
        (allow file-write* (subpath "/private/var/folders"))
        (allow file-write* (subpath "/private/tmp"))
        ; Allow read/write to /dev/null (used by many commands for discarding output)
        (allow file-read* (literal "/dev/null"))
        (allow file-write* (literal "/dev/null"))
        ; Allow file I/O control operations
        (allow file-ioctl)
        ; Allow network (some scripts may need it)
        (allow network*)
        ; Allow sysctl for process management
        (allow sysctl-read)
        ; Allow mach lookups for IPC
        (allow mach-lookup)
        ; Allow signal handling
        (allow signal)
        ; Allow IPC operations
        (allow ipc-posix*)
        """
    }

    /// Resolves symlinks in a path using C's realpath.
    ///
    /// This is necessary because sandbox-exec uses real paths, not symlinked paths.
    /// For example, `/var/folders/...` must be `/private/var/folders/...` for sandbox rules.
    private func resolveRealPath(_ path: String) -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard let result = realpath(path, &buffer) else {
            return path
        }
        return String(cString: result)
    }
}
