@testable import EggKit
import FileManagerProtocol
import Foundation
import Path
import Testing

struct TemplateExpanderTests {
    @Test(.inTemporaryDirectory, arguments: TestCase.allCases)
    func expand(_ testCase: TestCase) async throws {
        let fileSystem = FileManager.default
        let tempDir = try await fileSystem.makeTemporaryDirectory(prefix: "template-expander-test")

        defer {
            Task { try? await fileSystem.remove(tempDir) }
        }

        let templateDir = tempDir.appending(component: "template")
        let outputDir = tempDir.appending(component: "output")

        try await fileSystem.makeDirectory(at: templateDir, options: [.createTargetParentDirectories])

        // Setup template using helper
        try await setupTemplate(testCase.templateSetup, in: templateDir, using: fileSystem)

        // Setup existing files in output directory
        try await setupExistingFiles(testCase.existingFiles, in: outputDir, using: fileSystem)

        // Setup step outputs using helper
        let outputs = await setupOutputs(testCase.stepOutputs)

        let expander = TemplateExpander(
            fileSystem: fileSystem,
            templateDirectory: templateDir,
            outputDirectory: outputDir,
            isInteractive: testCase.isInteractive,
            override: testCase.override
        )

        switch testCase.expectation {
        case let .success(verifications):
            try await expander.expand(
                substituting: testCase.macros,
                with: outputs,
                excluding: testCase.excludeRules
            )
            // Verify expectations using helper
            try await verifyExpectations(verifications, in: outputDir, using: fileSystem)

        case let .failure(expectedError):
            let error = await #expect(throws: TemplateExpander.Error.self) {
                try await expander.expand(
                    substituting: testCase.macros,
                    with: outputs,
                    excluding: testCase.excludeRules
                )
            }
            #expect(error == expectedError)
        }
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let templateSetup: [TemplateSetup]
        let macros: [ResolvedMacro]
        let stepOutputs: [TestOutput]
        let excludeRules: [Config.ExcludeRule]?
        let existingFiles: [ExistingFile]
        let isInteractive: Bool
        let override: Bool
        let expectation: Expectation

        var testDescription: String { description }

        // Convenience initializer with defaults
        init(
            _ description: String,
            templateSetup: [TemplateSetup],
            macros: [ResolvedMacro] = [],
            stepOutputs: [TestOutput] = [],
            excludeRules: [Config.ExcludeRule]? = nil,
            existingFiles: [ExistingFile] = [],
            isInteractive: Bool = false,
            override: Bool = false,
            expectation: Expectation
        ) {
            self.description = description
            self.templateSetup = templateSetup
            self.macros = macros
            self.stepOutputs = stepOutputs
            self.excludeRules = excludeRules
            self.existingFiles = existingFiles
            self.isInteractive = isInteractive
            self.override = override
            self.expectation = expectation
        }

        // Convenience method for simple success cases
        static func success(
            _ description: String,
            templateSetup: [TemplateSetup],
            macros: [ResolvedMacro] = [],
            stepOutputs: [TestOutput] = [],
            excludeRules: [Config.ExcludeRule]? = nil,
            existingFiles: [ExistingFile] = [],
            isInteractive: Bool = false,
            override: Bool = false,
            verifications: [Verification]
        ) -> TestCase {
            TestCase(
                description,
                templateSetup: templateSetup,
                macros: macros,
                stepOutputs: stepOutputs,
                excludeRules: excludeRules,
                existingFiles: existingFiles,
                isInteractive: isInteractive,
                override: override,
                expectation: .success(verifications: verifications)
            )
        }

