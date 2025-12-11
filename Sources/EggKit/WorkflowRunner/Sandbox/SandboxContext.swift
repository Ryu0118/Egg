import FileSystem
import Foundation
import Path
import ProcessRunning

/// Manages a sandboxed environment for atomic workflow execution.
///
/// SandboxContext creates a temporary directory that is a clone of the working directory.
/// All workflow operations execute within this sandbox. Only when all operations complete
/// successfully are the changes applied back to the real working directory.
///
/// The sandbox uses APFS copy-on-write cloning for instant creation regardless of
/// directory size. Changes are detected via filesystem watchers and applied as a
/// partial diff.
///
/// ## Usage
/// ```swift
/// let sandbox = try await SandboxContext.create(
///     cloning: workingDirectory,
///     fileSystem: fileSystem
/// )
///
/// // Execute operations in sandbox.root
/// // ...
///
/// // Apply changes on success
/// try await sandbox.applyChanges(force: false)
///
/// // Or discard on failure
/// await sandbox.discard()
/// ```
actor SandboxContext {
    /// The sandbox root directory (clone of workingDirectory).
    let root: AbsolutePath

    /// The original working directory that was cloned.
    let originalWorkingDirectory: AbsolutePath

    /// File system for all operations.
    /// Note: Using nonisolated(unsafe) because FileSystem is actually Sendable
    /// and all its methods are thread-safe. This avoids false positive data race
    /// warnings when calling nonisolated async methods from actor context.
    private nonisolated(unsafe) let fileSystem: any FileSysteming

    /// Watcher for sandbox directory changes.
    private let sandboxWatcher: any DirectoryWatching

    /// Watcher for working directory changes (to detect concurrent modifications).
    private let workingDirectoryWatcher: any DirectoryWatching

    /// Whether the sandbox has been discarded.
    private(set) var isDiscarded: Bool = false

    /// Process runner for git diff operations.
    private let processRunner: any ProcessRunning

    /// Directory cloner for creating sandbox copies.
    private let directoryCloner: any DirectoryCloning

    private init(
        root: AbsolutePath,
        originalWorkingDirectory: AbsolutePath,
        fileSystem: sending any FileSysteming,
        sandboxWatcher: any DirectoryWatching,
        workingDirectoryWatcher: any DirectoryWatching,
        processRunner: any ProcessRunning,
        directoryCloner: any DirectoryCloning
    ) {
        self.root = root
        self.originalWorkingDirectory = originalWorkingDirectory
        self.fileSystem = fileSystem
        self.sandboxWatcher = sandboxWatcher
        self.workingDirectoryWatcher = workingDirectoryWatcher
        self.processRunner = processRunner
        self.directoryCloner = directoryCloner
    }

    /// Creates a new sandbox context by cloning the working directory.
    ///
    /// - Parameters:
    ///   - workingDirectory: The directory to clone into sandbox
    ///   - homeDirectory: User's home directory (for ~/.eggs/sandboxes/)
    ///   - fileSystem: File system for operations
    ///   - sandboxWatcher: Watcher for sandbox changes
    ///   - workingDirectoryWatcher: Watcher for working directory changes
    ///   - processRunner: Process runner for git operations
    ///   - directoryCloner: Cloner for creating sandbox copy (defaults to APFS cloner)
    /// - Returns: A new SandboxContext with cloned directory
    /// - Throws: SandboxContext.Error.creationFailed on file system errors
    static func create(
        cloning workingDirectory: AbsolutePath,
        homeDirectory: AbsolutePath,
        fileSystem: any FileSysteming,
        sandboxWatcher: some DirectoryWatching,
        workingDirectoryWatcher: some DirectoryWatching,
        processRunner: some ProcessRunning,
        directoryCloner: some DirectoryCloning = APFSDirectoryCloner()
    ) async throws -> SandboxContext {
        // Wrap in nonisolated(unsafe) to avoid false-positive Sendable warnings.
        // FileSystem is actually thread-safe and all its methods are nonisolated.
        nonisolated(unsafe) let fs = fileSystem

        do {
            // Create sandbox in ~/.eggs/sandboxes/{uuid}/
            let sandboxesDirectory = homeDirectory.appending(components: ".eggs", "sandboxes")
            try await fs.makeDirectory(at: sandboxesDirectory)
            let sandboxDirectory = sandboxesDirectory.appending(component: UUID().uuidString)

            // Clone entire working directory using the provided cloner
            try directoryCloner.clone(from: workingDirectory.asURL, to: sandboxDirectory.asURL)

            // Start watchers immediately after cloning
            try await sandboxWatcher.start(watching: sandboxDirectory)
            try await workingDirectoryWatcher.start(watching: workingDirectory)

            return SandboxContext(
                root: sandboxDirectory,
                originalWorkingDirectory: workingDirectory,
                fileSystem: fs,
                sandboxWatcher: sandboxWatcher,
                workingDirectoryWatcher: workingDirectoryWatcher,
                processRunner: processRunner,
                directoryCloner: directoryCloner
            )
        } catch let error as SandboxContext.Error {
            throw error
        } catch {
            throw SandboxContext.Error.creationFailed(reason: error.localizedDescription)
        }
    }

    /// Validates that a path is within sandbox boundaries.
    ///
    /// This method performs syntactic validation only (no filesystem access).
    /// It checks that the path, after normalization, is a descendant of the sandbox root.
    ///
    /// - Parameter path: Absolute path to validate
    /// - Throws: SandboxContext.Error.escapeAttempt if path escapes sandbox
    func validatePath(_ path: AbsolutePath) throws {
        guard !isDiscarded else {
            throw SandboxContext.Error.alreadyDiscarded
        }

        // Path library automatically normalizes paths during initialization,
        // resolving .. and . components syntactically.
        // Use isDescendantOfOrEqual to check if path is within sandbox.
        guard path.isDescendantOfOrEqual(to: root) else {
            throw SandboxContext.Error.escapeAttempt(path: path.pathString)
        }
    }

    /// Computes the summary of changes between sandbox and original working directory.
    ///
    /// This method drains watcher events and uses git diff to determine which files
    /// were added, modified, or deleted in the sandbox compared to the original.
    ///
    /// - Returns: Summary of changes to be applied
    /// - Throws: SandboxContext.Error.alreadyDiscarded if sandbox was already discarded
    func computeChangeSummary() async throws -> ChangeSummary {
        let events = try await collectWatcherEvents()
        return try await computeChangeSummary(using: events)
    }

    /// Detects potential conflicts by checking if the working directory was modified.
    ///
    /// Any path that appears in the working directory watcher is treated as a
    /// potential conflict, regardless of the diff outcome.
    ///
    /// - Returns: List of potential conflicts
    func detectConflicts() async throws -> [ConflictInfo] {
        let events = try await collectWatcherEvents()
        let summary = try await computeChangeSummary(using: events)
        return detectConflicts(using: events, changeSummary: summary)
    }

    /// Applies sandbox changes to the original working directory.
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
    ///   - force: If true, override conflicts with warning. If false, throw error on conflicts.
    /// - Returns: List of conflicts that were overridden (empty if no conflicts or force=false)
    /// - Throws: SandboxContext.Error.conflictingFiles if conflicts detected and force=false
    func applyChanges(_ changes: ChangeSummary, force: Bool) async throws -> [ConflictInfo] {
        guard !isDiscarded else {
            throw SandboxContext.Error.alreadyDiscarded
        }

        // Collect watcher events to detect working directory conflicts
        let events = try await collectWatcherEvents()

        // Detect conflicts based on watcher events
        let conflicts = detectConflicts(using: events, changeSummary: changes)

        // Handle conflicts
        if !conflicts.isEmpty, !force {
            throw SandboxContext.Error.conflictingFiles(conflicts)
        }

        // Skip if no changes
        guard !changes.isEmpty else {
            await discard()
            return conflicts
        }

        // Stage and apply changes with guaranteed cleanup
        try await ApplyStagingArea.withStaging(
            sandboxRoot: root,
            workingDirectory: originalWorkingDirectory,
            fileSystem: fileSystem
        ) { staging, fileSystem in
            let manifest = try await staging.stage(changes: changes, fileSystem: fileSystem)
            try await staging.apply(manifest: manifest, fileSystem: fileSystem)
        }

        await discard()

        return conflicts
    }

    /// Discards the sandbox without applying changes.
    ///
    /// Removes all sandbox contents and stops watchers. Safe to call multiple times (idempotent).
    func discard() async {
        guard !isDiscarded else { return }

        // Stop watchers
        await sandboxWatcher.stop()
        await workingDirectoryWatcher.stop()

        isDiscarded = true
        try? await fileSystem.remove(root)
    }

    /// Returns whether the sandbox has been discarded.
    var discarded: Bool {
        isDiscarded
    }
}

