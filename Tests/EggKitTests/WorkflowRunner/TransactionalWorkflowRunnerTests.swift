@testable import EggKit
import FileSystem
import Foundation
import Noora
import Path
import ProcessRunning
import Testing

struct TransactionalWorkflowRunnerTests {
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

        // Setup initial working directory files
        for item in testCase.workingDirSetup {
            try await setupItem(item, in: workingDir, using: fileSystem)
        }

        // Setup template
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
        let runner = TransactionalWorkflowRunner(
            processRunner: ProcessRunner(),
            fileSystem: fileSystem,
            workingDirectory: workingDir,
            homeDirectory: homeDir,
            noora: nooraMock,
            isInteractive: false,
            force: testCase.force,
            workspaceWatcher: ScanningDirectoryWatcher(fileSystem: FileSystem()),
            workingDirectoryWatcher: ScanningDirectoryWatcher(fileSystem: FileSystem())
        )

        do {
            let outputDir = try await runner.run(
                config: config,
                macroInputs: .parsed(testCase.macros),
                templateDirectory: templateDir
            )

            // Verify success expectations
            if case let .success(verifications) = testCase.expectation {
                try await verifyExpectations(verifications, in: outputDir, using: fileSystem)
            } else {
                Issue.record("Expected error but succeeded")
            }
        } catch {
            // Verify error expectations
            if case let .error(errorType) = testCase.expectation {
                try verifyError(error, matches: errorType)
            } else {
                throw error
            }
        }
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let workingDirSetup: [FileSetup]
        let templateSetup: [FileSetup]
        let macroDefinitions: [Config.Macro]
        let macros: [ParsedMacroDefinition]
        let preHatchSteps: [Config.LifecycleStep]?
        let hatchConfig: Config.HatchConfig
        let postHatchSteps: [Config.LifecycleStep]?
        let force: Bool
        let expectation: Expectation

        var testDescription: String { description }

        init(
            _ description: String,
            workingDirSetup: [FileSetup] = [],
            templateSetup: [FileSetup],
            macroDefinitions: [Config.Macro] = [],
            macros: [ParsedMacroDefinition] = [],
            preHatchSteps: [Config.LifecycleStep]? = nil,
            hatchConfig: Config.HatchConfig = Config.HatchConfig(output: "."),
            postHatchSteps: [Config.LifecycleStep]? = nil,
            force: Bool = true,
            expectation: Expectation
        ) {
            self.description = description
            self.workingDirSetup = workingDirSetup
            self.templateSetup = templateSetup
            self.macroDefinitions = macroDefinitions
            self.macros = macros
            self.preHatchSteps = preHatchSteps
            self.hatchConfig = hatchConfig
            self.postHatchSteps = postHatchSteps
            self.force = force
            self.expectation = expectation
        }

        static func success(
            _ description: String,
            workingDirSetup: [FileSetup] = [],
            templateSetup: [FileSetup],
            macroDefinitions: [Config.Macro] = [],
            macros: [ParsedMacroDefinition] = [],
            preHatchSteps: [Config.LifecycleStep]? = nil,
            hatchConfig: Config.HatchConfig = Config.HatchConfig(output: "."),
            postHatchSteps: [Config.LifecycleStep]? = nil,
            force: Bool = true,
            verifications: [Verification]
        ) -> TestCase {
            TestCase(
                description,
                workingDirSetup: workingDirSetup,
                templateSetup: templateSetup,
                macroDefinitions: macroDefinitions,
                macros: macros,
                preHatchSteps: preHatchSteps,
                hatchConfig: hatchConfig,
                postHatchSteps: postHatchSteps,
                force: force,
                expectation: .success(verifications: verifications)
            )
        }

        enum FileSetup {
            case file(path: String, content: String)
            case directory(path: String)
        }

        enum Expectation {
            case success(verifications: [Verification])
            case error(ExpectedError)
        }

        enum ExpectedError {
            case userAborted
            case escapeAttempt
        }

        enum Verification {
            case fileExists(path: String)
            case fileNotExists(path: String)
            case fileContent(path: String, expectedContent: String)
            case directoryExists(path: String)
        }

