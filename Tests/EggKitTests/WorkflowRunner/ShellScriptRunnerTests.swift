@testable import EggKit
import Foundation
import ProcessRunning
import Subprocess
import Testing

#if canImport(System)
    import System
#else
    import SystemPackage
#endif

actor StreamCollector {
    var streamedChunks: [String] = []

    func append(_ chunk: String) {
        streamedChunks.append(chunk)
    }

    func getChunks() -> [String] {
        streamedChunks
    }
}

@Suite(.serialized)
struct ShellScriptRunnerTests {
    @Test(arguments: TestCase.allCases)
    func execute(_ testCase: TestCase) async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let runner = ShellScriptRunner(
            processRunner: ProcessRunner(),
            workingDirectory: tempDir
        )

        switch testCase.expectation {
        case let .success(expectedStdout, expectedStderr):
            let (stdout, stderr) = try await runner.execute(testCase.command)

            if expectedStdout.isEmpty {
                #expect(stdout.isEmpty)
            } else {
                #expect(stdout.contains(expectedStdout))
            }

            if let expectedStderr {
                if expectedStderr.isEmpty {
                    #expect(stderr?.isEmpty ?? true)
                } else {
                    #expect(stderr?.contains(expectedStderr) ?? false)
                }
            }
        case let .failure(expectedExitCode):
            let error = await #expect(throws: LifecycleStepError.self) {
                try await runner.execute(testCase.command)
            }