extension SandboxContext {
    /// Directories that should be excluded from change detection and conflict checks.
    private static let excludedDirectories: Set<String> = [".git", ".eggs"]

    /// Returns true if the path should be excluded from change detection.
    private static func shouldExclude(_ path: RelativePath) -> Bool {
        guard let first = path.components.first else { return false }
        return excludedDirectories.contains(first)
    }

    private struct WatcherEvents: Sendable {
        let sandbox: Set<RelativePath>
        let working: Set<RelativePath>

        var targetPaths: Set<RelativePath> {
            sandbox.union(working)
        }
    }

    private func collectWatcherEvents() async throws -> WatcherEvents {
        guard !isDiscarded else {
            throw SandboxContext.Error.alreadyDiscarded
        }

        let sandboxTouched = await sandboxWatcher.drainEvents()
        let workingTouched = await workingDirectoryWatcher.drainEvents()

        return WatcherEvents(sandbox: sandboxTouched, working: workingTouched)
    }

    private nonisolated func computeChangeSummary(using events: WatcherEvents) async throws -> ChangeSummary {
        guard await !isDiscarded else {
            throw SandboxContext.Error.alreadyDiscarded
        }

        // Filter out excluded directory paths (e.g., .git, .eggs)
        let targetPaths = events.targetPaths.filter { !Self.shouldExclude($0) }

        guard !targetPaths.isEmpty else {
            return .none
        }

        let diffRunner = GitDiffRunner(processRunner: processRunner, fileSystem: fileSystem)
        return try await diffRunner.computeChanges(
            sandboxRoot: root,
            workingDirectory: originalWorkingDirectory,
            targetPaths: targetPaths
        )
    }

    private func detectConflicts(
        using events: WatcherEvents,
        changeSummary: ChangeSummary
    ) -> [ConflictInfo] {
        // Filter out excluded directories from working directory changes
        let workingChanges = events.working.filter { !Self.shouldExclude($0) }
        guard !workingChanges.isEmpty else { return [] }

        let deletedPaths = Set(changeSummary.deleted)

        let conflicts = workingChanges.map { path -> ConflictInfo in
            let type: ConflictInfo.ConflictType = deletedPaths.contains(path) ? .deletedButModified : .bothModified
            return ConflictInfo(path: path, type: type)
        }

        return conflicts.sorted { $0.path.pathString < $1.path.pathString }
    }

    private func stopWatchers() async {
        await sandboxWatcher.stop()
        await workingDirectoryWatcher.stop()
    }
}
