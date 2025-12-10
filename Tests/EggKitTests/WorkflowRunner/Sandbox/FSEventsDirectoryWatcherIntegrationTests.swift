@testable import EggKit
import FileSystem
import Foundation
import Path
import Testing

/// Integration tests that verify FSEventsDirectoryWatcher correctly detects
/// file system changes using real FSEvents.
struct FSEventsDirectoryWatcherIntegrationTests {
    private let fileSystem = FileSystem()

    // MARK: - Helper

    /// Context passed to the test closure containing the watcher, watched directory, and file system.
    struct WatcherContext {
        let watcher: FSEventsDirectoryWatcher
        let directory: AbsolutePath
        let fileSystem: FileSystem

        /// Writes text directly to a file using FileHandle (non-atomic) to ensure FSEvents detection.
        func writeText(_ text: String, at path: AbsolutePath) throws {
            let data = Data(text.utf8)
            if FileManager.default.fileExists(atPath: path.pathString) {
                let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path.pathString))
                try handle.truncate(atOffset: 0)
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                FileManager.default.createFile(atPath: path.pathString, contents: data)
            }
        }

        /// Creates a directory at the given path.
        func makeDirectory(at path: AbsolutePath) async throws {
            try await fileSystem.makeDirectory(at: path)
        }

        /// Removes the item at the given path.
        func remove(_ path: AbsolutePath) throws {
            try FileManager.default.removeItem(atPath: path.pathString)
        }
    }

    /// Creates a temporary directory, starts a watcher on it, and executes the given closure.
    /// The watcher is automatically stopped and the directory cleaned up after the closure completes.
    private func withWatcher(
        _ operation: (WatcherContext) async throws -> Void
    ) async throws {
        try await fileSystem.withTemporaryDirectory(prefix: "fsevents-test") { tempDir in
            let watcher = FSEventsDirectoryWatcher()
            try await watcher.start(watching: tempDir)
            defer { Task { await watcher.stop() } }

            let context = WatcherContext(
                watcher: watcher,
                directory: tempDir,
                fileSystem: fileSystem
            )
            try await operation(context)
        }
    }

    // MARK: - Tests

    @Test("detects new file creation")
    func detectsNewFileCreation() async throws {
        try await withWatcher { ctx in
            let filePath = ctx.directory.appending(component: "new-file.txt")
            try ctx.writeText("content", at: filePath)

            try await Task.sleep(for: .milliseconds(200))

            let events = await ctx.watcher.drainEvents()
            let expectedPath = try RelativePath(validating: "new-file.txt")
            #expect(events.contains(expectedPath), "Should detect new file creation")
        }
    }

    @Test("detects file modification")
    func detectsFileModification() async throws {
        try await fileSystem.withTemporaryDirectory(prefix: "fsevents-test") { tempDir in
            let filePath = tempDir.appending(component: "existing.txt")
            FileManager.default.createFile(atPath: filePath.pathString, contents: Data("original".utf8))

            let watcher = FSEventsDirectoryWatcher()
            try await watcher.start(watching: tempDir)
            defer { Task { await watcher.stop() } }

            FileManager.default.createFile(atPath: filePath.pathString, contents: Data("modified".utf8))

            try await Task.sleep(for: .milliseconds(200))

            let events = await watcher.drainEvents()
            let expectedPath = try RelativePath(validating: "existing.txt")
            #expect(events.contains(expectedPath), "Should detect file modification")
        }
    }

    @Test("detects file deletion")
    func detectsFileDeletion() async throws {
        try await fileSystem.withTemporaryDirectory(prefix: "fsevents-test") { tempDir in
            let filePath = tempDir.appending(component: "to-delete.txt")
            FileManager.default.createFile(atPath: filePath.pathString, contents: Data("content".utf8))

            let watcher = FSEventsDirectoryWatcher()
            try await watcher.start(watching: tempDir)
            defer { Task { await watcher.stop() } }

            try FileManager.default.removeItem(atPath: filePath.pathString)

            try await Task.sleep(for: .milliseconds(200))

            let events = await watcher.drainEvents()
            let expectedPath = try RelativePath(validating: "to-delete.txt")
            #expect(events.contains(expectedPath), "Should detect file deletion")
        }
    }

    @Test("detects nested file changes")
    func detectsNestedFileChanges() async throws {
        try await withWatcher { ctx in
            let nestedDir = ctx.directory.appending(component: "subdir")
            try await ctx.makeDirectory(at: nestedDir)

            let nestedFile = nestedDir.appending(component: "nested.txt")
            try ctx.writeText("nested content", at: nestedFile)

            try await Task.sleep(for: .milliseconds(200))

            let events = await ctx.watcher.drainEvents()
            let expectedPath = try RelativePath(validating: "subdir/nested.txt")
            #expect(events.contains(expectedPath), "Should detect nested file creation")
        }
    }

    @Test("detects multiple file changes")
    func detectsMultipleChanges() async throws {
        try await withWatcher { ctx in
            let file1 = ctx.directory.appending(component: "file1.txt")
            let file2 = ctx.directory.appending(component: "file2.txt")
            let file3 = ctx.directory.appending(component: "file3.txt")

            try ctx.writeText("content1", at: file1)
            try ctx.writeText("content2", at: file2)
            try ctx.writeText("content3", at: file3)

            try await Task.sleep(for: .milliseconds(200))

            let events = await ctx.watcher.drainEvents()

            let expected1 = try RelativePath(validating: "file1.txt")
            let expected2 = try RelativePath(validating: "file2.txt")
            let expected3 = try RelativePath(validating: "file3.txt")

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
    func stopIsIdempotent() async throws {
        try await fileSystem.withTemporaryDirectory(prefix: "fsevents-test") { tempDir in
            let watcher = FSEventsDirectoryWatcher()
            try await watcher.start(watching: tempDir)

            await watcher.stop()
            await watcher.stop()
            await watcher.stop()
        }
    }

    @Test("can restart after stop")
    func canRestartAfterStop() async throws {
        try await fileSystem.withTemporaryDirectory(prefix: "fsevents-test") { tempDir in
            let watcher = FSEventsDirectoryWatcher()

            try await watcher.start(watching: tempDir)
            await watcher.stop()

            try await watcher.start(watching: tempDir)
            defer { Task { await watcher.stop() } }

            let filePath = tempDir.appending(component: "after-restart.txt")
            FileManager.default.createFile(atPath: filePath.pathString, contents: Data("content".utf8))

            try await Task.sleep(for: .milliseconds(200))

            let events = await watcher.drainEvents()
            let expectedPath = try RelativePath(validating: "after-restart.txt")
            #expect(events.contains(expectedPath), "Should detect file after restart")
        }
    }

    @Test("accumulates events across multiple drains")
    func accumulatesEventsAcrossMultipleDrains() async throws {
        try await withWatcher { ctx in
            let file1 = ctx.directory.appending(component: "first.txt")
            try ctx.writeText("first", at: file1)

            try await Task.sleep(for: .milliseconds(200))

            let events1 = await ctx.watcher.drainEvents()
            let expected1 = try RelativePath(validating: "first.txt")
            #expect(events1.contains(expected1), "First drain should contain first.txt")

            let file2 = ctx.directory.appending(component: "second.txt")
            try ctx.writeText("second", at: file2)

            try await Task.sleep(for: .milliseconds(200))

            let events2 = await ctx.watcher.drainEvents()
            let expected2 = try RelativePath(validating: "second.txt")
            #expect(events2.contains(expected1), "Second drain should still contain first.txt")
            #expect(events2.contains(expected2), "Second drain should contain second.txt")
        }
    }

    @Test("detects deeply nested changes")
    func detectsDeeplyNestedChanges() async throws {
        try await withWatcher { ctx in
            let deepPath = ctx.directory
                .appending(component: "a")
                .appending(component: "b")
                .appending(component: "c")
                .appending(component: "d")

            try await ctx.makeDirectory(at: deepPath)

            let deepFile = deepPath.appending(component: "deep.txt")
            try ctx.writeText("deep content", at: deepFile)

            try await Task.sleep(for: .milliseconds(200))

            let events = await ctx.watcher.drainEvents()
            let expectedPath = try RelativePath(validating: "a/b/c/d/deep.txt")
            #expect(events.contains(expectedPath), "Should detect deeply nested file")
        }
    }

    @Test("ignores changes outside watched directory")
    func ignoresChangesOutsideWatchedDirectory() async throws {
        try await fileSystem.withTemporaryDirectory(prefix: "fsevents-test") { tempDir in
            let watchedDir = tempDir.appending(component: "watched")
            let outsideDir = tempDir.appending(component: "outside")

            try await fileSystem.makeDirectory(at: watchedDir)
            try await fileSystem.makeDirectory(at: outsideDir)

            let watcher = FSEventsDirectoryWatcher()
            try await watcher.start(watching: watchedDir)
            defer { Task { await watcher.stop() } }

            let outsideFile = outsideDir.appending(component: "outside.txt")
            FileManager.default.createFile(atPath: outsideFile.pathString, contents: Data("outside content".utf8))

            let insideFile = watchedDir.appending(component: "inside.txt")
            FileManager.default.createFile(atPath: insideFile.pathString, contents: Data("inside content".utf8))

            try await Task.sleep(for: .milliseconds(200))

            let events = await watcher.drainEvents()

            let insidePath = try RelativePath(validating: "inside.txt")
            #expect(events.contains(insidePath), "Should detect file inside watched directory")
            #expect(events.count == 1, "Should only detect changes inside watched directory")
        }
    }
}
