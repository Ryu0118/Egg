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

    init(
        processRunner: any ProcessRunning,
        workingDirectory: AbsolutePath
    ) {
        self.processRunner = processRunner
        self.workingDirectory = workingDirectory
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
            environment: .inherit,
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
            environment: .inherit,
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
}
