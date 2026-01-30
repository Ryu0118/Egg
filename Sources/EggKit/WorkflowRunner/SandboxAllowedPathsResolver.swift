import Foundation
import Noora

/// Resolves and validates sandbox.allowed_paths from config.
///
/// This helper expands macros in allowed_paths and handles user confirmation
/// for extended sandbox permissions.
struct SandboxAllowedPathsResolver {
    private let homeDirectory: URL
    private let noora: any Noorable

    init(homeDirectory: URL, noora: some Noorable) {
        self.homeDirectory = homeDirectory
        self.noora = noora
    }

    /// Expands macros in sandbox.allowed_paths and converts to URLs.
    ///
    /// Note: Step outputs are NOT available at this point since pre_hatch hasn't run yet.
    /// The empty StepOutputsStorage ensures any `${{ }}` references will fail gracefully.
    ///
    /// - Parameters:
    ///   - allowedPaths: Raw paths from config.sandbox.allowed_paths (may contain macros)
    ///   - macros: Resolved macros for substitution
    ///   - workingDirectory: Working directory for variable resolution context
    /// - Returns: Array of expanded absolute path URLs
    /// - Throws: If variable resolution fails
    func expandAllowedPaths(
        _ allowedPaths: [String]?,
        macros: [ResolvedMacro],
        workingDirectory: URL
    ) async throws -> [URL] {
        guard let paths = allowedPaths, !paths.isEmpty else {
            return []
        }

        // Empty storage: step outputs don't exist yet (pre_hatch hasn't run).
        // Any ${{ }} references will throw undefinedOutputReference error.
        let outputs = StepOutputsStorage()
        let builtInContext = BuiltInMacroContext(
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory
        )
        let resolver = VariableResolver(
            macros: macros,
            outputs: outputs,
            builtInMacroContext: builtInContext
        )

        var expandedPaths: [URL] = []
        for path in paths {
            let expanded = try await resolver.resolve(path)
            let normalized = expandShellPath(expanded)

            // Only absolute paths are allowed
            guard normalized.hasPrefix("/") else {
                noora.warning("Ignoring non-absolute path in sandbox.allowed_paths: \(expanded)")
                continue
            }

            expandedPaths.append(URL(filePath: normalized))
        }

        return expandedPaths
    }

    /// Prompts user for confirmation to allow extended sandbox write access.
    ///
    /// - Parameter paths: The paths that will be writable outside the sandbox
    /// - Returns: True if user confirms, false otherwise
    func confirmSandboxAllowedPaths(_ paths: [String]) -> Bool {
        noora.passthrough("\n⚠️ Extended Sandbox Write Access Requested\n")
        noora.passthrough("The following paths outside the sandbox will be writable:\n")
        for path in paths {
            noora.passthrough("  - \(path)\n")
        }
        noora.passthrough("\n")

        return noora.yesOrNoChoicePrompt(
            title: "Sandbox Permission",
            question: "Allow writing to these paths?"
        )
    }

    /// Expands shell path shortcuts like `~` and `$HOME`.
    private func expandShellPath(_ path: String) -> String {
        var result = path

        // Expand ~ at the beginning
        if result.hasPrefix("~/") {
            result = homeDirectory.path(percentEncoded: false) + result.dropFirst(1)
        } else if result == "~" {
            result = homeDirectory.path(percentEncoded: false)
        }

        // Expand $HOME
        result = result.replacingOccurrences(
            of: "$HOME",
            with: homeDirectory.path(percentEncoded: false)
        )

        return result
    }

}
