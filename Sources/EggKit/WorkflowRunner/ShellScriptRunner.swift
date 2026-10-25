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
    private let temporaryDirectory: URL

    /// - Parameter temporaryDirectory: The temp directory the sandbox must
    ///   keep writable. Defaults to ``processTemporaryDirectory``.
    init(
        processRunner: any ProcessRunning,
        workingDirectory: URL,
        additionalEnvironment: [String: String] = [:],
        executionEnvironment: ExecutionEnvironment = .unsandboxed,
        temporaryDirectory: URL = processTemporaryDirectory,
    ) {
        self.processRunner = processRunner
        self.workingDirectory = workingDirectory
        self.additionalEnvironment = additionalEnvironment
        self.executionEnvironment = executionEnvironment
        self.temporaryDirectory = temporaryDirectory
    }

    /// The temp directory child scripts see through `TMPDIR`.
    ///
    /// `TMPDIR` is read directly because `FileManager.temporaryDirectory` does
    /// not reliably reflect it (on Darwin it can come from `confstr`), and the
    /// scripts inherit the environment variable, not Foundation's answer.
    static var processTemporaryDirectory: URL {
        if let value = ProcessInfo.processInfo.environment["TMPDIR"], !value.isEmpty {
            return URL(filePath: value, directoryHint: .isDirectory)
        }
        return FileManager.default.temporaryDirectory
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
        let resolvedWorkingDirectory = Self.resolveRealPath(workingDirectory.path(percentEncoded: false))

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
                // Already decoded above — carrying it costs nothing, and
                // without it the step's own account of why it failed is lost.
                stdout: stdout,
                stderr: "",
            )
        }

        return stdout
    }

    /// Generates a Sandbox Profile Language (SBPL) profile that restricts file access.
    ///
    /// The profile:
    /// - Denies all operations by default
    /// - Allows process execution (required for running commands)
    /// - Allows read access to all files
    /// - Allows read/write access only to the staging root directory
    /// - Allows read/write access to additional allowed paths (from config.sandbox.allowed_paths)
    /// - Allows read/write access to the system temp directories and to the effective
    ///   temp directory (`TMPDIR`) when it lives elsewhere, e.g. on an external volume
    /// - Explicitly denies write access to the original working directory
    /// - Allows network access (some scripts may need it)
    ///
    /// Reference: https://reverse.put.as/wp-content/uploads/2011/09/Apple-Sandbox-Guide-v1.0.pdf
    static func generateSandboxProfile(
        for configuration: SandboxConfiguration,
        temporaryDirectory: URL? = nil,
    ) -> String {
        let writableRootPath = resolveRealPath(configuration.writableRoot.path(percentEncoded: false))
        let escapedWritableRoot = escapeForSandboxProfile(writableRootPath)

        let deniedRules = configuration.deniedPaths.map { path -> String in
            let resolved = resolveRealPath(path.path(percentEncoded: false))
            let escaped = escapeForSandboxProfile(resolved)
            return """
            (deny file-write* (subpath "\(escaped)"))
            (deny file-read* (subpath "\(escaped)"))
            """
        }.joined(separator: "\n")

        let allowedPathRules = configuration.allowedPaths.map { path -> String in
            let resolved = resolveRealPath(path.path(percentEncoded: false))
            let escaped = escapeForSandboxProfile(resolved)
            return """
            ; Allow write access to user-specified path: \(path.path(percentEncoded: false))
            (allow file-write* (subpath "\(escaped)"))
            """
        }.joined(separator: "\n")

        let temporaryDirectoryRules = effectiveTemporaryDirectory(temporaryDirectory, configuration: configuration)
            .map { path -> String in
                let escaped = escapeForSandboxProfile(path)
                return """
                ; Allow read/write access to the effective temp directory (TMPDIR) outside the system temp directories
                (allow file-read* (subpath "\(escaped)"))
                (allow file-write* (subpath "\(escaped)"))
                """
            } ?? ""

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
        \(temporaryDirectoryRules)
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
            let profile = Self.generateSandboxProfile(for: configuration, temporaryDirectory: temporaryDirectory)
            return (
                .path("/usr/bin/sandbox-exec"),
                ["-p", profile, "/bin/sh", "-c", command],
            )
        }
    }

    /// Resolves symlinks in a path using C's realpath.
    ///
    /// This is necessary because sandbox-exec uses real paths, not symlinked paths.
    /// For example, `/var/folders/...` must be `/private/var/folders/...` for sandbox rules.
    private static func resolveRealPath(_ path: String) -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard let result = realpath(path, &buffer) else {
            return path
        }
        return String(cString: result)
    }

    /// Returns the canonical path of `temporaryDirectory` when the profile must
    /// add a rule for it, or `nil` when it needs none.
    ///
    /// A rule is skipped when the directory is empty, missing, or `/`; already
    /// covered by the system temp directories or the sandbox's writable root;
    /// or contains a denied path. The last case matters because the temp rule
    /// comes after the deny rules and would otherwise re-open a directory the
    /// sandbox exists to protect (e.g. `TMPDIR` set to a parent of the project).
    /// The rule covers exactly this directory's subtree, never its parent.
    private static func effectiveTemporaryDirectory(
        _ temporaryDirectory: URL?,
        configuration: SandboxConfiguration,
    ) -> String? {
        guard let temporaryDirectory else { return nil }
        let rawPath = temporaryDirectory.path(percentEncoded: false)
        var isDirectory: ObjCBool = false
        guard !rawPath.isEmpty,
              FileManager.default.fileExists(atPath: rawPath, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return nil
        }

        // realpath so /var vs /private/var and symlinked TMPDIR values match what
        // the sandbox sees.
        let resolved = resolveRealPath(rawPath)
        guard resolved != "/" else { return nil }

        let alreadyWritable = ["/private/var/folders", "/private/tmp", resolveRealPath(configuration.writableRoot.path(percentEncoded: false))]
        if alreadyWritable.contains(where: { isPath(resolved, insideOrEqualTo: $0) }) {
            return nil
        }

        let deniedPaths = configuration.deniedPaths.map { resolveRealPath($0.path(percentEncoded: false)) }
        if deniedPaths.contains(where: { isPath($0, insideOrEqualTo: resolved) }) {
            return nil
        }

        return resolved
    }

    private static func isPath(_ path: String, insideOrEqualTo root: String) -> Bool {
        path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    /// Escapes a path for use inside an SBPL string literal, where `\` and `"` are special.
    private static func escapeForSandboxProfile(_ path: String) -> String {
        path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
