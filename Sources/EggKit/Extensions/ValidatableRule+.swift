import Interaction

extension [any ValidationRule] {
    func validationErrors(for input: String) -> [ValidationError] {
        validate(input)
    }
}
