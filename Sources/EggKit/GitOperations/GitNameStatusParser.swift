import Foundation

/// Parses the output of `git diff --name-status -z` into a `ChangeSummary`.
struct GitNameStatusParser {
    let workingRoot: URL
    let workspaceRoot: URL

    func parse(components: [Substring]) -> ChangeSummary {
        var index = 0
        var added: [String] = []
        var modified: [String] = []
        var deleted: [String] = []

        while index < components.count {
            let statusLine = String(components[index])
            index += 1
            guard let status = statusLine.first else { continue }

            switch status {
            case "A":
                if let path = nextPath(components: components, index: &index) {
                    added.append(path)
                }
            case "M":
                if let path = nextPath(components: components, index: &index) {
                    modified.append(path)
                }
            case "D":
                if let path = nextPath(components: components, index: &index) {
                    deleted.append(path)
                }
            case "R":
                if let oldPath = nextPath(components: components, index: &index) {
                    deleted.append(oldPath)
                }
                if let newPath = nextPath(components: components, index: &index) {
                    added.append(newPath)
                }
            case "C":
                // Copy has two paths (source, destination) - skip both
                _ = nextPath(components: components, index: &index)
                _ = nextPath(components: components, index: &index)
            default:
                if index < components.count {
                    index += 1
                }
            }
        }

        return ChangeSummary(
            added: added.sorted { $0 < $1 },
            modified: modified.sorted { $0 < $1 },
            deleted: deleted.sorted { $0 < $1 },
        )
    }

    private func nextPath(components: [Substring], index: inout Int) -> String? {
        guard index < components.count else { return nil }
        let rawPath = String(components[index])
        index += 1
        return extractRelativePath(rawPath)
    }

    private func extractRelativePath(_ rawPath: String) -> String? {
        if let relative = rawPath.removingPrefix(workingRoot.path(percentEncoded: false) + "/") {
            return relative
        }

        if let relative = rawPath.removingPrefix(workspaceRoot.path(percentEncoded: false) + "/") {
            return relative
        }

        return rawPath
    }
}

private extension String {
    func removingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}
