import FileManagerProtocol
import Foundation
#if canImport(Darwin)
    import Darwin
#endif

/// Advisory, process-scoped mutual exclusion for a single hatch transaction
/// or rollback bundle, backed by `flock(2)` on a dedicated lock file.
///
/// The lock is tied to the file descriptor's lifetime, so the kernel releases
/// it automatically if the process dies (crash, `SIGKILL`) — no PID or
/// staleness bookkeeping needed. This makes it safe across processes (CLI vs.
/// CLI, CLI vs. the long-lived MCP server) and across concurrent `Task`s
/// within the MCP server process, since `flock` semantics apply per
/// `open()`ed file description, not per-thread: two `Task`s racing on the
/// same token in one process still serialize correctly because each
/// `withLock` call opens its own fd.
enum TransactionLock {
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
    static func withLock<T>(
        directory: URL,
        wait: TimeInterval? = nil,
        fileManager: some FileManagerProtocol,
        body: () throws -> T,
    ) throws -> T {
        let fd = try open(directory: directory, wait: wait, fileManager: fileManager)
        defer {
            flock(fd, LOCK_UN)
            close(fd)
        }
        return try body()
    }

    /// Same as ``withLock(directory:wait:fileManager:body:)-9v2y8``, but for
    /// `async throws` bodies (used by `apply`/`preview`, which call into
    /// `async` phase-runner code). Acquisition itself stays a plain
    /// synchronous syscall — it's expected to be near-instant (fail-fast, no
    /// long blocking wait by default) — so this doesn't need `Task.detached`.
    static func withLock<T>(
        directory: URL,
        wait: TimeInterval? = nil,
        fileManager: some FileManagerProtocol,
        body: () async throws -> T,
    ) async throws -> T {
        let fd = try open(directory: directory, wait: wait, fileManager: fileManager)
        defer {
            flock(fd, LOCK_UN)
            close(fd)
        }
        return try await body()
    }

    private static func open(directory: URL, wait: TimeInterval?, fileManager: some FileManagerProtocol) throws -> Int32 {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appending(path: ".lock").path(percentEncoded: false)

        let fd = path.withCString { Darwin.open($0, O_CREAT | O_RDWR, 0o644) }
        guard fd >= 0 else {
            throw Error.lockFileUnavailable(path: path, underlying: String(cString: strerror(errno)))
        }

        do {
            try acquire(fd: fd, path: path, wait: wait)
        } catch {
            close(fd)
            throw error
        }
        return fd
    }

    private static func acquire(fd: Int32, path: String, wait: TimeInterval?) throws {
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
            usleep(50000) // 50ms poll
        }
        throw Error.locked(path: path)
    }
}
