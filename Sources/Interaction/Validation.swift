import Foundation

/// Validates a text prompt answer.
public protocol ValidationRule: Sendable {
    /// Returns a validation error when the input is invalid.
    func validate(_ input: String) -> ValidationError?
}

/// A user-facing validation failure.
public struct ValidationError: LocalizedError, Equatable, Sendable {
    /// The validation message to display.
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}

public extension ValidationRule {
    func isValid(_ input: String) -> Bool {
        validate(input) == nil
    }

    func validate(input: String) -> Bool {
        isValid(input)
    }
}

/// Requires non-empty text input.
public struct NonEmptyRule: ValidationRule {
    private let message: String

    public init(message: String = "Input cannot be empty.") {
        self.message = message
    }

    /// Validates that the input is not empty.
    public func validate(_ input: String) -> ValidationError? {
        input.isEmpty ? ValidationError(message) : nil
    }
}

/// Requires input length to fall within a closed range.
public struct LengthRule: ValidationRule {
    private let range: ClosedRange<Int>
    private let message: String

    public init(_ range: ClosedRange<Int>, message: String) {
        self.range = range
        self.message = message
    }

    /// Validates that the input length is in the configured range.
    public func validate(_ input: String) -> ValidationError? {
        range.contains(input.count) ? nil : ValidationError(message)
    }
}

public extension Collection<any ValidationRule> {
    func validate(_ input: String) -> [ValidationError] {
        compactMap { $0.validate(input) }
    }

    func validate(input: String) -> [ValidationError] {
        validate(input)
    }
}
