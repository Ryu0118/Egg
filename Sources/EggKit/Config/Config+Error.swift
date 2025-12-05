import Foundation
import Noora

extension ConfigValidator {
    enum Error: LocalizedError {
        case macroNameEmpty(context: String)
        case macroDescriptionEmpty(context: String)
        case invalidMacroNameFormat(context: String, name: String)
        case duplicateMacroName(context: String, name: String)
        case choiceTypeMissingChoices(context: String, name: String)
        case choiceTypeEmptyChoices(context: String, name: String)
        case choiceDefaultValueNotInChoices(context: String, name: String, defaultValue: String, choices: [String])
        case arrayDefaultValueInvalidFormat(context: String, name: String)
        case arrayDefaultValueNotInChoices(context: String, name: String, value: String, choices: [String])
        case booleanDefaultValueInvalid(context: String, name: String, defaultValue: String)
        case pathDefaultValueInvalidCharacters(context: String, name: String)
        case invalidRegexPattern(context: String, name: String, pattern: String)
        case defaultValueDoesNotMatchRegex(context: String, name: String, defaultValue: String, pattern: String)
        case lifecycleStepMissingRunOrHatch(context: String)
        case lifecycleStepIdEmpty(context: String)
        case lifecycleStepIdInvalidCharacters(context: String, id: String)
        case lifecycleStepConditionEmpty(context: String)
        case lifecycleStepRunEmpty(context: String)
        case hatchOutputEmpty
        case excludePathEmpty(context: String)
        case excludeConditionEmpty(context: String)
        case excludePathsEmpty(context: String)
        case excludeConditionalPathEmpty(context: String, pathIndex: Int)
        case undefinedMacroReferenced(context: String, macroName: String)
        case duplicateStepId(context: String, index: Int, id: String)
        case validatableRulesError(any ValidatableError)
        case invalidConditionExpression(context: String, expression: String)

        var errorDescription: String? {
            switch self {
            case .macroNameEmpty(let context):
                "\(context): Macro name cannot be empty."
            case .macroDescriptionEmpty(let context):
                "\(context): Macro description cannot be empty."
            case .invalidMacroNameFormat(let context, let name):
                "\(context): Macro name '\(name)' must be in the format '___MACRO_NAME___' (three underscores, uppercase letters)."
            case .duplicateMacroName(let context, let name):
                "\(context): Duplicate macro name '\(name)'."
            case .choiceTypeMissingChoices(let context, let name):
                "\(context): Macro '\(name)' of type 'choice' must have 'choices' defined."
            case .choiceTypeEmptyChoices(let context, let name):
                "\(context): Macro '\(name)' of type 'choice' must have at least one choice."
            case .choiceDefaultValueNotInChoices(let context, let name, let defaultValue, let choices):
                "\(context): Macro '\(name)' default value '\(defaultValue)' must be one of the choices: \(choices.joined(separator: ", "))."
            case .arrayDefaultValueInvalidFormat(let context, let name):
                "\(context): Macro '\(name)' default value must be a valid array format like '[value1, value2]'."
            case .arrayDefaultValueNotInChoices(let context, let name, let value, let choices):
                "\(context): Macro '\(name)' default value '\(value)' must be one of the choices: \(choices.joined(separator: ", "))."
            case .booleanDefaultValueInvalid(let context, let name, let defaultValue):
                "\(context): Macro '\(name)' of type 'boolean' must have default value 'true' or 'false', got '\(defaultValue)'."
            case .pathDefaultValueInvalidCharacters(let context, let name):
                "\(context): Macro '\(name)' default path contains invalid characters."
            case .invalidRegexPattern(let context, let name, let pattern):
                "\(context): Macro '\(name)' has invalid regular expression pattern '\(pattern)'."
            case .defaultValueDoesNotMatchRegex(let context, let name, let defaultValue, let pattern):
                "\(context): Macro '\(name)' default value '\(defaultValue)' does not match validation pattern '\(pattern)'."
            case .lifecycleStepMissingRunOrHatch(let context):
                "\(context): Either 'run' or 'hatch' must be specified."
            case .lifecycleStepIdEmpty(let context):
                "\(context): Step ID cannot be empty."
            case .lifecycleStepIdInvalidCharacters(let context, let id):
                "\(context): Step ID '\(id)' contains invalid characters. Only alphanumeric characters, hyphens, and underscores are allowed."
            case .lifecycleStepConditionEmpty(let context):
                "\(context): Conditional expression cannot be empty."
            case .lifecycleStepRunEmpty(let context):
                "\(context): 'run' command cannot be empty."
            case .hatchOutputEmpty:
                "hatch.output: Output directory cannot be empty."
            case .excludePathEmpty(let context):
                "\(context): Exclude path cannot be empty."
            case .excludeConditionEmpty(let context):
                "\(context): Conditional expression cannot be empty."
            case .excludePathsEmpty(let context):
                "\(context): Conditional exclude must have at least one path."
            case .excludeConditionalPathEmpty(let context, let pathIndex):
                "\(context).paths[\(pathIndex)]: Exclude path cannot be empty."
            case .undefinedMacroReferenced(let context, let macroName):
                "\(context): Undefined macro '\(macroName)' is referenced."
            case .duplicateStepId(let context, let index, let id):
                "\(context)[\(index)]: Duplicate step ID '\(id)'."
            case .validatableRulesError(let error):
                error.message
            case .invalidConditionExpression(let context, let expression):
                "\(context): Condition expression '\(expression)' must evaluate to a boolean value."
            }
        }
    }
}

extension ConfigValidator.Error: Equatable {
    static func == (lhs: ConfigValidator.Error, rhs: ConfigValidator.Error) -> Bool {
        lhs.errorDescription == rhs.errorDescription
    }
}

extension ConfigValidator.Error? {
    var asErrors: [ConfigValidator.Error] {
        if let self {
            [self]
        } else {
            []
        }
    }
}