        // Convenience method for failure cases
        static func failure(
            _ description: String,
            templateSetup: [TemplateSetup],
            macros: [ResolvedMacro] = [],
            stepOutputs: [TestOutput] = [],
            excludeRules: [Config.ExcludeRule]? = nil,
            existingFiles: [ExistingFile] = [],
            isInteractive: Bool = false,
            override: Bool = false,
            expectedError: TemplateExpander.Error
        ) -> TestCase {
            TestCase(
                description,
                templateSetup: templateSetup,
                macros: macros,
                stepOutputs: stepOutputs,
                excludeRules: excludeRules,
                existingFiles: existingFiles,
                isInteractive: isInteractive,
                override: override,
                expectation: .failure(expectedError: expectedError)
            )
        }

        enum TemplateSetup {
            case file(path: String, content: String)
            case directory(path: String)
            case binaryFile(path: String, data: Data)
        }

        struct ExistingFile {
            let path: String
            let content: String
        }

        enum Expectation {
            case success(verifications: [Verification])
            case failure(expectedError: TemplateExpander.Error)
        }

        enum Verification {
            case fileExists(path: String)
            case fileNotExists(path: String)
            case fileContent(path: String, expectedContent: String)
            case binaryFileContent(path: String, expectedData: Data)
            case directoryExists(path: String)
        }

