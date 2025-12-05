import Foundation

extension ConfigValidator {
    struct PreHatchValidator {
        private let ifValidator: IfValidator
        
        init(macros: [Macro] = []) {
            self.ifValidator = IfValidator(macros: macros)
        }
        
        func validate(_ steps: [LifecycleStep]) async -> [Error] {
            var errors: [Error] = []
            
            for (index, step) in steps.enumerated() {
                let context = "pre_hatch[\(index)]"
                
                errors += validateRequiredFields(step, context: context).asErrors
                    + validateStepId(step, context: context).asErrors
                if let conditionError = await validateCondition(step, context: context) {
                    errors.append(conditionError)
                }
                errors += validateRun(step, context: context).asErrors
            }
            
            return errors + validateStepIdUniqueness(steps)
        }
        
        private func validateStepIdUniqueness(_ steps: [LifecycleStep]) -> [Error] {
            var errors: [Error] = []
            var seenIds: Set<String> = []
            
            for (index, step) in steps.enumerated() {
                if let id = step.id {
                    if seenIds.contains(id) {
                        errors += [.duplicateStepId(context: "pre_hatch", index: index, id: id)]
                    } else {
                        seenIds.insert(id)
                    }
                }
            }
            
            return errors
        }
        
        private func validateRequiredFields(_ step: LifecycleStep, context: String) -> Error? {
            (step.run == nil || step.run?.isEmpty == true) ? .lifecycleStepMissingRunOrHatch(context: context) : nil
        }
        
        private func validateStepId(_ step: LifecycleStep, context: String) -> Error? {
            guard let id = step.id else {
                return nil
            }
            
            if id.isEmpty {
                return .lifecycleStepIdEmpty(context: context)
            } else if !isValidStepId(id) {
                return .lifecycleStepIdInvalidCharacters(context: context, id: id)
            }
            
            return nil
        }
        
        private func validateCondition(_ step: LifecycleStep, context: String) async -> Error? {
            guard let condition = step.if else {
                return nil
            }
            
            if condition.isEmpty {
                return .lifecycleStepConditionEmpty(context: context)
            }
            
            // Check if it evaluates to a boolean
            return await ifValidator.validate(condition, context: context)
        }
        
        private func validateRun(_ step: LifecycleStep, context: String) -> Error? {
            (step.run?.isEmpty == true) ? .lifecycleStepRunEmpty(context: context) : nil
        }
        
        // MARK: - Helper Methods
        
        private func isValidStepId(_ id: String) -> Bool {
            return id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        }
    }
}
