@testable import EggKit
import FileSystem
import Foundation
import Path
import Testing

struct FileSystemAtomicTests {
    @Test(arguments: TestCase.allCases)
    func withAtomicCopyAndWrite(_ testCase: TestCase) async throws {
        let fileSystem = FileSystem()
        let tempBase = try await fileSystem.makeTemporaryDirectory(prefix: "atomic-test")

        defer {
            Task { try? await fileSystem.remove(tempBase) }
        }

        let sourceDir = tempBase.appending(component: "source")
        let destDir = tempBase.appending(component: "dest")

        try await setupSource(testCase.sourceSetup, in: sourceDir, using: fileSystem)
        try await setupDestination(testCase.destSetup, in: destDir, using: fileSystem)

        switch testCase.expectation {
        case let .success(verifications):
            try await executeAtomicCopy(
                from: sourceDir,
                to: destDir,
                transform: testCase.transform,
                using: fileSystem
            )
            try await verify(verifications, in: destDir, using: fileSystem)

        case .failure:
            await expectFailure {
                try await self.executeAtomicCopy(
                    from: sourceDir,
                    to: destDir,
                    transform: testCase.transform,
                    using: fileSystem
                )
            }
            try await verifyDestinationUnchanged(testCase.destSetup, in: destDir, using: fileSystem)
        }
    }
}

extension FileSystemAtomicTests {
    private func setupSource(
        _ items: [TestCase.Setup],
        in directory: AbsolutePath,
        using fileSystem: FileSystem
    ) async throws {
        try await fileSystem.makeDirectory(at: directory)
        for item in items {
            try await createItem(item, in: directory, using: fileSystem)
        }
    }

    private func setupDestination(
        _ items: [TestCase.Setup],
        in directory: AbsolutePath,
        using fileSystem: FileSystem
    ) async throws {
        guard !items.isEmpty else { return }
        try await fileSystem.makeDirectory(at: directory)
        for item in items {
            try await createItem(item, in: directory, using: fileSystem)
        }
    }

    private func createItem(
        _ item: TestCase.Setup,
        in baseDir: AbsolutePath,
        using fileSystem: FileSystem
    ) async throws {
        switch item {
        case let .file(path, content):
            let fullPath = baseDir.appending(components: path.split(separator: "/").map(String.init))
            try await createParentDirectoryIfNeeded(for: fullPath, using: fileSystem)
            try await fileSystem.writeText(content, at: fullPath)

        case let .directory(path):
            let fullPath = baseDir.appending(components: path.split(separator: "/").map(String.init))
            try await fileSystem.makeDirectory(at: fullPath, options: [.createTargetParentDirectories])
        }
    }

    private func createParentDirectoryIfNeeded(
        for path: AbsolutePath,
        using fileSystem: FileSystem
    ) async throws {
        let parent = path.parentDirectory
        if !(try await fileSystem.exists(parent)) {
            try await fileSystem.makeDirectory(at: parent, options: [.createTargetParentDirectories])
        }
    }
}

extension FileSystemAtomicTests {
    private func executeAtomicCopy(
        from source: AbsolutePath,
        to destination: AbsolutePath,
        transform: @Sendable (AbsolutePath) async throws -> Void,
        using fileSystem: FileSystem
    ) async throws {
        try await fileSystem.withAtomicCopyAndWrite(
            from: source,
            to: destination,
            perform: transform
        )
    }

    private func expectFailure(_ operation: () async throws -> Void) async {
        await #expect(throws: (any Swift.Error).self) {
            try await operation()
        }
    }
}

// MARK: - Verification Helpers

extension FileSystemAtomicTests {
    private func verify(
        _ verifications: [TestCase.Verification],
        in directory: AbsolutePath,
        using fileSystem: FileSystem
    ) async throws {
        for verification in verifications {
            try await verifyItem(verification, in: directory, using: fileSystem)
        }
    }

    private func verifyItem(
        _ verification: TestCase.Verification,
        in baseDir: AbsolutePath,
        using fileSystem: FileSystem
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

        case let .fileDoesNotExist(path):
            let fullPath = resolvePath(path, in: baseDir)
            let exists = try await fileSystem.exists(fullPath)
            #expect(!exists, "Expected file NOT to exist at \(path)")

        case let .directoryExists(path):
            let fullPath = resolvePath(path, in: baseDir)
            let exists = try await fileSystem.exists(fullPath, isDirectory: true)
            #expect(exists, "Expected directory to exist at \(path)")
        }
    }

    private func verifyDestinationUnchanged(
        _ originalSetup: [TestCase.Setup],
        in directory: AbsolutePath,
        using fileSystem: FileSystem
    ) async throws {
        for item in originalSetup {
            if case let .file(path, expectedContent) = item {
                let fullPath = resolvePath(path, in: directory)
                let data = try await fileSystem.readFile(at: fullPath)
                let actual = String(data: data, encoding: .utf8)
                #expect(actual == expectedContent, "Destination should be unchanged after failure")
            }
        }
    }

    private func resolvePath(_ relativePath: String, in baseDir: AbsolutePath) -> AbsolutePath {
        if relativePath == "." {
            return baseDir
        }
        return baseDir.appending(components: relativePath.split(separator: "/").map(String.init))
    }
}

