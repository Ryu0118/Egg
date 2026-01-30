import Foundation
import RegexBuilder

extension ConfigValidator {
    struct IfValidator {
        private let macros: [Config.Macro]
        private let evaluator = JSEvaluator()

        init(macros: [Config.Macro]) {
            self.macros = macros
        }

        func validate(_ ifContent: String, context: String) async -> Error? {
            // Expand variable references in the condition expression
            let expandedExpression = expandVariables(in: ifContent)

            // Evaluate with JavaScript and check if it's a boolean
            let value = evaluator.evaluate(expandedExpression)
            let isBool = value?.toBool() != nil

            guard isBool else {
                return .invalidConditionExpression(context: context, expression: ifContent)
            }

            return nil
        }

        private func expandVariables(in expression: String) -> String {
            var expanded = expression

            // Expand step outputs (${{ ... }}) as String literals
            expanded = expandStepOutputs(in: expanded)

            // Expand macros (___MACRO_NAME___) with type-appropriate values
            expanded = expandMacros(in: expanded)

            return expanded
        }

        private func expandStepOutputs(in text: String) -> String {
            // Replace ${{ pre_hatch.id.outputs.key }} format with String literals
            var result = text
            var matches: [(range: Range<String.Index>, replacement: String)] = []

            for match in text.matches(of: Regexes.stepOutput) {
                let content = String(match.1)
                // Always treat as String (escape is needed)
                let escapedContent = escapeStringForJS(content)
                let replacement = "\"\(escapedContent)\""

                let range = match.range
                matches.append((range: range, replacement: replacement))
            }

            // Replace from back to front (to avoid index shifting)
            for (range, replacement) in matches.reversed() {
                result.replaceSubrange(range, with: replacement)
            }

            return result
        }

        private func expandMacros(in text: String) -> String {
            var expanded = text
            var matches: [(range: Range<String.Index>, replacement: String)] = []

            for match in text.matches(of: Regexes.macroReference) {
                let macroName = String(match.0)

                // Find macro definition
                if let macro = macros.first(where: { $0.name == macroName }) {
                    let replacement = valueForMacro(macro)
                    let range = match.range
                    matches.append((range: range, replacement: replacement))
                }
            }

            // Replace from back to front (to avoid index shifting)
            for (range, replacement) in matches.reversed() {
                expanded.replaceSubrange(range, with: replacement)
            }

            return expanded
        }

        private func valueForMacro(_ macro: Config.Macro) -> String {
            switch macro.type {
            case .boolean:
                // Boolean type: true or false
                return macro.default?.stringValue == "true" ? "true" : "false"

            case .string, .path:
                // String and path types: string literals
                let defaultValue = macro.default?.stringValue ?? "test"
                let escaped = escapeStringForJS(defaultValue)
                return "\"\(escaped)\""

            case .choice:
                // Choice type: string literal (use default value or first choice)
                if let defaultValue = macro.default?.stringValue {
                    let escaped = escapeStringForJS(defaultValue)
                    return "\"\(escaped)\""
                } else if let choices = macro.choices, let firstChoice = choices.first {
                    let escaped = escapeStringForJS(firstChoice)
                    return "\"\(escaped)\""
                }
                return "\"test\""

            case .choices:
                // Choices type (multiple selection): array literal
                if let defaultValue = macro.default {
                    // Convert to JS array format
                    let arrayValues = defaultValue.arrayValue.map { "\"\(escapeStringForJS($0))\"" }.joined(separator: ", ")
                    return "[\(arrayValues)]"
                } else if let choices = macro.choices, !choices.isEmpty {
                    // Create array from choices
                    let arrayValues = choices.map { "\"\(escapeStringForJS($0))\"" }.joined(separator: ", ")
                    return "[\(arrayValues)]"
                }
                return "[]"

            case .array:
                // Array type (free-form): array literal
                if let defaultValue = macro.default {
                    // Convert to JS array format
                    let arrayValues = defaultValue.arrayValue.map { "\"\(escapeStringForJS($0))\"" }.joined(separator: ", ")
                    return "[\(arrayValues)]"
                }
                return "[]"
            }
        }

        private func escapeStringForJS(_ value: String) -> String {
            return value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\t", with: "\\t")
        }
    }
}
