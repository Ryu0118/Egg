import Foundation
import RegexBuilder

extension ConfigValidator {
    struct MacrosValidator {
        func validate(_ macros: [Config.Macro], config: Config) -> [Error] {
            var errors: [Error] = []

            for (index, macro) in macros.enumerated() {
                let context = "macros[\(index)]"

                errors += validateRequiredFields(macro, context: context)
                    + validateMacroName(macro, context: context)
                    + validateMacroType(macro, context: context)
                    + validateMacroValidation(macro, context: context).asErrors
            }

            return errors + validateMacroNameUniqueness(macros) + validateMacroReferences(config, definedMacros: macros)
        }

        private func validateMacroReferences(_ config: Config, definedMacros: [Config.Macro]) -> [Error] {
            var errors: [Error] = []
            let definedMacroNames = Set(definedMacros.map { $0.name })

            // Check macros used in pre_hatch run commands
            if let preHatch = config.preHatch {
                for (index, step) in preHatch.enumerated() {
                    if let run = step.run {
                        errors += validateMacroReferencesInText(run, definedMacroNames: definedMacroNames, context: "pre_hatch[\(index)].run")
                    }

                    if let condition = step.if {
                        errors += validateMacroReferencesInText(condition, definedMacroNames: definedMacroNames, context: "pre_hatch[\(index)].if")
                    }
                }
            }

            // Check macros used in post_hatch run commands
            if let postHatch = config.postHatch {
                for (index, step) in postHatch.enumerated() {
                    if let run = step.run {
                        errors += validateMacroReferencesInText(run, definedMacroNames: definedMacroNames, context: "post_hatch[\(index)].run")
                    }

                    if let condition = step.if {
                        errors += validateMacroReferencesInText(condition, definedMacroNames: definedMacroNames, context: "post_hatch[\(index)].if")
                    }
                }
            }

            // Check macros used in hatch.output
            let hatch = config.hatch
            errors += validateMacroReferencesInText(hatch.output, definedMacroNames: definedMacroNames, context: "hatch.output")

            // Check macros used in hatch.exclude condition expressions
            if let exclude = hatch.exclude {
                for (index, rule) in exclude.enumerated() {
                    switch rule {
                    case .path:
                        break
                    case let .conditional(conditional):
                        errors += validateMacroReferencesInText(conditional.if, definedMacroNames: definedMacroNames, context: "hatch.exclude[\(index)].if")
                    }
                }
            }

            return errors
        }

        private func validateRequiredFields(_ macro: Config.Macro, context: String) -> [Error] {
            var errors: [Error] = []

            if macro.name.isEmpty {
                errors += [.macroNameEmpty(context: context)]
            }

            if macro.description.isEmpty {
                errors += [.macroDescriptionEmpty(context: context)]
            }

            return errors
        }

        private func validateMacroName(_ macro: Config.Macro, context: String) -> [Error] {
            guard !macro.name.isEmpty else {
                return []
            }

            var errors: [Error] = []

            if !isValidMacroName(macro.name) {
                errors.append(.invalidMacroNameFormat(context: context, name: macro.name))
            }

            if BuiltInMacros.isReserved(macro.name) {
                errors.append(.reservedMacroName(context: context, name: macro.name))
            }

            return errors
        }

        private func validateMacroNameUniqueness(_ macros: [Config.Macro]) -> [Error] {
            var errors: [Error] = []
            var macroNames: Set<String> = []

            for (index, macro) in macros.enumerated() {
                let context = "macros[\(index)]"

                if macroNames.contains(macro.name) {
                    errors += [.duplicateMacroName(context: context, name: macro.name)]
                } else {
                    macroNames.insert(macro.name)
                }
            }

            return errors
        }

        private func validateMacroType(_ macro: Config.Macro, context: String) -> [Error] {
            switch macro.type {
            case .choice:
                return validateChoiceType(macro, context: context)
            case .array:
                return validateArrayType(macro, context: context)
            case .boolean:
                return validateBooleanType(macro, context: context).asErrors
            case .path:
                return validatePathType(macro, context: context).asErrors
            case .string:
                return []
            }
        }

