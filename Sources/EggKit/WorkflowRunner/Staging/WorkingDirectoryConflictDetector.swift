import FileManagerProtocol
import Foundation

/// Detects whether the real working directory drifted from the staged baseline
/// for the specific files a transaction is about to touch.
///
/// This answers a different question from ``GitStagingChangeDetector``: not
/// "what did the workflow change" but "did the user edit any of the files we
/// are about to apply, since the preview was taken." It compares only the
/// transaction's own paths, so there is no directory walk and no need to reason
/// about ignored artifacts.
struct WorkingDirectoryConflictDetector {
    private let fileManager: any FileManagerProtocol

    init(fileManager: some FileManagerProtocol) {
        self.fileManager = fileManager
    }

    /// Returns the subset of `paths` whose contents in `workingRoot` differ from
    /// the captured `referenceRoot` snapshot.
    func conflictingPaths(
        referenceRoot: URL,
        workingRoot: URL,
        paths: [String],
    ) throws -> [String] {
        try paths.filter { path in
            let reference = referenceRoot.appending(path: path)
            let working = workingRoot.appending(path: path)
            return try contents(of: reference) != contents(of: working)
        }
        .sorted()
    }

    private func contents(of url: URL) throws -> Data? {
        guard fileManager.exists(url), !fileManager.isDirectory(at: url) else {
            return nil
        }
        return try fileManager.readFile(at: url)
    }
}
