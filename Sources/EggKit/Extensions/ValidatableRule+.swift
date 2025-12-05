import Noora

extension [any ValidatableRule] {
    func validate(input: String) -> [any ValidatableError] {
        compactMap { rule -> (any ValidatableError)? in
            if !rule.validate(input: input) {
                return rule.error
            }
            return nil
        }
    }
}
