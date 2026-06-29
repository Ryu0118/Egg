@testable import EggKit
import FileManagerProtocol
import Foundation
import Testing

struct InstallArgumentsValidatorTests {
    private let fileManager: any FileManagerProtocol = FileManager.default

    @Test(arguments: TestCase.allCases)
    func validate(_ testCase: TestCase) async throws {
        let validator = InstallArgumentsValidator(
            url: testCase.url,
            branch: testCase.branch,
            tag: testCase.tag,
            revision: testCase.revision,
            templates: testCase.templates,
            excludeTemplates: testCase.excludeTemplates,
            global: testCase.global,
            projectDirectory: testCase.projectDirectory,
            workingDirectory: testCase.workingDirectory,
            homeDirectory: testCase.homeDirectory,
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

    @Test
    func `validate local path absolute`() async throws {
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "install-validator-test")
        defer { try? fileManager.removeItem(at: tempDir) }

        let templatesDir = tempDir.appending(path: "templates")
        try fileManager.createDirectory(at: templatesDir, withIntermediateDirectories: true)

        let validator = InstallArgumentsValidator(
            url: templatesDir.path(percentEncoded: false),
            branch: nil,
            tag: nil,
            revision: nil,
            templates: [],
            excludeTemplates: [],
            global: false,
            projectDirectory: tempDir,
            workingDirectory: tempDir,
            homeDirectory: tempDir,
        )

        let result = try await validator.validate()
        guard case let .direct(source, location, filter) = result else {
            Issue.record("Expected direct mode")
            return
        }
        guard case let .local(path) = source else {
            Issue.record("Expected local source")
            return
        }
        #expect(path.standardizedFileURL.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/")) == templatesDir.standardizedFileURL.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        #expect(location == .project)
        #expect(filter == .none)
    }

    @Test
    func `validate local path relative`() async throws {
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "install-validator-test")
        defer { try? fileManager.removeItem(at: tempDir) }

        let templatesDir = tempDir.appending(path: "templates")
        try fileManager.createDirectory(at: templatesDir, withIntermediateDirectories: true)

        let validator = InstallArgumentsValidator(
            url: "./templates",
            branch: nil,
            tag: nil,
            revision: nil,
            templates: [],
            excludeTemplates: [],
            global: true,
            projectDirectory: tempDir,
            workingDirectory: tempDir,
            homeDirectory: tempDir,
        )

        let result = try await validator.validate()
        guard case let .direct(source, location, filter) = result else {
            Issue.record("Expected direct mode")
            return
        }
        guard case let .local(path) = source else {
            Issue.record("Expected local source")
            return
        }
        #expect(path.standardizedFileURL.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/")) == templatesDir.standardizedFileURL.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        #expect(location == .global)
        #expect(filter == .none)
    }

    @Test
    func `validate local path plain relative`() async throws {
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "install-validator-test")
        defer { try? fileManager.removeItem(at: tempDir) }

        let nestedDir = tempDir.appending(path: ".claude/plugins/my-plugin")
        try fileManager.createDirectory(at: nestedDir, withIntermediateDirectories: true)

        let validator = InstallArgumentsValidator(
            url: ".claude/plugins/my-plugin",
            branch: nil,
            tag: nil,
            revision: nil,
            templates: [],
            excludeTemplates: [],
            global: true,
            projectDirectory: tempDir,
            workingDirectory: tempDir,
            homeDirectory: tempDir,
        )

