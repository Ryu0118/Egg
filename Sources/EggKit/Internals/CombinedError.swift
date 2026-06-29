import Foundation

struct CombinedError: LocalizedError {
    let errors: [any Error]
    let errorMessageModifier: @Sendable (String) -> String

    var errorDescription: String? {
        errors.compactMap(\.localizedDescription)
            .map(errorMessageModifier)
            .joined(separator: "\n")
    }
}
