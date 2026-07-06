import AsyncOperations
import FileManagerProtocol
import Foundation
import ProcessRunning
import Subprocess

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

    init(
        processRunner: some ProcessRunning = ProcessRunner(),
        fileManager: some FileManagerProtocol = FileManager.default,
        apfsCloner: some DirectoryCloning = APFSDirectoryCloner(),
    ) {
        self.processRunner = processRunner
        self.fileManager = fileManager
        self.apfsCloner = apfsCloner
        gitRepositoryChecker = GitRepositoryChecker(processRunner: processRunner)
    }

    func clone(from source: URL, to destination: URL) async throws {
        guard source.isFileURL, destination.isFileURL else {
            throw CloningError.invalidURL
        }

        // Check if source is a git repository
        guard await gitRepositoryChecker.isGitRepository(source) else {
            // Fall back to APFS cloning for non-git directories — entry by
            // entry, so egg's own .egg records stay out of the clone here
            // too (the whole-directory clone used to re-copy every prior
            // preview's records, compounding on each run).
            try await cloneAllEntries(from: source, to: destination)
            return
        }

        // Get list of tracked and untracked (but not ignored) files
        let files = try await cloneableFiles(in: source)

        guard !files.isEmpty else {
            // No files to clone, just create the destination directory
            try fileManager.createDirectory(
                at: destination,
                withIntermediateDirectories: true,
            )
            return
        }

        // Create destination directory
        try fileManager.createDirectory(
            at: destination,
            withIntermediateDirectories: true,
        )

        // Clone each file using APFS clonefile
        // Filter out files that don't exist in the working directory
        // (git ls-files -c includes deleted files that are still in the index).
        //
        // existsAsLink, not fileExists: a dangling symlink is still a
        // git-tracked, clonable file — fileExists follows the link and
        // reports false for it, which would silently drop it from the clone
        // and leave git's later diff misclassifying it as "added" instead of
        // "modified" at apply time.
        let existingFiles = files.filter { file in
            let sourceFile = source.appending(path: file)
            return fileManager.existsAsLink(sourceFile)
        }

        try await existingFiles.asyncForEach(numberOfConcurrentTasks: 10) { file in
            let sourceFile = source.appending(path: file)
            let destFile = destination.appending(path: file)

            // Create parent directories if needed
            let destParent = destFile.deletingLastPathComponent()
            if destParent != destination {
                try fileManager.createDirectory(
                    at: destParent,
                    withIntermediateDirectories: true,
                )
            }

            try await apfsCloner.clone(from: sourceFile, to: destFile)
        }
    }

    /// Clones every top-level entry of a non-git directory except egg's own
    /// `.egg` bookkeeping. APFS clones directories recursively, so one call
    /// per entry keeps the copy-on-write efficiency of the old
    /// whole-directory clone.
    private func cloneAllEntries(from source: URL, to destination: URL) async throws {
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let entries = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil, options: [])
        for entry in entries where entry.lastPathComponent != ".egg" {
            try await apfsCloner.clone(from: entry, to: destination.appending(path: entry.lastPathComponent))
        }
    }

    /// Lists git-tracked files and untracked files that aren't ignored —
    /// exactly the set `clone(from:to:)` copies. `StagingPreflight` uses the
    /// same enumeration to size a clone before starting it.
    ///
    /// egg's own `.egg/` bookkeeping is excluded outright, the way git
    /// excludes `.git` from its own operations. `.egg` is untracked and its
    /// `transactions/*/work` trees are git repositories of their own, so
    /// `ls-files` reports each as a single entry while a directory clone
    /// copies the whole tree — every preview then re-cloned all prior
    /// previews' records (which nest their own `.egg` snapshots), compounding
    /// ~3x per preview until two user files became millions of staged ones.
    ///
    /// Runs `git ls-files -c -o --exclude-standard` to get:
    /// - `-c`: Cached (tracked) files
    /// - `-o`: Other (untracked) files
    /// - `--exclude-standard`: Respect .gitignore, .git/info/exclude, etc.
    func cloneableFiles(in directory: URL) async throws -> [String] {
        let arguments = [
            "ls-files",
            "-c", // Cached (tracked) files
            "-o", // Other (untracked) files
            "--exclude-standard", // Respect .gitignore
            "-z", // NUL-separated output
        ]

        let result = try await processRunner.run(
            .path("/usr/bin/git"),
            arguments: Arguments(arguments),
            environment: .inherit,
            workingDirectory: FilePath(directory.path),
            platformOptions: PlatformOptions(),
            input: .none,
            output: .bytes(limit: 50 * 1024 * 1024), // 50MB limit for large repos
            error: .bytes(limit: 1024),
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
            .filter { !isEggBookkeepingPath($0) }
    }

    /// True for egg's own `.egg/` transaction/rollback records — never part
    /// of a staging clone, exactly like `.git` is never part of git's view.
    private func isEggBookkeepingPath(_ path: String) -> Bool {
        path == ".egg" || path == ".egg/" || path.hasPrefix(".egg/")
    }

    /// Parses NUL-separated file paths from git ls-files output.
    private func parseNullSeparatedPaths(_ output: String) -> [String] {
        output
            .split(separator: "\0", omittingEmptySubsequences: true)
            .map { String($0) }
    }
}

/// Errors specific to GitTrackedDirectoryCloner.
enum GitTrackedClonerError: Error, LocalizedError {
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