            guard let error, case let .shellExecutionError(_, exitCode, _) = error else {
                Issue.record("Expected shellExecutionError but got different error")
                return
            }
            if let expectedExitCode {
                #expect(exitCode == expectedExitCode)
            }
        }
    }

    @Test(arguments: StreamingTestCase.allCases)
    func executeStreaming(_ testCase: StreamingTestCase) async throws {
        let tempDir = URL(filePath: NSTemporaryDirectory())
        let runner = ShellScriptRunner(
            processRunner: ProcessRunner(),
            workingDirectory: tempDir
        )

        switch testCase.expectation {
        case let .success(expectedStdout):
            let collector = StreamCollector()

            let stdout = try await runner.executeStreaming(testCase.command) { chunk in
                Task {
                    await collector.append(chunk)
                }
            }

            // Verify that output was streamed
            let chunks = await collector.getChunks()
            #expect(!chunks.isEmpty, "Expected streamed output but got none")

            // Verify the complete stdout
            if expectedStdout.isEmpty {
                #expect(stdout.isEmpty)
            } else {
                #expect(stdout.contains(expectedStdout))
            }

            // Verify streamed chunks contain the expected output
            let combinedChunks = chunks.joined()
            #expect(combinedChunks.contains(expectedStdout))
        case let .failure(expectedExitCode):
            let error = await #expect(throws: LifecycleStepError.self) {
                try await runner.executeStreaming(testCase.command) { _ in }
            }

            guard let error, case let .shellExecutionError(_, exitCode, _) = error else {
                Issue.record("Expected shellExecutionError but got different error")
                return
            }
            if let expectedExitCode {
                #expect(exitCode == expectedExitCode)
            }
        }
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let command: String
        let expectation: Expectation

        var testDescription: String { description }

        enum Expectation {
            case success(expectedStdout: String, expectedStderr: String?)
            case failure(expectedExitCode: Int32?)
        }

        static let allCases: [TestCase] = [
            TestCase(
                description: "executes simple echo command",
                command: "echo 'Hello, World!'",
                expectation: .success(expectedStdout: "Hello, World!", expectedStderr: nil)
            ),
            TestCase(
                description: "captures stdout from command",
                command: "echo 'version=1.0.0'",
                expectation: .success(expectedStdout: "version=1.0.0", expectedStderr: nil)
            ),
            TestCase(
                description: "captures multiline stdout",
                command: """
                echo "line1"
                echo "line2"
                echo "line3"
                """,
                expectation: .success(expectedStdout: "line1", expectedStderr: nil)
            ),
            TestCase(
                description: "executes command with variables",
                command: "VAR='test'; echo $VAR",
                expectation: .success(expectedStdout: "test", expectedStderr: nil)
            ),
            TestCase(
                description: "executes command with pipe",
                command: "echo 'hello world' | tr '[:lower:]' '[:upper:]'",
                expectation: .success(expectedStdout: "HELLO WORLD", expectedStderr: nil)
            ),
            TestCase(
                description: "handles empty stdout",
                command: "true",
                expectation: .success(expectedStdout: "", expectedStderr: nil)
            ),
            TestCase(
                description: "throws on non-zero exit code",
                command: "exit 1",
                expectation: .failure(expectedExitCode: 1)
            ),
            TestCase(
                description: "throws on command not found",
                command: "nonexistent-command-xyz",
                expectation: .failure(expectedExitCode: 127)
            ),
            TestCase(
                description: "captures stderr on failure",
                command: "cat /nonexistent/file 2>&1",
                expectation: .failure(expectedExitCode: 1)
            ),
            TestCase(
                description: "executes complex shell script",
                command: """
                if [ -n "$HOME" ]; then
                  echo "HOME is set"
                else
                  echo "HOME is not set"
                fi
                """,
                expectation: .success(expectedStdout: "HOME is set", expectedStderr: nil)
            ),
        ]
    }

    struct StreamingTestCase: CustomTestStringConvertible {
        let description: String
        let command: String
        let expectation: Expectation

        var testDescription: String { description }

        enum Expectation {
            case success(expectedStdout: String)
            case failure(expectedExitCode: Int32?)
        }

        static let allCases: [StreamingTestCase] = [
            StreamingTestCase(
                description: "streams simple echo command",
                command: "echo 'Hello, Streaming!'",
                expectation: .success(expectedStdout: "Hello, Streaming!")
            ),
            StreamingTestCase(
                description: "streams multiline output",
                command: """
                echo "line1"
                echo "line2"
                echo "line3"
                """,
                expectation: .success(expectedStdout: "line1")
            ),
            StreamingTestCase(
                description: "streams command with pipe",
                command: "echo 'streaming test' | tr '[:lower:]' '[:upper:]'",
                expectation: .success(expectedStdout: "STREAMING TEST")
            ),
            StreamingTestCase(
                description: "throws on non-zero exit code",
                command: "exit 1",
                expectation: .failure(expectedExitCode: 1)
            ),
            StreamingTestCase(
                description: "throws on command not found",
                command: "nonexistent-streaming-command",
                expectation: .failure(expectedExitCode: 127)
            ),
        ]
    }

    @Test(arguments: EnvironmentTestCase.allCases)
    func executeWithAdditionalEnvironment(_ testCase: EnvironmentTestCase) async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let runner = ShellScriptRunner(
            processRunner: ProcessRunner(),
            workingDirectory: tempDir,
            additionalEnvironment: testCase.additionalEnvironment
        )

        let (stdout, _) = try await runner.execute(testCase.command)
        #expect(stdout.contains(testCase.expectedOutput), "Expected '\(testCase.expectedOutput)' in stdout, got '\(stdout)'")
    }

    @Test(arguments: EnvironmentTestCase.allCases)
    func executeStreamingWithAdditionalEnvironment(_ testCase: EnvironmentTestCase) async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let runner = ShellScriptRunner(
            processRunner: ProcessRunner(),
            workingDirectory: tempDir,
            additionalEnvironment: testCase.additionalEnvironment
        )

        let stdout = try await runner.executeStreaming(testCase.command) { _ in }
        #expect(stdout.contains(testCase.expectedOutput), "Expected '\(testCase.expectedOutput)' in stdout, got '\(stdout)'")
    }

    struct EnvironmentTestCase: CustomTestStringConvertible {
        let description: String
        let command: String
        let additionalEnvironment: [String: String]
        let expectedOutput: String

        var testDescription: String { description }

        static let allCases: [EnvironmentTestCase] = [
            EnvironmentTestCase(
                description: "accesses single additional environment variable",
                command: "echo $EGG_WORKSPACE_ROOT",
                additionalEnvironment: ["EGG_WORKSPACE_ROOT": "/tmp/workspace"],
                expectedOutput: "/tmp/workspace"
            ),
            EnvironmentTestCase(
                description: "accesses multiple additional environment variables",
                command: "echo $EGG_WORKSPACE_ROOT:$EGG_ORIGINAL_WORKING_DIR",
                additionalEnvironment: [
                    "EGG_WORKSPACE_ROOT": "/tmp/workspace",
                    "EGG_ORIGINAL_WORKING_DIR": "/Users/test/project",
                ],
                expectedOutput: "/tmp/workspace:/Users/test/project"
            ),
            EnvironmentTestCase(
                description: "additional environment variables are available in subshell",
                command: "sh -c 'echo $EGG_TEST_VAR'",
                additionalEnvironment: ["EGG_TEST_VAR": "subshell_value"],
                expectedOutput: "subshell_value"
            ),
            EnvironmentTestCase(
                description: "additional environment overrides inherited variable",
                command: "echo $HOME",
                additionalEnvironment: ["HOME": "/custom/home"],
                expectedOutput: "/custom/home"
            ),
            EnvironmentTestCase(
                description: "inherited environment is still accessible",
                command: "echo $PATH | grep -q '/' && echo 'PATH_EXISTS'",
                additionalEnvironment: ["EGG_CUSTOM": "value"],
                expectedOutput: "PATH_EXISTS"
            ),
            EnvironmentTestCase(
                description: "empty additional environment still inherits parent",
                command: "echo $PATH | grep -q '/' && echo 'PATH_EXISTS'",
                additionalEnvironment: [:],
                expectedOutput: "PATH_EXISTS"
            ),
        ]
    }
}
