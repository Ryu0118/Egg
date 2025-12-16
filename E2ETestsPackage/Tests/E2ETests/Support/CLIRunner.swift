import Foundation
import ProcessRunning
import Subprocess

#if canImport(System)
    import System
#else
    import SystemPackage
#endif

/// Helper for running CLI commands in tests
struct CLIRunner: Sendable {
    private let binaryPath: URL
    private let processRunner: ProcessRunner

    /// Initialize the CLI runner by getting the binary path from BinaryBuildState
    init() async throws {
        binaryPath = try await BinaryBuildState.shared.getBinaryPath()
        processRunner = ProcessRunner()
    }

    /// Run a CLI command with variadic arguments
    /// - Parameters:
    ///   - arguments: The command arguments
    ///   - workingDirectory: Optional working directory for the command
    ///   - environment: Optional environment variables
    /// - Returns: The CLI result containing exit code and output
    func run(
        _ arguments: String...,
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil
    ) async throws -> CLIResult {
        try await run(
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment
        )
    }

    /// Run a CLI command with an array of arguments
    /// - Parameters:
    ///   - arguments: The command arguments as an array
    ///   - workingDirectory: Optional working directory for the command
    ///   - environment: Optional environment variables
    /// - Returns: The CLI result containing exit code and output
    func run(
        arguments: [String],
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil
    ) async throws -> CLIResult {
        let executablePath = FilePath(binaryPath.path(percentEncoded: false))
        let env: Environment
        if let environment {
            var envDict: [Environment.Key: String] = [:]
            for (key, value) in environment {
                envDict[Environment.Key(stringLiteral: key)] = value
            }
            env = .custom(envDict)
        } else {
            env = .inherit
        }
        let workingDir: FilePath? = workingDirectory.map { FilePath($0.path(percentEncoded: false)) }
        let outputConfig: StringOutput = .string(limit: 10 * 1024 * 1024)
        let errorConfig: StringOutput = .string(limit: 10 * 1024 * 1024)

        let result = try await processRunner.run(
            .path(executablePath),
            arguments: Arguments(arguments),
            environment: env,
            workingDirectory: workingDir,
            output: outputConfig,
            error: errorConfig
        )

        let exitCode: Int32
        switch result.terminationStatus {
        case let .exited(code):
            exitCode = code
        case let .unhandledException(code):
            exitCode = code
        }

        return CLIResult(
            exitCode: exitCode,
            stdout: result.standardOutput ?? "",
            stderr: result.standardError ?? ""
        )
    }
}
