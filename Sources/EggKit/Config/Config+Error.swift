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
            case let .macroNameEmpty(context):
                "\(context): Macro name cannot be empty."
            case let .macroDescriptionEmpty(context):
                "\(context): Macro description cannot be empty."
            case let .invalidMacroNameFormat(context, name):
                "\(context): Macro name '\(name)' must be in the format '___MACRO_NAME___' (three underscores, uppercase letters)."
            case let .duplicateMacroName(context, name):
                "\(context): Duplicate macro name '\(name)'."
            case let .choiceTypeMissingChoices(context, name):
                "\(context): Macro '\(name)' of type 'choice' must have 'choices' defined."
            case let .choiceTypeEmptyChoices(context, name):
                "\(context): Macro '\(name)' of type 'choice' must have at least one choice."
            case let .choiceDefaultValueNotInChoices(context, name, defaultValue, choices):
                "\(context): Macro '\(name)' default value '\(defaultValue)' must be one of the choices: \(choices.joined(separator: ", "))."
            case let .arrayDefaultValueInvalidFormat(context, name):
                "\(context): Macro '\(name)' default value must be a valid array format like '[value1, value2]'."
            case let .arrayDefaultValueNotInChoices(context, name, value, choices):
                "\(context): Macro '\(name)' default value '\(value)' must be one of the choices: \(choices.joined(separator: ", "))."
            case let .booleanDefaultValueInvalid(context, name, defaultValue):
                "\(context): Macro '\(name)' of type 'boolean' must have default value 'true' or 'false', got '\(defaultValue)'."
            case let .pathDefaultValueInvalidCharacters(context, name):
                "\(context): Macro '\(name)' default path contains invalid characters."
            case let .invalidRegexPattern(context, name, pattern):
                "\(context): Macro '\(name)' has invalid regular expression pattern '\(pattern)'."
            case let .defaultValueDoesNotMatchRegex(context, name, defaultValue, pattern):
                "\(context): Macro '\(name)' default value '\(defaultValue)' does not match validation pattern '\(pattern)'."
            case let .lifecycleStepMissingRunOrHatch(context):
                "\(context): Either 'run' or 'hatch' must be specified."
            case let .lifecycleStepIdEmpty(context):
                "\(context): Step ID cannot be empty."
            case let .lifecycleStepIdInvalidCharacters(context, id):
                "\(context): Step ID '\(id)' contains invalid characters. Only alphanumeric characters, hyphens, and underscores are allowed."
            case let .lifecycleStepConditionEmpty(context):
                "\(context): Conditional expression cannot be empty."
            case let .lifecycleStepRunEmpty(context):
                "\(context): 'run' command cannot be empty."
            case .hatchOutputEmpty:
                "hatch.output: Output directory cannot be empty."
            case let .excludePathEmpty(context):
                "\(context): Exclude path cannot be empty."
            case let .excludeConditionEmpty(context):
                "\(context): Conditional expression cannot be empty."
            case let .excludePathsEmpty(context):
                "\(context): Conditional exclude must have at least one path."
            case let .excludeConditionalPathEmpty(context, pathIndex):
                "\(context).paths[\(pathIndex)]: Exclude path cannot be empty."
            case let .undefinedMacroReferenced(context, macroName):
                "\(context): Undefined macro '\(macroName)' is referenced."
            case let .duplicateStepId(context, index, id):
                "\(context)[\(index)]: Duplicate step ID '\(id)'."
            case let .validatableRulesError(error):
                error.message
            case let .invalidConditionExpression(context, expression):
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
