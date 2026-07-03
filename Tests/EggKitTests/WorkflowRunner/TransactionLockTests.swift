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
    func `Acquires and releases, creating the directory if needed`() async throws {
        let root = try makeDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let target = root.appending(path: "does/not/exist/yet")

        let result = try await TransactionLock.shared.withLock(directory: target, fileManager: fileManager) {
            42
        }
        #expect(result == 42)
        #expect(fileManager.exists(target.appending(path: ".lock")))
    }

    @Test
    func `A second fail-fast acquisition on the same directory is rejected while the first is held`() async throws {
        let root = try makeDirectory()
        defer { try? fileManager.removeItem(at: root) }

        _ = try await TransactionLock.shared.withLock(directory: root, fileManager: fileManager) {
            // Simulate a second, independent acquisition attempt (as another
            // process would make, opening its own fd on the same lock file)
            // while the first is still held.
            await #expect(throws: TransactionLock.Error.self) {
                try await TransactionLock.shared.withLock(directory: root, fileManager: fileManager) {}
            }
        }
    }

    @Test
    func `The lock is released after the body returns, so a subsequent acquisition succeeds`() async throws {
        let root = try makeDirectory()
        defer { try? fileManager.removeItem(at: root) }

        try await TransactionLock.shared.withLock(directory: root, fileManager: fileManager) {}
        // Must not throw: the first lock was released.
        try await TransactionLock.shared.withLock(directory: root, fileManager: fileManager) {}
    }

    @Test
    func `The lock is released even when the body throws`() async throws {
        let root = try makeDirectory()
        defer { try? fileManager.removeItem(at: root) }

        struct Boom: Swift.Error {}
        await #expect(throws: Boom.self) {
            try await TransactionLock.shared.withLock(directory: root, fileManager: fileManager) {
                throw Boom()
            }
        }
        // Must not throw: the failed attempt's lock was still released.
        try await TransactionLock.shared.withLock(directory: root, fileManager: fileManager) {}
    }

    @Test
    func `wait polls until the lock is released, rather than failing immediately`() async throws {
        let root = try makeDirectory()
        defer { try? fileManager.removeItem(at: root) }

        let holder = Task {
            try await TransactionLock.shared.withLock(directory: root, fileManager: fileManager) {
                try await Task.sleep(for: .milliseconds(200))
            }
        }
        try await Task.sleep(for: .milliseconds(50))

        // Fail-fast would throw immediately; wait: 2 should succeed once the
        // holder releases (well within the 2s budget).
        let result = try await TransactionLock.shared.withLock(directory: root, wait: 2, fileManager: fileManager) {
            "acquired"
        }
        #expect(result == "acquired")
        try await holder.value
    }

    @Test
    func `Directories with unrelated names lock independently`() async throws {
        let root = try makeDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let dirA = root.appending(path: "a")
        let dirB = root.appending(path: "b")

        try await TransactionLock.shared.withLock(directory: dirA, fileManager: fileManager) {
            // A lock on an unrelated directory must not contend with dirA's.
            try await TransactionLock.shared.withLock(directory: dirB, fileManager: fileManager) {}
        }
    }
}
