@testable import EggKit
import FileManagerProtocol
import Foundation
import Testing

struct TemplatesFinderTests {
    // MARK: - fetchTemplate Tests

    @Test(arguments: FetchTemplateTestCase.allCases)
    func fetchTemplate(_ testCase: FetchTemplateTestCase) async throws {
        let fileManager: any FileManagerProtocol = FileManager.default
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "templates-finder-test")

        defer {
            try? fileManager.removeItem(at: tempDir)
        }

        let projectDirectory = tempDir.appending(path: "project")
        let homeDirectory = tempDir.appending(path: "home")

        try fileManager.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: homeDirectory, withIntermediateDirectories: true)

        // Create templates
        for template in testCase.templates {
            let templateDir: URL
            switch template.location {
            case .global:
                templateDir = homeDirectory.appending(path: ".eggs").appending(path: template.dirName)
            case .project:
                templateDir = projectDirectory.appending(path: ".eggs").appending(path: template.dirName)
            }

            try fileManager.createDirectory(at: templateDir, withIntermediateDirectories: true)

            let configPath = templateDir.appending(path: "config.yml")
            let configContent = """
            name: \(template.configName)
            description: Test template
            hatch:
              output: .
            """
            try fileManager.writeText(configContent, at: configPath)
        }

        let finder = TemplatesFinder(
            fileManager: fileManager,
            projectDirectory: projectDirectory,
            workingDirectory: projectDirectory,
            homeDirectory: homeDirectory
        )

        switch testCase.expected {
        case let .success(expectedConfigName):
            let result = try await finder.fetchTemplate(testCase.searchName)
            #expect(result.config.name == expectedConfigName)
        case .failure:
            await #expect(throws: TemplatesFinder.Error.self) {
                _ = try await finder.fetchTemplate(testCase.searchName)
            }
        }
    }

    struct FetchTemplateTestCase: CustomTestStringConvertible {
        let description: String
        let templates: [TemplateSetup]
        let searchName: String
        let expected: Result

        var testDescription: String { description }

        struct TemplateSetup {
            let dirName: String
            let configName: String
            let location: LocationKind

            enum LocationKind {
                case global
                case project
            }
        }

        enum Result {
            case success(configName: String)
            case failure
        }

        static let allCases: [FetchTemplateTestCase] = [
            // Search by config.yml name
            FetchTemplateTestCase(
                description: "finds template by config.yml name when different from dir name",
                templates: [
                    TemplateSetup(dirName: "my-template-dir", configName: "MyTemplate", location: .global),
                ],
                searchName: "MyTemplate",
                expected: .success(configName: "MyTemplate")
            ),
            FetchTemplateTestCase(
                description: "finds template by config.yml name in project location",
                templates: [
                    TemplateSetup(dirName: "project-template-dir", configName: "ProjectTemplate", location: .project),
                ],
                searchName: "ProjectTemplate",
                expected: .success(configName: "ProjectTemplate")
            ),

            // Search by directory name (backwards compatibility)
            FetchTemplateTestCase(
                description: "finds template by directory name when config name differs",
                templates: [
                    TemplateSetup(dirName: "my-template-dir", configName: "MyTemplate", location: .global),
                ],
                searchName: "my-template-dir",
                expected: .success(configName: "MyTemplate")
            ),

            // Config name takes priority
            FetchTemplateTestCase(
                description: "config name takes priority over directory name",
                templates: [
                    TemplateSetup(dirName: "DirNameTemplate", configName: "ConfigNameTemplate", location: .global),
                    TemplateSetup(dirName: "ConfigNameTemplate", configName: "OtherTemplate", location: .global),
                ],
                searchName: "ConfigNameTemplate",
                expected: .success(configName: "ConfigNameTemplate")
            ),

            // Not found
            FetchTemplateTestCase(
                description: "throws error when template not found",
                templates: [
                    TemplateSetup(dirName: "existing-template", configName: "ExistingTemplate", location: .global),
                ],
                searchName: "NonExistentTemplate",
                expected: .failure
            ),

            // Same name in config and directory
            FetchTemplateTestCase(
                description: "finds template when config name matches directory name",
                templates: [
                    TemplateSetup(dirName: "MyTemplate", configName: "MyTemplate", location: .global),
                ],
                searchName: "MyTemplate",
                expected: .success(configName: "MyTemplate")
            ),
        ]
    }
}
