@testable import EggKit
import FileSystem
import Foundation
import Path
import ProcessRunning
import Testing

/// Integration tests that verify GitDiffRunner correctly computes changes
/// between working directory and sandbox using real file system and git.
struct GitDiffRunnerIntegrationTests {
    private let fileSystem = FileSystem()

    @Test(arguments: TestCase.allCases)
    func computeChanges(_ testCase: TestCase) async throws {
        try await fileSystem.withTemporaryDirectory(prefix: "git-diff-runner-test") { tempRoot in
            let workingDir = tempRoot.appending(component: "working")
            let sandboxDir = tempRoot.appending(component: "sandbox")

            try await setupDirectory(workingDir, files: testCase.workingFiles)
            try await setupDirectory(sandboxDir, files: testCase.sandboxFiles)

            let targetPaths = try buildTargetPaths(testCase: testCase)

            let runner = GitDiffRunner(
                processRunner: ProcessRunner(),
                fileSystem: fileSystem
            )

            let summary = try await runner.computeChanges(
                sandboxRoot: sandboxDir,
                workingDirectory: workingDir,
                targetPaths: targetPaths
            )

            try assertChangeSummary(
                summary,
                expectedAdded: testCase.expectedAdded,
                expectedModified: testCase.expectedModified,
                expectedDeleted: testCase.expectedDeleted
            )
        }
    }

    /// Creates a directory and populates it with the specified files.
    private func setupDirectory(
        _ directory: AbsolutePath,
        files: [FileEntry]
    ) async throws {
        try await fileSystem.makeDirectory(at: directory)

        for file in files {
            let path = directory.appending(
                components: file.path.split(separator: "/").map(String.init)
            )
            try await createFileWithParentDirectories(at: path, content: file.content)
        }
    }

    /// Creates a file at the given path, creating parent directories as needed.
    private func createFileWithParentDirectories(
        at path: AbsolutePath,
        content: String
    ) async throws {
        let parent = path.parentDirectory
        if try await !fileSystem.exists(parent) {
            try await fileSystem.makeDirectory(at: parent)
        }
        try await fileSystem.writeText(content, at: path)
    }

    /// Builds the set of target paths from all files in the test case.
    private func buildTargetPaths(testCase: TestCase) throws -> Set<RelativePath> {
        var paths = Set<RelativePath>()
        for file in testCase.workingFiles {
            try paths.insert(RelativePath(validating: file.path))
        }
        for file in testCase.sandboxFiles {
            try paths.insert(RelativePath(validating: file.path))
        }
        return paths
    }

