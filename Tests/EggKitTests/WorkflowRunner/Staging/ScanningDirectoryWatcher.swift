@testable import EggKit
import FileManagerProtocol
import Foundation
import Path

/// A directory watcher that scans all files on drainEvents() instead of relying on FSEvents.
///
/// This is useful for testing where FSEvents may not deliver events quickly enough.
/// Instead of tracking events, it scans the directory when asked and reports all files.
actor ScanningDirectoryWatcher: DirectoryWatching {
    private var watchedDirectory: AbsolutePath?
    private var isRunning: Bool = false
    private let fileManager: FileManagerProtocol

    init(fileManager: FileManagerProtocol = FileManager.default) {
        self.fileManager = fileManager
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

        // Scan all files in directory recursively and return as events
        var events: Set<RelativePath> = []

        do {
            // Recursively enumerate all files in the directory
            try await enumerateFiles(in: directory, baseDirectory: directory, events: &events)
        } catch {
            // If we can't scan, return empty set
        }

        return events
    }

    /// Recursively enumerates all files in a directory and collects relative paths.
    private func enumerateFiles(
        in directory: AbsolutePath,
        baseDirectory: AbsolutePath,
        events: inout Set<RelativePath>
    ) async throws {
        let directoryURL = URL(filePath: directory.pathString)
        let contents = try await fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        )

        for itemURL in contents {
            let itemPath = itemURL.path

            // Calculate relative path from base directory
            let basePath = baseDirectory.pathString + "/"
            if itemPath.hasPrefix(basePath) {
                let relativePart = String(itemPath.dropFirst(basePath.count))
                if let relativePath = try? RelativePath(validating: relativePart) {
                    events.insert(relativePath)
                }
            }

            // Recursively enumerate subdirectories
            if try await fileManager.isDirectory(at: itemURL) {
                let subdirectoryPath = try AbsolutePath(validating: itemPath)
                try await enumerateFiles(in: subdirectoryPath, baseDirectory: baseDirectory, events: &events)
            }
        }
    }

    var running: Bool {
        isRunning
    }
}
