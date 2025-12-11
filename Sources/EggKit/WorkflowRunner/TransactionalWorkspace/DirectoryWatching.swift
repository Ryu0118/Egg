import Foundation
import Path

/// Protocol for watching file system changes in a directory.
///
/// Implementations capture paths that have been modified (created, updated, deleted, renamed)
/// within the watched directory. This is used for change detection during transactional workspace execution.
protocol DirectoryWatching: Sendable {
    /// Starts watching the specified directory for changes.
    ///
    /// - Parameter directory: The directory to watch
    /// - Throws: If the watcher fails to start
    func start(watching directory: AbsolutePath) async throws

    /// Stops watching and releases resources.
    ///
    /// Safe to call multiple times (idempotent).
    func stop() async

    /// Returns all paths that have changed since the watcher started.
    ///
    /// Returns relative paths (relative to the watched directory).
    /// The watcher continues running after draining.
    ///
    /// - Returns: Set of relative paths that were touched
    func drainEvents() async -> Set<RelativePath>
}

/// Errors that can occur during directory watching.
enum DirectoryWatcherError: LocalizedError, Equatable {
    case failedToStart(reason: String)
    case notStarted
    case alreadyStarted

    var errorDescription: String? {
        switch self {
        case let .failedToStart(reason):
            return "Failed to start directory watcher: \(reason)"
        case .notStarted:
            return "Directory watcher has not been started"
        case .alreadyStarted:
            return "Directory watcher is already started"
        }
    }
}
