import FileManagerProtocol
import Foundation
import Testing

/// Lifecycle scripts run under `sandbox-exec`. A `TMPDIR` outside
/// `/private/tmp` and `/private/var/folders` (for example an external volume)
/// must stay writable for them.
@Suite(.buildBinary, .serialized)
struct SandboxTempDirectoryTests {
    let fileManager: any FileManagerProtocol = FileManager.default

    @Test("hatch preview lets a sandboxed lifecycle script write to a TMPDIR outside the system temp directories")
    func scriptWritesToCustomTempDirectory() async throws {
        let runner = try await CLIRunner()

        // The package's .build directory is on neither built-in temp root.
        let scratch = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: ".build")
            .appending(path: "sandbox-tmpdir-e2e-\(UUID().uuidString)")
        let project = scratch.appending(path: "project")
        let tempDir = scratch.appending(path: "tmp")
        try fileManager.createDirectory(at: project, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: scratch) }

        try runGit(["init", "-q"], in: project)
        try runGit(["commit", "--allow-empty", "-q", "-m", "init"], in: project)

        let templateDir = project.appending(path: ".eggs/TempProbe")
        try fileManager.createDirectory(at: templateDir.appending(path: "files"), withIntermediateDirectories: true)
        try """
        name: TempProbe
        description: writes to TMPDIR from a lifecycle script
        pre_hatch:
          - run: 'echo probe > "$TMPDIR/egg-probe.txt" && cat "$TMPDIR/egg-probe.txt"'
        hatch:
          output: .
        """.write(to: templateDir.appending(path: "config.yml"), atomically: true, encoding: .utf8)
        try "hello\n".write(to: templateDir.appending(path: "files/hello.txt"), atomically: true, encoding: .utf8)

        let result = try await runner.run(
            "hatch", "preview", "TempProbe",
            workingDirectory: project,
            environment: [
                "TMPDIR": tempDir.path(percentEncoded: false),
                "HOME": scratch.path(percentEncoded: false),
            ],
        )

        #expect(result.succeeded, Comment(rawValue: result.stderr + result.stdout))
        #expect(fileManager.fileExists(atPath: tempDir.appending(path: "egg-probe.txt").path(percentEncoded: false)))
    }

    private func runGit(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        try process.run()
        process.waitUntilExit()
    }
}
