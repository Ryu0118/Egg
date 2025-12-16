import FileManagerProtocol
import Foundation
import Testing

@Suite(.buildBinary, .serialized)
struct TemplateValidateCommandTests {
    let fileManager: any FileManagerProtocol = FileManager.default

    @Test("--help shows validate command help")
    func helpFlag() async throws {
        let runner = try await CLIRunner()
        let result = try await runner.run("template", "validate", "--help")

        #expect(result.succeeded)
        #expect(result.stdout.contains("OVERVIEW: Validate a template's config.yaml"))
        #expect(result.stdout.contains("USAGE: egg template validate"))
        #expect(result.stdout.contains("<template-path>"))
    }

    @Test(arguments: TestCase.allCases)
    func validateTemplate(_ testCase: TestCase) async throws {
        let runner = try await CLIRunner()
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "cli-test-validate")
        defer { try? fileManager.removeItem(at: tempDir) }

        // Setup template
        let templateDir = tempDir.appending(path: "TestTemplate")
        try fileManager.createDirectory(at: templateDir, withIntermediateDirectories: true)

        if let configContent = testCase.configContent {
            let configPath = templateDir.appending(path: "config.yml")
            try configContent.write(to: configPath, atomically: true, encoding: .utf8)
        }

        let arguments = ["template", "validate", templateDir.path(percentEncoded: false)]

        let result = try await runner.run(arguments: arguments)

        switch testCase.expected {
        case .success:
            #expect(result.succeeded, "Expected success but got exit code \(result.exitCode): \(result.stderr)")
        case let .failure(errorContains):
            #expect(!result.succeeded, "Expected failure but command succeeded")
            let output = result.stderr + result.stdout
            #expect(output.contains(errorContains), "Expected error containing '\(errorContains)' but got: \(output)")
        }
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let configContent: String?
        let expected: Expected

        var testDescription: String { description }

        enum Expected {
            case success
            case failure(errorContains: String)
        }

        static let allCases: [TestCase] = [
            // Success cases
            TestCase(
                description: "validates valid config.yml",
                configContent: """
                name: ValidTemplate
                description: A valid template
                hatch:
                  output: .
                """,
                expected: .success
            ),
            TestCase(
                description: "validates config with macros",
                configContent: """
                name: TemplateWithMacros
                description: Template with macros
                macros:
                  - name: ___PROJECT_NAME___
                    description: Enter project name
                    type: string
                hatch:
                  output: .
                """,
                expected: .success
            ),

            // Error cases
            TestCase(
                description: "fails when config.yml is missing",
                configContent: nil,
                expected: .failure(errorContains: "Error")
            ),
            TestCase(
                description: "fails when config.yml has invalid YAML syntax",
                configContent: """
                name: InvalidTemplate
                description: [invalid yaml
                """,
                expected: .failure(errorContains: "Error")
            ),
            TestCase(
                description: "fails when required field is missing",
                configContent: """
                description: Missing name field
                hatch:
                  output: .
                """,
                expected: .failure(errorContains: "Error")
            ),
        ]
    }
}
