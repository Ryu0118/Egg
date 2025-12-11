@testable import EggKit
import FileSystem
import Foundation
import Path
import Testing

struct ApplyStagingAreaTests {
    @Test(arguments: TestCase.allCases)
    func applyStagingArea(_ testCase: TestCase) async throws {
        let context = try await TestContext.setUp(testCase: testCase)
        defer { Task { await context.tearDown() } }

        switch testCase.expectation {
        case let .success(expectedFiles):
            try await context.executeStageAndApply()
            try await context.verifyExpectedFiles(expectedFiles)

        case .emptyManifest:
            try await context.verifyEmptyManifest()

        case let .manifestCounts(add, modify, delete):
            try await context.verifyManifestCounts(add: add, modify: modify, delete: delete)

        case .stagingCleanedUp:
            let stagingRoot = try await context.executeStageAndApplyReturningRoot()
            try await context.verifyStagingCleanedUp(stagingRoot: stagingRoot)

        case .stagingCleanedUpOnError:
            let stagingRoot = try await context.executeStagingWithError()
            try await context.verifyStagingCleanedUp(stagingRoot: stagingRoot)
        }
    }
}

extension ApplyStagingAreaTests {
    struct TestContext {
        let fileSystem: FileSystem
        let tempDir: AbsolutePath
        let workspaceRoot: AbsolutePath
        let workingDir: AbsolutePath
        let changes: ChangeSummary

        static func setUp(testCase: TestCase) async throws -> TestContext {
            let fileSystem = FileSystem()
            let tempDir = try await fileSystem.makeTemporaryDirectory(prefix: "staging-test")

            let workspaceRoot = tempDir.appending(component: "workspace")
            let workingDir = tempDir.appending(component: "working")

            try await fileSystem.makeDirectory(at: workspaceRoot)
            try await fileSystem.makeDirectory(at: workingDir)

            try await createFiles(testCase.workspaceFiles, in: workspaceRoot, fileSystem: fileSystem)
            try await createFiles(testCase.workingDirFiles, in: workingDir, fileSystem: fileSystem)

            let changes = try buildChangeSummary(testCase: testCase)

            return TestContext(
                fileSystem: fileSystem,
                tempDir: tempDir,
                workspaceRoot: workspaceRoot,
                workingDir: workingDir,
                changes: changes
            )
        }

        func tearDown() async {
            try? await fileSystem.remove(tempDir)
        }

        func executeStageAndApply() async throws {
            try await ApplyStagingArea.withStaging(
                workspaceRoot: workspaceRoot,
                workingDirectory: workingDir,
                fileSystem: fileSystem
            ) { staging, fs in
                let manifest = try await staging.stage(changes: changes, fileSystem: fs)
                try await staging.apply(manifest: manifest, fileSystem: fs)
            }
        }

        func executeStageAndApplyReturningRoot() async throws -> AbsolutePath {
            let staging = try await ApplyStagingArea.create(
                workspaceRoot: workspaceRoot,
                workingDirectory: workingDir,
                fileSystem: fileSystem
            )
            let root = staging.root

            do {
                let manifest = try await staging.stage(changes: changes, fileSystem: fileSystem)
                try await staging.apply(manifest: manifest, fileSystem: fileSystem)
                await staging.cleanup(fileSystem: fileSystem)
            } catch {
                await staging.cleanup(fileSystem: fileSystem)
                throw error
            }

            return root
        }

        func executeStagingWithError() async throws -> AbsolutePath {
            let staging = try await ApplyStagingArea.create(
                workspaceRoot: workspaceRoot,
                workingDirectory: workingDir,
                fileSystem: fileSystem
            )
            let root = staging.root

            do {
                let badChanges = try ChangeSummary(
                    added: [RelativePath(validating: "nonexistent.txt")],
                    modified: [],
                    deleted: []
                )
                _ = try await staging.stage(changes: badChanges, fileSystem: fileSystem)
                await staging.cleanup(fileSystem: fileSystem)
            } catch {
                await staging.cleanup(fileSystem: fileSystem)
            }

            return root
        }

