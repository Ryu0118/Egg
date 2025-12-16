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
        let normalizedTarget = normalizedPath
        let normalizedBase = base.normalizedPath

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
        return normalizedTarget
    }

    /// Creates a new URL by appending a relative path string.
    ///
    /// This is a convenience wrapper around `appending(path:)` that accepts
    /// a relative path string directly.
    ///
    /// - Parameter relativePath: The relative path to append.
    /// - Returns: A new URL with the path appended.
    func appendingRelativePath(_ relativePath: String) -> URL {
        guard !relativePath.isEmpty, relativePath != "." else {
            return self
        }
        return appending(path: relativePath)
    }

    /// Returns true if this URL is located under the given base URL.
    ///
    /// - Parameter base: The base URL to check against.
    /// - Returns: True if this URL's path starts with the base URL's path.
    func isUnder(_ base: URL) -> Bool {
        let normalizedTarget = normalizedPath
        let normalizedBase = base.normalizedPath

        return normalizedTarget == normalizedBase || normalizedTarget.hasPrefix(normalizedBase + "/")
    }

    /// Returns a relative path string from the base URL, throwing if not within base.
    ///
    /// Unlike `relativePath(from:)`, this method throws an error if this URL
    /// is not located under the base URL.
    ///
    /// - Parameter base: The base URL to compute the relative path from.
    /// - Returns: The relative path string (without leading slash), or "." if paths are equal.
    /// - Throws: `RelativePathError.notWithinBase` if this URL is not under the base.
    ///
    /// Example:
    /// ```swift
    /// let project = URL(filePath: "/Users/user/Projects/MyApp")
    /// let working = URL(filePath: "/Users/user/Projects")
    /// try project.relativePathThrowing(from: working) // "MyApp"
    ///
    /// let outside = URL(filePath: "/tmp/other")
    /// try outside.relativePathThrowing(from: working) // throws RelativePathError.notWithinBase
    /// ```
    func relativePathThrowing(from base: URL) throws -> String {
        // Same path
        if isSamePath(to: base) {
            return "."
        }

        let normalizedTarget = normalizedPath
        let normalizedBase = base.normalizedPath

        // Check if target is under base
        let basePrefix = normalizedBase + "/"
        guard normalizedTarget.hasPrefix(basePrefix) else {
            throw RelativePathError.notWithinBase(path: normalizedTarget, base: normalizedBase)
        }

        let relative = String(normalizedTarget.dropFirst(basePrefix.count))
        return relative.isEmpty ? "." : relative
    }
}

/// Errors that can occur during relative path computation.
enum RelativePathError: LocalizedError {
    /// The path is not within the specified base directory.
    case notWithinBase(path: String, base: String)

    var errorDescription: String? {
        switch self {
        case let .notWithinBase(path, base):
            "Path '\(path)' is not within base '\(base)'"
        }
    }
}
