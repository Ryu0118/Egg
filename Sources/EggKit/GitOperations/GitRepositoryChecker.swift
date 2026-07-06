import Foundation
import ProcessRunning
import Subprocess

#if canImport(System)
    import System
#else
    import SystemPackage
#endif

/// Checks if a directory is inside a git repository.
struct GitRepositoryChecker {
    private let processRunner: any ProcessRunning

    init(processRunner: some ProcessRunning = ProcessRunner()) {
        self.processRunner = processRunner
    }

    /// The repository's top-level working-tree directory, or nil when the
    /// directory isn't inside a git repository.
    ///
    /// Uses `git rev-parse --show-toplevel`. Callers compare it against the
    /// working directory to detect "running from a subdirectory of the repo"
    /// — where hatch output resolves relative to the subdirectory, which is
    /// easy to trip over silently.
    func repositoryRoot(of directory: URL) async -> URL? {
        let result = try? await processRunner.run(
            .path("/usr/bin/git"),
            arguments: Arguments(["rev-parse", "--show-toplevel"]),
            environment: .inherit,
            workingDirectory: FilePath(directory.path),
            platformOptions: PlatformOptions(),
            input: .none,
            output: .bytes(limit: 4096),
            error: .bytes(limit: 1024),
        )

        guard let result, case let .exited(code) = result.terminationStatus, code == 0 else {
            return nil
        }

        let path = String(decoding: result.standardOutput, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return URL(filePath: path)
    }

    /// Checks if the directory is inside a git repository.
    ///
    /// Uses `git rev-parse --is-inside-work-tree` to determine if the directory
    /// is within a git repository's working tree.
    ///
    /// - Parameter directory: The directory URL to check
    /// - Returns: `true` if the directory is inside a git repository, `false` otherwise
    func isGitRepository(_ directory: URL) async -> Bool {
        let result = try? await processRunner.run(
            .path("/usr/bin/git"),
            arguments: Arguments(["rev-parse", "--is-inside-work-tree"]),
            environment: .inherit,
            workingDirectory: FilePath(directory.path),
            platformOptions: PlatformOptions(),
            input: .none,
            output: .bytes(limit: 1024),
            error: .bytes(limit: 1024),
        )

        guard let result else { return false }

        return switch result.terminationStatus {
        case let .exited(code):
            code == 0
        case .unhandledException:
            false
        }
    }
}
