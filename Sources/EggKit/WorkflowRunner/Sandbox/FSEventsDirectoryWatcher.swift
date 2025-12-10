import CoreServices
import Foundation
import Path

/// FSEvents-based implementation of DirectoryWatching for macOS.
///
/// Uses the FSEvents API to efficiently monitor directory changes without polling.
/// Events are coalesced and converted to relative paths for change detection.
actor FSEventsDirectoryWatcher: DirectoryWatching {
    /// The directory being watched.
    private var watchedDirectory: AbsolutePath?

    /// The FSEvents stream reference.
    private var eventStream: FSEventStreamRef?
    private var streamContext: UnsafeMutablePointer<FSEventStreamContext>?

    /// Accumulated set of changed paths (relative to watched directory).
    private var changedPaths: Set<RelativePath> = []

    /// Whether the watcher is currently running.
    private var isRunning: Bool = false

    /// Dispatch queue for FSEvents callbacks.
    private let dispatchQueue = DispatchQueue(label: "com.egg.fsevents-watcher", qos: .utility)

    /// Thread-safe event buffer for receiving events from the callback.
    private let eventBuffer = EventBuffer()

    // MARK: - DirectoryWatching Protocol

    func start(watching directory: AbsolutePath) async throws {
        guard !isRunning else {
            throw DirectoryWatcherError.alreadyStarted
        }

        watchedDirectory = directory
        changedPaths = []

        // Create FSEvents stream
        let context = createStreamContext()
        streamContext = context

        let pathsToWatch = [directory.pathString] as CFArray

        guard let stream = FSEventStreamCreate(
            nil,
            fsEventsCallback,
            context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.1, // Latency in seconds (100ms coalescing)
            UInt32(
                kFSEventStreamCreateFlagFileEvents |
                    kFSEventStreamCreateFlagNoDefer |
                    kFSEventStreamCreateFlagUseCFTypes
            )
        ) else {
            cleanupStreamResources()
            throw DirectoryWatcherError.failedToStart(reason: "Failed to create FSEvents stream")
        }

        eventStream = stream
        FSEventStreamSetDispatchQueue(stream, dispatchQueue)

        guard FSEventStreamStart(stream) else {
            cleanupStreamResources()
            throw DirectoryWatcherError.failedToStart(reason: "Failed to start FSEvents stream")
        }

        isRunning = true
    }

    func stop() async {
        guard isRunning else { return }

        cleanupStreamResources()
        watchedDirectory = nil
        isRunning = false
    }

    func drainEvents() async -> Set<RelativePath> {
        // Drain buffered events and process them
        let bufferedPaths = eventBuffer.drain()

        guard let watchedDirectory else {
            return changedPaths
        }

        for path in bufferedPaths {
            if let relativePath = makeRelativePath(from: path, relativeTo: watchedDirectory) {
                changedPaths.insert(relativePath)
            }
        }

        return changedPaths
    }

    private func createStreamContext() -> UnsafeMutablePointer<FSEventStreamContext> {
        let context = UnsafeMutablePointer<FSEventStreamContext>.allocate(capacity: 1)
        context.pointee = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(eventBuffer).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        return context
    }

    /// Converts an absolute path string to a RelativePath relative to the watched directory.
    private func makeRelativePath(from absolutePath: String, relativeTo base: AbsolutePath) -> RelativePath? {
        // Normalize both paths to resolve symlinks (e.g., /var -> /private/var)
        // FSEvents reports real paths while the watched directory may use symlinked paths
        let basePath = (base.pathString as NSString).standardizingPath
        let normalizedPath = (absolutePath as NSString).standardizingPath

        // Ensure the path is within the watched directory
        guard normalizedPath.hasPrefix(basePath) else { return nil }

        // Remove the base path prefix
        var relativePart = String(normalizedPath.dropFirst(basePath.count))

        // Remove leading slash if present
        if relativePart.hasPrefix("/") {
            relativePart = String(relativePart.dropFirst())
        }

        // Skip empty paths (the watched directory itself)
        guard !relativePart.isEmpty else { return nil }

        return try? RelativePath(validating: relativePart)
    }

    private func cleanupStreamResources() {
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            eventStream = nil
        }
        streamContext?.deallocate()
        streamContext = nil
    }
}

/// Thread-safe buffer for collecting FSEvents paths from the callback.
private final class EventBuffer: @unchecked Sendable {
    private var paths: [String] = []
    private let lock = NSLock()

    func append(_ newPaths: [String]) {
        lock.lock()
        defer { lock.unlock() }
        paths.append(contentsOf: newPaths)
    }

    func drain() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        let result = paths
        paths = []
        return result
    }
}

/// C-style callback function for FSEvents.
private func fsEventsCallback(
    _: ConstFSEventStreamRef,
    info: UnsafeMutableRawPointer?,
    numEvents _: Int,
    eventPaths: UnsafeMutableRawPointer,
    _: UnsafePointer<FSEventStreamEventFlags>,
    _: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = info else { return }

    // Get the event buffer
    let buffer = Unmanaged<EventBuffer>.fromOpaque(info).takeUnretainedValue()

    // Convert paths
    guard let pathArray = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }

    // Add to buffer
    buffer.append(pathArray)
}