        func verifyExpectedFiles(_ expectedFiles: [ExpectedFile]) async throws {
            for expectedFile in expectedFiles {
                let filePath = workingDir.appending(
                    components: expectedFile.path.split(separator: "/").map(String.init)
                )

                if let expectedContent = expectedFile.expectedContent {
                    #expect(
                        try await fileSystem.exists(filePath),
                        "File '\(expectedFile.path)' should exist"
                    )
                    let content = try await fileSystem.readTextFile(at: filePath)
                    #expect(
                        content == expectedContent,
                        "File '\(expectedFile.path)' content mismatch: expected '\(expectedContent)', got '\(content)'"
                    )
                } else {
                    #expect(
                        try await !fileSystem.exists(filePath),
                        "File '\(expectedFile.path)' should not exist"
                    )
                }
            }
        }

        func verifyEmptyManifest() async throws {
            try await ApplyStagingArea.withStaging(
                workspaceRoot: workspaceRoot,
                workingDirectory: workingDir,
                fileSystem: fileSystem
            ) { staging, fs in
                let manifest = try await staging.stage(changes: changes, fileSystem: fs)
                #expect(manifest.totalCount == 0, "Expected empty manifest")
            }
        }

        func verifyManifestCounts(add: Int, modify: Int, delete: Int) async throws {
            try await ApplyStagingArea.withStaging(
                workspaceRoot: workspaceRoot,
                workingDirectory: workingDir,
                fileSystem: fileSystem
            ) { staging, fs in
                let manifest = try await staging.stage(changes: changes, fileSystem: fs)
                #expect(manifest.addCount == add, "Expected \(add) adds, got \(manifest.addCount)")
                #expect(manifest.modifyCount == modify, "Expected \(modify) modifies, got \(manifest.modifyCount)")
                #expect(manifest.deleteCount == delete, "Expected \(delete) deletes, got \(manifest.deleteCount)")
            }
        }

        func verifyStagingCleanedUp(stagingRoot: AbsolutePath) async throws {
            #expect(
                try await !fileSystem.exists(stagingRoot),
                "Staging directory should be cleaned up"
            )
        }

        private static func createFiles(
            _ files: [FileEntry],
            in directory: AbsolutePath,
            fileSystem: FileSystem
        ) async throws {
            for file in files {
                let filePath = directory.appending(
                    components: file.path.split(separator: "/").map(String.init)
                )
                let parent = filePath.parentDirectory
                if try await !fileSystem.exists(parent) {
                    try await fileSystem.makeDirectory(at: parent)
                }
                try await fileSystem.writeText(file.content, at: filePath)
            }
        }

        private static func buildChangeSummary(testCase: TestCase) throws -> ChangeSummary {
            let added = try testCase.addedPaths.map { try RelativePath(validating: $0) }
            let modified = try testCase.modifiedPaths.map { try RelativePath(validating: $0) }
            let deleted = try testCase.deletedPaths.map { try RelativePath(validating: $0) }
            return ChangeSummary(added: added, modified: modified, deleted: deleted)
        }
    }
}

extension ApplyStagingAreaTests {
    struct FileEntry {
        let path: String
        let content: String
    }

    struct ExpectedFile {
        let path: String
        let expectedContent: String? // nil means file should not exist
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let workspaceFiles: [FileEntry]
        let workingDirFiles: [FileEntry]
        let addedPaths: [String]
        let modifiedPaths: [String]
        let deletedPaths: [String]
        let expectation: Expectation

        var testDescription: String { description }

        init(
            description: String,
            workspaceFiles: [FileEntry] = [],
            workingDirFiles: [FileEntry] = [],
            addedPaths: [String] = [],
            modifiedPaths: [String] = [],
            deletedPaths: [String] = [],
            expectation: Expectation
        ) {
            self.description = description
            self.workspaceFiles = workspaceFiles
            self.workingDirFiles = workingDirFiles
            self.addedPaths = addedPaths
            self.modifiedPaths = modifiedPaths
            self.deletedPaths = deletedPaths
            self.expectation = expectation
        }

        enum Expectation {
            case success(expectedFiles: [ExpectedFile])
            case emptyManifest
            case manifestCounts(add: Int, modify: Int, delete: Int)
            case stagingCleanedUp
            case stagingCleanedUpOnError
        }
    }
}

