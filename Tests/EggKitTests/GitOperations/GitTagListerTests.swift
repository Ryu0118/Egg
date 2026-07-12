@testable import EggKit
import FileManagerProtocol
import Foundation
import Testing

struct GitTagListerTests {
    // MARK: - Pure output parsing

    @Test("parses lightweight and annotated tags, merging peeled entries")
    func parseTagOutput() {
        let output = """
        a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2\trefs/tags/1.0.0
        d4e5f6a7b8c9d4e5f6a7b8c9d4e5f6a7b8c9d4e5\trefs/tags/v1.1.0
        97117bc42b44f33e0d04b543b815ad9f3079f25e\trefs/tags/v1.1.0^{}
        """

        let tags = GitTagLister.parseTagOutput(output)

        #expect(tags == [
            GitRemoteTag(
                name: "1.0.0",
                objectSHA: "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2",
                peeledSHA: nil,
            ),
            GitRemoteTag(
                name: "v1.1.0",
                objectSHA: "d4e5f6a7b8c9d4e5f6a7b8c9d4e5f6a7b8c9d4e5",
                peeledSHA: "97117bc42b44f33e0d04b543b815ad9f3079f25e",
            ),
        ])
        #expect(tags[0].revision == "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2")
        #expect(tags[1].revision == "97117bc42b44f33e0d04b543b815ad9f3079f25e")
    }

    @Test("skips junk lines, non-tag refs, and malformed SHAs")
    func parseTagOutputSkipsJunk() {
        let output = """
        a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2\trefs/heads/main
        not-a-sha\trefs/tags/broken
        a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2
        deadbeef\trefs/tags/short-sha

        a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2\trefs/tags/2.0.0
        """

        let tags = GitTagLister.parseTagOutput(output)

        #expect(tags.map(\.name) == ["2.0.0"])
    }

    @Test("orphan peeled entries without a base tag are dropped")
    func parseTagOutputOrphanPeeled() {
        let output = "97117bc42b44f33e0d04b543b815ad9f3079f25e\trefs/tags/ghost^{}"
        #expect(GitTagLister.parseTagOutput(output).isEmpty)
    }

    @Test("parses branch head output and returns nil for empty output")
    func parseBranchOutput() {
        let output = "97117bc42b44f33e0d04b543b815ad9f3079f25e\trefs/heads/main"
        #expect(
            GitTagLister.parseBranchOutput(output, branch: "main")
                == "97117bc42b44f33e0d04b543b815ad9f3079f25e",
        )
        #expect(GitTagLister.parseBranchOutput(output, branch: "develop") == nil)
        #expect(GitTagLister.parseBranchOutput("", branch: "main") == nil)
    }

    // MARK: - Integration against a real repository

    @Test("lists tags and branch heads from a real repository")
    func listTagsFromRealRepository() async throws {
        let fileManager: some FileManagerProtocol = FileManager.default
        let root = try fileManager.makeTemporaryDirectory(prefix: "GitTagListerTests")
        defer { try? fileManager.removeItem(at: root) }

        let repo = root.appending(path: "repo")
        try fileManager.createDirectory(at: repo, withIntermediateDirectories: true)
        try fileManager.writeText("hello\n", at: repo.appending(path: "README.md"))
        try runGit(["init", "--quiet", "-b", "main"], in: repo)
        try runGit(["add", "."], in: repo)
        try runGit(["commit", "--quiet", "-m", "initial"], in: repo)
        try runGit(["tag", "1.0.0"], in: repo)
        try runGit(["tag", "-a", "v1.1.0", "-m", "release 1.1.0"], in: repo)
        let headSHA = try runGit(["rev-parse", "HEAD"], in: repo)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let repoPath = repo.path(percentEncoded: false)
        let url = GitURL(original: repoPath, normalized: repoPath)
        let lister = GitTagLister()

        let tags = try await lister.listTags(url: url)
        #expect(tags.count == 2)

        let lightweight = try #require(tags.first { $0.name == "1.0.0" })
        #expect(lightweight.peeledSHA == nil)
        #expect(lightweight.revision == headSHA)

        let annotated = try #require(tags.first { $0.name == "v1.1.0" })
        #expect(annotated.peeledSHA != nil)
        #expect(annotated.objectSHA != headSHA)
        #expect(annotated.revision == headSHA)

        #expect(try await lister.remoteBranchRevision(url: url, branch: "main") == headSHA)
        #expect(try await lister.remoteBranchRevision(url: url, branch: "missing") == nil)
    }

    @Test("throws lsRemoteFailed with stderr for a nonexistent repository")
    func lsRemoteFailure() async throws {
        let url = GitURL(
            original: "/nonexistent/egg-tag-lister-test",
            normalized: "/nonexistent/egg-tag-lister-test",
        )
        let lister = GitTagLister()

        let error = try await #require(throws: GitTagLister.Error.self) {
            try await lister.listTags(url: url)
        }
        guard case let .lsRemoteFailed(failedURL, exitCode, stderr) = error else {
            Issue.record("expected .lsRemoteFailed, got \(error)")
            return
        }
        #expect(failedURL == "/nonexistent/egg-tag-lister-test")
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
