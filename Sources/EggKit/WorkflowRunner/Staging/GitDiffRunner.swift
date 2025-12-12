import FileManagerProtocol
import Foundation
import ProcessRunning
import Subprocess

#if canImport(System)
    import System
#else
    import SystemPackage
#endif

/// Runs git diff to detect changes between staging and working directory.
///
/// Uses `git diff --no-index` to compare directories without requiring a git repository.
/// This leverages Git's efficient diff algorithm, rename detection, and large file handling.
///
/// Note: Using nonisolated(unsafe) for fileManager because FileManagerProtocol
/// is not Sendable but the concrete implementations are thread-safe. This allows
/// GitDiffRunner to be created and used from actor-isolated contexts.
struct GitDiffRunner {
    private let processRunner: any ProcessRunning
    private let fileManager: any FileManagerProtocol

    init(
        processRunner: some ProcessRunning = ProcessRunner(),
        fileManager: some FileManagerProtocol
    ) {
        self.processRunner = processRunner
        self.fileManager = fileManager
    }

    /// Computes changes between staging and working directory for specific paths.
    ///
    /// Only compares files at the specified relative paths (from watcher events).
    /// This targeted approach avoids scanning entire directory trees.
    ///
    /// - Parameters:
    ///   - workspaceRoot: The staging root directory
    ///   - workingDirectory: The original working directory
    ///   - targetPaths: Relative paths to compare (from watcher events)
    /// - Returns: Change summary with added, modified, and deleted files
    func computeChanges(
        workspaceRoot: URL,
        workingDirectory: URL,
        targetPaths: Set<String>
    ) async throws -> ChangeSummary {
        guard !targetPaths.isEmpty else {
            return .none
        }

        let tempRoot = try fileManager.makeTemporaryDirectory(prefix: "egg-git-diff")
        defer { try? fileManager.removeItem(at: tempRoot) }

        let workingTemp = tempRoot.appending(path: "working")
        let workspaceTemp = tempRoot.appending(path: "workspace")

        let hasCopiedFiles = try copyTargetPaths(
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

    /// Copies target paths from working directory and staging to temporary directories for comparison.
    ///
    /// Only copies **files** (not directories). Directory paths are skipped because:
    /// 1. FSEvents reports directory changes separately from file changes
    /// 2. Copying an entire directory would include unchanged files, causing false positives
    /// 3. If files within a directory changed, FSEvents also reports those individual files
    ///
    /// - Returns: `true` if any files were copied, `false` otherwise.
    private func copyTargetPaths(
        _ targetPaths: Set<String>,
        workingDirectory: URL,
        workspaceRoot: URL,
        workingTemp: URL,
        workspaceTemp: URL
    ) throws -> Bool {
        try fileManager.createDirectory(at: workingTemp, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workspaceTemp, withIntermediateDirectories: true)

        var copiedAny = false

        for relativePath in targetPaths {
            let workingPath = workingDirectory.appending(path: relativePath)
            let workspacePath = workspaceRoot.appending(path: relativePath)

            // Skip directories - only process files
            // FSEvents reports file changes individually, so directory-level events
            // don't need to trigger recursive copies which could include unchanged files
            let isWorkingDirectory = fileManager.isDirectory(at: workingPath)
            let isWorkspaceDirectory = fileManager.isDirectory(at: workspacePath)

            if isWorkingDirectory || isWorkspaceDirectory {
                continue
            }

            let copiedWorking = try fileManager.copyIfExists(
                from: workingPath,
                to: workingTemp.appending(path: relativePath)
            )
            let copiedWorkspace = try fileManager.copyIfExists(
                from: workspacePath,
                to: workspaceTemp.appending(path: relativePath)
            )

            if copiedWorking || copiedWorkspace {
                copiedAny = true
            }
        }

        return copiedAny
    }

    private func runGitDiff(
        workingRoot: URL,
        workspaceRoot: URL
    ) async throws -> ChangeSummary {
        let arguments = [
            "diff",
            "--no-index",
            "--name-status",
            "-z",
            workingRoot.path,
            workspaceRoot.path,
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
                throw StagingContext.Error.gitDiffFailed(exitCode: code)
            }
        case .unhandledException:
            throw StagingContext.Error.gitDiffCrashed
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
        workingRoot: URL,
        workspaceRoot: URL
    ) -> ChangeSummary {
        let parser = GitNameStatusParser(
            workingRoot: workingRoot,
            workspaceRoot: workspaceRoot
        )
        return parser.parse(components: output.split(separator: "\0", omittingEmptySubsequences: false))
    }
}
