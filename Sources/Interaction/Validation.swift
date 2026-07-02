import Foundation

public protocol ValidationRule: Sendable {
    func validate(_ input: String) -> ValidationError?
}

public struct ValidationError: LocalizedError, Equatable, Sendable {
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

public struct NonEmptyRule: ValidationRule {
    private let message: String

    public init(message: String = "Input cannot be empty.") {
        self.message = message
    }

    public func validate(_ input: String) -> ValidationError? {
        input.isEmpty ? ValidationError(message) : nil
    }
}

public struct LengthRule: ValidationRule {
    private let range: ClosedRange<Int>
    private let message: String

    public init(_ range: ClosedRange<Int>, message: String) {
        self.range = range
        self.message = message
    }

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
