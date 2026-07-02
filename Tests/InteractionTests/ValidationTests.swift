@testable import Interaction
import Testing

struct ValidationTests {
    @Test func `validation error exposes localized message`() {
        let error = ValidationError("Expected message")

        #expect(error.localizedDescription == "Expected message")
    }

    @Test func `validation rules support boolean compatibility checks`() {
        let rule = NonEmptyRule(message: "Required")

        #expect(rule.validate(input: "value"))
        #expect(!rule.validate(input: ""))
    }

    @Test func `validation rule collections return errors`() {
        let rules: [any ValidationRule] = [
            NonEmptyRule(message: "Required"),
            LengthRule(2 ... 4, message: "Must be short"),
        ]

        #expect(rules.validate(input: "").map(\.message) == ["Required", "Must be short"])
        #expect(rules.validate(input: "abc").isEmpty)
    }
}
