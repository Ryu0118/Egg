import Foundation

/// Errors occurring during array format evaluation.
enum ArrayFormatError: LocalizedError, Equatable {
    /// JavaScript evaluation returned null or undefined.
    case evaluationFailed(format: String)

    /// JavaScript evaluation returned a non-string value.
    case nonStringResult(format: String, actualType: String)

    var errorDescription: String? {
        switch self {
        case let .evaluationFailed(format):
            "Array format evaluation failed: '\(format)' returned null or undefined"
        case let .nonStringResult(format, actualType):
            "Array format must return a string, but '\(format)' returned \(actualType)"
        }
    }
}