        static let allCases: [TestCase] = [
            // Basic workflow in transactional workspace
            .success(
                "executes complete workflow in transactional workspace",
                templateSetup: [
                    .file(path: "README.md", content: "Hello World"),
                ],
                verifications: [
                    .fileExists(path: "README.md"),
                    .fileContent(path: "README.md", expectedContent: "Hello World"),
                ]
            ),

            // Pre-hatch creates file that appears in working dir after apply
            .success(
                "pre_hatch changes applied to working dir",
                templateSetup: [
                    .file(path: "app.txt", content: "app"),
                ],
                preHatchSteps: [
                    Config.LifecycleStep(run: "echo 'pre_hatch_output' > pre_output.txt"),
                ],
                verifications: [
                    .fileExists(path: "app.txt"),
                    .fileExists(path: "pre_output.txt"),
                    .fileContent(path: "pre_output.txt", expectedContent: "pre_hatch_output\n"),
                ]
            ),

            // Post-hatch creates file that appears in working dir after apply
            .success(
                "post_hatch changes applied to working dir",
                templateSetup: [
                    .file(path: "app.txt", content: "app"),
                ],
                postHatchSteps: [
                    Config.LifecycleStep(run: "echo 'post_hatch_output' > post_output.txt"),
                ],
                verifications: [
                    .fileExists(path: "app.txt"),
                    .fileExists(path: "post_output.txt"),
                    .fileContent(path: "post_output.txt", expectedContent: "post_hatch_output\n"),
                ]
            ),

            // Complete workflow: pre_hatch + hatch + post_hatch
            .success(
                "complete workflow with all phases",
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
                postHatchSteps: [
                    Config.LifecycleStep(run: "echo 'Done' > done.txt"),
                ],
                verifications: [
                    .fileContent(path: "PROJECT", expectedContent: "MyApp v2.0.0"),
                    .fileExists(path: "done.txt"),
                ]
            ),

            // Macro substitution
            .success(
                "applies macro substitution",
                templateSetup: [
                    .file(path: "config.txt", content: "name=___PROJECT___\nversion=___VERSION___"),
                ],
                macroDefinitions: [
                    Config.Macro(name: "___PROJECT___", description: "Project", type: .string),
                    Config.Macro(name: "___VERSION___", description: "Version", type: .string),
                ],
                macros: [
                    ParsedMacroDefinition(macro: "___PROJECT___", values: ["TestProject"]),
                    ParsedMacroDefinition(macro: "___VERSION___", values: ["1.0.0"]),
                ],
                verifications: [
                    .fileContent(path: "config.txt", expectedContent: "name=TestProject\nversion=1.0.0"),
                ]
            ),

            // Environment variables available in transactional workspace scripts
            .success(
                "workspace env vars available in pre_hatch",
                templateSetup: [
                    .file(path: "app.txt", content: "app"),
                ],
                preHatchSteps: [
                    Config.LifecycleStep(run: "echo \"workspace=$EGG_WORKSPACE_ROOT\" > env.txt"),
                ],
                verifications: [
                    .fileExists(path: "env.txt"),
                    // File should contain workspace= (non-empty value)
                ]
            ),

            // Hatch with exclusion rules
            .success(
                "applies exclusion rules",
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

            // Output to subdirectory
            .success(
                "outputs to subdirectory",
                templateSetup: [
                    .file(path: "README.md", content: "Hello"),
                ],
                hatchConfig: Config.HatchConfig(output: "subdir"),
                verifications: [
                    .directoryExists(path: "."),
                    .fileExists(path: "README.md"),
                ]
            ),

            // Existing files are modified (not duplicated)
            .success(
                "modifies existing files",
                workingDirSetup: [
                    .file(path: "existing.txt", content: "old content"),
                ],
                templateSetup: [
                    .file(path: "existing.txt", content: "new content"),
                ],
                verifications: [
                    .fileContent(path: "existing.txt", expectedContent: "new content"),
                ]
            ),

            // Pre-hatch output propagates to hatch
            .success(
                "pre_hatch outputs available in hatch",
                templateSetup: [
                    .file(path: "version.txt", content: "${{ pre_hatch.get_version.outputs.ver }}"),
                ],
                preHatchSteps: [
                    Config.LifecycleStep(id: "get_version", run: "echo ver=3.5.1"),
                ],
                verifications: [
                    .fileContent(path: "version.txt", expectedContent: "3.5.1"),
                ]
            ),

            // Post-hatch can access pre_hatch outputs
            .success(
                "post_hatch accesses pre_hatch outputs",
                templateSetup: [
                    .file(path: "README.md", content: "Project"),
                ],
                preHatchSteps: [
                    Config.LifecycleStep(id: "info", run: "echo name=TestProject"),
                ],
                postHatchSteps: [
                    Config.LifecycleStep(run: "echo \"Project: ${{ pre_hatch.info.outputs.name }}\" > info.txt"),
                ],
                verifications: [
                    .fileExists(path: "info.txt"),
                    .fileContent(path: "info.txt", expectedContent: "Project: TestProject\n"),
                ]
            ),

            // Multiple pre-hatch steps
            .success(
                "chains multiple pre_hatch steps",
                templateSetup: [
                    .file(path: "combined.txt", content: "${{ pre_hatch.step1.outputs.val }},${{ pre_hatch.step2.outputs.val }}"),
                ],
                preHatchSteps: [
                    Config.LifecycleStep(id: "step1", run: "echo val=A"),
                    Config.LifecycleStep(id: "step2", run: "echo val=B"),
                ],
                verifications: [
                    .fileContent(path: "combined.txt", expectedContent: "A,B"),
                ]
            ),

            // Multiple post-hatch steps
            .success(
                "executes multiple post_hatch steps",
                templateSetup: [
                    .file(path: "README.md", content: "Project"),
                ],
                postHatchSteps: [
                    Config.LifecycleStep(run: "echo 'Step 1' > step1.txt"),
                    Config.LifecycleStep(run: "echo 'Step 2' > step2.txt"),
                ],
                verifications: [
                    .fileExists(path: "step1.txt"),
                    .fileExists(path: "step2.txt"),
                ]
            ),

            // Directory structure preservation
            .success(
                "preserves directory structure",
                templateSetup: [
                    .directory(path: "src"),
                    .file(path: "src/main.swift", content: "main"),
                    .directory(path: "tests"),
                    .file(path: "tests/test.swift", content: "test"),
                ],
                verifications: [
                    .directoryExists(path: "src"),
                    .fileExists(path: "src/main.swift"),
                    .directoryExists(path: "tests"),
                    .fileExists(path: "tests/test.swift"),
                ]
            ),

            // Conditional step execution
            .success(
                "executes conditional pre_hatch step",
                templateSetup: [
                    .file(path: "README.md", content: "Project"),
                ],
                macroDefinitions: [
                    Config.Macro(name: "___ENABLE___", description: "Enable", type: .boolean),
                ],
                macros: [
                    ParsedMacroDefinition(macro: "___ENABLE___", values: ["true"]),
                ],
                preHatchSteps: [
                    Config.LifecycleStep(
                        id: "conditional",
                        if: "___ENABLE___ === true",
                        run: "echo enabled=yes > conditional.txt"
                    ),
                ],
                verifications: [
                    .fileExists(path: "conditional.txt"),
                ]
            ),
        ]
    }

