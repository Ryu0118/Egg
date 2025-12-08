@testable import EggKit
import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing

struct DuplicateTemplateNameGeneratorTests {
    @Test(.inTemporaryDirectory, arguments: TestCase.allCases)
    func generateDefaultName(_ testCase: TestCase) async throws {
        guard let tempDir = FileSystem.temporaryTestDirectory else {
            throw TestError.temporaryDirectoryNotAvailable
        }

        let fileSystem = FileSystem()
        let projectDirectory = tempDir.appending(component: "project")
        let homeDirectory = tempDir.appending(component: "home")

        try await setupDirectories(
            fileSystem: fileSystem,
            projectDirectory: projectDirectory,
            homeDirectory: homeDirectory
        )

        let sourceLocation = testCase.sourceLocation(projectDirectory: projectDirectory)

        try await createExistingTemplates(
            testCase.existingTemplates,
            in: sourceLocation,
            fileSystem: fileSystem,
            projectDirectory: projectDirectory,
            homeDirectory: homeDirectory
        )

        let templatesFinder = TemplatesFinder(
            fileSystem: fileSystem,
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
        fileSystem: some FileSysteming,
        projectDirectory: AbsolutePath,
        homeDirectory: AbsolutePath
    ) async throws {
        try await fileSystem.makeDirectory(at: projectDirectory, options: [.createTargetParentDirectories])
        try await fileSystem.makeDirectory(at: homeDirectory, options: [.createTargetParentDirectories])
    }

    private func createExistingTemplates(
        _ templateNames: Set<String>,
        in sourceLocation: TemplateLocationType,
        fileSystem: some FileSysteming,
        projectDirectory: AbsolutePath,
        homeDirectory: AbsolutePath
    ) async throws {
        let templateDirectory = sourceLocation == .global
            ? homeDirectory.appending(component: ".eggs")
            : projectDirectory.appending(component: ".eggs")

        for templateName in templateNames {
            let templatePath = templateDirectory.appending(component: templateName)
            try await fileSystem.makeDirectory(at: templatePath, options: [.createTargetParentDirectories])

            let configPath = templatePath.appending(component: "config.yml")
            let configContent = """
            name: \(templateName)
            description: Test template
            """
            try await fileSystem.writeText(configContent, at: configPath)
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
