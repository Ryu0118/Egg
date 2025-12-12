@testable import EggKit
import FileManagerProtocol
import Foundation
import Path
import Testing

struct DirectoryCloningTests {
    @Test(.inTemporaryDirectory, arguments: TestCase.allCases)
    func clone(_ testCase: TestCase) async throws {
        let fileSystem = FileManager.default
        let tempDirURL = try fileSystem.makeTemporaryDirectory(prefix: "DirectoryCloningTests")
        let tempDir = try AbsolutePath(validating: tempDirURL.path)

        let sourceDir = tempDir.appending(component: "source")
        let destDir = tempDir.appending(component: "dest")

        try await setupSource(testCase.sourceSetup, in: sourceDir, using: fileSystem)

        let cloner = APFSDirectoryCloner()

        switch testCase.expectation {
        case let .success(verifications):
            try await cloner.clone(
                from: URL(filePath: sourceDir.pathString),
                to: URL(filePath: destDir.pathString)
            )
            try await verify(verifications, in: destDir, using: fileSystem)

        case let .failure(expectedError):
            await #expect(throws: expectedError) {
                try await cloner.clone(
                    from: URL(filePath: sourceDir.pathString),
                    to: URL(filePath: destDir.pathString)
                )
            }
        }
    }

    @Test
    func cloneFailsWithNonFileURL() async throws {
        let cloner = APFSDirectoryCloner()
        let httpURL = URL(string: "https://example.com")!
        let fileURL = URL(filePath: "/tmp/test")

        await #expect(throws: CloningError.invalidURL) {
            try await cloner.clone(from: httpURL, to: fileURL)
        }

        await #expect(throws: CloningError.invalidURL) {
            try await cloner.clone(from: fileURL, to: httpURL)
        }
    }

    @Test(.inTemporaryDirectory)
    func cloneFailsWhenDestinationExists() async throws {
        let fileSystem = FileManager.default
        let tempDirURL = try fileSystem.makeTemporaryDirectory(prefix: "DirectoryCloningTests")
        let tempDir = try AbsolutePath(validating: tempDirURL.path)

        let sourceDir = tempDir.appending(component: "source")
        let destDir = tempDir.appending(component: "dest")

        let sourceDirURL = URL(filePath: sourceDir.pathString)
        let destDirURL = URL(filePath: destDir.pathString)

        try await fileSystem.createDirectory(at: sourceDirURL, withIntermediateDirectories: true)
        try await fileSystem.writeText("source content", at: URL(filePath: sourceDir.appending(component: "file.txt").pathString))

        try await fileSystem.createDirectory(at: destDirURL, withIntermediateDirectories: true)
        try await fileSystem.writeText("dest content", at: URL(filePath: destDir.appending(component: "existing.txt").pathString))

        let cloner = APFSDirectoryCloner()

        await #expect(throws: CloningError.self) {
            try await cloner.clone(
                from: URL(filePath: sourceDir.pathString),
                to: URL(filePath: destDir.pathString)
            )
        }
    }

    @Test
    func cloningErrorDescriptions() {
        let invalidURLError = CloningError.invalidURL
        #expect(invalidURLError.errorDescription == "The provided URL is not a valid file URL")

        let systemError = CloningError.systemError(code: 17, message: "File exists")
        #expect(systemError.errorDescription == "Cloning failed with error code 17: File exists")
    }
}

extension DirectoryCloningTests {
    private func setupSource(
        _ items: [TestCase.Setup],
        in directory: AbsolutePath,
        using fileSystem: FileManagerProtocol
    ) async throws {
        let directoryURL = URL(filePath: directory.pathString)
        try await fileSystem.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        for item in items {
            try await createItem(item, in: directory, using: fileSystem)
        }
    }

