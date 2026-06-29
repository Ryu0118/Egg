import Foundation

extension ConfigValidator {
    struct HatchValidator {
        private let ifValidator: IfValidator

        init(macros: [Config.Macro] = []) {
            ifValidator = IfValidator(macros: macros)
        }

        func validate(_ hatch: Config.HatchConfig) async -> [Error] {
            var errors = validateOutput(hatch).asErrors

            if let exclude = hatch.exclude {
                errors += await validateExcludeRules(exclude)
            }

            return errors
        }

        private func validateOutput(_ hatch: Config.HatchConfig) -> Error? {
            hatch.output.isEmpty ? .hatchOutputEmpty : nil
        }

        private func validateExcludeRules(_ excludeRules: [Config.ExcludeRule]) async -> [Error] {
            var errors: [Error] = []

            for (index, rule) in excludeRules.enumerated() {
                let context = "hatch.exclude[\(index)]"

                switch rule {
                case let .path(path):
                    errors += validateExcludePath(path, context: context).asErrors
                case let .conditional(conditional):
                    errors += await validateConditionalExclude(conditional, context: context)
                }
            }

            return errors
        }

        private func validateExcludePath(_ path: String, context: String) -> Error? {
            path.isEmpty ? .excludePathEmpty(context: context) : nil
        }

        private func validateConditionalExclude(_ conditional: Config.ConditionalExclude, context: String) async -> [Error] {
            var errors: [Error] = []

            if conditional.if.isEmpty {
                errors += [.excludeConditionEmpty(context: context)]
            } else if let error = await ifValidator.validate(conditional.if, context: context) { // Check if it evaluates to a boolean
                errors.append(error)
            }

            if conditional.paths.isEmpty {
                errors += [.excludePathsEmpty(context: context)]
            }

            for (pathIndex, path) in conditional.paths.enumerated() {
                if path.isEmpty {
                    errors += [
                        .excludeConditionalPathEmpty(
                            context: context,
                            pathIndex: pathIndex,
                        ),
                    ]
                }
            }

            return errors
        }
    }
}
