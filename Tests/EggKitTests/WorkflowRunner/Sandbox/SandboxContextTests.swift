@testable import EggKit
import FileSystem
import Foundation
import Path
import Testing

struct SandboxContextTests {
    @Test(arguments: TestCase.allCases)
    func sandboxContext(_ testCase: TestCase) async throws {
        let fileSystem = FileSystem()
        let tempDir = try await fileSystem.makeTemporaryDirectory(prefix: "sandbox-test")

        defer {
            Task { try? await fileSystem.remove(tempDir) }
        }

        // Setup working directory if needed
        let workingDir = tempDir.appending(component: "working")
        try await fileSystem.makeDirectory(at: workingDir)

        // Create initial files
        for file in testCase.initialFiles {
            let filePath = workingDir.appending(components: file.path.split(separator: "/").map(String.init))
            let parent = filePath.parentDirectory
            if try await !fileSystem.exists(parent) {
                try await fileSystem.makeDirectory(at: parent)
            }
            try await fileSystem.writeText(file.content, at: filePath)
        }

        // Create sandbox
        let sandbox = try await SandboxContext.create(
            cloning: workingDir,
            fileSystem: fileSystem
        )

        defer {
            Task { await sandbox.discard() }
        }

        switch testCase.expectation {
        case let .success(checks):
            for check in checks {
                switch check {
                case .sandboxExists:
                    let sandboxRoot = await sandbox.root
                    #expect(try await fileSystem.exists(sandboxRoot), "Sandbox root should exist")

                case .originalWorkingDirectoryStored:
                    let originalDir = await sandbox.originalWorkingDirectory
                    #expect(originalDir == workingDir, "Original working directory should match")

                case let .fileCloned(relativePath):
                    let sandboxRoot = await sandbox.root
                    let filePath = sandboxRoot.appending(components: relativePath.split(separator: "/").map(String.init))
                    #expect(try await fileSystem.exists(filePath), "File '\(relativePath)' should be cloned")

                case let .fileContent(relativePath, expectedContent):
                    let sandboxRoot = await sandbox.root
                    let filePath = sandboxRoot.appending(components: relativePath.split(separator: "/").map(String.init))
                    let content = try await fileSystem.readTextFile(at: filePath)
                    #expect(content == expectedContent, "File '\(relativePath)' should have correct content")

                case let .pathValidationSucceeds(relativePath):
                    let sandboxRoot = await sandbox.root
                    let path = sandboxRoot.appending(components: relativePath.split(separator: "/").map(String.init))
                    try await sandbox.validatePath(path)

                case .discardRemovesSandbox:
                    let sandboxRoot = await sandbox.root
                    await sandbox.discard()
                    #expect(try await !fileSystem.exists(sandboxRoot), "Sandbox should be removed after discard")

                case .discardedState(let expected):
                    let discarded = await sandbox.isDiscarded
                    #expect(discarded == expected, "Discarded state should be \(expected)")

                case .discardIsIdempotent:
                    await sandbox.discard()
                    await sandbox.discard()
                    await sandbox.discard()
                    let discarded = await sandbox.isDiscarded
                    #expect(discarded, "Multiple discards should not throw")
                }
            }

        case let .pathValidationFails(absolutePath, expectedErrorPath):
            let path = try AbsolutePath(validating: absolutePath)
            let error = await #expect(throws: SandboxContext.Error.self) {
                try await sandbox.validatePath(path)
            }

            guard case let .escapeAttempt(errorPath) = error else {
                Issue.record("Expected escapeAttempt error but got \(String(describing: error))")
                return
            }
            #expect(errorPath == expectedErrorPath, "Expected error path '\(expectedErrorPath)', got '\(errorPath)'")

        case .pathValidationFailsOutsideSandbox:
            let sandboxRoot = await sandbox.root
            let escapePath = sandboxRoot.parentDirectory.appending(component: "outside")
            let error = await #expect(throws: SandboxContext.Error.self) {
                try await sandbox.validatePath(escapePath)
            }

            guard case .escapeAttempt = error else {
                Issue.record("Expected escapeAttempt error but got \(String(describing: error))")
                return
            }

        case .validationFailsAfterDiscard:
            let sandboxRoot = await sandbox.root
            await sandbox.discard()
            let error = await #expect(throws: SandboxContext.Error.self) {
                try await sandbox.validatePath(sandboxRoot)
            }
            #expect(error == .alreadyDiscarded, "Expected alreadyDiscarded error")

        case .computeChangeSummaryFailsAfterDiscard:
            await sandbox.discard()
            let error = await #expect(throws: SandboxContext.Error.self) {
                _ = try await sandbox.computeChangeSummary()
            }
            #expect(error == .alreadyDiscarded, "Expected alreadyDiscarded error")

        case .applyChangesFailsAfterDiscard:
            await sandbox.discard()
            let error = await #expect(throws: SandboxContext.Error.self) {
                let emptyChanges = ChangeSummary(added: [], modified: [], deleted: [])
                _ = try await sandbox.applyChanges(emptyChanges, force: false)
            }
            #expect(error == .alreadyDiscarded, "Expected alreadyDiscarded error")
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
        ]
    }
}