    private func createItem(
        _ item: TestCase.Setup,
        in baseDir: AbsolutePath,
        using fileSystem: FileManagerProtocol
    ) async throws {
        switch item {
        case let .file(path, content):
            let fullPath = baseDir.appending(components: path.split(separator: "/").map(String.init))
            try await createParentDirectoryIfNeeded(for: fullPath, using: fileSystem)
            let fileURL = URL(filePath: fullPath.pathString)
            try await fileSystem.writeText(content, at: fileURL)

        case let .directory(path):
            let fullPath = baseDir.appending(components: path.split(separator: "/").map(String.init))
            let directoryURL = URL(filePath: fullPath.pathString)
            try await fileSystem.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    private func createParentDirectoryIfNeeded(
        for path: AbsolutePath,
        using fileSystem: FileManagerProtocol
    ) async throws {
        let parent = path.parentDirectory
        if try !(await fileSystem.exists(parent)) {
            let parentURL = URL(filePath: parent.pathString)
            try await fileSystem.createDirectory(at: parentURL, withIntermediateDirectories: true)
        }
    }
}

extension DirectoryCloningTests {
    private func verify(
        _ verifications: [TestCase.Verification],
        in directory: AbsolutePath,
        using fileSystem: FileManagerProtocol
    ) async throws {
        for verification in verifications {
            try await verifyItem(verification, in: directory, using: fileSystem)
        }
    }

    private func verifyItem(
        _ verification: TestCase.Verification,
        in baseDir: AbsolutePath,
        using fileSystem: FileManagerProtocol
    ) async throws {
        switch verification {
        case let .fileExists(path):
            let fullPath = resolvePath(path, in: baseDir)
            let exists = try await fileSystem.exists(fullPath)
            #expect(exists, "Expected file to exist at \(path)")

        case let .fileContent(path, expected):
            let fullPath = resolvePath(path, in: baseDir)
            let data = try await fileSystem.readFile(at: fullPath)
            let actual = String(data: data, encoding: .utf8)
            #expect(actual == expected, "Expected content '\(expected)' at \(path), got '\(actual ?? "nil")'")

        case let .directoryExists(path):
            let fullPath = resolvePath(path, in: baseDir)
            let fullPathURL = URL(filePath: fullPath.pathString)
            let exists = try await fileSystem.exists(fullPath)
            let isDir = exists ? try await fileSystem.isDirectory(at: fullPathURL) : false
            #expect(exists && isDir, "Expected directory to exist at \(path)")
        }
    }

    private func resolvePath(_ relativePath: String, in baseDir: AbsolutePath) -> AbsolutePath {
        if relativePath == "." {
            return baseDir
        }
        return baseDir.appending(components: relativePath.split(separator: "/").map(String.init))
    }
}

extension DirectoryCloningTests {
    struct TestCase: CustomTestStringConvertible, Sendable {
        let description: String
        let sourceSetup: [Setup]
        let expectation: Expectation

        var testDescription: String { description }

        enum Setup: Sendable {
            case file(path: String, content: String)
            case directory(path: String)
        }

        enum Verification: Sendable {
            case fileExists(path: String)
            case fileContent(path: String, expected: String)
            case directoryExists(path: String)
        }

        enum Expectation: Sendable {
            case success(verifications: [Verification])
            case failure(CloningError)
        }

        static let allCases: [TestCase] = [
            TestCase(
                description: "clones single file",
                sourceSetup: [
                    .file(path: "file.txt", content: "hello"),
                ],
                expectation: .success(verifications: [
                    .fileExists(path: "file.txt"),
                    .fileContent(path: "file.txt", expected: "hello"),
                ])
            ),

            TestCase(
                description: "clones directory with multiple files",
                sourceSetup: [
                    .file(path: "a.txt", content: "content a"),
                    .file(path: "b.txt", content: "content b"),
                    .file(path: "c.txt", content: "content c"),
                ],
                expectation: .success(verifications: [
                    .fileContent(path: "a.txt", expected: "content a"),
                    .fileContent(path: "b.txt", expected: "content b"),
                    .fileContent(path: "c.txt", expected: "content c"),
                ])
            ),

            TestCase(
                description: "clones nested directory structure",
                sourceSetup: [
                    .file(path: "dir/subdir/file.txt", content: "nested content"),
                    .file(path: "dir/another.txt", content: "another"),
                ],
                expectation: .success(verifications: [
                    .directoryExists(path: "dir"),
                    .directoryExists(path: "dir/subdir"),
                    .fileContent(path: "dir/subdir/file.txt", expected: "nested content"),
                    .fileContent(path: "dir/another.txt", expected: "another"),
                ])
            ),

            TestCase(
                description: "clones empty directory",
                sourceSetup: [
                    .directory(path: "empty"),
                ],
                expectation: .success(verifications: [
                    .directoryExists(path: "empty"),
                ])
            ),

            TestCase(
                description: "clones deeply nested structure",
                sourceSetup: [
                    .file(path: "a/b/c/d/e/deep.txt", content: "deep"),
                ],
                expectation: .success(verifications: [
                    .directoryExists(path: "a/b/c/d/e"),
                    .fileContent(path: "a/b/c/d/e/deep.txt", expected: "deep"),
                ])
            ),

            TestCase(
                description: "clones mixed structure with files and directories",
                sourceSetup: [
                    .file(path: "root.txt", content: "root"),
                    .directory(path: "empty_dir"),
                    .file(path: "subdir/file.txt", content: "subdir file"),
                ],
                expectation: .success(verifications: [
                    .fileContent(path: "root.txt", expected: "root"),
                    .directoryExists(path: "empty_dir"),
                    .fileContent(path: "subdir/file.txt", expected: "subdir file"),
                ])
            ),
        ]
    }

    enum TestError: Error {
        case temporaryDirectoryNotAvailable
    }
}
