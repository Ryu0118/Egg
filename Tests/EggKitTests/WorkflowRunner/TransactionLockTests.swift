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

    @Test("A waiting acquirer never keeps a lock on an unlinked lock file while another process holds the live one")
    func waitingAcquirerRetriesWhenTheLockFileWasUnlinked() async throws {
        let root = try makeDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let lockFile = root.appending(path: ".lock")

        actor Occupancy {
            private var occupants = 0
            private(set) var maxOccupants = 0
            func enter() {
                occupants += 1
                maxOccupants = max(maxOccupants, occupants)
            }

            func exit() {
                occupants -= 1
            }
        }
        let occupancy = Occupancy()
        let fm = fileManager

        // A holds the lock and — like discard's pair deletion — unlinks the
        // lock file as its final act while still holding it.
        let holderA = Task {
            try await TransactionLock.shared.withLock(directory: root, fileManager: fm) {
                try await Task.sleep(for: .milliseconds(150))
                try? fm.removeItem(at: lockFile)
            }
        }
        try await Task.sleep(for: .milliseconds(50))

        // B starts waiting while A still holds: its fd points at the inode A
        // is about to unlink. After A releases, B's next poll succeeds on
        // that dead inode — without the inode re-check it would hold a lock
        // that excludes nobody.
        let waiterB = Task {
            try await TransactionLock.shared.withLock(directory: root, wait: 5, fileManager: fm) {
                await occupancy.enter()
                try await Task.sleep(for: .milliseconds(300))
                await occupancy.exit()
            }
        }
        try await Task.sleep(for: .milliseconds(50))
        try await holderA.value

        // C arrives right after A released: the path is empty, so C creates
        // a fresh lock file. If B kept its dead lock, B and C would both be
        // inside their critical sections at once.
        let holderC = Task {
            try await TransactionLock.shared.withLock(directory: root, wait: 5, fileManager: fm) {
                await occupancy.enter()
                try await Task.sleep(for: .milliseconds(300))
                await occupancy.exit()
            }
        }

        try await waiterB.value
        try await holderC.value
        #expect(await occupancy.maxOccupants == 1)
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
