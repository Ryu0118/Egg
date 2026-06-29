@testable import EggKit
import FileManagerProtocol
import Foundation

/// A directory watcher that scans all files on drainEvents() instead of relying on FSEvents.
///
/// This is useful for testing where FSEvents may not deliver events quickly enough.
/// Instead of tracking events, it scans the directory when asked and reports all files.
actor ScanningDirectoryWatcher: DirectoryWatching {
    private var watchedDirectory: URL?
    private var isRunning: Bool = false
    private let fileManager: FileManagerProtocol

    init(fileManager: FileManagerProtocol = FileManager.default) {
        self.fileManager = fileManager
    }

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
        guard let directory = watchedDirectory else {
            return []
        }

        // Scan all files in directory recursively and return as events
        var events: Set<String> = []

        // Recursively enumerate all files in the directory
        enumerateFiles(in: directory, baseDirectory: directory, events: &events)

        return events
    }

    /// Recursively enumerates all files in a directory and collects relative paths.
    private func enumerateFiles(
        in directory: URL,
        baseDirectory: URL,
        events: inout Set<String>,
    ) {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [],
        ) else {
            return
        }

        let basePath = baseDirectory.path(percentEncoded: false)

        for itemURL in contents {
            let itemPath = itemURL.path(percentEncoded: false)

            // Calculate relative path from base directory
            if itemPath.hasPrefix(basePath) {
                var relativePart = String(itemPath.dropFirst(basePath.count))
                // Remove leading slash if present
                if relativePart.hasPrefix("/") {
                    relativePart = String(relativePart.dropFirst())
                }
                if !relativePart.isEmpty {
                    events.insert(relativePart)
                }
            }

            // Recursively enumerate subdirectories
            if fileManager.isDirectory(at: itemURL) {
                enumerateFiles(in: itemURL, baseDirectory: baseDirectory, events: &events)
            }
        }
    }

    var running: Bool {
        isRunning
    }
}
