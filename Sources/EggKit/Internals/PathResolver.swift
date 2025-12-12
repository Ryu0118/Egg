import Foundation

package func resolveToAbsoluteURL(
    _ input: String,
    workingDirectory: URL,
    homeDirectory: URL
) throws -> URL {
    // Handle tilde expansion
    let expandedValue = if input.hasPrefix("~/") {
        homeDirectory.path(percentEncoded: false) + String(input.dropFirst(1))
    } else if input == "~" {
        homeDirectory.path(percentEncoded: false)
    } else {
        input
    }

    // Try to resolve as absolute path first
    if expandedValue.hasPrefix("/") {
        return URL(filePath: expandedValue)
    }

    // Otherwise, resolve as relative path from working directory
    return URL(filePath: expandedValue, relativeTo: workingDirectory)
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
