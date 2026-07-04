import Foundation
import ProcessRunning

#if canImport(System)
    import System
#else
    import SystemPackage
#endif

/// Actor that caches the binary build result across test suites
actor BinaryBuildState {
    static let shared = BinaryBuildState()

    var buildTask: Task<URL, any Error>?

    private let processRunner: ProcessRunner
    private var cachedBinaryPath: URL?
    private var buildError: Error?

    private init() {
        processRunner = ProcessRunner()
    }

    /// Get the path to the built binary, building it if necessary
    func getBinaryPath() async throws -> URL {
        // Return cached path if available
        if let cachedPath = cachedBinaryPath {
            return cachedPath
        }

        // Re-throw cached error if build previously failed
        if let error = buildError {
            throw error
        }

        if let buildTask {
            return try await buildTask.value
        }

        do {
            let buildTask = Task {
                try await buildBinary()
            }
            self.buildTask = buildTask
            let path = try await buildTask.value
            cachedBinaryPath = path
            return path
        } catch {
            buildError = error
            throw error
        }
    }

    private func buildBinary() async throws -> URL {
        let packageRoot = findPackageRoot()

        let result = try await processRunner.run(
            .path(FilePath("/usr/bin/xcrun")),
            arguments: [
                "swift",
                "build",
                "--package-path",
                packageRoot.path(percentEncoded: false),
                "--product",
                "egg",
            ],
            workingDirectory: FilePath(packageRoot.path(percentEncoded: false)),
        ) { _, stream in
            var stdoutBuffer = Data()

            for try await chunk in stream {
                // Collect bytes for return value
                chunk.withUnsafeBytes { ptr in
                    stdoutBuffer.append(contentsOf: ptr)
                }
                // Stream output to caller's closure
                if let chunkString = String(data: Data(buffer: chunk), encoding: .utf8) {
                    print(chunkString)
                }
            }

            return stdoutBuffer
        }

        let output = String(data: result.value, encoding: .utf8)

        guard result.terminationStatus.isSuccess else {
            let exitCode: Int32 = switch result.terminationStatus {
            case let .exited(code):
                code
            case let .unhandledException(code):
                code
            }
            throw BinaryBuildError.buildFailed(exitCode: exitCode, output: output ?? "")
        }

        // Get binary path from build directory
        let binaryPath = packageRoot
            .appending(path: ".build")
            .appending(path: "debug")
            .appending(path: "egg")

        // Verify binary exists
        guard FileManager.default.fileExists(atPath: binaryPath.path(percentEncoded: false)) else {
            throw BinaryBuildError.binaryNotFound(path: binaryPath.path(percentEncoded: false))
        }

        return binaryPath
    }

    private func findPackageRoot() -> URL {
        // Use #filePath to find the current file location and navigate to egg package root
        let currentFile = URL(filePath: #filePath)
        // Navigate from E2ETestsPackage/Tests/E2ETests/Support/BinaryBuildState.swift to egg package root
        return currentFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