// MARK: - Test Case Definition

extension FileSystemAtomicTests {
    struct TestCase: CustomTestStringConvertible, Sendable {
        let description: String
        let sourceSetup: [Setup]
        let destSetup: [Setup]
        let transform: @Sendable (AbsolutePath) async throws -> Void
        let expectation: Expectation

        var testDescription: String { description }

        enum Setup: Sendable {
            case file(path: String, content: String)
            case directory(path: String)
        }

        enum Verification: Sendable {
            case fileExists(path: String)
            case fileContent(path: String, expected: String)
            case fileDoesNotExist(path: String)
            case directoryExists(path: String)
        }

        enum Expectation: Sendable {
            case success(verifications: [Verification])
            case failure
        }

        static let allCases: [TestCase] = [
            // Basic copy to new destination
            TestCase(
                description: "copies source to new destination",
                sourceSetup: [
                    .file(path: "file.txt", content: "hello"),
                ],
                destSetup: [],
                transform: { _ in },
                expectation: .success(verifications: [
                    .fileExists(path: "file.txt"),
                    .fileContent(path: "file.txt", expected: "hello"),
                ])
            ),

            // Copy with transformation
            TestCase(
                description: "applies transformation during copy",
                sourceSetup: [
                    .file(path: "file.txt", content: "original"),
                ],
                destSetup: [],
                transform: { workDir in
                    let filePath = workDir.appending(component: "file.txt")
                    let fs = FileSystem()
                    try await fs.writeText("transformed", at: filePath, options: [.overwrite])
                },
                expectation: .success(verifications: [
                    .fileContent(path: "file.txt", expected: "transformed"),
                ])
            ),

            // Copy nested directory structure
            TestCase(
                description: "copies nested directory structure",
                sourceSetup: [
                    .file(path: "dir/subdir/file.txt", content: "nested content"),
                    .file(path: "dir/another.txt", content: "another"),
                ],
                destSetup: [],
                transform: { _ in },
                expectation: .success(verifications: [
                    .directoryExists(path: "dir"),
                    .directoryExists(path: "dir/subdir"),
                    .fileContent(path: "dir/subdir/file.txt", expected: "nested content"),
                    .fileContent(path: "dir/another.txt", expected: "another"),
                ])
            ),

            // Merge with existing destination
            TestCase(
                description: "merges with existing destination",
                sourceSetup: [
                    .file(path: "new-file.txt", content: "new content"),
                ],
                destSetup: [
                    .file(path: "existing-file.txt", content: "existing content"),
                ],
                transform: { _ in },
                expectation: .success(verifications: [
                    .fileContent(path: "new-file.txt", expected: "new content"),
                    .fileContent(path: "existing-file.txt", expected: "existing content"),
                ])
            ),

            // Overwrite existing file in destination
            TestCase(
                description: "overwrites existing file in destination",
                sourceSetup: [
                    .file(path: "file.txt", content: "new content"),
                ],
                destSetup: [
                    .file(path: "file.txt", content: "old content"),
                ],
                transform: { _ in },
                expectation: .success(verifications: [
                    .fileContent(path: "file.txt", expected: "new content"),
                ])
            ),

            // Transform adds new file
            TestCase(
                description: "transform can add new files",
                sourceSetup: [
                    .file(path: "original.txt", content: "original"),
                ],
                destSetup: [],
                transform: { workDir in
                    let newFile = workDir.appending(component: "generated.txt")
                    let fs = FileSystem()
                    try await fs.writeText("generated content", at: newFile)
                },
                expectation: .success(verifications: [
                    .fileContent(path: "original.txt", expected: "original"),
                    .fileContent(path: "generated.txt", expected: "generated content"),
                ])
            ),

            // Transform removes file
            TestCase(
                description: "transform can remove files",
                sourceSetup: [
                    .file(path: "keep.txt", content: "keep"),
                    .file(path: "remove.txt", content: "remove"),
                ],
                destSetup: [],
                transform: { workDir in
                    let removeFile = workDir.appending(component: "remove.txt")
                    let fs = FileSystem()
                    try await fs.remove(removeFile)
                },
                expectation: .success(verifications: [
                    .fileContent(path: "keep.txt", expected: "keep"),
                    .fileDoesNotExist(path: "remove.txt"),
                ])
            ),

            // Rollback on transform failure
            TestCase(
                description: "rolls back on transform failure",
                sourceSetup: [
                    .file(path: "file.txt", content: "new"),
                ],
                destSetup: [
                    .file(path: "existing.txt", content: "should remain"),
                ],
                transform: { _ in
                    throw TestError.transformFailed
                },
                expectation: .failure
            ),

            // Multiple files at root level
            TestCase(
                description: "copies multiple files at root level",
                sourceSetup: [
                    .file(path: "a.txt", content: "a"),
                    .file(path: "b.txt", content: "b"),
                    .file(path: "c.txt", content: "c"),
                ],
                destSetup: [],
                transform: { _ in },
                expectation: .success(verifications: [
                    .fileContent(path: "a.txt", expected: "a"),
                    .fileContent(path: "b.txt", expected: "b"),
                    .fileContent(path: "c.txt", expected: "c"),
                ])
            ),
        ]
    }

    enum TestError: Swift.Error, Sendable {
        case transformFailed
    }
}
