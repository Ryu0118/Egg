import FileManagerProtocol
import Foundation
import Testing

@Suite(.buildBinary, .serialized)
struct TemplateListCommandTests {
    let fileManager: any FileManagerProtocol = FileManager.default

    @Test
    func `--help shows list command help`() async throws {
        let runner = try await CLIRunner()
        let result = try await runner.run("template", "list", "--help")

        #expect(result.succeeded)
        #expect(result.stdout.contains("OVERVIEW: List all available templates"))
        #expect(result.stdout.contains("USAGE: egg template list"))
        #expect(result.stdout.contains("--location"))
        #expect(result.stdout.contains("--project-directory"))
        #expect(result.stdout.contains("--hide-description"))
        #expect(result.stdout.contains("--template-search-paths"))
    }

    @Test(arguments: TestCase.allCases)
    func `list templates`(_ testCase: TestCase) async throws {
        let runner = try await CLIRunner()
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "cli-test-list")
        defer { try? fileManager.removeItem(at: tempDir) }

        let homeDir = tempDir.appending(path: "home")
        let projectDir = tempDir.appending(path: "project")
        let customDir = tempDir.appending(path: "custom")
        try fileManager.createDirectory(at: homeDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: projectDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: customDir, withIntermediateDirectories: true)

        // Setup templates
        try setupTemplates(
            testCase.templates,
            homeDir: homeDir,
            projectDir: projectDir,
            customDir: customDir,
        )

        let customDirForArgs = testCase.useCustomSearchPath ? customDir : nil
        let arguments = testCase.buildArguments(projectDir: projectDir, customDir: customDirForArgs)
        let environment = ["HOME": homeDir.path(percentEncoded: false)]

        let result = try await runner.run(
            arguments: arguments,
            environment: environment,
        )

        #expect(result.succeeded, "Expected success but got exit code \(result.exitCode): \(result.stderr)")

