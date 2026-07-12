@testable import EggKit
import FileManagerProtocol
import Foundation
import Testing

struct GitClonerTests {
    @Test("headRevision resolves the SHA checked out at a cloned directory")
    func headRevisionAgainstRealRepository() async throws {
        let fileManager: some FileManagerProtocol = FileManager.default
        let root = try fileManager.makeTemporaryDirectory(prefix: "GitClonerTests")
        defer { try? fileManager.removeItem(at: root) }

        let repo = root.appending(path: "repo")
        try fileManager.createDirectory(at: repo, withIntermediateDirectories: true)
        try fileManager.writeText("hello\n", at: repo.appending(path: "README.md"))
        try runGit(["init", "--quiet", "-b", "main"], in: repo)
        try runGit(["add", "."], in: repo)
        try runGit(["commit", "--quiet", "-m", "initial"], in: repo)
        let headSHA = try runGit(["rev-parse", "HEAD"], in: repo)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let revision = try await GitCloner().headRevision(at: repo)
        #expect(revision == headSHA)
    }

    @Test("headRevision throws headRevisionFailed for a non-repository directory")
    func headRevisionFailure() async throws {
        let fileManager: some FileManagerProtocol = FileManager.default
        let root = try fileManager.makeTemporaryDirectory(prefix: "GitClonerTests")
        defer { try? fileManager.removeItem(at: root) }

        let error = try await #require(throws: GitCloner.Error.self) {
            try await GitCloner().headRevision(at: root)
        }
        guard case let .headRevisionFailed(path, exitCode, stderr) = error else {
            Issue.record("expected .headRevisionFailed, got \(error)")
            return
        }
        #expect(path == root.path(percentEncoded: false))
        #expect(exitCode != 0)
        #expect(!stderr.isEmpty)
    }

    // MARK: - Helpers

    @discardableResult
    private func runGit(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = ["-c", "user.name=egg-tests", "-c", "user.email=egg-tests@example.com"] + arguments
        process.currentDirectoryURL = directory
        let stdout = Pipe()
        process.standardOutput = stdout
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            struct GitCommandFailed: Error {}
            throw GitCommandFailed()
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }
}