        let result = try await validator.validate()
        guard case let .direct(source, location, filter) = result else {
            Issue.record("Expected direct mode")
            return
        }
        guard case let .local(path) = source else {
            Issue.record("Expected local source")
            return
        }
        #expect(path.standardizedFileURL.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/")) == nestedDir.standardizedFileURL.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        #expect(location == .global)
        #expect(filter == .none)
    }

    @Test
    func `validate local path with filter`() async throws {
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "install-validator-test")
        defer { try? fileManager.removeItem(at: tempDir) }

        let templatesDir = tempDir.appending(path: "templates")
        try fileManager.createDirectory(at: templatesDir, withIntermediateDirectories: true)

        let validator = InstallArgumentsValidator(
            url: templatesDir.path(percentEncoded: false),
            branch: nil,
            tag: nil,
            revision: nil,
            templates: ["swift-module"],
            excludeTemplates: [],
            global: false,
            projectDirectory: tempDir,
            workingDirectory: tempDir,
            homeDirectory: tempDir,
        )

        let result = try await validator.validate()
        guard case let .direct(source, location, filter) = result else {
            Issue.record("Expected direct mode")
            return
        }
        guard case let .local(path) = source else {
            Issue.record("Expected local source")
            return
        }
        #expect(path.standardizedFileURL.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/")) == templatesDir.standardizedFileURL.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        #expect(location == .project)
        #expect(filter == .include(["swift-module"]))
    }

    @Test
    func `validate local path with ref option throws error`() async throws {
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "install-validator-test")
        defer { try? fileManager.removeItem(at: tempDir) }

        let templatesDir = tempDir.appending(path: "templates")
        try fileManager.createDirectory(at: templatesDir, withIntermediateDirectories: true)

        let validator = InstallArgumentsValidator(
            url: templatesDir.path(percentEncoded: false),
            branch: "main",
            tag: nil,
            revision: nil,
            templates: [],
            excludeTemplates: [],
            global: false,
            projectDirectory: tempDir,
            workingDirectory: tempDir,
            homeDirectory: tempDir,
        )

        await #expect(throws: InstallArgumentsValidator.Error.refOptionsNotAllowedForLocalPath) {
            _ = try await validator.validate()
        }
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let url: String?
        let branch: String?
        let tag: String?
        let revision: String?
        let templates: [String]
        let excludeTemplates: [String]
        let global: Bool
        let projectDirectory: URL
        let workingDirectory: URL
        let homeDirectory: URL
        let expected: Result

        var testDescription: String {
            description
        }

        private static let defaultProjectDirectory = URL(filePath: "/project")
        private static let defaultWorkingDirectory = URL(filePath: "/project")
        private static let defaultHomeDirectory = URL(filePath: "/home")

        static func makeTestCase(
            description: String,
            url: String? = nil,
            branch: String? = nil,
            tag: String? = nil,
            revision: String? = nil,
            templates: [String] = [],
            excludeTemplates: [String] = [],
            global: Bool = false,
            expected: Result,
        ) -> TestCase {
            TestCase(
                description: description,
                url: url,
                branch: branch,
                tag: tag,
                revision: revision,
                templates: templates,
                excludeTemplates: excludeTemplates,
                global: global,
                projectDirectory: defaultProjectDirectory,
                workingDirectory: defaultWorkingDirectory,
                homeDirectory: defaultHomeDirectory,
                expected: expected,
            )
        }

        static let allCases: [TestCase] = [
            // Interactive mode
            makeTestCase(
                description: "returns interactive mode when URL is nil",
                expected: .success(.interactive),
            ),

            // Direct mode - Git URL only (default branch, no filter)
            makeTestCase(
                description: "returns direct mode with git source when only URL is provided (HTTPS)",
                url: "https://github.com/user/repo.git",
                expected: .success(.direct(
                    source: .git(
                        url: GitURL(original: "https://github.com/user/repo.git", normalized: "https://github.com/user/repo.git"),
                        ref: nil,
                    ),
                    location: .project,
                    filter: .none,
                )),
            ),
            makeTestCase(
                description: "returns direct mode with git source when only URL is provided (SSH)",
                url: "git@github.com:user/repo.git",
                expected: .success(.direct(
                    source: .git(
                        url: GitURL(original: "git@github.com:user/repo.git", normalized: "git@github.com:user/repo.git"),
                        ref: nil,
                    ),
                    location: .project,
                    filter: .none,
                )),
            ),

            // Direct mode with branch
            makeTestCase(
                description: "returns direct mode with branch ref",
                url: "https://github.com/user/repo.git",
                branch: "develop",
                expected: .success(.direct(
                    source: .git(
                        url: GitURL(original: "https://github.com/user/repo.git", normalized: "https://github.com/user/repo.git"),
                        ref: .branch("develop"),
                    ),
                    location: .project,
                    filter: .none,
                )),
            ),

            // Direct mode with tag
            makeTestCase(
                description: "returns direct mode with tag ref",
                url: "https://github.com/user/repo.git",
                tag: "v1.0.0",
                expected: .success(.direct(
                    source: .git(
                        url: GitURL(original: "https://github.com/user/repo.git", normalized: "https://github.com/user/repo.git"),
                        ref: .tag("v1.0.0"),
                    ),
                    location: .project,
                    filter: .none,
                )),
            ),

            // Direct mode with revision
            makeTestCase(
                description: "returns direct mode with revision ref",
                url: "https://github.com/user/repo.git",
                revision: "abc123def456",
                expected: .success(.direct(
                    source: .git(
                        url: GitURL(original: "https://github.com/user/repo.git", normalized: "https://github.com/user/repo.git"),
                        ref: .revision("abc123def456"),
                    ),
                    location: .project,
                    filter: .none,
                )),
            ),

            // Direct mode with global location
            makeTestCase(
                description: "returns direct mode with global location",
                url: "https://github.com/user/repo.git",
                global: true,
                expected: .success(.direct(
                    source: .git(
                        url: GitURL(original: "https://github.com/user/repo.git", normalized: "https://github.com/user/repo.git"),
                        ref: nil,
                    ),
                    location: .global,
                    filter: .none,
                )),
            ),

            // Direct mode with include filter
            makeTestCase(
                description: "returns direct mode with include filter (single template)",
                url: "https://github.com/user/repo.git",
                templates: ["swift-module"],
                expected: .success(.direct(
                    source: .git(
                        url: GitURL(original: "https://github.com/user/repo.git", normalized: "https://github.com/user/repo.git"),
                        ref: nil,
                    ),
                    location: .project,
                    filter: .include(["swift-module"]),
                )),
            ),
            makeTestCase(
                description: "returns direct mode with include filter (multiple templates)",
                url: "https://github.com/user/repo.git",
                templates: ["swift-module", "swift-package"],
                expected: .success(.direct(
                    source: .git(
                        url: GitURL(original: "https://github.com/user/repo.git", normalized: "https://github.com/user/repo.git"),
                        ref: nil,
                    ),
                    location: .project,
                    filter: .include(["swift-module", "swift-package"]),
                )),
            ),

            // Direct mode with exclude filter
            makeTestCase(
                description: "returns direct mode with exclude filter (single template)",
                url: "https://github.com/user/repo.git",
                excludeTemplates: ["swiftui-view"],
                expected: .success(.direct(
                    source: .git(
                        url: GitURL(original: "https://github.com/user/repo.git", normalized: "https://github.com/user/repo.git"),
                        ref: nil,
                    ),
                    location: .project,
                    filter: .exclude(["swiftui-view"]),
                )),
            ),
            makeTestCase(
                description: "returns direct mode with exclude filter (multiple templates)",
                url: "https://github.com/user/repo.git",
                excludeTemplates: ["swiftui-view", "swift-package"],
                expected: .success(.direct(
                    source: .git(
                        url: GitURL(original: "https://github.com/user/repo.git", normalized: "https://github.com/user/repo.git"),
                        ref: nil,
                    ),
                    location: .project,
                    filter: .exclude(["swiftui-view", "swift-package"]),
                )),
            ),

            // Direct mode with all options
            makeTestCase(
                description: "returns direct mode with tag, global, and include filter",
                url: "https://github.com/user/repo.git",
                tag: "v2.0.0",
                templates: ["swift-module"],
                global: true,
                expected: .success(.direct(
                    source: .git(
                        url: GitURL(original: "https://github.com/user/repo.git", normalized: "https://github.com/user/repo.git"),
                        ref: .tag("v2.0.0"),
                    ),
                    location: .global,
                    filter: .include(["swift-module"]),
                )),
            ),

            // Error cases - invalid source
            makeTestCase(
                description: "throws error for invalid source",
                url: "not-a-valid-url",
                expected: .failure(.invalidSourcePath("not-a-valid-url")),
            ),
            makeTestCase(
                description: "throws error for empty source",
                url: "",
                expected: .failure(.invalidSourcePath("")),
            ),
            makeTestCase(
                description: "throws error for URL with unsupported protocol",
                url: "ftp://github.com/user/repo.git",
                expected: .failure(.invalidSourcePath("ftp://github.com/user/repo.git")),
            ),

            // Error cases - mutually exclusive ref options
            makeTestCase(
                description: "throws error when both branch and tag are specified",
                url: "https://github.com/user/repo.git",
                branch: "develop",
                tag: "v1.0.0",
                expected: .failure(.mutuallyExclusiveRefOptions),
            ),
            makeTestCase(
                description: "throws error when both branch and revision are specified",
                url: "https://github.com/user/repo.git",
                branch: "develop",
                revision: "abc123",
                expected: .failure(.mutuallyExclusiveRefOptions),
            ),
            makeTestCase(
                description: "throws error when both tag and revision are specified",
                url: "https://github.com/user/repo.git",
                tag: "v1.0.0",
                revision: "abc123",
                expected: .failure(.mutuallyExclusiveRefOptions),
            ),
            makeTestCase(
                description: "throws error when all three ref options are specified",
                url: "https://github.com/user/repo.git",
                branch: "develop",
                tag: "v1.0.0",
                revision: "abc123",
                expected: .failure(.mutuallyExclusiveRefOptions),
            ),

            // Error cases - mutually exclusive filter options
            makeTestCase(
                description: "throws error when both template and exclude are specified",
                url: "https://github.com/user/repo.git",
                templates: ["swift-module"],
                excludeTemplates: ["swiftui-view"],
                expected: .failure(.mutuallyExclusiveFilterOptions),
            ),
        ]

        enum Result {
            case success(InstallRunnerMode)
            case failure(InstallArgumentsValidator.Error)
        }
    }
}

extension InstallRunnerMode: Equatable {
    public static func == (lhs: InstallRunnerMode, rhs: InstallRunnerMode) -> Bool {
        switch (lhs, rhs) {
        case (.interactive, .interactive):
            true
        case let (.direct(lhsSource, lhsLocation, lhsFilter),
                  .direct(rhsSource, rhsLocation, rhsFilter)):
            lhsSource == rhsSource && lhsLocation == rhsLocation && lhsFilter == rhsFilter
        default:
            false
        }
    }
}
