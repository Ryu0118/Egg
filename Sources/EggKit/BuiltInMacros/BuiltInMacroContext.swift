import Foundation
import Path

/// Context for resolving built-in macros.
///
/// This structure provides all the runtime information needed to resolve built-in macros.
/// It is designed to be injectable for testing purposes.
package struct BuiltInMacroContext: Sendable {
    /// The resolved output directory (available after hatch.output resolution).
    package let outputDirectory: AbsolutePath?

    /// The current working directory.
    package let workingDirectory: AbsolutePath

    /// The user's home directory.
    package let homeDirectory: AbsolutePath

    /// The current date (injectable for testing).
    package let currentDate: Date

    /// System environment variables (injectable for testing).
    package let environment: [String: String]

    package init(
        outputDirectory: AbsolutePath? = nil,
        workingDirectory: AbsolutePath,
        homeDirectory: AbsolutePath,
        currentDate: Date = Date(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.outputDirectory = outputDirectory
        self.workingDirectory = workingDirectory
        self.homeDirectory = homeDirectory
        self.currentDate = currentDate
        self.environment = environment
    }
}
