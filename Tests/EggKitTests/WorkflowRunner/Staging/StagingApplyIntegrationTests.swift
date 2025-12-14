@testable import EggKit
import FileManagerProtocol
import Foundation
import Noora
import ProcessRunning
import Testing

/// Integration tests for StagingContext's applyChanges functionality.
///
/// These tests verify the full workflow of:
/// 1. Creating a staging area from working directory
/// 2. Making changes in the staging area
/// 3. Applying changes back to the working directory
@Suite(.serialized)
struct StagingApplyIntegrationTests {
    @Test(arguments: TestCase.allCases)
    func applyChanges(_ testCase: TestCase) async throws {
        let fileManager: some FileManagerProtocol = FileManager.default
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "workspace-apply-test")

        defer {
            try? fileManager.removeItem(at: tempDir)
        }

        // Setup working directory
        let workingDir = tempDir.appending(path: "working")
        try fileManager.createDirectory(at: workingDir, withIntermediateDirectories: true)

        // Create initial files in working directory
        for file in testCase.initialFiles {
            let components = file.path.split(separator: "/").map(String.init)
            var filePath = workingDir
            for component in components {
                filePath = filePath.appending(path: component)
            }
            let parent = filePath.deletingLastPathComponent()
            if !fileManager.exists(parent) {
                try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            }
            try fileManager.writeText(file.content, at: filePath, encoding: .utf8)
        }

        // Create staging area with mock watchers for predictable testing
        let workspaceWatcher = MockDirectoryWatcher()
        let workingDirWatcher = MockDirectoryWatcher()

        let staging = try await StagingContext.create(
            cloning: workingDir,
            fileManager: fileManager,
            workspaceWatcher: workspaceWatcher,
            workingDirectoryWatcher: workingDirWatcher,
            processRunner: ProcessRunner(),
            requireGitRepository: false,
            noora: NooraMock()
        )

        let workspaceRoot = await staging.root

        defer {
            Task { await staging.discard() }
        }

        // Apply staging area modifications
        for modification in testCase.workspaceModifications {
            let components = modification.path.split(separator: "/").map(String.init)
            var path = workspaceRoot
            for component in components {
                path = path.appending(path: component)
            }

            switch modification.operation {
            case let .create(content):
                let parent = path.deletingLastPathComponent()
                if !fileManager.exists(parent) {
                    try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
                }
                try fileManager.writeText(content, at: path, encoding: .utf8)
                // Simulate watcher event
                await workspaceWatcher.simulateEvent(at: modification.path)

            case let .modify(content):
                try fileManager.writeText(content, at: path, encoding: .utf8)
                await workspaceWatcher.simulateEvent(at: modification.path)

            case .delete:
                try fileManager.removeItem(at: path)
                await workspaceWatcher.simulateEvent(at: modification.path)
            }
        }

        // Simulate concurrent working directory modifications if any
        for modification in testCase.workingDirModifications {
            let components = modification.path.split(separator: "/").map(String.init)
            var path = workingDir
            for component in components {
                path = path.appending(path: component)
            }

            switch modification.operation {
            case let .create(content):
                let parent = path.deletingLastPathComponent()
                if !fileManager.exists(parent) {
                    try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
                }
                try fileManager.writeText(content, at: path, encoding: .utf8)
                await workingDirWatcher.simulateEvent(at: modification.path)

            case let .modify(content):
                try fileManager.writeText(content, at: path, encoding: .utf8)
                await workingDirWatcher.simulateEvent(at: modification.path)

            case .delete:
                try fileManager.removeItem(at: path)
                await workingDirWatcher.simulateEvent(at: modification.path)
            }
        }

