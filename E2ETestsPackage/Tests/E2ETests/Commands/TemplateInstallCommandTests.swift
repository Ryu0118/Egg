import FileManagerProtocol
import Foundation
import Testing

@Suite(.buildBinary, .serialized)
struct TemplateInstallCommandTests {
    let fileManager: any FileManagerProtocol = FileManager.default

    // Test repository URL (HTTPS with token for CI, SSH for local development)
    static let testRepoOwner = "Ryu0118"
    static let testRepoName = "swift-egg-templates"

    /// Known templates in the test repository
    static let knownTemplates = ["SwiftModule", "iOSProjectGenTemplate"]

    static var testRepoURL: String {
        if let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"] {
            return "https://x-access-token:\(token)@github.com/\(testRepoOwner)/\(testRepoName).git"
        }
        return "git@github.com:\(testRepoOwner)/\(testRepoName).git"
    }

    // MARK: - Help

    @Test("template install --help documents git source flags (--branch/--tag/--revision) and filter/destination flags (--template/--exclude/--global/--force)")
    func helpShowsInstallCommandHelp() async throws {
        let runner = try await CLIRunner()
        let result = try await runner.run("template", "install", "--help")

        #expect(result.succeeded)
        #expect(result.stdout.contains("OVERVIEW: Install templates from a Git repository or local directory"))
        #expect(result.stdout.contains("USAGE: egg template install"))
        #expect(result.stdout.contains("--branch"))
        #expect(result.stdout.contains("--tag"))
        #expect(result.stdout.contains("--revision"))
        #expect(result.stdout.contains("--template"))
        #expect(result.stdout.contains("--exclude"))
        #expect(result.stdout.contains("--global"))
        #expect(result.stdout.contains("--force"))
    }

    // MARK: - Validation Errors

    @Test("fails with an Invalid error when the source is neither a valid URL nor an existing local path")
    func failsWithInvalidURL() async throws {
        let (runner, env, projectDir, cleanup) = try await makeTestEnvironment()
        defer { cleanup() }

        let result = try await runner.run(
            arguments: ["template", "install", "not-a-valid-url", "--global", "--project-directory", projectDir.path(percentEncoded: false)],
            environment: env,
        )

        #expect(!result.succeeded)
        #expect((result.stderr + result.stdout).contains("Invalid"))
    }

    @Test("fails with a Cannot use both error when --template and --exclude are combined")
    func failsWhenUsingBothTemplateAndExclude() async throws {
        let (runner, env, projectDir, cleanup) = try await makeTestEnvironment()
        defer { cleanup() }

        let result = try await runner.run(
            arguments: ["template", "install", Self.testRepoURL, "--global", "--template", "Foo", "--exclude", "Bar", "--project-directory", projectDir.path(percentEncoded: false)],
            environment: env,
        )

        #expect(!result.succeeded)
        #expect((result.stderr + result.stdout).contains("Cannot use both"))
    }

    @Test("fails with an Only one of error when --branch and --tag are combined")
    func failsWhenUsingBranchAndTagTogether() async throws {
        let (runner, env, projectDir, cleanup) = try await makeTestEnvironment()
        defer { cleanup() }

        let result = try await runner.run(
            arguments: ["template", "install", Self.testRepoURL, "--global", "--branch", "main", "--tag", "v1.0", "--project-directory", projectDir.path(percentEncoded: false)],
            environment: env,
        )

        #expect(!result.succeeded)
        #expect((result.stderr + result.stdout).contains("Only one of"))
    }

    @Test("fails with a not-allowed-for-local-path error when --branch is combined with a local directory source")
    func failsWhenUsingBranchWithLocalPath() async throws {
        let (runner, env, projectDir, cleanup) = try await makeTestEnvironment()
        defer { cleanup() }

        let localDir = projectDir.appending(path: "templates")
        try fileManager.createDirectory(at: localDir, withIntermediateDirectories: true)

        let result = try await runner.run(
            arguments: ["template", "install", localDir.path(percentEncoded: false), "--global", "--branch", "main", "--project-directory", projectDir.path(percentEncoded: false)],
            environment: env,
        )

        #expect(!result.succeeded)
        #expect((result.stderr + result.stdout).contains("not allowed when installing from a local path"))
    }

    // MARK: - Git Repository Installation

    @Test("installs every template from the repo into ~/.eggs when no --template/--exclude filter is given")
    func installsAllTemplatesToGlobalLocation() async throws {
        let (runner, env, projectDir, cleanup) = try await makeTestEnvironment()
        defer { cleanup() }
        let fixture = try makeGitTemplateFixture(in: projectDir)

        let result = try await runner.run(
            arguments: ["template", "install", fixture.repositoryURL, "--global", "--project-directory", projectDir.path(percentEncoded: false)],
            environment: env,
        )

        #expect(result.succeeded, "Expected success but got exit code \(result.exitCode): \(result.stderr)")

        let homeDir = try URL(filePath: #require(env["HOME"]))
        for template in Self.knownTemplates {
            let path = homeDir.appending(path: ".eggs/\(template)")
            #expect(fileManager.fileExists(atPath: path.path(percentEncoded: false)), "Template \(template) should exist")
        }
    }

    @Test("installs every template into the project's local .eggs directory when --global is omitted")
    func installsAllTemplatesToProjectLocation() async throws {
        let (runner, env, projectDir, cleanup) = try await makeTestEnvironment()
        defer { cleanup() }
        let fixture = try makeGitTemplateFixture(in: projectDir)

        let result = try await runner.run(
            arguments: ["template", "install", fixture.repositoryURL, "--project-directory", projectDir.path(percentEncoded: false)],
            environment: env,
        )

        #expect(result.succeeded, "Expected success but got exit code \(result.exitCode): \(result.stderr)")

        for template in Self.knownTemplates {
            let path = projectDir.appending(path: ".eggs/\(template)")
            #expect(fileManager.fileExists(atPath: path.path(percentEncoded: false)), "Template \(template) should exist")
        }
    }

    @Test("--template SwiftModule installs only that template and skips iOSProjectGenTemplate")
    func installsSpecificTemplateUsingTemplateFilter() async throws {
        let (runner, env, projectDir, cleanup) = try await makeTestEnvironment()
        defer { cleanup() }
        let fixture = try makeGitTemplateFixture(in: projectDir)

        let result = try await runner.run(
            arguments: ["template", "install", fixture.repositoryURL, "--global", "--template", "SwiftModule", "--project-directory", projectDir.path(percentEncoded: false)],
            environment: env,
        )

        #expect(result.succeeded, "Expected success but got exit code \(result.exitCode): \(result.stderr)")

        let homeDir = try URL(filePath: #require(env["HOME"]))
        #expect(fileManager.fileExists(atPath: homeDir.appending(path: ".eggs/SwiftModule").path(percentEncoded: false)))
        #expect(!fileManager.fileExists(atPath: homeDir.appending(path: ".eggs/iOSProjectGenTemplate").path(percentEncoded: false)))
    }

    @Test("--exclude iOSProjectGenTemplate installs SwiftModule but skips the excluded template")
    func excludesSpecificTemplateUsingExcludeFilter() async throws {
        let (runner, env, projectDir, cleanup) = try await makeTestEnvironment()
        defer { cleanup() }
        let fixture = try makeGitTemplateFixture(in: projectDir)

        let result = try await runner.run(
            arguments: ["template", "install", fixture.repositoryURL, "--global", "--exclude", "iOSProjectGenTemplate", "--project-directory", projectDir.path(percentEncoded: false)],
            environment: env,
        )

        #expect(result.succeeded, "Expected success but got exit code \(result.exitCode): \(result.stderr)")

        let homeDir = try URL(filePath: #require(env["HOME"]))
        #expect(fileManager.fileExists(atPath: homeDir.appending(path: ".eggs/SwiftModule").path(percentEncoded: false)))
        #expect(!fileManager.fileExists(atPath: homeDir.appending(path: ".eggs/iOSProjectGenTemplate").path(percentEncoded: false)))
    }

    @Test("--branch main checks out and installs the template fixture from that branch")
    func installsFromSpecificBranch() async throws {
        let (runner, env, projectDir, cleanup) = try await makeTestEnvironment()
        defer { cleanup() }
        let fixture = try makeGitTemplateFixture(in: projectDir)

        let result = try await runner.run(
            arguments: ["template", "install", fixture.repositoryURL, "--global", "--branch", "main", "--template", "SwiftModule", "--project-directory", projectDir.path(percentEncoded: false)],
            environment: env,
        )

        #expect(result.succeeded, "Expected success but got exit code \(result.exitCode): \(result.stderr)")

        let homeDir = try URL(filePath: #require(env["HOME"]))
        #expect(fileManager.fileExists(atPath: homeDir.appending(path: ".eggs/SwiftModule").path(percentEncoded: false)))
    }

    @Test("--revision <sha> installs the template fixture pinned to that exact commit")
    func installsFromSpecificRevision() async throws {
        let (runner, env, projectDir, cleanup) = try await makeTestEnvironment()
        defer { cleanup() }
        let fixture = try makeGitTemplateFixture(in: projectDir)

        let result = try await runner.run(
            arguments: ["template", "install", fixture.repositoryURL, "--global", "--revision", fixture.revision, "--template", "SwiftModule", "--project-directory", projectDir.path(percentEncoded: false)],
            environment: env,
        )

        #expect(result.succeeded, "Expected success but got exit code \(result.exitCode): \(result.stderr)")

        let homeDir = try URL(filePath: #require(env["HOME"]))
        #expect(fileManager.fileExists(atPath: homeDir.appending(path: ".eggs/SwiftModule").path(percentEncoded: false)))
    }

    @Test("--force overwrites an existing template directory, replacing its prior marker file")
    func overwritesExistingTemplateWithForce() async throws {
        let (runner, env, projectDir, cleanup) = try await makeTestEnvironment()
        defer { cleanup() }
        let fixture = try makeGitTemplateFixture(in: projectDir)

        let homeDir = try URL(filePath: #require(env["HOME"]))
        let existingTemplate = homeDir.appending(path: ".eggs/SwiftModule")
        try fileManager.createDirectory(at: existingTemplate, withIntermediateDirectories: true)
        let markerFile = existingTemplate.appending(path: "marker.txt")
        try "original".write(to: markerFile, atomically: true, encoding: .utf8)

        let result = try await runner.run(
            arguments: ["template", "install", fixture.repositoryURL, "--global", "--template", "SwiftModule", "--force", "--project-directory", projectDir.path(percentEncoded: false)],
            environment: env,
        )

        #expect(result.succeeded, "Expected success but got exit code \(result.exitCode): \(result.stderr)")
        #expect(!fileManager.fileExists(atPath: markerFile.path(percentEncoded: false)), "Marker should be gone after overwrite")
    }

    @Test("without --force, install fails and leaves the existing template's marker file untouched")
    func skipsExistingTemplateWithoutForce() async throws {
        let (runner, env, projectDir, cleanup) = try await makeTestEnvironment()
        defer { cleanup() }
        let fixture = try makeGitTemplateFixture(in: projectDir)

        let homeDir = try URL(filePath: #require(env["HOME"]))
        let existingTemplate = homeDir.appending(path: ".eggs/SwiftModule")
        try fileManager.createDirectory(at: existingTemplate, withIntermediateDirectories: true)
        let markerFile = existingTemplate.appending(path: "marker.txt")
        try "original".write(to: markerFile, atomically: true, encoding: .utf8)

        let result = try await runner.run(
            arguments: ["template", "install", fixture.repositoryURL, "--global", "--template", "SwiftModule", "--project-directory", projectDir.path(percentEncoded: false)],
            environment: env,
        )

        #expect(!result.succeeded, "Expected failure when all templates skipped")
        #expect(fileManager.fileExists(atPath: markerFile.path(percentEncoded: false)), "Marker should still exist")
    }

    @Test("fails when the git repository URL points to a repository that does not exist")
    func failsWithNonExistentRepository() async throws {
        let (runner, env, projectDir, cleanup) = try await makeTestEnvironment()
        defer { cleanup() }

        let result = try await runner.run(
            arguments: ["template", "install", "git@github.com:nonexistent-user-12345/nonexistent-repo-67890.git", "--global", "--project-directory", projectDir.path(percentEncoded: false)],
            environment: env,
        )

        #expect(!result.succeeded)
    }

    @Test("fails when --branch references a branch that does not exist in the repository")
    func failsWithNonExistentBranch() async throws {
        let (runner, env, projectDir, cleanup) = try await makeTestEnvironment()
        defer { cleanup() }
        let fixture = try makeGitTemplateFixture(in: projectDir)

        let result = try await runner.run(
            arguments: ["template", "install", fixture.repositoryURL, "--global", "--branch", "nonexistent-branch-12345", "--project-directory", projectDir.path(percentEncoded: false)],
            environment: env,
        )

        #expect(!result.succeeded)
    }

    // MARK: - Global Install Manifest Registration

    @Test("install --global --tag registers an exact: requirement in eggs.yml, pins eggs-lock.yml, and a subsequent sync --global is a no-op")
    func globalInstallWithTagRegistersManifestAndSyncIsNoOp() async throws {
        let (runner, env, projectDir, cleanup) = try await makeTestEnvironment()
        defer { cleanup() }
        let repoURL = try makeTaggedGitRepository(in: projectDir, templateName: "SwiftModule", tag: "1.0.0")

        let install = try await runner.run(
            arguments: ["template", "install", repoURL, "--global", "--tag", "1.0.0", "--project-directory", projectDir.path(percentEncoded: false)],
            environment: env,
        )
        #expect(install.succeeded, "Expected success but got exit code \(install.exitCode): \(install.stderr)")
        #expect(install.stdout.contains("Registered in"))

        let homeDir = try URL(filePath: #require(env["HOME"]))
        #expect(fileManager.fileExists(atPath: homeDir.appending(path: ".eggs/SwiftModule").path(percentEncoded: false)))

        let manifestPath = homeDir.appending(path: ".config/egg/eggs.yml")
        let manifest = try String(contentsOf: manifestPath, encoding: .utf8)
        #expect(manifest.contains("exact: 1.0.0"))
        #expect(manifest.contains(repoURL))

        let lockPath = homeDir.appending(path: ".config/egg/eggs-lock.yml")
        #expect(fileManager.fileExists(atPath: lockPath.path(percentEncoded: false)))

        // sync --global re-reads the manifest/lock this install just wrote;
        // the pin already satisfies the requirement, so nothing re-resolves
        // or re-installs.
        let sync = try await runner.run(
            arguments: ["template", "sync", "--global", "--project-directory", projectDir.path(percentEncoded: false)],
            environment: env,
        )
        #expect(sync.succeeded, "Expected success but got exit code \(sync.exitCode): \(sync.stderr)")
    }

    @Test("install --global with no ref registers a revision: requirement resolved from HEAD")
    func globalInstallWithDefaultBranchRegistersRevision() async throws {
        let (runner, env, projectDir, cleanup) = try await makeTestEnvironment()
        defer { cleanup() }
        let fixture = try makeGitTemplateFixture(in: projectDir)

        let result = try await runner.run(
            arguments: ["template", "install", fixture.repositoryURL, "--global", "--template", "SwiftModule", "--project-directory", projectDir.path(percentEncoded: false)],
            environment: env,
        )
        #expect(result.succeeded, "Expected success but got exit code \(result.exitCode): \(result.stderr)")

        let homeDir = try URL(filePath: #require(env["HOME"]))
        let manifestPath = homeDir.appending(path: ".config/egg/eggs.yml")
        let manifest = try String(contentsOf: manifestPath, encoding: .utf8)
        #expect(manifest.contains("revision: \(fixture.revision)"))
    }

    @Test("install --project does not create any manifest")
    func projectInstallDoesNotRegisterManifest() async throws {
        let (runner, env, projectDir, cleanup) = try await makeTestEnvironment()
        defer { cleanup() }
        let fixture = try makeGitTemplateFixture(in: projectDir)

        let result = try await runner.run(
            arguments: ["template", "install", fixture.repositoryURL, "--project-directory", projectDir.path(percentEncoded: false)],
            environment: env,
        )
        #expect(result.succeeded, "Expected success but got exit code \(result.exitCode): \(result.stderr)")
        #expect(!result.stdout.contains("Registered in"))

        let homeDir = try URL(filePath: #require(env["HOME"]))
        #expect(!fileManager.fileExists(atPath: homeDir.appending(path: ".config/egg/eggs.yml").path(percentEncoded: false)))
        #expect(!fileManager.fileExists(atPath: projectDir.appending(path: "eggs.yml").path(percentEncoded: false)))
    }

    // MARK: - Local Path Installation

    @Test("installs both templates when given an absolute local directory path as the source")
    func installsTemplatesFromLocalAbsolutePath() async throws {
        let (runner, env, projectDir, cleanup) = try await makeTestEnvironment()
        defer { cleanup() }

        let sourceDir = projectDir.appending(path: "source-templates")
        try setupLocalTemplates(at: sourceDir, names: ["LocalTemplate1", "LocalTemplate2"])

        let result = try await runner.run(
            arguments: ["template", "install", sourceDir.path(percentEncoded: false), "--global", "--project-directory", projectDir.path(percentEncoded: false)],
            environment: env,
        )

        #expect(result.succeeded, "Expected success but got exit code \(result.exitCode): \(result.stderr)")

        let homeDir = try URL(filePath: #require(env["HOME"]))
        #expect(fileManager.fileExists(atPath: homeDir.appending(path: ".eggs/LocalTemplate1").path(percentEncoded: false)))
        #expect(fileManager.fileExists(atPath: homeDir.appending(path: ".eggs/LocalTemplate2").path(percentEncoded: false)))
    }

    @Test("resolves a ./-prefixed relative source path against the working directory to install the template")
    func installsTemplatesFromLocalRelativePathWith() async throws {
        let (runner, env, projectDir, cleanup) = try await makeTestEnvironment()
        defer { cleanup() }

        let sourceDir = projectDir.appending(path: "my-templates")
        try setupLocalTemplates(at: sourceDir, names: ["RelativePathTemplate"])

        let result = try await runner.run(
            arguments: ["template", "install", "./my-templates", "--global", "--project-directory", projectDir.path(percentEncoded: false)],
            workingDirectory: projectDir,
            environment: env,
        )

        #expect(result.succeeded, "Expected success but got exit code \(result.exitCode): \(result.stderr)")

        let homeDir = try URL(filePath: #require(env["HOME"]))
        #expect(fileManager.fileExists(atPath: homeDir.appending(path: ".eggs/RelativePathTemplate").path(percentEncoded: false)))
    }

    @Test("resolves a bare relative source path (no ./ prefix, with subdirectories) against the working directory to install the template")
    func installsTemplatesFromPlainRelativePathWithout() async throws {
        let (runner, env, projectDir, cleanup) = try await makeTestEnvironment()
        defer { cleanup() }

        let sourceDir = projectDir.appending(path: ".claude/plugins/my-plugin")
        try setupLocalTemplates(at: sourceDir, names: ["PluginTemplate"])

        let result = try await runner.run(
            arguments: ["template", "install", ".claude/plugins/my-plugin", "--global", "--project-directory", projectDir.path(percentEncoded: false)],
            workingDirectory: projectDir,
            environment: env,
        )

        #expect(result.succeeded, "Expected success but got exit code \(result.exitCode): \(result.stderr)")

        let homeDir = try URL(filePath: #require(env["HOME"]))
        #expect(fileManager.fileExists(atPath: homeDir.appending(path: ".eggs/PluginTemplate").path(percentEncoded: false)))
    }

    @Test("--template filter on a local-path source installs only the matching template and skips the rest")
    func installsTemplatesFromLocalPathWithFilter() async throws {
        let (runner, env, projectDir, cleanup) = try await makeTestEnvironment()
        defer { cleanup() }

        let sourceDir = projectDir.appending(path: "source-templates")
        try setupLocalTemplates(at: sourceDir, names: ["IncludedTemplate", "ExcludedTemplate"])

        let result = try await runner.run(
            arguments: ["template", "install", sourceDir.path(percentEncoded: false), "--global", "--template", "IncludedTemplate", "--project-directory", projectDir.path(percentEncoded: false)],
            environment: env,
        )

        #expect(result.succeeded, "Expected success but got exit code \(result.exitCode): \(result.stderr)")

        let homeDir = try URL(filePath: #require(env["HOME"]))
        #expect(fileManager.fileExists(atPath: homeDir.appending(path: ".eggs/IncludedTemplate").path(percentEncoded: false)))
        #expect(!fileManager.fileExists(atPath: homeDir.appending(path: ".eggs/ExcludedTemplate").path(percentEncoded: false)))
    }

    @Test("fails with an invalid-source error when the local source path does not exist")
    func failsWhenLocalPathDoesNotExist() async throws {
        let (runner, env, projectDir, cleanup) = try await makeTestEnvironment()
        defer { cleanup() }

        let nonExistentPath = projectDir.appending(path: "nonexistent-templates")

        let result = try await runner.run(
            arguments: ["template", "install", nonExistentPath.path(percentEncoded: false), "--global", "--project-directory", projectDir.path(percentEncoded: false)],
            environment: env,
        )

        #expect(!result.succeeded)
        let output = result.stderr + result.stdout
        #expect(output.lowercased().contains("invalid"), "Expected invalid source error but got: \(output)")
    }

    // MARK: - Helpers

    private func makeTestEnvironment() async throws -> (runner: CLIRunner, env: [String: String], projectDir: URL, cleanup: () -> Void) {
        let runner = try await CLIRunner()
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "cli-test-install")

        let homeDir = tempDir.appending(path: "home")
        let projectDir = tempDir.appending(path: "project")
        try fileManager.createDirectory(at: homeDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let env = ["HOME": homeDir.path(percentEncoded: false)]
        let cleanup: () -> Void = { [fileManager] in
            try? fileManager.removeItem(at: tempDir)
        }

        return (runner, env, projectDir, cleanup)
    }

    private func setupLocalTemplates(at directory: URL, names: [String]) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        for name in names {
            let templateDir = directory.appending(path: name)
            try fileManager.createDirectory(at: templateDir, withIntermediateDirectories: true)

            let configContent = """
            name: "\(name)"
            description: "A test template"
            hatch:
              output: "./output"
            """
            let configPath = templateDir.appending(path: "config.yml")
            try configContent.write(to: configPath, atomically: true, encoding: .utf8)
        }
    }

    private func makeGitTemplateFixture(in directory: URL) throws -> GitTemplateFixture {
        let repositoryDirectory = directory.appending(path: "git-template-fixture")
        try setupLocalTemplates(at: repositoryDirectory, names: Self.knownTemplates)
        try runGit(["init", "--initial-branch", "main"], in: repositoryDirectory)
        try runGit(["config", "user.name", "Egg E2E"], in: repositoryDirectory)
        try runGit(["config", "user.email", "egg-e2e@example.com"], in: repositoryDirectory)
        try runGit(["add", "."], in: repositoryDirectory)
        try runGit(["commit", "-m", "Add template fixtures"], in: repositoryDirectory)
        let revision = try runGit(["rev-parse", "HEAD"], in: repositoryDirectory)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return GitTemplateFixture(
            repositoryURL: repositoryDirectory.absoluteURL.standardizedFileURL.absoluteString,
            revision: revision,
        )
    }

    /// Creates a git repository containing one template, tagged so
    /// `install --tag` and the resulting `eggs.yml` registration have a
    /// real tag to resolve against.
    private func makeTaggedGitRepository(in directory: URL, templateName: String, tag: String) throws -> String {
        let repositoryDirectory = directory.appending(path: "tagged-git-fixture")
        try setupLocalTemplates(at: repositoryDirectory, names: [templateName])
        try runGit(["init", "--initial-branch", "main"], in: repositoryDirectory)
        try runGit(["config", "user.name", "Egg E2E"], in: repositoryDirectory)
        try runGit(["config", "user.email", "egg-e2e@example.com"], in: repositoryDirectory)
        try runGit(["add", "."], in: repositoryDirectory)
        try runGit(["commit", "-m", "Add template fixtures"], in: repositoryDirectory)
        try runGit(["tag", tag], in: repositoryDirectory)
        return repositoryDirectory.absoluteURL.standardizedFileURL.absoluteString
    }

    @discardableResult
    private func runGit(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        let stdout = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw GitFixtureError(arguments: arguments, exitCode: process.terminationStatus, stderr: stderr)
        }
        return stdout
    }
}

private struct GitTemplateFixture {
    let repositoryURL: String
    let revision: String
}

private struct GitFixtureError: LocalizedError {
    let arguments: [String]
    let exitCode: Int32
    let stderr: String

    var errorDescription: String? {
        "git \(arguments.joined(separator: " ")) failed with exit code \(exitCode): \(stderr)"
    }
}
