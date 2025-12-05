import Foundation
import Testing
import FileSystem
import FileSystemTesting
import Path
@testable import EggKit

struct CreateArgumentsValidatorTests {
    @Test(.inTemporaryDirectory, arguments: TestCase.allCases)
    func validate(_ testCase: TestCase) async throws {
        guard let tempDir = FileSystem.temporaryTestDirectory else {
            throw TestError.temporaryDirectoryNotAvailable
        }
        
        let fileSystem = FileSystem()
        let projectDirectory = tempDir.appending(component: "project")
        let homeDirectory = tempDir.appending(component: "home")
        
        // Create directories
        try await fileSystem.makeDirectory(at: projectDirectory, options: [.createTargetParentDirectories])
        try await fileSystem.makeDirectory(at: homeDirectory, options: [.createTargetParentDirectories])
        
        // Create existing templates if needed
        for templateName in testCase.existingTemplates {
            // TemplatesFinder checks both global and project locations, so create in both
            let globalPath = homeDirectory.appending(component: ".eggs").appending(component: templateName)
            let projectPath = projectDirectory.appending(component: ".eggs").appending(component: templateName)
            try await fileSystem.makeDirectory(at: globalPath, options: [.createTargetParentDirectories])
            try await fileSystem.makeDirectory(at: projectPath, options: [.createTargetParentDirectories])
        }
        
        let validator = CreateArgumentsValidator(
            name: testCase.name,
            description: testCase.templateDescription,
            location: testCase.location,
            projectDirectory: projectDirectory,
            homeDirectory: homeDirectory,
            fileSystem: fileSystem
        )
        
        switch testCase.expected {
        case .success(let expectedMode):
            let result = try await validator.validate()
            #expect(result == expectedMode)
        case .failure(let expectedError):
            await #expect(throws: expectedError) {
                _ = try await validator.validate()
            }
        }
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let name: String?
        let templateDescription: String?
        let location: TemplateLocationType?
        let existingTemplates: Set<String>
        let expected: Result

        var testDescription: String { description }

        static let allCases: [TestCase] = [
            // Success cases
            TestCase(
                description: "returns noora mode when all fields are nil",
                name: nil,
                templateDescription: nil,
                location: nil,
                existingTemplates: [],
                expected: .success(.noora)
            ),
            TestCase(
                description: "returns provided mode when all fields are provided and template does not exist",
                name: "MyTemplate",
                templateDescription: "A test template",
                location: .global,
                existingTemplates: [],
                expected: .success(.provided(name: "MyTemplate", description: "A test template", location: .global))
            ),
            TestCase(
                description: "returns provided mode with project location",
                name: "ProjectTemplate",
                templateDescription: "Project template",
                location: .project,
                existingTemplates: [],
                expected: .success(.provided(name: "ProjectTemplate", description: "Project template", location: .project))
            ),

            // Error cases - missing fields
            TestCase(
                description: "throws error when only name is provided",
                name: "MyTemplate",
                templateDescription: nil,
                location: nil,
                existingTemplates: [],
                expected: .failure(.missingFields(missing: [.description, .location], provided: [.name]))
            ),
            TestCase(
                description: "throws error when only description is provided",
                name: nil,
                templateDescription: "A description",
                location: nil,
                existingTemplates: [],
                expected: .failure(.missingFields(missing: [.name, .location], provided: [.description]))
            ),
            TestCase(
                description: "throws error when only location is provided",
                name: nil,
                templateDescription: nil,
                location: .global,
                existingTemplates: [],
                expected: .failure(.missingFields(missing: [.name, .description], provided: [.location]))
            ),
            TestCase(
                description: "throws error when name and description are provided but location is missing",
                name: "MyTemplate",
                templateDescription: "A description",
                location: nil,
                existingTemplates: [],
                expected: .failure(.missingFields(missing: [.location], provided: [.name, .description]))
            ),
            TestCase(
                description: "throws error when name and location are provided but description is missing",
                name: "MyTemplate",
                templateDescription: nil,
                location: .global,
                existingTemplates: [],
                expected: .failure(.missingFields(missing: [.description], provided: [.name, .location]))
            ),
            TestCase(
                description: "throws error when description and location are provided but name is missing",
                name: nil,
                templateDescription: "A description",
                location: .global,
                existingTemplates: [],
                expected: .failure(.missingFields(missing: [.name], provided: [.description, .location]))
            ),

            // Error cases - template already exists
            TestCase(
                description: "throws error when template already exists in global location",
                name: "ExistingTemplate",
                templateDescription: "A description",
                location: .global,
                existingTemplates: ["ExistingTemplate"],
                expected: .failure(.templateAlreadyExists)
            ),
            TestCase(
                description: "throws error when template already exists in project location",
                name: "ExistingTemplate",
                templateDescription: "A description",
                location: .project,
                existingTemplates: ["ExistingTemplate"],
                expected: .failure(.templateAlreadyExists)
            ),
        ]

        enum Result {
            case success(CreateRunnerMode)
            case failure(CreateArgumentsValidator.Error)
        }
    }
    
    enum TestError: Error {
        case temporaryDirectoryNotAvailable
    }
}

// MARK: - Equatable conformance for CreateRunnerMode

extension CreateRunnerMode: Equatable {
    public static func == (lhs: CreateRunnerMode, rhs: CreateRunnerMode) -> Bool {
        switch (lhs, rhs) {
        case (.noora, .noora):
            return true
        case (.provided(let lhsName, let lhsDescription, let lhsLocation),
              .provided(let rhsName, let rhsDescription, let rhsLocation)):
            return lhsName == rhsName && lhsDescription == rhsDescription && lhsLocation == rhsLocation
        default:
            return false
        }
    }
}

// MARK: - Equatable conformance for CreateArgumentsValidator.Error

extension CreateArgumentsValidator.Error: Equatable {
    public static func == (lhs: CreateArgumentsValidator.Error, rhs: CreateArgumentsValidator.Error) -> Bool {
        switch (lhs, rhs) {
        case (.missingFields(let lhsMissing, let lhsProvided),
              .missingFields(let rhsMissing, let rhsProvided)):
            return lhsMissing == rhsMissing && lhsProvided == rhsProvided
        case (.templateAlreadyExists, .templateAlreadyExists):
            return true
        default:
            return false
        }
    }
}
