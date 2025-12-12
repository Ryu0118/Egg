@testable import EggKit
import FileManagerProtocol
import Foundation
import Path
import Testing

struct DuplicateTemplateNameGeneratorTests {
    @Test(arguments: TestCase.allCases)
    func generateDefaultName(_ testCase: TestCase) async throws {
        let fileManager = FileManager.default
        let tempDir = try await fileManager.makeTemporaryDirectory(prefix: "duplicate-name-test")

        defer {
            Task { try? await fileManager.remove(tempDir) }
        }

        let projectDirectory = tempDir.appending(component: "project")
        let homeDirectory = tempDir.appending(component: "home")

        try await setupDirectories(
            fileManager: fileManager,
            projectDirectory: projectDirectory,
            homeDirectory: homeDirectory
        )

        let sourceLocation = testCase.sourceLocation(projectDirectory: projectDirectory)

        try await createExistingTemplates(
            testCase.existingTemplates,
            in: sourceLocation,
            fileManager: fileManager,
            projectDirectory: projectDirectory,
            homeDirectory: homeDirectory
        )

        let templatesFinder = TemplatesFinder(
            fileSystem: fileManager,
            projectDirectory: projectDirectory,
            workingDirectory: projectDirectory,
            homeDirectory: homeDirectory
        )

        let result = await DuplicateTemplateNameGenerator.generateDefaultName(
            baseName: testCase.baseName,
            sourceLocation: sourceLocation,
            templatesFinder: templatesFinder,
            emitValidationErrorLog: false
        )

        #expect(result == testCase.expected)
    }

    private func setupDirectories(
        fileManager: some FileManagerProtocol,
        projectDirectory: AbsolutePath,
        homeDirectory: AbsolutePath
    ) async throws {
        let projectURL = URL(filePath: projectDirectory.pathString)
        let homeURL = URL(filePath: homeDirectory.pathString)
        try await fileManager.createDirectory(at: projectURL, withIntermediateDirectories: true)
        try await fileManager.createDirectory(at: homeURL, withIntermediateDirectories: true)
    }

    private func createExistingTemplates(
        _ templateNames: Set<String>,
        in sourceLocation: TemplateLocationType,
        fileManager: some FileManagerProtocol,
        projectDirectory: AbsolutePath,
        homeDirectory: AbsolutePath
    ) async throws {
        let templateDirectory = sourceLocation == .global
            ? homeDirectory.appending(component: ".eggs")
            : projectDirectory.appending(component: ".eggs")

        for templateName in templateNames {
            let templatePath = templateDirectory.appending(component: templateName)
            let templateURL = URL(filePath: templatePath.pathString)
            try await fileManager.createDirectory(at: templateURL, withIntermediateDirectories: true)

            let configPath = templatePath.appending(component: "config.yml")
            let configURL = URL(filePath: configPath.pathString)
            let configContent = """
            name: \(templateName)
            description: Test template
            hatch:
              output: .
            """
            try await fileManager.writeText(configContent, at: configURL)
        }
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let baseName: String
        let sourceLocationKind: TemplateLocationType.Kind
        let existingTemplates: Set<String>
        let expected: String

        var testDescription: String { description }

        func sourceLocation(projectDirectory: AbsolutePath) -> TemplateLocationType {
            sourceLocationKind.toConcreteType(projectDirectory, workingDirectory: projectDirectory)
        }

        static let allCases: [TestCase] = [
            TestCase(
                description: "returns base name with (1) when no templates exist",
                baseName: "MyTemplate",
                sourceLocationKind: .global,
                existingTemplates: [],
                expected: "MyTemplate (1)"
            ),
            TestCase(
                description: "returns base name with (2) when (1) already exists",
                baseName: "MyTemplate",
                sourceLocationKind: .global,
                existingTemplates: ["MyTemplate (1)"],
                expected: "MyTemplate (2)"
            ),
            TestCase(
                description: "returns base name with (3) when (1) and (2) exist",
                baseName: "MyTemplate",
                sourceLocationKind: .global,
                existingTemplates: ["MyTemplate (1)", "MyTemplate (2)"],
                expected: "MyTemplate (3)"
            ),
            TestCase(
                description: "returns base name with (1) when only base name exists without number",
                baseName: "MyTemplate",
                sourceLocationKind: .global,
                existingTemplates: ["MyTemplate"],
                expected: "MyTemplate (1)"
            ),
            TestCase(
                description: "returns base name with (2) when base name and (1) exist",
                baseName: "MyTemplate",
                sourceLocationKind: .global,
                existingTemplates: ["MyTemplate", "MyTemplate (1)"],
                expected: "MyTemplate (2)"
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
                expected: "MyTemplate (5)"
            ),
            TestCase(
                description: "returns base name with (1) when only other templates exist",
                baseName: "MyTemplate",
                sourceLocationKind: .global,
                existingTemplates: ["OtherTemplate", "OtherTemplate (1)"],
                expected: "MyTemplate (1)"
            ),
            TestCase(
                description: "works with project location when no templates exist",
                baseName: "ProjectTemplate",
                sourceLocationKind: .project,
                existingTemplates: [],
                expected: "ProjectTemplate (1)"
            ),
            TestCase(
                description: "works with project location when (1) exists",
                baseName: "ProjectTemplate",
                sourceLocationKind: .project,
                existingTemplates: ["ProjectTemplate (1)"],
                expected: "ProjectTemplate (2)"
            ),
            TestCase(
                description: "returns base name with (1) when only (5) exists",
                baseName: "MyTemplate",
                sourceLocationKind: .global,
                existingTemplates: ["MyTemplate (5)"],
                expected: "MyTemplate (1)"
            ),
        ]
    }

    enum TestError: Error {
        case temporaryDirectoryNotAvailable
    }
}