extension ApplyStagingAreaTests.TestCase {
    static let allCases: [ApplyStagingAreaTests.TestCase] = [
        emptyChangesCase,
    ] + addOperationCases
        + modifyOperationCases
        + deleteOperationCases
        + mixedOperationCases
        + manifestCountCases
        + cleanupCases
        + edgeCases

    private static let emptyChangesCase = ApplyStagingAreaTests.TestCase(
        description: "empty changes produces empty manifest",
        expectation: .emptyManifest
    )

    private static let addOperationCases: [ApplyStagingAreaTests.TestCase] = [
        ApplyStagingAreaTests.TestCase(
            description: "stages and applies single added file",
            workspaceFiles: [
                ApplyStagingAreaTests.FileEntry(path: "new.txt", content: "new content"),
            ],
            addedPaths: ["new.txt"],
            expectation: .success(expectedFiles: [
                ApplyStagingAreaTests.ExpectedFile(path: "new.txt", expectedContent: "new content"),
            ])
        ),
        ApplyStagingAreaTests.TestCase(
            description: "stages and applies added file in subdirectory",
            workspaceFiles: [
                ApplyStagingAreaTests.FileEntry(path: "subdir/nested/file.txt", content: "nested content"),
            ],
            addedPaths: ["subdir/nested/file.txt"],
            expectation: .success(expectedFiles: [
                ApplyStagingAreaTests.ExpectedFile(path: "subdir/nested/file.txt", expectedContent: "nested content"),
            ])
        ),
        ApplyStagingAreaTests.TestCase(
            description: "stages and applies multiple added files",
            workspaceFiles: [
                ApplyStagingAreaTests.FileEntry(path: "file1.txt", content: "content1"),
                ApplyStagingAreaTests.FileEntry(path: "file2.txt", content: "content2"),
                ApplyStagingAreaTests.FileEntry(path: "dir/file3.txt", content: "content3"),
            ],
            addedPaths: ["file1.txt", "file2.txt", "dir/file3.txt"],
            expectation: .success(expectedFiles: [
                ApplyStagingAreaTests.ExpectedFile(path: "file1.txt", expectedContent: "content1"),
                ApplyStagingAreaTests.ExpectedFile(path: "file2.txt", expectedContent: "content2"),
                ApplyStagingAreaTests.ExpectedFile(path: "dir/file3.txt", expectedContent: "content3"),
            ])
        ),
    ]

    private static let modifyOperationCases: [ApplyStagingAreaTests.TestCase] = [
        ApplyStagingAreaTests.TestCase(
            description: "stages and applies single modified file",
            workspaceFiles: [
                ApplyStagingAreaTests.FileEntry(path: "existing.txt", content: "modified content"),
            ],
            workingDirFiles: [
                ApplyStagingAreaTests.FileEntry(path: "existing.txt", content: "original content"),
            ],
            modifiedPaths: ["existing.txt"],
            expectation: .success(expectedFiles: [
                ApplyStagingAreaTests.ExpectedFile(path: "existing.txt", expectedContent: "modified content"),
            ])
        ),
        ApplyStagingAreaTests.TestCase(
            description: "stages and applies multiple modified files",
            workspaceFiles: [
                ApplyStagingAreaTests.FileEntry(path: "file1.txt", content: "modified1"),
                ApplyStagingAreaTests.FileEntry(path: "dir/file2.txt", content: "modified2"),
            ],
            workingDirFiles: [
                ApplyStagingAreaTests.FileEntry(path: "file1.txt", content: "original1"),
                ApplyStagingAreaTests.FileEntry(path: "dir/file2.txt", content: "original2"),
            ],
            modifiedPaths: ["file1.txt", "dir/file2.txt"],
            expectation: .success(expectedFiles: [
                ApplyStagingAreaTests.ExpectedFile(path: "file1.txt", expectedContent: "modified1"),
                ApplyStagingAreaTests.ExpectedFile(path: "dir/file2.txt", expectedContent: "modified2"),
            ])
        ),
    ]

