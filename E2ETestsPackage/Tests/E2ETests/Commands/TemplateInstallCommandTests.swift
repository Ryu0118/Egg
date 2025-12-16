import FileManagerProtocol
import Foundation
import Testing

@Suite(.buildBinary, .serialized)
struct TemplateInstallCommandTests {
    let fileManager: any FileManagerProtocol = FileManager.default

    // Test repository URL (SSH to avoid authentication issues in subprocesses)
    static let testRepoURL = "git@github.com:Ryu0118/swift-egg-templates.git"
    // Known templates in the test repository
    static let knownTemplates = ["SwiftModule", "iOSProjectGenTemplate"]
    // Known commit SHA for revision tests
    static let knownCommitSHA = "8f65013501f58d2989eca79a20474c299b640e27"

    @Test("--help shows install command help")
    func helpFlag() async throws {
        let runner = try await CLIRunner()
        let result = try await runner.run("template", "install", "--help")

        #expect(result.succeeded)
        #expect(result.stdout.contains("OVERVIEW: Install templates from a Git repository"))
        #expect(result.stdout.contains("USAGE: egg template install"))
        #expect(result.stdout.contains("--branch"))
        #expect(result.stdout.contains("--tag"))
        #expect(result.stdout.contains("--revision"))
        #expect(result.stdout.contains("--template"))
        #expect(result.stdout.contains("--exclude"))
        #expect(result.stdout.contains("--global"))
        #expect(result.stdout.contains("--force"))
    }

    @Test(arguments: ValidationErrorTestCase.allCases)
    func validationErrors(_ testCase: ValidationErrorTestCase) async throws {
        let runner = try await CLIRunner()
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "cli-test-install")
        defer { try? fileManager.removeItem(at: tempDir) }

