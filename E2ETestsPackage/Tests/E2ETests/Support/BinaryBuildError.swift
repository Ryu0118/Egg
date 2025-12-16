import Foundation

/// Errors that can occur during binary building
enum BinaryBuildError: Error, LocalizedError {
    case buildFailed(exitCode: Int32, output: String)
    case binaryNotFound(path: String)

    var errorDescription: String? {
        switch self {
        case let .buildFailed(exitCode, output):
            "Build failed with exit code \(exitCode): \(output)"
        case let .binaryNotFound(path):
            "Binary not found at path: \(path)"
        }
    }
}
