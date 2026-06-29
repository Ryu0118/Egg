import FileManagerProtocol
import Foundation
import Testing

@Suite(.buildBinary, .serialized)
struct TemplateInstallCommandTests {
    let fileManager: any FileManagerProtocol = FileManager.default

    // Test repository URL (HTTPS with token for CI, SSH for local development)
    static let testRepoOwner = "Ryu0118"
    static let testRepoName = "swift-egg-templates"

    static var testRepoURL: String {
        if let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"] {
            return "https://x-access-token:\(token)@github.com/\(testRepoOwner)/\(testRepoName).git"
        }
        return "git@github.com:\(testRepoOwner)/\(testRepoName).git"
    }

    /// Known templates in the test repository
    static let knownTemplates = ["SwiftModule", "iOSProjectGenTemplate"]
    /// Known commit SHA for revision tests
    static let knownCommitSHA = "8f65013501f58d2989eca79a20474c299b640e27"

    // MARK: - Help

    @Test
    func `--help shows install command help`() async throws {
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

    @Test
    func `fails with invalid URL`() async throws {
        let (runner, env, projectDir, cleanup) = try await makeTestEnvironment()
        defer { cleanup() }

        let result = try await runner.run(
            arguments: ["template", "install", "not-a-valid-url", "--global", "--project-directory", projectDir.path(percentEncoded: false)],
            environment: env,
        )

        #expect(!result.succeeded)
        #expect((result.stderr + result.stdout).contains("Invalid"))
    }

    @Test
    func `fails when using both --template and --exclude`() async throws {
        let (runner, env, projectDir, cleanup) = try await makeTestEnvironment()
        defer { cleanup() }

        let result = try await runner.run(
            arguments: ["template", "install", Self.testRepoURL, "--global", "--template", "Foo", "--exclude", "Bar", "--project-directory", projectDir.path(percentEncoded: false)],
            environment: env,
        )

        #expect(!result.succeeded)
        #expect((result.stderr + result.stdout).contains("Cannot use both"))
    }

    @Test
    func `fails when using --branch and --tag together`() async throws {
        let (runner, env, projectDir, cleanup) = try await makeTestEnvironment()
        defer { cleanup() }

        let result = try await runner.run(
            arguments: ["template", "install", Self.testRepoURL, "--global", "--branch", "main", "--tag", "v1.0", "--project-directory", projectDir.path(percentEncoded: false)],
            environment: env,
        )

        #expect(!result.succeeded)
        #expect((result.stderr + result.stdout).contains("Only one of"))
    }

    @Test
    func `fails when using --branch with local path`() async throws {
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

    @Test
    func `installs all templates to global location`() async throws {
        let (runner, env, projectDir, cleanup) = try await makeTestEnvironment()
        defer { cleanup() }

        let result = try await runner.run(
            arguments: ["template", "install", Self.testRepoURL, "--global", "--project-directory", projectDir.path(percentEncoded: false)],
            environment: env,
        )

        #expect(result.succeeded, "Expected success: \(result.stderr)")

        let homeDir = try URL(filePath: #require(env["HOME"]))
        for template in Self.knownTemplates {
            let path = homeDir.appending(path: ".eggs/\(template)")
            #expect(fileManager.fileExists(atPath: path.path(percentEncoded: false)), "Template \(template) should exist")
        }
    }

    @Test
    func `installs all templates to project location`() async throws {
        let (runner, env, projectDir, cleanup) = try await makeTestEnvironment()
        defer { cleanup() }

        let result = try await runner.run(
            arguments: ["template", "install", Self.testRepoURL, "--project-directory", projectDir.path(percentEncoded: false)],
            environment: env,
        )

        #expect(result.succeeded, "Expected success: \(result.stderr)")

        for template in Self.knownTemplates {
            let path = projectDir.appending(path: ".eggs/\(template)")
            #expect(fileManager.fileExists(atPath: path.path(percentEncoded: false)), "Template \(template) should exist")
        }
    }

    @Test
    func `installs specific template using --template filter`() async throws {
        let (runner, env, projectDir, cleanup) = try await makeTestEnvironment()
        defer { cleanup() }

        let result = try await runner.run(
            arguments: ["template", "install", Self.testRepoURL, "--global", "--template", "SwiftModule", "--project-directory", projectDir.path(percentEncoded: false)],
            environment: env,
        )

        #expect(result.succeeded, "Expected success: \(result.stderr)")

        let homeDir = try URL(filePath: #require(env["HOME"]))
        #expect(fileManager.fileExists(atPath: homeDir.appending(path: ".eggs/SwiftModule").path(percentEncoded: false)))
        #expect(!fileManager.fileExists(atPath: homeDir.appending(path: ".eggs/iOSProjectGenTemplate").path(percentEncoded: false)))
    }

    @Test
    func `excludes specific template using --exclude filter`() async throws {
        let (runner, env, projectDir, cleanup) = try await makeTestEnvironment()
        defer { cleanup() }

        let result = try await runner.run(
            arguments: ["template", "install", Self.testRepoURL, "--global", "--exclude", "iOSProjectGenTemplate", "--project-directory", projectDir.path(percentEncoded: false)],
            environment: env,
        )

        #expect(result.succeeded, "Expected success: \(result.stderr)")

        let homeDir = try URL(filePath: #require(env["HOME"]))
        #expect(fileManager.fileExists(atPath: homeDir.appending(path: ".eggs/SwiftModule").path(percentEncoded: false)))
        #expect(!fileManager.fileExists(atPath: homeDir.appending(path: ".eggs/iOSProjectGenTemplate").path(percentEncoded: false)))
    }

    @Test
    func `installs from specific branch`() async throws {
        let (runner, env, projectDir, cleanup) = try await makeTestEnvironment()
        defer { cleanup() }

        let result = try await runner.run(
            arguments: ["template", "install", Self.testRepoURL, "--global", "--branch", "main", "--template", "SwiftModule", "--project-directory", projectDir.path(percentEncoded: false)],
            environment: env,
        )

        #expect(result.succeeded, "Expected success: \(result.stderr)")

        let homeDir = try URL(filePath: #require(env["HOME"]))
        #expect(fileManager.fileExists(atPath: homeDir.appending(path: ".eggs/SwiftModule").path(percentEncoded: false)))
    }

    @Test
    func `installs from specific revision`() async throws {
        let (runner, env, projectDir, cleanup) = try await makeTestEnvironment()
        defer { cleanup() }

        let result = try await runner.run(
            arguments: ["template", "install", Self.testRepoURL, "--global", "--revision", Self.knownCommitSHA, "--template", "SwiftModule", "--project-directory", projectDir.path(percentEncoded: false)],
            environment: env,
        )

        #expect(result.succeeded, "Expected success: \(result.stderr)")

        let homeDir = try URL(filePath: #require(env["HOME"]))
        #expect(fileManager.fileExists(atPath: homeDir.appending(path: ".eggs/SwiftModule").path(percentEncoded: false)))
    }

    @Test
    func `overwrites existing template with --force`() async throws {
        let (runner, env, projectDir, cleanup) = try await makeTestEnvironment()
        defer { cleanup() }

        let homeDir = try URL(filePath: #require(env["HOME"]))
        let existingTemplate = homeDir.appending(path: ".eggs/SwiftModule")
        try fileManager.createDirectory(at: existingTemplate, withIntermediateDirectories: true)
        let markerFile = existingTemplate.appending(path: "marker.txt")
        try "original".write(to: markerFile, atomically: true, encoding: .utf8)

        let result = try await runner.run(
            arguments: ["template", "install", Self.testRepoURL, "--global", "--template", "SwiftModule", "--force", "--project-directory", projectDir.path(percentEncoded: false)],
            environment: env,
        )

        #expect(result.succeeded, "Expected success: \(result.stderr)")
        #expect(!fileManager.fileExists(atPath: markerFile.path(percentEncoded: false)), "Marker should be gone after overwrite")
    }

    @Test
    func `skips existing template without --force`() async throws {
        let (runner, env, projectDir, cleanup) = try await makeTestEnvironment()
        defer { cleanup() }

        let homeDir = try URL(filePath: #require(env["HOME"]))
        let existingTemplate = homeDir.appending(path: ".eggs/SwiftModule")
        try fileManager.createDirectory(at: existingTemplate, withIntermediateDirectories: true)
        let markerFile = existingTemplate.appending(path: "marker.txt")
        try "original".write(to: markerFile, atomically: true, encoding: .utf8)

        let result = try await runner.run(
            arguments: ["template", "install", Self.testRepoURL, "--global", "--template", "SwiftModule", "--project-directory", projectDir.path(percentEncoded: false)],
            environment: env,
        )

        #expect(!result.succeeded, "Expected failure when all templates skipped")
        #expect(fileManager.fileExists(atPath: markerFile.path(percentEncoded: false)), "Marker should still exist")
    }

    @Test
    func `fails with non-existent repository`() async throws {
        let (runner, env, projectDir, cleanup) = try await makeTestEnvironment()
        defer { cleanup() }

        let result = try await runner.run(
            arguments: ["template", "install", "git@github.com:nonexistent-user-12345/nonexistent-repo-67890.git", "--global", "--project-directory", projectDir.path(percentEncoded: false)],
            environment: env,
        )

        #expect(!result.succeeded)
    }

    @Test
    func `fails with non-existent branch`() async throws {
        let (runner, env, projectDir, cleanup) = try await makeTestEnvironment()
        defer { cleanup() }

        let result = try await runner.run(
            arguments: ["template", "install", Self.testRepoURL, "--global", "--branch", "nonexistent-branch-12345", "--project-directory", projectDir.path(percentEncoded: false)],
            environment: env,
        )

        #expect(!result.succeeded)
    }

    // MARK: - Local Path Installation

    @Test
    func `installs templates from local absolute path`() async throws {
        let (runner, env, projectDir, cleanup) = try await makeTestEnvironment()
        defer { cleanup() }

        let sourceDir = projectDir.appending(path: "source-templates")
        try setupLocalTemplates(at: sourceDir, names: ["LocalTemplate1", "LocalTemplate2"])

        let result = try await runner.run(
            arguments: ["template", "install", sourceDir.path(percentEncoded: false), "--global", "--project-directory", projectDir.path(percentEncoded: false)],
            environment: env,
        )

        #expect(result.succeeded, "Expected success: \(result.stderr)")

        let homeDir = try URL(filePath: #require(env["HOME"]))
        #expect(fileManager.fileExists(atPath: homeDir.appending(path: ".eggs/LocalTemplate1").path(percentEncoded: false)))
        #expect(fileManager.fileExists(atPath: homeDir.appending(path: ".eggs/LocalTemplate2").path(percentEncoded: false)))
    }

    @Test
    func `installs templates from local relative path with ./`() async throws {
        let (runner, env, projectDir, cleanup) = try await makeTestEnvironment()
        defer { cleanup() }

        let sourceDir = projectDir.appending(path: "my-templates")
        try setupLocalTemplates(at: sourceDir, names: ["RelativePathTemplate"])

        let result = try await runner.run(
            arguments: ["template", "install", "./my-templates", "--global", "--project-directory", projectDir.path(percentEncoded: false)],
            environment: env,
            workingDirectory: projectDir,
        )

        #expect(result.succeeded, "Expected success: \(result.stderr)")

        let homeDir = try URL(filePath: #require(env["HOME"]))
        #expect(fileManager.fileExists(atPath: homeDir.appending(path: ".eggs/RelativePathTemplate").path(percentEncoded: false)))
    }

    @Test
    func `installs templates from plain relative path without ./`() async throws {
        let (runner, env, projectDir, cleanup) = try await makeTestEnvironment()
        defer { cleanup() }

        let sourceDir = projectDir.appending(path: ".claude/plugins/my-plugin")
        try setupLocalTemplates(at: sourceDir, names: ["PluginTemplate"])

        let result = try await runner.run(
            arguments: ["template", "install", ".claude/plugins/my-plugin", "--global", "--project-directory", projectDir.path(percentEncoded: false)],
            environment: env,
            workingDirectory: projectDir,
        )

        #expect(result.succeeded, "Expected success: \(result.stderr)")

        let homeDir = try URL(filePath: #require(env["HOME"]))
        #expect(fileManager.fileExists(atPath: homeDir.appending(path: ".eggs/PluginTemplate").path(percentEncoded: false)))
    }

    @Test
    func `installs templates from local path with filter`() async throws {
        let (runner, env, projectDir, cleanup) = try await makeTestEnvironment()
        defer { cleanup() }

        let sourceDir = projectDir.appending(path: "source-templates")
        try setupLocalTemplates(at: sourceDir, names: ["IncludedTemplate", "ExcludedTemplate"])

        let result = try await runner.run(
            arguments: ["template", "install", sourceDir.path(percentEncoded: false), "--global", "--template", "IncludedTemplate", "--project-directory", projectDir.path(percentEncoded: false)],
            environment: env,
        )

        #expect(result.succeeded, "Expected success: \(result.stderr)")

        let homeDir = try URL(filePath: #require(env["HOME"]))
        #expect(fileManager.fileExists(atPath: homeDir.appending(path: ".eggs/IncludedTemplate").path(percentEncoded: false)))
        #expect(!fileManager.fileExists(atPath: homeDir.appending(path: ".eggs/ExcludedTemplate").path(percentEncoded: false)))
    }

    @Test
    func `fails when local path does not exist`() async throws {
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
        let cleanup = { [fileManager] in
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
}