        // Verify expected outputs
        for expectedOutput in testCase.expectedOutputContains {
            #expect(result.stdout.contains(expectedOutput),
                    "Expected output to contain '\(expectedOutput)' but got: \(result.stdout)")
        }

        // Verify unexpected outputs
        for unexpectedOutput in testCase.expectedOutputNotContains {
            #expect(!result.stdout.contains(unexpectedOutput),
                    "Expected output NOT to contain '\(unexpectedOutput)' but it did: \(result.stdout)")
        }
    }

    private func setupTemplates(
        _ templates: [TestCase.TemplateSetup],
        homeDir: URL,
        projectDir: URL,
        customDir: URL,
    ) throws {
        for template in templates {
            let templateDir: URL = switch template.location {
            case .global:
                homeDir.appending(path: ".eggs/\(template.name)")
            case .project:
                projectDir.appending(path: ".eggs/\(template.name)")
            case .custom:
                customDir.appending(path: template.name)
            case .customRoot:
                customDir
            }

            if !fileManager.fileExists(atPath: templateDir.path(percentEncoded: false)) {
                try fileManager.createDirectory(at: templateDir, withIntermediateDirectories: true)
            }

            // Config must include required 'hatch' section with 'output' field
            let configContent = """
            name: \(template.name)
            description: \(template.description)
            hatch:
              output: .
            """
            let configPath = templateDir.appending(path: "config.yml")
            try configContent.write(to: configPath, atomically: true, encoding: .utf8)
        }
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let templates: [TemplateSetup]
        let locationFilter: Location?
        let hideDescription: Bool
        let expectedOutputContains: [String]
        let expectedOutputNotContains: [String]
        let useCustomSearchPath: Bool

        var testDescription: String {
            description
        }

        init(
            description: String,
            templates: [TemplateSetup],
            locationFilter: Location?,
            hideDescription: Bool,
            expectedOutputContains: [String],
            expectedOutputNotContains: [String],
            useCustomSearchPath: Bool = false,
        ) {
            self.description = description
            self.templates = templates
            self.locationFilter = locationFilter
            self.hideDescription = hideDescription
            self.expectedOutputContains = expectedOutputContains
            self.expectedOutputNotContains = expectedOutputNotContains
            self.useCustomSearchPath = useCustomSearchPath
        }

        func buildArguments(projectDir: URL, customDir: URL? = nil) -> [String] {
            var args = ["template", "list"]
            args += ["--project-directory", projectDir.path(percentEncoded: false)]

            if let location = locationFilter {
                args += ["--location", location.rawValue]
            }
            if hideDescription {
                args.append("--hide-description")
            }
            if let customDir {
                args += ["--template-search-paths", customDir.path(percentEncoded: false)]
            }
            return args
        }

        enum Location: String {
            case global
            case project
        }

        struct TemplateSetup {
            let name: String
            let description: String
            let location: LocationKind

            enum LocationKind {
                case global
                case project
                case custom
                case customRoot
            }
        }

        static let allCases: [TestCase] = [
            // Empty list
            TestCase(
                description: "shows no templates when none exist",
                templates: [],
                locationFilter: nil,
                hideDescription: false,
                expectedOutputContains: [],
                expectedOutputNotContains: [],
            ),

            // Basic listing
            TestCase(
                description: "lists existing global template",
                templates: [
                    TemplateSetup(name: "TestTemplate", description: "A test template", location: .global),
                ],
                locationFilter: nil,
                hideDescription: false,
                expectedOutputContains: ["TestTemplate"],
                expectedOutputNotContains: [],
            ),
            TestCase(
                description: "lists existing project template",
                templates: [
                    TemplateSetup(name: "ProjectTemplate", description: "A project template", location: .project),
                ],
                locationFilter: nil,
                hideDescription: false,
                expectedOutputContains: ["ProjectTemplate"],
                expectedOutputNotContains: [],
            ),
            TestCase(
                description: "lists multiple templates from both locations",
                templates: [
                    TemplateSetup(name: "GlobalTemplate", description: "Global template", location: .global),
                    TemplateSetup(name: "ProjectTemplate", description: "Project template", location: .project),
                ],
                locationFilter: nil,
                hideDescription: false,
                expectedOutputContains: ["GlobalTemplate", "ProjectTemplate"],
                expectedOutputNotContains: [],
            ),

            // Location filter tests
            TestCase(
                description: "filters by global location",
                templates: [
                    TemplateSetup(name: "GlobalTemplate", description: "Global template", location: .global),
                    TemplateSetup(name: "ProjectTemplate", description: "Project template", location: .project),
                ],
                locationFilter: .global,
                hideDescription: false,
                expectedOutputContains: ["GlobalTemplate"],
                expectedOutputNotContains: ["ProjectTemplate"],
            ),
            TestCase(
                description: "filters by project location",
                templates: [
                    TemplateSetup(name: "GlobalTemplate", description: "Global template", location: .global),
                    TemplateSetup(name: "ProjectTemplate", description: "Project template", location: .project),
                ],
                locationFilter: .project,
                hideDescription: false,
                expectedOutputContains: ["ProjectTemplate"],
                expectedOutputNotContains: ["GlobalTemplate"],
            ),

            // Hide description tests
            TestCase(
                description: "hides description column when --hide-description is used",
                templates: [
                    TemplateSetup(name: "TestTemplate", description: "UniqueDescriptionText", location: .global),
                ],
                locationFilter: nil,
                hideDescription: true,
                expectedOutputContains: ["TestTemplate"],
                expectedOutputNotContains: ["UniqueDescriptionText"],
            ),

            // Custom search paths tests
            TestCase(
                description: "lists template from custom search path",
                templates: [
                    TemplateSetup(name: "CustomTemplate", description: "A custom path template", location: .custom),
                ],
                locationFilter: nil,
                hideDescription: false,
                expectedOutputContains: ["CustomTemplate"],
                expectedOutputNotContains: [],
                useCustomSearchPath: true,
            ),
            TestCase(
                description: "lists templates from all locations including custom",
                templates: [
                    TemplateSetup(name: "GlobalTemplate", description: "Global template", location: .global),
                    TemplateSetup(name: "ProjectTemplate", description: "Project template", location: .project),
                    TemplateSetup(name: "CustomTemplate", description: "Custom template", location: .custom),
                ],
                locationFilter: nil,
                hideDescription: false,
                expectedOutputContains: ["GlobalTemplate", "ProjectTemplate", "CustomTemplate"],
                expectedOutputNotContains: [],
                useCustomSearchPath: true,
            ),
            TestCase(
                description: "does not list custom template when search path not provided",
                templates: [
                    TemplateSetup(name: "GlobalTemplate", description: "Global template", location: .global),
                    TemplateSetup(name: "CustomOnlyTemplate", description: "Custom template", location: .custom),
                ],
                locationFilter: nil,
                hideDescription: false,
                expectedOutputContains: ["GlobalTemplate"],
                expectedOutputNotContains: ["CustomOnlyTemplate"],
                useCustomSearchPath: false,
            ),

            // Custom search path pointing directly to a template root
            TestCase(
                description: "lists template when custom search path points to template root",
                templates: [
                    TemplateSetup(name: "CustomRootTemplate", description: "Root-level template", location: .customRoot),
                ],
                locationFilter: nil,
                hideDescription: false,
                expectedOutputContains: ["CustomRootTemplate"],
                expectedOutputNotContains: [],
                useCustomSearchPath: true,
            ),
        ]
    }
}
