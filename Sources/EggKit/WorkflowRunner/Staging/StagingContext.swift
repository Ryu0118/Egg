import FileManagerProtocol
import Foundation
import Interaction
import Noora
import ProcessRunning

/// Manages a staging environment for atomic workflow execution.
///
/// StagingContext creates a temporary directory that is a clone of the working directory.
/// All workflow operations execute within this staging area. Only when all operations complete
/// successfully are the changes applied back to the real working directory.
///
/// By default, the staging area only clones git-tracked files (using `git ls-files`),
/// which excludes build caches, node_modules, and other gitignored content.
/// Each file is cloned using APFS copy-on-write for efficiency.
/// Changes are detected via filesystem watchers and applied as a partial diff.
///
/// ## Usage
/// ```swift
/// let workspace = try await StagingContext.create(
///     cloning: workingDirectory,
///     fileSystem: fileSystem
/// )
///
/// // Execute operations in workspace.root
/// // ...
///
/// // Apply changes on success
/// try await workspace.applyChanges(override: false)
///
/// // Or discard on failure
/// await workspace.discard()
/// ```
actor StagingContext {
    /// The staging root directory (clone of workingDirectory) where work is performed.
    let root: URL

    /// Reference workspace directory (clean clone for comparison).
    /// Used to detect actual file changes vs. mere file access events.
    let reference: URL

    /// The original working directory that was cloned.
    let originalWorkingDirectory: URL

    /// File manager for all operations.
    private let fileManager: any FileManagerProtocol

    /// Watcher for staging directory changes.
    private let workspaceWatcher: any DirectoryWatching

    /// Watcher for working directory changes (to detect concurrent modifications).
    private let workingDirectoryWatcher: any DirectoryWatching

    /// Whether the staging area has been discarded.
    private(set) var isDiscarded: Bool = false

    /// Process runner for git diff operations.
    private let processRunner: any ProcessRunning

    /// Directory cloner for creating staging copies.
    private let directoryCloner: any DirectoryCloning

    /// Interaction instance for logging output.
    private let interaction: any InteractionProviding

    /// Noora instance for prompts.
    private let noora: any Noorable

    private init(
        root: URL,
        reference: URL,
        originalWorkingDirectory: URL,
        fileManager: any FileManagerProtocol,
        workspaceWatcher: any DirectoryWatching,
        workingDirectoryWatcher: any DirectoryWatching,
        processRunner: any ProcessRunning,
        directoryCloner: any DirectoryCloning,
        noora: any Noorable,
        interaction: any InteractionProviding,
    ) {
        self.root = root
        self.reference = reference
        self.originalWorkingDirectory = originalWorkingDirectory
        self.fileManager = fileManager
        self.workspaceWatcher = workspaceWatcher
        self.workingDirectoryWatcher = workingDirectoryWatcher
        self.processRunner = processRunner
        self.directoryCloner = directoryCloner
        self.noora = noora
        self.interaction = interaction
    }

    /// Creates a new staging context by cloning the working directory.
    ///
    /// Creates two workspace clones:
    /// 1. **Work workspace (root)**: Where template expansion and modifications occur
    /// 2. **Reference workspace**: Clean copy for detecting actual file changes
    ///
    /// This dual-workspace approach allows accurate change detection by comparing
    /// the work workspace against the reference, filtering out false positives from
    /// FSEvents that trigger on file access (not just modifications).
    ///
    /// - Parameters:
    ///   - workingDirectory: The directory to clone into staging area
    ///   - fileManager: File manager for operations
    ///   - workspaceWatcher: Watcher for staging changes
    ///   - workingDirectoryWatcher: Watcher for working directory changes
    ///   - processRunner: Process runner for git operations
    ///   - directoryCloner: Cloner for creating staging copy (defaults to git-tracked cloner)
    /// - Returns: A new StagingContext with cloned directories
    /// - Throws: StagingContext.Error.creationFailed on file system errors
    static func create(
        cloning workingDirectory: URL,
        fileManager: some FileManagerProtocol,
        workspaceWatcher: some DirectoryWatching,
        workingDirectoryWatcher: some DirectoryWatching,
        processRunner: some ProcessRunning,
        directoryCloner: some DirectoryCloning = GitTrackedDirectoryCloner(),
        requireGitRepository: Bool = true,
        noora: some Noorable = Noora(),
        interaction: some InteractionProviding = Terminal(),
    ) async throws -> StagingContext {
        do {
            // Create staging base directory in a temporary location
            let workspaceBaseDirectory = try fileManager.makeTemporaryDirectory(prefix: "egg-staging")
            let workDirectory = workspaceBaseDirectory.appending(path: "work")
            let referenceDirectory = workspaceBaseDirectory.appending(path: "reference")

            let readyToCopyToStaging: Bool =
                if !requireGitRepository {
                    true
                } else if await !(GitRepositoryChecker(processRunner: processRunner).isGitRepository(workingDirectory)) {
                    // If not under git management, copying all directories may take a very long time.
                    // Proceed anyway? Or consider using --no-staging mode instead.
                    noora.yesOrNoChoicePrompt(
                        title: "Copying All Files May Take Time",
                        question: "The working directory is not under git management. Copying all directories may take a very long time. Proceed anyway? (Consider using --no-staging mode instead)",
                    )
                } else {
                    true
                }

            // If not ready, throw StagingContext.Error.userAborted here.
            guard readyToCopyToStaging else {
                throw StagingContext.Error.userAborted
            }

            // Create work workspace (where modifications happen)
            async let workDirCloning: () = try directoryCloner.clone(from: workingDirectory, to: workDirectory)
            // Create reference workspace (clean copy for comparison)
            async let referenceDirCloning: () = try directoryCloner.clone(from: workingDirectory, to: referenceDirectory)

            _ = try await (workDirCloning, referenceDirCloning)

            // Start watchers immediately after cloning
            try await workspaceWatcher.start(watching: workDirectory)
            try await workingDirectoryWatcher.start(watching: workingDirectory)

            return StagingContext(
                root: workDirectory,
                reference: referenceDirectory,
                originalWorkingDirectory: workingDirectory,
                fileManager: fileManager,
                workspaceWatcher: workspaceWatcher,
                workingDirectoryWatcher: workingDirectoryWatcher,
                processRunner: processRunner,
                directoryCloner: directoryCloner,
                noora: noora,
                interaction: interaction,
            )
        } catch let error as StagingContext.Error {
            throw error
        } catch {
            throw StagingContext.Error.creationFailed(reason: error.localizedDescription)
        }
    }

    /// Validates that a path is within staging boundaries.
    ///
    /// This method performs syntactic validation only (no filesystem access).
    /// It checks that the path, after normalization, is a descendant of the staging root.
    ///
    /// - Parameter path: Absolute path to validate
    /// - Throws: StagingContext.Error.escapeAttempt if path escapes staging area
    func validatePath(_ path: URL) throws {
        guard !isDiscarded else {
            throw StagingContext.Error.alreadyDiscarded
        }

        func normalizedComponents(for url: URL) -> [String] {
            var components = url.standardizedFileURL.pathComponents
            if components.count > 2, components[1] == "private", components[2] == "var" {
                components.remove(at: 1)
            }
            return components
        }

        let pathComponents = normalizedComponents(for: path)
        let rootComponents = normalizedComponents(for: root)

        let isWithinRoot =
            pathComponents.count >= rootComponents.count &&
            zip(rootComponents, pathComponents).allSatisfy { $0 == $1 }

        guard isWithinRoot else {
            throw StagingContext.Error.escapeAttempt(path: path.path(percentEncoded: false))
        }
    }

    /// Computes the summary of changes between staging area and original working directory.
    ///
    /// This method drains watcher events and uses git diff to determine which files
    /// were added, modified, or deleted in the staging area compared to the original.
    ///
    /// - Returns: Summary of changes to be applied
    /// - Throws: StagingContext.Error.alreadyDiscarded if staging area was already discarded
    func computeChangeSummary() async throws -> ChangeSummary {
        let events = try await collectWatcherEvents()
        return try await computeChangeSummary(using: events)
    }

    /// Detects actual conflicts by comparing both staging area and working directory against reference.
    ///
    /// A conflict is detected when the same file was actually modified in both:
    /// - The work workspace (compared to reference workspace)
    /// - The working directory (compared to reference workspace)
    ///
    /// This filters out false positives from FSEvents that trigger on file access.
    ///
    /// - Returns: List of actual conflicts
    func detectConflicts() async throws -> [ConflictInfo] {
        let events = try await collectWatcherEvents()
        let workspaceChanges = try await computeChangeSummary(using: events)
        let workingChanges = try await computeWorkingDirectoryChanges(using: events)
        return detectConflicts(using: events, changeSummary: workspaceChanges, workingDirectoryChanges: workingChanges)
    }

    /// Applies staging changes to the original working directory.
    ///
    /// Uses the provided change summary (from `computeChangeSummary()`) and applies:
    /// - New files: Added to working directory
    /// - Modified files: Updated in working directory
    /// - Deleted files: Removed from working directory
    ///
    /// Uses a two-phase staging approach:
    /// 1. Stage: Materialize all changes in a temporary staging area
    /// 2. Apply: Transfer staged changes to working directory
    ///
    /// - Parameters:
    ///   - changes: The change summary to apply (obtained from `computeChangeSummary()`)
    ///   - override: If true, override conflicts with warning. If false, throw error on conflicts.
    /// - Returns: List of conflicts that were overridden (empty if no conflicts or override=false)
    /// - Throws: StagingContext.Error.conflictingFiles if conflicts detected and override=false
    func applyChanges(_ changes: ChangeSummary, override: Bool) async throws -> [ConflictInfo] {
        guard !isDiscarded else {
            throw StagingContext.Error.alreadyDiscarded
        }

        // Collect watcher events to detect working directory conflicts
        let events = try await collectWatcherEvents()

        // Compute actual working directory changes (compare against reference)
        let workingChanges = try await computeWorkingDirectoryChanges(using: events)

        // Detect conflicts: paths modified in both staging area and working directory
        let conflicts = detectConflicts(using: events, changeSummary: changes, workingDirectoryChanges: workingChanges)

        // Handle conflicts
        if !conflicts.isEmpty, !override {
            throw StagingContext.Error.conflictingFiles(conflicts)
        }

        // Skip if no changes
        guard !changes.isEmpty else {
            await discard()
            return conflicts
        }

        // Stage and apply changes with guaranteed cleanup
        try ApplyStagingArea.withStaging(
            workspaceRoot: root,
            workingDirectory: originalWorkingDirectory,
            fileManager: fileManager,
        ) { staging, fileManager in
            let manifest = try staging.stage(changes: changes, fileManager: fileManager)
            try staging.apply(manifest: manifest, fileManager: fileManager)
        }

        await discard()

        return conflicts
    }

    /// Discards the staging area without applying changes.
    ///
    /// Removes the temporary staging directory.
    /// Safe to call multiple times (idempotent).
    func discard() async {
        guard !isDiscarded else { return }

        interaction.writeLine("🗑️ Discarding staging workspace...")

        // Stop watchers
        await workspaceWatcher.stop()
        await workingDirectoryWatcher.stop()

        isDiscarded = true

        // Remove the parent staging directory (contains both work and reference)
        // root is /tmp/egg-staging-{uuid}/work, so parent is /tmp/egg-staging-{uuid}
        let workspaceBaseDirectory = root.deletingLastPathComponent()
        try? fileManager.removeItem(at: workspaceBaseDirectory)
    }
}