        private func validateChoiceType(_ macro: Config.Macro, context: String) -> [Error] {
            guard let choices = macro.choices else {
                return [.choiceTypeMissingChoices(context: context, name: macro.name)]
            }

            var errors: [Error] = []

            if choices.isEmpty {
                errors += [.choiceTypeEmptyChoices(context: context, name: macro.name)]
            }

            if let defaultValue = macro.default, !choices.contains(defaultValue) {
                errors += [.choiceDefaultValueNotInChoices(
                    context: context,
                    name: macro.name,
                    defaultValue: defaultValue,
                    choices: choices
                )]
            }

            return errors
        }

        private func validateArrayType(_ macro: Config.Macro, context: String) -> [Error] {
            guard let defaultValue = macro.default else {
                return []
            }

            var errors: [Error] = []

            if !isValidArrayString(defaultValue) {
                errors += [.arrayDefaultValueInvalidFormat(
                    context: context,
                    name: macro.name
                )]
            } else if let choices = macro.choices {
                let arrayValues = parseArrayString(defaultValue)
                for value in arrayValues {
                    if !choices.contains(value) {
                        errors += [.arrayDefaultValueNotInChoices(
                            context: context,
                            name: macro.name,
                            value: value,
                            choices: choices
                        )]
                    }
                }
            }

            return errors
        }

        private func validateBooleanType(_ macro: Config.Macro, context: String) -> Error? {
            guard let defaultValue = macro.default,
                  defaultValue != "true",
                  defaultValue != "false"
            else {
                return nil
            }

            return .booleanDefaultValueInvalid(context: context, name: macro.name, defaultValue: defaultValue)
        }

        private func validatePathType(_ macro: Config.Macro, context: String) -> Error? {
            guard let defaultValue = macro.default, !defaultValue.isEmpty, defaultValue.contains("\0") else {
                return nil
            }

            return .pathDefaultValueInvalidCharacters(context: context, name: macro.name)
        }

        private func validateMacroValidation(_ macro: Config.Macro, context: String) -> Error? {
            guard let validatePattern = macro.validate else {
                return nil
            }

            // Check if the regular expression is valid
            guard (try? Regex(validatePattern)) != nil else {
                return .invalidRegexPattern(
                    context: context,
                    name: macro.name,
                    pattern: validatePattern
                )
            }

            guard let defaultValue = macro.default else {
                return nil
            }

            // Check if the default value matches the regular expression
            guard let regex = try? Regex(validatePattern) else {
                return nil
            }

            if defaultValue.firstMatch(of: regex) == nil {
                return .defaultValueDoesNotMatchRegex(
                    context: context,
                    name: macro.name,
                    defaultValue: defaultValue,
                    pattern: validatePattern
                )
            }

            return nil
        }

        private func validateMacroReferencesInText(_ text: String, definedMacroNames: Set<String>, context: String) -> [Error] {
            let referencedMacros = extractMacroReferences(from: text)

            return referencedMacros.compactMap { macroName in
                // Built-in macros are always available
                if BuiltInMacros.isReserved(macroName) {
                    return nil
                }
                return definedMacroNames.contains(macroName) ? nil : Error.undefinedMacroReferenced(context: context, macroName: macroName)
            }
        }

        private func isValidMacroName(_ name: String) -> Bool {
            guard name.hasPrefix("___"), name.hasSuffix("___") else {
                return false
            }

            let inner = String(name.dropFirst(3).dropLast(3))

            guard !inner.isEmpty else {
                return false
            }

            return inner.allSatisfy { $0.isUppercase || $0.isNumber || $0 == "_" }
        }

        private func extractMacroReferences(from text: String) -> Set<String> {
            var macros: Set<String> = []

            for match in text.matches(of: Regexes.macroReference) {
                let macroName = String(match.0)
                macros.insert(macroName)
            }

            return macros
        }

        private func isValidArrayString(_ value: String) -> Bool {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("[") && trimmed.hasSuffix("]")
        }

        private func parseArrayString(_ value: String) -> [String] {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else {
                return []
            }

            let inner = String(trimmed.dropFirst().dropLast())
            return inner.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
        }
    }
}