        // Execute test expectation
        switch testCase.expectation {
        case let .successfulApply(expectedFiles):
            let changes = try await staging.computeChangeSummary()
            let conflicts = try await staging.applyChanges(changes, override: testCase.forceApply)
            #expect(conflicts.isEmpty || testCase.forceApply, "Expected no conflicts when not forcing")

            // Verify expected files in working directory
            for expectedFile in expectedFiles {
                let components = expectedFile.path.split(separator: "/").map(String.init)
                var filePath = workingDir
                for component in components {
                    filePath = filePath.appending(path: component)
                }

                if let expectedContent = expectedFile.expectedContent {
                    #expect(fileManager.exists(filePath), "File '\(expectedFile.path)' should exist")
                    let data = try fileManager.readFile(at: filePath)
                    let content = String(data: data, encoding: .utf8)
                    #expect(content == expectedContent, "File '\(expectedFile.path)' should have content '\(expectedContent)', got '\(content ?? "nil")'")
                } else {
                    #expect(!fileManager.exists(filePath), "File '\(expectedFile.path)' should not exist")
                }
            }

        case let .conflictsDetected(expectedConflictPaths):
            // Without override, should throw conflict error
            let changes = try await staging.computeChangeSummary()
            let error = await #expect(throws: StagingContext.Error.self) {
                _ = try await staging.applyChanges(changes, override: false)
            }

            guard case let .conflictingFiles(conflicts) = error else {
                Issue.record("Expected conflictingFiles error, got \(String(describing: error))")
                return
            }

            let conflictPaths = conflicts.map { $0.pathString }.sorted()
            #expect(conflictPaths == expectedConflictPaths.sorted(), "Expected conflicts at \(expectedConflictPaths), got \(conflictPaths)")

        case .emptyChangeSummary:
            let summary = try await staging.computeChangeSummary()
            #expect(summary.isEmpty, "Expected empty change summary")
        }
    }

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
        let workspaceModifications: [Modification]
        let workingDirModifications: [Modification]
        let forceApply: Bool
        let expectation: Expectation

        var testDescription: String { description }

        init(
            description: String,
            initialFiles: [InitialFile] = [],
            workspaceModifications: [Modification] = [],
            workingDirModifications: [Modification] = [],
            forceApply: Bool = false,
            expectation: Expectation
        ) {
            self.description = description
            self.initialFiles = initialFiles
            self.workspaceModifications = workspaceModifications
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
                workspaceModifications: [
                    Modification(path: "new.txt", operation: .create(content: "new content")),
                ],
                expectation: .successfulApply(expectedFiles: [
                    ExpectedFile(path: "new.txt", expectedContent: "new content"),
                ])
            ),

            TestCase(
                description: "adds new file in subdirectory",
                initialFiles: [],
                workspaceModifications: [
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
                workspaceModifications: [
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
                workspaceModifications: [
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
                workspaceModifications: [
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
                description: "detects conflict when both staging area and working dir modify same file",
                initialFiles: [
                    InitialFile(path: "conflict.txt", content: "original"),
                ],
                workspaceModifications: [
                    Modification(path: "conflict.txt", operation: .modify(content: "workspace version")),
                ],
                workingDirModifications: [
                    Modification(path: "conflict.txt", operation: .modify(content: "working dir version")),
                ],
                expectation: .conflictsDetected(conflictPaths: ["conflict.txt"])
            ),

            // Override apply with conflicts
            TestCase(
                description: "override apply overrides conflicts",
                initialFiles: [
                    InitialFile(path: "conflict.txt", content: "original"),
                ],
                workspaceModifications: [
                    Modification(path: "conflict.txt", operation: .modify(content: "workspace wins")),
                ],
                workingDirModifications: [
                    Modification(path: "conflict.txt", operation: .modify(content: "working dir loses")),
                ],
                forceApply: true,
                expectation: .successfulApply(expectedFiles: [
                    ExpectedFile(path: "conflict.txt", expectedContent: "workspace wins"),
                ])
            ),
        ]
    }

    private func initializeGitRepository(at directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["init"]
        process.currentDirectoryURL = directory
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw GitInitializationError.failed(status: process.terminationStatus)
        }
    }

    private enum GitInitializationError: Error {
        case failed(status: Int32)
    }
}
