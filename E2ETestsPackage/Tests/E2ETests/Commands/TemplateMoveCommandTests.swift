import FileManagerProtocol
import Foundation
import Testing

@Suite(.buildBinary, .serialized)
struct TemplateMoveCommandTests {
    let fileManager: any FileManagerProtocol = FileManager.default

    @Test("--help shows move command help")
    func helpFlag() async throws {
        let runner = try await CLIRunner()
        let result = try await runner.run("template", "move", "--help")

        #expect(result.succeeded)
        #expect(result.stdout.contains("OVERVIEW: Move a template"))
        #expect(result.stdout.contains("USAGE: egg template move"))
        #expect(result.stdout.contains("<template-name>"))
        #expect(result.stdout.contains("--to"))
        #expect(result.stdout.contains("--force"))
        #expect(result.stdout.contains("--project-directory"))
        #expect(result.stdout.contains("--template-search-paths"))
    }

    @Test(arguments: TestCase.allCases)
    func moveTemplate(_ testCase: TestCase) async throws {
        let runner = try await CLIRunner()
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "cli-test-move")
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
            try verifyMove(
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
            hatch:
              output: .
            """
            let configPath = templateDir.appending(path: "config.yml")
            try configContent.write(to: configPath, atomically: true, encoding: .utf8)

            // Create template directory with a test file
            let templateContentsDir = templateDir.appending(path: "template")
            try fileManager.createDirectory(at: templateContentsDir, withIntermediateDirectories: true)

            let testFilePath = templateContentsDir.appending(path: "test.txt")
            try "Test content for \(template.name)".write(to: testFilePath, atomically: true, encoding: .utf8)
        }
    }

    private func verifyMove(
        testCase: TestCase,
        homeDir: URL,
        projectDir: URL
    ) throws {
        guard let verification = testCase.verification else { return }

        // Verify source no longer exists
        let sourceDir: URL
        switch verification.sourceLocation {
        case .global:
            sourceDir = homeDir.appending(path: ".eggs/\(verification.templateName)")
        case .project:
            sourceDir = projectDir.appending(path: ".eggs/\(verification.templateName)")
        }
        #expect(!fileManager.fileExists(atPath: sourceDir.path(percentEncoded: false)),
                "Source template should no longer exist at \(sourceDir.path)")

        // Verify target exists
        let targetDir: URL
        switch verification.targetLocation {
        case .global:
            targetDir = homeDir.appending(path: ".eggs/\(verification.templateName)")
        case .project:
            targetDir = projectDir.appending(path: ".eggs/\(verification.templateName)")
        }
        #expect(fileManager.fileExists(atPath: targetDir.path(percentEncoded: false)),
                "Target template should exist at \(targetDir.path)")

        // Verify config.yml exists at target
        let configPath = targetDir.appending(path: "config.yml")
        #expect(fileManager.fileExists(atPath: configPath.path(percentEncoded: false)),
                "config.yml should exist at target")

        // Verify template content was moved
        let templateContentsDir = targetDir.appending(path: "template")
        #expect(fileManager.fileExists(atPath: templateContentsDir.path(percentEncoded: false)),
                "template directory should exist at target")
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let templates: [TemplateSetup]
        let templateToMove: String
        let targetLocation: Location
        let force: Bool
        let expected: Expected
        let verification: Verification?

        var testDescription: String { description }

        func buildArguments(projectDir: URL) -> [String] {
            var args = [
                "template", "move", templateToMove,
                "--to", targetLocation.rawValue,
                "--project-directory", projectDir.path(percentEncoded: false),
            ]
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
            let sourceLocation: Location
            let targetLocation: Location
        }

        static let allCases: [TestCase] = [
            // Success cases
            TestCase(
                description: "moves template from global to project",
                templates: [
                    TemplateSetup(name: "GlobalTemplate", description: "A global template", location: .global),
                ],
                templateToMove: "GlobalTemplate",
                targetLocation: .project,
                force: false,
                expected: .success,
                verification: Verification(
                    templateName: "GlobalTemplate",
                    sourceLocation: .global,
                    targetLocation: .project
                )
            ),
            TestCase(
                description: "moves template from project to global",
                templates: [
                    TemplateSetup(name: "ProjectTemplate", description: "A project template", location: .project),
                ],
                templateToMove: "ProjectTemplate",
                targetLocation: .global,
                force: false,
                expected: .success,
                verification: Verification(
                    templateName: "ProjectTemplate",
                    sourceLocation: .project,
                    targetLocation: .global
                )
            ),
            TestCase(
                description: "overwrites target when --force is used",
                templates: [
                    TemplateSetup(name: "MyTemplate", description: "Source template", location: .global),
                    TemplateSetup(name: "MyTemplate", description: "Target template", location: .project),
                ],
                templateToMove: "MyTemplate",
                targetLocation: .project,
                force: true,
                expected: .success,
                verification: Verification(
                    templateName: "MyTemplate",
                    sourceLocation: .global,
                    targetLocation: .project
                )
            ),

            // Error cases
            TestCase(
                description: "fails when template does not exist",
                templates: [],
                templateToMove: "NonExistentTemplate",
                targetLocation: .project,
                force: false,
                expected: .failure(errorContains: "not found"),
                verification: nil
            ),
            TestCase(
                description: "fails when target already exists without --force",
                templates: [
                    TemplateSetup(name: "MyTemplate", description: "Source template", location: .global),
                    TemplateSetup(name: "MyTemplate", description: "Target template", location: .project),
                ],
                templateToMove: "MyTemplate",
                targetLocation: .project,
                force: false,
                expected: .failure(errorContains: "already exists"),
                verification: nil
            ),
        ]
    }
}
