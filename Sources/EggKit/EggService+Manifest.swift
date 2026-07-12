import FileManagerProtocol
import Foundation

/// Declarative template workflow: `egg template sync` / `egg template
/// update` for the machine-readable frontends (CLI `--json` and MCP).
/// The human CLI path constructs `TemplateSyncRunner` directly.
public extension EggService {
    // MARK: - Sync Templates

    func syncTemplates(scope: String? = nil, dryRun: Bool = false) async throws -> SyncResult {
        try await runManifestWorkflow(mode: .sync, scope: scope, dryRun: dryRun)
    }

    // MARK: - Update Templates

    func updateTemplates(scope: String? = nil, dryRun: Bool = false) async throws -> SyncResult {
        try await runManifestWorkflow(mode: .update, scope: scope, dryRun: dryRun)
    }

    // MARK: - Shared Helpers

    /// Parses a scope string ("global" / "project" / nil for all-that-exist)
    /// into a selection, mirroring `parseLocationKind`.
    package func parseManifestScopeSelection(_ scope: String?) throws -> ManifestScopeSelection {
        switch scope {
        case nil:
            return .all
        case "global":
            return .global
        case "project":
            return .project
        case let .some(other):
            throw EggServiceError.invalidLocation(other)
        }
    }

    private func runManifestWorkflow(
        mode: TemplateSyncRunner.SyncMode,
        scope: String?,
        dryRun: Bool,
    ) async throws -> SyncResult {
        let scopes = try ManifestScopeResolver.resolve(
            selection: parseManifestScopeSelection(scope),
            projectDirectory: projectDirectory,
            homeDirectory: homeDirectory,
            fileManager: fileManager,
        )

        let runner = TemplateSyncRunner(
            mode: mode,
            dryRun: dryRun,
            scopes: scopes,
            projectDirectory: projectDirectory,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
            fileManager: fileManager,
            // Progress lines must not interleave with the encoded result the
            // service's callers put on stdout.
            interaction: SilentInteraction(),
        )

        return try await runner.run()
    }
}