extension StagingContext {
    private struct WatcherEvents {
        let workspace: Set<String>
        let working: Set<String>

        var targetPaths: Set<String> {
            workspace.union(working)
        }
    }

    private func collectWatcherEvents() async throws -> WatcherEvents {
        guard !isDiscarded else {
            throw StagingContext.Error.alreadyDiscarded
        }

        let workspaceTouched = await workspaceWatcher.drainEvents()
        let workingTouched = await workingDirectoryWatcher.drainEvents()

        return WatcherEvents(workspace: workspaceTouched, working: workingTouched)
    }

    /// Computes actual changes in the work workspace by comparing against the reference workspace.
    ///
    /// For each path detected by FSEvents, we check if the file actually changed by comparing
    /// the work workspace against the reference workspace. This filters out false positives from
    /// FSEvents that trigger on file access (read) rather than actual modifications.
    ///
    /// When FSEvents reports a directory (e.g., when a directory is moved into the watched area),
    /// we recursively expand it to include all files within, since FSEvents only reports the
    /// top-level directory, not its contents.
    private nonisolated func computeChangeSummary(using events: WatcherEvents) async throws -> ChangeSummary {
        guard await !isDiscarded else {
            throw StagingContext.Error.alreadyDiscarded
        }

        // Filter out excluded directory paths (e.g., .git, .eggs)
        let workspacePaths = events.workspace

        guard !workspacePaths.isEmpty else {
            return .none
        }

        // Expand directories to include their contents recursively
        // FSEvents only reports directory-level events when directories are moved,
        // so we need to enumerate contents to detect all file changes
        let expandedPaths = try await expandDirectories(workspacePaths, relativeTo: root)

        guard !expandedPaths.isEmpty else {
            return .none
        }

        // Compare work workspace against reference workspace to detect actual changes
        let diffRunner = GitDiffRunner(processRunner: processRunner, fileManager: fileManager)
        return try await diffRunner.computeChanges(
            workspaceRoot: root,
            workingDirectory: reference,
            targetPaths: expandedPaths,
        )
    }

