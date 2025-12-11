import FileSystem
import Foundation
import Path

/// Manages a temporary staging area for applying transactional workspace changes atomically.
///
/// The staging area provides a two-phase commit for transactional workspace changes:
/// 1. Stage: Materialize all changes (adds/modifies/deletes) in a temporary directory
/// 2. Apply: Transfer staged changes to the working directory
///
/// If staging fails, no changes are made to the working directory.
/// If apply fails mid-way, the staging area contains rollback information.
///
struct ApplyStagingArea {
    /// The root directory of the staging area.
    let root: AbsolutePath

    /// The transactional workspace root directory (source of changes).
    let workspaceRoot: AbsolutePath

    /// The original working directory (destination of changes).
    let workingDirectory: AbsolutePath

    private var stagedPayloadRoot: AbsolutePath {
        root.appending(component: "staged")
    }

    private var backupRoot: AbsolutePath {
        root.appending(component: "backup")
    }

    private init(root: AbsolutePath, workspaceRoot: AbsolutePath, workingDirectory: AbsolutePath) {
        self.root = root
        self.workspaceRoot = workspaceRoot
        self.workingDirectory = workingDirectory
    }

    /// Creates a new staging area within the transactional workspace directory.
    ///
    /// - Parameters:
    ///   - workspaceRoot: The transactional workspace root directory
    ///   - workingDirectory: The original working directory
    ///   - fileSystem: File system for operations
    /// - Returns: A new ApplyStagingArea
    static func create(
        workspaceRoot: AbsolutePath,
        workingDirectory: AbsolutePath,
        fileSystem: any FileSysteming
    ) async throws -> ApplyStagingArea {
        // Create staging directory under system temporary directory with unique prefix
        let stagingRoot = try await fileSystem.makeTemporaryDirectory(prefix: "egg-apply-staging")

        let area = ApplyStagingArea(
            root: stagingRoot,
            workspaceRoot: workspaceRoot,
            workingDirectory: workingDirectory
        )

        try await area.ensureBaseDirectories(fileSystem: fileSystem)
        return area
    }

    /// Executes staging operations with guaranteed cleanup.
    ///
    /// This method creates a staging area, executes the provided closure, and ensures
    /// the staging area is cleaned up regardless of success or failure.
    ///
    /// The closure receives both the staging area and the file system to avoid
    /// capturing actor-isolated state, which would cause Swift 6 concurrency errors.
    ///
    /// - Parameters:
    ///   - workspaceRoot: The transactional workspace root directory
    ///   - workingDirectory: The original working directory
    ///   - fileSystem: File system for operations
    ///   - body: Closure that receives the staging area and file system
    /// - Returns: The result of the closure
    /// - Throws: Any error thrown by the closure or staging area creation
    static func withStaging<T: Sendable>(
        workspaceRoot: AbsolutePath,
        workingDirectory: AbsolutePath,
        fileSystem: any FileSysteming,
        body: @Sendable (ApplyStagingArea, any FileSysteming) async throws -> T
    ) async throws -> T {
        let staging = try await create(
            workspaceRoot: workspaceRoot,
            workingDirectory: workingDirectory,
            fileSystem: fileSystem
        )

        do {
            let result = try await body(staging, fileSystem)
            await staging.cleanup(fileSystem: fileSystem)
            return result
        } catch {
            await staging.cleanup(fileSystem: fileSystem)
            throw error
        }
    }

    /// Stages all changes from the transactional workspace based on the change summary.
    ///
    /// This method prepares all file operations without touching the working directory:
    /// - Copies new/modified files from transactional workspace to staging area
    /// - Records deletions in the manifest
    ///
    /// - Parameters:
    ///   - changes: The change summary describing what to apply
    ///   - fileSystem: File system for operations
    /// - Returns: Manifest describing staged changes
    /// - Throws: If staging fails
    func stage(
        changes: ChangeSummary,
        fileSystem: any FileSysteming
    ) async throws -> ChangeManifest {
        try await ensureBaseDirectories(fileSystem: fileSystem)

        var entries: [ChangeEntry] = []
        entries.reserveCapacity(changes.totalCount)

        try entries.append(contentsOf: await stageAddedFiles(changes.added, fileSystem: fileSystem))
        try entries.append(contentsOf: await stageModifiedFiles(changes.modified, fileSystem: fileSystem))
        try entries.append(contentsOf: await stageDeletedFiles(changes.deleted, fileSystem: fileSystem))

        return ChangeManifest(entries: entries)
    }

