@testable import EggKit
import FileManagerProtocol
import Foundation
import ProcessRunning
import Testing

/// Integration tests that verify GitDiffRunner correctly computes changes
/// between working directory and workspace using real file system and git.
struct GitDiffRunnerIntegrationTests {
    private let fileManager: any FileManagerProtocol = FileManager.default

    @Test("compute changes", arguments: TestCase.allCases)
    func computeChanges(_ testCase: TestCase) async throws {
        let tempRoot = try fileManager.makeTemporaryDirectory(prefix: "git-diff-runner-test")
        defer { try? fileManager.removeItem(at: tempRoot) }

        let workingDir = tempRoot.appending(path: "working")
        let workspaceDir = tempRoot.appending(path: "staging")

        try setupDirectory(workingDir, files: testCase.workingFiles)
        try setupDirectory(workspaceDir, files: testCase.workspaceFiles)

        let targetPaths = buildTargetPaths(testCase: testCase)

        let runner = GitDiffRunner(
            processRunner: ProcessRunner(),
            fileManager: fileManager,
        )

        let summary = try await runner.computeChanges(
            workspaceRoot: workspaceDir,
            workingDirectory: workingDir,
            targetPaths: targetPaths,
        )

        assertChangeSummary(
            summary,
            expectedAdded: testCase.expectedAdded,
            expectedModified: testCase.expectedModified,
            expectedDeleted: testCase.expectedDeleted,
        )
    }

