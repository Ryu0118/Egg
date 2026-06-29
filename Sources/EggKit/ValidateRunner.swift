import FileManagerProtocol
import Foundation
import Noora

package struct ValidateRunner {
    private let mode: ValidateRunnerMode
    private let fileManager: any FileManagerProtocol
    private let noora: any Noorable
    private let validator = ConfigValidator()

    package init(
        mode: ValidateRunnerMode,
        fileManager: some FileManagerProtocol,
        noora: some Noorable = Noora(),
    ) {
        self.mode = mode
        self.fileManager = fileManager
        self.noora = noora
    }

    package func run() async throws {
        switch mode {
        case let .direct(config, templatePath):
            try await validateConfig(config: config, templatePath: templatePath)
        case .mcp:
            // MCP mode returns result, use runMcp() instead
            break
        }
    }

    /// Run in MCP mode and return structured result
    package func runMcp(
        config: Config,
        templatePath: URL,
    ) async -> ValidateResult {
        do {
            try await validator.validate(config)
            return ValidateResult(
                templateName: config.name,
                templatePath: templatePath.path(percentEncoded: false),
                isValid: true,
                errors: nil,
            )
        } catch {
            let errors = extractValidationErrors(from: error)
            return ValidateResult(
                templateName: config.name,
                templatePath: templatePath.path(percentEncoded: false),
                isValid: false,
                errors: errors,
            )
        }
    }

    private func extractValidationErrors(from error: Swift.Error) -> [String] {
        if let combinedError = error as? CombinedError {
            return combinedError.errors.map(\.localizedDescription)
        }
        return [error.localizedDescription]
    }

    private func validateConfig(
        config: Config,
        templatePath: URL,
    ) async throws {
        do {
            try await validator.validate(config)
            noora.success("Template '\(config.name)' at \(templatePath.path) is valid")
        } catch {
            noora.error("Validation failed for template at \(templatePath.path)")
            throw error
        }
    }
}
