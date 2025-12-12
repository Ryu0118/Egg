@testable import EggKit
import FileManagerProtocol
import Foundation
import Noora
import ProcessRunning
import Testing

struct StagingContextTests {
    @Test(.serialized, arguments: TestCase.allCases)
    func stagingContext(_ testCase: TestCase) async throws {
        let fileManager: some FileManagerProtocol = FileManager.default
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "workspace-test")

        defer {
            try? fileManager.removeItem(at: tempDir)
        }

        let workingDir = try setupWorkingDirectory(
            in: tempDir,
            initialFiles: testCase.initialFiles,
            fileManager: fileManager
        )

        let staging = try await StagingContext.create(
            cloning: workingDir,
            homeDirectory: tempDir,
            fileManager: fileManager,
            workspaceWatcher: ScanningDirectoryWatcher(fileManager: fileManager),
            workingDirectoryWatcher: ScanningDirectoryWatcher(fileManager: fileManager),
            processRunner: ProcessRunner(),
            requireGitRepository: false,
            noora: NooraMock()
        )

        defer {
            Task { await staging.discard() }
        }

        switch testCase.expectation {
        case let .success(checks):
            for check in checks {
                try await assertSuccessCheck(check, staging: staging, workingDir: workingDir, fileManager: fileManager)
            }

        case let .pathValidationFails(absolutePath, expectedErrorPath):
            try await assertPathValidationFails(
                absolutePath: absolutePath,
                expectedErrorPath: expectedErrorPath,
                staging: staging
            )

        case .pathValidationFailsOutsideWorkspace:
            await assertPathValidationFailsOutsideWorkspace(staging: staging)

        case .validationFailsAfterDiscard:
            await assertValidationFailsAfterDiscard(staging: staging)

        case .computeChangeSummaryFailsAfterDiscard:
            await assertComputeChangeSummaryFailsAfterDiscard(staging: staging)

        case .applyChangesFailsAfterDiscard:
            await assertApplyChangesFailsAfterDiscard(staging: staging)
        }
    }

    struct InitialFile {
        let path: String
        let content: String
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let initialFiles: [InitialFile]
        let expectation: Expectation

        var testDescription: String { description }

        enum SuccessCheck {
            case workspaceExists
            case originalWorkingDirectoryStored
            case fileCloned(relativePath: String)
            case fileContent(relativePath: String, expectedContent: String)
            case pathValidationSucceeds(relativePath: String)
            case discardRemovesWorkspace
            case discardedState(Bool)
            case discardIsIdempotent
            case changeSummaryIgnoresGitDirectory
        }

        enum Expectation {
            case success(checks: [SuccessCheck])
            case pathValidationFails(absolutePath: String, expectedErrorPath: String)
            case pathValidationFailsOutsideWorkspace
            case validationFailsAfterDiscard
            case computeChangeSummaryFailsAfterDiscard
            case applyChangesFailsAfterDiscard
        }

        static let allCases: [TestCase] = [
            // Creation tests
            TestCase(
                description: "creates staging area from working directory with files",
                initialFiles: [
                    InitialFile(path: "file1.txt", content: "content1"),
                    InitialFile(path: "file2.txt", content: "content2"),
                    InitialFile(path: "subdir/nested.txt", content: "nested"),
                ],
                expectation: .success(checks: [
                    .workspaceExists,
                    .fileCloned(relativePath: "file1.txt"),
                    .fileCloned(relativePath: "file2.txt"),
                    .fileCloned(relativePath: "subdir/nested.txt"),
                    .fileContent(relativePath: "file1.txt", expectedContent: "content1"),
                ])
            ),

            TestCase(
                description: "creates staging area from empty working directory",
                initialFiles: [],
                expectation: .success(checks: [
                    .workspaceExists,
                ])
            ),

            TestCase(
                description: "stores original working directory reference",
                initialFiles: [],
                expectation: .success(checks: [
                    .originalWorkingDirectoryStored,
                ])
            ),

            // Path validation tests
            TestCase(
                description: "validates path inside staging area",
                initialFiles: [],
                expectation: .success(checks: [
                    .pathValidationSucceeds(relativePath: "file.txt"),
                    .pathValidationSucceeds(relativePath: "deep/nested/path"),
                ])
            ),

            TestCase(
                description: "rejects path outside staging area (absolute path)",
                initialFiles: [],
                expectation: .pathValidationFails(
                    absolutePath: "/etc/passwd",
                    expectedErrorPath: "/etc/passwd"
                )
            ),

            TestCase(
                description: "rejects path escaping via parent directory",
                initialFiles: [],
                expectation: .pathValidationFailsOutsideWorkspace
            ),

            TestCase(
                description: "throws alreadyDiscarded when validating after discard",
                initialFiles: [],
                expectation: .validationFailsAfterDiscard
            ),

            // Discard tests
            TestCase(
                description: "discard removes staging area directory",
                initialFiles: [
                    InitialFile(path: "file.txt", content: "content"),
                ],
                expectation: .success(checks: [
                    .discardRemovesWorkspace,
                ])
            ),

            TestCase(
                description: "discard is idempotent",
                initialFiles: [],
                expectation: .success(checks: [
                    .discardIsIdempotent,
                ])
            ),

            TestCase(
                description: "discarded property reflects state",
                initialFiles: [],
                expectation: .success(checks: [
                    .discardedState(false),
                ])
            ),

            // computeChangeSummary and applyChanges guard tests
            TestCase(
                description: "computeChangeSummary throws after discard",
                initialFiles: [],
                expectation: .computeChangeSummaryFailsAfterDiscard
            ),

            TestCase(
                description: "applyChanges throws after discard",
                initialFiles: [],
                expectation: .applyChangesFailsAfterDiscard
            ),

            // .git directory ignore test
            TestCase(
                description: "computeChangeSummary ignores .git directory changes",
                initialFiles: [
                    InitialFile(path: ".git/config", content: "git config"),
                    InitialFile(path: ".git/objects/abc", content: "object"),
                    InitialFile(path: "README.md", content: "readme"),
                ],
                expectation: .success(checks: [
                    .changeSummaryIgnoresGitDirectory,
                ])
            ),
        ]
    }

    private func setupWorkingDirectory(
        in tempDir: URL,
        initialFiles: [InitialFile],
        fileManager: some FileManagerProtocol
    ) throws -> URL {
        let workingDir = tempDir.appending(path: "working")
        try fileManager.createDirectory(at: workingDir, withIntermediateDirectories: true)

        try initializeGitRepository(at: workingDir)

        for file in initialFiles {
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

        return workingDir
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

    private func assertSuccessCheck(
        _ check: TestCase.SuccessCheck,
        staging: StagingContext,
        workingDir: URL,
        fileManager: some FileManagerProtocol
    ) async throws {
        switch check {
        case .workspaceExists:
            let workspaceRoot = await staging.root
            #expect(fileManager.exists(workspaceRoot), "Staging area root should exist")

        case .originalWorkingDirectoryStored:
            let originalDir = await staging.originalWorkingDirectory
            #expect(originalDir == workingDir, "Original working directory should match")

        case let .fileCloned(relativePath):
            let components = relativePath.split(separator: "/").map(String.init)
            var filePath = await staging.root
            for component in components {
                filePath = filePath.appending(path: component)
            }
            #expect(fileManager.exists(filePath), "File '\(relativePath)' should be cloned")

        case let .fileContent(relativePath, expectedContent):
            let components = relativePath.split(separator: "/").map(String.init)
            var filePath = await staging.root
            for component in components {
                filePath = filePath.appending(path: component)
            }
            let data = try fileManager.readFile(at: filePath)
            let content = String(data: data, encoding: .utf8)
            #expect(content == expectedContent, "File '\(relativePath)' should have correct content")

        case let .pathValidationSucceeds(relativePath):
            let components = relativePath.split(separator: "/").map(String.init)
            var path = await staging.root
            for component in components {
                path = path.appending(path: component)
            }
            try await staging.validatePath(path)

        case .discardRemovesWorkspace:
            let workspaceRoot = await staging.root
            await staging.discard()
            #expect(!fileManager.exists(workspaceRoot), "Staging area should be removed after discard")

        case let .discardedState(expected):
            let discarded = await staging.isDiscarded
            #expect(discarded == expected, "Discarded state should be \(expected)")

        case .discardIsIdempotent:
            await staging.discard()
            await staging.discard()
            await staging.discard()
            let discarded = await staging.isDiscarded
            #expect(discarded, "Multiple discards should not throw")

        case .changeSummaryIgnoresGitDirectory:
            // Modify files in staging area: both .git and regular files
            let workspaceRoot = await staging.root
            let gitConfigPath = workspaceRoot.appending(path: ".git").appending(path: "config")
            let gitNewFilePath = workspaceRoot.appending(path: ".git").appending(path: "new-file")
            let readmePath = workspaceRoot.appending(path: "README.md")

            // Modify .git files (remove and rewrite to trigger change)
            try fileManager.removeItem(at: gitConfigPath)
            try fileManager.writeText("modified git config", at: gitConfigPath, encoding: .utf8)

            // Add new file in .git
            try fileManager.writeText("new file in git", at: gitNewFilePath, encoding: .utf8)

            // Modify regular file (remove and rewrite)
            try fileManager.removeItem(at: readmePath)
            try fileManager.writeText("modified readme", at: readmePath, encoding: .utf8)

            // Compute change summary
            let summary = try await staging.computeChangeSummary()

            // Verify .git paths are not in the summary
            let allPaths = summary.added + summary.modified + summary.deleted
            let gitPaths = allPaths.filter { $0.hasPrefix(".git/") || $0 == ".git" }
            #expect(gitPaths.isEmpty, ".git paths should be ignored in change summary, but found: \(gitPaths)")

            // Verify README.md is in the summary (as modified)
            let hasReadme = summary.modified.contains { $0 == "README.md" }
            #expect(hasReadme, "README.md should be in modified list")
        }
    }

    private func assertPathValidationFails(
        absolutePath: String,
        expectedErrorPath: String,
        staging: StagingContext
    ) async throws {
        let path = URL(filePath: absolutePath)
        let error = await #expect(throws: StagingContext.Error.self) {
            try await staging.validatePath(path)
        }

        guard case let .escapeAttempt(errorPath) = error else {
            Issue.record("Expected escapeAttempt error but got \(String(describing: error))")
            return
        }
        #expect(errorPath == expectedErrorPath, "Expected error path '\(expectedErrorPath)', got '\(errorPath)'")
    }

    private func assertPathValidationFailsOutsideWorkspace(staging: StagingContext) async {
        let escapePath = await staging.root.deletingLastPathComponent().appending(path: "outside")
        let error = await #expect(throws: StagingContext.Error.self) {
            try await staging.validatePath(escapePath)
        }

        guard case .escapeAttempt = error else {
            Issue.record("Expected escapeAttempt error but got \(String(describing: error))")
            return
        }
    }

    private func assertValidationFailsAfterDiscard(staging: StagingContext) async {
        let workspaceRoot = await staging.root
        await staging.discard()
        let error = await #expect(throws: StagingContext.Error.self) {
            try await staging.validatePath(workspaceRoot)
        }
        #expect(error == .alreadyDiscarded, "Expected alreadyDiscarded error")
    }

    private func assertComputeChangeSummaryFailsAfterDiscard(staging: StagingContext) async {
        await staging.discard()
        let error = await #expect(throws: StagingContext.Error.self) {
            _ = try await staging.computeChangeSummary()
        }
        #expect(error == .alreadyDiscarded, "Expected alreadyDiscarded error")
    }

    private func assertApplyChangesFailsAfterDiscard(staging: StagingContext) async {
        await staging.discard()
        let error = await #expect(throws: StagingContext.Error.self) {
            let emptyChanges = ChangeSummary(added: [], modified: [], deleted: [])
            _ = try await staging.applyChanges(emptyChanges, override: false)
        }
        #expect(error == .alreadyDiscarded, "Expected alreadyDiscarded error")
    }
}
