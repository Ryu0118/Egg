import Foundation

/// A `Sendable` JSON value — `[String: Any]` cannot cross an actor boundary,
/// and stringly-typed dictionaries are what led the previous version of
/// `MCPRunner` to reach for `@unchecked Sendable` instead. This makes the
/// actor's request/response API honestly typed.
enum JSONValue {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(any value: Any) {
        switch value {
        case is NSNull:
            self = .null
        case let value as Bool:
            self = .bool(value)
        case let value as any BinaryInteger:
            self = .number(Double(value))
        case let value as Double:
            self = .number(value)
        case let value as String:
            self = .string(value)
        case let value as [Any]:
            self = .array(value.map(JSONValue.init(any:)))
        case let value as [String: Any]:
            self = .object(value.mapValues(JSONValue.init(any:)))
        default:
            self = .null
        }
    }

    /// Foundation representation, for building request payloads with
    /// `JSONSerialization` or comparing against plain Swift literals in tests.
    var anyValue: Any {
        switch self {
        case .null: NSNull()
        case let .bool(value): value
        case let .number(value): value
        case let .string(value): value
        case let .array(values): values.map(\.anyValue)
        case let .object(values): values.mapValues(\.anyValue)
        }
    }

    subscript(key: String) -> JSONValue? {
        guard case let .object(values) = self else { return nil }
        return values[key]
    }

    var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case let .bool(value) = self else { return nil }
        return value
    }

    var arrayValue: [JSONValue]? {
        guard case let .array(values) = self else { return nil }
        return values
    }

    var objectValue: [String: JSONValue]? {
        guard case let .object(values) = self else { return nil }
        return values
    }

    static func decode(_ data: Data) throws -> JSONValue {
        try JSONValue(any: JSONSerialization.jsonObject(with: data))
    }

    static func decode(_ text: String) throws -> JSONValue {
        try decode(Data(text.utf8))
    }
}