    /// Applies staged changes to the working directory.
    ///
    /// Changes are applied in order: Deletes → Adds → Modifies
    /// This order minimizes conflicts and ensures clean state.
    ///
    /// - Parameter fileSystem: File system for operations
    /// - Throws: If apply fails
    func apply(
        manifest: ChangeManifest,
        fileSystem: any FileSysteming
    ) async throws {
        let deleteEntries = manifest.entries.filter { $0.kind == .delete }
        let addEntries = manifest.entries.filter { $0.kind == .add }
        let modifyEntries = manifest.entries.filter { $0.kind == .modify }

        var executedEntries: [ChangeEntry] = []

        do {
            for entry in deleteEntries {
                try await performDelete(entry, fileSystem: fileSystem)
                executedEntries.append(entry)
            }

            for entry in addEntries {
                try await performAdd(entry, fileSystem: fileSystem)
                executedEntries.append(entry)
            }

            for entry in modifyEntries {
                try await performModify(entry, fileSystem: fileSystem)
                executedEntries.append(entry)
            }
        } catch {
            do {
                try await rollback(entries: executedEntries, fileSystem: fileSystem)
            } catch let rollbackError {
                throw ApplyStagingArea.Error.rollbackFailed(
                    applyError: error,
                    rollbackError: rollbackError
                )
            }
            throw error
        }
    }

    private func performDelete(_ entry: ChangeEntry, fileSystem: any FileSysteming) async throws {
        let targetPath = targetPath(for: entry.relativePath)
        try await fileSystem.removeIfExists(targetPath)
    }

    private func performAdd(_ entry: ChangeEntry, fileSystem: any FileSysteming) async throws {
        guard let stagedPath = entry.stagedPath else {
            throw ApplyStagingArea.Error.missingStagedArtifact(path: entry.relativePath.pathString)
        }

        let targetPath = targetPath(for: entry.relativePath)
        try await ensureParentDirectory(for: targetPath, fileSystem: fileSystem)
        try await fileSystem.copy(stagedPath, to: targetPath)
    }

    private func performModify(_ entry: ChangeEntry, fileSystem: any FileSysteming) async throws {
        guard let stagedPath = entry.stagedPath else {
            throw ApplyStagingArea.Error.missingStagedArtifact(path: entry.relativePath.pathString)
        }

        let targetPath = targetPath(for: entry.relativePath)
        try await fileSystem.removeIfExists(targetPath)

        try await ensureParentDirectory(for: targetPath, fileSystem: fileSystem)
        try await fileSystem.copy(stagedPath, to: targetPath)
    }

    private func rollback(
        entries: [ChangeEntry],
        fileSystem: any FileSysteming
    ) async throws {
        guard !entries.isEmpty else { return }

        for entry in entries.reversed() {
            let targetPath = targetPath(for: entry.relativePath)

            switch entry.kind {
            case .delete:
                if let backupPath = entry.backupPath, try await fileSystem.exists(backupPath) {
                    try await ensureParentDirectory(for: targetPath, fileSystem: fileSystem)
                    try await fileSystem.copy(backupPath, to: targetPath)
                }

            case .add:
                try await fileSystem.removeIfExists(targetPath)

            case .modify:
                try await fileSystem.removeIfExists(targetPath)

                if let backupPath = entry.backupPath, try await fileSystem.exists(backupPath) {
                    try await ensureParentDirectory(for: targetPath, fileSystem: fileSystem)
                    try await fileSystem.copy(backupPath, to: targetPath)
                }
            }
        }
    }

    private func stagedPath(for relativePath: RelativePath) -> AbsolutePath {
        stagedPayloadRoot.appending(relativePath)
    }

    private func backupPath(for relativePath: RelativePath) -> AbsolutePath {
        backupRoot.appending(relativePath)
    }

    private func targetPath(for relativePath: RelativePath) -> AbsolutePath {
        workingDirectory.appending(relativePath)
    }

    private func ensureParentDirectory(
        for path: AbsolutePath,
        fileSystem: any FileSysteming
    ) async throws {
        let parent = path.parentDirectory
        if try await !fileSystem.exists(parent) {
            try await fileSystem.makeDirectory(at: parent, options: [.createTargetParentDirectories])
        }
    }

    private func ensureBaseDirectories(fileSystem: any FileSysteming) async throws {
        try await fileSystem.makeDirectory(at: stagedPayloadRoot, options: [.createTargetParentDirectories])
        try await fileSystem.makeDirectory(at: backupRoot, options: [.createTargetParentDirectories])
    }