        let homeDir = tempDir.appending(path: "home")
        let projectDir = tempDir.appending(path: "project")
        try fileManager.createDirectory(at: homeDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let environment = ["HOME": homeDir.path(percentEncoded: false)]
        let arguments = testCase.buildArguments(projectDir: projectDir)

        let result = try await runner.run(
            arguments: arguments,
            environment: environment
        )

        #expect(!result.succeeded, "Expected failure but command succeeded")
        let output = result.stderr + result.stdout
        #expect(
            output.contains(testCase.expectedErrorContains),
            "Expected error containing '\(testCase.expectedErrorContains)' but got: \(output)"
        )
    }

    @Test(arguments: NetworkTestCase.allCases)
    func networkOperations(_ testCase: NetworkTestCase) async throws {
        let runner = try await CLIRunner()
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "cli-test-install")
        defer { try? fileManager.removeItem(at: tempDir) }

        let homeDir = tempDir.appending(path: "home")
        let projectDir = tempDir.appending(path: "project")
        try fileManager.createDirectory(at: homeDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: projectDir, withIntermediateDirectories: true)

        // Setup existing templates if needed
        if let existingTemplate = testCase.existingTemplate {
            let eggsDir = homeDir.appending(path: ".eggs/\(existingTemplate)")
            try fileManager.createDirectory(at: eggsDir, withIntermediateDirectories: true)
            let markerFile = eggsDir.appending(path: "marker.txt")
            try "original".write(to: markerFile, atomically: true, encoding: .utf8)
        }

        let environment = ["HOME": homeDir.path(percentEncoded: false)]
        let arguments = testCase.buildArguments(projectDir: projectDir)

        let result = try await runner.run(
            arguments: arguments,
            environment: environment
        )

        switch testCase.expected {
        case .success:
            #expect(result.succeeded, "Expected success but got exit code \(result.exitCode): \(result.stderr)")
            try verifyInstallation(testCase: testCase, homeDir: homeDir, projectDir: projectDir)
        case let .failure(errorContains):
            #expect(!result.succeeded, "Expected failure but command succeeded")
            if let errorContains {
                let output = result.stderr + result.stdout
                #expect(
                    output.contains(errorContains),
                    "Expected error containing '\(errorContains)' but got: \(output)"
                )
            }
        }
    }

    private func verifyInstallation(
        testCase: NetworkTestCase,
        homeDir: URL,
        projectDir: URL
    ) throws {
        guard let verification = testCase.verification else { return }

        let eggsDir = verification.location == .global
            ? homeDir.appending(path: ".eggs")
            : projectDir.appending(path: ".eggs")

        for templateName in verification.expectedTemplates {
            let templatePath = eggsDir.appending(path: templateName)
            #expect(
                fileManager.fileExists(atPath: templatePath.path(percentEncoded: false)),
                "Template '\(templateName)' should exist at \(templatePath.path)"
            )
        }

        for templateName in verification.unexpectedTemplates {
            let templatePath = eggsDir.appending(path: templateName)
            #expect(
                !fileManager.fileExists(atPath: templatePath.path(percentEncoded: false)),
                "Template '\(templateName)' should NOT exist at \(templatePath.path)"
            )
        }

        if verification.markerShouldExist {
            let markerPath = eggsDir.appending(path: "\(verification.expectedTemplates.first ?? "")/marker.txt")
            #expect(
                fileManager.fileExists(atPath: markerPath.path(percentEncoded: false)),
                "Marker file should still exist (template was skipped)"
            )
        }

        if verification.markerShouldBeGone {
            let markerPath = eggsDir.appending(path: "\(verification.expectedTemplates.first ?? "")/marker.txt")
            #expect(
                !fileManager.fileExists(atPath: markerPath.path(percentEncoded: false)),
                "Marker file should be gone (template was overwritten)"
            )
        }
    }

    struct ValidationErrorTestCase: CustomTestStringConvertible {
        let description: String
        let url: String?
        let extraArgs: [String]
        let expectedErrorContains: String

        var testDescription: String { description }

        func buildArguments(projectDir: URL) -> [String] {
            var args = ["template", "install"]
            if let url {
                args.append(url)
            }
            args += extraArgs
            args += ["--project-directory", projectDir.path(percentEncoded: false)]
            return args
        }

        static let allCases: [ValidationErrorTestCase] = [
            ValidationErrorTestCase(
                description: "fails with invalid URL",
                url: "not-a-valid-url",
                extraArgs: ["--global"],
                expectedErrorContains: "Invalid"
            ),
            ValidationErrorTestCase(
                description: "fails when using both --template and --exclude",
                url: TemplateInstallCommandTests.testRepoURL,
                extraArgs: ["--global", "--template", "Foo", "--exclude", "Bar"],
                expectedErrorContains: "Cannot use both"
            ),
            ValidationErrorTestCase(
                description: "fails when using --branch and --tag together",
                url: TemplateInstallCommandTests.testRepoURL,
                extraArgs: ["--global", "--branch", "main", "--tag", "v1.0"],
                expectedErrorContains: "Only one of"
            ),
            ValidationErrorTestCase(
                description: "fails when using --branch and --revision together",
                url: TemplateInstallCommandTests.testRepoURL,
                extraArgs: ["--global", "--branch", "main", "--revision", "abc123"],
                expectedErrorContains: "Only one of"
            ),
            ValidationErrorTestCase(
                description: "fails when using --tag and --revision together",
                url: TemplateInstallCommandTests.testRepoURL,
                extraArgs: ["--global", "--tag", "v1.0", "--revision", "abc123"],
                expectedErrorContains: "Only one of"
            ),
        ]
    }

    struct NetworkTestCase: CustomTestStringConvertible {
        let description: String
        let url: String
        let refOption: RefOption?
        let location: Location
        let templateFilter: [String]
        let excludeFilter: [String]
        let force: Bool
        let existingTemplate: String?
        let expected: Expected
        let verification: Verification?

        var testDescription: String { description }

        func buildArguments(projectDir: URL) -> [String] {
            var args = ["template", "install", url]

            switch refOption {
            case let .branch(name):
                args += ["--branch", name]
            case let .tag(name):
                args += ["--tag", name]
            case let .revision(sha):
                args += ["--revision", sha]
            case nil:
                break
            }

            if location == .global {
                args.append("--global")
            }

            for template in templateFilter {
                args += ["--template", template]
            }

            for exclude in excludeFilter {
                args += ["--exclude", exclude]
            }

            if force {
                args.append("--force")
            }

            args += ["--project-directory", projectDir.path(percentEncoded: false)]
            return args
        }

        enum RefOption {
            case branch(String)
            case tag(String)
            case revision(String)
        }

        enum Location: String {
            case global
            case project
        }

        enum Expected {
            case success
            case failure(errorContains: String?)
        }

        struct Verification {
            let location: Location
            let expectedTemplates: [String]
            let unexpectedTemplates: [String]
            let markerShouldExist: Bool
            let markerShouldBeGone: Bool

            init(
                location: Location,
                expectedTemplates: [String] = [],
                unexpectedTemplates: [String] = [],
                markerShouldExist: Bool = false,
                markerShouldBeGone: Bool = false
            ) {
                self.location = location
                self.expectedTemplates = expectedTemplates
                self.unexpectedTemplates = unexpectedTemplates
                self.markerShouldExist = markerShouldExist
                self.markerShouldBeGone = markerShouldBeGone
            }
        }

        static let allCases: [NetworkTestCase] = [
            // Success cases
            NetworkTestCase(
                description: "installs all templates to global location",
                url: TemplateInstallCommandTests.testRepoURL,
                refOption: nil,
                location: .global,
                templateFilter: [],
                excludeFilter: [],
                force: false,
                existingTemplate: nil,
                expected: .success,
                verification: Verification(
                    location: .global,
                    expectedTemplates: TemplateInstallCommandTests.knownTemplates
                )
            ),
            NetworkTestCase(
                description: "installs all templates to project location",
                url: TemplateInstallCommandTests.testRepoURL,
                refOption: nil,
                location: .project,
                templateFilter: [],
                excludeFilter: [],
                force: false,
                existingTemplate: nil,
                expected: .success,
                verification: Verification(
                    location: .project,
                    expectedTemplates: TemplateInstallCommandTests.knownTemplates
                )
            ),
            NetworkTestCase(
                description: "installs specific template using --template filter",
                url: TemplateInstallCommandTests.testRepoURL,
                refOption: nil,
                location: .global,
                templateFilter: ["SwiftModule"],
                excludeFilter: [],
                force: false,
                existingTemplate: nil,
                expected: .success,
                verification: Verification(
                    location: .global,
                    expectedTemplates: ["SwiftModule"],
                    unexpectedTemplates: ["iOSProjectGenTemplate"]
                )
            ),
            NetworkTestCase(
                description: "excludes specific template using --exclude filter",
                url: TemplateInstallCommandTests.testRepoURL,
                refOption: nil,
                location: .global,
                templateFilter: [],
                excludeFilter: ["iOSProjectGenTemplate"],
                force: false,
                existingTemplate: nil,
                expected: .success,
                verification: Verification(
                    location: .global,
                    expectedTemplates: ["SwiftModule"],
                    unexpectedTemplates: ["iOSProjectGenTemplate"]
                )
            ),
            NetworkTestCase(
                description: "installs from specific branch",
                url: TemplateInstallCommandTests.testRepoURL,
                refOption: .branch("main"),
                location: .global,
                templateFilter: ["SwiftModule"],
                excludeFilter: [],
                force: false,
                existingTemplate: nil,
                expected: .success,
                verification: Verification(
                    location: .global,
                    expectedTemplates: ["SwiftModule"]
                )
            ),
            NetworkTestCase(
                description: "installs from specific revision",
                url: TemplateInstallCommandTests.testRepoURL,
                refOption: .revision(TemplateInstallCommandTests.knownCommitSHA),
                location: .global,
                templateFilter: ["SwiftModule"],
                excludeFilter: [],
                force: false,
                existingTemplate: nil,
                expected: .success,
                verification: Verification(
                    location: .global,
                    expectedTemplates: ["SwiftModule"]
                )
            ),
            NetworkTestCase(
                description: "overwrites existing template with --force",
                url: TemplateInstallCommandTests.testRepoURL,
                refOption: nil,
                location: .global,
                templateFilter: ["SwiftModule"],
                excludeFilter: [],
                force: true,
                existingTemplate: "SwiftModule",
                expected: .success,
                verification: Verification(
                    location: .global,
                    expectedTemplates: ["SwiftModule"],
                    markerShouldBeGone: true
                )
            ),
            NetworkTestCase(
                description: "skips existing template without --force",
                url: TemplateInstallCommandTests.testRepoURL,
                refOption: nil,
                location: .global,
                templateFilter: ["SwiftModule"],
                excludeFilter: [],
                force: false,
                existingTemplate: "SwiftModule",
                expected: .failure(errorContains: nil),
                verification: Verification(
                    location: .global,
                    expectedTemplates: ["SwiftModule"],
                    markerShouldExist: true
                )
            ),

            // Failure cases
            NetworkTestCase(
                description: "fails with non-existent repository",
                url: "https://github.com/nonexistent-user-12345/nonexistent-repo-67890",
                refOption: nil,
                location: .global,
                templateFilter: [],
                excludeFilter: [],
                force: false,
                existingTemplate: nil,
                expected: .failure(errorContains: nil),
                verification: nil
            ),
            NetworkTestCase(
                description: "fails with non-existent branch",
                url: TemplateInstallCommandTests.testRepoURL,
                refOption: .branch("nonexistent-branch-12345"),
                location: .global,
                templateFilter: [],
                excludeFilter: [],
                force: false,
                existingTemplate: nil,
                expected: .failure(errorContains: nil),
                verification: nil
            ),
        ]
    }
}
