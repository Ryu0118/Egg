import Foundation
import Path

package func resolveToAbsolutePath(
    _ input: String,
    workingDirectory: AbsolutePath,
    homeDirectory: AbsolutePath
) throws -> AbsolutePath {
    // Handle tilde expansion
    let expandedValue = if input.hasPrefix("~/") {
        homeDirectory.pathString + String(input.dropFirst(1))
    } else if input == "~" {
        homeDirectory.pathString
    } else {
        input
    }

    // Try to resolve as absolute path first
    if let absolutePath = try? AbsolutePath(validating: expandedValue) {
        return absolutePath
    }

    // Otherwise, resolve as relative path from working directory
    if let absolutePath = try? AbsolutePath(validating: expandedValue, relativeTo: workingDirectory) {
        return absolutePath
    }

    throw PathResolutionError.cannotResolve(input)
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
