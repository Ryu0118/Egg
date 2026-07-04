@testable import EggKit
import FileManagerProtocol
import Foundation
import Testing

/// Integration tests that verify FSEventsDirectoryWatcher correctly detects
/// file system changes using real FSEvents.
struct FSEventsDirectoryWatcherIntegrationTests {
    private let fileManager: any FileManagerProtocol = FileManager.default

    /// Context passed to the test closure containing the watcher, watched directory, and file manager.
    struct WatcherContext {
        let watcher: FSEventsDirectoryWatcher
        let directory: URL
        let fileManager: any FileManagerProtocol

        /// Writes text to a file.
        func writeText(_ text: String, at path: URL) throws {
            try fileManager.writeText(text, at: path, encoding: .utf8)
        }

        /// Creates a directory at the given path.
        func makeDirectory(at path: URL) throws {
            try fileManager.createDirectory(at: path, withIntermediateDirectories: true)
        }

        /// Removes the item at the given path.
        func remove(_ path: URL) throws {
            try fileManager.removeItem(at: path)
        }
    }

    /// Creates a temporary directory, starts a watcher on it, and executes the given closure.
    /// The watcher is automatically stopped and the directory cleaned up after the closure completes.
    private func withWatcher(
        _ operation: (WatcherContext) async throws -> Void,
    ) async throws {
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "fsevents-test")
        defer { try? fileManager.removeItem(at: tempDir) }

        let watcher = FSEventsDirectoryWatcher()
        try await watcher.start(watching: tempDir)
        defer { Task { await watcher.stop() } }

