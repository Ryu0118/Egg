@testable import EggKit
import FileManagerProtocol
import Foundation
import Testing

struct DirectoryCloningTests {
    @Test(arguments: TestCase.allCases)
    func clone(_ testCase: TestCase) async throws {
        let fileManager: any FileManagerProtocol = FileManager.default
        let tempDirURL = try fileManager.makeTemporaryDirectory(prefix: "DirectoryCloningTests")
        let tempDir = URL(filePath: tempDirURL.path(percentEncoded: false))

        let sourceDir = tempDir.appending(path: "source")
        let destDir = tempDir.appending(path: "dest")

        try setupSource(testCase.sourceSetup, in: sourceDir, using: fileManager)

        let cloner = APFSDirectoryCloner()

        switch testCase.expectation {
        case let .success(verifications):
            try await cloner.clone(
                from: sourceDir,
                to: destDir
            )
            try verify(verifications, in: destDir, using: fileManager)

        case let .failure(expectedError):
            await #expect(throws: expectedError) {
                try await cloner.clone(
                    from: sourceDir,
                    to: destDir
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

    @Test
    func cloneFailsWhenDestinationExists() async throws {
        let fileManager: any FileManagerProtocol = FileManager.default
        let tempDirURL = try fileManager.makeTemporaryDirectory(prefix: "DirectoryCloningTests")
        let tempDir = URL(filePath: tempDirURL.path(percentEncoded: false))

        let sourceDir = tempDir.appending(path: "source")
        let destDir = tempDir.appending(path: "dest")

        try fileManager.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try fileManager.writeText("source content", at: sourceDir.appending(path: "file.txt"), encoding: .utf8)

        try fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)
        try fileManager.writeText("dest content", at: destDir.appending(path: "existing.txt"), encoding: .utf8)

        let cloner = APFSDirectoryCloner()

        await #expect(throws: CloningError.self) {
            try await cloner.clone(
                from: sourceDir,
                to: destDir
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
        in directory: URL,
        using fileManager: some FileManagerProtocol
    ) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        for item in items {
            try createItem(item, in: directory, using: fileManager)
        }
    }

    private func createItem(
        _ item: TestCase.Setup,
        in baseDir: URL,
        using fileManager: some FileManagerProtocol
    ) throws {
        switch item {
        case let .file(path, content):
            var fullPath = baseDir
            for component in path.split(separator: "/").map(String.init) {
                fullPath = fullPath.appending(path: component)
            }
            try createParentDirectoryIfNeeded(for: fullPath, using: fileManager)
            try fileManager.writeText(content, at: fullPath, encoding: .utf8)

        case let .directory(path):
            var fullPath = baseDir
            for component in path.split(separator: "/").map(String.init) {
                fullPath = fullPath.appending(path: component)
            }
            try fileManager.createDirectory(at: fullPath, withIntermediateDirectories: true)

        case let .symlink(path, target):
            var fullPath = baseDir
            for component in path.split(separator: "/").map(String.init) {
                fullPath = fullPath.appending(path: component)
            }
            try createParentDirectoryIfNeeded(for: fullPath, using: fileManager)
            try FileManager.default.createSymbolicLink(
                atPath: fullPath.path(percentEncoded: false),
                withDestinationPath: target
            )
        }
    }

    private func createParentDirectoryIfNeeded(
        for path: URL,
        using fileManager: some FileManagerProtocol
    ) throws {
        let parent = path.deletingLastPathComponent()
        if !fileManager.exists(parent) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
    }
}

extension DirectoryCloningTests {
    private func verify(
        _ verifications: [TestCase.Verification],
        in directory: URL,
        using fileManager: some FileManagerProtocol
    ) throws {
        for verification in verifications {
            try verifyItem(verification, in: directory, using: fileManager)
        }
    }

    private func verifyItem(
        _ verification: TestCase.Verification,
        in baseDir: URL,
        using fileManager: some FileManagerProtocol
    ) throws {
        switch verification {
        case let .fileExists(path):
            let fullPath = resolvePath(path, in: baseDir)
            let exists = fileManager.exists(fullPath)
            #expect(exists, "Expected file to exist at \(path)")

        case let .fileContent(path, expected):
            let fullPath = resolvePath(path, in: baseDir)
            let data = try fileManager.readFile(at: fullPath)
            let actual = String(data: data, encoding: .utf8)
            #expect(actual == expected, "Expected content '\(expected)' at \(path), got '\(actual ?? "nil")'")

        case let .directoryExists(path):
            let fullPath = resolvePath(path, in: baseDir)
            let exists = fileManager.exists(fullPath)
            let isDir = exists ? fileManager.isDirectory(at: fullPath) : false
            #expect(exists && isDir, "Expected directory to exist at \(path)")

        case let .symlinkExists(path, expectedTarget):
            let fullPath = resolvePath(path, in: baseDir)
            let pathString = fullPath.path(percentEncoded: false)
            var isSymlink = false
            if let attrs = try? FileManager.default.attributesOfItem(atPath: pathString),
               let fileType = attrs[.type] as? FileAttributeType
            {
                isSymlink = fileType == .typeSymbolicLink
            }
            #expect(isSymlink, "Expected symlink at \(path), but it's not a symlink")

            if isSymlink {
                let actualTarget = try? FileManager.default.destinationOfSymbolicLink(atPath: pathString)
                #expect(actualTarget == expectedTarget, "Expected symlink target '\(expectedTarget)' at \(path), got '\(actualTarget ?? "nil")'")
            }
        }
    }

    private func resolvePath(_ relativePath: String, in baseDir: URL) -> URL {
        if relativePath == "." {
            return baseDir
        }
        var fullPath = baseDir
        for component in relativePath.split(separator: "/").map(String.init) {
            fullPath = fullPath.appending(path: component)
        }
        return fullPath
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
            case symlink(path: String, target: String)
        }

        enum Verification: Sendable {
            case fileExists(path: String)
            case fileContent(path: String, expected: String)
            case directoryExists(path: String)
            case symlinkExists(path: String, target: String)
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

            TestCase(
                description: "preserves symbolic links",
                sourceSetup: [
                    .file(path: "target.txt", content: "target content"),
                    .symlink(path: "link.txt", target: "target.txt"),
                ],
                expectation: .success(verifications: [
                    .fileContent(path: "target.txt", expected: "target content"),
                    .symlinkExists(path: "link.txt", target: "target.txt"),
                ])
            ),

            TestCase(
                description: "preserves symbolic links in nested directories",
                sourceSetup: [
                    .file(path: "dir/target.txt", content: "nested target"),
                    .symlink(path: "dir/link.txt", target: "target.txt"),
                ],
                expectation: .success(verifications: [
                    .fileContent(path: "dir/target.txt", expected: "nested target"),
                    .symlinkExists(path: "dir/link.txt", target: "target.txt"),
                ])
            ),
        ]
    }

    enum TestError: Error {
        case temporaryDirectoryNotAvailable
    }
}
