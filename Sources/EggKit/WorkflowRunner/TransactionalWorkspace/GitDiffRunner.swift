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

/// Runs git diff to detect changes between transactional workspace and working directory.
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

    /// Computes changes between transactional workspace and working directory for specific paths.
    ///
    /// Only compares files at the specified relative paths (from watcher events).
    /// This targeted approach avoids scanning entire directory trees.
    ///
    /// - Parameters:
    ///   - workspaceRoot: The transactional workspace root directory
    ///   - workingDirectory: The original working directory
    ///   - targetPaths: Relative paths to compare (from watcher events)
    /// - Returns: Change summary with added, modified, and deleted files
    func computeChanges(
        workspaceRoot: AbsolutePath,
        workingDirectory: AbsolutePath,
        targetPaths: Set<RelativePath>
    ) async throws -> ChangeSummary {
        guard !targetPaths.isEmpty else {
            return .none
        }

        return try await fileSystem.withTemporaryDirectory(prefix: "egg-git-diff") { tempRoot in
            let workingTemp = tempRoot.appending(component: "working")
            let workspaceTemp = tempRoot.appending(component: "workspace")

            let hasCopiedFiles = try await copyTargetPaths(
                targetPaths,
                workingDirectory: workingDirectory,
                workspaceRoot: workspaceRoot,
                workingTemp: workingTemp,
                workspaceTemp: workspaceTemp
            )

            guard hasCopiedFiles else {
                return .none
            }

            return try await runGitDiff(workingRoot: workingTemp, workspaceRoot: workspaceTemp)
        }
    }

    /// Copies target paths from working directory and transactional workspace to temporary directories for comparison.
    ///
    /// Only copies **files** (not directories). Directory paths are skipped because:
    /// 1. FSEvents reports directory changes separately from file changes
    /// 2. Copying an entire directory would include unchanged files, causing false positives
    /// 3. If files within a directory changed, FSEvents also reports those individual files
    ///
    /// - Returns: `true` if any files were copied, `false` otherwise.
    private func copyTargetPaths(
        _ targetPaths: Set<RelativePath>,
        workingDirectory: AbsolutePath,
        workspaceRoot: AbsolutePath,
        workingTemp: AbsolutePath,
        workspaceTemp: AbsolutePath
    ) async throws -> Bool {
        try await fileSystem.makeDirectory(at: workingTemp)
        try await fileSystem.makeDirectory(at: workspaceTemp)

        var copiedAny = false

        for relativePath in targetPaths {
            let workingPath = workingDirectory.appending(relativePath)
            let workspacePath = workspaceRoot.appending(relativePath)

            // Skip directories - only process files
            // FSEvents reports file changes individually, so directory-level events
            // don't need to trigger recursive copies which could include unchanged files
            let isWorkingDirectory = try await fileSystem.exists(workingPath, isDirectory: true)
            let isWorkspaceDirectory = try await fileSystem.exists(workspacePath, isDirectory: true)

            if isWorkingDirectory || isWorkspaceDirectory {
                continue
            }

            let copiedWorking = try await fileSystem.copyIfExists(
                from: workingPath,
                to: workingTemp.appending(relativePath)
            )
            let copiedWorkspace = try await fileSystem.copyIfExists(
                from: workspacePath,
                to: workspaceTemp.appending(relativePath)
            )

            if copiedWorking || copiedWorkspace {
                copiedAny = true
            }
        }

        return copiedAny
    }

    private func runGitDiff(
        workingRoot: AbsolutePath,
        workspaceRoot: AbsolutePath
    ) async throws -> ChangeSummary {
        let arguments = [
            "diff",
            "--no-index",
            "--name-status",
            "-z",
            workingRoot.pathString,
            workspaceRoot.pathString,
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
                throw TransactionalWorkspaceContext.Error.gitDiffFailed(exitCode: code)
            }
        case .unhandledException:
            throw TransactionalWorkspaceContext.Error.gitDiffCrashed
        }

        guard !result.standardOutput.isEmpty else {
            return .none
        }

        let outputString = String(decoding: result.standardOutput, as: UTF8.self)
        return parseNameStatusOutput(
            outputString,
            workingRoot: workingRoot,
            workspaceRoot: workspaceRoot
        )
    }

    private func parseNameStatusOutput(
        _ output: String,
        workingRoot: AbsolutePath,
        workspaceRoot: AbsolutePath
    ) -> ChangeSummary {
        let parser = GitNameStatusParser(
            workingRoot: workingRoot,
            workspaceRoot: workspaceRoot
        )
        return parser.parse(components: output.split(separator: "\0", omittingEmptySubsequences: false))
    }
}
