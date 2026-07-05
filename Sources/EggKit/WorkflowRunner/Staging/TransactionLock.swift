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

    /// Takes two locks in the one fixed order every dual-domain hatch verb
    /// must follow: the transactions directory (outer) first, the rollback
    /// bundle directory (inner) second — never the reverse, or two verbs
    /// could deadlock.
    ///
    /// A transaction's applyToken and rollbackId are the same value by
    /// construction, so the outer lock serializes rollback, discard, and
    /// apply of the same transaction against each other, while the inner
    /// lock additionally excludes older egg binaries, which take only the
    /// bundle lock.
    func withLocks<T>(
        outer: URL,
        inner: URL,
        fileManager: some FileManagerProtocol,
        body: () async throws -> T,
    ) async throws -> T {
        try await withLock(directory: outer, fileManager: fileManager) {
            try await withLock(directory: inner, fileManager: fileManager) {
                try await body()
            }
        }
    }

    private static func open(directory: URL, wait: TimeInterval?, fileManager: some FileManagerProtocol) async throws -> Int32 {
        let path = directory.appending(path: ".lock").path(percentEncoded: false)
        let deadline = wait.map { Date().addingTimeInterval($0) }

        // A holder may legitimately unlink this lock file while holding the
        // lock: discard and orphan cleanup delete the directory that contains
        // it as their final act. flock is bound to the inode, not the path,
        // so a lock acquired on an fd whose file has since been unlinked or
        // replaced excludes nobody — a later opener creates a fresh inode at
        // the same path and locks it instantly. Guard against holding such a
        // dead lock: after acquiring, verify the fd still names the inode
        // currently at `path`, and race for the live file otherwise.
        //
        // The other half of the protocol is a discipline on deleters: unlink
        // the lock file only as the final act before release, never with
        // guarded work still to do.
        while true {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let fd = path.withCString { Darwin.open($0, O_CREAT | O_RDWR, 0o644) }
            guard fd >= 0 else {
                throw Error.lockFileUnavailable(path: path, underlying: String(cString: strerror(errno)))
            }

            do {
                try await acquire(fd: fd, path: path, deadline: deadline)
            } catch {
                close(fd)
                throw error
            }

            if isLiveLock(fd: fd, path: path) {
                return fd
            }
            flock(fd, LOCK_UN)
            close(fd)
        }
    }

    /// Whether `fd` still refers to the inode currently at `path` — i.e. the
    /// locked file was not unlinked or replaced while we were acquiring.
    private static func isLiveLock(fd: Int32, path: String) -> Bool {
        var fdStat = stat()
        var pathStat = stat()
        guard fstat(fd, &fdStat) == 0,
              path.withCString({ stat($0, &pathStat) }) == 0
        else { return false }
        return fdStat.st_dev == pathStat.st_dev && fdStat.st_ino == pathStat.st_ino
    }

    private static func acquire(fd: Int32, path: String, deadline: Date?) async throws {
        if flock(fd, LOCK_EX | LOCK_NB) == 0 { return }
        guard errno == EWOULDBLOCK else {
            throw Error.lockFileUnavailable(path: path, underlying: String(cString: strerror(errno)))
        }
        guard let deadline else {
            throw Error.locked(path: path)
        }

        while Date() < deadline {
            if flock(fd, LOCK_EX | LOCK_NB) == 0 { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw Error.locked(path: path)
    }
}
