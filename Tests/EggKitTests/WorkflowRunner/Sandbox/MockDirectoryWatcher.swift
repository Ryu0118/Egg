import Foundation
import Path
@testable import EggKit

/// Mock implementation of DirectoryWatching for testing.
///
/// Allows tests to simulate file system events without actual FSEvents.
actor MockDirectoryWatcher: DirectoryWatching {
    /// The directory being "watched".
    private var watchedDirectory: AbsolutePath?

    /// Whether the watcher is running.
    private var isRunning: Bool = false

    /// Events that will be returned by drainEvents().
    private var simulatedEvents: Set<RelativePath> = []


    func start(watching directory: AbsolutePath) async throws {
        guard !isRunning else {
            throw DirectoryWatcherError.alreadyStarted
        }
        watchedDirectory = directory
        isRunning = true
    }

    func stop() async {
        isRunning = false
        watchedDirectory = nil
    }

    func drainEvents() async -> Set<RelativePath> {
        simulatedEvents
    }


    /// Simulates a file event at the given relative path.
    func simulateEvent(at relativePath: RelativePath) {
        simulatedEvents.insert(relativePath)
    }

    /// Simulates multiple file events.
    func simulateEvents(_ relativePaths: [RelativePath]) {
        for path in relativePaths {
            simulatedEvents.insert(path)
        }
    }

    /// Simulates a file event from a string path.
    func simulateEvent(at pathString: String) throws {
        let relativePath = try RelativePath(validating: pathString)
        simulatedEvents.insert(relativePath)
    }

    /// Clears all simulated events.
    func clearEvents() {
        simulatedEvents = []
    }

    /// Returns whether the watcher is currently running.
    var running: Bool {
        isRunning
    }
}
