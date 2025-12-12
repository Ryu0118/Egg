@testable import EggKit
import Foundation

/// Mock implementation of DirectoryWatching for testing.
///
/// Allows tests to simulate file system events without actual FSEvents.
actor MockDirectoryWatcher: DirectoryWatching {
    /// The directory being "watched".
    private var watchedDirectory: URL?

    /// Whether the watcher is running.
    private var isRunning: Bool = false

    /// Events that will be returned by drainEvents().
    private var simulatedEvents: Set<String> = []

    func start(watching directory: URL) async throws {
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

    func drainEvents() async -> Set<String> {
        simulatedEvents
    }

    /// Simulates a file event at the given relative path.
    func simulateEvent(at relativePath: String) {
        simulatedEvents.insert(relativePath)
    }

    /// Simulates multiple file events.
    func simulateEvents(_ relativePaths: [String]) {
        for path in relativePaths {
            simulatedEvents.insert(path)
        }
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
