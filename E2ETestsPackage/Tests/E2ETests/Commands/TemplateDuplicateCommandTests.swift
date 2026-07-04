import FileManagerProtocol
import Foundation
import Testing

@Suite(.buildBinary, .serialized)
struct TemplateDuplicateCommandTests {
    let fileManager: any FileManagerProtocol = FileManager.default

    @Test("--help shows duplicate command help")
    func helpShowsDuplicateCommandHelp() async throws {
        let runner = try await CLIRunner()
        let result = try await runner.run("template", "duplicate", "--help")

        #expect(result.succeeded)
        #expect(result.stdout.contains("OVERVIEW: Duplicate an existing template"))
        #expect(result.stdout.contains("USAGE: egg template duplicate"))
        #expect(result.stdout.contains("<template-name>"))
        #expect(result.stdout.contains("--name"))
        #expect(result.stdout.contains("--description"))
        #expect(result.stdout.contains("--project-directory"))
        #expect(result.stdout.contains("--template-search-paths"))
    }

    @Test(
        "duplicates a template under a new name while preserving the original, failing when the source is missing or the target name is taken",
        arguments: TestCase.allCases,
    )
    func duplicateTemplate(_ testCase: TestCase) async throws {
        let runner = try await CLIRunner()
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "cli-test-duplicate")
        defer { try? fileManager.removeItem(at: tempDir) }

        let homeDir = tempDir.appending(path: "home")
        let projectDir = tempDir.appending(path: "project")
        try fileManager.createDirectory(at: homeDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: projectDir, withIntermediateDirectories: true)

        // Setup templates
        try setupTemplates(
            testCase.templates,
            homeDir: homeDir,
            projectDir: projectDir,
        )

        let arguments = testCase.buildArguments(projectDir: projectDir)
        let environment = ["HOME": homeDir.path(percentEncoded: false)]

        let result = try await runner.run(
            arguments: arguments,
            environment: environment,
        )

        switch testCase.expected {
        case .success:
            #expect(result.succeeded, "Expected success but got exit code \(result.exitCode): \(result.stderr)")
            try verifyDuplication(
                testCase: testCase,
                homeDir: homeDir,
                projectDir: projectDir,
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
        projectDir: URL,
    ) throws {
        for template in templates {
            let templateDir: URL = switch template.location {
            case .global:
                homeDir.appending(path: ".eggs/\(template.name)")
            case .project:
                projectDir.appending(path: ".eggs/\(template.name)")
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

    private func verifyDuplication(
        testCase: TestCase,
        homeDir: URL,
        projectDir: URL,
    ) throws {
        guard let verification = testCase.verification else { return }

        // Verify original still exists
        let originalDir: URL = switch verification.originalLocation {
        case .global:
            homeDir.appending(path: ".eggs/\(verification.originalName)")
        case .project:
            projectDir.appending(path: ".eggs/\(verification.originalName)")
        }
        #expect(fileManager.fileExists(atPath: originalDir.path(percentEncoded: false)),
                "Original template should still exist at \(originalDir.path)")

        // Verify duplicate was created
        let duplicateDir: URL = switch verification.duplicateLocation {
        case .global:
            homeDir.appending(path: ".eggs/\(verification.duplicateName)")
        case .project:
            projectDir.appending(path: ".eggs/\(verification.duplicateName)")
        }
        #expect(fileManager.fileExists(atPath: duplicateDir.path(percentEncoded: false)),
                "Duplicate template should exist at \(duplicateDir.path)")

        // Verify config.yml was created with new name
        let configPath = duplicateDir.appending(path: "config.yml")
        #expect(fileManager.fileExists(atPath: configPath.path(percentEncoded: false)),
                "config.yml should exist in duplicate")

        // Verify template content was copied
        let templateContentsDir = duplicateDir.appending(path: "template")
        #expect(fileManager.fileExists(atPath: templateContentsDir.path(percentEncoded: false)),
                "template directory should exist in duplicate")
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let templates: [TemplateSetup]
        let sourceTemplate: String
        let newName: String
        let newDescription: String
        let expected: Expected
        let verification: Verification?

        static let allCases: [TestCase] = [
            // Success cases
            TestCase(
                description: "duplicates global template",
                templates: [
                    TemplateSetup(name: "OriginalTemplate", description: "Original template", location: .global),
                ],
                sourceTemplate: "OriginalTemplate",
                newName: "DuplicatedTemplate",
                newDescription: "A duplicated template",
                expected: .success,
                verification: Verification(
                    originalName: "OriginalTemplate",
                    originalLocation: .global,
                    duplicateName: "DuplicatedTemplate",
                    duplicateLocation: .global,
                ),
            ),
            TestCase(
                description: "duplicates project template",
                templates: [
                    TemplateSetup(name: "ProjectOriginal", description: "Project original", location: .project),
                ],
                sourceTemplate: "ProjectOriginal",
                newName: "ProjectDuplicate",
                newDescription: "A duplicated project template",
                expected: .success,
                verification: Verification(
                    originalName: "ProjectOriginal",
                    originalLocation: .project,
                    duplicateName: "ProjectDuplicate",
                    duplicateLocation: .project,
                ),
            ),

            // Error cases
            TestCase(
                description: "fails when source template does not exist",
                templates: [],
                sourceTemplate: "NonExistentTemplate",
                newName: "NewTemplate",
                newDescription: "New description",
                expected: .failure(errorContains: "not found"),
                verification: nil,
            ),
            TestCase(
                description: "fails when target name already exists",
                templates: [
                    TemplateSetup(name: "OriginalTemplate", description: "Original", location: .global),
                    TemplateSetup(name: "ExistingTemplate", description: "Existing", location: .global),
                ],
                sourceTemplate: "OriginalTemplate",
                newName: "ExistingTemplate",
                newDescription: "Trying to overwrite",
                expected: .failure(errorContains: "already exists"),
                verification: nil,
            ),
        ]

        func buildArguments(projectDir: URL) -> [String] {
            [
                "template", "duplicate", sourceTemplate,
                "--name", newName,
                "--description", newDescription,
                "--project-directory", projectDir.path(percentEncoded: false),
            ]
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
            let originalName: String
            let originalLocation: Location
            let duplicateName: String
            let duplicateLocation: Location
        }

        var testDescription: String {
            description
        }
    }
}
