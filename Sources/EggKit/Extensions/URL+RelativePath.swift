import Foundation

package extension URL {
    /// Returns a relative path string from the base URL to this URL.
    ///
    /// If this URL is not under the base URL, returns the absolute path.
    ///
    /// - Parameter base: The base URL to compute the relative path from.
    /// - Returns: The relative path string (without leading slash), or "." if paths are equal.
    ///
    /// Example:
    /// ```swift
    /// let project = URL(filePath: "/Users/user/Projects/MyApp")
    /// let working = URL(filePath: "/Users/user/Projects")
    /// project.relativePath(from: working) // "MyApp"
    ///
    /// let same = URL(filePath: "/Users/user/Projects")
    /// same.relativePath(from: working) // "."
    /// ```
    func relativePath(from base: URL) -> String {
        let targetPath = self.path(percentEncoded: false)
        let basePath = base.path(percentEncoded: false)

        // Normalize paths by removing trailing slashes for comparison
        let normalizedTarget = targetPath.hasSuffix("/") ? String(targetPath.dropLast()) : targetPath
        let normalizedBase = basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath

        // Same path
        if normalizedTarget == normalizedBase {
            return "."
        }

        // Check if target is under base
        let basePrefix = normalizedBase + "/"
        if normalizedTarget.hasPrefix(basePrefix) {
            let relative = String(normalizedTarget.dropFirst(basePrefix.count))
            return relative.isEmpty ? "." : relative
        }

        // Not under base, return absolute path
        return targetPath
    }

    /// Creates a new URL by appending a relative path string.
    ///
    /// This is a convenience wrapper around `appending(path:)` that accepts
    /// a relative path string directly.
    ///
    /// - Parameter relativePath: The relative path to append.
    /// - Returns: A new URL with the path appended.
    func appendingRelativePath(_ relativePath: String) -> URL {
        appending(path: relativePath)
    }

    /// Returns true if this URL is located under the given base URL.
    ///
    /// - Parameter base: The base URL to check against.
    /// - Returns: True if this URL's path starts with the base URL's path.
    func isUnder(_ base: URL) -> Bool {
        let targetPath = self.path(percentEncoded: false)
        let basePath = base.path(percentEncoded: false)

        let normalizedTarget = targetPath.hasSuffix("/") ? String(targetPath.dropLast()) : targetPath
        let normalizedBase = basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath

        return normalizedTarget == normalizedBase || normalizedTarget.hasPrefix(normalizedBase + "/")
    }
}
