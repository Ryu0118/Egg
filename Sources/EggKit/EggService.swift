import FileManagerProtocol
import Foundation
import ProcessRunning

/// The application-service facade shared by every egg frontend.
///
/// Both the CLI (for its JSON-emitting paths: the hatch transaction flow and
/// `--json` template commands) and the MCP server call these use-case methods
/// and encode the same Codable result models — one source of truth for
/// behavior and output shape, regardless of which frontend invoked it.
///
/// **Why this exists alongside the `Runner` types.** The CLI's interactive
/// paths (`egg hatch`, `egg template create` with no `--json`) call a
/// `Runner` directly, because they need to prompt — `ListRunner`,
/// `CreateRunner`, etc. `EggService` exists only for the non-interactive,
/// machine-readable paths (`--json`, and every MCP tool): it is the one
/// place that resolves a request into a `Runner` call and encodes the result,
/// so the CLI's `--json` output and the MCP tool's output can't drift apart.
/// If you're calling into egg from human-driven, prompt-friendly code, go
/// through a `Runner` directly instead of adding a method here.
///
/// `EggService` itself is a thin router: each method resolves a `Template`
/// or parses a request, then hands off to the `Runner` type that owns the
/// actual domain logic (`ListRunner`, `HatchRunner`,
/// `AgentHatchTransactionRunner`, ...). The methods are grouped by domain
/// into separate files — `EggService+Templates.swift` (CRUD: list, detail,
/// create, delete, duplicate, move, validate, install) and
/// `EggService+Hatch.swift` (the hatch/preview/apply/rollback/discard
/// transaction flow) — so each file's diff stays scoped to one concern. This
/// split is organizational only: before it, all 16 methods sat in one
/// 699-line file, which read like a god object despite `EggService` itself
/// being correctly scoped (a router, not a place where domain logic lives).
public struct EggService: Sendable {
    let fileManager: any FileManagerProtocol
    let workingDirectory: URL
    let homeDirectory: URL
    let projectDirectory: URL
    let additionalSearchPaths: [URL]

    public init(
        fileManager: any FileManagerProtocol = FileManager.default,
        workingDirectory: URL? = nil,
        projectDirectory: URL? = nil,
        homeDirectory: URL? = nil,
        additionalSearchPaths: [URL] = [],
    ) {
        self.fileManager = fileManager
        self.workingDirectory = workingDirectory ?? URL(filePath: FileManager.default.currentDirectoryPath)
        self.homeDirectory = homeDirectory ?? Self.resolveHomeDirectory()
        self.projectDirectory = projectDirectory ?? self.workingDirectory
        self.additionalSearchPaths = additionalSearchPaths
    }

    /// The home directory, respecting the `HOME` environment variable.
    ///
    /// Every caller that omits `homeDirectory` falls back to this — MCP
    /// handlers all construct `EggService` with no explicit home, so if this
    /// read `FileManager.default.homeDirectoryForCurrentUser` (which ignores
    /// `$HOME` on macOS) directly, an overridden `HOME` would make the CLI
    /// and MCP resolve different `~/.eggs` directories for global templates.
    /// Tests (and any sandboxed run) that set `HOME` to a temp directory
    /// depend on this.
    package static func resolveHomeDirectory() -> URL {
        if let homePath = ProcessInfo.processInfo.environment["HOME"] {
            return URL(filePath: homePath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}

@available(*, deprecated, renamed: "EggService", message: "MCPService was renamed: it is the shared application service for every frontend (CLI and MCP), not MCP-specific.")
public typealias MCPService = EggService
