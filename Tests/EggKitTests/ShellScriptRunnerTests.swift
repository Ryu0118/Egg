@testable import EggKit
import Foundation
import Path
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

struct ShellScriptRunnerTests {
    @Test(arguments: TestCase.allCases)
    func execute(_ testCase: TestCase) async throws {
        let tempDir = try AbsolutePath(validating: FileManager.default.temporaryDirectory.path(percentEncoded: false))
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
                    #expect(stderr.isEmpty)
                } else {
                    #expect(stderr.contains(expectedStderr))
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
        let tempDir = try AbsolutePath(validating: NSTemporaryDirectory())
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
}
