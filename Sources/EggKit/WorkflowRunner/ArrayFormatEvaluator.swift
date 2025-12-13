import Foundation
import JavaScriptCore

/// Evaluates array format expressions using JavaScriptCore.
struct ArrayFormatEvaluator: ArrayFormatEvaluating {
    /// Default format expression when none is specified.
    private static let defaultFormat: String = #"$elements.join(", ")"#

    private let jsEvaluator: JSEvaluator

    init(jsEvaluator: JSEvaluator = JSEvaluator()) {
        self.jsEvaluator = jsEvaluator
    }

    func evaluate(format: String?, values: [String]) throws -> String {
        let format = format ?? Self.defaultFormat
        let jsonArray = buildJSONArray(from: values)
        let script = buildScript(jsonArray: jsonArray, format: format)

        guard let result = jsEvaluator.evaluate(script) else {
            throw ArrayFormatError.evaluationFailed(format: format)
        }

        return try extractStringResult(from: result, format: format)
    }
}

// MARK: - Private Helpers

private extension ArrayFormatEvaluator {
    func buildJSONArray(from values: [String]) -> String {
        let escaped = values.map { escapeForJSON($0) }
        return "[\(escaped.joined(separator: ", "))]"
    }

    func escapeForJSON(_ string: String) -> String {
        var result = "\""
        for char in string {
            switch char {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default: result.append(char)
            }
        }
        result += "\""
        return result
    }

    func buildScript(jsonArray: String, format: String) -> String {
        "(function() { const $elements = \(jsonArray); return \(format); })()"
    }

    func extractStringResult(from value: JSValue, format: String) throws -> String {
        if value.isNull || value.isUndefined {
            throw ArrayFormatError.evaluationFailed(format: format)
        }

        if value.isString {
            return value.toString()
        }

        let actualType = detectJSType(value)
        throw ArrayFormatError.nonStringResult(format: format, actualType: actualType)
    }

    func detectJSType(_ value: JSValue) -> String {
        if value.isBoolean { return "boolean" }
        if value.isNumber { return "number" }
        if value.isArray { return "array" }
        if value.isObject { return "object" }
        return "unknown"
    }
}
