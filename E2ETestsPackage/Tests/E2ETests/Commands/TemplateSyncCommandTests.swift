import FileManagerProtocol
import Foundation
import Testing

@Suite(.buildBinary, .serialized)
struct TemplateSyncCommandTests {
    let fileManager: any FileManagerProtocol = FileManager.default

    // MARK: - Help

    @Test("template sync --help documents scope, dry-run, and json flags")
    func helpShowsSyncCommandHelp() async throws {
        let runner = try await CLIRunner()
        let result = try await runner.run("template", "sync", "--help")

        #expect(result.succeeded)
        #expect(result.stdout.contains("USAGE: egg template sync"))
        #expect(result.stdout.contains("--global"))
        #expect(result.stdout.contains("--project"))
        #expect(result.stdout.contains("--dry-run"))
        #expect(result.stdout.contains("--json"))
    }

    @Test("template update --help documents the re-resolve behavior")
    func helpShowsUpdateCommandHelp() async throws {
        let runner = try await CLIRunner()
        let result = try await runner.run("template", "update", "--help")

        #expect(result.succeeded)
        #expect(result.stdout.contains("USAGE: egg template update"))
        #expect(result.stdout.contains("latest eligible"))
    }

    // MARK: - Full lifecycle against a real tagged repository

    @Test("sync resolves from:, honors the lock on re-sync, and fails a bumped constraint naming the highest tag")
    func syncLifecycle() async throws {
        let env = try await makeSyncEnvironment()
        defer { env.cleanup() }

        // Repo with a lightweight v1.0.0, an annotated 1.1.0, and an
        // excluded prerelease 2.0.0-beta.1.
        let repo = try makeTaggedRepository(
            in: env.tempDir,
            templateName: "SyncTemplate",
            tags: [("v1.0.0", false), ("1.1.0", true), ("2.0.0-beta.1", false)],
        )
        try writeManifest(env, "eggs:\n  - url: file://\(repo.path(percentEncoded: false))\n    from: \"1.0.0\"\n")

        // First sync: resolves 1.1.0, installs, writes the lock.
        let first = try await env.runner.run(
            arguments: ["template", "sync", "--project", "--project-directory", env.projectPath],
            environment: env.env,
        )
        #expect(first.succeeded)
        #expect(first.stdout.contains("resolved 1.1.0"))
        #expect(first.stdout.contains("Installed 'SyncTemplate'"))
        #expect(fileManager.fileExists(atPath: env.projectDir.appending(path: ".eggs/SyncTemplate/config.yml").path(percentEncoded: false)))

        let lockPath = env.projectDir.appending(path: "eggs-lock.yml")
        let lockAfterFirst = try String(contentsOf: lockPath, encoding: .utf8)
        #expect(lockAfterFirst.contains("eggs:"), "lockfile top-level key mirrors the manifest's eggs: key")
        #expect(!lockAfterFirst.contains("templates:"))
        #expect(lockAfterFirst.contains("version: 1.1.0"))
        #expect(!lockAfterFirst.contains("2.0.0-beta.1"), "prereleases stay out of a release-bounded range")

        // Re-sync: the lock is reused.
        let second = try await env.runner.run(
            arguments: ["template", "sync", "--project", "--project-directory", env.projectPath],
            environment: env.env,
        )
        #expect(second.succeeded)
        #expect(second.stdout.contains("reusing locked 1.1.0"))

        // update --dry-run --json: reports without touching the lock.
        let dryRun = try await env.runner.run(
            arguments: ["template", "update", "--project", "--dry-run", "--json", "--project-directory", env.projectPath],
            environment: env.env,
        )
        #expect(dryRun.succeeded)
        #expect(dryRun.stdout.contains("\"dryRun\" : true"))
        #expect(dryRun.stdout.contains("\"lockfileWritten\" : false"))
        let lockAfterDryRun = try String(contentsOf: lockPath, encoding: .utf8)
        #expect(lockAfterDryRun == lockAfterFirst)

        // Bump the constraint past every release tag: sync fails naming the
        // highest available tag, and the previous pin survives.
        try writeManifest(env, "eggs:\n  - url: file://\(repo.path(percentEncoded: false))\n    from: \"2.0.0\"\n")
        let bumped = try await env.runner.run(
            arguments: ["template", "sync", "--project", "--project-directory", env.projectPath],
            environment: env.env,
        )
        #expect(!bumped.succeeded)
        let bumpedOutput = bumped.stdout + bumped.stderr
        #expect(bumpedOutput.contains("no version satisfying 'from: 2.0.0'"))
        #expect(bumpedOutput.contains("highest available: 2.0.0-beta.1"))
        let lockAfterFailure = try String(contentsOf: lockPath, encoding: .utf8)
        #expect(lockAfterFailure.contains("version: 1.1.0"), "a failed entry keeps its previous pin")
    }

