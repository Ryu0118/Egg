@testable import EggKit
import FileSystem
import Foundation
import Noora
import Path
import ProcessRunning
import Testing

struct LifecycleWorkflowRunnerTests {
    @Test(.inTemporaryDirectory, arguments: TestCase.allCases)
    func run(_ testCase: TestCase) async throws {
        guard let tempDir = FileSystem.temporaryTestDirectory else {
            throw TestError.temporaryDirectoryNotAvailable
        }

        let fileSystem = FileSystem()
        let workingDir = tempDir.appending(component: "work")
        let homeDir = tempDir.appending(component: "home")
        let templateDir = tempDir.appending(component: "template")

        try await fileSystem.makeDirectory(at: workingDir, options: [.createTargetParentDirectories])
        try await fileSystem.makeDirectory(at: homeDir, options: [.createTargetParentDirectories])
        try await fileSystem.makeDirectory(at: templateDir, options: [.createTargetParentDirectories])

        // Setup template using helper
        try await setupTemplate(testCase.templateSetup, in: templateDir, using: fileSystem)

        let config = Config(
            name: "Test Template",
            description: "Test Description",
            macros: testCase.macroDefinitions.isEmpty ? nil : testCase.macroDefinitions,
            preHatch: testCase.preHatchSteps,
            hatch: testCase.hatchConfig,
            postHatch: testCase.postHatchSteps
        )

        let nooraMock = NooraMock()
        let runner = LifecycleWorkflowRunner(
            processRunner: ProcessRunner(),
            fileSystem: fileSystem,
            workingDirectory: workingDir,
            homeDirectory: homeDir,
            noora: nooraMock
        )

        let outputDir = try await runner.run(
            config: config,
            macroInputs: .parsed(testCase.macros),
            templateDirectory: templateDir
        )

        // Verify expectations using helper
        try await verifyExpectations(testCase.expectation.verifications, in: outputDir, using: fileSystem)
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let templateSetup: [TemplateSetup]
        let macroDefinitions: [Config.Macro]
        let macros: [ParsedMacroDefinition]
        let preHatchSteps: [Config.LifecycleStep]?
        let hatchConfig: Config.HatchConfig
        let postHatchSteps: [Config.LifecycleStep]?
        let expectation: Expectation

        var testDescription: String { description }

        // Convenience initializer with defaults
        init(
            _ description: String,
            templateSetup: [TemplateSetup],
            macroDefinitions: [Config.Macro] = [],
            macros: [ParsedMacroDefinition] = [],
            preHatchSteps: [Config.LifecycleStep]? = nil,
            hatchConfig: Config.HatchConfig,
            postHatchSteps: [Config.LifecycleStep]? = nil,
            expectation: Expectation
        ) {
            self.description = description
            self.templateSetup = templateSetup
            self.macroDefinitions = macroDefinitions
            self.macros = macros
            self.preHatchSteps = preHatchSteps
            self.hatchConfig = hatchConfig
            self.postHatchSteps = postHatchSteps
            self.expectation = expectation
        }

        // Convenience method for simple success cases
        static func success(
            _ description: String,
            templateSetup: [TemplateSetup],
            macroDefinitions: [Config.Macro] = [],
            macros: [ParsedMacroDefinition] = [],
            preHatchSteps: [Config.LifecycleStep]? = nil,
            hatchConfig: Config.HatchConfig = Config.HatchConfig(output: "."),
            postHatchSteps: [Config.LifecycleStep]? = nil,
            verifications: [Verification]
        ) -> TestCase {
            TestCase(
                description,
                templateSetup: templateSetup,
                macroDefinitions: macroDefinitions,
                macros: macros,
                preHatchSteps: preHatchSteps,
                hatchConfig: hatchConfig,
                postHatchSteps: postHatchSteps,
                expectation: .success(verifications: verifications)
            )
        }

        enum TemplateSetup {
            case file(path: String, content: String)
            case directory(path: String)
        }

        enum Expectation {
            case success(verifications: [Verification])

            var verifications: [Verification] {
                switch self {
                case let .success(verifications):
                    return verifications
                }
            }
        }

        enum Verification {
            case fileExists(path: String)
            case fileNotExists(path: String)
            case fileContent(path: String, expectedContent: String)
            case directoryExists(path: String)
        }

        static let allCases: [TestCase] = [
            // Hatch only workflow
            .success(
                "runs hatch phase only",
                templateSetup: [
                    .file(path: "README.md", content: "Hello World"),
                ],
                hatchConfig: Config.HatchConfig(output: "."),
                verifications: [
                    .fileExists(path: "README.md"),
                    .fileContent(path: "README.md", expectedContent: "Hello World"),
                ]
            ),

            // Pre-hatch + Hatch workflow
            .success(
                "runs pre_hatch and hatch phases",
                templateSetup: [
                    .file(path: "VERSION", content: "${{ pre_hatch.setup.outputs.version }}"),
                ],
                preHatchSteps: [
                    Config.LifecycleStep(id: "setup", run: "echo version=1.0.0"),
                ],
                hatchConfig: Config.HatchConfig(output: "."),
                verifications: [
                    .fileExists(path: "VERSION"),
                    .fileContent(path: "VERSION", expectedContent: "1.0.0"),
                ]
            ),

            // Hatch + Post-hatch workflow
            .success(
                "runs hatch and post_hatch phases",
                templateSetup: [
                    .file(path: "app.swift", content: "print(\"Hello\")"),
                ],
                hatchConfig: Config.HatchConfig(output: "."),
                postHatchSteps: [
                    Config.LifecycleStep(run: "echo 'Formatted' > formatted.txt"),
                ],
                verifications: [
                    .fileExists(path: "app.swift"),
                    .fileExists(path: "formatted.txt"),
                    .fileContent(path: "formatted.txt", expectedContent: "Formatted\n"),
                ]
            ),

            // Complete workflow: Pre-hatch + Hatch + Post-hatch
            .success(
                "runs complete workflow",
                templateSetup: [
                    .file(path: "PROJECT", content: "___NAME___ v${{ pre_hatch.setup.outputs.version }}"),
                ],
                macroDefinitions: [
                    Config.Macro(name: "___NAME___", description: "Name", type: .string),
                ],
                macros: [
                    ParsedMacroDefinition(macro: "___NAME___", values: ["MyApp"]),
                ],
                preHatchSteps: [
                    Config.LifecycleStep(id: "setup", run: "echo version=2.0.0"),
                ],
                hatchConfig: Config.HatchConfig(output: "."),
                postHatchSteps: [
                    Config.LifecycleStep(run: "echo 'Done' > done.txt"),
                ],
                verifications: [
                    .fileExists(path: "PROJECT"),
                    .fileContent(path: "PROJECT", expectedContent: "MyApp v2.0.0"),
                    .fileExists(path: "done.txt"),
                    .fileContent(path: "done.txt", expectedContent: "Done\n"),
                ]
            ),

            // Post-hatch can access pre-hatch outputs
            .success(
                "post_hatch accesses pre_hatch outputs",
                templateSetup: [
                    .file(path: "README.md", content: "Project"),
                ],
                preHatchSteps: [
                    Config.LifecycleStep(id: "info", run: "echo name=TestProject"),
                ],
                hatchConfig: Config.HatchConfig(output: "."),
                postHatchSteps: [
                    Config.LifecycleStep(run: "echo \"Project: ${{ pre_hatch.info.outputs.name }}\" > info.txt"),
                ],
                verifications: [
                    .fileExists(path: "info.txt"),
                    .fileContent(path: "info.txt", expectedContent: "Project: TestProject\n"),
                ]
            ),

            // Hatch with exclusion rules
            .success(
                "applies exclusion rules during hatch",
                templateSetup: [
                    .file(path: "keep.txt", content: "keep"),
                    .file(path: "exclude.txt", content: "exclude"),
                ],
                hatchConfig: Config.HatchConfig(
                    output: ".",
                    exclude: [.path("exclude.txt")]
                ),
                verifications: [
                    .fileExists(path: "keep.txt"),
                    .fileNotExists(path: "exclude.txt"),
                ]
            ),

            // Conditional exclusion in hatch
            .success(
                "applies conditional exclusion during hatch",
                templateSetup: [
                    .file(path: "keep.txt", content: "keep"),
                    .file(path: "debug.txt", content: "debug"),
                ],
                macroDefinitions: [
                    Config.Macro(name: "___DEBUG___", description: "Debug Mode", type: .boolean),
                ],
                macros: [
                    ParsedMacroDefinition(macro: "___DEBUG___", values: ["true"]),
                ],
                hatchConfig: Config.HatchConfig(
                    output: ".",
                    exclude: [
                        .conditional(Config.ConditionalExclude(
                            if: "___DEBUG___ === true",
                            paths: ["debug.txt"]
                        )),
                    ]
                ),
                verifications: [
                    .fileExists(path: "keep.txt"),
                    .fileNotExists(path: "debug.txt"),
                ]
            ),

            // Multiple pre-hatch steps with chaining
            .success(
                "chains multiple pre_hatch steps",
                templateSetup: [
                    .file(path: "info.txt", content: "${{ pre_hatch.step1.outputs.value }},${{ pre_hatch.step2.outputs.value }}"),
                ],
                preHatchSteps: [
                    Config.LifecycleStep(id: "step1", run: "echo value=A"),
                    Config.LifecycleStep(id: "step2", run: "echo value=B"),
                ],
                hatchConfig: Config.HatchConfig(output: "."),
                verifications: [
                    .fileContent(path: "info.txt", expectedContent: "A,B"),
                ]
            ),

            // Multiple post-hatch steps
            .success(
                "executes multiple post_hatch steps",
                templateSetup: [
                    .file(path: "README.md", content: "Project"),
                ],
                hatchConfig: Config.HatchConfig(output: "."),
                postHatchSteps: [
                    Config.LifecycleStep(run: "echo 'Step 1' > step1.txt"),
                    Config.LifecycleStep(run: "echo 'Step 2' > step2.txt"),
                ],
                verifications: [
                    .fileExists(path: "step1.txt"),
                    .fileExists(path: "step2.txt"),
                    .fileContent(path: "step1.txt", expectedContent: "Step 1\n"),
                    .fileContent(path: "step2.txt", expectedContent: "Step 2\n"),
                ]
            ),

            // Conditional step execution in pre-hatch
            .success(
                "executes conditional pre_hatch step",
                templateSetup: [
                    .file(path: "README.md", content: "Project"),
                ],
                macroDefinitions: [
                    Config.Macro(name: "___ENABLE___", description: "Enable Feature", type: .boolean),
                ],
                macros: [
                    ParsedMacroDefinition(macro: "___ENABLE___", values: ["true"]),
                ],
                preHatchSteps: [
                    Config.LifecycleStep(
                        if: "___ENABLE___ === true",
                        run: "echo enabled=yes"
                    ),
                ],
                hatchConfig: Config.HatchConfig(output: "."),
                verifications: [
                    .fileExists(path: "README.md"),
                ]
            ),

            // Directory structure creation
            .success(
                "creates directory structure",
                templateSetup: [
                    .directory(path: "src"),
                    .file(path: "src/main.swift", content: "main"),
                    .directory(path: "tests"),
                    .file(path: "tests/test.swift", content: "test"),
                ],
                hatchConfig: Config.HatchConfig(output: "."),
                verifications: [
                    .directoryExists(path: "src"),
                    .fileExists(path: "src/main.swift"),
                    .directoryExists(path: "tests"),
                    .fileExists(path: "tests/test.swift"),
                ]
            ),

            // Macro substitution in hatch.output
            .success(
                "substitutes macros in hatch output path",
                templateSetup: [
                    .file(path: "README.md", content: "Hello"),
                ],
                macroDefinitions: [
                    Config.Macro(name: "___OUTPUT___", description: "Output Directory", type: .string),
                ],
                macros: [
                    ParsedMacroDefinition(macro: "___OUTPUT___", values: ["my-output"]),
                ],
                hatchConfig: Config.HatchConfig(output: "___OUTPUT___"),
                verifications: [
                    .fileExists(path: "README.md"),
                    .fileContent(path: "README.md", expectedContent: "Hello"),
                ]
            ),
        ]
    }

