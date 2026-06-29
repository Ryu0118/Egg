import Foundation

package enum PathResolver {
    package static func resolveToAbsoluteURL(
        _ input: String,
        workingDirectory: URL,
        homeDirectory: URL,
    ) throws -> URL {
        // Trim leading/trailing whitespace (trailing spaces are usually typos)
        let trimmedInput = input.trimmingCharacters(in: .whitespaces)

        // Handle tilde expansion
        let expandedValue = if trimmedInput.hasPrefix("~/") {
            homeDirectory.path(percentEncoded: false) + String(trimmedInput.dropFirst(1))
        } else if trimmedInput == "~" {
            homeDirectory.path(percentEncoded: false)
        } else {
            trimmedInput
        }

        // Try to resolve as absolute path first
        if expandedValue.hasPrefix("/") {
            return URL(filePath: expandedValue).standardizedFileURL
        }

        // Otherwise, resolve relative to the provided working directory.
        // Using `appending(path:)` preserves directory semantics (e.g., "." stays within the working directory)
        // while still allowing standardization to collapse ".." segments safely.
        return workingDirectory
            .appending(path: expandedValue)
            .standardizedFileURL
    }
}

enum PathResolutionError: LocalizedError {
    case cannotResolve(String)

    var errorDescription: String? {
        switch self {
        case let .cannotResolve(path):
            "Cannot resolve path: '\(path)'"
        }
    }
}
