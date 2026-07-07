import Foundation
import Interaction

extension Config {
    static var templateNameValidationRules: [ValidationRule] {
        [
            .nonEmpty(message: "Project name cannot be empty."),
            .directoryName(error: "Invalid directory name. Cannot contain '/' or start with whitespace."),
            .templateNameLength,
        ]
    }

    static var descriptionValidationRules: [ValidationRule] {
        [
            .nonEmpty(message: "Description cannot be empty."),
            .descriptionLength,
        ]
    }
}
