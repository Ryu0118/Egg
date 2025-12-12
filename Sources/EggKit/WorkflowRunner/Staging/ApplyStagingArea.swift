import FileManagerProtocol
import Foundation

/// Manages a temporary staging area for applying staging changes atomically.
///
/// The staging area provides a two-phase commit for staging changes:
/// 1. Stage: Materialize all changes (adds/modifies/deletes) in a temporary directory
/// 2. Apply: Transfer staged changes to the working directory
///
/// If staging fails, no changes are made to the working directory.
/// If apply fails mid-way, the staging area contains rollback information.
///
struct ApplyStagingArea {
    /// The root directory of the staging area.
    let root: URL

    /// The staging root directory (source of changes).
    let workspaceRoot: URL

    /// The original working directory (destination of changes).
    let workingDirectory: URL

    private var stagedPayloadRoot: URL {
        root.appending(path: "staged")
    }

    private var backupRoot: URL {
        root.appending(path: "backup")
    }

    private init(root: URL, workspaceRoot: URL, workingDirectory: URL) {
        self.root = root
        self.workspaceRoot = workspaceRoot
        self.workingDirectory = workingDirectory
    }

    /// Creates a new staging area within the staging directory.
    ///
    /// - Parameters:
    ///   - workspaceRoot: The staging root directory
    ///   - workingDirectory: The original working directory
    ///   - fileManager: File manager for operations
    /// - Returns: A new ApplyStagingArea
    static func create(
        workspaceRoot: URL,
        workingDirectory: URL,
        fileManager: some FileManagerProtocol
    ) throws -> ApplyStagingArea {
        // Create staging directory under system temporary directory with unique prefix
        let stagingRoot = try fileManager.makeTemporaryDirectory(prefix: "egg-apply-staging")

        let area = ApplyStagingArea(
            root: stagingRoot,
            workspaceRoot: workspaceRoot,
            workingDirectory: workingDirectory
        )

        try area.ensureBaseDirectories(fileManager: fileManager)
        return area
    }

    /// Executes staging operations with guaranteed cleanup.
    ///
    /// This method creates a staging area, executes the provided closure, and ensures
    /// the staging area is cleaned up regardless of success or failure.
    ///
    /// The closure receives both the staging area and the file manager to avoid
    /// capturing actor-isolated state, which would cause Swift 6 concurrency errors.
    ///
    /// - Parameters:
    ///   - workspaceRoot: The staging root directory
    ///   - workingDirectory: The original working directory
    ///   - fileManager: File manager for operations
    ///   - body: Closure that receives the staging area and file manager
    /// - Returns: The result of the closure
    /// - Throws: Any error thrown by the closure or staging area creation
    static func withStaging<T: Sendable, FM: FileManagerProtocol>(
        workspaceRoot: URL,
        workingDirectory: URL,
        fileManager: FM,
        body: @Sendable (ApplyStagingArea, FM) throws -> T
    ) throws -> T {
        let staging = try create(
            workspaceRoot: workspaceRoot,
            workingDirectory: workingDirectory,
            fileManager: fileManager
        )

        do {
            let result = try body(staging, fileManager)
            staging.cleanup(fileManager: fileManager)
            return result
        } catch {
            staging.cleanup(fileManager: fileManager)
            throw error
        }
    }

    /// Stages all changes from the staging based on the change summary.
    ///
    /// This method prepares all file operations without touching the working directory:
    /// - Copies new/modified files from staging to staging area
    /// - Records deletions in the manifest
    ///
    /// - Parameters:
    ///   - changes: The change summary describing what to apply
    ///   - fileManager: File manager for operations
    /// - Returns: Manifest describing staged changes
    /// - Throws: If staging fails
    func stage(
        changes: ChangeSummary,
        fileManager: some FileManagerProtocol
    ) throws -> ChangeManifest {
        try ensureBaseDirectories(fileManager: fileManager)

        var entries: [ChangeEntry] = []
        entries.reserveCapacity(changes.totalCount)

        try entries.append(contentsOf: stageAddedFiles(changes.added, fileManager: fileManager))
        try entries.append(contentsOf: stageModifiedFiles(changes.modified, fileManager: fileManager))
        try entries.append(contentsOf: stageDeletedFiles(changes.deleted, fileManager: fileManager))

        return ChangeManifest(entries: entries)
    }

    /// Applies staged changes to the working directory.
    ///
    /// Changes are applied in order: Deletes → Adds → Modifies
    /// This order minimizes conflicts and ensures clean state.
    ///
    /// - Parameter fileManager: File manager for operations
    /// - Throws: If apply fails
    func apply(
        manifest: ChangeManifest,
        fileManager: some FileManagerProtocol
    ) throws {
        let deleteEntries = manifest.entries.filter { $0.kind == .delete }
        let addEntries = manifest.entries.filter { $0.kind == .add }
        let modifyEntries = manifest.entries.filter { $0.kind == .modify }

        var executedEntries: [ChangeEntry] = []

        do {
            for entry in deleteEntries {
                try performDelete(entry, fileManager: fileManager)
                executedEntries.append(entry)
            }

            for entry in addEntries {
                try performAdd(entry, fileManager: fileManager)
                executedEntries.append(entry)
            }

            for entry in modifyEntries {
                try performModify(entry, fileManager: fileManager)
                executedEntries.append(entry)
            }
        } catch {
            do {
                try rollback(entries: executedEntries, fileManager: fileManager)
            } catch let rollbackError {
                throw ApplyStagingArea.Error.rollbackFailed(
                    applyError: error,
                    rollbackError: rollbackError
                )
            }
            throw error
        }
    }

