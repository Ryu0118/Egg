@testable import EggKit
import FileManagerProtocol
import Foundation
import Testing

struct MoveArgumentsValidatorTests {
    @Test(arguments: TestCase.allCases)
    func validate(_ testCase: TestCase) async throws {
        let fileManager: any FileManagerProtocol = FileManager.default

        // Create temporary directory for this test
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "move-validator-test")
        defer {
            try? fileManager.removeItem(at: tempDir)
        }

        let projectDirectory = tempDir.appending(path: "project")
        let homeDirectory = tempDir.appending(path: "home")

        // Create directories
        try fileManager.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: homeDirectory, withIntermediateDirectories: true)

        // Create existing templates if needed
        try setupTemplates(
            testCase: testCase,
            projectDirectory: projectDirectory,
            homeDirectory: homeDirectory,
            fileManager: fileManager
        )

        let validator = MoveArgumentsValidator(
            templateName: testCase.templateName,
            to: testCase.targetLocation,
            force: testCase.force,
            projectDirectory: projectDirectory,
            workingDirectory: projectDirectory,
            homeDirectory: homeDirectory,
            fileManager: fileManager
        )

        switch testCase.expected {
        case let .success(expectedMode):
            let result = try await validator.validate()
            #expect(result.matches(expectedMode))
        case let .failure(expectedError):
            await #expect(throws: expectedError) {
                _ = try await validator.validate()
            }
        }
    }

    private func setupTemplates(
        testCase: TestCase,
        projectDirectory: URL,
        homeDirectory: URL,
        fileManager: some FileManagerProtocol
    ) throws {
        // Create source templates
        for (name, location) in testCase.existingTemplates {
            let templatePath = location.toPath(
                templateName: name,
                projectDirectory: projectDirectory,
                homeDirectory: homeDirectory
            )
            try fileManager.createDirectory(at: templatePath, withIntermediateDirectories: true)

            let configPath = templatePath.appending(path: "config.yml")
            let configContent = """
            name: \(name)
            description: Test template
            hatch:
              output: .
            """
            try fileManager.writeText(configContent, at: configPath)
        }
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let templateName: String?
        let targetLocation: TemplateLocationType.Kind?
        let force: Bool
        let existingTemplates: [(name: String, location: TemplateLocationType.Kind)]
        let expected: Result

        var testDescription: String { description }

        static let allCases: [TestCase] = [
            // Success cases
            TestCase(
                description: "returns interactive mode when templateName and targetLocation are nil",
                templateName: nil,
                targetLocation: nil,
                force: false,
                existingTemplates: [],
                expected: .success(.interactive)
            ),
            TestCase(
                description: "returns selectTarget mode when templateName is provided but targetLocation is nil",
                templateName: "MyTemplate",
                targetLocation: nil,
                force: false,
                existingTemplates: [("MyTemplate", .global)],
                expected: .success(.selectTarget(
                    name: "MyTemplate",
                    sourceLocation: .global
                ))
            ),
            TestCase(
                description: "returns direct mode when both templateName and targetLocation are provided",
                templateName: "MyTemplate",
                targetLocation: .project,
                force: false,
                existingTemplates: [("MyTemplate", .global)],
                expected: .success(.direct(
                    name: "MyTemplate",
                    sourceLocationKind: .global,
                    targetLocationKind: .project
                ))
            ),
            TestCase(
                description: "returns direct mode with force when target exists and force is true",
                templateName: "MyTemplate",
                targetLocation: .project,
                force: true,
                existingTemplates: [("MyTemplate", .global), ("MyTemplate", .project)],
                expected: .success(.direct(
                    name: "MyTemplate",
                    sourceLocationKind: .global,
                    targetLocationKind: .project
                ))
            ),
            TestCase(
                description: "correctly identifies template in project location",
                templateName: "ProjectTemplate",
                targetLocation: .global,
                force: false,
                existingTemplates: [("ProjectTemplate", .project)],
                expected: .success(.direct(
                    name: "ProjectTemplate",
                    sourceLocationKind: .project,
                    targetLocationKind: .global
                ))
            ),
            TestCase(
                description: "correctly identifies template in global location",
                templateName: "GlobalTemplate",
                targetLocation: .project,
                force: false,
                existingTemplates: [("GlobalTemplate", .global)],
                expected: .success(.direct(
                    name: "GlobalTemplate",
                    sourceLocationKind: .global,
                    targetLocationKind: .project
                ))
            ),

            // Error cases
            TestCase(
                description: "throws templateNotFound when template does not exist",
                templateName: "NonExistent",
                targetLocation: .project,
                force: false,
                existingTemplates: [],
                expected: .failure(.templateNotFound(name: "NonExistent"))
            ),
            TestCase(
                description: "throws sameLocation when trying to move to same location (global)",
                templateName: "MyTemplate",
                targetLocation: .global,
                force: false,
                existingTemplates: [("MyTemplate", .global)],
                expected: .failure(.sameLocation(name: "MyTemplate", location: "global"))
            ),
            TestCase(
                description: "throws sameLocation when trying to move to same location (project)",
                templateName: "MyTemplate",
                targetLocation: .project,
                force: false,
                existingTemplates: [("MyTemplate", .project)],
                expected: .failure(.sameLocation(name: "MyTemplate", location: "project"))
            ),
            TestCase(
                description: "throws targetAlreadyExists when target exists and force is false",
                templateName: "MyTemplate",
                targetLocation: .project,
                force: false,
                existingTemplates: [("MyTemplate", .global), ("MyTemplate", .project)],
                expected: .failure(.targetAlreadyExists(name: "MyTemplate", location: "project"))
            ),
            TestCase(
                description: "throws sameLocation when both exist and trying to move to where template is found (global takes priority)",
                templateName: "MyTemplate",
                targetLocation: .global,
                force: false,
                existingTemplates: [("MyTemplate", .project), ("MyTemplate", .global)],
                expected: .failure(.sameLocation(name: "MyTemplate", location: "global"))
            ),
        ]

        enum Result {
            case success(ExpectedMode)
            case failure(MoveArgumentsValidator.Error)
        }

        enum ExpectedMode {
            case interactive
            case selectTarget(name: String, sourceLocation: TemplateLocationType.Kind)
            case direct(
                name: String,
                sourceLocationKind: TemplateLocationType.Kind,
                targetLocationKind: TemplateLocationType.Kind
            )
        }
    }
}

