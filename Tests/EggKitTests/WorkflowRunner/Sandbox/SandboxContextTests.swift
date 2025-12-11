@testable import EggKit
import FileSystem
import Foundation
import Path
import ProcessRunning
import Testing

struct SandboxContextTests {
    @Test(arguments: TestCase.allCases)
    func sandboxContext(_ testCase: TestCase) async throws {
        let fileSystem = FileSystem()
        let tempDir = try await fileSystem.makeTemporaryDirectory(prefix: "sandbox-test")

        defer {
            Task { try? await fileSystem.remove(tempDir) }
        }

        let workingDir = try await setupWorkingDirectory(
            in: tempDir,
            initialFiles: testCase.initialFiles,
            fileSystem: fileSystem
        )

        let sandbox = try await SandboxContext.create(
            cloning: workingDir,
            fileSystem: fileSystem,
            sandboxWatcher: ScanningDirectoryWatcher(fileSystem: fileSystem),
            workingDirectoryWatcher: ScanningDirectoryWatcher(fileSystem: fileSystem),
            processRunner: ProcessRunner()
        )

        defer {
            Task { await sandbox.discard() }
        }

        switch testCase.expectation {
        case let .success(checks):
            for check in checks {
                try await assertSuccessCheck(check, sandbox: sandbox, workingDir: workingDir, fileSystem: fileSystem)
            }

        case let .pathValidationFails(absolutePath, expectedErrorPath):
            try await assertPathValidationFails(
                absolutePath: absolutePath,
                expectedErrorPath: expectedErrorPath,
                sandbox: sandbox
            )

        case .pathValidationFailsOutsideSandbox:
            await assertPathValidationFailsOutsideSandbox(sandbox: sandbox)

        case .validationFailsAfterDiscard:
            await assertValidationFailsAfterDiscard(sandbox: sandbox)

        case .computeChangeSummaryFailsAfterDiscard:
            await assertComputeChangeSummaryFailsAfterDiscard(sandbox: sandbox)

        case .applyChangesFailsAfterDiscard:
            await assertApplyChangesFailsAfterDiscard(sandbox: sandbox)
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
            case sandboxExists
            case originalWorkingDirectoryStored
            case fileCloned(relativePath: String)
            case fileContent(relativePath: String, expectedContent: String)
            case pathValidationSucceeds(relativePath: String)
            case discardRemovesSandbox
            case discardedState(Bool)
            case discardIsIdempotent
            case changeSummaryIgnoresGitDirectory
        }

        enum Expectation {
            case success(checks: [SuccessCheck])
            case pathValidationFails(absolutePath: String, expectedErrorPath: String)
            case pathValidationFailsOutsideSandbox
            case validationFailsAfterDiscard
            case computeChangeSummaryFailsAfterDiscard
            case applyChangesFailsAfterDiscard
        }

        static let allCases: [TestCase] = [
            // Creation tests
            TestCase(
                description: "creates sandbox from working directory with files",
                initialFiles: [
                    InitialFile(path: "file1.txt", content: "content1"),
                    InitialFile(path: "file2.txt", content: "content2"),
                    InitialFile(path: "subdir/nested.txt", content: "nested"),
                ],
                expectation: .success(checks: [
                    .sandboxExists,
                    .fileCloned(relativePath: "file1.txt"),
                    .fileCloned(relativePath: "file2.txt"),
                    .fileCloned(relativePath: "subdir/nested.txt"),
                    .fileContent(relativePath: "file1.txt", expectedContent: "content1"),
                ])
            ),

            TestCase(
                description: "creates sandbox from empty working directory",
                initialFiles: [],
                expectation: .success(checks: [
                    .sandboxExists,
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
                description: "validates path inside sandbox",
                initialFiles: [],
                expectation: .success(checks: [
                    .pathValidationSucceeds(relativePath: "file.txt"),
                    .pathValidationSucceeds(relativePath: "deep/nested/path"),
                ])
            ),

            TestCase(
                description: "rejects path outside sandbox (absolute path)",
                initialFiles: [],
                expectation: .pathValidationFails(
                    absolutePath: "/etc/passwd",
                    expectedErrorPath: "/etc/passwd"
                )
            ),

            TestCase(
                description: "rejects path escaping via parent directory",
                initialFiles: [],
                expectation: .pathValidationFailsOutsideSandbox
            ),

            TestCase(
                description: "throws alreadyDiscarded when validating after discard",
                initialFiles: [],
                expectation: .validationFailsAfterDiscard
            ),

            // Discard tests
            TestCase(
                description: "discard removes sandbox directory",
                initialFiles: [
                    InitialFile(path: "file.txt", content: "content"),
                ],
                expectation: .success(checks: [
                    .discardRemovesSandbox,
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
        in tempDir: AbsolutePath,
        initialFiles: [InitialFile],
        fileSystem: FileSystem
    ) async throws -> AbsolutePath {
        let workingDir = tempDir.appending(component: "working")
        try await fileSystem.makeDirectory(at: workingDir)

        for file in initialFiles {
            let filePath = workingDir.appending(components: file.path.split(separator: "/").map(String.init))
            let parent = filePath.parentDirectory

            if try await !fileSystem.exists(parent) {
                try await fileSystem.makeDirectory(at: parent)
            }

            try await fileSystem.writeText(file.content, at: filePath)
        }

        return workingDir
    }

    private func assertSuccessCheck(
        _ check: TestCase.SuccessCheck,
        sandbox: SandboxContext,
        workingDir: AbsolutePath,
        fileSystem: FileSystem
    ) async throws {
        switch check {
        case .sandboxExists:
            let sandboxRoot = await sandbox.root
            #expect(try await fileSystem.exists(sandboxRoot), "Sandbox root should exist")

        case .originalWorkingDirectoryStored:
            let originalDir = await sandbox.originalWorkingDirectory
            #expect(originalDir == workingDir, "Original working directory should match")

        case let .fileCloned(relativePath):
            let filePath = await sandbox.root.appending(components: relativePath.split(separator: "/").map(String.init))
            #expect(try await fileSystem.exists(filePath), "File '\(relativePath)' should be cloned")

        case let .fileContent(relativePath, expectedContent):
            let filePath = await sandbox.root.appending(components: relativePath.split(separator: "/").map(String.init))
            let content = try await fileSystem.readTextFile(at: filePath)
            #expect(content == expectedContent, "File '\(relativePath)' should have correct content")

        case let .pathValidationSucceeds(relativePath):
            let path = await sandbox.root.appending(components: relativePath.split(separator: "/").map(String.init))
            try await sandbox.validatePath(path)

        case .discardRemovesSandbox:
            let sandboxRoot = await sandbox.root
            await sandbox.discard()
            #expect(try await !fileSystem.exists(sandboxRoot), "Sandbox should be removed after discard")

        case let .discardedState(expected):
            let discarded = await sandbox.isDiscarded
            #expect(discarded == expected, "Discarded state should be \(expected)")

        case .discardIsIdempotent:
            await sandbox.discard()
            await sandbox.discard()
            await sandbox.discard()
            let discarded = await sandbox.isDiscarded
            #expect(discarded, "Multiple discards should not throw")

        case .changeSummaryIgnoresGitDirectory:
            // Modify files in sandbox: both .git and regular files
            let sandboxRoot = await sandbox.root
            let gitConfigPath = sandboxRoot.appending(components: [".git", "config"])
            let gitNewFilePath = sandboxRoot.appending(components: [".git", "new-file"])
            let readmePath = sandboxRoot.appending(component: "README.md")

            // Modify .git files (remove and rewrite to trigger change)
            try await fileSystem.remove(gitConfigPath)
            try await fileSystem.writeText("modified git config", at: gitConfigPath)

            // Add new file in .git
            try await fileSystem.writeText("new file in git", at: gitNewFilePath)

            // Modify regular file (remove and rewrite)
            try await fileSystem.remove(readmePath)
            try await fileSystem.writeText("modified readme", at: readmePath)

            // Compute change summary
            let summary = try await sandbox.computeChangeSummary()

            // Verify .git paths are not in the summary
            let allPaths = summary.added + summary.modified + summary.deleted
            let gitPaths = allPaths.filter { $0.components.first == ".git" }
            #expect(gitPaths.isEmpty, ".git paths should be ignored in change summary, but found: \(gitPaths)")

            // Verify README.md is in the summary (as modified)
            let hasReadme = summary.modified.contains { $0.pathString == "README.md" }
            #expect(hasReadme, "README.md should be in modified list")
        }
    }

    private func assertPathValidationFails(
        absolutePath: String,
        expectedErrorPath: String,
        sandbox: SandboxContext
    ) async throws {
        let path = try AbsolutePath(validating: absolutePath)
        let error = await #expect(throws: SandboxContext.Error.self) {
            try await sandbox.validatePath(path)
        }

        guard case let .escapeAttempt(errorPath) = error else {
            Issue.record("Expected escapeAttempt error but got \(String(describing: error))")
            return
        }
        #expect(errorPath == expectedErrorPath, "Expected error path '\(expectedErrorPath)', got '\(errorPath)'")
    }

    private func assertPathValidationFailsOutsideSandbox(sandbox: SandboxContext) async {
        let escapePath = await sandbox.root.parentDirectory.appending(component: "outside")
        let error = await #expect(throws: SandboxContext.Error.self) {
            try await sandbox.validatePath(escapePath)
        }

        guard case .escapeAttempt = error else {
            Issue.record("Expected escapeAttempt error but got \(String(describing: error))")
            return
        }
    }

    private func assertValidationFailsAfterDiscard(sandbox: SandboxContext) async {
        let sandboxRoot = await sandbox.root
        await sandbox.discard()
        let error = await #expect(throws: SandboxContext.Error.self) {
            try await sandbox.validatePath(sandboxRoot)
        }
        #expect(error == .alreadyDiscarded, "Expected alreadyDiscarded error")
    }

    private func assertComputeChangeSummaryFailsAfterDiscard(sandbox: SandboxContext) async {
        await sandbox.discard()
        let error = await #expect(throws: SandboxContext.Error.self) {
            _ = try await sandbox.computeChangeSummary()
        }
        #expect(error == .alreadyDiscarded, "Expected alreadyDiscarded error")
    }

    private func assertApplyChangesFailsAfterDiscard(sandbox: SandboxContext) async {
        await sandbox.discard()
        let error = await #expect(throws: SandboxContext.Error.self) {
            let emptyChanges = ChangeSummary(added: [], modified: [], deleted: [])
            _ = try await sandbox.applyChanges(emptyChanges, force: false)
        }
        #expect(error == .alreadyDiscarded, "Expected alreadyDiscarded error")
    }
}
