@testable import EggKit
import FileManagerProtocol
import Foundation
import Testing

@Suite("TransactionLock")
struct TransactionLockTests {
    private let fileManager: some FileManagerProtocol = FileManager.default

    private func makeDirectory() throws -> URL {
        try fileManager.makeTemporaryDirectory(prefix: "TransactionLockTests")
    }

    @Test
    func `Acquires and releases, creating the directory if needed`() throws {
        let root = try makeDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let target = root.appending(path: "does/not/exist/yet")

        let result = try TransactionLock.withLock(directory: target, fileManager: fileManager) {
            42
        }
        #expect(result == 42)
        #expect(fileManager.exists(target.appending(path: ".lock")))
    }

    @Test
    func `A second fail-fast acquisition on the same directory is rejected while the first is held`() throws {
        let root = try makeDirectory()
        defer { try? fileManager.removeItem(at: root) }

        try TransactionLock.withLock(directory: root, fileManager: fileManager) {
            // Simulate a second, independent acquisition attempt (as another
            // process would make, opening its own fd on the same lock file)
            // while the first is still held.
            #expect(throws: TransactionLock.Error.self) {
                try TransactionLock.withLock(directory: root, fileManager: fileManager) {}
            }
        }
    }

    @Test
    func `The lock is released after the body returns, so a subsequent acquisition succeeds`() throws {
        let root = try makeDirectory()
        defer { try? fileManager.removeItem(at: root) }

        try TransactionLock.withLock(directory: root, fileManager: fileManager) {}
        // Must not throw: the first lock was released.
        try TransactionLock.withLock(directory: root, fileManager: fileManager) {}
    }

    @Test
    func `The lock is released even when the body throws`() throws {
        let root = try makeDirectory()
        defer { try? fileManager.removeItem(at: root) }

        struct Boom: Swift.Error {}
        #expect(throws: Boom.self) {
            try TransactionLock.withLock(directory: root, fileManager: fileManager) {
                throw Boom()
            }
        }
        // Must not throw: the failed attempt's lock was still released.
        try TransactionLock.withLock(directory: root, fileManager: fileManager) {}
    }

    @Test
    func `wait polls until the lock is released, rather than failing immediately`() async throws {
        let root = try makeDirectory()
        defer { try? fileManager.removeItem(at: root) }

        let (holderAcquired, holderAcquiredContinuation) = AsyncStream<Void>.makeStream()

        // Open the lock on a background task, hold it briefly, then release.
        let holder = Task {
            try await TransactionLock.withLock(directory: root, fileManager: fileManager) {
                holderAcquiredContinuation.yield()
                holderAcquiredContinuation.finish()
                try await Task.sleep(nanoseconds: 200_000_000) // 200ms
            }
        }
        for await _ in holderAcquired {
            break
        }

        // Fail-fast would throw immediately; wait: 2 should succeed once the
        // holder releases (well within the 2s budget).
        let result = try TransactionLock.withLock(directory: root, wait: 2, fileManager: fileManager) {
            "acquired"
        }
        #expect(result == "acquired")
        try await holder.value
    }

    @Test
    func `Directories with unrelated names lock independently`() throws {
        let root = try makeDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let dirA = root.appending(path: "a")
        let dirB = root.appending(path: "b")

        try TransactionLock.withLock(directory: dirA, fileManager: fileManager) {
            // A lock on an unrelated directory must not contend with dirA's.
            try TransactionLock.withLock(directory: dirB, fileManager: fileManager) {}
        }
    }
}
