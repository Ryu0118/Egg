@testable import EggKit
import FileManagerProtocol
import Foundation
import Testing

struct TemplateExpanderTests {
    private func makeBuiltInMacroContext(
        workingDirectory: URL,
        outputDirectory: URL,
    ) -> BuiltInMacroContext {
        BuiltInMacroContext(
            outputDirectory: outputDirectory,
            workingDirectory: workingDirectory,
            homeDirectory: workingDirectory,
            currentDate: Date(timeIntervalSince1970: 0),
            environment: [:],
        )
    }

    @Test(arguments: TestCase.allCases)
    func expand(_ testCase: TestCase) async throws {
        let fileManager: any FileManagerProtocol = FileManager.default
        let tempDir = URL(filePath: NSTemporaryDirectory()).appending(path: "template-expander-test-\(UUID().uuidString)")

        defer {
            try? fileManager.removeItem(at: tempDir)
        }

        let templateDir = tempDir.appending(path: "template")
        let outputDir = tempDir.appending(path: "output")

        try fileManager.createDirectory(at: templateDir, withIntermediateDirectories: true)

        // Setup template using helper
        try setupTemplate(testCase.templateSetup, in: templateDir, using: fileManager)

        // Setup existing files in output directory
        try setupExistingFiles(testCase.existingFiles, in: outputDir, using: fileManager)

        // Setup step outputs using helper
        let outputs = await setupOutputs(testCase.stepOutputs)

        let expander = TemplateExpander(
            fileManager: fileManager,
            templateDirectory: templateDir,
            outputDirectory: outputDir,
            builtInMacroContext: makeBuiltInMacroContext(
                workingDirectory: tempDir,
                outputDirectory: outputDir,
            ),
            isInteractive: testCase.isInteractive,
            override: testCase.override,
        )

        switch testCase.expectation {
        case let .success(verifications):
            try await expander.expand(
                substituting: testCase.macros,
                with: outputs,
                excluding: testCase.excludeRules,
            )
            // Verify expectations using helper
            try verifyExpectations(verifications, in: outputDir, using: fileManager)

        case let .failure(expectedError):
            let error = await #expect(throws: TemplateExpander.Error.self) {
                try await expander.expand(
                    substituting: testCase.macros,
                    with: outputs,
                    excluding: testCase.excludeRules,
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
                ],
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
                ],
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
                ],
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
                ],
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
                ],
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
                ],
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
                ],
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
                        paths: ["debug.txt"],
                    )),
                ],
                verifications: [
                    .fileExists(path: "keep.txt"),
                    .fileNotExists(path: "debug.txt"),
                ],
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
                        paths: ["debug.txt"],
                    )),
                ],
                verifications: [
                    .fileExists(path: "keep.txt"),
                    .fileExists(path: "debug.txt"),
                ],
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
                ],
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
                ],
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
                ],
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
                ],
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
                ],
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
                ],
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
                expectedError: .existingFilesWouldBeOverwritten(files: ["file.txt"]),
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
                expectedError: .existingFilesWouldBeOverwritten(files: ["Sources/Module/File.swift"]),
            ),

            // MARK: - Stencil template processing

            .success(
                "processes .stencil file with Stencil engine",
                templateSetup: [
                    .file(path: "App.swift.stencil", content: "struct {{ ___NAME___ }}App {}"),
                ],
                macros: [
                    ResolvedMacro(name: "___NAME___", description: "", value: .string("My")),
                ],
                verifications: [
                    .fileExists(path: "App.swift"),
                    .fileNotExists(path: "App.swift.stencil"),
                    .fileContent(path: "App.swift", expectedContent: "struct MyApp {}"),
                ],
            ),
            .success(
                "processes .stencil file with conditional",
                templateSetup: [
                    .file(path: "main.swift.stencil", content: "{% if ___ASYNC___ %}@main\nstruct App {\n    static func main() async {}\n}{% else %}print(\"Hello\"){% endif %}"),
                ],
                macros: [
                    ResolvedMacro(name: "___ASYNC___", description: "", value: .boolean(true)),
                ],
                verifications: [
                    .fileContent(path: "main.swift", expectedContent: "@main\nstruct App {\n    static func main() async {}\n}"),
                ],
            ),
            .success(
                "processes .stencil file with loop",
                templateSetup: [
                    .file(path: "imports.swift.stencil", content: "{% for m in ___MODULES___ %}import {{ m }}\n{% endfor %}"),
                ],
                macros: [
                    ResolvedMacro(name: "___MODULES___", description: "", value: .array(["Foundation", "UIKit"])),
                ],
                verifications: [
                    .fileContent(path: "imports.swift", expectedContent: "import Foundation\nimport UIKit\n"),
                ],
            ),
            .success(
                "processes .stencil file with step outputs",
                templateSetup: [
                    .file(path: "version.txt.stencil", content: "v{{ pre_hatch.setup.outputs.version }}"),
                ],
                stepOutputs: [
                    TestOutput(phase: .preHatch, stepId: "setup", values: ["version": "1.2.3"]),
                ],
                verifications: [
                    .fileContent(path: "version.txt", expectedContent: "v1.2.3"),
                ],
            ),
            .success(
                "keeps native files alongside .stencil files",
                templateSetup: [
                    .file(path: "native.swift", content: "// ___NAME___"),
                    .file(path: "template.swift.stencil", content: "// {{ ___NAME___ }}"),
                ],
                macros: [
                    ResolvedMacro(name: "___NAME___", description: "", value: .string("Test")),
                ],
                verifications: [
                    .fileContent(path: "native.swift", expectedContent: "// Test"),
                    .fileContent(path: "template.swift", expectedContent: "// Test"),
                ],
            ),
        ]

        /// Convenience initializer with defaults
        init(
            _ description: String,
            templateSetup: [TemplateSetup],
            macros: [ResolvedMacro] = [],
            stepOutputs: [TestOutput] = [],
            excludeRules: [Config.ExcludeRule]? = nil,
            existingFiles: [ExistingFile] = [],
            isInteractive: Bool = false,
            override: Bool = false,
            expectation: Expectation,
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

        /// Convenience method for simple success cases
        static func success(
            _ description: String,
            templateSetup: [TemplateSetup],
            macros: [ResolvedMacro] = [],
            stepOutputs: [TestOutput] = [],
            excludeRules: [Config.ExcludeRule]? = nil,
            existingFiles: [ExistingFile] = [],
            isInteractive: Bool = false,
            override: Bool = false,
            verifications: [Verification],
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
                expectation: .success(verifications: verifications),
            )
        }

        /// Convenience method for failure cases
        static func failure(
            _ description: String,
            templateSetup: [TemplateSetup],
            macros: [ResolvedMacro] = [],
            stepOutputs: [TestOutput] = [],
            excludeRules: [Config.ExcludeRule]? = nil,
            existingFiles: [ExistingFile] = [],
            isInteractive: Bool = false,
            override: Bool = false,
            expectedError: TemplateExpander.Error,
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
                expectation: .failure(expectedError: expectedError),
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

        var testDescription: String {
            description
        }
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
    private func setupTemplate(_ setup: [TestCase.TemplateSetup], in templateDir: URL, using fileManager: any FileManagerProtocol) throws {
        for item in setup {
            switch item {
            case let .file(path, content):
                try createFile(at: path, content: content, in: templateDir, using: fileManager)
            case let .directory(path):
                let dirPath = path.split(separator: "/").reduce(templateDir) { $0.appending(path: String($1)) }
                try fileManager.createDirectory(at: dirPath, withIntermediateDirectories: true)
            case let .binaryFile(path, data):
                try createBinaryFile(at: path, data: data, in: templateDir, using: fileManager)
            }
        }
    }

    private func createFile(at path: String, content: String, in baseDir: URL, using fileManager: any FileManagerProtocol) throws {
        let components = path.split(separator: "/").map(String.init)
        let filePath = components.reduce(baseDir) { $0.appending(path: String($1)) }

        if components.count > 1 {
            let parentPath = Array(components.dropLast()).reduce(baseDir) { $0.appending(path: String($1)) }
            try fileManager.createDirectory(at: parentPath, withIntermediateDirectories: true)
        }

        try fileManager.writeText(content, at: filePath, encoding: .utf8)
    }

    private func createBinaryFile(at path: String, data: Data, in baseDir: URL, using fileManager: any FileManagerProtocol) throws {
        let components = path.split(separator: "/").map(String.init)
        let filePath = components.reduce(baseDir) { $0.appending(path: String($1)) }

        if components.count > 1 {
            let parentPath = Array(components.dropLast()).reduce(baseDir) { $0.appending(path: String($1)) }
            try fileManager.createDirectory(at: parentPath, withIntermediateDirectories: true)
        }

        try data.write(to: filePath)
    }

    private func setupExistingFiles(_ existingFiles: [TestCase.ExistingFile], in outputDir: URL, using fileManager: any FileManagerProtocol) throws {
        guard !existingFiles.isEmpty else { return }

        try fileManager.createDirectory(at: outputDir, withIntermediateDirectories: true)

        for existing in existingFiles {
            try createFile(at: existing.path, content: existing.content, in: outputDir, using: fileManager)
        }
    }

    private func setupOutputs(_ outputs: [TestOutput]) async -> StepOutputsStorage {
        let storage = StepOutputsStorage()
        for output in outputs {
            await storage.store(phase: output.phase, stepId: output.stepId, outputs: output.values)
        }
        return storage
    }

    private func verifyExpectations(_ verifications: [TestCase.Verification], in outputDir: URL, using fileManager: any FileManagerProtocol) throws {
        for verification in verifications {
            switch verification {
            case let .fileExists(path):
                let filePath = path.split(separator: "/").reduce(outputDir) { $0.appending(path: String($1)) }
                #expect(fileManager.exists(filePath), "Expected file to exist: \(path)")

            case let .fileNotExists(path):
                let filePath = path.split(separator: "/").reduce(outputDir) { $0.appending(path: String($1)) }
                #expect(!fileManager.exists(filePath), "Expected file to not exist: \(path)")

            case let .fileContent(path, expectedContent):
                let filePath = path.split(separator: "/").reduce(outputDir) { $0.appending(path: String($1)) }
                let data = try fileManager.readFile(at: filePath)
                let actualContent = String(data: data, encoding: .utf8) ?? ""
                #expect(actualContent == expectedContent, "Content mismatch in \(path)")

            case let .binaryFileContent(path, expectedData):
                let filePath = path.split(separator: "/").reduce(outputDir) { $0.appending(path: String($1)) }
                let actualData = try fileManager.readFile(at: filePath)
                #expect(actualData == expectedData, "Binary data mismatch in \(path)")

            case let .directoryExists(path):
                let dirPath = path.split(separator: "/").reduce(outputDir) { $0.appending(path: String($1)) }
                #expect(fileManager.exists(dirPath), "Expected directory to exist: \(path)")
            }
        }
    }
}
