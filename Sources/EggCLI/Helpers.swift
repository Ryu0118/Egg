import ArgumentParser
import EggKit
import FileManagerProtocol
import Foundation
import Interaction

package protocol HasProjectDirectory {
    var projectDirectory: String? { get }
    static var fileManager: any FileManagerProtocol { get }
}

package extension HasProjectDirectory {
    func resolveProjectDirectory() async throws -> URL {
        if let projectDirectory {
            URL(filePath: projectDirectory, relativeTo: URL(filePath: Self.fileManager.currentDirectoryPath))
        } else {
            URL(filePath: Self.fileManager.currentDirectoryPath)
        }
    }
}

package protocol HasTemplateSearchPaths {
    var templateSearchPaths: [String] { get }
    static var fileManager: any FileManagerProtocol { get }
}

package extension HasTemplateSearchPaths {
    func resolveTemplateSearchPaths() -> [URL] {
        templateSearchPaths.map { path in
            URL(filePath: path, relativeTo: URL(filePath: Self.fileManager.currentDirectoryPath))
        }
    }
}

extension TemplateLocationType.Kind: ExpressibleByArgument {}

/// Helpers for resolving command-line environment values.
package enum CLIEnvironment {
    /// Returns the home directory, respecting the HOME environment variable.
    ///
    /// Tests can set HOME to a temporary directory, so command code must not
    /// read `FileManager.default.homeDirectoryForCurrentUser` directly.
    package static func resolveHomeDirectory() -> URL {
        if let homePath = ProcessInfo.processInfo.environment["HOME"] {
            return URL(filePath: homePath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}

/// Helpers for command output that should share Interaction styling.
package enum CLIOutput {
    /// Prints a value as stable, pretty-printed JSON to stdout.
    ///
    /// Agent-facing hatch transaction commands emit JSON by default so an
    /// agent can parse the result directly. Keys are sorted so the output is
    /// stable across runs.
    package static func printJSON(_ value: some Encodable) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        if let string = String(data: data, encoding: .utf8) {
            print(string)
        }
    }

    /// Prints a failure message to stderr-like terminal output.
    package static func printError(_ message: String) {
        GuardedTerminal().writeFailure("\(message)")
    }

    /// Prints a success message using the shared terminal style.
    package static func printSuccess(_ message: String) {
        GuardedTerminal().writeSuccess("\(message)")
    }

    /// Prints a warning message using the shared terminal style.
    package static func printWarning(_ message: String) {
        GuardedTerminal().writeWarning("\(message)")
    }
}
