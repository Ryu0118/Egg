import Foundation
import Interaction

extension Config {
    static var templateNameValidationRules: [any ValidationRule] {
        [
            NonEmptyRule(message: "Project name cannot be empty."),
            DirectoryNameValidationRule(error: "Invalid directory name. Cannot contain '/' or start with whitespace."),
            LengthValidationRule.templateName,
        ]
    }

    static var descriptionValidationRules: [any ValidationRule] {
        [
            NonEmptyRule(message: "Description cannot be empty."),
            LengthValidationRule.description,
        ]
    }
}
