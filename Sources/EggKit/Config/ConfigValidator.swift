import Foundation
import Interaction

struct ConfigValidator {
    private let macrosValidator = MacrosValidator()

    func validate(_ config: Config) async throws {
        var allErrors: [Error] = []

        let templateNameErrors = Config.templateNameValidationRules.validate(config.name).map { Error.validationRuleError($0) }
        let descriptionErrors = Config.descriptionValidationRules.validate(config.description).map { Error.validationRuleError($0) }

        allErrors += templateNameErrors + descriptionErrors

        let macros = config.macros ?? []
        let preHatchValidator = PreHatchValidator(macros: macros)
        let postHatchValidator = PostHatchValidator(macros: macros)
        let hatchValidator = HatchValidator(macros: macros)

        if !macros.isEmpty {
            allErrors += macrosValidator.validate(macros, config: config)
        }

        if let preHatch = config.preHatch {
            allErrors += await preHatchValidator.validate(preHatch)
        }

        if let postHatch = config.postHatch {
            allErrors += await postHatchValidator.validate(postHatch)
        }

        allErrors += await hatchValidator.validate(config.hatch)

        if !allErrors.isEmpty {
            throw CombinedError(errors: allErrors) { "⛔️ \($0)" }
        }
    }
}
