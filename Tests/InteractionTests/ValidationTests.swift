@testable import Interaction
import Testing

struct ValidationTests {
    @Test func `validation error exposes localized message`() {
        let error = ValidationError("Expected message")

        #expect(error.localizedDescription == "Expected message")
    }

    @Test func `validation rules return nil for valid input`() {
        let rule = NonEmptyRule(message: "Required")

        #expect(rule.validate("value") == nil)
        #expect(rule.validate("")?.message == "Required")
    }

    @Test func `validation rule collections return errors`() {
        struct ShortRule: PredicateValidationRule {
            let error = ValidationError("Must be short")

            func validate(input: String) -> Bool {
                input.count <= 4
            }
        }

        let rules: [any ValidationRule] = [NonEmptyRule(message: "Required"), ShortRule()]

        #expect(rules.validate("").map(\.message) == ["Required"])
        #expect(rules.validate("abcdefgh").map(\.message) == ["Must be short"])
        #expect(rules.validate("abc").isEmpty)
    }

    @Test func `predicate validation rules bridge to validation errors`() {
        struct EvenLengthRule: PredicateValidationRule {
            let error = ValidationError("Must have even length")

            func validate(input: String) -> Bool {
                input.count.isMultiple(of: 2)
            }
        }

        let rule = EvenLengthRule()

        #expect(rule.validate("ab") == nil)
        #expect(rule.validate("abc") == rule.error)
    }
}
