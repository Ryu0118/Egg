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

    // MARK: - fetchTemplate with Custom Search Paths Tests

    @Test(arguments: FetchTemplateWithCustomPathsTestCase.allCases)
    func fetchTemplateWithCustomPaths(_ testCase: FetchTemplateWithCustomPathsTestCase) async throws {
        let fileManager: any FileManagerProtocol = FileManager.default
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "templates-finder-custom-test")

        defer {
            try? fileManager.removeItem(at: tempDir)
        }

        let projectDirectory = tempDir.appending(path: "project")
        let homeDirectory = tempDir.appending(path: "home")
        let customPath1 = tempDir.appending(path: "custom1")
        let customPath2 = tempDir.appending(path: "custom2")

        try fileManager.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: customPath1, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: customPath2, withIntermediateDirectories: true)

        // Create templates
        for template in testCase.templates {
            let templateDir: URL
            switch template.location {
            case .global:
                templateDir = homeDirectory.appending(path: ".eggs").appending(path: template.dirName)
            case .project:
                templateDir = projectDirectory.appending(path: ".eggs").appending(path: template.dirName)
            case .custom1:
                templateDir = customPath1.appending(path: template.dirName)
            case .custom2:
                templateDir = customPath2.appending(path: template.dirName)
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

        let customSearchPaths = testCase.useCustomPaths ? [customPath1, customPath2] : []
        let finder = TemplatesFinder(
            fileManager: fileManager,
            projectDirectory: projectDirectory,
            workingDirectory: projectDirectory,
            homeDirectory: homeDirectory,
            additionalSearchPaths: customSearchPaths
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

    struct FetchTemplateWithCustomPathsTestCase: CustomTestStringConvertible {
        let description: String
        let templates: [TemplateSetup]
        let searchName: String
        let useCustomPaths: Bool
        let expected: Result

        var testDescription: String { description }

        struct TemplateSetup {
            let dirName: String
            let configName: String
            let location: LocationKind

            enum LocationKind {
                case global
                case project
                case custom1
                case custom2
            }
        }

        enum Result {
            case success(configName: String)
            case failure
        }

        static let allCases: [FetchTemplateWithCustomPathsTestCase] = [
            // Custom path basic
            FetchTemplateWithCustomPathsTestCase(
                description: "finds template in custom search path",
                templates: [
                    TemplateSetup(dirName: "CustomTemplate", configName: "CustomTemplate", location: .custom1),
                ],
                searchName: "CustomTemplate",
                useCustomPaths: true,
                expected: .success(configName: "CustomTemplate")
            ),

            // Custom path priority over global
            FetchTemplateWithCustomPathsTestCase(
                description: "custom path takes priority over global",
                templates: [
                    TemplateSetup(dirName: "MyTemplate", configName: "MyTemplate", location: .custom1),
                    TemplateSetup(dirName: "MyTemplate", configName: "GlobalTemplate", location: .global),
                ],
                searchName: "MyTemplate",
                useCustomPaths: true,
                expected: .success(configName: "MyTemplate")
            ),

            // Custom path priority over project
            FetchTemplateWithCustomPathsTestCase(
                description: "custom path takes priority over project",
                templates: [
                    TemplateSetup(dirName: "MyTemplate", configName: "MyTemplate", location: .custom1),
                    TemplateSetup(dirName: "MyTemplate", configName: "ProjectTemplate", location: .project),
                ],
                searchName: "MyTemplate",
                useCustomPaths: true,
                expected: .success(configName: "MyTemplate")
            ),

            // First custom path takes priority over second
            FetchTemplateWithCustomPathsTestCase(
                description: "first custom path takes priority over second custom path",
                templates: [
                    TemplateSetup(dirName: "MyTemplate", configName: "FirstCustomTemplate", location: .custom1),
                    TemplateSetup(dirName: "MyTemplate", configName: "SecondCustomTemplate", location: .custom2),
                ],
                searchName: "MyTemplate",
                useCustomPaths: true,
                expected: .success(configName: "FirstCustomTemplate")
            ),

            // Template only in custom path (not in global/project)
            FetchTemplateWithCustomPathsTestCase(
                description: "finds template when only exists in custom path",
                templates: [
                    TemplateSetup(dirName: "OnlyCustom", configName: "OnlyCustomTemplate", location: .custom1),
                    TemplateSetup(dirName: "OtherTemplate", configName: "OtherTemplate", location: .global),
                ],
                searchName: "OnlyCustomTemplate",
                useCustomPaths: true,
                expected: .success(configName: "OnlyCustomTemplate")
            ),

            // Custom path template not found when custom paths not enabled
            FetchTemplateWithCustomPathsTestCase(
                description: "does not find custom path template when custom paths disabled",
                templates: [
                    TemplateSetup(dirName: "CustomOnly", configName: "CustomOnly", location: .custom1),
                ],
                searchName: "CustomOnly",
                useCustomPaths: false,
                expected: .failure
            ),

            // Falls back to global when not in custom paths
            FetchTemplateWithCustomPathsTestCase(
                description: "falls back to global when not in custom paths",
                templates: [
                    TemplateSetup(dirName: "GlobalTemplate", configName: "GlobalTemplate", location: .global),
                ],
                searchName: "GlobalTemplate",
                useCustomPaths: true,
                expected: .success(configName: "GlobalTemplate")
            ),
        ]
    }

    // MARK: - listAll with Custom Search Paths Tests

    @Test
    func listAllIncludesCustomPathTemplates() async throws {
        let fileManager: any FileManagerProtocol = FileManager.default
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "templates-finder-list-test")

        defer {
            try? fileManager.removeItem(at: tempDir)
        }

        let projectDirectory = tempDir.appending(path: "project")
        let homeDirectory = tempDir.appending(path: "home")
        let customPath = tempDir.appending(path: "custom")

        try fileManager.createDirectory(at: projectDirectory.appending(path: ".eggs"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: homeDirectory.appending(path: ".eggs"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: customPath, withIntermediateDirectories: true)

        // Create templates
        let globalTemplateDir = homeDirectory.appending(path: ".eggs/GlobalTemplate")
        let projectTemplateDir = projectDirectory.appending(path: ".eggs/ProjectTemplate")
        let customTemplateDir = customPath.appending(path: "CustomTemplate")

        for (dir, name) in [(globalTemplateDir, "GlobalTemplate"), (projectTemplateDir, "ProjectTemplate"), (customTemplateDir, "CustomTemplate")] {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            let configContent = """
            name: \(name)
            description: Test template
            hatch:
              output: .
            """
            try fileManager.writeText(configContent, at: dir.appending(path: "config.yml"))
        }

        let finder = TemplatesFinder(
            fileManager: fileManager,
            projectDirectory: projectDirectory,
            workingDirectory: projectDirectory,
            homeDirectory: homeDirectory,
            additionalSearchPaths: [customPath]
        )

        let templates = try await finder.listAll(emitValidationErrorLog: false)

        #expect(templates.custom.count == 1)
        #expect(templates.custom.first?.config.name == "CustomTemplate")
        #expect(templates.global.count == 1)
        #expect(templates.global.first?.config.name == "GlobalTemplate")
        #expect(templates.project.count == 1)
        #expect(templates.project.first?.config.name == "ProjectTemplate")
        #expect(templates.all.count == 3)
    }

    @Test
    func existsReturnsTrueForCustomPathTemplate() async throws {
        let fileManager: any FileManagerProtocol = FileManager.default
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "templates-finder-exists-test")

        defer {
            try? fileManager.removeItem(at: tempDir)
        }

        let projectDirectory = tempDir.appending(path: "project")
        let homeDirectory = tempDir.appending(path: "home")
        let customPath = tempDir.appending(path: "custom")

        try fileManager.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: customPath, withIntermediateDirectories: true)

        // Create template only in custom path
        let customTemplateDir = customPath.appending(path: "CustomOnlyTemplate")
        try fileManager.createDirectory(at: customTemplateDir, withIntermediateDirectories: true)
        let configContent = """
        name: CustomOnlyTemplate
        description: Test template
        hatch:
          output: .
        """
        try fileManager.writeText(configContent, at: customTemplateDir.appending(path: "config.yml"))

        let finder = TemplatesFinder(
            fileManager: fileManager,
            projectDirectory: projectDirectory,
            workingDirectory: projectDirectory,
            homeDirectory: homeDirectory,
            additionalSearchPaths: [customPath]
        )

        #expect(finder.exists("CustomOnlyTemplate") == true)
        #expect(finder.exists("NonExistentTemplate") == false)
    }

    @Test
    func listWithLocationsIncludesCustomLocation() async throws {
        let fileManager: any FileManagerProtocol = FileManager.default
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "templates-finder-locations-test")

        defer {
            try? fileManager.removeItem(at: tempDir)
        }

        let projectDirectory = tempDir.appending(path: "project")
        let homeDirectory = tempDir.appending(path: "home")
        let customPath = tempDir.appending(path: "custom")

        try fileManager.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: customPath, withIntermediateDirectories: true)

        // Create template in custom path
        let customTemplateDir = customPath.appending(path: "CustomTemplate")
        try fileManager.createDirectory(at: customTemplateDir, withIntermediateDirectories: true)
        let configContent = """
        name: CustomTemplate
        description: Test template
        hatch:
          output: .
        """
        try fileManager.writeText(configContent, at: customTemplateDir.appending(path: "config.yml"))

        let finder = TemplatesFinder(
            fileManager: fileManager,
            projectDirectory: projectDirectory,
            workingDirectory: projectDirectory,
            homeDirectory: homeDirectory,
            additionalSearchPaths: [customPath]
        )

        let templatesWithLocations = try await finder.listWithLocations(emitValidationErrorLog: false)

        #expect(templatesWithLocations.count == 1)
        let first = templatesWithLocations.first
        #expect(first?.template.config.name == "CustomTemplate")
        if case .custom(let url) = first?.location {
            #expect(url == customPath)
        } else {
            Issue.record("Expected .custom location but got \(String(describing: first?.location))")
        }
    }
}