    private func stageAddedFiles(
        _ paths: [RelativePath],
        fileSystem: any FileSysteming
    ) async throws -> [ChangeEntry] {
        var entries: [ChangeEntry] = []
        entries.reserveCapacity(paths.count)

        for path in paths {
            let source = workspaceRoot.appending(path)
            let stagedDestination = stagedPath(for: path)
            try await copyToStaging(source: source, destination: stagedDestination, fileSystem: fileSystem)

            entries.append(
                ChangeEntry(
                    relativePath: path,
                    kind: .add,
                    stagedPath: stagedDestination,
                    backupPath: nil
                )
            )
        }

        return entries
    }

    private func stageModifiedFiles(
        _ paths: [RelativePath],
        fileSystem: any FileSysteming
    ) async throws -> [ChangeEntry] {
        var entries: [ChangeEntry] = []
        entries.reserveCapacity(paths.count)

        for path in paths {
            let source = workspaceRoot.appending(path)
            let stagedDestination = stagedPath(for: path)
            try await copyToStaging(source: source, destination: stagedDestination, fileSystem: fileSystem)
            let backup = try await backupOriginalIfNeeded(relativePath: path, fileSystem: fileSystem)

            entries.append(
                ChangeEntry(
                    relativePath: path,
                    kind: .modify,
                    stagedPath: stagedDestination,
                    backupPath: backup
                )
            )
        }

        return entries
    }

    private func stageDeletedFiles(
        _ paths: [RelativePath],
        fileSystem: any FileSysteming
    ) async throws -> [ChangeEntry] {
        var entries: [ChangeEntry] = []
        entries.reserveCapacity(paths.count)

        for path in paths {
            guard let backup = try await backupOriginalIfNeeded(relativePath: path, fileSystem: fileSystem) else {
                continue
            }

            entries.append(
                ChangeEntry(
                    relativePath: path,
                    kind: .delete,
                    stagedPath: nil,
                    backupPath: backup
                )
            )
        }

        return entries
    }

    private func copyToStaging(
        source: AbsolutePath,
        destination: AbsolutePath,
        fileSystem: any FileSysteming
    ) async throws {
        try await ensureParentDirectory(for: destination, fileSystem: fileSystem)
        try await fileSystem.copy(source, to: destination)
    }

    private func backupOriginalIfNeeded(
        relativePath: RelativePath,
        fileSystem: any FileSysteming
    ) async throws -> AbsolutePath? {
        let original = targetPath(for: relativePath)
        guard try await fileSystem.exists(original) else {
            return nil
        }

        let backupDestination = backupPath(for: relativePath)
        try await ensureParentDirectory(for: backupDestination, fileSystem: fileSystem)
        try await fileSystem.copy(original, to: backupDestination)
        return backupDestination
    }

    /// Cleans up the staging area.
    ///
    /// Removes all staging artifacts. Safe to call multiple times.
    ///
    /// - Parameter fileSystem: File system for operations
    func cleanup(fileSystem: any FileSysteming) async {
        try? await fileSystem.remove(root)
    }
}

/// Manifest describing all changes to be applied.
struct ChangeManifest: Equatable, Sendable {
    let entries: [ChangeEntry]

    var addCount: Int { entries.filter { $0.kind == .add }.count }
    var modifyCount: Int { entries.filter { $0.kind == .modify }.count }
    var deleteCount: Int { entries.filter { $0.kind == .delete }.count }
    var totalCount: Int { entries.count }
}

/// A single change entry in the manifest.
struct ChangeEntry: Equatable, Sendable {
    let relativePath: RelativePath
    let kind: ChangeKind
    let stagedPath: AbsolutePath?
    let backupPath: AbsolutePath?
}

/// The type of change to apply.
enum ChangeKind: Equatable, Sendable {
    case add
    case modify
    case delete
}

/// Errors that can occur during staging operations.
extension ApplyStagingArea {
    enum Error: LocalizedError, Equatable {
        case rollbackFailed(applyError: any Swift.Error, rollbackError: any Swift.Error)
        case missingStagedArtifact(path: String)

        var errorDescription: String? {
            switch self {
            case let .rollbackFailed(applyError, rollbackError):
                return "Failed to roll back partially applied changes. Apply error: \(applyError.localizedDescription); Rollback error: \(rollbackError.localizedDescription)"
            case let .missingStagedArtifact(path):
                return "Missing staged artifact for \(path)"
            }
        }

        static func == (lhs: Error, rhs: Error) -> Bool {
            lhs.errorDescription == rhs.errorDescription
        }
    }
}
