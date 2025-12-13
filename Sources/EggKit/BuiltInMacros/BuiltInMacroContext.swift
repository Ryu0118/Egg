import Foundation

/// Context for resolving built-in macros.
///
/// This structure provides all the runtime information needed to resolve built-in macros.
/// It is designed to be injectable for testing purposes.
struct BuiltInMacroContext: Sendable {
    /// The resolved output directory (available after hatch.output resolution).
    let outputDirectory: URL?

    /// The current working directory.
    let workingDirectory: URL

    /// The user's home directory.
    let homeDirectory: URL

    /// The current date (injectable for testing).
    let currentDate: Date

    /// System environment variables (injectable for testing).
    let environment: [String: String]

    init(
        outputDirectory: URL? = nil,
        workingDirectory: URL,
        homeDirectory: URL,
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
