@testable import EggKit
import Foundation
import ProcessRunning
import Testing

/// The sandbox profile must keep the process's effective temp directory
/// writable even when `TMPDIR` points outside `/private/tmp` and
/// `/private/var/folders` (e.g. an external volume), without widening the
/// boundary to the directory's parent.
@Suite("Sandbox profile temp directory", .serialized)
struct SandboxProfileTests {
    /// A scratch area under the package's `.build`, which is on neither of the
    /// built-in temp roots (the repository lives outside `/private/tmp` and
    /// `/private/var/folders`).
    private struct Scratch {
        let root: URL

        init() throws {
            let packageRoot = URL(filePath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            root = packageRoot
                .appending(path: ".build")
                .appending(path: "sandbox-profile-tests")
                .appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        func directory(_ name: String) throws -> URL {
            let url = root.appending(path: name)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func configuration(writableRoot: URL, deniedPaths: [URL] = []) -> SandboxConfiguration {
        SandboxConfiguration(writableRoot: writableRoot, deniedPaths: deniedPaths)
    }

    private func real(_ url: URL) -> String {
        url.resolvingSymlinksInPath().path(percentEncoded: false)
    }

    private func profile(_ configuration: SandboxConfiguration, temporaryDirectory: URL?) -> String {
        ShellScriptRunner.generateSandboxProfile(for: configuration, temporaryDirectory: temporaryDirectory)
    }

    @Test("a temp directory outside the system temp roots gets read/write rules for exactly its own subtree")
    func customTempDirectoryIsAllowed() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let staging = try scratch.directory("staging")
        let temp = try scratch.directory("tmp")

        let result = profile(configuration(writableRoot: staging), temporaryDirectory: temp)

        #expect(result.contains("(allow file-write* (subpath \"\(real(temp))\"))"))
        #expect(!result.contains("(allow file-write* (subpath \"\(real(scratch.root))\"))"))
    }

    @Test("a symlinked temp directory is canonicalized to its real path")
    func symlinkedTempDirectoryIsResolved() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let staging = try scratch.directory("staging")
        let target = try scratch.directory("real-tmp")
        let link = scratch.root.appending(path: "link-tmp")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let result = profile(configuration(writableRoot: staging), temporaryDirectory: link)

        #expect(result.contains("(allow file-write* (subpath \"\(real(target))\"))"))
        #expect(!result.contains(link.path(percentEncoded: false)))
    }

    @Test("quotes, backslashes, and spaces in the temp path are escaped for the profile string")
    func specialCharactersAreEscaped() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let staging = try scratch.directory("staging")
        let temp = try scratch.directory("my \"quoted\" tmp\\dir")

        let result = profile(configuration(writableRoot: staging), temporaryDirectory: temp)

        let escaped = real(temp)
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        #expect(result.contains("(allow file-write* (subpath \"\(escaped)\"))"))
    }

    @Test("a temp directory that is missing, empty, root, or already covered adds no rule", arguments: [
        "missing", "root", "private-tmp", "var-folders", "inside-writable-root",
    ])
    func uncoveredCasesAddNoRule(_ kind: String) throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let staging = try scratch.directory("staging")
        let inside = try scratch.directory("staging/scratch")
        let config = configuration(writableRoot: staging)
        let baseline = profile(config, temporaryDirectory: nil)

        let temp: URL = switch kind {
        case "missing": scratch.root.appending(path: "does-not-exist")
        case "root": URL(filePath: "/")
        case "private-tmp": URL(filePath: "/private/tmp")
        case "var-folders": FileManager.default.temporaryDirectory
        default: inside
        }

        #expect(profile(config, temporaryDirectory: temp) == baseline)
    }

    @Test("a temp directory that contains a denied path adds no rule, so the deny cannot be reopened")
    func tempDirectoryAboveDeniedPathIsIgnored() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let staging = try scratch.directory("staging")
        let project = try scratch.directory("tmp/project")
        let temp = scratch.root.appending(path: "tmp")
        let config = configuration(writableRoot: staging, deniedPaths: [project])

        #expect(profile(config, temporaryDirectory: temp) == profile(config, temporaryDirectory: nil))
    }

    @Test("a nil temp directory leaves the original profile unchanged")
    func nilTempDirectoryMatchesBaseline() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let staging = try scratch.directory("staging")
        let config = configuration(writableRoot: staging)

        #expect(!profile(config, temporaryDirectory: nil).contains("effective temp directory"))
    }

    // MARK: - Effective temp directory

    @Test("the process temp directory follows TMPDIR and falls back when it is unset or empty")
    func processTemporaryDirectoryFollowsTMPDIR() {
        let original = ProcessInfo.processInfo.environment["TMPDIR"]
        defer {
            if let original {
                setenv("TMPDIR", original, 1)
            } else {
                unsetenv("TMPDIR")
            }
        }

        setenv("TMPDIR", "/Volumes/External/tmp/", 1)
        #expect(ShellScriptRunner.processTemporaryDirectory.path(percentEncoded: false) == "/Volumes/External/tmp/")

        setenv("TMPDIR", "", 1)
        #expect(ShellScriptRunner.processTemporaryDirectory == FileManager.default.temporaryDirectory)

        unsetenv("TMPDIR")
        #expect(ShellScriptRunner.processTemporaryDirectory == FileManager.default.temporaryDirectory)
    }

    // MARK: - Real sandbox-exec

    @Test("a sandboxed script can write to a TMPDIR outside the system temp roots but not to the parent directory")
    func sandboxedScriptWritesToCustomTempDirectory() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let staging = try scratch.directory("staging")
        let temp = try scratch.directory("tmp")
        let sibling = scratch.root.appending(path: "outside.txt")

        let runner = ShellScriptRunner(
            processRunner: ProcessRunner(),
            workingDirectory: staging,
            additionalEnvironment: ["TMPDIR": temp.path(percentEncoded: false)],
            executionEnvironment: .sandboxed(configuration(writableRoot: staging)),
            temporaryDirectory: temp,
        )

        let output = try await runner.executeStreaming(
            "echo ok > \"$TMPDIR/inside.txt\" && cat \"$TMPDIR/inside.txt\"",
        ) { _ in }
        #expect(output.contains("ok"))

        await #expect(throws: LifecycleStepError.self) {
            _ = try await runner.executeStreaming("echo no > \"\(sibling.path(percentEncoded: false))\"") { _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: sibling.path(percentEncoded: false)))
    }
}
