import Foundation
import ProcessRunning
import Subprocess

#if canImport(System)
    import System
#else
    import SystemPackage
#endif

/// A protocol for cloning Git repositories.
package protocol GitCloning: Sendable {
    /// Clones a Git repository to the specified destination.
    ///
    /// - Parameters:
    ///   - url: The Git URL to clone
    ///   - destination: The directory to clone into
    ///   - ref: Optional Git reference (branch/tag/revision). If `nil`, uses the default branch.
    /// - Throws: `GitCloner.Error` if cloning fails
    func clone(url: GitURL, to destination: URL, ref: GitRef?) async throws

    /// Returns the commit SHA currently checked out at `destination`.
    ///
    /// - Parameter destination: A directory previously populated by `clone(url:to:ref:)`.
    /// - Throws: `GitCloner.Error` if `git rev-parse HEAD` fails.
    func headRevision(at destination: URL) async throws -> String
}

/// Clones Git repositories using the system `git` command.
///
/// Supports cloning with specific branches, tags, or commit SHAs.
/// Uses the user's existing Git authentication (SSH keys, credential helpers).
package struct GitCloner: GitCloning {
    private let processRunner: any ProcessRunning

    package init(processRunner: some ProcessRunning = ProcessRunner()) {
        self.processRunner = processRunner
    }

    package func clone(url: GitURL, to destination: URL, ref: GitRef?) async throws {
        switch ref {
        case let .branch(name):
            try await cloneWithBranch(url: url, to: destination, branch: name)
        case let .tag(name):
            try await cloneWithBranch(url: url, to: destination, branch: name)
        case let .revision(sha):
            try await cloneAndCheckout(url: url, to: destination, revision: sha)
        case nil:
            try await cloneDefault(url: url, to: destination)
        }
    }

    package func headRevision(at destination: URL) async throws -> String {
        let result = try await processRunner.run(
            .path("/usr/bin/git"),
            arguments: Arguments(["rev-parse", "HEAD"]),
            environment: .inherit,
            workingDirectory: FilePath(destination.path),
            platformOptions: PlatformOptions(),
            input: .none,
            output: .bytes(limit: .max),
            error: .bytes(limit: .max),
        )

        switch result.terminationStatus {
        case let .exited(code) where code != 0:
            let stderr = String(decoding: result.standardError, as: UTF8.self)
            throw Error.headRevisionFailed(path: destination.path(percentEncoded: false), exitCode: code, stderr: stderr)
        case .unhandledException:
            throw Error.headRevisionFailed(path: destination.path(percentEncoded: false), exitCode: -1, stderr: "Unhandled exception")
        default:
            return String(decoding: result.standardOutput, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Clones with the default branch (no --branch flag)
    private func cloneDefault(url: GitURL, to destination: URL) async throws {
        let arguments = Arguments([
            "clone",
            url.normalized,
            destination.path,
        ])

        let result = try await processRunner.run(
            .path("/usr/bin/git"),
            arguments: arguments,
            environment: .inherit,
            workingDirectory: nil,
            platformOptions: PlatformOptions(),
            input: .none,
            output: .bytes(limit: .max),
            error: .bytes(limit: .max),
        )

        switch result.terminationStatus {
        case let .exited(code) where code != 0:
            let stderr = String(decoding: result.standardError, as: UTF8.self)
            throw Error.cloneFailed(url: url.original, exitCode: code, stderr: stderr)
        case .unhandledException:
            throw Error.cloneFailed(url: url.original, exitCode: -1, stderr: "Unhandled exception")
        default:
            break
        }
    }

    /// Clones with a specific branch or tag using --branch flag
    private func cloneWithBranch(url: GitURL, to destination: URL, branch: String) async throws {
        let arguments = Arguments([
            "clone",
            "--branch", branch,
            url.normalized,
            destination.path,
        ])

        let result = try await processRunner.run(
            .path("/usr/bin/git"),
            arguments: arguments,
            environment: .inherit,
            workingDirectory: nil,
            platformOptions: PlatformOptions(),
            input: .none,
            output: .bytes(limit: .max),
            error: .bytes(limit: .max),
        )

        switch result.terminationStatus {
        case let .exited(code) where code != 0:
            let stderr = String(decoding: result.standardError, as: UTF8.self)
            throw Error.cloneFailed(url: url.original, exitCode: code, stderr: stderr)
        case .unhandledException:
            throw Error.cloneFailed(url: url.original, exitCode: -1, stderr: "Unhandled exception")
        default:
            break
        }
    }

    /// Clones and then checks out a specific revision (commit SHA)
    private func cloneAndCheckout(url: GitURL, to destination: URL, revision: String) async throws {
        // First, clone without specifying a branch
        try await cloneDefault(url: url, to: destination)

        // Then checkout the specific revision
        let checkoutArguments = Arguments([
            "checkout",
            revision,
        ])

        let checkoutResult = try await processRunner.run(
            .path("/usr/bin/git"),
            arguments: checkoutArguments,
            environment: .inherit,
            workingDirectory: FilePath(destination.path),
            platformOptions: PlatformOptions(),
            input: .none,
            output: .bytes(limit: .max),
            error: .bytes(limit: .max),
        )

        switch checkoutResult.terminationStatus {
        case let .exited(code) where code != 0:
            let stderr = String(decoding: checkoutResult.standardError, as: UTF8.self)
            // Check if the error indicates the ref was not found
            if stderr.contains("did not match any") || stderr.contains("pathspec") {
                throw Error.refNotFound(ref: .revision(revision))
            }
            throw Error.checkoutFailed(ref: .revision(revision), exitCode: code, stderr: stderr)
        case .unhandledException:
            throw Error.checkoutFailed(ref: .revision(revision), exitCode: -1, stderr: "Unhandled exception")
        default:
            break
        }
    }
}

package extension GitCloner {
    /// Errors that can occur during Git cloning operations.
    enum Error: LocalizedError, Equatable {
        /// The clone operation failed
        case cloneFailed(url: String, exitCode: Int32, stderr: String)
        /// The checkout operation failed after cloning
        case checkoutFailed(ref: GitRef, exitCode: Int32, stderr: String)
        /// The specified ref (branch/tag/revision) was not found
        case refNotFound(ref: GitRef)
        /// `git rev-parse HEAD` failed at a previously-cloned directory
        case headRevisionFailed(path: String, exitCode: Int32, stderr: String)

        package var errorDescription: String? {
            switch self {
            case let .cloneFailed(url, exitCode, stderr):
                var message = "Failed to clone repository '\(url)' (exit code: \(exitCode))"
                if !stderr.isEmpty {
                    message += "\n\(stderr)"
                }
                return message

            case let .checkoutFailed(ref, exitCode, stderr):
                var message = "Failed to checkout \(ref.typeDescription) '\(ref.value)' (exit code: \(exitCode))"
                if !stderr.isEmpty {
                    message += "\n\(stderr)"
                }
                return message

            case let .refNotFound(ref):
                return "\(ref.typeDescription.capitalized) '\(ref.value)' was not found in the repository"

            case let .headRevisionFailed(path, exitCode, stderr):
                var message = "Failed to resolve HEAD revision at '\(path)' (exit code: \(exitCode))"
                if !stderr.isEmpty {
                    message += "\n\(stderr)"
                }
                return message
            }
        }
    }
}

private extension GitRef {
    var typeDescription: String {
        switch self {
        case .branch: "branch"
        case .tag: "tag"
        case .revision: "revision"
        }
    }
}
