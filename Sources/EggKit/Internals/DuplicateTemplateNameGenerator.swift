import Foundation

/// Namespace for template name generation utilities
package enum DuplicateTemplateNameGenerator {
    /// Generates a default template name by appending the smallest available number
    /// to the base name, ensuring uniqueness within the specified location.
    static func generateDefaultName(
        baseName: String,
        sourceLocation: TemplateLocationType,
        templatesFinder: TemplatesFinder,
        emitValidationErrorLog: Bool,
    ) async -> String {
        // Get all templates from the same location as source
        let allTemplates = try? await templatesFinder.list(
            for: sourceLocation,
            emitValidationErrorLog: emitValidationErrorLog,
        )
        let existingNames = Set(allTemplates?.map(\.config.name) ?? [])

        // Find the smallest available number
        var number = 1
        while true {
            let candidateName = "\(baseName) (\(number))"
            if !existingNames.contains(candidateName) {
                return candidateName
            }
            number += 1
        }
    }
}
