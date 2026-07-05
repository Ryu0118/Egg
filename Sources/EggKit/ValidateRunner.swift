import FileManagerProtocol
import Foundation
import Interaction

package struct ValidateRunner {
    private let mode: ValidateRunnerMode
    private let fileManager: any FileManagerProtocol
    private let interaction: any InteractionProviding
    private let validator = ConfigValidator()

    package init(
        mode: ValidateRunnerMode,
        fileManager: some FileManagerProtocol,
        interaction: some InteractionProviding = GuardedTerminal(),
    ) {
        self.mode = mode
        self.fileManager = fileManager
        self.interaction = interaction
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
        let warnings = unknownKeyWarnings(templatePath: templatePath)
        do {
            try await validator.validate(config)
            return ValidateResult(
                templateName: config.name,
                templatePath: templatePath.path(percentEncoded: false),
                isValid: true,
                errors: nil,
                warnings: warnings.isEmpty ? nil : warnings,
            )
        } catch {
            let errors = extractValidationErrors(from: error)
            return ValidateResult(
                templateName: config.name,
                templatePath: templatePath.path(percentEncoded: false),
                isValid: false,
                errors: errors,
                warnings: warnings.isEmpty ? nil : warnings,
            )
        }
    }

    /// Keys the decoder silently ignored — a typo'd section means a feature
    /// is off with no signal, so validate surfaces it even though decoding
    /// succeeded.
    private func unknownKeyWarnings(templatePath: URL) -> [String] {
        let configURL = templatePath.appending(path: "config.yml")
        guard let data = try? fileManager.readFile(at: configURL),
              let text = String(data: data, encoding: .utf8)
        else { return [] }
        return ConfigUnknownKeyScanner().unknownKeyWarnings(inYAML: text)
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
        for warning in unknownKeyWarnings(templatePath: templatePath) {
            interaction.writeWarning(StyledText(warning))
        }
        do {
            try await validator.validate(config)
            interaction.writeSuccess("Template '\(config.name)' at \(templatePath.path) is valid")
        } catch {
            interaction.writeFailure("Validation failed for template at \(templatePath.path)")
            throw error
        }
    }
}