    private static let deleteOperationCases: [ApplyStagingAreaTests.TestCase] = [
        ApplyStagingAreaTests.TestCase(
            description: "stages and applies single deleted file",
            workingDirFiles: [
                ApplyStagingAreaTests.FileEntry(path: "delete-me.txt", content: "to be deleted"),
            ],
            deletedPaths: ["delete-me.txt"],
            expectation: .success(expectedFiles: [
                ApplyStagingAreaTests.ExpectedFile(path: "delete-me.txt", expectedContent: nil),
            ])
        ),
        ApplyStagingAreaTests.TestCase(
            description: "stages and applies multiple deleted files",
            workingDirFiles: [
                ApplyStagingAreaTests.FileEntry(path: "delete1.txt", content: "content1"),
                ApplyStagingAreaTests.FileEntry(path: "dir/delete2.txt", content: "content2"),
            ],
            deletedPaths: ["delete1.txt", "dir/delete2.txt"],
            expectation: .success(expectedFiles: [
                ApplyStagingAreaTests.ExpectedFile(path: "delete1.txt", expectedContent: nil),
                ApplyStagingAreaTests.ExpectedFile(path: "dir/delete2.txt", expectedContent: nil),
            ])
        ),
        ApplyStagingAreaTests.TestCase(
            description: "delete of nonexistent file is skipped",
            deletedPaths: ["nonexistent.txt"],
            expectation: .emptyManifest
        ),
    ]

    private static let mixedOperationCases: [ApplyStagingAreaTests.TestCase] = [
        ApplyStagingAreaTests.TestCase(
            description: "stages and applies mixed operations",
            workspaceFiles: [
                ApplyStagingAreaTests.FileEntry(path: "new.txt", content: "new content"),
                ApplyStagingAreaTests.FileEntry(path: "modify.txt", content: "modified content"),
            ],
            workingDirFiles: [
                ApplyStagingAreaTests.FileEntry(path: "modify.txt", content: "original content"),
                ApplyStagingAreaTests.FileEntry(path: "delete.txt", content: "to delete"),
                ApplyStagingAreaTests.FileEntry(path: "untouched.txt", content: "unchanged"),
            ],
            addedPaths: ["new.txt"],
            modifiedPaths: ["modify.txt"],
            deletedPaths: ["delete.txt"],
            expectation: .success(expectedFiles: [
                ApplyStagingAreaTests.ExpectedFile(path: "new.txt", expectedContent: "new content"),
                ApplyStagingAreaTests.ExpectedFile(path: "modify.txt", expectedContent: "modified content"),
                ApplyStagingAreaTests.ExpectedFile(path: "delete.txt", expectedContent: nil),
                ApplyStagingAreaTests.ExpectedFile(path: "untouched.txt", expectedContent: "unchanged"),
            ])
        ),
    ]

    private static let manifestCountCases: [ApplyStagingAreaTests.TestCase] = [
        ApplyStagingAreaTests.TestCase(
            description: "manifest has correct counts for adds",
            workspaceFiles: [
                ApplyStagingAreaTests.FileEntry(path: "a.txt", content: "a"),
                ApplyStagingAreaTests.FileEntry(path: "b.txt", content: "b"),
            ],
            addedPaths: ["a.txt", "b.txt"],
            expectation: .manifestCounts(add: 2, modify: 0, delete: 0)
        ),
        ApplyStagingAreaTests.TestCase(
            description: "manifest has correct counts for modifies",
            workspaceFiles: [
                ApplyStagingAreaTests.FileEntry(path: "a.txt", content: "mod-a"),
                ApplyStagingAreaTests.FileEntry(path: "b.txt", content: "mod-b"),
                ApplyStagingAreaTests.FileEntry(path: "c.txt", content: "mod-c"),
            ],
            workingDirFiles: [
                ApplyStagingAreaTests.FileEntry(path: "a.txt", content: "orig-a"),
                ApplyStagingAreaTests.FileEntry(path: "b.txt", content: "orig-b"),
                ApplyStagingAreaTests.FileEntry(path: "c.txt", content: "orig-c"),
            ],
            modifiedPaths: ["a.txt", "b.txt", "c.txt"],
            expectation: .manifestCounts(add: 0, modify: 3, delete: 0)
        ),
        ApplyStagingAreaTests.TestCase(
            description: "manifest has correct counts for deletes",
            workingDirFiles: [
                ApplyStagingAreaTests.FileEntry(path: "a.txt", content: "a"),
                ApplyStagingAreaTests.FileEntry(path: "b.txt", content: "b"),
            ],
            deletedPaths: ["a.txt", "b.txt"],
            expectation: .manifestCounts(add: 0, modify: 0, delete: 2)
        ),
        ApplyStagingAreaTests.TestCase(
            description: "manifest has correct mixed counts",
            workspaceFiles: [
                ApplyStagingAreaTests.FileEntry(path: "new1.txt", content: "n1"),
                ApplyStagingAreaTests.FileEntry(path: "new2.txt", content: "n2"),
                ApplyStagingAreaTests.FileEntry(path: "mod1.txt", content: "mod"),
            ],
            workingDirFiles: [
                ApplyStagingAreaTests.FileEntry(path: "mod1.txt", content: "orig"),
                ApplyStagingAreaTests.FileEntry(path: "del1.txt", content: "d1"),
                ApplyStagingAreaTests.FileEntry(path: "del2.txt", content: "d2"),
                ApplyStagingAreaTests.FileEntry(path: "del3.txt", content: "d3"),
            ],
            addedPaths: ["new1.txt", "new2.txt"],
            modifiedPaths: ["mod1.txt"],
            deletedPaths: ["del1.txt", "del2.txt", "del3.txt"],
            expectation: .manifestCounts(add: 2, modify: 1, delete: 3)
        ),
    ]

