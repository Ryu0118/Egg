@testable import EggKit
import FileSystem
import Foundation
import Path
import ProcessRunning
import Testing

/// Integration tests for SandboxContext's applyChanges functionality.
///
/// These tests verify the full workflow of:
/// 1. Creating a sandbox from working directory
/// 2. Making changes in the sandbox
/// 3. Applying changes back to the working directory
struct SandboxApplyIntegrationTests {
    @Test(arguments: TestCase.allCases)
    func applyChanges(_ testCase: TestCase) async throws {
        let fileSystem = FileSystem()
        let tempDir = try await fileSystem.makeTemporaryDirectory(prefix: "sandbox-apply-test")

        defer {
            Task { try? await fileSystem.remove(tempDir) }
        }

        // Setup working directory
        let workingDir = tempDir.appending(component: "working")
        try await fileSystem.makeDirectory(at: workingDir)

        // Create initial files in working directory
        for file in testCase.initialFiles {
            let filePath = workingDir.appending(components: file.path.split(separator: "/").map(String.init))
            let parent = filePath.parentDirectory
            if try await !fileSystem.exists(parent) {
                try await fileSystem.makeDirectory(at: parent)
            }
            try await fileSystem.writeText(file.content, at: filePath)
        }

        // Create sandbox with mock watchers for predictable testing
        let sandboxWatcher = MockDirectoryWatcher()
        let workingDirWatcher = MockDirectoryWatcher()

        let sandbox = try await SandboxContext.create(
            cloning: workingDir,
            fileSystem: fileSystem,
            sandboxWatcher: sandboxWatcher,
            workingDirectoryWatcher: workingDirWatcher,
            processRunner: ProcessRunner()
        )

        let sandboxRoot = await sandbox.root

        defer {
            Task { await sandbox.discard() }
        }

        // Apply sandbox modifications
        for modification in testCase.sandboxModifications {
            let path = sandboxRoot.appending(components: modification.path.split(separator: "/").map(String.init))

            switch modification.operation {
            case .create(let content):
                let parent = path.parentDirectory
                if try await !fileSystem.exists(parent) {
                    try await fileSystem.makeDirectory(at: parent)
                }
                try await fileSystem.writeText(content, at: path)
                // Simulate watcher event
                let relativePath = try RelativePath(validating: modification.path)
                await sandboxWatcher.simulateEvent(at: relativePath)

            case .modify(let content):
                try await fileSystem.writeText(content, at: path, options: [.overwrite])
                let relativePath = try RelativePath(validating: modification.path)
                await sandboxWatcher.simulateEvent(at: relativePath)

            case .delete:
                try await fileSystem.remove(path)
                let relativePath = try RelativePath(validating: modification.path)
                await sandboxWatcher.simulateEvent(at: relativePath)
            }
        }

        // Simulate concurrent working directory modifications if any
        for modification in testCase.workingDirModifications {
            let path = workingDir.appending(components: modification.path.split(separator: "/").map(String.init))

            switch modification.operation {
            case .create(let content):
                let parent = path.parentDirectory
                if try await !fileSystem.exists(parent) {
                    try await fileSystem.makeDirectory(at: parent)
                }
                try await fileSystem.writeText(content, at: path)
                let relativePath = try RelativePath(validating: modification.path)
                await workingDirWatcher.simulateEvent(at: relativePath)

            case .modify(let content):
                try await fileSystem.writeText(content, at: path, options: [.overwrite])
                let relativePath = try RelativePath(validating: modification.path)
                await workingDirWatcher.simulateEvent(at: relativePath)

            case .delete:
                try await fileSystem.remove(path)
                let relativePath = try RelativePath(validating: modification.path)
                await workingDirWatcher.simulateEvent(at: relativePath)
            }
        }

        // Execute test expectation
        switch testCase.expectation {
        case .successfulApply(let expectedFiles):
            let changes = try await sandbox.computeChangeSummary()
            let conflicts = try await sandbox.applyChanges(changes, force: testCase.forceApply)
            #expect(conflicts.isEmpty || testCase.forceApply, "Expected no conflicts when not forcing")

            // Verify expected files in working directory
            for expectedFile in expectedFiles {
                let filePath = workingDir.appending(components: expectedFile.path.split(separator: "/").map(String.init))

                if let expectedContent = expectedFile.expectedContent {
                    #expect(try await fileSystem.exists(filePath), "File '\(expectedFile.path)' should exist")
                    let content = try await fileSystem.readTextFile(at: filePath)
                    #expect(content == expectedContent, "File '\(expectedFile.path)' should have content '\(expectedContent)', got '\(content)'")
                } else {
                    #expect(try await !fileSystem.exists(filePath), "File '\(expectedFile.path)' should not exist")
                }
            }

        case .conflictsDetected(let expectedConflictPaths):
            // Without force, should throw conflict error
            let changes = try await sandbox.computeChangeSummary()
            let error = await #expect(throws: SandboxContext.Error.self) {
                _ = try await sandbox.applyChanges(changes, force: false)
            }

            guard case let .conflictingFiles(conflicts) = error else {
                Issue.record("Expected conflictingFiles error, got \(String(describing: error))")
                return
            }

            let conflictPaths = conflicts.map { $0.path.pathString }.sorted()
            #expect(conflictPaths == expectedConflictPaths.sorted(), "Expected conflicts at \(expectedConflictPaths), got \(conflictPaths)")

        case .emptyChangeSummary:
            let summary = try await sandbox.computeChangeSummary()
            #expect(summary.isEmpty, "Expected empty change summary")
        }
    }

    // MARK: - Test Types

    struct InitialFile {
        let path: String
        let content: String
    }

    struct Modification {
        let path: String
        let operation: Operation

        enum Operation {
            case create(content: String)
            case modify(content: String)
            case delete
        }
    }

    struct ExpectedFile {
        let path: String
        let expectedContent: String? // nil means file should not exist
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let initialFiles: [InitialFile]
        let sandboxModifications: [Modification]
        let workingDirModifications: [Modification]
        let forceApply: Bool
        let expectation: Expectation

        var testDescription: String { description }

        init(
            description: String,
            initialFiles: [InitialFile] = [],
            sandboxModifications: [Modification] = [],
            workingDirModifications: [Modification] = [],
            forceApply: Bool = false,
            expectation: Expectation
        ) {
            self.description = description
            self.initialFiles = initialFiles
            self.sandboxModifications = sandboxModifications
            self.workingDirModifications = workingDirModifications
            self.forceApply = forceApply
            self.expectation = expectation
        }

        enum Expectation {
            case successfulApply(expectedFiles: [ExpectedFile])
            case conflictsDetected(conflictPaths: [String])
            case emptyChangeSummary
        }

        static let allCases: [TestCase] = [
            // No changes
            TestCase(
                description: "no changes results in empty summary",
                initialFiles: [
                    InitialFile(path: "file.txt", content: "original"),
                ],
                expectation: .emptyChangeSummary
            ),

            // Add file
            TestCase(
                description: "adds new file to working directory",
                initialFiles: [],
                sandboxModifications: [
                    Modification(path: "new.txt", operation: .create(content: "new content")),
                ],
                expectation: .successfulApply(expectedFiles: [
                    ExpectedFile(path: "new.txt", expectedContent: "new content"),
                ])
            ),

            TestCase(
                description: "adds new file in subdirectory",
                initialFiles: [],
                sandboxModifications: [
                    Modification(path: "subdir/nested/new.txt", operation: .create(content: "nested content")),
                ],
                expectation: .successfulApply(expectedFiles: [
                    ExpectedFile(path: "subdir/nested/new.txt", expectedContent: "nested content"),
                ])
            ),

            // Modify file
            TestCase(
                description: "modifies existing file",
                initialFiles: [
                    InitialFile(path: "file.txt", content: "original"),
                ],
                sandboxModifications: [
                    Modification(path: "file.txt", operation: .modify(content: "modified")),
                ],
                expectation: .successfulApply(expectedFiles: [
                    ExpectedFile(path: "file.txt", expectedContent: "modified"),
                ])
            ),

            // Delete file
            TestCase(
                description: "deletes file from working directory",
                initialFiles: [
                    InitialFile(path: "delete-me.txt", content: "to delete"),
                ],
                sandboxModifications: [
                    Modification(path: "delete-me.txt", operation: .delete),
                ],
                expectation: .successfulApply(expectedFiles: [
                    ExpectedFile(path: "delete-me.txt", expectedContent: nil),
                ])
            ),

            // Multiple operations
            TestCase(
                description: "handles multiple operations",
                initialFiles: [
                    InitialFile(path: "keep.txt", content: "keep"),
                    InitialFile(path: "modify.txt", content: "original"),
                    InitialFile(path: "delete.txt", content: "to delete"),
                ],
                sandboxModifications: [
                    Modification(path: "modify.txt", operation: .modify(content: "modified")),
                    Modification(path: "delete.txt", operation: .delete),
                    Modification(path: "new.txt", operation: .create(content: "new")),
                ],
                expectation: .successfulApply(expectedFiles: [
                    ExpectedFile(path: "keep.txt", expectedContent: "keep"),
                    ExpectedFile(path: "modify.txt", expectedContent: "modified"),
                    ExpectedFile(path: "delete.txt", expectedContent: nil),
                    ExpectedFile(path: "new.txt", expectedContent: "new"),
                ])
            ),

            // Conflict detection
            TestCase(
                description: "detects conflict when both sandbox and working dir modify same file",
                initialFiles: [
                    InitialFile(path: "conflict.txt", content: "original"),
                ],
                sandboxModifications: [
                    Modification(path: "conflict.txt", operation: .modify(content: "sandbox version")),
                ],
                workingDirModifications: [
                    Modification(path: "conflict.txt", operation: .modify(content: "working dir version")),
                ],
                expectation: .conflictsDetected(conflictPaths: ["conflict.txt"])
            ),

            // Force apply with conflicts
            TestCase(
                description: "force apply overrides conflicts",
                initialFiles: [
                    InitialFile(path: "conflict.txt", content: "original"),
                ],
                sandboxModifications: [
                    Modification(path: "conflict.txt", operation: .modify(content: "sandbox wins")),
                ],
                workingDirModifications: [
                    Modification(path: "conflict.txt", operation: .modify(content: "working dir loses")),
                ],
                forceApply: true,
                expectation: .successfulApply(expectedFiles: [
                    ExpectedFile(path: "conflict.txt", expectedContent: "sandbox wins"),
                ])
            ),
        ]
    }
}
