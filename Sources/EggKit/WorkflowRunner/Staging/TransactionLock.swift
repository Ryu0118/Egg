import FileManagerProtocol
import Foundation
#if canImport(Darwin)
    import Darwin
#endif

/// Actor-isolated transaction gate backed by `flock(2)` on a dedicated lock file.
///
/// The lock is tied to the file descriptor's lifetime, so the kernel releases
/// it automatically if the process dies (crash, `SIGKILL`) — no PID or
/// staleness bookkeeping needed. The actor provides an async Swift API for
/// in-process callers, while `flock` keeps CLI and MCP processes serialized
/// against each other.
actor TransactionLock {
    static let shared = TransactionLock()

    enum Error: LocalizedError, Equatable {
        case locked(path: String)
        case lockFileUnavailable(path: String, underlying: String)

        var errorDescription: String? {
            switch self {
            case let .locked(path):
                "'\(path)' is locked by another egg process. Retry once it completes, or pass --wait to block."
            case let .lockFileUnavailable(path, underlying):
                "Could not open lock file at '\(path)': \(underlying)"
            }
        }
    }

    /// Acquires an exclusive lock on `directory/.lock` (creating `directory`
    /// and the lock file if needed), runs `body`, and always releases the
    /// lock (via fd close) before returning — even if `body` throws.
    ///
    /// - Parameter wait: `nil` (default) fails fast (`EWOULDBLOCK` ->
    ///   ``Error/locked(path:)``) if the lock is already held. A positive
    ///   value polls at a short interval up to that many seconds before
    ///   giving up with the same error.
    func withLock<T>(
        directory: URL,
        wait: TimeInterval? = nil,
        fileManager: some FileManagerProtocol,
        body: () throws -> T,
    ) async throws -> T {
        let fd = try await Self.open(directory: directory, wait: wait, fileManager: fileManager)
        defer {
            flock(fd, LOCK_UN)
            close(fd)
        }
        return try body()
    }

    /// Same as ``withLock(directory:wait:fileManager:body:)-9v2y8``, but for
    /// `async throws` bodies (used by `apply`/`preview`, which call into
    /// `async` phase-runner code). Waiting uses cooperative `Task.sleep`
    /// polling so a waiter never blocks actor progress while another task is
    /// holding and about to release the file lock.
    func withLock<T>(
        directory: URL,
        wait: TimeInterval? = nil,
        fileManager: some FileManagerProtocol,
        body: () async throws -> T,
    ) async throws -> T {
        let fd = try await Self.open(directory: directory, wait: wait, fileManager: fileManager)
        defer {
            flock(fd, LOCK_UN)
            close(fd)
        }
        return try await body()
    }

    private static func open(directory: URL, wait: TimeInterval?, fileManager: some FileManagerProtocol) async throws -> Int32 {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appending(path: ".lock").path(percentEncoded: false)

        let fd = path.withCString { Darwin.open($0, O_CREAT | O_RDWR, 0o644) }
        guard fd >= 0 else {
            throw Error.lockFileUnavailable(path: path, underlying: String(cString: strerror(errno)))
        }

        do {
            try await acquire(fd: fd, path: path, wait: wait)
        } catch {
            close(fd)
            throw error
        }
        return fd
    }

    private static func acquire(fd: Int32, path: String, wait: TimeInterval?) async throws {
        if flock(fd, LOCK_EX | LOCK_NB) == 0 { return }
        guard errno == EWOULDBLOCK else {
            throw Error.lockFileUnavailable(path: path, underlying: String(cString: strerror(errno)))
        }
        guard let wait, wait > 0 else {
            throw Error.locked(path: path)
        }

        let deadline = Date().addingTimeInterval(wait)
        while Date() < deadline {
            if flock(fd, LOCK_EX | LOCK_NB) == 0 { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw Error.locked(path: path)
    }
}
