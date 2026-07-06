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
        let warnings = warnings(config: config, templatePath: templatePath)
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

    /// Problems that don't make the config invalid but do silently disable
    /// something: keys the decoder ignored (a typo'd section switches a
    /// feature off with no signal) and macros whose CLI flag a hatch
    /// subcommand's built-in flag shadows (the macro can never be passed on
    /// that command line).
    private func warnings(config: Config, templatePath: URL) -> [String] {
        rawYAMLWarnings(templatePath: templatePath)
            + HatchReservedFlags.collisionWarnings(for: config.macros ?? [])
    }

    /// Warnings only the raw YAML can reveal: keys the decoder ignored and
    /// `if` conditions a YAML tag silently swallowed.
    private func rawYAMLWarnings(templatePath: URL) -> [String] {
        let configURL = templatePath.appending(path: "config.yml")
        guard let data = try? fileManager.readFile(at: configURL),
              let text = String(data: data, encoding: .utf8)
        else { return [] }
        let scanner = ConfigUnknownKeyScanner()
        return scanner.unknownKeyWarnings(inYAML: text) + scanner.swallowedConditionWarnings(inYAML: text)
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
        for warning in warnings(config: config, templatePath: templatePath) {
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
