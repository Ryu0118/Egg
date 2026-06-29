@testable import EggKit
import FileManagerProtocol
import Foundation
import Testing

struct DuplicateTemplateNameGeneratorTests {
    @Test(arguments: TestCase.allCases)
    func `generate default name`(_ testCase: TestCase) async throws {
        let fileManager: any FileManagerProtocol = FileManager.default
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "duplicate-name-test")

        defer {
            try? fileManager.removeItem(at: tempDir)
        }

        let projectDirectory = tempDir.appending(path: "project")
        let homeDirectory = tempDir.appending(path: "home")

        try setupDirectories(
            fileManager: fileManager,
            projectDirectory: projectDirectory,
            homeDirectory: homeDirectory,
        )

        let sourceLocation = testCase.sourceLocation(projectDirectory: projectDirectory)

        try createExistingTemplates(
            testCase.existingTemplates,
            in: sourceLocation,
            fileManager: fileManager,
            projectDirectory: projectDirectory,
            homeDirectory: homeDirectory,
        )

        let templatesFinder = TemplatesFinder(
            fileManager: fileManager,
            projectDirectory: projectDirectory,
            workingDirectory: projectDirectory,
            homeDirectory: homeDirectory,
        )

        let result = await DuplicateTemplateNameGenerator.generateDefaultName(
            baseName: testCase.baseName,
            sourceLocation: sourceLocation,
            templatesFinder: templatesFinder,
            emitValidationErrorLog: false,
        )

        #expect(result == testCase.expected)
    }

    private func setupDirectories(
        fileManager: some FileManagerProtocol,
        projectDirectory: URL,
        homeDirectory: URL,
    ) throws {
        try fileManager.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
    }

    private func createExistingTemplates(
        _ templateNames: Set<String>,
        in sourceLocation: TemplateLocationType,
        fileManager: some FileManagerProtocol,
        projectDirectory: URL,
        homeDirectory: URL,
    ) throws {
        let templateDirectory = sourceLocation == .global
            ? homeDirectory.appending(path: ".eggs")
            : projectDirectory.appending(path: ".eggs")

        for templateName in templateNames {
            let templatePath = templateDirectory.appending(path: templateName)
            try fileManager.createDirectory(at: templatePath, withIntermediateDirectories: true)

            let configPath = templatePath.appending(path: "config.yml")
            let configContent = """
            name: \(templateName)
            description: Test template
            hatch:
              output: .
            """
            try fileManager.writeText(configContent, at: configPath)
        }
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let baseName: String
        let sourceLocationKind: TemplateLocationType.Kind
        let existingTemplates: Set<String>
        let expected: String

        var testDescription: String {
            description
        }

        func sourceLocation(projectDirectory: URL) -> TemplateLocationType {
            sourceLocationKind.toConcreteType(projectDirectory, workingDirectory: projectDirectory)
        }

        static let allCases: [TestCase] = [
            TestCase(
                description: "returns base name with (1) when no templates exist",
                baseName: "MyTemplate",
                sourceLocationKind: .global,
                existingTemplates: [],
                expected: "MyTemplate (1)",
            ),
            TestCase(
                description: "returns base name with (2) when (1) already exists",
                baseName: "MyTemplate",
                sourceLocationKind: .global,
                existingTemplates: ["MyTemplate (1)"],
                expected: "MyTemplate (2)",
            ),
            TestCase(
                description: "returns base name with (3) when (1) and (2) exist",
                baseName: "MyTemplate",
                sourceLocationKind: .global,
                existingTemplates: ["MyTemplate (1)", "MyTemplate (2)"],
                expected: "MyTemplate (3)",
            ),
            TestCase(
                description: "returns base name with (1) when only base name exists without number",
                baseName: "MyTemplate",
                sourceLocationKind: .global,
                existingTemplates: ["MyTemplate"],
                expected: "MyTemplate (1)",
            ),
            TestCase(
                description: "returns base name with (2) when base name and (1) exist",
                baseName: "MyTemplate",
                sourceLocationKind: .global,
                existingTemplates: ["MyTemplate", "MyTemplate (1)"],
                expected: "MyTemplate (2)",
            ),
            TestCase(
                description: "returns base name with (5) when (1) through (4) exist",
                baseName: "MyTemplate",
                sourceLocationKind: .global,
                existingTemplates: [
                    "MyTemplate (1)",
                    "MyTemplate (2)",
                    "MyTemplate (3)",
                    "MyTemplate (4)",
                ],
                expected: "MyTemplate (5)",
            ),
            TestCase(
                description: "returns base name with (1) when only other templates exist",
                baseName: "MyTemplate",
                sourceLocationKind: .global,
                existingTemplates: ["OtherTemplate", "OtherTemplate (1)"],
                expected: "MyTemplate (1)",
            ),
            TestCase(
                description: "works with project location when no templates exist",
                baseName: "ProjectTemplate",
                sourceLocationKind: .project,
                existingTemplates: [],
                expected: "ProjectTemplate (1)",
            ),
            TestCase(
                description: "works with project location when (1) exists",
                baseName: "ProjectTemplate",
                sourceLocationKind: .project,
                existingTemplates: ["ProjectTemplate (1)"],
                expected: "ProjectTemplate (2)",
            ),
            TestCase(
                description: "returns base name with (1) when only (5) exists",
                baseName: "MyTemplate",
                sourceLocationKind: .global,
                existingTemplates: ["MyTemplate (5)"],
                expected: "MyTemplate (1)",
            ),
        ]
    }

    enum TestError: Error {
        case temporaryDirectoryNotAvailable
    }
}
