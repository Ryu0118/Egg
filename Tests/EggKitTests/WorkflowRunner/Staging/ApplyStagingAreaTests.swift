@testable import EggKit
import FileManagerProtocol
import Foundation
import Testing

struct ApplyStagingAreaTests {
    @Test(arguments: TestCase.allCases)
    func applyStagingArea(_ testCase: TestCase) throws {
        let context = try TestContext.setUp(testCase: testCase)
        defer { try? context.tearDown() }

        switch testCase.expectation {
        case let .success(expectedFiles):
            try context.executeStageAndApply()
            try context.verifyExpectedFiles(expectedFiles)

        case .emptyManifest:
            try context.verifyEmptyManifest()

        case let .manifestCounts(add, modify, delete):
            try context.verifyManifestCounts(add: add, modify: modify, delete: delete)

        case .stagingCleanedUp:
            let stagingRoot = try context.executeStageAndApplyReturningRoot()
            try context.verifyStagingCleanedUp(stagingRoot: stagingRoot)

        case .stagingCleanedUpOnError:
            let stagingRoot = try context.executeStagingWithError()
            try context.verifyStagingCleanedUp(stagingRoot: stagingRoot)
        }
    }
}

extension ApplyStagingAreaTests {
    struct TestContext {
        let fileManager: any FileManagerProtocol
        let tempDir: URL
        let workspaceRoot: URL
        let workingDir: URL
        let changes: ChangeSummary

        static func setUp(testCase: TestCase) throws -> TestContext {
            let fileManager = FileManager.default as any FileManagerProtocol
            let tempDir = try fileManager.makeTemporaryDirectory(prefix: "staging-test")

            let workspaceRoot = tempDir.appending(path: "workspace")
            let workingDir = tempDir.appending(path: "working")

            try fileManager.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: workingDir, withIntermediateDirectories: true)

            try createFiles(testCase.workspaceFiles, in: workspaceRoot, fileManager: fileManager)
            try createFiles(testCase.workingDirFiles, in: workingDir, fileManager: fileManager)

            let changes = buildChangeSummary(testCase: testCase)

            return TestContext(
                fileManager: fileManager,
                tempDir: tempDir,
                workspaceRoot: workspaceRoot,
                workingDir: workingDir,
                changes: changes
            )
        }

        func tearDown() throws {
            try fileManager.removeItem(at: tempDir)
        }

        func executeStageAndApply() throws {
            try ApplyStagingArea.withStaging(
                workspaceRoot: workspaceRoot,
                workingDirectory: workingDir,
                fileManager: fileManager
            ) { staging, fs in
                let manifest = try staging.stage(changes: changes, fileManager: fs)
                try staging.apply(manifest: manifest, fileManager: fs)
            }
        }

        func executeStageAndApplyReturningRoot() throws -> URL {
            let staging = try ApplyStagingArea.create(
                workspaceRoot: workspaceRoot,
                workingDirectory: workingDir,
                fileManager: fileManager
            )
            let root = staging.root

            do {
                let manifest = try staging.stage(changes: changes, fileManager: fileManager)
                try staging.apply(manifest: manifest, fileManager: fileManager)
                staging.cleanup(fileManager: fileManager)
            } catch {
                staging.cleanup(fileManager: fileManager)
                throw error
            }

            return root
        }

        func executeStagingWithError() throws -> URL {
            let staging = try ApplyStagingArea.create(
                workspaceRoot: workspaceRoot,
                workingDirectory: workingDir,
                fileManager: fileManager
            )
            let root = staging.root

            do {
                let badChanges = ChangeSummary(
                    added: ["nonexistent.txt"],
                    modified: [],
                    deleted: []
                )
                _ = try staging.stage(changes: badChanges, fileManager: fileManager)
                staging.cleanup(fileManager: fileManager)
            } catch {
                staging.cleanup(fileManager: fileManager)
            }

            return root
        }

        func verifyExpectedFiles(_ expectedFiles: [ExpectedFile]) throws {
            for expectedFile in expectedFiles {
                let filePath = workingDir.appending(
                    path: expectedFile.path
                )

                if let expectedContent = expectedFile.expectedContent {
                    #expect(
                        fileManager.exists(filePath),
                        "File '\(expectedFile.path)' should exist"
                    )
                    let data = try fileManager.readFile(at: filePath)
                    let content = String(data: data, encoding: .utf8) ?? ""
                    #expect(
                        content == expectedContent,
                        "File '\(expectedFile.path)' content mismatch: expected '\(expectedContent)', got '\(content)'"
                    )
                } else {
                    #expect(
                        !fileManager.exists(filePath),
                        "File '\(expectedFile.path)' should not exist"
                    )
                }
            }
        }

        func verifyEmptyManifest() throws {
            try ApplyStagingArea.withStaging(
                workspaceRoot: workspaceRoot,
                workingDirectory: workingDir,
                fileManager: fileManager
            ) { staging, fs in
                let manifest = try staging.stage(changes: changes, fileManager: fs)
                #expect(manifest.totalCount == 0, "Expected empty manifest")
            }
        }

        func verifyManifestCounts(add: Int, modify: Int, delete: Int) throws {
            try ApplyStagingArea.withStaging(
                workspaceRoot: workspaceRoot,
                workingDirectory: workingDir,
                fileManager: fileManager
            ) { staging, fs in
                let manifest = try staging.stage(changes: changes, fileManager: fs)
                #expect(manifest.addCount == add, "Expected \(add) adds, got \(manifest.addCount)")
                #expect(manifest.modifyCount == modify, "Expected \(modify) modifies, got \(manifest.modifyCount)")
                #expect(manifest.deleteCount == delete, "Expected \(delete) deletes, got \(manifest.deleteCount)")
            }
        }

        func verifyStagingCleanedUp(stagingRoot: URL) throws {
            #expect(
                !fileManager.exists(stagingRoot),
                "Staging directory should be cleaned up"
            )
        }

        private static func createFiles(
            _ files: [FileEntry],
            in directory: URL,
            fileManager: any FileManagerProtocol
        ) throws {
            for file in files {
                let filePath = directory.appending(path: file.path)
                let parent = filePath.deletingLastPathComponent()
                if !fileManager.exists(parent) {
                    try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
                }
                try fileManager.writeText(file.content, at: filePath, encoding: .utf8)
            }
        }

        private static func buildChangeSummary(testCase: TestCase) -> ChangeSummary {
            return ChangeSummary(
                added: testCase.addedPaths,
                modified: testCase.modifiedPaths,
                deleted: testCase.deletedPaths
            )
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
