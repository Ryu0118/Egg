@testable import EggKit
import FileManagerProtocol
import Foundation
import Testing

struct FileSystemAtomicTests {
    @Test("with atomic copy and write", arguments: TestCase.allCases)
    func withAtomicCopyAndWrite(_ testCase: TestCase) async throws {
        let fileManager: any FileManagerProtocol = FileManager.default
        let tempBase = try fileManager.makeTemporaryDirectory(prefix: "atomic-test")

        defer {
            try? fileManager.removeItem(at: tempBase)
        }

        let sourceDir = tempBase.appending(path: "source")
        let destDir = tempBase.appending(path: "dest")

        try setupSource(testCase.sourceSetup, in: sourceDir, using: fileManager)
        try setupDestination(testCase.destSetup, in: destDir, using: fileManager)

        switch testCase.expectation {
        case let .success(verifications):
            try await executeAtomicCopy(
                from: sourceDir,
                to: destDir,
                transform: testCase.transform,
                using: fileManager,
            )
            try verify(verifications, in: destDir, using: fileManager)

        case .failure:
            await expectFailure {
                try await executeAtomicCopy(
                    from: sourceDir,
                    to: destDir,
                    transform: testCase.transform,
                    using: fileManager,
                )
            }
            try verifyDestinationUnchanged(testCase.destSetup, in: destDir, using: fileManager)
        }
    }
}

extension FileSystemAtomicTests {
    private func setupSource(
        _ items: [TestCase.Setup],
        in directory: URL,
        using fileManager: some FileManagerProtocol,
    ) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        for item in items {
            try createItem(item, in: directory, using: fileManager)
        }
    }

    private func setupDestination(
        _ items: [TestCase.Setup],
        in directory: URL,
        using fileManager: some FileManagerProtocol,
    ) throws {
        guard !items.isEmpty else { return }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        for item in items {
            try createItem(item, in: directory, using: fileManager)
        }
    }

    private func createItem(
        _ item: TestCase.Setup,
        in baseDir: URL,
        using fileManager: some FileManagerProtocol,
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
        }
    }

    private func createParentDirectoryIfNeeded(
        for path: URL,
        using fileManager: some FileManagerProtocol,
    ) throws {
        let parent = path.deletingLastPathComponent()
        if !fileManager.exists(parent) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
    }
}

extension FileSystemAtomicTests {
    private func executeAtomicCopy(
        from source: URL,
        to destination: URL,
        transform: @Sendable (URL) throws -> Void,
        using fileManager: some FileManagerProtocol,
    ) async throws {
        try await fileManager.withAtomicCopyAndWrite(
            from: source,
            to: destination,
            perform: { workingDirectory in
                try transform(workingDirectory)
            },
        )
    }

    private func expectFailure(_ operation: () async throws -> Void) async {
        await #expect(throws: (any Swift.Error).self) {
            try await operation()
        }
    }
}

extension FileSystemAtomicTests {
    private func verify(
        _ verifications: [TestCase.Verification],
        in directory: URL,
        using fileManager: some FileManagerProtocol,
    ) throws {
        for verification in verifications {
            try verifyItem(verification, in: directory, using: fileManager)
        }
    }