    enum TestError: Error {
        case temporaryDirectoryNotAvailable
    }
}

extension LifecycleWorkflowRunnerTests {
    private func setupTemplate(_ setup: [TestCase.TemplateSetup], in templateDir: AbsolutePath, using fileSystem: FileSystem) async throws {
        for item in setup {
            switch item {
            case let .file(path, content):
                try await createFile(at: path, content: content, in: templateDir, using: fileSystem)
            case let .directory(path):
                let dirPath = templateDir.appending(components: path.split(separator: "/").map(String.init))
                try await fileSystem.makeDirectory(at: dirPath, options: [.createTargetParentDirectories])
            }
        }
    }

    private func createFile(at path: String, content: String, in baseDir: AbsolutePath, using fileSystem: FileSystem) async throws {
        let components = path.split(separator: "/").map(String.init)
        let filePath = baseDir.appending(components: components)

        if components.count > 1 {
            let parentPath = baseDir.appending(components: Array(components.dropLast()))
            try await fileSystem.makeDirectory(at: parentPath, options: [.createTargetParentDirectories])
        }

        try await fileSystem.writeText(content, at: filePath)
    }

    private func verifyExpectations(_ verifications: [TestCase.Verification], in outputDir: AbsolutePath, using fileSystem: FileSystem) async throws {
        for verification in verifications {
            switch verification {
            case let .fileExists(path):
                let filePath = outputDir.appending(components: path.split(separator: "/").map(String.init))
                #expect(try await fileSystem.exists(filePath), "Expected file to exist: \(path)")

            case let .fileNotExists(path):
                let filePath = outputDir.appending(components: path.split(separator: "/").map(String.init))
                #expect(try await !fileSystem.exists(filePath), "Expected file to not exist: \(path)")

            case let .fileContent(path, expectedContent):
                let filePath = outputDir.appending(components: path.split(separator: "/").map(String.init))
                let data = try await fileSystem.readFile(at: filePath)
                let actualContent = String(data: data, encoding: .utf8) ?? ""
                #expect(actualContent == expectedContent, "Content mismatch in \(path)")

            case let .directoryExists(path):
                let dirPath = outputDir.appending(components: path.split(separator: "/").map(String.init))
                #expect(try await fileSystem.exists(dirPath, isDirectory: true), "Expected directory to exist: \(path)")
            }
        }
    }
}
