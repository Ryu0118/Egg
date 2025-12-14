@testable import EggKit
import FileManagerProtocol
import Foundation
import Noora
import Testing

struct MoveRunnerTests {
    @Test(arguments: TestCase.allCases)
    func run(_ testCase: TestCase) async throws {
        let fileManager: any FileManagerProtocol = FileManager.default
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "move-runner-test")

        defer {
            try? fileManager.removeItem(at: tempDir)
        }

        let projectDirectory = tempDir.appending(path: "project")
        let homeDirectory = tempDir.appending(path: "home")

        try fileManager.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: homeDirectory, withIntermediateDirectories: true)

        // Setup initial templates
        try setupTemplates(
            templates: testCase.initialTemplates,
            projectDirectory: projectDirectory,
            homeDirectory: homeDirectory,
            fileManager: fileManager
        )

        let mode = testCase.mode(projectDirectory: projectDirectory)
        let runner = MoveRunner(
            mode: mode,
            force: testCase.force,
            projectDirectory: projectDirectory,
            workingDirectory: projectDirectory,
            homeDirectory: homeDirectory,
            fileManager: fileManager,
            noora: NooraMock()
        )

        if let expectedError = testCase.expectedError {
            await #expect(throws: expectedError) {
                try await runner.run()
            }
        } else {
            try await runner.run()

            // Verify the move occurred correctly
            try verifyMoveResult(
                testCase: testCase,
                projectDirectory: projectDirectory,
                homeDirectory: homeDirectory,
                fileManager: fileManager
            )
        }
    }

    private func setupTemplates(
        templates: [(name: String, location: TemplateLocationType.Kind, content: String)],
        projectDirectory: URL,
        homeDirectory: URL,
        fileManager: some FileManagerProtocol
    ) throws {
        for (name, location, content) in templates {
            let templatePath = location.toPath(
                templateName: name,
                projectDirectory: projectDirectory,
                homeDirectory: homeDirectory
            )
            try fileManager.createDirectory(at: templatePath, withIntermediateDirectories: true)

            let configPath = templatePath.appending(path: "config.yml")
            try fileManager.writeText(content, at: configPath)

            // Add additional test file
            let testFilePath = templatePath.appending(path: "test.txt")
            try fileManager.writeText("Test content for \(name)", at: testFilePath)
        }
    }

    private func verifyMoveResult(
        testCase: TestCase,
        projectDirectory: URL,
        homeDirectory: URL,
        fileManager: some FileManagerProtocol
    ) throws {
        guard let verification = testCase.verification else {
            return
        }

        // Verify source no longer exists
        let sourcePath = verification.sourceLocation.toPath(
            templateName: verification.templateName,
            projectDirectory: projectDirectory,
            homeDirectory: homeDirectory
        )
        #expect(!fileManager.fileExists(atPath: sourcePath.path(percentEncoded: false)))

        // Verify target exists
        let targetPath = verification.targetLocation.toPath(
            templateName: verification.templateName,
            projectDirectory: projectDirectory,
            homeDirectory: homeDirectory
        )
        #expect(fileManager.fileExists(atPath: targetPath.path(percentEncoded: false)))

        // Verify content was preserved
        let configPath = targetPath.appending(path: "config.yml")
        #expect(fileManager.fileExists(atPath: configPath.path(percentEncoded: false)))

        let testFilePath = targetPath.appending(path: "test.txt")
        #expect(fileManager.fileExists(atPath: testFilePath.path(percentEncoded: false)))

        let testFileData = try fileManager.readFile(at: testFilePath)
        let testFileContent = String(data: testFileData, encoding: .utf8) ?? ""
        #expect(testFileContent == "Test content for \(verification.templateName)")
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let initialTemplates: [(name: String, location: TemplateLocationType.Kind, content: String)]
        let modeConfig: ModeConfig
        let force: Bool
        let verification: Verification?
        let expectedError: MoveRunner.Error?

        var testDescription: String { description }

        func mode(projectDirectory: URL) -> MoveRunnerMode {
            modeConfig.toMode(projectDirectory: projectDirectory)
        }

        static let allCases: [TestCase] = [
            // Success cases - direct mode
            TestCase(
                description: "successfully moves template from global to project",
                initialTemplates: [
                    ("MyTemplate", .global, """
                    name: MyTemplate
                    description: Test template
                    hatch:
                      output: .
                    """),
                ],
                modeConfig: .direct(
                    name: "MyTemplate",
                    sourceLocation: .global,
                    targetLocation: .project
                ),
                force: false,
                verification: Verification(
                    templateName: "MyTemplate",
                    sourceLocation: .global,
                    targetLocation: .project
                ),
                expectedError: nil
            ),
            TestCase(
                description: "successfully moves template from project to global",
                initialTemplates: [
                    ("ProjectTemplate", .project, """
                    name: ProjectTemplate
                    description: Project test template
                    hatch:
                      output: .
                    """),
                ],
                modeConfig: .direct(
                    name: "ProjectTemplate",
                    sourceLocation: .project,
                    targetLocation: .global
                ),
                force: false,
                verification: Verification(
                    templateName: "ProjectTemplate",
                    sourceLocation: .project,
                    targetLocation: .global
                ),
                expectedError: nil
            ),
            TestCase(
                description: "successfully overwrites target when force is true",
                initialTemplates: [
                    ("MyTemplate", .global, """
                    name: MyTemplate
                    description: Source template
                    hatch:
                      output: .
                    """),
                    ("MyTemplate", .project, """
                    name: MyTemplate
                    description: Old target template
                    hatch:
                      output: .
                    """),
                ],
                modeConfig: .direct(
                    name: "MyTemplate",
                    sourceLocation: .global,
                    targetLocation: .project
                ),
                force: true,
                verification: Verification(
                    templateName: "MyTemplate",
                    sourceLocation: .global,
                    targetLocation: .project
                ),
                expectedError: nil
            ),
            TestCase(
                description: "auto-creates target directory if it doesn't exist",
                initialTemplates: [
                    ("NewTemplate", .global, """
                    name: NewTemplate
                    description: New template
                    hatch:
                      output: .
                    """),
                ],
                modeConfig: .direct(
                    name: "NewTemplate",
                    sourceLocation: .global,
                    targetLocation: .project
                ),
                force: false,
                verification: Verification(
                    templateName: "NewTemplate",
                    sourceLocation: .global,
                    targetLocation: .project
                ),
                expectedError: nil
            ),
            TestCase(
                description: "preserves template content during move",
                initialTemplates: [
                    ("ComplexTemplate", .global, """
                    name: ComplexTemplate
                    description: Complex template with macros
                    macros:
                      - name: projectName
                        type: text
                        prompt: Project name
                    hatch:
                      output: .
                    """),
                ],
                modeConfig: .direct(
                    name: "ComplexTemplate",
                    sourceLocation: .global,
                    targetLocation: .project
                ),
                force: false,
                verification: Verification(
                    templateName: "ComplexTemplate",
                    sourceLocation: .global,
                    targetLocation: .project
                ),
                expectedError: nil
            ),

            // Error cases
            TestCase(
                description: "throws targetAlreadyExists when target exists and force is false",
                initialTemplates: [
                    ("MyTemplate", .global, """
                    name: MyTemplate
                    description: Source template
                    hatch:
                      output: .
                    """),
                    ("MyTemplate", .project, """
                    name: MyTemplate
                    description: Target template
                    hatch:
                      output: .
                    """),
                ],
                modeConfig: .direct(
                    name: "MyTemplate",
                    sourceLocation: .global,
                    targetLocation: .project
                ),
                force: false,
                verification: nil,
                expectedError: .targetAlreadyExists(name: "MyTemplate", location: "project")
            ),
        ]

        enum ModeConfig {
            case direct(
                name: String,
                sourceLocation: TemplateLocationType.Kind,
                targetLocation: TemplateLocationType.Kind
            )

            func toMode(projectDirectory: URL) -> MoveRunnerMode {
                switch self {
                case let .direct(name, sourceLocation, targetLocation):
                    let sourcePath = sourceLocation.toPath(
                        templateName: name,
                        projectDirectory: projectDirectory,
                        homeDirectory: projectDirectory.deletingLastPathComponent().appending(path: "home")
                    )
                    return .direct(
                        name: name,
                        path: sourcePath.path(percentEncoded: false),
                        sourceLocation: sourceLocation.toConcreteType(
                            projectDirectory,
                            workingDirectory: projectDirectory
                        ),
                        targetLocation: targetLocation.toConcreteType(
                            projectDirectory,
                            workingDirectory: projectDirectory
                        )
                    )
                }
            }
        }

        struct Verification {
            let templateName: String
            let sourceLocation: TemplateLocationType.Kind
            let targetLocation: TemplateLocationType.Kind
        }
    }
}

extension MoveRunner.Error: Equatable {
    public static func == (lhs: MoveRunner.Error, rhs: MoveRunner.Error) -> Bool {
        switch (lhs, rhs) {
        case (.noTemplatesFound, .noTemplatesFound):
            return true
        case (.noAvailableTargets, .noAvailableTargets):
            return true
        case let (.targetAlreadyExists(lhsName, lhsLocation), .targetAlreadyExists(rhsName, rhsLocation)):
            return lhsName == rhsName && lhsLocation == rhsLocation
        case let (.moveFailed(lhsName, _), .moveFailed(rhsName, _)):
            // Compare only the name, not the underlying error
            return lhsName == rhsName
        default:
            return false
        }
    }
}

// Shared helper extension to convert Kind to actual path
fileprivate extension TemplateLocationType.Kind {
    func toPath(
        templateName: String,
        projectDirectory: URL,
        homeDirectory: URL
    ) -> URL {
        switch self {
        case .global:
            return homeDirectory.appending(path: ".eggs").appending(path: templateName)
        case .project:
            return projectDirectory.appending(path: ".eggs").appending(path: templateName)
        }
    }
}