        static let allCases: [TestCase] = [
            // Basic template expansion
            .success(
                "expands simple template",
                templateSetup: [
                    .file(path: "README.md", content: "Hello World"),
                ],
                verifications: [
                    .fileExists(path: "README.md"),
                    .fileContent(path: "README.md", expectedContent: "Hello World"),
                ]
            ),

            // Macro substitution in content
            .success(
                "substitutes macros in content",
                templateSetup: [
                    .file(path: "info.txt", content: "Project: ___PROJECT_NAME___"),
                ],
                macros: [
                    ResolvedMacro(name: "___PROJECT_NAME___", description: "Project Name", value: .string("MyApp")),
                ],
                verifications: [
                    .fileContent(path: "info.txt", expectedContent: "Project: MyApp"),
                ]
            ),

            // Macro substitution in filenames
            .success(
                "substitutes macros in filenames",
                templateSetup: [
                    .file(path: "___PROJECT_NAME___.swift", content: "content"),
                ],
                macros: [
                    ResolvedMacro(name: "___PROJECT_NAME___", description: "Project Name", value: .string("MyApp")),
                ],
                verifications: [
                    .fileExists(path: "MyApp.swift"),
                    .fileNotExists(path: "___PROJECT_NAME___.swift"),
                ]
            ),

            // Step output substitution
            .success(
                "substitutes step outputs in content",
                templateSetup: [
                    .file(path: "VERSION", content: "Version: ${{ pre_hatch.setup.outputs.version }}"),
                ],
                stepOutputs: [
                    TestOutput(phase: .preHatch, stepId: "setup", values: ["version": "1.0.0"]),
                ],
                verifications: [
                    .fileContent(path: "VERSION", expectedContent: "Version: 1.0.0"),
                ]
            ),

            // Directory structure
            .success(
                "expands directory structure",
                templateSetup: [
                    .directory(path: "src"),
                    .file(path: "src/main.swift", content: "main code"),
                    .directory(path: "tests"),
                    .file(path: "tests/test.swift", content: "test code"),
                ],
                verifications: [
                    .directoryExists(path: "src"),
                    .fileExists(path: "src/main.swift"),
                    .directoryExists(path: "tests"),
                    .fileExists(path: "tests/test.swift"),
                ]
            ),

            // Skip config.yml
            .success(
                "skips config.yml",
                templateSetup: [
                    .file(path: "config.yml", content: "config"),
                    .file(path: "README.md", content: "readme"),
                ],
                verifications: [
                    .fileNotExists(path: "config.yml"),
                    .fileExists(path: "README.md"),
                ]
            ),

            // Unconditional exclusion
            .success(
                "applies unconditional exclude rules",
                templateSetup: [
                    .file(path: "keep.txt", content: "keep"),
                    .file(path: "exclude.txt", content: "exclude"),
                ],
                excludeRules: [.path("exclude.txt")],
                verifications: [
                    .fileExists(path: "keep.txt"),
                    .fileNotExists(path: "exclude.txt"),
                ]
            ),

            // Conditional exclusion - true
            .success(
                "applies conditional exclude rules when true",
                templateSetup: [
                    .file(path: "keep.txt", content: "keep"),
                    .file(path: "debug.txt", content: "debug"),
                ],
                macros: [
                    ResolvedMacro(name: "___DEBUG___", description: "Debug Mode", value: .boolean(true)),
                ],
                excludeRules: [
                    .conditional(Config.ConditionalExclude(
                        if: "___DEBUG___ === true",
                        paths: ["debug.txt"]
                    )),
                ],
                verifications: [
                    .fileExists(path: "keep.txt"),
                    .fileNotExists(path: "debug.txt"),
                ]
            ),

            // Conditional exclusion - false
            .success(
                "does not apply conditional exclude rules when false",
                templateSetup: [
                    .file(path: "keep.txt", content: "keep"),
                    .file(path: "debug.txt", content: "debug"),
                ],
                macros: [
                    ResolvedMacro(name: "___DEBUG___", description: "Debug Mode", value: .boolean(false)),
                ],
                excludeRules: [
                    .conditional(Config.ConditionalExclude(
                        if: "___DEBUG___ === true",
                        paths: ["debug.txt"]
                    )),
                ],
                verifications: [
                    .fileExists(path: "keep.txt"),
                    .fileExists(path: "debug.txt"),
                ]
            ),

            // Glob pattern exclusion
            .success(
                "applies glob patterns for exclusion",
                templateSetup: [
                    .file(path: "keep.txt", content: "keep"),
                    .file(path: "test1.tmp", content: "test1"),
                    .file(path: "test2.tmp", content: "test2"),
                ],
                excludeRules: [.path("*.tmp")],
                verifications: [
                    .fileExists(path: "keep.txt"),
                    .fileNotExists(path: "test1.tmp"),
                    .fileNotExists(path: "test2.tmp"),
                ]
            ),

            // Binary file handling
            .success(
                "handles binary files",
                templateSetup: [
                    .binaryFile(path: "image.jpg", data: Data([0xFF, 0xD8, 0xFF, 0xE0])),
                ],
                verifications: [
                    .fileExists(path: "image.jpg"),
                    .binaryFileContent(path: "image.jpg", expectedData: Data([0xFF, 0xD8, 0xFF, 0xE0])),
                ]
            ),

            // Combined macros and outputs
            .success(
                "combines macros and outputs in content",
                templateSetup: [
                    .file(path: "info.txt", content: "Project: ___PROJECT_NAME___ v${{ pre_hatch.setup.outputs.version }}"),
                ],
                macros: [
                    ResolvedMacro(name: "___PROJECT_NAME___", description: "Project Name", value: .string("MyApp")),
                ],
                stepOutputs: [
                    TestOutput(phase: .preHatch, stepId: "setup", values: ["version": "2.0.0"]),
                ],
                verifications: [
                    .fileContent(path: "info.txt", expectedContent: "Project: MyApp v2.0.0"),
                ]
            ),

            // Override overwrites existing files
            .success(
                "overwrites existing files with override flag",
                templateSetup: [
                    .file(path: "file.txt", content: "new content"),
                ],
                existingFiles: [
                    ExistingFile(path: "file.txt", content: "old content"),
                ],
                override: true,
                verifications: [
                    .fileContent(path: "file.txt", expectedContent: "new content"),
                ]
            ),

            // Override overwrites nested files
            .success(
                "overwrites nested existing files with override flag",
                templateSetup: [
                    .file(path: "src/main.swift", content: "new main"),
                ],
                existingFiles: [
                    ExistingFile(path: "src/main.swift", content: "old main"),
                ],
                override: true,
                verifications: [
                    .fileContent(path: "src/main.swift", expectedContent: "new main"),
                ]
            ),

            // No conflict when files don't overlap
            .success(
                "succeeds when no existing files conflict",
                templateSetup: [
                    .file(path: "new-file.txt", content: "new content"),
                ],
                existingFiles: [
                    ExistingFile(path: "existing-file.txt", content: "existing content"),
                ],
                override: false,
                verifications: [
                    .fileExists(path: "new-file.txt"),
                    .fileExists(path: "existing-file.txt"),
                ]
            ),

            // Error without override when files conflict
            .failure(
                "throws error without override when files conflict",
                templateSetup: [
                    .file(path: "file.txt", content: "new content"),
                ],
                existingFiles: [
                    ExistingFile(path: "file.txt", content: "old content"),
                ],
                override: false,
                expectedError: .existingFilesWouldBeOverwritten(files: ["file.txt"])
            ),

            // Error reports only leaf paths, not parent directories
            .failure(
                "reports only leaf paths in conflict error",
                templateSetup: [
                    .file(path: "Sources/Module/File.swift", content: "code"),
                ],
                existingFiles: [
                    ExistingFile(path: "Sources/Module/File.swift", content: "old code"),
                ],
                override: false,
                expectedError: .existingFilesWouldBeOverwritten(files: ["Sources/Module/File.swift"])
            ),
        ]
    }

    struct TestOutput {
        let phase: LifecyclePhase
        let stepId: String
        let values: [String: String]
    }

    enum TestError: Error {
        case temporaryDirectoryNotAvailable
    }
}