extension MoveRunnerMode {
    func matches(_ expected: MoveArgumentsValidatorTests.TestCase.ExpectedMode) -> Bool {
        switch (self, expected) {
        case (.interactive, .interactive):
            return true
        case let (.selectTarget(actualName, _, actualSource),
                  .selectTarget(expectedName, expectedSource)):
            return actualName == expectedName && actualSource.name == expectedSource.rawValue
        case let (.direct(actualName, _, actualSource, actualTarget),
                  .direct(expectedName, expectedSource, expectedTarget)):
            return actualName == expectedName
                && actualSource.name == expectedSource.rawValue
                && actualTarget.name == expectedTarget.rawValue
        default:
            return false
        }
    }
}

extension MoveArgumentsValidator.Error: Equatable {
    public static func == (lhs: MoveArgumentsValidator.Error, rhs: MoveArgumentsValidator.Error) -> Bool {
        switch (lhs, rhs) {
        case let (.templateNotFound(lhsName), .templateNotFound(rhsName)):
            return lhsName == rhsName
        case let (.sameLocation(lhsName, lhsLocation), .sameLocation(rhsName, rhsLocation)):
            return lhsName == rhsName && lhsLocation == rhsLocation
        case let (.targetAlreadyExists(lhsName, lhsLocation), .targetAlreadyExists(rhsName, rhsLocation)):
            return lhsName == rhsName && lhsLocation == rhsLocation
        default:
            return false
        }
    }
}

// Shared helper extension to convert Kind to actual path
private extension TemplateLocationType.Kind {
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
