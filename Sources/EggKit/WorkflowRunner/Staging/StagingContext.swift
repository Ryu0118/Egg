import FileSystem
import Foundation
import Noora
import Path
import ProcessRunning

/// Manages a staging environment for atomic workflow execution.
///
/// StagingContext creates a temporary directory that is a clone of the working directory.
/// All workflow operations execute within this staging area. Only when all operations complete
/// successfully are the changes applied back to the real working directory.
///
/// The staging area uses APFS copy-on-write cloning for instant creation regardless of
/// directory size. Changes are detected via filesystem watchers and applied as a
/// partial diff.
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
    let root: AbsolutePath

    /// Reference workspace directory (clean clone for comparison).
    /// Used to detect actual file changes vs. mere file access events.
    let reference: AbsolutePath

    /// The original working directory that was cloned.
    let originalWorkingDirectory: AbsolutePath

    /// File system for all operations.
    /// Note: Using nonisolated(unsafe) because FileSystem is actually Sendable
    /// and all its methods are thread-safe. This avoids false positive data race
    /// warnings when calling nonisolated async methods from actor context.
    private nonisolated(unsafe) let fileSystem: any FileSysteming

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

    /// Noora instance for logging output.
    private nonisolated(unsafe) let noora: any Noorable

    private init(
        root: AbsolutePath,
        reference: AbsolutePath,
        originalWorkingDirectory: AbsolutePath,
        fileSystem: sending any FileSysteming,
        workspaceWatcher: any DirectoryWatching,
        workingDirectoryWatcher: any DirectoryWatching,
        processRunner: any ProcessRunning,
        directoryCloner: any DirectoryCloning,
        noora: any Noorable
    ) {
        self.root = root
        self.reference = reference
        self.originalWorkingDirectory = originalWorkingDirectory
        self.fileSystem = fileSystem
        self.workspaceWatcher = workspaceWatcher
        self.workingDirectoryWatcher = workingDirectoryWatcher
        self.processRunner = processRunner
        self.directoryCloner = directoryCloner
        self.noora = noora
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
    ///   - homeDirectory: User's home directory (for ~/.eggs/workspaces/)
    ///   - fileSystem: File system for operations
    ///   - workspaceWatcher: Watcher for staging changes
    ///   - workingDirectoryWatcher: Watcher for working directory changes
    ///   - processRunner: Process runner for git operations
    ///   - directoryCloner: Cloner for creating staging copy (defaults to APFS cloner)
    /// - Returns: A new StagingContext with cloned directories
    /// - Throws: StagingContext.Error.creationFailed on file system errors
    static func create(
        cloning workingDirectory: AbsolutePath,
        homeDirectory: AbsolutePath,
        fileSystem: any FileSysteming,
        workspaceWatcher: some DirectoryWatching,
        workingDirectoryWatcher: some DirectoryWatching,
        processRunner: some ProcessRunning,
        directoryCloner: some DirectoryCloning = APFSDirectoryCloner(),
        noora: some Noorable = Noora()
    ) async throws -> StagingContext {
        // Wrap in nonisolated(unsafe) to avoid false-positive Sendable warnings.
        // FileSystem and Noora are actually thread-safe and all their methods are nonisolated.
        nonisolated(unsafe) let fs = fileSystem
        nonisolated(unsafe) let nra = noora

        do {
            // Create staging base directory in ~/.eggs/workspaces/{uuid}/
            let workspacesDirectory = homeDirectory.appending(components: ".eggs", "workspaces")
            let workspaceBaseDirectory = workspacesDirectory.appending(component: UUID().uuidString)
            let workDirectory = workspaceBaseDirectory.appending(component: "work")
            let referenceDirectory = workspaceBaseDirectory.appending(component: "reference")

            try await fs.makeDirectory(at: workspacesDirectory)
            try await fs.makeDirectory(at: workspaceBaseDirectory)

            // Create work workspace (where modifications happen)
            async let workDirCloning: () = try directoryCloner.clone(from: workingDirectory.asURL, to: workDirectory.asURL)
            // Create reference workspace (clean copy for comparison)
            async let referenceDirCloning: () = try directoryCloner.clone(from: workingDirectory.asURL, to: referenceDirectory.asURL)

            _ = try await (workDirCloning, referenceDirCloning)

            // Start watchers immediately after cloning
            try await workspaceWatcher.start(watching: workDirectory)
            try await workingDirectoryWatcher.start(watching: workingDirectory)

            return StagingContext(
                root: workDirectory,
                reference: referenceDirectory,
                originalWorkingDirectory: workingDirectory,
                fileSystem: fs,
                workspaceWatcher: workspaceWatcher,
                workingDirectoryWatcher: workingDirectoryWatcher,
                processRunner: processRunner,
                directoryCloner: directoryCloner,
                noora: nra
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
    func validatePath(_ path: AbsolutePath) throws {
        guard !isDiscarded else {
            throw StagingContext.Error.alreadyDiscarded
        }

        // Path library automatically normalizes paths during initialization,
        // resolving .. and . components syntactically.
        // Use isDescendantOfOrEqual to check if path is within staging area.
        guard path.isDescendantOfOrEqual(to: root) else {
            throw StagingContext.Error.escapeAttempt(path: path.pathString)
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
        try await ApplyStagingArea.withStaging(
            workspaceRoot: root,
            workingDirectory: originalWorkingDirectory,
            fileSystem: fileSystem
        ) { staging, fileSystem in
            let manifest = try await staging.stage(changes: changes, fileSystem: fileSystem)
            try await staging.apply(manifest: manifest, fileSystem: fileSystem)
        }

        await discard()

        return conflicts
    }

    /// Discards the staging area without applying changes.
    ///
    /// Removes all staging contents (both work and reference directories) and stops watchers.
    /// Safe to call multiple times (idempotent).
    func discard() async {
        guard !isDiscarded else { return }

        noora.passthrough("🗑️ Discarding staging area at \(root.pathString)...\n")

        // Stop watchers
        await workspaceWatcher.stop()
        await workingDirectoryWatcher.stop()

        isDiscarded = true

        // Remove the parent staging directory (contains both work and reference)
        // root is ~/.eggs/workspaces/{uuid}/work, so parent is ~/.eggs/workspaces/{uuid}
        let workspaceBaseDirectory = root.parentDirectory
        try? await fileSystem.remove(workspaceBaseDirectory)
    }

    /// Returns whether the staging area has been discarded.
    var discarded: Bool {
        isDiscarded
    }
}

extension StagingContext {
    /// Directories that should be excluded from change detection and conflict checks.
    private static let excludedDirectories: Set<String> = [".git", ".eggs"]

    /// Returns true if the path should be excluded from change detection.
    private static func shouldExclude(_ path: RelativePath) -> Bool {
        guard let first = path.components.first else { return false }
        return excludedDirectories.contains(first)
    }

    private struct WatcherEvents: Sendable {
        let workspace: Set<RelativePath>
        let working: Set<RelativePath>

        var targetPaths: Set<RelativePath> {
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
        let workspacePaths = events.workspace.filter { !Self.shouldExclude($0) }

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
        let diffRunner = GitDiffRunner(processRunner: processRunner, fileSystem: fileSystem)
        return try await diffRunner.computeChanges(
            workspaceRoot: root,
            workingDirectory: reference,
            targetPaths: expandedPaths
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

        // Filter out excluded directory paths (e.g., .git, .eggs)
        let workingPaths = events.working.filter { !Self.shouldExclude($0) }

        guard !workingPaths.isEmpty else {
            return .none
        }

        // Expand directories to include their contents recursively
        let expandedPaths = try await expandDirectories(workingPaths, relativeTo: originalWorkingDirectory)

        guard !expandedPaths.isEmpty else {
            return .none
        }

        // Compare working directory against reference workspace to detect actual changes
        let diffRunner = GitDiffRunner(processRunner: processRunner, fileSystem: fileSystem)
        return try await diffRunner.computeChanges(
            workspaceRoot: originalWorkingDirectory,
            workingDirectory: reference,
            targetPaths: expandedPaths
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
        _ paths: Set<RelativePath>,
        relativeTo baseDirectory: AbsolutePath
    ) async throws -> Set<RelativePath> {
        var expandedPaths = Set<RelativePath>()

        for relativePath in paths {
            let absolutePath = baseDirectory.appending(relativePath)

            // Check if path exists and is a directory
            let isDirectory = (try? await fileSystem.exists(absolutePath, isDirectory: true)) ?? false

            if isDirectory {
                // Recursively enumerate all files in the directory
                let contents = try await enumerateDirectoryRecursively(absolutePath, relativeTo: baseDirectory)
                expandedPaths.formUnion(contents)
                // Also include the directory itself (for detecting directory additions)
                expandedPaths.insert(relativePath)
            } else {
                // Regular file, include as-is
                expandedPaths.insert(relativePath)
            }
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
        _ directory: AbsolutePath,
        relativeTo baseDirectory: AbsolutePath
    ) async throws -> Set<RelativePath> {
        var result = Set<RelativePath>()

        let contents = try await fileSystem.contentsOfDirectory(directory)

        for item in contents {
            // Compute relative path from base directory
            let relativePathString = item.pathString.replacingOccurrences(
                of: baseDirectory.pathString + "/",
                with: ""
            )

            guard let relativePath = try? RelativePath(validating: relativePathString) else {
                continue
            }

            // Skip excluded paths
            guard !Self.shouldExclude(relativePath) else {
                continue
            }

            result.insert(relativePath)

            // Recurse into subdirectories
            let isSubdirectory = (try? await fileSystem.exists(item, isDirectory: true)) ?? false
            if isSubdirectory {
                let subcontents = try await enumerateDirectoryRecursively(item, relativeTo: baseDirectory)
                result.formUnion(subcontents)
            }
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
        workingDirectoryChanges: ChangeSummary
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
            return ConflictInfo(path: path, type: type)
        }

        return conflicts.sorted { $0.path.pathString < $1.path.pathString }
    }

    private func stopWatchers() async {
        await workspaceWatcher.stop()
        await workingDirectoryWatcher.stop()
    }
}