    /// Tests that directory paths in targetPaths are skipped and only file-level changes are detected.
    @Test("directory paths are skipped")
    func directoryPathsAreSkipped() async throws {
        let tempRoot = try fileManager.makeTemporaryDirectory(prefix: "git-diff-dir-skip-test")
        defer { try? fileManager.removeItem(at: tempRoot) }

        let workingDir = tempRoot.appending(path: "working")
        let workspaceDir = tempRoot.appending(path: "staging")

        // Setup: both directories have identical content in Tests/EggKitTests/
        // but we'll include the directory path "Tests/EggKitTests" in targetPaths
        try fileManager.createDirectory(at: workingDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workspaceDir, withIntermediateDirectories: true)

        // Create identical files in both directories
        let workingTestsDir = workingDir.appending(path: "Tests").appending(path: "EggKitTests")
        let workspaceTestsDir = workspaceDir.appending(path: "Tests").appending(path: "EggKitTests")
        try fileManager.createDirectory(at: workingTestsDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workspaceTestsDir, withIntermediateDirectories: true)

        let workingTest1 = workingTestsDir.appending(path: "Test1.swift")
        let workspaceTest1 = workspaceTestsDir.appending(path: "Test1.swift")
        let workingTest2 = workingTestsDir.appending(path: "Test2.swift")
        let workspaceTest2 = workspaceTestsDir.appending(path: "Test2.swift")
        try fileManager.writeText("test1", at: workingTest1, encoding: .utf8)
        try fileManager.writeText("test1", at: workspaceTest1, encoding: .utf8)
        try fileManager.writeText("test2", at: workingTest2, encoding: .utf8)
        try fileManager.writeText("test2", at: workspaceTest2, encoding: .utf8)

        // Create a file that was actually changed in workspace
        let workingSrcDir = workingDir.appending(path: "Sources")
        let workspaceSrcDir = workspaceDir.appending(path: "Sources")
        try fileManager.createDirectory(at: workingSrcDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workspaceSrcDir, withIntermediateDirectories: true)

        let workingMain = workingSrcDir.appending(path: "main.swift")
        let workspaceMain = workspaceSrcDir.appending(path: "main.swift")
        try fileManager.writeText("original", at: workingMain, encoding: .utf8)
        try fileManager.writeText("modified", at: workspaceMain, encoding: .utf8)

        // Include a directory path in targetPaths - this should be skipped
        // In practice, this happens when FSEvents reports directory-level changes
        let targetPaths: Set = [
            "Tests/EggKitTests", // directory - should be skipped
            "Sources/main.swift", // file - should be processed
        ]

        let runner = GitDiffRunner(
            processRunner: ProcessRunner(),
            fileManager: fileManager,
        )

        let summary = try await runner.computeChanges(
            workspaceRoot: workspaceDir,
            workingDirectory: workingDir,
            targetPaths: targetPaths,
        )

        // Only the file change should be detected; the directory path should be skipped
        // and should NOT cause Test1.swift or Test2.swift to appear as deleted/modified
        #expect(summary.added.isEmpty, "No files should be added")
        #expect(
            summary.modified == ["Sources/main.swift"],
            "Only Sources/main.swift should be modified",
        )
        #expect(summary.deleted.isEmpty, "No files should be deleted (directory path was skipped)")
    }

    /// Creates a directory and populates it with the specified files.
    private func setupDirectory(
        _ directory: URL,
        files: [FileEntry],
    ) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        for file in files {
            let components = file.path.split(separator: "/").map(String.init)
            var path = directory
            for component in components {
                path = path.appending(path: component)
            }
            try createFileWithParentDirectories(at: path, content: file.content)
        }
    }

    /// Creates a file at the given path, creating parent directories as needed.
    private func createFileWithParentDirectories(
        at path: URL,
        content: String,
    ) throws {
        let parent = path.deletingLastPathComponent()
        if !fileManager.exists(parent) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        try fileManager.writeText(content, at: path, encoding: .utf8)
    }

    /// Builds the set of target paths from all files in the test case.
    private func buildTargetPaths(testCase: TestCase) -> Set<String> {
        var paths = Set<String>()
        for file in testCase.workingFiles {
            paths.insert(file.path)
        }
        for file in testCase.workspaceFiles {
            paths.insert(file.path)
        }
        return paths
    }

    /// Asserts that the change summary matches expected values.
    private func assertChangeSummary(
        _ summary: ChangeSummary,
        expectedAdded: [String],
        expectedModified: [String],
        expectedDeleted: [String],
    ) {
        let expectedAddedPaths = expectedAdded.sorted()
        let expectedModifiedPaths = expectedModified.sorted()
        let expectedDeletedPaths = expectedDeleted.sorted()

        #expect(
            summary.added.sorted() == expectedAddedPaths,
            "Added files mismatch",
        )
        #expect(
            summary.modified.sorted() == expectedModifiedPaths,
            "Modified files mismatch",
        )
        #expect(
            summary.deleted.sorted() == expectedDeletedPaths,
            "Deleted files mismatch",
        )
    }

    struct FileEntry {
        let path: String
        let content: String
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let workingFiles: [FileEntry]
        let workspaceFiles: [FileEntry]
        let expectedAdded: [String]
        let expectedModified: [String]
        let expectedDeleted: [String]

        static let allCases: [TestCase] = [
            TestCase(
                description: "identical directories produce empty summary",
                workingFiles: [
                    FileEntry(path: "file.txt", content: "same content"),
                ],
                workspaceFiles: [
                    FileEntry(path: "file.txt", content: "same content"),
                ],
                expectedAdded: [],
                expectedModified: [],
                expectedDeleted: [],
            ),
            TestCase(
                description: "detects single added file",
                workingFiles: [],
                workspaceFiles: [
                    FileEntry(path: "new.txt", content: "new content"),
                ],
                expectedAdded: ["new.txt"],
                expectedModified: [],
                expectedDeleted: [],
            ),
            TestCase(
                description: "detects single modified file",
                workingFiles: [
                    FileEntry(path: "file.txt", content: "original"),
                ],
                workspaceFiles: [
                    FileEntry(path: "file.txt", content: "modified"),
                ],
                expectedAdded: [],
                expectedModified: ["file.txt"],
                expectedDeleted: [],
            ),
            TestCase(
                description: "detects single deleted file",
                workingFiles: [
                    FileEntry(path: "removed.txt", content: "will be removed"),
                ],
                workspaceFiles: [],
                expectedAdded: [],
                expectedModified: [],
                expectedDeleted: ["removed.txt"],
            ),
            TestCase(
                description: "handles files in nested directories",
                workingFiles: [
                    FileEntry(path: "src/main.swift", content: "original main"),
                ],
                workspaceFiles: [
                    FileEntry(path: "src/main.swift", content: "modified main"),
                    FileEntry(path: "src/utils/helper.swift", content: "new helper"),
                ],
                expectedAdded: ["src/utils/helper.swift"],
                expectedModified: ["src/main.swift"],
                expectedDeleted: [],
            ),
            TestCase(
                description: "handles mixed add, modify, delete",
                workingFiles: [
                    FileEntry(path: "keep.txt", content: "unchanged"),
                    FileEntry(path: "modify.txt", content: "original"),
                    FileEntry(path: "delete.txt", content: "to delete"),
                ],
                workspaceFiles: [
                    FileEntry(path: "keep.txt", content: "unchanged"),
                    FileEntry(path: "modify.txt", content: "modified"),
                    FileEntry(path: "add.txt", content: "new file"),
                ],
                expectedAdded: ["add.txt"],
                expectedModified: ["modify.txt"],
                expectedDeleted: ["delete.txt"],
            ),
            TestCase(
                description: "handles files with spaces in names",
                workingFiles: [],
                workspaceFiles: [
                    FileEntry(path: "my file.txt", content: "content"),
                    FileEntry(path: "folder with space/another file.txt", content: "nested"),
                ],
                expectedAdded: ["folder with space/another file.txt", "my file.txt"],
                expectedModified: [],
                expectedDeleted: [],
            ),
            TestCase(
                description: "handles multiple files in same directory",
                workingFiles: [
                    FileEntry(path: "a.txt", content: "a original"),
                    FileEntry(path: "b.txt", content: "b original"),
                    FileEntry(path: "c.txt", content: "c unchanged"),
                ],
                workspaceFiles: [
                    FileEntry(path: "a.txt", content: "a modified"),
                    FileEntry(path: "c.txt", content: "c unchanged"),
                    FileEntry(path: "d.txt", content: "d new"),
                ],
                expectedAdded: ["d.txt"],
                expectedModified: ["a.txt"],
                expectedDeleted: ["b.txt"],
            ),
            TestCase(
                description: "handles deeply nested directories",
                workingFiles: [
                    FileEntry(path: "a/b/c/d/deep.txt", content: "original"),
                ],
                workspaceFiles: [
                    FileEntry(path: "a/b/c/d/deep.txt", content: "modified"),
                    FileEntry(path: "a/b/c/d/e/deeper.txt", content: "new"),
                ],
                expectedAdded: ["a/b/c/d/e/deeper.txt"],
                expectedModified: ["a/b/c/d/deep.txt"],
                expectedDeleted: [],
            ),
            TestCase(
                description: "file changes across different subdirectories",
                workingFiles: [
                    FileEntry(path: "src/old.swift", content: "old code"),
                    FileEntry(path: "tests/test.swift", content: "test code"),
                ],
                workspaceFiles: [
                    FileEntry(path: "src/new.swift", content: "new code"),
                    FileEntry(path: "tests/test.swift", content: "updated test"),
                ],
                expectedAdded: ["src/new.swift"],
                expectedModified: ["tests/test.swift"],
                expectedDeleted: ["src/old.swift"],
            ),
        ]

        var testDescription: String {
            description
        }
    }
}
