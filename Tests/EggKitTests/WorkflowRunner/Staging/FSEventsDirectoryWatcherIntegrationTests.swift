@testable import EggKit
import FileSystem
import Foundation
import Path
import Testing

/// Integration tests that verify FSEventsDirectoryWatcher correctly detects
/// file system changes using real FSEvents.
struct FSEventsDirectoryWatcherIntegrationTests {
    private let fileSystem = FileSystem()

    /// Context passed to the test closure containing the watcher, watched directory, and file system.
    struct WatcherContext {
        let watcher: FSEventsDirectoryWatcher
        let directory: AbsolutePath
        let fileSystem: FileSystem

        /// Writes text to a file.
        func writeText(_ text: String, at path: AbsolutePath) async throws {
            try await fileSystem.writeText(text, at: path)
        }

        /// Creates a directory at the given path.
        func makeDirectory(at path: AbsolutePath) async throws {
            try await fileSystem.makeDirectory(at: path)
        }

        /// Removes the item at the given path.
        func remove(_ path: AbsolutePath) async throws {
            try await fileSystem.remove(path)
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

    @Test("detects new file creation")
    func detectsNewFileCreation() async throws {
        try await withWatcher { ctx in
            let filePath = ctx.directory.appending(component: "new-file.txt")
            try await ctx.writeText("content", at: filePath)

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
            try await fileSystem.writeText("original", at: filePath)

            let watcher = FSEventsDirectoryWatcher()
            try await watcher.start(watching: tempDir)
            defer { Task { await watcher.stop() } }

            // FileSystem.writeText doesn't support overwriting existing files,
            // so we use Data.write for modification
            try Data("modified".utf8).write(to: URL(fileURLWithPath: filePath.pathString))

            try await Task.sleep(for: .milliseconds(200))

            let events = await watcher.drainEvents()
            let expectedPath = try RelativePath(validating: "existing.txt")
            #expect(events.contains(expectedPath), "Should detect file modification")
        }
    }

    @Test("detects file deletion")
    func detectsFileDeletion() async throws {
        try await withWatcher { ctx in
            let filePath = ctx.directory.appending(component: "to-delete.txt")
            // Create file first
            try await ctx.writeText("content", at: filePath)

            // Small delay to let creation events settle
            try await Task.sleep(for: .milliseconds(100))

            // Clear creation events
            _ = await ctx.watcher.drainEvents()

            // Now delete
            try FileManager.default.removeItem(atPath: filePath.pathString)

            try await Task.sleep(for: .milliseconds(200))

            let events = await ctx.watcher.drainEvents()
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
            try await ctx.writeText("nested content", at: nestedFile)

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

            try await ctx.writeText("content1", at: file1)
            try await ctx.writeText("content2", at: file2)
            try await ctx.writeText("content3", at: file3)

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
            try await fileSystem.writeText("content", at: filePath)

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
            try await ctx.writeText("first", at: file1)

            try await Task.sleep(for: .milliseconds(200))

            let events1 = await ctx.watcher.drainEvents()
            let expected1 = try RelativePath(validating: "first.txt")
            #expect(events1.contains(expected1), "First drain should contain first.txt")

            let file2 = ctx.directory.appending(component: "second.txt")
            try await ctx.writeText("second", at: file2)

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
            try await ctx.writeText("deep content", at: deepFile)

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
            try await fileSystem.writeText("outside content", at: outsideFile)

            let insideFile = watchedDir.appending(component: "inside.txt")
            try await fileSystem.writeText("inside content", at: insideFile)

            try await Task.sleep(for: .milliseconds(200))

            let events = await watcher.drainEvents()

            let insidePath = try RelativePath(validating: "inside.txt")
            #expect(events.contains(insidePath), "Should detect file inside watched directory")
            #expect(events.count == 1, "Should only detect changes inside watched directory")
        }
    }

    // MARK: - Move operation tests (investigating staging workflow issue)

    @Test("detects file moved INTO watched directory from outside")
    func detectsFileMoveIntoWatchedDirectory() async throws {
        try await fileSystem.withTemporaryDirectory(prefix: "fsevents-test") { tempDir in
            let watchedDir = tempDir.appending(component: "watched")
            let outsideDir = tempDir.appending(component: "outside")

            try await fileSystem.makeDirectory(at: watchedDir)
            try await fileSystem.makeDirectory(at: outsideDir)

            // Create file outside watched directory BEFORE starting watcher
            let outsideFile = outsideDir.appending(component: "to-move.txt")
            try await fileSystem.writeText("content to move", at: outsideFile)

            let watcher = FSEventsDirectoryWatcher()
            try await watcher.start(watching: watchedDir)
            defer { Task { await watcher.stop() } }

            // Move file INTO watched directory
            let insideFile = watchedDir.appending(component: "moved.txt")
            try FileManager.default.moveItem(
                atPath: outsideFile.pathString,
                toPath: insideFile.pathString
            )

            try await Task.sleep(for: .milliseconds(300))

            let events = await watcher.drainEvents()
            let expectedPath = try RelativePath(validating: "moved.txt")

            print("DEBUG: Events detected: \(events)")
            #expect(events.contains(expectedPath), "Should detect file moved into watched directory")
        }
    }

    @Test("detects directory moved INTO watched directory from outside")
    func detectsDirectoryMoveIntoWatchedDirectory() async throws {
        try await fileSystem.withTemporaryDirectory(prefix: "fsevents-test") { tempDir in
            let watchedDir = tempDir.appending(component: "watched")
            let outsideDir = tempDir.appending(component: "outside")

            try await fileSystem.makeDirectory(at: watchedDir)
            try await fileSystem.makeDirectory(at: outsideDir)

            // Create directory with files outside watched directory
            let sourceDirPath = outsideDir.appending(component: "subdir")
            try await fileSystem.makeDirectory(at: sourceDirPath)
            try await fileSystem.writeText("file1 content", at: sourceDirPath.appending(component: "file1.txt"))
            try await fileSystem.writeText("file2 content", at: sourceDirPath.appending(component: "file2.txt"))

            let watcher = FSEventsDirectoryWatcher()
            try await watcher.start(watching: watchedDir)
            defer { Task { await watcher.stop() } }

            // Move entire directory INTO watched directory
            let destDirPath = watchedDir.appending(component: "subdir")
            try FileManager.default.moveItem(
                atPath: sourceDirPath.pathString,
                toPath: destDirPath.pathString
            )

            try await Task.sleep(for: .milliseconds(300))

            let events = await watcher.drainEvents()

            print("DEBUG: Events detected for directory move: \(events)")

            // Check if we detect the directory or its contents
            let expectedDir = try RelativePath(validating: "subdir")
            let expectedFile1 = try RelativePath(validating: "subdir/file1.txt")
            let expectedFile2 = try RelativePath(validating: "subdir/file2.txt")

            let detectsDirectory = events.contains(expectedDir)
            let detectsFile1 = events.contains(expectedFile1)
            let detectsFile2 = events.contains(expectedFile2)

            print("DEBUG: Detects directory? \(detectsDirectory)")
            print("DEBUG: Detects file1? \(detectsFile1)")
            print("DEBUG: Detects file2? \(detectsFile2)")

            // At minimum, we should detect something
            #expect(!events.isEmpty, "Should detect something when directory is moved in")
        }
    }

    @Test("detects directory moved from /var/folders (simulating atomic copy)")
    func detectsDirectoryMoveFromVarFolders() async throws {
        // This simulates what withAtomicCopyAndWrite does:
        // 1. Creates temp directory in /var/folders
        // 2. Does work there
        // 3. Moves result to destination

        try await fileSystem.withTemporaryDirectory(prefix: "fsevents-watched") { watchedDir in
            // Create another temp directory (will be in /var/folders)
            try await fileSystem.withTemporaryDirectory(prefix: "fsevents-source") { sourceDir in
                // Create files in source (simulating template expansion)
                let sourceDirPath = sourceDir.appending(component: "output")
                try await fileSystem.makeDirectory(at: sourceDirPath)
                try await fileSystem.writeText("template content", at: sourceDirPath.appending(component: "Template.swift"))

                print("DEBUG: Source path: \(sourceDirPath.pathString)")
                print("DEBUG: Watched path: \(watchedDir.pathString)")

                let watcher = FSEventsDirectoryWatcher()
                try await watcher.start(watching: watchedDir)
                defer { Task { await watcher.stop() } }

                // Move from /var/folders to watched directory
                let destPath = watchedDir.appending(component: "output")
                try FileManager.default.moveItem(
                    atPath: sourceDirPath.pathString,
                    toPath: destPath.pathString
                )

                try await Task.sleep(for: .milliseconds(300))

                let events = await watcher.drainEvents()

                print("DEBUG: Events after move from /var/folders: \(events)")

                let expectedDir = try RelativePath(validating: "output")
                let expectedFile = try RelativePath(validating: "output/Template.swift")

                print("DEBUG: Detects 'output' directory? \(events.contains(expectedDir))")
                print("DEBUG: Detects 'output/Template.swift'? \(events.contains(expectedFile))")

                #expect(!events.isEmpty, "Should detect move from /var/folders into watched directory")
            }
        }
    }

    @Test("detects files when moved directly to watched root (simulating output='.')")
    func detectsFilesMoveDirectlyToRoot() async throws {
        // This simulates: hatch.output = "." where files are placed directly in staging root
        try await fileSystem.withTemporaryDirectory(prefix: "fsevents-watched") { watchedDir in
            try await fileSystem.withTemporaryDirectory(prefix: "fsevents-source") { sourceDir in
                // Create files in source (simulating template with multiple files)
                try await fileSystem.writeText("file1 content", at: sourceDir.appending(component: "File1.swift"))
                try await fileSystem.writeText("file2 content", at: sourceDir.appending(component: "File2.swift"))
                let subdir = sourceDir.appending(component: "Models")
                try await fileSystem.makeDirectory(at: subdir)
                try await fileSystem.writeText("model content", at: subdir.appending(component: "Model.swift"))

                let watcher = FSEventsDirectoryWatcher()
                try await watcher.start(watching: watchedDir)
                defer { Task { await watcher.stop() } }

                // Move each item individually to root (like mergeDirectory does)
                for item in try FileManager.default.contentsOfDirectory(atPath: sourceDir.pathString) {
                    let src = sourceDir.appending(component: item)
                    let dst = watchedDir.appending(component: item)
                    try FileManager.default.moveItem(atPath: src.pathString, toPath: dst.pathString)
                }

                try await Task.sleep(for: .milliseconds(300))

                let events = await watcher.drainEvents()

                print("DEBUG: Events when moving to root: \(events)")

                let expectedFile1 = try RelativePath(validating: "File1.swift")
                let expectedFile2 = try RelativePath(validating: "File2.swift")
                let expectedModels = try RelativePath(validating: "Models")
                let expectedModel = try RelativePath(validating: "Models/Model.swift")

                print("DEBUG: Detects File1.swift? \(events.contains(expectedFile1))")
                print("DEBUG: Detects File2.swift? \(events.contains(expectedFile2))")
                print("DEBUG: Detects Models? \(events.contains(expectedModels))")
                print("DEBUG: Detects Models/Model.swift? \(events.contains(expectedModel))")

                #expect(events.contains(expectedFile1), "Should detect File1.swift")
                #expect(events.contains(expectedFile2), "Should detect File2.swift")
            }
        }
    }

    @Test("detects file created via FileSystem.move")
    func detectsFileCreatedViaFileSystemMove() async throws {
        try await fileSystem.withTemporaryDirectory(prefix: "fsevents-test") { tempDir in
            let watchedDir = tempDir.appending(component: "watched")
            let outsideDir = tempDir.appending(component: "outside")

            try await fileSystem.makeDirectory(at: watchedDir)
            try await fileSystem.makeDirectory(at: outsideDir)

            // Create file outside
            let sourceFile = outsideDir.appending(component: "source.txt")
            try await fileSystem.writeText("content", at: sourceFile)

            let watcher = FSEventsDirectoryWatcher()
            try await watcher.start(watching: watchedDir)
            defer { Task { await watcher.stop() } }

            // Use FileSystem.move (same as what the code uses)
            let destFile = watchedDir.appending(component: "dest.txt")
            try await fileSystem.move(from: sourceFile, to: destFile)

            try await Task.sleep(for: .milliseconds(300))

            let events = await watcher.drainEvents()

            print("DEBUG: Events after FileSystem.move: \(events)")

            let expectedPath = try RelativePath(validating: "dest.txt")
            #expect(events.contains(expectedPath), "Should detect file created via FileSystem.move")
        }
    }
}
