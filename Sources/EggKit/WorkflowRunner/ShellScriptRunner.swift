import Foundation
import Path
import ProcessRunning
import Subprocess

#if canImport(System)
    import System
#else
    import SystemPackage
#endif

/// Executes shell commands and captures output.
struct ShellScriptRunner {
    private let processRunner: any ProcessRunning
    private let workingDirectory: AbsolutePath
    private let additionalEnvironment: [String: String]

    init(
        processRunner: any ProcessRunning,
        workingDirectory: AbsolutePath,
        additionalEnvironment: [String: String] = [:]
    ) {
        self.processRunner = processRunner
        self.workingDirectory = workingDirectory
        self.additionalEnvironment = additionalEnvironment
    }

    /// Executes a shell command and captures stdout and stderr.
    ///
    /// - Parameter command: The shell command to execute
    /// - Returns: Tuple of (stdout, stderr)
    /// - Throws: LifecycleStepError.shellExecutionError if the command exits with non-zero status
    func execute(_ command: String) async throws -> (stdout: String, stderr: String) {
        let result = try await processRunner.run(
            .path("/bin/sh"),
            arguments: ["-c", command],
            environment: mergedEnvironment,
            workingDirectory: FilePath(workingDirectory.pathString),
            platformOptions: PlatformOptions(),
            input: .none,
            output: .bytes(limit: .max),
            error: .bytes(limit: .max)
        )

        let stdout = String(decoding: result.standardOutput, as: UTF8.self)
        let stderr = String(decoding: result.standardError, as: UTF8.self)

        guard result.terminationStatus.isSuccess else {
            let exitCode: Int32
            switch result.terminationStatus {
            case let .exited(code):
                exitCode = code
            case let .unhandledException(code):
                exitCode = code
            }
            throw LifecycleStepError.shellExecutionError(
                command: command,
                exitCode: exitCode,
                stderr: stderr
            )
        }

        return (stdout: stdout, stderr: stderr)
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
        onOutput: @escaping (String) -> Void
    ) async throws -> String {
        let result = try await processRunner.run(
            .path("/bin/sh"),
            arguments: ["-c", command],
            environment: mergedEnvironment,
            workingDirectory: FilePath(workingDirectory.pathString)
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
            let exitCode: Int32
            switch result.terminationStatus {
            case let .exited(code):
                exitCode = code
            case let .unhandledException(code):
                exitCode = code
            }
            throw LifecycleStepError.shellExecutionError(
                command: command,
                exitCode: exitCode,
                stderr: ""
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
}