    /// Computes actual changes in the working directory by comparing against the reference workspace.
    ///
    /// For each path detected by FSEvents in the working directory, we check if the file actually
    /// changed by comparing against the reference workspace. This filters out false positives from
    /// FSEvents that trigger on file access (read) rather than actual modifications.
    ///
    /// When FSEvents reports a directory, we recursively expand it to include all files within.
    private nonisolated func computeWorkingDirectoryChanges(using events: WatcherEvents) async throws -> ChangeSummary {
        guard await !isDiscarded else {
            throw StagingContext.Error.alreadyDiscarded
        }

        let workingPaths = events.working

        guard !workingPaths.isEmpty else {
            return .none
        }

        // Expand directories to include their contents recursively
        let expandedPaths = try await expandDirectories(workingPaths, relativeTo: originalWorkingDirectory)

        guard !expandedPaths.isEmpty else {
            return .none
        }

        // Compare working directory against reference workspace to detect actual changes
        let diffRunner = GitDiffRunner(processRunner: processRunner, fileManager: fileManager)
        return try await diffRunner.computeChanges(
            workspaceRoot: originalWorkingDirectory,
            workingDirectory: reference,
            targetPaths: expandedPaths,
        )
    }

    /// Expands a set of relative paths by recursively enumerating directory contents.
    ///
    /// When FSEvents reports a directory (e.g., when it's moved into the watched area),
    /// it only reports the directory itself, not its contents. This method expands such
    /// directories to include all files within them.
    ///
    /// - Parameters:
    ///   - paths: Set of relative paths reported by FSEvents
    ///   - baseDirectory: The base directory to resolve relative paths against
    /// - Returns: Expanded set of relative paths including all files within directories
    private nonisolated func expandDirectories(
        _ paths: Set<String>,
        relativeTo baseDirectory: URL,
    ) async throws -> Set<String> {
        var expandedPaths = Set<String>()

        for relativePath in paths {
            let absolutePath = baseDirectory.appending(path: relativePath)

            // Check if path exists and is a directory
            let isDir = fileManager.isDirectory(at: absolutePath)

            if isDir {
                // Recursively enumerate all files in the directory
                let contents = try enumerateDirectoryRecursively(absolutePath, relativeTo: baseDirectory)
                expandedPaths.formUnion(contents)
            }
            expandedPaths.insert(relativePath)
        }

        return expandedPaths
    }

