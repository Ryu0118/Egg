import FileManagerProtocol
import Foundation
import Testing

@Suite(.buildBinary, .serialized)
struct TemplateDeleteCommandTests {
    let fileManager: any FileManagerProtocol = FileManager.default

    @Test("--help shows delete command help")
    func helpFlag() async throws {
        let runner = try await CLIRunner()
        let result = try await runner.run("template", "delete", "--help")

        #expect(result.succeeded)
        #expect(result.stdout.contains("OVERVIEW: Delete a template"))
        #expect(result.stdout.contains("USAGE: egg template delete"))
        #expect(result.stdout.contains("<template-name>"))
        #expect(result.stdout.contains("--force"))
        #expect(result.stdout.contains("--project-directory"))
        #expect(result.stdout.contains("--template-search-paths"))
    }

    @Test(arguments: TestCase.allCases)
    func deleteTemplate(_ testCase: TestCase) async throws {
        let runner = try await CLIRunner()
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "cli-test-delete")
        defer { try? fileManager.removeItem(at: tempDir) }

        let homeDir = tempDir.appending(path: "home")
        let projectDir = tempDir.appending(path: "project")
        try fileManager.createDirectory(at: homeDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: projectDir, withIntermediateDirectories: true)

        // Setup templates
        try setupTemplates(
            testCase.templates,
            homeDir: homeDir,
            projectDir: projectDir
        )

        let arguments = testCase.buildArguments(projectDir: projectDir)
        let environment = ["HOME": homeDir.path(percentEncoded: false)]

        let result = try await runner.run(
            arguments: arguments,
            environment: environment
        )

        switch testCase.expected {
        case .success:
            #expect(result.succeeded, "Expected success but got exit code \(result.exitCode): \(result.stderr)")
            try verifyDeletion(
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

    private func setupTemplates(
        _ templates: [TestCase.TemplateSetup],
        homeDir: URL,
        projectDir: URL
    ) throws {
        for template in templates {
            let templateDir: URL
            switch template.location {
            case .global:
                templateDir = homeDir.appending(path: ".eggs/\(template.name)")
            case .project:
                templateDir = projectDir.appending(path: ".eggs/\(template.name)")
            }

            try fileManager.createDirectory(at: templateDir, withIntermediateDirectories: true)

            let configContent = """
            name: \(template.name)
            description: \(template.description)
            """
            let configPath = templateDir.appending(path: "config.yml")
            try configContent.write(to: configPath, atomically: true, encoding: .utf8)
        }
    }

    private func verifyDeletion(
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

        #expect(!fileManager.fileExists(atPath: templateDir.path(percentEncoded: false)),
                "Template directory should have been deleted at \(templateDir.path)")
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let templates: [TemplateSetup]
        let templateToDelete: String
        let force: Bool
        let expected: Expected
        let verification: Verification?

        var testDescription: String { description }

        func buildArguments(projectDir: URL) -> [String] {
            var args = ["template", "delete", templateToDelete]
            args += ["--project-directory", projectDir.path(percentEncoded: false)]
            if force {
                args.append("--force")
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

        struct TemplateSetup {
            let name: String
            let description: String
            let location: Location
        }

        struct Verification {
            let templateName: String
            let location: Location
        }

        static let allCases: [TestCase] = [
            // Success cases
            TestCase(
                description: "deletes global template with --force flag",
                templates: [
                    TemplateSetup(name: "TestTemplate", description: "A test template", location: .global),
                ],
                templateToDelete: "TestTemplate",
                force: true,
                expected: .success,
                verification: Verification(templateName: "TestTemplate", location: .global)
            ),
            TestCase(
                description: "deletes project template with --force flag",
                templates: [
                    TemplateSetup(name: "ProjectTemplate", description: "A project template", location: .project),
                ],
                templateToDelete: "ProjectTemplate",
                force: true,
                expected: .success,
                verification: Verification(templateName: "ProjectTemplate", location: .project)
            ),

            // Error cases
            TestCase(
                description: "fails when template does not exist",
                templates: [],
                templateToDelete: "NonExistentTemplate",
                force: true,
                expected: .failure(errorContains: "not found"),
                verification: nil
            ),
        ]
    }
}
