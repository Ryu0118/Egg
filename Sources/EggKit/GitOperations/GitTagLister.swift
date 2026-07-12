import Foundation
import ProcessRunning
import Subprocess

#if canImport(System)
    import System
#else
    import SystemPackage
#endif

/// A tag advertised by a remote Git repository.
package struct GitRemoteTag: Equatable {
    /// The tag name (e.g. "v1.2.3"), without the `refs/tags/` prefix.
    package let name: String
    /// The SHA of the tag ref itself. For annotated tags this is the tag
    /// object, not the commit.
    package let objectSHA: String
    /// The commit SHA an annotated tag points to (from the `^{}` peeled
    /// entry). `nil` for lightweight tags.
    package let peeledSHA: String?

    package init(name: String, objectSHA: String, peeledSHA: String? = nil) {
        self.name = name
        self.objectSHA = objectSHA
        self.peeledSHA = peeledSHA
    }

    /// The commit SHA to install from: the peeled SHA when present
    /// (annotated tag), otherwise the object SHA (lightweight tag).
    package var revision: String {
        peeledSHA ?? objectSHA
    }
}

/// A protocol for listing refs advertised by a remote Git repository.
package protocol GitTagListing: Sendable {
    /// Lists all tags advertised by the remote.
    func listTags(url: GitURL) async throws -> [GitRemoteTag]

    /// Returns the commit SHA of a remote branch head, or `nil` when the
    /// branch does not exist on the remote.
    func remoteBranchRevision(url: GitURL, branch: String) async throws -> String?
}

/// Lists remote refs using `git ls-remote`, without cloning.
///
/// Uses the user's existing Git authentication (SSH keys, credential
/// helpers), exactly like ``GitCloner``.
package struct GitTagLister: GitTagListing {
    private let processRunner: any ProcessRunning

    package init(processRunner: some ProcessRunning = ProcessRunner()) {
        self.processRunner = processRunner
    }

    package func listTags(url: GitURL) async throws -> [GitRemoteTag] {
        let output = try await runLsRemote(url: url, arguments: ["ls-remote", "--tags", url.normalized])
        return Self.parseTagOutput(output)
    }

    package func remoteBranchRevision(url: GitURL, branch: String) async throws -> String? {
        let output = try await runLsRemote(
            url: url,
            arguments: ["ls-remote", url.normalized, "refs/heads/\(branch)"],
        )
        return Self.parseBranchOutput(output, branch: branch)
    }

    /// Parses `git ls-remote --tags` output.
    ///
    /// Annotated tags produce two lines — `refs/tags/<name>` (tag object)
    /// and `refs/tags/<name>^{}` (peeled commit) — which are merged into a
    /// single ``GitRemoteTag``. Unparseable lines are skipped silently.
    static func parseTagOutput(_ output: String) -> [GitRemoteTag] {
        let tagRefPrefix = "refs/tags/"
        let peeledSuffix = "^{}"

        var order: [String] = []
        var objectSHAs: [String: String] = [:]
        var peeledSHAs: [String: String] = [:]

        for line in output.split(separator: "\n") {
            guard let (sha, ref) = parseLine(line), ref.hasPrefix(tagRefPrefix) else {
                continue
            }
            let name = String(ref.dropFirst(tagRefPrefix.count))
            if name.hasSuffix(peeledSuffix) {
                peeledSHAs[String(name.dropLast(peeledSuffix.count))] = sha
            } else {
                if objectSHAs[name] == nil {
                    order.append(name)
                }
                objectSHAs[name] = sha
            }
        }

        return order.compactMap { name in
            guard let objectSHA = objectSHAs[name] else {
                return nil
            }
            return GitRemoteTag(name: name, objectSHA: objectSHA, peeledSHA: peeledSHAs[name])
        }
    }

    /// Parses `git ls-remote <url> refs/heads/<branch>` output into the
    /// branch head SHA, or `nil` when the remote advertised nothing.
    static func parseBranchOutput(_ output: String, branch: String) -> String? {
        let expectedRef = "refs/heads/\(branch)"
        for line in output.split(separator: "\n") {
            guard let (sha, ref) = parseLine(line) else {
                continue
            }
            if ref == expectedRef {
                return sha
            }
        }
        return nil
    }

    private func runLsRemote(url: GitURL, arguments: [String]) async throws -> String {
        let result = try await processRunner.run(
            .path("/usr/bin/git"),
            arguments: Arguments(arguments),
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
            throw Error.lsRemoteFailed(url: url.original, exitCode: code, stderr: stderr)
        case .unhandledException:
            throw Error.lsRemoteFailed(url: url.original, exitCode: -1, stderr: "Unhandled exception")
        default:
            return String(decoding: result.standardOutput, as: UTF8.self)
        }
    }

    private static func parseLine(_ line: Substring) -> (sha: String, ref: String)? {
        let parts = line.split(separator: "\t", maxSplits: 1)
        guard parts.count == 2 else {
            return nil
        }
        let sha = String(parts[0])
        guard sha.count == 40, sha.allSatisfy(\.isHexDigit) else {
            return nil
        }
        return (sha, String(parts[1]))
    }
}

package extension GitTagLister {
    /// Errors that can occur while listing remote refs.
    enum Error: LocalizedError, Equatable {
        /// The `git ls-remote` invocation failed. `stderr` is surfaced
        /// verbatim so SSH/auth problems are diagnosable.
        case lsRemoteFailed(url: String, exitCode: Int32, stderr: String)

        package var errorDescription: String? {
            switch self {
            case let .lsRemoteFailed(url, exitCode, stderr):
                var message = "git ls-remote failed for '\(url)' (exit code: \(exitCode))"
                if !stderr.isEmpty {
                    message += "\n\(stderr)"
                }
                return message
            }
        }
    }
}
