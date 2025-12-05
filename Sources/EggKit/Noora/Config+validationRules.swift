import Foundation
import Noora

extension Config {
    static var templateNameValidationRules: [any ValidatableRule] {
        [
            NonEmptyValidationRule(error: "Project name cannot be empty."),
            DirectoryNameValidationRule(error: "Invalid directory name. Cannot contain '/' or start with whitespace."),
            LengthValidationRule.templateName
        ]
    }

    static var descriptionValidationRules: [any ValidatableRule] {
        [
            NonEmptyValidationRule(error: "Description cannot be empty."),
            LengthValidationRule.description
        ]
    }
}
