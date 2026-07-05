import Foundation

package extension URL {
    /// Returns the path string with trailing slashes removed.
    ///
    /// This normalizes paths for consistent comparison, since `/path/to/dir`
    /// and `/path/to/dir/` refer to the same location.
    ///
    /// The root path "/" is preserved as-is.
    ///
    /// Example:
    /// ```swift
    /// URL(filePath: "/tmp/work/").normalizedPath   // "/tmp/work"
    /// URL(filePath: "/tmp/work///").normalizedPath // "/tmp/work"
    /// URL(filePath: "/").normalizedPath            // "/"
    /// ```
    var normalizedPath: String {
        // Use resolvingSymlinksInPath() to get the canonical path.
        // This resolves symlinks AND normalizes case on case-insensitive filesystems (macOS APFS).
        var path = resolvingSymlinksInPath().path(percentEncoded: false)

        // resolvingSymlinksInPath() only canonicalizes components that exist
        // on disk: an existing path spelled /private/var/… comes back as
        // /var/…, but a not-yet-created path (e.g. a hatch output directory)
        // keeps its /private prefix. Strip it for the well-known /private
        // symlink roots so both spellings of the same location compare equal.
        for root in ["/private/var", "/private/tmp", "/private/etc"] where path == root || path.hasPrefix(root + "/") {
            path.removeFirst("/private".count)
            break
        }

        guard path != "/" else { return path }

        while path.hasSuffix("/"), path.count > 1 {
            path.removeLast()
        }
        return path
    }

    /// Checks if this URL points to the same path as another URL.
    ///
    /// Comparison is done after normalizing both paths (resolving symlinks,
    /// standardizing representation, and removing trailing slashes).
    ///
    /// - Parameter other: The URL to compare against.
    /// - Returns: `true` if both URLs point to the same path.
    ///
    /// Example:
    /// ```swift
    /// let a = URL(filePath: "/tmp/work")
    /// let b = URL(filePath: "/tmp/work/")
    /// a.isSamePath(to: b) // true
    ///
    /// let c = URL(filePath: "/tmp/./work")
    /// a.isSamePath(to: c) // true
    /// ```
    func isSamePath(to other: URL) -> Bool {
        normalizedPath == other.normalizedPath
    }
}
