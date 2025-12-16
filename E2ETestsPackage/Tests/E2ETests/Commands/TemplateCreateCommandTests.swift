import FileManagerProtocol
import Foundation
import Testing

@Suite(.buildBinary, .serialized)
struct TemplateCreateCommandTests {
    let fileManager: any FileManagerProtocol = FileManager.default

    // MARK: - Help Tests

    @Test("--help shows create command help")
    func helpFlag() async throws {
        let runner = try await CLIRunner()
        let result = try await runner.run("template", "create", "--help")

        #expect(result.succeeded)
        #expect(result.stdout.contains("OVERVIEW: Create a new template"))
        #expect(result.stdout.contains("USAGE: egg template create"))
        #expect(result.stdout.contains("--name"))
        #expect(result.stdout.contains("--description"))
        #expect(result.stdout.contains("--location"))
        #expect(result.stdout.contains("--skip-config"))
    }

    // MARK: - Parameterized Tests

    @Test(arguments: TestCase.allCases)
    func createTemplate(_ testCase: TestCase) async throws {
        let runner = try await CLIRunner()
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "cli-test-create")
        defer { try? fileManager.removeItem(at: tempDir) }

        let homeDir = tempDir.appending(path: "home")
        let projectDir = tempDir.appending(path: "project")
        try fileManager.createDirectory(at: homeDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: projectDir, withIntermediateDirectories: true)

        // Setup existing templates if needed
        for templateName in testCase.existingTemplates {
            let globalPath = homeDir.appending(path: ".eggs/\(templateName)")
            try fileManager.createDirectory(at: globalPath, withIntermediateDirectories: true)
        }

        let arguments = testCase.buildArguments(projectDir: projectDir)
        let environment = ["HOME": homeDir.path(percentEncoded: false)]

        let result = try await runner.run(
            arguments: arguments,
            environment: environment
        )

        switch testCase.expected {
        case .success:
            #expect(result.succeeded, "Expected success but got exit code \(result.exitCode): \(result.stderr)")
            try verifySuccess(
                testCase: testCase,
                homeDir: homeDir,
                projectDir: projectDir
            )
        case let .failure(errorContains):
            #expect(!result.succeeded, "Expected failure but command succeeded")
            let output = result.stderr + result.stdout
            #expect(output.contains(errorContains), "Expected error containing '\(errorContains)' but got: \(output)")
        }
    }

    private func verifySuccess(
        testCase: TestCase,
        homeDir: URL,
        projectDir: URL
    ) throws {
        guard let verification = testCase.verification else { return }

        let templateDir: URL
        switch verification.location {
        case .global:
            templateDir = homeDir.appending(path: ".eggs/\(verification.templateName)")
        case .project:
            templateDir = projectDir.appending(path: ".eggs/\(verification.templateName)")
        }

        #expect(fileManager.fileExists(atPath: templateDir.path(percentEncoded: false)),
                "Template directory should exist at \(templateDir.path)")

        if verification.expectConfig {
            let configPath = templateDir.appending(path: "config.yml")
            #expect(fileManager.fileExists(atPath: configPath.path(percentEncoded: false)),
                    "config.yml should exist")
        }

        if verification.expectNoConfig {
            let configPath = templateDir.appending(path: "config.yml")
            #expect(!fileManager.fileExists(atPath: configPath.path(percentEncoded: false)),
                    "config.yml should NOT exist")
        }

        if verification.expectTemplateDir {
            // CLI creates template files directly in template directory (no "template" subdirectory)
            // Verify a default template file exists instead
            let defaultFilePath = templateDir.appending(path: "___FILE_NAME___View.swift")
            #expect(fileManager.fileExists(atPath: defaultFilePath.path(percentEncoded: false)),
                    "default template file should exist")
        }
    }

    // MARK: - Test Case Definition

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let name: String
        let templateDescription: String
        let location: Location
        let skipConfig: Bool
        let existingTemplates: [String]
        let expected: Expected
        let verification: Verification?

        var testDescription: String { description }

        func buildArguments(projectDir: URL) -> [String] {
            var args = [
                "template", "create",
                "--name", name,
                "--description", templateDescription,
                "--location", location.rawValue
            ]
            if location == .project {
                args += ["--project-directory", projectDir.path(percentEncoded: false)]
            }
            if skipConfig {
                args.append("--skip-config")
            }
            return args
        }

        enum Location: String {
            case global
            case project
        }

        enum Expected {
            case success
            case failure(errorContains: String)
        }

        struct Verification {
            let templateName: String
            let location: Location
            let expectConfig: Bool
            let expectNoConfig: Bool
            let expectTemplateDir: Bool

            init(
                templateName: String,
                location: Location,
                expectConfig: Bool = true,
                expectNoConfig: Bool = false,
                expectTemplateDir: Bool = true
            ) {
                self.templateName = templateName
                self.location = location
                self.expectConfig = expectConfig
                self.expectNoConfig = expectNoConfig
                self.expectTemplateDir = expectTemplateDir
            }
        }

        static let allCases: [TestCase] = [
            // Success cases
            TestCase(
                description: "creates template in global location",
                name: "GlobalTemplate",
                templateDescription: "A global test template",
                location: .global,
                skipConfig: false,
                existingTemplates: [],
                expected: .success,
                verification: Verification(
                    templateName: "GlobalTemplate",
                    location: .global
                )
            ),
            TestCase(
                description: "creates template in project location",
                name: "ProjectTemplate",
                templateDescription: "A project test template",
                location: .project,
                skipConfig: false,
                existingTemplates: [],
                expected: .success,
                verification: Verification(
                    templateName: "ProjectTemplate",
                    location: .project
                )
            ),
            TestCase(
                description: "creates template without config.yml when --skip-config is used",
                name: "NoConfigTemplate",
                templateDescription: "Template without config",
                location: .global,
                skipConfig: true,
                existingTemplates: [],
                expected: .success,
                verification: Verification(
                    templateName: "NoConfigTemplate",
                    location: .global,
                    expectConfig: false,
                    expectNoConfig: true
                )
            ),

            // Error cases
            TestCase(
                description: "fails when template already exists",
                name: "ExistingTemplate",
                templateDescription: "Duplicate template",
                location: .global,
                skipConfig: false,
                existingTemplates: ["ExistingTemplate"],
                expected: .failure(errorContains: "already exists"),
                verification: nil
            ),
        ]
    }
}
