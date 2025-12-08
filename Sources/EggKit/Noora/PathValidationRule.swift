import Foundation
import Noora
import Path

package struct PathValidationRule: ValidatableRule {
    package let error: any ValidatableError
    private let workingDirectory: AbsolutePath
    private let homeDirectory: AbsolutePath

    package init(workingDirectory: AbsolutePath, homeDirectory: AbsolutePath, error: String) {
        self.workingDirectory = workingDirectory
        self.homeDirectory = homeDirectory
        self.error = error
    }

    package func validate(input: String) -> Bool {
        guard !input.isEmpty else { return false }

        // Try to resolve the path
        do {
            let _ = try resolveToAbsolutePath(input)
            return true
        } catch {
            return false
        }
    }

    package func resolveToAbsolutePath(_ input: String) throws -> AbsolutePath {
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
}
