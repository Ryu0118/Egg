import FileManagerProtocol
import Foundation
import ProcessRunning
import Subprocess
import AsyncOperations
import Noora

#if canImport(System)
    import System
#else
    import SystemPackage
#endif

/// Clones only git-tracked files from a source directory to a destination.
///
/// Uses `git ls-files -c -o --exclude-standard` to enumerate tracked files
/// and untracked files that aren't gitignored. Each file is cloned using
/// APFS copy-on-write for efficiency.
///
/// This avoids copying:
/// - Files in .gitignore (build caches, node_modules, etc.)
/// - The .git directory itself
///
/// If the source directory is not a git repository, falls back to APFS cloning
/// of the entire directory.
struct GitTrackedDirectoryCloner: DirectoryCloning {
    private let processRunner: any ProcessRunning
    private let fileManager: any FileManagerProtocol
    private let apfsCloner: any DirectoryCloning
    private let gitRepositoryChecker: GitRepositoryChecker
    nonisolated(unsafe) private let noora: any Noorable

    init(
        processRunner: some ProcessRunning = ProcessRunner(),
        fileManager: some FileManagerProtocol = FileManager.default,
        apfsCloner: some DirectoryCloning = APFSDirectoryCloner(),
        noora: some Noorable = Noora()
    ) {
        self.processRunner = processRunner
        self.fileManager = fileManager
        self.apfsCloner = apfsCloner
        self.gitRepositoryChecker = GitRepositoryChecker(processRunner: processRunner)
        self.noora = noora
    }

    func clone(from source: URL, to destination: URL) async throws {
        guard source.isFileURL, destination.isFileURL else {
            throw CloningError.invalidURL
        }

        // Check if source is a git repository
        guard await gitRepositoryChecker.isGitRepository(source) else {
            // Fall back to APFS cloning for non-git directories
            try await apfsCloner.clone(from: source, to: destination)
            return
        }

        // Get list of tracked and untracked (but not ignored) files
        let files = try await listGitTrackedFiles(in: source)

        guard !files.isEmpty else {
            // No files to clone, just create the destination directory
            try fileManager.createDirectory(
                at: destination,
                withIntermediateDirectories: true
            )
            return
        }

        // Create destination directory
        try fileManager.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )

        // Clone each file using APFS clonefile
        // Filter out files that don't exist in the working directory
        // (git ls-files -c includes deleted files that are still in the index)
        let existingFiles = files.filter { file in
            let sourceFile = source.appending(path: file)
            return fileManager.fileExists(atPath: sourceFile.path(percentEncoded: false))
        }

        try await existingFiles.asyncForEach(numberOfConcurrentTasks: 10) { file in
            let sourceFile = source.appending(path: file)
            let destFile = destination.appending(path: file)

            // Create parent directories if needed
            let destParent = destFile.deletingLastPathComponent()
            if destParent != destination {
                try self.fileManager.createDirectory(
                    at: destParent,
                    withIntermediateDirectories: true
                )
            }

            try await self.apfsCloner.clone(from: sourceFile, to: destFile)
        }
    }

    /// Lists git-tracked files and untracked files that aren't ignored.
    ///
    /// Runs `git ls-files -c -o --exclude-standard` to get:
    /// - `-c`: Cached (tracked) files
    /// - `-o`: Other (untracked) files
    /// - `--exclude-standard`: Respect .gitignore, .git/info/exclude, etc.
    private func listGitTrackedFiles(in directory: URL) async throws -> [String] {
        let arguments = [
            "ls-files",
            "-c",           // Cached (tracked) files
            "-o",           // Other (untracked) files
            "--exclude-standard",  // Respect .gitignore
            "-z",           // NUL-separated output
        ]

        let result = try await processRunner.run(
            .path("/usr/bin/git"),
            arguments: Arguments(arguments),
            environment: .inherit,
            workingDirectory: FilePath(directory.path),
            platformOptions: PlatformOptions(),
            input: .none,
            output: .bytes(limit: 50 * 1024 * 1024),  // 50MB limit for large repos
            error: .bytes(limit: 1024)
        )

        switch result.terminationStatus {
        case let .exited(code):
            guard code == 0 else {
                throw GitTrackedClonerError.gitCommandFailed(exitCode: code)
            }
        case .unhandledException:
            throw GitTrackedClonerError.gitCommandCrashed
        }

        guard !result.standardOutput.isEmpty else {
            return []
        }

        let outputString = String(decoding: result.standardOutput, as: UTF8.self)
        return parseNullSeparatedPaths(outputString)
    }

    /// Parses NUL-separated file paths from git ls-files output.
    private func parseNullSeparatedPaths(_ output: String) -> [String] {
        output
            .split(separator: "\0", omittingEmptySubsequences: true)
            .map { String($0) }
    }
}

/// Errors specific to GitTrackedDirectoryCloner.
enum GitTrackedClonerError: Error, Sendable, LocalizedError {
    case gitCommandFailed(exitCode: Int32)
    case gitCommandCrashed
    case notAGitRepository

    var errorDescription: String? {
        switch self {
        case let .gitCommandFailed(exitCode):
            "git ls-files failed with exit code \(exitCode)"
        case .gitCommandCrashed:
            "git ls-files crashed unexpectedly"
        case .notAGitRepository:
            "The directory is not a git repository"
        }
    }
}
