import FileManagerProtocol
import Foundation
import ProcessRunning
import Subprocess

#if canImport(System)
    import System
#else
    import SystemPackage
#endif

/// Detects changes a lifecycle workflow made inside a staging clone using git.
///
/// The staging clone is turned into a throwaway git repository: a baseline
/// commit captures the cloned tree, the workflow runs, and `git diff` against
/// that baseline reports exactly what changed.
///
/// Because the project's own `.gitignore` is a tracked file it is present in
/// the clone, so artifacts a script generates (for example `node_modules` from
/// `npm install` or `.build` from `swift build`) are suppressed by the same
/// rules git already applies to the real repository. There is no hardcoded
/// list of excluded directories: the single source of truth for what counts as
/// a change is git itself.
///
/// Only `.egg/` is excluded structurally, via the staging repo's
/// `.git/info/exclude`, so egg's own transaction/rollback bookkeeping never
/// shows up as a change.
struct GitStagingChangeDetector {
    private let processRunner: any ProcessRunning
    private let fileManager: any FileManagerProtocol

    /// Pathspecs forwarded to git so callers can widen or narrow the change set.
    ///
    /// `include` entries are force-added even when ignored; `exclude` entries
    /// become `:(exclude)` pathspecs. Both are applied to the baseline and to
    /// the diff so the snapshot and the detection stay consistent.
    struct PathFilter {
        var include: [String]
        var exclude: [String]

        init(include: [String] = [], exclude: [String] = []) {
            self.include = include
            self.exclude = exclude
        }

        var isEmpty: Bool {
            include.isEmpty && exclude.isEmpty
        }
    }

    init(
        processRunner: some ProcessRunning = ProcessRunner(),
        fileManager: some FileManagerProtocol,
    ) {
        self.processRunner = processRunner
        self.fileManager = fileManager
    }

    /// Records a baseline commit for the cloned tree before the workflow runs.
    ///
    /// Call this on the freshly cloned staging workspace, then run the
    /// lifecycle workflow, then call ``changes(in:filter:)`` to see what moved.
    func recordBaseline(in workspace: URL, filter: PathFilter = PathFilter()) async throws {
        try await git(["init", "-q"], in: workspace)
        try writeStructuralExcludes(in: workspace)
        try await stageAll(in: workspace, filter: filter)
        try await git(
            ["commit", "--quiet", "--allow-empty", "--no-verify", "-m", "egg-staging-baseline"],
            in: workspace,
        )
    }

    /// Returns what the workflow changed since ``recordBaseline(in:filter:)``.
    func changes(in workspace: URL, filter: PathFilter = PathFilter()) async throws -> ChangeSummary {
        // A lifecycle script may have cloned something (a dependency checkout,
        // for example) since the baseline — refresh the structural excludes so
        // the new nested repository can't fatal the stage below.
        try writeStructuralExcludes(in: workspace)
        try await stageAll(in: workspace, filter: filter)

        var arguments = ["diff", "--cached", "--name-status", "-z", "--no-renames", "HEAD"]
        arguments.append(contentsOf: pathspec(for: filter))
        let output = try await git(arguments, in: workspace)
        let components = output.split(separator: "\0", omittingEmptySubsequences: true)
        let parser = GitNameStatusParser(workingRoot: workspace, workspaceRoot: workspace)
        return parser.parse(components: components)
    }

    /// Returns the unified diff for a single changed path, relative to the baseline.
    ///
    /// Used to enrich a preview when the caller asks for `--diff`: the staged
    /// patch shows exactly what content the workflow would add or modify.
    func unifiedDiff(for path: String, in workspace: URL) async throws -> String {
        try await git(
            ["diff", "--cached", "-p", "--no-renames", "HEAD", "--", path],
            in: workspace,
        )
    }

