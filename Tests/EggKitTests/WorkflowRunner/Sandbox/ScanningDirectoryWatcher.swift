@testable import EggKit
import FileSystem
import Foundation
import Path

/// A directory watcher that scans all files on drainEvents() instead of relying on FSEvents.
///
/// This is useful for testing where FSEvents may not deliver events quickly enough.
/// Instead of tracking events, it scans the directory when asked and reports all files.
actor ScanningDirectoryWatcher: DirectoryWatching {
    private var watchedDirectory: AbsolutePath?
    private var isRunning: Bool = false
    private let fileSystem: FileSystem

    init(fileSystem: FileSystem = FileSystem()) {
        self.fileSystem = fileSystem
    }

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
        guard let directory = watchedDirectory else {
            return []
        }

        // Scan all files in directory using glob and return as events
        var events: Set<RelativePath> = []

        do {
            // Use glob to find all files recursively
            let sequence = try fileSystem.glob(directory: directory, include: ["**/*"])
            for try await fullPath in sequence {
                // Calculate relative path from watched directory
                let fullPathString = fullPath.pathString
                let basePath = directory.pathString + "/"
                if fullPathString.hasPrefix(basePath) {
                    let relativePart = String(fullPathString.dropFirst(basePath.count))
                    if let relativePath = try? RelativePath(validating: relativePart) {
                        events.insert(relativePath)
                    }
                }
            }
        } catch {
            // If we can't scan, return empty set
        }

        return events
    }

    var running: Bool {
        isRunning
    }
}
