@testable import EggKit
import FileManagerProtocol
import Foundation
import Testing

struct InstallRunnerTests {
    private let fileManager: any FileManagerProtocol = FileManager.default

    @Test(arguments: TestCase.allCases)
    func run(_ testCase: TestCase) async throws {
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "install-runner-test")
        defer { try? fileManager.removeItem(at: tempDir) }

        let projectDirectory = tempDir.appending(path: "project")
        let homeDirectory = tempDir.appending(path: "home")
        let clonedRepoDirectory = tempDir.appending(path: "cloned-repo")

        try fileManager.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: clonedRepoDirectory, withIntermediateDirectories: true)

        // Setup cloned repo templates
        try setupClonedRepoTemplates(
            templates: testCase.repoTemplates,
            repoDirectory: clonedRepoDirectory,
        )

        // Setup existing templates if any
        try setupExistingTemplates(
            templates: testCase.existingTemplates,
            projectDirectory: projectDirectory,
            homeDirectory: homeDirectory,
        )

        let mockGitCloner = MockGitCloner(clonedDirectory: clonedRepoDirectory, fileManager: fileManager)
        let mode = testCase.mode
        let location = testCase.location.toConcreteType(projectDirectory, workingDirectory: projectDirectory)

        let runner = InstallRunner(
            mode: mode,
            force: testCase.force,
            projectDirectory: projectDirectory,
            workingDirectory: projectDirectory,
            homeDirectory: homeDirectory,
            fileManager: fileManager,
            interaction: TestInteraction(),
            gitCloner: mockGitCloner,
            directoryCloner: APFSDirectoryCloner(),
            templateDiscoverer: TemplateDiscoverer(fileManager: fileManager),
        )

        switch testCase.expected {
        case let .success(expectedResult):
            let result = try await runner.run()
            verifyResult(result, expectedResult: expectedResult)
            try verifyInstalledTemplates(
                testCase: testCase,
                location: location,
                projectDirectory: projectDirectory,
                homeDirectory: homeDirectory,
            )
        case let .failure(expectedError):
            await #expect(throws: expectedError) {
                _ = try await runner.run()
            }
        }
    }

    private func setupClonedRepoTemplates(
        templates: [RepoTemplate],
        repoDirectory: URL,
    ) throws {
        for template in templates {
            let templateDir = repoDirectory.appending(path: template.name)
            try fileManager.createDirectory(at: templateDir, withIntermediateDirectories: true)

            let configPath = templateDir.appending(path: "config.yml")
            try fileManager.writeText(template.config, at: configPath)

            // Add a marker file to verify cloning
            let markerPath = templateDir.appending(path: "marker.txt")
            try fileManager.writeText("Template: \(template.name)", at: markerPath)
        }
    }

    private func setupExistingTemplates(
        templates: [ExistingTemplate],
        projectDirectory: URL,
        homeDirectory: URL,
    ) throws {
        for template in templates {
            let templatePath = template.location.toPath(
                templateName: template.name,
                projectDirectory: projectDirectory,
                homeDirectory: homeDirectory,
            )
            try fileManager.createDirectory(at: templatePath, withIntermediateDirectories: true)

            let configPath = templatePath.appending(path: "config.yml")
            try fileManager.writeText(template.config, at: configPath)
        }
    }

    private func verifyResult(_ result: InstallResult, expectedResult: ExpectedResult) {
        #expect(Set(result.installed) == Set(expectedResult.installed))
        #expect(result.skipped.count == expectedResult.skippedCount)
        #expect(result.failed.count == expectedResult.failedCount)

        for skipReason in expectedResult.skippedReasons {
            let hasSkipped = result.skipped.contains { $0.name == skipReason.name && $0.reason == skipReason.reason }
            #expect(hasSkipped, "Expected template '\(skipReason.name)' to be skipped with reason \(skipReason.reason)")
        }
    }

    private func verifyInstalledTemplates(
        testCase: TestCase,
        location _: TemplateLocationType,
        projectDirectory: URL,
        homeDirectory: URL,
    ) throws {
        for templateName in testCase.expectedInstalledNames {
            let templatePath = testCase.location.toPath(
                templateName: templateName,
                projectDirectory: projectDirectory,
                homeDirectory: homeDirectory,
            )
            #expect(fileManager.fileExists(atPath: templatePath.path(percentEncoded: false)))

            // Verify marker file was copied
            let markerPath = templatePath.appending(path: "marker.txt")
            #expect(fileManager.fileExists(atPath: markerPath.path(percentEncoded: false)))
        }
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let mode: InstallRunnerMode
        let location: TemplateLocationType.Kind
        let force: Bool
        let repoTemplates: [RepoTemplate]
        let existingTemplates: [ExistingTemplate]
        let expected: Result
        let expectedInstalledNames: [String]

        var testDescription: String {
            description
        }

        static let allCases: [TestCase] = [
            // Success cases - install all templates
            TestCase(
                description: "installs single template to project",
                mode: .direct(
                    source: .git(
                        url: GitURL(original: "https://github.com/user/repo.git", normalized: "https://github.com/user/repo.git"),
                        ref: nil,
                    ),
                    location: .project,
                    filter: .none,
                ),
                location: .project,
                force: false,
                repoTemplates: [
                    RepoTemplate(name: "swift-module", config: validConfig("Swift Module")),
                ],
                existingTemplates: [],
                expected: .success(ExpectedResult(
                    installed: ["swift-module"],
                    skippedCount: 0,
                    failedCount: 0,
                    skippedReasons: [],
                )),
                expectedInstalledNames: ["swift-module"],
            ),

            TestCase(
                description: "installs multiple templates to global",
                mode: .direct(
                    source: .git(
                        url: GitURL(original: "https://github.com/user/repo.git", normalized: "https://github.com/user/repo.git"),
                        ref: nil,
                    ),
                    location: .global,
                    filter: .none,
                ),
                location: .global,
                force: false,
                repoTemplates: [
                    RepoTemplate(name: "swift-module", config: validConfig("Swift Module")),
                    RepoTemplate(name: "swift-package", config: validConfig("Swift Package")),
                    RepoTemplate(name: "swiftui-view", config: validConfig("SwiftUI View")),
                ],
                existingTemplates: [],
                expected: .success(ExpectedResult(
                    installed: ["swift-module", "swift-package", "swiftui-view"],
                    skippedCount: 0,
                    failedCount: 0,
                    skippedReasons: [],
                )),
                expectedInstalledNames: ["swift-module", "swift-package", "swiftui-view"],
            ),

            // Filter cases - include filter
            TestCase(
                description: "installs only included templates",
                mode: .direct(
                    source: .git(
                        url: GitURL(original: "https://github.com/user/repo.git", normalized: "https://github.com/user/repo.git"),
                        ref: nil,
                    ),
                    location: .project,
                    filter: .include(["swift-module"]),
                ),
                location: .project,
                force: false,
                repoTemplates: [
                    RepoTemplate(name: "swift-module", config: validConfig("Swift Module")),
                    RepoTemplate(name: "swift-package", config: validConfig("Swift Package")),
                    RepoTemplate(name: "swiftui-view", config: validConfig("SwiftUI View")),
                ],
                existingTemplates: [],
                expected: .success(ExpectedResult(
                    installed: ["swift-module"],
                    skippedCount: 2,
                    failedCount: 0,
                    skippedReasons: [
                        (name: "swift-package", reason: .excludedByFilter),
                        (name: "swiftui-view", reason: .excludedByFilter),
                    ],
                )),
                expectedInstalledNames: ["swift-module"],
            ),

            // Filter cases - exclude filter
            TestCase(
                description: "skips excluded templates",
                mode: .direct(
                    source: .git(
                        url: GitURL(original: "https://github.com/user/repo.git", normalized: "https://github.com/user/repo.git"),
                        ref: nil,
                    ),
                    location: .project,
                    filter: .exclude(["swiftui-view"]),
                ),
                location: .project,
                force: false,
                repoTemplates: [
                    RepoTemplate(name: "swift-module", config: validConfig("Swift Module")),
                    RepoTemplate(name: "swift-package", config: validConfig("Swift Package")),
                    RepoTemplate(name: "swiftui-view", config: validConfig("SwiftUI View")),
                ],
                existingTemplates: [],
                expected: .success(ExpectedResult(
                    installed: ["swift-module", "swift-package"],
                    skippedCount: 1,
                    failedCount: 0,
                    skippedReasons: [
                        (name: "swiftui-view", reason: .excludedByFilter),
                    ],
                )),
                expectedInstalledNames: ["swift-module", "swift-package"],
            ),

            // Already exists cases
            TestCase(
                description: "skips existing template without force",
                mode: .direct(
                    source: .git(
                        url: GitURL(original: "https://github.com/user/repo.git", normalized: "https://github.com/user/repo.git"),
                        ref: nil,
                    ),
                    location: .project,
                    filter: .none,
                ),
                location: .project,
                force: false,
                repoTemplates: [
                    RepoTemplate(name: "swift-module", config: validConfig("Swift Module")),
                    RepoTemplate(name: "swift-package", config: validConfig("Swift Package")),
                ],
                existingTemplates: [
                    ExistingTemplate(name: "swift-module", location: .project, config: validConfig("Existing Module")),
                ],
                expected: .success(ExpectedResult(
                    installed: ["swift-package"],
                    skippedCount: 1,
                    failedCount: 0,
                    skippedReasons: [
                        (name: "swift-module", reason: .alreadyExists),
                    ],
                )),
                expectedInstalledNames: ["swift-package"],
            ),

            TestCase(
                description: "overwrites existing template with force",
                mode: .direct(
                    source: .git(
                        url: GitURL(original: "https://github.com/user/repo.git", normalized: "https://github.com/user/repo.git"),
                        ref: nil,
                    ),
                    location: .project,
                    filter: .none,
                ),
                location: .project,
                force: true,
                repoTemplates: [
                    RepoTemplate(name: "swift-module", config: validConfig("Swift Module")),
                ],
                existingTemplates: [
                    ExistingTemplate(name: "swift-module", location: .project, config: validConfig("Existing Module")),
                ],
                expected: .success(ExpectedResult(
                    installed: ["swift-module"],
                    skippedCount: 0,
                    failedCount: 0,
                    skippedReasons: [],
                )),
                expectedInstalledNames: ["swift-module"],
            ),

            // Error cases
            TestCase(
                description: "throws error when no templates found",
                mode: .direct(
                    source: .git(
                        url: GitURL(original: "https://github.com/user/empty-repo.git", normalized: "https://github.com/user/empty-repo.git"),
                        ref: nil,
                    ),
                    location: .project,
                    filter: .none,
                ),
                location: .project,
                force: false,
                repoTemplates: [],
                existingTemplates: [],
                expected: .failure(.noTemplatesFound(source: .git(
                    url: GitURL(original: "https://github.com/user/empty-repo.git", normalized: "https://github.com/user/empty-repo.git"),
                    ref: nil,
                ))),
                expectedInstalledNames: [],
            ),

            // Combined filter and existing
            TestCase(
                description: "handles both filter and existing templates",
                mode: .direct(
                    source: .git(
                        url: GitURL(original: "https://github.com/user/repo.git", normalized: "https://github.com/user/repo.git"),
                        ref: nil,
                    ),
                    location: .project,
                    filter: .exclude(["swiftui-view"]),
                ),
                location: .project,
                force: false,
                repoTemplates: [
                    RepoTemplate(name: "swift-module", config: validConfig("Swift Module")),
                    RepoTemplate(name: "swift-package", config: validConfig("Swift Package")),
                    RepoTemplate(name: "swiftui-view", config: validConfig("SwiftUI View")),
                ],
                existingTemplates: [
                    ExistingTemplate(name: "swift-module", location: .project, config: validConfig("Existing Module")),
                ],
                expected: .success(ExpectedResult(
                    installed: ["swift-package"],
                    skippedCount: 2,
                    failedCount: 0,
                    skippedReasons: [
                        (name: "swift-module", reason: .alreadyExists),
                        (name: "swiftui-view", reason: .excludedByFilter),
                    ],
                )),
                expectedInstalledNames: ["swift-package"],
            ),

            // Git ref cases
            TestCase(
                description: "installs from specific branch",
                mode: .direct(
                    source: .git(
                        url: GitURL(original: "https://github.com/user/repo.git", normalized: "https://github.com/user/repo.git"),
                        ref: .branch("develop"),
                    ),
                    location: .project,
                    filter: .none,
                ),
                location: .project,
                force: false,
                repoTemplates: [
                    RepoTemplate(name: "swift-module", config: validConfig("Swift Module")),
                ],
                existingTemplates: [],
                expected: .success(ExpectedResult(
                    installed: ["swift-module"],
                    skippedCount: 0,
                    failedCount: 0,
                    skippedReasons: [],
                )),
                expectedInstalledNames: ["swift-module"],
            ),

            TestCase(
                description: "installs from specific tag",
                mode: .direct(
                    source: .git(
                        url: GitURL(original: "https://github.com/user/repo.git", normalized: "https://github.com/user/repo.git"),
                        ref: .tag("v1.0.0"),
                    ),
                    location: .project,
                    filter: .none,
                ),
                location: .project,
                force: false,
                repoTemplates: [
                    RepoTemplate(name: "swift-module", config: validConfig("Swift Module")),
                ],
                existingTemplates: [],
                expected: .success(ExpectedResult(
                    installed: ["swift-module"],
                    skippedCount: 0,
                    failedCount: 0,
                    skippedReasons: [],
                )),
                expectedInstalledNames: ["swift-module"],
            ),

            TestCase(
                description: "installs from specific revision",
                mode: .direct(
                    source: .git(
                        url: GitURL(original: "https://github.com/user/repo.git", normalized: "https://github.com/user/repo.git"),
                        ref: .revision("abc123"),
                    ),
                    location: .project,
                    filter: .none,
                ),
                location: .project,
                force: false,
                repoTemplates: [
                    RepoTemplate(name: "swift-module", config: validConfig("Swift Module")),
                ],
                existingTemplates: [],
                expected: .success(ExpectedResult(
                    installed: ["swift-module"],
                    skippedCount: 0,
                    failedCount: 0,
                    skippedReasons: [],
                )),
                expectedInstalledNames: ["swift-module"],
            ),
        ]

        enum Result {
            case success(ExpectedResult)
            case failure(InstallRunner.Error)
        }
    }

    struct RepoTemplate {
        let name: String
        let config: String
    }

    struct ExistingTemplate {
        let name: String
        let location: TemplateLocationType.Kind
        let config: String
    }

    struct ExpectedResult {
        let installed: [String]
        let skippedCount: Int
        let failedCount: Int
        let skippedReasons: [(name: String, reason: SkipReason)]
    }
}

private struct MockGitCloner: GitCloning {
    let clonedDirectory: URL
    let fileManager: any FileManagerProtocol

    func clone(url _: GitURL, to destination: URL, ref _: GitRef?) async throws {
        // Copy the cloned repo directory to destination
        let contents = try fileManager.contentsOfDirectory(
            at: clonedDirectory,
            includingPropertiesForKeys: nil,
            options: [],
        )

        for item in contents {
            let destItem = destination.appending(path: item.lastPathComponent)
            try fileManager.copyItem(at: item, to: destItem)
        }
    }
}

private extension TemplateLocationType.Kind {
    func toPath(
        templateName: String,
        projectDirectory: URL,
        homeDirectory: URL,
    ) -> URL {
        switch self {
        case .global:
            homeDirectory.appending(path: ".eggs").appending(path: templateName)
        case .project:
            projectDirectory.appending(path: ".eggs").appending(path: templateName)
        }
    }
}

private func validConfig(_ name: String) -> String {
    """
    name: "\(name)"
    description: "A test template"
    hatch:
      output: "./output"
    """
}