    enum TestError: Error {
        case temporaryDirectoryNotAvailable
    }
}

extension TransactionalWorkflowRunnerTests {
    private func setupItem(_ item: TestCase.FileSetup, in baseDir: AbsolutePath, using fileSystem: FileSystem) async throws {
        switch item {
        case let .file(path, content):
            try await createFile(at: path, content: content, in: baseDir, using: fileSystem)
        case let .directory(path):
            let dirPath = baseDir.appending(components: path.split(separator: "/").map(String.init))
            try await fileSystem.makeDirectory(at: dirPath, options: [.createTargetParentDirectories])
        }
    }

    private func setupTemplate(_ setup: [TestCase.FileSetup], in templateDir: AbsolutePath, using fileSystem: FileSystem) async throws {
        for item in setup {
            try await setupItem(item, in: templateDir, using: fileSystem)
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

    private func verifyError(_ error: Error, matches expectedType: TestCase.ExpectedError) throws {
        switch expectedType {
        case .userAborted:
            guard let workspaceError = error as? TransactionalWorkspaceContext.Error,
                  case .userAborted = workspaceError
            else {
                Issue.record("Expected userAborted error, got: \(error)")
                return
            }

        case .escapeAttempt:
            guard let workspaceError = error as? TransactionalWorkspaceContext.Error,
                  case .escapeAttempt = workspaceError
            else {
                Issue.record("Expected escapeAttempt error, got: \(error)")
                return
            }
        }
    }
}