        let context = WatcherContext(
            watcher: watcher,
            directory: tempDir,
            fileManager: fileManager,
        )
        try await operation(context)
    }

    @Test("reports the relative path of a newly created file after a real FSEvents notification fires")
    func detectsNewFileCreation() async throws {
        try await withWatcher { ctx in
            let filePath = ctx.directory.appending(path: "new-file.txt")
            try ctx.writeText("content", at: filePath)

            try await Task.sleep(for: .milliseconds(200))

            let events = await ctx.watcher.drainEvents()
            let expectedPath = "new-file.txt"
            #expect(events.contains(expectedPath), "Should detect new file creation")
        }
    }

    @Test("reports the relative path of an existing file after its contents are overwritten with Data.write")
    func detectsFileModification() async throws {
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "fsevents-test")
        defer { try? fileManager.removeItem(at: tempDir) }

        let filePath = tempDir.appending(path: "existing.txt")
        try fileManager.writeText("original", at: filePath, encoding: .utf8)

        let watcher = FSEventsDirectoryWatcher()
        try await watcher.start(watching: tempDir)
        defer { Task { await watcher.stop() } }

        // Use Data.write for modification
        try Data("modified".utf8).write(to: filePath)

        try await Task.sleep(for: .milliseconds(200))

        let events = await watcher.drainEvents()
        let expectedPath = "existing.txt"
        #expect(events.contains(expectedPath), "Should detect file modification")
    }

    @Test("reports the relative path of a file removed after its creation events were already drained")
    func detectsFileDeletion() async throws {
        try await withWatcher { ctx in
            let filePath = ctx.directory.appending(path: "to-delete.txt")
            // Create file first
            try ctx.writeText("content", at: filePath)

            // Small delay to let creation events settle
            try await Task.sleep(for: .milliseconds(100))

            // Clear creation events
            _ = await ctx.watcher.drainEvents()

            // Now delete
            try FileManager.default.removeItem(at: filePath)

            try await Task.sleep(for: .milliseconds(200))

            let events = await ctx.watcher.drainEvents()
            let expectedPath = "to-delete.txt"
            #expect(events.contains(expectedPath), "Should detect file deletion")
        }
    }

    @Test("reports the relative path of a file created inside a newly-created subdirectory of the watched root")
    func detectsNestedFileChanges() async throws {
        try await withWatcher { ctx in
            let nestedDir = ctx.directory.appending(path: "subdir")
            try ctx.makeDirectory(at: nestedDir)

            let nestedFile = nestedDir.appending(path: "nested.txt")
            try ctx.writeText("nested content", at: nestedFile)

            try await Task.sleep(for: .milliseconds(200))

            let events = await ctx.watcher.drainEvents()
            let expectedPath = "subdir/nested.txt"
            #expect(events.contains(expectedPath), "Should detect nested file creation")
        }
    }

    @Test("reports the relative paths of three files created concurrently in a single batch of events")
    func detectsMultipleFileChanges() async throws {
        try await withWatcher { ctx in
            let file1 = ctx.directory.appending(path: "file1.txt")
            let file2 = ctx.directory.appending(path: "file2.txt")
            let file3 = ctx.directory.appending(path: "file3.txt")

            try ctx.writeText("content1", at: file1)
            try ctx.writeText("content2", at: file2)
            try ctx.writeText("content3", at: file3)

            try await Task.sleep(for: .milliseconds(200))

            let events = await ctx.watcher.drainEvents()

            let expected1 = "file1.txt"
            let expected2 = "file2.txt"
            let expected3 = "file3.txt"

            #expect(events.contains(expected1), "Should detect file1.txt")
            #expect(events.contains(expected2), "Should detect file2.txt")
            #expect(events.contains(expected3), "Should detect file3.txt")
        }
    }

    @Test("returns empty events when no changes")
    func returnsEmptyEventsWhenNoChanges() async throws {
        try await withWatcher { ctx in
            try await Task.sleep(for: .milliseconds(150))

            let events = await ctx.watcher.drainEvents()
            #expect(events.isEmpty, "Should return empty set when no changes")
        }
    }

    @Test("throws when started twice")
    func throwsWhenStartedTwice() async throws {
        try await withWatcher { ctx in
            await #expect(throws: DirectoryWatcherError.alreadyStarted) {
                try await ctx.watcher.start(watching: ctx.directory)
            }
        }
    }

    @Test("stop is idempotent - calling multiple times does not throw")
    func stopIsIdempotentCallingMultipleTimesDoesNotThrow() async throws {
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "fsevents-test")
        defer { try? fileManager.removeItem(at: tempDir) }

        let watcher = FSEventsDirectoryWatcher()
        try await watcher.start(watching: tempDir)

        await watcher.stop()
        await watcher.stop()
        await watcher.stop()
    }

    @Test("can restart after stop")
    func canRestartAfterStop() async throws {
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "fsevents-test")
        defer { try? fileManager.removeItem(at: tempDir) }

        let watcher = FSEventsDirectoryWatcher()

        try await watcher.start(watching: tempDir)
        await watcher.stop()

        try await watcher.start(watching: tempDir)
        defer { Task { await watcher.stop() } }

        let filePath = tempDir.appending(path: "after-restart.txt")
        try fileManager.writeText("content", at: filePath, encoding: .utf8)

        try await Task.sleep(for: .milliseconds(200))

        let events = await watcher.drainEvents()
        let expectedPath = "after-restart.txt"
        #expect(events.contains(expectedPath), "Should detect file after restart")
    }

    @Test("accumulates events across multiple drains")
    func accumulatesEventsAcrossMultipleDrains() async throws {
        try await withWatcher { ctx in
            let file1 = ctx.directory.appending(path: "first.txt")
            try ctx.writeText("first", at: file1)

            try await Task.sleep(for: .milliseconds(200))

            let events1 = await ctx.watcher.drainEvents()
            let expected1 = "first.txt"
            #expect(events1.contains(expected1), "First drain should contain first.txt")

            let file2 = ctx.directory.appending(path: "second.txt")
            try ctx.writeText("second", at: file2)

            try await Task.sleep(for: .milliseconds(200))

            let events2 = await ctx.watcher.drainEvents()
            let expected2 = "second.txt"
            #expect(events2.contains(expected1), "Second drain should still contain first.txt")
            #expect(events2.contains(expected2), "Second drain should contain second.txt")
        }
    }

    @Test("detects deeply nested changes")
    func detectsDeeplyNestedChanges() async throws {
        try await withWatcher { ctx in
            let deepPath = ctx.directory
                .appending(path: "a")
                .appending(path: "b")
                .appending(path: "c")
                .appending(path: "d")

            try ctx.makeDirectory(at: deepPath)

            let deepFile = deepPath.appending(path: "deep.txt")
            try ctx.writeText("deep content", at: deepFile)

            try await Task.sleep(for: .milliseconds(200))

            let events = await ctx.watcher.drainEvents()
            let expectedPath = "a/b/c/d/deep.txt"
            #expect(events.contains(expectedPath), "Should detect deeply nested file")
        }
    }

    @Test("ignores changes outside watched directory")
    func ignoresChangesOutsideWatchedDirectory() async throws {
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "fsevents-test")
        defer { try? fileManager.removeItem(at: tempDir) }

        let watchedDir = tempDir.appending(path: "watched")
        let outsideDir = tempDir.appending(path: "outside")

        try fileManager.createDirectory(at: watchedDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outsideDir, withIntermediateDirectories: true)

        let watcher = FSEventsDirectoryWatcher()
        try await watcher.start(watching: watchedDir)
        defer { Task { await watcher.stop() } }

        let outsideFile = outsideDir.appending(path: "outside.txt")
        try fileManager.writeText("outside content", at: outsideFile, encoding: .utf8)

        let insideFile = watchedDir.appending(path: "inside.txt")
        try fileManager.writeText("inside content", at: insideFile, encoding: .utf8)

        try await Task.sleep(for: .milliseconds(200))

        let events = await watcher.drainEvents()

        let insidePath = "inside.txt"
        #expect(events.contains(insidePath), "Should detect file inside watched directory")
        #expect(events.count == 1, "Should only detect changes inside watched directory")
    }
}
