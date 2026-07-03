import FileManagerProtocol
import Foundation
import Testing

@Suite(.buildBinary, .serialized)
struct HatchCommandTests {
    let fileManager: any FileManagerProtocol = FileManager.default

    @Test
    func `--help shows hatch command help`() async throws {
        let runner = try await CLIRunner()
        let result = try await runner.run("hatch", "--help")

        #expect(result.succeeded)
        #expect(result.stdout.contains("OVERVIEW:"))
        #expect(result.stdout.contains("USAGE: egg hatch"))
        #expect(result.stdout.contains("--no-staging"))
        #expect(result.stdout.contains("--override-conflicts"))
        #expect(result.stdout.contains("--no-sandbox"))
        #expect(result.stdout.contains("--apply-changes"))
        #expect(result.stdout.contains("--project-directory"))
        #expect(result.stdout.contains("--template-search-paths"))
    }

    @Test
    func `preview help shows sandbox controls`() async throws {
        let runner = try await CLIRunner()
        let result = try await runner.run("hatch", "preview", "--help")

        #expect(result.succeeded)
        #expect(result.stdout.contains("--no-sandbox"))
    }

    @Test(arguments: TestCase.allCases)
    func `hatch template`(_ testCase: TestCase) async throws {
        let runner = try await CLIRunner()
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "cli-test-hatch")
        defer { try? fileManager.removeItem(at: tempDir) }

        let homeDir = tempDir.appending(path: "home")
        let projectDir = tempDir.appending(path: "project")
        let outputDir = tempDir.appending(path: "output")
        let customDir = tempDir.appending(path: "custom")
        try fileManager.createDirectory(at: homeDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: projectDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outputDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: customDir, withIntermediateDirectories: true)

        // Setup template
        if let template = testCase.template {
            try setupTemplate(
                template,
                homeDir: homeDir,
                projectDir: projectDir,
                customDir: customDir,
            )
        }

        // Setup existing files for conflict tests
        for existingFile in testCase.existingFiles {
            let filePath = outputDir.appending(path: existingFile.path)
            let parentDir = filePath.deletingLastPathComponent()
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
            try existingFile.content.write(to: filePath, atomically: true, encoding: .utf8)
        }

        let customDirForArgs = testCase.useCustomSearchPath ? customDir : nil
        let arguments = testCase.buildArguments(projectDir: projectDir, outputDir: outputDir, customDir: customDirForArgs)
        let environment = ["HOME": homeDir.path(percentEncoded: false)]

        let result = try await runner.run(
            arguments: arguments,
            workingDirectory: outputDir,
            environment: environment,
        )

