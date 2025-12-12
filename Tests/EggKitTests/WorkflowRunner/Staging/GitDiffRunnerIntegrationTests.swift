@testable import EggKit
import FileManagerProtocol
import Foundation
import Path
import ProcessRunning
import Testing

/// Integration tests that verify GitDiffRunner correctly computes changes
/// between working directory and workspace using real file system and git.
struct GitDiffRunnerIntegrationTests {
    private let fileManager = FileManager.default

    @Test(arguments: TestCase.allCases)
    func computeChanges(_ testCase: TestCase) async throws {
        try await fileManager.withTemporaryDirectory(prefix: "git-diff-runner-test") { tempRoot in
            let workingDir = tempRoot.appending(component: "working")
            let workspaceDir = tempRoot.appending(component: "staging")

            try await setupDirectory(workingDir, files: testCase.workingFiles)
            try await setupDirectory(workspaceDir, files: testCase.workspaceFiles)

            let targetPaths = try buildTargetPaths(testCase: testCase)

            let runner = GitDiffRunner(
                processRunner: ProcessRunner(),
                fileManager: fileManager
            )

            let summary = try await runner.computeChanges(
                workspaceRoot: workspaceDir,
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
        let directoryURL = URL(filePath: directory.pathString)
        try await fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

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
        if try await !fileManager.exists(parent) {
            let parentURL = URL(filePath: parent.pathString)
            try await fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        }
        let fileURL = URL(filePath: path.pathString)
        try await fileManager.writeText(content, at: fileURL)
    }

    /// Builds the set of target paths from all files in the test case.
    private func buildTargetPaths(testCase: TestCase) throws -> Set<RelativePath> {
        var paths = Set<RelativePath>()
        for file in testCase.workingFiles {
            try paths.insert(RelativePath(validating: file.path))
        }
        for file in testCase.workspaceFiles {
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
        let workspaceFiles: [FileEntry]
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
                workspaceFiles: [
                    FileEntry(path: "file.txt", content: "same content"),
                ],
                expectedAdded: [],
                expectedModified: [],
                expectedDeleted: []
            ),
            TestCase(
                description: "detects single added file",
                workingFiles: [],
                workspaceFiles: [
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
                workspaceFiles: [
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
                workspaceFiles: [],
                expectedAdded: [],
                expectedModified: [],
                expectedDeleted: ["removed.txt"]
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
                expectedDeleted: []
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
                expectedDeleted: ["delete.txt"]
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
                expectedDeleted: []
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
                expectedDeleted: ["b.txt"]
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
                expectedDeleted: []
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
                expectedDeleted: ["src/old.swift"]
            ),
        ]
    }

    /// Tests that directory paths in targetPaths are skipped and only file-level changes are detected.
    @Test
    func directoryPathsAreSkipped() async throws {
        try await fileManager.withTemporaryDirectory(prefix: "git-diff-dir-skip-test") { tempRoot in
            let workingDir = tempRoot.appending(component: "working")
            let workspaceDir = tempRoot.appending(component: "staging")

            // Setup: both directories have identical content in Tests/EggKitTests/
            // but we'll include the directory path "Tests/EggKitTests" in targetPaths
            let workingDirURL = URL(filePath: workingDir.pathString)
            let workspaceDirURL = URL(filePath: workspaceDir.pathString)
            try await fileManager.createDirectory(at: workingDirURL, withIntermediateDirectories: true)
            try await fileManager.createDirectory(at: workspaceDirURL, withIntermediateDirectories: true)

            // Create identical files in both directories
            let workingTestsDir = workingDir.appending(components: ["Tests", "EggKitTests"])
            let workspaceTestsDir = workspaceDir.appending(components: ["Tests", "EggKitTests"])
            let workingTestsDirURL = URL(filePath: workingTestsDir.pathString)
            let workspaceTestsDirURL = URL(filePath: workspaceTestsDir.pathString)
            try await fileManager.createDirectory(at: workingTestsDirURL, withIntermediateDirectories: true)
            try await fileManager.createDirectory(at: workspaceTestsDirURL, withIntermediateDirectories: true)

            let workingTest1 = URL(filePath: workingTestsDir.appending(component: "Test1.swift").pathString)
            let workspaceTest1 = URL(filePath: workspaceTestsDir.appending(component: "Test1.swift").pathString)
            let workingTest2 = URL(filePath: workingTestsDir.appending(component: "Test2.swift").pathString)
            let workspaceTest2 = URL(filePath: workspaceTestsDir.appending(component: "Test2.swift").pathString)
            try await fileManager.writeText("test1", at: workingTest1)
            try await fileManager.writeText("test1", at: workspaceTest1)
            try await fileManager.writeText("test2", at: workingTest2)
            try await fileManager.writeText("test2", at: workspaceTest2)

            // Create a file that was actually changed in workspace
            let workingSrcDir = workingDir.appending(component: "Sources")
            let workspaceSrcDir = workspaceDir.appending(component: "Sources")
            let workingSrcDirURL = URL(filePath: workingSrcDir.pathString)
            let workspaceSrcDirURL = URL(filePath: workspaceSrcDir.pathString)
            try await fileManager.createDirectory(at: workingSrcDirURL, withIntermediateDirectories: true)
            try await fileManager.createDirectory(at: workspaceSrcDirURL, withIntermediateDirectories: true)

            let workingMain = URL(filePath: workingSrcDir.appending(component: "main.swift").pathString)
            let workspaceMain = URL(filePath: workspaceSrcDir.appending(component: "main.swift").pathString)
            try await fileManager.writeText("original", at: workingMain)
            try await fileManager.writeText("modified", at: workspaceMain)

            // Include a directory path in targetPaths - this should be skipped
            // In practice, this happens when FSEvents reports directory-level changes
            let targetPaths: Set<RelativePath> = try [
                RelativePath(validating: "Tests/EggKitTests"), // directory - should be skipped
                RelativePath(validating: "Sources/main.swift"), // file - should be processed
            ]

            let runner = GitDiffRunner(
                processRunner: ProcessRunner(),
                fileManager: fileManager
            )

            let summary = try await runner.computeChanges(
                workspaceRoot: workspaceDir,
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
