import Foundation
import Yams

/// Human-readable messages for config.yml decode failures.
///
/// A raw `DecodingError` surfaces as Foundation's generic "The data couldn't
/// be read because it is missing." — no key, no location, nothing to act on.
/// This names the exact key path and what went wrong with it; Yams syntax
/// errors already carry line/column marks, so they pass through with their
/// own description.
package enum ConfigDecodingErrorFormatter {
    package static func message(for error: any Swift.Error) -> String {
        switch error {
        case let DecodingError.keyNotFound(key, context):
            "missing required key '\(path(context.codingPath, appending: key))'."
        case let DecodingError.typeMismatch(_, context):
            "wrong type at '\(path(context.codingPath))': \(context.debugDescription)"
        case let DecodingError.valueNotFound(_, context):
            "missing value at '\(path(context.codingPath))': \(context.debugDescription)"
        case let DecodingError.dataCorrupted(context):
            if let yamlError = context.underlyingError as? YamlError {
                "invalid YAML: \(yamlError)"
            } else if context.codingPath.isEmpty {
                "invalid YAML: \(context.debugDescription)"
            } else {
                "invalid value at '\(path(context.codingPath))': \(context.debugDescription)"
            }
        case let yamlError as YamlError:
            "invalid YAML: \(yamlError)"
        default:
            error.localizedDescription
        }
    }

    /// Renders a coding path as `macros[0].name`.
    private static func path(_ codingPath: [any CodingKey], appending key: (any CodingKey)? = nil) -> String {
        var rendered = ""
        for key in codingPath + (key.map { [$0] } ?? []) {
            if let index = key.intValue {
                rendered += "[\(index)]"
            } else {
                rendered += rendered.isEmpty ? key.stringValue : ".\(key.stringValue)"
            }
        }
        return rendered.isEmpty ? "(top level)" : rendered
    }
}
