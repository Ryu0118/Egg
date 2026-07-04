import Foundation
import Interaction

/// Resolves and validates sandbox.allowed_paths from config.
///
/// This helper expands macros in allowed_paths and handles user confirmation
/// for extended sandbox permissions.
struct SandboxAllowedPathsResolver {
    private let homeDirectory: URL
    private let interaction: any InteractionProviding

    init(
        homeDirectory: URL,
        interaction: some InteractionProviding = Terminal(),
    ) {
        self.homeDirectory = homeDirectory
        self.interaction = interaction
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
        workingDirectory: URL,
    ) async throws -> [URL] {
        guard let paths = allowedPaths, !paths.isEmpty else {
            return []
        }

        // Empty storage: step outputs don't exist yet (pre_hatch hasn't run).
        // Any ${{ }} references will throw undefinedOutputReference error.
        let outputs = StepOutputsStorage()
        let builtInContext = BuiltInMacroContext(
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
        )
        let resolver = VariableResolver(
            macros: macros,
            outputs: outputs,
            builtInMacroContext: builtInContext,
        )

        var expandedPaths: [URL] = []
        for path in paths {
            let expanded = try await resolver.resolve(path)
            let normalized = expandShellPath(expanded)

            // Only absolute paths are allowed
            guard normalized.hasPrefix("/") else {
                interaction.writeWarning("Ignoring non-absolute path in sandbox.allowed_paths: \(expanded)")
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
        interaction.writeLine()
        interaction.writeLine("⚠️ Extended Sandbox Write Access Requested")
        interaction.writeLine("The following paths outside the sandbox will be writable:")
        for path in paths {
            interaction.writeLine("- \(path)", tab: 1)
        }
        interaction.writeLine()

        return interaction.yesOrNoChoicePrompt(
            title: "Sandbox Permission",
            question: "Allow writing to these paths?",
        )
    }

    /// Expands, confirms, and resolves sandbox.allowed_paths for a lifecycle run.
    ///
    /// In interactive sessions the user is prompted to allow the extended write
    /// access; declining continues in sandbox-only mode. Non-interactive sessions
    /// cannot be prompted, so any non-empty allowed_paths is rejected outright.
    ///
    /// - Returns: The confirmed allowed paths, or an empty array if the user
    ///   declined extended access.
    /// - Throws: `LifecycleStepError.sandboxPermissionRequired` when non-interactive.
    func resolveConfirmedAllowedPaths(
        _ allowedPaths: [String]?,
        macros: [ResolvedMacro],
        workingDirectory: URL,
        isInteractive: Bool,
        sandboxDisabled: Bool,
    ) async throws -> [URL] {
        let expandedAllowedPaths = try await expandAllowedPaths(
            allowedPaths,
            macros: macros,
            workingDirectory: workingDirectory,
        )

        guard !expandedAllowedPaths.isEmpty, !sandboxDisabled else {
            return []
        }

        guard isInteractive else {
            throw LifecycleStepError.sandboxPermissionRequired(
                paths: expandedAllowedPaths.map { $0.path(percentEncoded: false) },
            )
        }

        let confirmed = confirmSandboxAllowedPaths(
            expandedAllowedPaths.map { $0.path(percentEncoded: false) },
        )
        if !confirmed {
            interaction.writeLine("⚠️ Continuing without extended sandbox permissions (sandbox-only mode).")
        }
        return confirmed ? expandedAllowedPaths : []
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
            with: homeDirectory.path(percentEncoded: false),
        )

        return result
    }
}
