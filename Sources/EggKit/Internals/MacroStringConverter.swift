import Foundation

/// Converts ResolvedMacro values to string representations.
///
/// Provides two conversion modes:
/// - **Shell mode**: For use in shell scripts (no quoting)
/// - **JavaScript mode**: For use in JS evaluation (type-aware quoting)
enum MacroStringConverter {
    /// Converts a macro value to a string for shell scripts (no quoting).
    ///
    /// Conversion rules:
    /// - `.string(s)` → `s`
    /// - `.boolean(b)` → `"true"` or `"false"`
    /// - `.choice(c)` → `c`
    /// - `.choices(c)` → Comma-separated string (e.g., `"iOS, macOS"`)
    /// - `.array(a, format)` → Formatted string via JavaScript expression
    /// - `.path(p)` → Resolved absolute path relative to working directory
    ///
    /// - Throws: `ArrayFormatError` when array format evaluation fails
    static func toShellString(
        _ value: ResolvedMacro.Value,
        workingDirectory: URL,
        homeDirectory: URL
    ) throws -> String {
        switch value {
        case let .string(s):
            return s
        case let .boolean(b):
            return b ? "true" : "false"
        case let .choice(c):
            return c
        case let .choices(c):
            return c.joined(separator: ", ")
        case let .array(elements, format):
            return try ArrayFormatEvaluator().evaluate(format: format, values: elements)
        case let .path(p):
            // Resolve path relative to working directory to ensure absolute path
            let absolutePath = resolvePath(p, workingDirectory: workingDirectory, homeDirectory: homeDirectory)
            return normalizeTrailingSlash(absolutePath.path(percentEncoded: false))
        }
    }

    /// Converts a macro value to a JavaScript literal with type-aware quoting.
    ///
    /// Conversion rules for JavaScript evaluation:
    /// - `.string(s)` → `"s"` (quoted)
    /// - `.boolean(b)` → `true` or `false` (unquoted)
    /// - `.choice(c)` → `"c"` (quoted)
    /// - `.choices(c)` → `["item1", "item2"]` (JSON array)
    /// - `.array(a)` → `["item1", "item2"]` (JSON array)
    /// - `.path(p)` → `"path"` (quoted, resolved absolute path)
    static func toJavaScriptLiteral(
        _ value: ResolvedMacro.Value,
        workingDirectory: URL,
        homeDirectory: URL
    ) -> String {
        switch value {
        case let .string(s):
            return escapeAndQuote(s)
        case let .boolean(b):
            return b ? "true" : "false"
        case let .choice(c):
            return escapeAndQuote(c)
        case let .choices(c):
            // Convert to JSON array: ["item1", "item2"]
            let quotedItems = c.map { escapeAndQuote($0) }
            return "[" + quotedItems.joined(separator: ", ") + "]"
        case let .array(elements, _):
            // Convert to JSON array: ["item1", "item2"]
            let quotedItems = elements.map { escapeAndQuote($0) }
            return "[" + quotedItems.joined(separator: ", ") + "]"
        case let .path(p):
            // Resolve path relative to working directory to ensure absolute path
            let absolutePath = resolvePath(p, workingDirectory: workingDirectory, homeDirectory: homeDirectory)
            return escapeAndQuote(normalizeTrailingSlash(absolutePath.path(percentEncoded: false)))
        }
    }

    /// Escapes and quotes a string for JavaScript evaluation.
    ///
    /// Escapes:
    /// - Backslashes: \ → \\
    /// - Double quotes: " → \"
    /// - Newlines: \n → \\n
    /// - Carriage returns: \r → \\r
    /// - Tabs: \t → \\t
    static func escapeAndQuote(_ string: String) -> String {
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    /// Normalizes a path by removing trailing slashes.
    ///
    /// This prevents issues where paths like `/path/to/dir/` cause double slashes
    /// when concatenated with other path components (e.g., `/path/to/dir//file`).
    ///
    /// - Parameter path: The path string to normalize
    /// - Returns: The path with trailing slashes removed (except for root "/")
    private static func normalizeTrailingSlash(_ path: String) -> String {
        // Don't remove the slash from root path "/"
        guard path != "/" else { return path }

        var result = path
        while result.hasSuffix("/") && result.count > 1 {
            result.removeLast()
        }
        return result
    }

    /// Resolves a path URL to an absolute path relative to the working directory.
    ///
    /// If the URL is already absolute, it is returned as-is (standardized).
    /// If the URL is relative, it is resolved relative to the working directory.
    ///
    /// - Parameters:
    ///   - path: The path URL to resolve
    ///   - workingDirectory: The working directory to resolve relative paths against
    ///   - homeDirectory: The home directory for tilde expansion
    /// - Returns: An absolute, standardized URL
    private static func resolvePath(_ path: URL, workingDirectory: URL, homeDirectory: URL) -> URL {
        // Check if URL is already absolute
        if path.isFileURL && path.path(percentEncoded: false).hasPrefix("/") {
            return path.standardizedFileURL
        }

        // If relative, resolve against working directory
        // Convert URL to string first to handle relative paths properly
        let pathString = path.path(percentEncoded: false)
        
        // Use resolveToAbsoluteURL to handle tilde expansion and relative path resolution
        do {
            return try resolveToAbsoluteURL(pathString, workingDirectory: workingDirectory, homeDirectory: homeDirectory)
        } catch {
            // Fallback: if resolution fails, try appending to working directory
            return workingDirectory.appending(path: pathString).standardizedFileURL
        }
    }
}
