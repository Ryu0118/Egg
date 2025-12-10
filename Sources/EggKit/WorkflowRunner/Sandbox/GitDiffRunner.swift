import FileSystem
import Foundation
import Path
import ProcessRunning
import Subprocess

#if canImport(System)
    import System
#else
    import SystemPackage
#endif

/// Runs git diff to detect changes between sandbox and working directory.
///
/// Uses `git diff --no-index` to compare directories without requiring a git repository.
/// This leverages Git's efficient diff algorithm, rename detection, and large file handling.
///
/// Note: Using nonisolated(unsafe) for fileSystem because FileSysteming protocol
/// is not Sendable but the concrete implementations are thread-safe. This allows
/// GitDiffRunner to be created and used from actor-isolated contexts.
struct GitDiffRunner {
    private let processRunner: any ProcessRunning
    private let fileSystem: any FileSysteming

    init(
        processRunner: some ProcessRunning = ProcessRunner(),
        fileSystem: any FileSysteming
    ) {
        self.processRunner = processRunner
        self.fileSystem = fileSystem
    }

    /// Computes changes between sandbox and working directory for specific paths.
    ///
    /// Only compares files at the specified relative paths (from watcher events).
    /// This targeted approach avoids scanning entire directory trees.
    ///
    /// - Parameters:
    ///   - sandboxRoot: The sandbox root directory
    ///   - workingDirectory: The original working directory
    ///   - targetPaths: Relative paths to compare (from watcher events)
    /// - Returns: Change summary with added, modified, and deleted files
    func computeChanges(
        sandboxRoot: AbsolutePath,
        workingDirectory: AbsolutePath,
        targetPaths: Set<RelativePath>
    ) async throws -> ChangeSummary {
        guard !targetPaths.isEmpty else {
            return .none
        }

        return try await fileSystem.withTemporaryDirectory(prefix: "egg-git-diff") { tempRoot in
            let workingTemp = tempRoot.appending(component: "working")
            let sandboxTemp = tempRoot.appending(component: "sandbox")

            let hasCopiedFiles = try await copyTargetPaths(
                targetPaths,
                workingDirectory: workingDirectory,
                sandboxRoot: sandboxRoot,
                workingTemp: workingTemp,
                sandboxTemp: sandboxTemp
            )

            guard hasCopiedFiles else {
                return .none
            }

            return try await runGitDiff(workingRoot: workingTemp, sandboxRoot: sandboxTemp)
        }
    }

    /// Copies target paths from working directory and sandbox to temporary directories for comparison.
    ///
    /// - Returns: `true` if any files were copied, `false` otherwise.
    private func copyTargetPaths(
        _ targetPaths: Set<RelativePath>,
        workingDirectory: AbsolutePath,
        sandboxRoot: AbsolutePath,
        workingTemp: AbsolutePath,
        sandboxTemp: AbsolutePath
    ) async throws -> Bool {
        try await fileSystem.makeDirectory(at: workingTemp)
        try await fileSystem.makeDirectory(at: sandboxTemp)

        var copiedAny = false

        for relativePath in targetPaths {
            let copiedWorking = try await fileSystem.copyIfExists(
                from: workingDirectory.appending(relativePath),
                to: workingTemp.appending(relativePath)
            )
            let copiedSandbox = try await fileSystem.copyIfExists(
                from: sandboxRoot.appending(relativePath),
                to: sandboxTemp.appending(relativePath)
            )

            if copiedWorking || copiedSandbox {
                copiedAny = true
            }
        }

        return copiedAny
    }

    private func runGitDiff(
        workingRoot: AbsolutePath,
        sandboxRoot: AbsolutePath
    ) async throws -> ChangeSummary {
        let arguments = [
            "diff",
            "--no-index",
            "--name-status",
            "-z",
            workingRoot.pathString,
            sandboxRoot.pathString,
        ]

        let result = try await processRunner.run(
            .path("/usr/bin/git"),
            arguments: Arguments(arguments),
            environment: .inherit,
            workingDirectory: nil,
            platformOptions: PlatformOptions(),
            input: .none,
            output: .bytes(limit: 10 * 1024 * 1024),
            error: .bytes(limit: 1024)
        )

        switch result.terminationStatus {
        case let .exited(code):
            // 0 = no differences, 1 = differences found
            guard code == 0 || code == 1 else {
                throw SandboxContext.Error.gitDiffFailed(exitCode: code)
            }
        case .unhandledException:
            throw SandboxContext.Error.gitDiffCrashed
        }

        guard !result.standardOutput.isEmpty else {
            return .none
        }

        let outputString = String(decoding: result.standardOutput, as: UTF8.self)
        return parseNameStatusOutput(
            outputString,
            workingRoot: workingRoot,
            sandboxRoot: sandboxRoot
        )
    }

    private func parseNameStatusOutput(
        _ output: String,
        workingRoot: AbsolutePath,
        sandboxRoot: AbsolutePath
    ) -> ChangeSummary {
        let parser = GitNameStatusParser(
            workingRoot: workingRoot,
            sandboxRoot: sandboxRoot
        )
        return parser.parse(components: output.split(separator: "\0", omittingEmptySubsequences: false))
    }
}