    private static let cleanupCases: [ApplyStagingAreaTests.TestCase] = [
        ApplyStagingAreaTests.TestCase(
            description: "staging directory is cleaned up after successful apply",
            workspaceFiles: [
                ApplyStagingAreaTests.FileEntry(path: "file.txt", content: "content"),
            ],
            addedPaths: ["file.txt"],
            expectation: .stagingCleanedUp
        ),
        ApplyStagingAreaTests.TestCase(
            description: "staging directory is cleaned up on error",
            expectation: .stagingCleanedUpOnError
        ),
    ]

    private static let edgeCases: [ApplyStagingAreaTests.TestCase] = [
        ApplyStagingAreaTests.TestCase(
            description: "handles file with special characters in name",
            workspaceFiles: [
                ApplyStagingAreaTests.FileEntry(path: "file with spaces.txt", content: "spaces"),
            ],
            addedPaths: ["file with spaces.txt"],
            expectation: .success(expectedFiles: [
                ApplyStagingAreaTests.ExpectedFile(path: "file with spaces.txt", expectedContent: "spaces"),
            ])
        ),
        ApplyStagingAreaTests.TestCase(
            description: "handles deeply nested paths",
            workspaceFiles: [
                ApplyStagingAreaTests.FileEntry(path: "a/b/c/d/e/file.txt", content: "deep"),
            ],
            addedPaths: ["a/b/c/d/e/file.txt"],
            expectation: .success(expectedFiles: [
                ApplyStagingAreaTests.ExpectedFile(path: "a/b/c/d/e/file.txt", expectedContent: "deep"),
            ])
        ),
        ApplyStagingAreaTests.TestCase(
            description: "preserves files not in change summary",
            workspaceFiles: [
                ApplyStagingAreaTests.FileEntry(path: "new.txt", content: "new"),
            ],
            workingDirFiles: [
                ApplyStagingAreaTests.FileEntry(path: "existing.txt", content: "keep me"),
            ],
            addedPaths: ["new.txt"],
            expectation: .success(expectedFiles: [
                ApplyStagingAreaTests.ExpectedFile(path: "new.txt", expectedContent: "new"),
                ApplyStagingAreaTests.ExpectedFile(path: "existing.txt", expectedContent: "keep me"),
            ])
        ),
        ApplyStagingAreaTests.TestCase(
            description: "handles empty file content",
            workspaceFiles: [
                ApplyStagingAreaTests.FileEntry(path: "empty.txt", content: ""),
            ],
            addedPaths: ["empty.txt"],
            expectation: .success(expectedFiles: [
                ApplyStagingAreaTests.ExpectedFile(path: "empty.txt", expectedContent: ""),
            ])
        ),
    ]
}
