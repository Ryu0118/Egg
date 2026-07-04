@testable import EggKit
import FileManagerProtocol
import Foundation
import Testing

struct CreateArgumentsValidatorTests {
    @Test(arguments: TestCase.allCases)
    func validate(_ testCase: TestCase) async throws {
        let fileManager: any FileManagerProtocol = FileManager.default

        // Create temporary directory for this test
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "create-validator-test")
        defer {
            try? fileManager.removeItem(at: tempDir)
        }

        let projectDirectory = tempDir.appending(path: "project")
        let homeDirectory = tempDir.appending(path: "home")

        // Create directories
        try fileManager.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: homeDirectory, withIntermediateDirectories: true)

        // Create existing templates if needed
        for templateName in testCase.existingTemplates {
            // TemplatesFinder checks both global and project locations, so create in both
            let globalPath = homeDirectory.appending(path: ".eggs").appending(path: templateName)
            let projectPath = projectDirectory.appending(path: ".eggs").appending(path: templateName)
            try fileManager.createDirectory(at: globalPath, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: projectPath, withIntermediateDirectories: true)
        }

        let validator = CreateArgumentsValidator(
            name: testCase.name,
            description: testCase.templateDescription,
            location: testCase.location,
            projectDirectory: projectDirectory,
            workingDirectory: projectDirectory,
            homeDirectory: homeDirectory,
            fileManager: fileManager,
        )

        switch testCase.expected {
        case let .success(expectedMode):
            let result = try await validator.validate()
            #expect(result == expectedMode)
        case let .failure(expectedError):
            await #expect(throws: expectedError) {
                _ = try await validator.validate()
            }
        }
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let name: String?
        let templateDescription: String?
        let location: TemplateLocationType.Kind?
        let existingTemplates: Set<String>
        let expected: Result

        static let allCases: [TestCase] = [
            // Success cases
            TestCase(
                description: "returns interactive mode when all fields are nil",
                name: nil,
                templateDescription: nil,
                location: nil,
                existingTemplates: [],
                expected: .success(.interactive),
            ),
            TestCase(
                description: "returns direct mode when all fields are provided and template does not exist",
                name: "MyTemplate",
                templateDescription: "A test template",
                location: .global,
                existingTemplates: [],
                expected: .success(.direct(name: "MyTemplate", description: "A test template", location: .global)),
            ),
            TestCase(
                description: "returns direct mode with project location",
                name: "ProjectTemplate",
                templateDescription: "Project template",
                location: .project,
                existingTemplates: [],
                expected: .success(.direct(name: "ProjectTemplate", description: "Project template", location: .project)),
            ),

            // Error cases - missing fields
            TestCase(
                description: "throws error when only name is provided",
                name: "MyTemplate",
                templateDescription: nil,
                location: nil,
                existingTemplates: [],
                expected: .failure(.missingFields(missing: [.description, .location], provided: [.name])),
            ),
            TestCase(
                description: "throws error when only description is provided",
                name: nil,
                templateDescription: "A description",
                location: nil,
                existingTemplates: [],
                expected: .failure(.missingFields(missing: [.name, .location], provided: [.description])),
            ),
            TestCase(
                description: "throws error when only location is provided",
                name: nil,
                templateDescription: nil,
                location: .global,
                existingTemplates: [],
                expected: .failure(.missingFields(missing: [.name, .description], provided: [.location])),
            ),
            TestCase(
                description: "throws error when name and description are provided but location is missing",
                name: "MyTemplate",
                templateDescription: "A description",
                location: nil,
                existingTemplates: [],
                expected: .failure(.missingFields(missing: [.location], provided: [.name, .description])),
            ),
            TestCase(
                description: "throws error when name and location are provided but description is missing",
                name: "MyTemplate",
                templateDescription: nil,
                location: .global,
                existingTemplates: [],
                expected: .failure(.missingFields(missing: [.description], provided: [.name, .location])),
            ),
            TestCase(
                description: "throws error when description and location are provided but name is missing",
                name: nil,
                templateDescription: "A description",
                location: .global,
                existingTemplates: [],
                expected: .failure(.missingFields(missing: [.name], provided: [.description, .location])),
            ),

            // Error cases - template already exists
            TestCase(
                description: "throws error when template already exists in global location",
                name: "ExistingTemplate",
                templateDescription: "A description",
                location: .global,
                existingTemplates: ["ExistingTemplate"],
                expected: .failure(.templateAlreadyExists),
            ),
            TestCase(
                description: "throws error when template already exists in project location",
                name: "ExistingTemplate",
                templateDescription: "A description",
                location: .project,
                existingTemplates: ["ExistingTemplate"],
                expected: .failure(.templateAlreadyExists),
            ),
        ]

        var testDescription: String {
            description
        }

        enum Result {
            case success(CreateRunnerMode)
            case failure(CreateArgumentsValidator.Error)
        }
    }

    enum TestError: Error {
        case temporaryDirectoryNotAvailable
    }
}

extension CreateRunnerMode: Equatable {
    public static func == (lhs: CreateRunnerMode, rhs: CreateRunnerMode) -> Bool {
        switch (lhs, rhs) {
        case (.interactive, .interactive):
            true
        case let (.direct(lhsName, lhsDescription, lhsLocation),
                  .direct(rhsName, rhsDescription, rhsLocation)):
            lhsName == rhsName && lhsDescription == rhsDescription && lhsLocation == rhsLocation
        default:
            false
        }
    }
}

extension CreateArgumentsValidator.Error: Equatable {
    public static func == (lhs: CreateArgumentsValidator.Error, rhs: CreateArgumentsValidator.Error) -> Bool {
        switch (lhs, rhs) {
        case let (.missingFields(lhsMissing, lhsProvided),
                  .missingFields(rhsMissing, rhsProvided)):
            lhsMissing == rhsMissing && lhsProvided == rhsProvided
        case (.templateAlreadyExists, .templateAlreadyExists):
            true
        default:
            false
        }
    }
}