    private func stageAll(in workspace: URL, filter: PathFilter) async throws {
        var arguments = ["add", "-A"]
        if !filter.exclude.isEmpty {
            arguments.append("--")
            arguments.append(".")
            arguments.append(contentsOf: filter.exclude.map { ":(exclude)\($0)" })
        }
        try await git(arguments, in: workspace)

        // Includes must be force-added so a normally-ignored path participates.
        // Only existing paths are force-added: at baseline time a script may not
        // have generated them yet, and `git add -f` fatals on a missing pathspec.
        let existingIncludes = filter.include.filter { relativePath in
            fileManager.exists(workspace.appending(path: relativePath))
        }
        if !existingIncludes.isEmpty {
            try await git(["add", "-f", "--"] + existingIncludes, in: workspace)
        }
    }

    private func pathspec(for filter: PathFilter) -> [String] {
        guard !filter.exclude.isEmpty else { return [] }
        return ["--"] + ["."] + filter.exclude.map { ":(exclude)\($0)" }
    }

    private func writeStructuralExcludes(in workspace: URL) throws {
        let excludeFile = workspace.appending(path: ".git/info/exclude")
        let lines = ["\(EggBookkeeping.directoryName)/"] + nestedRepositoryPaths(in: workspace).map { "/\($0)/" }
        try fileManager.writeText(lines.joined(separator: "\n") + "\n", at: excludeFile)
    }

    /// Directories under `workspace` that are themselves git repositories
    /// (holding a `.git` directory or gitfile), relative to the workspace.
    ///
    /// The parent repository treats a nested repository as an opaque gitlink,
    /// and `git add -A` fatals outright on one with no commit checked out
    /// ("does not have a commit checked out") — a vendored checkout in the
    /// working directory or a dependency a lifecycle script cloned are both
    /// everyday cases. Excluding them structurally keeps the staging repo's
    /// view identical to how git itself scopes the parent repository.
    private func nestedRepositoryPaths(in workspace: URL) -> [String] {
        guard let enumerator = fileManager.enumerator(
            at: workspace,
            includingPropertiesForKeys: nil,
        ) else { return [] }

        var paths: [String] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent == ".git" else { continue }
            let parent = url.deletingLastPathComponent()
            // The workspace root's own .git is the staging repo itself.
            guard !parent.isSamePath(to: workspace) else { continue }
            paths.append(parent.relativePath(from: workspace))
            enumerator.skipDescendants()
        }
        return paths.sorted()
    }

    @discardableResult
    private func git(_ arguments: [String], in workspace: URL) async throws -> String {
        // Identity flags are passed per-invocation so the throwaway repo never
        // depends on the user's global git config (which may be unset in CI).
        let identityFlags = [
            "-c", "user.name=egg",
            "-c", "user.email=egg@localhost",
            "-c", "commit.gpgsign=false",
        ]
        let result = try await processRunner.run(
            .path("/usr/bin/git"),
            arguments: Arguments(identityFlags + arguments),
            environment: .inherit,
            workingDirectory: FilePath(workspace.path),
            platformOptions: PlatformOptions(),
            input: .none,
            output: .bytes(limit: 50 * 1024 * 1024),
            error: .bytes(limit: 8 * 1024),
        )

        switch result.terminationStatus {
        case let .exited(code):
            guard code == 0 else {
                let message = String(decoding: result.standardError, as: UTF8.self)
                throw Error.gitFailed(arguments: arguments, exitCode: code, message: message)
            }
        case .unhandledException:
            throw Error.gitCrashed(arguments: arguments)
        }

        return String(decoding: result.standardOutput, as: UTF8.self)
    }
}

extension GitStagingChangeDetector {
    /// Errors raised while running git inside the staging workspace.
    enum Error: Swift.Error, LocalizedError {
        case gitFailed(arguments: [String], exitCode: Int32, message: String)
        case gitCrashed(arguments: [String])

        var errorDescription: String? {
            switch self {
            case let .gitFailed(arguments, exitCode, message):
                "git \(arguments.joined(separator: " ")) failed (exit \(exitCode)): \(message)"
            case let .gitCrashed(arguments):
                "git \(arguments.joined(separator: " ")) crashed unexpectedly"
            }
        }
    }
}