extension TemplateExpanderTests {
    private func setupTemplate(_ setup: [TestCase.TemplateSetup], in templateDir: AbsolutePath, using fileSystem: FileSystem) async throws {
        for item in setup {
            switch item {
            case let .file(path, content):
                try await createFile(at: path, content: content, in: templateDir, using: fileSystem)
            case let .directory(path):
                let dirPath = templateDir.appending(components: path.split(separator: "/").map(String.init))
                try await fileSystem.makeDirectory(at: dirPath, options: [.createTargetParentDirectories])
            case let .binaryFile(path, data):
                try await createBinaryFile(at: path, data: data, in: templateDir, using: fileSystem)
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

    private func createBinaryFile(at path: String, data: Data, in baseDir: AbsolutePath, using fileSystem: FileSystem) async throws {
        let components = path.split(separator: "/").map(String.init)
        let filePath = baseDir.appending(components: components)

        if components.count > 1 {
            let parentPath = baseDir.appending(components: Array(components.dropLast()))
            try await fileSystem.makeDirectory(at: parentPath, options: [.createTargetParentDirectories])
        }

        try data.write(to: URL(filePath: filePath.pathString))
    }

    private func setupExistingFiles(_ existingFiles: [TestCase.ExistingFile], in outputDir: AbsolutePath, using fileSystem: FileSystem) async throws {
        guard !existingFiles.isEmpty else { return }

        try await fileSystem.makeDirectory(at: outputDir, options: [.createTargetParentDirectories])

        for existing in existingFiles {
            try await createFile(at: existing.path, content: existing.content, in: outputDir, using: fileSystem)
        }
    }

    private func setupOutputs(_ outputs: [TestOutput]) async -> StepOutputsStorage {
        let storage = StepOutputsStorage()
        for output in outputs {
            await storage.store(phase: output.phase, stepId: output.stepId, outputs: output.values)
        }
        return storage
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

            case let .binaryFileContent(path, expectedData):
                let filePath = outputDir.appending(components: path.split(separator: "/").map(String.init))
                let actualData = try await fileSystem.readFile(at: filePath)
                #expect(actualData == expectedData, "Binary data mismatch in \(path)")

            case let .directoryExists(path):
                let dirPath = outputDir.appending(components: path.split(separator: "/").map(String.init))
                #expect(try await fileSystem.exists(dirPath, isDirectory: true), "Expected directory to exist: \(path)")
            }
        }
    }
}
