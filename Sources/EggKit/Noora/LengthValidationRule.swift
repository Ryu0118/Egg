import Foundation
import Noora

package struct LengthValidationRule: ValidatableRule {
    package let error: any ValidatableError
    
    private let minLength: Int
    private let maxLength: Int
    
    package init(minLength: Int, maxLength: Int, error: String) {
        self.minLength = minLength
        self.maxLength = maxLength
        self.error = error
    }
    
    package func validate(input: String) -> Bool {
        let length = input.count
        return length >= minLength && length <= maxLength
    }
}

extension LengthValidationRule {
    static let templateName: Self = LengthValidationRule(
        minLength: 1,
        maxLength: 100,
        error: "Template name must be between 1 and 100 characters."
    )
    static let description: Self = LengthValidationRule(
        minLength: 1,
        maxLength: 5000,
        error: "Description must be between 1 and 5000 characters."
    )
}