    /// Asserts that the change summary matches expected values.
    private func assertChangeSummary(
        _ summary: ChangeSummary,
        expectedAdded: [String],
        expectedModified: [String],
        expectedDeleted: [String]
    ) throws {
        let expectedAddedPaths = try expectedAdded
            .map { try RelativePath(validating: $0) }
            .sorted { $0.pathString < $1.pathString }
        let expectedModifiedPaths = try expectedModified
            .map { try RelativePath(validating: $0) }
            .sorted { $0.pathString < $1.pathString }
        let expectedDeletedPaths = try expectedDeleted
            .map { try RelativePath(validating: $0) }
            .sorted { $0.pathString < $1.pathString }

        #expect(
            summary.added.sorted { $0.pathString < $1.pathString } == expectedAddedPaths,
            "Added files mismatch"
        )
        #expect(
            summary.modified.sorted { $0.pathString < $1.pathString } == expectedModifiedPaths,
            "Modified files mismatch"
        )
        #expect(
            summary.deleted.sorted { $0.pathString < $1.pathString } == expectedDeletedPaths,
            "Deleted files mismatch"
        )
    }

    struct FileEntry {
        let path: String
        let content: String
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let workingFiles: [FileEntry]
        let sandboxFiles: [FileEntry]
        let expectedAdded: [String]
        let expectedModified: [String]
        let expectedDeleted: [String]

        var testDescription: String { description }

        static let allCases: [TestCase] = [
            TestCase(
                description: "identical directories produce empty summary",
                workingFiles: [
                    FileEntry(path: "file.txt", content: "same content"),
                ],
                sandboxFiles: [
                    FileEntry(path: "file.txt", content: "same content"),
                ],
                expectedAdded: [],
                expectedModified: [],
                expectedDeleted: []
            ),
            TestCase(
                description: "detects single added file",
                workingFiles: [],
                sandboxFiles: [
                    FileEntry(path: "new.txt", content: "new content"),
                ],
                expectedAdded: ["new.txt"],
                expectedModified: [],
                expectedDeleted: []
            ),
            TestCase(
                description: "detects single modified file",
                workingFiles: [
                    FileEntry(path: "file.txt", content: "original"),
                ],
                sandboxFiles: [
                    FileEntry(path: "file.txt", content: "modified"),
                ],
                expectedAdded: [],
                expectedModified: ["file.txt"],
                expectedDeleted: []
            ),
            TestCase(
                description: "detects single deleted file",
                workingFiles: [
                    FileEntry(path: "removed.txt", content: "will be removed"),
                ],
                sandboxFiles: [],
                expectedAdded: [],
                expectedModified: [],
                expectedDeleted: ["removed.txt"]
            ),
            TestCase(
                description: "handles files in nested directories",
                workingFiles: [
                    FileEntry(path: "src/main.swift", content: "original main"),
                ],
                sandboxFiles: [
                    FileEntry(path: "src/main.swift", content: "modified main"),
                    FileEntry(path: "src/utils/helper.swift", content: "new helper"),
                ],
                expectedAdded: ["src/utils/helper.swift"],
                expectedModified: ["src/main.swift"],
                expectedDeleted: []
            ),
            TestCase(
                description: "handles mixed add, modify, delete",
                workingFiles: [
                    FileEntry(path: "keep.txt", content: "unchanged"),
                    FileEntry(path: "modify.txt", content: "original"),
                    FileEntry(path: "delete.txt", content: "to delete"),
                ],
                sandboxFiles: [
                    FileEntry(path: "keep.txt", content: "unchanged"),
                    FileEntry(path: "modify.txt", content: "modified"),
                    FileEntry(path: "add.txt", content: "new file"),
                ],
                expectedAdded: ["add.txt"],
                expectedModified: ["modify.txt"],
                expectedDeleted: ["delete.txt"]
            ),
            TestCase(
                description: "handles files with spaces in names",
                workingFiles: [],
                sandboxFiles: [
                    FileEntry(path: "my file.txt", content: "content"),
                    FileEntry(path: "folder with space/another file.txt", content: "nested"),
                ],
                expectedAdded: ["folder with space/another file.txt", "my file.txt"],
                expectedModified: [],
                expectedDeleted: []
            ),
            TestCase(
                description: "handles multiple files in same directory",
                workingFiles: [
                    FileEntry(path: "a.txt", content: "a original"),
                    FileEntry(path: "b.txt", content: "b original"),
                    FileEntry(path: "c.txt", content: "c unchanged"),
                ],
                sandboxFiles: [
                    FileEntry(path: "a.txt", content: "a modified"),
                    FileEntry(path: "c.txt", content: "c unchanged"),
                    FileEntry(path: "d.txt", content: "d new"),
                ],
                expectedAdded: ["d.txt"],
                expectedModified: ["a.txt"],
                expectedDeleted: ["b.txt"]
            ),
            TestCase(
                description: "handles deeply nested directories",
                workingFiles: [
                    FileEntry(path: "a/b/c/d/deep.txt", content: "original"),
                ],
                sandboxFiles: [
                    FileEntry(path: "a/b/c/d/deep.txt", content: "modified"),
                    FileEntry(path: "a/b/c/d/e/deeper.txt", content: "new"),
                ],
                expectedAdded: ["a/b/c/d/e/deeper.txt"],
                expectedModified: ["a/b/c/d/deep.txt"],
                expectedDeleted: []
            ),
            TestCase(
                description: "file changes across different subdirectories",
                workingFiles: [
                    FileEntry(path: "src/old.swift", content: "old code"),
                    FileEntry(path: "tests/test.swift", content: "test code"),
                ],
                sandboxFiles: [
                    FileEntry(path: "src/new.swift", content: "new code"),
                    FileEntry(path: "tests/test.swift", content: "updated test"),
                ],
                expectedAdded: ["src/new.swift"],
                expectedModified: ["tests/test.swift"],
                expectedDeleted: ["src/old.swift"]
            ),
        ]
    }

    /// Tests that directory paths in targetPaths are skipped and only file-level changes are detected.
    @Test
    func directoryPathsAreSkipped() async throws {
        try await fileSystem.withTemporaryDirectory(prefix: "git-diff-dir-skip-test") { tempRoot in
            let workingDir = tempRoot.appending(component: "working")
            let sandboxDir = tempRoot.appending(component: "sandbox")

            // Setup: both directories have identical content in Tests/EggKitTests/
            // but we'll include the directory path "Tests/EggKitTests" in targetPaths
            try await fileSystem.makeDirectory(at: workingDir)
            try await fileSystem.makeDirectory(at: sandboxDir)

            // Create identical files in both directories
            let workingTestsDir = workingDir.appending(components: ["Tests", "EggKitTests"])
            let sandboxTestsDir = sandboxDir.appending(components: ["Tests", "EggKitTests"])
            try await fileSystem.makeDirectory(at: workingTestsDir, options: [.createTargetParentDirectories])
            try await fileSystem.makeDirectory(at: sandboxTestsDir, options: [.createTargetParentDirectories])

            try await fileSystem.writeText("test1", at: workingTestsDir.appending(component: "Test1.swift"))
            try await fileSystem.writeText("test1", at: sandboxTestsDir.appending(component: "Test1.swift"))
            try await fileSystem.writeText("test2", at: workingTestsDir.appending(component: "Test2.swift"))
            try await fileSystem.writeText("test2", at: sandboxTestsDir.appending(component: "Test2.swift"))

            // Create a file that was actually changed in sandbox
            let workingSrcDir = workingDir.appending(component: "Sources")
            let sandboxSrcDir = sandboxDir.appending(component: "Sources")
            try await fileSystem.makeDirectory(at: workingSrcDir)
            try await fileSystem.makeDirectory(at: sandboxSrcDir)

            try await fileSystem.writeText("original", at: workingSrcDir.appending(component: "main.swift"))
            try await fileSystem.writeText("modified", at: sandboxSrcDir.appending(component: "main.swift"))

            // Include a directory path in targetPaths - this should be skipped
            // In practice, this happens when FSEvents reports directory-level changes
            let targetPaths: Set<RelativePath> = [
                try RelativePath(validating: "Tests/EggKitTests"), // directory - should be skipped
                try RelativePath(validating: "Sources/main.swift"), // file - should be processed
            ]

            let runner = GitDiffRunner(
                processRunner: ProcessRunner(),
                fileSystem: fileSystem
            )

            let summary = try await runner.computeChanges(
                sandboxRoot: sandboxDir,
                workingDirectory: workingDir,
                targetPaths: targetPaths
            )

            // Only the file change should be detected; the directory path should be skipped
            // and should NOT cause Test1.swift or Test2.swift to appear as deleted/modified
            #expect(summary.added.isEmpty, "No files should be added")
            #expect(
                summary.modified.map(\.pathString) == ["Sources/main.swift"],
                "Only Sources/main.swift should be modified"
            )
            #expect(summary.deleted.isEmpty, "No files should be deleted (directory path was skipped)")
        }
    }
}
