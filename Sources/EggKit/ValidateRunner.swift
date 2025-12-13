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
        noora: some Noorable = Noora()
    ) {
        self.mode = mode
        self.fileManager = fileManager
        self.noora = noora
    }

    package func run() async throws {
        switch mode {
        case let .direct(config, templatePath):
            try await validateConfig(config: config, templatePath: templatePath)
        }
    }

    private func validateConfig(
        config: Config,
        templatePath: URL
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
