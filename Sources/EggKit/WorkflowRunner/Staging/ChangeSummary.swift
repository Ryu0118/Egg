import Foundation
import Path

/// Summary of changes to be applied from staging to working directory.
struct ChangeSummary: Equatable, Sendable {
    let added: [RelativePath]
    let modified: [RelativePath]
    let deleted: [RelativePath]

    var isEmpty: Bool {
        added.isEmpty && modified.isEmpty && deleted.isEmpty
    }

    /// Total number of changes.
    var totalCount: Int {
        added.count + modified.count + deleted.count
    }

    /// All paths that have any kind of change.
    var allPaths: [RelativePath] {
        added + modified + deleted
    }
}

extension ChangeSummary {
    static var none: Self {
        ChangeSummary(added: [], modified: [], deleted: [])
    }
}
