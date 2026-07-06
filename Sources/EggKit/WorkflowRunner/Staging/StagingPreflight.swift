import FileManagerProtocol
import Foundation
import ProcessRunning

/// Measures how many files a staging clone of a directory would copy, so
/// callers can warn or refuse *before* paying the cost.
///
/// Staging clones a directory twice (work + reference). Each file is an APFS
/// copy-on-write clone, so the cost is not bytes but *file count* — one
/// syscall and directory bookkeeping per file — and for a large repository
/// (or a non-git directory, where the clone falls back to copying
/// everything) that adds up to minutes before the first byte of template
/// output exists. The previous guard was a data-blind prompt that fired the
/// same words for ten files or ten million.
struct StagingPreflight {
    /// Above this many files, staging stops being interactive-fast and the
    /// guards kick in: agent flows refuse (with escape hatches named in the
    /// error), human flows get a prompt with the real number.
    static let defaultFileLimit = 20000

    private let processRunner: any ProcessRunning
    private let fileManager: any FileManagerProtocol

    init(
        processRunner: some ProcessRunning = ProcessRunner(),
        fileManager: some FileManagerProtocol = FileManager.default,
    ) {
        self.processRunner = processRunner
        self.fileManager = fileManager
    }

    /// Exact count of the files a git-aware staging clone would copy:
    /// tracked files plus untracked files that aren't gitignored — the same
    /// `git ls-files` enumeration the cloner itself performs.
    ///
    /// - Precondition: `directory` is a git repository.
    func countGitCloneableFiles(in directory: URL) async throws -> Int {
        try await GitTrackedDirectoryCloner(
            processRunner: processRunner,
            fileManager: fileManager,
        ).cloneableFiles(in: directory).count
    }

    /// File count for a non-git directory, where the staging clone falls
    /// back to copying *everything*. Counting everything is itself expensive
    /// on a huge tree, so enumeration stops at `cap + 1`: an inexact result
    /// (`isExact == false`) means "more than `cap`".
    func countAllFiles(in directory: URL, cap: Int = StagingPreflight.defaultFileLimit) -> (count: Int, isExact: Bool) {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
        ) else {
            return (0, true)
        }

        var count = 0
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                continue
            }
            count += 1
            if count > cap {
                return (count, false)
            }
        }
        return (count, true)
    }
}
