@testable import EggKit
import FileManagerProtocol
import Foundation
import Testing

struct TemplateDiscovererTests {
    private let fileManager: any FileManagerProtocol = FileManager.default

    @Test(arguments: TestCase.allCases)
    func discoverTemplates(_ testCase: TestCase) async throws {
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "template-discoverer-test")
        defer { try? fileManager.removeItem(at: tempDir) }

        // Setup directory structure
        try testCase.setup(in: tempDir, fileManager: fileManager)

        let discoverer = TemplateDiscoverer(fileManager: fileManager)
        let templates = try await discoverer.discoverTemplates(in: tempDir)

        #expect(templates.count == testCase.expectedCount)

        for expectedName in testCase.expectedNames {
            let found = templates.contains { $0.name == expectedName }
            #expect(found, "Expected to find template '\(expectedName)'")
        }

        for excludedName in testCase.excludedNames {
            let found = templates.contains { $0.name == excludedName }
            #expect(!found, "Expected NOT to find template '\(excludedName)'")
        }
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let directories: [DirectorySpec]
        let expectedCount: Int
        let expectedNames: [String]
        let excludedNames: [String]

        var testDescription: String { description }

        func setup(in baseDir: URL, fileManager: any FileManagerProtocol) throws {
            for dir in directories {
                let dirPath = baseDir.appending(path: dir.name)
                try fileManager.createDirectory(at: dirPath, withIntermediateDirectories: true)

                if let config = dir.configContent {
                    let configPath = dirPath.appending(path: "config.yml")
                    try config.write(to: configPath, atomically: true, encoding: .utf8)
                }

                if let readme = dir.readmeContent {
                    let readmePath = dirPath.appending(path: "README.md")
                    try readme.write(to: readmePath, atomically: true, encoding: .utf8)
                }
            }
        }

        static let allCases: [TestCase] = [
            TestCase(
                description: "finds single valid template",
                directories: [
                    DirectorySpec(name: "my-template", configContent: validConfig("My Template")),
                ],
                expectedCount: 1,
                expectedNames: ["my-template"],
                excludedNames: []
            ),
            TestCase(
                description: "finds multiple valid templates",
                directories: [
                    DirectorySpec(name: "swift-module", configContent: validConfig("Swift Module")),
                    DirectorySpec(name: "swift-package", configContent: validConfig("Swift Package")),
                    DirectorySpec(name: "swiftui-view", configContent: validConfig("SwiftUI View")),
                ],
                expectedCount: 3,
                expectedNames: ["swift-module", "swift-package", "swiftui-view"],
                excludedNames: []
            ),
            TestCase(
                description: "skips directory without config.yml",
                directories: [
                    DirectorySpec(name: "no-config", configContent: nil),
                    DirectorySpec(name: "valid-template", configContent: validConfig("Valid Template")),
                ],
                expectedCount: 1,
                expectedNames: ["valid-template"],
                excludedNames: ["no-config"]
            ),
            TestCase(
                description: "skips directory with invalid YAML",
                directories: [
                    DirectorySpec(name: "invalid-yaml", configContent: "invalid: yaml: content"),
                    DirectorySpec(name: "valid-template", configContent: validConfig("Valid Template")),
                ],
                expectedCount: 1,
                expectedNames: ["valid-template"],
                excludedNames: ["invalid-yaml"]
            ),
            TestCase(
                description: "skips directory with validation error (empty output)",
                directories: [
                    DirectorySpec(name: "invalid-config", configContent: configWithEmptyOutput()),
                    DirectorySpec(name: "valid-template", configContent: validConfig("Valid Template")),
                ],
                expectedCount: 1,
                expectedNames: ["valid-template"],
                excludedNames: ["invalid-config"]
            ),
            TestCase(
                description: "skips hidden directories",
                directories: [
                    DirectorySpec(name: ".hidden-template", configContent: validConfig("Hidden")),
                    DirectorySpec(name: "visible-template", configContent: validConfig("Visible")),
                ],
                expectedCount: 1,
                expectedNames: ["visible-template"],
                excludedNames: [".hidden-template"]
            ),
            TestCase(
                description: "skips .git directory",
                directories: [
                    DirectorySpec(name: ".git", configContent: validConfig("Git")),
                    DirectorySpec(name: "real-template", configContent: validConfig("Real")),
                ],
                expectedCount: 1,
                expectedNames: ["real-template"],
                excludedNames: [".git"]
            ),
            TestCase(
                description: "skips .github directory",
                directories: [
                    DirectorySpec(name: ".github", configContent: validConfig("GitHub")),
                    DirectorySpec(name: "real-template", configContent: validConfig("Real")),
                ],
                expectedCount: 1,
                expectedNames: ["real-template"],
                excludedNames: [".github"]
            ),
            TestCase(
                description: "skips node_modules directory",
                directories: [
                    DirectorySpec(name: "node_modules", configContent: validConfig("Node Modules")),
                    DirectorySpec(name: "real-template", configContent: validConfig("Real")),
                ],
                expectedCount: 1,
                expectedNames: ["real-template"],
                excludedNames: ["node_modules"]
            ),
            TestCase(
                description: "returns empty list for empty repository",
                directories: [],
                expectedCount: 0,
                expectedNames: [],
                excludedNames: []
            ),
            TestCase(
                description: "returns empty list when all templates are invalid",
                directories: [
                    DirectorySpec(name: "invalid1", configContent: "invalid: yaml: content"),
                    DirectorySpec(name: "invalid2", configContent: configWithEmptyOutput()),
                    DirectorySpec(name: "no-config", configContent: nil),
                ],
                expectedCount: 0,
                expectedNames: [],
                excludedNames: ["invalid1", "invalid2", "no-config"]
            ),
        ]

        // Helper functions for config content
        private static func validConfig(_ name: String) -> String {
            """
            name: "\(name)"
            description: "A test template"
            hatch:
              output: "./output"
            """
        }

        private static func configWithEmptyOutput() -> String {
            """
            name: "Test"
            description: "Test"
            hatch:
              output: ""
            """
        }
    }

    struct DirectorySpec {
        let name: String
        let configContent: String?
        let readmeContent: String?

        init(name: String, configContent: String?, readmeContent: String? = nil) {
            self.name = name
            self.configContent = configContent
            self.readmeContent = readmeContent
        }
    }
}
