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

    // MARK: - Global install manifest registration

    @Test("global install with --tag parsed as SemVer registers an exact: requirement")
    func registersExactForSemVerTag() async throws {
        let (runner, manifestPath, cleanup) = try makeRegistrationEnvironment(ref: .tag("1.2.0"))
        defer { cleanup() }

        let result = try await runner.run()
        #expect(result.manifestUpdated == manifestPath.path(percentEncoded: false))

        let manifest = try ManifestLoader(fileManager: fileManager).load(manifestPath: manifestPath)
        let entry = try #require(manifest.templates.first)
        #expect(entry.declaredURL == "https://github.com/user/repo.git")
        guard case let .git(_, requirement) = entry.source else {
            Issue.record("expected a git source")
            return
        }
        #expect(requirement == .exact(SemanticVersion(major: 1, minor: 2, patch: 0)))

        let lockfilePath = ManifestLocator.lockfileURL(forManifestAt: manifestPath)
        let lockfile = try #require(try LockfileStore(fileManager: fileManager).load(lockfilePath: lockfilePath))
        #expect(lockfile.entry(forURL: "https://github.com/user/repo.git") != nil)
    }

    @Test("global install with a non-SemVer --tag registers a revision: requirement")
    func registersRevisionForNonSemVerTag() async throws {
        let (runner, manifestPath, cleanup) = try makeRegistrationEnvironment(ref: .tag("release-candidate"))
        defer { cleanup() }

        _ = try await runner.run()

        let manifest = try ManifestLoader(fileManager: fileManager).load(manifestPath: manifestPath)
        let entry = try #require(manifest.templates.first)
        guard case let .git(_, requirement) = entry.source else {
            Issue.record("expected a git source")
            return
        }
        guard case .revision = requirement else {
            Issue.record("expected .revision, got \(requirement)")
            return
        }
    }

    @Test("global install with --branch registers a branch: requirement")
    func registersBranchRequirement() async throws {
        let (runner, manifestPath, cleanup) = try makeRegistrationEnvironment(ref: .branch("develop"))
        defer { cleanup() }

        _ = try await runner.run()

        let manifest = try ManifestLoader(fileManager: fileManager).load(manifestPath: manifestPath)
        let entry = try #require(manifest.templates.first)
        guard case let .git(_, requirement) = entry.source else {
            Issue.record("expected a git source")
            return
        }
        #expect(requirement == .branch("develop"))
    }

    @Test("global install with --revision registers the SHA verbatim")
    func registersRevisionVerbatim() async throws {
        let sha = String(repeating: "f", count: 40)
        let (runner, manifestPath, cleanup) = try makeRegistrationEnvironment(ref: .revision(sha))
        defer { cleanup() }

        _ = try await runner.run()

        let manifest = try ManifestLoader(fileManager: fileManager).load(manifestPath: manifestPath)
        let entry = try #require(manifest.templates.first)
        guard case let .git(_, requirement) = entry.source else {
            Issue.record("expected a git source")
            return
        }
        #expect(requirement == .revision(sha))
    }

    @Test("global install with no ref registers a revision: requirement resolved from HEAD")
    func registersRevisionForDefaultBranch() async throws {
        let (runner, manifestPath, cleanup) = try makeRegistrationEnvironment(ref: nil)
        defer { cleanup() }

        _ = try await runner.run()

        let manifest = try ManifestLoader(fileManager: fileManager).load(manifestPath: manifestPath)
        let entry = try #require(manifest.templates.first)
        guard case let .git(_, requirement) = entry.source else {
            Issue.record("expected a git source")
            return
        }
        guard case .revision = requirement else {
            Issue.record("expected .revision, got \(requirement)")
            return
        }
    }

    @Test("project-scope install does not touch any manifest")
    func projectInstallDoesNotRegister() async throws {
        let (tempDir, projectDirectory, homeDirectory, sourceDirectory) = try makeRegistrationTestDirs(sourceDirectoryName: "cloned-repo")
        defer { try? fileManager.removeItem(at: tempDir) }

        let url = GitURL(original: "https://github.com/user/repo.git", normalized: "https://github.com/user/repo.git")
        let runner = InstallRunner(
            mode: .direct(source: .git(url: url, ref: nil), location: .project, filter: .none),
            force: false,
            projectDirectory: projectDirectory,
            workingDirectory: projectDirectory,
            homeDirectory: homeDirectory,
            fileManager: fileManager,
            interaction: TestInteraction(),
            gitCloner: MockGitCloner(clonedDirectory: sourceDirectory, fileManager: fileManager),
            directoryCloner: APFSDirectoryCloner(),
            templateDiscoverer: TemplateDiscoverer(fileManager: fileManager),
        )

        let result = try await runner.run()
        #expect(result.manifestUpdated == nil)

        let projectManifestPath = projectDirectory.appending(path: "eggs.yml")
        let globalManifestPath = homeDirectory.appending(path: ".config").appending(path: "egg").appending(path: "eggs.yml")
        #expect(!fileManager.exists(projectManifestPath))
        #expect(!fileManager.exists(globalManifestPath))
    }

    @Test("local-path install does not touch any manifest")
    func localPathInstallDoesNotRegister() async throws {
        let (tempDir, projectDirectory, homeDirectory, sourceDirectory) = try makeRegistrationTestDirs(sourceDirectoryName: "local-templates")
        defer { try? fileManager.removeItem(at: tempDir) }

        let runner = InstallRunner(
            mode: .direct(source: .local(path: sourceDirectory), location: .global, filter: .none),
            force: false,
            projectDirectory: projectDirectory,
            workingDirectory: projectDirectory,
            homeDirectory: homeDirectory,
            fileManager: fileManager,
            interaction: TestInteraction(),
            gitCloner: MockGitCloner(clonedDirectory: sourceDirectory, fileManager: fileManager),
            directoryCloner: APFSDirectoryCloner(),
            templateDiscoverer: TemplateDiscoverer(fileManager: fileManager),
        )

        let result = try await runner.run()
        #expect(result.manifestUpdated == nil)

        let globalManifestPath = homeDirectory.appending(path: ".config").appending(path: "egg").appending(path: "eggs.yml")
        #expect(!fileManager.exists(globalManifestPath))
    }

    @Test("re-installing the same URL replaces the manifest entry rather than duplicating it")
    func reinstallReplacesEntry() async throws {
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "install-registration-test")
        defer { try? fileManager.removeItem(at: tempDir) }
        let projectDirectory = tempDir.appending(path: "project")
        let homeDirectory = tempDir.appending(path: "home")
        let clonedRepoDirectory = tempDir.appending(path: "cloned-repo")
        try fileManager.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: clonedRepoDirectory, withIntermediateDirectories: true)
        try setupClonedRepoTemplates(
            templates: [RepoTemplate(name: "swift-module", config: Self.validConfig("Swift Module"))],
            repoDirectory: clonedRepoDirectory,
        )
        let manifestPath = homeDirectory.appending(path: ".config").appending(path: "egg").appending(path: "eggs.yml")

        let firstRunner = makeRegistrationRunner(tempDir: tempDir, ref: .branch("main"), force: true)
        _ = try await firstRunner.run()

        // Re-run with a different ref against the same environment (force
        // so the already-installed template doesn't get skipped).
        let secondRunner = makeRegistrationRunner(tempDir: tempDir, ref: .tag("2.0.0"), force: true)
        _ = try await secondRunner.run()

        let manifest = try ManifestLoader(fileManager: fileManager).load(manifestPath: manifestPath)
        #expect(manifest.templates.count == 1)
        guard case let .git(_, requirement) = manifest.templates[0].source else {
            Issue.record("expected a git source")
            return
        }
        #expect(requirement == .exact(SemanticVersion(major: 2, minor: 0, patch: 0)))
    }

    /// Creates a fresh temp dir with `project`/`home`/`<sourceDirectoryName>`
    /// subdirectories, seeded with one template in the source directory.
    private func makeRegistrationTestDirs(
        sourceDirectoryName: String,
    ) throws -> (tempDir: URL, projectDirectory: URL, homeDirectory: URL, sourceDirectory: URL) {
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "install-registration-test")
        let projectDirectory = tempDir.appending(path: "project")
        let homeDirectory = tempDir.appending(path: "home")
        let sourceDirectory = tempDir.appending(path: sourceDirectoryName)
        try fileManager.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try setupClonedRepoTemplates(
            templates: [RepoTemplate(name: "swift-module", config: Self.validConfig("Swift Module"))],
            repoDirectory: sourceDirectory,
        )
        return (tempDir, projectDirectory, homeDirectory, sourceDirectory)
    }

    private func makeRegistrationRunner(
        tempDir: URL,
        ref: GitRef?,
        filter: TemplateFilter = .none,
        force: Bool = false,
    ) -> InstallRunner {
        let projectDirectory = tempDir.appending(path: "project")
        let homeDirectory = tempDir.appending(path: "home")
        let clonedRepoDirectory = tempDir.appending(path: "cloned-repo")
        let mockGitCloner = MockGitCloner(clonedDirectory: clonedRepoDirectory, fileManager: fileManager)
        let url = GitURL(original: "https://github.com/user/repo.git", normalized: "https://github.com/user/repo.git")
        return InstallRunner(
            mode: .direct(source: .git(url: url, ref: ref), location: .global, filter: filter),
            force: force,
            projectDirectory: projectDirectory,
            workingDirectory: projectDirectory,
            homeDirectory: homeDirectory,
            fileManager: fileManager,
            interaction: TestInteraction(),
            gitCloner: mockGitCloner,
            directoryCloner: APFSDirectoryCloner(),
            templateDiscoverer: TemplateDiscoverer(fileManager: fileManager),
            gitTagLister: MockGitTagLister(),
        )
    }

    private func makeRegistrationEnvironment(
        ref: GitRef?,
        filter: TemplateFilter = .none,
        force: Bool = false,
    ) throws -> (runner: InstallRunner, manifestPath: URL, cleanup: () -> Void) {
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "install-registration-test")
        let projectDirectory = tempDir.appending(path: "project")
        let homeDirectory = tempDir.appending(path: "home")
        let clonedRepoDirectory = tempDir.appending(path: "cloned-repo")

        try fileManager.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: clonedRepoDirectory, withIntermediateDirectories: true)
        try setupClonedRepoTemplates(
            templates: [RepoTemplate(name: "swift-module", config: Self.validConfig("Swift Module"))],
            repoDirectory: clonedRepoDirectory,
        )

        let runner = makeRegistrationRunner(tempDir: tempDir, ref: ref, filter: filter, force: force)
        let manifestPath = homeDirectory.appending(path: ".config").appending(path: "egg").appending(path: "eggs.yml")
        return (runner, manifestPath, { try? fileManager.removeItem(at: tempDir) })
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
                    RepoTemplate(name: "swift-module", config: InstallRunnerTests.validConfig("Swift Module")),
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
                    RepoTemplate(name: "swift-module", config: InstallRunnerTests.validConfig("Swift Module")),
                    RepoTemplate(name: "swift-package", config: InstallRunnerTests.validConfig("Swift Package")),
                    RepoTemplate(name: "swiftui-view", config: InstallRunnerTests.validConfig("SwiftUI View")),
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
                    RepoTemplate(name: "swift-module", config: InstallRunnerTests.validConfig("Swift Module")),
                    RepoTemplate(name: "swift-package", config: InstallRunnerTests.validConfig("Swift Package")),
                    RepoTemplate(name: "swiftui-view", config: InstallRunnerTests.validConfig("SwiftUI View")),
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
                    RepoTemplate(name: "swift-module", config: InstallRunnerTests.validConfig("Swift Module")),
                    RepoTemplate(name: "swift-package", config: InstallRunnerTests.validConfig("Swift Package")),
                    RepoTemplate(name: "swiftui-view", config: InstallRunnerTests.validConfig("SwiftUI View")),
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
                    RepoTemplate(name: "swift-module", config: InstallRunnerTests.validConfig("Swift Module")),
                    RepoTemplate(name: "swift-package", config: InstallRunnerTests.validConfig("Swift Package")),
                ],
                existingTemplates: [
                    ExistingTemplate(name: "swift-module", location: .project, config: InstallRunnerTests.validConfig("Existing Module")),
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
                    RepoTemplate(name: "swift-module", config: InstallRunnerTests.validConfig("Swift Module")),
                ],
                existingTemplates: [
                    ExistingTemplate(name: "swift-module", location: .project, config: InstallRunnerTests.validConfig("Existing Module")),
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
                    RepoTemplate(name: "swift-module", config: InstallRunnerTests.validConfig("Swift Module")),
                    RepoTemplate(name: "swift-package", config: InstallRunnerTests.validConfig("Swift Package")),
                    RepoTemplate(name: "swiftui-view", config: InstallRunnerTests.validConfig("SwiftUI View")),
                ],
                existingTemplates: [
                    ExistingTemplate(name: "swift-module", location: .project, config: InstallRunnerTests.validConfig("Existing Module")),
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
                    RepoTemplate(name: "swift-module", config: InstallRunnerTests.validConfig("Swift Module")),
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
                    RepoTemplate(name: "swift-module", config: InstallRunnerTests.validConfig("Swift Module")),
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
                    RepoTemplate(name: "swift-module", config: InstallRunnerTests.validConfig("Swift Module")),
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

        var testDescription: String {
            description
        }

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

    fileprivate static func validConfig(_ name: String) -> String {
        """
        name: "\(name)"
        description: "A test template"
        hatch:
          output: "./output"
        """
    }
}

private struct MockGitCloner: GitCloning {
    let clonedDirectory: URL
    let fileManager: any FileManagerProtocol
    var revision: String = "abc123abc123abc123abc123abc123abc123ab"

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

    func headRevision(at _: URL) async throws -> String {
        revision
    }
}

/// Reports no tags for any URL, so requirement resolution always falls back
/// to the cloned directory's HEAD instead of hitting the network.
private struct MockGitTagLister: GitTagListing {
    func listTags(url _: GitURL) async throws -> [GitRemoteTag] {
        []
    }

    func remoteBranchRevision(url _: GitURL, branch _: String) async throws -> String? {
        nil
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
