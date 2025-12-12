@testable import EggKit
import FileManagerProtocol
import Foundation
import Noora
import ProcessRunning
import Testing

struct LifecycleWorkflowRunnerTests {
    @Test(arguments: TestCase.allCases)
    func run(_ testCase: TestCase) async throws {
        let fileManager: some FileManagerProtocol = FileManager.default
        let tempDir = try fileManager.makeTemporaryDirectory(prefix: "lifecycle-test")

        defer {
            try? fileManager.removeItem(at: tempDir)
        }

        let workingDir = tempDir.appending(path: "work")
        let homeDir = tempDir.appending(path: "home")
        let templateDir = tempDir.appending(path: "template")

        try fileManager.createDirectory(at: workingDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: homeDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: templateDir, withIntermediateDirectories: true)

        // Setup template using helper
        try setupTemplate(testCase.templateSetup, in: templateDir, using: fileManager)

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
            fileManager: fileManager,
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
        try verifyExpectations(testCase.expectation.verifications, in: outputDir, using: fileManager)
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
}

extension LifecycleWorkflowRunnerTests {
    private func setupTemplate(_ setup: [TestCase.TemplateSetup], in templateDir: URL, using fileManager: some FileManagerProtocol) throws {
        for item in setup {
            switch item {
            case let .file(path, content):
                try createFile(at: path, content: content, in: templateDir, using: fileManager)
            case let .directory(path):
                let dirPath = templateDir.appending(path: path)
                try fileManager.createDirectory(at: dirPath, withIntermediateDirectories: true)
            }
        }
    }

    private func createFile(at path: String, content: String, in baseDir: URL, using fileManager: some FileManagerProtocol) throws {
        let filePath = baseDir.appending(path: path)
        let parentPath = filePath.deletingLastPathComponent()

        if !fileManager.exists(parentPath) {
            try fileManager.createDirectory(at: parentPath, withIntermediateDirectories: true)
        }

        try fileManager.writeText(content, at: filePath, encoding: .utf8)
    }

    private func verifyExpectations(_ verifications: [TestCase.Verification], in outputDir: URL, using fileManager: some FileManagerProtocol) throws {
        for verification in verifications {
            switch verification {
            case let .fileExists(path):
                let filePath = outputDir.appending(path: path)
                #expect(fileManager.exists(filePath), "Expected file to exist: \(path)")

            case let .fileNotExists(path):
                let filePath = outputDir.appending(path: path)
                #expect(!fileManager.exists(filePath), "Expected file to not exist: \(path)")

            case let .fileContent(path, expectedContent):
                let filePath = outputDir.appending(path: path)
                let data = try fileManager.readFile(at: filePath)
                let actualContent = String(data: data, encoding: .utf8) ?? ""
                #expect(actualContent == expectedContent, "Content mismatch in \(path)")

            case let .directoryExists(path):
                let dirPath = outputDir.appending(path: path)
                #expect(fileManager.isDirectory(at: dirPath), "Expected directory to exist: \(path)")
            }
        }
    }
}