        switch testCase.expected {
        case .success:
            #expect(result.succeeded, "Expected success but got exit code \(result.exitCode): \(result.stderr)")
            try verifyHatch(testCase: testCase, outputDir: outputDir)
        case let .failure(errorContains):
            #expect(!result.succeeded, "Expected failure but command succeeded")
            let output = result.stderr + result.stdout
            #expect(
                output.contains(errorContains),
                "Expected error containing '\(errorContains)' but got: \(output)",
            )
        }
    }

    private func setupTemplate(
        _ template: TestCase.TemplateSetup,
        homeDir: URL,
        projectDir: URL,
        customDir: URL,
    ) throws {
        let templateDir: URL = switch template.location {
        case .global:
            homeDir.appending(path: ".eggs/\(template.name)")
        case .project:
            projectDir.appending(path: ".eggs/\(template.name)")
        case .custom:
            customDir.appending(path: template.name)
        case .customRoot:
            customDir
        }

        if !fileManager.fileExists(atPath: templateDir.path(percentEncoded: false)) {
            try fileManager.createDirectory(at: templateDir, withIntermediateDirectories: true)
        }

        // Write config.yml
        try template.configYaml.write(
            to: templateDir.appending(path: "config.yml"),
            atomically: true,
            encoding: .utf8,
        )

        // Write template files
        for file in template.files {
            let filePath = templateDir.appending(path: file.path)
            let parentDir = filePath.deletingLastPathComponent()
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
            try file.content.write(to: filePath, atomically: true, encoding: .utf8)
        }

        // Write lifecycle scripts if any
        if let preHatchScript = template.preHatchScript {
            let scriptPath = templateDir.appending(path: "pre_hatch.sh")
            try preHatchScript.write(to: scriptPath, atomically: true, encoding: .utf8)
        }

        if let postHatchScript = template.postHatchScript {
            let scriptPath = templateDir.appending(path: "post_hatch.sh")
            try postHatchScript.write(to: scriptPath, atomically: true, encoding: .utf8)
        }
    }

    private func verifyHatch(testCase: TestCase, outputDir: URL) throws {
        guard let verification = testCase.verification else { return }

        for expectedFile in verification.expectedFiles {
            let filePath = outputDir.appending(path: expectedFile.path)
            #expect(
                fileManager.fileExists(atPath: filePath.path(percentEncoded: false)),
                "Expected file '\(expectedFile.path)' should exist",
            )

            if let expectedContent = expectedFile.contentContains {
                let content = try String(contentsOf: filePath, encoding: .utf8)
                #expect(
                    content.contains(expectedContent),
                    "File '\(expectedFile.path)' should contain '\(expectedContent)' but got: \(content)",
                )
            }
        }

        for unexpectedFile in verification.unexpectedFiles {
            let filePath = outputDir.appending(path: unexpectedFile)
            #expect(
                !fileManager.fileExists(atPath: filePath.path(percentEncoded: false)),
                "Unexpected file '\(unexpectedFile)' should NOT exist",
            )
        }
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let template: TemplateSetup?
        let templateName: String
        let macros: [String: [String]]
        let flags: Flags
        let existingFiles: [FileSetup]
        let expected: Expected
        let verification: Verification?
        let useCustomSearchPath: Bool

        var testDescription: String {
            description
        }

        init(
            description: String,
            template: TemplateSetup?,
            templateName: String,
            macros: [String: [String]],
            flags: Flags,
            existingFiles: [FileSetup],
            expected: Expected,
            verification: Verification?,
            useCustomSearchPath: Bool = false,
        ) {
            self.description = description
            self.template = template
            self.templateName = templateName
            self.macros = macros
            self.flags = flags
            self.existingFiles = existingFiles
            self.expected = expected
            self.verification = verification
            self.useCustomSearchPath = useCustomSearchPath
        }

        func buildArguments(projectDir: URL, outputDir _: URL, customDir: URL? = nil) -> [String] {
            // Order: hatch <template-name> [options] [flags] [macros...]
            // Flags must come BEFORE macros (captureForPassthrough captures everything after)
            var args = ["hatch", templateName]

            // Options first
            args += ["--project-directory", projectDir.path(percentEncoded: false)]
            args += ["--picker", "text"]

            // Add custom search paths if provided
            if let customDir {
                args += ["--template-search-paths", customDir.path(percentEncoded: false)]
            }

            // Then flags
            if flags.noStaging {
                args.append("--no-staging")
            }
            if flags.overrideConflicts {
                args.append("--override-conflicts")
            }
            if flags.noSandbox {
                args.append("--no-sandbox")
            }
            if flags.applyChanges {
                args.append("--apply-changes")
            }

            // Macros LAST (captureForPassthrough)
            // Values are passed as separate arguments for arrays/choices support
            for (key, values) in macros.sorted(by: { $0.key < $1.key }) {
                args.append("--\(key)")
                args.append(contentsOf: values)
            }

            return args
        }

        enum Location {
            case global
            case project
            case custom
            case customRoot
        }

        enum Expected {
            case success
            case failure(errorContains: String)
        }

        struct Flags {
            var noStaging: Bool = false
            var overrideConflicts: Bool = false
            var noSandbox: Bool = false
            var applyChanges: Bool = false

            static let none = Flags()
            static let directApply = Flags(noStaging: true, applyChanges: true)
            static let withOverride = Flags(noStaging: true, overrideConflicts: true, applyChanges: true)
            static let withNoSandbox = Flags(noStaging: true, noSandbox: true, applyChanges: true)
        }

        struct TemplateSetup {
            let name: String
            let location: Location
            let configYaml: String
            let files: [FileSetup]
            let preHatchScript: String?
            let postHatchScript: String?

            init(
                name: String,
                location: Location,
                configYaml: String,
                files: [FileSetup] = [],
                preHatchScript: String? = nil,
                postHatchScript: String? = nil,
            ) {
                self.name = name
                self.location = location
                self.configYaml = configYaml
                self.files = files
                self.preHatchScript = preHatchScript
                self.postHatchScript = postHatchScript
            }
        }

        struct FileSetup {
            let path: String
            let content: String
        }

        struct Verification {
            let expectedFiles: [ExpectedFile]
            let unexpectedFiles: [String]

            init(expectedFiles: [ExpectedFile] = [], unexpectedFiles: [String] = []) {
                self.expectedFiles = expectedFiles
                self.unexpectedFiles = unexpectedFiles
            }
        }

        struct ExpectedFile {
            let path: String
            let contentContains: String?

            init(_ path: String, contentContains: String? = nil) {
                self.path = path
                self.contentContains = contentContains
            }
        }

        static let allCases: [TestCase] = [
            // Basic template execution
            basicTemplateExecution,
            macroSubstitution,
            templateNotFound,
            overrideConflicts,
            preHatchLifecycle,
            postHatchLifecycle,
            // Stencil template tests
            stencilBasicRendering,
            stencilConditionalRendering,
            stencilLoopRendering,
            // Custom search paths tests
            customSearchPathTemplate,
            customSearchPathTemplateAtRoot,
            customSearchPathTemplateNotFoundWithoutFlag,
        ]

        /// Basic template execution without macros
        static let basicTemplateExecution = TestCase(
            description: "executes basic template without macros",
            template: TemplateSetup(
                name: "BasicTemplate",
                location: .global,
                configYaml: """
                name: BasicTemplate
                description: A basic test template
                hatch:
                  output: .
                """,
                files: [
                    FileSetup(path: "README.md", content: "# Hello World\n"),
                ],
            ),
            templateName: "BasicTemplate",
            macros: [:],
            flags: .directApply,
            existingFiles: [],
            expected: .success,
            verification: Verification(
                expectedFiles: [
                    ExpectedFile("README.md", contentContains: "Hello World"),
                ],
            ),
        )

        /// Macro substitution test
        static let macroSubstitution = TestCase(
            description: "performs macro substitution in file names and content",
            template: TemplateSetup(
                name: "MacroTemplate",
                location: .global,
                configYaml: """
                name: MacroTemplate
                description: Template with macros
                macros:
                  - name: ___MODULE_NAME___
                    description: The module name
                    type: string
                hatch:
                  output: .
                """,
                files: [
                    FileSetup(
                        path: "___MODULE_NAME___.swift",
                        content: """
                        // ___MODULE_NAME___.swift
                        struct ___MODULE_NAME___ {
                            let name = "___MODULE_NAME___"
                        }
                        """,
                    ),
                ],
            ),
            templateName: "MacroTemplate",
            macros: ["MODULE-NAME": ["MyModule"]],
            flags: .directApply,
            existingFiles: [],
            expected: .success,
            verification: Verification(
                expectedFiles: [
                    ExpectedFile("MyModule.swift", contentContains: "struct MyModule"),
                ],
            ),
        )

        /// Template not found error
        static let templateNotFound = TestCase(
            description: "fails when template does not exist",
            template: nil,
            templateName: "NonExistentTemplate",
            macros: [:],
            flags: .directApply,
            existingFiles: [],
            expected: .failure(errorContains: "not found"),
            verification: nil,
        )

        /// Override conflicts test
        static let overrideConflicts = TestCase(
            description: "overwrites existing files with --override-conflicts",
            template: TemplateSetup(
                name: "OverrideTemplate",
                location: .global,
                configYaml: """
                name: OverrideTemplate
                description: Template for override test
                hatch:
                  output: .
                """,
                files: [
                    FileSetup(path: "existing.txt", content: "new content from template"),
                ],
            ),
            templateName: "OverrideTemplate",
            macros: [:],
            flags: .withOverride,
            existingFiles: [
                FileSetup(path: "existing.txt", content: "original content"),
            ],
            expected: .success,
            verification: Verification(
                expectedFiles: [
                    ExpectedFile("existing.txt", contentContains: "new content from template"),
                ],
            ),
        )

        /// Pre-hatch lifecycle test
        static let preHatchLifecycle = TestCase(
            description: "executes pre_hatch lifecycle scripts",
            template: TemplateSetup(
                name: "PreHatchTemplate",
                location: .global,
                configYaml: """
                name: PreHatchTemplate
                description: Template with pre_hatch
                pre_hatch:
                  - run: echo "pre-hatch executed" > pre_hatch_marker.txt
                hatch:
                  output: .
                """,
                files: [
                    FileSetup(path: "main.txt", content: "main content"),
                ],
            ),
            templateName: "PreHatchTemplate",
            macros: [:],
            flags: .withNoSandbox,
            existingFiles: [],
            expected: .success,
            verification: Verification(
                expectedFiles: [
                    ExpectedFile("main.txt", contentContains: "main content"),
                    ExpectedFile("pre_hatch_marker.txt", contentContains: "pre-hatch executed"),
                ],
            ),
        )

        /// Post-hatch lifecycle test
        static let postHatchLifecycle = TestCase(
            description: "executes post_hatch lifecycle scripts",
            template: TemplateSetup(
                name: "PostHatchTemplate",
                location: .global,
                configYaml: """
                name: PostHatchTemplate
                description: Template with post_hatch
                hatch:
                  output: .
                post_hatch:
                  - run: echo "post-hatch executed" > post_hatch_marker.txt
                """,
                files: [
                    FileSetup(path: "main.txt", content: "main content"),
                ],
            ),
            templateName: "PostHatchTemplate",
            macros: [:],
            flags: .withNoSandbox,
            existingFiles: [],
            expected: .success,
            verification: Verification(
                expectedFiles: [
                    ExpectedFile("main.txt", contentContains: "main content"),
                    ExpectedFile("post_hatch_marker.txt", contentContains: "post-hatch executed"),
                ],
            ),
        )

        // MARK: - Stencil Template Tests

        /// Basic Stencil variable rendering
        static let stencilBasicRendering = TestCase(
            description: "renders .stencil file with variable substitution",
            template: TemplateSetup(
                name: "StencilBasicTemplate",
                location: .global,
                configYaml: """
                name: StencilBasicTemplate
                description: Template with Stencil file
                macros:
                  - name: ___PROJECT_NAME___
                    description: The project name
                    type: string
                  - name: ___AUTHOR___
                    description: Author name
                    type: string
                hatch:
                  output: .
                """,
                files: [
                    FileSetup(
                        path: "README.md.stencil",
                        content: """
                        # {{ ___PROJECT_NAME___ }}

                        Created by {{ ___AUTHOR___ }}.
                        """,
                    ),
                ],
            ),
            templateName: "StencilBasicTemplate",
            macros: ["AUTHOR": ["John Doe"], "PROJECT-NAME": ["MyAwesomeProject"]],
            flags: .directApply,
            existingFiles: [],
            expected: .success,
            verification: Verification(
                expectedFiles: [
                    ExpectedFile("README.md", contentContains: "# MyAwesomeProject"),
                    ExpectedFile("README.md", contentContains: "Created by John Doe"),
                ],
                unexpectedFiles: ["README.md.stencil"],
            ),
        )

        /// Stencil conditional rendering
        static let stencilConditionalRendering = TestCase(
            description: "renders .stencil file with conditional blocks",
            template: TemplateSetup(
                name: "StencilConditionalTemplate",
                location: .global,
                configYaml: """
                name: StencilConditionalTemplate
                description: Template with Stencil conditionals
                macros:
                  - name: ___BUILD_TYPE___
                    description: Build type
                    type: choice
                    choices: [debug, release]
                hatch:
                  output: .
                """,
                files: [
                    FileSetup(
                        path: "Config.swift.stencil",
                        content: """
                        import Foundation

                        {% if ___BUILD_TYPE___ == "release" %}
                        let isRelease = true
                        let optimization = "-O"
                        {% else %}
                        let isRelease = false
                        let optimization = "-Onone"
                        {% endif %}
                        """,
                    ),
                ],
            ),
            templateName: "StencilConditionalTemplate",
            macros: ["BUILD-TYPE": ["release"]],
            flags: .directApply,
            existingFiles: [],
            expected: .success,
            verification: Verification(
                expectedFiles: [
                    ExpectedFile("Config.swift", contentContains: "let isRelease = true"),
                    ExpectedFile("Config.swift", contentContains: "let optimization = \"-O\""),
                ],
                unexpectedFiles: ["Config.swift.stencil"],
            ),
        )

        /// Stencil loop rendering using choices macro (multiple values)
        static let stencilLoopRendering = TestCase(
            description: "renders .stencil file with loop blocks",
            template: TemplateSetup(
                name: "StencilLoopTemplate",
                location: .global,
                configYaml: """
                name: StencilLoopTemplate
                description: Template with Stencil loops
                macros:
                  - name: ___PLATFORMS___
                    description: Target platforms
                    type: choices
                    choices: [iOS, macOS, watchOS, tvOS]
                hatch:
                  output: .
                """,
                files: [
                    FileSetup(
                        path: "Platforms.swift.stencil",
                        content: """
                        import Foundation

                        let platforms: [String] = [
                        {% for p in ___PLATFORMS___ %}
                            "{{ p }}",
                        {% endfor %}
                        ]
                        """,
                    ),
                ],
            ),
            templateName: "StencilLoopTemplate",
            macros: ["PLATFORMS": ["iOS", "macOS"]],
            flags: .directApply,
            existingFiles: [],
            expected: .success,
            verification: Verification(
                expectedFiles: [
                    ExpectedFile("Platforms.swift", contentContains: "\"iOS\""),
                    ExpectedFile("Platforms.swift", contentContains: "\"macOS\""),
                ],
                unexpectedFiles: ["Platforms.swift.stencil"],
            ),
        )

        // MARK: - Custom Search Paths Tests

        /// Template in custom search path
        static let customSearchPathTemplate = TestCase(
            description: "executes template from custom search path",
            template: TemplateSetup(
                name: "CustomPathTemplate",
                location: .custom,
                configYaml: """
                name: CustomPathTemplate
                description: A template in custom search path
                macros:
                  - name: ___APP_NAME___
                    description: App name
                    type: string
                hatch:
                  output: .
                """,
                files: [
                    FileSetup(path: "___APP_NAME___.swift", content: "// ___APP_NAME___ from custom path\n"),
                ],
            ),
            templateName: "CustomPathTemplate",
            macros: ["APP-NAME": ["MyCustomApp"]],
            flags: .directApply,
            existingFiles: [],
            expected: .success,
            verification: Verification(
                expectedFiles: [
                    ExpectedFile("MyCustomApp.swift", contentContains: "MyCustomApp from custom path"),
                ],
            ),
            useCustomSearchPath: true,
        )

        static let customSearchPathTemplateAtRoot = TestCase(
            description: "executes template when custom search path points to template root",
            template: TemplateSetup(
                name: "CustomRootTemplate",
                location: .customRoot,
                configYaml: """
                name: CustomRootTemplate
                description: Custom root template
                macros:
                  - name: ___APP_NAME___
                    description: App name
                    type: string
                hatch:
                  output: .
                """,
                files: [
                    FileSetup(path: "___APP_NAME___.swift", content: "// ___APP_NAME___ from custom root path\n"),
                ],
            ),
            templateName: "CustomRootTemplate",
            macros: ["APP-NAME": ["RootCustomApp"]],
            flags: .directApply,
            existingFiles: [],
            expected: .success,
            verification: Verification(
                expectedFiles: [
                    ExpectedFile("RootCustomApp.swift", contentContains: "RootCustomApp from custom root path"),
                ],
            ),
            useCustomSearchPath: true,
        )

        /// Template not found when custom path not provided
        static let customSearchPathTemplateNotFoundWithoutFlag = TestCase(
            description: "fails when template only in custom path but flag not provided",
            template: TemplateSetup(
                name: "CustomOnlyTemplate",
                location: .custom,
                configYaml: """
                name: CustomOnlyTemplate
                description: A template only in custom path
                hatch:
                  output: .
                """,
                files: [
                    FileSetup(path: "file.txt", content: "content"),
                ],
            ),
            templateName: "CustomOnlyTemplate",
            macros: [:],
            flags: .directApply,
            existingFiles: [],
            expected: .failure(errorContains: "not found"),
            verification: nil,
            useCustomSearchPath: false,
        )
    }
}