    /// Recursively enumerates all files and directories within the given directory.
    ///
    /// - Parameters:
    ///   - directory: The directory to enumerate
    ///   - baseDirectory: The base directory for computing relative paths
    /// - Returns: Set of relative paths for all items within the directory
    private nonisolated func enumerateDirectoryRecursively(
        _ directory: URL,
        relativeTo baseDirectory: URL,
    ) throws -> Set<String> {
        var result = Set<String>()

        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [],
            errorHandler: nil,
        ) else {
            return result
        }

        let basePath = baseDirectory.path(percentEncoded: false) + "/"

        while let item = enumerator.nextObject() as? URL {
            let relativePathString = item.path(percentEncoded: false)
                .replacingOccurrences(of: basePath, with: "")

            result.insert(relativePathString)
        }

        return result
    }

    /// Detects conflicts by comparing both working directory and staging changes against reference.
    ///
    /// A conflict occurs when:
    /// 1. A file was actually modified in the working directory (compared to reference)
    /// 2. The same file was also actually modified in the staging area (in changeSummary)
    ///
    /// This filters out false positives from FSEvents that trigger on file access.
    private func detectConflicts(
        using _: WatcherEvents,
        changeSummary: ChangeSummary,
        workingDirectoryChanges: ChangeSummary,
    ) -> [ConflictInfo] {
        // Get paths that were actually modified in working directory
        let actualWorkingChanges = Set(workingDirectoryChanges.allPaths)
        guard !actualWorkingChanges.isEmpty else { return [] }

        // Get paths that were actually modified in staging area
        let actualWorkspaceChanges = Set(changeSummary.allPaths)

        // Conflicts are paths modified in both
        let conflictPaths = actualWorkingChanges.intersection(actualWorkspaceChanges)
        guard !conflictPaths.isEmpty else { return [] }

        let deletedInWorkspace = Set(changeSummary.deleted)

        let conflicts = conflictPaths.map { path -> ConflictInfo in
            let type: ConflictInfo.ConflictType = deletedInWorkspace.contains(path) ? .deletedButModified : .bothModified
            return ConflictInfo(pathString: path, type: type)
        }

        return conflicts.sorted { $0.pathString < $1.pathString }
    }

    private func stopWatchers() async {
        await workspaceWatcher.stop()
        await workingDirectoryWatcher.stop()
    }
}
