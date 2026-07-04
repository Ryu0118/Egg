@testable import EggKit
import FileManagerProtocol
import Foundation
import Testing

@Suite("Serializes concurrent hatch transactions on the same directory")
struct TransactionLockTests {
    private let fileManager: some FileManagerProtocol = FileManager.default

    private func makeDirectory() throws -> URL {
        try fileManager.makeTemporaryDirectory(prefix: "TransactionLockTests")
    }

    @Test("Acquires a lock on a directory that does not yet exist, creating it and writing a .lock file, then releases it")
    func acquiresAndReleasesCreatingTheDirectoryIfNeeded() async throws {
        let root = try makeDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let target = root.appending(path: "does/not/exist/yet")

        let result = try await TransactionLock.shared.withLock(directory: target, fileManager: fileManager) {
            42
        }
        #expect(result == 42)
        #expect(fileManager.exists(target.appending(path: ".lock")))
    }

    @Test("Rejects a fail-fast lock attempt on the same directory while another transaction still holds the lock")
    func aSecondFailFastAcquisitionOnTheSameDirectoryIsRejectedWhileTheFirstIsHeld() async throws {
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

    @Test("Releases the lock once the locked closure returns normally, allowing a following acquisition on the same directory to succeed")
    func theLockIsReleasedAfterTheBodyReturnsSoASubsequentAcquisitionSucceeds() async throws {
        let root = try makeDirectory()
        defer { try? fileManager.removeItem(at: root) }

        try await TransactionLock.shared.withLock(directory: root, fileManager: fileManager) {}
        // Must not throw: the first lock was released.
        try await TransactionLock.shared.withLock(directory: root, fileManager: fileManager) {}
    }

    @Test("Releases the lock even when the locked closure throws, so a subsequent acquisition still succeeds")
    func theLockIsReleasedEvenWhenTheBodyThrows() async throws {
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

    @Test("With a wait budget, blocks and polls until a concurrently held lock is released instead of failing fast")
    func waitPollsUntilTheLockIsReleasedRatherThanFailingImmediately() async throws {
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

    @Test("Allows locks on two unrelated sibling directories to be held at the same time without contending")
    func directoriesWithUnrelatedNamesLockIndependently() async throws {
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