    @Test("local manifest entries install but are never recorded in the lock")
    func localEntriesAreNotLocked() async throws {
        let env = try await makeSyncEnvironment()
        defer { env.cleanup() }

        let localTemplates = env.projectDir.appending(path: "local-templates")
        try writeTemplate(named: "LocalOnly", into: localTemplates)
        try writeManifest(env, "eggs:\n  - url: ./local-templates\n")

        let result = try await env.runner.run(
            arguments: ["template", "sync", "--project", "--project-directory", env.projectPath],
            environment: env.env,
        )

        #expect(result.succeeded)
        #expect(result.stdout.contains("Installed 'LocalOnly'"))
        #expect(fileManager.fileExists(atPath: env.projectDir.appending(path: ".eggs/LocalOnly/config.yml").path(percentEncoded: false)))
        #expect(!fileManager.fileExists(atPath: env.projectDir.appending(path: "eggs-lock.yml").path(percentEncoded: false)))
    }

    // MARK: - Errors and partial failure

    @Test("sync with no manifest anywhere fails listing the searched paths")
    func noManifestFails() async throws {
        let env = try await makeSyncEnvironment()
        defer { env.cleanup() }

        let result = try await env.runner.run(
            arguments: ["template", "sync", "--project-directory", env.projectPath],
            environment: env.env,
        )

        #expect(!result.succeeded)
        #expect((result.stdout + result.stderr).contains("no manifest found. Searched:"))
    }

    @Test("a failing source exits nonzero while healthy entries still install")
    func partialFailure() async throws {
        let env = try await makeSyncEnvironment()
        defer { env.cleanup() }

        let localTemplates = env.projectDir.appending(path: "local-templates")
        try writeTemplate(named: "Healthy", into: localTemplates)
        try writeManifest(
            env,
            """
            eggs:
              - url: file:///nonexistent/egg-sync-e2e.git
                branch: main
              - url: ./local-templates
            """,
        )

        let result = try await env.runner.run(
            arguments: ["template", "sync", "--project", "--project-directory", env.projectPath],
            environment: env.env,
        )

        #expect(!result.succeeded)
        let output = result.stdout + result.stderr
        #expect(output.contains("Installed 'Healthy'"))
        #expect(output.contains("1 source(s) failed"))
        #expect(fileManager.fileExists(atPath: env.projectDir.appending(path: ".eggs/Healthy/config.yml").path(percentEncoded: false)))
    }

    // MARK: - Helpers

    private struct SyncEnvironment {
        let runner: CLIRunner
        let env: [String: String]
        let tempDir: URL
        let projectDir: URL
        let cleanup: () -> Void

        var projectPath: String {
            projectDir.path(percentEncoded: false)
        }
    }

    private func makeSyncEnvironment() async throws -> SyncEnvironment {
        let runner = try await CLIRunner()
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "cli-test-sync")

        let homeDir = tempDir.appending(path: "home")
        let projectDir = tempDir.appending(path: "project")
        try fileManager.createDirectory(at: homeDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let env = ["HOME": homeDir.path(percentEncoded: false)]
        return SyncEnvironment(
            runner: runner,
            env: env,
            tempDir: tempDir,
            projectDir: projectDir,
            cleanup: { [fileManager] in try? fileManager.removeItem(at: tempDir) },
        )
    }

    private func writeManifest(_ env: SyncEnvironment, _ yaml: String) throws {
        try yaml.write(to: env.projectDir.appending(path: "eggs.yml"), atomically: true, encoding: .utf8)
    }

    private func writeTemplate(named name: String, into directory: URL) throws {
        let templateDir = directory.appending(path: name)
        try fileManager.createDirectory(at: templateDir, withIntermediateDirectories: true)
        try """
        name: "\(name)"
        description: "A test template"
        hatch:
          output: "./output"
        """.write(to: templateDir.appending(path: "config.yml"), atomically: true, encoding: .utf8)
    }

    /// Creates a git repository containing one template, then lays the
    /// given tags (`annotated: true` uses `git tag -a`) on successive
    /// commits so every tag resolves to a real revision.
    private func makeTaggedRepository(
        in directory: URL,
        templateName: String,
        tags: [(name: String, annotated: Bool)],
    ) throws -> URL {
        let repo = directory.appending(path: "repo")
        try writeTemplate(named: templateName, into: repo)
        try runGit(["init", "--quiet", "-b", "main"], in: repo)
        try runGit(["add", "."], in: repo)
        try runGit(["commit", "--quiet", "-m", "initial"], in: repo)
        for tag in tags {
            if tag.annotated {
                try runGit(["tag", "-a", tag.name, "-m", "release \(tag.name)"], in: repo)
            } else {
                try runGit(["tag", tag.name], in: repo)
            }
        }
        return repo
    }

    @discardableResult
    private func runGit(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = ["-c", "user.name=egg-e2e", "-c", "user.email=egg-e2e@example.com"] + arguments
        process.currentDirectoryURL = directory
        let stdout = Pipe()
        process.standardOutput = stdout
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            struct GitCommandFailed: Error {}
            throw GitCommandFailed()
        }
        return String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}