    private func verifyItem(
        _ verification: TestCase.Verification,
        in baseDir: URL,
        using fileManager: some FileManagerProtocol,
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

        case let .fileDoesNotExist(path):
            let fullPath = resolvePath(path, in: baseDir)
            let exists = fileManager.exists(fullPath)
            #expect(!exists, "Expected file NOT to exist at \(path)")

        case let .directoryExists(path):
            let fullPath = resolvePath(path, in: baseDir)
            let exists = fileManager.exists(fullPath) && fileManager.isDirectory(at: fullPath)
            #expect(exists, "Expected directory to exist at \(path)")
        }
    }

    private func verifyDestinationUnchanged(
        _ originalSetup: [TestCase.Setup],
        in directory: URL,
        using fileManager: some FileManagerProtocol,
    ) throws {
        for item in originalSetup {
            if case let .file(path, expectedContent) = item {
                let fullPath = resolvePath(path, in: directory)
                let data = try fileManager.readFile(at: fullPath)
                let actual = String(data: data, encoding: .utf8)
                #expect(actual == expectedContent, "Destination should be unchanged after failure")
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

extension FileSystemAtomicTests {
    struct TestCase: CustomTestStringConvertible {
        let description: String
        let sourceSetup: [Setup]
        let destSetup: [Setup]
        let transform: @Sendable (URL) throws -> Void
        let expectation: Expectation

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
                ]),
            ),

            // Copy with transformation
            TestCase(
                description: "applies transformation during copy",
                sourceSetup: [
                    .file(path: "file.txt", content: "original"),
                ],
                destSetup: [],
                transform: { workDir in
                    let filePath = workDir.appending(path: "file.txt")
                    let fileManager = FileManager.default
                    try fileManager.writeText("transformed", at: filePath, encoding: .utf8)
                },
                expectation: .success(verifications: [
                    .fileContent(path: "file.txt", expected: "transformed"),
                ]),
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
                ]),
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
                ]),
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
                ]),
            ),

            // Transform adds new file
            TestCase(
                description: "transform can add new files",
                sourceSetup: [
                    .file(path: "original.txt", content: "original"),
                ],
                destSetup: [],
                transform: { workDir in
                    let newFile = workDir.appending(path: "generated.txt")
                    let fileManager = FileManager.default
                    try fileManager.writeText("generated content", at: newFile, encoding: .utf8)
                },
                expectation: .success(verifications: [
                    .fileContent(path: "original.txt", expected: "original"),
                    .fileContent(path: "generated.txt", expected: "generated content"),
                ]),
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
                    let removeFile = workDir.appending(path: "remove.txt")
                    let fileManager = FileManager.default
                    try fileManager.removeItem(at: removeFile)
                },
                expectation: .success(verifications: [
                    .fileContent(path: "keep.txt", expected: "keep"),
                    .fileDoesNotExist(path: "remove.txt"),
                ]),
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
                expectation: .failure,
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
                ]),
            ),

            // Recursive merge: preserves files in existing subdirectories
            TestCase(
                description: "recursively merges directories preserving existing files",
                sourceSetup: [
                    .file(path: "Sources/NewModule/NewModule.swift", content: "new module"),
                ],
                destSetup: [
                    .file(path: "Sources/ExistingModule/Existing.swift", content: "existing"),
                    .file(path: "Sources/ExistingModule/Helper.swift", content: "helper"),
                ],
                transform: { _ in },
                expectation: .success(verifications: [
                    // New content is added
                    .directoryExists(path: "Sources/NewModule"),
                    .fileContent(path: "Sources/NewModule/NewModule.swift", expected: "new module"),
                    // Existing content is preserved
                    .directoryExists(path: "Sources/ExistingModule"),
                    .fileContent(path: "Sources/ExistingModule/Existing.swift", expected: "existing"),
                    .fileContent(path: "Sources/ExistingModule/Helper.swift", expected: "helper"),
                ]),
            ),

            // Recursive merge: updates files in nested directories
            TestCase(
                description: "recursively merges and updates files in nested directories",
                sourceSetup: [
                    .file(path: "dir/subdir/updated.txt", content: "updated content"),
                    .file(path: "dir/subdir/new.txt", content: "new file"),
                ],
                destSetup: [
                    .file(path: "dir/subdir/updated.txt", content: "old content"),
                    .file(path: "dir/subdir/preserved.txt", content: "should be preserved"),
                    .file(path: "dir/other/other.txt", content: "other file"),
                ],
                transform: { _ in },
                expectation: .success(verifications: [
                    // Updated file has new content
                    .fileContent(path: "dir/subdir/updated.txt", expected: "updated content"),
                    // New file is added
                    .fileContent(path: "dir/subdir/new.txt", expected: "new file"),
                    // Existing file is preserved
                    .fileContent(path: "dir/subdir/preserved.txt", expected: "should be preserved"),
                    // Files in other directories preserved
                    .fileContent(path: "dir/other/other.txt", expected: "other file"),
                ]),
            ),

            // Deep recursive merge
            TestCase(
                description: "handles deeply nested recursive merge",
                sourceSetup: [
                    .file(path: "a/b/c/d/new.txt", content: "deep new"),
                ],
                destSetup: [
                    .file(path: "a/b/c/d/existing.txt", content: "deep existing"),
                    .file(path: "a/b/c/sibling.txt", content: "sibling"),
                    .file(path: "a/b/other/file.txt", content: "other branch"),
                ],
                transform: { _ in },
                expectation: .success(verifications: [
                    .fileContent(path: "a/b/c/d/new.txt", expected: "deep new"),
                    .fileContent(path: "a/b/c/d/existing.txt", expected: "deep existing"),
                    .fileContent(path: "a/b/c/sibling.txt", expected: "sibling"),
                    .fileContent(path: "a/b/other/file.txt", expected: "other branch"),
                ]),
            ),
        ]

        enum Setup {
            case file(path: String, content: String)
            case directory(path: String)
        }

        enum Verification {
            case fileExists(path: String)
            case fileContent(path: String, expected: String)
            case fileDoesNotExist(path: String)
            case directoryExists(path: String)
        }

        enum Expectation {
            case success(verifications: [Verification])
            case failure
        }

        var testDescription: String {
            description
        }
    }

    enum TestError: Swift.Error {
        case transformFailed
    }
}
