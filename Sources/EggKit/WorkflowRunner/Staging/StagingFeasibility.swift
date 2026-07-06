import FileManagerProtocol
import Foundation
import ProcessRunning

/// Resolves whether a directory can be staged, and at what cost — the single
/// decision both entry points into staging need before doing any work.
///
/// Staging clones a directory twice (workspace + reference). A git
/// repository scopes that clone to tracked and non-ignored files; a non-git
/// directory copies everything, unfiltered. Either way the cost is
/// per-file, so a huge directory is refused up front rather than silently
/// grinding for minutes — and a non-git directory needs the same kind of
/// consent a human gives at the interactive prompt, since it copies whatever
/// is there with no `.gitignore` scoping.
///
/// `AgentHatchTransactionRunner.preview()` (the non-interactive agent path)
/// and `EggService.hatchTemplate` (the MCP path, which has no prompt channel
/// at all — reaching one would exit the process mid-request) both resolve
/// through here so the decision can't drift between them. Each caller
/// translates the outcome into its own error type, since the two entry
/// points intentionally speak different vocabularies (`AgentHatchTransactionRunner.Error`
/// for the CLI-facing transaction flow, `EggServiceError` for MCP).
struct StagingFeasibility {
    /// Above this many files, staging stops being interactive-fast and needs
    /// either consent (non-git) or an explicit size override (large git repo).
    static let defaultFileLimit = StagingPreflight.defaultFileLimit

    private let preflight: StagingPreflight

    init(processRunner: some ProcessRunning = ProcessRunner(), fileManager: some FileManagerProtocol = FileManager.default) {
        preflight = StagingPreflight(processRunner: processRunner, fileManager: fileManager)
    }

    /// Every fact needed to decide whether `directory` may be staged and to
    /// write an actionable refusal if not.
    struct Facts {
        let isGitRepository: Bool
        let fileCount: Int
        let isExactCount: Bool
    }

    /// The resolved facts about `directory`, without applying any consent —
    /// callers combine this with their own `allowLargeStaging`/
    /// `allowNonGitStaging` flags via ``Decision``. `countCap` bounds the
    /// non-git enumeration (see ``StagingPreflight/countAllFiles(in:cap:)``);
    /// pass the same limit ``decide(facts:allowLargeStaging:allowNonGitStaging:limit:)``
    /// will apply, so an inexact count is never mistaken for one comfortably
    /// under a caller-configured, non-default limit.
    func facts(for directory: URL, processRunner: some ProcessRunning, countCap: Int = StagingFeasibility.defaultFileLimit) async throws -> Facts {
        if await GitRepositoryChecker(processRunner: processRunner).isGitRepository(directory) {
            let count = try await preflight.countGitCloneableFiles(in: directory)
            return Facts(isGitRepository: true, fileCount: count, isExactCount: true)
        }
        let (count, isExact) = preflight.countAllFiles(in: directory, cap: countCap)
        return Facts(isGitRepository: false, fileCount: count, isExactCount: isExact)
    }

    /// What a caller should do, given the resolved facts and its consent flags.
    enum Decision {
        /// Staging may proceed. `warnings` are non-fatal context to attach to
        /// the result (e.g. "this directory isn't git-tracked").
        case proceed(warnings: [StagingWarning])
        /// `directory` isn't a git repository and `allowNonGitStaging` wasn't
        /// given — the caller needs to ask (a human prompt) or refuse (an
        /// agent/MCP path) naming `fileCount`.
        case nonGitConsentRequired(fileCount: Int, isExact: Bool)
        /// The measured file count exceeds the limit and `allowLargeStaging`
        /// wasn't given.
        case tooLarge(fileCount: Int, limit: Int)
    }

    /// A warning ``Decision/proceed(warnings:)`` can carry — kept type-only
    /// here so this file has no dependency on either caller's warning model;
    /// each caller maps `NonGitStaging` to its own warning type.
    enum StagingWarning {
        case nonGitStaging
    }

    /// Applies `allowLargeStaging`/`allowNonGitStaging` to `facts` and
    /// returns what the caller should do. `limit` must match the `countCap`
    /// passed to ``facts(for:processRunner:countCap:)``.
    func decide(facts: Facts, allowLargeStaging: Bool, allowNonGitStaging: Bool, limit: Int = StagingFeasibility.defaultFileLimit) -> Decision {
        guard facts.isGitRepository else {
            guard allowNonGitStaging else {
                return .nonGitConsentRequired(fileCount: facts.fileCount, isExact: facts.isExactCount)
            }
            guard facts.fileCount <= limit || allowLargeStaging else {
                return .tooLarge(fileCount: facts.fileCount, limit: limit)
            }
            return .proceed(warnings: [.nonGitStaging])
        }

        guard allowLargeStaging || facts.fileCount <= limit else {
            return .tooLarge(fileCount: facts.fileCount, limit: limit)
        }
        return .proceed(warnings: [])
    }
}