    private func performDelete(_ entry: ChangeEntry, fileManager: some FileManagerProtocol) throws {
        let targetPath = targetPath(for: entry.relativePath)
        try fileManager.removeIfExists(targetPath)
    }

    private func performAdd(_ entry: ChangeEntry, fileManager: some FileManagerProtocol) throws {
        guard let stagedPath = entry.stagedPath else {
            throw ApplyStagingArea.Error.missingStagedArtifact(path: entry.relativePath)
        }

        let targetPath = targetPath(for: entry.relativePath)
        try ensureParentDirectory(for: targetPath, fileManager: fileManager)
        try fileManager.copyItem(at: stagedPath, to: targetPath)
    }

    private func performModify(_ entry: ChangeEntry, fileManager: some FileManagerProtocol) throws {
        guard let stagedPath = entry.stagedPath else {
            throw ApplyStagingArea.Error.missingStagedArtifact(path: entry.relativePath)
        }

        let targetPath = targetPath(for: entry.relativePath)
        try fileManager.removeIfExists(targetPath)

        try ensureParentDirectory(for: targetPath, fileManager: fileManager)
        try fileManager.copyItem(at: stagedPath, to: targetPath)
    }

    private func rollback(
        entries: [ChangeEntry],
        fileManager: some FileManagerProtocol
    ) throws {
        guard !entries.isEmpty else { return }

        for entry in entries.reversed() {
            let targetPath = targetPath(for: entry.relativePath)

            switch entry.kind {
            case .delete:
                if let backupPath = entry.backupPath, try fileManager.exists(backupPath) {
                    try ensureParentDirectory(for: targetPath, fileManager: fileManager)
                    try fileManager.copyItem(at: backupPath, to: targetPath)
                }

            case .add:
                try fileManager.removeIfExists(targetPath)

            case .modify:
                try fileManager.removeIfExists(targetPath)

                if let backupPath = entry.backupPath, try fileManager.exists(backupPath) {
                    try ensureParentDirectory(for: targetPath, fileManager: fileManager)
                    try fileManager.copyItem(at: backupPath, to: targetPath)
                }
            }
        }
    }

    private func stagedPath(for relativePath: String) -> URL {
        stagedPayloadRoot.appending(path: relativePath)
    }

    private func backupPath(for relativePath: String) -> URL {
        backupRoot.appending(path: relativePath)
    }

    private func targetPath(for relativePath: String) -> URL {
        workingDirectory.appending(path: relativePath)
    }

    private func ensureParentDirectory(
        for path: URL,
        fileManager: some FileManagerProtocol
    ) throws {
        let parent = path.deletingLastPathComponent()
        if !fileManager.exists(parent) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
    }

    private func ensureBaseDirectories(fileManager: some FileManagerProtocol) throws {
        try fileManager.createDirectory(at: stagedPayloadRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: true)
    }

    private func stageAddedFiles(
        _ paths: [String],
        fileManager: some FileManagerProtocol
    ) throws -> [ChangeEntry] {
        var entries: [ChangeEntry] = []
        entries.reserveCapacity(paths.count)

        for path in paths {
            let source = workspaceRoot.appending(path: path)
            let stagedDestination = stagedPath(for: path)
            try copyToStaging(source: source, destination: stagedDestination, fileManager: fileManager)

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
        _ paths: [String],
        fileManager: some FileManagerProtocol
    ) throws -> [ChangeEntry] {
        var entries: [ChangeEntry] = []
        entries.reserveCapacity(paths.count)

        for path in paths {
            let source = workspaceRoot.appending(path: path)
            let stagedDestination = stagedPath(for: path)
            try copyToStaging(source: source, destination: stagedDestination, fileManager: fileManager)
            let backup = try backupOriginalIfNeeded(relativePath: path, fileManager: fileManager)

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
        _ paths: [String],
        fileManager: some FileManagerProtocol
    ) throws -> [ChangeEntry] {
        var entries: [ChangeEntry] = []
        entries.reserveCapacity(paths.count)

        for path in paths {
            guard let backup = try backupOriginalIfNeeded(relativePath: path, fileManager: fileManager) else {
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
        source: URL,
        destination: URL,
        fileManager: some FileManagerProtocol
    ) throws {
        try ensureParentDirectory(for: destination, fileManager: fileManager)
        try fileManager.copyItem(at: source, to: destination)
    }

    private func backupOriginalIfNeeded(
        relativePath: String,
        fileManager: some FileManagerProtocol
    ) throws -> URL? {
        let original = targetPath(for: relativePath)
        guard try fileManager.exists(original) else {
            return nil
        }

        let backupDestination = backupPath(for: relativePath)
        try ensureParentDirectory(for: backupDestination, fileManager: fileManager)
        try fileManager.copyItem(at: original, to: backupDestination)
        return backupDestination
    }

    /// Cleans up the staging area.
    ///
    /// Removes all staging artifacts. Safe to call multiple times.
    ///
    /// - Parameter fileManager: File manager for operations
    func cleanup(fileManager: some FileManagerProtocol) {
        try? fileManager.removeItem(at: root)
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
    let relativePath: String
    let kind: ChangeKind
    let stagedPath: URL?
    let backupPath: URL?
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
