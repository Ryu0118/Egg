import Foundation

struct CombinedError: LocalizedError {
    let errors: [any Error]
    let errorMessageModifier: @Sendable (String) -> String

    init(
        errors: [any Error],
        errorMessageModifier: @Sendable @escaping (String) -> String
    ) {
        self.errors = errors
        self.errorMessageModifier = errorMessageModifier
    }

    var errorDescription: String? {
        errors.compactMap(\.localizedDescription)
            .map(errorMessageModifier)
            .joined(separator: "\n\n")
    }
}
